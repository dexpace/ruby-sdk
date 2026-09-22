# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "zlib"
require "stringio"
require "dexpace/conformance"
require_relative "net_http_hermetic_proxy"

# The helpers the adapter's own suites share: a tracked WireServer per test, closed in teardown
# so nothing leaks past DexpaceTestCase's thread count; a request against that server; the one
# send primitive; and the scripts, clients and environment swaps the exchange tests need. The
# fixture is dexpace-conformance's own WireServer (design boundary 13), never a second one.
# Every including suite also runs under NetHTTPHermeticProxy, so a host's proxy variables never
# reach an owning adapter built here.
module AdapterFixtures
  include NetHTTPHermeticProxy

  def teardown
    @servers&.each(&:close)
    super
  end

  def wire(script)
    server = Dexpace::Conformance::WireServer.start(script)
    (@servers ||= []) << server
    server
  end

  # An explicit nil proxy, as the adapter's own ProxyRoute passes: Net::HTTP.new's `:ENV`
  # default reaches URI#find_proxy on `#start`, whose upper-case-HTTP_PROXY warning the test
  # base makes fatal (R2-1; test/support/net_http_warmup.rb has the mechanism). The two R17
  # controls that want `:ENV` build their own client and set http_proxy themselves.
  def client_for(port)
    client = ::Net::HTTP.new("127.0.0.1", port, nil, nil, nil, nil)
    client.max_retries = 0
    client
  end

  def request_for(server, path: "/")
    Dexpace::Request.build(method: "GET", url: "http://127.0.0.1:#{server.port}#{path}",
                           headers: Dexpace::Headers::EMPTY, body: nil,)
  end

  def settle(adapter, request, options = Dexpace::RequestOptions::EMPTY)
    adapter.call(request, options, Dexpace::Cancellation.none)
  end

  def elapsed
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  end

  # A chunked body of `count` one-byte chunks, each `delay` seconds apart; the wait is on the
  # socket, never a sleep the client could not interrupt.
  def trickle(count, delay)
    lambda do |conn, _head|
      conn.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
      count.times do |i|
        conn.wait_readable(delay) if i.positive?
        conn.write("1\r\n#{i}\r\n")
      end
      conn.write("0\r\n\r\n")
    end
  end

  # Two responses on ONE connection: the first request was read by the fixture, the second is
  # read here, so a client that keeps its connection alive is told apart from one that does not.
  # The first response says so (`close: false`): since phase 8c every scripted head announces
  # `Connection: close` by default, because the fixture closes after one exchange and a pooling
  # client re-used the closed connection otherwise; this is the one script that serves two.
  def keep_alive_twice(first, second)
    lambda do |conn, _head|
      Dexpace::Conformance::Scripts.write_response(conn, body: first, close: false)
      head = (+"").b
      head << conn.readpartial(4096) until head.include?("\r\n\r\n")
      Dexpace::Conformance::Scripts.write_response(conn, body: second)
    end
  end

  # TRANSPORT-29's proof: `threads` threads each sending `rounds` echo requests through one
  # adapter, every response matched to its own request; the mismatches, which must be none. A
  # raise inside a thread is recorded as a mismatch rather than aborting the join.
  def echo_mismatches(adapter, server, threads:, rounds:)
    mismatches = ::Thread::Queue.new
    workers = Array.new(threads) do |t|
      ::Thread.new do
        rounds.times do |i|
          path = "/#{t}-#{i}"
          body = settle(adapter, request_for(server, path: path)).body_string
          mismatches.push([path, body]) unless body == path
        rescue StandardError => error
          mismatches.push([path, error])
        end
      end
    end
    workers.each(&:join)
    found = []
    found << mismatches.pop until mismatches.empty?
    found
  end

  def gzip(string)
    io = StringIO.new((+"").b)
    writer = Zlib::GzipWriter.new(io)
    writer.write(string)
    writer.finish
    io.string
  end

  def with_env(pairs)
    saved = pairs.to_h { |name, _| [name, ENV.fetch(name, nil)] }
    pairs.each { |name, value| ENV[name] = value }
    yield
  ensure
    saved.each { |name, value| ENV[name] = value }
  end
end
