# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/serde/json"

# SERDE-1's round trip, SERDE-19's default wiring, SERDE-24's encoder default. Design §3.4 fixes the
# last two "here rather than left to the JSON gem's own", so they are the adapter's and are tested
# through the real codec end to end. An extra suite beside codec_test.rb.
class DexpaceSerdeJSONDefaultsTest < DexpaceTestCase
  C = Dexpace::Serde::JSON::Codec
  T = Dexpace::Serde::Tristate

  # A PATCH model: one plain field and one tri-state field, both ways.
  class Patch
    def self.dexpace_load(parsed, ctx)
      h = ctx.object!(parsed)
      new(name: ctx.string!(h["name"], key: "name"),
          nick: T.of(String).dexpace_load_field(h, "nick", ctx),)
    end

    attr_reader :name, :nick

    def initialize(name:, nick:)
      @name = name
      @nick = nick
    end

    def ==(other) = other.is_a?(Patch) && name == other.name && nick == other.nick

    def dexpace_dump = { "name" => @name, "nick" => @nick }
  end

  def source(text) = Dexpace::IO::BufferedSource.of_bytes(text.b)

  # SERDE-1's conformance clause: "assert the serializer and deserializer round-trip a value with
  # each other" -- one bundle, one reference.
  test "SERDE-1: the encoder and decoder round-trip through one bundle" do
    codec = C.default
    original = Patch.new(name: "Ré", nick: T.present("n"))
    back = codec.load(source(codec.dump_string(original)), Patch)

    assert_equal("Ré", back.name)
    assert_equal("n", back.nick.value)
    assert_equal(original, back)
  end

  # SERDE-19's conformance clause, quoted: "build from a bare codec with default settings; assert
  # Absent omits the key and Null emits null." P7-9 is what makes this structural rather than a
  # convention every model must remember.
  test "SERDE-19: the DEFAULT configuration wires tri-state, with nothing registered" do
    codec = C.default

    assert_equal("{\"name\":\"x\"}", codec.dump_string(Patch.new(name: "x", nick: T::ABSENT)))
    assert_equal("{\"name\":\"x\",\"nick\":null}", codec.dump_string(Patch.new(name: "x", nick: T::NULL)))
    assert_equal("{\"name\":\"x\",\"nick\":\"n\"}",
                 codec.dump_string(Patch.new(name: "x", nick: T.present("n"))),)
  end

  test "SERDE-16/SERDE-17: the same three shapes decode back to the three states" do
    codec = C.default

    assert_predicate(codec.load(source("{\"name\":\"x\"}"), Patch).nick, :absent?)
    assert_predicate(codec.load(source("{\"name\":\"x\",\"nick\":null}"), Patch).nick, :null?)
    assert_equal("n", codec.load(source("{\"name\":\"x\",\"nick\":\"n\"}"), Patch).nick.value)
  end

  # The property test testing/f36a19cd makes mandatory for a value object with parse-constructor
  # invariants: over a seeded generator of Absent/Null/Present values embedded in a model,
  # load(dump(v)) == v for every case, the seed pinned and printed on failure.
  test "SERDE-15/SERDE-16: a seeded sample of tri-state models round-trips exactly" do
    codec = C.default
    states = [T::ABSENT, T::NULL]

    sample(count: 64) do |rng|
      nick = rng.rand(3).zero? ? T.present("n#{rng.rand(1000)}é") : states[rng.rand(2)]
      original = Patch.new(name: "name#{rng.rand(1000)}", nick: nick)

      assert_equal(original, codec.load(source(codec.dump_string(original)), Patch))
    end
  end

  test "SERDE-20: a top-level tri-state and an array element degrade to null through the codec" do
    codec = C.default

    assert_equal("null", codec.dump_string(T::ABSENT))
    assert_equal("null", codec.dump_string(T::NULL))
    assert_equal("[null,null,\"v\"]", codec.dump_string([T::ABSENT, T::NULL, T.present("v")]))
  end

  # SERDE-24's conformance clause through the real codec: "serialize an instant -> ISO-8601 string,
  # deserialize -> equality with the original." Design §3.4: "never epoch numbers".
  test "SERDE-24: the default encoder renders a Time as an ISO-8601 string, not an epoch number" do
    encoded = C.default.dump_string({ "at" => ::Time.utc(2026, 9, 10, 12) })

    assert_equal("{\"at\":\"2026-09-10T12:00:00.000000Z\"}", encoded)
    refute_match(/\d{10}/, encoded.sub("2026", ""))
  end

  test "SERDE-24: the round trip holds within the stated precision domain" do
    codec = C.default
    t = ::Time.at(1_757_505_600, 123_456, :usec).utc

    assert_equal(t, codec.load(source(codec.dump_string(t)), Dexpace::Serde::Instant))
  end

  test "SERDE-24: a seeded sample of integer-microsecond Times round-trips through the codec" do
    codec = C.default

    sample(count: 32) do |rng|
      t = ::Time.at(rng.rand(0..4_102_444_800), rng.rand(0..999_999), :usec).utc

      assert_equal(t, codec.load(source(codec.dump_string(t)), Dexpace::Serde::Instant))
    end
  end

  # P7-8, executable. Outside the domain the encoding truncates, and the YARD says so.
  test "P7-8: a Float-second Time truncates through the real codec too" do
    codec = C.default
    t = ::Time.new(2026, 9, 10, 12, 0, 0.123456, "+02:00")

    assert_equal("\"2026-09-10T12:00:00.123455+02:00\"", codec.dump_string(t))
    refute_equal(t, codec.load(source(codec.dump_string(t)), Dexpace::Serde::Instant))
  end

  test "a Date and a DateTime take the same default" do
    assert_equal("\"2026-09-10\"", C.default.dump_string(::Date.new(2026, 9, 10)))
    assert_equal("\"2026-09-10T12:00:00.000000+00:00\"",
                 C.default.dump_string(::DateTime.new(2026, 9, 10, 12, 0, 0)),)
  end

  test "the default table is the adapter's: core's Native walk alone refuses a Time" do
    assert_raises(Dexpace::Serde::SerializationError) { Dexpace::Serde::Native.of(::Time.at(0)) }
    assert_equal("\"1970-01-01T00:00:00.000000Z\"", C.default.dump_string(::Time.at(0).utc))
  end
end
