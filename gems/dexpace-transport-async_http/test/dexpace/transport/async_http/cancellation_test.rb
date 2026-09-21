# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/async_http_holding_server"
require_relative "../../../support/async_http_recording_body"
require_relative "../../../support/async_http_reactor"
require "dexpace/transport/async_http"

# R13: "writes a test asserting the close ran on a cancellation specifically -- not only on a
# timeout, which is the test a correct-looking wrong implementation passes." The cancellation
# cases and the timeout pair (adapter_test.rb) are kept in this gem so neither can be deleted
# without the other being missed. TRANSPORT-7: cancel an in-flight future and the native call is
# cancelled. TRANSPORT-9: a native response obtained after the pivot was cancelled is closed,
# never delivered. ASYNC-6: both directions -- the token and the future reach the exchange, and
# the exchange's own end settles the pivot. Deterministic, per the design's three techniques:
# the SERVER decides when the client is blocked (AsyncHTTPHoldingServer#wait_for_accept), a
# Cancellation::Source the test owns fires the cancel, and the assertions are on counts and
# outcomes, never on elapsed time. Every wait is bounded, because "hangs" is the failure mode.
# Two nested classes under Metrics/ClassLength: the cancel reaching a blocked exchange, and the
# cancel around and after a delivery.
module DexpaceTransportAsyncHTTPCancellationTests
  # The request builder and the bounded wait both classes share.
  module CancellationTestSupport
    include AsyncHTTPReactor

    AsyncHTTP = Dexpace::Transport::AsyncHTTP
    BOUND = 5.0

    def request(url)
      builder = Dexpace::Request.builder
      builder.url = url
      builder.build
    end

    def value_within(future, cancellation: nil)
      future.value(cancellation: cancellation, deadline: Dexpace::Clock.deadline_in(BOUND))
    end
  end

  # A cancel -- the token's, the future's, one from a foreign thread -- reaching an exchange blocked
  # on the head.
  class DexpaceTransportAsyncHTTPCancellationTest < DexpaceTestCase
    include CancellationTestSupport

    # TRANSPORT-7 / ASYNC-6 (token -> exchange): cancelling the token aborts a native call blocked
    # waiting for the head and settles a terminal, non-retryable cancellation.
    test "TRANSPORT-7/ASYNC-6: cancelling the token aborts a blocked native call and settles a " \
         "terminal, non-retryable CancelledError with the token's reason" do
      server = AsyncHTTPHoldingServer.new(hold: :head)
      adapter = AsyncHTTP.build
      source = Dexpace::Cancellation.source

      reactor_over(server) do |task|
        future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil, source.token)
        server.wait_for_accept # provably blocked waiting for the head; no sleep needed
        source.cancel(:token_cancelled)

        error = assert_raises(Dexpace::CancelledError) { value_within(future) }
        assert_equal(:token_cancelled, error.reason)
        assert_predicate(future, :cancelled?)
        refute_respond_to(error, :retryable?)
        assert_exchange_released(task)
      end
    ensure
      adapter&.close
      server&.close
    end

    # ASYNC-6 (future -> exchange): cancelling the FUTURE itself, not the token, must also reach
    # the in-flight exchange -- the direction only an async transport can satisfy for real.
    test "ASYNC-6: cancelling the future reaches the native exchange and settles it cancelled" do
      server = AsyncHTTPHoldingServer.new(hold: :head)
      adapter = AsyncHTTP.build

      reactor_over(server) do |task|
        future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil, nil)
        server.wait_for_accept
        future.cancel(:future_cancelled)

        error = assert_raises(Dexpace::CancelledError) { value_within(future) }
        assert_equal(:future_cancelled, error.reason)
        assert_predicate(future, :cancelled?)
        assert_exchange_released(task)
      end
    ensure
      adapter&.close
      server&.close
    end

    # The bridge as built: the token's hook runs on the CANCELLER's thread, where Fiber.scheduler
    # is nil and Async::Task#cancel raises NoMethodError, so the cancel is marshalled through a
    # queue to a watcher task on the reactor. The conformance suite's TRANSPORT-3 assertion cancels
    # from an OS thread exactly like this.
    test "a token cancelled from a foreign OS thread still reaches the exchange, promptly" do
      server = AsyncHTTPHoldingServer.new(hold: :head)
      adapter = AsyncHTTP.build
      source = Dexpace::Cancellation.source
      canceller = nil

      reactor_over(server) do |task|
        future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil, source.token)
        server.wait_for_accept
        canceller = ::Thread.new { source.cancel(:from_another_thread) }

        error = assert_raises(Dexpace::CancelledError) { value_within(future) }
        assert_equal(:from_another_thread, error.reason)
        assert_exchange_released(task)
      end
      canceller.join
    ensure
      adapter&.close
      server&.close
    end
  end

  # A cancel racing the delivery (TRANSPORT-9), landing after it (ASYNC-20), or reaching a blocked
  # body read (TRANSPORT-7's body path).
  class DexpaceTransportAsyncHTTPCancellationDeliveryTest < DexpaceTestCase
    include CancellationTestSupport

    # TRANSPORT-9: the token is cancelled WHILE the native call is in flight and the native call
    # returns a response anyway -- the exact race the requirement names. Check-after-resume sees
    # the token before the response is delivered, and the response is closed exactly once.
    test "TRANSPORT-9: a native response obtained after the token was cancelled mid-flight is " \
         "closed exactly once, never delivered" do
      native = AsyncHTTPRecordingBody.new(["late".b], length: 4)
      source = Dexpace::Cancellation.source
      client = Object.new
      client.define_singleton_method(:retries) { 0 }
      client.define_singleton_method(:pool) { Object.new.tap { |pool| def pool.close = nil } }
      client.define_singleton_method(:call) do |_native|
        source.cancel(:mid_flight)
        ::Protocol::HTTP::Response.new("HTTP/1.1", 200, ::Protocol::HTTP::Headers.new, native)
      end
      adapter = AsyncHTTP.using(client)

      Sync do
        future = adapter.call(request("http://example.test/"), nil, source.token)

        assert_predicate(future, :cancelled?)
        assert_raises(Dexpace::CancelledError) { value_within(future) }
      end

      assert_equal(1, native.close_count)
    end

    # The negative twin (ASYNC-20): a response already delivered to the caller must not be closed
    # by a late cancellation of the future -- a cancel on a settled pivot is a no-op.
    test "ASYNC-20: cancelling the future after delivery does not close the delivered response" do
      server = AsyncHTTPHoldingServer.new(hold: :head)
      adapter = AsyncHTTP.build

      reactor_over(server) do
        future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil, nil)
        server.wait_for_accept
        server.release("ok")
        response = value_within(future)

        future.cancel(:too_late) # no-op: the pivot is already settled successfully

        refute_predicate(response.body, :closed?)
        refute_predicate(future, :cancelled?)
        assert_equal("ok", response.body_string)
      end
    ensure
      adapter&.close
      server&.close
    end

    # A cancel that lands after delivery but through the TOKEN reaches a consumer blocked in a
    # body read: the watcher closes the response from inside the reactor, the blocked read wakes,
    # and the token is asked first, so the reader sees the cancellation and not a stream failure.
    test "TRANSPORT-7 on the body path: a token cancelled under a blocked body read wakes the " \
         "reader with CancelledError and releases the body" do
      server = AsyncHTTPHoldingServer.new(hold: :body)
      adapter = AsyncHTTP.build
      source = Dexpace::Cancellation.source
      arrived = ::Thread::Queue.new
      canceller = ::Thread.new do
        arrived.pop # the first chunk was yielded: the reader is now blocked on the held second one
        source.cancel(:reader_cancelled)
      end

      reactor_over(server) do |task|
        response = value_within(adapter.call(request("http://127.0.0.1:#{server.port}/"), nil,
                                             source.token,))
        server.wait_for_accept
        chunks = []
        # Bounded: a watcher that never closed the delivered response would leave the read blocked
        # for good, and Async::TimeoutError is a StandardError the assertion below refuses.
        error = assert_raises(Dexpace::CancelledError) do
          task.with_timeout(BOUND) do
            response.body.each do |chunk|
              chunks << chunk
              arrived.push(true)
            end
          end
        end

        assert_equal(:reader_cancelled, error.reason)
        assert_equal(["first"], chunks)
        assert_predicate(response.body, :closed?)
      end
      canceller.join
    ensure
      adapter&.close
      server&.close
    end
  end
end
