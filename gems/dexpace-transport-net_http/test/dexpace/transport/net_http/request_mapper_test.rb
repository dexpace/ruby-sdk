# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/net_http_recording_sink"
require "dexpace/transport/net_http"

# TRANSPORT-10, TRANSPORT-11, TRANSPORT-17, TRANSPORT-26, and the wire-boundary re-validation
# call site phase 1 postponed to the adapters (HTTP-17, HTTP-18, XCUT-18). 8a's R2, P8-2, P8-3,
# P8-4 and P8-13, at the unit level: what the native request carries after mapping, before any
# socket. RequestMapper is a private_constant, reached through const_get. Two nested classes
# under Metrics/ClassLength (6c's shape): the header policy, and the body with its framing.
module DexpaceTransportNetHttpRequestMapperTest
  NetHTTP = Dexpace::Transport::NetHTTP
  RequestMapper = NetHTTP.const_get(:RequestMapper)
  Events = Dexpace::Instrumentation::Events

  # The request and header builders both classes share.
  module Mapping
    def request(method: "GET", headers: Dexpace::Headers::EMPTY, body: nil,
                url: "http://127.0.0.1:1/a?b=1")
      Dexpace::Request.build(method: method, url: url, headers: headers, body: body)
    end

    def native(logger: Dexpace::Instrumentation::Logger::NULL, **)
      RequestMapper.build(request(**), logger: logger)
    end

    def headers(pairs)
      Dexpace::Headers.builder.tap { |b| pairs.each { |name, value| b.add(name, value) } }.build
    end

    def json_body(bytes)
      Dexpace::Body.bytes(bytes.b, media_type: Dexpace::MediaType.parse("application/json"))
    end
  end

  # R2 steps 1 to 4: re-validation, the managed drop set, the auto-stamps and decode_content.
  class HeadersTest < DexpaceTestCase
    include Mapping

    test "is a private_constant of NetHTTP" do
      assert_raises(NameError) { NetHTTP::RequestMapper }
    end

    test "P8-2: the three construction-time auto-stamps are deleted" do
      req = native

      refute(req.key?("Accept"))
      refute(req.key?("Accept-Encoding"))
      refute(req.key?("User-Agent"))
      assert_equal("GET", req.method)
      assert_equal("/a?b=1", req.path)
    end

    test "TRANSPORT-11 / P8-13: MANAGED_HEADERS is exactly the ten folded names" do
      assert_equal(%w[host content-length transfer-encoding connection keep-alive
                      proxy-connection te trailer upgrade expect], NetHTTP::MANAGED_HEADERS,)
      assert_predicate(NetHTTP::MANAGED_HEADERS, :frozen?)
      refute_includes(NetHTTP::MANAGED_HEADERS, "proxy-authorization")
    end

    test "TRANSPORT-11: managed headers are dropped even when the caller set them; the rest pass" do
      req = native(headers: headers("Host" => "bogus.example", "Content-Length" => "9999",
                                    "Connection" => "keep-alive", "X-Pass" => "kept",))

      refute(req.key?("Host"), "Net::HTTP fills Host from the URL only when the slot is empty")
      refute(req.key?("Content-Length"))
      refute(req.key?("Connection"))
      assert_equal("kept", req["X-Pass"])
    end

    test "TRANSPORT-11: each drop is logged once at VERBOSE under the shared event and fields" do
      sink = NetHTTPRecordingSink.new
      logger = Dexpace::Instrumentation::Logger.build(sink: sink)

      native(logger: logger, headers: headers("Host" => "bogus", "Expect" => "100-continue",
                                              "X-Pass" => "kept",),)

      drops = sink.events(Events::TRANSPORT_HEADER_DROPPED)

      assert_equal(2, drops.size)
      assert_equal(%i[debug debug], drops.map(&:severity))
      assert_equal(%w[Host Expect], drops.map { |entry| entry.payload["header"] })
      assert_equal(["transport managed header (TRANSPORT-11)"],
                   drops.map { |entry| entry.payload["reason"] }.uniq,)
    end

    test "proxy-authorization is NOT managed: a caller-set value passes through" do
      req = native(headers: headers("Proxy-Authorization" => "Basic x"))

      assert_equal("Basic x", req["Proxy-Authorization"])
    end

    test "a multi-valued caller header keeps both values" do
      two = headers("X-Multi" => "a").new_builder.tap { |b| b.add("X-Multi", "b") }.build

      assert_equal(%w[a b], native(headers: two).get_fields("X-Multi"))
    end

    # HTTP-17/HTTP-18: a duck-typed impostor that never met a builder -- the residual gap design
    # §10.10 admits -- is refused at the wire boundary before anything is copied.
    test "HTTP-17: a forged CRLF header NAME is refused before anything is copied" do
      forged = forged_request("X-Evil\r\nInjected", "v")

      error = assert_raises(Dexpace::InvalidArgumentError) do
        RequestMapper.build(forged, logger: Dexpace::Instrumentation::Logger::NULL)
      end
      assert_match(/X-Evil/, error.message)
    end

    test "HTTP-18: a forged CRLF header VALUE is refused before anything is copied" do
      forged = forged_request("X-Evil", "a\r\nInjected: b")

      assert_raises(Dexpace::InvalidArgumentError) do
        RequestMapper.build(forged, logger: Dexpace::Instrumentation::Logger::NULL)
      end
    end

    test "P8-3: decode_content is off unconditionally, whatever the caller's Accept-Encoding" do
      plain = native
      with_header = native(headers: headers("Accept-Encoding" => "gzip"))

      refute(plain.decode_content)
      refute(plain.key?("Accept-Encoding"))
      refute(with_header.decode_content)
      assert_equal("gzip", with_header["Accept-Encoding"])
    end

    private

    # Anything answering #method/#url/#headers/#body duck-types past the builder entirely
    # (design §10.10, P8); this one carries a header no Dexpace::Headers would ever have admitted.
    def forged_request(name, value)
      forged_headers = Object.new
      forged_headers.define_singleton_method(:each_entry) { |&blk| blk.call(name, value) }
      forged = Object.new
      forged.define_singleton_method(:method) { Dexpace::Method::GET }
      forged.define_singleton_method(:url) { Dexpace::URL.parse!("http://127.0.0.1:1/") }
      forged.define_singleton_method(:headers) { forged_headers }
      forged.define_singleton_method(:body) { nil }
      forged
    end
  end

  # R2 steps 5 to 8: Content-Type, framing and the body stream.
  class BodyTest < DexpaceTestCase
    include Mapping

    test "TRANSPORT-10 (a): an explicit Content-Type wins over the body's own media type" do
      req = native(method: "POST", headers: headers("content-type" => "text/plain"),
                   body: json_body("{}"),)

      assert_equal("text/plain", req["Content-Type"])
      assert_equal(1, req.get_fields("Content-Type").size)
    end

    test "TRANSPORT-10 (b): the body's media type is used when the caller set none" do
      req = native(method: "POST", body: json_body("{}"))

      assert_equal("application/json", req["Content-Type"])
    end

    test "P8-4: no header and no body media type falls back to octet-stream, body or not" do
      with_body = native(method: "POST", body: Dexpace::Body.bytes("x".b))
      without = native(method: "POST")

      assert_equal(NetHTTP::DEFAULT_CONTENT_TYPE, with_body["Content-Type"])
      assert_equal(NetHTTP::DEFAULT_CONTENT_TYPE, without["Content-Type"])
      assert_equal("application/octet-stream", NetHTTP::DEFAULT_CONTENT_TYPE)
    end

    test "a body-forbidden method gets no Content-Type and no body stream at all" do
      req = native(method: "GET")

      refute(req.key?("Content-Type"))
      assert_nil(req.body_stream)
      refute_predicate(req, :request_body_permitted?)
    end

    test "framing: Content-Length from a known-length body, never Transfer-Encoding" do
      req = native(method: "POST", body: Dexpace::Body.bytes("abc".b))

      assert_equal("3", req["Content-Length"])
      refute(req.key?("Transfer-Encoding"))
    end

    test "framing: Transfer-Encoding: chunked from an unknown-length body" do
      req = native(method: "POST", body: Dexpace::Body.chunked(["a".b, "b".b]))

      assert_equal("chunked", req["Transfer-Encoding"])
      refute(req.key?("Content-Length"))
    end

    test "TRANSPORT-17: the body is attached once, as a BufferedSource over the body's #each" do
      req = native(method: "POST", body: Dexpace::Body.bytes("abc".b))

      assert_kind_of(Dexpace::IO::BufferedSource, req.body_stream)
      assert_nil(req.body)
      assert_equal("abc".b, req.body_stream.readpartial(16))
    end

    test "TRANSPORT-26: a body-less POST attaches no stream; Net::HTTP sends Content-Length: 0" do
      req = native(method: "POST")

      assert_nil(req.body_stream)
      refute(req.key?("Content-Length"))
      assert_predicate(req, :request_body_permitted?)
    end

    test "response_body_permitted is false only for HEAD" do
      refute_predicate(native(method: "HEAD"), :response_body_permitted?)
      assert_predicate(native(method: "GET"), :response_body_permitted?)
      assert_predicate(native(method: "DELETE"), :response_body_permitted?)
    end
  end
end
