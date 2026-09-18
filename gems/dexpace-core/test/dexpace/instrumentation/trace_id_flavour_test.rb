# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# OBS-27's trace-id flavours and CTX-14's "a trace-id encoding flavor" slot; P4-7's split of the
# reserved trace-id sentinel from the span-id one; and, from phase 5c, OBS-27's generation with
# its unconditional zero-draw coercion (P5-44, P5-50).
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the table
# and the two predicates here, each flavour's own rule and the construction pattern below, then
# phase 5c's generation.
class DexpaceInstrumentationTraceIdFlavourTest < DexpaceTestCase
  Flavour = Dexpace::Instrumentation::TraceIdFlavour

  FLAVOURS = [
    Flavour::NONE,
    Flavour::W3C,
    Flavour::DATADOG,
  ].freeze

  VALID_SAMPLES = {
    Flavour::NONE => [],
    Flavour::W3C => ["a" * 32, "0123456789abcdef" * 2],
    Flavour::DATADOG => %w[1 42 18446744073709551615],
  }.freeze

  INVALID_SAMPLES = {
    Flavour::NONE => ["a" * 32, "0", ""],
    Flavour::W3C => ["A" * 32, "a" * 31, "a" * 33, "", "0"],
    Flavour::DATADOG => ["1a", "", "0" * 32, "184467440737095516150", "99999999999999999999"],
  }.freeze

  test ".of round-trips a recognised name" do
    FLAVOURS.each { |flavour| assert_same(flavour, Flavour.of(flavour.name)) }
  end

  test ".of raises Dexpace::InvalidArgumentError on an unrecognised name, like Protocol.parse" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Flavour.of(:bogus) }

    assert_includes(error.message, ":bogus")
    assert_raises(Dexpace::InvalidArgumentError) { Flavour.of("w3c") }
  end

  test "ALL is the frozen closed set, in the design's order" do
    assert_equal(FLAVOURS, Flavour::ALL)
    assert_predicate(Flavour::ALL, :frozen?)
    assert_equal(%i[none w3c datadog], Flavour::ALL.map(&:name))
  end

  test "NONE's sentinel is OBS-26's 32 hex zeros, not a flavour-specific zero draw" do
    assert_equal("0" * 32, Flavour::NONE.invalid_trace_id)
    assert_equal("0" * 32, Flavour::W3C.invalid_trace_id)
  end

  test "DATADOG's own zero draw is '0', distinct from OBS-26's sentinel (P4-7)" do
    assert_equal("0", Flavour::DATADOG.invalid_trace_id)
  end

  test "NONE renders only the sentinel: a disabled-tracing bundle carries no trace id of its own" do
    assert(Flavour::NONE.renders?("0" * 32))
    refute(Flavour::NONE.valid_trace_id?("0" * 32))
    refute(Flavour::NONE.renders?("a" * 32))
    refute(Flavour::NONE.renders?("0"))
  end

  # testing/f36a19cd: a parse-constructor invariant gets a round-trip property test.
  # #renders?(x) == (#valid_trace_id?(x) || x == invalid_trace_id) for every generated x, and the
  # two predicates disagree at exactly one input: the flavour's own sentinel.
  test "renders? and valid_trace_id? agree everywhere except at the sentinel" do
    sample(count: 64, seed: 20_260_908) do |rng|
      flavour = FLAVOURS.sample(random: rng)
      candidates = [flavour.invalid_trace_id] + VALID_SAMPLES[flavour] + INVALID_SAMPLES[flavour]
      candidate = candidates.sample(random: rng)

      assert_equal(
        flavour.valid_trace_id?(candidate) || candidate == flavour.invalid_trace_id,
        flavour.renders?(candidate),
        "#{flavour.name}: #{candidate.inspect}",
      )
    end
  end

  test "the sentinel is the one input where the two predicates disagree" do
    FLAVOURS.each do |flavour|
      assert(flavour.renders?(flavour.invalid_trace_id))
      refute(flavour.valid_trace_id?(flavour.invalid_trace_id))
    end
  end

  test "every valid sample is valid and renders; every invalid sample is neither" do
    FLAVOURS.each do |flavour|
      VALID_SAMPLES[flavour].each do |trace_id|
        assert(flavour.valid_trace_id?(trace_id), "#{flavour.name}: #{trace_id.inspect}")
        assert(flavour.renders?(trace_id), "#{flavour.name}: #{trace_id.inspect}")
      end
      INVALID_SAMPLES[flavour].each do |trace_id|
        refute(flavour.valid_trace_id?(trace_id), "#{flavour.name}: #{trace_id.inspect}")
        refute(flavour.renders?(trace_id), "#{flavour.name}: #{trace_id.inspect}")
      end
    end
  end

  # OBS-26 and OBS-27, per flavour, and the construction pattern.
  class PerFlavourTest < DexpaceTestCase
    test "DATADOG accepts a 64-bit decimal rendering and nothing wider" do
      datadog = Flavour::DATADOG

      assert(datadog.valid_trace_id?("18446744073709551615"))
      refute(datadog.valid_trace_id?("184467440737095516150"))
      refute(datadog.valid_trace_id?("1a"))
      refute(datadog.valid_trace_id?(""))
    end

    # OBS-27's Datadog flavour is "a 64-bit unsigned integer rendered as a decimal string", and a
    # digit count cannot express that bound: \A[0-9]{1,20}\z accepts both values below, and only
    # the second is out of range. The bound is max_value on the flavour, so this is the one test
    # that fails if it is dropped -- the digit-count test above passes either way.
    test "OBS-27: DATADOG rejects a 20-digit value above 2**64 - 1, at the boundary" do
      datadog = Flavour::DATADOG

      assert(datadog.valid_trace_id?(((2**64) - 1).to_s))
      refute(datadog.valid_trace_id?((2**64).to_s))
      refute(datadog.valid_trace_id?("99999999999999999999"))
      refute(datadog.renders?("99999999999999999999"))
      assert_equal((2**64) - 1, datadog.max_value)
      assert_nil(Flavour::W3C.max_value)
      assert_nil(Flavour::NONE.max_value)
    end

    # OBS-26: "32 lowercase hex chars". Lowercase-only and rejected rather than folded -- a fold
    # would silently accept 0A where the wire form is 0a (Dexpace/NoLocaleCaseFold has nothing to
    # bite on here because nothing folds).
    test "W3C accepts exactly 32 lowercase hex characters" do
      assert(Flavour::W3C.valid_trace_id?("a" * 32))
      assert(Flavour::W3C.valid_trace_id?("0123456789abcdef" * 2))
      refute(Flavour::W3C.valid_trace_id?("A" * 32))
      refute(Flavour::W3C.valid_trace_id?("a" * 31))
      refute(Flavour::W3C.valid_trace_id?("a" * 33))
      refute(Flavour::W3C.valid_trace_id?("g" * 32))
    end

    test "every flavour is a frozen Data with its pattern built with a per-pattern timeout" do
      FLAVOURS.each do |flavour|
        assert_predicate(flavour, :frozen?)
        assert_predicate(flavour.invalid_trace_id, :frozen?)
        refute_nil(flavour.trace_id_pattern.timeout, "#{flavour.name}: no per-pattern timeout")
        assert_in_delta(1.0, flavour.trace_id_pattern.timeout)
      end
      assert_nil(Regexp.timeout, "no process-global regexp budget is imposed on the host")
    end

    test "the construction pattern: private new, validating build, and #with through build" do
      refute_respond_to(Flavour, :new)
      assert_raises(Dexpace::InvalidArgumentError) do
        Flavour.build(name: nil, trace_id_pattern: /x/, invalid_trace_id: "0")
      end
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Flavour::W3C.with(invalid_trace_id: nil)
      end

      assert_equal("invalid_trace_id is required", error.message)
      derived = Flavour::W3C.with(name: :other)

      assert_equal(:other, derived.name)
      assert_same(Flavour::W3C.trace_id_pattern, derived.trace_id_pattern)
    end
  end

  # OBS-27: generation, per flavour, from the CSPRNG path (XCUT-21's, not CFG-32's non-cryptographic
  # one -- boundary 8 keeps the two apart), with the coercion driven through the optional
  # generator seam because a zero draw is unreachable by sampling.
  class GenerationTest < DexpaceTestCase
    # The seam's protocol is SecureRandom's own two methods, so a `Random` instance -- which has
    # both through Random::Formatter -- is a deterministic stand-in and no module is swapped.
    class ZeroGenerator
      def hex(_bytes) = "0" * 32
      def random_number(_max) = 0
    end

    test "OBS-27: W3C generates 32 lowercase hex chars, never the sentinel, frozen" do
      flavour = Flavour::W3C
      ids = Array.new(1000) { flavour.generate_trace_id }

      ids.each do |id|
        assert_match(/\A[0-9a-f]{32}\z/, id)
        refute_equal(flavour.invalid_trace_id, id)
        assert(flavour.valid_trace_id?(id))
        assert_predicate(id, :frozen?)
      end
      assert_equal(1000, ids.uniq.size, "a 128-bit CSPRNG draw does not repeat in a thousand")
    end

    test "OBS-27: DATADOG generates a decimal 64-bit unsigned integer, never '0', frozen" do
      flavour = Flavour::DATADOG
      ids = Array.new(1000) { flavour.generate_trace_id }

      ids.each do |id|
        assert_match(/\A[0-9]{1,20}\z/, id)
        refute_equal(flavour.invalid_trace_id, id)
        assert(flavour.valid_trace_id?(id))
        assert_includes(1..((2**64) - 1), ::Kernel.Integer(id, 10))
        assert_predicate(id, :frozen?)
      end
    end

    test "OBS-27: NONE always yields the invalid sentinel, the same frozen object" do
      assert_same(Flavour::NONE.invalid_trace_id, Flavour::NONE.generate_trace_id)
      assert_same(Flavour::NONE.invalid_trace_id, Flavour::NONE.generate_trace_id(ZeroGenerator.new))
      assert_equal("0" * 32, Flavour::NONE.generate_trace_id)
    end

    # "a zero draw MUST be coerced to a non-zero value": a substitution, not a redraw, because a
    # redraw loop against an always-zero generator never terminates and the requirement's word
    # is "coerced". The result is valid under the flavour, so it renders in a Bundle.
    test "OBS-27: a zero draw is coerced to a valid non-zero id for W3C and DATADOG" do
      zero = ZeroGenerator.new
      w3c = Flavour::W3C.generate_trace_id(zero)
      datadog = Flavour::DATADOG.generate_trace_id(zero)

      assert_equal("#{"0" * 31}1", w3c)
      assert(Flavour::W3C.valid_trace_id?(w3c))
      assert_equal("1", datadog)
      assert(Flavour::DATADOG.valid_trace_id?(datadog))
    end

    test "OBS-27: a seeded Random is a deterministic generator through the same seam" do
      first = Flavour::W3C.generate_trace_id(::Random.new(42))
      second = Flavour::W3C.generate_trace_id(::Random.new(42))

      assert_equal(first, second)
      assert(Flavour::W3C.valid_trace_id?(first))
      assert_equal(
        Flavour::DATADOG.generate_trace_id(::Random.new(7)),
        Flavour::DATADOG.generate_trace_id(::Random.new(7)),
      )
    end

    # P5-50: generation dispatches on the name because a fourth Data member is redefinition
    # (boundary 10), so a flavour derived through #with with a name outside OBS-27's three has
    # no generator and says so in the SDK's own error.
    test "P5-50: a flavour outside the closed set raises InvalidArgumentError from generation" do
      other = Flavour::W3C.with(name: :other)
      error = assert_raises(Dexpace::InvalidArgumentError) { other.generate_trace_id }

      assert_includes(error.message, ":other")
    end
  end
end
