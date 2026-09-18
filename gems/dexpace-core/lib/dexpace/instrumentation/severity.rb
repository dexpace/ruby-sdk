# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Instrumentation
    # OBS-2: the facade's four severity levels -- ERROR, WARNING, INFO, VERBOSE -- and their
    # mapping onto a sink's ERROR, WARN, INFO and DEBUG. A frozen `Data` closed set over a
    # frozen table with an `.of` factory (type-system/545949a5), the shape Pipeline::Stage
    # takes: no public constructor, no derivation, and the four constants are the whole
    # population. The mapping is DATA, two members of the value rather than a `case`, so the
    # facade's sink call is `sink.public_send(severity.sink_method)` and its enabled check is
    # `sink.public_send(severity.sink_predicate)` -- one code path for four levels, a fifth
    # impossible to add by accident and the fourth impossible to map twice.
    class Severity < Data.define(:name, :sink_method, :sink_predicate)
      include Model

      private_class_method :new, :[]

      # Validates the three members. Reached only from the four constants below.
      def initialize(name:, sink_method:, sink_predicate:)
        [name, sink_method, sink_predicate].each do |member|
          next if member.is_a?(::Symbol)

          raise InvalidArgumentError, "a severity member must be a Symbol, got #{member.inspect}"
        end
        super
      end

      # Always raises: the closed set has no derivation, and the sink mapping OBS-2 fixes is
      # not a caller's to change (P4-32's shape).
      #
      # @param _changes [Hash, nil] ignored
      # @raise [Dexpace::InvalidArgumentError] always
      def with(_changes = nil)
        raise InvalidArgumentError,
              "the severity set is closed at four and a Severity cannot be derived; " \
              "use the constants on Dexpace::Instrumentation::Severity (OBS-2)"
      end

      # The most severe level, mapped onto the sink's #error / #error?.
      ERROR = new(name: :error, sink_method: :error, sink_predicate: :error?)
      # Mapped onto the sink's #warn / #warn?.
      WARNING = new(name: :warning, sink_method: :warn, sink_predicate: :warn?)
      # Mapped onto the sink's #info / #info?.
      INFO = new(name: :info, sink_method: :info, sink_predicate: :info?)
      # The most verbose level, mapped onto the sink's #debug / #debug?.
      VERBOSE = new(name: :verbose, sink_method: :debug, sink_predicate: :debug?)

      # All four, most severe first.
      ALL = [ERROR, WARNING, INFO, VERBOSE].freeze

      LOOKUP = ALL.to_h { |severity| [severity.name, severity] }.freeze
      private_constant :LOOKUP

      # Resolves a level by its name, by identity: `Severity.of(:info)` is `Severity::INFO`.
      #
      # @param name [Symbol] one of :error, :warning, :info or :verbose
      # @return [Severity]
      # @raise [Dexpace::InvalidArgumentError] for any other value
      def self.of(name)
        LOOKUP.fetch(name) do
          raise InvalidArgumentError,
                "unknown severity #{name.inspect}; expected one of #{LOOKUP.keys.inspect}"
        end
      end
    end
  end
end
