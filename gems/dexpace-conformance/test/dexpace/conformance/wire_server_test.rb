# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"
require "net/http"

# Design §9.3's TCPServer fixture (8a's R7): a fresh server per test, never a shared one, so
# #connections is never order-dependent across tests (testing/4ef070df). Every wait is a blocking
# Queue#pop or a bounded join, never a sleep-poll; and #close closes every accepted socket and joins
# every handler thread, so a test that started a server leaks nothing DexpaceTestCase's teardown
# counts. Three nested classes under Metrics/ClassLength (6c's shape): what the server records,
# how it closes, and the plain client the suites drive it with.
module DexpaceConformanceWireServerTest
  WireServer = Dexpace::Conformance::WireServer
  Scripts = Dexpace::Conformance::Scripts

  # One GET through a plain client, built with an explicit nil proxy: Net::HTTP's `:ENV` default
  # reaches URI#find_proxy, whose upper-case-HTTP_PROXY warning the test base makes fatal (R2-1).
  module Fetch
    def get(port, path = "/")
      ::Net::HTTP.start("127.0.0.1", port, nil, nil, nil, nil) do |c|
        c.max_retries = 0
        c.request(::Net::HTTP::Get.new(path))
      end
    end
  end

  # What the server answers and records.
  class RecordingTest < DexpaceTestCase
    include Fetch

    test "starts on an ephemeral port and answers a scripted response" do
      server = WireServer.start(Scripts.fixed("hi"))

      res = get(server.port)

      assert_equal("200", res.code)
      assert_equal("hi", res.body)
      server.close
    end

    test "records requests and connections, independently of the client's own count" do
      server = WireServer.start(Scripts.fixed("x"))

      2.times { |i| get(server.port, "/p#{i}") }

      assert_equal(2, server.requests.size)
      assert_equal(2, server.connections)
      assert_equal(["/p0", "/p1"], server.requests.map(&:path))
      assert_equal("GET /p0 HTTP/1.1", server.requests.first.request_line)
      assert_equal("127.0.0.1:#{server.port}", server.requests.first.header("host"))
      assert_nil(server.requests.first.header("x-absent"))
      assert_equal("", server.requests.first.body)
      server.close
    end

    test "records a Content-Length request body and a chunked one, so an upload is observable" do
      server = WireServer.start(Scripts.fixed("x"))
      ::Net::HTTP.start("127.0.0.1", server.port, nil, nil, nil, nil) do |c|
        c.max_retries = 0
        fixed = ::Net::HTTP::Post.new("/fixed")
        fixed["Content-Type"] = "application/octet-stream"
        fixed.body = "caf\xE9".b
        c.request(fixed)
      end
      ::Net::HTTP.start("127.0.0.1", server.port, nil, nil, nil, nil) do |c|
        c.max_retries = 0
        chunked = ::Net::HTTP::Post.new("/chunked")
        chunked["Content-Type"] = "application/octet-stream"
        chunked["Transfer-Encoding"] = "chunked"
        source = Object.new
        chunks = ["ab".b, "cde".b]
        source.define_singleton_method(:readpartial) do |_n, outbuf = nil|
          raise ::EOFError if chunks.empty?

          chunk = chunks.shift
          outbuf ? outbuf.replace(chunk) : chunk
        end
        chunked.body_stream = source
        c.request(chunked)
      end

      assert_equal(["caf\xE9".b, "abcde".b], server.requests.map(&:body))
      assert_equal(Encoding::BINARY, server.requests.first.body.encoding)
      server.close
    end

    # The reader's Content-Length grammar is core's spelling for a pattern a wire value reaches
    # (PacingParsers, P6-61): a Regexp.new with its own timeout and a bounded run, the same bound
    # the adapter's own ResponseMapper applies. A raw socket is the one way to send the sixteen
    # digits Net::HTTP would refuse to frame.
    test "the request reader's length grammar has a timeout and admits at most fifteen digits" do
      grammar = WireServer.const_get(:RequestReader).const_get(:LENGTH)

      refute_nil(grammar.timeout, "a literal carries no per-pattern timeout")
      assert_in_delta(1.0, grammar.timeout, 0.0)
      assert_match(grammar, "9" * 15)
      refute_match(grammar, "9" * 16)
      server = WireServer.start(Scripts.fixed("x"))
      socket = ::TCPSocket.new("127.0.0.1", server.port)
      socket.write("POST /long HTTP/1.1\r\nHost: h\r\nContent-Length: #{"9" * 16}\r\n\r\nab")
      socket.close_write
      socket.read
      socket.close

      assert_equal([""], server.requests.map(&:body), "an over-long length frames no body")
      server.close
    end

    test "records closed_connections apart from connections; #await_closed_connection waits" do
      server = WireServer.start(Scripts.fixed("x"))

      get(server.port)

      assert(server.await_closed_connection) # a blocking Queue#pop, never a sleep-poll
      assert_equal(1, server.closed_connections)
      assert_equal(1, server.connections)
      server.close
    end

    test "#await_closed_connection with a bound answers nil when nothing finishes in time" do
      server = WireServer.start(Scripts.fixed("x"))

      took = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      answered = server.await_closed_connection(timeout: 0.1)
      took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - took

      assert_nil(answered)
      assert_operator(took, :<, 1.0)
      server.close
    end

    test "a script that raises does not crash the accept loop or strand later connections" do
      calls = 0
      server = WireServer.start(lambda do |conn, _head|
        calls += 1
        raise "first script failure" if calls == 1

        Scripts.write_response(conn, body: "recovered")
      end)

      assert_raises(::EOFError, ::Errno::ECONNRESET) { get(server.port) }
      assert_equal("recovered", get(server.port).body)
      server.close
    end
  end

  # How the server closes: bounded, idempotent, and waking everything it owns.
  class ClosingTest < DexpaceTestCase
    include Fetch

    test "the block form closes the server on any exit" do
      port = nil
      WireServer.start(Scripts.fixed("x")) do |server|
        port = server.port
      end

      assert_raises(Errno::ECONNREFUSED) { get(port) }
    end

    test "#close is idempotent and bounded" do
      server = WireServer.start(Scripts.fixed("x"))

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      server.close
      server.close
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

      assert_operator(elapsed, :<, 1.0)
    end

    # The teardown property every test in every suite relies on: a handler blocked on a socket --
    # hang_after_headers never answers -- is woken by #close closing the accepted socket, so the
    # thread ends and the test's own thread count is unchanged (DexpaceTestCase#teardown).
    test "#close wakes a handler blocked on its socket and joins it, promptly" do
      entered = ::Thread::Queue.new
      server = WireServer.start(Scripts.hang_after_headers(on_headers_written: lambda {
        entered.push(true)
      }))
      client = ::TCPSocket.new("127.0.0.1", server.port)
      client.write("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
      entered.pop
      threads_before_close = ::Thread.list.size

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      server.close
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      client.close

      assert_operator(elapsed, :<, 1.0)
      assert_operator(::Thread.list.size, :<, threads_before_close,
                      "the accept and handler threads ended",)
      assert_equal(1, server.closed_connections)
    end

    test "a waiter that outlives the server gets nil from #await_closed_connection, not a hang" do
      server = WireServer.start(Scripts.fixed("x"))
      waiter = ::Thread.new { server.await_closed_connection }

      server.close

      refute_nil(waiter.join(2), "the waiter did not wake within two seconds")
      assert_nil(waiter.value)
    end
  end

  # The plain client every suite of this gem drives the server with.
  class PlainClientTest < DexpaceTestCase
    include Fetch

    # R2-1: Fetch#get passes an explicit nil proxy, so an upper-case HTTP_PROXY on the host is
    # inert; with Net::HTTP's `:ENV` default, URI#find_proxy would warn about that spelling before
    # its loopback exemption, and DexpaceTestCase makes the warning fatal. The lower-case name is
    # cleared because find_proxy prefers it and warns only in its absence.
    test "R2-1: the plain client is inert to an upper-case HTTP_PROXY and reaches the server" do
      server = WireServer.start(Scripts.fixed("direct"))
      saved = { "HTTP_PROXY" => ENV.fetch("HTTP_PROXY", nil),
                "http_proxy" => ENV.fetch("http_proxy", nil), }
      ENV["HTTP_PROXY"] = "http://127.0.0.1:9"
      ENV["http_proxy"] = nil

      assert_equal("direct", get(server.port).body)
      assert_equal(1, server.connections)
    ensure
      saved&.each { |name, value| ENV[name] = value }
      server&.close
    end
  end
end
