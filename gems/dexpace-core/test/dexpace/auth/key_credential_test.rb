# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "pp"
require "stringio"
require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/key_credential"

# Exercises: AUTH-8, AUTH-9, AUTH-26 -- the API-key credential: non-blank key, a valid header
# name, reference identity, and the key absent from every rendering.
class DexpaceAuthKeyCredentialTest < DexpaceTestCase
  KeyCredential = Dexpace::Auth::KeyCredential

  test "AUTH-9: the api_key must be non-blank" do
    assert_raises(Dexpace::InvalidArgumentError) { KeyCredential.new(api_key: "") }
    assert_raises(Dexpace::InvalidArgumentError) { KeyCredential.new(api_key: "  ") }
    assert_raises(Dexpace::InvalidArgumentError) { KeyCredential.new(api_key: nil) }
  end

  test "AUTH-26: the header defaults to Authorization, the prefix to none" do
    credential = KeyCredential.new(api_key: "k")

    assert_equal("Authorization", credential.header_name)
    assert_nil(credential.prefix)
    assert_equal("k", credential.key_value)
  end

  test "the header name is validated as a field name, and a prefix must be non-blank" do
    credential = KeyCredential.new(api_key: "k", header_name: "X-Api-Key", prefix: "Key")

    assert_equal("X-Api-Key", credential.header_name)
    assert_equal("Key", credential.prefix)
    assert_raises(Dexpace::InvalidArgumentError) do
      KeyCredential.new(api_key: "k", header_name: "bad name")
    end
    assert_raises(Dexpace::InvalidArgumentError) { KeyCredential.new(api_key: "k", prefix: " ") }
  end

  test "AUTH-8: reference identity -- two instances with identical fields are NOT equal" do
    a = KeyCredential.new(api_key: "x")
    b = KeyCredential.new(api_key: "x")

    refute_equal(a, b)
    refute_operator(a, :eql?, b)
    refute_equal(a.hash, b.hash)
    assert_equal([a], [a] & [a])
  end

  test "AUTH-8: #to_s, #inspect and pp redact the key and show the header name and prefix" do
    credential = KeyCredential.new(api_key: "super-secret-key", header_name: "X-Api-Key",
                                   prefix: "Key",)
    output = StringIO.new
    PP.pp(credential, output)

    [credential.to_s, credential.inspect, output.string, [credential].inspect].each do |text|
      refute_includes(text, "super-secret")
      assert_includes(text, "X-Api-Key")
      assert_includes(text, "Key")
      assert_includes(text, Dexpace::Auth::REDACTED)
    end
    assert_equal("super-secret-key", credential.key_value)
  end

  test "frozen at the end of construction, its Strings copied" do
    key = +"k"
    credential = KeyCredential.new(api_key: key)
    key << "!"

    assert_predicate(credential, :frozen?)
    assert_equal("k", credential.key_value)
  end
end
