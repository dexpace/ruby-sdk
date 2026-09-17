# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/fake_config_source"

# CFG-8, CFG-9, CFG-10, CFG-12 and CFG-37 on Dexpace::Configuration::Builder and the derivation
# that routes through it. Every Configuration passes both seams explicitly (see
# configuration_test.rb for why).
module Dexpace
  # CFG-8, CFG-9 and CFG-10 on the Builder and the derivation.
  class BuilderTest < DexpaceTestCase
    test "CFG-8: builder mutation after build never reaches a built configuration" do
      builder = Configuration.builder
      builder.env_source = FakeConfigSource.new
      builder.override("KEY", "v1")
      first = builder.build

      builder.override("KEY", "v2")
      second = builder.build

      assert_equal("v1", first.string("KEY"))
      assert_equal("v2", second.string("KEY"))
      assert_predicate(first, :frozen?)
      assert_predicate(first.overrides, :frozen?)
      assert_raises(FrozenError) { first.overrides["KEY"] = "mutated" }
    end

    # The guard that aliases the source Hash runs red here: the caller's hash stays unfrozen and
    # a later write to it is invisible to the model (Model.own's copy: true).
    test "CFG-8: .build copies the override map it is handed and freezes only the copy" do
      source = { "KEY" => "v1" }
      cfg = Configuration.build(overrides: source, env_source: FakeConfigSource.new,
                                property_source: FakeConfigSource.new,)
      source["KEY"] = "changed"
      source["NEW"] = "late"

      refute_predicate(source, :frozen?)
      assert_equal("v1", cfg.string("KEY"))
      assert_nil(cfg.string("NEW"))
      refute_same(source, cfg.overrides)
    end

    test "CFG-9: derive is copy-on-write; the receiver is untouched and both seams are shared" do
      env = FakeConfigSource.new("A" => "alpha")
      prop = FakeConfigSource.new("b" => "bravo")
      orig = Configuration.build(overrides: { "O" => "orig" }, env_source: env,
                                 property_source: prop,)

      derived = orig.derive do |builder|
        builder.override("O", "new_orig")
        builder.override("EXTRA", "extra")
      end

      assert_equal("orig", orig.string("O"))
      assert_nil(orig.string("EXTRA"))
      assert_equal("new_orig", derived.string("O"))
      assert_equal("extra", derived.string("EXTRA"))
      # assert_same, never assert_equal: "inherited by reference (shared, not copied)".
      assert_same(orig.env_source, derived.env_source)
      assert_same(orig.property_source, derived.property_source)
      assert_equal("alpha", derived.string("A"))
      assert_equal("bravo", derived.string("B"))
    end

    test "CFG-9: a mutator that replaces a seam replaces it on the derived instance only" do
      orig = Configuration.build(env_source: FakeConfigSource.new("K" => "old"),
                                 property_source: FakeConfigSource.new,)
      replacement = FakeConfigSource.new("K" => "new")

      derived = orig.derive { |builder| builder.env_source = replacement }

      assert_same(replacement, derived.env_source)
      assert_equal("new", derived.string("K"))
      assert_equal("old", orig.string("K"))
    end

    # #property on top of an INHERITED seam composes rather than raising or discarding: the added
    # key shadows the inherited source and every other key still routes through it. That is what
    # lets a second Dexpace.configure add a property to the process-wide slot (CFG-13's
    # last-write-wins) without violating CFG-9 -- the by-reference pass-through is the branch
    # taken when no #property was called.
    test "CFG-9 / CFG-13: #property over an inherited seam composes; untouched, it is shared" do
      prop = FakeConfigSource.new("a.b" => "v")
      base = Configuration.build(env_source: FakeConfigSource.new, property_source: prop)

      untouched = base.derive { |builder| builder.override("X", "1") }

      assert_same(prop, untouched.property_source)

      composed = base.derive { |builder| builder.property("c.d", "w") }

      refute_same(prop, composed.property_source)
      assert_equal("w", composed.raw_property("c.d"))
      assert_equal("v", composed.raw_property("a.b"))
      assert_equal("v", base.raw_property("a.b"))
      assert_nil(base.raw_property("c.d"))
    end

    test "CFG-10: remove drops only the override, leaves no tombstone, and is a no-op if absent" do
      env = FakeConfigSource.new("K" => "from_env")
      cfg = Configuration.build(overrides: { "K" => "v" }, env_source: env,
                                property_source: FakeConfigSource.new,)

      removed = cfg.derive { |builder| builder.remove("K") }

      refute_includes(removed.overrides.keys, "K")
      assert_equal("from_env", removed.string("K")) # falls through as if never overridden
      assert_equal("v", cfg.string("K"))

      noop = cfg.derive { |builder| builder.remove("NEVER") }

      assert_equal(cfg.overrides, noop.overrides)
    end
  end

  # CFG-12, CFG-37 and the construction contract on the Builder.
  class BuilderContractTest < DexpaceTestCase
    test "CFG-12: the builder has no mutex (by requirement); the built model is what is shared" do
      builder = Configuration.builder

      refute(builder.instance_variables.any? do |name|
        builder.instance_variable_get(name).is_a?(::Thread::Mutex)
      end)
      assert_kind_of(Dexpace::Builder, builder)
      assert_predicate(builder.build, :frozen?)
    end

    test "#property after an explicit #property_source= raises, and the reverse" do
      builder = Configuration.builder
      builder.property_source = FakeConfigSource.new
      error = assert_raises(InvalidArgumentError) { builder.property("k", "v") }

      assert_match(/property_source=/, error.message)

      other = Configuration.builder
      other.property("k", "v")

      assert_raises(InvalidArgumentError) { other.property_source = FakeConfigSource.new }
    end

    test "CFG-4: a camelCase key set through Builder#property keeps its casing; CFG-3 holds" do
      cfg = Configuration.builder
        .tap { |b| b.env_source = FakeConfigSource.new }
        .property("https.proxyHost", "proxy.corp")
        .property("max.retry.attempts", "5")
        .build

      assert_equal("proxy.corp", cfg.raw_property("https.proxyHost"))
      assert_nil(cfg.raw_property("https.proxyhost"))
      assert_equal("5", cfg.string("MAX_RETRY_ATTEMPTS"))
    end

    test "CFG-37: every mutating operation fails fast on a null or empty required argument" do
      builder = Configuration.builder

      assert_raises(InvalidArgumentError) { builder.override("", "val") }
      assert_raises(InvalidArgumentError) { builder.override("   ", "val") }
      assert_raises(InvalidArgumentError) { builder.override(nil, "val") }
      assert_raises(InvalidArgumentError) { builder.override("K", nil) }
      assert_raises(InvalidArgumentError) { builder.property(nil, "val") }
      assert_raises(InvalidArgumentError) { builder.property("", "val") }
      assert_raises(InvalidArgumentError) { builder.property("k", nil) }
      assert_raises(InvalidArgumentError) { builder.remove(nil) }
      assert_raises(InvalidArgumentError) { builder.env_source = nil }
      assert_raises(InvalidArgumentError) { builder.env_source = "not callable" }
      assert_raises(InvalidArgumentError) { builder.property_source = nil }
      assert_raises(InvalidArgumentError) { Configuration.build(env_source: nil) }
      assert_raises(InvalidArgumentError) { Configuration.build(env_source: "not callable") }
      assert_raises(InvalidArgumentError) { Configuration.build(property_source: :sym) }
      assert_raises(InvalidArgumentError) { Configuration.build(overrides: nil) }
      assert_raises(InvalidArgumentError) { Configuration.build(overrides: [%w[k v]]) }
      assert_raises(InvalidArgumentError) { Configuration.build(overrides: { "k" => nil }) }

      error = assert_raises(InvalidArgumentError) { Configuration::EMPTY.derive }

      assert_equal("derive block is required", error.message)
    end

    # Builder.new is public and takes a seed map: the seeds go through #override and the seams
    # through the setters' guard, so the public constructor cannot store what the setters refuse
    # -- before review round 0 a nil seed value became "" (R0-6).
    test "CFG-37: Builder.new refuses a nil or blank seed and a nil or non-callable seam" do
      seeds = [{ "K" => nil }, { "" => "v" }, { nil => "v" }, { "  " => "v" }]

      seeds.each do |overrides|
        assert_raises(InvalidArgumentError, overrides.inspect) do
          Configuration::Builder.new(overrides: overrides)
        end
      end
      assert_raises(InvalidArgumentError) { Configuration::Builder.new(overrides: nil) }
      assert_raises(InvalidArgumentError) { Configuration::Builder.new(overrides: [%w[k v]]) }
      assert_raises(InvalidArgumentError) { Configuration::Builder.new(env_source: nil) }
      assert_raises(InvalidArgumentError) { Configuration::Builder.new(env_source: "text") }
      assert_raises(InvalidArgumentError) { Configuration::Builder.new(property_source: :sym) }

      seeded = Configuration::Builder.new(overrides: { K: 1, "trim" => " v " },
                                          env_source: Configuration::Sources::NONE,).build

      assert_equal("1", seeded.string("K"))
      assert_equal(" v ", seeded.string("trim"))
      assert_nil(Configuration::Builder.new(property_source: nil).build.string("K"))
    end

    test "SEAM-29 / HTTP-3: .new is private, .build validates, #with re-validates through .build" do
      refute_respond_to(Configuration, :new)
      cfg = Configuration.build(env_source: FakeConfigSource.new,
                                property_source: FakeConfigSource.new,)

      derived = cfg.with(overrides: { "K" => "v" })

      assert_equal("v", derived.string("K"))
      assert_predicate(derived.overrides, :frozen?)
      assert_same(cfg, cfg.with)
      # Data#with skips an initialize override on 3.2.11; Model#with routes through .build on
      # every row, which is what makes this raise on the floor too.
      assert_raises(InvalidArgumentError) { cfg.with(env_source: nil) }
    end

    test "CFG-8 / CFG-13: EMPTY is frozen, carries no override and platform-backed seams" do
      assert_predicate(Configuration::EMPTY, :frozen?)
      assert_empty(Configuration::EMPTY.overrides)
      assert_same(Configuration::Sources::ENVIRONMENT, Configuration::EMPTY.env_source)
      assert_same(Configuration::Sources::NONE, Configuration::EMPTY.property_source)
    end

    test "#new_builder dups the override map, never aliasing the model's" do
      cfg = Configuration.build(overrides: { "K" => "v" }, env_source: FakeConfigSource.new,
                                property_source: FakeConfigSource.new,)
      builder = cfg.new_builder
      builder.override("K", "changed")

      assert_equal("v", cfg.string("K"))
      assert_equal("changed", builder.build.string("K"))
    end
  end
end
