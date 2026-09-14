# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-29, HTTP-31, HTTP-32, design §3.5. None of Ruby's three built-in escapers implements RFC
# 3986 component encoding: URI.encode_www_form_component and CGI.escape emit "+" for a space and
# URI::RFC3986_PARSER.escape leaves "/", "+" and "*" bare. This is the hand-written one.
class DexpacePercentEncodingTest < DexpaceTestCase
  Codec = Dexpace::PercentEncoding

  test "encodes everything outside the unreserved set, and nothing inside it" do
    assert_equal("a%20b%2A~%2B%2F%21%28%29%27", Codec.encode_component("a b*~+/!()'"))
  end

  test "leaves the unreserved set untouched" do
    unreserved = "AZaz09-._~"

    assert_equal(unreserved, Codec.encode_component(unreserved))
  end

  test "encodes a multi-byte character as its UTF-8 bytes, uppercase" do
    assert_equal("caf%C3%A9", Codec.encode_component("café"))
  end

  test "encodes and decodes the empty string as itself" do
    assert_equal("", Codec.encode_component(""))
    assert_equal("", Codec.decode_component(""))
  end

  test "decoding leaves a plus as a plus" do
    assert_equal("a+b", Codec.decode_component("a+b"))
  end

  test "decoding accepts lower-case hex digits" do
    assert_equal("café", Codec.decode_component("caf%c3%a9"))
  end

  test "decoding a malformed escape falls back to the raw text rather than raising" do
    assert_equal("a%zzb", Codec.decode_component("a%zzb"))
    assert_equal("a%", Codec.decode_component("a%"))
    assert_equal("a%4", Codec.decode_component("a%4"))
  end

  test "round-trips bytes that are not valid UTF-8" do
    assert_equal("%FF", Codec.encode_component(Codec.decode_component("%FF")))
    assert_equal("%C3%A9", Codec.encode_component("caf\xC3\xA9".b[3..]))
  end

  test "the decoded text is tagged UTF-8, whatever the bytes say" do
    assert_equal(Encoding::UTF_8, Codec.decode_component("%FF").encoding)
    assert_equal(Encoding::UTF_8, Codec.decode_component("plain").encoding)
  end

  test "the helper that tests the unreserved set is internal, not public surface" do
    refute_respond_to(Codec, :passthrough)
  end

  # testing/f36a19cd: a round-trip property over a byte alphabet that includes "%", "+", space
  # and bytes at or above 0x80, so the invalid-UTF-8 path is exercised as well as the ASCII one.
  test "encode is stable under decode-then-encode over arbitrary bytes" do
    alphabet = [0x25, 0x2B, 0x20, 0x41, 0x7E, 0x2A, 0x80, 0xC3, 0xA9, 0xFF]
    sample(count: 128) do |rng|
      bytes = Array.new(rng.rand(0..12)) { alphabet.sample(random: rng) }.pack("C*")
      encoded = Codec.encode_component(bytes)

      assert_equal(encoded, Codec.encode_component(Codec.decode_component(encoded)))
      assert_equal(bytes, Codec.decode_component(encoded).b)
    end
  end
end
