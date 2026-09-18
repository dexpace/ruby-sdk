# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../http_date"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Resilience
    # RETRY-15, RETRY-17, RETRY-19, RECOV-24, RECOV-25: the per-form pacing-header value parsers,
    # one method per wire form, each TOTAL over a String -- nil for anything it cannot read, never
    # a raise and never a zero delay it did not earn (RETRY-16, RECOV-23). Policy.pacing_delay is
    # the public dispatch over them and nothing outside this file names a form directly, which is
    # why this is a private_constant on 5a's ConfigParsers precedent (the plan's open question 2):
    # Policy's public surface stays the methods the design names and the parsing internals carry
    # no NFR-4 lock. It has a sig/ mirror because the strict `core` Steep target types its call
    # sites, and no test/ mirror -- every branch is asserted through Policy.pacing_delay.
    #
    # Three grammars, each anchored \A..\z, each compiled once with its own timeout (never
    # Regexp.timeout), and none can backtrack: digit runs and one optional fraction. RETRY-19's
    # screen is the DECIMAL grammar, applied BEFORE String#to_f -- "30d", "0x10", "1e3", "5_0",
    # "Infinity", "NaN" and " 5" all fail it and fall through to the HTTP-date attempt, which
    # rejects them too, so the answer is nil. Nothing here calls Float() or Integer() on an
    # unscreened value: Integer("5_0", 10) is 50 on every supported Ruby (verified 3.2.11,
    # 3.4.10, 4.0.6), which is exactly the mis-parse the screen exists to prevent.
    module PacingParsers
      extend self

      DECIMAL_GRAMMAR = ::Regexp.new('\A\d+(\.\d+)?\z', timeout: 1.0).freeze
      INTEGER_GRAMMAR = ::Regexp.new('\A\d+\z', timeout: 1.0).freeze
      private_constant :DECIMAL_GRAMMAR, :INTEGER_GRAMMAR

      # The upper bound of RECOV-25's positive jitter: [100%, 120%] of the computed delta.
      RESET_JITTER_CEILING = 1.2
      private_constant :RESET_JITTER_CEILING

      # Retry-After: delta-seconds first (integer and fractional, sub-second honoured), then an
      # RFC 1123 HTTP-date through the ONE parser, whose past instants floor to zero (RETRY-17).
      # An unparseable value is nil, distinct from a past date's 0.0.
      def parse_retry_after(value, now:)
        return nil unless value.is_a?(::String)
        return value.to_f if DECIMAL_GRAMMAR.match?(value)

        instant = Dexpace::HTTPDate.parse(value)
        [(instant - now).to_f, 0.0].max
      rescue Dexpace::InvalidArgumentError
        nil
      end

      # retry-after-ms / x-ms-retry-after-ms: a non-negative integer count of milliseconds.
      def parse_millis(value)
        return nil unless value.is_a?(::String) && INTEGER_GRAMMAR.match?(value)

        value.to_i / 1000.0
      end

      # X-RateLimit-Reset: Unix epoch seconds. A reset already past floors to zero (RETRY-17); a
      # future one is jittered UPWARD to [100%, 120%] of the delta (RECOV-25), inside the parser,
      # so the caller applies no second jitter on top (RETRY-20, RECOV-22). The jitter is drawn
      # only over a finite range: a digit run long enough to convert to Infinity is out of range
      # and answers nil (RETRY-16), and a finite delta whose 120% would overflow is returned
      # unjittered for the dispatcher's 365-day clamp to bound -- Random#rand raises EDOM on an
      # infinite bound (verified on 4.0.6), and RECOV-26's "never surface an arithmetic overflow
      # mid-retry" covers a server's hint before any clamp reaches it.
      def parse_epoch_reset(value, now:, random:)
        return nil unless value.is_a?(::String) && INTEGER_GRAMMAR.match?(value)

        delta = [(value.to_i - now.to_i).to_f, 0.0].max
        return nil unless delta.finite?
        return 0.0 if delta.zero?

        ceiling = delta * RESET_JITTER_CEILING
        ceiling.finite? ? random.rand(delta..ceiling) : delta
      end
    end
    private_constant :PacingParsers
  end
end
