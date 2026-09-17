# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/fake_context"
require "open3"
require "rbconfig"

# The configured cap phase 4a postponed to phase 5a (CTX-11's cross-reference row): ContextStore
# .default reads Keys::MAX_TRACKED_CONTEXTS from the chain at its FIRST construction, under a
# mutex, falling back to MAX_TRACKED_CONTEXTS. Phase 4a assigned .default at file load; this phase
# makes the construction a synchronised first call so a Dexpace.configure at boot reaches it, and
# the phase-4a fresh-process case in context_store_test.rb changed to say so.
#
# The store is a process-lifetime property, so every case that needs a fresh one asks a fresh
# process, exactly as phase 4a's own case does -- `require "dexpace"` and a one-line program --
# rather than reaching into the class ivar.
module ContextStoreConfigTest
  LIB = File.expand_path("../../lib", __dir__)
  SUPPORT = File.expand_path("../support", __dir__)

  # A fresh interpreter running `program` after `require "dexpace"`, with bundler's RUBYOPT
  # cleared so nothing but the gem's own tree loads, and MAX_TRACKED_CONTEXTS cleared so the
  # child reads the cap from its program and never from the host's environment (review round 0,
  # R0-7); the one case about the environment tier sets it explicitly through `env:`.
  def self.fresh(program, env: {})
    Open3.capture3(
      { "RUBYOPT" => nil, "MAX_TRACKED_CONTEXTS" => nil }.merge(env),
      RbConfig.ruby, "-w", "-W:deprecated", "-I", LIB, "-I", SUPPORT, "-e",
      "require \"dexpace\"; #{program}",
    )
  end

  # The one-line program that fills the process-wide store past a small cap and prints its size.
  FILL = "require \"fake_context\"; store = Dexpace::ContextStore.default; " \
         "6.times { |i| store.set(FakeContext.new(call_key: \"k\#{i}\", store: store)) }; " \
         "print store.size"
  KEY = "Dexpace::Configuration::Keys::MAX_TRACKED_CONTEXTS"

  # The cap's source, read where it matters: at the first construction.
  class SourceTest < DexpaceTestCase
    def teardown
      Dexpace.reset_config!
      super
    end

    test "context-store cap: .default is one process-wide store, the same object on every call" do
      store = Dexpace::ContextStore.default

      assert_instance_of(Dexpace::ContextStore, store)
      assert_same(store, Dexpace::ContextStore.default)
    end

    test "context-store cap: a fresh process constructs no store until the first call" do
      out, err, status = ContextStoreConfigTest.fresh(
        "print Dexpace::ContextStore.instance_variable_get(:@default).nil?, ' ', " \
        "Dexpace::ContextStore.default.equal?(Dexpace::ContextStore.default)",
      )

      assert_predicate(status, :success?, err)
      assert_empty(err)
      assert_equal("true true", out)
    end

    # The wiring itself: a Dexpace.configure BEFORE the first promotion sets the cap the
    # process-wide store is built with. Driven end to end -- configure, then fill past the cap
    # through the real store -- in a fresh process, because this one's store already exists.
    test "context-store cap: a configure before the first call sets the process-wide store's cap" do
      out, err, status = ContextStoreConfigTest.fresh(
        "Dexpace.configure { |c| c.override(#{KEY}, \"3\") }; #{FILL}",
      )

      assert_predicate(status, :success?, err)
      assert_empty(err)
      assert_equal("3", out)
    end

    test "context-store cap: the environment tier reaches the cap too, with no configure at all" do
      out, err, status = ContextStoreConfigTest.fresh(FILL)
      # ENV is read by exact name through Sources::ENVIRONMENT, so the variable is set on the child.
      env_out, env_err, env_status =
        ContextStoreConfigTest.fresh(FILL, env: { "MAX_TRACKED_CONTEXTS" => "4" })

      assert_predicate(status, :success?, err)
      assert_equal("6", out) # the default cap is 1024, so nothing was evicted
      assert_predicate(env_status, :success?, env_err)
      assert_equal("4", env_out)
    end

    # The consequence the design states because it is not obvious: the store is constructed once,
    # so a configure AFTER the first call does not resize it and neither does reset_config!. A
    # test that needs a different cap builds its own ContextStore.new(cap:).
    test "context-store cap: a configure after the first call does not resize the store" do
      out, err, status = ContextStoreConfigTest.fresh(
        "first = Dexpace::ContextStore.default; " \
        "Dexpace.configure { |c| c.override(#{KEY}, \"2\") }; #{FILL}; " \
        "print ' ', first.equal?(Dexpace::ContextStore.default)",
      )

      assert_predicate(status, :success?, err)
      assert_equal("6 true", out)
    end

    test "context-store cap: an unparseable or non-positive cap falls back to 1024, never raises" do
      ["many", "0", "-5", ""].each do |value|
        fill = FILL.sub("6.times", "1030.times")
        out, err, status = ContextStoreConfigTest.fresh(
          "Dexpace.configure { |c| c.override(#{KEY}, #{value.inspect}) }; #{fill}",
        )

        assert_predicate(status, :success?, err)
        assert_equal(Dexpace::ContextStore::MAX_TRACKED_CONTEXTS.to_s, out, value.inspect)
      end
    end

    # What the wiring reads, asserted in-process as well: the same key, the same fallback.
    test "context-store cap: the key is Keys::MAX_TRACKED_CONTEXTS and the fallback the constant" do
      Dexpace.configure { |c| c.override(Dexpace::Configuration::Keys::MAX_TRACKED_CONTEXTS, "3") }

      cap = Dexpace.configuration.integer(Dexpace::Configuration::Keys::MAX_TRACKED_CONTEXTS,
                                          default: Dexpace::ContextStore::MAX_TRACKED_CONTEXTS,)

      assert_equal(3, cap)
      assert_equal(1024, Dexpace::ContextStore::MAX_TRACKED_CONTEXTS)
    end
  end

  # XCUT-11: the first construction under contention.
  class RaceTest < DexpaceTestCase
    # The construction itself is what the mutex covers, so the construction is what the fixture
    # slows: a `new` held for 50 ms widens the `||=` window from microseconds to something 16
    # threads all land in, and an unsynchronised `@default ||= new(...)` -- the guard the design
    # names -- lets every one of them build its own store and publish it, where under the mutex
    # they see one. Reproduced red on 3.2.11 and 4.0.6 with the mutex removed. The seams are slow
    # as well, and run OUTSIDE the lock (the next case), so a slow seam alone no longer
    # discriminates the mutex -- which is why the slowed step is `new` (review round 0, R0-4).
    test "XCUT-11: 16 threads reaching .default first get ONE store, even under a slow new" do
      out, err, status = ContextStoreConfigTest.fresh(<<~RUBY)
        slow = ->(key) { sleep(0.05); nil }
        Dexpace.configure { |c| c.env_source = slow; c.property_source = slow }
        Dexpace::ContextStore.singleton_class.prepend(Module.new do
          def new(...) = (sleep(0.05); super)
        end)
        go = Thread::Queue.new
        threads = Array.new(16) { Thread.new { go.pop; Dexpace::ContextStore.default } }
        16.times { go << true }
        print threads.map(&:value).map(&:object_id).uniq.size
      RUBY

      assert_predicate(status, :success?, err)
      assert_empty(err)
      assert_equal("1", out)
    end

    # The two seams are caller-supplied callables, and Dexpace.configure's rule -- no user code
    # under a non-reentrant mutex -- applies to the store's first-call construction too: the
    # chain is read BEFORE the lock and only the `||=` runs inside it. A seam that asks whether
    # the calling thread owns the store's mutex is the direct observation; a seam that re-entered
    # the store under the lock would have deadlocked (review round 0, R0-4).
    test "XCUT-11: the configuration seams run outside the store's mutex, never under it" do
      out, err, status = ContextStoreConfigTest.fresh(<<~RUBY)
        mutex = Dexpace::ContextStore.instance_variable_get(:@default_mutex)
        owned = []
        probe = ->(key) { owned << mutex.owned?; nil }
        Dexpace.configure { |c| c.env_source = probe; c.property_source = probe }
        Dexpace::ContextStore.default
        print owned.size.positive?, ' ', owned.none?
      RUBY

      assert_predicate(status, :success?, err)
      assert_empty(err)
      assert_equal("true true", out)
    end

    # Once published, the reference is read without the lock and without the chain: a later
    # .default runs no seam at all, which is what makes a promotion after the first free of both.
    test "context-store cap: after the first call, .default reads neither seam again" do
      out, err, status = ContextStoreConfigTest.fresh(<<~RUBY)
        calls = 0
        counting = ->(key) { calls += 1; nil }
        Dexpace.configure { |c| c.env_source = counting; c.property_source = counting }
        first = Dexpace::ContextStore.default
        after_first = calls
        100.times { Dexpace::ContextStore.default }
        print after_first.positive?, ' ', calls == after_first
      RUBY

      assert_predicate(status, :success?, err)
      assert_empty(err)
      assert_equal("true true", out)
    end
  end
end
