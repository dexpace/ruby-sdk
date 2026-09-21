# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/async_http_server_fixture"
require "dexpace/transport/async_http"

# The design's verified facts 2 and 3, as the fixture's own proof of concept before the wire
# grammar and dispatch suites build on it: a plaintext prior-knowledge h2 pair, a TLS pair
# negotiating h2 by real ALPN against a per-run self-signed certificate, and the HTTP/1.1
# constructor over the same interface. No lib/ mirror: it proves a test double. The fixture
# writes nothing to stderr through Console -- no readiness probe of the wrong protocol -- which
# the adapter's own no-stderr assertion in dispatch_conformance_test.rb reads.
class DexpaceTransportAsyncHTTPServerFixtureTest < DexpaceTestCase
  test "plaintext prior-knowledge h2 negotiates HTTP/2 with no client-side ALPN" do
    Sync do
      server = AsyncHTTPServerFixture.plaintext { |_request| [200, [], ["hi"]] }
      client = ::Async::HTTP::Client.new(server.client_endpoint, retries: 0)

      response = client.get("/")

      assert_equal("HTTP/2", response.version)
      assert_equal("hi", response.read)
    ensure
      client&.close
      server&.close
    end
  end

  test "TLS negotiates h2 by ALPN against the fixture's self-signed certificate, generated " \
       "fresh for this run" do
    Sync do
      server = AsyncHTTPServerFixture.tls { |_request| [200, [], ["hi"]] }
      client = ::Async::HTTP::Client.new(server.client_endpoint, retries: 0)

      response = client.get("/")

      assert_equal("HTTP/2", response.version)
      assert_equal("hi", response.read)
      assert_equal("https", server.client_endpoint.url.scheme)
    ensure
      client&.close
      server&.close
    end
  end

  test "the http1 constructor serves HTTP/1.1 over the same interface, and records the headers" do
    Sync do
      server = AsyncHTTPServerFixture.http1 { |_request| [200, [], ["hi"]] }
      client = ::Async::HTTP::Client.new(server.client_endpoint, retries: 0)

      response = client.get("/", { "x-probe" => "1" })

      assert_equal("HTTP/1.1", response.version)
      assert_equal("hi", response.read)
      assert_includes(server.received.last, %w[x-probe 1])
    ensure
      client&.close
      server&.close
    end
  end

  test "each run generates its own certificate rather than a cached one" do
    Sync do
      a = AsyncHTTPServerFixture.tls { |_r| [200, [], []] }
      b = AsyncHTTPServerFixture.tls { |_r| [200, [], []] }

      refute_equal(a.certificate.to_der, b.certificate.to_der)
    ensure
      a&.close
      b&.close
    end
  end

  # Without the close, the accept task would keep the enclosing Sync block from returning.
  test "#url names the fixture's own origin, and #close finishes the accept loop" do
    Sync do |task|
      server = AsyncHTTPServerFixture.http1 { |_r| [200, [], []] }
      port = server.client_endpoint.url.port

      assert_equal("http://127.0.0.1:#{port}/x", server.url("/x"))
      refute_predicate(server, :closed?)
      server.close
      task.yield

      assert_predicate(server, :closed?)
    end
  end
end
