# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "stringio"
require_relative "../../../test_helper"
require_relative "../../../support/async_http_server_fixture"
require_relative "../../../support/async_http_holding_server"
require_relative "../../../support/async_http_recording_sink"
require_relative "../../../support/async_http_reactor"
require "dexpace/transport/async_http"

# TRANSPORT-23 (never a null success), ASYNC-22 (many concurrent calls through one adapter, no
# cross-talk -- over HTTP/1.1's pool AND over one multiplexed HTTP/2 connection, the property the
# gem exists to prove), ASYNC-7's reactor-backed half of §3.3's contrast (a cancellation aborts a
# blocked read at the next scheduler checkpoint), the composed AsyncPipeline over the real
# adapter, and the stderr the adapter's whole lifecycle leaves clean: Console's default output
# would write JSON warnings there, and nothing in this SDK may.
#
# Three ways to HTTP/2 through the adapter, each what a caller would do: an OWNING adapter reaches
# it over TLS by ALPN (`AsyncHTTP.build(ssl_context:)` trusting the fixture's certificate --
# plaintext prior-knowledge h2 is not something an adapter can know from a URL, and the plaintext
# client defaults to HTTP/1.1), and a BORROWING adapter over a caller's own prior-knowledge client.
# Two nested classes under Metrics/ClassLength: the deliveries, and the composition around them.
module DexpaceTransportAsyncHTTPDispatchConformanceTest
  # The request builder, the bounded wait, the adapter per fixture flavour and the pool probe both
  # classes share.
  module DispatchTestSupport
    include AsyncHTTPReactor

    AsyncHTTP = Dexpace::Transport::AsyncHTTP
    BOUND = 5.0

    def request(url, headers: {})
      builder = Dexpace::Request.builder
      builder.url = url
      headers.each { |name, value| builder.header(name, value) }
      builder.build
    end

    def value_within(future)
      future.value(deadline: Dexpace::Clock.deadline_in(BOUND))
    end

    # The adapter a caller builds for each fixture flavour.
    def adapter_for(server, variant)
      case variant
      when :http1 then AsyncHTTP.build
      when :tls then AsyncHTTP.build(ssl_context: server.client_endpoint.ssl_context)
      else AsyncHTTP.using(::Async::HTTP::Client.new(server.client_endpoint, retries: 0))
      end
    end

    def pool_size(adapter, server)
      clients = adapter.instance_variable_get(:@clients)
      by_key = clients.instance_variable_get(:@by_key)
      key = by_key.keys.find { |k| k.origin[2] == server.client_endpoint.url.port }
      by_key.fetch(key).pool.size
    end
  end

  # TRANSPORT-23 through a real reactor, and ASYNC-22 over three protocol shapes and two threads.
  class DeliveryTest < DexpaceTestCase
    include DispatchTestSupport

    test "TRANSPORT-23: a successful dispatch through a real reactor never settles with a nil " \
         "response -- over HTTP/1.1, TLS-negotiated HTTP/2 and prior-knowledge HTTP/2 alike" do
      Sync do
        { http1: "http/1.1", tls: "http/2", plaintext: "http/2" }.each do |variant, wire|
          server = AsyncHTTPServerFixture.public_send(variant) { |_req| [200, [], ["ok"]] }
          adapter = adapter_for(server, variant)
          response = value_within(adapter.call(request(server.url), nil, nil))

          refute_nil(response)
          assert_instance_of(Dexpace::Response, response)
          assert_equal("ok", response.body_string)
          assert_equal(wire, response.protocol.wire, variant.to_s)
          adapter.close
          server.close
        end
      end
    end

    # ASYNC-22: sixteen, because the requirement's own word is "many" and the design's probe ran
    # eight. Over HTTP/1.1 the pool serves them within its bound; over HTTP/2 ONE connection
    # multiplexes all sixteen streams, which is the property a thread pool cannot have.
    { http1: AsyncHTTP::DEFAULT_CONNECTION_LIMIT, tls: 1 }.each do |variant, connections|
      test "ASYNC-22 over #{variant}: sixteen concurrent calls through one owning adapter each " \
           "resolve to their own response with no cross-talk, over at most #{connections} " \
           "connection(s)" do
        Sync do
          server = AsyncHTTPServerFixture.public_send(variant) do |req|
            [200, [], [req.headers["x-nonce"].to_s]]
          end
          adapter = adapter_for(server, variant)
          futures = Array.new(16) do |i|
            adapter.call(request(server.url, headers: { "X-Nonce" => i.to_s }), nil, nil)
          end

          bodies = futures.map { |future| value_within(future).body_string }

          assert_equal((0...16).map(&:to_s), bodies)
          assert_equal(16, server.received.size)
          assert_operator(pool_size(adapter, server), :<=, connections)
          assert_operator(pool_size(adapter, server), :>=, 1)
        ensure
          adapter&.close
          server&.close
        end
      end
    end

    # ASYNC-22's multi-thread clause, structurally: two OS threads, each its own reactor, each
    # driving one shared adapter -- the shape that never completed through one shared client.
    test "ASYNC-22 across threads: two reactors on two threads share one adapter and each gets " \
         "its own client" do
      server = nil
      adapter = AsyncHTTP.build
      Sync do
        server = AsyncHTTPServerFixture.http1 { |req| [200, [], [req.headers["x-nonce"].to_s]] }
        url = server.url
        results = Array.new(2) do |thread_index|
          ::Thread.new do
            Sync do
              Array.new(5) do |i|
                nonce = "#{thread_index}-#{i}"
                [nonce, value_within(adapter.call(request(url, headers: { "X-Nonce" => nonce }),
                                                  nil, nil,)).body_string,]
              end
            end
          end
        end.map(&:value)

        results.flatten(1).each { |nonce, body| assert_equal(nonce, body) }
        assert_equal(2, adapter.instance_variable_get(:@clients).size)
      ensure
        server&.close
      end
    ensure
      adapter&.close
    end
  end

  # ASYNC-7's scheduler-checkpoint cancellation, the standard async pipeline over the adapter, and
  # the clean stderr.
  class CompositionTest < DexpaceTestCase
    include DispatchTestSupport

    # ASYNC-7, this gem's own half of the cross-adapter contrast §3.3 fixes: "the reactor-backed
    # ones abort at the next scheduler checkpoint." Measured as a bound, not compared against a
    # README string: the server never releases, so a read left to finish would wait for the
    # fixture's own teardown; the cancellation reaches it well before.
    test "ASYNC-7: a cancellation aborts a blocked read at the next scheduler checkpoint, well " \
         "under the time the response would have taken to arrive" do
      server = AsyncHTTPHoldingServer.new(hold: :head)
      adapter = AsyncHTTP.build
      source = Dexpace::Cancellation.source

      reactor_over(server) do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil, source.token)
        server.wait_for_accept
        source.cancel(:abort_now)
        assert_raises(Dexpace::CancelledError) { value_within(future) }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        assert_operator(elapsed, :<, 1.0)
      end
    ensure
      adapter&.close
      server&.close
    end

    # The composed shape a generated client runs: phase 4c's AsyncPipeline.standard over the real
    # adapter, driven from inside the caller's reactor.
    test "AsyncPipeline.standard over the real adapter delivers a response through the future" do
      Sync do
        server = AsyncHTTPServerFixture.http1 { |_req| [200, [%w[x-served 1]], ["piped"]] }
        adapter = AsyncHTTP.build
        pipeline = Dexpace::AsyncPipeline.standard(adapter, redirect: :unsupported)

        response = value_within(pipeline.call(request(server.url), Dexpace::RequestOptions::EMPTY,
                                              Dexpace::Cancellation.none,))

        assert_equal("piped", response.body_string)
        assert_equal(["1"], response.headers["x-served"])
      ensure
        adapter&.close
        server&.close
      end
    end

    # A whole lifecycle -- build, a request over HTTP/1.1 and over TLS HTTP/2, an unread close over
    # HTTP/2, a cancellation, close -- writes nothing to stderr: Console's JSON output and the
    # runtime's warnings alike. The runner's stderr scan reads only `warning:`; this reads all of
    # it.
    test "a full adapter lifecycle leaves stderr clean" do
      original = $stderr
      captured = StringIO.new
      $stderr = captured
      begin
        server = AsyncHTTPHoldingServer.new(hold: :head)
        source = Dexpace::Cancellation.source
        reactor_over(server) do
          h1 = AsyncHTTPServerFixture.http1 { |_req| [200, [], ["ok"]] }
          h2 = AsyncHTTPServerFixture.tls { |_req| [200, [], ["ok"]] }
          adapter = AsyncHTTP.build(ssl_context: h2.client_endpoint.ssl_context)
          value_within(adapter.call(request(h1.url), nil, nil)).close
          value_within(adapter.call(request(h2.url), nil, nil)).close
          future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil, source.token)
          server.wait_for_accept
          source.cancel(:lifecycle)
          assert_raises(Dexpace::CancelledError) { value_within(future) }
          adapter.close
          h1.close
          h2.close
        end
        server.close
      ensure
        $stderr = original
      end

      assert_empty(captured.string)
    end
  end
end
