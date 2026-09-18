# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/allocation_delta"
require_relative "../../support/recording_span"
require "dexpace"

# CTX-14's "an active span" slot and CTX-15's "a no-op span": one shared, frozen object, so
# OBS-25's "MUST NOT allocate per call" is assertable by reference identity (phase 4 fixed the
# object's identity; phase 5c gave its class OBS-21's protocol, Task 3). OBS-21's recording branch
# is asserted against RecordingSpan, because core ships no recording span (P5-48).
class DexpaceInstrumentationNoSpanTest < DexpaceTestCase
  NO_SPAN = Dexpace::Instrumentation::NO_SPAN
  FROZEN_ATTRS = { "tier" => "l1" }.freeze
  SPAN_PROTOCOL = %i[recording? set_attribute add_event record_error status= finish context].freeze

  test "NO_SPAN is a single frozen instance" do
    assert_predicate(NO_SPAN, :frozen?)
    assert_same(NO_SPAN, Dexpace::Instrumentation::NO_SPAN)
  end

  # The object is public by identity; its class is a private_constant, so phase 5c widened it
  # without an NFR-4 diff and nothing can build a second one.
  test "NO_SPAN's class is a private_constant, reachable by no qualified name" do
    refute_includes(Dexpace::Instrumentation.constants(false), :NoSpan)
    assert_raises(::NameError) { Dexpace::Instrumentation::NoSpan }
  end

  # Phase 4 fixed the slot and phase 5c the protocol: exactly OBS-21's seven methods, and the
  # RBS interface _Span declares the same seven.
  test "NO_SPAN's class defines exactly OBS-21's seven methods" do
    assert_equal(SPAN_PROTOCOL.sort, NO_SPAN.class.public_instance_methods(false).sort)
  end

  # OBS-21 on the shipped no-op, OBS-25's identity, and P5-42's signatures.
  class ProtocolTest < DexpaceTestCase
    include AllocationDelta

    test "OBS-21: NO_SPAN is non-recording and every mutator is inert and returns self" do
      refute_predicate(NO_SPAN, :recording?)
      assert_same(NO_SPAN, NO_SPAN.set_attribute("http.status_code", 200))
      assert_same(NO_SPAN, NO_SPAN.add_event("cache_hit"))
      assert_same(NO_SPAN, NO_SPAN.add_event("cache_hit", attributes: FROZEN_ATTRS))
      assert_same(NO_SPAN, NO_SPAN.record_error(::StandardError.new("boom")))
      assert_same(NO_SPAN, NO_SPAN.record_error(::StandardError.new("x"), attributes: FROZEN_ATTRS))
    end

    # `span.status = :ok` as an expression evaluates to its right-hand side whatever the method
    # returns, so the assignment form asserts nothing; public_send reaches the return value.
    # #status is not readable back, which is the inertness.
    test "OBS-21: #status= returns its argument and drops it; #finish is a nil no-op, twice" do
      assert_equal(:ok, NO_SPAN.public_send(:status=, :ok))
      refute_respond_to(NO_SPAN, :status)
      assert_nil(NO_SPAN.finish)
      assert_nil(NO_SPAN.finish(end_timestamp: ::Time.now))
      assert_nil(NO_SPAN.finish)
    end

    test "OBS-25, CTX-15: NO_SPAN's context is Bundle::NONE by identity" do
      assert_same(Dexpace::Instrumentation::Bundle::NONE, NO_SPAN.context)
      assert_same(NO_SPAN, NO_SPAN.context.span)
    end

    test "P5-42: every attributes parameter is a named optional keyword, never a ** splat" do
      %i[add_event record_error].each do |name|
        params = NO_SPAN.method(name).parameters

        refute_includes(params.map(&:first), :keyrest, "#{name} takes a ** splat")
        assert_includes(params, %i[key attributes], "#{name} names attributes:")
      end
      assert_equal([%i[key end_timestamp]], NO_SPAN.method(:finish).parameters)
      assert_equal([%i[req key], %i[req value]], NO_SPAN.method(:set_attribute).parameters)
    end

    # OBS-25's "Selecting a no-op path MUST NOT allocate per call", as the two-loop delta over
    # the whole protocol with arguments that cannot allocate -- frozen constants, a Symbol, an
    # Integer -- which is what makes the assertion insensitive to the caller (5b's R8;
    # support/allocation_delta.rb). The magic comment is a repository rule, not a precondition.
    test "OBS-25: the whole no-op span protocol allocates nothing per call" do
      error = ::StandardError.new("boom").freeze
      per_call = allocations_per_call do
        NO_SPAN.recording?
        NO_SPAN.set_attribute("k", 1)
        NO_SPAN.add_event("e", attributes: FROZEN_ATTRS)
        NO_SPAN.record_error(error, attributes: FROZEN_ATTRS)
        NO_SPAN.status = :ok
        NO_SPAN.finish
        NO_SPAN.context
      end

      assert_in_delta(0.0, per_call, 0.0, "the no-op span path allocates per call")
    end
  end

  # OBS-21's recording branch, on the fake core does not ship (P5-48).
  class RecordingBranchTest < DexpaceTestCase
    test "OBS-21: a recording span keeps what a mutator is handed" do
      span = Dexpace::RecordingSpan.new
      error = ::StandardError.new("fail")

      assert_predicate(span, :recording?)
      assert_same(span, span.set_attribute("key", "val"))
      assert_equal({ "key" => "val" }, span.attributes)
      assert_same(span, span.add_event("retry", attributes: FROZEN_ATTRS))
      assert_equal([{ name: "retry", attributes: FROZEN_ATTRS }], span.events)
      assert_same(span, span.record_error(error))
      assert_same(error, span.errors.first[:error])
      assert_equal(:error, span.public_send(:status=, :error))
      assert_equal(:error, span.status)
    end

    # "call end() twice and assert no duplicate export": one entry in finished_at, carrying the
    # first call's timestamp. Unassertable against NO_SPAN, which exports nothing either way.
    test "OBS-21: #finish is idempotent -- a second call exports nothing" do
      span = Dexpace::RecordingSpan.new
      first = ::Time.utc(2026, 9, 17, 12, 0, 0)
      second = ::Time.utc(2026, 9, 17, 12, 0, 5)

      assert_nil(span.finish(end_timestamp: first))
      assert_nil(span.finish(end_timestamp: second))
      assert_equal([first], span.finished_at)
    end

    test "OBS-21: a non-recording fake is as inert as NO_SPAN, and finish on it is a no-op" do
      quiet = Dexpace::RecordingSpan.new(recording: false)

      refute_predicate(quiet, :recording?)
      assert_same(quiet, quiet.set_attribute("k", "v"))
      assert_empty(quiet.attributes)
      assert_nil(quiet.finish)
      assert_empty(quiet.finished_at)
    end
  end
end
