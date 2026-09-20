# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/net_http_recording_sink"
require "dexpace/transport/net_http"

# TRANSPORT-14, TRANSPORT-24, TRANSPORT-27 (8a's R4) at the unit level: native heads built
# directly, no socket, a two-method duck as the pump. ResponseMapper is a private_constant,
# reached through const_get. Two nested classes under Metrics/ClassLength (6c's shape): the head
# and its headers, then the body's length, type and absence.
module DexpaceTransportNetHttpResponseMapperTest
  NetHTTP = Dexpace::Transport::NetHTTP
  ResponseMapper = NetHTTP.const_get(:ResponseMapper)
  Events = Dexpace::Instrumentation::Events

  # The request, the scripted pump and the native head both classes build.
  module Heads
    def dexpace_request(method: "GET")
      Dexpace::Request.build(method: method, url: "http://127.0.0.1:1/",
                             headers: Dexpace::Headers::EMPTY, body: nil,)
    end

    # A pump over scripted chunks: #readpartial hands them out, then raises EOF.
    def pump_of(*chunks)
      pump = Object.new
      queue = chunks.map(&:b)
      pump.define_singleton_method(:readpartial) do |*_|
        raise ::EOFError if queue.empty?

        queue.shift
      end
      pump.define_singleton_method(:close) { @closed = true }
      pump.define_singleton_method(:closed?) { @closed ? true : false }
      pump
    end

    def ok(pairs = {})
      native = ::Net::HTTPOK.new("1.1", "200", "OK")
      pairs.each { |name, value| Array(value).each { |v| native.add_field(name, v) } }
      native
    end

    def build(native, pump: pump_of, request: dexpace_request, **)
      ResponseMapper.build(request: request, native: native, pump: pump, **)
    end
  end

  # The status line, the protocol and TRANSPORT-14's header filter.
  class HeadTest < DexpaceTestCase
    include Heads

    test "is a private_constant of NetHTTP" do
      assert_raises(NameError) { NetHTTP::ResponseMapper }
    end

    test "maps the status line and the protocol, and reads the body through the pump" do
      response = build(ok("Content-Length" => "2"), pump: pump_of("hi"))

      assert_equal(200, response.status.code)
      assert_equal("OK", response.reason)
      assert_equal(Dexpace::Protocol::HTTP_1_1, response.protocol)
      assert_equal(2, response.body.content_length)
      assert_equal("hi", response.body_string)
    end

    test "TRANSPORT-24: a vendor status maps totally, and a 499 too" do
      vendor = ::Net::HTTPResponse.send(:response_class, "520").new("1.1", "520", "Vendor")
      vendor["Content-Length"] = "0"
      client = ::Net::HTTPResponse.send(:response_class, "499").new("1.1", "499", "")
      client["Content-Length"] = "0"

      assert_equal(520, build(vendor).status.code)
      assert_equal(499, build(client).status.code)
    end

    test "TRANSPORT-14: a control-byte value is dropped; the body and remaining headers survive" do
      response = build(ok("X-Ctl" => "a\x01b", "X-Ok" => "fine", "Content-Length" => "2"),
                       pump: pump_of("hi"),)

      refute_includes(response.headers, "X-Ctl")
      assert_equal(["fine"], response.headers["X-Ok"])
      assert_equal("hi", response.body_string)
    end

    test "TRANSPORT-14: a non-ASCII NAME is dropped; the body still reads" do
      native = ok("Content-Length" => "2")
      native.instance_variable_get(:@header)["x-b\xE9d".b] = ["v"]

      response = build(native, pump: pump_of("hi"))

      assert_equal(%w[content-length], response.headers.names)
      assert_equal("hi", response.body_string)
    end

    test "TRANSPORT-14: obs-text in a value is preserved, never stripped" do
      response = build(ok("X-Obs" => "caf\xE9".b, "Content-Length" => "0"))

      assert_equal(["caf\xE9".b], response.headers["X-Obs"])
    end

    test "TRANSPORT-14: each drop is logged once at VERBOSE by NAME, under the shared event" do
      sink = NetHTTPRecordingSink.new
      logger = Dexpace::Instrumentation::Logger.build(sink: sink)

      build(ok("X-Ctl" => "a\x01b", "Content-Length" => "0"), logger: logger)

      drops = sink.events(Events::TRANSPORT_HEADER_DROPPED)

      assert_equal(1, drops.size)
      assert_equal(:debug, drops.first.severity)
      assert_equal("x-ctl", drops.first.payload["header"])
      assert_equal("malformed inbound header (TRANSPORT-14)", drops.first.payload["reason"])
      refute_match(/\x01/, drops.first.payload.inspect, "the value is never logged")
    end

    test "a multi-valued Set-Cookie survives as two values (verified fact 6: #to_hash, not #[])" do
      response = build(ok("Set-Cookie" => %w[a=1 b=2], "Content-Length" => "0"))

      assert_equal(%w[a=1 b=2], response.headers["Set-Cookie"])
    end

    test "an HTTP/1.0 head raises InvalidArgumentError: Protocol admits 1.1 and 2 only (HTTP-33)" do
      native = ::Net::HTTPOK.new("1.0", "200", "OK")
      native["Content-Length"] = "0"

      assert_raises(Dexpace::InvalidArgumentError) { build(native) }
    end
  end

  # R4's length parse, TRANSPORT-27's downgrades, and the responses that carry no body.
  class BodyTest < DexpaceTestCase
    include Heads

    test "TRANSPORT-27: a non-numeric Content-Length maps to the -1 sentinel and the body reads" do
      native = ok("Content-Length" => "abc")

      response = build(native, pump: pump_of("hi"))

      assert_equal(-1, response.body.content_length)
      assert_equal(["abc"], response.headers["Content-Length"], "the raw header reaches the caller")
      assert_nil(native["Content-Length"], "deleted from the NATIVE response before read_body")
      assert_equal("hi", response.body_string)
    end

    test "R4: negative, multi-valued and absent Content-Lengths map to -1; a good one is exact" do
      lengths = [ok("Content-Length" => "-4"), ok("Content-Length" => %w[3 3]), ok,
                 ok("Content-Length" => "7"),].map do |native|
        build(native, pump: pump_of("x")).body.content_length
      end

      assert_equal([-1, -1, -1, 7], lengths)
    end

    test "TRANSPORT-27: a malformed Content-Type downgrades to nil rather than raising" do
      response = build(ok("Content-Type" => "not a/;;media type", "Content-Length" => "0"))

      assert_nil(response.body.media_type)
      assert_equal(["not a/;;media type"], response.headers["Content-Type"])
    end

    test "a well-formed Content-Type is parsed, with its charset" do
      response = build(ok("Content-Type" => "text/plain; charset=utf-8", "Content-Length" => "0"))
      media = response.body.media_type

      assert_equal(%w[text plain], [media.type, media.subtype])
      assert_equal("utf-8", media.charset)
    end

    test "a 204 gets no body, and the pump is closed immediately" do
      pump = pump_of
      native = ::Net::HTTPNoContent.new("1.1", "204", "No Content")

      response = build(native, pump: pump)

      assert_nil(response.body)
      assert_predicate(pump, :closed?)
    end

    test "a HEAD response gets no body whatever its status class says, and the pump is closed" do
      pump = pump_of

      response = build(ok("Content-Length" => "99"), pump: pump, head: true,
                                                     request: dexpace_request(method: "HEAD"),)

      assert_nil(response.body)
      assert_equal(["99"], response.headers["Content-Length"])
      assert_predicate(pump, :closed?)
    end
  end
end
