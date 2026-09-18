# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CFG-22's proxy type: a closed set of three, a frozen Data over a frozen table with .of as its
# only lookup, in phase 4c's Stage shape (P4-32, P4-56) rather than phase 1's Status shape.
class DexpaceProxyTypeTest < DexpaceTestCase
  test "CFG-22: HTTP, SOCKS4 and SOCKS5 are frozen Data constants with their names" do
    { HTTP: "HTTP", SOCKS4: "SOCKS4", SOCKS5: "SOCKS5" }.each do |constant, name|
      type = Dexpace::Proxy::Type.const_get(constant)

      assert_instance_of(Dexpace::Proxy::Type, type)
      assert_predicate(type, :frozen?)
      assert_equal(name, type.name)
      assert_predicate(type.name, :frozen?)
    end
  end

  test "CFG-22: .of resolves a token case-insensitively, trimmed, to the shared instance" do
    assert_same(Dexpace::Proxy::Type::HTTP, Dexpace::Proxy::Type.of("http"))
    assert_same(Dexpace::Proxy::Type::HTTP, Dexpace::Proxy::Type.of(" HTTP "))
    assert_same(Dexpace::Proxy::Type::SOCKS4, Dexpace::Proxy::Type.of(:socks4))
    assert_same(Dexpace::Proxy::Type::SOCKS5, Dexpace::Proxy::Type.of("SOCKS5"))
    assert_same(Dexpace::Proxy::Type::SOCKS5, Dexpace::Proxy::Type.of(Dexpace::Proxy::Type::SOCKS5))
  end

  test "CFG-22: .of refuses an unknown token, a blank one and nil, naming the closed set" do
    ["UNKNOWN", "socks", "", "  ", "http4"].each do |token|
      error = assert_raises(Dexpace::InvalidArgumentError, token.inspect) do
        Dexpace::Proxy::Type.of(token)
      end

      assert_match(/HTTP, SOCKS4, SOCKS5/, error.message)
    end
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Proxy::Type.of(nil) }
  end

  # P4-32 / P4-56: the set is closed structurally. Data#with would mint a fourth member .of
  # cannot find -- on 3.4 and 4.0 it copies without the constructor, and through Model#with it
  # would route to a .build that does not exist -- so #with refuses, and both generated
  # constructors are private.
  test "P4-56: #with refuses, .new and .[] are private, and there is no .build" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Proxy::Type::HTTP.with(name: "HTTP4")
    end

    assert_match(/closed/, error.message)
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Proxy::Type::HTTP.with(name: "HTTP") }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Proxy::Type::HTTP.with }
    refute_respond_to(Dexpace::Proxy::Type, :new)
    refute_respond_to(Dexpace::Proxy::Type, :[])
    refute_respond_to(Dexpace::Proxy::Type, :build)
    refute_includes(Dexpace::Proxy::Type.constants, :ALL)
  end

  # P8's send hole is not defended, but the constructor validates on its own: reached through
  # it, an unknown name is refused by #initialize rather than minting a fourth member.
  test "CFG-22: the constructor itself refuses an unknown name, even through send" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Proxy::Type.send(:new, name: "FTP")
    end

    assert_match(/unknown proxy type "FTP"/, error.message)
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Proxy::Type.send(:new, name: nil) }
  end

  test "CFG-22: a dup is == its constant and .of canonicalises it back to the constant" do
    copy = Dexpace::Proxy::Type::SOCKS4.dup

    assert_equal(Dexpace::Proxy::Type::SOCKS4, copy)
    refute_same(Dexpace::Proxy::Type::SOCKS4, copy)
    assert_same(Dexpace::Proxy::Type::SOCKS4, Dexpace::Proxy::Type.of(copy))
  end

  test "property: .of round-trips every member's own name, in any case" do
    sample(count: 64) do |rng|
      type = [Dexpace::Proxy::Type::HTTP, Dexpace::Proxy::Type::SOCKS4,
              Dexpace::Proxy::Type::SOCKS5,].sample(random: rng)
      token = type.name.chars.map { |c| rng.rand(2).zero? ? c.downcase : c }.join

      assert_same(type, Dexpace::Proxy::Type.of(token))
    end
  end
end
