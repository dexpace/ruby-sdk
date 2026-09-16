# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../recovery"
require_relative "request_chain"
require_relative "response_chain"
require_relative "../error/invalid_argument_error"
require_relative "../error/outcome_error"
require_relative "../http/response"
require_relative "../outcome"
require_relative "../outcome/success"
require_relative "../outcome/failure"
require_relative "../registry"

module Dexpace
  module Recovery
    # RECOV-2's unified orchestrator: one send is the request chain, then the transport, then the
    # response chain, and no throwable from the first two bypasses the third. Everything before
    # the response chain runs inside one rescue region, so a before-request throw -- the defining
    # invariant's own example -- is converted into a Failure and threaded through the recovery
    # steps exactly as a transport failure is, and the transport is never called after a request
    # step has thrown.
    #
    # It is itself a Dexpace::Transport by phase 2's duck type, `#call(request, options,
    # cancellation)`, which costs nothing and is what lets a recovery-aware stack nest. It is not
    # a pipeline runtime and knows nothing about one; spec §8.3 keeps the two layers apart and
    # phase 4c's pipeline stands in wherever a transport is expected on its own account.
    #
    # The conversion boundary is StandardError, with two named exceptions (R6, P4-19). The fatal
    # family outside it -- ScriptError, SignalException, NoMemoryError, SystemStackError -- is
    # surfaced unchanged with no trail (RETRY-25), which is the same split every Ruby program's
    # bare `rescue` already codes against. And Dexpace::OutcomeError, a StandardError, is
    # re-raised by name: it means a fold was handed something that is not an Outcome, which is a
    # defect and not an outcome, and NoMatchingPatternError being inside StandardError is why the
    # conforming-looking route would demote it to a Failure a recovery step may swallow.
    #
    # The invariant has ONE blind spot, documented rather than discovered: LoadError and
    # NotImplementedError are ScriptErrors, so a caller-supplied step that lazily `require`s
    # something absent, or an adapter author's `raise NotImplementedError`, escapes the recovery
    # chain entirely and no recovery hook observes it. Core requires nothing lazily, so no core
    # step can do this; a step author who wants a lazy dependency observed by the chain loads it
    # at construction rather than at #call, or rescues its own LoadError and raises a
    # StandardError.
    #
    # RECOV-10's unwrap: on Success the response, on Failure `raise error, cause: nil` -- the
    # same object, never wrapped or substituted, and with an assignment suppressed that a bare
    # `raise` would make: `$!` is non-nil inside a method called from a caller's `rescue`, and a
    # bare `raise error` on an error whose #cause is nil would hand it the caller's unrelated
    # in-flight exception as a parent (verified on 3.2.11, 3.4.10 and 4.0.6). Any typed-exception
    # surfacing is a recovery step's job, by constructing the error and returning a Failure.
    #
    # RECOV-11 has nothing to do here, structurally (P4-17): the requirement's own portability
    # note says a port preserves whatever its cancellation primitive is, and phase 2's is a
    # latch -- Source#cancel is idempotent and #cancelled? is computed from the sources -- so
    # converting a CancelledError into a Failure cannot swallow the signal, and the token the
    # caller passed still answers #cancelled? afterwards. A ::Interrupt is outside StandardError
    # and passes through unconverted, which preserves it maximally.
    class Orchestrator
      # @return [#call] the transport, `#call(request, options, cancellation) -> Response`
      attr_reader :transport

      # @return [Dexpace::Recovery::RequestChain]
      attr_reader :request_chain

      # @return [Dexpace::Recovery::ResponseChain]
      attr_reader :response_chain

      private_class_method :new

      # @param transport [#call] any Dexpace::Transport by the duck type
      # @param request_chain [Dexpace::Recovery::RequestChain]
      # @param response_chain [Dexpace::Recovery::ResponseChain]
      # @return [Dexpace::Recovery::Orchestrator]
      # @raise [Dexpace::InvalidArgumentError] when any of the three is nil or the wrong shape
      def self.build(transport:, request_chain:, response_chain:)
        Model.required!("transport", transport)
        unless Registry.callable?(transport, arity: 3)
          raise InvalidArgumentError,
                "transport must respond to #call(request, options, cancellation)"
        end
        Model.required!("request_chain", request_chain)
        Model.required!("response_chain", response_chain)

        new(transport: transport, request_chain: request_chain, response_chain: response_chain)
      end

      def initialize(transport:, request_chain:, response_chain:)
        @transport = transport
        @request_chain = request_chain
        @response_chain = response_chain
      end

      # One send, as a transport. The region rescues StandardError and nothing wider: the fatal
      # family propagates through it untouched, and OutcomeError is re-raised by name.
      #
      # @param request [Dexpace::Request]
      # @param options [Dexpace::RequestOptions]
      # @param cancellation [Dexpace::Cancellation, nil]
      # @return [Dexpace::Response] the terminal Success's response
      # @raise [Exception] the terminal Failure's error, unchanged
      # @raise [Dexpace::OutcomeError] when a fold was handed something that is not an Outcome
      def call(request, options, cancellation)
        outcome = begin
          sent = @request_chain.apply(request)
          response = check_response(@transport.call(sent, options, cancellation))
          Outcome::Success.build(response: response)
        rescue OutcomeError
          raise
        rescue ::StandardError => error
          Outcome::Failure.build(error: error)
        end

        unwrap(@response_chain.apply(outcome))
      end

      private

      # A transport that returned something other than a Response has broken SEAM-11, and the
      # caller learns it as a Failure rather than as a NoMethodError from inside the chain.
      def check_response(value)
        return value if value.is_a?(Response)

        raise InvalidArgumentError,
              "the transport must return a Dexpace::Response, got #{value.class}"
      end

      # RECOV-10, and R6's second exhaustiveness arm: the chain is reached through an #apply duck
      # type, so its return is unproven here.
      def unwrap(outcome)
        case outcome
        in Outcome::Success then outcome.response
        in Outcome::Failure then raise outcome.error, cause: nil
        else raise OutcomeError.new(outcome.class), cause: nil
        end
      end
    end
  end
end
