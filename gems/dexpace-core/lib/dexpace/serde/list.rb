# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "scalars"
require_relative "decode_context"

module Dexpace
  module Serde
    # The Array combinator (SERDE-6): a witness for `Array[element]`, built BY VALUE from a concrete
    # element witness -- `List.of(Pet)`, `List.of(String)`, `List.of(List.of(Integer))` -- so a
    # parametric target is stated once, as data, with no reflective reconstruction anywhere. A
    # combinator is itself a witness, so combinators nest.
    #
    # Construction resolves the element through the scalar table and `Dexpace::Serde.witness!`,
    # so `List.of(nil)` and `List.of(Object.new)` raise at CONSTRUCTION with an actionable message
    # -- SERDE-8's "reject construction with no type argument", implemented. Its "unresolved type
    # variable" half is unreachable rather than emulated: a combinator cannot exist without a
    # concrete element (`serde/ffc92673`), which is also why `.witness!` fails earlier than the
    # reference's binder-resolution failure. A frozen Data in the phase-1 shape: `.new` and `.[]`
    # private, `.build` the validating factory `.of` and `#with` both route through.
    class List < Data.define(:element)
      include Model

      private_class_method :new, :[]

      # The ergonomic constructor design §7.3 names.
      #
      # @param element [Module, Object] the element witness, or String / Integer / Float / BOOLEAN
      # @return [List]
      # @raise [Dexpace::InvalidArgumentError] when `element` is not a witness (SERDE-8)
      def self.of(element) = build(element: element)

      # The validating factory every construction path goes through.
      #
      # @param element [Module, Object] the element witness
      # @return [List]
      # @raise [Dexpace::InvalidArgumentError] when `element` is not a witness (SERDE-8)
      def self.build(element:)
        new(element: element)
      end

      def initialize(element:)
        super(element: Scalars.resolve(element))
      end

      # The witness protocol: an Array whose every element decoded through the element witness at
      # its own index, so an element's shape failure names `/3/name` and not the container.
      #
      # @param parsed [Object] the parsed value; anything but an Array is a shape failure
      # @param ctx [Dexpace::Serde::DecodeContext]
      # @return [Array] fresh, never the parsed Array
      # @raise [Dexpace::Serde::DeserializationError]
      def dexpace_load(parsed, ctx)
        ctx.array!(parsed).each_with_index.map do |item, index|
          element.dexpace_load(item, ctx.at(index))
        end
      end
    end
  end
end
