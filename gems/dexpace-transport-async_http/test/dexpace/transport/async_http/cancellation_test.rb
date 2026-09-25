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

    # Review round 2's R2-1. `Cancellation::Source#cancel` steals its hooks under its mutex, flips
    # the flag and runs them OUTSIDE it, on the canceller's thread -- so the exchange can end
    # between the flip and the adapter's hook: check-after-resume sees the flag, the pivot
    # settles cancelled and the exchange closes its queue before the hook pushes onto it, and a
    # push onto a closed queue raises `ClosedQueueError`, which `Hooks.notify` would hand back to
    # the caller's `Source#cancel`. Deterministic through an ordinary caller's hook registered
    # FIRST, which parks the canceller across exactly that window; the same ordering needs no
    # slow hook when the canceller is merely descheduled there. A cancel that lost the race
    # against the exchange's own end is not the caller's failure.
    test "a token cancel in flight while the exchange finishes never raises out of " \
         "Source#cancel on the canceller's thread, and the future is cancelled" do
      source = Dexpace::Cancellation.source
      flagged = ::Thread::Queue.new  # the canceller has flipped the flag and is in its hooks
      finished = ::Thread::Queue.new # the exchange has ended: let the adapter's hook run now
      outcome = ::Thread::Queue.new
      source.token.on_cancel do |_reason|
        flagged.push(true)
        finished.pop
      end
      client = Object.new
      client.define_singleton_method(:retries) { 0 }
      client.define_singleton_method(:pool) { Object.new.tap { |pool| def pool.close = nil } }
      client.define_singleton_method(:call) do |_native|
        flagged.pop # scheduler-aware: the reactor keeps turning until the cancel is in flight
        ::Protocol::HTTP::Response.new("HTTP/1.1", 204, ::Protocol::HTTP::Headers.new, nil)
      end
      adapter = AsyncHTTP.using(client)
      canceller = nil

      Sync do |task|
        future = adapter.call(request("http://example.test/"), nil, source.token)
        canceller = ::Thread.new do
          outcome.push(begin
            source.cancel(:racing)
          rescue ::StandardError => error
            error
          end)
        end

        error = assert_raises(Dexpace::CancelledError) { value_within(future) }

        assert_equal(:racing, error.reason)
        assert_predicate(future, :cancelled?)
        assert_exchange_released(task) # the exchange ended and closed its queue...
      ensure
        finished.push(true) # ...and only now does the adapter's hook run (on every path)
      end
      canceller.join
      result = outcome.pop

      assert_same(true, result, "Source#cancel raised #{result.inspect} out of the adapter's hook")
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
    # by a late cancellation of the future -- a cancel on a settled pivot is a no-op. The watcher
    # that would close it on a TOKEN cancel stays for the life of the delivered response, and
    # transient: a body a caller never closes must not hold the caller's `Sync` block open --
    # without `transient: true` that property fails as a hang and never by name (review round
    # 2's R2-3), so it is asserted here before the body is released and its release is asserted
    # to end the watcher.
    test "ASYNC-20: cancelling the future after delivery does not close the delivered response; " \
         "its watcher stays, transient, until the body is released" do
      server = AsyncHTTPHoldingServer.new(hold: :head)
      adapter = AsyncHTTP.build

      reactor_over(server) do |task|
        future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil, nil)
        server.wait_for_accept
        server.release("ok")
        response = value_within(future)

        future.cancel(:too_late) # no-op: the pivot is already settled successfully

        refute_predicate(response.body, :closed?)
        refute_predicate(future, :cancelled?)
        # Read while the body is open and asserted only after its release: a non-transient
        # watcher under a still-open body would hold the reactor open on the failing assertion.
        transient = watcher_tasks(task).map(&:transient?)

        assert_equal("ok", response.body_string)
        assert_equal([true], transient, "one watcher per delivered response, and transient")
        assert_exchange_released(task) # the body's release is what ends the watcher
      end
    ensure
      adapter&.close
      server&.close
    end

    # A cancel that lands after delivery but through the TOKEN reaches a consumer blocked in a
    # body read: the watcher wakes the parked reader from inside the reactor, the reader closes
    # the body, and the token is asked first, so the reader sees the cancellation and not a
    # stream failure.
    test "TRANSPORT-7 on the body path: a token cancelled under a blocked body read wakes the " \
         "reader with CancelledError and releases the body" do
      assert_body_read_woken
    end

    # The same, on every selector this host has. The watcher used to CLOSE the delivered
    # response under the parked reader and rely on the close to wake it, which io_uring does and
    # epoll does not: green on a developer machine, red on every hosted runner (whose io-event
    # has no liburing), and on Ruby 4.0 IO#close's own deferred interrupt landed later in the
    # fixture's Thread#join. Naming the selector keeps the property host-independent.
    AsyncHTTPReactor::SELECTORS.each do |selector|
      test "TRANSPORT-7 on the body path, on the #{selector} selector: the parked reader is " \
           "woken by the watcher, never by the test's bound" do
        assert_body_read_woken(selector: selector)
      end
    end

    private

    def assert_body_read_woken(selector: nil)
      server = AsyncHTTPHoldingServer.new(hold: :body)
      adapter = AsyncHTTP.build
      source = Dexpace::Cancellation.source
      arrived = ::Thread::Queue.new
      canceller = cancel_on(arrived, source)

      reactor_over(server, selector: selector) do |task|
        response = held_response(adapter, server, source)

        assert_woken_by_watcher(response, *read_until_cancelled(task, response, arrived))
      end
      canceller.join
    ensure
      adapter&.close
      server&.close
    end

    def cancel_on(arrived, source)
      ::Thread.new do
        arrived.pop # the first chunk was yielded: the reader is now blocked on the held second one
        source.cancel(:reader_cancelled)
      end
    end

    # The delivered response whose body the holding server keeps open after the first chunk.
    def held_response(adapter, server, source)
      url = "http://127.0.0.1:#{server.port}/"
      value_within(adapter.call(request(url), nil, source.token)).tap { server.wait_for_accept }
    end

    # Bounded: a watcher that never woke the parked reader would leave the read blocked for good.
    # The bound's Async::TimeoutError is a StandardError the token-first classifier turns into
    # the SAME CancelledError, so the cause is what tells the two wakes apart.
    def read_until_cancelled(task, response, arrived)
      chunks = []
      error = assert_raises(Dexpace::CancelledError) do
        task.with_timeout(BOUND) do
          response.body.each do |chunk|
            chunks << chunk
            arrived.push(true)
          end
        end
      end
      [error, chunks]
    end

    def assert_woken_by_watcher(response, error, chunks)
      assert_equal(:reader_cancelled, error.reason)
      # The wake must be the WATCHER's and never this test's own bound: with the watcher's wake
      # of the delivered response deleted (the reviewer's mutation 37), the bound fires inside
      # the native read five seconds later and the classifier still answers
      # CancelledError(:reader_cancelled) with the body closed -- every assertion around this one
      # passes. The watcher's wake is an IOError raised into the parked reader.
      refute_kind_of(::Async::TimeoutError, error.cause,
                     "the reader was woken by the test's bound, not by the watcher",)
      assert_kind_of(::IOError, error.cause)
      assert_equal(["first"], chunks)
      assert_predicate(response.body, :closed?)
    end
  end
end
