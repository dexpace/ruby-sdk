# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../error/protocol_error"
require_relative "../http/response"
require_relative "../recovery"
require_relative "../registry"
require_relative "deserialization_error"
require_relative "decode_context"
require_relative "decoding_handler"

module Dexpace
  module Serde
    # SERDE-28's status-aware response handler: a Dexpace::_ResponseHandler supplied into phase
    # 3b's TypedResponse, dispatching on the status in three branches --
    #
    #   2xx                            -> the DecodingHandler built from the same serde and witness
    #   4xx / 5xx                      -> raise factory.call(Recovery.buffer_error_body(response))
    #   anything else (1xx, 3xx, 304)  -> close the response; raise DeserializationError, "<code>
    # ..."
    #
    # The 2xx branch DELEGATES rather than re-implementing, so SERDE-27's five clauses have exactly
    # one implementation and "decode the body only on a 2xx status" is a branch, not a second
    # decoder. The 4xx/5xx branch uses phase 4b's objects and adds none: Recovery.buffer_error_body
    # is the ONE buffering call site (RECOV-16, BODY-30, HTTP-52 -- it already returns the response
    # unchanged when the body is nil, so no nil check here), and its Body.buffer_bounded closes the
    # live body in its own `ensure`, so this branch adds NO close of its own -- a second one would
    # be a double close of an object 4b already released, which is why the suite counts raw closes.
    # `factory:` defaults to core's ProtocolError.for as one frozen lambda, the exact shape
    # Recovery::ErrorMappingStep uses, so a generated SDK substitutes its typed errors here with the
    # keyword it already knows from the recovery chain and SERDE-28's "the MAPPED HTTP-error
    # exception" is RECOV-15's object rather than a second one; `.for` and not `.for_or_nil`,
    # because the branch has already established `status.error?`. The error is raised `cause: nil`:
    # the factory CONSTRUCTED it, and a bare `raise` inside a caller's rescue would chain the
    # caller's in-flight exception onto it (`pipeline/7ce4431d`).
    #
    # The third branch is where SERDE-28 is easiest to get half-right: the message "leads with the
    # status code and preserves conditional/redirect context (ETag / Location)", so it copies the
    # RAW `ETag` and `Location` header values and parses neither -- running a malformed server ETag
    # through HTTP-48's validating helper inside an error path would turn a diagnostic into a second
    # failure. The chapter's conformance clause also names "a non-canonical 599", which is a 5xx
    # and therefore the SECOND branch; it is called out here because a reader skimming
    # "non-canonical" will file it under the third.
    #
    # A frozen Data in the phase-1 shape. Its members are the three build keywords, so `#with`
    # re-derives the whole thing through `.build`; the DecodingHandler for the 2xx branch is built
    # once in `#initialize` -- which is also where the serde and the witness are validated.
    class StatusAwareHandler < Data.define(:serde, :witness, :factory)
      include Model

      # Core's factory as a callable: one frozen object, the same proc type a caller's factory
      # has (ErrorMappingStep's shape). Private, because P7-2 fixes the public constants.
      DEFAULT_FACTORY = ->(response) { ProtocolError.for(response) }.freeze
      private_constant :DEFAULT_FACTORY

      private_class_method :new, :[]

      # The validating factory every construction path goes through.
      #
      # @param serde [Dexpace::_Codec] the codec, `#load(source, witness)` at least
      # @param witness [Object] the SUCCESS type's witness: a class answering .dexpace_load, or a
      #   combinator; the error payload never reaches it
      # @param factory [#call] `#call(buffered_response) -> Exception`, ProtocolError.for by default
      # @return [StatusAwareHandler] frozen
      # @raise [Dexpace::InvalidArgumentError] on a nil serde, a non-witness, or a nil or
      #   non-callable factory
      def self.build(serde:, witness:, factory: DEFAULT_FACTORY)
        new(serde: serde, witness: witness, factory: factory)
      end

      def initialize(serde:, witness:, factory:)
        Model.required!("factory", factory)
        unless Registry.callable?(factory, arity: 1)
          raise InvalidArgumentError, "factory must respond to #call(response)"
        end

        # Validates the serde and the witness (SERDE-8, at construction) and is the one decoder.
        @decoding = DecodingHandler.build(serde: serde, witness: witness)
        super(serde: @decoding.serde, witness: @decoding.witness, factory: factory)
      end

      # The _ResponseHandler protocol, dispatched on the status (SERDE-28).
      #
      # @param response [Dexpace::Response]
      # @return [Object] the witness's decode, for a 2xx
      # @raise [Exception] the factory's error, for a 4xx or 5xx, carrying the buffered response
      # @raise [Dexpace::Serde::DeserializationError] for a 1xx or a 3xx, leading with the code, or
      #   from the decoder on a 2xx with a missing, empty or malformed body
      # @raise [Dexpace::InvalidArgumentError] when `response` is not a Dexpace::Response, or the
      #   factory returned something that is not an Exception
      def call(response)
        unless response.is_a?(Response)
          raise InvalidArgumentError, "response must be a Dexpace::Response, got #{response.class}"
        end
        return @decoding.call(response) if response.success?
        return raise_mapped(response) if response.error?

        raise_unhandled(response)
      end

      private

      # 4xx/5xx: buffer (which closes the live response), map, raise. No second close.
      def raise_mapped(response)
        error = factory.call(Recovery.buffer_error_body(response))
        unless error.is_a?(::Exception)
          raise InvalidArgumentError,
                "factory must return an Exception for status #{response.status.code}, " \
                "got #{error.class}"
        end

        raise error, cause: nil
      end

      # 1xx or 3xx: close, then raise with the code first and the raw conditional/redirect headers.
      def raise_unhandled(response)
        message = unhandled_message(response)
        response.close
        raise DeserializationError, message
      end

      def unhandled_message(response)
        status = response.status
        headers = response.headers
        context = %w[etag location].filter_map do |name|
          values = headers[name]
          "#{name}: #{values.join(", ")}" unless values.nil? || values.empty?
        end
        target = DecodeContext.root(target: witness).target
        lead = "#{status.code} #{status.canonical_name}".rstrip
        ["#{lead}: not decoded into #{target}, only a 2xx body is (SERDE-28)", *context].join("; ")
      end
    end
  end
end
