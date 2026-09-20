# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "native"
require_relative "scalars"
require_relative "decode_context"

module Dexpace
  module Serde
    # The three-state PATCH type (SERDE-14–SERDE-20, SERDE-30): Absent (the key is missing), Null
    # (the key is present with an explicit null) and Present (the key carries a value). A module
    # included by all three values -- exactly Outcome's shape (4b) and Context's (4a) -- so
    # `v.is_a?(Dexpace::Serde::Tristate)` is one type test and the RBS union has a name.
    #
    # SERDE-14's illegal fourth state, Present-of-null, is unrepresentable on BOTH paths: `Present`
    # validates in `#initialize`, so `.build`, the private `.new` and `.[]`, and the
    # send-past-private hole P8 records all refuse nil; and `Dexpace::Model#with` routes a
    # derivation through `.build` on every supported Ruby (`data-modeling/83610619`: Data#with skips
    # an `initialize` override on 3.2), so `Tristate.present(1).with(value: nil)` raises too. The
    # covariance clause is satisfied by the language (design §11.15) and has no code.
    #
    # `.of(element)` and `.from_nullable(value)` are two different things with two different names,
    # deliberately: the first is the decode-side combinator design §7.3 names, the second is
    # SERDE-18's "nullable-to-(present|null) mapper that can never yield Absent". One `.of` doing
    # both would be the API-design mistake SERDE-18's own conformance clause exists to catch.
    #
    # `#dexpace_dump` is where the type meets Native's walk: OMIT for Absent (the walk drops the
    # key, SERDE-15), nil for Null, the inner value for Present (re-walked, so a nested model or a
    # nested Tristate is handled by the same recursion). The two sentinels override `#to_s` and
    # `#inspect` (SERDE-30, taken) because Ruby's default `#inspect` renders an object id, which
    # would make a log line or a test failure differ between runs; the frozen singletons are
    # Ractor-shareable as a free side effect that no claim rests on.
    module Tristate
      # @return [Boolean] whether this is the Absent value
      def absent? = false

      # @return [Boolean] whether this is the Null value
      def null? = false

      # @return [Boolean] whether this is a Present value
      def present? = false

      # SERDE-18's value-or-null accessor: the inner value for Present, nil otherwise.
      #
      # @return [Object, nil]
      def value_or_nil = nil

      # SERDE-18's three-way fold.
      #
      # @param on_absent [#call] called with no argument for Absent
      # @param on_null [#call] called with no argument for Null
      # @param on_present [#call] called with the inner value for Present
      # @return [Object] whatever the matching callable returned
      def fold(on_absent:, on_null:, on_present:)
        if present?
          on_present.call(value_or_nil)
        elsif null?
          on_null.call
        else
          on_absent.call
        end
      end

      # The Absent sentinel's class: private, so a caller reaches the value through ABSENT alone.
      class Absent
        include Tristate

        # @return [true]
        def absent? = true

        # SERDE-15: an Absent field's key is omitted; the walk drops OMIT.
        #
        # @return [Dexpace::Serde::OMIT]
        def dexpace_dump = OMIT

        # @return [String] "Absent" (SERDE-30)
        def to_s = "Absent"
        alias inspect to_s
      end

      # The Null sentinel's class: private, so a caller reaches the value through NULL alone.
      class Null
        include Tristate

        # @return [true]
        def null? = true

        # SERDE-15: a Null field emits its key with a wire null.
        #
        # @return [nil]
        def dexpace_dump = nil

        # @return [String] "Null" (SERDE-30)
        def to_s = "Null"
        alias inspect to_s
      end
      private_constant :Absent, :Null

      # The Absent value: the key is missing.
      ABSENT = Absent.new.freeze

      # The Null value: the key is present with an explicit null.
      NULL = Null.new.freeze

      # A Present value, bounded to non-null (SERDE-14). A frozen Data in the phase-1 shape whose
      # equality is the inner value's.
      class Present < Data.define(:value)
        include Model
        include Tristate

        private_class_method :new, :[]

        # The validating factory every construction path goes through (`#with` included).
        #
        # @param value [Object] non-nil
        # @return [Present]
        # @raise [Dexpace::InvalidArgumentError] "value is required", on nil (SERDE-14, SEAM-29)
        def self.build(value:)
          new(value: value)
        end

        def initialize(value:)
          Model.required!("value", value)
          super
        end

        # @return [true]
        def present? = true

        # @return [Object] the inner value
        def value_or_nil = value

        # SERDE-15: a Present field emits its key with the encoded inner value; Native re-walks it.
        #
        # @return [Object] the inner value
        def dexpace_dump = value
      end

      # The decode-side combinator `.of` returns: a witness for a tri-state field. Private, because
      # `.of` is the whole of its public surface; a frozen Data by value from its element witness.
      class Combinator < Data.define(:element)
        include Model

        private_class_method :new, :[]

        # @param element [Module, Object] the element witness, or a scalar class the table knows
        # @return [Combinator]
        def self.build(element:)
          new(element: element)
        end

        def initialize(element:)
          super(element: Scalars.resolve(element))
        end

        # SERDE-20's top-level case: the protocol entry point sees only the value, so a null is
        # Null and anything else is Present of the element's decode.
        #
        # @param parsed [Object]
        # @param ctx [Dexpace::Serde::DecodeContext]
        # @return [Tristate]
        def dexpace_load(parsed, ctx)
          return NULL if parsed.nil?

          Present.build(value: element.dexpace_load(parsed, ctx))
        end

        # SERDE-16/SERDE-17's in-object case, three lines because of verified fact 6: the enclosing
        # Hash answers `key?` directly, so a missing key is Absent, a present null is Null and a
        # present value is Present of the element's decode at the key's own path. No field-default
        # machinery, none emulated.
        #
        # @param hash [Hash] the enclosing parsed object
        # @param key [String] the field's key
        # @param ctx [Dexpace::Serde::DecodeContext] the enclosing object's context
        # @return [Tristate]
        def dexpace_load_field(hash, key, ctx)
          entries = ctx.object!(hash)
          return ABSENT unless entries.key?(key)

          value = entries[key]
          return NULL if value.nil?

          Present.build(value: element.dexpace_load(value, ctx.at(key)))
        end
      end
      private_constant :Combinator

      class << self
        # SERDE-18: the Absent factory.
        #
        # @return [Tristate] ABSENT
        def absent = ABSENT

        # SERDE-18: the explicit-null factory.
        #
        # @return [Tristate] NULL
        def null = NULL

        # SERDE-18: the Present factory, refusing nil.
        #
        # @param value [Object] non-nil
        # @return [Tristate::Present]
        # @raise [Dexpace::InvalidArgumentError] on nil (SERDE-14)
        def present(value) = Present.build(value: value)

        # SERDE-18's nullable mapper: Present for a non-nil value, Null for nil, and NEVER Absent.
        #
        # @param value [Object, nil]
        # @return [Tristate]
        def from_nullable(value) = value.nil? ? NULL : Present.build(value: value)

        # The decode-side combinator (design §7.3): a witness for a tri-state field of `element`,
        # with `#dexpace_load_field(hash, key, ctx)` for the in-object case and the protocol's
        # `#dexpace_load(parsed, ctx)` for the top-level one.
        #
        # @param element [Module, Object] the element witness, or a scalar class
        # @return [Object] a witness
        # @raise [Dexpace::InvalidArgumentError] when `element` is not a witness (SERDE-8)
        def of(element) = Combinator.build(element: element)
      end
    end
  end
end
