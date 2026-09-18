# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/challenge"

# Exercises: AUTH-12 -- one parsed challenge: scheme and parameter names folded once at
# construction with a bare downcase, values verbatim, the token68 key, frozen throughout.
class DexpaceAuthChallengeTest < DexpaceTestCase
  Challenge = Dexpace::Auth::Challenge

  test "AUTH-12: the scheme and the parameter names are lower-cased; values kept verbatim" do
    challenge = Challenge.build(scheme: "DiGeSt", params: { "REALM" => "MiXeD", "Nonce" => "N" })

    assert_equal("digest", challenge.scheme)
    assert_equal({ "realm" => "MiXeD", "nonce" => "N" }, challenge.params)
  end

  test "AUTH-12: the token68 value sits under the synthetic key" do
    challenge = Challenge.build(scheme: "Bearer", params: { "token68" => "abc==" })

    assert_equal("abc==", challenge.token68)
    assert_equal("token68", Challenge::TOKEN68)
    assert_nil(Challenge.build(scheme: "Basic").token68)
  end

  test "the params default to empty, are copied and frozen, and must be String to String" do
    params = { "realm" => "r" }
    challenge = Challenge.build(scheme: "basic", params: params)
    params["nonce"] = "n"

    assert_equal({ "realm" => "r" }, challenge.params)
    assert_predicate(challenge.params, :frozen?)
    assert_empty(Challenge.build(scheme: "basic").params)
    assert_raises(Dexpace::InvalidArgumentError) do
      Challenge.build(scheme: "b", params: { realm: "r" })
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Challenge.build(scheme: "b", params: { "r" => 1 })
    end
    assert_raises(Dexpace::InvalidArgumentError) { Challenge.build(scheme: "b", params: nil) }
  end

  test "the scheme must be a non-empty String" do
    assert_raises(Dexpace::InvalidArgumentError) { Challenge.build(scheme: "") }
    assert_raises(Dexpace::InvalidArgumentError) { Challenge.build(scheme: nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Challenge.build(scheme: :basic) }
  end

  test "the construction pattern: .new private, value equality, #with through .build" do
    refute_respond_to(Challenge, :new)

    assert_equal(Challenge.build(scheme: "basic"), Challenge.build(scheme: "BASIC"))
    assert_equal("digest", Challenge.build(scheme: "basic").with(scheme: "Digest").scheme)
  end
end
