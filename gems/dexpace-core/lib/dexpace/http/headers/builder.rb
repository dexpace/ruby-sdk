# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../builder"
require_relative "../../model"
require_relative "../header_name"
require_relative "../header_syntax"

module Dexpace
  class Headers
    # The mutable assembler for a Headers (HTTP-14, HTTP-15), validating by its direction's
    # grammar on every add so a rejected entry leaves no partial state behind.
    class Builder
      include Dexpace::Builder

      # Which grammar this builder validates values by: :outbound (HTTP-18) or :inbound (HTTP-19).
      attr_reader :direction

      # HTTP-3: a builder pre-filled from a model dups every value list rather than aliasing it.
      def initialize(direction: :outbound, values: {}, casing: {})
        @direction = direction
        @values = values.transform_values(&:dup)
        @casing = casing.dup
      end

      # Appends a value to the name's list (HTTP-14). Validate BEFORE recording: recording the
      # casing first leaves an orphan entry behind when the value is rejected, and #names would
      # then report a header the model does not carry -- a partial side effect testing/62f8f4ec
      # exists to catch.
      def add(name, value)
        header = HeaderName.of(name)
        validated = validate_value(value, header)
        record(header)
        (@values[header.folded] ||= []) << validated
        self
      end

      # Replaces the name's whole list with one value; `nil` removes the header entirely
      # (HTTP-15).
      def set(name, value)
        return remove(name) if value.nil?

        header = HeaderName.of(name)
        validated = validate_value(value, header)
        record(header)
        @values[header.folded] = [validated]
        self
      end

      # Drops every value of the name and forgets its casing.
      def remove(name)
        folded = HeaderName.of(name).folded
        @values.delete(folded)
        @casing.delete(folded)
        self
      end

      # The frozen model; the builder stays usable and later mutation does not reach it.
      def build
        Headers.build(values: @values, casing: @casing, direction: @direction)
      end

      private

      # The first casing seen for a name is the one emitted (HTTP-21); a later add under another
      # casing appends to the same list without renaming it.
      def record(header)
        @casing[header.folded] ||= header.original
      end

      # HTTP-20: the message names the header (trimmed, and escaped by HeaderSyntax) and never
      # echoes the value.
      def validate_value(value, header)
        Model.required!("header value", value)
        raise InvalidArgumentError, "header value must be a String" unless value.is_a?(String)

        if @direction == :inbound
          HeaderSyntax.validate_inbound_value!(value, name: header.original)
        else
          HeaderSyntax.validate_outbound_value!(value, name: header.original)
        end
      end
    end
  end
end
