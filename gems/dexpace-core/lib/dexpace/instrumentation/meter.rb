# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-31's monotonic integer counter, the no-op: discards every measurement. The class
    # behind the one shared instrument NO_METER#create_counter returns.
    #
    # OBS-33's MUST-document half, stated where a duck-typed SPI can bind it: only non-negative
    # increments are valid. A negative delta is undefined behaviour and is the caller's
    # responsibility, and "the core instrument MUST NOT validate this on the hot path" -- so
    # there is no check here, deliberately, and none in a conforming adapter either. The same
    # sentence is on _Counter#add in sig/. Frozen, stateless, safe from any thread (OBS-30).
    class NoCounter
      # Discards the increment (OBS-31), validating nothing (OBS-33).
      #
      # @param amount [Integer] the non-negative increment; a negative one is undefined behaviour
      # @param attributes [Hash{String => Object}, nil] per-measurement attributes, frozen by
      #   the caller
      # @return [nil]
      # rubocop:disable-next Lint/UnusedMethodArgument -- the measurement is discarded by design
      def add(amount, attributes: nil)
        nil
      end
    end
    private_constant :NoCounter

    # OBS-31's floating-point histogram, the no-op: discards every measurement. The class behind
    # the one shared instrument NO_METER#create_histogram returns. "A histogram MUST tolerate
    # any input without throwing (the no-op discards it)" -- NaN and either Infinity included --
    # and handling of non-finite values is a concrete adapter's (OBS-33); there is nothing here
    # to throw from. Frozen, stateless, safe from any thread (OBS-30).
    class NoHistogram
      # Discards the measurement (OBS-31, OBS-33).
      #
      # @param amount [Numeric] the measurement; any value, finite or not
      # @param attributes [Hash{String => Object}, nil] per-measurement attributes, frozen by
      #   the caller
      # @return [nil]
      # rubocop:disable-next Lint/UnusedMethodArgument -- the measurement is discarded by design
      def record(amount, attributes: nil)
        nil
      end
    end
    private_constant :NoHistogram

    # The two shared instrument singletons OBS-31 requires the default meter to return. Private:
    # "returns shared instrument singletons" is a reference-identity claim assertable
    # meter-to-meter -- `create_counter("a")` against `create_counter("b")` -- without naming
    # either instrument, so execution-context/b58728da's qualified-reference argument does not
    # force them public and api-design/b0e18938's minimal-surface rule keeps them private. That
    # is the asymmetry with NO_SPAN, which is public because Bundle::NONE.span must be asserted
    # against a qualified name.
    NO_COUNTER = NoCounter.new.freeze
    private_constant :NO_COUNTER

    NO_HISTOGRAM = NoHistogram.new.freeze
    private_constant :NO_HISTOGRAM

    # OBS-31's Meter, the no-op: manufactures the two shared instruments above whatever it is
    # asked for, and pulls no metrics runtime into core -- there is no dependency to pull. Named
    # keywords, never a `**` splat (P5-42); nothing here writes an ivar, so every call on the
    # frozen NO_METER allocates nothing (OBS-25 through OBS-31's sharing clause).
    #
    # No instrument name, unit or attribute set is fixed here: OBS-32's OpenTelemetry conventions
    # are post-v1 with dexpace-instrumentation-otel, and the two instrument names 5b's step
    # records under are 5b's constants (R11).
    class NoMeter
      # rubocop:disable Lint/UnusedMethodArgument -- name, unit and description are the
      # documented protocol; a discarding meter has nothing to do with them.

      # The shared no-op counter, whatever the name (OBS-31).
      #
      # @param name [String] the instrument name
      # @param unit [String, nil] the UCUM unit symbol
      # @param description [String, nil] the instrument description
      # @return [Object] the one shared no-op _Counter
      def create_counter(name, unit: nil, description: nil)
        NO_COUNTER
      end

      # The shared no-op histogram, whatever the name (OBS-31).
      #
      # @param name [String] the instrument name
      # @param unit [String, nil] the UCUM unit symbol
      # @param description [String, nil] the instrument description
      # @return [Object] the one shared no-op _Histogram
      def create_histogram(name, unit: nil, description: nil)
        NO_HISTOGRAM
      end
      # rubocop:enable Lint/UnusedMethodArgument
    end
    private_constant :NoMeter

    # The one shared, frozen no-op meter: OBS-31's default, and the `meter:` default of 5b's
    # instrumentation step (R11). Public for the reason NO_SPAN is -- a qualified reference is
    # how a conformance assertion names it -- while its instruments stay private (above).
    NO_METER = NoMeter.new.freeze
  end
end
