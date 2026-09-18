# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/retry_fixtures"
require_relative "../../support/scripted_async_transport"
require_relative "../../support/recording_http_tracer"
require_relative "../../support/recording_sink"
require_relative "../../support/parking_scheduler"
require_relative "../../support/fake_config_source"

# Exercises: RETRY-2, RETRY-5, RETRY-7, RETRY-8, RETRY-13, RETRY-20, RETRY-23, RETRY-24,
# RETRY-25, RETRY-26, RETRY-30, RETRY-31, RETRY-32, RETRY-33, RETRY-34, RETRY-35, RETRY-39,
# RETRY-40, RETRY-41, RETRY-42, RETRY-44, RETRY-45, OBS-29, OBS-30, PIPE-29, PIPE-30, XCUT-3,
# CFG-18, P6-5, P6-7, P6-60, R2
#
# The asynchronous stage-based retry step, driven through a REAL Dexpace::AsyncPipeline over a
# ScriptedAsyncTransport whose futures settle INLINE -- the shape that overflowed the plan's
# recursive pump -- and, for R2's scheduler route, through 5a's ParkingScheduler, the one double
# that can drive a timed wait (its loop runs in #close, so every case joins the scheduler's
# thread). No test here sleeps a thread: a zero-length delay completes inline, a positive one
# either parks a fiber or fails the future. Hermetic: a build with no settings reads the
# configured MAX_RETRY_ATTEMPTS, so every nested class runs behind a FakeConfigSource env seam.
# Split into nested classes under Metrics/ClassLength.
class DexpaceResilienceAsyncRetryStepTest < DexpaceTestCase
  AsyncRetryStep = Dexpace::Resilience::AsyncRetryStep
  Stages = Dexpace::Pipeline::Stages

  # The async pipeline shape every nested class drives, and the seam.
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

    def pipeline(step, script, settle_later: false)
      transport = ScriptedAsyncTransport.new(script, settle_later: settle_later)
      wrapper = RecordingWrapper.new(step)
      built = Dexpace::Pipeline::Builder.new(transport: transport).append(wrapper).build_async
      [built, transport, wrapper]
    end

    def drive(step, script, request: retry_request, options: Dexpace::RequestOptions::EMPTY,
              cancellation: Dexpace::Cancellation.none)
      built, transport, wrapper = pipeline(step, script)
      future = built.call(request, options, cancellation)
      [future, transport, wrapper]
    end

    # Zero-length waits, so no scheduler is needed and nothing sleeps (RETRY-31).
    def inline_settings(**overrides)
      retry_settings(initial_delay: 0.0, **overrides)
    end
  end
  include Fixtures

  test "declares Stages::RETRY, is frozen, hides .new, and returns a Future" do
    step = AsyncRetryStep.build

    assert_same(Stages::RETRY, step.stage)
    assert_predicate(step, :frozen?)
    refute_respond_to(AsyncRetryStep, :new)
    future, = drive(step, [retry_response(200)])

    assert_kind_of(Dexpace::Async::Future, future)
    assert_equal(200, future.value.status.code)
  end

  test "pipeline/86343352: forks for EVERY drive including the first, never calls its cursor" do
    step = AsyncRetryStep.build(settings: inline_settings(max_retries: 3))
    future, transport, wrapper = drive(step, [retry_response(503), retry_response(503),
                                              retry_response(200),],)

    assert_equal(200, future.value.status.code)
    assert_equal(3, transport.calls.size)
    assert_equal(3, wrapper.cursors.first.forks)
    assert_equal(0, wrapper.cursors.first.calls)
  end

  test "RETRY-44: the SAME request object is re-sent on every attempt" do
    step = AsyncRetryStep.build(settings: inline_settings(max_retries: 2))
    request = retry_request
    future, transport, = drive(step, [retry_response(503), retry_response(200)], request: request)

    assert_equal(200, future.value.status.code)
    transport.calls.each { |(sent, _options, _token)| assert_same(request, sent) }
  end

  test "RETRY-42: eight threads through one frozen step keep their attempt counts apart" do
    step = AsyncRetryStep.build(settings: inline_settings(max_retries: 3))
    results = Array.new(8) do
      ::Thread.new do
        future, transport, = drive(step, [retry_response(503), retry_response(503),
                                          retry_response(200),],)
        [future.value.status.code, transport.calls.size]
      end
    end.map(&:value)

    assert_equal([[200, 3]] * 8, results)
  end

  # RETRY-30, RETRY-31, R2's three routes, RETRY-45.
  class TrampolineTest < DexpaceTestCase
    include Fixtures

    # The depth probe: a transport that records the call-stack depth at every attempt. A pump
    # that recursed would show a depth growing with the attempt number; a flat one shows the
    # same depth at attempt 1 and attempt N.
    def depth_probe(depths, response)
      lambda do |_request, _options, _cancellation|
        depths << caller.size
        response
      end
    end

    test "RETRY-30 / RETRY-31: 2000 zero-length retries build no N-deep stack, measured" do
      depths = []
      failures = Array.new(2_000) { depth_probe(depths, retry_response(503)) }
      script = failures + [depth_probe(depths, retry_response(200))]
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 2_000))

      assert_nil(::Fiber.scheduler, "no scheduler anywhere in this test")
      future, transport, = drive(step, script)

      assert_equal(200, future.value.status.code)
      assert_equal(2_001, transport.calls.size)
      assert_equal(2_001, depths.size)
      assert_equal(depths.first, depths.last, "attempt 1 and attempt 2001 at the same depth")
      assert_equal(1, depths.uniq.size, "every attempt at one depth: the pump is flat")
    end

    test "R2 / RETRY-31: a zero-length delay completes inline and re-arms the pump, no scheduler" do
      assert_nil(::Fiber.scheduler)
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 1))
      future, transport, = drive(step, [retry_response(503), retry_response(200)])

      assert_predicate(future, :settled?, "settled before #call returned: no wait happened")
      assert_equal(200, future.value.status.code)
      assert_equal(2, transport.calls.size)
    end

    test "R2 / CFG-18: a positive delay under a scheduler parks the fiber, blocks no thread" do
      scheduler = ParkingScheduler.new
      settings = retry_settings(initial_delay: 0.01, max_retries: 2)
      step = AsyncRetryStep.build(settings: settings)
      future = nil
      thread = ::Thread.new do
        ::Fiber.set_scheduler(scheduler)
        ::Fiber.schedule do
          future, = drive(step, [retry_response(503), retry_response(503), retry_response(200)])
        end
      end
      thread.join

      assert_predicate(future, :settled?)
      assert_equal(200, future.value.status.code)
      assert_operator(scheduler.block_count, :>=, 2, "one park per positive wait")
      assert_equal(0, scheduler.kernel_sleep_count)
    end

    test "R2 / RETRY-33: a positive delay with NO scheduler fails the future with SeamError" do
      assert_nil(::Fiber.scheduler)
      step = AsyncRetryStep.build(settings: retry_settings(initial_delay: 0.01, max_retries: 2))
      first = RetryableError.new("first")
      future, transport, = drive(step, [first, retry_response(200)])

      assert_predicate(future, :settled?, "not a hang, not a blocking fallback")
      error = assert_raises(Dexpace::SeamError) { future.value }

      assert_match(/Fiber\.set_scheduler/, error.message)
      assert_equal([first], Dexpace.suppressed(error), "the trail travels with the SeamError")
      assert_equal(1, transport.calls.size, "no second attempt was launched")
    end

    test "RETRY-45: no scheduler is installed, read or shut down by the driver" do
      scheduler = ParkingScheduler.new
      closed = false
      scheduler.define_singleton_method(:close) do
        closed = true
        super()
      end
      step = AsyncRetryStep.build(settings: retry_settings(initial_delay: 0.001, max_retries: 1))
      future = nil
      thread = ::Thread.new do
        ::Fiber.set_scheduler(scheduler)
        ::Fiber.schedule { future, = drive(step, [retry_response(503), retry_response(200)]) }

        refute(closed, "the driver did not close the scheduler while it was running")
      end
      thread.join

      assert_equal(200, future.value.status.code)
      assert(closed, "the interpreter closed it at thread end, as CFG-18's own suite relies on")
    end
  end

  # RETRY-32, RETRY-33, RETRY-23: the async terminal paths.
  class TerminalPathsTest < DexpaceTestCase
    include Fixtures

    test "RETRY-32: a cancelled future launches no further attempt and closes the in-flight one" do
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 3))
      in_flight = retry_response(503)
      transport = ScriptedAsyncTransport.new([in_flight, retry_response(503)], settle_later: true)
      built = Dexpace::Pipeline::Builder.new(transport: transport).append(step).build_async

      future = built.call(retry_request)

      refute_predicate(future, :settled?)
      future.cancel(:caller)

      assert_predicate(future, :cancelled?)
      assert(transport.settle_next!, "the abandoned attempt now lands")
      assert_predicate(in_flight.body, :closed?, "closed rather than leaked")
      assert_equal(1, transport.calls.size, "no second attempt after the cancellation")
      assert_nil(transport.settle_next!)
    end

    test "RETRY-32: a deadline that cancels the future during a wait stops the loop" do
      scheduler = ParkingScheduler.new
      step = AsyncRetryStep.build(settings: retry_settings(initial_delay: 0.05, max_retries: 5))
      transport = nil
      outcome = nil
      thread = ::Thread.new do
        ::Fiber.set_scheduler(scheduler)
        ::Fiber.schedule do
          future, transport, = drive(step, Array.new(6) { retry_response(503) })
          future.cancel(:deadline)
          outcome = future.cancelled?
        end
      end
      thread.join

      assert(outcome)
      assert_equal(1, transport.calls.size)
    end

    test "RETRY-33: a throwing should_retry completes the future exceptionally, response closed" do
      open_response = retry_response(503)
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 1),
                                  should_retry: ->(*) { raise "boom" },)
      future, = drive(step, [open_response])

      assert_predicate(future, :settled?, "the one outcome RETRY-33 names is a hang; not this")
      error = assert_raises(Dexpace::RetryPredicateError) { future.value }

      assert_equal("boom", error.cause.message)
      assert_predicate(open_response.body, :closed?)
    end

    test "RETRY-33: a throwing tracer callback completes the future exceptionally, no hang" do
      exploding = ::Object.new
      def exploding.attempt_started(*) = raise("tracer blew up")
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 1),
                                  http_tracer_factory: ->(_cursor) { exploding },)
      future, = drive(step, [retry_response(200)])

      assert_predicate(future, :settled?)
      error = assert_raises(::RuntimeError) { future.value }

      assert_equal("tracer blew up", error.message)
    end

    test "RETRY-33 / RETRY-35: a tracer raising in attempt_failed closes the response, no hang" do
      open_response = retry_response(503)
      exploding = ::Object.new
      def exploding.attempt_started(*) = nil
      def exploding.attempt_failed(*) = raise("tracer blew up")
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 2),
                                  http_tracer_factory: ->(_cursor) { exploding },)
      future, transport, = drive(step, [open_response, retry_response(200)])

      assert_predicate(future, :settled?)
      error = assert_raises(::RuntimeError) { future.value }

      assert_equal("tracer blew up", error.message)
      assert_predicate(open_response.body, :closed?, "the sync driver closes it the same way")
      assert_equal(1, transport.calls.size)
    end

    test "RETRY-33: a throwing factory completes the future exceptionally" do
      step = AsyncRetryStep.build(settings: inline_settings,
                                  http_tracer_factory: ->(_cursor) { raise "no tracer" },)
      future, transport, = drive(step, [retry_response(200)])

      assert_raises(::RuntimeError) { future.value }
      assert_equal(0, transport.calls.size)
    end

    test "RETRY-33 / RETRY-35: a throwing delay computation closes the response and fails" do
      open_response = retry_response(503)
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 1),
                                  delay_override: ->(*) { raise ::NotImplementedError, "fatal" },)
      transport = ScriptedAsyncTransport.new([open_response])
      built = Dexpace::Pipeline::Builder.new(transport: transport).append(step).build_async

      # The fatal family is re-raised AFTER the future is failed (RETRY-25 with RETRY-33), and
      # the async driver's normalisation lets a ScriptError through, so it reaches this frame.
      assert_raises(::NotImplementedError) { built.call(retry_request) }
      assert_predicate(open_response.body, :closed?)
    end

    test "RETRY-25: a fatal-family error from the downstream is surfaced unchanged, unretried" do
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 3))
      fatal = ::NoMemoryError.new("oom")
      completer = Dexpace::Async::Completer.new
      completer.fail(fatal)
      transport = ->(_request, _options, _cancellation) { completer.future }
      built = Dexpace::Pipeline::Builder.new(transport: transport).append(step).build_async
      future = built.call(retry_request)

      surfaced = assert_raises(::NoMemoryError) { future.value }

      assert_same(fatal, surfaced)
      assert_empty(Dexpace.suppressed(surfaced))
    end
  end

  # RETRY-23 / RECOV-27 on the async path: the token during a wait and at the boundary.
  class CancellationTest < DexpaceTestCase
    include Fixtures

    test "RETRY-25: a fatal-family error answering the capability is still never retried" do
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 3))
      fatal = RetryableFatal.new("oom, and lying about it")
      completer = Dexpace::Async::Completer.new
      completer.fail(fatal)
      sends = 0
      transport = lambda do |_request, _options, _cancellation|
        sends += 1
        completer.future
      end
      built = Dexpace::Pipeline::Builder.new(transport: transport).append(step).build_async

      surfaced = assert_raises(RetryableFatal) { built.call(retry_request).value }

      assert_same(fatal, surfaced)
      assert_equal(1, sends)
    end

    test "RETRY-23 / XCUT-3: a token cancelled during a wait cancels the timer, fails the future" do
      scheduler = ParkingScheduler.new
      source = Dexpace::Cancellation.source
      step = AsyncRetryStep.build(settings: retry_settings(initial_delay: 0.05, max_retries: 5))
      first = RetryableError.new("first")
      result = nil
      transport = nil
      thread = ::Thread.new do
        ::Fiber.set_scheduler(scheduler)
        ::Fiber.schedule do
          future, transport, = drive(step, [first, retry_response(200)],
                                     cancellation: source.token,)
          source.cancel(:token)
          result = begin
            future.value
          rescue Dexpace::CancelledError => error
            error
          end
        end
      end
      thread.join

      assert_kind_of(Dexpace::CancelledError, result)
      assert_equal(:token, result.reason)
      assert_equal([first], Dexpace.suppressed(result))
      assert_equal(1, transport.calls.size)
    end

    test "RETRY-23: a cancelled token is checked at the top of every attempt" do
      source = Dexpace::Cancellation.source
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 5))
      script = [lambda { |*|
        source.cancel(:mid)
        retry_response(503)
      }, retry_response(200),]
      future, transport, = drive(step, script, cancellation: source.token)

      error = assert_raises(Dexpace::CancelledError) { future.value }

      assert_equal(:mid, error.reason)
      assert_equal(1, transport.calls.size)
    end

    test "RETRY-23 / P6-60: a should_retry answering true cannot retry a downstream cancellation" do
      seen = []
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 5),
                                  should_retry: lambda { |failure, _request|
                                    seen << failure
                                    true
                                  },)
      future, transport, = drive(step, [Dexpace::CancelledError.new(:downstream),
                                        retry_response(200),],)

      error = assert_raises(Dexpace::CancelledError) { future.value }

      assert_equal(:downstream, error.reason)
      assert_equal(1, transport.calls.size)
      assert_empty(seen, "the predicate is never consulted for a cancellation")
    end

    test "RETRY-23 / P6-60: a cancellation wrapped by a retryable error is terminal on this path" do
      wrapped = begin
        begin
          raise Dexpace::CancelledError, :token
        rescue Dexpace::CancelledError
          raise RetryableError, "read interrupted"
        end
      rescue RetryableError => error
        error
      end
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 5))
      future, transport, = drive(step, [wrapped, retry_response(200)])

      assert_same(wrapped, assert_raises(RetryableError) { future.value })
      assert_equal(1, transport.calls.size)
    end
  end

  # The shared decision and delay logic, asserted on the async path too (design §11.12).
  class SharedShapeTest < DexpaceTestCase
    include Fixtures

    test "RETRY-5 / RETRY-7 / RETRY-8: the re-sendability gate, predicate or no predicate" do
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 5),
                                  should_retry: ->(*) { true },)
      future, transport, = drive(step, [retry_response(503), retry_response(200)],
                                 request: retry_request(method: "POST"),)

      assert_equal(503, future.value.status.code)
      assert_equal(1, transport.calls.size)
      future, transport, = drive(step, [retry_response(503), retry_response(200)],
                                 request: retry_request(method: "POST", body: replayable_body),)

      assert_equal(200, future.value.status.code)
      assert_equal(2, transport.calls.size)
    end

    test "RETRY-34: the terminal failure carries the whole prior trail, skipping itself" do
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 2))
      errors = Array.new(3) { |i| RetryableError.new("attempt #{i + 1}") }
      future, = drive(step, errors)

      surfaced = assert_raises(RetryableError) { future.value }

      assert_same(errors[2], surfaced)
      assert_equal(errors[0..1], Dexpace.suppressed(surfaced))
      same = RetryableError.new("same")
      future, = drive(step, [same, same, same])

      assert_same(same, assert_raises(RetryableError) { future.value })
      assert_empty(Dexpace.suppressed(same))
    end

    test "RETRY-34: a terminal error status is DELIVERED, never failed" do
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 1))
      future, transport, = drive(step, [retry_response(503), retry_response(503)])

      assert_equal(503, future.value.status.code)
      assert_equal(2, transport.calls.size)
      refute_predicate(future.value.body, :closed?)
    end

    test "RETRY-2 / RETRY-24: the capability query decides the throwable branch" do
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 2))
      future, transport, = drive(step, [RetryableError.new("timeout"), retry_response(200)])

      assert_equal(200, future.value.status.code)
      assert_equal(2, transport.calls.size)
      future, transport, = drive(step, [UnretryableError.new("no"), retry_response(200)])

      assert_raises(UnretryableError) { future.value }
      assert_equal(1, transport.calls.size)
    end

    test "RETRY-20 / RETRY-39: the override sees the response on one path, the error on another" do
      seen = []
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 2, initial_delay: 0.0),
                                  delay_override: lambda { |attempt, response, error|
                                    seen << [attempt, response&.status&.code, error.class]
                                    0.0
                                  },)
      future, = drive(step, [retry_response(503, headers: { "Retry-After" => "0" }),
                             RetryableError.new("x"), retry_response(200),],)

      assert_equal(200, future.value.status.code)
      assert_equal([[1, 503, NilClass], [2, nil, RetryableError]], seen)
    end

    test "RETRY-40: a throwing delay-override is logged and falls back on the async path too" do
      sink = RecordingSink.new
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 1),
                                  delay_override: ->(*) { raise "override down" },
                                  logger: Dexpace::Instrumentation::Logger.build(sink: sink),)
      future, = drive(step, [retry_response(503), retry_response(200)])

      assert_equal(200, future.value.status.code)
      assert_equal([:warn], sink.entries.map(&:severity))
    end

    test "RETRY-41: the per-call override wins, on the async path too" do
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 5))
      options = Dexpace::RequestOptions.build(timeout: nil, max_retries: 1, tags: {})
      future, transport, = drive(step, Array.new(6) { retry_response(503) }, options: options)

      assert_equal(503, future.value.status.code)
      assert_equal(2, transport.calls.size)
    end

    test "OBS-29 / P6-7: the per-attempt group, from one tracer per operation, with the cursor" do
      tracer = Dexpace::RecordingHTTPTracer.new
      cursors = []
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 1),
                                  http_tracer_factory: lambda { |cursor|
                                    cursors << cursor
                                    tracer
                                  },)
      future, _transport, wrapper = drive(step, [retry_response(503), retry_response(503)])

      assert_equal(503, future.value.status.code)
      assert_equal([wrapper.cursors.first], cursors)
      assert_equal(%i[attempt_started attempt_failed attempt_started retries_exhausted],
                   tracer.events.map(&:first),)
      tracer.events.each { |event| assert_same(wrapper.cursors.first, event[1]) }
      assert_kind_of(Dexpace::ProtocolError, tracer.events[1][2])
      assert_in_delta(0.0, tracer.events[1][3])
    end

    test "OBS-29: a failure that was never retryable ends with no retries_exhausted" do
      tracer = Dexpace::RecordingHTTPTracer.new
      step = AsyncRetryStep.build(settings: inline_settings(max_retries: 2),
                                  http_tracer_factory: ->(_cursor) { tracer },)
      future, = drive(step, [retry_response(404)])

      assert_equal(404, future.value.status.code)
      assert_equal(%i[attempt_started], tracer.events.map(&:first))
    end
  end
end
