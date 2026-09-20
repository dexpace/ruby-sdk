# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/assertion_probe"
require_relative "../../../support/raw_wire_transport"
require_relative "../../../support/stub_transport"
require "dexpace/conformance"

# Group 3 (8a plan Task 11): TRANSPORT-25, TRANSPORT-19 and TRANSPORT-28's reachable clauses, each
# proven in both directions. TRANSPORT-19's subject is the response's own close, so its two
# directions are hand-built responses whose close is instant or slow.
class DexpaceConformanceStreamingAssertionsTest < DexpaceTestCase
  include AssertionProbe

  # A response whose body close takes `close_seconds` -- the slow one SIMULATES a producer that
  # is waited for, which is the behaviour under test and the only sleep in this file. The body is
  # a duck answering #source and #close (P3-23), which is all Response#close is written against.
  def response_closing_in(close_seconds)
    lambda do |request, _options, _cancellation|
      inner = Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes("aaaaa".b))
      slow = Object.new
      slow.define_singleton_method(:source) { inner.source }
      slow.define_singleton_method(:media_type) { nil }
      slow.define_singleton_method(:content_length) { -1 }
      slow.define_singleton_method(:close) do
        sleep(close_seconds)
        inner.close
      end
      Dexpace::Response.build(request: request, protocol: "HTTP/1.1", status: 200,
                              headers: Dexpace::Headers::EMPTY_INBOUND, body: slow,)
    end
  end

  test "the group registers three assertions after the first eleven" do
    assert_equal([["TRANSPORT-25"], ["TRANSPORT-19"], ["TRANSPORT-28"]],
                 Suite.assertions[11, 3].map(&:ids),)
  end

  test "TRANSPORT-25: a byte-exact multi-megabyte round trip with the connection released passes" do
    assert_passes(find("TRANSPORT-25"), build: raw)
  end

  test "TRANSPORT-25: a short read fails on the bytes; a connection left open fails on release" do
    assertion = find("TRANSPORT-25")

    assert_fails(assertion, build: raw(:short_read), matching: /byte-exactly/)
    assert_fails(assertion, build: raw(:leave_open), matching: /did not release the connection/)
  end

  test "TRANSPORT-19: an instant, idempotent close passes; one that waits for the producer fails" do
    assertion = find("TRANSPORT-19")

    assert_passes(assertion, build: ->(**_) { StubTransport.new(&response_closing_in(0)) })
    assert_fails(assertion, build: ->(**_) { StubTransport.new(&response_closing_in(1.2)) },
                            matching: /blocked/,)
  end

  test "TRANSPORT-28: the file window reaches the wire and the body replays; whole file fails" do
    assertion = find("TRANSPORT-28")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:ignore_window), matching: /byte range was not honoured/)
  end
end
