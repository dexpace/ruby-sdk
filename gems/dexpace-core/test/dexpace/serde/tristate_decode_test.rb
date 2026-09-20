# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SERDE-16 and SERDE-17. The asymmetry SERDE-17 documents does not bite in Ruby: JSON.parse yields
# an ordinary Hash and hash.key?("x") distinguishes an absent key from a present null directly
# (serde/5fe8e3ed, verified), so the witness decides per key with full knowledge of the enclosing
# model's shape. There is no field-default machinery and none is emulated.
#
# TWO entry points, and the reason is measurable: #dexpace_load_field needs the ENCLOSING Hash to
# ask key?, while the protocol's #dexpace_load sees only the value and cannot. The second is
# SERDE-20's top-level case. An extra suite beside tristate_test.rb, the file's mirror, because
# the decode half is a different concern from the value type.
class DexpaceSerdeTristateDecodeTest < DexpaceTestCase
  S = Dexpace::Serde
  T = S::Tristate

  def ctx = S::DecodeContext.root

  # SERDE-16's own conformance clause: decode {}, {"x":null}, {"x":value}.
  test "SERDE-16/SERDE-17: a missing key is Absent, an explicit null is Null, a value is Present" do
    w = T.of(String)

    assert_same(T::ABSENT, w.dexpace_load_field({}, "x", ctx))
    assert_same(T::NULL, w.dexpace_load_field({ "x" => nil }, "x", ctx))
    assert_equal("v", w.dexpace_load_field({ "x" => "v" }, "x", ctx).value)
  end

  # SERDE-17's conformance clause names the trap by name: "assert Absent, NOT Null".
  test "SERDE-17: an omitted field is Absent and never Null" do
    result = T.of(String).dexpace_load_field({}, "x", ctx)

    assert_predicate(result, :absent?)
    refute_predicate(result, :null?)
  end

  test "SERDE-16: the inner value's declared element type is preserved" do
    assert_instance_of(::Float, T.of(Float).dexpace_load_field({ "x" => 1 }, "x", ctx).value)
    assert_raises(Dexpace::Serde::DeserializationError) do
      T.of(Integer).dexpace_load_field({ "x" => "5" }, "x", ctx)
    end
  end

  test "the field's shape failure names the field's own path" do
    error = assert_raises(Dexpace::Serde::DeserializationError) do
      T.of(Integer).dexpace_load_field({ "x" => "5" }, "x", ctx.at("pet"))
    end

    assert_equal("expected Integer at /pet/x, got String", error.message)
  end

  test "#dexpace_load_field refuses a non-Hash enclosing value through the context" do
    assert_raises(Dexpace::Serde::DeserializationError) do
      T.of(String).dexpace_load_field([], "x", ctx)
    end
  end

  # SERDE-20's decode half: "deserialize a top-level null -> Null".
  test "SERDE-20: a top-level null decodes to Null through the protocol entry point" do
    assert_same(T::NULL, T.of(String).dexpace_load(nil, ctx))
    assert_equal("v", T.of(String).dexpace_load("v", ctx).value)
  end

  test "SERDE-8: Tristate.of rejects a non-witness like every other combinator" do
    assert_raises(Dexpace::InvalidArgumentError) { T.of(Object.new) }
    assert_raises(Dexpace::InvalidArgumentError) { T.of(nil) }
  end

  test "Tristate.of and Tristate.from_nullable are different things with different names" do
    assert(S.witness?(T.of(String)))
    refute(S.witness?(T.from_nullable("v")))
  end

  test "the combinator is a frozen value with structural equality and nests" do
    assert_equal(T.of(String), T.of(String))
    assert_predicate(T.of(String), :frozen?)
    assert_predicate(T.of(S::List.of(String)).dexpace_load(%w[a], ctx), :present?)
  end

  test "the combinator's class is not public API: it is reached through .of alone" do
    refute_includes(T.constants(false), :Combinator)
  end
end
