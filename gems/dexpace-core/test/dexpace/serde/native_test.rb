# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require "time"

# SERDE-15, SERDE-19, SERDE-20 (P7-9). Design §7.3 puts the Absent-key omission in each model's own
# #dexpace_dump; the port puts it in this walk instead, because SERDE-19 is a MUST whose named
# failure -- "absent this wiring, Absent and Null become indistinguishable on the wire" -- is
# exactly what a per-model convention produces when one model forgets. In the walk it is
# structural, which is the word §7.3 itself uses for what SERDE-19 needs.
class DexpaceSerdeNativeTest < DexpaceTestCase
  S = Dexpace::Serde
  T = S::Tristate

  # A PATCH model whose fields are tri-state: the walk, not this method, drops an Absent key.
  class Patch
    def initialize(name:, nick:)
      @name = name
      @nick = nick
    end

    def dexpace_dump = { "name" => @name, "nick" => @nick }
  end

  # A model whose dump nests another model, so the re-walk is exercised two levels deep.
  class Owner
    def initialize(pet) = @pet = pet
    def dexpace_dump = { "pet" => @pet, "tags" => %w[a] }
  end

  test "native scalars pass through" do
    assert_nil(S::Native.of(nil))
    assert_equal([true, false, 1, 1.5, "é"], S::Native.of([true, false, 1, 1.5, "é"]))
    assert_equal(::Encoding::UTF_8, S::Native.of("é").encoding, "nothing is retagged")
  end

  test "anything answering #dexpace_dump is replaced and re-walked, recursively" do
    assert_equal({ "name" => "x", "nick" => nil }, S::Native.of(Patch.new(name: "x", nick: T::NULL)))
    assert_equal({ "pet" => { "name" => "x" }, "tags" => %w[a] },
                 S::Native.of(Owner.new(Patch.new(name: "x", nick: T::ABSENT))),)
  end

  # SERDE-15: Absent MUST omit the key entirely; Null MUST emit the key with a wire null; Present
  # MUST emit the key with the encoded inner value.
  test "SERDE-15: Absent omits the key, Null emits a null, Present emits the value" do
    assert_equal({ "name" => "x" }, S::Native.of(Patch.new(name: "x", nick: T::ABSENT)))
    assert_equal({ "name" => "x", "nick" => nil }, S::Native.of(Patch.new(name: "x", nick: T::NULL)))
    assert_equal({ "name" => "x", "nick" => "n" },
                 S::Native.of(Patch.new(name: "x", nick: T.present("n"))),)
  end

  test "SERDE-15: a Present holding a model is re-walked, so a nested Absent is dropped too" do
    inner = Patch.new(name: "y", nick: T::ABSENT)

    assert_equal({ "name" => "x", "nick" => { "name" => "y" } },
                 S::Native.of(Patch.new(name: "x", nick: T.present(inner))),)
  end

  # SERDE-20: degrade gracefully where no enclosing object can omit a key.
  test "SERDE-20: a top-level Absent and Null both render null rather than throwing" do
    assert_nil(S::Native.of(T::ABSENT))
    assert_nil(S::Native.of(T::NULL))
    assert_nil(S::Native.of(S::OMIT))
  end

  test "SERDE-20: an array element Absent becomes null rather than being dropped" do
    assert_equal([nil, nil, "v"], S::Native.of([T::ABSENT, T::NULL, T.present("v")]))
    assert_equal(3, S::Native.of([T::ABSENT, T::ABSENT, T::ABSENT]).length, "positions are kept")
  end

  # Verified fact 3 is why this test exists: ::JSON.generate(Object.new) returns
  # "\"#<Object:0x…>\"" rather than raising, so SERDE-9/SERDE-10's "an unserializable value throws
  # the serialization subtype" is a requirement the generator alone silently fails.
  test "an unserializable value raises SerializationError NAMING THE CLASS" do
    error = assert_raises(Dexpace::Serde::SerializationError) { S::Native.of(Object.new) }

    assert_match(/Object/, error.message)
    assert_kind_of(Dexpace::Serde::Error, error)
    assert_raises(Dexpace::Serde::SerializationError) { S::Native.of(:symbol) }
    assert_raises(Dexpace::Serde::SerializationError) { S::Native.of([1, [2, Object.new]]) }
  end

  test "Hash keys are Strings or Symbols, coerced to Strings, and anything else raises" do
    assert_equal({ "a" => 1, "b" => 2 }, S::Native.of({ "a" => 1, b: 2 }))
    error = assert_raises(Dexpace::Serde::SerializationError) { S::Native.of({ Object.new => 1 }) }

    assert_match(/key/, error.message)
    assert_raises(Dexpace::Serde::SerializationError) { S::Native.of({ 1 => 1 }) }
  end

  test "the encoders table is the ONE hook, and core ships it empty" do
    walked = S::Native.of(::Time.utc(2026, 9, 10), encoders: { ::Time => :iso8601.to_proc })

    assert_equal("2026-09-10T00:00:00Z", walked)
    assert_raises(Dexpace::Serde::SerializationError) { S::Native.of(::Time.utc(2026, 9, 10)) }
  end

  test "an encoder's result is re-walked, and a subclass finds its superclass's encoder" do
    encoders = { ::Numeric => ->(n) { { "n" => n.to_s } }, ::Time => ->(t) { [t.to_i, T::ABSENT] } }

    assert_equal({ "n" => "1/2" }, S::Native.of(Rational(1, 2), encoders: encoders))
    assert_equal([0, nil], S::Native.of(::Time.at(0), encoders: encoders))
  end

  test "a value answering #dexpace_dump wins over an encoder for its class" do
    patch = Patch.new(name: "x", nick: T::ABSENT)

    assert_equal({ "name" => "x" }, S::Native.of(patch, encoders: { Patch => ->(_) { "encoded" } }))
  end

  test "the walk returns fresh collections and never aliases the caller's" do
    source = { "a" => [1] }
    walked = S::Native.of(source)

    refute_same(source, walked)
    refute_same(source["a"], walked["a"])
    assert_equal({ "a" => [1] }, source)
  end

  test "a mutable String is copied and frozen on the way out; a frozen one passes as it is" do
    mutable = +"x"
    frozen = "y"

    refute_same(mutable, S::Native.of(mutable))
    assert_predicate(S::Native.of(mutable), :frozen?)
    assert_same(frozen, S::Native.of(frozen))
  end

  test "OMIT is a frozen sentinel with a stable textual form and a class a caller cannot name" do
    assert_predicate(S::OMIT, :frozen?)
    assert_equal("Omit", S::OMIT.to_s)
    assert_equal("Omit", S::OMIT.inspect)
    refute_includes(S.constants(false), :Omit)
  end

  test "encoders: must be a Hash of Class to callable" do
    assert_raises(Dexpace::InvalidArgumentError) { S::Native.of(1, encoders: nil) }
    assert_raises(Dexpace::InvalidArgumentError) { S::Native.of(1, encoders: { "Time" => ->(t) { t } }) }
    assert_raises(Dexpace::InvalidArgumentError) { S::Native.of(1, encoders: { ::Time => :iso8601 }) }
  end
end
