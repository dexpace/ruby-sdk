# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/transport/async_http"
require "dexpace/conformance"

# The second driver over the shared conformance suite (8a's R16, the suite contract): every
# assertion 8a wrote and the six 8c added, run unchanged against the real asynchronous adapter
# through MinitestDriver, with the three mechanisms the suite contract added for exactly this
# driver -- `settle:` awaits the future, `around:` opens the reactor an assertion's body runs
# inside, and `borrow:` builds the caller's own client -- and two NAMED WAIVERS, both this
# adapter's alone (§9.3's mechanism, the id listed so the gap stays visible):
#
# - TRANSPORT-14's malformed-inbound-NAME clause: protocol-http1 raises BadHeader out of the read
#   before a response exists to adapt (P8-38). The suite carries TWO assertions under that id,
#   the per-header leniency and the multi-valued Set-Cookie, both over the same script whose
#   non-ASCII name refuses the whole head here, so the one waiver skips both (a waiver is by id,
#   design §9.3); the obs-text, control-byte-in-a-value and multi-valued halves are asserted in
#   response_mapper_test.rb.
# - TRANSPORT-27's invalid-Content-Length clause: Protocol::HTTP1::BadRequest out of the read, no
#   response object to downgrade; the malformed-Content-Type half is asserted in
#   response_mapper_test.rb. 8a's driver waives nothing: Net::HTTP delivers both heads.
#
# TRANSPORT-18 reports vacuous by measurement (a skip): with `retries: 0` no native
# re-subscription exists to measure, exactly as on 8a's adapter. So this driver's run is four
# skips -- three waived over two ids, one vacuous -- and every other assertion passes,
# TRANSPORT-12 and TRANSPORT-13 included, which are vacuous by measurement on 8a's adapter and
# real here.
#
# The reactor shape, decided 2026-09-21: an assertion that settles from another OS thread
# (TRANSPORT-5's pair, TRANSPORT-29's eight) opens a reactor of its own per settle, because the
# adapter creates none (P8-39) and one async-http client cannot be shared across reactors on
# different threads -- the client map is keyed by (reactor, origin), so each such reactor gets
# its own client and the map's cap retires the ones whose reactor has exited. `kase.teardown`
# runs outside `around:`, so `Adapter#close` is reactor-free by construction.
#
# And a response never outlives the reactor that produced it: `Sync` returns only when the
# reactor has no work left, stopping the pool's transient gardener first, whose `ensure` closes
# the pool by DRAINING it -- a wait on every busy connection, and the connection behind an
# unread body is busy until that body is read or closed. Hand a streaming response out of a
# `Sync` and the `Sync` never returns (found by TRANSPORT-29's hang, 2026-09-21; the README
# states the same rule for a consumer). So the per-settle reactor materialises the body inside
# itself through Response#body_bytes -- the connection is released there, the reactor exits --
# and hands the assertion a replayable BufferBody with the same media type, which reads exactly
# as the streamed one would have. `body_bytes` is loud past the materialisation ceiling, never a
# markerless truncation, which is why it is that and not Body.buffer_bounded.
class DexpaceTransportAsyncHTTPConformanceTest < DexpaceTestCase
  extend Dexpace::Conformance::MinitestDriver

  AsyncHTTP = Dexpace::Transport::AsyncHTTP
  WAIVED = %w[TRANSPORT-14 TRANSPORT-27].freeze

  # Runs the block inside the calling fiber's reactor, or a fresh one when the thread has none.
  def self.in_reactor(&)
    ::Async::Task.current? ? yield : Sync(&)
  end

  # The settle for a thread with no reactor of its own: a fresh reactor, closed before this
  # returns, with the body read inside it (see the header) -- a bodyless response goes out as it
  # is.
  def self.settle_in_own_reactor(transport, request, options, cancellation)
    Sync do
      response = transport.call(request, options, cancellation).value(cancellation: cancellation)
      body = response.body
      next response if body.nil?

      buffer = Dexpace::IO::Buffer.new
      buffer.write(response.body_bytes)
      response.with(body: Dexpace::Body.buffer(buffer, media_type: body.media_type))
    end
  end

  conformance(
    Dexpace::Conformance::TransportSuite,
    # Clause 4: a FACTORY, never an instance and never a constant; the two settings the contract
    # allows, `timeout:` and `logger:`, are `.build`'s own keywords.
    build: ->(**settings) { AsyncHTTP.build(**settings) },
    # Clause 4a: the factory takes the fixture's PORT and returns a BorrowedPair, so no assertion
    # inside dexpace-conformance ever names Async::HTTP::Client. The client is built where the
    # assertion runs -- inside `around:`'s reactor, the one it is then bound to -- with
    # `retries: 0` set by the CALLER, never by `.using`, which refuses a client that lacks it.
    # The probe is a real round trip through the client itself.
    borrow: lambda do |port|
      uri = ::URI::RFC3986_PARSER.parse("http://127.0.0.1:#{port}")
      client = ::Async::HTTP::Client.new(::Async::HTTP::Endpoint.new(uri), retries: 0)
      Dexpace::Conformance::BorrowedPair.build(
        transport: AsyncHTTP.using(client),
        probe: lambda do
          in_reactor { client.get("/").read == "ok" }
        rescue ::StandardError
          false
        end,
      )
    end,
    # Clause 8: `send` is ONE primitive and the async driver is what awaits the future; a
    # cancellation surfaces from here as Dexpace::CancelledError because Completer#request_cancel
    # settles the cancellation Future#value re-raises (clause 5). Inside `around:`'s reactor the
    # response streams; from a thread of the assertion's own it is materialised (header).
    settle: lambda do |transport, request, options, cancellation|
      if ::Async::Task.current?
        transport.call(request, options, cancellation).value(cancellation: cancellation)
      else
        settle_in_own_reactor(transport, request, options, cancellation)
      end
    end,
    # Clause 9: the runner INVOKES each assertion, so this driver wraps it in the reactor the
    # adapter needs (P8-39) and a streamed body is read inside.
    around: ->(&block) { Sync { block.call } },
    waive: WAIVED,
  )

  # The driver's own contract, checked rather than assumed: every assertion became a test method,
  # and the skips this run reports are exactly the ones the header accounts for.
  test "one generated test per assertion, and the two waivers are the named ones" do
    generated = public_methods(false).grep(/\Atest_/).reject do |name|
      name.to_s.start_with?("test_: ")
    end
    ids = Dexpace::Conformance::TransportSuite.assertions.flat_map(&:ids).uniq

    assert_equal(Dexpace::Conformance::TransportSuite.assertions.size, generated.size)
    assert_equal(34, generated.size)
    assert_equal(%w[TRANSPORT-14 TRANSPORT-27], WAIVED)
    assert_empty(WAIVED - ids, "a waiver must name an id the suite carries")
    assert_includes(ids, "TRANSPORT-12")
    assert_includes(ids, "TRANSPORT-13")
    refute_includes(ids, "TRANSPORT-8")
  end

  # The waiver's antecedent, measured rather than cited: the head 8a's WireServer script writes
  # for TRANSPORT-14 makes protocol-http1 refuse the whole response, and the one for TRANSPORT-27
  # the same, so this adapter never sees a response object for either.
  test "the two waived clauses are unreachable here: protocol-http1 refuses both heads out of " \
       "the read, as retryable transport failures" do
    %i[malformed_headers malformed_content_length].each do |script|
      server = Dexpace::Conformance::WireServer.start(Dexpace::Conformance::Scripts.public_send(script))
      adapter = AsyncHTTP.build
      request = Dexpace::Request.build(method: "GET", url: "http://127.0.0.1:#{server.port}/",
                                       headers: Dexpace::Headers::EMPTY, body: nil,)
      begin
        Sync do
          error = assert_raises(Dexpace::TransportError) do
            adapter.call(request, nil, nil).value(deadline: Dexpace::Clock.deadline_in(5))
          end

          assert_predicate(error, :retryable?, script.to_s)
          assert_kind_of(::Protocol::HTTP1::Error, error.cause, script.to_s)
        end
      ensure
        adapter.close
        server.close
      end
    end
  end
end
