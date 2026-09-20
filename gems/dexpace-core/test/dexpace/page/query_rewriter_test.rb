# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# Exercises: PAGE-21, PAGE-22, PAGE-23, PAGE-24, and phase 7c's P7-4.
#
# This module exists because Ruby's query helpers are the exact inverse of PAGE-22 in both
# directions (measured on every CI row: URI.decode_www_form("q=a+b") -> [["q", "a b"]] and
# URI.encode_www_form_component("a b") -> "a+b"), and because Dexpace::Query.parse(q).encode
# re-encodes every parameter, which is the canonicalisation PAGE-21 forbids in as many words. The
# codec it uses is phase 1's PercentEncoding, already shipped and tested; nothing new is encoded.
class DexpacePageQueryRewriterTest < DexpaceTestCase
  R = Dexpace::Page::QueryRewriter

  test "PAGE-21: untargeted parameters are copied byte-for-byte, order preserved" do
    result = R.set("flag&filter=a:b&page=1", "page", "2")

    assert_equal("flag&filter=a:b&page=2", result)
    # The requirement's own conformance clause asks for byte identity of the untargeted parts, not
    # for URL equality -- so assert the segments, not the whole string.
    assert_equal(%w[flag filter=a:b], result.split("&")[0, 2])
  end

  test "PAGE-21: reserved characters, empty segments and a value with an = survive untouched" do
    assert_equal("a=b=c&&x=%zz&page=2", R.set("a=b=c&&x=%zz&page=1", "page", "2"))
    assert_equal("q=a+b&page=2", R.set("q=a+b", "page", "2"))
  end

  test "PAGE-22: encoding is RFC 3986 component encoding" do
    assert_equal("q=a%20b", R.set("", "q", "a b"))
    assert_equal("token=a%2Bb%2Fc%3D", R.set("", "token", "a+b/c="))
    assert_equal("na%20me=v", R.set("", "na me", "v"))
  end

  test "PAGE-22: reading decodes with the same semantics -- a literal + reads back as +" do
    assert_equal("a+b", R.get("q=a+b", "q"))
    assert_equal("a b", R.get("q=a%20b", "q"))
    assert_equal("", R.get("flag", "flag"))          # value-less flag -> empty string
    assert_equal("", R.get("flag=", "flag"))         # an empty value reads as empty too
    assert_equal("1", R.get("p=1&p=2", "p"))          # first match wins
    assert_equal("b=c", R.get("a=b=c", "a"))          # split on the FIRST = only
    assert_nil(R.get("p=1", "absent"))
    assert_nil(R.get(nil, "p"))
    assert_nil(R.get("", "p"))
  end

  test "PAGE-22: the name is matched decoded, so pa%67e and page are one parameter" do
    assert_equal("1", R.get("pa%67e=1", "page"))
    assert_equal("page=2", R.set("pa%67e=1", "page", "2"))
  end

  test "PAGE-23: replace first in place, drop duplicates, append if absent, remove when nil" do
    assert_equal("page=2&sort=asc", R.set("page=1&sort=asc", "page", "2"))
    assert_equal("sort=asc", R.set("page=1&sort=asc", "page", nil))
    assert_equal("p=1&q=2", R.set(R.set("p=1&p=9", "p", "1"), "q", "2"))
    assert_equal("sort=asc&page=2", R.set("sort=asc", "page", "2"))
    assert_equal("a=1&p=3&b=2", R.set("a=1&p=1&b=2&p=2", "p", "3"))
    assert_equal("a=1&b=2", R.set("a=1&p=1&b=2&p=2", "p", nil))
  end

  test "P7-4: removing the only parameter yields no query at all, not a dangling ?" do
    url = Dexpace::URL.parse!("https://x/a?page=1")

    assert_nil(R.set("page=1", "page", nil))
    assert_equal("https://x/a", Dexpace::URL.external_form(R.rewrite_url(url, "page", nil)))
  end

  test "PAGE-24: every non-query component survives exactly" do
    url = Dexpace::URL.parse!("https://user:pw@api.example.com:8443/a/b?flag&page=1#frag")
    out = R.rewrite_url(url, "page", "2")

    assert_equal("https://user:pw@api.example.com:8443/a/b?flag&page=2#frag",
                 Dexpace::URL.external_form(out),)
    assert_equal("https", out.scheme)
    assert_equal("user:pw", out.userinfo)
    assert_equal(8443, out.port)
    assert_equal("/a/b", out.path)
    assert_equal("frag", out.fragment)
    assert_equal("flag&page=1", url.query) # the caller's frozen URI is untouched
  end

  test "PAGE-24: a URL with no query at all gains one, and nothing else moves" do
    url = Dexpace::URL.parse!("https://h/p#f")

    assert_equal("https://h/p?cursor=c#f",
                 Dexpace::URL.external_form(R.rewrite_url(url, "cursor", "c")),)
  end

  test "PAGE-21 (property): every other segment stays byte-identical, and get reads back set" do
    pieces = ["flag", "filter=a:b", "x=%20", "q=a+b", "p=1", "p=2", "", "k==v", "%zz=1", "r=/;,@"]
    names = %w[p page cursor]
    values = ["2", "a b", "a+b/c=", "", "%", "é"]
    sample(count: 128) do |rng|
      query = Array.new(rng.rand(0..6)) { pieces[rng.rand(pieces.size)] }.join("&")
      name = names[rng.rand(names.size)]
      value = values[rng.rand(values.size)]
      out = R.set(query, name, value)

      assert_equal(value, R.get(out, name), "get(set(#{query.inspect}, #{name}, #{value.inspect}))")
      untargeted = ->(q) { q.to_s.split("&", -1).reject { |seg| seg.split("=", 2).first == name } }

      assert_equal(untargeted.call(query), untargeted.call(out),
                   "untargeted segments of #{query.inspect}",)
    end
  end
end
