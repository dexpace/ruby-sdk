# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
# The one file in this gem that opens a socket, so the one that parks net-http's Timeout thread
# (net-http < 0.7 connects through Timeout.timeout) outside every per-test thread count -- the
# repository's shared warm-up, required from here alone and never from the gem's test_helper
# (P8-62; the pool itself never touches a socket).
require_relative "../../../../../../test/support/net_http_warmup"
require "dexpace/async/thread"
# 8a's two gems, reachable through the root Gemfile's path-load of every gems/* directory under
# `bundle exec` (8a's own adapter_fixtures.rb reaches dexpace/conformance the same way). Nothing
# under this gem's lib/ names either: gates:clean_bundle, which cannot see test/, is unaffected.
require "dexpace/transport/net_http"
require "dexpace/conformance"

# The charter's convergence point 2: `Transport.async_over(net_http_transport, executor:
# thread_pool)` is where ASYNC-1, ASYNC-2, ASYNC-5, ASYNC-14, ASYNC-19 and ASYNC-20 first meet a
# REAL socket rather than a double, and where PIPE-33's met clauses are exercised end to end. Each
# ID is proven against PoolFakeTransport in bridge_test.rb; this suite proves the COMPOSITION,
# and it is this lane's because 8a landed first. The server is dexpace-conformance's WireServer
# on 127.0.0.1 with a scripted reply; every wait is bounded (Future#value(deadline:),
# await_closed_connection(timeout:)); the pool and the server are closed in teardown before the
# base's thread count runs.
#
# The three proxy keys are blanked through the configuration chain's override tier around every
# test (a local copy of 8a's NetHTTPHermeticProxy, never a reach into that gem's test/): every
# NetHTTP.build resolves its proxy through Dexpace.configuration, whose environment tier is the
# real ENV, so a host exporting HTTPS_PROXY would otherwise route the loopback fixture through it.
class ComposedTransportTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool
  WireServer = Dexpace::Conformance::WireServer
  Scripts = Dexpace::Conformance::Scripts
  NetHTTP = Dexpace::Transport::NetHTTP
  PROXY_KEYS = [
    Dexpace::Configuration::Keys::HTTP_PROXY,
    Dexpace::Configuration::Keys::HTTPS_PROXY,
    Dexpace::Configuration::Keys::NO_PROXY,
  ].freeze

  def setup
    super
    Dexpace.configure { |builder| PROXY_KEYS.each { |key| builder.override(key, "") } }
    @pool = Pool.build(size: 2, name: "composed")
  end

  def teardown
    @server&.close
    @pool.close
    Dexpace.reset_config!
    super
  end

  def start(script)
    @server = WireServer.start(script)
  end

  def url(path = "/") = "http://127.0.0.1:#{@server.port}#{path}"

  def request(path = "/")
    Dexpace::Request.build(method: :get, url: url(path), headers: Dexpace::Headers::EMPTY)
  end

  def within(seconds) = Dexpace::Clock.deadline_in(seconds)

  def adapter(timeout: 5) = NetHTTP.build(timeout: timeout)

  def async(transport = adapter) = Dexpace::Transport.async_over(transport, executor: @pool)

  # ASYNC-1, ASYNC-2, ASYNC-19 over the socket.
  class DeliveryTest < ComposedTransportTest
    test "ASYNC-1: a 200 over the wire is the exact Response the adapter built, on a worker" do
      start(Scripts.fixed("hello from the wire"))
      seen = ::Thread::Queue.new
      real = adapter
      recording = lambda do |req, opts, tok|
        seen << ::Thread.current.name
        real.call(req, opts, tok).tap { |response| seen << response }
      end

      response = async(recording).call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none) # rubocop:disable Layout/LineLength
        .value(deadline: within(10))

      assert_match(/\Acomposed worker [01]\z/, seen.pop)
      assert_same(response, seen.pop,
                  "the object the adapter built is the object the future delivered",)
      assert_kind_of(Dexpace::Response, response)
      assert_equal(200, response.status.code)
      assert_equal("hello from the wire", response.body_string)
      assert_equal("GET / HTTP/1.1", @server.requests.first.request_line)
      response.close
    end

    test "ASYNC-2: a scripted failure arrives as the exception the adapter raised, retryable" do
      start(Scripts.hang_after_headers)
      options = Dexpace::RequestOptions.build(timeout: 0.2, max_retries: nil, tags: {})
      future = async.call(request, options, Dexpace::Cancellation.none)
      response = future.value(deadline: within(10))

      # The head arrives; the per-call 0.2 s budget (ASYNC-19, the options object reaching the
      # adapter across the hop) then bounds the body read, which fails retryable, never hanging.
      error = assert_raises(Dexpace::TransportError) { response.body_string }

      assert_predicate(error, :retryable?)
      assert_equal(:read, error.phase)
      response.close
    end

    test "ASYNC-2: a refused connection fails the future with TransportError, never a raise" do
      listener = ::TCPServer.new("127.0.0.1", 0)
      port = listener.addr[1]
      listener.close
      refused = Dexpace::Request.build(method: :get, url: "http://127.0.0.1:#{port}/",
                                       headers: Dexpace::Headers::EMPTY,)

      future = async.call(refused, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)

      error = assert_raises(Dexpace::TransportError) { future.value(deadline: within(10)) }
      assert_equal(:connect, error.phase)
      assert_kind_of(::SystemCallError, error.cause)
    end

    test "ASYNC-2: submitting through a closed pool fails the future and never opens a socket" do
      start(Scripts.fixed("never"))
      @pool.close

      future = async.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)

      assert_raises(Dexpace::ClosedError) { future.value }
      assert_equal(0, @server.connections)
    end

    test "ASYNC-19: the caller's RequestOptions object reaches the adapter across the hop" do
      start(Scripts.fixed("options"))
      options = Dexpace::RequestOptions.build(timeout: 3.0, max_retries: nil, tags: { "t" => "1" })
      recorded = ::Thread::Queue.new
      real = adapter
      recording = lambda { |req, opts, tok|
        recorded << opts
        real.call(req, opts, tok)
      }

      async(recording).call(request, options,
                            Dexpace::Cancellation.none,).value(deadline: within(10)).close

      assert_same(options, recorded.pop)
    end
  end

  # ASYNC-5 and ASYNC-20 over the socket, and ASYNC-14 through sync_over.
  class CancellationTest < ComposedTransportTest
    # ASYNC-5's window over a real socket: the adapter has produced a pump-backed Response (the
    # head is in, the connection held open by the script until the peer closes it) and the worker
    # is held INSIDE the send before it returns; the cancel lands there, so the bridge's
    # check-after-send closes the orphan instead of delivering it, and the server sees the
    # connection released -- exactly once, by Closeable's latch, whoever loses the race.
    test "ASYNC-5: a cancel after the adapter produced a Response closes it, releasing the wire" do
      start(Scripts.fixed("orphan", hold: true))
      produced = ::Thread::Queue.new
      gate = ::Thread::Queue.new
      real = adapter
      windowed = lambda do |req, opts, tok|
        response = real.call(req, opts, tok)
        produced << response
        gate.pop
        response
      end
      source = Dexpace::Cancellation.source

      future = async(windowed).call(request, Dexpace::RequestOptions::EMPTY, source.token)
      response = produced.pop(timeout: 10)

      refute_nil(response)
      refute_predicate(response.body, :closed?)
      source.cancel(:window)
      gate << :go

      error = assert_raises(Dexpace::CancelledError) { future.value(deadline: within(10)) }

      assert_equal(:window, error.reason)
      assert_predicate(response.body, :closed?)
      assert_equal(1, @server.await_closed_connection(timeout: 5),
                   "the orphan's connection was never released",)
      assert_equal(1, @server.connections)
    end

    test "ASYNC-20: a cancel after delivery leaves the Response open and its body readable" do
      start(Scripts.fixed("still readable", hold: true))

      future = async.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
      response = future.value(deadline: within(10))
      future.cancel(:late)

      refute_predicate(future, :cancelled?)
      refute_predicate(response.body, :closed?)
      assert_equal("still readable", response.body_string)
      response.close

      assert_equal(1, @server.await_closed_connection(timeout: 5))
    end

    test "ASYNC-14: sync_over round-trips through the pool and the socket" do
      start(Scripts.fixed("round trip"))
      sync = Dexpace::AsyncTransport.sync_over(async)

      response = sync.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)

      assert_equal("round trip", response.body_string)
      assert_equal(1, @server.requests.size)
      response.close
    end

    test "ASYNC-14: a cancel under a blocked send surfaces through sync_over as CancelledError" do
      blocked = ::Thread::Queue.new
      start(Scripts.hang_before_headers(on_request_read: -> { blocked << :blocked }))
      source = Dexpace::Cancellation.source
      sync = Dexpace::AsyncTransport.sync_over(async)
      canceller = ::Thread.new do
        blocked.pop
        source.cancel(:interrupted)
      end

      error = assert_raises(Dexpace::CancelledError) do
        sync.call(request, Dexpace::RequestOptions::EMPTY, source.token)
      end
      canceller.join

      assert_equal(:interrupted, error.reason)
      refute_kind_of(::IOError, error)
    end
  end

  # PIPE-33 over the real adapter.
  class PipelineTest < ComposedTransportTest
    test "PIPE-33: a whole Pipeline.standard over the real adapter runs as one posted unit" do
      start(Scripts.sequenced("first", "second"))
      posts = ::Thread::Queue.new
      counting = Object.new
      pool = @pool
      counting.define_singleton_method(:post) do |&block|
        posts << :posted
        pool.post(&block)
      end
      pipeline = Dexpace::Pipeline.standard(adapter)

      response = Dexpace::Transport.async_over(pipeline, executor: counting)
        .call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
        .value(deadline: within(10))

      assert_equal("first", response.body_string)
      assert_equal(1, posts.size)
      response.close
    end
  end
end
