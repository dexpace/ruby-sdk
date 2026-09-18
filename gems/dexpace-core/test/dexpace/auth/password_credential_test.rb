# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "pp"
require "stringio"
require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/password_credential"

# Exercises: AUTH-8, AUTH-14 (P6-3) -- the username/password pair: no blank check at
# construction (AUTH-9 does not name this type, and AUTH-14's laxer rule lives at the
# handlers), value equality, both fields redacted in every rendering.
class DexpaceAuthPasswordCredentialTest < DexpaceTestCase
  PasswordCredential = Dexpace::Auth::PasswordCredential

  test "P6-3: an empty or whitespace-only field is ACCEPTED; only nil and a non-String refused" do
    assert_equal("", PasswordCredential.build(username: "u", password: "").password)
    assert_equal("   ", PasswordCredential.build(username: "u", password: "   ").password)
    assert_equal("", PasswordCredential.build(username: "", password: "p").username)
    assert_equal("username is required",
                 assert_raises(Dexpace::InvalidArgumentError) do
                   PasswordCredential.build(username: nil, password: "p")
                 end.message,)
    assert_raises(Dexpace::InvalidArgumentError) do
      PasswordCredential.build(username: "u", password: 1)
    end
  end

  test "AUTH-8: both fields redacted in #to_s, #inspect and pp; the real fields intact" do
    credential = PasswordCredential.build(username: "alice-user", password: "super-secret")
    output = StringIO.new
    PP.pp(credential, output)

    [credential.to_s, credential.inspect, output.string, credential.to_s].each do |text|
      refute_includes(text, "super-secret")
      refute_includes(text, "alice-user")
      assert_includes(text, Dexpace::Auth::REDACTED)
    end
    assert_equal("alice-user", credential.username)
    assert_equal("super-secret", credential.password)
  end

  test "value equality over both fields, unaffected by the redacted form" do
    a = PasswordCredential.build(username: "u", password: "p")

    assert_equal(a, PasswordCredential.build(username: "u", password: "p"))
    refute_equal(a, PasswordCredential.build(username: "u", password: "q"))
    assert_equal(a.inspect, PasswordCredential.build(username: "u", password: "q").inspect)
  end

  test "the construction pattern: .new private, frozen copies, #with through .build" do
    refute_respond_to(PasswordCredential, :new)
    password = +"p"
    credential = PasswordCredential.build(username: "u", password: password)
    password << "!"

    assert_equal("p", credential.password)
    assert_equal("v", credential.with(username: "v").username)
    assert_raises(Dexpace::InvalidArgumentError) { credential.with(password: nil) }
  end
end
