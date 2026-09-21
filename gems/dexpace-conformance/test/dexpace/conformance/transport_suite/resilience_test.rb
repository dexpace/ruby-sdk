# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/assertion_probe"
require_relative "../../../support/raw_wire_transport"
require "dexpace/conformance"

# Group 4 (8a plan Task 12): TRANSPORT-1, 2, 3, 4, 17, 18, 20 and 22, each proven in both
# directions against RawWireTransport. TRANSPORT-18 is the one whose correct outcome is Vacuous:
# vacuity is measured, and the double that re-sends on its own turns it into a Failure.
class DexpaceConformanceResilienceAssertionsTest < DexpaceTestCase
  include AssertionProbe

  test "the group registers eight assertions after the first fourteen" do
    ids = Suite.assertions[14, 8].map(&:ids)

    assert_equal([["TRANSPORT-1"], ["TRANSPORT-2"], ["TRANSPORT-3"], ["TRANSPORT-4"],
                  ["TRANSPORT-17"], ["TRANSPORT-18"], ["TRANSPORT-20"], ["TRANSPORT-22"],], ids,)
  end

  test "TRANSPORT-1: a raw 302 returned passes; a transport that follows it fails" do
    assertion = find("TRANSPORT-1")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:pretend_followed), matching: /redirect was followed/)
  end

  test "TRANSPORT-2: one connection, one pull over a dropped attempt passes; native retry fails" do
    assertion = find("TRANSPORT-2")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:retry_once), matching: /silently retried/)
  end

  test "TRANSPORT-3: a cancel as CancelledError passes; the same as a retryable failure fails" do
    assertion = find("TRANSPORT-3")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:misclassify_cancel), matching: /swallowed or misclassified/)
  end

  test "TRANSPORT-4: a retryable timeout with the flag clear passes; raised as a cancel, fails" do
    assertion = find("TRANSPORT-4")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:cancel_on_timeout), matching: /did not classify retryable/)
    assert_fails(assertion, build: raw(:non_retryable_timeout),
                            matching: /did not classify retryable/,)
  end

  test "TRANSPORT-17: one request, one pull, the bytes intact passes; a second send fails" do
    assertion = find("TRANSPORT-17")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:send_twice), matching: /more than once/)
  end

  test "TRANSPORT-18: vacuous by measurement when nothing re-subscribed; a native re-send fails" do
    assertion = find("TRANSPORT-18")

    assert_vacuous(assertion, build: raw, matching: /antecedent is absent/)
    assert_fails(assertion, build: raw(:retry_once), matching: /re-subscribed/)
  end

  test "TRANSPORT-20: a refused connection as the retryable failure passes; a bare Errno fails" do
    assertion = find("TRANSPORT-20")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:bare_errno), matching: /was not retryable/)
  end

  test "TRANSPORT-22: a released connection after a caller failure passes; one left open fails" do
    assertion = find("TRANSPORT-22")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:leave_open), matching: /not released/)
  end
end
