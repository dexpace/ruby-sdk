# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/async_http_silent_server"
require_relative "../../../support/async_http_recording_body"
require_relative "../../../support/async_http_reactor"
require "dexpace/transport/async_http"

# R14: TRANSPORT-8's antecedent, measured live -- a cancellation "originating inside" the native
# client, from the host runtime's own structured-concurrency scope, while the SDK future is still
# live -- paired with a genuine timeout on the SAME withheld-head path, because the pair IS the
# requirement: the first settles a terminal, non-retryable cancellation, the second a retryable
# transport failure, discriminated by class (Async::Cancel < Exception against
# Async::TimeoutError < StandardError, XCUT-2) and never by message. This is the row §12 records
# as vacuous and this adapter satisfies; the §12 correction is on phase 10's inbound list. Two
# nested classes under Metrics/ClassLength: the pair, and the close discipline under both.
module DexpaceTransportAsyncHTTPParentCancellationTest
  # The request builder, the bounded wait and the supervisor both classes share.
  module ParentCancellationTestSupport
    include AsyncHTTPReactor

    AsyncHTTP = Dexpace::Transport::AsyncHTTP
    BOUND = 5.0

    def request(url)
      builder = Dexpace::Request.builder
      builder.url = url
      builder.build
    end

    def value_within(future)
      future.value(deadline: Dexpace::Clock.deadline_in(BOUND))
    end

    # A supervisor task that makes the call and then parks on a queue -- never a sleep -- until the
    # test closes it, so the exchange stays its live child. `Task#async` runs a child eagerly only
    # to its first suspension and hands control back to the CALLER's fiber then, so the future the
    # supervisor assigns is read only after it says it has it.
    def supervise(root, adapter, request, options: nil)
      ready = ::Thread::Queue.new
      park = ::Thread::Queue.new
      future = nil
      supervisor = root.async do
        future = adapter.call(request, options, nil)
        ready.push(true)
        park.pop
      end
      ready.pop
      [supervisor, future, park]
    end
  end

  # TRANSPORT-8 and its timeout pair over one withheld-head path, discriminated by class.
  class PairTest < DexpaceTestCase
    include ParentCancellationTestSupport

    # The exchange Adapter#call spawns is a CHILD of `supervisor`, because `task.async` inside
    # #call reads Async::Task.current at the moment #call runs. Cancelling `supervisor` from `root`
    # -- a sibling relationship, not self-cancellation -- cascades into the exchange exactly as an
    # "internal cancel-all" would (TRANSPORT-8's own example phrase). No Dexpace::Cancellation is
    # involved and no Future#cancel: nothing in the SDK asked for it.
    test "TRANSPORT-8: cancelling a PARENT task delivers Async::Cancel into the still-live " \
         "exchange and settles a terminal, non-retryable CancelledError" do
      server = AsyncHTTPSilentServer.new
      adapter = AsyncHTTP.build

      reactor_over(server) do |root|
        supervisor, future, park = supervise(root, adapter, request("http://127.0.0.1:#{server.port}/"))
        server.wait_for_accept
        supervisor.cancel

        error = assert_raises(Dexpace::CancelledError) { value_within(future) }
        assert_equal(:async_cancelled, error.reason)
        assert_predicate(future, :cancelled?)
        refute_respond_to(error, :retryable?)
        assert_equal(:cancelled, supervisor.status)
        park.close
      end
    ensure
      adapter&.close
      server&.close
    end

    test "TRANSPORT-8's pair: a with_timeout expiry on the SAME withheld-head path settles a " \
         "RETRYABLE Dexpace::TransportError, never CancelledError" do
      server = AsyncHTTPSilentServer.new
      adapter = AsyncHTTP.build

      reactor_over(server) do |task|
        options = Dexpace::RequestOptions.builder.tap { |b| b.timeout = 0.1 }.build
        future = adapter.call(request("http://127.0.0.1:#{server.port}/"), options, nil)
        server.wait_for_accept

        error = assert_raises(Dexpace::TransportError) { value_within(future) }
        assert_predicate(error, :retryable?)
        assert_kind_of(::Async::TimeoutError, error.cause)
        refute_predicate(future, :cancelled?)
        assert_exchange_released(task)
      end
    ensure
      adapter&.close
      server&.close
    end
  end

  # R13 and TRANSPORT-22: what a runtime cancellation, a deadline or an adaptation failure closes,
  # and exactly once.
  class CloseDisciplineTest < DexpaceTestCase
    include ParentCancellationTestSupport

    # R13, measured rather than assumed: on this adapter the native response exists only once
    # `Client#call` has returned, and no checkpoint lies between that return and delivery, so a
    # runtime cancellation or a deadline landing INSIDE the native call finds nothing of the
    # exchange's to close -- the library's own ensure releases the connection -- and the
    # undelivered-response close is reached on two paths: check-after-resume
    # (cancellation_test.rb's TRANSPORT-9 case, close_count 1) and an adaptation failure after
    # the head (TRANSPORT-22, below).
    test "R13: a runtime cancellation or a deadline landing inside the native call leaves no " \
         "undelivered response, and the pivot still settles" do
      %i[cancel timeout].each do |path|
        native = AsyncHTTPRecordingBody.new(["late".b], length: 4)
        gate = ::Thread::Queue.new
        client = Object.new
        client.define_singleton_method(:retries) { 0 }
        client.define_singleton_method(:pool) { Object.new.tap { |pool| def pool.close = nil } }
        client.define_singleton_method(:call) do |_native|
          gate.pop # suspends the exchange at a checkpoint until the test releases it
          ::Protocol::HTTP::Response.new("HTTP/1.1", 200, ::Protocol::HTTP::Headers.new, native)
        end
        adapter = AsyncHTTP.using(client)

        Sync do |root|
          options = Dexpace::RequestOptions.builder.tap { |b| b.timeout = 0.1 }.build
          supervisor, future, park = supervise(root, adapter, request("http://example.test/"),
                                               options: options,)
          if path == :cancel
            supervisor.cancel
            assert_raises(Dexpace::CancelledError) { value_within(future) }
          else
            assert_raises(Dexpace::TransportError) { value_within(future) }
            park.close
          end
          gate.close
        end

        assert_equal(0, native.close_count, "#{path}: the response never existed to be closed")
      end
    end

    # TRANSPORT-22's adaptation-failure half: a head phase 1's model refuses -- an HTTP/1.2 version,
    # a 999 status until phase 10 widened Status --
    # raises InvalidArgumentError through the future, and the native body the exchange was holding
    # is closed exactly once before the future settles.
    test "TRANSPORT-22: an adaptation failure after the head closes the native body exactly once " \
         "and settles InvalidArgumentError through the future" do
      native = AsyncHTTPRecordingBody.new(["late".b], length: 4)
      client = Object.new
      client.define_singleton_method(:retries) { 0 }
      client.define_singleton_method(:pool) { Object.new.tap { |pool| def pool.close = nil } }
      client.define_singleton_method(:call) do |_native|
        ::Protocol::HTTP::Response.new("HTTP/1.2", 200, ::Protocol::HTTP::Headers.new, native)
      end
      adapter = AsyncHTTP.using(client)

      Sync do
        future = adapter.call(request("http://example.test/"), nil, nil)

        assert_raises(Dexpace::InvalidArgumentError) { value_within(future) }
      end

      assert_equal(1, native.close_count)
    end

    # The net under #run's ensure, reached only when a runtime cancellation lands INSIDE an exit
    # arm: the adaptation failure above, with the undelivered native body's close suspending at a
    # checkpoint (a native close that waits on the peer's stream reset would) and the parent
    # cancelled there. Async::Cancel leaves the rescue arm before Errors.settle ran, so the
    # ensure's net is the only thing left to settle the pivot -- cancelled, never left pending
    # (review round 0's R0-4, a surviving mutant). No sleep: the body parks on a queue the test
    # never pushes to, and the cancellation is what wakes it.
    test "a runtime cancellation landing inside an exit arm's native close still settles the " \
         "pivot cancelled, through the ensure's net" do
      gate = ::Thread::Queue.new
      native = AsyncHTTPRecordingBody.new(["late".b], length: 4)
      native.define_singleton_method(:close) { |error = nil| gate.pop && super(error) }
      client = Object.new
      client.define_singleton_method(:retries) { 0 }
      client.define_singleton_method(:pool) { Object.new.tap { |pool| def pool.close = nil } }
      client.define_singleton_method(:call) do |_native|
        ::Protocol::HTTP::Response.new("HTTP/1.2", 200, ::Protocol::HTTP::Headers.new, native)
      end
      adapter = AsyncHTTP.using(client)

      Sync do |root|
        supervisor, future, park = supervise(root, adapter, request("http://example.test/"))

        refute_predicate(future, :settled?, "the exit arm is parked inside the native close")
        supervisor.cancel

        error = assert_raises(Dexpace::CancelledError) { value_within(future) }
        assert_equal(:async_cancelled, error.reason)
        assert_predicate(future, :cancelled?)
        assert_exchange_released(root)
        park.close
        gate.close
      end

      assert_equal(0, native.close_count, "the native close was interrupted, never completed")
    end
  end
end
