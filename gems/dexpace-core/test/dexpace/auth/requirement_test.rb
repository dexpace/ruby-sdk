# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/requirement"

# Exercises: AUTH-2 -- one scheme bound to its own scopes and params, immutable against a
# caller's later mutation of the retained collections (the deep half included), value equality
# over the three members, and #with routed through .build.
class DexpaceAuthRequirementTest < DexpaceTestCase
  Requirement = Dexpace::Auth::Requirement
  Scheme = Dexpace::Auth::Scheme

  test "AUTH-2: binds one scheme to its own scopes and params" do
    requirement = Requirement.build(scheme: Scheme::OAUTH2, scopes: %w[read write],
                                    params: { "aud" => "api" },)

    assert_same(Scheme::OAUTH2, requirement.scheme)
    assert_equal(%w[read write], requirement.scopes)
    assert_equal({ "aud" => "api" }, requirement.params)
  end

  test "AUTH-2: the collections default to empty and are preserved for every scheme" do
    requirement = Requirement.build(scheme: Scheme::BASIC)

    assert_empty(requirement.scopes)
    assert_empty(requirement.params)
    assert_equal(["x"], Requirement.build(scheme: Scheme::BASIC, scopes: ["x"]).scopes)
  end

  test "AUTH-2: a later mutation of the caller's collection cannot reach the stored value" do
    scopes = [+"read"]
    params = { "aud" => [+"api"] }
    requirement = Requirement.build(scheme: Scheme::OAUTH2, scopes: scopes, params: params)
    scopes << "write"
    params["aud"] << "other"

    assert_equal(["read"], requirement.scopes)
    assert_equal({ "aud" => ["api"] }, requirement.params)
  end

  # The half a shallow dup.freeze passes and still gets wrong: the caller mutates a String
  # INSIDE the retained collection. The fixture uses +"read" because a frozen literal would
  # raise FrozenError at the caller's own `<<` before proving anything.
  test "AUTH-2: a caller mutating a String INSIDE a retained collection cannot reach it" do
    scopes = [+"read"]
    params = { "aud" => [+"api"] }
    requirement = Requirement.build(scheme: Scheme::OAUTH2, scopes: scopes, params: params)
    scopes[0] << ":write"
    params["aud"][0] << ":other"

    assert_equal(["read"], requirement.scopes)
    assert_equal({ "aud" => ["api"] }, requirement.params)
    assert_predicate(requirement.scopes[0], :frozen?)
  end

  test "HTTP-5's pattern: the same frozen reference from every accessor" do
    requirement = Requirement.build(scheme: Scheme::OAUTH2, scopes: ["read"])

    assert_same(requirement.scopes, requirement.scopes)
    assert_predicate(requirement.scopes, :frozen?)
    assert_predicate(requirement.params, :frozen?)
  end

  test "AUTH-2: value equality over scheme, scopes and params" do
    a = Requirement.build(scheme: Scheme::BASIC, scopes: ["r"], params: { "k" => "v" })
    b = Requirement.build(scheme: "basic", scopes: ["r"], params: { "k" => "v" })

    assert_equal(a, b)
    assert_equal(a.hash, b.hash)
    refute_equal(a, Requirement.build(scheme: Scheme::BASIC, scopes: ["w"], params: { "k" => "v" }))
    refute_equal(a,
                 Requirement.build(scheme: Scheme::DIGEST, scopes: ["r"], params: { "k" => "v" }),)
  end

  test "the scheme is resolved through Scheme.of, and an unknown one is refused" do
    assert_same(Scheme::DIGEST, Requirement.build(scheme: :digest).scheme)
    assert_raises(Dexpace::InvalidArgumentError) { Requirement.build(scheme: "NTLM") }
    assert_raises(Dexpace::InvalidArgumentError) { Requirement.build(scheme: nil) }
  end

  test "the collections must be an Array and a Hash" do
    assert_raises(Dexpace::InvalidArgumentError) { Requirement.build(scheme: :basic, scopes: "r") }
    assert_raises(Dexpace::InvalidArgumentError) { Requirement.build(scheme: :basic, params: []) }
  end

  test "the construction pattern: .new private, #with re-validates through .build" do
    refute_respond_to(Requirement, :new)
    requirement = Requirement.build(scheme: Scheme::BASIC)
    derived = requirement.with(scheme: Scheme::DIGEST)

    assert_same(Scheme::DIGEST, derived.scheme)
    assert_same(requirement, requirement.with)
    assert_raises(Dexpace::InvalidArgumentError) { requirement.with(scheme: "NTLM") }
  end
end
