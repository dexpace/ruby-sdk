# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_codec"
require_relative "../../support/fake_response_body"
require_relative "../../support/recovery_fixtures"
require "dexpace"

# SERDE-27, whose conformance clause is a five-case matrix and gets five tests: "handle a valid body
# -> typed value plus one close; a bodyless response -> serde exception naming the target; malformed
# content -> serde exception with a non-null cause; a mid-stream I/O error -> propagates unwrapped;
# the response closes in every case."
#
# FakeCodec, never Dexpace::Serde::JSON -- SEAM-2, and no_concrete_codec_test.rb enforces it. The
# response is a REAL Dexpace::Response (TypedResponse type-checks it) over 3b's FakeResponseBody,
# whose #closes counts RAW close calls -- a Closeable-latched body could never show a second close.
# Split under Metrics/ClassLength: the matrix, then the construction and the TypedResponse wiring.
class DexpaceSerdeDecodingHandlerTest < DexpaceTestCase
  S = Dexpace::Serde

  # A named witness answering BOTH protocol methods: .dexpace_load for Dexpace::Serde.witness!,
  # which DecodingHandler.build runs, and .call for phase 2's FakeCodec#load, which predates the
  # protocol. A bare lambda answers only the second and fails at .build -- and widening witness! to
  # accept #call would break SERDE-5 and SERDE-8. FakeCodec hands #call the drained BINARY bytes, so
  # the witness retags before it folds.
  class UpcaseWitness
    def self.dexpace_load(parsed, _ctx) = parsed.dup.force_encoding(::Encoding::UTF_8).upcase
    def self.call(text) = dexpace_load(text, nil)
  end

  # The target whose NAME the bodyless error must carry.
  class PetWitness
    def self.dexpace_load(parsed, ctx) = ctx.object!(parsed)
    def self.call(text) = dexpace_load(text, S::DecodeContext.root(target: self))
  end

  # The responses and handlers the nested cases share.
  module Fixtures
    include RecoveryFixtures

    def body_of(text)
      FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes(text.b),
                           content_length: text.bytesize,)
    end

    def response_with(text, code: 200) = build_response(code, body: body_of(text))

    def handler(serde: FakeCodec.new, witness: UpcaseWitness)
      S::DecodingHandler.build(serde: serde, witness: witness)
    end
  end

  # SERDE-27's five-case conformance matrix, plus the two-subjects clause.
  class MatrixTest < DexpaceTestCase
    include Fixtures

    test "SERDE-27: a valid body decodes to the typed value and closes the response exactly once" do
      response = response_with("héllo")

      assert_equal("HÉLLO", handler.call(response))
      assert_equal(1, response.body.closes)
    end

    # "MUST surface a missing body (e.g. 204) as a serde exception NAMING THE TARGET TYPE".
    test "SERDE-27: a bodyless response raises naming the target, and still closes" do
      response = build_response(204, body: nil)

      error = assert_raises(Dexpace::Serde::DeserializationError) do
        handler(witness: PetWitness).call(response)
      end

      assert_match(/PetWitness/, error.message)
      assert_match(/no body/, error.message)
    end

    # A zero-length body is treated the same way, because a caller cannot distinguish them and the
    # codec's own end-of-input error names nothing useful. Detected with BufferedSource#eof?, a
    # non-consuming probe, never with #content_length (-1 for every unknown-length body) and never
    # by matching a parser message (which differs across json versions). Both halves of the message
    # are asserted: with the screen gone, FakeCodec hands PetWitness the drained "" and the
    # witness's OWN shape failure ("expected PetWitness (Hash) at /, got String") names the target
    # too, so /PetWitness/ alone would pass either way (review round 1, R1-1).
    test "SERDE-27: an empty body raises the same target-naming error, at any declared length" do
      empty = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("".b))
      response = build_response(200, body: empty)

      error = assert_raises(Dexpace::Serde::DeserializationError) do
        handler(witness: PetWitness).call(response)
      end

      assert_match(/PetWitness/, error.message)
      assert_match(/no body/, error.message)
      assert_equal(1, response.body.closes)
    end

    # The same clause for a witness that has no name to carry: DecodeContext.root gives an
    # anonymous class no target (P7-70), and the message says so in words rather than
    # interpolating nothing (review round 1, R1-4).
    test "SERDE-27: an anonymous witness is named as such, never as an empty name" do
      anonymous = Class.new { def self.dexpace_load(parsed, ctx) = ctx.object!(parsed) }

      error = assert_raises(Dexpace::Serde::DeserializationError) do
        handler(witness: anonymous).call(build_response(204, body: nil))
      end

      assert_match(/no body to decode into an anonymous witness:/, error.message)
      refute_match(/#<Class/, error.message)
    end

    test "SERDE-27: a codec failure surfaces as a serde exception with a NON-NIL cause" do
      exploding = Class.new(FakeCodec) do
        def load(_source, _witness)
          raise "the backing library said no"
        rescue ::RuntimeError
          raise Dexpace::Serde::DeserializationError, "decode failed"
        end
      end.new
      response = response_with("x")

      error = assert_raises(Dexpace::Serde::DeserializationError) do
        handler(serde: exploding).call(response)
      end

      refute_nil(error.cause)
      assert_equal("the backing library said no", error.cause.message)
      assert_equal(1, response.body.closes)
    end

    # SERDE-27's last clause and SERDE-12's, from the handler's side: a genuine mid-stream I/O error
    # propagates UNWRAPPED. Dexpace::StreamError is an ::IOError and no rescue in this path catches
    # it.
    test "SERDE-27: a mid-stream I/O error propagates unwrapped, and the response still closes" do
      failing = Class.new(FakeCodec) do
        def load(_source, _witness) = raise Dexpace::StreamError, "connection reset"
      end.new
      response = response_with("x")

      error = assert_raises(Dexpace::StreamError) { handler(serde: failing).call(response) }

      refute_kind_of(Dexpace::Serde::Error, error)
      assert_equal(1, response.body.closes)
    end

    test "SERDE-27: a StreamError from the source itself (the eof? probe) propagates unwrapped" do
      broken = Object.new
      def broken.eof? = raise Dexpace::StreamError, "connection reset before the first byte"
      response = build_response(200, body: FakeResponseBody.new(broken))

      assert_raises(Dexpace::StreamError) { handler.call(response) }
      assert_equal(1, response.body.closes)
    end

    # The clause that reads like a contradiction and is not: SERDE-3 binds the CODEC and its subject
    # is the caller's STREAM; SERDE-27 binds the HANDLER and its subject is the RESPONSE. Two rules,
    # two subjects. This test asserts both hold at once: the response closes once, the SOURCE the
    # codec was handed is the body's own handle and nobody closed it.
    test "the handler closes the response and hands the codec the body's own source, unclosed" do
      seen = []
      watching = Class.new(FakeCodec) do
        define_method(:load) do |source, witness|
          seen << source
          witness.call(source.read)
        end
      end.new
      response = response_with("x")

      handler(serde: watching).call(response)

      assert_same(response.body.source, seen.first, "the body's handle, not a copy")
      refute_predicate(seen.first, :closed?)
      assert_equal(1, response.body.closes)
    end

    # The handler reads response.body.SOURCE, and Dexpace::Body's module default for #source RAISES
    # Dexpace::StreamError naming the class (phase 3b, P3-23). Only ResponseBody,
    # ResponseLoggingBody and BufferBody override it -- BytesBody, which Body.bytes and Body.string
    # return, does not. So the obvious in-memory spelling is not readable by a typed handler, and
    # the failure looks exactly like SERDE-27's "genuine mid-stream I/O error" for a body that is
    # perfectly readable. This test makes the limit a documented contract rather than a discovery;
    # Body.buffer is the readable spelling.
    test "a BytesBody-backed response raises StreamError; Body.buffer is the readable spelling" do
      bytes = build_response(200, body: Dexpace::Body.bytes("héllo".b))

      error = assert_raises(Dexpace::StreamError) { handler.call(bytes) }

      assert_match(/BytesBody/, error.message)

      buffer = Dexpace::IO::Buffer.new
      buffer.write("héllo".b)
      buffered = build_response(200, body: Dexpace::Body.buffer(buffer))

      assert_equal("HÉLLO", handler.call(buffered))
    end
  end

  # Construction (SERDE-8 at build time) and the TypedResponse wiring 3b built for this.
  class ConstructionTest < DexpaceTestCase
    include Fixtures

    test "the handler is a _ResponseHandler, so TypedResponse takes it and runs it exactly once" do
      response = response_with("héllo")
      typed = Dexpace::TypedResponse.new(response: response, handler: handler)

      3.times { assert_equal("HÉLLO", typed.value) }

      assert_equal(1, response.body.closes)
    end

    test "a memoized failure is re-raised as the SAME object, so its cause survives" do
      typed = Dexpace::TypedResponse.new(response: response_with(""),
                                         handler: handler(witness: PetWitness),)
      first = assert_raises(Dexpace::Serde::DeserializationError) { typed.value }
      second = assert_raises(Dexpace::Serde::DeserializationError) { typed.value }

      assert_same(first, second)
    end

    test "a non-witness fails at handler construction, not at first body access" do
      assert_raises(Dexpace::InvalidArgumentError) do
        S::DecodingHandler.build(serde: FakeCodec.new, witness: 5)
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        S::DecodingHandler.build(serde: FakeCodec.new, witness: :upcase.to_proc)
      end
    end

    test "a missing serde fails with SEAM-29's message form, and a non-codec by name" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        S::DecodingHandler.build(serde: nil, witness: PetWitness)
      end

      assert_equal("serde is required", error.message)
      assert_raises(Dexpace::InvalidArgumentError) do
        S::DecodingHandler.build(serde: Object.new, witness: PetWitness)
      end
    end

    test "follows the construction pattern: private constructors, frozen, #with through .build" do
      built = handler

      refute_respond_to(S::DecodingHandler, :new)
      refute_respond_to(S::DecodingHandler, :[])
      assert_predicate(built, :frozen?)
      assert_equal(PetWitness, built.with(witness: PetWitness).witness)
      assert_raises(Dexpace::InvalidArgumentError) { built.with(witness: 5) }
    end

    test "anything but a Dexpace::Response is refused before any close is attempted" do
      assert_raises(Dexpace::InvalidArgumentError) { handler.call(Object.new) }
      assert_raises(Dexpace::InvalidArgumentError) { handler.call(nil) }
    end
  end
end
