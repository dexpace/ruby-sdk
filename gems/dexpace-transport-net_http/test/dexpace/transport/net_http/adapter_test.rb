# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/adapter_fixtures"
require "dexpace/transport/net_http"

# TRANSPORT-1 to 6, 15, 16, 20, 22, 29, 30 and the constructions (P8-6, P8-10, P8-15). The
# lifecycle and concurrency proofs over a real socket; the per-mapping unit tests live beside
# the mappers. Six nested classes under Metrics/ClassLength (6c's shape): the constructions,
# the lifecycle, the budget and failure classification, the wire, cancellation, and the proxy.
module DexpaceTransportNetHttpAdapterTest
  NetHTTP = Dexpace::Transport::NetHTTP
  Scripts = Dexpace::Conformance::Scripts

  # .build, .using, .default and what each refuses.
  class ConstructionTest < DexpaceTestCase
    include AdapterFixtures

    test ".build produces an owned adapter; .using produces a borrowing one; both are transports" do
      owned = NetHTTP.build
      borrowed = NetHTTP.using(client_for(1))

      assert_predicate(owned, :owned?)
      refute_predicate(borrowed, :owned?)
      assert(Dexpace::Transport.conforms?(owned))
      assert(Dexpace::Transport.conforms?(borrowed))
    end

    test "P8-10: .using refuses a client whose max_retries is not zero, without mutating it" do
      client = ::Net::HTTP.new("127.0.0.1", 1)

      error = assert_raises(Dexpace::InvalidArgumentError) { NetHTTP.using(client) }

      assert_match(/max_retries/, error.message)
      assert_equal(1, client.max_retries, "the client is the caller's (XCUT-22)")
    end

    test ".build validates its timeout and refuses a non-positive or non-finite one" do
      assert_raises(Dexpace::InvalidArgumentError) { NetHTTP.build(timeout: 0) }
      assert_raises(Dexpace::InvalidArgumentError) { NetHTTP.build(timeout: -1.0) }
      assert_raises(Dexpace::InvalidArgumentError) { NetHTTP.build(timeout: Float::INFINITY) }
      assert_raises(Dexpace::InvalidArgumentError) { NetHTTP.build(timeout: "5") }
      assert_predicate(NetHTTP.build(timeout: 2.5), :owned?)
    end

    test ".default builds a fresh owned instance every call, and the registry knows the key" do
      refute_same(NetHTTP.default, NetHTTP.default)
      assert_predicate(NetHTTP.default, :owned?)
      assert_includes(Dexpace::Transport.registered_keys, NetHTTP::REGISTRY_KEY)
    end

    test "Adapter.new is private: the two named entry points are the whole construction surface" do
      assert_raises(NoMethodError) { NetHTTP::Adapter.new }
    end

    test "a nil cancellation is the never-cancelled token" do
      server = wire(Scripts.fixed("ok"))

      response = NetHTTP.build.call(request_for(server), Dexpace::RequestOptions::EMPTY, nil)

      assert_equal("ok", response.body_string)
    end
  end

  # Close on both constructions, and the borrowing construction's three refusals (P8-15).
  class LifecycleTest < DexpaceTestCase
    include AdapterFixtures

    test "TRANSPORT-15/16: an owned adapter raises ClosedError after close; reclose is a no-op" do
      server = wire(Scripts.fixed("ok"))
      adapter = NetHTTP.build
      adapter.close
      adapter.close

      assert_predicate(adapter, :closed?)
      assert_raises(Dexpace::ClosedError) { settle(adapter, request_for(server)) }
      assert_equal(0, server.connections)
    end

    test "TRANSPORT-15: a borrowed adapter's close disables neither the caller's client nor it" do
      server = wire(Scripts.fixed("ok"))
      client = client_for(server.port)
      adapter = NetHTTP.using(client)
      settle(adapter, request_for(server)).close
      adapter.close

      assert_predicate(adapter, :closed?)
      assert_equal("200", client.start { |c| c.request(::Net::HTTP::Get.new("/")) }.code)
      assert_equal(200, settle(adapter, request_for(server)).tap(&:close).status.code,
                   "SEAM-15's borrowing mode: closes nothing and stays usable",)
    end

    test "TRANSPORT-16: a pre-existing cancellation flag is untouched by close" do
      source = Dexpace::Cancellation.source
      source.cancel(:before)
      adapter = NetHTTP.build

      adapter.close

      assert_predicate(source, :cancelled?)
      assert_equal(:before, source.reason)
    end

    test "P8-6: a non-nil per-call timeout against a borrowed client raises before any send" do
      server = wire(Scripts.fixed("ok"))
      adapter = NetHTTP.using(client_for(server.port))
      options = Dexpace::RequestOptions.build(timeout: 1.0, max_retries: nil, tags: {})

      error = assert_raises(Dexpace::InvalidArgumentError) do
        adapter.call(request_for(server), options, Dexpace::Cancellation.none)
      end

      assert_match(/TRANSPORT-5/, error.message)
      assert_equal(0, server.connections)
    end

    test "P8-15: a borrowed adapter refuses a request naming a different origin, unsent" do
      server = wire(Scripts.fixed("ok"))
      adapter = NetHTTP.using(client_for(server.port))
      elsewhere = Dexpace::Request.build(method: "GET", url: "http://127.0.0.1:1/",
                                         headers: Dexpace::Headers::EMPTY, body: nil,)
      https = Dexpace::Request.build(method: "GET", url: "https://127.0.0.1:#{server.port}/",
                                     headers: Dexpace::Headers::EMPTY, body: nil,)

      assert_raises(Dexpace::InvalidArgumentError) { settle(adapter, elsewhere) }
      assert_raises(Dexpace::InvalidArgumentError) { settle(adapter, https) }
      assert_equal(0, server.connections)
    end

    test "P8-15: a borrowed adapter reuses a client the caller started, and never finishes it" do
      server = wire(keep_alive_twice("one", "two"))
      client = client_for(server.port)
      client.start
      adapter = NetHTTP.using(client)

      first = settle(adapter, request_for(server)).body_string
      second = settle(adapter, request_for(server)).body_string

      assert_equal(%w[one two], [first, second])
      assert_predicate(client, :started?, "the adapter must not finish a client it does not own")
      assert_equal(1, server.connections, "one keep-alive connection served both exchanges")
      client.finish
    end

    test "P8-15: a borrowed response closed mid-stream leaves the caller's started client usable" do
      server = wire(Scripts.large(200_000))
      client = client_for(server.port)
      client.start
      adapter = NetHTTP.using(client)
      partial = settle(adapter, request_for(server))
      partial.body.source.read_into((+"").b, count: 10)
      partial.close

      whole = settle(adapter, request_for(server))

      assert_equal(200_000, whole.body_bytes.bytesize)
      assert_predicate(client, :started?)
      client.finish
    end
  end

  # The per-call budget (R3) and how a failure that produced no response is classified.
  class BudgetAndFailureTest < DexpaceTestCase
    include AdapterFixtures

    test "TRANSPORT-2: a dropped first connection is one connection and one failure, no retry" do
      server = wire(Scripts.fail_first_connection_then_succeed("ok"))

      error = assert_raises(Dexpace::TransportError) { settle(NetHTTP.build, request_for(server)) }

      assert_predicate(error, :retryable?)
      assert_equal(1, server.connections)
    end

    test "TRANSPORT-20: a refused connection is the canonical retryable failure, with its cause" do
      server = wire(Scripts.fixed("x"))
      request = request_for(server)
      server.close

      error = assert_raises(Dexpace::TransportError) { settle(NetHTTP.build, request) }

      assert_predicate(error, :retryable?)
      assert_equal(:connect, error.phase)
      assert_kind_of(::SystemCallError, error.cause)
    end

    test "TRANSPORT-4: a read timeout is a retryable failure; the cancellation flag stays clear" do
      server = wire(Scripts.hang_before_headers)
      source = Dexpace::Cancellation.source
      adapter = NetHTTP.build(timeout: 0.2)

      error = assert_raises(Dexpace::TransportError) do
        adapter.call(request_for(server), Dexpace::RequestOptions::EMPTY, source.token)
      end

      assert_predicate(error, :retryable?)
      refute_predicate(source, :cancelled?)
      assert_kind_of(::Net::ReadTimeout, error.cause)
    end

    test "TRANSPORT-5: the per-call timeout overrides the transport's, for that call only" do
      server = wire(Scripts.hang_before_headers)
      adapter = NetHTTP.build(timeout: 30.0)
      options = Dexpace::RequestOptions.build(timeout: 0.2, max_retries: nil, tags: {})

      took = elapsed do
        assert_raises(Dexpace::TransportError) do
          adapter.call(request_for(server), options, Dexpace::Cancellation.none)
        end
      end

      assert_operator(took, :<, 2.0)
    end

    # R3 (P8-5): the budget is TOTAL. Four chunks 0.15 s apart pass a per-read window of 0.4 s
    # one at a time and blow the same 0.4 s as a whole; only the total reading fails here.
    test "TRANSPORT-5 / P8-5: the budget bounds the whole call, not each read" do
      server = wire(trickle(4, 0.15))
      adapter = NetHTTP.build(timeout: 0.4)
      response = settle(adapter, request_for(server))
      error = nil

      took = elapsed { error = assert_raises(Dexpace::TransportError) { response.body_bytes } }

      assert_predicate(error, :retryable?)
      assert_operator(took, :<, 0.55, "a per-read budget would have taken 0.6 s or more")
    end

    # R3: a budget that is spent by the time the call is checked raises from the ADAPTER, before
    # any socket -- never handed to Net::HTTP as a zero or negative knob. A nanosecond is spent
    # between the deadline's construction and its check on every interpreter.
    test "TRANSPORT-6 / R3: an expired budget is refused before dispatch, as a retryable failure" do
      server = wire(Scripts.fixed("ok"))
      options = Dexpace::RequestOptions.build(timeout: 1e-9, max_retries: nil, tags: {})

      error = assert_raises(Dexpace::TransportError) do
        NetHTTP.build.call(request_for(server), options, Dexpace::Cancellation.none)
      end

      assert_predicate(error, :retryable?)
      assert_equal(:connect, error.phase)
      assert_match(/expired before dispatch/, error.message)
      assert_nil(error.cause, "the adapter's own raise, not a library timeout")
      assert_equal(0, server.connections)
    end

    test "the configured tier is read through Keys::REQUEST_TIMEOUT, as a duration" do
      server = wire(Scripts.hang_before_headers)
      key = Dexpace::Configuration::Keys::REQUEST_TIMEOUT
      Dexpace.configure { |builder| builder.override(key, "200ms") }

      took = elapsed do
        assert_raises(Dexpace::TransportError) { settle(NetHTTP.build, request_for(server)) }
      end

      assert_operator(took, :<, 2.0)
    ensure
      Dexpace.reset_config!
    end
  end

  # What one exchange puts on the wire and hands back, and the proxy the SDK resolved.
  class WireTest < DexpaceTestCase
    include AdapterFixtures

    test "TRANSPORT-1: a raw 302 with a Location comes back as it is and is never followed" do
      server = wire(Scripts.redirect("http://127.0.0.1:1/elsewhere"))

      response = settle(NetHTTP.build, request_for(server))

      assert_equal(302, response.status.code)
      assert_equal(["http://127.0.0.1:1/elsewhere"], response.headers["Location"])
      assert_equal(1, server.connections)
      response.close
    end

    test "TRANSPORT-29: many concurrent calls through one owned adapter each get their own reply" do
      server = wire(Scripts.echo_path)
      adapter = NetHTTP.build

      assert_empty(echo_mismatches(adapter, server, threads: 4, rounds: 10))
      adapter.close
    end

    # TRANSPORT-29 on the OTHER construction: satisfied by serialisation rather than by per-call
    # construction (P8-15), and a proof of one is not a proof of the other.
    test "TRANSPORT-29: concurrent calls through a borrowed adapter are serialised and matched" do
      server = wire(Scripts.echo_path)
      adapter = NetHTTP.using(client_for(server.port))

      assert_empty(echo_mismatches(adapter, server, threads: 4, rounds: 5))
    end

    test "P8-4: a ruby -w POST with and without a body raises no warning" do
      server = wire(Scripts.fixed("ok"))
      adapter = NetHTTP.build
      with_body = Dexpace::Request.build(method: "POST", url: "http://127.0.0.1:#{server.port}/",
                                         headers: Dexpace::Headers::EMPTY,
                                         body: Dexpace::Body.bytes("x".b),)
      without = with_body.new_builder.tap { |b| b.body = nil }.build

      settle(adapter, with_body).close # Warning.warn raises under DexpaceTestCase
      settle(adapter, without).close

      heads = server.requests.map(&:head)

      assert_equal(["Content-Length: 1\r\n", "Content-Length: 0\r\n"],
                   heads.map { |head| head.find { |line| line.start_with?("Content-Length") } },)
      assert_equal(["Content-Type: application/octet-stream\r\n"] * 2,
                   heads.map { |head| head.find { |line| line.start_with?("Content-Type") } },)
    end

    test "P8-3: a gzip response is delivered compressed, with Content-Encoding and length intact" do
      compressed = gzip("hello, faithfully")
      server = wire(Scripts.fixed(compressed, headers: { "Content-Encoding" => "gzip" }))
      request = request_for(server).new_builder.tap do |b|
        b.headers = Dexpace::Headers.builder.tap { |h| h.add("Accept-Encoding", "gzip") }.build
      end.build

      response = settle(NetHTTP.build, request)

      assert_equal(["gzip"], response.headers["Content-Encoding"])
      assert_equal(compressed.bytesize, response.body.content_length)
      assert_equal(compressed, response.body_bytes)
    end

    test "TRANSPORT-25: a chunked response streams and the body bytes are BINARY" do
      server = wire(Scripts.dribble("caf\xE9".b, "x", 0))

      response = settle(NetHTTP.build, request_for(server))
      bytes = response.body_bytes

      assert_equal(-1, response.body.content_length)
      assert_equal("caf\xE9x".b, bytes)
      assert_equal(Encoding::BINARY, bytes.encoding)
    end

    test "TRANSPORT-25: closing the response releases the connection, seen from the server" do
      server = wire(Scripts.large(5 * 1024 * 1024, hold: true))

      response = settle(NetHTTP.build, request_for(server))
      response.body.source.read_into((+"").b, count: 1024)
      response.close

      assert_equal(1, server.await_closed_connection(timeout: 2))
    end

    # The body is UNDRAINABLE -- a hundred bytes declared, two sent, the connection held -- so
    # only the adapter's own close in Adapter#dispatch's rescue can release it: with that guard
    # removed the producer stays blocked in read_body on the 98 bytes that never come, the server
    # never sees the peer close, and the bound below elapses. A two-byte body drained itself and
    # released the connection whether or not the guard existed (review round 0's mutation H).
    test "TRANSPORT-22: an adaptation failure after the head releases the connection and raises" do
      server = wire(lambda do |conn, _head|
        conn.write("HTTP/1.0 200 OK\r\nContent-Length: 100\r\n\r\nok")
        conn.read # holds the connection, and the 98 undelivered bytes, until the peer closes it
      end)

      assert_raises(Dexpace::InvalidArgumentError) { settle(NetHTTP.build, request_for(server)) }
      assert_equal(1, server.await_closed_connection(timeout: 2),
                   "the guard's close is the only thing that can release this connection",)
    end

    test "a HEAD response carries no body and no producer thread stays behind" do
      server = wire(Scripts.fixed("ignored"))
      request = request_for(server).new_builder.tap { |b| b.method = "HEAD" }.build

      response = settle(NetHTTP.build, request)

      assert_nil(response.body)
      assert_equal(["7"], response.headers["Content-Length"])
    end
  end

  # TRANSPORT-3: the token is asked first, at every point a cancel can land.
  class CancellationTest < DexpaceTestCase
    include AdapterFixtures

    # Verified fact 3: with max_retries at its default the call RETURNS 200 after a cancel, so
    # the assertion is on the outcome -- the exchange as a whole raises the cancellation. The
    # cancel fires once the server has flushed the head, which the caller may or may not have
    # popped yet, so either the call or the body read is where it surfaces; the pump's own suite
    # pins each side deterministically.
    test "TRANSPORT-3: a cancellation delivered under a blocked read raises CancelledError" do
      blocked = ::Thread::Queue.new
      server = wire(Scripts.hang_after_headers(on_headers_written: -> { blocked.push(true) }))
      source = Dexpace::Cancellation.source
      canceller = ::Thread.new do
        blocked.pop
        source.cancel(:test)
      end

      error = assert_raises(Dexpace::CancelledError) do
        NetHTTP.build.call(request_for(server), Dexpace::RequestOptions::EMPTY, source.token)
          .body_bytes
      end
      canceller.join

      assert_equal(:test, error.reason)
    end

    test "TRANSPORT-3: a cancellation before the head raises CancelledError from the call itself" do
      blocked = ::Thread::Queue.new
      server = wire(Scripts.hang_before_headers(on_request_read: -> { blocked.push(true) }))
      source = Dexpace::Cancellation.source
      canceller = ::Thread.new do
        blocked.pop
        source.cancel(:early)
      end

      error = assert_raises(Dexpace::CancelledError) do
        NetHTTP.build.call(request_for(server), Dexpace::RequestOptions::EMPTY, source.token)
      end
      canceller.join

      assert_equal(:early, error.reason)
    end

    test "an already-cancelled token is refused before anything reaches the wire" do
      server = wire(Scripts.fixed("ok"))
      source = Dexpace::Cancellation.source
      source.cancel(:gone)

      assert_raises(Dexpace::CancelledError) do
        NetHTTP.build.call(request_for(server), Dexpace::RequestOptions::EMPTY, source.token)
      end
      assert_equal(0, server.connections)
    end
  end

  # R17 and TRANSPORT-30: the proxy the SDK resolved is the only proxy the adapter uses.
  class ProxyTest < DexpaceTestCase
    include AdapterFixtures

    # R17: Net::HTTP.new's p_addr defaults to :ENV, and the resolver reads only the upper-case
    # keys, so a lower-case `http_proxy` naming the fixture is exactly what the old shape would
    # have honoured behind the SDK's back. The target is TEST-NET-1: unroutable, never loopback
    # (which find_proxy exempts), so the call times out against it instead of reaching the fixture.
    # A host's own no_proxy is cleared for the control, which find_proxy honours in either case.
    test "R17: with http_proxy in the environment the per-call client still does not proxy" do
      server = wire(Scripts.fixed("via proxy"))
      target = Dexpace::Request.build(method: "GET", url: "http://192.0.2.1/",
                                      headers: Dexpace::Headers::EMPTY, body: nil,)
      would_have = nil
      swapped = { "http_proxy" => "http://user:pw@127.0.0.1:#{server.port}",
                  "no_proxy" => nil, "NO_PROXY" => nil, }
      error = with_env(swapped) do
        would_have = ::Net::HTTP.new("192.0.2.1", 80).proxy?
        assert_raises(Dexpace::TransportError) { settle(NetHTTP.build(timeout: 0.3), target) }
      end

      assert(would_have, "Net::HTTP.new's own default WOULD have proxied")
      assert_predicate(error, :retryable?)
      assert_equal(0, server.connections, "nothing reached the environment's proxy")
    end

    # TRANSPORT-30: the proxy the SDK resolved IS used -- the fixture plays the proxy and sees
    # the absolute-form request line a proxy is sent. The chain is Configuration::EMPTY, whose
    # environment tier is the real ENV, so every key the resolver reads is overridden: the
    # resolver prefers HTTPS_PROXY over HTTP_PROXY and a host's NO_PROXY could cover the target,
    # and a blank override is an answer that masks the environment (review round 1's R1-1).
    test "TRANSPORT-30: a proxy resolved through the configuration chain carries the call" do
      server = wire(Scripts.fixed("via proxy"))
      target = Dexpace::Request.build(method: "GET", url: "http://192.0.2.1/x?y=1",
                                      headers: Dexpace::Headers::EMPTY, body: nil,)
      Dexpace.configure do |builder|
        builder.override(Dexpace::Configuration::Keys::HTTP_PROXY, "http://127.0.0.1:#{server.port}")
        builder.override(Dexpace::Configuration::Keys::HTTPS_PROXY, "")
        builder.override(Dexpace::Configuration::Keys::NO_PROXY, "")
      end

      response = settle(NetHTTP.build, target)

      assert_equal("via proxy", response.body_string)
      assert_equal("GET http://192.0.2.1/x?y=1 HTTP/1.1", server.requests.first.request_line)
    ensure
      Dexpace.reset_config!
    end
  end
end
