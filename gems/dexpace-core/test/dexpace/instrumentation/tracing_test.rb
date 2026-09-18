# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/allocation_delta"
require_relative "../../support/fiber_storage_facts"
require_relative "../../support/recording_span"
require "dexpace"

# OBS-22, OBS-23, OBS-25, OBS-26, OBS-30: the current-span carrier, activation with its scope
# handle (block form first, P5-45), log correlation over 5b's two keys (R12), the identity test
# that returns NO_SCOPE (P5-47), and the non-wrapping of a raise (boundary 2). Every nesting
# assertion uses two DISTINCT RecordingSpans by identity, because a test over one span passes
# under an implementation that never restores anything.
#
# Split into nested classes under Metrics/ClassLength: activation, correlation, no-op path.
class DexpaceInstrumentationTracingTest < DexpaceTestCase
  include FiberStorageFacts

  Tracing = Dexpace::Instrumentation::Tracing
  Bundle = Dexpace::Instrumentation::Bundle
  NO_SPAN = Dexpace::Instrumentation::NO_SPAN
  NO_SCOPE = Dexpace::Instrumentation::NO_SCOPE
  TRACE_ID = Dexpace::Instrumentation::Diagnostics::TRACE_ID
  SPAN_ID = Dexpace::Instrumentation::Diagnostics::SPAN_ID
  CURRENT_SPAN = :"dexpace.current_span"
  TRACED = Bundle.build(
    trace_id: "4bf92f3577b34da6a3ce929d0e0e4736", span_id: "00f067aa0ba902b7",
    trace_flags: "01", flavour: Dexpace::Instrumentation::TraceIdFlavour::W3C,
  )

  # testing/4ef070df: restore both diagnostic slots and the current-span slot unconditionally,
  # including on failure, or a later test in the same fiber inherits them. A module, because
  # the nested classes below subclass DexpaceTestCase and not this class.
  module SlotReset
    def teardown
      ::Fiber[CURRENT_SPAN] = nil
      ::Fiber[TRACE_ID] = nil
      ::Fiber[SPAN_ID] = nil
      super
    end
  end
  include SlotReset

  test "OBS-22: .current_span is NO_SPAN when nothing is active -- never nil" do
    assert_same(NO_SPAN, Tracing.current_span)
  end

  test "OBS-22: nested activations with distinct spans restore the outer, then the initial" do
    outer = Dexpace::RecordingSpan.new
    inner = Dexpace::RecordingSpan.new

    Tracing.with_span(outer) do |yielded_outer|
      assert_same(outer, yielded_outer)
      assert_same(outer, Tracing.current_span)

      Tracing.with_span(inner) do |yielded_inner|
        assert_same(inner, yielded_inner)
        assert_same(inner, Tracing.current_span)
      end

      assert_same(outer, Tracing.current_span)
    end

    assert_same(NO_SPAN, Tracing.current_span)
  end

  # OBS-22's throw clause, asserted on the SLOT after the raise -- assert_raises alone proves
  # nothing about restoration -- and OBS-30's non-wrapping: the raise reaches the caller.
  test "OBS-22, OBS-30: a raise inside with_span propagates and the prior span is restored" do
    outer = Dexpace::RecordingSpan.new
    inner = Dexpace::RecordingSpan.new

    Tracing.with_span(outer) do
      error = assert_raises(::RuntimeError) { Tracing.with_span(inner) { raise "boom" } }

      assert_equal("boom", error.message)
      assert_same(outer, Tracing.current_span)
    end

    assert_same(NO_SPAN, Tracing.current_span)
  end

  test "OBS-22: with_span returns the block's value" do
    assert_equal(:value, Tracing.with_span(Dexpace::RecordingSpan.new) { :value })
  end

  # OBS-22's literal requirement: "return a scope handle", nested by hand and closed by hand,
  # which is the non-lexical form 5b's AsyncStep needs (P5-45).
  test "OBS-22: .activate returns a handle whose #close restores, nested by hand" do
    outer = Dexpace::RecordingSpan.new
    inner = Dexpace::RecordingSpan.new
    outer_scope = Tracing.activate(outer)
    inner_scope = Tracing.activate(inner)

    assert_same(inner, Tracing.current_span)
    assert_instance_of(Dexpace::Instrumentation::Scope, outer_scope)
    refute_same(NO_SCOPE, inner_scope)

    inner_scope.close

    assert_same(outer, Tracing.current_span)

    outer_scope.close

    assert_same(NO_SPAN, Tracing.current_span)
  end

  # OBS-23 over 5b's two keys, and OBS-26's guard.
  class CorrelationTest < DexpaceTestCase
    include FiberStorageFacts
    include SlotReset

    test "OBS-23: correlate pushes trace.id and span.id for the scope and removes them after" do
      span = Dexpace::RecordingSpan.new

      assert_diagnostic_key_unset(TRACE_ID)
      assert_diagnostic_key_unset(SPAN_ID)

      Tracing.with_correlated_span(span, TRACED) do
        assert_same(span, Tracing.current_span)
        assert_equal("4bf92f3577b34da6a3ce929d0e0e4736", ::Fiber[TRACE_ID])
        assert_equal("00f067aa0ba902b7", ::Fiber[SPAN_ID])
      end

      assert_same(NO_SPAN, Tracing.current_span)
      # "restore each key to its prior value (or remove it if previously unset)": the removal
      # half, which assert_nil cannot see -- Fiber[k] is nil whether the key is absent or
      # present-with-nil -- so the storage map is what is asserted (floor-aware, P5-72).
      assert_diagnostic_key_removed(TRACE_ID)
      assert_diagnostic_key_removed(SPAN_ID)
    end

    test "OBS-23: correlate restores a previously-set key to its prior value" do
      ::Fiber[TRACE_ID] = "prior-trace"
      ::Fiber[SPAN_ID] = "prior-span"

      Tracing.with_correlated_span(Dexpace::RecordingSpan.new, TRACED) do
        assert_equal("4bf92f3577b34da6a3ce929d0e0e4736", ::Fiber[TRACE_ID])
      end

      assert_equal("prior-trace", ::Fiber[TRACE_ID])
      assert_equal("prior-span", ::Fiber[SPAN_ID])
    end

    test "OBS-23, OBS-30: a raise inside with_correlated_span propagates and restores all three" do
      outer = Dexpace::RecordingSpan.new
      ::Fiber[TRACE_ID] = "prior-trace"

      Tracing.with_span(outer) do
        assert_raises(::RuntimeError) do
          Tracing.with_correlated_span(Dexpace::RecordingSpan.new, TRACED) { raise "boom" }
        end

        assert_same(outer, Tracing.current_span)
        assert_equal("prior-trace", ::Fiber[TRACE_ID])
        assert_diagnostic_key_unset(SPAN_ID)
      end
    end

    # The negative needs the positive beside it: a non-recording RecordingSpan, NOT NO_SPAN --
    # with NO_SPAN the slot already holds it, the identity test returns NO_SCOPE, and the test
    # passes against an implementation that does nothing at all. "Delegates to plain
    # current-span activation" is the assertion.
    test "OBS-23: a non-recording span skips the push and still becomes the current span" do
      quiet = Dexpace::RecordingSpan.new(recording: false)

      Tracing.with_correlated_span(quiet, TRACED) do
        assert_same(quiet, Tracing.current_span)
        assert_diagnostic_key_unset(TRACE_ID)
        assert_diagnostic_key_unset(SPAN_ID)
      end

      assert_same(NO_SPAN, Tracing.current_span)
    end

    # The only state 5b's step can reach in phase 5: a real tracer_factory: makes the span
    # recording while the bundle a step can see is always Bundle::NONE (R11). Pushing NONE's
    # sentinels would publish trace.id=<32 zeros> on every log line -- a fake trace, which OBS-26
    # requires be treated as no-trace and which is worse than an absent key.
    test "OBS-26: a recording span with an invalid bundle activates but pushes no key" do
      span = Dexpace::RecordingSpan.new

      Tracing.with_correlated_span(span, Bundle::NONE) do
        assert_same(span, Tracing.current_span)
        assert_diagnostic_key_unset(TRACE_ID)
        assert_diagnostic_key_unset(SPAN_ID)
      end

      assert_same(NO_SPAN, Tracing.current_span)
    end

    test "OBS-23: the correlating handle restores span and keys by hand, in nested order" do
      first = TRACED.with(span_id: "1111111111111111")
      second = TRACED.with(span_id: "2222222222222222")
      outer = Tracing.correlate(Dexpace::RecordingSpan.new, first)
      inner = Tracing.correlate(Dexpace::RecordingSpan.new, second)

      assert_equal("2222222222222222", ::Fiber[SPAN_ID])

      inner.close

      assert_equal("1111111111111111", ::Fiber[SPAN_ID])
      assert_equal(TRACED.trace_id, ::Fiber[TRACE_ID])

      outer.close

      assert_diagnostic_key_removed(SPAN_ID)
      assert_same(NO_SPAN, Tracing.current_span)
    end
  end

  # OBS-25's cached-singleton scope on the identity test (P5-47), and the allocation-free
  # untraced path.
  class NoOpPathTest < DexpaceTestCase
    include AllocationDelta
    include SlotReset

    test "OBS-25, P5-47: activating the span that is already current returns NO_SCOPE" do
      span = Dexpace::RecordingSpan.new

      Tracing.with_span(span) do
        assert_same(NO_SCOPE, Tracing.activate(span))
        assert_same(span, Tracing.current_span)
        assert_same(NO_SCOPE, Tracing.correlate(span, Bundle::NONE))
      end
      assert_same(NO_SCOPE, Tracing.activate(NO_SPAN), "NO_SPAN on an empty slot owes nothing")
      assert_same(NO_SCOPE, Tracing.correlate(NO_SPAN, TRACED), "non-recording, nothing owed")
    end

    # A non-recording span over a RECORDING one still owes the restore, so the identity test
    # and not the recording flag is what decides (P5-47): the flag reading would leave the
    # recording span un-restored, OBS-22's exact failure.
    test "P5-47: a non-recording span activated over a recording one owes a real restore" do
      recording = Dexpace::RecordingSpan.new
      quiet = Dexpace::RecordingSpan.new(recording: false)

      Tracing.with_span(recording) do
        scope = Tracing.correlate(quiet, TRACED)

        refute_same(NO_SCOPE, scope)
        assert_same(quiet, Tracing.current_span)

        scope.close

        assert_same(recording, Tracing.current_span)
      end
    end

    test "OBS-25: correlate returns NO_SCOPE when the span and both keys are already in place" do
      span = Dexpace::RecordingSpan.new
      scope = Tracing.correlate(span, TRACED)

      assert_same(NO_SCOPE, Tracing.correlate(span, TRACED))
      assert_same(NO_SCOPE, Tracing.activate(span))

      scope.close
    end

    # OBS-25's conformance clause: "with no tracer installed, start/end spans in a loop and
    # assert the same singletons and no per-iteration allocation". The untraced application's
    # every activation is of NO_SPAN over a slot holding NO_SPAN.
    test "OBS-25: the untraced activation path allocates nothing per call" do
      tracer = Dexpace::Instrumentation::NO_TRACER_FACTORY.tracer("op")
      per_call = allocations_per_call do
        span = tracer.start_span("op")
        Tracing.with_span(span) { Tracing.current_span }
        Tracing.with_correlated_span(span, Bundle::NONE) { nil }
        Tracing.activate(span).close
        span.finish
      end

      assert_in_delta(0.0, per_call, 0.0, "the untraced activation path allocates per call")
    end

    # The carrier is Fiber[] and not Thread.current[] (boundary 14): a span activated before a
    # thread, a fiber or an enumerator is created is current inside each.
    test "OBS-23: the current span is inherited by a child thread, fiber and enumerator" do
      span = Dexpace::RecordingSpan.new

      Tracing.with_correlated_span(span, TRACED) do
        seen = [
          ::Thread.new { [Tracing.current_span, ::Fiber[TRACE_ID]] }.value,
          ::Fiber.new { [Tracing.current_span, ::Fiber[TRACE_ID]] }.resume,
          ::Enumerator.new { |y| y << [Tracing.current_span, ::Fiber[TRACE_ID]] }.next,
        ]

        seen.each do |current, trace_id|
          assert_same(span, current)
          assert_equal(TRACED.trace_id, trace_id)
        end
      end
    end
  end
end
