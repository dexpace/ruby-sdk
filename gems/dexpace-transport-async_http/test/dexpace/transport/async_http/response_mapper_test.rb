# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/async_http_recording_body"
require_relative "../../../support/async_http_recording_sink"
require "dexpace/transport/async_http"

# Dispatch step 15. TRANSPORT-14: obs-text in a value preserved, a control byte in a value
# dropped (that header only, logged verbose); the malformed-NAME half is unreachable on this
# adapter -- protocol-http1 raises BadHeader out of the read before a response exists to adapt
# (P8-38) -- so it is a NAMED WAIVER in the conformance driver, not a test here. TRANSPORT-24:
# the status mapping over the model's range. TRANSPORT-27: a malformed Content-Type downgrades to
# no media type; an absent native length maps to the -1 sentinel. The body handed on is the
# native BODY, never the response, whose #read is the whole body joined. Two nested classes under
# Metrics/ClassLength: the head, and the body.
module DexpaceTransportAsyncHTTPResponseMapperTest
  # The native response, the request and the mapper call both classes share.
  module ResponseMapperTestSupport
    ResponseMapper = Dexpace::Transport::AsyncHTTP.const_get(:ResponseMapper, false)
    ResponseBody = Dexpace::Transport::AsyncHTTP.const_get(:ResponseBody, false)
    EVENT = Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED

    def native_response(status: 200, headers: [], body: AsyncHTTPRecordingBody.new([], length: nil),
                        version: "HTTP/1.1")
      ::Protocol::HTTP::Response.new(version, status, ::Protocol::HTTP::Headers.new(headers), body)
    end

    def request(method: "GET")
      builder = Dexpace::Request.builder
      builder.method = method
      builder.url = "https://example.test/"
      builder.build
    end

    def map(native, request: self.request, logger: Dexpace::Instrumentation::Logger::NULL,
            head: false, on_release: nil)
      ResponseMapper.call(native, request: request, logger: logger, head: head,
                                  cancellation: Dexpace::Cancellation.none, on_release: on_release,)
    end
  end

  # The status and protocol (TRANSPORT-24) and the inbound header leniency (TRANSPORT-14).
  class HeadTest < DexpaceTestCase
    include ResponseMapperTestSupport

    test "TRANSPORT-24: a non-standard status inside the model's range maps, with a readable " \
         "body" do
      native = native_response(status: 520, body: AsyncHTTPRecordingBody.new(["hi".b], length: 2))
      response = map(native)

      assert_equal(520, response.status.code)
      assert_equal("http/1.1", response.protocol.wire)
      assert_equal("hi", response.body_string)
    end

    test "TRANSPORT-24: an HTTP/2 head maps to the model's http/2 protocol" do
      response = map(native_response(version: "HTTP/2"))

      assert_equal("http/2", response.protocol.wire)
    end

    # HTTP-10, HTTP-33, TRANSPORT-24: phase 10 widened Status to every code a status line can carry
    # and Protocol by HTTP/1.0, the two phase-1 questions 8a routed. Until then this test asserted
    # both heads raised; it is that pin, inverted.
    test "a vendor 999 status and an HTTP/1.0 head both map" do
      assert_equal(999, map(native_response(status: 999)).status.code)
      assert_equal("http/1.0", map(native_response(version: "HTTP/1.0")).protocol.wire)
    end

    test "a version the model does not know is InvalidArgumentError after the head (HTTP-33)" do
      assert_raises(Dexpace::InvalidArgumentError) { map(native_response(version: "HTTP/1.2")) }
    end

    test "TRANSPORT-14: a control byte in an inbound value is dropped, that header only, and " \
         "logged verbose by name" do
      sink = AsyncHTTPRecordingSink.new
      native = native_response(headers: [["x-ctl", "a\x01b"], ["x-normal", "n"]])
      response = map(native, logger: Dexpace::Instrumentation::Logger.build(sink: sink))

      assert_nil(response.headers["x-ctl"])
      assert_equal(["n"], response.headers["x-normal"])
      assert_equal(%i[debug], sink.severities(EVENT))
      assert_equal("x-ctl", sink.events(EVENT).first.payload["header"])
      assert_equal("malformed inbound header (TRANSPORT-14)",
                   sink.events(EVENT).first.payload["reason"],)
    end

    test "TRANSPORT-14: obs-text in an inbound value is preserved, and a repeated Set-Cookie " \
         "survives as two values" do
      native = native_response(headers: [["x-obs", "caf\xE9".b], ["set-cookie", "a=1"],
                                         ["set-cookie", "b=2"],])
      response = map(native)

      assert_equal(["caf\xE9".b], response.headers["x-obs"])
      assert_equal(["a=1", "b=2"], response.headers["set-cookie"])
    end

    test "TRANSPORT-14: an inbound name HeaderSyntax refuses is dropped rather than failing " \
         "the response, should one ever arrive" do
      native = native_response(headers: [["x-b\xE9d".b, "y"], %w[x-ok 1]])
      response = map(native)

      assert_equal(["1"], response.headers["x-ok"])
      assert_equal(1, response.headers.size)
    end
  end

  # The media type and length (TRANSPORT-27), which native body is handed on, and the three shapes
  # that carry none.
  class BodyTest < DexpaceTestCase
    include ResponseMapperTestSupport

    test "TRANSPORT-27: a malformed Content-Type downgrades to no media type rather than " \
         "failing the response, and the raw value still reaches the caller" do
      native = native_response(headers: [["content-type", "not a/;;media type"]])
      response = map(native)

      assert_nil(response.body.media_type)
      assert_equal(["not a/;;media type"], response.headers["content-type"])
    end

    test "a well-formed Content-Type reaches the body as its media type" do
      native = native_response(headers: [["content-type", "text/plain; charset=utf-8"]])

      assert_equal("text/plain; charset=utf-8", map(native).body.media_type.render)
    end

    test "TRANSPORT-27: an absent native length maps to the -1 sentinel, a known one exactly" do
      assert_equal(-1, map(native_response).body.content_length)
      known = native_response(body: AsyncHTTPRecordingBody.new(["hi".b], length: 2))

      assert_equal(2, map(known).body.content_length)
    end

    test "the body handed on is a ResponseBody over the native BODY, never the response" do
      native = native_response(body: AsyncHTTPRecordingBody.new(["hi".b], length: 2))
      response = map(native)

      assert_kind_of(ResponseBody, response.body)
      assert_same(native.body, response.body.instance_variable_get(:@native))
    end

    test "a response the library delivers with no body -- a 204 -- gets body nil and the release " \
         "hook runs at once" do
      released = 0
      response = map(native_response(status: 204, body: nil), on_release: -> { released += 1 })

      assert_nil(response.body)
      assert_equal(1, released)
    end

    test "a HEAD response carries no body whatever the head says, and its native body is closed" do
      native = AsyncHTTPRecordingBody.new([], length: 2)
      response = map(native_response(body: native), request: request(method: "HEAD"), head: true)

      assert_nil(response.body)
      assert_equal(1, native.close_count)
    end

    test "a Protocol::HTTP::Body::Head native body is treated as no body" do
      head = ::Protocol::HTTP::Body::Head.new(5)
      response = map(native_response(body: head))

      assert_nil(response.body)
    end

    test "the HTTP/1.1 reason phrase is carried, and its absence over HTTP/2 is nil" do
      with_reason = native_response
      with_reason.define_singleton_method(:reason) { "Custom Reason" }

      assert_equal("Custom Reason", map(with_reason).reason)
      assert_nil(map(native_response(version: "HTTP/2")).reason)
    end
  end
end
