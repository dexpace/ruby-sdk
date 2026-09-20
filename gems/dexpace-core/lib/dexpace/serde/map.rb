# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "scalars"
require_relative "decode_context"

module Dexpace
  module Serde
    # The Hash combinator (SERDE-6): a witness for `Hash[key, value]`, built by value from a key
    # witness and a value witness -- `Map.of(String, Pet)`. The key witness is REQUIRED rather than
    # assumed to be String: JSON's keys always are, but a codec whose keys are not inherits the
    # combinator unchanged, and a key of the wrong shape is a shape failure like any other. Both
    # arguments resolve through the scalar table and `Dexpace::Serde.witness!` at construction
    # (SERDE-8). A frozen Data in the phase-1 shape.
    class Map < Data.define(:key, :value)
      include Model

      private_class_method :new, :[]

      # The ergonomic constructor design §7.3 names.
      #
      # @param key [Module, Object] the key witness, or a scalar class
      # @param value [Module, Object] the value witness, or a scalar class
      # @return [Map]
      # @raise [Dexpace::InvalidArgumentError] when either is not a witness (SERDE-8)
      def self.of(key, value) = build(key: key, value: value)

      # The validating factory every construction path goes through.
      #
      # @param key [Module, Object] the key witness
      # @param value [Module, Object] the value witness
      # @return [Map]
      # @raise [Dexpace::InvalidArgumentError] when either is not a witness (SERDE-8)
      def self.build(key:, value:)
        new(key: key, value: value)
      end

      def initialize(key:, value:)
        super(key: Scalars.resolve(key), value: Scalars.resolve(value))
      end

      # The witness protocol: a Hash whose every entry has its key and its value decoded through
      # the two witnesses at the entry's own path.
      #
      # @param parsed [Object] the parsed value; anything but a Hash is a shape failure
      # @param ctx [Dexpace::Serde::DecodeContext]
      # @return [Hash] fresh, never the parsed Hash
      # @raise [Dexpace::Serde::DeserializationError]
      def dexpace_load(parsed, ctx)
        ctx.object!(parsed).to_h do |raw_key, raw_value|
          frame = ctx.at(raw_key.is_a?(::Integer) ? raw_key : raw_key.to_s)
          [key.dexpace_load(raw_key, frame), value.dexpace_load(raw_value, frame)]
        end
      end
    end
  end
end
