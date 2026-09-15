# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-3, HTTP-4, HTTP-5, HTTP-13, HTTP-14, HTTP-15, HTTP-16, HTTP-17, HTTP-18, HTTP-19, HTTP-21,
# XCUT-15. Three behaviour groups, the second and third nested so the file keeps one top-level
# suite per lib file: lookup and equality here, isolation from builders and callers in
# IsolationTest, and what `.build` owes a caller who never met a Builder in BuildTest.
class DexpaceHeadersTest < DexpaceTestCase
  def build_headers
    Dexpace::Headers.builder.add("Content-Type", "application/json").add("Accept", "*/*").build
  end

  test "resolves a name added under one casing through any other" do
    assert_equal(["application/json"], build_headers["CONTENT-TYPE"])
    assert_equal(["application/json"], build_headers[Dexpace::HeaderName.of("content-type")])
    assert_includes(build_headers, "content-TYPE")
  end

  test "iterates distinct names in insertion order with their original casing" do
    assert_equal(%w[Content-Type Accept], build_headers.names)
  end

  test "entries and each_entry yield every name-value pair in insertion order" do
    headers = Dexpace::Headers.builder.add("Accept", "a").add("X-A", "1").add("Accept", "b").build

    assert_equal([%w[Accept a], %w[Accept b], %w[X-A 1]], headers.entries)
    assert_equal(headers.entries, headers.each_entry.to_a)
    yielded = []

    assert_same(headers, headers.each_entry { |pair| yielded << pair })
    assert_equal(headers.entries, yielded)
  end

  test "reports its size and emptiness by distinct name" do
    assert_equal(2, build_headers.size)
    refute_predicate(build_headers, :empty?)
    assert_predicate(Dexpace::Headers::EMPTY, :empty?)
    assert_equal(0, Dexpace::Headers::EMPTY.size)
  end

  test "equality is by folded name and value, so casing and direction take no part" do
    outbound = Dexpace::Headers.builder.add("Accept", "*/*").build
    inbound = Dexpace::Headers.inbound_builder.add("accept", "*/*").build

    assert_equal(outbound, Dexpace::Headers.builder.add("ACCEPT", "*/*").build)
    assert_equal(outbound.hash, inbound.hash)
    assert(outbound.eql?(inbound))
    refute_equal(outbound, Dexpace::Headers.builder.add("Accept", "text/plain").build)
    refute_equal(Dexpace::Headers::EMPTY, {})
  end

  test "an absent name reads as nil and is not contained" do
    headers = build_headers

    assert_nil(headers["X-Absent"])
    refute_includes(headers, "X-Absent")
  end

  test "does not expose its internal hashes" do
    refute_respond_to(build_headers, :values)
    refute_respond_to(build_headers, :casing)
  end

  test "the two canonical empties carry their direction and share nothing with a builder" do
    assert_equal(:outbound, Dexpace::Headers::EMPTY.direction)
    assert_equal(:inbound, Dexpace::Headers::EMPTY_INBOUND.direction)
    assert_equal(Dexpace::Headers::EMPTY, Dexpace::Headers::EMPTY_INBOUND)
    built = Dexpace::Headers::EMPTY.new_builder.add("Accept", "a").build

    assert_predicate(Dexpace::Headers::EMPTY, :empty?)
    assert_equal(["a"], built["Accept"])
  end

  # HTTP-3, HTTP-5, HTTP-19, XCUT-15: the model is isolated from the builder it came from, the
  # builder derived from it, and the caller's own collections.
  class IsolationTest < DexpaceTestCase
    def build_headers
      Dexpace::Headers.builder.add("Content-Type", "application/json").add("Accept", "*/*").build
    end

    # HTTP-5, in its two tiers: "name-set and entry-set accessors return a fresh per-call
    # snapshot; per-name value-list accessors return the instance's own list."
    test "the name set and the entry set are a fresh frozen snapshot on every call" do
      headers = build_headers

      assert_predicate(headers.names, :frozen?)
      refute_same(headers.names, headers.names)
      assert_predicate(headers.entries, :frozen?)
      refute_same(headers.entries, headers.entries)
      assert(headers.entries.all?(&:frozen?))
    end

    test "a per-name value list is the model's own frozen list, not a copy" do
      headers = build_headers

      assert_predicate(headers["Accept"], :frozen?)
      assert_same(headers["Accept"], headers["Accept"])
      assert_raises(FrozenError) { headers["Accept"] << "text/plain" }
    end

    test "a value list obtained before a builder mutation is unchanged after it" do
      headers = build_headers
      snapshot = headers["Accept"]
      builder = headers.new_builder
      builder.add("Accept", "text/plain")

      assert_equal(["*/*"], snapshot)
      assert_equal(["*/*"], headers["Accept"])
    end

    test "new_builder does not alias the model's value lists" do
      headers = build_headers
      derived = headers.new_builder.add("Accept", "text/plain").build

      assert_equal(["*/*"], headers["Accept"])
      assert_equal(["*/*", "text/plain"], derived["Accept"])
      assert_equal(%w[Content-Type Accept], derived.names)
    end

    test "new_builder carries the direction, so an inbound model derives an inbound builder" do
      inbound = Dexpace::Headers.inbound_builder.add("Content-Disposition", "v\xC3\xA5lue").build

      assert_equal(:inbound, inbound.direction)
      assert_equal(:inbound, inbound.new_builder.direction)
      derived = inbound.new_builder.add("X-Other", "v\xC3\xA5lue").build

      assert_equal(["v\xC3\xA5lue"], derived["X-Other"])
    end

    test "an outbound model derives an outbound builder, which still refuses obs-text" do
      derived = build_headers.new_builder

      assert_equal(:outbound, derived.direction)
      assert_raises(Dexpace::InvalidArgumentError) { derived.add("X-Other", "v\xC3\xA5lue") }
    end

    test "is Ractor-shareable, which proves the deep freeze reached every value list" do
      assert(Ractor.shareable?(build_headers))
    end

    # XCUT-15: a live Hash handed to .build is copied, so the caller's later mutation is invisible.
    test "a model built from live hashes does not change when the caller mutates them later" do
      values = { "accept" => [+"*/*"] }
      casing = { "accept" => +"Accept" }
      headers = Dexpace::Headers.build(values: values, casing: casing)
      values["accept"] << "text/plain"
      values["x-a"] = ["1"]
      casing["accept"] << "-Language"

      assert_equal(["*/*"], headers["Accept"])
      assert_equal(["Accept"], headers.names)
      refute_predicate(values, :frozen?)
      refute_predicate(values["accept"], :frozen?)
    end
  end

  # HTTP-4, HTTP-17, HTTP-18, HTTP-19: what `.build` owes a caller who never met a Builder. These
  # are not redundant with the builder's own negative tests: they are the proof that the
  # validation lives in the model, where #with and send(:new, ...) also have to meet it.
  class BuildTest < DexpaceTestCase
    # HTTP-2's gap is real, so .build validates rather than trusting its caller: it is public API
    # and a transport, a fixture or a later phase can reach it without ever meeting a Builder.
    test "build rejects a name no builder would have accepted" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(values: { "a\r\nb" => ["x"] }, casing: { "a\r\nb" => "a\r\nb" })
      end
    end

    test "build rejects a value no builder would have accepted" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(
          values: { "x-trace" => ["a\r\nb"] }, casing: { "x-trace" => "X-Trace" },
        )
      end
    end

    test "build rejects a stored name with no matching original casing" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(values: { "accept" => ["*/*"] }, casing: { "other" => "Other" })
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(values: { "accept" => ["*/*"] }, casing: { "accept" => "Other" })
      end
    end

    # The two hashes are one collection seen twice, so the check is a set equality: a casing
    # entry with no value list would make #names report a header that #size and #[] do not have.
    test "build rejects a casing entry that carries no values" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(values: {}, casing: { "x-a" => "X-A" })
      end
    end

    test "build rejects a stored name that is not folded and an unknown direction" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(values: { "Accept" => ["*/*"] }, casing: { "Accept" => "Accept" })
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(values: {}, casing: {}, direction: :sideways)
      end
    end

    test "build rejects a value list that is not a list of Strings" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(values: { "x-a" => [1] }, casing: { "x-a" => "X-A" })
      end
    end

    test "build names a missing collection through the shared required-field helper" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(values: nil, casing: {})
      end

      assert_equal("values is required", error.message)
    end

    # The container type is checked before anything reads it, so a wrong-shaped collection is a
    # Dexpace::InvalidArgumentError and never a NoMethodError escaping `rescue Dexpace::Error`
    # from inside the name validation -- through `.build` and through #with alike.
    test "build and with reject a collection that is not a Hash with the SDK's error" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(values: "x", casing: {})
      end

      assert_includes(error.message, "values")
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(values: {}, casing: [])
      end

      assert_includes(error.message, "casing")
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers::EMPTY.with(values: [], casing: {})
      end
    end

    test "build validates inbound values by the inbound grammar" do
      built = Dexpace::Headers.build(
        values: { "x-a" => ["v\xC3\xA5lue"] }, casing: { "x-a" => "X-A" }, direction: :inbound,
      )

      assert_equal(["v\xC3\xA5lue"], built["X-A"])
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Headers.build(values: { "x-a" => ["v\xC3\xA5lue"] }, casing: { "x-a" => "X-A" })
      end
    end

    test "with re-validates, so a derived collection cannot carry a CRLF value" do
      headers = Dexpace::Headers.builder.add("Accept", "*/*").build

      assert_raises(Dexpace::InvalidArgumentError) do
        headers.with(values: { "accept" => ["a\r\nb"] }, casing: { "accept" => "Accept" })
      end
    end
  end
end
