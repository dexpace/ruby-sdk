# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/fake_config_source"

# CFG-13: the process-wide slot -- last-write-wins replacement, safe publication, defaulting to
# the empty configuration -- through Dexpace.configure, .configuration and .reset_config!.
# Every test that calls .configure restores the slot in teardown (testing/4ef070df).
module ConfigTest
  # The slot's contract.
  class SlotTest < DexpaceTestCase
    def teardown
      Dexpace.reset_config!
      super
    end

    test "CFG-13: the slot defaults to Configuration::EMPTY, by identity" do
      assert_same(Dexpace::Configuration::EMPTY, Dexpace.configuration)
    end

    test "CFG-13: configure yields a builder seeded from the live slot and publishes the result" do
      returned = Dexpace.configure do |c|
        c.env_source = FakeConfigSource.new
        c.override("APP_NAME", "DexpaceApp")
        c.property("service.timeout", "5000")
      end

      assert_same(returned, Dexpace.configuration)
      assert_equal("DexpaceApp", Dexpace.configuration.string("APP_NAME"))
      assert_equal("5000", Dexpace.configuration.string("SERVICE_TIMEOUT"))
      assert_equal("5000", Dexpace.configuration.raw_property("service.timeout"))
    end

    # The slot is seeded from itself, so a builder that treated an inherited seam as explicitly
    # installed would make THIS raise -- and a library setting a default at boot followed by an
    # application adding one is the ordinary case. CFG-13 is last-write-wins, asserted at the key
    # level.
    test "CFG-13: a second configure adds a property to the slot; a third replaces one key" do
      Dexpace.configure { |c| c.property("service.timeout", "5000") }
      Dexpace.configure { |c| c.property("https.proxyHost", "proxy.corp") }

      assert_equal("proxy.corp", Dexpace.configuration.raw_property("https.proxyHost"))
      assert_equal("5000", Dexpace.configuration.raw_property("service.timeout"))

      Dexpace.configure { |c| c.property("service.timeout", "9000") }

      assert_equal("9000", Dexpace.configuration.raw_property("service.timeout"))
      assert_equal("proxy.corp", Dexpace.configuration.raw_property("https.proxyHost"))
    end

    # 5a's review R1-2, repaired by phase 10: every configure that added a property wrapped the
    # inherited source in one more closure, so a lookup walked one frame per configure ever made
    # and nothing released them. The base source records how deep below the lookup it was
    # reached; after 200 configures that depth must equal the depth after 2.
    test "CFG-13: a lookup's depth does not grow with the number of configures" do
      depths = []
      base = lambda do |_key|
        depths << caller.size
        nil
      end
      Dexpace.configure { |c| c.property_source = base }
      Dexpace.configure { |c| c.property("a", "1") }
      Dexpace.configure { |c| c.property("b", "2") }
      Dexpace.configuration.string("absent")
      200.times { |i| Dexpace.configure { |c| c.property("k#{i}", i.to_s) } }
      Dexpace.configuration.string("absent")

      assert_equal(depths.first, depths.last, "the property chain grew with the configure count")
      assert_equal("1", Dexpace.configuration.string("a"))
      assert_equal("199", Dexpace.configuration.string("k199"))
    end

    test "CFG-13: reset_config! restores Configuration::EMPTY and returns it" do
      Dexpace.configure { |c| c.override("K", "V") }

      refute_same(Dexpace::Configuration::EMPTY, Dexpace.configuration)
      assert_same(Dexpace::Configuration::EMPTY, Dexpace.reset_config!)
      assert_same(Dexpace::Configuration::EMPTY, Dexpace.configuration)
    end

    # The mutex is held across the assignment and nothing else: the block runs before it is taken,
    # so a block that reads the slot cannot deadlock a non-reentrant, per-fiber-owned mutex.
    test "CFG-13: a configure block that reads Dexpace.configuration does not deadlock" do
      Dexpace.configure do |c|
        assert_kind_of(Dexpace::Configuration, Dexpace.configuration)
        c.override("REENTRANT", "safe")
      end

      assert_equal("safe", Dexpace.configuration.string("REENTRANT"))
    end

    test "CFG-13 / CFG-37: configure without a block fails fast and publishes nothing" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace.configure }

      assert_equal("configure block is required", error.message)
      assert_same(Dexpace::Configuration::EMPTY, Dexpace.configuration)
    end

    test "CFG-37: a block that raises publishes nothing" do
      before = Dexpace.configuration

      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace.configure { |c| c.override("K", nil) }
      end
      assert_same(before, Dexpace.configuration)
    end

    test "CFG-8 / CFG-13: the published snapshot is frozen, so a reader observes it whole" do
      Dexpace.configure { |c| c.override("K", "V") }
      snapshot = Dexpace.configuration

      assert_predicate(snapshot, :frozen?)
      assert_predicate(snapshot.overrides, :frozen?)

      Dexpace.configure { |c| c.override("K", "W") }

      assert_equal("V", snapshot.string("K"))
      assert_equal("W", Dexpace.configuration.string("K"))
      refute_same(snapshot, Dexpace.configuration)
    end

    test "CFG-13: no observer, listener or change notification exists on the slot" do
      %i[on_configure subscribe add_listener on_change].each do |name|
        refute_respond_to(Dexpace, name)
      end
    end
  end

  # XCUT-11: the slot under concurrent writers and readers.
  class RaceTest < DexpaceTestCase
    def teardown
      Dexpace.reset_config!
      super
    end

    # A frozen snapshot swapped under the mutex: every reader sees a whole configuration -- one of
    # the published ones or the empty one -- never a torn or unfrozen object, and the last writer
    # to run wins. The guard that drops the mutex around the swap runs red on the assert_same
    # below only probabilistically, which is why the invariant every reader checks is the one
    # that is asserted deterministically.
    test "XCUT-11 / CFG-13: 16 writers and 16 readers over one slot see only whole snapshots" do
      seen = ::Thread::Queue.new
      go = ::Thread::Queue.new
      writers = Array.new(16) do |i|
        Thread.new do
          go.pop
          50.times { |n| Dexpace.configure { |c| c.override("W", "#{i}-#{n}") } }
        end
      end
      readers = Array.new(16) do
        Thread.new do
          go.pop
          200.times do
            cfg = Dexpace.configuration
            seen << [cfg.frozen?, cfg.overrides.frozen?, cfg.is_a?(Dexpace::Configuration)]
          end
        end
      end
      32.times { go << true }
      (writers + readers).each(&:join)

      assert_equal(3200, seen.size)
      seen.size.times { assert_equal([true, true, true], seen.pop) }
      assert_match(/\A\d+-49\z/, Dexpace.configuration.string("W"))
    end

    # Under the GVL a single reference assignment is atomic, so dropping the mutex around the
    # swap is invisible to every behavioural case above; XCUT-11's rule is stated for the row a
    # GVL-free interpreter would add (docs/first-release.md's IO-38 trigger), so the shape is
    # pinned by text: both writers publish inside `@config_mutex.synchronize`.
    test "XCUT-11 / CFG-13: both publications happen inside the one mutex" do
      path = File.expand_path("../../lib/dexpace/config.rb", __dir__)
      code = File.readlines(path).grep_v(/\A\s*#/).join

      assert_equal(2, code.scan(/@config_mutex\.synchronize \{ @configuration = /).size)
      assert_empty(code.scan(/^\s*@configuration = (?!Configuration::EMPTY$)/))
    end

    test "XCUT-11 / CFG-13: configure and reset_config! racing leave the slot whole either way" do
      go = ::Thread::Queue.new
      threads = Array.new(8) do |i|
        Thread.new do
          go.pop
          100.times do
            i.even? ? Dexpace.configure { |c| c.override("R", i.to_s) } : Dexpace.reset_config!
          end
        end
      end
      8.times { go << true }
      threads.each(&:join)

      final = Dexpace.configuration

      assert_predicate(final, :frozen?)
      assert_kind_of(Dexpace::Configuration, final)
    end
  end
end
