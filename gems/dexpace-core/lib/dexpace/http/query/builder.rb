# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../builder"
require_relative "../../error/invalid_argument_error"

module Dexpace
  class Query
    # The mutable assembler for a Query (HTTP-28, HTTP-30).
    #
    # #add coerces a scalar and refuses a container. Query.build requires every pair to be two
    # Strings, and this is where a caller's raw value becomes one -- phase 2's operation
    # projection passes operation inputs straight through, so `{ limit: 1 }` has to render
    # `limit=1` rather than raise. A Hash or an Array is refused rather than coerced, because
    # `#to_s` on a container emits Ruby's inspect form onto the wire, which is a silently wrong
    # URL rather than a failure; a caller flattening an object-valued parameter supplies the
    # flattened names itself, one #add per leaf.
    class Builder
      include Dexpace::Builder

      # The classes #add and #set coerce through #to_s, and the only ones.
      SCALARS = [::String, ::Symbol, ::Integer, ::Float, ::TrueClass, ::FalseClass].freeze

      # HTTP-3: a builder pre-filled from a model dups every pair rather than aliasing it.
      def initialize(pairs: [])
        @pairs = pairs.map(&:dup)
      end

      # Appends one value under the name; `nil` is the value-less parameter, "" (HTTP-28).
      def add(name, value)
        @pairs << pair(coerce(name, "query name"), value)
        self
      end

      # Replaces every occurrence of the name with the given values, in place at the name's first
      # position; an empty list removes the name, so no phantom entry can reach the model
      # (HTTP-30).
      def set(name, values)
        key = coerce(name, "query name")
        raise InvalidArgumentError, "query values must be a list" unless values.is_a?(Array)

        replacements = values.map { |value| pair(key, value) }
        position = @pairs.index { |pair| pair.first == key } || @pairs.length
        @pairs.reject! { |pair| pair.first == key }
        @pairs.insert([position, @pairs.length].min, *replacements)
        self
      end

      # Drops every occurrence of the name.
      def remove(name)
        key = coerce(name, "query name")
        @pairs.reject! { |pair| pair.first == key }
        self
      end

      # The frozen model; the builder stays usable and later mutation does not reach it.
      def build
        Query.build(pairs: @pairs)
      end

      private

      # One [name, value] pair; `nil` is the value-less parameter, "" (HTTP-28).
      def pair(key, value)
        [key, value.nil? ? "" : coerce(value, "query value")] #: [String, String]
      end

      def coerce(value, label)
        unless SCALARS.any? { |type| value.is_a?(type) }
          raise InvalidArgumentError,
                "#{label} must be a scalar, got #{value.class} -- flatten it before adding it"
        end

        value.to_s
      end
    end
  end
end
