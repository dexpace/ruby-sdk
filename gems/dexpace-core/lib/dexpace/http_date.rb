# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "time"

require_relative "model"
require_relative "error/invalid_argument_error"

module Dexpace
  # RFC 1123 HTTP-date formatting and parsing: CFG-29, CFG-30 and CFG-31.
  #
  # The two directions deliberately do not share a mechanism (P5-12). Formatting is
  # Time#httpdate, whose body is `getutc.strftime('%a, %d %b %Y %T GMT')` and which is byte-exact
  # against the specification's own example. Parsing is an OWNED anchored grammar: Time.httpdate
  # rejects three of CFG-30's four zone tokens and accepts RFC 850, asctime and a leading space --
  # two whole date formats with no "Xxx, " prefix, which is the exact prefix CFG-31's strictness
  # clause is about -- so a normalise-then-delegate parser passes chapter 16's two conformance
  # cases and still violates the clause they are cases of (R2). Time.parse is banned repository-
  # wide (Dexpace/NoTimeParse) and would be wrong here anyway. Phase 6a's Retry-After reads through
  # this parser and no other.
  module HTTPDate
    extend self

    MONTHS = {
      "jan" => 1, "feb" => 2, "mar" => 3, "apr" => 4, "may" => 5, "jun" => 6,
      "jul" => 7, "aug" => 8, "sep" => 9, "oct" => 10, "nov" => 11, "dec" => 12,
    }.freeze

    # One pattern, anchored \A..\z, folded case-insensitively as a whole: CFG-30 makes month names
    # case-insensitive and is silent about the zone, and folding everything accepts a strict
    # superset of what the requirement demands accepted, so it cannot reject a conforming input.
    # Single literal spaces, never \s+ -- \s also matches a newline, so "Sun,\n06 Nov ..." would
    # parse under \s+ -- and \z, never \Z, which would accept a trailing newline. The "Xxx, "
    # prefix is REQUIRED: CFG-30 and CFG-31 both describe stripping a prefix that is there, and
    # Time.httpdate rejects a bare "06 Nov 1994 ..." too, so the port and the stdlib agree. No
    # normalisation runs before the match, which is how CFG-31's blank-input failure is a
    # property of the pattern rather than of whatever a normaliser did to the input. The timeout
    # is per-pattern (never Regexp.timeout), on a grammar whose one variable-width group is a
    # bounded digit run that cannot backtrack, by the same rule phase 1 applied to a
    # two-character hex pattern. The day group is (\d{1,2}), not (\d{2}): RETRY-15 requires the
    # Retry-After HTTP-date form to be parsed "tolerant of an informational weekday and
    # single-digit day", design §6.1 forbids a second parser, and phase 6a widened this group in
    # place (its R1) -- "Sun, 6 Nov 1994 08:49:37 GMT" parses as 6 November. Nothing else moved:
    # the weekday is still REQUIRED and still not validated (CFG-30's "informational only" and
    # RETRY-15's "informational weekday" are one tolerance), and RFC 850, asctime, a leading
    # space, a two-digit year and a trailing token all still fail (CFG-31).
    GRAMMAR = ::Regexp.new(
      '\A[A-Za-z]{3}, (\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) ' \
      '(GMT|UTC|\+0000|\+00:00)\z',
      ::Regexp::IGNORECASE,
      timeout: 1.0,
    ).freeze

    # Neither is public surface -- a month table and one pattern with a single reader each, and
    # P5-1 enumerates HTTPDate alone. A bare reference from inside `module Dexpace; module
    # HTTPDate` resolves whatever the visibility, which is what let phase 6a widen the day group
    # above in place at no cost to the public surface.
    private_constant :MONTHS, :GRAMMAR

    # The canonical HTTP-date form, rendered in UTC with a literal GMT and a zero-padded day
    # (CFG-29). Sub-second precision is dropped, as the format has no field for it.
    #
    # Locale-independent: CRuby's strftime carries its own English weekday and month tables and
    # never consults the C locale, verified under a user-space de_DE.UTF-8 (built with localedef
    # into LOCPATH, where `date` renders "Sonntag November") on 3.2.11 and 4.0.6.
    #
    # @param time [Time] the instant to render
    # @return [String]
    # @raise [Dexpace::InvalidArgumentError] when the argument is absent or not a Time
    def format(time)
      Model.required!("time", time)
      raise InvalidArgumentError, "time must be a Time, got #{time.class}" unless time.is_a?(::Time)

      time.getutc.httpdate
    end

    # The UTC instant an RFC 1123 date denotes, with CFG-30's four tolerances, RETRY-15's
    # single-digit day (phase 6a's widening) and CFG-31's strictness: the four zone tokens all
    # mean the zero offset, month and zone case do not matter, the weekday is stripped and never
    # compared against the date, a one-digit day is read as that day; blank input, a missing
    # comma, an absent weekday, RFC 850, asctime, a leading space and a trailing token all fail.
    # So does a syntactically well-formed but impossible date -- Time.utc silently normalises
    # 31 November, 29 February 1995, hour 24 and second 60 into the next day, month, day or
    # minute, so every component is checked against what Time.utc built rather than trusted.
    #
    # @param text [String] the header value, exactly as received
    # @return [Time] a UTC instant
    # @raise [Dexpace::InvalidArgumentError] naming the input, on any failure
    def parse(text)
      Model.required!("text", text)
      match = text.is_a?(::String) ? GRAMMAR.match(text) : nil
      raise InvalidArgumentError, "not an RFC 1123 date: #{text.inspect}" if match.nil?

      month = MONTHS[match[2].to_s.downcase]
      raise InvalidArgumentError, "unknown month in RFC 1123 date: #{text.inspect}" if month.nil?

      build_utc(fields_of(match, month), text)
    end

    private

    # year, month, day, hour, minute, second -- Time.utc's positional order.
    def fields_of(match, month)
      [match[3].to_i, month, match[1].to_i, match[4].to_i, match[5].to_i, match[6].to_i]
    end

    # Time.utc raises ArgumentError for some impossible components (day 32, minute 60) and
    # normalises others (day 31 in November, hour 24, second 60); both are one parse error here.
    # The rescue wraps ONLY Time.utc: Dexpace::InvalidArgumentError < ::ArgumentError, so a
    # method-level rescue would catch the raises above and rewrap them with a second message.
    def build_utc(fields, text)
      year, month, day, hour, min, sec = fields
      instant = begin
        ::Time.utc(year, month, day, hour, min, sec)
      rescue ::ArgumentError
        raise InvalidArgumentError, "impossible date components in RFC 1123 date: #{text.inspect}"
      end
      back = [instant.year, instant.month, instant.day, instant.hour, instant.min, instant.sec]
      return instant if back == fields

      raise InvalidArgumentError, "impossible date components in RFC 1123 date: #{text.inspect}"
    end
  end
end
