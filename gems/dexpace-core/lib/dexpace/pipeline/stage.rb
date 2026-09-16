# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Pipeline
    # One stage in the pipeline's total ordering (PIPE-1, PIPE-3): a name, a sparse order key, and
    # two flags -- whether the stage is a pillar admitting at most one step (PIPE-4) and whether it
    # is the terminal SEND hop that admits none (PIPE-8).
    #
    # The set is closed at sixteen, structurally (P4-32): both generated constructors are private
    # and there is no public factory at all, so every instance is one of the constants on
    # Dexpace::Pipeline::Stages and Stages.of is the only lookup. That is what makes PIPE-2's
    # "the runtime MUST preserve the pillar precedence chain" a property of the type rather than
    # a policy -- a caller cannot mint a sixteenth-and-a-half stage and therefore cannot add a
    # pillar. Data#with would reopen the set on 3.4 and 4.0 (it copies without calling
    # #initialize's caller, and Model#with would route to a .build that does not exist), so #with
    # is overridden to refuse. The send hole phase 1's P8 names stays open and is not closable.
    #
    # Nothing sorts a Stage at run time. A Data responds to <=> through Kernel#<=>, which returns
    # nil for two distinct stages, so `entries.sort_by(&:stage)` raises ArgumentError at the first
    # two-stage pipeline; ordering is always Stages::ALL's position, and #order exists so a caller
    # can order by it, never so the runtime does.
    class Stage < Data.define(:name, :order, :pillar, :terminal)
      include Model

      # Data.define generates .[] alongside .new; both are private, because P4-32's closed-set
      # claim is structural and .[] alone would reopen it.
      private_class_method :new, :[]

      # @param name [Symbol] the stage's name, what an error message names (PIPE-5, PIPE-18)
      # @param order [Integer] the sparse order key (PIPE-3)
      # @param pillar [Boolean] whether the stage admits at most one step (PIPE-4)
      # @param terminal [Boolean] whether the stage is the SEND hop (PIPE-8); implies pillar
      # @raise [Dexpace::InvalidArgumentError] on a member of the wrong shape, or a terminal
      #   stage that is not also a pillar (PIPE-4's parenthesis)
      def initialize(name:, order:, pillar:, terminal:)
        raise InvalidArgumentError, "name must be a Symbol (PIPE-1)" unless name.is_a?(::Symbol)
        raise InvalidArgumentError, "order must be an Integer (PIPE-1)" unless order.is_a?(Integer)
        raise InvalidArgumentError, "pillar must be true or false (PIPE-4)" unless boolean?(pillar)
        unless boolean?(terminal)
          raise InvalidArgumentError, "terminal must be true or false (PIPE-8)"
        end
        if terminal && !pillar
          raise InvalidArgumentError, "a terminal stage is also a pillar (PIPE-4)"
        end

        super
      end

      # The two flags read as predicates; the raw Data readers are private so the surface carries
      # one spelling of each (phase 1's Headers and Query hide a reader the same way).
      private :pillar, :terminal

      # Whether the stage admits at most one step (PIPE-4), and -- unless it is also terminal --
      # whether a step occupying it may fork (R10).
      def pillar? = pillar

      # Whether the stage is the reserved SEND hop (PIPE-8).
      def terminal? = terminal

      # Whether a step may be installed here: every stage but SEND (PIPE-8).
      def installable? = !terminal

      # The closed set has no derivation: there is no Stage.build for Model#with to route
      # through, and Data#with would mint a stage Stages.of cannot find (P4-32).
      #
      # @raise [Dexpace::InvalidArgumentError] always
      def with(_changes = nil)
        raise InvalidArgumentError,
              "the stage set is closed at sixteen and a Stage cannot be derived; " \
              "use the constants on Dexpace::Pipeline::Stages (P4-32)"
      end

      private

      def boolean?(value) = [true, false].include?(value)
    end
  end
end
