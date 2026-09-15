# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-21, HTTP-13. HTTP-22's interning is a MAY and is not built (docs/first-release.md).
class DexpaceHeaderNameTest < DexpaceTestCase
  test "compares by the folded form while keeping the original casing for the wire" do
    name = Dexpace::HeaderName.of("Content-Type")

    assert_equal(Dexpace::HeaderName.of("CONTENT-TYPE"), name)
    assert_equal("Content-Type", name.to_s)
    assert_equal("Content-Type", name.original)
  end

  test "hashes by the folded form, so two casings share a Hash slot" do
    table = { Dexpace::HeaderName.of("Content-Type") => 1 }

    assert_equal(1, table[Dexpace::HeaderName.of("content-type")])
    assert(Dexpace::HeaderName.of("Accept").eql?(Dexpace::HeaderName.of("ACCEPT")))
  end

  test "is not equal to a plain string of the same folded form" do
    refute_equal(Dexpace::HeaderName.of("Accept"), "accept")
  end

  test "folds with no locale argument, so a dotted I never becomes a dotless one" do
    assert_equal("if-none-match", Dexpace::HeaderName.of("If-None-Match").folded)
  end

  test "enforces HTTP-17's name validation" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HeaderName.of("a\r\nb") }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HeaderName.of("") }
  end

  test "requires a name, naming the field" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HeaderName.of(nil) }

    assert_equal("header name is required", error.message)
  end

  test "accepts a HeaderName, so the string-keyed API interoperates" do
    name = Dexpace::HeaderName.of("Accept")

    assert_same(name, Dexpace::HeaderName.of(name))
  end

  test "trims before folding" do
    assert_equal("accept", Dexpace::HeaderName.of("  Accept  ").folded)
    assert_equal("Accept", Dexpace::HeaderName.of("  Accept  ").original)
  end

  # The bytes are ASCII and every byte check passes; only the tag is one Ruby refuses to fold.
  # Without the retag the fold raises Encoding::CompatibilityError from inside Ruby, which
  # escapes `rescue Dexpace::Error` -- a validator that crashes has not accepted its input either.
  test "folds a name whose tag is a stateful encoding rather than crashing on it" do
    name = Dexpace::HeaderName.of("Accept".encode("ISO-2022-JP"))

    assert_equal("accept", name.folded)
    assert_equal(Dexpace::HeaderName.of("Accept"), name)
    assert_equal("Accept", name.to_s)
    assert_equal(Encoding::US_ASCII, name.original.encoding)
  end

  test "is frozen and does not alias the caller's mutable string" do
    source = +"Accept"
    name = Dexpace::HeaderName.of(source)
    source << "-Language"

    assert_predicate(name, :frozen?)
    assert_predicate(name.original, :frozen?)
    assert_equal("Accept", name.original)
  end

  # .build validates; it is not a wrapper around `new`. Without an initialize override, `#with`
  # reaches the generated constructor, `HeaderName.of("Accept").with(original: "a\r\nb")`
  # succeeds, and the CRLF reaches the wire through a name that never met a validator.
  test "with re-validates and re-folds, so a derived name cannot carry CRLF" do
    name = Dexpace::HeaderName.of("Accept")

    assert_raises(Dexpace::InvalidArgumentError) { name.with(original: "a\r\nb") }
    assert_equal("content-type", name.with(original: "Content-Type").folded)
  end

  test "the fold is stable under re-folding" do
    sample(count: 64) do |rng|
      original = Array.new(rng.rand(1..12)) { rng.rand(0x21..0x7E).chr }.join
      folded = Dexpace::HeaderName.of(original).folded

      assert_equal(folded, Dexpace::HeaderName.of(folded).folded)
      assert_equal(Dexpace::HeaderName.of(original), Dexpace::HeaderName.of(folded))
    end
  end
end
