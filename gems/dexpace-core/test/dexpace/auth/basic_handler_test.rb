# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/basic_handler"
require_relative "../../support/auth_fixtures"

# Exercises: AUTH-14 -- Basic: `Basic ` + pack("m0") of the UTF-8 bytes, computed once and
# reused by both roles, the challenge accepted case-insensitively, non-empty (not non-blank)
# credentials, and never Base64.
class DexpaceAuthBasicHandlerTest < DexpaceTestCase
  include AuthFixtures

  BasicHandler = Dexpace::Auth::BasicHandler
  Challenge = Dexpace::Auth::Challenge

  def credential(username: "alice", password: "s3cr3t")
    Dexpace::Auth::PasswordCredential.build(username: username, password: password)
  end

  def challenge(scheme) = Challenge.build(scheme: scheme)

  test "AUTH-14: the value is Basic plus the base64 of username:password" do
    handler = BasicHandler.new(credential)

    assert_equal("Basic YWxpY2U6czNjcjN0",
                 handler.authorization_for([challenge("basic")], https_request, proxy: false),)
  end

  test "AUTH-14: the UTF-8 bytes of a non-ASCII credential are what is encoded, whatever its tag" do
    handler = BasicHandler.new(credential(username: "ü", password: "pä"))
    value = handler.authorization_for([challenge("basic")], https_request, proxy: false)

    assert_equal("Basic w7w6cMOk", value)
    assert_predicate(value, :ascii_only?)
    latin1 = credential(username: "ü".encode("ISO-8859-1"), password: "pä".encode("ISO-8859-1"))
    stamped = BasicHandler.new(latin1).call(https_request)

    assert_equal("Basic w7w6cMOk", stamped.headers["Authorization"].first)
  end

  test "AUTH-14: computed once -- both roles return the same frozen String object" do
    handler = BasicHandler.new(credential)
    answered = handler.authorization_for([challenge("basic")], https_request, proxy: false)

    assert_same(answered,
                handler.authorization_for([challenge("basic")], https_request, proxy: true),)
    assert_same(answered, handler.call(https_request).headers["Authorization"].first)
    assert_predicate(answered, :frozen?)
    assert_predicate(handler, :frozen?)
  end

  test "AUTH-14: a Basic challenge is accepted case-insensitively, any other declined" do
    handler = BasicHandler.new(credential)

    refute_nil(handler.authorization_for([challenge("BASIC")], https_request, proxy: false))
    refute_nil(handler.authorization_for([challenge("digest"), challenge("Basic")], https_request,
                                         proxy: false,))
    assert_nil(handler.authorization_for([challenge("digest")], https_request, proxy: false))
    assert_nil(handler.authorization_for([], https_request, proxy: false))
  end

  test "AUTH-14 preemptively: #call stamps Authorization with no challenge, and SETS it" do
    handler = BasicHandler.new(credential)
    already = https_request(headers: Dexpace::Headers.builder.add("Authorization", "old").build)

    assert_equal(["Basic YWxpY2U6czNjcjN0"], handler.call(https_request).headers["Authorization"])
    assert_equal(["Basic YWxpY2U6czNjcjN0"], handler.call(already).headers["Authorization"])
  end

  test "AUTH-14's laxer rule: whitespace-only is permitted; empty is refused" do
    BasicHandler.new(credential(password: "   "))
    BasicHandler.new(credential(username: " "))

    assert_raises(Dexpace::InvalidArgumentError) { BasicHandler.new(credential(username: "")) }
    assert_raises(Dexpace::InvalidArgumentError) { BasicHandler.new(credential(password: "")) }
    assert_raises(Dexpace::InvalidArgumentError) { BasicHandler.new("alice:s3cr3t") }
  end

  test "RFC 7617 §2: a username carrying a colon cannot be encoded unambiguously and is refused" do
    assert_raises(Dexpace::InvalidArgumentError) { BasicHandler.new(credential(username: "a:b")) }
  end

  test "never Base64: the source spells pack(\"m0\") and requires no base64" do
    source = File.read(File.expand_path("../../../lib/dexpace/auth/basic_handler.rb", __dir__))

    assert_includes(source, 'pack("m0")')
    refute_match(/Base64\.|require ["']base64/, source)
  end
end
