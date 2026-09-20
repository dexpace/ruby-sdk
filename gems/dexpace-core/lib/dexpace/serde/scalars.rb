# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "witness"
require_relative "decode_context"

module Dexpace
  module Serde
    # The scalar witnesses behind the ergonomic spellings design §7.3 uses verbatim --
    # `List.of(String)`, `Map.of(String, Pet)`, `Tristate.of(Float)` -- so a combinator's argument
    # is uniformly "a witness" while a bare class object still works where a scalar is meant. A
    # private_constant with a sig/ mirror, consulted by every combinator's constructor; not public
    # API. The one public name it needs, BOOLEAN, is defined below it on Serde itself.
    module Scalars
      extend self

      # One scalar witness: a name for the diagnostics and the DecodeContext check it delegates to.
      # Frozen singletons, so two `List.of(String)` share one element and compare equal.
      class Scalar
        # @param name [String] the textual form
        # @param check [Proc] `(parsed, ctx) -> value`, one of DecodeContext's `!` methods
        def initialize(name, check)
          @name = name
          @check = check
          freeze
        end

        # The witness protocol: delegates the shape check to the context (SERDE-21, SERDE-22).
        #
        # @param parsed [Object]
        # @param ctx [Dexpace::Serde::DecodeContext]
        # @return [Object] the checked value
        def dexpace_load(parsed, ctx) = @check.call(parsed, ctx)

        # @return [String] the scalar's name
        def to_s = @name
        alias inspect to_s
      end

      # The String witness: DecodeContext#string!.
      STRING = Scalar.new("String", ->(parsed, ctx) { ctx.string!(parsed) })
      # The Integer witness: DecodeContext#integer!.
      INTEGER = Scalar.new("Integer", ->(parsed, ctx) { ctx.integer!(parsed) })
      # The Float witness: DecodeContext#float!, with SERDE-22's widening.
      FLOAT = Scalar.new("Float", ->(parsed, ctx) { ctx.float!(parsed) })
      # The boolean witness, published on Serde as BOOLEAN: DecodeContext#boolean!.
      BOOLEAN = Scalar.new("Boolean", ->(parsed, ctx) { ctx.boolean!(parsed) })

      # The class-to-witness table. ::Time is deliberately absent: the ISO-8601 wiring is the
      # adapter's per design §3.4, and a core mapping would make it every codec's default. Booleans
      # are not keyed on TrueClass/FalseClass either -- that is what BOOLEAN is for.
      TABLE = { ::String => STRING, ::Integer => INTEGER, ::Float => FLOAT }.freeze

      # The one place the ergonomic spelling and the protocol meet: a class in the table resolves
      # to its scalar witness, and anything else must be a witness in its own right (SERDE-8's
      # fail-fast, at construction).
      #
      # @param witness [Module, Object] a table class or a witness
      # @return [Object] a witness
      # @raise [Dexpace::InvalidArgumentError] when it is neither
      def resolve(witness)
        TABLE.fetch(witness) { Dexpace::Serde.witness!(witness) }
      end
    end
    private_constant :Scalars

    # The boolean scalar witness -- `List.of(Dexpace::Serde::BOOLEAN)` -- a NAMED witness rather
    # than two class keys, because Ruby has no Boolean class to key on and `List.of(TrueClass)`
    # would read as a list of `true`s. Accepts exactly `true` and `false` (SERDE-21).
    BOOLEAN = Scalars::BOOLEAN
  end
end
