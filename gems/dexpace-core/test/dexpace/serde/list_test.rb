# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SERDE-6, SERDE-8, SERDE-23. Parametric targets are covered by combinators that are themselves
# witnesses, each built BY VALUE from a concrete element witness -- so a parametric target is stated
# once, as data, with no reflective reconstruction anywhere.
class DexpaceSerdeListTest < DexpaceTestCase
  S = Dexpace::Serde

  # A model class that is a witness: the smallest DTO with one typed field.
  class Pet
    attr_reader :name

    def self.dexpace_load(parsed, ctx)
      h = ctx.object!(parsed)
      new(ctx.string!(h["name"], key: "name"))
    end

    def initialize(name) = @name = name
  end

  def ctx = S::DecodeContext.root

  # SERDE-5's own conformance clause: "decode a JSON object into a concrete DTO via the type-witness
  # path; assert the result is the real DTO type and field access returns typed values".
  test "SERDE-6: a list of a DTO decodes to real DTOs with typed field access" do
    pets = S::List.of(Pet).dexpace_load([{ "name" => "Ré" }, { "name" => "b" }], ctx)

    assert_equal([Pet, Pet], pets.map(&:class))
    assert_equal("Ré", pets.first.name)
  end

  test "the ergonomic scalar spellings design §7.3 uses work verbatim" do
    assert_equal(%w[a b], S::List.of(String).dexpace_load(%w[a b], ctx))
    assert_equal([1, 2], S::List.of(Integer).dexpace_load([1, 2], ctx))
    assert_equal([1.0], S::List.of(Float).dexpace_load([1], ctx)) # SERDE-22 widening
    assert_equal([true], S::List.of(S::BOOLEAN).dexpace_load([true], ctx))
  end

  # SERDE-8: reject construction with no type argument or an unresolved one, failing FAST -- at
  # witness construction, not deep inside a parse. The "unresolved type variable" state is
  # unreachable by construction (serde/ffc92673) and is stated in the YARD, not emulated.
  test "SERDE-8: a list cannot be built from a non-witness" do
    assert_raises(Dexpace::InvalidArgumentError) { S::List.of(nil) }
    assert_raises(Dexpace::InvalidArgumentError) { S::List.of(Object.new) }
    assert_raises(Dexpace::InvalidArgumentError) { S::List.of(::Symbol) }
  end

  test "a combinator is itself a witness, so combinators nest" do
    nested = S::List.of(S::List.of(String))

    assert(S.witness?(nested))
    assert_equal([%w[a]], nested.dexpace_load([%w[a]], ctx))
  end

  test "a combinator is a frozen value with structural equality, built through .build" do
    assert_equal(S::List.of(Pet), S::List.of(Pet))
    assert_equal(S::List.of(String), S::List.build(element: String))
    assert_predicate(S::List.of(Pet), :frozen?)
    refute_respond_to(S::List, :new)
    refute_respond_to(S::List, :[])
    assert_equal(S::List.of(Integer), S::List.of(String).with(element: Integer))
  end

  test "the element error names the element's own path, not the container's" do
    error = assert_raises(Dexpace::Serde::DeserializationError) do
      S::List.of(Pet).dexpace_load([{ "name" => 1 }], ctx)
    end

    assert_equal("expected String at /0/name, got Integer", error.message)
  end

  test "a non-array names Array at the list's own path" do
    error = assert_raises(Dexpace::Serde::DeserializationError) do
      S::List.of(String).dexpace_load({ "a" => 1 }, ctx.at("tags"))
    end

    assert_equal("expected Array at /tags, got Hash", error.message)
  end

  test "the decoded list is a fresh Array and never the parsed one" do
    parsed = %w[a b]

    refute_same(parsed, S::List.of(String).dexpace_load(parsed, ctx))
  end

  test "the root context names the combinator's class when it is the decode's target" do
    assert_equal("Dexpace::Serde::List", S::DecodeContext.root(target: S::List.of(Pet)).target)
  end
end
