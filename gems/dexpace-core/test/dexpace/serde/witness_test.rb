# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SERDE-5, SERDE-7, SERDE-8. Ruby erases nothing but reifies no element types, so the requirement is
# live and its mechanism (a reflective type token) is unavailable -- design §10.14 substitutes a
# class-object-and-combinator protocol. A witness is any object responding to .dexpace_load, which
# covers a model CLASS and a combinator INSTANCE with one predicate (verified fact 15: respond_to?
# sees a class method).
class DexpaceSerdeWitnessTest < DexpaceTestCase
  # The smallest model class that is a witness.
  class Pet
    def self.dexpace_load(parsed, ctx) = new(ctx.object!(parsed))
    def initialize(hash) = @hash = hash
  end

  test "a class answering .dexpace_load is a witness" do
    assert(Dexpace::Serde.witness?(Pet))
    assert_same(Pet, Dexpace::Serde.witness!(Pet))
  end

  test "an ordinary object answering #dexpace_load is a witness too" do
    combinator = Object.new
    def combinator.dexpace_load(parsed, _ctx) = parsed

    assert(Dexpace::Serde.witness?(combinator))
    assert_same(combinator, Dexpace::Serde.witness!(combinator))
  end

  # SERDE-8: reject construction with no type argument, failing fast with an actionable message.
  test "anything else is not a witness and witness! says what is missing" do
    refute(Dexpace::Serde.witness?(Object.new))
    refute(Dexpace::Serde.witness?(nil))
    refute(Dexpace::Serde.witness?("not a witness"))
    refute(Dexpace::Serde.witness?(::String), "a class with no .dexpace_load is not one either")

    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Serde.witness!(nil) }

    assert_match(/dexpace_load/, error.message)
    assert_match(/NilClass/, error.message)
  end

  # SERDE-5's witness is EXPLICIT and SERDE-8's construction fails FAST: a bare lambda answers #call
  # and is not a witness, and widening the predicate to accept #call would make every lambda one
  # and both MUSTs unenforceable. Phase 2's FakeCodec drives its witness through #call because it
  # predates the protocol; a handler test therefore uses a named class answering both.
  test "a #call-shaped object is NOT a witness: the protocol method is the one name" do
    refute(Dexpace::Serde.witness?(->(parsed, _ctx) { parsed }))
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Serde.witness!(->(text) { text }) }
  end

  # SERDE-7: the ergonomic route IS the generic carrier. There is no raw-class path beside it to
  # forget to route through, because the class object is itself the witness.
  test "the ergonomic spelling and the carrier spelling are the same object" do
    assert_same(Pet, Dexpace::Serde.witness!(Pet))
  end

  test "the two protocol method names are public frozen symbols, and the predicate reads them" do
    assert_equal(:dexpace_load, Dexpace::Serde::WITNESS_METHOD)
    assert_equal(:dexpace_dump, Dexpace::Serde::DUMP_METHOD)
    assert_predicate(Dexpace::Serde::WITNESS_METHOD, :frozen?)
    assert_predicate(Dexpace::Serde::DUMP_METHOD, :frozen?)
  end

  test "the seam module still has no instance side: the predicates are singleton methods" do
    assert_empty(Dexpace::Serde.instance_methods(false))
    assert_respond_to(Dexpace::Serde, :witness?)
    assert_respond_to(Dexpace::Serde, :witness!)
  end
end
