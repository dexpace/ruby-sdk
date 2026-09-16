# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "probe_step"
require_relative "forking_probe"
require_relative "state_probe"
require_relative "inline_executor"
require_relative "fake_async_transport"

# The pipeline doubles, driven red first because they are load-bearing: verified fact 3's ==
# relation is what makes the PIPE-6 fixture discriminate, ForkingProbe's close discipline is
# PIPE-40's conformance fixture, and the executor's count is PIPE-33 clause 2's one assertion.
class PipelineDoublesTest < DexpaceTestCase
  # Verified fact 3, and the shape the design got wrong once in drafting: two probes over SEPARATE
  # logs are == only while both are empty, so the PIPE-6 pair shares one log object and stays ==
  # across execution. A pair built the other way stops being == the moment either runs, and the
  # collision then raises for the wrong reason.
  test "ProbeStep instances with equal tags over one shared log are == and not equal?" do
    log = []
    first = ProbeStep.new(tag: :retry, log: log)
    second = ProbeStep.new(tag: :retry, log: log)

    assert_equal(first, second)
    refute_same(first, second)

    log << %i[enter retry]

    assert_equal(first, second, "must remain == across shared log mutation (PIPE-6 fixture)")
  end

  test "ProbeStep instances over separate logs stop being == once one of them runs" do
    first = ProbeStep.new(tag: :retry, log: [])
    second = ProbeStep.new(tag: :retry, log: [])

    assert_equal(first, second)
    first.log << %i[enter retry]

    refute_equal(first, second, "the trap the shared-log fixture exists to avoid")
  end

  test "ProbeStep instances with distinct tags are not ==" do
    log = []

    refute_equal(ProbeStep.new(tag: :auth, log: log), ProbeStep.new(tag: :retry, log: log))
  end

  test "ProbeStep records entry and exit around the downstream call" do
    log = []
    cursor = Class.new { def call(request) = "res_#{request}" }.new

    assert_equal("res_req", ProbeStep.new(tag: :a, log: log).call("req", cursor))
    assert_equal([%i[enter a], %i[exit a]], log)
  end

  # R10: no probe declares #stage, so every install in this phase's suite names the stage as an
  # argument -- row 5 of the precedence table. A declaring probe would be rejected by row 3
  # wherever a test installs it somewhere other than the stage it hard-codes.
  test "no probe declares #stage" do
    refute_respond_to(ProbeStep.new(tag: :a, log: []), :stage)
    refute_respond_to(ForkingProbe.new, :stage)
    refute_respond_to(StateProbe.new(stage_to_read: Dexpace::Pipeline::Stages::REDIRECT), :stage)
  end

  test "every probe conforms to the two-argument step protocol" do
    assert(Dexpace::Pipeline::Step.conforms?(ProbeStep.new(tag: :a, log: [])))
    assert(Dexpace::Pipeline::Step.conforms?(ForkingProbe.new))
    state_probe = StateProbe.new(stage_to_read: Dexpace::Pipeline::Stages::REDIRECT)

    assert(Dexpace::Pipeline::Step.conforms?(state_probe))
  end

  # Phase 2's InlineExecutor, extended compatibly with a count: PIPE-33 clause 2's "single opaque
  # unit" is assert_equal(1, executor.posts) for a five-step pipeline, and phase 2's suites, which
  # never read the count, are unchanged.
  test "InlineExecutor counts post invocations and runs the block inline" do
    executor = InlineExecutor.new

    assert_equal(0, executor.posts)

    run = false
    executor.post { run = true }

    assert_equal(1, executor.posts)
    assert(run)
  end

  # Phase 2's fake, reused: it settles synchronously unless settle_later: is given, and exposes
  # the Completer so a test can drive the settlement race deliberately.
  test "FakeAsyncTransport delivers a settled Future, and a deferred one it settles on demand" do
    transport = FakeAsyncTransport.new(response: "ok")
    future = transport.call(:request, :options, nil)

    assert_instance_of(Dexpace::Async::Future, future)
    assert_equal("ok", future.value)
    assert_equal([[:request, :options, nil]], transport.calls)

    deferred = FakeAsyncTransport.new(response: "later", settle_later: true)
    future = deferred.call(:request, :options, nil)

    refute_predicate(future, :settled?)
    deferred.settle

    assert_equal("later", future.value)
  end
end
