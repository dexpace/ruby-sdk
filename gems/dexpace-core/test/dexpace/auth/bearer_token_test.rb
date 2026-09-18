# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "pp"
require "stringio"
require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/bearer_token"

# Exercises: AUTH-8, AUTH-9, AUTH-10 -- the bearer token: non-blank, optional expiry with an
# additive margin, value equality over the real fields, and the secret absent from every
# rendering Ruby has, pp included.
class DexpaceAuthBearerTokenTest < DexpaceTestCase
  BearerToken = Dexpace::Auth::BearerToken

  def token(value = "SECRET-TOKEN", expiry: nil) = BearerToken.build(token: value, expiry: expiry)

  test "AUTH-9: the token must be non-blank: nil, empty and whitespace-only are all refused" do
    assert_equal("token is required",
                 assert_raises(Dexpace::InvalidArgumentError) { token(nil) }.message,)
    assert_equal("token must not be blank",
                 assert_raises(Dexpace::InvalidArgumentError) { token("") }.message,)
    assert_raises(Dexpace::InvalidArgumentError) { token("   ") }
    assert_raises(Dexpace::InvalidArgumentError) { token("\t\n") }
    assert_raises(Dexpace::InvalidArgumentError) { token(:sym) }
  end

  test "AUTH-10: a nil expiry never expires, whatever the margin" do
    never = token(expiry: nil)

    refute(never.expired?(now: Time.at(10**12), margin: 0))
    refute(never.expired?(now: Time.at(10**12), margin: 10**9))
    assert_nil(never.expiry)
  end

  test "AUTH-10: expired iff (now + margin) is STRICTLY after the expiry" do
    expiring = token(expiry: Time.at(1000))

    refute(expiring.expired?(now: Time.at(994), margin: 5)) # 999, not after 1000
    refute(expiring.expired?(now: Time.at(995), margin: 5)) # 1000, not strictly after
    assert(expiring.expired?(now: Time.at(996), margin: 5)) # 1001
    refute(expiring.expired?(now: Time.at(1000)))           # margin defaults to 0
    assert(expiring.expired?(now: Time.at(1001)))
  end

  test "the expiry must be a Time or nil" do
    assert_raises(Dexpace::InvalidArgumentError) { token(expiry: 1000) }
  end

  test "AUTH-8: #to_s and #inspect redact the token and show the expiry" do
    secret = token("super-secret-token", expiry: Time.at(1000).utc)

    refute_includes(secret.to_s, "super-secret")
    refute_includes(secret.inspect, "super-secret")
    refute_includes(secret.to_s, "super-secret")
    assert_includes(secret.to_s, Dexpace::Auth::REDACTED)
    assert_includes(secret.inspect, "1970-01-01 00:16:40 UTC")
    assert_includes([secret].inspect, Dexpace::Auth::REDACTED)
  end

  # pp does not call #inspect on a Data -- pp.rb gives Data its own #pretty_print that walks the
  # members -- so this is the rendering a two-override credential leaks through.
  test "AUTH-8: pp does not print the token either" do
    output = StringIO.new
    PP.pp(token("super-secret-token"), output)

    refute_includes(output.string, "super-secret")
    assert_includes(output.string, Dexpace::Auth::REDACTED)
  end

  test "AUTH-8: redaction corrupts nothing -- the real field is intact and read by the stamper" do
    secret = token("super-secret-token")
    secret.inspect

    assert_equal("super-secret-token", secret.token)
    assert_equal({ token: "super-secret-token", expiry: nil }, secret.to_h)
  end

  test "AUTH-8: value equality and hashing over the real token and expiry, not the redacted form" do
    a = token("t", expiry: Time.at(1))
    b = token("t", expiry: Time.at(1))

    assert_equal(a, b)
    assert_equal(a.hash, b.hash)
    refute_equal(a, token("u", expiry: Time.at(1)))
    refute_equal(a, token("t", expiry: Time.at(2)))
    assert_equal(token("t").inspect, token("u").inspect) # equal renderings, unequal tokens
  end

  test "the construction pattern: .new private, frozen, #with re-validates through .build" do
    refute_respond_to(BearerToken, :new)
    secret = token("t")

    assert_predicate(secret, :frozen?)
    assert_equal(Time.at(5), secret.with(expiry: Time.at(5)).expiry)
    assert_raises(Dexpace::InvalidArgumentError) { secret.with(token: " ") }
  end
end
