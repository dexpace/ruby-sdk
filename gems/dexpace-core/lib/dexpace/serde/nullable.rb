# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "scalars"
require_relative "decode_context"

module Dexpace
  module Serde
    # The nullable combinator (SERDE-6): a witness that accepts a wire null where its element
    # witness would not -- `Nullable.of(Pet)` decodes `null` to nil and anything else through `Pet`.
    #
    # It is the witness-aware half of SERDE-13's repair. `#load` screens nothing for nil itself,
    # because THIS witness and `Tristate.of` legitimately want a top-level null (SERDE-20), and
    # neither ever calls `ctx.object!` on nil -- so a null into a non-null target still fails
    # through the element witness, naming the target, with no exemption anywhere. Resolves its
    # element at construction (SERDE-8); a frozen Data in the phase-1 shape.
    class Nullable < Data.define(:element)
      include Model

      private_class_method :new, :[]

      # The ergonomic constructor design §7.3 names.
      #
      # @param element [Module, Object] the element witness, or a scalar class
      # @return [Nullable]
      # @raise [Dexpace::InvalidArgumentError] when `element` is not a witness (SERDE-8)
      def self.of(element) = build(element: element)

      # The validating factory every construction path goes through.
      #
      # @param element [Module, Object] the element witness
      # @return [Nullable]
      # @raise [Dexpace::InvalidArgumentError] when `element` is not a witness (SERDE-8)
      def self.build(element:)
        new(element: element)
      end

      def initialize(element:)
        super(element: Scalars.resolve(element))
      end

      # The witness protocol: nil for a wire null, the element's decode otherwise.
      #
      # @param parsed [Object]
      # @param ctx [Dexpace::Serde::DecodeContext]
      # @return [Object, nil]
      # @raise [Dexpace::Serde::DeserializationError] from the element witness
      def dexpace_load(parsed, ctx)
        return nil if parsed.nil?

        element.dexpace_load(parsed, ctx)
      end
    end
  end
end
