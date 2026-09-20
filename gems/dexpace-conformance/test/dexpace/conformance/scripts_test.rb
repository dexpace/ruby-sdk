# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"
require "net/http"

# The named response scripts, each driven through a real socket by a plain Net::HTTP so what a
# script puts on the wire is what a transport under test will meet. Every wire answers HTTP/1.1 on
# its status line: phase 1's Protocol.parse has no alias for "http/1.0" (8a plan, Task 17). Two
# nested classes under Metrics/ClassLength (6c's shape): the scripts that answer, and the ones
# that wait or fail.
module DexpaceConformanceScriptsTest
  WireServer = Dexpace::Conformance::WireServer
  Scripts = Dexpace::Conformance::Scripts

  # One GET through a plain client, with no transparent decompression.
  module Fetch
    def fetch(script, path: "/", &block)
      WireServer.start(script) do |server|
        ::Net::HTTP.start("127.0.0.1", server.port) do |c|
          c.max_retries = 0
          c.read_timeout = 5
          req = ::Net::HTTP::Get.new(path)
          req["Accept-Encoding"] = "identity"
          block ? c.request(req, &block) : c.request(req)
        end
      end
    end

    def get(server, path = "/")
      ::Net::HTTP.start("127.0.0.1", server.port) do |c|
        c.max_retries = 0
        c.request(::Net::HTTP::Get.new(path))
      end
    end
  end

  # The scripts that answer.
  class AnswersTest < DexpaceTestCase
    include Fetch

    test "fixed writes a Content-Length body with the given status and headers" do
      res = fetch(Scripts.fixed("hello", status: "201 Created", headers: { "X-A" => "1" }))

      assert_equal("201", res.code)
      assert_equal("Created", res.message)
      assert_equal("hello", res.body)
      assert_equal("5", res["Content-Length"])
      assert_equal("1", res["X-A"])
    end

    test "large writes large_body's deterministic, non-uniform bytes" do
      body = Scripts.large_body(70_000)

      assert_equal(70_000, body.bytesize)
      assert_equal("abcdefghijklmnopqrstuvwxyzab", body[0, 28])
      assert_equal(Encoding::BINARY, body.encoding)
      assert_equal(body, fetch(Scripts.large(70_000)).body.b)
    end

    test "redirect writes a raw 302 with a Location and no body" do
      res = fetch(Scripts.redirect("http://elsewhere.invalid/"))

      assert_equal("302", res.code)
      assert_equal("http://elsewhere.invalid/", res["Location"])
    end

    test "vendor_status writes any status code with a body" do
      res = fetch(Scripts.vendor_status(520, "vendor error"))

      assert_equal("520", res.code)
      assert_equal("vendor error", res.body)
    end

    test "malformed_headers writes a control byte, a non-ASCII name, obs-text and two cookies" do
      res = fetch(Scripts.malformed_headers)
      hash = res.to_hash

      assert_equal(["a\x01b".b], hash["x-ctl"])
      assert_equal(["caf\xE9".b], hash["x-obs"])
      assert_includes(hash.keys.map(&:b), "x-b\xE9d".b)
      assert_equal(["a=1", "b=2"], hash["set-cookie"])
      assert_equal("hi", res.body)
    end

    test "malformed_content_length writes a non-numeric Content-Length Net::HTTP itself rejects" do
      raw = nil
      error = assert_raises(::Net::HTTPHeaderSyntaxError) do
        fetch(Scripts.malformed_content_length) do |res|
          raw = res.to_hash["content-length"]
          res.read_body
        end
      end

      assert_equal(["abc"], raw)
      assert_match(/Content-Length/, error.message)
    end

    test "sequenced answers each connection with the next body and repeats the last" do
      WireServer.start(Scripts.sequenced("one", "two")) do |server|
        bodies = Array.new(3) { get(server).body }

        assert_equal(%w[one two two], bodies)
      end
    end

    test "echo_path answers with the request's own path, which TRANSPORT-29's matching needs" do
      assert_equal("/a-7", fetch(Scripts.echo_path, path: "/a-7").body)
    end

    test "write_response is the one primitive: status line, headers, Content-Length, body" do
      res = fetch(lambda { |conn, _head|
        Scripts.write_response(conn, status: "418 Teapot", body: "short")
      })

      assert_equal("418", res.code)
      assert_equal("short", res.body)
      assert_equal("5", res["Content-Length"])
      assert_equal("1.1", res.http_version)
    end
  end

  # The scripts that wait, hold or fail -- every wait on the socket, none on a sleep.
  class WaitsTest < DexpaceTestCase
    include Fetch

    def timing_out(script, read_timeout: 0.2)
      WireServer.start(script) do |server|
        assert_raises(::Net::ReadTimeout) do
          ::Net::HTTP.start("127.0.0.1", server.port) do |c|
            c.max_retries = 0
            c.read_timeout = read_timeout
            c.request(::Net::HTTP::Get.new("/before"))
          end
        end
        yield server
      end
    end

    test "dribble writes two chunks with a real gap between them" do
      arrivals = []
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      fetch(Scripts.dribble("aaaaa", "bbbbb", 0.3)) do |res|
        res.read_body do |chunk|
          arrivals << [chunk, Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0]
        end
      end

      assert_equal(%w[aaaaa bbbbb], arrivals.map(&:first))
      assert_operator(arrivals[0].last, :<, 0.2)
      assert_operator(arrivals[1].last, :>=, 0.25)
    end

    test "fixed with hold: true holds the connection until the peer closes it" do
      WireServer.start(Scripts.fixed("ok", hold: true)) do |server|
        socket = ::TCPSocket.new("127.0.0.1", server.port)
        socket.write("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
        socket.read(3) # the status line has started: the response is written

        assert_nil(server.await_closed_connection(timeout: 0.2), "held while the peer stays")
        socket.close

        assert_equal(1, server.await_closed_connection(timeout: 2))
      end
    end

    test "hang_before_headers reads the request, calls the hook once, and never answers at all" do
      hooked = 0
      seen = nil
      timing_out(Scripts.hang_before_headers(on_request_read: -> { hooked += 1 })) do |server|
        seen = server.requests.map(&:path)
      end

      assert_equal(1, hooked)
      assert_equal(["/before"], seen, "the request was read in full before the hook fired")
    end

    test "hang_after_headers writes a chunked head, calls the hook once, and never answers" do
      hooked = 0
      timing_out(Scripts.hang_after_headers(on_headers_written: -> { hooked += 1 })) { |_| nil }

      assert_equal(1, hooked)
    end

    test "fail_first_connection_then_succeed drops the first connection and answers the rest" do
      WireServer.start(Scripts.fail_first_connection_then_succeed("ok")) do |server|
        assert_raises(::EOFError, ::Errno::ECONNRESET) { get(server) }
        assert_equal("ok", get(server).body)
        assert_equal(2, server.connections)
      end
    end

    # Measured on net-http 0.4.1, 0.6.0 and 0.9.1: Net::HTTP#read_body reads a Content-Length
    # body with `ignore_eof = true`, so a truncated transfer is a SILENTLY short body at the
    # native level and never an EOFError -- which is why the adapter's short-transfer detection
    # is phase 3b's ResponseBody#write_to over the declared length, not anything Net::HTTP raises.
    test "truncated declares more than it sends; Net::HTTP itself returns the short body" do
      res = fetch(Scripts.truncated(declared_length: 10, actual_body: "abc"))

      assert_equal("10", res["Content-Length"])
      assert_equal("abc", res.body)
    end
  end
end
