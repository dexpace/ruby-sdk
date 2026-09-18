# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/scheme"

# Exercises: AUTH-1 -- the closed five-member scheme set, closed structurally in the
# Pipeline::Stage / Proxy::Type shape: both generated constructors private, #with refusing,
# .of the one lookup, and NO_AUTH a distinct sentinel.
class DexpaceAuthSchemeTest < DexpaceTestCase
  Scheme = Dexpace::Auth::Scheme

  test "AUTH-1: the set is exactly OAUTH2, API_KEY, BASIC, DIGEST and NO_AUTH, in that order" do
    assert_equal(%w[OAUTH2 API_KEY BASIC DIGEST NO_AUTH], Scheme::ALL.map(&:name))
    assert_predicate(Scheme::ALL, :frozen?)
    Scheme::ALL.each { |scheme| assert_same(scheme, Scheme.const_get(scheme.name)) }
  end

  test "AUTH-1: NO_AUTH is a distinct sentinel and not any wire scheme" do
    (Scheme::ALL - [Scheme::NO_AUTH]).each do |scheme|
      refute_equal(Scheme::NO_AUTH, scheme)
      refute_same(Scheme::NO_AUTH, scheme)
    end
  end

  test ".of resolves a name in any case, a Symbol, or a Scheme back to the shared constant" do
    assert_same(Scheme::BASIC, Scheme.of("BASIC"))
    assert_same(Scheme::BASIC, Scheme.of("basic"))
    assert_same(Scheme::BASIC, Scheme.of(" Basic "))
    assert_same(Scheme::DIGEST, Scheme.of(:digest))
    assert_same(Scheme::API_KEY, Scheme.of(Scheme::API_KEY))
    assert_same(Scheme::NO_AUTH, Scheme.of(Scheme::NO_AUTH.dup))
  end

  test ".of refuses an unknown, blank or absent name with the SDK's error" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Scheme.of("NTLM") }

    assert_includes(error.message, "NTLM")
    assert_raises(Dexpace::InvalidArgumentError) { Scheme.of("") }
    assert_raises(Dexpace::InvalidArgumentError) { Scheme.of(nil) }
  end

  test "the constants carry their names: built through the private .new, never allocate" do
    assert_equal("NO_AUTH", Scheme::NO_AUTH.name)
    assert_equal("OAUTH2", Scheme::OAUTH2.to_s)
    assert_predicate(Scheme::OAUTH2.name, :frozen?)
  end

  test "P4-32's shape: .new and .[] are private, #with refuses, so the set cannot grow" do
    refute_respond_to(Scheme, :new)
    refute_respond_to(Scheme, :[])
    assert_raises(NoMethodError) { Scheme.new(name: "NTLM") }
    assert_raises(NoMethodError) { Scheme["NTLM"] }
    assert_raises(Dexpace::InvalidArgumentError) { Scheme::BASIC.with(name: "NTLM") }
    assert_raises(Dexpace::InvalidArgumentError) { Scheme::BASIC.with }
  end

  test "send(:new) past the private constructor still meets the validating initialize" do
    assert_raises(Dexpace::InvalidArgumentError) { Scheme.send(:new, name: "ntlm") }
    assert_raises(Dexpace::InvalidArgumentError) { Scheme.send(:new, name: nil) }
  end

  test "a copy is == its constant and .of canonicalises it back" do
    copy = Marshal.load(Marshal.dump(Scheme::DIGEST))

    assert_equal(Scheme::DIGEST, copy)
    refute_same(Scheme::DIGEST, copy)
    assert_same(Scheme::DIGEST, Scheme.of(copy))
  end
end
