# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/adapter_fixtures"
require "dexpace/transport/net_http"

# TRANSPORT-19, TRANSPORT-25, and the mechanism TRANSPORT-22 rests on: 8a's R1 (P8-1), the
# group R1 is answerable to. The fixture is dexpace-conformance's own WireServer (design boundary
# 13: never a second fixture hand-rolled beside it), reached through the root Gemfile's path
# loading and never through this gem's gemspec. No test sleeps to synchronise: every wait is a
# queue pop, a bounded join or the dribble script's own deliberate delay, which is the thing
# under test. ResponsePump is a private_constant, reached through const_get. Four nested
# classes under Metrics/ClassLength (6c's shape): delivery, teardown, the carried failures, and
# a token already cancelled at construction.
module DexpaceTransportNetHttpResponsePumpTest
  NetHTTP = Dexpace::Transport::NetHTTP
  ResponsePump = NetHTTP.const_get(:ResponsePump)
  Scripts = Dexpace::Conformance::Scripts

  # The pump construction and the drain the three classes share.
  module Pumping
    include AdapterFixtures

    def get
      ::Net::HTTPGenericRequest.new("GET", false, true, "/", {})
    end

    def pump_for(server, cancellation: Dexpace::Cancellation.none, **)
      ResponsePump.new(http: client_for(server.port), native: get, deadline: nil,
                       cancellation: cancellation, **,)
    end

    def drain(pump, size = 64 * 1024)
      drained = (+"").b
      loop { drained << pump.readpartial(size) }
    rescue Dexpace::EndOfStreamError
      drained
    end
  end

  # The head, the chunks and the end of stream.
  class DeliveryTest < DexpaceTestCase
    include Pumping

    test "is a private_constant of NetHTTP" do
      assert_raises(NameError) { NetHTTP::ResponsePump }
    end

    test "delivers the head before the second chunk, with a real time gap (never buffered whole)" do
      pump = pump_for(wire(Scripts.dribble("aaaaa", "bbbbb", 0.3)))
      head = nil

      head_at = elapsed { head = pump.head_or_raise }

      assert_equal("200", head.code)
      assert_operator(head_at, :<, 0.15, "the head must not wait for the second chunk")
      assert_equal("aaaaabbbbb", drain(pump, 16))
      pump.close
    end

    test "with a block, #head_or_raise yields the head and returns the block's value" do
      pump = pump_for(wire(Scripts.fixed("ok")))

      code = pump.head_or_raise { |head| head.code.to_i }

      assert_equal(200, code)
      assert_equal("ok", drain(pump))
      pump.close
    end

    test "TRANSPORT-25: a multi-megabyte body round-trips byte-exactly; close is idempotent" do
      body = Scripts.large_body(4 * 1024 * 1024)
      pump = pump_for(wire(Scripts.fixed(body)))
      pump.head_or_raise

      drained = drain(pump)

      assert_equal(body.bytesize, drained.bytesize)
      assert_equal(body, drained)
      pump.close
      pump.close
    end

    test "a drained pump reports end of stream, not a closed response" do
      pump = pump_for(wire(Scripts.fixed("ok")))
      pump.head_or_raise
      drain(pump)

      assert_raises(Dexpace::EndOfStreamError) { pump.readpartial(1) }
      pump.close
    end

    test "writing into an explicit outbuf retags it to BINARY via #replace" do
      pump = pump_for(wire(Scripts.fixed("caf\xE9".b)))
      pump.head_or_raise
      outbuf = (+"prior").force_encoding(Encoding::UTF_8)

      returned = pump.readpartial(16, outbuf)

      assert_same(outbuf, returned)
      assert_equal(Encoding::BINARY, outbuf.encoding)
      assert_equal("caf\xE9".b, outbuf)
      pump.close
    end

    test "#readpartial honours maxlen, keeping the remainder for the next read" do
      pump = pump_for(wire(Scripts.fixed("abcdef")))
      pump.head_or_raise

      assert_equal("ab", pump.readpartial(2))
      assert_equal("cd", pump.readpartial(2))
      assert_equal("ef", pump.readpartial(16))
      pump.close
    end
  end

  # R1's release: bounded, idempotent, from any state, and on both constructions.
  class TeardownTest < DexpaceTestCase
    include Pumping

    test "TRANSPORT-19: closing mid-stream with the producer blocked on a socket read is prompt" do
      pump = pump_for(wire(Scripts.dribble("a", "b", 10))) # never waits 10 s: close wins
      pump.head_or_raise
      pump.readpartial(16) # consumes "a", leaves the producer blocked waiting for "b"

      took = elapsed { pump.close }

      assert_operator(took, :<, 1.0)
      assert_operator(elapsed { pump.close }, :<, 0.1, "idempotent")
      assert_raises(Dexpace::ClosedError) { pump.readpartial(1) }
    end

    test "closing before any read, and with the producer blocked on the queue, both return" do
      early = pump_for(wire(Scripts.fixed("x" * 100_000)))

      assert_operator(elapsed { early.close }, :<, 1.0)

      blocked = pump_for(wire(Scripts.fixed("x" * (1024 * 1024))))
      blocked.head_or_raise
      blocked.readpartial(1) # the producer is now blocked pushing into the full queue

      assert_operator(elapsed { blocked.close }, :<, 1.0)
    end

    # P8-52: the hook is registered on the SOURCE for the response's life and withdrawn by
    # #release, observed the way core's own cancellation suite observes a bounded registration --
    # the source's hook list, one longer while the pump is open and back to its size after the
    # close. A retained hook was unobservable through the closed pump alone: it would only have
    # closed an already-closed pump again (review round 0's mutation E).
    test "the cancellation subscription is detached when the pump is closed" do
      source = Dexpace::Cancellation.source
      hooks = -> { source.instance_variable_get(:@hooks).size }
      before = hooks.call
      pump = pump_for(wire(Scripts.fixed("ok")), cancellation: source.token)

      assert_equal(before + 1, hooks.call, "the pump subscribed for the response's life")
      pump.head_or_raise
      drain(pump)
      pump.close

      assert_equal(before, hooks.call, "#release withdrew the pump's one registration")
      source.cancel(:late) # nothing left to close; a retained hook would close a closed pump twice

      assert_predicate(pump, :closed?)
    end

    # XCUT-13: the join in #release is BOUNDED by JOIN_DEADLINE_SECONDS, asserted over the source
    # because the one producer that can outlive it -- a borrowed client's, left to the caller's
    # own read_timeout -- would cost the suite the whole deadline to observe.
    test "the producer join in #release is bounded by JOIN_DEADLINE_SECONDS, never unbounded" do
      path = File.expand_path("../../../../lib/dexpace/transport/net_http/response_pump.rb",
                              __dir__,)
      source = File.read(path)

      assert_match(/@thread&\.join\(JOIN_DEADLINE_SECONDS\)/, source)
      refute_match(/@thread&?\.join\b(?!\(JOIN_DEADLINE_SECONDS\))/, source)
    end

    # P8-15: the borrowing construction. The pump must neither start nor finish a client it does
    # not own, so an ALREADY-STARTED client is reused and survives the response's close; the
    # permit is returned by the producer once the client is free.
    test "owns_connection: false neither starts nor finishes the client; the permit comes back" do
      server = wire(Scripts.fixed("ok"))
      http = client_for(server.port)
      http.start
      permit = ::Thread::SizedQueue.new(1)

      pump = ResponsePump.new(http: http, native: get, deadline: nil,
                              cancellation: Dexpace::Cancellation.none, owns_connection: false,
                              permit: permit,)
      pump.head_or_raise
      drain(pump)
      pump.close

      assert_predicate(http, :started?, "the adapter must not finish a client it does not own")
      assert_equal(1, permit.size, "the permit is returned once the producer is done (P8-15)")
      http.finish
    end
  end

  # What a failure looks like from the consumer's thread: its class, its cause and its timing.
  class FailuresTest < DexpaceTestCase
    include Pumping

    # A chunked head, one chunk, then the connection drops with no terminating 0-chunk: the
    # next read inside Net::HTTP raises, after the head was delivered.
    def truncated_chunked
      lambda do |conn, _head|
        conn.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na\r\n")
        conn.close
      end
    end

    # pipeline/7ce4431d: a carried failure is raised with its cause spelled explicitly. An
    # unrelated exception is deliberately in flight here, so a bare `raise` -- which would take
    # `$!` -- is the only way the cause assertion below can fail.
    test "a producer failure after the head surfaces on the consumer's thread with its cause" do
      pump = pump_for(wire(truncated_chunked))
      pump.head_or_raise
      pump.readpartial(16) # "a"

      error = begin
        raise "unrelated, deliberately in flight"
      rescue RuntimeError
        begin
          pump.readpartial(16)
          nil
        rescue StandardError => caught
          caught
        end
      end

      assert_instance_of(Dexpace::TransportError, error)
      assert_equal(:read, error.phase)
      assert_predicate(error, :retryable?)
      refute_nil(error.cause)
      refute_equal("unrelated, deliberately in flight", error.cause.message)
      pump.close
    end

    test "a failure before the head is raised from #head_or_raise, classified and with its cause" do
      server = wire(Scripts.fixed("x"))
      http = client_for(server.port)
      server.close
      pump = ResponsePump.new(http: http, native: get, deadline: nil,
                              cancellation: Dexpace::Cancellation.none,)

      error = assert_raises(Dexpace::TransportError) { pump.head_or_raise }

      assert_equal(:connect, error.phase)
      assert_kind_of(::SystemCallError, error.cause)
      pump.close
    end

    # TRANSPORT-3: the token is asked first. The cancel lands while the producer is blocked in
    # a socket read, and the failure it produces classifies as the cancellation, not as a reset.
    test "a cancel under a blocked body read closes the pump and the read raises CancelledError" do
      entered = ::Thread::Queue.new
      server = wire(Scripts.hang_after_headers(on_headers_written: -> { entered.push(true) }))
      source = Dexpace::Cancellation.source
      pump = pump_for(server, cancellation: source.token)
      pump.head_or_raise
      canceller = ::Thread.new do
        entered.pop
        source.cancel(:gave_up)
      end

      error = assert_raises(Dexpace::CancelledError) { pump.readpartial(16) }
      canceller.join

      assert_equal(:gave_up, error.reason)
      assert_predicate(pump, :closed?)
      pump.close
    end

    test "a cancel before the head classifies #head_or_raise's failure as the cancellation" do
      entered = ::Thread::Queue.new
      server = wire(Scripts.hang_before_headers(on_request_read: -> { entered.push(true) }))
      source = Dexpace::Cancellation.source
      pump = pump_for(server, cancellation: source.token)
      canceller = ::Thread.new do
        entered.pop
        source.cancel(:early)
      end

      error = assert_raises(Dexpace::CancelledError) { pump.head_or_raise }
      canceller.join

      assert_equal(:early, error.reason)
      pump.close
    end

    # R3: the budget is refreshed into read_timeout after every chunk, so a trickling body
    # cannot multiply it by the chunk count; an expired budget mid-exchange surfaces as a
    # retryable transport failure rather than a hang.
    test "a deadline that expires between chunks fails the read with a retryable TransportError" do
      deadline = NetHTTP.const_get(:Deadline).build(clock: Dexpace::Clock::SYSTEM, budget: 0.25)
      http = client_for(wire(Scripts.dribble("a", "b", 10)).port)
      pump = ResponsePump.new(http: http, native: get, deadline: deadline,
                              cancellation: Dexpace::Cancellation.none,)
      pump.head_or_raise
      pump.readpartial(16)
      error = nil

      took = elapsed { error = assert_raises(Dexpace::TransportError) { pump.readpartial(16) } }

      assert_predicate(error, :retryable?)
      assert_operator(took, :<, 2.0)
      pump.close
    end
  end

  # Review round 1, P8-64: Cancellation::Source runs an already-cancelled hook inline, so the
  # pump's own subscription can close it from inside its constructor.
  class AlreadyCancelledTest < DexpaceTestCase
    include Pumping

    # A pump built over a cancelled token comes back closed, opened no connection, holds no
    # producer thread (the test base counts threads around every test), and classifies its
    # first read as the cancellation it was. The fixture holds before headers so that a producer
    # which DID start would be caught twice over: one connection recorded, and a join spent on
    # the hold that outlives the constructor.
    test "a token already cancelled at construction yields a closed pump that sent nothing" do
      server = wire(Scripts.hang_before_headers)
      source = Dexpace::Cancellation.source
      source.cancel(:already)

      pump = pump_for(server, cancellation: source.token)

      assert_predicate(pump, :closed?, "the inline hook closed the pump before #new returned")
      error = assert_raises(Dexpace::CancelledError) { pump.head_or_raise }

      assert_equal(:already, error.reason)
      assert_equal(0, server.connections, "a pump closed at construction exchanges nothing")
      pump.close
    end

    # The same over the borrowing construction: the permit the exchange would have returned
    # from the producer's ensure comes back from the constructor instead, exactly once, so the
    # next borrowed call is not held for a producer that never existed.
    test "a token already cancelled at construction hands the borrowed permit straight back" do
      server = wire(Scripts.hang_before_headers)
      source = Dexpace::Cancellation.source
      source.cancel(:already)
      permit = ::Thread::SizedQueue.new(1)

      pump = pump_for(server, cancellation: source.token, owns_connection: false, permit: permit)

      assert_predicate(pump, :closed?)
      assert_equal(1, permit.size, "the permit is back, once")
      assert_raises(Dexpace::CancelledError) { pump.readpartial(16) }
      assert_equal(0, server.connections)
      pump.close
    end
  end
end
