# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/retry_fixtures"
require_relative "../../support/scripted_transport"
require_relative "../../support/scripted_async_transport"
require_relative "../../support/fake_config_source"

# Exercises: RETRY-14, RETRY-13, RECOV-30, RETRY-12, P6-6
#
# The convergence point inside 6a (the charter's second): the three drivers -- the recovery
# engine and the two stage steps -- built from ONE RetrySettings, driven against an identical
# failure sequence, exhaust after the SAME number of wire sends. Under the shared defaults that
# number is three: the stage stack's max-retries (2) plus one initial send, which is the
# recovery stack's max-attempts (3), an identity and not a coincidence (P6-6). No lib/ mirror:
# this file asserts an equivalence between three files rather than one file's contract.
class DexpaceResilienceBudgetEquivalenceTest < DexpaceTestCase
  include RetryFixtures

  def setup
    super
    Dexpace.configure { |c| c.env_source = FakeConfigSource.new }
  end

  def teardown
    Dexpace.reset_config!
    super
  end

  def recovery_sends(settings, failures)
    transport = ScriptedTransport.new(failures)
    engine = Dexpace::Resilience::RecoveryRetry.build(transport: transport, settings: settings)
    assert_raises(Dexpace::ProtocolError) do
      engine.call(retry_request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
    end
    transport.calls.size
  end

  def stage_sends(settings, failures)
    transport = ScriptedTransport.new(failures)
    step = Dexpace::Resilience::RetryStep.build(settings: settings)
    response = Dexpace::Pipeline::Builder.new(transport: transport).append(step).build
      .call(retry_request)

    assert_equal(503, response.status.code)
    transport.calls.size
  end

  def async_stage_sends(settings, failures)
    transport = ScriptedAsyncTransport.new(failures)
    step = Dexpace::Resilience::AsyncRetryStep.build(settings: settings)
    future = Dexpace::Pipeline::Builder.new(transport: transport).append(step).build_async
      .call(retry_request)

    assert_equal(503, future.value.status.code)
    transport.calls.size
  end

  def unavailable(count) = Array.new(count) { retry_response(503) }

  test "RETRY-14: under the shared defaults all three drivers exhaust after exactly three sends" do
    settings = Dexpace::Resilience::RetrySettings.build(initial_delay: 0.0, jitter: 0.0,
                                                        clock: FakeClock.new,)

    assert_equal(2, settings.max_retries, "RETRY-12's default, the stage vocabulary")
    recovery = recovery_sends(settings, unavailable(6))
    stage = stage_sends(settings, unavailable(6))
    async = async_stage_sends(settings, unavailable(6))

    assert_equal(3, recovery, "max-attempts 3: max_retries + the initial send")
    assert_equal(3, stage, "max-retries 2 + the initial send")
    assert_equal(3, async)
    assert_equal(recovery, stage)
    assert_equal(stage, async)
  end

  test "RETRY-14 / P6-6: the equivalence holds for any configured value, as an identity" do
    [0, 1, 4].each do |retries|
      settings = Dexpace::Resilience::RetrySettings.build(initial_delay: 0.0, jitter: 0.0,
                                                          max_retries: retries,
                                                          clock: FakeClock.new,)
      sends = retries + 1

      assert_equal(sends, recovery_sends(settings, unavailable(sends + 2)), "recovery, #{retries}")
      assert_equal(sends, stage_sends(settings, unavailable(sends + 2)), "stage, #{retries}")
      assert_equal(sends, async_stage_sends(settings, unavailable(sends + 2)), "async, #{retries}")
    end
  end

  test "RETRY-14 / RETRY-12: the configured MAX_RETRY_ATTEMPTS reaches all three stacks alike" do
    Dexpace.configure do |c|
      c.env_source = FakeConfigSource.new(Dexpace::Configuration::Keys::MAX_RETRY_ATTEMPTS => "3")
    end
    settings = Dexpace::Resilience::RetrySettings.build(initial_delay: 0.0, jitter: 0.0,
                                                        clock: FakeClock.new,)

    assert_equal(3, settings.max_retries)
    assert_equal(4, recovery_sends(settings, unavailable(8)))
    assert_equal(4, stage_sends(settings, unavailable(8)))
    assert_equal(4, async_stage_sends(settings, unavailable(8)))
  end

  test "RETRY-13 / RECOV-30: the two clock-driven stacks wait on ONE schedule from one settings" do
    # The async driver waits through Async.delay and never the clock: with no scheduler a
    # positive delay fails its future (R2), so its row in this file is the send count above and
    # its schedule is the same RetryStepHelpers#resolve_delay the sync step's suite pins.
    clocks = Array.new(2) { FakeClock.new }
    settings = Dexpace::Resilience::RetrySettings.build(initial_delay: 0.3, multiplier: 3.0,
                                                        max_delay: 5.0, jitter: 0.0,
                                                        max_retries: 3, clock: clocks[0],)
    recovery_sends(settings, unavailable(6))
    stage_sends(settings.with(clock: clocks[1]), unavailable(6))
    schedules = clocks.map { |clock| clock.sleeps.map { _1[:duration] } }

    assert_equal(3, schedules[0].size)
    [0.3, 0.9, 2.7].zip(schedules[0]).each do |(expected, actual)|
      assert_in_delta(expected, actual)
    end
    assert_equal(schedules[0], schedules[1], "one calculator, two stacks, one schedule")
  end
end
