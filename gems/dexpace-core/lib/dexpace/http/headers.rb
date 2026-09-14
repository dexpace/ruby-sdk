# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "header_name"
require_relative "header_syntax"

module Dexpace
  # A case-insensitive, multi-value, insertion-ordered header collection (HTTP-13 - HTTP-21).
  #
  # Two parallel frozen hashes rather than one: `values` is keyed by the folded name for lookup,
  # containment, equality and hashing, and `casing` carries the original casing HTTP-21 requires
  # for wire emission. Both are deep-frozen once at construction, and both readers are private --
  # the model's public surface is the accessors below, not its internals.
  #
  # `direction` is a member because HTTP-19's lenient inbound grammar is a property of the model,
  # not of the builder that happened to make it: without it, #new_builder on a response's headers
  # would hand back a strict builder that rejects the obs-text the model already holds.
  class Headers < Data.define(:values, :casing, :direction)
    include Model

    private_class_method :new
    private :values, :casing

    # The two grammars a collection can have been validated by (HTTP-18 outbound, HTTP-19 inbound).
    DIRECTIONS = %i[outbound inbound].freeze

    # The validating factory. `values` maps folded name to value list and `casing` maps folded
    # name to the casing to emit; both are copied and deep-frozen here, never aliased.
    def self.build(values:, casing:, direction: :outbound)
      new(
        values: Model.own(Model.required!("values", values)),
        casing: Model.own(Model.required!("casing", casing)),
        direction: direction,
      )
    end

    # A builder validating by the outbound grammar: the one a request's headers use.
    def self.builder
      Builder.new(direction: :outbound)
    end

    # A builder validating by the inbound grammar, which admits obs-text (HTTP-19).
    def self.inbound_builder
      Builder.new(direction: :inbound)
    end

    # HTTP-2's gap makes this necessary rather than paranoid: `.build` is public, `new` is
    # reachable through `send`, and #with routes every derivation back through `.build`. A model
    # whose only validation lived in Builder#add would accept a CRLF name from any of the three.
    def initialize(values:, casing:, direction:)
      validate_direction!(direction)
      validate_names!(values, casing)
      validate_values!(values, casing, direction)
      super
    end

    # HTTP-5, second tier: "per-name value-list accessors return the instance's own list". The
    # list is already frozen, so returning it is both cheaper and stricter than copying.
    def [](name)
      values[HeaderName.of(name).folded]
    end

    # Containment under the fold (HTTP-13).
    def include?(name)
      values.key?(HeaderName.of(name).folded)
    end

    # HTTP-5, first tier: "name-set and entry-set accessors return a fresh per-call snapshot".
    # Hash#values allocates, and the freeze makes the snapshot read-only rather than merely new.
    def names
      casing.values.freeze
    end

    # Every [name, value] pair in insertion order, a fresh frozen snapshot per call (HTTP-5).
    def entries
      pairs = [] #: Array[[String, String]]
      values.each do |folded, list|
        list.each { |value| pairs << [casing.fetch(folded), value] }
      end
      pairs.each(&:freeze).freeze
    end

    # Yields each [name, value] pair; without a block, an Enumerator over the same snapshot.
    def each_entry(&block)
      return enum_for(:each_entry) unless block

      entries.each(&block)
      self
    end

    # The number of distinct names.
    def size
      values.size
    end

    # True when no header is carried.
    def empty?
      values.empty?
    end

    # HTTP-3: a builder pre-filled from this instance that dups every value list and carries the
    # direction, so later mutation cannot reach back into this model.
    def new_builder
      Builder.new(direction: direction, values: values, casing: casing)
    end

    # HTTP-13 folds names for "storage, lookup, containment, mutation, removal, equality, and
    # hashing", so equality is over the folded values alone: two collections differing only in the
    # casing they will emit, or in the direction that validated them, are the same headers. Data
    # would generate equality over all three members and get that wrong (api-design/e4fa3438
    # permits the override with this comment).
    def ==(other)
      other.is_a?(Headers) && values == other.send(:values)
    end
    alias eql? ==

    # Agrees with #==: over the folded values alone.
    def hash
      values.hash
    end

    # The four validators are made private by name, below them, rather than under a `private`
    # section: the two constants at the end call `.build`, which runs them, so they must follow
    # the definitions, and a constant after a bare `private` reads as scoped when it is not.
    def validate_direction!(direction)
      return if DIRECTIONS.include?(direction)

      raise InvalidArgumentError, "direction must be one of: #{DIRECTIONS.join(", ")}"
    end

    # Set equality, not a one-way walk: a casing entry with no value list is not merely untidy,
    # it makes #names report a header #size and #[] do not have.
    def validate_names!(values, casing)
      orphans = casing.keys - values.keys
      unless orphans.empty?
        raise InvalidArgumentError,
              "casing carries #{HeaderSyntax.escape(orphans.first)}, which holds no values"
      end

      values.each_key { |folded| validate_name!(folded, casing[folded]) }
    end

    # A stored key must be a valid name already in its folded form, and its casing entry must
    # fold back to it; otherwise a lookup under the fold would miss the entry.
    def validate_name!(folded, original)
      return if HeaderName.of(folded).folded == folded && !original.nil? &&
                HeaderName.of(original).folded == folded

      raise InvalidArgumentError,
            "header #{HeaderSyntax.escape(folded)} is not stored under its folded name with " \
            "a matching original casing"
    end

    def validate_values!(values, casing, direction)
      values.each do |folded, list|
        name = casing.fetch(folded)
        unless list.is_a?(Array) && list.all?(String)
          raise InvalidArgumentError,
                "values for header #{HeaderSyntax.escape(folded)} must be a list of Strings"
        end

        list.each do |value|
          if direction == :inbound
            HeaderSyntax.validate_inbound_value!(value, name: name)
          else
            HeaderSyntax.validate_outbound_value!(value, name: name)
          end
        end
      end
    end

    private :validate_direction!, :validate_names!, :validate_name!, :validate_values!

    # The canonical outbound empty, so "no headers" allocates nothing per request.
    EMPTY = build(values: {}, casing: {})
    # The inbound counterpart, and not a convenience: `direction` is a member precisely so that
    # #new_builder agrees with the model it came from, and a response defaulted to the OUTBOUND
    # empty would hand a transport a strict builder that refuses the obs-text HTTP-19 relaxes.
    EMPTY_INBOUND = build(values: {}, casing: {}, direction: :inbound)
  end
end
