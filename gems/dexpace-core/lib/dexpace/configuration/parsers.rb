# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # The three value parsers behind Configuration#integer, #boolean and #duration (CFG-5, CFG-6,
  # CFG-7). Each is total: a missing or unparseable input yields the caller's default and never
  # raises, which is CFG-5's "MUST never throw" read across all three.
  #
  # A private_constant on Dexpace (P2-15, P4-3): reachable by bare name from any file that
  # reopens `module Dexpace` in the full nesting form, asserted at its call sites in
  # configuration_test.rb, with no sig/ mirror of its own beyond the strict Steep target's need,
  # no YARD-gate entry and no surface-manifest row.
  module ConfigParsers
    extend self

    # ISO-8601, CFG-7's first branch, hand-written because Date._iso8601 parses no duration at all
    # (verified: "PT5S", "P1D", "P1DT2H3M4S" all return {}). IGNORECASE for the same reason R2
    # folds the whole date grammar: accepting more than CFG-7 demands cannot reject a conforming
    # input, and CFG-7's own "leading 'P'/'p'" already sets the direction. A negative designator
    # never matches -- \d+ has no sign -- so "A negative duration MUST be rejected" is a property
    # of the pattern. Timeouts are per-pattern, never Regexp.timeout.
    DURATION_ISO = ::Regexp.new(
      '\A[Pp](?:(?<d>\d+)D)?(?:T(?:(?<h>\d+)H)?(?:(?<m>\d+)M)?(?:(?<s>\d+(?:\.\d+)?)S)?)?\z',
      ::Regexp::IGNORECASE,
      timeout: 1.0,
    ).freeze

    # `<number><unit>`, CFG-7's second branch: ms, s, m, h, d, folded case-insensitively, with
    # optional whitespace between number and unit.
    DURATION_UNIT = ::Regexp.new(
      '\A(?<val>\d+(?:\.\d+)?)\s*(?<unit>ms|s|m|h|d)\z',
      ::Regexp::IGNORECASE,
      timeout: 1.0,
    ).freeze

    # A bare number, CFG-7's third branch: MILLISECONDS, which is the clause a reader gets wrong.
    DURATION_BARE = ::Regexp.new('\A(?<val>\d+(?:\.\d+)?)\z', timeout: 1.0).freeze

    # Seconds per shorthand unit, CFG-7's five.
    UNIT_SECONDS = { "ms" => 0.001, "s" => 1.0, "m" => 60.0, "h" => 3600.0, "d" => 86_400.0 }.freeze
    # Seconds per ISO-8601 designator, keyed by DURATION_ISO's capture names.
    ISO_SCALES = { d: 86_400.0, h: 3600.0, m: 60.0, s: 1.0 }.freeze

    # Base 10 explicit (CFG-5): Integer("010") is 8 and Integer("010", 10) is 10, so a deployment
    # setting MAX_RETRY_ATTEMPTS=010 would otherwise silently get 8. Negative values are valid and
    # returned as-is. Ruby's two tolerances are documented rather than removed: "1_000" resolves
    # to 1000 and " 5 " to 5. `Kernel.Integer(...)` and never `::Integer(...)`, which is a
    # constant reference.
    def parse_integer(raw, default: nil)
      return default if raw.nil?

      value = ::Kernel.Integer(raw.to_s, 10, exception: false)
      value.nil? ? default : value
    end

    # Exactly "true" and "false", case-insensitively, and nothing else (CFG-6): "1", "0", "yes",
    # "no", "on", "off" all fall to the default. No trimming -- CFG-6 grants case-insensitivity
    # and nothing else. `downcase` with no argument (Dexpace/NoLocaleCaseFold).
    def parse_boolean(raw, default: nil)
      return default if raw.nil?

      case raw.to_s.downcase
      when "true" then true
      when "false" then false
      else default
      end
    end

    # The three branches in CFG-7's own order -- ISO-8601 when the string starts with P or p,
    # `<number><unit>`, then a bare number as milliseconds -- returning Float SECONDS (P5-4), the
    # unit Kernel#sleep, Thread::Queue#pop(timeout:) and phase 1's RequestOptions#timeout speak.
    # A negative value in any branch and an unknown unit both yield the default.
    def parse_duration(raw, default: nil)
      return default if raw.nil?

      text = raw.to_s.strip
      return default if text.empty?

      seconds = text.start_with?("P", "p") ? iso_seconds(text) : shorthand_seconds(text)
      seconds.nil? ? default : seconds
    end

    private

    # A bare "P" or "PT" designates nothing and is not a duration; the pattern admits it because
    # every component is optional, so the empty case is refused here.
    def iso_seconds(text)
      match = DURATION_ISO.match(text)
      return nil if match.nil? || match.captures.compact.empty?

      ISO_SCALES.sum(0.0) { |name, scale| match[name].to_f * scale }
    end

    def shorthand_seconds(text)
      if (match = DURATION_UNIT.match(text))
        match[:val].to_f * UNIT_SECONDS.fetch(match[:unit].downcase)
      elsif (match = DURATION_BARE.match(text))
        match[:val].to_f / 1000.0
      end
    end
  end

  private_constant :ConfigParsers
end
