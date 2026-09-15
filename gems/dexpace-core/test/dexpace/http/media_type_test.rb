# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-23, HTTP-24, HTTP-25, HTTP-26, HTTP-27, HTTP-53.
class DexpaceMediaTypeTest < DexpaceTestCase
  test "lower-cases type, subtype and parameter keys while preserving a value's case" do
    media = Dexpace::MediaType.parse("Application/JSON;Charset=UTF-8")

    assert_equal("application", media.type)
    assert_equal("json", media.subtype)
    assert_equal({ "charset" => "UTF-8" }, media.parameters)
  end

  test "equality is case-insensitive on type, subtype and keys and case-sensitive on values" do
    folded = Dexpace::MediaType.parse("text/plain; q=1")
    upper = Dexpace::MediaType.parse("text/plain; q=A")

    assert_equal(folded, Dexpace::MediaType.parse("Text/Plain; Q=1"))
    refute_equal(upper, folded.with(parameters: { "q" => "a" }))
    assert_equal(upper, folded.with(parameters: { "q" => "A" }))
  end

  test "splits parameters respecting quoted strings and only on the first equals" do
    media = Dexpace::MediaType.parse(%(text/plain; q="a;b=c"; x=1))

    assert_equal({ "q" => "a;b=c", "x" => "1" }, media.parameters)
    assert_equal({ "k" => "a=b" }, Dexpace::MediaType.parse("text/plain; k=a=b").parameters)
  end

  test "round-trips through render, quoting and escaping a value that is not a token" do
    original = Dexpace::MediaType.parse(%(text/plain; q="a\\"b"))

    assert_equal(original, Dexpace::MediaType.parse(original.render))
    assert_equal(%(text/plain; q="a\\"b"), original.render)
    assert_equal(
      "application/json; charset=utf-8",
      Dexpace::MediaType.parse("Application/JSON ; charset=utf-8").to_s,
    )
  end

  test "resolves charset case-insensitively and returns nil when absent or unknown" do
    assert_equal("utf-8", Dexpace::MediaType.parse("text/plain; CharSet=utf-8").charset)
    assert_equal("utf-8", Dexpace::MediaType.parse("text/plain; charset=UTF-8").charset)
    assert_nil(Dexpace::MediaType.parse("text/plain").charset)
    assert_nil(Dexpace::MediaType.parse("text/plain; charset=bogus").charset)
  end

  test "rejects the malformed forms HTTP-53 names" do
    [
      "", "   ", "bare", "/plain", "text/", "text/plain/x", "text/plain; q", "text/plain; =1",
      "text/plain; q=", %(text/plain; q="open), %(text/plain; q="a"x), "text/plain; q=1; ",
    ].each do |bad|
      assert_raises(Dexpace::InvalidArgumentError, bad) { Dexpace::MediaType.parse(bad) }
    end
  end

  test "requires the input, naming the field" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::MediaType.parse(nil) }

    assert_equal("media type is required", error.message)
  end

  test "with re-validates, so a derived media type cannot carry an unfolded type" do
    json = Dexpace::MediaType.parse("application/json")

    assert_raises(Dexpace::InvalidArgumentError) { json.with(type: "TEXT") }
    assert_raises(Dexpace::InvalidArgumentError) { json.with(parameters: { "Q" => "1" }) }
    assert_raises(Dexpace::InvalidArgumentError) { json.with(subtype: "js on") }
    assert_equal("text", json.with(type: "text").type)
  end

  test "build validates and owns its parameters, so a live hash cannot reach the model" do
    parameters = { "q" => +"1" }
    media = Dexpace::MediaType.build(type: "text", subtype: "plain", parameters: parameters)
    parameters["q"] << "0"
    parameters["x"] = "y"

    assert_equal({ "q" => "1" }, media.parameters)
    assert_predicate(media.parameters, :frozen?)
    assert(Ractor.shareable?(media))
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::MediaType.build(type: "text", subtype: "plain", parameters: { "q" => "a\rb" })
    end
    # A non-copyable object where the Hash belongs is refused before anything is copied, so
    # the stdlib's TypeError from Ractor.make_shareable never escapes `rescue Dexpace::Error`.
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::MediaType.build(type: "text", subtype: "plain", parameters: -> {})
    end
  end

  test "matches a wildcard only in the sanctioned positions, ignoring parameters" do
    json = Dexpace::MediaType.parse("application/json; charset=utf-8")

    assert(Dexpace::MediaType.parse("*/*").matches?(json))
    assert(Dexpace::MediaType.parse("application/*").matches?(json))
    assert(Dexpace::MediaType.parse("application/json").matches?(json))
    refute(Dexpace::MediaType.parse("text/*").matches?(json))
    refute(Dexpace::MediaType.parse("application/xml").matches?(json))
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::MediaType.parse("*/json") }
  end

  # A non-MediaType operand is a caller mistake, and the SDK's error is what reports it -- not a
  # NoMethodError from reading `type` off whatever was passed.
  test "matches? refuses an operand that is not a MediaType" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::MediaType.parse("*/*").matches?(nil) }
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::MediaType.parse("text/plain").matches?("text/plain")
    end
  end

  # testing/f36a19cd: a round-trip property is mandatory for a parser.
  test "parse(render(parse(text))) == parse(text) over a bounded alphabet" do
    alphabet = [*"a".."f", *"0".."3", ";", "=", '"', "\\", " ", "-", "/"]
    sample(count: 64) do |rng|
      value = Array.new(rng.rand(1..8)) { alphabet.sample(random: rng) }.join
      escaped = value.gsub(/(["\\])/) { "\\#{Regexp.last_match(1)}" }
      text = %(text/plain; key="#{escaped}")
      parsed = Dexpace::MediaType.parse(text)

      assert_equal(value, parsed.parameters.fetch("key"))
      assert_equal(parsed, Dexpace::MediaType.parse(parsed.render))
    end
  end

  # HTTP-26: what the bytes decide, and what the tag does not. Nested so the file keeps one
  # top-level suite per lib file.
  class EncodingTest < DexpaceTestCase
    test "rejects a control or non-ASCII byte anywhere, by the outbound header-value predicate" do
      ["text/pl\rain", "text/pl\xC3\xA5in", "text/plain; q=\"\x7F\"", "text/pl\xE9in"].each do |bad|
        error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::MediaType.parse(bad) }

        refute_match(/invalid byte sequence/, error.message)
      end
    end

    # HTTP-26's byte predicate passes a stateful-encoding tag over ASCII bytes, and every
    # character operation after it -- the scanner, the fold, #render's interpolation, #charset's
    # fold -- would raise Encoding::CompatibilityError. The parser and the constructor both retag.
    test "parses and builds from Strings whose tag is a stateful encoding" do
      parsed = Dexpace::MediaType.parse("Text/Plain; Charset=UTF-8".encode("ISO-2022-JP"))

      assert_equal(Dexpace::MediaType.parse("text/plain; charset=UTF-8"), parsed)
      assert_equal("utf-8", parsed.charset)
      assert_equal("text/plain; charset=UTF-8", parsed.render)
      built = Dexpace::MediaType.build(
        type: "text".encode("ISO-2022-JP"), subtype: "plain".encode("ISO-2022-JP"),
        parameters: { "q".encode("ISO-2022-JP") => "a b".encode("ISO-2022-JP") },
      )

      assert_equal(%(text/plain; q="a b"), built.render)
      assert_equal(Dexpace::MediaType.parse(%(text/plain; q="a b")), built)
    end
  end
end
