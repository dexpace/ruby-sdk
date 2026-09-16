# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# OBS-27's trace-id flavours and CTX-14's "a trace-id encoding flavor" slot; P4-7's split of the
# reserved trace-id sentinel from the span-id one.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the table
# and the two predicates here, each flavour's own rule and the construction pattern below.
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
end
