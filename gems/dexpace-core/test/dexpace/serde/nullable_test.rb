# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SERDE-6, SERDE-8, SERDE-13, SERDE-20: the combinator that accepts a wire null where its element
# witness would not. It is the witness-aware half of SERDE-13's repair -- #load screens nothing for
# nil itself, because THIS is the witness that legitimately wants one.
class DexpaceSerdeNullableTest < DexpaceTestCase
  S = Dexpace::Serde

  # A model class that is a witness, and one that refuses nil through the context.
  class Pet
    attr_reader :name

    def self.dexpace_load(parsed, ctx)
      h = ctx.object!(parsed)
      new(ctx.string!(h["name"], key: "name"))
    end

    def initialize(name) = @name = name
  end

  def ctx = S::DecodeContext.root

  test "SERDE-6: Nullable accepts nil where the element witness would not" do
    assert_nil(S::Nullable.of(Pet).dexpace_load(nil, ctx))
    assert_instance_of(Pet, S::Nullable.of(Pet).dexpace_load({ "name" => "x" }, ctx))
    assert_raises(Dexpace::Serde::DeserializationError) { Pet.dexpace_load(nil, ctx) }
  end

  test "a non-nil value still goes through the element witness's strictness" do
    assert_raises(Dexpace::Serde::DeserializationError) do
      S::Nullable.of(Integer).dexpace_load("5", ctx)
    end
    assert_in_delta(1.0, S::Nullable.of(Float).dexpace_load(1, ctx))
  end

  test "SERDE-8: Nullable cannot be built from a non-witness" do
    assert_raises(Dexpace::InvalidArgumentError) { S::Nullable.of(Object.new) }
    assert_raises(Dexpace::InvalidArgumentError) { S::Nullable.of(nil) }
  end

  test "a nullable is a frozen value with structural equality, built through .build like a model" do
    assert_equal(S::Nullable.of(Pet), S::Nullable.of(Pet))
    assert_equal(S::Nullable.of(Pet), S::Nullable.build(element: Pet))
    assert_predicate(S::Nullable.of(Pet), :frozen?)
    refute_respond_to(S::Nullable, :new)
    refute_respond_to(S::Nullable, :[])
    assert(S.witness?(S::Nullable.of(Pet)))
  end

  test "a nullable element inside a list turns a null element into nil rather than a failure" do
    assert_equal(["a", nil], S::List.of(S::Nullable.of(String)).dexpace_load(["a", nil], ctx))
    assert_raises(Dexpace::Serde::DeserializationError) do
      S::List.of(String).dexpace_load(["a", nil], ctx)
    end
  end
end
