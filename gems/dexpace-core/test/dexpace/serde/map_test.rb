# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SERDE-6, SERDE-8: the Hash-shaped combinator. The key witness is REQUIRED rather than assumed to
# be String, so a codec whose keys are not strings inherits the combinator unchanged.
class DexpaceSerdeMapTest < DexpaceTestCase
  S = Dexpace::Serde

  # A model class that is a witness.
  class Pet
    attr_reader :name

    def self.dexpace_load(parsed, ctx)
      h = ctx.object!(parsed)
      new(ctx.string!(h["name"], key: "name"))
    end

    def initialize(name) = @name = name
  end

  def ctx = S::DecodeContext.root

  test "SERDE-6: a map keyed by String and valued by a DTO" do
    map = S::Map.of(String, Pet).dexpace_load({ "a" => { "name" => "x" } }, ctx)

    assert_instance_of(Pet, map["a"])
    assert_equal("x", map["a"].name)
  end

  test "the ergonomic scalar spellings work for both positions" do
    assert_equal({ "a" => 1.0 }, S::Map.of(String, Float).dexpace_load({ "a" => 1 }, ctx))
    assert_equal({ "a" => true }, S::Map.of(String, S::BOOLEAN).dexpace_load({ "a" => true }, ctx))
  end

  test "SERDE-8: a map cannot be built from a non-witness in either position" do
    assert_raises(Dexpace::InvalidArgumentError) { S::Map.of(String, nil) }
    assert_raises(Dexpace::InvalidArgumentError) { S::Map.of(nil, String) }
    assert_raises(Dexpace::InvalidArgumentError) { S::Map.of(Object.new, Pet) }
  end

  test "keys go through the key witness, so a key of the wrong shape is a shape failure too" do
    integer_keyed = S::Map.of(Integer, String)

    assert_equal({ 1 => "a" }, integer_keyed.dexpace_load({ 1 => "a" }, ctx))
    error = assert_raises(Dexpace::Serde::DeserializationError) do
      integer_keyed.dexpace_load({ "1" => "a" }, ctx)
    end

    assert_equal("expected Integer at /1, got String", error.message)
  end

  test "a value error names the entry's own path" do
    error = assert_raises(Dexpace::Serde::DeserializationError) do
      S::Map.of(String, Pet).dexpace_load({ "a" => { "name" => 1 } }, ctx.at("pets"))
    end

    assert_equal("expected String at /pets/a/name, got Integer", error.message)
  end

  test "a non-object names Hash at the map's own path" do
    error = assert_raises(Dexpace::Serde::DeserializationError) do
      S::Map.of(String, String).dexpace_load([], ctx)
    end

    assert_equal("expected Hash at /, got Array", error.message)
  end

  test "a map is a frozen value with structural equality, built through .build like a model" do
    assert_equal(S::Map.of(String, Pet), S::Map.of(String, Pet))
    assert_equal(S::Map.of(String, Pet), S::Map.build(key: String, value: Pet))
    assert_predicate(S::Map.of(String, Pet), :frozen?)
    refute_respond_to(S::Map, :new)
    refute_respond_to(S::Map, :[])
    assert_equal(S::Map.of(String, Integer), S::Map.of(String, Pet).with(value: Integer))
  end

  test "the decoded map is a fresh Hash and never the parsed one" do
    parsed = { "a" => "b" }

    refute_same(parsed, S::Map.of(String, String).dexpace_load(parsed, ctx))
  end

  test "a map nests inside a list and a list inside a map" do
    assert_equal([{ "a" => [1] }],
                 S::List.of(S::Map.of(String, S::List.of(Integer)))
                   .dexpace_load([{ "a" => [1] }], ctx),)
  end
end
