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
    # The negative half of phase 10's repair: widening the table by one form must not turn a
    # loud failure into a silent one for every other version.
    ["http/0.9", "HTTP/3", "http/1", "http/1.10"].each do |text|
      assert_raises(Dexpace::InvalidArgumentError, text) { Dexpace::Protocol.parse(text) }
    end
  end

  # HTTP-33 names http/1.1 and http/2 as EXAMPLES of the canonical form; a real HTTP/1.0 status
  # line is one any server may send, and both adapters feed their native version straight here, so
  # before phase 10 an HTTP/1.0 response made both ResponseMappers raise (8a's hand-forward).
  test "parses HTTP/1.0 to its own canonical form, and build accepts exactly that form" do
    ["HTTP/1.0", "http/1.0"].each do |text|
      assert_equal("http/1.0", Dexpace::Protocol.parse(text).wire)
    end
    assert_equal(Dexpace::Protocol::HTTP_1_0, Dexpace::Protocol.parse("HTTP/1.0"))
    assert_equal(Dexpace::Protocol::HTTP_1_0, Dexpace::Protocol.build(wire: "http/1.0"))
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

  # The byte check passes a stateful-encoding tag over ASCII bytes; the fold is what would raise.
  test "parses an identifier whose tag is a stateful encoding" do
    stateful = "HTTP/2.0".encode("ISO-2022-JP")

    assert_equal(Dexpace::Protocol::HTTP_2, Dexpace::Protocol.parse(stateful))
    assert_equal(Encoding::ISO_2022_JP, stateful.encoding)
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
