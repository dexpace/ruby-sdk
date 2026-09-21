# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/async_http_recording_sink"
require "dexpace/transport/async_http"

# Dispatch steps 4 to 9. The wire-boundary re-validation phase 1 postponed to the adapters
# (HTTP-17, HTTP-18, XCUT-18): HeaderSyntax re-run immediately before dispatch, on every name
# and outbound value. TRANSPORT-11: the framing-header drop set, ten folded names, each a
# smuggling vector on this adapter (a caller-set host or content-length is APPENDED beside the
# library's own). TRANSPORT-12/13, P8-40: the RFC 7230 token predicate applied before dispatch,
# on both protocols, over the seventeen bytes HTTP-17 admits and the token set refuses. Two
# nested classes under Metrics/ClassLength: the header gates, and the rest of the mapping.
module DexpaceTransportAsyncHTTPRequestMapperTest
  # The request builder, the recording logger, the mapper call and the forged requests both
  # classes share.
  module RequestMapperTestSupport
    RequestMapper = Dexpace::Transport::AsyncHTTP.const_get(:RequestMapper, false)
    RequestBody = Dexpace::Transport::AsyncHTTP.const_get(:RequestBody, false)
    DropPolicy = Dexpace::Transport::AsyncHTTP::DropPolicy
    EVENT = Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED

    # Request::Builder exposes a writer per member plus #header(name, value) and no readers, so
    # headers are accumulated here rather than read back.
    def request(headers: {}, body: nil, method: "GET", url: "https://example.test/p?q=1")
      builder = Dexpace::Request.builder
      builder.method = method
      builder.url = url
      headers.each { |name, value| builder.header(name, value) }
      builder.body = body
      builder.build
    end

    def logger_and_sink
      sink = AsyncHTTPRecordingSink.new
      [Dexpace::Instrumentation::Logger.build(sink: sink), sink]
    end

    def map(request, logger: Dexpace::Instrumentation::Logger::NULL, policy: DropPolicy.build)
      RequestMapper.call(request, logger: logger, drop_policy: policy)
    end

    def names(native) = native.headers.to_a.map { |name, _| name.downcase }

    # A request-shaped object answering the four readers the seam contract types nothing about,
    # carrying headers no Dexpace validation has seen -- design §10.10's admitted hole.
    def forged_request(name, value)
      forged_request_with([name, value])
    end

    def forged_request_with(*pairs)
      template = request
      headers = Object.new
      headers.define_singleton_method(:each_entry) do |&block|
        pairs.each do |pair|
          block.call(*pair)
        end
      end
      forged = Object.new
      forged.define_singleton_method(:method) { template.method }
      forged.define_singleton_method(:url) { template.url }
      forged.define_singleton_method(:headers) { headers }
      forged.define_singleton_method(:body) { nil }
      forged
    end
  end

  # The re-validation, the framing drop set and the token predicate: what never reaches the wire.
  class HeaderGatesTest < DexpaceTestCase
    include RequestMapperTestSupport

    test "HTTP-17: a header name HeaderSyntax rejects raises before anything is mapped" do
      forged = forged_request("X-Evil\r\nInjected", "v")

      error = assert_raises(Dexpace::InvalidArgumentError) { map(forged) }

      assert_match(/HTTP-17/, error.message)
    end

    test "HTTP-18: an outbound value HeaderSyntax rejects raises before anything is mapped" do
      forged = forged_request("X-Evil", "a\r\nInjected: 1")

      error = assert_raises(Dexpace::InvalidArgumentError) { map(forged) }

      assert_match(/HTTP-18/, error.message)
    end

    test "TRANSPORT-11: the ten framing headers are dropped and logged verbose, " \
         "case-insensitively" do
      logger, sink = logger_and_sink
      framing = Dexpace::Transport::AsyncHTTP::FRAMING_HEADERS.map.with_index do |name, index|
        [index.even? ? name.upcase : name.capitalize, "v"]
      end.to_h
      native = map(request(headers: framing.merge("X-Keep" => "yes")), logger: logger)

      assert_equal(["x-keep"], names(native))
      assert_equal(%i[debug] * 10, sink.severities(EVENT))
      assert_equal("transport framing header (TRANSPORT-11)",
                   sink.events(EVENT).first.payload["reason"],)
    end

    test "TRANSPORT-11: the drop set is exactly the ten folded names the charter fixes, and " \
         "proxy-authorization is not among them" do
      expected = %w[host content-length transfer-encoding connection keep-alive proxy-connection te
                    trailer upgrade expect]

      assert_equal(expected, Dexpace::Transport::AsyncHTTP::FRAMING_HEADERS)
      assert_predicate(Dexpace::Transport::AsyncHTTP::FRAMING_HEADERS, :frozen?)
      native = map(request(headers: { "Proxy-Authorization" => "Basic abc" }))

      assert_includes(names(native), "proxy-authorization")
    end

    test "TRANSPORT-12/13, P8-40: a model-valid non-token name is dropped, reported through the " \
         "policy, and every other header still maps" do
      logger, sink = logger_and_sink
      req = request(headers: { "X-Bad:Name" => "v", "X-Normal" => "n" })

      assert(Dexpace::HeaderSyntax.valid_name?("X-Bad:Name"), "the model admits it (HTTP-17)")
      refute(Dexpace::HeaderSyntax.token?("X-Bad:Name"), "the wire grammar refuses it")
      native = map(req, logger: logger)

      assert_equal(["x-normal"], names(native))
      assert_equal(%i[warn], sink.severities(EVENT))
      assert_equal("X-Bad:Name", sink.events(EVENT).first.payload["header"])
      assert_match(/TRANSPORT-12/, sink.events(EVENT).first.payload["reason"])
    end

    # The antecedent, measured: exactly the bytes HTTP-17 admits and RFC 7230's tchar refuses.
    test "TRANSPORT-12: the seventeen bytes the model admits and the token grammar refuses" do
      admitted = (0x21..0x7E).map(&:chr).select do |byte|
        Dexpace::HeaderSyntax.valid_name?("x#{byte}") && !Dexpace::HeaderSyntax.token?("x#{byte}")
      end

      assert_equal('"(),/:;<=>?@[\]{}'.chars, admitted)
      admitted.each do |byte|
        native = map(request(headers: { "x#{byte}" => "v", "X-Ok" => "1" }))

        assert_equal(["x-ok"], names(native), byte.inspect)
      end
    end
  end

  # Content-Type's three cases, the body, the target and authority, and a name's spelling.
  class MappingTest < DexpaceTestCase
    include RequestMapperTestSupport

    test "TRANSPORT-10: an explicit Content-Type wins over the body's own media type" do
      body = Dexpace::Body.string("{}", media_type: Dexpace::MediaType.parse("application/json"))
      native = map(request(headers: { "Content-Type" => "text/plain" }, body: body, method: "POST"))

      assert_equal([["Content-Type", "text/plain"]],
                   native.headers.to_a.select { |name, _| name.downcase == "content-type" },)
    end

    test "TRANSPORT-10: with no explicit header, the body's own media type is emitted" do
      body = Dexpace::Body.string("{}", media_type: Dexpace::MediaType.parse("application/json"))
      native = map(request(body: body, method: "POST"))

      assert_equal([["content-type", "application/json"]],
                   native.headers.to_a.select { |name, _| name.downcase == "content-type" },)
    end

    test "TRANSPORT-10: no header and no media type invents nothing -- async-http stamps no " \
         "default of its own, unlike Net::HTTP" do
      native = map(request(body: Dexpace::Body.bytes("raw".b), method: "POST"))

      refute_includes(names(native), "content-type")
    end

    test "a body-less request maps to a nil native body, and a body-forbidden method attaches " \
         "none" do
      assert_nil(map(request(method: "POST")).body)
      assert_nil(map(request(method: "GET")).body)
    end

    test "a body maps to a RequestBody the library pulls; framing is never copied from a header" do
      native = map(request(headers: { "Content-Length" => "999" },
                           body: Dexpace::Body.bytes("abc".b), method: "POST",))

      assert_kind_of(RequestBody, native.body)
      assert_equal(3, native.body.length)
      refute_includes(names(native), "content-length")
    end

    test "the native request carries the scheme, the authority with a non-default port, the " \
         "method token and the request target with its query" do
      native = map(request(url: "https://example.test:8443/a%20b?q=1", method: "POST"))
      default = map(request(url: "http://example.test/"))

      assert_equal("https", native.scheme)
      assert_equal("example.test:8443", native.authority)
      assert_equal("POST", native.method)
      assert_equal("/a%20b?q=1", native.path)
      assert_equal("example.test", default.authority)
    end

    test "a caller's spelling of a name survives as spelled, and a duplicate name twice" do
      native = map(request(headers: { "X-MiXeD-CaSe" => "1" }))
      twice = map(forged_request_with(%w[Set-Cookie a], %w[Set-Cookie b]))

      assert_includes(native.headers.to_a, %w[X-MiXeD-CaSe 1])
      assert_equal(2, twice.headers.to_a.count { |name, _| name == "Set-Cookie" })
    end
  end
end
