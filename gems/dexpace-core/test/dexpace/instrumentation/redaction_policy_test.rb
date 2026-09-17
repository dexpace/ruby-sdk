# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/instrumentation/redaction_policy"

# Exercises: OBS-12, OBS-17, OBS-18, XCUT-19
#
# The policy is a frozen Data of three folded Sets and one boolean, and it has NO member that can
# reach userinfo (OBS-11, XCUT-19(a)): that redaction is unconditional, and there is no keyword,
# field or configuration key that turns it off. The default membership is XCUT-19's audited
# subject (phase 9) and NFR-4 locks it, so it is asserted exactly, name by name.
class DexpaceInstrumentationRedactionPolicyTest < DexpaceTestCase
  Policy = Dexpace::Instrumentation::RedactionPolicy

  # P5-30: chosen, not derived. Twenty-six diagnostic, non-credential names; the credential
  # carriers (authorization, proxy-authorization, cookie, set-cookie, x-api-key) are absent, and
  # so are the two challenge headers, because a Digest challenge carries a server nonce and
  # whether that is loggable is AUTH's question (phase 6).
  DEFAULT_HEADERS = %w[
    accept accept-encoding cache-control connection content-encoding content-length
    content-location content-type date etag expires if-match if-modified-since if-none-match
    if-unmodified-since last-modified location retry-after server traceparent tracestate
    user-agent vary via x-correlation-id x-request-id
  ].freeze

  test "OBS-12, OBS-17, OBS-18: DEFAULT carries exactly the three default sets, marker mode" do
    policy = Policy::DEFAULT

    assert_predicate(policy, :frozen?)
    assert_equal(::Set["api-version"], policy.query_allow_list)
    assert_equal(::Set["location", "content-location"], policy.url_header_names)
    assert_equal(::Set.new(DEFAULT_HEADERS), policy.header_allow_list)
    assert_equal(26, policy.header_allow_list.size)
    refute(policy.omit_disallowed_headers, "P5-35: the marker, not omission, is the default")
    [policy.query_allow_list, policy.header_allow_list, policy.url_header_names].each do |set|
      assert_predicate(set, :frozen?)
    end
  end

  # OBS-18's negative, name by name: the credential and challenge headers are not in the list.
  test "OBS-18, XCUT-19: no credential-bearing or challenge header is allow-listed by default" do
    %w[authorization proxy-authorization cookie set-cookie x-api-key www-authenticate
       proxy-authenticate].each do |name|
      refute_includes(Policy::DEFAULT.header_allow_list, name, name)
    end
  end

  test "XCUT-19: the policy has no member that can reach userinfo" do
    assert_equal(%i[query_allow_list header_allow_list url_header_names omit_disallowed_headers],
                 Policy.members,)
    refute(Policy.members.any? { |member| member.to_s.include?("userinfo") })
  end

  test "OBS-12: .build folds every name with a locale-free downcase into frozen Sets" do
    custom = Policy.build(
      query_allow_list: ["Api-Version", :Page, "İd"],
      header_allow_list: %w[Content-Type Accept],
      url_header_names: ["Location"],
      omit_disallowed_headers: :truthy,
    )

    assert_equal(::Set["api-version", "page", "i̇d"], custom.query_allow_list)
    assert_equal(::Set["content-type", "accept"], custom.header_allow_list)
    assert_equal(::Set["location"], custom.url_header_names)
    assert_equal(true, custom.omit_disallowed_headers) # rubocop:disable Minitest/AssertTruthy -- the boolean, not a truthy value
    assert_predicate(custom, :frozen?)
    assert_predicate(custom.query_allow_list, :frozen?)
  end

  test "OBS-12: an empty query allow-list is a real value, so every parameter is redacted" do
    policy = Policy.build(query_allow_list: [])

    assert_empty(policy.query_allow_list)
    refute_includes(policy.query_allow_list, "api-version")
  end

  test "OBS-12: a list holding something that is not a name is refused at construction" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Policy.build(query_allow_list: [nil]) }
    assert_match(/query_allow_list/, error.message)
    assert_raises(Dexpace::InvalidArgumentError) { Policy.build(header_allow_list: nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Policy.build(url_header_names: "location") }
  end

  # Model#with routes through .build (never Data#with, which skips the initialize override on
  # Ruby 3.2), so a derived policy is re-folded and re-frozen.
  test "OBS-17: #with derives a policy through the validating .build and leaves DEFAULT alone" do
    derived = Policy::DEFAULT.with(omit_disallowed_headers: true, url_header_names: ["Link"])

    assert(derived.omit_disallowed_headers)
    assert_equal(::Set["link"], derived.url_header_names)
    assert_equal(Policy::DEFAULT.query_allow_list, derived.query_allow_list)
    assert_equal(Policy::DEFAULT.header_allow_list, derived.header_allow_list)
    refute(Policy::DEFAULT.omit_disallowed_headers)
    assert_same(Policy::DEFAULT, Policy::DEFAULT.with)
    refute_respond_to(Policy, :new)
  end
end
