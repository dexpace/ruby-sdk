# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/assertion_probe"
require_relative "../../../support/raw_wire_transport"
require "dexpace/conformance"

# Group 7 (phase 8c): TRANSPORT-12 and 13, each proven in both directions against
# RawWireTransport's drop mode, and in the third direction the two share: VACUOUS by measurement
# against the plain double, which copies a model-valid non-token name to the wire exactly as
# Net::HTTP does.
class DexpaceConformanceHeaderDropsAssertionsTest < DexpaceTestCase
  include AssertionProbe

  # The build factory that honours the `logger:` setting TRANSPORT-13 passes.
  def raw_logged(*defects, drop_non_token: false)
    lambda do |logger: Dexpace::Instrumentation::Logger::NULL, **_settings|
      RawWireTransport.new(*defects, drop_non_token: drop_non_token, logger: logger)
    end
  end

  test "the group registers the last two assertions, after group six's four" do
    assert_equal([%w[TRANSPORT-12], %w[TRANSPORT-13]], Suite.assertions[32, 2].map(&:ids))
    assert_equal(34, Suite.assertions.size)
  end

  test "TRANSPORT-12: a dropped non-token name passes; a native refusal escaping fails; a native " \
       "client that sends it is vacuous by measurement" do
    assertion = find("TRANSPORT-12")

    assert_passes(assertion, build: raw_logged(drop_non_token: true))
    assert_fails(assertion, build: raw(:refuse_non_token), matching: /native exception escaped/)
    assert_vacuous(assertion, build: raw, matching: /antecedent is absent/)
  end

  test "TRANSPORT-13: once-per-name, bounded drops pass; every-drop-warns fails; a silent drop " \
       "fails; a native client that sends the name is vacuous by measurement" do
    assertion = find("TRANSPORT-13")

    assert_passes(assertion, build: raw_logged(drop_non_token: true))
    assert_fails(assertion, build: raw_logged(:drop_non_token_loudly),
                            matching: /warn once then go quiet/,)
    assert_fails(assertion, build: raw_logged(:drop_non_token_silently),
                            matching: /without a drop record/,)
    assert_vacuous(assertion, build: raw, matching: /antecedent is absent/)
  end
end
