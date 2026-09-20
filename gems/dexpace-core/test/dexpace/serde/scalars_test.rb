# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SERDE-6, SERDE-21, SERDE-22: the scalar witnesses behind the ergonomic spellings
# `List.of(String)`, `Map.of(String, Pet)` and `Tristate.of(Float)`, plus the one public constant --
# Dexpace::Serde::BOOLEAN, a NAMED witness rather than two class keys, because Ruby has no Boolean
# class to key on and `List.of(TrueClass)` would read as a list of `true`s (the plan's resolved
# question 1). The table is a private_constant and is asserted here through the combinators that
# consult it; the file mirrors lib/dexpace/serde/scalars.rb.
class DexpaceSerdeScalarsTest < DexpaceTestCase
  S = Dexpace::Serde

  def ctx = S::DecodeContext.root

  test "BOOLEAN is a public frozen witness with a stable textual form" do
    assert(S.witness?(S::BOOLEAN))
    assert_predicate(S::BOOLEAN, :frozen?)
    assert_equal("Boolean", S::BOOLEAN.to_s)
    assert_equal("Boolean", S::BOOLEAN.inspect)
  end

  test "BOOLEAN accepts exactly true and false and refuses the SERDE-21 coercions" do
    assert(S::BOOLEAN.dexpace_load(true, ctx))
    refute(S::BOOLEAN.dexpace_load(false, ctx))
    assert_raises(Dexpace::Serde::DeserializationError) { S::BOOLEAN.dexpace_load("true", ctx) }
    assert_raises(Dexpace::Serde::DeserializationError) { S::BOOLEAN.dexpace_load(1, ctx) }
    assert_raises(Dexpace::Serde::DeserializationError) { S::BOOLEAN.dexpace_load(nil, ctx) }
  end

  test "String, Integer and Float resolve to scalar witnesses through every combinator" do
    assert_equal(%w[a], S::List.of(::String).dexpace_load(%w[a], ctx))
    assert_equal({ "a" => 1 }, S::Map.of(::String, ::Integer).dexpace_load({ "a" => 1 }, ctx))
    assert_in_delta(2.0, S::Nullable.of(::Float).dexpace_load(2, ctx))
    assert_equal(3, S::Tristate.of(::Integer).dexpace_load(3, ctx).value)
  end

  test "the same class resolves to the SAME scalar witness, so combinators stay equal" do
    assert_equal(S::List.of(::String), S::List.of(::String))
    assert_same(S::List.of(::String).element, S::List.of(::String).element)
  end

  test "SERDE-21/SERDE-22 through the scalar witnesses: strict, with the one widening" do
    assert_raises(Dexpace::Serde::DeserializationError) { S::List.of(::Integer).dexpace_load(["5"], ctx) }
    assert_raises(Dexpace::Serde::DeserializationError) { S::List.of(::String).dexpace_load([5], ctx) }
    assert_equal([1.0], S::List.of(::Float).dexpace_load([1], ctx))
    assert_equal([""], S::List.of(::String).dexpace_load([""], ctx))
  end

  # A class the table does not know must answer .dexpace_load like anything else -- ::Time is
  # deliberately NOT mapped in core (the ISO-8601 wiring is the adapter's, design §3.4), and
  # ::Symbol, ::Hash and ::Array are not witnesses either.
  test "a class outside the table is not a witness by virtue of being a class" do
    assert_raises(Dexpace::InvalidArgumentError) { S::List.of(::Time) }
    assert_raises(Dexpace::InvalidArgumentError) { S::List.of(::Symbol) }
    assert_raises(Dexpace::InvalidArgumentError) { S::List.of(::Hash) }
    assert_raises(Dexpace::InvalidArgumentError) { S::List.of(::TrueClass) }
  end

  test "the lookup table is not public API" do
    refute_includes(S.constants(false), :Scalars)
    assert_includes(S.constants(false), :BOOLEAN)
  end
end
