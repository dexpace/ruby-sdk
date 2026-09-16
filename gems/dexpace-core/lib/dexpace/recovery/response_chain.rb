# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../recovery"
require_relative "ownership"
require_relative "../error/invalid_argument_error"
require_relative "../error/outcome_error"
require_relative "../http/response"
require_relative "../outcome"
require_relative "../outcome/success"
require_relative "../outcome/failure"

module Dexpace
  module Recovery
    # The response recovery chain (RECOV-4 through RECOV-8, RECOV-12 through RECOV-14): two folds
    # over two frozen step lists, in one fixed order -- every response step first, on the success
    # path only, then every recovery step, on every outcome, always (RECOV-6).
    #
    # The two loops fold different types, and that is RECOV-4's own parenthesis. A RESPONSE step
    # is `Response -> Response`: the loop unwraps the Success, hands the step the response, and
    # rewraps whatever comes back; it runs only while the outcome is a Success (RECOV-4), so a
    # response step can never return a Failure or a substitute Success. A RECOVERY step is
    # `Outcome -> Outcome`: it is handed the outcome itself, runs whatever the outcome is --
    # including a failure a response step just produced by throwing (RECOV-5) -- and is the only
    # step position that can deliberately return a different outcome, which is where RECOV-13
    # lands. A step is any one-argument #call-able (R8 clause 3), so a lambda qualifies and a
    # Transform installs as itself.
    #
    # A throwing response step's error becomes a Failure fed to the recovery steps (RECOV-7); a
    # throwing recovery step's error becomes a Failure fed to the NEXT recovery step (RECOV-8),
    # never aborting the remainder. Both go through Ownership.close_on_throw, the one place the
    # in-hand response is closed. RECOV-9 is a SHOULD about step authors: a recovery step should
    # not throw, and should surface its error by returning Outcome::Failure.build(error:); a
    # throw is tolerated, but it cedes control of the wrapped error to this chain's defensive
    # catch, and a step that returns a Failure keeps it.
    #
    # #apply raises for no Outcome input and no step behaviour inside StandardError (RECOV-8),
    # with three stated exceptions rather than two (P4-19): the fatal family, which is surfaced
    # unchanged (RETRY-25); Dexpace::OutcomeError, raised when a recovery step returns something
    # that is not an Outcome and re-raised by name rather than demoted to a Failure a later step
    # may swallow (R6); and a non-Outcome ARGUMENT, refused at this boundary with
    # InvalidArgumentError before any fold runs. The `case/in` with the raising `else` is used at
    # exactly the place a value arrives from a caller-supplied step with its type unproven; the
    # other such place is the orchestrator's unwrap.
    #
    # RECOV-14, the explicit MUST for this chain: both lists are copied and frozen at
    # construction with a shallow `dup` (P4-22), and the chain holds no other state, so one chain
    # is safe to apply concurrently from any number of contexts.
    class ResponseChain
      # @return [Array<#call>] the frozen `Response -> Response` list
      attr_reader :response_steps

      # @return [Array<#call>] the frozen `Outcome -> Outcome` list
      attr_reader :recovery_steps

      private_class_method :new

      # @param response_steps [Array<#call>] `Response -> Response`, applied on a Success only
      # @param recovery_steps [Array<#call>] `Outcome -> Outcome`, applied on every outcome
      # @return [Dexpace::Recovery::ResponseChain]
      # @raise [Dexpace::InvalidArgumentError] when either list is not an Array of callables
      def self.build(response_steps: [], recovery_steps: [])
        new(
          response_steps: copy("response_steps", response_steps),
          recovery_steps: copy("recovery_steps", recovery_steps),
        )
      end

      def self.copy(name, steps)
        unless steps.is_a?(::Array) && steps.all? { |step| step.respond_to?(:call) }
          raise InvalidArgumentError, "#{name} must be an Array of objects responding to #call"
        end

        steps.dup.freeze
      end
      private_class_method :copy

      def initialize(response_steps:, recovery_steps:)
        @response_steps = response_steps
        @recovery_steps = recovery_steps
      end

      # @param outcome [Dexpace::Outcome]
      # @return [Dexpace::Outcome] the terminal outcome, after both folds
      # @raise [Dexpace::InvalidArgumentError] when `outcome` is not a Dexpace::Outcome
      # @raise [Dexpace::OutcomeError] when a recovery step returned something that is not one
      def apply(outcome)
        unless outcome.is_a?(Outcome)
          raise InvalidArgumentError, "outcome must be a Dexpace::Outcome"
        end

        recover(respond(outcome))
      end

      private

      # RECOV-4, RECOV-6, RECOV-7: the response steps, on a Success only, each rewrapped -- the
      # outcome itself when the step handed the same response back, so a pass-through allocates
      # nothing -- and the loop ends at the first throw because the outcome is then a Failure.
      def respond(outcome)
        @response_steps.each do |step|
          break unless outcome.is_a?(Outcome::Success)

          outcome = Ownership.close_on_throw(outcome) { rewrap(outcome, step) }
        end
        outcome
      end

      def rewrap(success, step)
        response = check_response(step.call(success.response))
        response.equal?(success.response) ? success : Outcome::Success.build(response: response)
      end

      # RECOV-5, RECOV-8: the recovery steps, on every outcome, each handed the outcome itself.
      def recover(outcome)
        @recovery_steps.each do |step|
          outcome = Ownership.close_on_throw(outcome) do
            check_outcome(step.call(outcome))
          end
        end
        outcome
      end

      # A response step's return that is not a Response is a caller step's mistake, and it takes
      # the throw path: raised inside the Ownership region, so the in-hand response is released.
      def check_response(value)
        return value if value.is_a?(Response)

        raise InvalidArgumentError,
              "a response step must return a Dexpace::Response, got #{value.class}"
      end

      # R6's exhaustiveness arm. The OutcomeError is constructed here, so `cause: nil` keeps a
      # caller's in-flight exception off it (verified fact 5), and Ownership re-raises it by name.
      def check_outcome(value)
        case value
        in Outcome::Success | Outcome::Failure then value
        else raise OutcomeError.new(value.class), cause: nil
        end
      end
    end
  end
end
