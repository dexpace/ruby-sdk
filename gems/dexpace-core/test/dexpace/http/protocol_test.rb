# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-33.
class DexpaceProtocolTest < DexpaceTestCase
  test "exposes a canonical lower-case wire form" do
    assert_equal("http/1.1", Dexpace::Protocol::HTTP_1_1.wire)
    assert_equal("http/2", Dexpace::Protocol::HTTP_2.wire)
    assert_equal("http/2", Dexpace::Protocol::HTTP_2.to_s)
  end

  test "parses the canonical forms and the two aliases, case-insensitively" do
    ["HTTP/2", "http/2", "HTTP/2.0", "http/2.0", "Http/2.0"].each do |text|
      assert_equal(Dexpace::Protocol::HTTP_2, Dexpace::Protocol.parse(text))
    end
    assert_equal(Dexpace::Protocol::HTTP_1_1, Dexpace::Protocol.parse("HTTP/1.1"))
  end

  test "raises on an unrecognised identifier, naming it" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Protocol.parse("spdy/3") }

    assert_includes(error.message, "spdy/3")
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Protocol.parse("http/1.0") }
  end

  test "requires an identifier, naming the field" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Protocol.parse(nil) }

    assert_equal("protocol is required", error.message)
  end

  # The byte check runs before `downcase`, which would otherwise raise a raw ArgumentError from
  # inside Ruby and escape `rescue Dexpace::Error`.
  test "rejects an identifier carrying invalid UTF-8 with the SDK's own error" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Protocol.parse("h\xE9") }

    refute_match(/invalid byte sequence/, error.message)
  end

  test "parse is idempotent on a Protocol" do
    assert_same(Dexpace::Protocol::HTTP_2, Dexpace::Protocol.parse(Dexpace::Protocol::HTTP_2))
  end

  test "with re-validates, so a derived protocol cannot carry an unknown wire form" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Protocol::HTTP_2.with(wire: "http/9") }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Protocol::HTTP_2.with(wire: "HTTP/2") }
    assert_equal(Dexpace::Protocol::HTTP_1_1, Dexpace::Protocol::HTTP_2.with(wire: "http/1.1"))
  end

  test "build accepts only a canonical wire form, which parse normalises to" do
    assert_equal(Dexpace::Protocol::HTTP_2, Dexpace::Protocol.build(wire: "http/2"))
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Protocol.build(wire: "http/2.0") }
  end
end
