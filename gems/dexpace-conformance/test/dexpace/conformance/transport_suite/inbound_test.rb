# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/assertion_probe"
require_relative "../../../support/stub_transport"
require "dexpace/conformance"

# Group 2 (8a plan Task 10): TRANSPORT-24, TRANSPORT-14 and TRANSPORT-27, each proven to pass
# against a hand-built conforming response and to fail against the one hand-built defect it was
# written for. The stub never touches the fixture: every question these assertions ask is of the
# Dexpace::Response, which is the point (suite contract clauses 2, 6, 7).
class DexpaceConformanceInboundAssertionsTest < DexpaceTestCase
  include AssertionProbe

  def inbound(pairs)
    builder = Dexpace::Headers.inbound_builder
    pairs.each { |name, values| Array(values).each { |value| builder.add(name, value) } }
    builder.build
  end

  def response_of(status:, body:, headers: Dexpace::Headers::EMPTY_INBOUND, media_type: nil,
                  content_length: body.bytesize)
    lambda do |request, _options, _cancellation|
      Dexpace::Response.build(
        request: request, protocol: "HTTP/1.1", status: status, headers: headers,
        body: Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(body.b),
                                        media_type: media_type, content_length: content_length,),
      )
    end
  end

  def stub(&on_call)
    ->(**_settings) { StubTransport.new(&on_call) }
  end

  test "the group registers four assertions after the outbound seven" do
    assert_equal([["TRANSPORT-24"], ["TRANSPORT-14"], ["TRANSPORT-14"], ["TRANSPORT-27"]],
                 Suite.assertions[7, 4].map(&:ids),)
  end

  test "TRANSPORT-24: a 520 with a body passes; a status quietly normalised to 502 fails" do
    assertion = find("TRANSPORT-24")

    assert_passes(assertion, build: stub(&response_of(status: 520, body: "vendor error")))
    assert_fails(assertion, build: stub(&response_of(status: 502, body: "vendor error")),
                            matching: /not surfaced faithfully/,)
  end

  test "TRANSPORT-14: obs-text kept and malformed headers dropped pass; stripped obs-text fails" do
    assertion = find_all("TRANSPORT-14")[0]
    kept = inbound("X-Obs" => "caf\xE9".b, "X-Ok" => "fine", "Set-Cookie" => %w[a=1 b=2])
    stripped = inbound("X-Obs" => "caf?", "X-Ok" => "fine")

    assert_passes(assertion, build: stub(&response_of(status: 200, body: "hi", headers: kept)))
    assert_fails(assertion, build: stub(&response_of(status: 200, body: "hi", headers: stripped)),
                            matching: /leniency did not hold/,)
  end

  test "TRANSPORT-14: two Set-Cookie values pass; a joined one fails" do
    assertion = find_all("TRANSPORT-14")[1]
    two = inbound("Set-Cookie" => %w[a=1 b=2])
    joined = inbound("Set-Cookie" => "a=1, b=2")

    assert_passes(assertion, build: stub(&response_of(status: 200, body: "hi", headers: two)))
    assert_fails(assertion, build: stub(&response_of(status: 200, body: "hi", headers: joined)),
                            matching: /collapsed/,)
  end

  test "TRANSPORT-27: nil media type, -1 length and a readable body pass; a length or type fails" do
    assertion = find("TRANSPORT-27")

    assert_passes(assertion, build: stub(&response_of(status: 200, body: "hi", content_length: -1)))
    assert_fails(assertion, build: stub(&response_of(status: 200, body: "hi", content_length: 2)),
                            matching: /downgrade did not hold/,)
    typed = response_of(status: 200, body: "hi", content_length: -1,
                        media_type: Dexpace::MediaType.parse("text/plain"),)

    assert_fails(assertion, build: stub(&typed), matching: /downgrade did not hold/)
  end
end
