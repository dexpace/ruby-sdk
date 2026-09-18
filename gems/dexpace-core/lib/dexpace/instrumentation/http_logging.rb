# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Instrumentation
    # OBS-34 and OBS-35: the HTTP logging granularity -- none, headers-only, headers-plus-body --
    # as a frozen `Data` closed set over a frozen table, the shape Severity and Pipeline::Stage
    # take: no public constructor, no derivation, three constants and DEFAULT. `order` exists for
    # exactly one comparison, #at_least?, which is the only question the instrumentation step
    # asks of its level.
    #
    # Two ways in from text, because the tolerant parse has a caller with no Configuration: a
    # caller holding a level String from a YAML file, a Rails initializer or a flag gets OBS-35's
    # tolerance through .parse without touching the chain, and .resolve is .parse over
    # Configuration#string. .resolve takes its key as a REQUIRED keyword (P5-36): OBS-35's
    # embedded MUST is "The SDK MUST NOT bake in a default config key name", and 5a's
    # reconciliation against CFG-14 fixed the published log-level key as a name a caller may
    # pass and never a fallback any resolver reads on its own.
    class HTTPLogging < Data.define(:name, :order)
      include Model

      private_class_method :new, :[]

      # Validates the two members. Reached only from the three constants below.
      def initialize(name:, order:)
        raise InvalidArgumentError, "name must be a Symbol" unless name.is_a?(::Symbol)
        raise InvalidArgumentError, "order must be an Integer" unless order.is_a?(::Integer)

        super
      end

      # OBS-34's one comparison: whether this level includes `other`'s output.
      #
      # @param other [HTTPLogging]
      # @return [Boolean]
      def at_least?(other)
        order >= other.order
      end

      # Always raises: the closed set has no derivation.
      #
      # @param _changes [Hash, nil] ignored
      # @raise [Dexpace::InvalidArgumentError] always
      def with(_changes = nil)
        raise InvalidArgumentError,
              "the HTTP logging level set is closed at three and a level cannot be derived; " \
              "use the constants on Dexpace::Instrumentation::HTTPLogging (OBS-34)"
      end

      # No request or response log events (OBS-34); tracing and metrics still run.
      NONE = new(name: :none, order: 0)
      # Request and response events with their headers, and no body capture.
      HEADERS = new(name: :headers, order: 1)
      # Headers plus a bounded body preview on the response and failure events (OBS-36).
      BODY = new(name: :body, order: 2)

      # OBS-34's "defaulting to none (logging off unless explicitly opted in)", XCUT-19(e).
      DEFAULT = NONE

      ALL = [NONE, HEADERS, BODY].freeze
      private_constant :ALL
      LOOKUP = ALL.to_h { |level| [level.name, level] }.freeze
      private_constant :LOOKUP
      TEXT_LOOKUP = ALL.to_h { |level| [level.name.name, level] }.freeze
      private_constant :TEXT_LOOKUP

      # Resolves a level by its name, strictly and by identity.
      #
      # @param name [Symbol] :none, :headers or :body
      # @return [HTTPLogging]
      # @raise [Dexpace::InvalidArgumentError] for any other value
      def self.of(name)
        LOOKUP.fetch(name) do
          raise InvalidArgumentError,
                "unknown HTTP logging level #{name.inspect}; expected one of #{LOOKUP.keys.inspect}"
        end
      end

      # OBS-35's tolerant parse: whitespace-trimmed, case-insensitive (`downcase` with no
      # argument, Dexpace/NoLocaleCaseFold), and `default` for an absent, empty or unrecognised
      # value. Never raises: the text is scrubbed before the fold so invalid bytes cannot.
      #
      # @param text [String, Symbol, nil] the configured value
      # @param default [HTTPLogging] what an absent, empty or unrecognised value resolves to
      # @return [HTTPLogging]
      def self.parse(text, default: NONE)
        return default if text.nil?

        TEXT_LOOKUP.fetch(text.to_s.scrub("").strip.downcase, default)
      end

      # OBS-35's layered resolution: .parse over the chain's four tiers for `key`, which the
      # caller names and this method never defaults (P5-36).
      #
      # @param configuration [Dexpace::Configuration] the chain
      # @param key [String] the caller's key; the published log-level name on
      #   Configuration::Keys is one a caller may pass here, and 5a's keys_test.rb asserts that
      #   no file under lib/ spells it out -- this one included
      # @param default [HTTPLogging] what an absent, empty or unrecognised value resolves to
      # @return [HTTPLogging]
      def self.resolve(configuration, key:, default: NONE)
        parse(configuration.string(key), default: default)
      end
    end
  end
end
