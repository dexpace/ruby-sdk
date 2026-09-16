# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../recovery"
require_relative "../error/invalid_argument_error"
require_relative "../http/request"

module Dexpace
  module Recovery
    # RECOV-3: the request recovery chain, a sequential left-to-right fold over an ordered list of
    # `Request -> Request` steps -- the output of step N is the input of step N+1, an empty chain
    # returns its input by identity, and a throwing step aborts the remainder and propagates.
    # This chain is deliberately NOT total: the throw is RECOV-3's own text, and RECOV-2's
    # orchestrator is what converts it into a Failure and threads it through the response chain,
    # so a before-request throw never skips after-error handling.
    #
    # A step is any #call-able of one argument (R8 clause 3): a bare lambda qualifies, and a
    # :request Transform installs as itself through its forwarding #call with no adapter. The
    # fold is Array#reduce and never an Enumerator, per design §7.1. A step that returns
    # something other than a Dexpace::Request is refused before the next step sees it -- a
    # caller-supplied step's mistake, raised as InvalidArgumentError so the orchestrator surfaces
    # it like any other error a step raises.
    #
    # RECOV-14, resolved toward the stricter of the reference's two behaviours: the list is
    # copied and frozen at construction, so later mutation of the caller's array cannot reach the
    # chain, and #steps returns that frozen copy itself. A shallow `dup` and not Model.own,
    # because a step is a callable whose closure cannot be deep-copied and the requirement is
    # about the LIST (P4-22); no shareability claim is made for a chain. A chain holds no other
    # state, so it is safe to apply concurrently from any number of contexts.
    class RequestChain
      # @return [Array<#call>] the frozen step list
      attr_reader :steps

      private_class_method :new

      # @param steps [Array<#call>] `Request -> Request` steps, applied in order
      # @return [Dexpace::Recovery::RequestChain]
      # @raise [Dexpace::InvalidArgumentError] when `steps` is not an Array of callables
      def self.build(steps: [])
        unless steps.is_a?(::Array) && steps.all? { |step| step.respond_to?(:call) }
          raise InvalidArgumentError, "steps must be an Array of objects responding to #call"
        end

        new(steps: steps.dup.freeze)
      end

      def initialize(steps:)
        @steps = steps
      end

      # @param request [Dexpace::Request]
      # @return [Dexpace::Request] the fold's result; the same object for an empty chain
      # @raise [Exception] whatever a step raised, with the remaining steps not invoked (RECOV-3)
      # @raise [Dexpace::InvalidArgumentError] when `request`, or a step's return, is not a Request
      def apply(request)
        check(request)
        @steps.reduce(request) { |current, step| check(step.call(current)) }
      end

      private

      def check(value)
        return value if value.is_a?(Request)

        raise InvalidArgumentError,
              "a request step must return a Dexpace::Request, got #{value.class}"
      end
    end
  end
end
