# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
require_relative "../../support/diagnostic_context"
require_relative "../../support/fake_clock"
require_relative "../../support/fake_transport"
# 5c's doubles, consumed and not redefined (P5-48, P5-73): one double per idea.
require_relative "../../support/recording_tracer"
require_relative "../../support/recording_span"
require_relative "../../support/recording_meter"
require "dexpace"

# Exercises: OBS-17, OBS-18, OBS-20, OBS-34, OBS-36, OBS-38, OBS-39, BODY-19, BODY-22, BODY-34
#
# The sync step, driven through a REAL Dexpace::Pipeline over a fake transport: Builder#append
# reads #stage, the driver hands the step a real Cursor, and the step calls it once. The one
# test that discharges OBS-34's conformance clause asserts four things at once on purpose -- a
# test that asserted only "no events at none" passes under an implementation that guards the
# span with the same `if`.
#
# Split into nested classes under Metrics/ClassLength: the independence clause, the events, the
# body level, the asymmetry.
class DexpaceInstrumentationStepTest < DexpaceTestCase
  Step = Dexpace::Instrumentation::Step
  HTTPLogging = Dexpace::Instrumentation::HTTPLogging
  Keys = Dexpace::Instrumentation::Keys
  Events = Dexpace::Instrumentation::Events
  Logger = Dexpace::Instrumentation::Logger
  Redactor = Dexpace::Instrumentation::Redactor

  # The shared fixtures, reachable lexically from the nested classes.
  module Fixtures
    JSON = Dexpace::MediaType.parse("application/json; charset=utf-8")

    def build_request(method: "GET", url: "https://example.com/data", headers: {}, body: nil)
      builder = Dexpace::Headers.builder
      headers.each { |name, value| builder.add(name, value) }
      Dexpace::Request.build(method: method, url: url, headers: builder.build, body: body)
    end

    def build_response(request, status: 200, headers: {}, body: nil)
      builder = Dexpace::Headers.inbound_builder
      headers.each { |name, value| builder.add(name, value) }
      Dexpace::Response.build(request: request, protocol: Dexpace::Protocol::HTTP_1_1,
                              status: status, headers: builder.build, body: body,)
    end

    def buffer_body(text, media_type: JSON)
      buffer = Dexpace::IO::Buffer.new
      buffer.write(text)
      Dexpace::Body.buffer(buffer, media_type: media_type)
    end

    def pipeline(step, transport)
      Dexpace::Pipeline::Builder.new(transport: transport).append(step).build
    end

    def drive(step, request, response: nil, raises: nil)
      pipeline(step, FakeTransport.new(response: response, raises: raises)).call(request)
    end
  end
  include Fixtures

  # OBS-34's conformance clause, first half, transcribed: at none, zero sink writes, one span
  # started and finished, the counter and the histogram each recorded once -- under 5b's two
  # instrument names, so a swap of the two constants would fail.
  test "OBS-34: at level NONE no log event is emitted while the span and both instruments run" do
    sink = RecordingSink.new
    factory = Dexpace::RecordingTracerFactory.new
    meter = Dexpace::RecordingMeter.new
    clock = FakeClock.new(monotonic: 100.0)
    step = Step.build(logger: Logger.build(sink: sink), level: HTTPLogging::NONE,
                      tracer_factory: factory, meter: meter, clock: clock,)
    request = build_request
    response = build_response(request)
    transport = FakeTransport.new(response: response, before_return: -> { clock.advance(0.25) })

    assert_same(response, pipeline(step, transport).call(request))
    assert_empty(sink.entries)
    assert_equal(1, factory.tracers.size)
    assert_equal("GET", factory.tracers.first.name)
    span = factory.tracers.first.spans.first

    assert_equal(1, factory.tracers.first.spans.size)
    assert_equal(1, span.finished_at.size, "started once and finished once")
    assert_equal("GET", span.attributes["span.name"])
    assert_equal([Keys::INSTRUMENT_REQUEST_COUNT], meter.counters.map(&:name))
    assert_equal([Keys::INSTRUMENT_REQUEST_DURATION], meter.histograms.map(&:name))
    assert_equal([{ amount: 1, attributes: nil }], meter.counters.first.records)
    assert_equal([{ amount: 250.0, attributes: nil }], meter.histograms.first.records)
  end

  test "OBS-34: the two instruments are created once in .build, and the defaults are the no-ops" do
    meter = Dexpace::RecordingMeter.new
    step = Step.build(logger: Logger::NULL, level: HTTPLogging::NONE,
                      meter: meter,)
    request = build_request
    3.times { drive(step, request, response: build_response(request)) }

    assert_equal(1, meter.counters.size)
    assert_equal(1, meter.histograms.size)
    assert_equal(3, meter.counters.first.records.size)
    assert_predicate(step, :frozen?)
    assert_same(Dexpace::Pipeline::Stages::LOGGING, step.stage)
    assert(Dexpace::Pipeline::Step.conforms?(step))
    refute_respond_to(Step, :new)
  end

  # 4c: "a step that drives the chain exactly once drives it through #call, and #call and
  # #fork are disjoint on one cursor". A recording stand-in for the cursor is the only way to
  # see a fork: through the real pipeline a fork that then calls looks like a call.
  test "the step drives the cursor exactly once through #call and never forks" do
    step = Step.build(logger: Logger::NULL, level: HTTPLogging::NONE)
    request = build_request
    response = build_response(request)
    cursor = ::Object.new
    cursor.instance_variable_set(:@calls, [])
    cursor.define_singleton_method(:call) do |given|
      @calls << given
      response
    end
    cursor.define_singleton_method(:fork) { |state: nil| raise "forked with #{state.inspect}" }

    assert_same(response, step.call(request, cursor))
    assert_equal([request], cursor.instance_variable_get(:@calls))
  end

  test "the step is installed by its own stage, and the level and the cap are validated at build" do
    step = Step.build(logger: Logger::NULL, level: HTTPLogging::NONE)
    entries = Dexpace::Pipeline::Builder.new(transport: FakeTransport.new).append(step).entries

    assert_equal([Dexpace::Pipeline::Stages::LOGGING], entries.map(&:stage))
    assert_raises(Dexpace::InvalidArgumentError) do
      Step.build(logger: Logger::NULL, level: :headers)
    end
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Step.build(logger: Logger::NULL, level: HTTPLogging::BODY)
    end

    assert_equal("preview_bytes is required", error.message)
    [0, -1, 8.5, "16"].each do |cap|
      assert_raises(Dexpace::InvalidArgumentError, cap.inspect) do
        Step.build(logger: Logger::NULL, level: HTTPLogging::BODY,
                   preview_bytes: cap,)
      end
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Step.build(logger: nil, level: HTTPLogging::NONE)
    end
  end

  # OBS-39 and OBS-18 at the headers level.
  class EventsTest < DexpaceTestCase
    include Fixtures

    Step = Dexpace::Instrumentation::Step
    HTTPLogging = Dexpace::Instrumentation::HTTPLogging
    Keys = Dexpace::Instrumentation::Keys
    Events = Dexpace::Instrumentation::Events
    Logger = Dexpace::Instrumentation::Logger
    Redactor = Dexpace::Instrumentation::Redactor
    RedactionPolicy = Dexpace::Instrumentation::RedactionPolicy

    def headers_step(sink, redactor: Redactor::DEFAULT, clock: FakeClock.new)
      Step.build(logger: Logger.build(sink: sink, redactor: redactor), level: HTTPLogging::HEADERS,
                 clock: clock,)
    end

    test "OBS-39: at HEADERS the request and response events carry the documented keys" do
      sink = RecordingSink.new
      clock = FakeClock.new(monotonic: 5.0)
      step = headers_step(sink, clock: clock)
      request = build_request(method: "POST",
                              url: "https://user:pw@example.com/submit?token=secret",
                              headers: { "Content-Type" => "application/json" },
                              body: Dexpace::Body.string("payload"),)
      response = build_response(request, status: 201,
                                         headers: { "Location" => "https://example.com/r/1?token=s",
                                                    "Content-Length" => "7", },
                                         body: buffer_body("created"),)
      transport = FakeTransport.new(response: response, before_return: -> { clock.advance(0.0125) })

      pipeline(step, transport).call(request)

      assert_equal(%i[info info], sink.entries.map(&:severity))
      req_event, res_event = sink.payloads

      assert_equal(Events::HTTP_REQUEST, req_event[Keys::EVENT])
      assert_equal("POST", req_event[Keys::HTTP_REQUEST_METHOD])
      assert_equal("https://***:***@example.com/submit?token=***", req_event[Keys::URL_FULL])
      assert_equal("application/json", req_event["#{Keys::HTTP_REQUEST_HEADER_PREFIX}content-type"])
      assert_equal(7, req_event[Keys::HTTP_REQUEST_BODY_SIZE])
      refute(req_event.key?(Keys::HTTP_REQUEST_BODY_PREVIEW), "no preview below the body level")

      assert_equal(Events::HTTP_RESPONSE, res_event[Keys::EVENT])
      assert_equal(201, res_event[Keys::HTTP_RESPONSE_STATUS_CODE])
      assert_in_delta(12.5, res_event[Keys::HTTP_RESPONSE_DURATION_MS], 0.0001)
      assert_equal("https://example.com/r/1?token=***",
                   res_event["#{Keys::HTTP_RESPONSE_HEADER_PREFIX}location"],)
      assert_equal("7", res_event["#{Keys::HTTP_RESPONSE_HEADER_PREFIX}content-length"])
      assert_equal(7, res_event[Keys::HTTP_RESPONSE_BODY_SIZE])
      refute(res_event.key?(Keys::HTTP_RESPONSE_BODY_PREVIEW))
      refute_includes(sink.payloads.inspect, "secret")
      refute_includes(sink.payloads.inspect, "user:pw")
    end

    # OBS-18's negative, which is the assertion that matters: the credential appears NOWHERE in
    # the payload, not merely not under its own key. P5-35: the marker, not omission, is the
    # default, because present-and-redacted and absent are different facts to a reader.
    test "OBS-18: a non-allow-listed header is marked REDACTED by default; its value is nowhere" do
      sink = RecordingSink.new
      request = build_request(headers: { "Content-Type" => "text/plain",
                                         "Authorization" => "Bearer sk-live-abc123",
                                         "Cookie" => "session=deadbeef", })
      drive(headers_step(sink), request, response: build_response(request))
      payload = sink.payloads.first

      assert_equal("text/plain", payload["#{Keys::HTTP_REQUEST_HEADER_PREFIX}content-type"])
      assert_equal(Redactor::REDACTED_HEADER, payload["#{Keys::HTTP_REQUEST_HEADER_PREFIX}authorization"])
      assert_equal(Redactor::REDACTED_HEADER, payload["#{Keys::HTTP_REQUEST_HEADER_PREFIX}cookie"])
      refute_includes(sink.payloads.inspect, "Bearer")
      refute_includes(sink.payloads.inspect, "sk-live-abc123")
      refute_includes(sink.payloads.inspect, "deadbeef")
    end

    # OBS-18's boolean selects between the two modes, and both have a caller: a policy whose
    # true branch has no test is a policy nothing exercises.
    test "OBS-18: omit_disallowed_headers true omits the header instead of marking it" do
      sink = RecordingSink.new
      policy = RedactionPolicy::DEFAULT.with(omit_disallowed_headers: true)
      request = build_request(headers: { "Content-Type" => "text/plain",
                                         "Authorization" => "Bearer sk-live-abc123", })
      drive(headers_step(sink, redactor: Redactor.build(policy: policy)), request,
            response: build_response(request),)
      payload = sink.payloads.first

      refute(payload.key?("#{Keys::HTTP_REQUEST_HEADER_PREFIX}authorization"))
      assert_equal("text/plain", payload["#{Keys::HTTP_REQUEST_HEADER_PREFIX}content-type"])
      refute_includes(sink.payloads.inspect, "sk-live-abc123")
    end

    # P5-100 end to end: `location` is on the default allow-list, so a hostile server's
    # network-path or unparseable Location reached the sink verbatim before the round-0 fix.
    # The assertion is the chapter's own -- neither substring of the credential appears in ANY
    # payload -- and it runs through a real pipeline, not the redactor alone.
    test "OBS-11, OBS-16, OBS-17, P5-100: a hostile Location's userinfo never reaches the sink" do
      ["//user:secret@evil/x", "//user:secret@evil/x?code=S", "http://user:secret@evil/p x",
       "https://user:secret@evil/p?%zz=1",].each do |hostile|
        sink = RecordingSink.new
        request = build_request
        response = build_response(request, status: 302, headers: { "Location" => hostile })
        drive(headers_step(sink), request, response: response)
        location = sink.payloads[1]["#{Keys::HTTP_RESPONSE_HEADER_PREFIX}location"]

        assert_includes(location, "***:***@", hostile)
        refute_includes(sink.payloads.inspect, "secret", hostile)
        refute_includes(sink.payloads.inspect, "user:", hostile)
        refute_includes(sink.payloads.inspect, "code=S", hostile)
      end
    end

    test "OBS-17, OBS-39: a multi-valued allow-listed header is one joined field; names fold" do
      sink = RecordingSink.new
      request = build_request(headers: { "Accept" => "text/html" })
      response = build_response(request, headers: { "Vary" => "Accept", "vary" => "Cookie",
                                                    "Content-Location" => "/p?sig=1", },)
      drive(headers_step(sink), request, response: response)
      res_event = sink.payloads[1]

      assert_equal("text/html", sink.payloads[0]["#{Keys::HTTP_REQUEST_HEADER_PREFIX}accept"])
      assert_equal("Accept, Cookie", res_event["#{Keys::HTTP_RESPONSE_HEADER_PREFIX}vary"])
      assert_equal("/p?***", res_event["#{Keys::HTTP_RESPONSE_HEADER_PREFIX}content-location"])
    end
  end

  # OBS-39's failure event and OBS-10's fold, through the step.
  class FailureEventsTest < DexpaceTestCase
    include Fixtures

    Step = Dexpace::Instrumentation::Step
    HTTPLogging = Dexpace::Instrumentation::HTTPLogging
    Keys = Dexpace::Instrumentation::Keys
    Events = Dexpace::Instrumentation::Events
    Logger = Dexpace::Instrumentation::Logger
    Redactor = Dexpace::Instrumentation::Redactor

    def headers_step(sink, clock: FakeClock.new)
      Step.build(logger: Logger.build(sink: sink), level: HTTPLogging::HEADERS, clock: clock)
    end

    test "OBS-39: a failure emits http.response at ERROR with error.type and cause; re-raises" do
      sink = RecordingSink.new
      clock = FakeClock.new(monotonic: 1.0)
      step = headers_step(sink, clock: clock)
      request = build_request
      failure = Dexpace::TransportError.new("connection reset") if defined?(Dexpace::TransportError)
      failure ||= ::IOError.new("connection reset")
      transport = FakeTransport.new(raises: failure, before_return: -> { clock.advance(0.5) })

      raised = assert_raises(failure.class) { pipeline(step, transport).call(request) }

      assert_same(failure, raised)
      assert_equal(%i[info error], sink.entries.map(&:severity))
      payload = sink.payloads[1]

      assert_equal(Events::HTTP_RESPONSE, payload[Keys::EVENT])
      assert_equal(failure.class.name, payload[Keys::ERROR_TYPE])
      assert_equal("#{failure.class.name.split("::").last}: connection reset", payload[Keys::CAUSE])
      assert_in_delta(500.0, payload[Keys::HTTP_RESPONSE_DURATION_MS], 0.0001)
      refute(payload.key?(Keys::HTTP_RESPONSE_STATUS_CODE))
    end

    test "OBS-39: an anonymous error class reports its nearest named ancestor as error.type" do
      sink = RecordingSink.new
      request = build_request
      anonymous = ::Class.new(::IOError).new("anon")

      assert_raises(::IOError) { drive(headers_step(sink), request, raises: anonymous) }
      assert_equal("IOError", sink.payloads[1][Keys::ERROR_TYPE])
    end

    test "OBS-10, OBS-39: the events fold the diagnostic context of the calling fiber" do
      sink = RecordingSink.new
      request = build_request
      DiagnosticContext.preserve do
        ::Fiber[:"trace.id"] = "4bf92f3577b34da6a3ce929d0e0e4736"
        drive(headers_step(sink), request, response: build_response(request))
      end

      sink.payloads.each do |payload|
        assert_equal("4bf92f3577b34da6a3ce929d0e0e4736", payload["trace.id"])
      end
    end
  end

  # OBS-34's second half, OBS-36 and OBS-38: the body level.
  class BodyLevelTest < DexpaceTestCase
    include Fixtures

    Step = Dexpace::Instrumentation::Step
    HTTPLogging = Dexpace::Instrumentation::HTTPLogging
    Keys = Dexpace::Instrumentation::Keys
    Logger = Dexpace::Instrumentation::Logger
    Redactor = Dexpace::Instrumentation::Redactor

    # A request preview exists only once something WRITES the body, which is what a transport
    # does and what RequestLoggingBody taps; FakeTransport reads nothing, so this one drains the
    # wrapped body into a Buffer sink the way the terminal transport would.
    class WritingTransport
      attr_reader :written

      def initialize(response)
        @response = response
        @written = nil
      end

      def call(request, _options, _cancellation)
        sink = Dexpace::IO::Buffer.new
        request.body&.write_to(sink)
        @written = sink.snapshot
        @response
      end
    end

    def body_step(sink, cap:)
      Step.build(logger: Logger.build(sink: sink), level: HTTPLogging::BODY, preview_bytes: cap)
    end

    # OBS-34's second half ("at body level assert body preview fields present") and the whole
    # of OBS-36's: the caller receives every byte, the preview is capped, and the size field is
    # the CAPTURE's. The request preview rides on the response event, not the request event,
    # because the write happens inside cursor.call.
    test "OBS-34, OBS-36: at BODY the previews are present, capped, sized from the capture" do
      sink = RecordingSink.new
      cap = 16
      request = build_request(method: "POST",
                              body: Dexpace::Body.string("R" * 100,
                                                         media_type: JSON,),)
      response = build_response(request, body: buffer_body("S" * 100))
      transport = WritingTransport.new(response)

      returned = pipeline(body_step(sink, cap: cap), transport).call(request)

      assert_kind_of(Dexpace::ResponseLoggingBody, returned.body)
      assert_equal("S" * 100, returned.body_string, "the caller receives every byte (OBS-36)")
      assert_equal("R" * 100, transport.written, "and the wire body is untouched by the tap")
      req_event, res_event = sink.payloads

      refute(req_event.key?(Keys::HTTP_REQUEST_BODY_PREVIEW))
      assert_equal(100, req_event[Keys::HTTP_REQUEST_BODY_SIZE],
                   "the declared length, at request time",)
      assert_equal("R" * cap, res_event[Keys::HTTP_REQUEST_BODY_PREVIEW])
      assert_equal(cap, res_event[Keys::HTTP_REQUEST_BODY_SIZE])
      assert_equal("S" * cap, res_event[Keys::HTTP_RESPONSE_BODY_PREVIEW])
      assert_equal(cap, res_event[Keys::HTTP_RESPONSE_BODY_SIZE])
      refute_equal(100, res_event[Keys::HTTP_RESPONSE_BODY_SIZE],
                   "the preview's size, never the length",)
    end

    # OBS-38 through the step: charset-aware for text, size-only for binary.
    test "OBS-38: the previews are rendered charset-aware for text and size-only for binary" do
      sink = RecordingSink.new
      latin1 = Dexpace::MediaType.parse("text/plain; charset=iso-8859-1")
      request = build_request(method: "POST",
                              body: Dexpace::Body.bytes("caf\xE9".b,
                                                        media_type: latin1,),)
      png = Dexpace::MediaType.parse("image/png")
      response = build_response(request, body: buffer_body("\x89PNG\r\n".b, media_type: png))

      pipeline(body_step(sink, cap: 64), WritingTransport.new(response)).call(request)
      res_event = sink.payloads[1]

      assert_equal("café", res_event[Keys::HTTP_REQUEST_BODY_PREVIEW])
      assert_equal(4, res_event[Keys::HTTP_REQUEST_BODY_SIZE])
      assert_equal("[binary 6 bytes captured]", res_event[Keys::HTTP_RESPONSE_BODY_PREVIEW])
    end

    # BODY-34 and the body-logging caps' gate: below the body level neither wrapper is built and
    # the response body reaches the caller as the transport produced it -- even with a cap
    # supplied, because the LEVEL is the gate and the cap is only its size.
    test "BODY-34: below BODY no wrapper is constructed and the body is the transport's own" do
      sink = RecordingSink.new
      request = build_request(method: "POST", body: Dexpace::Body.string("R" * 100))
      body = buffer_body("S" * 100)
      response = build_response(request, body: body)
      step = Step.build(logger: Logger.build(sink: sink), level: HTTPLogging::HEADERS,
                        preview_bytes: 16,)
      transport = WritingTransport.new(response)

      returned = pipeline(step, transport).call(request)

      assert_same(body, returned.body)
      assert_equal("R" * 100, transport.written)
      assert_kind_of(Dexpace::BytesBody, transport_request_body(transport))
    end

    test "OBS-39: at BODY a failure event carries the request preview and no response preview" do
      sink = RecordingSink.new
      request = build_request(method: "POST",
                              body: Dexpace::Body.string("R" * 100,
                                                         media_type: JSON,),)

      assert_raises(::IOError) do
        drive(body_step(sink, cap: 8), request, raises: ::IOError.new("x"))
      end
      failure = sink.payloads[1]

      assert_equal("IOError", failure[Keys::ERROR_TYPE])
      assert_equal("", failure[Keys::HTTP_REQUEST_BODY_PREVIEW],
                   "nothing was written before it failed",)
      assert_equal(0, failure[Keys::HTTP_REQUEST_BODY_SIZE])
      refute(failure.key?(Keys::HTTP_RESPONSE_BODY_PREVIEW))
      refute(failure.key?(Keys::HTTP_RESPONSE_BODY_SIZE))
    end

    test "OBS-36: a body-less request and response at BODY emit no preview fields" do
      sink = RecordingSink.new
      request = build_request
      drive(body_step(sink, cap: 8), request, response: build_response(request, status: 204))
      res_event = sink.payloads[1]

      refute(res_event.key?(Keys::HTTP_REQUEST_BODY_PREVIEW))
      refute(res_event.key?(Keys::HTTP_RESPONSE_BODY_PREVIEW))
      assert_equal(204, res_event[Keys::HTTP_RESPONSE_STATUS_CODE])
    end

    private

    # The transport's view of the request body is not recorded by WritingTransport; FakeTransport
    # records the request it was called with.
    def transport_request_body(transport)
      transport.instance_variable_get(:@response).request.body
    end
  end

  # OBS-20's asymmetry: two halves in two tests that must not be merged.
  class AsymmetryTest < DexpaceTestCase
    include Fixtures

    Step = Dexpace::Instrumentation::Step
    HTTPLogging = Dexpace::Instrumentation::HTTPLogging
    Keys = Dexpace::Instrumentation::Keys
    Events = Dexpace::Instrumentation::Events
    Logger = Dexpace::Instrumentation::Logger
    Redactor = Dexpace::Instrumentation::Redactor

    # A sink whose INFO write raises and whose WARN write records: the request completes and the
    # failure of the log emission is re-surfaced as an http.instrumentation.log diagnostic.
    test "OBS-20: a raising sink cannot fail the request, and the failure becomes a diagnostic" do
      sink = RecordingSink.new
      sink.define_singleton_method(:info) { |*| raise ::IOError, "sink write failure" }
      step = Step.build(logger: Logger.build(sink: sink), level: HTTPLogging::HEADERS)
      request = build_request
      response = build_response(request)

      assert_same(response, drive(step, request, response: response))
      assert_equal(%i[warn warn], sink.entries.map(&:severity), "one diagnostic per site")
      sink.payloads.each do |payload|
        assert_equal(Events::INSTRUMENTATION_LOG, payload[Keys::EVENT])
        assert_equal("IOError: sink write failure", payload[Keys::CAUSE])
      end
    end

    test "OBS-20: a sink that raises on every call, the diagnostic included, cannot fail it" do
      hostile = ::Object.new
      %i[debug? info? warn? error?].each { |name| hostile.define_singleton_method(name) { true } }
      %i[debug info warn error].each do |name|
        hostile.define_singleton_method(name) do |*|
          raise "x"
        end
      end
      step = Step.build(logger: Logger.build(sink: hostile), level: HTTPLogging::HEADERS)
      request = build_request
      response = build_response(request)

      assert_same(response, drive(step, request, response: response))
    end

    # The other half is an assert_raises, and writing it as "and nothing bad happens" is how the
    # asymmetry gets quietly removed. The meter is deliberately NOT wrapped (OBS-30's contract).
    test "OBS-20, OBS-30: a throwing meter propagates and fails the request" do
      throwing = Dexpace::RecordingMeter.new
      throwing.counters # touch, then replace the counter's #add
      step = Step.build(logger: Logger::NULL, level: HTTPLogging::NONE,
                        meter: throwing,)
      throwing.counters.first.define_singleton_method(:add) do |*|
        raise ::StandardError, "meter failure"
      end
      request = build_request

      error = assert_raises(::StandardError) do
        drive(step, request, response: build_response(request))
      end

      assert_equal("meter failure", error.message)
    end

    test "OBS-20, OBS-30: a throwing tracer propagates before the chain is driven" do
      factory = ::Object.new
      def factory.tracer(*, **) = raise(::StandardError, "tracer failure")
      transport = FakeTransport.new(response: nil)
      step = Step.build(logger: Logger::NULL, level: HTTPLogging::NONE,
                        tracer_factory: factory,)

      assert_raises(::StandardError) { pipeline(step, transport).call(build_request) }
      assert_empty(transport.calls, "the chain was never driven")
    end

    # OBS-22/OBS-23 through the step: the scope is closed and the span finished on failure too.
    test "OBS-34: the span is finished and the current span restored when the chain raises" do
      factory = Dexpace::RecordingTracerFactory.new
      step = Step.build(logger: Logger::NULL, level: HTTPLogging::NONE,
                        tracer_factory: factory,)

      assert_raises(::IOError) { drive(step, build_request, raises: ::IOError.new("x")) }
      assert_equal(1, factory.tracers.first.spans.first.finished_at.size)
      assert_same(Dexpace::Instrumentation::NO_SPAN, Dexpace::Instrumentation::Tracing.current_span)
    end
  end
end
