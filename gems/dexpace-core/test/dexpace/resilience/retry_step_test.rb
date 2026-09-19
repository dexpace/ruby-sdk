# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/retry_fixtures"
require_relative "../../support/scripted_transport"
require_relative "../../support/recording_http_tracer"
require_relative "../../support/recording_sink"
require_relative "../../support/state_probe"
require_relative "../../support/fake_config_source"

# Exercises: RETRY-2, RETRY-5, RETRY-6, RETRY-7, RETRY-8, RETRY-9, RETRY-10, RETRY-11, RETRY-12,
# RETRY-13, RETRY-15, RETRY-20, RETRY-21, RETRY-22, RETRY-23, RETRY-24, RETRY-25, RETRY-26,
# RETRY-28, RETRY-34, RETRY-35, RETRY-36, RETRY-39, RETRY-40, RETRY-41, RETRY-42, RETRY-44,
# RETRY-45, OBS-29, OBS-30, PIPE-15, PIPE-16, PIPE-40, XCUT-3, P6-5, P6-7, P6-11, P6-60
#
# The synchronous stage-based retry step, driven through a REAL Dexpace::Pipeline over a
# ScriptedTransport: Builder#append reads #stage, the driver mints the step's cursor, and the
# fork-for-every-drive rule is asserted through a recording cursor over that real one. Every
# wait is a FakeClock's -- a real Clock::SYSTEM wait in this suite is a finding -- and the one
# SYSTEM-clock test is the RETRY-23 case whose zero-length wait cannot observe the token.
# Hermetic: a RetryStep.build with no settings reads the configured MAX_RETRY_ATTEMPTS, so every
# nested class runs behind a FakeConfigSource env seam. Split into nested classes under
# Metrics/ClassLength.
class DexpaceResilienceRetryStepTest < DexpaceTestCase
  RetryStep = Dexpace::Resilience::RetryStep
  Stages = Dexpace::Pipeline::Stages

  # The pipeline shape every nested class drives, the counters it reads off, and the seam.
  module Fixtures
    include RetryFixtures

    # Hermetic (5a's rule, R0-1): a default-settings build reads Keys::MAX_RETRY_ATTEMPTS off the
    # process slot, so every test runs behind a FakeConfigSource env seam and resets the slot.
    def setup
      super
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new }
    end

    def teardown
      Dexpace.reset_config!
      super
    end

    def pipeline(step, script, wrap: true, extra: [])
      transport = ScriptedTransport.new(script)
      installed = wrap ? RecordingWrapper.new(step) : step
      builder = Dexpace::Pipeline::Builder.new(transport: transport).append(installed)
      extra.each { |(probe, stage)| builder.append(probe, stage: stage) }
      [builder.build, transport, installed]
    end

    def drive(step, script, request: retry_request, options: Dexpace::RequestOptions::EMPTY,
              cancellation: Dexpace::Cancellation.none)
      built, transport, wrapper = pipeline(step, script)
      response = built.call(request, options, cancellation)
      [response, transport, wrapper]
    end
  end
  include Fixtures

  test "declares Stages::RETRY, is frozen, hides .new, and is installed by its own stage" do
    step = RetryStep.build

    assert_same(Stages::RETRY, step.stage)
    assert_predicate(step, :frozen?)
    refute_respond_to(RetryStep, :new)
    assert(Dexpace::Pipeline::Step.conforms?(step))
    entries = Dexpace::Pipeline::Builder.new(transport: ScriptedTransport.new([])).append(step)
      .entries

    assert_equal([Stages::RETRY], entries.map(&:stage))
  end

  test "the constructor validates every keyword and names it" do
    assert_raises(Dexpace::InvalidArgumentError) { RetryStep.build(settings: :defaults) }
    assert_raises(Dexpace::InvalidArgumentError) { RetryStep.build(http_tracer_factory: :none) }
    assert_raises(Dexpace::InvalidArgumentError) { RetryStep.build(delay_override: 1.0) }
    assert_raises(Dexpace::InvalidArgumentError) { RetryStep.build(should_retry: true) }
    assert_raises(Dexpace::InvalidArgumentError) { RetryStep.build(logger: RecordingSink.new) }
  end

  test "pipeline/86343352 / PIPE-15 / PIPE-16: forks for EVERY drive, first included, no call" do
    step = RetryStep.build(settings: retry_settings(max_retries: 3))
    response, transport, wrapper = drive(step, [retry_response(503), retry_response(503),
                                                retry_response(200),],)

    assert_equal(200, response.status.code)
    assert_equal(3, transport.calls.size)
    assert_equal(1, wrapper.cursors.size, "the step's own #call ran once for the operation")
    assert_equal(3, wrapper.cursors.first.forks, "one fork per drive, attempt 1 included")
    assert_equal(0, wrapper.cursors.first.calls, "the owning cursor's #call was never invoked")
    refute_predicate(wrapper.cursors.first.real, :spent?)
  end

  test "RETRY-44: every attempt re-sends the SAME request object through a fresh fork" do
    step = RetryStep.build(settings: retry_settings(max_retries: 2))
    request = retry_request
    _response, transport, = drive(step, [retry_response(503), retry_response(200)],
                                  request: request,)

    assert_equal(2, transport.calls.size)
    transport.calls.each { |(sent, _options, _token)| assert_same(request, sent) }
  end

  test "RETRY-36: a 503, 503, 200 sequence terminates on the 200 after three sends" do
    step = RetryStep.build(settings: retry_settings(max_retries: 2))
    response, transport, = drive(step, [retry_response(503), retry_response(503),
                                        retry_response(200),],)

    assert_equal(200, response.status.code)
    assert_equal(3, transport.calls.size)
    refute_predicate(response.body, :closed?, "the response handed back is never closed")
  end

  test "RETRY-42: eight threads through one frozen step keep their attempt counts apart" do
    step = RetryStep.build(settings: retry_settings(max_retries: 3))
    results = Array.new(8) do
      ::Thread.new do
        response, transport, = drive(step, [retry_response(503), retry_response(503),
                                            retry_response(200),],)
        [response.status.code, transport.calls.size]
      end
    end.map(&:value)

    assert_equal([[200, 3]] * 8, results)
  end

  test "boundary 2: a RETRY fork writes no cursor state under any stage's key" do
    probe = StateProbe.new(stage_to_read: Stages::RETRY)
    step = RetryStep.build(settings: retry_settings(max_retries: 1))
    built, = pipeline(step, [retry_response(503), retry_response(200)],
                      extra: [[probe, Stages::AUTH]],)

    built.call(retry_request)

    assert_equal(2, probe.reads.size)
    probe.reads.each { |read| assert_empty(read) }
  end

  # RETRY-5..8, RETRY-2, RETRY-24, RETRY-25, RETRY-34: the two axes and the terminal paths.
  class EligibilityTest < DexpaceTestCase
    include Fixtures

    test "RETRY-5 / RETRY-7: a bare non-idempotent POST gets exactly one attempt, any status" do
      step = RetryStep.build(settings: retry_settings(max_retries: 5))
      response, transport, = drive(step, [retry_response(503), retry_response(200)],
                                   request: retry_request(method: "POST"),)

      assert_equal(503, response.status.code)
      assert_equal(1, transport.calls.size)
    end

    test "RETRY-5 / RETRY-8: a replayable body is re-sent; a consumed one is not, PUT or POST" do
      step = RetryStep.build(settings: retry_settings(max_retries: 5))
      response, transport, = drive(step, [retry_response(503), retry_response(200)],
                                   request: retry_request(method: "POST", body: replayable_body),)

      assert_equal(200, response.status.code)
      assert_equal(2, transport.calls.size)

      response, transport, = drive(step, [retry_response(503), retry_response(200)],
                                   request: retry_request(method: "PUT", body: consumed_body),)

      assert_equal(503, response.status.code)
      assert_equal(1, transport.calls.size)
    end

    test "RETRY-8: a should_retry answering true cannot override the re-sendability gate" do
      step = RetryStep.build(settings: retry_settings(max_retries: 5), should_retry: ->(*) { true })
      response, transport, = drive(step, [retry_response(503), retry_response(200)],
                                   request: retry_request(method: "POST"),)

      assert_equal(503, response.status.code)
      assert_equal(1, transport.calls.size)
    end

    test "RETRY-2 / RETRY-24: a throwable answering the capability is retried; one without, not" do
      step = RetryStep.build(settings: retry_settings(max_retries: 2))
      response, transport, = drive(step, [RetryableError.new("read timeout"),
                                          retry_response(200),],)

      assert_equal(200, response.status.code)
      assert_equal(2, transport.calls.size)

      error = assert_raises(UnretryableError) do
        drive(step, [UnretryableError.new("no"), retry_response(200)])
      end

      assert_empty(Dexpace.suppressed(error))
      error = assert_raises(::ArgumentError) { drive(step, [::ArgumentError.new("bug")]) }

      assert_equal("bug", error.message)
    end

    test "RETRY-37 / XCUT-7: the configured set is authoritative, wider and narrower" do
      wider = RetryStep.build(settings: retry_settings(max_retries: 2, retryable_statuses: [418]))
      response, transport, = drive(wider, [retry_response(418), retry_response(200)])

      assert_equal(200, response.status.code)
      assert_equal(2, transport.calls.size)

      narrower = RetryStep.build(settings: retry_settings(max_retries: 2,
                                                          retryable_statuses: [429],))
      response, transport, = drive(narrower, [retry_response(503), retry_response(200)])

      assert_equal(503, response.status.code, "503 is baked-retryable and still refused")
      assert_equal(1, transport.calls.size)
    end
  end

  # RETRY-34 and RETRY-25: the terminal paths.
  class TerminalPathTest < DexpaceTestCase
    include Fixtures

    test "RETRY-34: the terminal raise is the LAST error, carrying the prior trail, never itself" do
      step = RetryStep.build(settings: retry_settings(max_retries: 2))
      errors = Array.new(3) { |i| RetryableError.new("attempt #{i + 1}") }

      surfaced = assert_raises(RetryableError) { drive(step, errors) }

      assert_same(errors[2], surfaced)
      assert_equal(errors[0..1], Dexpace.suppressed(surfaced))
      refute_includes(Dexpace.suppressed(surfaced), surfaced)
      assert_nil(surfaced.cause, "pipeline/7ce4431d: the carried re-raise assigns no cause")
    end

    test "RETRY-34 / pipeline/7ce4431d: the carried re-raise adds nothing to a cause already set" do
      # $! is non-nil inside anything called from a CALLER's rescue block. On this stack every
      # surfaced throwable was RAISED by the downstream inside that same extent, so Ruby assigned
      # the caller's exception as its cause at the transport's own raise, and a cause once set
      # survives every later raise (verified on 4.0.6) -- which is why this test can assert only
      # that the step's `raise failure, cause: nil` leaves that cause exactly as it found it. The
      # DISCRIMINATING fixture, an error constructed and never raised, is RecoveryRetry's
      # ProtocolError; its suite is where a bare `raise error` runs red.
      step = RetryStep.build(settings: retry_settings(max_retries: 1))
      errors = [RetryableError.new("one"), RetryableError.new("two")]
      surfaced = nil
      in_flight = nil
      begin
        raise ::IOError, "the caller's own in-flight exception"
      rescue ::IOError => error
        in_flight = error
        surfaced = assert_raises(RetryableError) { drive(step, errors) }
      end

      assert_same(errors[1], surfaced)
      assert_same(in_flight, surfaced.cause, "set by the transport's raise, untouched since")
      assert_equal([errors[0]], Dexpace.suppressed(surfaced))
    end

    test "RETRY-34: a reused error instance trips no self-suppression -- the skip-self guard" do
      step = RetryStep.build(settings: retry_settings(max_retries: 2))
      same = RetryableError.new("same instance every time")

      surfaced = assert_raises(RetryableError) { drive(step, [same, same, same]) }

      assert_same(same, surfaced)
      assert_empty(Dexpace.suppressed(surfaced))
    end

    test "RETRY-34: on eventual success the prior trail is discarded" do
      step = RetryStep.build(settings: retry_settings(max_retries: 2))
      first = RetryableError.new("one")
      response, = drive(step, [first, retry_response(200)])

      assert_equal(200, response.status.code)
      assert_empty(Dexpace.suppressed(first), "nothing was ever attached to a non-terminal error")
    end

    test "RETRY-34: a terminal error status is RETURNED, never raised, its trail discarded" do
      step = RetryStep.build(settings: retry_settings(max_retries: 1))
      response, transport, = drive(step, [retry_response(503), retry_response(503)])

      assert_equal(503, response.status.code)
      assert_equal(2, transport.calls.size)
      refute_predicate(response.body, :closed?)
    end

    test "RETRY-35 / OBS-30: a tracer raising in retries_exhausted propagates, terminal closed" do
      # R1-1: the terminal emission sits inside the same fence as the decision -- a throwing
      # tracer fails the request (OBS-30, never contained) but the terminal error-status response
      # it would otherwise have returned is closed first, as the async pump's guarded block
      # already did; round 0 had closed the same drift for attempt_failed only (R0-4).
      terminal = retry_response(503)
      exploding = ::Object.new
      def exploding.attempt_started(*) = nil
      def exploding.attempt_failed(*) = nil
      def exploding.retries_exhausted(*) = raise("tracer blew up")
      step = RetryStep.build(settings: retry_settings(max_retries: 1),
                             http_tracer_factory: ->(_cursor) { exploding },)

      error = assert_raises(::RuntimeError) { drive(step, [retry_response(503), terminal]) }

      assert_equal("tracer blew up", error.message)
      assert_predicate(terminal.body, :closed?, "closed before the raise propagated")
    end

    test "RETRY-25: a fatal-family error propagates unchanged, unretried, unattached, unreported" do
      tracer = Dexpace::RecordingHTTPTracer.new
      step = RetryStep.build(settings: retry_settings(max_retries: 3),
                             http_tracer_factory: ->(_cursor) { tracer },)
      fatal = ::NoMemoryError.new("oom")

      surfaced = assert_raises(::NoMemoryError) { drive(step, [fatal, retry_response(200)]) }

      assert_same(fatal, surfaced)
      assert_empty(Dexpace.suppressed(surfaced))
      assert_equal(%i[attempt_started], tracer.events.map(&:first), "no attempt_failed for it")
    end

    test "RETRY-25: a fatal-family error answering the capability is still never retried" do
      step = RetryStep.build(settings: retry_settings(max_retries: 3))
      fatal = RetryableFatal.new("oom, and lying about it")
      built, transport, = pipeline(step, [fatal, retry_response(200)])

      surfaced = assert_raises(RetryableFatal) { built.call(retry_request) }

      assert_same(fatal, surfaced)
      assert_equal(1, transport.calls.size, "never a second send")
    end

    test "RETRY-25: a fatal-family error from inside the retry decision is not classified either" do
      step = RetryStep.build(settings: retry_settings(max_retries: 3),
                             should_retry: ->(*) { raise ::NoMemoryError, "oom in predicate" },)
      open_response = retry_response(503)

      assert_raises(::NoMemoryError) { drive(step, [open_response]) }
      assert_predicate(open_response.body, :closed?, "RETRY-35: closed before propagating")
    end
  end

  # RETRY-9..12, RETRY-15, RETRY-20..22, RETRY-35, RETRY-39, RETRY-40: delays and the close.
  class DelayTest < DexpaceTestCase
    include Fixtures

    test "RETRY-9 / RETRY-12 / RETRY-13: the schedule is Policy's, on the settings' clock" do
      clock = FakeClock.new
      settings = retry_settings(clock: clock, max_retries: 3)
      step = RetryStep.build(settings: settings)
      response, transport, = drive(step, [retry_response(503), retry_response(503),
                                          retry_response(503), retry_response(200),],)

      assert_equal(200, response.status.code)
      assert_equal(4, transport.calls.size)
      assert_equal([0.1, 0.2, 0.4], clock.sleeps.map { _1[:duration] })
      expected = (1..3).map do |attempt|
        Dexpace::Resilience::Policy.backoff_delay(attempt, **settings.backoff_arguments)
      end

      assert_equal(expected, clock.sleeps.map { _1[:duration] })
    end

    test "RETRY-26 / XCUT-3: every wait is the clock's cancellable sleep with the cursor's token" do
      clock = FakeClock.new
      step = RetryStep.build(settings: retry_settings(clock: clock, max_retries: 1))
      source = Dexpace::Cancellation.source
      drive(step, [retry_response(503), retry_response(200)], cancellation: source.token)

      assert_equal(1, clock.sleeps.size)
      assert_same(source.token, clock.sleeps.first[:cancellation])
    end

    test "RETRY-35: the response is released BEFORE the wait; the delay is read from it first" do
      closed_at_sleep = []
      hinted = retry_response(503, headers: { "Retry-After" => "3" })
      clock = FakeClock.new
      clock.define_singleton_method(:sleep) do |duration, cancellation: nil|
        closed_at_sleep << hinted.body.closed?
        super(duration, cancellation: cancellation)
      end
      step = RetryStep.build(settings: retry_settings(clock: clock, max_retries: 1))
      response, = drive(step, [hinted, retry_response(200)])

      assert_equal(200, response.status.code)
      assert_equal([true], closed_at_sleep, "closed before the wait")
      assert_equal([3.0], clock.sleeps.map { _1[:duration] }, "the hint was read while open")
    end

    test "RETRY-35 / OBS-30: a tracer raising in attempt_failed propagates, the response closed" do
      # The emission sits inside the same fence as the delay resolution: a throwing tracer fails
      # the request (OBS-30, never contained) but never leaves the superseded response open
      # across the propagation -- the async driver's guarded block already closed it (R0-4).
      open_response = retry_response(503)
      exploding = ::Object.new
      def exploding.attempt_started(*) = nil
      def exploding.attempt_failed(*) = raise("tracer blew up")
      clock = FakeClock.new
      step = RetryStep.build(settings: retry_settings(clock: clock, max_retries: 2),
                             http_tracer_factory: ->(_cursor) { exploding },)

      error = assert_raises(::RuntimeError) { drive(step, [open_response, retry_response(200)]) }

      assert_equal("tracer blew up", error.message)
      assert_predicate(open_response.body, :closed?, "closed before the raise propagated")
      assert_empty(clock.sleeps, "the wait was never reached")
    end

    test "RETRY-20 / RETRY-22: a pacing hint REPLACES the schedule verbatim; a bad one falls" do
      clock = FakeClock.new
      settings = retry_settings(clock: clock, initial_delay: 30.0, max_delay: 30.0, jitter: 0.5,
                                max_retries: 2,)
      step = RetryStep.build(settings: settings)
      drive(step, [retry_response(503, headers: { "Retry-After" => "2" }),
                   retry_response(429, headers: { "Retry-After" => "soon" }),
                   retry_response(200),],)
      first, second = clock.sleeps.map { _1[:duration] }

      assert_in_delta(2.0, first, 0.001, "verbatim: not 30.0 and not jittered into [1.5, 2.5]")
      assert_operator(second, :>=, 30.0 * 0.75)
      assert_operator(second, :<=, 30.0 * 1.25)
    end

    test "RETRY-21: the stage stack walks the caller's header order" do
      clock = FakeClock.new
      settings = retry_settings(clock: clock, max_retries: 1,
                                pacing_header_order: %w[retry-after-ms Retry-After],)
      step = RetryStep.build(settings: settings)
      both = { "Retry-After" => "9", "retry-after-ms" => "500" }
      drive(step, [retry_response(503, headers: both), retry_response(200)])

      assert_equal([0.5], clock.sleeps.map { _1[:duration] })
    end

    test "RETRY-15: an HTTP-date hint is measured from the settings clock's own now" do
      clock = FakeClock.new(now: ::Time.utc(2026, 9, 18, 12, 0, 0))
      step = RetryStep.build(settings: retry_settings(clock: clock, max_retries: 1))
      hinted = retry_response(503, headers: { "Retry-After" => "Fri, 18 Sep 2026 12:00:45 GMT" })
      drive(step, [hinted, retry_response(200)])

      assert_equal([45.0], clock.sleeps.map { _1[:duration] })
    end

    test "RETRY-39: the exception path skips the header step and reaches backoff" do
      clock = FakeClock.new
      seen = []
      step = RetryStep.build(settings: retry_settings(clock: clock, max_retries: 1),
                             delay_override: lambda { |attempt, response, error|
                               seen << [attempt, response, error]
                               nil
                             },)
      drive(step, [RetryableError.new("boom"), retry_response(200)])

      assert_equal(1, seen.size)
      assert_equal(1, seen.first[0])
      assert_nil(seen.first[1], "no response on the exception path")
      assert_kind_of(RetryableError, seen.first[2])
      assert_equal([0.1], clock.sleeps.map { _1[:duration] })
    end
  end

  # RETRY-39's first tier and RETRY-40's non-fatal half.
  class DelayOverrideTest < DexpaceTestCase
    include Fixtures

    test "RETRY-39: a present delay-override wins over a present pacing hint" do
      clock = FakeClock.new
      step = RetryStep.build(settings: retry_settings(clock: clock, max_retries: 1),
                             delay_override: ->(_attempt, _response, _error) { 7 },)
      drive(step, [retry_response(503, headers: { "Retry-After" => "2" }), retry_response(200)])

      assert_equal([7.0], clock.sleeps.map { _1[:duration] })
    end

    test "RETRY-40: a throwing delay-override is non-fatal -- logged, and backoff applies" do
      clock = FakeClock.new
      sink = RecordingSink.new
      step = RetryStep.build(settings: retry_settings(clock: clock, max_retries: 1),
                             delay_override: ->(*) { raise "override down" },
                             logger: Dexpace::Instrumentation::Logger.build(sink: sink),)
      response, = drive(step, [retry_response(503), retry_response(200)])

      assert_equal(200, response.status.code)
      assert_equal([0.1], clock.sleeps.map { _1[:duration] })
      assert_equal([:warn], sink.entries.map(&:severity))
      payload = sink.payloads.first

      assert_equal(Dexpace::Instrumentation::Events::INSTRUMENTATION_HOOK,
                   payload[Dexpace::Instrumentation::Keys::EVENT],)
      assert_match(/override down/, payload[Dexpace::Instrumentation::Keys::CAUSE])
    end

    test "RETRY-40: a delay-override answering a negative or non-numeric value is logged too" do
      clock = FakeClock.new
      sink = RecordingSink.new
      step = RetryStep.build(settings: retry_settings(clock: clock, max_retries: 2),
                             delay_override: ->(attempt, *) { attempt == 1 ? -1 : "soon" },
                             logger: Dexpace::Instrumentation::Logger.build(sink: sink),)
      drive(step, [retry_response(503), retry_response(503), retry_response(200)])

      assert_equal([0.1, 0.2], clock.sleeps.map { _1[:duration] })
      assert_equal(2, sink.entries.size)
    end

    test "RETRY-35 / RETRY-40: a throwing delay computation still closes the response first" do
      open_response = retry_response(503)
      step = RetryStep.build(settings: retry_settings(max_retries: 1),
                             delay_override: ->(*) { raise ::NotImplementedError, "fatal-shaped" },)

      assert_raises(::NotImplementedError) { drive(step, [open_response]) }
      assert_predicate(open_response.body, :closed?)
    end
  end

  # RETRY-40's predicate, RETRY-41's count, RETRY-23's cancellation.
  class PredicateAndBudgetTest < DexpaceTestCase
    include Fixtures

    test "RETRY-40: a throwing should_retry aborts as RetryPredicateError, the raise its cause" do
      open_response = retry_response(503)
      step = RetryStep.build(settings: retry_settings(max_retries: 1),
                             should_retry: ->(*) { raise "boom" },)

      error = assert_raises(Dexpace::RetryPredicateError) { drive(step, [open_response]) }

      assert_kind_of(::RuntimeError, error.cause)
      assert_equal("boom", error.cause.message)
      assert_kind_of(Dexpace::Error, error)
      assert_predicate(open_response.body, :closed?, "RETRY-35's third ordering")
    end

    test "RETRY-40: should_retry receives the failure and the request and decides the condition" do
      seen = []
      step = RetryStep.build(settings: retry_settings(max_retries: 5),
                             should_retry: lambda { |failure, request|
                               seen << [failure, request]
                               failure.is_a?(Dexpace::ProtocolError) && failure.status.code == 404
                             },)
      request = retry_request
      response, transport, = drive(step, [retry_response(404), retry_response(503)],
                                   request: request,)

      assert_equal(503, response.status.code, "404 retried by the predicate, 503 refused by it")
      assert_equal(2, transport.calls.size)
      assert_equal(2, seen.size)
      assert_same(request, seen.first[1])
      assert_equal(404, seen.first[0].status.code)
    end

    test "RETRY-41: the per-call max_retries override wins over the configured value" do
      step = RetryStep.build(settings: retry_settings(max_retries: 5))
      options = Dexpace::RequestOptions.build(timeout: nil, max_retries: 1, tags: {})
      response, transport, = drive(step, Array.new(6) { retry_response(503) }, options: options)

      assert_equal(503, response.status.code)
      assert_equal(2, transport.calls.size, "one retry: the override")

      options = Dexpace::RequestOptions.build(timeout: nil, max_retries: 0, tags: {})
      _response, transport, = drive(step, Array.new(6) { retry_response(503) }, options: options)

      assert_equal(1, transport.calls.size, "zero means no retries")
    end

    test "RETRY-41: with no override the configured value applies, and zero disables retries" do
      step = RetryStep.build(settings: retry_settings(max_retries: 0))
      _response, transport, = drive(step, [retry_response(503), retry_response(200)])

      assert_equal(1, transport.calls.size)
    end

    test "RETRY-23 / RECOV-27: cancellation during the wait aborts the loop as CancelledError" do
      source = Dexpace::Cancellation.source
      step = RetryStep.build(settings: retry_settings(max_retries: 5, initial_delay: 5.0))
      script = [lambda { |*|
        source.cancel(:test)
        retry_response(503)
      }, retry_response(200),]

      error = assert_raises(Dexpace::CancelledError) do
        drive(step, script, cancellation: source.token)
      end

      assert_equal(:test, error.reason)
      refute(Dexpace::Resilience::Policy.throwable_retryable?(error), "never a retryable condition")
    end

    test "RETRY-23: a cancelled token is checked at the top of every attempt, wait or no wait" do
      # Under Clock::SYSTEM a zero-length sleep returns before the token check (5a, verified), so
      # this attempt-boundary check is the only thing standing between the cancellation and a
      # second send. The one SYSTEM-clock wait in this suite is this zero-length one.
      source = Dexpace::Cancellation.source
      settings = Dexpace::Resilience::RetrySettings.build(max_retries: 5, initial_delay: 0.0,
                                                          jitter: 0.0,)
      step = RetryStep.build(settings: settings)
      script = [lambda { |*|
        source.cancel(:mid_attempt)
        retry_response(503)
      }, retry_response(200),]

      error = assert_raises(Dexpace::CancelledError) do
        drive(step, script, cancellation: source.token)
      end

      assert_equal(:mid_attempt, error.reason)
    end

    test "RETRY-23: a downstream cancellation surfaces as terminal, is never retried" do
      step = RetryStep.build(settings: retry_settings(max_retries: 5))
      error = assert_raises(Dexpace::CancelledError) do
        drive(step, [Dexpace::CancelledError.new(:downstream), retry_response(200)])
      end

      assert_equal(:downstream, error.reason)
    end

    test "RETRY-23: no attempt is launched after a cancellation observed mid-loop" do
      source = Dexpace::Cancellation.source
      step = RetryStep.build(settings: retry_settings(max_retries: 5))
      script = [lambda { |*|
        source.cancel(:stop)
        retry_response(503)
      }, retry_response(200),]

      assert_raises(Dexpace::CancelledError) { drive(step, script, cancellation: source.token) }
      # the script's second entry was never consumed
      _built, transport, = pipeline(step, script)

      assert_equal(0, transport.calls.size)
    end
  end

  # RETRY-23's guard ahead of the caller's predicate and the capability (P6-60).
  class CancellationGuardTest < DexpaceTestCase
    include Fixtures

    test "RETRY-23 / P6-60: a should_retry answering true cannot retry a downstream cancellation" do
      step = RetryStep.build(settings: retry_settings(max_retries: 5), should_retry: ->(*) { true })
      seen = []
      spy = RetryStep.build(settings: retry_settings(max_retries: 5),
                            should_retry: lambda { |failure, _request|
                              seen << failure
                              true
                            },)

      error = assert_raises(Dexpace::CancelledError) do
        drive(step, [Dexpace::CancelledError.new(:downstream), retry_response(200)])
      end

      assert_equal(:downstream, error.reason)
      assert_raises(Dexpace::CancelledError) do
        drive(spy, [Dexpace::CancelledError.new(:downstream), retry_response(200)])
      end
      assert_empty(seen, "the predicate is never consulted for a cancellation")
    end

    test "RETRY-23 / P6-60: a cancellation WRAPPED by a retryable error is terminal too" do
      # A transport that wraps the token's raise in its own retryable error: the capability
      # branch alone would retry it; the guard reads the cancellation it carries.
      wrapped = begin
        begin
          raise Dexpace::CancelledError, :token
        rescue Dexpace::CancelledError
          raise RetryableError, "read interrupted"
        end
      rescue RetryableError => error
        error
      end
      step = RetryStep.build(settings: retry_settings(max_retries: 5))

      surfaced = assert_raises(RetryableError) { drive(step, [wrapped, retry_response(200)]) }

      assert_same(wrapped, surfaced)
      assert_kind_of(Dexpace::CancelledError, surfaced.cause)
      assert_empty(Dexpace.suppressed(surfaced), "one attempt: no trail")
      _built, transport, = pipeline(step, [wrapped, retry_response(200)])

      assert_equal(0, transport.calls.size)
    end

    test "RETRY-23: the guard runs before the re-sendability gate and emits no retries_exhausted" do
      tracer = Dexpace::RecordingHTTPTracer.new
      step = RetryStep.build(settings: retry_settings(max_retries: 0),
                             http_tracer_factory: ->(_cursor) { tracer },)

      assert_raises(Dexpace::CancelledError) do
        drive(step, [Dexpace::CancelledError.new(:downstream)],
              request: retry_request(method: "POST", body: replayable_body),)
      end
      assert_equal(%i[attempt_started], tracer.events.map(&:first),
                   "a cancellation is :stop, never :exhausted, at any budget",)
    end
  end

  # OBS-29's per-attempt group, and the three text-scan guards (RETRY-13, RETRY-28, RETRY-45).
  class TracerAndGuardsTest < DexpaceTestCase
    include Fixtures

    RESILIENCE = File.expand_path("../../../lib/dexpace/resilience", __dir__)

    def source(name) = File.read(File.join(RESILIENCE, "#{name}.rb")).gsub(/^\s*#.*$/, "")

    test "OBS-29 / P6-7: the factory is called once per operation, with the cursor as context" do
      tracers = []
      cursors = []
      step = RetryStep.build(settings: retry_settings(max_retries: 2),
                             http_tracer_factory: lambda { |cursor|
                               cursors << cursor
                               tracers << Dexpace::RecordingHTTPTracer.new
                               tracers.last
                             },)
      _response, _transport, wrapper = drive(step, [retry_response(503), retry_response(200)])

      assert_equal(1, tracers.size)
      assert_equal([wrapper.cursors.first], cursors, "the step's own cursor, not a fork")
      tracers.first.events.each { |event| assert_same(wrapper.cursors.first, event[1]) }
    end

    test "OBS-29: attempt_started, attempt_failed with the delay, attempt_started, then success" do
      tracer = Dexpace::RecordingHTTPTracer.new
      step = RetryStep.build(settings: retry_settings(max_retries: 2),
                             http_tracer_factory: ->(_cursor) { tracer },)
      drive(step, [retry_response(503), retry_response(200)])
      names = tracer.events.map(&:first)

      assert_equal(%i[attempt_started attempt_failed attempt_started], names)
      assert_equal(1, tracer.events[0][2])
      assert_kind_of(Dexpace::ProtocolError, tracer.events[1][2], "an Exception, never a Response")
      assert_equal(503, tracer.events[1][2].status.code)
      assert_in_delta(0.1, tracer.events[1][3])
      assert_equal(2, tracer.events[2][2])
    end

    test "OBS-29: retries_exhausted fires once, after the last attempt, with the surfaced error" do
      tracer = Dexpace::RecordingHTTPTracer.new
      step = RetryStep.build(settings: retry_settings(max_retries: 1),
                             http_tracer_factory: ->(_cursor) { tracer },)
      errors = [RetryableError.new("one"), RetryableError.new("two")]

      surfaced = assert_raises(RetryableError) { drive(step, errors) }
      names = tracer.events.map(&:first)

      assert_equal(%i[attempt_started attempt_failed attempt_started retries_exhausted], names)
      assert_same(surfaced, tracer.events.last[2])
      assert_same(errors[0], tracer.events[1][2])
    end

    test "OBS-29: an exhausted error STATUS reports a ProtocolError carrying the trail" do
      tracer = Dexpace::RecordingHTTPTracer.new
      step = RetryStep.build(settings: retry_settings(max_retries: 1),
                             http_tracer_factory: ->(_cursor) { tracer },)
      drive(step, [retry_response(503), retry_response(503)])
      exhausted = tracer.events.last

      assert_equal(:retries_exhausted, exhausted.first)
      assert_equal(503, exhausted[2].status.code)
      assert_equal([tracer.events[1][2]], Dexpace.suppressed(exhausted[2]))
    end

    test "OBS-29: a failure that was never retryable ends with no retries_exhausted at all" do
      tracer = Dexpace::RecordingHTTPTracer.new
      step = RetryStep.build(settings: retry_settings(max_retries: 2),
                             http_tracer_factory: ->(_cursor) { tracer },)
      drive(step, [retry_response(404)])

      assert_equal(%i[attempt_started], tracer.events.map(&:first))
      assert_raises(::ArgumentError) { drive(step, [::ArgumentError.new("bug")]) }
      assert_equal(%i[attempt_started attempt_started], tracer.events.map(&:first))
    end

    test "OBS-30: a throwing tracer propagates and fails the request; core wraps no callback" do
      exploding = ::Object.new
      def exploding.attempt_started(*) = raise("tracer blew up")
      step = RetryStep.build(settings: retry_settings(max_retries: 1),
                             http_tracer_factory: ->(_cursor) { exploding },)

      error = assert_raises(::RuntimeError) { drive(step, [retry_response(200)]) }

      assert_equal("tracer blew up", error.message)
    end

    test "RETRY-28 / P6-5: neither stage driver names the budget, by text" do
      %w[retry_step async_retry_step retry_step_helpers].each do |name|
        code = source(name)

        refute_match(/budget_remaining|total_timeout/, code, name)
      end
      assert_match(/budget_remaining/, source("recovery_retry"), "the recovery driver alone")
    end

    test "RETRY-13: no delay literal outside Policy, in any resilience file" do
      %w[retry_step async_retry_step retry_step_helpers recovery_retry resend retry_settings]
        .each do |name|
        code = source(name)

        refute_match(/\b(0\.2|2\.0|8\.0)\b/, code, "#{name} re-types a Policy default")
        refute_match(/DEFAULT_(INITIAL_DELAY|MULTIPLIER|MAX_DELAY|JITTER)\s*=/, code, name)
      end
    end

    test "RETRY-45: the engine never shuts down or installs a scheduler, by text" do
      Dir[File.join(RESILIENCE, "*.rb")].each do |path|
        code = File.read(path).gsub(/^\s*#.*$/, "")

        touches = code.scan(/set_scheduler|scheduler&?\.close|shutdown/)

        assert_empty(touches, "#{File.basename(path)} touches a scheduler")
      end
    end
  end
end
