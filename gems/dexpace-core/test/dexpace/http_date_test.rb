# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# CFG-29 (formatting), CFG-30 (tolerant parsing) and CFG-31 (strict parsing): Time#httpdate for
# the one direction it is byte-exact in, and an owned anchored grammar for the other (R2, P5-12).
module HTTPDateTest
  EXAMPLE = Time.utc(1994, 11, 6, 8, 49, 37)

  # CFG-29.
  class FormatTest < DexpaceTestCase
    test "CFG-29: formats the specification's own example byte for byte, day zero-padded" do
      assert_equal("Sun, 06 Nov 1994 08:49:37 GMT", Dexpace::HTTPDate.format(EXAMPLE))
      assert_equal("Mon, 01 Jan 2024 00:00:00 GMT", Dexpace::HTTPDate.format(Time.utc(2024, 1, 1)))
    end

    test "CFG-29: a non-UTC instant is rendered in UTC with a literal GMT" do
      local = Time.new(1994, 11, 6, 10, 49, 37, "+02:00")

      assert_equal("Sun, 06 Nov 1994 08:49:37 GMT", Dexpace::HTTPDate.format(local))
      assert_equal("Sun, 06 Nov 1994 08:49:37 GMT", Dexpace::HTTPDate.format(EXAMPLE.getlocal))
    end

    test "CFG-29: sub-second precision is dropped, not rounded up" do
      assert_equal("Sun, 06 Nov 1994 08:49:37 GMT", Dexpace::HTTPDate.format(EXAMPLE + 0.999))
    end

    test "CFG-29 / SEAM-29: format requires its argument, with the one message form" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.format(nil) }

      assert_equal("time is required", error.message)
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.format("1994") }
    end

    # Open question 2, settled at execution: CRuby's strftime carries its own English tables,
    # verified under a user-space de_DE.UTF-8 built with localedef into LOCPATH, where `date`
    # prints "Sonntag November" and Time#httpdate still prints "Sun, 06 Nov". A locale a test
    # process cannot install is not asserted here; what is asserted is that the formatter never
    # consults the locale through the one variable that could reach it.
    test "CFG-29: the formatter is locale-independent for the locales this process can select" do
      %w[C POSIX C.UTF-8 en_US.UTF-8].each do |name|
        rendered = with_lc_all(name) { Dexpace::HTTPDate.format(EXAMPLE) }

        assert_equal("Sun, 06 Nov 1994 08:49:37 GMT", rendered, name)
      end
    end

    private

    def with_lc_all(name)
      previous = ENV.fetch("LC_ALL", nil)
      ENV["LC_ALL"] = name
      yield
    ensure
      previous.nil? ? ENV.delete("LC_ALL") : ENV["LC_ALL"] = previous
    end
  end

  # CFG-30 and CFG-31.
  class ParseTest < DexpaceTestCase
    test "CFG-30: all four zone tokens parse to the identical UTC instant" do
      [
        "Sun, 06 Nov 1994 08:49:37 GMT",
        "Sun, 06 Nov 1994 08:49:37 UTC",
        "Sun, 06 Nov 1994 08:49:37 +0000",
        "Sun, 06 Nov 1994 08:49:37 +00:00",
      ].each do |text|
        parsed = Dexpace::HTTPDate.parse(text)

        assert_equal(EXAMPLE, parsed, text)
        assert_predicate(parsed, :utc?, text)
      end
    end

    test "CFG-30: month and zone case do not matter; the weekday is stripped, not checked" do
      assert_equal(EXAMPLE, Dexpace::HTTPDate.parse("Sun, 06 nov 1994 08:49:37 GMT"))
      assert_equal(EXAMPLE, Dexpace::HTTPDate.parse("Sun, 06 NOV 1994 08:49:37 gmt"))
      # 6 November 1994 was a Sunday; the weekday is informational only (CFG-30).
      assert_equal(EXAMPLE, Dexpace::HTTPDate.parse("Mon, 06 Nov 1994 08:49:37 GMT"))
      assert_equal(EXAMPLE, Dexpace::HTTPDate.parse("xyz, 06 Nov 1994 08:49:37 GMT"))
    end

    test "CFG-31: blank input and a missing comma after the weekday fail with a parse error" do
      ["", "   ", "Mon 01 Jan 2024 00:00:00 GMT"].each do |text|
        error = assert_raises(Dexpace::InvalidArgumentError, text.inspect) do
          Dexpace::HTTPDate.parse(text)
        end

        assert_includes(error.message, text.inspect)
      end
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse(nil) }
    end

    # The rows a reader would not think to add: Time.httpdate accepts RFC 850 and asctime, so these
    # are what fail the day someone replaces the owned grammar with a delegation (R2, P5-12).
    test "CFG-31 / R2: RFC 850, asctime, a leading space and an embedded newline are rejected" do
      [
        "Sunday, 06-Nov-94 08:49:37 GMT",    # RFC 850
        "Sun Nov  6 08:49:37 1994",          # asctime -- no comma anywhere
        " Sun, 06 Nov 1994 08:49:37 GMT",    # leading space
        "Sun,\n06 Nov 1994 08:49:37 GMT",    # \s+ would accept this; a literal space does not
        "Sun, 06 Nov 1994 08:49:37 GMT\n",   # \Z would accept this; \z does not
        "Sun, 06 Nov 1994 08:49:37 GMT junk",
        "06 Nov 1994 08:49:37 GMT",          # no weekday at all: CFG-31's prefix is required
        "Sun, 06 Nov 1994 08:49:37",         # no zone
        "Sun, 06 Nov 1994 08:49:37 +0100",   # a non-zero offset is not one of the four tokens
        "Sun, 06 Nov 1994 08:49:37 EST",
        "Sun, 06 Nov 94 08:49:37 GMT",       # two-digit year
      ].each do |text|
        assert_raises(Dexpace::InvalidArgumentError, text.inspect) { Dexpace::HTTPDate.parse(text) }
      end
    end

    test "CFG-31: a well-formed but impossible date fails as a parse error, not an ArgumentError" do
      ["Sun, 32 Nov 1994 08:49:37 GMT", "Sun, 31 Nov 1994 08:49:37 GMT",
       "Sun, 06 Nov 1994 24:00:00 GMT", "Sun, 06 Nov 1994 08:60:37 GMT",
       "Sun, 29 Feb 1995 08:49:37 GMT", "Sun, 06 Xyz 1994 08:49:37 GMT",].each do |text|
        error = assert_raises(Dexpace::InvalidArgumentError, text.inspect) do
          Dexpace::HTTPDate.parse(text)
        end

        assert_includes(error.message, text.inspect)
      end
    end

    test "CFG-31: the grammar is one pattern, compiled once with a per-pattern timeout" do
      grammar = Dexpace::HTTPDate.const_get(:GRAMMAR)

      assert_kind_of(Regexp, grammar)
      refute_nil(grammar.timeout)
      assert_predicate(grammar, :frozen?)
      refute_includes(Dexpace::HTTPDate.constants, :GRAMMAR)
    end

    # testing/f36a19cd: a value with a parse-constructor round-trips. Floored, because RFC 1123
    # has no sub-second field, and every generated instant is UTC because the format renders UTC.
    test "property: parse(format(t)) == t.floor for sampled instants, seed logged on failure" do
      sample(count: 200) do |rng|
        instant = Time.at(rng.rand(0..4_102_444_800) + rng.rand).utc
        text = Dexpace::HTTPDate.format(instant)

        assert_equal(instant.floor, Dexpace::HTTPDate.parse(text), text)
      end
    end
  end
end
