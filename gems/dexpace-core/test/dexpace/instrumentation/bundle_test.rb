# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-14, CTX-15, OBS-26, OBS-27; P4-6 (validity derived) and P4-7 (the two sentinels split).
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# sentinels and the required members here, then Validation and Ownership below.
class DexpaceInstrumentationBundleTest < DexpaceTestCase
  Bundle = Dexpace::Instrumentation::Bundle
  Flavour = Dexpace::Instrumentation::TraceIdFlavour
  W3C = Flavour::W3C

  test "CTX-15: Bundle::NONE carries OBS-26's reserved sentinels, isValid false, isRemote false" do
    bundle = Bundle::NONE

    assert_equal("0" * 32, bundle.trace_id)
    assert_equal("0" * 16, bundle.span_id)
    assert_equal("00", bundle.trace_flags)
    assert_equal([], bundle.trace_state)
    assert_same(Flavour::NONE, bundle.flavour)
    refute_predicate(bundle, :valid?)
    refute_predicate(bundle, :remote?)
    refute(bundle.remote)
    assert_same(Dexpace::Instrumentation::NO_SPAN, bundle.span)
    assert_same(Dexpace::Instrumentation::NO_TRACER_FACTORY, bundle.tracer_factory)
  end

  # CTX-14's nine: eight stored members and the derived ninth. The member list is the contract
  # phase 5 may not widen (roadmap obligation 1; the design's handshake, clause 4).
  test "CTX-14: exactly eight stored members, in the design's order, and validity derived" do
    assert_equal(
      %i[trace_id span_id trace_flags trace_state flavour remote span tracer_factory],
      Bundle.members,
    )
    refute_includes(Bundle.members, :valid)
    assert_respond_to(Bundle::NONE, :valid?)
  end

  test "trace_id:, span_id: and flavour: are required -- there is no silent untraced default" do
    error = assert_raises(ArgumentError) do
      Bundle.build(span_id: "a" * 16, flavour: W3C)
    end

    # Both halves are load-bearing. Dexpace::InvalidArgumentError IS an ::ArgumentError (phase 1,
    # P1-3), so `assert_raises(ArgumentError)` alone passes just as well against a .build that
    # defaulted trace_id: to nil and let Model.required! reject it -- which is exactly the silent
    # untraced default this test exists to forbid. Ruby's own missing-keyword failure is the
    # assertion; the refute is what makes it discriminating.
    refute_kind_of(Dexpace::InvalidArgumentError, error)
    assert_includes(error.message, "missing keyword")
    assert_raises(ArgumentError) { Bundle.build(trace_id: "a" * 32, flavour: W3C) }
    assert_raises(ArgumentError) { Bundle.build(trace_id: "a" * 32, span_id: "b" * 16) }
  end

  test "OBS-26: an all-zero span id makes a bundle invalid even when its trace id is real" do
    bundle = Bundle.build(
      trace_id: "a" * 32, span_id: Bundle::INVALID_SPAN_ID, flavour: W3C,
    )

    refute_predicate(bundle, :valid?)
  end

  test "OBS-26: an all-zero trace id makes a bundle invalid even when its span id is real" do
    bundle = Bundle.build(trace_id: W3C.invalid_trace_id, span_id: "b" * 16, flavour: W3C)

    refute_predicate(bundle, :valid?)
  end

  # OBS-26's per-member validation and the flavour rule.
  class ValidationTest < DexpaceTestCase
    test "OBS-26: span_id, trace_flags and trace_state are each validated on their own" do
      base = { trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C }

      assert_raises(Dexpace::InvalidArgumentError) { Bundle.build(**base, span_id: "B" * 16) }
      assert_raises(Dexpace::InvalidArgumentError) { Bundle.build(**base, span_id: "b" * 15) }
      assert_raises(Dexpace::InvalidArgumentError) { Bundle.build(**base, trace_flags: "0") }
      assert_raises(Dexpace::InvalidArgumentError) { Bundle.build(**base, trace_flags: "ZZ") }
      assert_raises(Dexpace::InvalidArgumentError) { Bundle.build(**base, trace_flags: "0A") }
      assert_raises(Dexpace::InvalidArgumentError) { Bundle.build(**base, trace_state: [["v"]]) }
      assert_raises(Dexpace::InvalidArgumentError) do
        Bundle.build(**base, trace_state: [%w[vendor value], :not_a_pair])
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Bundle.build(**base, trace_state: [["vendor", 1]])
      end
      assert_raises(Dexpace::InvalidArgumentError) { Bundle.build(**base, trace_state: "a=b") }
      assert_raises(Dexpace::InvalidArgumentError) { Bundle.build(**base, flavour: :w3c) }
    end

    test "the wire forms are accepted: sampled flags, and a vendor trace-state list" do
      bundle = Bundle.build(
        trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C, trace_flags: "01",
        trace_state: [%w[vendor value], %w[other v2]], remote: true,
      )

      assert_equal("01", bundle.trace_flags)
      assert_equal([%w[vendor value], %w[other v2]], bundle.trace_state)
      assert_predicate(bundle, :remote?)
      assert_predicate(bundle, :valid?)
    end

    test "CTX-7: a bundle is frozen on construction, Bundle::NONE included" do
      assert_predicate(Bundle::NONE, :frozen?)
      assert_predicate(
        Bundle.build(trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C),
        :frozen?,
      )
    end

    test "an explicit nil trace_id gets SEAM-29's message, not a missing-keyword error" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Bundle.build(trace_id: nil, span_id: "a" * 16, flavour: W3C)
      end

      assert_equal("trace_id is required", error.message)
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Bundle.build(trace_id: "a" * 32, span_id: "a" * 16, flavour: nil)
      end
      assert_equal("flavour is required", error.message)
    end

    test "a valid W3C bundle reports valid? true" do
      bundle = Bundle.build(trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C)

      assert_predicate(bundle, :valid?)
    end

    # OBS-26/OBS-27 together: the flavour governs the trace id only, so a Datadog bundle carries a
    # decimal trace id and a hex span id -- odd to read, and what the two requirements say.
    test "a DATADOG bundle carries a decimal trace id and a 16-hex span id" do
      bundle = Bundle.build(trace_id: "42", span_id: "b" * 16, flavour: Flavour::DATADOG)

      assert_predicate(bundle, :valid?)
      assert_raises(Dexpace::InvalidArgumentError) do
        Bundle.build(trace_id: "42", span_id: "42", flavour: Flavour::DATADOG)
      end
      refute_predicate(Bundle.build(trace_id: "0", span_id: "b" * 16, flavour: Flavour::DATADOG),
                       :valid?,)
    end

    test "a malformed span_id is rejected even though valid? would not have caught it" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Bundle.build(trace_id: "a" * 32, span_id: "not-hex", flavour: W3C)
      end
    end

    test "a trace_id that does not match its flavour is rejected, naming the flavour" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Bundle.build(trace_id: "42", span_id: "b" * 16, flavour: W3C)
      end

      assert_includes(error.message, ":w3c")
      assert_raises(Dexpace::InvalidArgumentError) do
        Bundle.build(trace_id: "a" * 32, span_id: "b" * 16, flavour: Flavour::NONE)
      end
    end
  end

  # XCUT-15's ownership, the round trip, #with and the two constants.
  class OwnershipTest < DexpaceTestCase
    # XCUT-15: the model owns its collection outright. Model.own deep-copies then deep-freezes,
    # so the caller's array is untouched and the bundle's is frozen at every level -- which Data's
    # own shallow freeze would not do (design, verified fact 15).
    test "trace_state is deep-frozen through Model.own, independent of the caller's array" do
      source = [%w[vendor value]]
      bundle = Bundle.build(
        trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C, trace_state: source,
      )
      source << %w[other value]
      source.first << "extra"

      assert_equal([%w[vendor value]], bundle.trace_state)
      assert_predicate(bundle.trace_state, :frozen?)
      assert_predicate(bundle.trace_state.first, :frozen?)
      assert_predicate(bundle.trace_state.first.first, :frozen?)
      assert_same(bundle.trace_state, bundle.trace_state)
    end

    test "the string members are frozen without aliasing the caller's strings" do
      trace_id = +"a" * 32
      bundle = Bundle.build(
        trace_id: trace_id, span_id: +"b" * 16, flavour: W3C, trace_flags: +"01",
      )
      trace_id << "z"

      assert_equal("a" * 32, bundle.trace_id)
      assert_predicate(bundle.trace_id, :frozen?)
      assert_predicate(bundle.span_id, :frozen?)
      assert_predicate(bundle.trace_flags, :frozen?)
    end

    # testing/f36a19cd's round trip, over both hex flavours and the sentinel or a real id.
    test "Bundle.build(**bundle.to_h) == bundle for every generated bundle" do
      sample(count: 32, seed: 20_260_908) do |rng|
        flavour = rng.rand < 0.5 ? W3C : Flavour::DATADOG
        real = flavour == W3C ? "a" * 32 : "42"
        trace_id = rng.rand < 0.5 ? real : flavour.invalid_trace_id
        span_id = rng.rand < 0.5 ? "b" * 16 : Bundle::INVALID_SPAN_ID
        bundle = Bundle.build(
          trace_id: trace_id, span_id: span_id, flavour: flavour,
          trace_flags: rng.rand < 0.5 ? "00" : "01", remote: rng.rand < 0.5,
        )

        assert_equal(bundle, Bundle.build(**bundle.to_h))
        assert_equal(bundle.hash, Bundle.build(**bundle.to_h).hash)
      end
    end

    test "#with preserves member identity for members it is not handed" do
      bundle = Bundle.build(trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C)
      changed = bundle.with(remote: true)

      assert_same(bundle.span, changed.span)
      assert_same(bundle.tracer_factory, changed.tracer_factory)
      assert_same(bundle.trace_id, changed.trace_id)
      assert_predicate(changed, :remote?)
      refute_predicate(bundle, :remote?)
    end

    # P1-4: #with routes through the validating .build on every supported Ruby, which is what lets
    # phase 5 populate through Bundle::NONE.with(...) and get the same validation as .build.
    test "#with re-validates through .build: NONE.with(trace_id: real) is refused by NONE" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Bundle::NONE.with(trace_id: "a" * 32)
      end

      assert_includes(error.message, ":none")
      populated = Bundle::NONE.with(trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C)

      assert_predicate(populated, :valid?)
      refute_predicate(Bundle::NONE, :valid?)
    end

    test "INVALID_SPAN_ID is OBS-26's 16 hex zeros, frozen, and the same across flavours" do
      assert_equal("0" * 16, Bundle::INVALID_SPAN_ID)
      assert_predicate(Bundle::INVALID_SPAN_ID, :frozen?)
      assert_equal(
        Bundle::INVALID_SPAN_ID,
        Bundle.build(trace_id: "42", span_id: "0" * 16, flavour: Flavour::DATADOG).span_id,
      )
    end

    test "the construction pattern: new is private and .build is the one way in" do
      refute_respond_to(Bundle, :new)
    end
  end
end
