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

  # PAGE-19 (phase 7c, P7-3): RFC 3986 reference resolution against the originating page's
  # response URL, added beside .parse! so the parser pin lives in one file. The RFC 2396
  # behaviour -- dropping the last path segment for a query-only reference -- is the one the
  # requirement forbids in as many words, so it gets its own assertion. A nested class rather than
  # a second top-level one: Style/OneClassPerFile is live under NewCops.
  class ResolveTest < DexpaceTestCase
    BASE = Dexpace::URL.parse!("https://api.example.com/repo/issues?page=1")

    test "PAGE-19: a query-only reference preserves the base's full path" do
      assert_equal("https://api.example.com/repo/issues?page=2",
                   Dexpace::URL.external_form(Dexpace::URL.resolve(BASE, "?page=2")),)
    end

    test "PAGE-19: an absolute target is used as-is and a relative one resolves" do
      assert_equal("https://other.example/x",
                   Dexpace::URL.external_form(Dexpace::URL.resolve(BASE, "https://other.example/x")),)
      assert_equal("https://api.example.com/users?page=2",
                   Dexpace::URL.external_form(Dexpace::URL.resolve(BASE, "../users?page=2")),)
      assert_equal("https://other.example/p",
                   Dexpace::URL.external_form(Dexpace::URL.resolve(BASE, "//other.example/p")),)
    end

    test "PAGE-19: a target that cannot resolve returns nil rather than raising" do
      assert_nil(Dexpace::URL.resolve(BASE, "not a url"))
      assert_nil(Dexpace::URL.resolve(BASE, "http://[bad"))
      assert_nil(Dexpace::URL.resolve(BASE, "   "))
    end

    test "the base may be a String or a URI, the result is frozen, and the base is untouched" do
      from_string = Dexpace::URL.resolve("https://h/v1/x", "y")
      from_uri = Dexpace::URL.resolve(BASE, "y")

      assert_equal("https://h/v1/y", Dexpace::URL.external_form(from_string))
      assert_equal("https://api.example.com/repo/y", Dexpace::URL.external_form(from_uri))
      assert_predicate(from_uri, :frozen?)
      assert_equal("https://api.example.com/repo/issues?page=1", Dexpace::URL.external_form(BASE))
    end

    test "a nil or non-String reference is the caller's mistake, named, not an end-of-stream" do
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.resolve(BASE, nil) }
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.resolve(BASE, :next) }
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.resolve(nil, "y") }
    end

    test "a base that is neither a String nor a URI is refused by class, naming what arrived" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.resolve(:base, "y") }

      assert_match(/base must be a String or a URI, got Symbol/, error.message)
    end

    test "resolution is a successful join even when the result is not dispatchable" do
      # join hands back a mailto:, a host-less http:foo and an empty-host http:///p as SUCCESSFUL
      # resolutions (6b's REDIR-18 finding, P6-95); the dispatchability screen is the caller's --
      # Dexpace::Page.next_request_from's -- and never this function's.
      refute_nil(Dexpace::URL.resolve(BASE, "mailto:a@b"))
      refute_nil(Dexpace::URL.resolve(BASE, "http:foo"))
      assert_nil(Dexpace::URL.resolve(BASE, "http:foo").host)
    end
  end
end
