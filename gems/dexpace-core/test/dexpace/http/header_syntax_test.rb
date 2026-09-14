# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-17, HTTP-18, HTTP-19, HTTP-20, XCUT-18. Every predicate here reads bytes, and these are the
# cases that prove why: "a\0" survives String#strip, and a character regexp raises on invalid
# UTF-8 instead of returning false.
class DexpaceHeaderSyntaxTest < DexpaceTestCase
  Syntax = Dexpace::HeaderSyntax

  test "trims surrounding SP and HTAB and stores the bare name" do
    assert_equal("X-Trace", Syntax.validate_name!("  X-Trace  "))
    assert_equal("X-Trace", Syntax.validate_name!("\tX-Trace\t"))
  end

  test "rejects a name whose only content is a NUL that String#strip would remove" do
    assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("a\0") }
  end

  test "rejects a name with a trailing CR rather than trimming it away" do
    assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("a\r") }
  end

  test "rejects a blank name" do
    assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("   ") }
    assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("") }
  end

  test "rejects a name with an interior space, DEL or a non-ASCII byte" do
    ["X Trace", "a\x7Fb", "h\xC3\xA9der"].each do |name|
      assert_raises(Dexpace::InvalidArgumentError, name.inspect) { Syntax.validate_name!(name) }
    end
  end

  test "rejects a name carrying invalid UTF-8 with the SDK's error, not the regexp engine's" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("h\xE9der") }

    refute_match(/invalid byte sequence/, error.message)
  end

  test "rejects CRLF in a name, which is the request-splitting vector" do
    assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("a\r\nb") }
  end

  test "accepts HTAB inside an outbound value" do
    assert_equal("a\tb", Syntax.validate_outbound_value!("a\tb", name: "X-Trace"))
  end

  test "rejects a non-ASCII byte in an outbound value" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Syntax.validate_outbound_value!("v\xC3\xA5lue", name: "X-Trace")
    end
  end

  test "accepts obs-text in an inbound value, which HTTP-19 relaxes" do
    value = "v\xC3\xA5lue"

    assert_equal(value, Syntax.validate_inbound_value!(value, name: "Content-Disposition"))
  end

  test "rejects CRLF in an inbound value, which HTTP-19 does not relax" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Syntax.validate_inbound_value!("a\r\nb", name: "Content-Disposition")
    end
  end

  test "rejects DEL in an inbound value" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Syntax.validate_inbound_value!("a\x7Fb", name: "Content-Disposition")
    end
  end

  test "never echoes the offending value in the message" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Syntax.validate_outbound_value!("secret\r\ntoken", name: "Authorization")
    end

    refute_includes(error.message, "secret")
    assert_includes(error.message, "Authorization")
  end

  test "escapes control bytes in an echoed name" do
    assert_equal('a\\x0D\\x0Ab', Syntax.escape("a\r\nb"))
    assert_equal('h\\xE9der', Syntax.escape("h\xE9der"))
  end

  # HTTP-20: a rejected NAME is echoed, escaped, so the message cannot inject a line into a log.
  test "a rejected name appears in the message with its control bytes escaped" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("a\r\nb") }

    assert_includes(error.message, 'a\\x0D\\x0Ab')
    refute_includes(error.message, "\r")
  end

  test "the outbound grammar is strictly narrower than the inbound one" do
    sample(count: 128) do |rng|
      value = Array.new(rng.rand(0..8)) { rng.rand(0..255).chr }.join

      assert(Syntax.valid_inbound_value?(value)) if Syntax.valid_outbound_value?(value)
    end
  end

  test "recognises an RFC 7230 token and rejects separators, blanks and invalid UTF-8" do
    %w[GET propfind text-plain.ish *].each do |text|
      assert(Syntax.token?(text), "#{text} is a token")
    end
    ["", "GE T", "a/b", "a(b)", "GE\xE9T", "a\r\n"].each do |text|
      refute(Syntax.token?(text), text.inspect)
    end
  end

  test "the trim helper is internal, not public surface" do
    refute_respond_to(Syntax, :trimmable?)
  end
end
