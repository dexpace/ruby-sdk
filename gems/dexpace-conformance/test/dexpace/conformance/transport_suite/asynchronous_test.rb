# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/assertion_probe"
require_relative "../../../support/raw_wire_transport"
require "dexpace/conformance"

# Group 6 (phase 8c): TRANSPORT-7, 9, 21 and 23, each proven in both directions against
# RawWireTransport -- which reads bodies eagerly, so the mid-body cancellation surfaces from the
# send rather than from a later read, which is the shape the assertion admits. Phase 8c's other
# two rows, TRANSPORT-12 and 13, are group 7 (header_drops_test.rb).
class DexpaceConformanceAsynchronousAssertionsTest < DexpaceTestCase
  include AssertionProbe

  test "the group registers four assertions after the first twenty-eight, and no TRANSPORT-8" do
    assert_equal([%w[TRANSPORT-7], %w[TRANSPORT-9], %w[TRANSPORT-21], %w[TRANSPORT-23]],
                 Suite.assertions[28, 4].map(&:ids),)
    assert_equal(34, Suite.assertions.size)
    refute_includes(Suite.assertions.flat_map(&:ids), "TRANSPORT-8")
    assert_match(/TRANSPORT-8/, Suite::PREAMBLE)
  end

  test "TRANSPORT-7: a mid-body cancel as CancelledError with the connection released passes; " \
       "the same as a retryable failure fails" do
    assertion = find("TRANSPORT-7")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:misclassify_cancel), matching: /terminal interrupt/)
  end

  test "TRANSPORT-9: a response arriving after the cancel is not delivered passes; a transport " \
       "that ignores the token delivers it and fails" do
    assertion = find("TRANSPORT-9")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:ignore_cancel), matching: /delivered or misclassified/)
  end

  test "TRANSPORT-21: a classified adaptation failure passes; the raw exception escaping fails" do
    assertion = find("TRANSPORT-21")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:bare_adaptation), matching: /unclassified/)
  end

  test "TRANSPORT-23: a Dexpace::Response for a body and for none passes; a nil success fails" do
    assertion = find("TRANSPORT-23")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:null_success), matching: /other than a Dexpace::Response/)
  end
end
