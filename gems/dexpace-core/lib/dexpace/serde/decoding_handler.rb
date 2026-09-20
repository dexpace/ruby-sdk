# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../http/response"
require_relative "../http/body"
require_relative "deserialization_error"
require_relative "decode_context"
require_relative "witness"

module Dexpace
  module Serde
    # SERDE-27's response-decoding handler: a Dexpace::_ResponseHandler -- `#call(response) ->
    # value` -- supplied INTO phase 3b's Dexpace::TypedResponse and never replacing it (charter
    # boundary 7; 3b's `@state` memo and flip-only mutex are its, and this class holds no lock,
    # because a handler runs OUTSIDE that lock by construction). The five clauses, one at a time:
    #
    # - "stream the response body directly through the deserializer" -- the handler hands `#load`
    #   the body's own `#source`, a Dexpace::IO::BufferedSource, and copies nothing; `#body_string`
    #   is never called. Which bodies that is true of, stated because `#source`'s default raises:
    #   Dexpace::ResponseBody (the transport's), Dexpace::ResponseLoggingBody (phase 5b's) and
    #   Dexpace::BufferBody (`Body.buffer`, and what Recovery.buffer_error_body produces) answer it;
    #   a BytesBody -- `Body.bytes`, `Body.string` -- does NOT, and a typed handler over one raises
    #   Dexpace::StreamError naming the class, indistinguishable from a genuine I/O failure. For an
    #   in-memory response, `Body.buffer` is the readable spelling; the handler adds no
    #   `respond_to?` fallback because HTTP-41 names `#source` as THE read handle.
    # - "(without first materializing the whole body)" -- P7-1: NOT satisfied by the JSON adapter,
    #   which drains the source to EOF under Dexpace::IO.max_materialized_bytes; a body above that
    #   ceiling raises Dexpace::StreamError, an ::IOError, unwrapped. The handler's own behaviour is
    #   the strongest half available, and an adapter with a pull parser satisfies the clause with no
    #   change here because `#load` already takes the source.
    # - "MUST consume and close the response on every path" -- one unguarded `ensure`, because
    #   `#close` is on Dexpace::Body's contract with a no-op default (P3-23) and Response#close is
    #   `body&.close`. This does not conflict with SERDE-3: SERDE-3 binds the CODEC and its subject
    #   is the caller's STREAM (`#load` closes nothing); this is the HANDLER and its subject is the
    #   RESPONSE, which it owns for the duration of the call. Two rules, two subjects. A close that
    #   raises propagates over the primary rather than attaching to it (HTTP-43, BODY-15) -- a loud
    #   close, never Dexpace.close_quietly.
    # - "MUST surface a missing body (e.g. 204) as a serde exception naming the target type" -- a
    #   nil body AND an empty one, screened BEFORE `#load` with BufferedSource#eof?, a non-consuming
    #   probe, so the message can name the target only the handler knows; `#content_length` is -1
    #   for every unknown-length body and a parser's end-of-input message differs across versions,
    #   so neither is the test.
    # - "MUST surface a codec/parse failure as a serde exception chaining the original while letting
    #   a genuine mid-stream I/O error propagate unwrapped" -- both the codec's, not the handler's:
    #   the adapter re-raises inside its rescue (Ruby sets #cause) and rescues its library's error
    #   family alone, which a Dexpace::StreamError is structurally outside. The handler rescues
    #   nothing and re-wraps nothing.
    #
    # A frozen Data in the phase-1 shape: `.new` and `.[]` private, `.build(serde:, witness:)` the
    # validating factory, `Dexpace::Serde.witness!` at construction so a bad witness fails at
    # handler construction rather than at first body access -- which matters because TypedResponse
    # is lazy and a construction-time failure is the only one a caller sees before the wire.
    class DecodingHandler < Data.define(:serde, :witness)
      include Model

      private_class_method :new, :[]

      # The validating factory every construction path goes through.
      #
      # @param serde [Dexpace::_Codec] the codec, `#load(source, witness)` at least
      # @param witness [Object] the target: a class answering .dexpace_load, or a combinator
      # @return [DecodingHandler] frozen
      # @raise [Dexpace::InvalidArgumentError] on a nil serde ("serde is required"), one that does
      #   not answer #load, or a witness that is not one (SERDE-8)
      def self.build(serde:, witness:)
        new(serde: serde, witness: witness)
      end

      def initialize(serde:, witness:)
        Model.required!("serde", serde)
        unless serde.respond_to?(:load)
          raise InvalidArgumentError, "serde must answer #load(source, witness), got #{serde.class}"
        end

        super(serde: serde, witness: Dexpace::Serde.witness!(witness))
      end

      # The _ResponseHandler protocol: decodes the response's body through the codec into the
      # witness's type, closing the response on every path (SERDE-27).
      #
      # @param response [Dexpace::Response]
      # @return [Object] the witness's decode
      # @raise [Dexpace::Serde::DeserializationError] on a missing or empty body (naming the
      #   target), or from the codec on malformed or mis-shaped content (chaining the library's
      #   error)
      # @raise [Dexpace::StreamError] unwrapped, on a genuine I/O failure or a body over the ceiling
      # @raise [Dexpace::InvalidArgumentError] when `response` is not a Dexpace::Response
      def call(response)
        unless response.is_a?(Response)
          raise InvalidArgumentError, "response must be a Dexpace::Response, got #{response.class}"
        end

        begin
          decode(response)
        ensure
          # SERDE-27: every path. The HANDLER's subject is the response; the codec's (SERDE-3) is
          # the stream, and it closes nothing.
          response.close
        end
      end

      private

      def decode(response)
        body = response.body
        raise missing_body if body.nil?

        # BufferBody#source is a fresh view per call, so the one handle is obtained once and both
        # probed and decoded.
        source = body.source
        raise missing_body if source.eof?

        serde.load(source, witness)
      end

      # SERDE-27's "naming the target type": the name DecodeContext.root derives for the witness.
      def missing_body
        DeserializationError.new(
          "no body to decode into #{target_name}: the response carried none (SERDE-27)",
        )
      end

      # The witness's name as DecodeContext.root derives it, with a literal for the one witness
      # that has none: an anonymous class gets no target (P7-70, so `#error!` keeps its plain form
      # and no `#<Class:0x…>` reaches a message), and interpolating that nil here would read
      # "decode into : the response" (review round 1, R1-4).
      def target_name
        DecodeContext.root(target: witness).target || "an anonymous witness"
      end
    end
  end
end
