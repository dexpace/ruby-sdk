# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
require_relative "../../support/diagnostic_context"
require_relative "../../support/fiber_storage_facts"
require_relative "../../support/fake_clock"
require_relative "../../support/fake_async_transport"
require_relative "../../support/recording_tracer"
require_relative "../../support/recording_span"
require_relative "../../support/recording_meter"
require "dexpace"

# Exercises: OBS-17, OBS-20, OBS-24, OBS-34, OBS-36, OBS-39
#
# The async step, driven through a REAL Dexpace::AsyncPipeline over phase 2's Completer and
# Future -- used rather than faked, because the two shapes the step takes (the same future below
# the body level, a derived one at it, P5-94) are properties of the real pivot. `settle_later`
# is what separates the synchronous head from the settlement side.
#
# Split into nested classes under Metrics/ClassLength: the settlement, the body level, the
# thread boundary.
class DexpaceInstrumentationAsyncStepTest < DexpaceTestCase
  AsyncStep = Dexpace::Instrumentation::AsyncStep
  HTTPLogging = Dexpace::Instrumentation::HTTPLogging
  Keys = Dexpace::Instrumentation::Keys
  Events = Dexpace::Instrumentation::Events
  Logger = Dexpace::Instrumentation::Logger
  Redactor = Dexpace::Instrumentation::Redactor

  # The shared fixtures, reachable lexically from the nested classes.
  module Fixtures
    JSON = Dexpace::MediaType.parse("application/json")

    def build_request(method: "GET", body: nil)
      Dexpace::Request.build(method: method, url: "https://u:p@example.com/async?t=1",
                             headers: Dexpace::Headers::EMPTY, body: body,)
    end

    def build_response(request, status: 200, body: nil)
      Dexpace::Response.build(request: request, protocol: Dexpace::Protocol::HTTP_1_1,
                              status: status, headers: Dexpace::Headers::EMPTY_INBOUND, body: body,)
    end

    def buffer_body(text)
      buffer = Dexpace::IO::Buffer.new
      buffer.write(text)
      Dexpace::Body.buffer(buffer, media_type: JSON)
    end

    def pipeline(step, transport)
      Dexpace::Pipeline::Builder.new(transport: transport).append(step).build_async
    end

    def async_step(sink, level:, **extra)
      AsyncStep.build(logger: Logger.build(sink: sink), level: level, **extra)
    end
  end
  include Fixtures

  test "P5-34: AsyncStep is a Step with the same .build and stage, and .new stays private" do
    step = async_step(RecordingSink.new, level: HTTPLogging::NONE)

    assert_kind_of(Dexpace::Instrumentation::Step, step)
    assert_same(Dexpace::Pipeline::Stages::LOGGING, step.stage)
    assert_predicate(step, :frozen?)
    refute_respond_to(AsyncStep, :new)
    assert_raises(Dexpace::InvalidArgumentError) do
      async_step(RecordingSink.new, level: HTTPLogging::BODY)
    end
  end

  # OBS-34's clause on the async path: nothing logged at none, the span open across the
  # settlement and finished with the instruments only once the future settles.
  test "OBS-34: at NONE nothing is logged, and the span and instruments complete at settlement" do
    sink = RecordingSink.new
    factory = Dexpace::RecordingTracerFactory.new
    meter = Dexpace::RecordingMeter.new
    clock = FakeClock.new(monotonic: 10.0)
    step = async_step(sink, level: HTTPLogging::NONE, tracer_factory: factory, meter: meter,
                            clock: clock,)
    request = build_request
    transport = FakeAsyncTransport.new(response: build_response(request), settle_later: true)

    future = pipeline(step, transport).call(request)
    span = factory.tracers.first.spans.first

    refute_predicate(future, :settled?)
    assert_empty(span.finished_at, "the span outlives the head")
    assert_empty(meter.counters.first.records)

    clock.advance(0.75)
    transport.settle

    assert_predicate(future, :settled?)
    assert_empty(sink.entries)
    assert_equal(1, span.finished_at.size)
    assert_equal([{ amount: 1, attributes: nil }], meter.counters.first.records)
    assert_equal([{ amount: 750.0, attributes: nil }], meter.histograms.first.records)
  end

  # OBS-22/OBS-23 on the async path (P5-93): the scope is closed on the calling fiber at the end
  # of the head, so the caller's current span is restored BEFORE the future settles, and a
  # settlement on another thread never writes this fiber's storage.
  test "P5-93: the current span is restored on the calling fiber before the future settles" do
    factory = Dexpace::RecordingTracerFactory.new
    step = async_step(RecordingSink.new, level: HTTPLogging::NONE, tracer_factory: factory)
    request = build_request
    transport = FakeAsyncTransport.new(response: build_response(request), settle_later: true)
    outer = Dexpace::RecordingSpan.new

    Dexpace::Instrumentation::Tracing.with_span(outer) do
      pipeline(step, transport).call(request)

      assert_same(outer, Dexpace::Instrumentation::Tracing.current_span)
    end
    transport.settle

    assert_same(Dexpace::Instrumentation::NO_SPAN, Dexpace::Instrumentation::Tracing.current_span)
  end

  # OBS-39's two events, the settlement side.
  class SettlementTest < DexpaceTestCase
    include Fixtures

    AsyncStep = Dexpace::Instrumentation::AsyncStep
    HTTPLogging = Dexpace::Instrumentation::HTTPLogging
    Keys = Dexpace::Instrumentation::Keys
    Events = Dexpace::Instrumentation::Events
    Logger = Dexpace::Instrumentation::Logger
    Redactor = Dexpace::Instrumentation::Redactor

    test "OBS-39, P5-94: below BODY the events straddle the settlement on the same future" do
      sink = RecordingSink.new
      step = async_step(sink, level: HTTPLogging::HEADERS)
      request = build_request
      transport = FakeAsyncTransport.new(response: build_response(request, status: 202),
                                         settle_later: true,)

      future = pipeline(step, transport).call(request)

      assert_same(transport.completer.future, future, "the chain's own future, not a derived one")
      assert_equal([Events::HTTP_REQUEST], sink.payloads.map { |payload| payload[Keys::EVENT] })
      assert_equal("https://***:***@example.com/async?t=***", sink.payloads[0][Keys::URL_FULL])

      transport.settle

      assert_equal(202, future.value.status.code)
      assert_equal([Events::HTTP_REQUEST, Events::HTTP_RESPONSE],
                   sink.payloads.map { |payload| payload[Keys::EVENT] },)
      assert_equal(202, sink.payloads[1][Keys::HTTP_RESPONSE_STATUS_CODE])
    end

    test "OBS-39: a failed settlement emits the failure event with error.type and the cause" do
      sink = RecordingSink.new
      step = async_step(sink, level: HTTPLogging::HEADERS)
      transport = FakeAsyncTransport.new(raises: ::IOError.new("connection timeout"))

      future = pipeline(step, transport).call(build_request)

      assert_raises(::IOError) { future.value }
      failure = sink.payloads[1]

      assert_equal(Events::HTTP_RESPONSE, failure[Keys::EVENT])
      assert_equal("IOError", failure[Keys::ERROR_TYPE])
      assert_equal("IOError: connection timeout", failure[Keys::CAUSE])
      assert_equal(:error, sink.entries[1].severity)
    end

    # A cancellation settles with a CancelledError, which takes the failure branch: no third
    # branch is needed (the plan's open question 4).
    test "OBS-39: a cancelled future takes the failure branch with the cancellation's class" do
      sink = RecordingSink.new
      step = async_step(sink, level: HTTPLogging::HEADERS)
      transport = FakeAsyncTransport.new(response: nil, settle_later: true)

      future = pipeline(step, transport).call(build_request)
      future.cancel(:caller)

      assert_predicate(future, :cancelled?)
      assert_equal("Dexpace::CancelledError", sink.payloads[1][Keys::ERROR_TYPE])
    end

    # OBS-20's edge on this path: the meter runs on the settling side, unwrapped, so its failure
    # reaches whoever settles -- here, the test -- and not the caller of #call.
    test "OBS-20, OBS-30: a throwing meter propagates into the settling side" do
      meter = Dexpace::RecordingMeter.new
      step = async_step(RecordingSink.new, level: HTTPLogging::NONE, meter: meter)
      meter.counters.first.define_singleton_method(:add) do |*|
        raise ::StandardError, "meter failure"
      end
      request = build_request
      transport = FakeAsyncTransport.new(response: build_response(request), settle_later: true)

      future = pipeline(step, transport).call(request)
      error = assert_raises(::StandardError) { transport.settle }

      assert_equal("meter failure", error.message)
      assert_predicate(future, :settled?)
    end

    test "OBS-20: a raising sink fails neither the head nor the settlement" do
      sink = RecordingSink.new
      sink.define_singleton_method(:info) { |*| raise ::IOError, "sink write failure" }
      step = async_step(sink, level: HTTPLogging::HEADERS)
      request = build_request
      transport = FakeAsyncTransport.new(response: build_response(request))

      future = pipeline(step, transport).call(request)

      assert_equal(200, future.value.status.code)
      assert_equal(%i[warn warn], sink.entries.map(&:severity))
    end

    # The head raising AFTER the span was opened -- a cursor that raises synchronously, which
    # the driver would normalise but a direct caller would not -- tears down here, unwrapped:
    # the scope is closed, the span finished, both instruments recorded, and the raise stands.
    test "OBS-34: a head that raises after the span opened still closes, finishes and records" do
      factory = Dexpace::RecordingTracerFactory.new
      meter = Dexpace::RecordingMeter.new
      step = async_step(RecordingSink.new, level: HTTPLogging::NONE, tracer_factory: factory,
                                           meter: meter,)
      raising_cursor = ::Object.new
      def raising_cursor.call(_request) = raise(::IOError, "synchronous head failure")

      assert_raises(::IOError) { step.call(build_request, raising_cursor) }
      assert_equal(1, factory.tracers.first.spans.first.finished_at.size)
      assert_equal(1, meter.counters.first.records.size)
      assert_same(Dexpace::Instrumentation::NO_SPAN, Dexpace::Instrumentation::Tracing.current_span)
    end

    test "OBS-20, OBS-30: a throwing tracer in the head propagates and drives nothing" do
      factory = ::Object.new
      def factory.tracer(*, **) = raise(::StandardError, "tracer failure")
      transport = FakeAsyncTransport.new(response: nil)
      step = async_step(RecordingSink.new, level: HTTPLogging::NONE, tracer_factory: factory)

      # AsyncDriver normalises a step's synchronous StandardError into a failed future (PIPE-30).
      future = pipeline(step, transport).call(build_request)

      assert_raises(::StandardError) { future.value }
      assert_empty(transport.calls)
    end
  end

  # OBS-17's shared policy and 4c's never-forks rule, through the async step.
  class SharedShapeTest < DexpaceTestCase
    include Fixtures

    AsyncStep = Dexpace::Instrumentation::AsyncStep
    HTTPLogging = Dexpace::Instrumentation::HTTPLogging
    Keys = Dexpace::Instrumentation::Keys
    Logger = Dexpace::Instrumentation::Logger
    Redactor = Dexpace::Instrumentation::Redactor

    # OBS-17: "The redaction policy MUST be shared by the sync and async logging paths so it
    # cannot drift". Both steps write through one Emitter (P5-34), and this asserts the
    # observable half: the async path redacts a Location value and marks a credential header
    # exactly as the sync path does.
    test "OBS-17: the async path redacts headers under the same policy as the sync path" do
      sink = RecordingSink.new
      step = async_step(sink, level: HTTPLogging::HEADERS)
      request_headers = Dexpace::Headers.builder
      request_headers.add("Authorization", "Bearer sk-live-abc123")
      request = Dexpace::Request.build(method: "GET", url: "https://example.com/",
                                       headers: request_headers.build,)
      response_headers = Dexpace::Headers.inbound_builder
      response_headers.add("Location", "/cb?code=SECRET")
      response = Dexpace::Response.build(request: request, protocol: Dexpace::Protocol::HTTP_1_1,
                                         status: 302, headers: response_headers.build,)

      pipeline(step, FakeAsyncTransport.new(response: response)).call(request).value
      req_event, res_event = sink.payloads

      assert_equal(Redactor::REDACTED_HEADER, req_event["#{Keys::HTTP_REQUEST_HEADER_PREFIX}authorization"])
      assert_equal("/cb?***", res_event["#{Keys::HTTP_RESPONSE_HEADER_PREFIX}location"])
      refute_includes(sink.payloads.inspect, "SECRET")
      refute_includes(sink.payloads.inspect, "sk-live")
    end

    test "the async step drives the cursor exactly once through #call and never forks" do
      step = async_step(RecordingSink.new, level: HTTPLogging::NONE)
      completer = Dexpace::Async::Completer.new
      calls = []
      cursor = ::Object.new
      cursor.define_singleton_method(:call) do |given|
        calls << given
        completer.future
      end
      cursor.define_singleton_method(:fork) { |state: nil| raise "forked with #{state.inspect}" }
      request = build_request

      assert_same(completer.future, step.call(request, cursor))
      assert_equal([request], calls)
      completer.fulfil(build_response(request))
    end
  end

  # OBS-36 on the async path (P5-94): a derived future carrying the wrapped response.
  class BodyLevelTest < DexpaceTestCase
    include Fixtures

    AsyncStep = Dexpace::Instrumentation::AsyncStep
    HTTPLogging = Dexpace::Instrumentation::HTTPLogging
    Keys = Dexpace::Instrumentation::Keys
    Logger = Dexpace::Instrumentation::Logger
    Redactor = Dexpace::Instrumentation::Redactor

    test "OBS-36, P5-94: at BODY the caller gets the wrapped response, every byte, derived" do
      sink = RecordingSink.new
      step = async_step(sink, level: HTTPLogging::BODY, preview_bytes: 8)
      request = build_request
      response = build_response(request, body: buffer_body("S" * 100))
      transport = FakeAsyncTransport.new(response: response, settle_later: true)

      future = pipeline(step, transport).call(request)

      refute_same(transport.completer.future, future,
                  "a derived future, because the response is transformed",)

      transport.settle
      response = future.value

      assert_kind_of(Dexpace::ResponseLoggingBody, response.body)
      assert_equal("S" * 100, response.body_string, "OBS-36: every byte")
      assert_equal("S" * 8, sink.payloads[1][Keys::HTTP_RESPONSE_BODY_PREVIEW])
      assert_equal(8, sink.payloads[1][Keys::HTTP_RESPONSE_BODY_SIZE])
    end

    test "P5-94: the derived future forwards a failure as the same object and cancel propagates" do
      sink = RecordingSink.new
      step = async_step(sink, level: HTTPLogging::BODY, preview_bytes: 8)
      failure = ::IOError.new("boom")
      transport = FakeAsyncTransport.new(raises: failure)

      future = pipeline(step, transport).call(build_request)

      assert_same(failure, assert_raises(::IOError) { future.value })
      assert_equal("IOError", sink.payloads[1][Keys::ERROR_TYPE])

      pending = FakeAsyncTransport.new(response: nil, settle_later: true)
      derived = pipeline(step, pending).call(build_request)
      derived.cancel(:caller)

      assert_predicate(pending.completer.future, :cancelled?,
                       "cancelling the derived cancels the source",)
    end
  end

  # OBS-24 on the async path: the head's diagnostic context is bridged into the settlement.
  class ThreadBoundaryTest < DexpaceTestCase
    include Fixtures
    include FiberStorageFacts

    AsyncStep = Dexpace::Instrumentation::AsyncStep
    HTTPLogging = Dexpace::Instrumentation::HTTPLogging
    Keys = Dexpace::Instrumentation::Keys
    Logger = Dexpace::Instrumentation::Logger
    Redactor = Dexpace::Instrumentation::Redactor

    test "OBS-24: a settlement on another thread emits under the caller's captured context" do
      sink = RecordingSink.new
      step = async_step(sink, level: HTTPLogging::HEADERS)
      request = build_request
      transport = FakeAsyncTransport.new(response: build_response(request), settle_later: true)

      DiagnosticContext.preserve do
        ::Fiber[:"trace.id"] = "caller_trace"
        pipeline(step, transport).call(request)
        ::Fiber[:"trace.id"] = "changed_after_the_head"

        settler_after = ::Thread.new do
          ::Fiber[:"trace.id"] = "settler_own"
          transport.settle
          ::Fiber[:"trace.id"]
        end.value

        assert_equal("settler_own", settler_after, "the settling thread's own context is restored")
      end

      assert_equal(%w[caller_trace caller_trace], sink.payloads.map do |payload|
        payload["trace.id"]
      end,)
    end

    # The FAILURE event takes the same bridge (P5-93): the round-1 review found its bridge
    # unasserted -- a bare log_failure in AsyncStep#settle survived the suite. A settlement
    # failed from another thread emits under the caller's captured context, and the settling
    # thread's own keys are put back.
    test "OBS-24, OBS-39: a failure settled on another thread emits under the caller's context" do
      sink = RecordingSink.new
      step = async_step(sink, level: HTTPLogging::HEADERS)
      transport = FakeAsyncTransport.new(raises: ::IOError.new("reset by peer"), settle_later: true)

      DiagnosticContext.preserve do
        ::Fiber[:"trace.id"] = "caller_trace"
        ::Fiber[:"span.id"] = "caller_span"
        future = pipeline(step, transport).call(request = build_request)
        ::Fiber[:"trace.id"] = "changed_after_the_head"

        settler_after = ::Thread.new do
          ::Fiber[:"trace.id"] = "settler_own"
          ::Fiber[:"span.id"] = nil
          transport.settle
          [::Fiber[:"trace.id"], ::Fiber[:"span.id"]]
        end.value

        assert_raises(::IOError) { future.value }
        assert_equal(["settler_own", nil], settler_after, "the settler's own context is restored")
        assert_same(request, transport.calls.first.first)
      end
      failure = sink.payloads[1]

      assert_equal(Events::HTTP_RESPONSE, failure[Keys::EVENT])
      assert_equal("IOError", failure[Keys::ERROR_TYPE])
      assert_equal("caller_trace", failure["trace.id"])
      assert_equal("caller_span", failure["span.id"])
      assert_equal(:error, sink.entries[1].severity)
    end
  end
end
