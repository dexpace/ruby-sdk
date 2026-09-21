# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/async_http_recording_body"
require_relative "../../../support/async_http_recording_sink"
require_relative "../../../support/async_http_holding_server"
require_relative "../../../support/async_http_reactor"
require "dexpace/transport/async_http"

# Dispatch steps 1 to 3 and 10, TRANSPORT-15/16/21/29 and ASYNC-22's structural half: the pivot
# is minted and returned before anything fallible runs, every pre-dispatch failure is delivered
# through it, ownership is a construction-time fact, and nothing per-call lives on the adapter.
# Three nested classes under Metrics/ClassLength (8a's shape): the constructions, the
# pre-dispatch settlements, and the deadline's tiers.
module DexpaceTransportAsyncHTTPAdapterTest
  # The request builder and the three doubles every class here shares: a client answering
  # inline, a forged request that met no builder, and a native response.
  module AdapterTestSupport
    include AsyncHTTPReactor

    AsyncHTTP = Dexpace::Transport::AsyncHTTP
    Adapter = Dexpace::Transport::AsyncHTTP::Adapter

    def request(url: "https://example.test/", headers: {}, method: "GET", body: nil)
      builder = Dexpace::Request.builder
      builder.method = method
      builder.url = url
      headers.each { |name, value| builder.header(name, value) }
      builder.body = body
      builder.build
    end

    # A client that answers inline, with no reactor turn, so a future comes back already settled.
    # Built with its behaviour up front: redefining a singleton method warns under -w.
    def fake_client(response = nil, retries: 0, on_pool_close: nil, &block)
      pool = Object.new
      pool.define_singleton_method(:close) { on_pool_close&.call }
      client = Object.new
      client.define_singleton_method(:retries) { retries }
      client.define_singleton_method(:pool) { pool }
      client.define_singleton_method(:call) { |native| block ? yield(native) : response }
      client
    end

    # A request-shaped object answering the four readers, carrying headers no Dexpace validation
    # has seen -- design §10.10's admitted hole, the wire-boundary re-validation's own subject.
    def forged_request(name, value)
      template = request
      headers = Object.new
      headers.define_singleton_method(:each_entry) { |&block| block.call(name, value) }
      forged = Object.new
      forged.define_singleton_method(:method) { template.method }
      forged.define_singleton_method(:url) { template.url }
      forged.define_singleton_method(:headers) { headers }
      forged.define_singleton_method(:body) { nil }
      forged
    end

    def native_response(body = AsyncHTTPRecordingBody.new(["ok".b], length: 2), status: 200)
      ::Protocol::HTTP::Response.new("HTTP/1.1", status, ::Protocol::HTTP::Headers.new, body)
    end
  end

  # .build, .using, .default, what each refuses, and the per-call statelessness ASYNC-22 rests on.
  class DexpaceTransportAsyncHTTPAdapterConstructionTest < DexpaceTestCase
    include AdapterTestSupport

    test ".build builds and owns its own clients; .using borrows a caller's client and never " \
         "closes it (TRANSPORT-15, XCUT-22)" do
      owning = AsyncHTTP.build

      assert_predicate(owning, :owned?)
      assert(Dexpace::AsyncTransport.conforms?(owning))
      owning.close

      closed = false
      client = fake_client(on_pool_close: -> { closed = true })
      borrowing = AsyncHTTP.using(client)

      refute_predicate(borrowing, :owned?)
      borrowing.close

      refute(closed, "a borrowing adapter must never close the caller's client")
      assert_predicate(borrowing, :closed?)
    end

    test ".using refuses a client whose retries is not zero, and never sets it (TRANSPORT-2, " \
         "P8-10)" do
      client = fake_client(retries: 3)

      error = assert_raises(Dexpace::InvalidArgumentError) { AsyncHTTP.using(client) }

      assert_match(/retries == 0/, error.message)
      assert_equal(3, client.retries)
    end

    test ".build validates timeout: at construction" do
      assert_raises(Dexpace::InvalidArgumentError) { AsyncHTTP.build(timeout: 0) }
      assert_raises(Dexpace::InvalidArgumentError) { AsyncHTTP.build(timeout: Float::INFINITY) }
      assert_raises(Dexpace::InvalidArgumentError) { AsyncHTTP.build(timeout: "1") }
      AsyncHTTP.build(timeout: 0.5).close
    end

    test "Adapter.new is private behind the two validating factories" do
      assert_raises(NoMethodError) { Adapter.new }
    end

    test "#close is idempotent, does not block, and reports closed" do
      adapter = AsyncHTTP.build
      adapter.close
      adapter.close

      assert_predicate(adapter, :closed?)
    end

    # ASYNC-22 / TRANSPORT-29: the adapter's own state is its clients, its settings and Closeable's
    # latch -- nothing per call lives on self.
    test "ASYNC-22: nothing per-call lives on the adapter" do
      adapter = AsyncHTTP.build
      ivars = adapter.instance_variables.sort

      assert_equal(
        %i[@client @clients @configuration @dexpace_close_mutex @dexpace_closed @dexpace_owned
           @drop_policy @logger @timeout].sort, ivars,
      )
    ensure
      adapter&.close
    end
  end

  # Every failure before the exchange starts settles through the future the caller already holds.
  class DexpaceTransportAsyncHTTPAdapterPreDispatchTest < DexpaceTestCase
    include AdapterTestSupport

    # The positive outcome, never assert_nothing_raised: what TRANSPORT-21 asserts is that the
    # future comes back already settled and carries the failure.
    test "TRANSPORT-21: calling outside a reactor settles a SeamError through the future, never " \
         "a synchronous raise (P8-39)" do
      adapter = AsyncHTTP.build

      future = adapter.call(request, nil, Dexpace::Cancellation.none)

      assert_predicate(future, :settled?)
      error = assert_raises(Dexpace::SeamError) { future.value }
      assert_match(/Async reactor/, error.message)
      assert_match(/Sync \{ \}/, error.message)
    ensure
      adapter&.close
    end

    test "TRANSPORT-21 / HTTP-17: a header HeaderSyntax rejects settles through the future " \
         "(the wire-boundary re-validation), and no client is touched" do
      calls = 0
      adapter = AsyncHTTP.using(fake_client { calls += 1 })
      forged = forged_request("X-Evil\r\nInjected", "v")

      Sync do
        future = adapter.call(forged, nil, Dexpace::Cancellation.none)

        assert_predicate(future, :settled?)
        assert_raises(Dexpace::InvalidArgumentError) { future.value }
      end

      assert_equal(0, calls)
    end

    test "TRANSPORT-21: a URL the endpoint cannot dispatch settles InvalidArgumentError through " \
         "the future -- never a connection to port 21" do
      adapter = AsyncHTTP.build

      Sync do
        future = adapter.call(request(url: "ftp://example.test/"), nil, Dexpace::Cancellation.none)

        assert_predicate(future, :settled?)
        error = assert_raises(Dexpace::InvalidArgumentError) { future.value }
        assert_match(/http and https only/, error.message)
      end
    ensure
      adapter&.close
    end

    test "a send after close settles ClosedError through the future on an owning adapter, and " \
         "a borrowing adapter stays usable after its own close (SEAM-15, boundary 17)" do
      owning = AsyncHTTP.build
      owning.close
      borrowing = AsyncHTTP.using(fake_client(native_response))
      borrowing.close

      Sync do
        failed = owning.call(request, nil, Dexpace::Cancellation.none)

        assert_predicate(failed, :settled?)
        assert_raises(Dexpace::ClosedError) { failed.value }
        assert_equal(200, borrowing.call(request, nil, nil).value.status.code)
      end
    end

    test "an already-cancelled token settles a CANCELLATION before anything is mapped or sent" do
      calls = 0
      sink = AsyncHTTPRecordingSink.new
      adapter = AsyncHTTP.using(fake_client { calls += 1 },
                                logger: Dexpace::Instrumentation::Logger.build(sink: sink),)
      source = Dexpace::Cancellation.source
      source.cancel(:already_gone)

      Sync do
        future = adapter.call(request(headers: { "Expect" => "100-continue" }), nil, source.token)

        assert_predicate(future, :settled?)
        assert_predicate(future, :cancelled?)
        assert_equal(:already_gone, assert_raises(Dexpace::CancelledError) { future.value }.reason)
      end

      assert_equal(0, calls)
      assert_empty(sink.entries, "the request was never mapped: no managed-header drop was logged")
    end

    test "a nil cancellation is the never-cancelled token (P8-57's shape)" do
      adapter = AsyncHTTP.using(fake_client(native_response))

      Sync { assert_equal(200, adapter.call(request, nil, nil).value.status.code) }
    end

    test "a native failure raised inline settles a retryable TransportError with the cause" do
      adapter = AsyncHTTP.using(fake_client { raise ::Errno::ECONNREFUSED })

      Sync do
        future = adapter.call(request, nil, nil)
        error = assert_raises(Dexpace::TransportError) { future.value }

        assert_predicate(error, :retryable?)
        assert_kind_of(::Errno::ECONNREFUSED, error.cause)
        assert_equal(:connect, error.phase)
      end
    end

    test "TRANSPORT-23: a successful dispatch never settles with a nil response" do
      adapter = AsyncHTTP.using(fake_client(native_response))

      Sync do
        response = adapter.call(request, nil, nil).value

        refute_nil(response)
        assert_instance_of(Dexpace::Response, response)
        assert_equal("ok", response.body_string)
      end
    end
  end

  # The deadline's three tiers, and the pair TRANSPORT-8 shares with TRANSPORT-4.
  class DexpaceTransportAsyncHTTPAdapterTimeoutTest < DexpaceTestCase
    include AdapterTestSupport

    # The three tiers: the call, the transport, the configuration chain (a bare number is
    # milliseconds, CFG-7), then the default -- read through the adapter's own private resolver
    # because the deadline is applied inside the exchange task.
    test "the deadline's three tiers resolve highest first, and the configured tier reads " \
         "REQUEST_TIMEOUT through #duration" do
      key = Dexpace::Configuration::Keys::REQUEST_TIMEOUT
      configuration = Dexpace::Configuration.build(overrides: { key => "250ms" })
      adapter = AsyncHTTP.build(timeout: 2.5, configuration: configuration)
      per_call = Dexpace::RequestOptions.builder.tap { |b| b.timeout = 0.75 }.build

      assert_in_delta(0.75, adapter.send(:resolve_timeout, per_call))
      assert_in_delta(2.5, adapter.send(:resolve_timeout, nil))
      configured = AsyncHTTP.build(configuration: configuration)

      assert_in_delta(0.25, configured.send(:resolve_timeout, Dexpace::RequestOptions::EMPTY))
      assert_in_delta(60.0, AsyncHTTP.build(configuration: Dexpace::Configuration.build)
                                     .send(:resolve_timeout, nil),)
      assert_in_delta(60.0, AsyncHTTP::DEFAULT_TIMEOUT_SECONDS)
    ensure
      adapter&.close
      configured&.close
    end

    test "TRANSPORT-4/TRANSPORT-8's pair: a deadline that expires with the head withheld settles " \
         "a RETRYABLE TransportError and leaves the token clear" do
      server = AsyncHTTPHoldingServer.new(hold: :head)
      adapter = AsyncHTTP.build
      source = Dexpace::Cancellation.source
      reactor_over(server) do |task|
        options = Dexpace::RequestOptions.builder.tap { |b| b.timeout = 0.1 }.build
        future = adapter.call(request(url: "http://127.0.0.1:#{server.port}/"), options,
                              source.token,)
        server.wait_for_accept
        error = assert_raises(Dexpace::TransportError) do
          future.value(deadline: Dexpace::Clock.deadline_in(5))
        end

        assert_predicate(error, :retryable?)
        assert_kind_of(::Async::TimeoutError, error.cause)
        refute_predicate(source.token, :cancelled?)
        refute_predicate(future, :cancelled?)
        assert_exchange_released(task)
      end
    ensure
      adapter&.close
      server&.close
    end
  end
end
