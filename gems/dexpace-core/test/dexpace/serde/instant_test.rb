# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SERDE-24. "Whichever form is chosen, the encoding MUST round-trip to the same instant" -- and
# Time#iso8601(n) TRUNCATES rather than rounding, verified, so the guarantee holds over a stated
# precision domain and the port says which. P7-8.
#
# Dexpace/NoTimeParse bans Time.parse, Date.parse and DateTime.parse. Time.iso8601 and Time#iso8601
# are `time`'s and are not what the cop bans (verified).
class DexpaceSerdeInstantTest < DexpaceTestCase
  S = Dexpace::Serde

  def ctx = S::DecodeContext.root

  test "SERDE-24: an ISO-8601 string with microseconds, not an epoch number" do
    assert_equal("2026-09-10T12:00:00.000000Z",
                 S::Instant.dexpace_dump(::Time.utc(2026, 9, 10, 12)),)
  end

  # SERDE-24's own conformance clause: serialize an instant -> ISO-8601 string, deserialize ->
  # equality with the original.
  test "SERDE-24: whole seconds round-trip exactly" do
    t = ::Time.utc(2026, 9, 10, 12, 0, 0)

    assert_equal(t, S::Instant.dexpace_load(S::Instant.dexpace_dump(t), ctx))
  end

  test "SERDE-24: exact microseconds round-trip exactly -- the stated domain" do
    t = ::Time.at(1_757_505_600, 123_456, :usec).utc

    assert_equal(t, S::Instant.dexpace_load(S::Instant.dexpace_dump(t), ctx))
  end

  # A seeded property test over the domain (styleguide 11.7): integer-microsecond Times round-trip.
  test "SERDE-24: every integer-microsecond Time in a seeded sample round-trips" do
    sample(count: 64) do |rng|
      t = ::Time.at(rng.rand(0..4_102_444_800), rng.rand(0..999_999), :usec).utc

      assert_equal(t, S::Instant.dexpace_load(S::Instant.dexpace_dump(t), ctx))
    end
  end

  test "SERDE-24: a UTC offset survives the round trip" do
    t = ::Time.new(2026, 9, 10, 12, 0, 0, "+02:00")
    back = S::Instant.dexpace_load(S::Instant.dexpace_dump(t), ctx)

    assert_equal(t, back)
    assert_equal(7200, back.utc_offset)
  end

  # P7-8, executable rather than prose: OUTSIDE the domain the encoding truncates and the round trip
  # is lossy. Asserting it is what keeps the YARD caveat honest.
  test "P7-8: a Float-second Time truncates and does NOT round-trip" do
    t = ::Time.new(2026, 9, 10, 12, 0, 0.123456, "+02:00")

    assert_equal("2026-09-10T12:00:00.123455+02:00", S::Instant.dexpace_dump(t))
    refute_equal(t, S::Instant.dexpace_load(S::Instant.dexpace_dump(t), ctx))
  end

  test "a non-string, a malformed string and a lax form each raise naming Time" do
    [5, "not a time", "", "2026-09-10", "2026-09-10 12:00:00", nil].each do |bad|
      error = assert_raises(Dexpace::Serde::DeserializationError) { S::Instant.dexpace_load(bad, ctx) }

      assert_match(/Time/, error.message)
      assert_match(%r{ at /}, error.message)
    end
  end

  test "the failure names the field's path through the context" do
    error = assert_raises(Dexpace::Serde::DeserializationError) do
      S::Instant.dexpace_load("nope", ctx.at("created_at"))
    end

    assert_equal("expected Time (ISO-8601) at /created_at, got String", error.message)
  end

  test "dexpace_dump refuses anything that is not a Time, naming the class" do
    error = assert_raises(Dexpace::Serde::SerializationError) { S::Instant.dexpace_dump("2026") }

    assert_match(/String/, error.message)
  end

  test "Instant is a witness and nests in a combinator" do
    assert(S.witness?(S::Instant))
    assert_equal([::Time.utc(2026, 9, 10)],
                 S::List.of(S::Instant).dexpace_load(["2026-09-10T00:00:00.000000Z"], ctx),)
    assert_predicate(S::Tristate.of(S::Instant).dexpace_load(nil, ctx), :null?)
  end

  test "::Time itself is not in the scalar table: the wiring is the adapter's, not core's" do
    assert_raises(Dexpace::InvalidArgumentError) { S::List.of(::Time) }
  end
end
