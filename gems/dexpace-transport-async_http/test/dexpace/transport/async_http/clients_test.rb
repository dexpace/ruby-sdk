# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/async_http_holding_server"
require_relative "../../../support/async_http_hermetic_configuration"
require_relative "../../../support/async_http_reactor"
require "dexpace/transport/async_http"

# The (reactor, origin) client map. concurrency-and-async/c0fab747 (smallest critical section)
# and /ee54cb68 (never hold a lock across I/O): #fetch's mutex guards a Hash read and a Hash
# insert and nothing else -- the client is built outside the lock, because building an https one
# loads the default certificate store from disk. Async::HTTP::Client.new opens no socket, so a
# client discarded by a lost insert race costs nothing. XCUT-14: the map is bounded at
# MAX_ORIGINS and drains back under it in a loop after each insert, retiring what it evicts.
# P8-37, as built: #close retires every pooled connection and never waits. Every configuration a
# case builds is hermetic -- the environment tier answers nothing -- so the default the limit case
# pins is the default and not the host's TRANSPORT_CONNECTION_LIMIT. Two nested classes under
# Metrics/ClassLength: what #fetch builds, and what #close and the cap release.
module DexpaceTransportAsyncHTTPClientsTest
  # The stand-in reactor and the two builders both classes share.
  module ClientsTestSupport
    include AsyncHTTPReactor
    include AsyncHTTPHermeticConfiguration

    Clients = Dexpace::Transport::AsyncHTTP.const_get(:Clients, false)
    AsyncHTTP = Dexpace::Transport::AsyncHTTP

    # A stand-in reactor: the key compares it by identity, never by class.
    REACTOR = Object.new

    def url(string) = Dexpace::URL.parse!(string)

    def clients(**)
      Clients.build(configuration: hermetic_configuration, **)
    end
  end

  # One client per (reactor, origin), built with the native retry loop off, the configured limit
  # and the caller's TLS context.
  class FetchTest < DexpaceTestCase
    include ClientsTestSupport

    test "fetch memoises one client per origin under one reactor" do
      map = clients

      first = map.fetch(url("https://example.test/a"), reactor: REACTOR)
      second = map.fetch(url("https://EXAMPLE.test:443/b"), reactor: REACTOR)
      third = map.fetch(url("https://example.test:8443/a"), reactor: REACTOR)

      assert_same(first, second)
      refute_same(first, third)
      assert_equal(2, map.size)
    ensure
      map&.close
    end

    # ASYNC-22's multi-thread clause, structurally: one async-http client cannot be shared across
    # reactors on different OS threads (its pool waits on a Thread::Mutex the scheduler cannot
    # interrupt, measured), so the key is the reactor too.
    test "the same origin under a different reactor is a different client" do
      map = clients

      first = map.fetch(url("http://example.test/"), reactor: REACTOR)
      second = map.fetch(url("http://example.test/"), reactor: Object.new)

      refute_same(first, second)
      assert_equal(2, map.size)
    ensure
      map&.close
    end

    test "every client disables the native retry loop (TRANSPORT-2, TRANSPORT-17, TRANSPORT-18)" do
      map = clients
      client = map.fetch(url("https://example.test/"), reactor: REACTOR)

      assert_equal(0, client.retries)
      assert_operator(::Async::HTTP::DEFAULT_RETRIES, :>, 0,
                      "the default is what makes this load-bearing",)
    ensure
      map&.close
    end

    test "the connection limit reads TRANSPORT_CONNECTION_LIMIT off the configuration, default 8" do
      map = clients
      client = map.fetch(url("https://example.test/"), reactor: REACTOR)

      assert_equal(8, map.limit)
      assert_equal(AsyncHTTP::DEFAULT_CONNECTION_LIMIT, client.pool.instance_variable_get(:@limit))
    ensure
      map&.close
    end

    test "a configured connection limit overrides the default, and an explicit keyword " \
         "overrides both" do
      key = Dexpace::Configuration::Keys::TRANSPORT_CONNECTION_LIMIT
      configuration = hermetic_configuration({ key => "3" })
      configured = Clients.build(configuration: configuration)
      explicit = Clients.build(configuration: configuration, connection_limit: 2)

      assert_equal(3, configured.fetch(url("https://example.test/"), reactor: REACTOR).pool
                                  .instance_variable_get(:@limit),)
      assert_equal(2, explicit.fetch(url("https://example.test/"), reactor: REACTOR).pool
                                .instance_variable_get(:@limit),)
    ensure
      configured&.close
      explicit&.close
    end

    test "a limit that is not a positive Integer is refused at construction" do
      assert_raises(Dexpace::InvalidArgumentError) { clients(connection_limit: 0) }
      assert_raises(Dexpace::InvalidArgumentError) { clients(connection_limit: "8") }
    end

    test "a caller's ssl_context reaches every https client verbatim" do
      context = ::OpenSSL::SSL::SSLContext.new
      map = clients(ssl_context: context)
      client = map.fetch(url("https://example.test/"), reactor: REACTOR)

      assert_same(context, client.endpoint.ssl_context)
    ensure
      map&.close
    end
  end

  # P8-37's close, XCUT-14's cap, the lock's extent, and a close under an open response.
  class ReleaseTest < DexpaceTestCase
    include ClientsTestSupport

    # P8-37 as built: Client#close waits on the pool and writes a Console warning; pool.close
    # alone still drains while any resource is busy. #close retires every resource FIRST.
    test "close retires every pooled resource and closes the pool, never through Client#close" do
      map = clients
      client = map.fetch(url("https://example.test/"), reactor: REACTOR)
      calls = []
      client.define_singleton_method(:close) { calls << :client_close }
      client.pool.define_singleton_method(:close) { calls << :pool_close }
      client.pool.define_singleton_method(:retire) { |resource| calls << [:retire, resource] }
      client.pool.define_singleton_method(:resources) { { a: 1, b: 1 } }

      map.close

      assert_equal([%i[retire a], %i[retire b], :pool_close], calls)
      assert_equal(0, map.size)
    end

    test "close is idempotent, and a fetch afterwards builds afresh" do
      map = clients
      first = map.fetch(url("https://example.test/"), reactor: REACTOR)

      map.close
      map.close

      refute_same(first, map.fetch(url("https://example.test/"), reactor: REACTOR))
    ensure
      map&.close
    end

    # XCUT-14 (MUST): "bounded by a hard cap and MUST drain back under the cap after each insert
    # using a loop (not a single pre-insert check-then-evict)". Both influences are present: a
    # caller's URLs choose origins and a server's redirect Location chooses new ones.
    test "XCUT-14: the map is bounded at MAX_ORIGINS and drains back to the cap after each " \
         "insert" do
      map = clients

      (AsyncHTTP::MAX_ORIGINS + 5).times { |i| map.fetch(url("https://h#{i}.test/"), reactor: REACTOR) }

      assert_equal(32, AsyncHTTP::MAX_ORIGINS)
      assert_equal(AsyncHTTP::MAX_ORIGINS, map.size)
    ensure
      map&.close
    end

    # The values own pools, so eviction that does not retire is a connection leak wearing a cap.
    test "XCUT-14: an evicted client's pool is retired and closed, never merely dropped" do
      map = clients
      first = map.fetch(url("https://h0.test/"), reactor: REACTOR)
      closed = false
      first.pool.define_singleton_method(:close) { closed = true }

      (AsyncHTTP::MAX_ORIGINS + 1).times { |i| map.fetch(url("https://evict#{i}.test/"), reactor: REACTOR) }

      assert(closed, "the evicted client's pool must be closed")
    ensure
      map&.close
    end

    # A reactor that has exited leaves its clients useless: they are the first victims when the
    # cap is reached, before the oldest live one.
    test "XCUT-14: a client whose reactor has closed is evicted before a live one" do
      map = clients
      dead = Object.new
      def dead.closed? = true
      stale = map.fetch(url("https://stale.test/"), reactor: dead)
      live = map.fetch(url("https://live.test/"), reactor: REACTOR)

      (AsyncHTTP::MAX_ORIGINS - 1).times { |i| map.fetch(url("https://fill#{i}.test/"), reactor: REACTOR) }

      refute_same(stale, map.fetch(url("https://stale.test/"), reactor: dead), "the stale one went")
      assert_same(live, map.fetch(url("https://live.test/"), reactor: REACTOR),
                  "the live one stayed",)
    ensure
      map&.close
    end

    # concurrency-and-async/ee54cb68: the source is the assertion, because no timing test can tell
    # a client built under the lock from one built beside it.
    test "the client is built outside the mutex: no Endpoints call inside a synchronize block" do
      source = File.read(File.expand_path("../../../../lib/dexpace/transport/async_http/clients.rb",
                                          __dir__,))
      blocks = source.scan(/synchronize do(.*?)^\s*end$/m).flatten +
               source.scan(/synchronize \{(.*?)\}/).flatten

      refute_empty(blocks)
      blocks.each { |block| refute_match(/Endpoints|Client\.new|build_client/, block) }
    end

    # Measured against a real connection: a client with one response open is released at once.
    test "close returns at once with a response still open, and the open read then fails" do
      server = AsyncHTTPHoldingServer.new(hold: :body)
      map = clients
      elapsed = nil
      read_error = nil
      reactor_over(server) do |task|
        client = map.fetch(url("http://127.0.0.1:#{server.port}/"), reactor: ::Fiber.scheduler)
        response = client.get("/")
        server.wait_for_accept
        response.body.read
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          task.with_timeout(2) { map.close }
        rescue ::Async::TimeoutError
          flunk("close waited on the open response instead of retiring it (P8-37)")
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        begin
          task.with_timeout(2) { response.body.read }
        rescue StandardError => error
          read_error = error
        end
      ensure
        # A close that waited would have left the connection busy, and the reactor cannot exit
        # while it is: releasing the response here is what lets that flunk surface.
        ::Dexpace.close_quietly(response) if response
      end

      assert_operator(elapsed, :<, 1.0, "close waited on the open response")
      refute_nil(read_error)
    ensure
      server&.close
    end
  end
end
