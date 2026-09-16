# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "transform"
require_relative "../recovery"
require_relative "../error/invalid_argument_error"
require_relative "../error/protocol_error"
require_relative "../http/response"
require_relative "../registry"

module Dexpace
  module Recovery
    # RECOV-15: the status-to-typed-exception response transform. A transport returns a response
    # for every completed exchange, 4xx and 5xx included, so an error status is a response until
    # this step maps it: only 400..599 are errors (Status#error?, phase 1's, and no second
    # predicate), and a 1xx, 2xx or 3xx is returned BY IDENTITY with its body not read, consumed
    # or closed -- PIPE-37's parenthesised clause, which is what stops the outermost step from
    # draining a 2xx body on the way past when phase 4c installs it there.
    #
    # On an error status, three things in a fixed order: Recovery.buffer_error_body first, so the
    # connection is released and the body stays readable (RECOV-16, and RECOV-13's ownership
    # discharge, since the buffering closed the original); then the factory on the BUFFERED
    # response; then the raise. RECOV-7 converts the raise into a Failure. The raise is
    # `raise error, cause: nil`, never a bare `raise`: the factory CONSTRUCTED the error, so its
    # #cause is nil and a bare `raise` would fill it in from the caller's in-flight $! -- and
    # RECOV-10's `cause: nil` unwrap suppresses an assignment without clearing one already made,
    # so the pollution would survive to the call site and into every later classification that
    # walks Dexpace.each_cause. A 4xx raised from inside a caller's rescue is the ordinary case in
    # a generated client (verified on 3.2.11, 3.4.10 and 4.0.6).
    #
    # `factory:` defaults to core's own -- §5.1's "delegates to", XCUT-8's definite article -- as
    # one frozen lambda over ProtocolError.for rather than a Method object allocated per build
    # (the plan's open question 2). A generated SDK substitutes its typed errors by passing its
    # own `#call(response) -> Exception`, and the contract XCUT-8 fixes for core's factory holds
    # for the caller's: the step calls it only for an error status, so a factory that returns
    # anything but an Exception has broken its half and is refused as a caller mistake.
    #
    # A :response transform (R8): a ResponseChain response step as itself, and the pipeline's
    # outermost pre-redirect step through phase 4c's generic wrapper. It holds no per-call state.
    class ErrorMappingStep
      include Transform

      # Core's factory as a callable: one frozen object, the same proc type a caller's factory
      # has. Private, because P4-24 fixes the public constants this phase adds.
      DEFAULT_FACTORY = ->(response) { ProtocolError.for(response) }.freeze
      private_constant :DEFAULT_FACTORY

      # @return [#call] the factory, `#call(buffered_response) -> Exception`
      attr_reader :factory

      private_class_method :new

      # @param factory [#call] `#call(response) -> Exception`; core's ProtocolError.for by default
      # @return [Dexpace::Recovery::ErrorMappingStep]
      # @raise [Dexpace::InvalidArgumentError] when the factory is nil or not callable
      def self.build(factory: DEFAULT_FACTORY)
        Model.required!("factory", factory)
        unless Registry.callable?(factory, arity: 1)
          raise InvalidArgumentError, "factory must respond to #call(response)"
        end

        new(factory: factory)
      end

      def initialize(factory:)
        @factory = factory
      end

      # @return [Symbol] :response
      def phase = :response

      # @param response [Dexpace::Response]
      # @return [Dexpace::Response] the same object, for a status outside 400..599
      # @raise [Exception] the factory's error, for a status in 400..599, with its body buffered
      # @raise [Dexpace::InvalidArgumentError] when `response` is not a Dexpace::Response, or the
      #   factory returned something that is not an Exception
      def apply(response)
        unless response.is_a?(Response)
          raise InvalidArgumentError, "response must be a Dexpace::Response"
        end
        return response unless response.status.error?

        error = @factory.call(Recovery.buffer_error_body(response))
        unless error.is_a?(::Exception)
          raise InvalidArgumentError, "factory must return an Exception, got #{error.class}"
        end

        raise error, cause: nil
      end
    end
  end
end
