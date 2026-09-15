# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"

# HTTP-28, HTTP-30, SEAM-29.
class DexpaceQueryBuilderTest < DexpaceTestCase
  test "add appends in insertion order and set replaces every occurrence at the first position" do
    builder = Dexpace::Query.builder.add("a", "1").add("b", "2").add("a", "3")

    assert_equal("a=1&b=2&a=3", builder.build.encode)
    assert_equal("a=9&a=8&b=2", builder.set("a", %w[9 8]).build.encode)
    assert_equal("a=9&a=8&b=2&c=4", builder.set("c", ["4"]).build.encode)
  end

  test "remove drops every occurrence of a name" do
    builder = Dexpace::Query.builder.add("a", "1").add("b", "2").add("a", "3")

    assert_equal("b=2", builder.remove("a").build.encode)
    assert_equal("b=2", builder.remove("absent").build.encode)
  end

  # Phase 2's OperationProjection passes operation inputs through unchanged, so a scalar has to
  # coerce here; a container must not, because #to_s would put Ruby's inspect form on the wire.
  test "add coerces a scalar value and refuses a container" do
    builder = Dexpace::Query.builder.add("limit", 1).add(:sort, :name).add("live", true)
    query = builder.add("ratio", 0.5).add("off", false).build

    assert_equal("limit=1&sort=name&live=true&ratio=0.5&off=false", query.encode)
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Query.builder.add("filter", { "a" => 1 })
    end

    assert_includes(error.message, "Hash")
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.builder.add("ids", [1, 2]) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.builder.add(nil, "1") }
  end

  test "set refuses a container inside the list and a non-list" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.builder.set("a", [[1]]) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.builder.set("a", "1") }
  end

  # HTTP-30: an empty list would leave include? true and encode blind to it.
  test "a name whose value list is empty is dropped at build time" do
    query = Dexpace::Query.builder.add("a", "1").set("a", []).build

    refute_includes(query, "a")
    assert_equal("", query.encode)
  end

  test "a rejected value leaves the builder usable with no partial state" do
    builder = Dexpace::Query.builder.add("a", "1")

    assert_raises(Dexpace::InvalidArgumentError) { builder.add("b", [1]) }
    assert_equal("a=1", builder.build.encode)
  end

  test "building twice yields two independent models" do
    builder = Dexpace::Query.builder.add("a", "1")
    first = builder.build
    builder.add("a", "2")

    assert_equal(["1"], first["a"])
    assert_equal(%w[1 2], builder.build["a"])
  end

  test "implements the shared builder contract" do
    assert_kind_of(Dexpace::Builder, Dexpace::Query.builder)
  end
end
