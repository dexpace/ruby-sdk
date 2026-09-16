# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "step"
require_relative "../recovery/transform"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Pipeline
    # The generic adapter that installs a phase-4b Dexpace::Recovery::Transform into a non-pillar
    # stage (design §5.1, 4b's R8 clause 5; PIPE-37): the one object in this subsystem that names
    # a Dexpace::Recovery constant, and the only crossing between the two layers spec §8.3 keeps
    # apart. It depends on one value type and runs one way -- nothing under Dexpace::Recovery
    # names a cursor, a stage or a pipeline.
    #
    # It reads #phase ONCE, at build, and stores the branch; #call never asks again, so a
    # transform that changes its mind about #phase changes nothing -- the same composition-time
    # discipline Cursor#fork follows (R10), reached from the other direction. And it calls #apply,
    # never #call: 4b's Transform supplies `def call(value) = apply(value)` as the recovery
    # chain's one-argument step protocol, and this layer must not ride on it, so a future default
    # there cannot change what the pipeline does.
    #
    # It declares no #stage, deliberately. One wrapper serves three transforms whose correct
    # placements differ: PIPE-37 requires the error-mapping transform at Stages::PRE_REDIRECT,
    # outside every fork, so it observes only the single terminal response; an idempotency-key
    # transform belongs at or before PRE_RETRY so a re-attempt reuses the key. A #stage here
    # would be a stage for the wrapper rather than for what it wraps; the stage is named at
    # install (R10). This class cannot know which caller-supplied transforms are terminal-response
    # dependent, so PIPE-37's placement is documented, on PRE_REDIRECT and here, and not enforced.
    # What it does guarantee on the way past is nothing: a :response transform receives the
    # response the drive produced and returns what #apply returned, so 4b's untouched pass -- body
    # not read, consumed or closed on a non-error status -- reaches the caller intact.
    class TransformStep
      PHASES = %i[request response].freeze
      private_constant :PHASES

      # @return [Dexpace::Recovery::Transform] the wrapped transform
      attr_reader :transform

      private_class_method :new

      # The validating factory: the argument responds to #phase and #apply -- the two obligations
      # 4b's contract declares -- and #phase is :request or :response and nothing else. A third
      # value is refused in SEAM-29's message form; it is 4b's R8 clause 2, "neither may add a
      # third phase", made mechanical on this side, and the specific mistake it catches is a
      # phase naming the recovery-step list, which is Outcome -> Outcome and not a transform.
      #
      # @param transform [Dexpace::Recovery::Transform] anything answering #phase and #apply
      # @return [Dexpace::Pipeline::TransformStep]
      # @raise [Dexpace::InvalidArgumentError] for a non-transform or a third phase
      def self.build(transform)
        unless transform.respond_to?(:phase) && transform.respond_to?(:apply)
          raise InvalidArgumentError, "transform must respond to #phase and #apply"
        end

        phase = transform.phase
        unless PHASES.include?(phase)
          raise InvalidArgumentError,
                "transform #phase must be :request or :response, got #{phase.inspect}"
        end

        new(transform: transform, phase: phase)
      end

      def initialize(transform:, phase:)
        @transform = transform
        @phase = phase
      end

      # The whole behaviour, two lines: a :request transform applies to the request before the
      # drive, a :response transform to the response after it.
      #
      # @param request [Dexpace::Request]
      # @param cursor [Dexpace::Pipeline::Cursor]
      # @return [Dexpace::Response]
      def call(request, cursor)
        return cursor.call(@transform.apply(request)) if @phase == :request

        @transform.apply(cursor.call(request))
      end
    end
  end
end
