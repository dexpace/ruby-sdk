# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/fake_config_source"

# CFG-1 through CFG-4, CFG-8, CFG-13, CFG-37 and CFG-38 on Dexpace::Configuration -- the Builder's
# own rows are in configuration/builder_test.rb -- and CFG-5, CFG-6, CFG-7, CFG-33 and CFG-34
# asserted at their call sites, because ConfigParsers and DeepValue are private_constants with no
# test mirror (P2-15, P4-3). Inside `module Dexpace` so
# both are reachable by bare name, which is the reachability condition the privacy rests on.
#
# Every Configuration in this file passes BOTH seams explicitly. Configuration.build defaults
# env_source: to Sources::ENVIRONMENT, and a test that omits it reads the developer's real
# environment -- which CFG-11 exists to make unnecessary and which makes a suite depend on the
# machine it runs on.
module Dexpace
  module ConfigurationTest
    # CFG-1 to CFG-4: the four tiers and the two accessors.
    class LookupTest < DexpaceTestCase
      def build(overrides: {}, env: {}, prop: {})
        Configuration.build(
          overrides: overrides,
          env_source: FakeConfigSource.new(env),
          property_source: FakeConfigSource.new(prop),
        )
      end

      test "CFG-1: override, then exact-name env, then normalised property, then the default" do
        all = build(overrides: { "KEY" => "from_override" }, env: { "KEY" => "from_env" },
                    prop: { "key" => "from_prop" },)

        assert_equal("from_override", all.string("KEY", default: "default"))
        assert_equal("from_env", build(env: { "KEY" => "from_env" }, prop: { "key" => "from_prop" })
          .string("KEY", default: "default"),)
        assert_equal("from_prop",
                     build(prop: { "key" => "from_prop" }).string("KEY", default: "default"),)
        assert_equal("default", build.string("KEY", default: "default"))
        assert_nil(build.string("KEY"))
      end

      # The guard that swaps ENV and the configure tier runs red here: the specification's order is
      # kept even where it inverts Ruby convention (§10.16, boundary 6).
      test "CFG-1 / §10.16: the environment beats the property (configure) tier" do
        cfg = build(env: { "KEY" => "from_env" }, prop: { "key" => "from_prop" })

        assert_equal("from_env", cfg.string("KEY"))
      end

      test "CFG-2 asymmetry: empty env falls through; an empty override or property does not" do
        assert_equal("from_prop",
                     build(env: { "KEY" => "" }, prop: { "key" => "from_prop" }).string("KEY"),)
        assert_equal("fallback", build(env: { "KEY" => "" }).string("KEY", default: "fallback"))
        # The second half is what stops a later refactor making emptiness a chain-wide rule: CFG-2
        # names the environment layer and only the environment layer.
        assert_equal("",
                     build(overrides: { "KEY" => "" }, env: { "KEY" => "from_env" }).string("KEY"),)
        assert_equal("", build(prop: { "key" => "" }).string("KEY", default: "fallback"))
      end

      test "CFG-3: the property tier is queried under the normalised key: downcased, _ -> ." do
        cfg = build(prop: { "max.retry.attempts" => "5", "a.b.c" => "x" })

        assert_equal("5", cfg.string("MAX_RETRY_ATTEMPTS"))
        assert_equal("x", cfg.string("A_B_C"))
        assert_equal("x", cfg.string("a.b.c"))
        assert_nil(build(prop: { "MAX_RETRY_ATTEMPTS" => "5" }).string("MAX_RETRY_ATTEMPTS"))
      end

      test "CFG-1 / CFG-3: the override and environment tiers use the exact name, unnormalised" do
        assert_nil(build(overrides: { "max.retry.attempts" => "5" }).string("MAX_RETRY_ATTEMPTS"))
        assert_nil(build(env: { "max.retry.attempts" => "5" }).string("MAX_RETRY_ATTEMPTS"))
      end

      test "CFG-4: raw_property reads the exact property name with no normalisation" do
        cfg = build(prop: { "https.proxyHost" => "proxy.corp",
                            "http.nonProxyHosts" => "*.internal", })

        assert_equal("proxy.corp", cfg.raw_property("https.proxyHost"))
        assert_equal("*.internal", cfg.raw_property("http.nonProxyHosts"))
        assert_nil(cfg.raw_property("HTTPS.PROXYHOST"))
        assert_nil(cfg.raw_property("https.proxyhost"))
        assert_equal("d", cfg.raw_property("absent", default: "d"))
        assert_nil(cfg.raw_property("absent"))
      end

      # CFG-4 reads ONLY the property tier: an override or an env value under the same name does
      # not leak into it, which is what keeps §10.16's "one deviation applied twice" one deviation.
      test "CFG-4: raw_property consults neither the override map nor the environment" do
        cfg = build(overrides: { "https.proxyHost" => "o" }, env: { "https.proxyHost" => "e" })

        assert_nil(cfg.raw_property("https.proxyHost"))
      end

      test "CFG-37: a lookup name is required; a nil default is the documented-nullable one" do
        cfg = build

        assert_raises(InvalidArgumentError) { cfg.string(nil) }
        assert_raises(InvalidArgumentError) { cfg.raw_property(nil) }
        assert_raises(InvalidArgumentError) { cfg.integer(nil) }
        assert_nil(cfg.string("ANY", default: nil))
        assert_equal("x", cfg.string(:SYM_KEY, default: "x"))
      end
    end

    # CFG-5, CFG-6, CFG-7 and CFG-38: the typed accessors, asserted at ConfigParsers' call sites.
    class AccessorsTest < DexpaceTestCase
      def config(env)
        Configuration.build(env_source: FakeConfigSource.new(env),
                            property_source: FakeConfigSource.new,)
      end

      # Supplied through the ENV seam and not as an override, deliberately: a test that supplies
      # the value as an override passes against an implementation that reads only the override
      # map, which is the implementation CFG-38 exists to forbid.
      test "CFG-38: the typed accessors resolve through the env and property tiers, not the map" do
        cfg = Configuration.build(
          env_source: FakeConfigSource.new("INT_KEY" => "42", "BOOL_KEY" => "true",
                                           "DUR_KEY" => "500ms",),
          property_source: FakeConfigSource.new("prop.int" => "7", "prop.bool" => "FALSE",
                                                "prop.dur" => "PT2S",),
        )

        assert_equal(42, cfg.integer("INT_KEY"))
        assert_same(true, cfg.boolean("BOOL_KEY"))
        assert_in_delta(0.5, cfg.duration("DUR_KEY"), 1e-9)
        assert_equal(7, cfg.integer("PROP_INT"))
        assert_same(false, cfg.boolean("PROP_BOOL"))
        assert_in_delta(2.0, cfg.duration("PROP_DUR"), 1e-9)
      end

      test "CFG-38: the typed default applies only when the whole chain is absent or unparseable" do
        cfg = Configuration.build(overrides: { "OVER" => "1" },
                                  env_source: FakeConfigSource.new("BAD" => "x"),
                                  property_source: FakeConfigSource.new,)

        assert_equal(1, cfg.integer("OVER", default: 9))
        assert_equal(9, cfg.integer("BAD", default: 9))
        assert_equal(9, cfg.integer("ABSENT", default: 9))
      end

      test "CFG-5: integers parse in base 10, never throw, and negatives come back as-is" do
        cfg = config("OCTAL_LOOKING" => "010", "NEGATIVE" => "-5", "UNDERSCORED" => "1_000",
                     "PADDED" => " 5 ", "HEXY" => "0x10", "SCIENTIFIC" => "1e3", "JUNK" => "5x",
                     "FLOAT" => "1.5", "BLANK" => "",)

        # The live defect, not a theoretical one: Integer("010") is 8 and Integer("010", 10) is 10.
        assert_equal(10, cfg.integer("OCTAL_LOOKING"))
        assert_equal(-5, cfg.integer("NEGATIVE"))
        # Ruby's two tolerances, documented rather than removed.
        assert_equal(1000, cfg.integer("UNDERSCORED"))
        assert_equal(5, cfg.integer("PADDED"))
        %w[HEXY SCIENTIFIC JUNK FLOAT MISSING].each do |key|
          assert_equal(99, cfg.integer(key, default: 99), key)
          assert_nil(cfg.integer(key), key)
        end
        assert_equal(99, cfg.integer("BLANK", default: 99)) # CFG-2: "" in env is absent
      end

      test "CFG-6: the boolean accessor recognises exactly true and false, case-insensitively" do
        entries = { "T" => "true", "F" => "false", "UPPER" => "TRUE", "MIXED" => "FaLsE",
                    "PADDED" => " true", }
        %w[1 0 yes no on off t f].each_with_index { |token, i| entries["TOKEN#{i}"] = token }
        cfg = config(entries)

        assert_same(true, cfg.boolean("T"))
        assert_same(false, cfg.boolean("F"))
        assert_same(true, cfg.boolean("UPPER"))
        assert_same(false, cfg.boolean("MIXED"))
        # No trimming: CFG-6 grants case-insensitivity and nothing else.
        assert_nil(cfg.boolean("PADDED"))
        8.times { |i| assert_nil(cfg.boolean("TOKEN#{i}"), "TOKEN#{i} must not be recognised") }
        assert_same(true, cfg.boolean("MISSING", default: true))
        assert_same(false, cfg.boolean("TOKEN0", default: false))
      end

      test "CFG-7: durations parse ISO-8601, shorthand and bare milliseconds into Float seconds" do
        cfg = config("ISO_S" => "PT5S", "ISO_D" => "P1D", "ISO_MIX" => "P1DT2H3M4S",
                     "ISO_ZERO" => "PT0S", "ISO_LOWER" => "pt5s", "ISO_FRAC" => "PT0.5S",
                     "ISO_NEG" => "PT-5S", "ISO_BARE" => "P", "ISO_JUNK" => "P1X",
                     "MS" => "250ms", "SEC" => "3s", "MIN" => "2m", "HOUR" => "1h", "DAY" => "1d",
                     "CAPS" => "250MS", "SPACED" => "250 ms", "FRAC" => "1.5s",
                     "BARE" => "1500", "BARE_ZERO" => "0", "NEG_SHORT" => "-3s", "NEG_BARE" => "-1",
                     "UNKNOWN_UNIT" => "5w", "JUNK" => "soon",)

        # P5-4: the return is Float SECONDS, which is what Kernel#sleep, Queue#pop(timeout:) and
        # phase 1's RequestOptions#timeout already speak.
        expected = { "ISO_S" => 5.0, "ISO_D" => 86_400.0, "ISO_MIX" => 93_784.0, "ISO_ZERO" => 0.0,
                     "ISO_LOWER" => 5.0, "ISO_FRAC" => 0.5, "MS" => 0.25, "SEC" => 3.0,
                     "MIN" => 120.0, "HOUR" => 3600.0, "DAY" => 86_400.0, "CAPS" => 0.25,
                     "SPACED" => 0.25, "FRAC" => 1.5, "BARE" => 1.5, "BARE_ZERO" => 0.0, }
        expected.each do |key, seconds|
          value = cfg.duration(key)

          assert_kind_of(Float, value, key)
          assert_in_delta(seconds, value, 1e-9, key)
        end
        # A negative in any form, an unknown unit and garbage all yield the default, never throw.
        %w[ISO_NEG ISO_BARE ISO_JUNK NEG_SHORT NEG_BARE UNKNOWN_UNIT JUNK MISSING].each do |key|
          assert_equal(:d, cfg.duration(key, default: :d), key)
          assert_nil(cfg.duration(key), key)
        end
      end

      test "CFG-7: the three duration grammars are compiled once, each with its own timeout" do
        %i[DURATION_ISO DURATION_UNIT DURATION_BARE].each do |name|
          pattern = ConfigParsers.const_get(name)

          assert_kind_of(::Regexp, pattern, name.to_s)
          refute_nil(pattern.timeout, name.to_s)
        end
      end
    end

    # CFG-33 and CFG-34, at DeepValue's call sites (R4, P5-14, P5-15).
    class DeepValueTest < DexpaceTestCase
      # Two traps, and the pair is chosen to spring both. First: `[n] == [n]` with the SAME object
      # is true, because Array#== short-circuits on identity, so a test written with one NaN
      # literal passes against a broken implementation; refute_same makes the precondition
      # visible. Second: the payloads must DIFFER. 0.0/0.0 and -(0.0/0.0) are both NaN with
      # opposite sign bits, so Float#hash disagrees about them and an implementation that never
      # folds NaN fails here; a same-bits pair hashes equal through Float#hash alone. `"nan".to_f`
      # is NOT a NaN in Ruby; it is 0.0. No assertion names a literal hash: Float#hash is seeded
      # per process.
      test "CFG-34: NaN equals NaN, and two NaNs with different payloads hash alike" do
        a = 0.0 / 0.0
        b = -(0.0 / 0.0)

        refute_same(a, b)
        assert_predicate(a, :nan?)
        assert_predicate(b, :nan?)
        refute_equal(a.hash, b.hash) # the precondition: Ruby's own hash disagrees about this pair
        assert(DeepValue.equal?(a, b))
        assert(DeepValue.equal?([a], [b]))
        assert_equal(DeepValue.hash([a]), DeepValue.hash([b]))
        refute(DeepValue.equal?([a], [0.0]))
      end

      test "CFG-34: +0.0 and -0.0 are unequal, and their hashes differ to match" do
        assert_equal(0.0.hash, -0.0.hash) # Ruby's own agree, which is why the hash half is not free

        refute(DeepValue.equal?(0.0, -0.0))
        refute(DeepValue.equal?([0.0], [-0.0]))
        refute_equal(DeepValue.hash([0.0]), DeepValue.hash([-0.0]))
        assert(DeepValue.equal?([0.0], [0.0]))
        assert(DeepValue.equal?([-0.0], [-0.0]))
        assert_equal(DeepValue.hash([-0.0]), DeepValue.hash([-0.0]))
      end

      test "CFG-34 / P5-14: element kinds are distinct -- an Integer array is not a Float array" do
        assert_equal([1], [1.0]) # Ruby says they are equal; CFG-34 says they are not

        refute(DeepValue.equal?([1], [1.0]))
        refute_equal(DeepValue.hash([1]), DeepValue.hash([1.0]))
        assert(DeepValue.equal?([1, 2.5], [1, 2.5]))
        assert_equal(DeepValue.hash([1, 2.5]), DeepValue.hash([1, 2.5]))
      end

      test "CFG-33: content-based, recursive, null-safe; null hashes to zero" do
        assert(DeepValue.equal?(nil, nil))
        refute(DeepValue.equal?(nil, 1))
        refute(DeepValue.equal?(1, nil))
        assert_equal(0, DeepValue.hash(nil))
        assert(DeepValue.equal?([[1, "a"], { "k" => [2.0] }], [[1, "a"], { "k" => [2.0] }]))
        assert_equal(DeepValue.hash([[1, "a"], { "k" => [2.0] }]),
                     DeepValue.hash([[1, "a"], { "k" => [2.0] }]),)
        refute(DeepValue.equal?([[1, "a"]], [[1, "b"]]))
        refute(DeepValue.equal?({ "k" => 1 }, { "k" => 1, "j" => 2 }))
        refute(DeepValue.equal?([1, 2], [1, 2, 3]))
        assert(DeepValue.equal?("s", "s"))
        refute(DeepValue.equal?("s", :s))
      end

      test "CFG-33: byte arrays fall back to ordinary equality on the BINARY String" do
        # Ruby's primitive byte array is a String, so CFG-33's byte-array case is its "non-arrays
        # fall back to ordinary equality" clause and not an array-path branch.
        assert(DeepValue.equal?("\xff\x00".b, "\xff\x00".b))
        refute(DeepValue.equal?("\xff\x00".b, [255, 0]))
        assert_equal(DeepValue.hash("\xff\x00".b), DeepValue.hash("\xff\x00".b))
      end

      # P5-15: no CFG ID asks for this; a hand-written helper that stack-overflows on the one input
      # Array#== handles would be a regression against the language.
      test "CFG-33 / P5-15: a self-referential structure compares and hashes without overflowing" do
        x = []
        x << x
        y = []
        y << y

        assert(DeepValue.equal?(x, y))
        assert_equal(DeepValue.hash(x), DeepValue.hash(y))

        h = {}
        h["self"] = h

        assert(DeepValue.equal?(h, h))
        assert_kind_of(Integer, DeepValue.hash(h))
      end

      # The pair guard, and the stack that unwinds: two independent visited sets pass the cycle
      # case above and still get both of these wrong.
      test "CFG-33: the visited guard is keyed by the pair, and the hash stack unwinds" do
        one = [1]
        two = [2]

        refute(DeepValue.equal?([one, two, one], [[1], [2], [2]]))

        shared = [1]

        assert(DeepValue.equal?([shared, shared], [[1], [1]]))
        assert_equal(DeepValue.hash([shared, shared]), DeepValue.hash([[1], [1]]))
      end
    end

    # P2-15 / P4-3's reachability condition, asserted rather than assumed: a private_constant on
    # Dexpace is reachable by bare name from any file that reopens `module Dexpace; ...` in the
    # full nesting form -- which this suite does -- and unreachable through a qualified reference.
    # That asymmetry is what lets these two ship with no sig/ mirror, no YARD-gate entry and no
    # surface-manifest row, and it is why the assertions above can exist at all.
    class PrivacyTest < DexpaceTestCase
      test "P2-15: ConfigParsers and DeepValue are private constants, reachable only unqualified" do
        assert_kind_of(::Module, DeepValue)
        assert_kind_of(::Module, ConfigParsers)
        assert_raises(::NameError) { ::Dexpace::DeepValue }
        assert_raises(::NameError) { ::Dexpace::ConfigParsers }
        refute_includes(Dexpace.constants, :DeepValue)
        refute_includes(Dexpace.constants, :ConfigParsers)
      end
    end
  end
end
