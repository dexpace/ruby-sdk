# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/async_http_server_fixture"
require_relative "../../../support/async_http_recording_sink"
require "dexpace/transport/async_http"

# TRANSPORT-12/13 dispatched over BOTH protocols, and P8-40's reason: protocol-http1 refuses a
# non-token name AFTER the request line and host: are on the wire (a RefusedError, no 200) while
# protocol-http2 transmits it lowercased and unvalidated -- so a run over HTTP/1.1 alone could
# pass with the drop deleted (the library refusing instead), and only the h2 half proves the
# adapter's own predicate is doing anything on that protocol. The same fixture serves both, so
# "what did the peer receive" is read off the same kind of object on each. The wire-boundary
# re-validation's h2 half is here too: on HTTP/2 nothing below the model validates, and a CRLF
# value reaches the peer verbatim without it (the design's verified fact 4). Two nested classes
# under Metrics/ClassLength: the token predicate, and the re-validation with the spelling.
module DexpaceTransportAsyncHTTPWireGrammarTest
  # The request builder and the borrowing adapter both classes share.
  module WireGrammarTestSupport
    AsyncHTTP = Dexpace::Transport::AsyncHTTP
    DropPolicy = Dexpace::Transport::AsyncHTTP::DropPolicy
    EVENT = Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED

    def request(url, headers: {})
      builder = Dexpace::Request.builder
      builder.url = url
      headers.each { |name, value| builder.header(name, value) }
      builder.build
    end

    def borrowed(server, **)
      AsyncHTTP.using(::Async::HTTP::Client.new(server.client_endpoint, retries: 0), **)
    end
  end

  # TRANSPORT-12/13 over three protocol shapes, the default policy's once-per-name warning, and
  # the antecedent measured on protocol-http1.
  class TokenPredicateTest < DexpaceTestCase
    include WireGrammarTestSupport

    %i[http1 plaintext tls].each do |variant|
      test "TRANSPORT-12/13, P8-40 over #{variant}: a non-token name is dropped, the normal " \
           "header and body still dispatch, and the future completes normally" do
        Sync do
          server = AsyncHTTPServerFixture.public_send(variant) { |_req| [200, [], ["ok"]] }
          adapter = borrowed(server)
          req = request(server.url, headers: { "X-Bad:Name" => "v", "X-Normal" => "n" })

          response = adapter.call(req, nil, nil).value

          assert_equal(200, response.status.code)
          assert_equal("ok", response.body_string)
          names = server.received.last.map { |name, _| name.downcase }

          refute_includes(names, "x-bad:name")
          assert_includes(names, "x-normal")
        ensure
          server&.close
        end
      end
    end

    test "TRANSPORT-13: a real dispatch through the default policy warns once per distinct bad " \
         "name, then goes quiet" do
      sink = AsyncHTTPRecordingSink.new
      logger = Dexpace::Instrumentation::Logger.build(sink: sink)

      Sync do
        server = AsyncHTTPServerFixture.plaintext { |_req| [200, [], []] }
        adapter = borrowed(server, drop_policy: DropPolicy.build, logger: logger)
        req = request(server.url, headers: { "X-Bad:Name" => "v" })

        adapter.call(req, nil, nil).value.close
        adapter.call(req, nil, nil).value.close
        adapter.call(request(server.url, headers: { "y{bad}" => "v" }), nil, nil).value.close

        assert_equal(%i[warn debug warn], sink.severities(EVENT))
      ensure
        server&.close
      end
    end

    # The antecedent on HTTP/1.1, measured through the real library so the drop's reason is a
    # fact and not a citation: without the predicate, a model-valid name reaches protocol-http1,
    # which refuses it after the request line is on the wire.
    test "the antecedent: protocol-http1 refuses a model-valid non-token name that " \
         "protocol-http2 transmits" do
      Sync do
        h1 = AsyncHTTPServerFixture.http1 { |_req| [200, [], []] }
        h2 = AsyncHTTPServerFixture.plaintext { |_req| [200, [], []] }
        headers = ::Protocol::HTTP::Headers.new([["X-Bad:Name", "v"]])

        refused = assert_raises(::Protocol::HTTP::RefusedError) do
          ::Async::HTTP::Client.new(h1.client_endpoint, retries: 0).get("/", headers)
        end
        ::Async::HTTP::Client.new(h2.client_endpoint, retries: 0).get("/", headers).finish

        assert_kind_of(::Protocol::HTTP1::BadHeader, refused.cause)
        assert_includes(h2.received.last.map(&:first), "x-bad:name")
      ensure
        h1&.close
        h2&.close
      end
    end
  end

  # The wire-boundary re-validation over HTTP/2, its antecedent, and a name's spelling on each
  # protocol.
  class RevalidationTest < DexpaceTestCase
    include WireGrammarTestSupport

    # HTTP-17/HTTP-18/XCUT-18 over HTTP/2, where the re-validation is the ONLY defence: a forged
    # request carrying a CRLF value is refused before any byte reaches the peer, and the fixture
    # records nothing.
    test "wire-boundary re-validation over HTTP/2: a forged CRLF header value never reaches the " \
         "peer" do
      Sync do
        server = AsyncHTTPServerFixture.plaintext { |_req| [200, [], []] }
        adapter = borrowed(server)
        template = request(server.url)
        headers = Object.new
        headers.define_singleton_method(:each_entry) do |&block|
          block.call("x-inject", "a\r\nEvil: 1")
        end
        forged = Object.new
        forged.define_singleton_method(:method) { template.method }
        forged.define_singleton_method(:url) { template.url }
        forged.define_singleton_method(:headers) { headers }
        forged.define_singleton_method(:body) { nil }

        future = adapter.call(forged, nil, nil)

        assert_raises(Dexpace::InvalidArgumentError) { future.value }
        assert_empty(server.received)
      ensure
        server&.close
      end
    end

    # The counter-measurement for the test above: protocol-http2 itself transmits the CRLF value.
    test "the antecedent: protocol-http2 transmits a CRLF-bearing value verbatim" do
      Sync do
        server = AsyncHTTPServerFixture.plaintext { |_req| [200, [], []] }
        headers = ::Protocol::HTTP::Headers.new([["x-inject", "a\r\nEvil: 1"]])

        ::Async::HTTP::Client.new(server.client_endpoint, retries: 0).get("/", headers).finish

        assert_includes(server.received.last, ["x-inject", "a\r\nEvil: 1"])
      ensure
        server&.close
      end
    end

    test "a caller's mixed-case name reaches an HTTP/1.1 peer as spelled and an HTTP/2 peer " \
         "lowercased -- the intra-adapter folding hazard the suite compares folded for" do
      Sync do
        h1 = AsyncHTTPServerFixture.http1 { |_req| [200, [], []] }
        h2 = AsyncHTTPServerFixture.plaintext { |_req| [200, [], []] }
        [h1, h2].each do |server|
          borrowed(server).call(request(server.url, headers: { "X-MiXeD-CaSe" => "v" }), nil, nil)
            .value.close
        end

        assert_includes(h1.received.last.map(&:first), "X-MiXeD-CaSe")
        assert_includes(h2.received.last.map(&:first), "x-mixed-case")
      ensure
        h1&.close
        h2&.close
      end
    end
  end
end
