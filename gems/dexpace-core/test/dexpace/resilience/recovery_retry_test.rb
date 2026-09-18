# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/retry_fixtures"
require_relative "../../support/scripted_transport"
require_relative "../../support/recording_http_tracer"
require_relative "../../support/recording_sink"

# Exercises: RECOV-16, RECOV-17, RECOV-18, RECOV-19, RECOV-20, RECOV-21, RECOV-22, RECOV-23,
# RECOV-24, RECOV-26, RECOV-27, RECOV-28, RECOV-29, RECOV-30, RECOV-34, RETRY-4, RETRY-13,
# RETRY-14, RETRY-23, RETRY-25, RETRY-27, RETRY-34, RETRY-35, RETRY-36, RETRY-37, RETRY-41,
# RETRY-42, RETRY-44, OBS-29, CFG-16, SEAM-11, P6-3, P6-6, P6-8, P6-9
#
# The recovery-stack engine, driven directly as the Dexpace::Transport it is and, where the
# integration is the point, beneath a real Recovery::Orchestrator with a real
# ErrorMappingStep. Every wait is a FakeClock's, whose monotonic reading advances by exactly the
# slept duration, so the total-timeout arithmetic is exact rather than wall-clock-dependent.
# Split into nested classes under Metrics/ClassLength.
class DexpaceResilienceRecoveryRetryTest < DexpaceTestCase
  RecoveryRetry = Dexpace::Resilience::RecoveryRetry

  # The engine over a script, and the one call every test makes.
  module Fixtures
    include RetryFixtures

    def engine(script, settings: retry_settings, **keywords)
      transport = ScriptedTransport.new(script)
      [RecoveryRetry.build(transport: transport, settings: settings, **keywords), transport]
    end

    def send_through(built, request: retry_request, cancellation: Dexpace::Cancellation.none)
      built.call(request, Dexpace::RequestOptions::EMPTY, cancellation)
    end
  end
  include Fixtures

  test "SEAM-11 / P6-3: the engine is a Dexpace::Transport by the duck type, frozen, .new hidden" do
    built, = engine([retry_response(200)])

    assert(Dexpace::Transport.conforms?(built))
    assert(Dexpace::Registry.callable?(built, arity: 3))
    assert_predicate(built, :frozen?)
    refute_respond_to(RecoveryRetry, :new)
  end

  test "the constructor validates every keyword" do
    assert_raises(Dexpace::InvalidArgumentError) { RecoveryRetry.build(transport: :none) }
    assert_raises(Dexpace::InvalidArgumentError) do
      RecoveryRetry.build(transport: ->(_r, _o) {})
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      RecoveryRetry.build(transport: ScriptedTransport.new([]), settings: :defaults)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      RecoveryRetry.build(transport: ScriptedTransport.new([]), http_tracer_factory: :none)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      RecoveryRetry.build(transport: ScriptedTransport.new([]), logger: RecordingSink.new)
    end
  end

  test "RECOV-28: a success on the first attempt touches no clock and returns the response as is" do
    clock = FakeClock.new
    built, transport = engine([retry_response(200)], settings: retry_settings(clock: clock))
    response = send_through(built)

    assert_equal(200, response.status.code)
    assert_empty(clock.sleeps)
    assert_equal(1, transport.calls.size)
    refute_predicate(response.body, :closed?)
  end

  test "RECOV-19 / RETRY-36 / RETRY-44: 503, 503, 200 ends on the 200, re-sending ONE request" do
    built, transport = engine([retry_response(503), retry_response(503), retry_response(200)])
    request = retry_request
    response = send_through(built, request: request)

    assert_equal(200, response.status.code)
    assert_equal(3, transport.calls.size)
    transport.calls.each { |(sent, _options, _token)| assert_same(request, sent) }
  end

  test "RETRY-42 / RECOV-28: eight concurrent calls through one engine keep their budgets apart" do
    built, transport = engine(Array.new(16) { |i| retry_response(i.even? ? 503 : 200) },
                              settings: retry_settings(max_retries: 1),)
    results = Array.new(8) { ::Thread.new { send_through(built).status.code } }.map(&:value)

    assert_equal(16, transport.calls.size)
    assert_equal(8, results.count(200), results.inspect)
  end

  # RECOV-17, RECOV-18, RETRY-4, RETRY-25, RETRY-37: the two axes, on this stack.
  class ClassificationTest < DexpaceTestCase
    include Fixtures

    test "RECOV-17 / RETRY-4 / P6-8: a THROWN retryable failure is retried, not propagated" do
      built, transport = engine([RetryableError.new("reset"), RetryableError.new("reset"),
                                 retry_response(200),])
      response = send_through(built)

      assert_equal(200, response.status.code)
      assert_equal(3, transport.calls.size, "three sends, not one raise")
    end

    test "RECOV-17: a thrown failure with no capability is surfaced on the first attempt" do
      built, transport = engine([::ArgumentError.new("bug"), retry_response(200)])

      error = assert_raises(::ArgumentError) { send_through(built) }

      assert_equal("bug", error.message)
      assert_empty(Dexpace.suppressed(error))
      assert_equal(1, transport.calls.size)
    end

    test "RECOV-17 / RETRY-37: the configured set is authoritative -- wider, and narrower" do
      built, transport = engine([retry_response(418), retry_response(200)],
                                settings: retry_settings(retryable_statuses: [418]),)

      assert_equal(200, send_through(built).status.code)
      assert_equal(2, transport.calls.size, "418 is outside the baked set and still retried")
      built, transport = engine([retry_response(503), retry_response(200)],
                                settings: retry_settings(retryable_statuses: [429]),)

      assert_equal(503, send_through(built).status.code, "503 is baked-retryable and refused")
      assert_equal(1, transport.calls.size)
    end

    test "RECOV-19: a NON-retryable error status passes through as Success -- returned, buffered" do
      built, transport = engine([retry_response(404)])
      response = send_through(built)

      assert_equal(404, response.status.code)
      assert_equal(1, transport.calls.size)
      assert_kind_of(Dexpace::BufferBody, response.body, "buffered per RECOV-16")
      assert_equal("body 404", response.body_string)
    end

    test "RECOV-18 / RETRY-5 / RETRY-7: a bare POST is sent exactly once and its 503 returned" do
      built, transport = engine([retry_response(503), retry_response(200)],
                                settings: retry_settings(max_retries: 5),)
      response = send_through(built, request: retry_request(method: "POST"))

      assert_equal(503, response.status.code)
      assert_equal(1, transport.calls.size)
    end

    test "RECOV-18: a replayable body is re-sent and a consumed body is not" do
      built, transport = engine([retry_response(503), retry_response(200)])
      response = send_through(built, request: retry_request(method: "POST", body: replayable_body))

      assert_equal(200, response.status.code)
      assert_equal(2, transport.calls.size)
      built, transport = engine([RetryableError.new("reset"), retry_response(200)])

      assert_raises(RetryableError) do
        send_through(built, request: retry_request(method: "PUT", body: consumed_body))
      end
      assert_equal(1, transport.calls.size)
    end

    test "RETRY-25: a fatal-family error answering the capability is still never retried" do
      built, transport = engine([RetryableFatal.new("oom, lying"), retry_response(200)],
                                settings: retry_settings(max_retries: 3),)

      assert_raises(RetryableFatal) { send_through(built) }
      assert_equal(1, transport.calls.size)
    end

    test "RETRY-25: a fatal-family error propagates at the throw site, unclassified, unattached" do
      tracer = Dexpace::RecordingHTTPTracer.new
      built, transport = engine([::NoMemoryError.new("oom"), retry_response(200)],
                                http_tracer_factory: ->(_request) { tracer },)

      error = assert_raises(::NoMemoryError) { send_through(built) }

      assert_empty(Dexpace.suppressed(error))
      assert_equal(1, transport.calls.size)
      assert_equal(%i[attempt_started], tracer.events.map(&:first))
    end
  end

  # RECOV-20, RECOV-21, RECOV-22, RETRY-27, RETRY-34, P6-9: the budget and the terminal paths.
  class BudgetTest < DexpaceTestCase
    include Fixtures

    test "RECOV-20 / RETRY-34 / P6-9: exhausting the attempt cap RAISES, with the whole trail" do
      built, transport = engine(Array.new(3) { retry_response(503) },
                                settings: retry_settings(max_retries: 2),)

      error = assert_raises(Dexpace::ProtocolError) { send_through(built) }

      assert_equal(3, transport.calls.size, "max_retries 2 + 1 initial send (RETRY-14, P6-6)")
      assert_equal(503, error.status.code)
      assert_equal(2, Dexpace.suppressed(error).size)
      assert_equal([503, 503], Dexpace.suppressed(error).map { |prior| prior.status.code })
      assert_nil(error.cause, "pipeline/7ce4431d: the carried raise assigns no cause")
    end

    test "RETRY-34 / pipeline/7ce4431d: the carried raise assigns no cause in a caller's rescue" do
      built, = engine(Array.new(2) do
        retry_response(503)
      end, settings: retry_settings(max_retries: 1),)
      surfaced = nil
      begin
        raise ::IOError, "the caller's own in-flight exception"
      rescue ::IOError
        surfaced = assert_raises(Dexpace::ProtocolError) { send_through(built) }
      end

      assert_nil(surfaced.cause)
      assert_equal(1, Dexpace.suppressed(surfaced).size)
    end

    test "RETRY-34: a reused error instance trips no self-suppression on this stack either" do
      same = RetryableError.new("same")
      built, = engine([same, same, same], settings: retry_settings(max_retries: 2))

      surfaced = assert_raises(RetryableError) { send_through(built) }

      assert_same(same, surfaced)
      assert_empty(Dexpace.suppressed(surfaced))
    end

    test "RETRY-34: on eventual success the trail is discarded" do
      first = RetryableError.new("one")
      built, = engine([first, retry_response(200)])

      assert_equal(200, send_through(built).status.code)
      assert_empty(Dexpace.suppressed(first))
    end
  end

  # RECOV-20, RECOV-21, RECOV-22, RETRY-27: the total-timeout budget on a fake clock.
  class TotalTimeoutTest < DexpaceTestCase
    include Fixtures

    test "RECOV-20: a positive total_timeout aborts on `remaining`, at the attempt it names" do
      # remaining = total_timeout - elapsed, on a clock that advances by exactly each sleep:
      # 1.0 -> sleep 0.4 -> 0.6 -> sleep 0.4 -> 0.2, and 0.4 > 0.2 suppresses the third delay.
      clock = FakeClock.new
      settings = retry_settings(clock: clock, total_timeout: 1.0, initial_delay: 0.4,
                                max_delay: 0.4, max_retries: 10,)
      built, transport = engine(Array.new(11) { retry_response(503) }, settings: settings)

      error = assert_raises(Dexpace::ProtocolError) { send_through(built) }

      assert_equal(3, transport.calls.size, "exact, not merely under 11")
      assert_equal([0.4, 0.4], clock.sleeps.map { _1[:duration] }, "never over budget")
      assert_equal(2, Dexpace.suppressed(error).size)
    end

    test "RECOV-20: elapsed at or past the budget suppresses the next delay, delay or no delay" do
      clock = FakeClock.new
      settings = retry_settings(clock: clock, total_timeout: 1.0, initial_delay: 0.0,
                                max_retries: 10,)
      slow = lambda { |*|
        clock.advance(0.5)
        retry_response(503)
      }
      built, transport = engine([slow, slow, slow], settings: settings)

      assert_raises(Dexpace::ProtocolError) { send_through(built) }
      assert_equal(2, transport.calls.size, "1.0 elapsed after the second send: remaining 0.0")
    end

    test "RECOV-20 / RETRY-27: a zero total_timeout is unbounded -- only the cap stops the loop" do
      clock = FakeClock.new
      settings = retry_settings(clock: clock, total_timeout: 0, initial_delay: 100.0,
                                max_delay: 100.0, max_retries: 4,)
      built, transport = engine(Array.new(5) { retry_response(503) }, settings: settings)

      assert_raises(Dexpace::ProtocolError) { send_through(built) }
      assert_equal(5, transport.calls.size)
      assert_equal([100.0] * 4, clock.sleeps.map { _1[:duration] })
    end

    test "RECOV-22 / RETRY-20: a pacing hint replaces the schedule and is still budget-clamped" do
      clock = FakeClock.new
      settings = retry_settings(clock: clock, total_timeout: 5.0, initial_delay: 30.0,
                                max_delay: 30.0, max_retries: 5,)
      built, transport = engine([retry_response(503, headers: { "Retry-After" => "2" }),
                                 retry_response(503, headers: { "Retry-After" => "9" }),
                                 retry_response(200),], settings: settings,)

      assert_raises(Dexpace::ProtocolError) { send_through(built) }
      assert_equal([2.0], clock.sleeps.map { _1[:duration] }, "2 honoured; 9 > 3 remaining")
      assert_equal(2, transport.calls.size)
    end

    test "RECOV-24 / RECOV-29: the fixed precedence, and a malformed hint falls back to backoff" do
      clock = FakeClock.new
      built, = engine([retry_response(503, headers: { "Retry-After" => "garbage",
                                                      "retry-after-ms" => "1500", },),
                       retry_response(503, headers: { "Retry-After" => "junk" }),
                       retry_response(200),], settings: retry_settings(clock: clock),)

      send_through(built)

      durations = clock.sleeps.map { |sleep| sleep[:duration] }

      assert_equal([1.5, 0.2], durations, "the hint, then attempt 2's backoff")
    end

    test "RECOV-21 / RETRY-13: the schedule is Policy's own, on the settings clock" do
      clock = FakeClock.new
      settings = retry_settings(clock: clock, max_retries: 3)
      built, = engine(Array.new(3) { retry_response(503) } << retry_response(200),
                      settings: settings,)

      send_through(built)
      expected = (1..3).map do |attempt|
        Dexpace::Resilience::Policy.backoff_delay(attempt, **settings.backoff_arguments)
      end

      assert_equal(expected, clock.sleeps.map { _1[:duration] })
    end

    test "RETRY-41 / RECOV-34: zero retries is one send, and a valid settings never clamps" do
      # A negative max_retries cannot be built (RECOV-34 refuses it at construction), so
      # RETRY-41's clamp is unreachable on this stack through the public constructor; the
      # resolver is still the shared one and logs nothing for a valid value.
      sink = RecordingSink.new
      built, transport = engine(Array.new(4) { retry_response(503) },
                                settings: retry_settings(max_retries: 0),
                                logger: Dexpace::Instrumentation::Logger.build(sink: sink),)

      assert_raises(Dexpace::ProtocolError) { send_through(built) }
      assert_equal(1, transport.calls.size, "zero retries: one send")
      assert_empty(sink.entries)
    end
  end

  # RECOV-27, RETRY-23, RETRY-35, RECOV-16, OBS-29, the orchestrator integration.
  class IntegrationTest < DexpaceTestCase
    include Fixtures

    test "RECOV-27 / RETRY-23: cancellation during the wait aborts the loop as CancelledError" do
      source = Dexpace::Cancellation.source
      script = [lambda { |*|
        source.cancel(:test)
        retry_response(503)
      }, retry_response(200),]
      built, transport = engine(script, settings: retry_settings(initial_delay: 5.0))

      error = assert_raises(Dexpace::CancelledError) do
        send_through(built, cancellation: source.token)
      end

      assert_equal(1, transport.calls.size, "the second send never happened")
      assert_equal(:test, error.reason)
      refute(Dexpace::Resilience::Policy.throwable_retryable?(error))
    end

    test "RECOV-27: the wait is the clock's cancellable sleep with the caller's token" do
      clock = FakeClock.new
      source = Dexpace::Cancellation.source
      built, = engine([retry_response(503), retry_response(200)],
                      settings: retry_settings(clock: clock),)

      send_through(built, cancellation: source.token)

      assert_equal(1, clock.sleeps.size)
      assert_same(source.token, clock.sleeps.first[:cancellation])
    end

    test "RETRY-23: a cancelled token is checked at every attempt boundary" do
      source = Dexpace::Cancellation.source
      source.cancel(:already)
      built, transport = engine([retry_response(200)])

      assert_raises(Dexpace::CancelledError) { send_through(built, cancellation: source.token) }
      assert_equal(0, transport.calls.size)
    end

    test "RETRY-35 / RECOV-16: the error body is buffered (connection released) before the wait" do
      original = retry_response(503)
      released_at_sleep = []
      clock = FakeClock.new
      clock.define_singleton_method(:sleep) do |duration, cancellation: nil|
        released_at_sleep << original.body.closed?
        super(duration, cancellation: cancellation)
      end
      built, = engine([original, retry_response(200)], settings: retry_settings(clock: clock))

      send_through(built)

      assert_equal([true], released_at_sleep)
    end

    test "RETRY-35: the pacing delay is read from the buffered response, headers intact" do
      clock = FakeClock.new
      built, = engine([retry_response(503, headers: { "Retry-After" => "3" }), retry_response(200)],
                      settings: retry_settings(clock: clock),)

      send_through(built)

      assert_equal([3.0], clock.sleeps.map { _1[:duration] })
    end

    test "OBS-29 / P6-7: the tracer is made once per operation with the REQUEST as its context" do
      tracer = Dexpace::RecordingHTTPTracer.new
      contexts = []
      built, = engine([retry_response(503), retry_response(503), retry_response(200)],
                      http_tracer_factory: lambda { |request|
                        contexts << request
                        tracer
                      },)
      request = retry_request

      send_through(built, request: request)

      assert_equal([request], contexts)
      names = tracer.events.map(&:first)

      assert_equal(%i[attempt_started attempt_failed attempt_started attempt_failed
                      attempt_started], names,)
      tracer.events.each { |event| assert_same(request, event[1]) }
      assert_kind_of(Dexpace::ProtocolError, tracer.events[1][2])
      assert_in_delta(0.1, tracer.events[1][3])
    end

    test "OBS-29: retries_exhausted immediately precedes the terminal raise, with its error" do
      tracer = Dexpace::RecordingHTTPTracer.new
      built, = engine([retry_response(503), retry_response(503)],
                      settings: retry_settings(max_retries: 1),
                      http_tracer_factory: ->(_request) { tracer },)

      error = assert_raises(Dexpace::ProtocolError) { send_through(built) }

      assert_equal(:retries_exhausted, tracer.events.last.first)
      assert_same(error, tracer.events.last[2])
    end

    test "OBS-29: a never-retryable failure ends with no retries_exhausted" do
      tracer = Dexpace::RecordingHTTPTracer.new
      built, = engine([retry_response(404)], http_tracer_factory: ->(_request) { tracer })
      send_through(built)

      assert_equal(%i[attempt_started], tracer.events.map(&:first))
    end
  end

  # P6-3: the engine beneath a real Recovery::Orchestrator.
  class OrchestratorTest < DexpaceTestCase
    include Fixtures

    test "P6-3: beneath a real Orchestrator, RequestChain stamps once and the factory maps once" do
      calls = []
      factory = lambda do |response|
        calls << response.status.code
        Dexpace::ProtocolError.for(response)
      end
      built, transport = engine([retry_response(503), retry_response(404)],
                                settings: retry_settings(max_retries: 3),)
      stamp = Dexpace::Recovery::IdempotencyKeyStep.build(
        header: "Idempotency-Key", strategy: ->(_request) { Dexpace::UUID.generate },
        methods: [Dexpace::Method::PUT],
      )
      request_chain = Dexpace::Recovery::RequestChain.build(steps: [stamp])
      orchestrator = Dexpace::Recovery::Orchestrator.build(
        transport: built, request_chain: request_chain,
        response_chain: Dexpace::Recovery::ResponseChain.build(
          response_steps: [Dexpace::Recovery::ErrorMappingStep.build(factory: factory)],
        ),
      )

      request = retry_request(method: "PUT", body: replayable_body)
      error = assert_raises(Dexpace::ProtocolError) do
        orchestrator.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
      end

      assert_equal(404, error.status.code)
      assert_equal([404], calls, "once, on the terminal response, never on the retried 503")
      keys = transport.calls.map { |(sent, _o, _c)| sent.headers["Idempotency-Key"] }

      assert_equal(2, keys.size)
      assert_equal(keys.first, keys.last, "one key, stamped once, re-sent as is")
      refute_nil(keys.first)
    end

    test "P6-3: beneath the Orchestrator an exhausted retryable status surfaces as the raise" do
      built, = engine([retry_response(503), retry_response(503)],
                      settings: retry_settings(max_retries: 1),)
      orchestrator = Dexpace::Recovery::Orchestrator.build(
        transport: built, request_chain: Dexpace::Recovery::RequestChain.build,
        response_chain: Dexpace::Recovery::ResponseChain.build,
      )

      error = assert_raises(Dexpace::ProtocolError) do
        orchestrator.call(retry_request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
      end

      assert_equal(503, error.status.code)
      assert_equal(1, Dexpace.suppressed(error).size)
    end
  end
end
