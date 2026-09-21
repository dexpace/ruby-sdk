# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/assertion_probe"
require_relative "../../../support/raw_wire_transport"
require "dexpace/conformance"

# Group 1 (8a plan Task 9): TRANSPORT-10, TRANSPORT-11, TRANSPORT-26 and the wire-boundary
# re-validation (HTTP-17, HTTP-18, XCUT-18), each proven to pass against RawWireTransport's correct
# send and to fail against the one defect it was written to catch. The real adapter's run is the
# net_http gem's conformance_test.rb.
class DexpaceConformanceOutboundAssertionsTest < DexpaceTestCase
  include AssertionProbe

  test "the group registers seven assertions, in the chapter's order" do
    ids = Suite.assertions.first(7).map(&:ids)

    assert_equal([["TRANSPORT-10"], ["TRANSPORT-10"], ["TRANSPORT-10"], ["TRANSPORT-26"],
                  ["TRANSPORT-11"], %w[HTTP-17 XCUT-18], %w[HTTP-18 XCUT-18],], ids,)
  end

  test "TRANSPORT-10 (a): the explicit Content-Type wins: passes when kept, fails overridden" do
    assertion = find_all("TRANSPORT-10")[0]

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:override_type), matching: /overwritten/)
  end

  test "TRANSPORT-10 (b): the body's media type is used when the caller set none; ignored fails" do
    assertion = find_all("TRANSPORT-10")[1]

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:ignore_body_type), matching: /media type was not used/)
  end

  test "TRANSPORT-10 (c): a body with no media type is never sent as a form; stamped fails" do
    assertion = find_all("TRANSPORT-10")[2]

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:form_type), matching: /went out as a form/)
  end

  test "TRANSPORT-26: a body-less POST is a zero-length body; no Content-Length sent fails" do
    assertion = find("TRANSPORT-26")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:no_zero_length), matching: /zero-length/)
  end

  test "TRANSPORT-11: framing recomputed and pass-through kept; each clause fails on its defect" do
    assertion = find("TRANSPORT-11")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:forward_host),
                            matching: /framing headers were not recomputed/,)
    assert_fails(assertion, build: raw(:drop_pass_through),
                            matching: /pass-through header vanished/,)
  end

  # The socket count is the check that discriminates, and the error class alone would not:
  # Dexpace::Response.build refuses a request that is not a Dexpace::Request, so an adapter that
  # skipped the re-validation and SENT the forged bytes still raises InvalidArgumentError -- after
  # the injected header has reached the wire. Measured here with the double, recorded so nobody
  # weakens the assertion to the class check.
  # The failing direction reads the socket count: a non-validating double still raises after the
  # send, because Response.build refuses a forged Request, so only the connection count tells.
  test "HTTP-17 / HTTP-18: a forged CRLF name and value are each refused before dispatch" do
    name = find("HTTP-17")
    value = find("HTTP-18")

    assert_passes(name, build: raw)
    assert_passes(value, build: raw)
    assert_fails(name, build: raw(:skip_validation), matching: /reached the socket/)
    assert_fails(value, build: raw(:skip_validation), matching: /reached the socket/)
  end
end
