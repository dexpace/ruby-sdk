# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../recovery"

module Dexpace
  module Recovery
    # The pure transform contract that lets one object install into both pipeline layers without
    # a second implementation (design §5.1; R8). Design §5.1 promises the three shipped steps --
    # the idempotency key, the client identity and the error mapping -- are "written once against
    # the step protocol both layers share", and there is no such protocol: a pipeline step is
    # #call(request, cursor), a recovery request step is Request -> Request, a recovery response
    # step is Response -> Response. What is shared is a pure function of one value, and this is
    # its name.
    #
    # Five clauses. (1) #apply is the entire behaviour: a transform reads nothing but its argument
    # and its own frozen configuration, holds no per-call state (RECOV-14), performs no I/O, and
    # returns a value of the type it was handed -- and it may raise, which ErrorMappingStep does
    # by RECOV-15. (2) #phase is :request or :response, constant per class, read at composition
    # time and never at call time; it never names the recovery-step list, because a recovery
    # step is Outcome -> Outcome and is not a transform. (3) A recovery-chain step is a #call-able
    # of one argument, so (4) a transform is installed into a chain AS ITSELF: #call(value)
    # below forwards to #apply(value), the module's one default implementation, and no adapter
    # and no Method object exist on this side (P4-25). (5) The stage pipeline's generic wrapper
    # is phase 4c's, reads #phase once, and calls #apply rather than #call, so a future default
    # here cannot change what the pipeline does.
    #
    # Spec §8.3's two-layer prohibition is honoured by the shape: #call takes ONE argument and is
    # the recovery chain's own protocol -- the same #call a lambda, a Transport and phase 4's
    # pipeline all answer -- and nothing here names a stage or a cursor. Neither layer may add a
    # third #phase value; a transform over something that is neither a request nor a response is
    # a new deviation row and a change to this contract.
    #
    # A module rather than an unnamed duck type because NFR-11 wants a named type in the public
    # signature 4c writes and #phase needs documenting once rather than three times; the RBS
    # interface _Transform in sig/ is that name. The two declared methods raise
    # NotImplementedError -- a ScriptError, so an includer that forgot one is a programmer error
    # that escapes every StandardError rescue -- exactly as Closeable#release does.
    module Transform
      # @return [Symbol] :request or :response
      # @raise [NotImplementedError] until the includer defines it
      def phase
        raise ::NotImplementedError, "#{self.class}#phase must be implemented"
      end

      # @param value [Dexpace::Request, Dexpace::Response] per #phase
      # @return [Dexpace::Request, Dexpace::Response] the same type it was handed
      # @raise [NotImplementedError] until the includer defines it
      def apply(value)
        raise ::NotImplementedError, "#{self.class}#apply must be implemented"
      end

      # The recovery chain's one-argument step protocol, forwarded to #apply (R8 clause 4). Not
      # the pipeline's two-argument #call(request, cursor), which no object under
      # Dexpace::Recovery answers.
      #
      # @param value [Dexpace::Request, Dexpace::Response]
      # @return [Dexpace::Request, Dexpace::Response]
      def call(value)
        apply(value)
      end
    end
  end
end
