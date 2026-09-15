# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-28, HTTP-29, HTTP-30, HTTP-31, HTTP-32, HTTP-3, HTTP-5, XCUT-15. The lenient parse has
# its own nested group, ParseTest, so the file keeps one top-level suite per lib file.
class DexpaceQueryTest < DexpaceTestCase
  test "names are case-sensitive, unlike header names" do
    query = Dexpace::Query.builder.add("page", "1").add("Page", "2").build

    assert_equal(["1"], query["page"])
    assert_equal(["2"], query["Page"])
    assert_equal(%w[page Page], query.names)
  end

  test "encodes with RFC 3986 rules, one occurrence per value, in insertion order" do
    query = Dexpace::Query.builder.add("q", "a b").add("plus", "c+d").add("q", "z").build

    assert_equal("q=a%20b&plus=c%2Bd&q=z", query.encode)
    assert_equal(query.encode, query.to_s)
  end

  test "models a value-less parameter as one empty-string value, distinct from an absent name" do
    query = Dexpace::Query.builder.add("flag", nil).build

    assert_equal([""], query["flag"])
    assert_includes(query, "flag")
    assert_nil(query["absent"])
    refute_includes(query, "absent")
    assert_equal("flag=", query.encode)
  end

  test "returns empty for an empty query and omits the leading question mark" do
    assert_equal("", Dexpace::Query::EMPTY.encode)
    assert_predicate(Dexpace::Query::EMPTY, :empty?)
  end

  test "equality is order-sensitive: two instances are equal iff they encode identically" do
    first = Dexpace::Query.builder.add("a", "1").add("b", "2").build
    second = Dexpace::Query.builder.add("b", "2").add("a", "1").build

    refute_equal(first, second)
    assert_equal(first, Dexpace::Query.parse(first.encode))
    assert_equal(first.hash, Dexpace::Query.parse(first.encode).hash)
  end

  test "new_builder does not alias the model's pairs" do
    query = Dexpace::Query.builder.add("a", "1").build
    derived = query.new_builder.add("a", "2").build

    assert_equal(["1"], query["a"])
    assert_equal(%w[1 2], derived["a"])
  end

  # HTTP-5: "name-set and entry-set accessors return a fresh per-call snapshot", and the per-name
  # list, which no stored list backs, is a fresh frozen list too.
  test "the name set, the entry set and each value list are fresh frozen snapshots" do
    query = Dexpace::Query.builder.add("a", "1").build

    assert_predicate(query.names, :frozen?)
    refute_same(query.names, query.names)
    assert_predicate(query.entries, :frozen?)
    refute_same(query.entries, query.entries)
    assert_predicate(query["a"], :frozen?)
    assert_equal([%w[a 1]], query.entries)
    assert(query.entries.all?(&:frozen?))
  end

  test "build rejects a pair shape no builder would have produced" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.build(pairs: [["a"]]) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.build(pairs: [%w[a b], nil]) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.build(pairs: [["a", 1]]) }
    # A non-copyable object where the list belongs is refused before anything is copied, so
    # the stdlib's TypeError from Ractor.make_shareable never escapes `rescue Dexpace::Error`.
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.build(pairs: -> {}) }
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.build(pairs: nil) }

    assert_equal("pairs is required", error.message)
  end

  test "with re-validates, so a derived query cannot carry a malformed pair" do
    query = Dexpace::Query.builder.add("a", "1").build

    assert_raises(Dexpace::InvalidArgumentError) { query.with(pairs: [["a"]]) }
    assert_equal("b=2", query.with(pairs: [%w[b 2]]).encode)
  end

  # XCUT-15: a live list handed to .build is copied, so the caller's later mutation is invisible.
  test "build owns its pairs and is Ractor-shareable" do
    pairs = [[+"a", +"1"]]
    query = Dexpace::Query.build(pairs: pairs)
    pairs << %w[b 2]
    pairs.first.first << "x"

    assert_equal("a=1", query.encode)
    assert(Ractor.shareable?(query))
  end

  test "does not expose its internal pair list" do
    refute_respond_to(Dexpace::Query::EMPTY, :pairs)
  end

  # testing/f36a19cd: a round-trip property over generated queries.
  test "parse(q.encode) == q over generated queries" do
    alphabet = ["a", "b", " ", "+", "&", "=", "%", "é", "~", "*", ""]
    sample(count: 64) do |rng|
      builder = Dexpace::Query.builder
      rng.rand(0..5).times do
        name = Array.new(rng.rand(1..3)) { alphabet.sample(random: rng) }.join
        value = Array.new(rng.rand(0..3)) { alphabet.sample(random: rng) }.join
        builder.add(name.empty? ? "n" : name, value)
      end
      query = builder.build

      assert_equal(query, Dexpace::Query.parse(query.encode))
    end
  end

  # HTTP-31, HTTP-32: the lenient, total parse. Nested so the file keeps one top-level suite per
  # lib file.
  class ParseTest < DexpaceTestCase
    test "parses leniently: a leading ?, a bare segment, a stray &, a bad escape" do
      query = Dexpace::Query.parse("?a=1&&b&c=&d=%zz")

      assert_equal(["1"], query["a"])
      assert_equal([""], query["b"])
      assert_equal([""], query["c"])
      assert_equal(["%zz"], query["d"])
      assert_equal(%w[a b c d], query.names)
    end

    test "parses percent-escapes in names and values and leaves a plus as a plus" do
      query = Dexpace::Query.parse("a%20b=c%2Bd+e")

      assert_equal(["c+d+e"], query["a b"])
    end

    test "a blank or nil query parses to empty" do
      assert_predicate(Dexpace::Query.parse(nil), :empty?)
      assert_predicate(Dexpace::Query.parse("  "), :empty?)
      assert_predicate(Dexpace::Query.parse("?"), :empty?)
      assert_same(Dexpace::Query::EMPTY, Dexpace::Query.parse(nil))
    end

    test "parse is total over a query string carrying invalid UTF-8" do
      query = Dexpace::Query.parse("a=caf\xE9")

      assert_equal(["caf\xE9".b], query["a"].map(&:b))
      assert_equal("a=caf%E9", query.encode)
    end

    # Total over nil and every String; anything else is a caller mistake reported as the SDK's
    # error, as Protocol.parse and MediaType.parse do, never as a NoMethodError from `.b`.
    test "parse refuses an input that is neither nil nor a String with the SDK's error" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.parse(5) }

      assert_includes(error.message, "String")
    end
  end
end
