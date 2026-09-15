# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-46, HTTP-47, design §3.5: every parse is pinned to URI::RFC3986_PARSER.
class DexpaceUrlTest < DexpaceTestCase
  test "parses with the RFC 3986 parser, which is pinned on every supported Ruby" do
    url = Dexpace::URL.parse!("https://example.test/a%2Fb?x=%26")

    assert_kind_of(::URI::Generic, url)
    assert_equal("https://example.test/a%2Fb?x=%26", Dexpace::URL.external_form(url))
  end

  test "preserves already-encoded octets rather than normalising them away" do
    url = Dexpace::URL.parse!("https://example.test/a%2Fb")

    assert_includes(Dexpace::URL.external_form(url), "%2F")
  end

  test "rejects a malformed URL with an argument error carrying the offending input" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.parse!("::bad") }

    assert_includes(error.message, "::bad")
    assert_kind_of(::URI::InvalidURIError, error.cause)
  end

  test "rejects a relative URI, naming it" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.parse!("/relative") }

    assert_includes(error.message, "/relative")
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.parse!("example.test/a") }
  end

  test "rejects a nil URL through the shared required-field helper" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.parse!(nil) }

    assert_equal("url is required", error.message)
  end

  test "rejects a URL that is neither a String nor a URI" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.parse!(42) }
  end

  test "returns a frozen URI" do
    assert_predicate(Dexpace::URL.parse!("https://example.test/"), :frozen?)
  end

  test "accepts a URI object, returns it frozen, and does not freeze the caller's" do
    caller_uri = ::URI::RFC3986_PARSER.parse("https://example.test/")
    parsed = Dexpace::URL.parse!(caller_uri)

    assert_predicate(parsed, :frozen?)
    refute_predicate(caller_uri, :frozen?)
    refute_same(caller_uri, parsed)
    assert_equal("https://example.test/", Dexpace::URL.external_form(parsed))
  end

  test "rejects a relative URI object, and a URI object is still checked" do
    relative = ::URI::RFC3986_PARSER.parse("/only-a-path")

    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.parse!(relative) }
  end

  # URI::Generic#freeze is shallow: a frozen URI's host is still a mutable String, and `dup`
  # shares it with the source. The components are frozen too, so neither the caller's URI nor
  # the model's can be changed through a reader.
  test "freezes the URI's components, so a reader cannot mutate the URL in place" do
    caller_uri = ::URI::RFC3986_PARSER.parse("https://example.test/a?x=1")
    parsed = Dexpace::URL.parse!(caller_uri)

    assert_predicate(parsed.host, :frozen?)
    assert_predicate(parsed.path, :frozen?)
    assert_raises(FrozenError) { parsed.host << "x" }
    caller_uri.host << "x"

    assert_equal("https://example.test/a?x=1", Dexpace::URL.external_form(parsed))
  end

  # HTTP-46: the external form is the comparison key, and it is textual.
  test "the external form is the URI's own string form" do
    url = Dexpace::URL.parse!("HTTPS://Example.test:443/A?b=c#frag")

    assert_equal(url.to_s, Dexpace::URL.external_form(url))
  end
end
