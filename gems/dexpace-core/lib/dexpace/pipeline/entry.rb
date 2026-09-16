# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "stage"
require_relative "step"
require_relative "../error/pipeline_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Pipeline
    # An immutable association between a stage and a conforming step (PIPE-22, PIPE-25): the unit
    # the builder holds, the unit #reload and #install_preset take (PIPE-23, PIPE-24), and the unit
    # Builder.flattening reads back off a built runtime (PIPE-35). Public because the bulk reload
    # and FLATTEN both need a caller-visible "this step, at this stage" -- without it, reload would
    # take two parallel arrays and flatten would need the runtime to expose its internals.
    #
    # `name` is the optional surgical-edit anchor. PIPE-18 to PIPE-21 key on a step's TYPE, and
    # every lambda step's class is Proc, so a type anchor cannot address one lambda and not
    # another; a name addresses exactly one entry. It is NOT part of PIPE-22/PIPE-23's pair --
    # nothing reads it outside the four edits -- and type anchoring is unchanged.
    #
    # Phase 1's construction rule taken whole: both generated constructors are private, .build is
    # the only path in, and Model#with routes a derivation back through it so the checks hold on
    # every interpreter in the range.
    class Entry < Data.define(:stage, :step, :name)
      include Model

      # Data.define generates .[] alongside .new; both are private so .build is the only path.
      private_class_method :new, :[]

      # The validating factory: a real Stage that is installable (PIPE-8 is rejected HERE, the one
      # place every install funnels through), a step that conforms to the two-argument protocol,
      # and a name that is nil, a Symbol or a String -- a String copied and frozen so a caller's
      # later mutation cannot reach the entry (XCUT-15).
      #
      # @param stage [Dexpace::Pipeline::Stage]
      # @param step [#call] a two-argument callable (Step.conforms?)
      # @param name [Symbol, String, nil] the optional anchor
      # @return [Dexpace::Pipeline::Entry]
      # @raise [Dexpace::InvalidArgumentError] for a non-Stage, a non-conforming step or a name
      #   of another type
      # @raise [Dexpace::PipelineError] for the terminal SEND stage (PIPE-8)
      def self.build(stage:, step:, name: nil)
        unless stage.is_a?(Stage)
          raise InvalidArgumentError, "stage must be a Dexpace::Pipeline::Stage (PIPE-1)"
        end
        if stage.terminal?
          raise PipelineError, "cannot install step at terminal stage SEND (PIPE-8)"
        end
        unless Step.conforms?(step)
          raise InvalidArgumentError, "step must conform to Dexpace::Pipeline::Step (PIPE-12)"
        end

        new(stage: stage, step: step, name: anchor_name(name))
      end

      # nil, a Symbol, or a String owned by the entry (XCUT-15).
      def self.anchor_name(name)
        case name
        when nil, ::Symbol then name
        when ::String then Model.frozen_string(name)
        else raise InvalidArgumentError, "name must be a Symbol or String (PIPE-18)"
        end
      end
      private_class_method :anchor_name
    end
  end
end
