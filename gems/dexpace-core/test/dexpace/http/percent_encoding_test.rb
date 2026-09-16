# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-29, HTTP-31, HTTP-32, design §3.5; HTTP-38/BODY-35's form encoder in the nested FormTest.
# None of Ruby's three built-in escapers implements RFC 3986 component encoding:
# URI.encode_www_form_component and CGI.escape emit "+" for a space and
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

  # HTTP-38/BODY-35's form encoder, phase 3b's. `url-and-query-encoding/9ff11c34` asks for two
  # distinct functions with DISTINCT TESTS that are never interchanged; the distinctness is
  # asserted mechanically below rather than described.
  class FormTest < DexpaceTestCase
    def form(text) = Dexpace::PercentEncoding.encode_form_component(text)
    def component(text) = Dexpace::PercentEncoding.encode_component(text)

    test "encodes a space as + where the RFC 3986 encoder writes %20" do
      assert_equal("+", form(" "))
      assert_equal("%20", component(" "))
    end

    test "encodes a literal + as %2B in BOTH, so a + in form output is always a space" do
      assert_equal("%2B", form("+"))
      assert_equal("%2B", component("+"))
    end

    test "passes * through where the RFC 3986 encoder escapes it" do
      assert_equal("*", form("*"))
      assert_equal("%2A", component("*"))
    end

    test "escapes ~ where the RFC 3986 encoder passes it through" do
      assert_equal("%7E", form("~"))
      assert_equal("~", component("~"))
    end

    test "passes ASCII alphanumerics and - . _ through unchanged" do
      assert_equal("aZ0-._", form("aZ0-._"))
    end

    test "reads bytes, so invalid UTF-8 encodes byte-exactly instead of raising" do
      assert_equal("%FF", form("\xFF".b))
    end

    test "encodes multi-byte characters one byte at a time" do
      assert_equal("%C3%A9", form("é"))
    end

    test "encode_form joins pairs with & and each name to its value with =" do
      assert_equal("a=1&b=2", Dexpace::PercentEncoding.encode_form([%w[a 1], %w[b 2]]))
    end

    test "encode_form encodes both halves of every pair" do
      assert_equal("a+b=c%2Fd", Dexpace::PercentEncoding.encode_form([["a b", "c/d"]]))
    end

    test "encode_form on no pairs is the empty String" do
      assert_equal("", Dexpace::PercentEncoding.encode_form([]))
    end

    test "the form passthrough helper is internal, not public surface" do
      refute_respond_to(Dexpace::PercentEncoding, :form_passthrough)
    end

    # The mechanical version of "never interchanged": over the whole ASCII range the two functions
    # agree everywhere EXCEPT on the three characters they are defined to differ on.
    test "the two encoders differ only on space, ~ and *" do
      differing = (0..127).map(&:chr).reject { |c| form(c) == component(c) }

      assert_equal([" ", "*", "~"], differing.sort)
    end

    test "the two encoders never produce the same output for a String containing a space" do
      sample(count: 48, seed: 20_260_908) do |rng|
        text = "#{Array.new(rng.rand(1..12)) { rng.rand(0x20..0x7E).chr }.join} "

        refute_equal(form(text), component(text))
      end
    end
  end
end
