# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "time"

require_relative "serialization_error"
require_relative "decode_context"

module Dexpace
  module Serde
    # The ISO-8601 instant witness (SERDE-24): `.dexpace_load` parses an ISO-8601 string into a
    # ::Time and `.dexpace_dump` renders one, so the two halves of the round trip live together and
    # a caller never matches independent conventions. Core's, not the adapter's, because a witness
    # is codec-agnostic by construction and a second codec would otherwise write a second one; the
    # DEFAULT wiring of it as the encoder for ::Time stays the adapter's (design §3.4: "the
    # adapter's default encoder configuration renders date and time values as ISO-8601 strings"),
    # which is why ::Time is deliberately absent from core's scalar table and `List.of(::Time)` is
    # refused.
    #
    # `Time.iso8601` and `Time#iso8601` are `time`'s -- a default gem across the whole supported
    # range and on the require allowlist -- and are not what Dexpace/NoTimeParse bans (verified
    # fact 10). Phase 5a's Dexpace::HTTPDate is RFC 1123, a different grammar, and is not consumed.
    #
    # THE PRECISION DOMAIN (P7-8). The encoder emits `#iso8601(6)` -- microseconds, the resolution
    # the overwhelming majority of HTTP APIs use -- and `Time#iso8601(n)` TRUNCATES rather than
    # rounds, verified on every supported Ruby. So the round trip SERDE-24 requires holds exactly
    # for any Time whose `subsec` is an exact multiple of one microsecond: every Time this SDK
    # constructs (`Time.utc(...)`, `Time.at(sec, usec, :usec)`) and every Time this witness decodes.
    # Outside that domain the encoding truncates and the round trip is lossy, including the
    # ordinary-looking `Time.new(2026, 9, 10, 12, 0, 0.123456, "+02:00")`: its Float second is
    # stored as the exact rational 8895942329546431/72057594037927936 (0.12345599999...) and
    # renders as `...00.123455+02:00`, one microsecond low. The port does not round instead --
    # `Time#iso8601` is `time`'s, and re-implementing its formatter to round would be a second date
    # formatter beside HTTPDate.
    #
    # The decoder is strict the way SERDE-13/SERDE-21 want: `Time.iso8601` rejects `"2026-09-10"`,
    # `"2026-09-10 12:00:00"`, `""` and `"not a time"`, and each becomes a DeserializationError
    # naming `Time (ISO-8601)` at the field's path.
    module Instant
      extend self

      # What the shape failure names (SERDE-13): the target, and the grammar it wanted.
      EXPECTED = "Time (ISO-8601)"
      private_constant :EXPECTED

      # The witness protocol: an ISO-8601 string to a ::Time, or a shape failure naming Time.
      #
      # @param parsed [Object] the parsed value; anything but a well-formed ISO-8601 String fails
      # @param ctx [Dexpace::Serde::DecodeContext]
      # @return [Time]
      # @raise [Dexpace::Serde::DeserializationError]
      def dexpace_load(parsed, ctx)
        ctx.error!(expected: EXPECTED, actual: parsed) unless parsed.is_a?(::String)

        ::Time.iso8601(parsed)
      rescue ::ArgumentError
        ctx.error!(expected: EXPECTED, actual: parsed)
      end

      # The encoder half, what the adapter installs for ::Time: `time.iso8601(6)`, within the
      # precision domain stated above.
      #
      # @param time [Time]
      # @return [String] ISO-8601 with microseconds and the Time's own offset (`Z` for UTC)
      # @raise [Dexpace::Serde::SerializationError] when `time` is not a ::Time
      def dexpace_dump(time)
        unless time.is_a?(::Time)
          raise SerializationError,
                "Instant encodes a Time, got #{time.class}"
        end

        time.iso8601(6)
      end
    end
  end
end
