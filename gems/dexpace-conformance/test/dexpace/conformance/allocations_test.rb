# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# OBS-25: "Selecting a no-op path MUST NOT allocate per call." The iteration count is a REQUIRED
# keyword with no default (8a's open question 5): a caller who forgets it gets an ArgumentError,
# not a number that means nothing. The shape is core's own two-loop, agree-twice measurement
# (gems/dexpace-core/test/support/allocation_delta.rb), whose comment anticipates this copy: on
# the 3.2.11 floor a one-time interpreter cost can land inside a single measured block and come
# back negative, which a single loop would integer-divide to -1. What makes the measurement
# caller-insensitive is passing arguments that cannot allocate -- a frozen constant, a Symbol, an
# Integer, nil -- because an inline literal at the call site allocates per iteration whether or
# not the callee does (5b's R8).
class DexpaceConformanceAllocationsTest < DexpaceTestCase
  Allocations = Dexpace::Conformance::Allocations

  test "delta measures the per-iteration allocation cost, warming up first" do
    calls = 0
    delta = Allocations.delta(iterations: 1000) { calls += 1 }

    assert_in_delta(0.0, delta, 0.0)
    assert_kind_of(Float, delta)
    assert_operator(calls, :>, 1000, "the warm-up and the second loop must have run too")
  end

  test "a no-op path over frozen arguments measures exactly zero" do
    span = Dexpace::Instrumentation::NO_SPAN
    key = "k"
    delta = Allocations.delta(iterations: 500) { span.set_attribute(key, 1) }

    assert_in_delta(0.0, delta, 0.0)
  end

  test "an allocating block reports a positive per-iteration delta, one object for one String" do
    delta = Allocations.delta(iterations: 200) { +"" }

    assert_in_delta(1.0, delta, 0.0)
  end

  test "iterations is a required keyword and must be a positive Integer" do
    assert_raises(::ArgumentError) { Allocations.delta { nil } }
    assert_raises(Dexpace::InvalidArgumentError) { Allocations.delta(iterations: 0) { nil } }
    assert_raises(Dexpace::InvalidArgumentError) { Allocations.delta(iterations: 1.5) { nil } }
  end

  test "the GC is re-enabled afterwards, even when the block raises" do
    assert_raises(RuntimeError) { Allocations.delta(iterations: 10) { raise "boom" } }

    refute(::GC.disable, "GC.disable returns false when it was enabled, so the helper restored it")
    ::GC.enable
  end
end
