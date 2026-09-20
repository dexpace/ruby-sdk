# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/close_counting_source"
require "dexpace/serde/json"
require "stringio"

# SERDE-3's decode half, SERDE-5, SERDE-11, SERDE-12, SERDE-13, SERDE-21, SERDE-22, SERDE-23, and
# P7-6. An extra suite beside codec_test.rb, the file's mirror, because #load is where R1 and P7-6
# both live. Split under Metrics/ClassLength: the stream contract, then the shapes.
class DexpaceSerdeJSONCodecLoadTest < DexpaceTestCase
  C = Dexpace::Serde::JSON::Codec
  S = Dexpace::Serde

  # The DTO the SERDE-5 conformance clause decodes into.
  class Pet
    attr_reader :name

    def self.dexpace_load(parsed, ctx)
      h = ctx.object!(parsed)
      new(ctx.string!(h["name"], key: "name"))
    end

    def initialize(name) = @name = name
  end

  # The BufferedSource every case reads from.
  module Fixtures
    def source(text) = Dexpace::IO::BufferedSource.of_bytes(text.b)
  end

  # SERDE-3, SERDE-5, SERDE-9, SERDE-12 and R1: the stream contract and the failure model.
  class StreamTest < DexpaceTestCase
    include Fixtures

    # SERDE-5's conformance clause: decode a JSON object into a concrete DTO via the type-witness
    # path and assert the result is the REAL DTO type with typed field access.
    test "SERDE-5: decode through an explicit witness yields the real type" do
      pet = C.default.load(source("{\"name\":\"Ré\"}"), Pet)

      assert_instance_of(Pet, pet)
      assert_equal("Ré", pet.name)
      assert_equal(::Encoding::UTF_8, pet.name.encoding)
    end

    # SERDE-3, and message-bodies/a7afc6ee names this rule as 7a's: "a codec closes nothing".
    # SERDE-3's own tail -- "even when the codec's own auto-close feature is enabled" -- holds under
    # every option this adapter accepts, which is what the loop covers.
    test "SERDE-3: load reads to EOF and closes the caller's source exactly zero times" do
      [C.default, C.build(max_nesting: 4), C.build(allow_nan: true), C.build(script_safe: true),
       C.build(allow_duplicate_key: true),].each do |codec|
        tracked = CloseCountingSource.new("{\"name\":\"x\"}")

        codec.load(tracked, Pet)

        assert_equal(0, tracked.close_count)
        assert_predicate(tracked, :at_eof?)
      end
    end

    test "SERDE-3: a raw IO answering #read is read to EOF and left open too" do
      io = StringIO.new("{\"name\":\"x\"}".b)

      assert_equal("x", C.default.load(io, Pet).name)
      refute_predicate(io, :closed?)
      assert_predicate(io, :eof?)
    end

    test "SERDE-5: there is no witness-less overload to fall into" do
      assert_raises(::ArgumentError) { C.default.load(source("{}")) }
      assert_raises(Dexpace::InvalidArgumentError) { C.default.load(source("{}"), 5) }
      assert_raises(Dexpace::InvalidArgumentError) { C.default.load(source("{}"), ->(p, _c) { p }) }
    end

    # SERDE-9 from the decode side, and SERDE-11 (SHOULD, satisfied by the language: every one of
    # these is a StandardError descendant and appears in no declared signature).
    test "SERDE-13/SERDE-9: malformed input is the DESERIALIZATION subtype, with a cause" do
      error = assert_raises(Dexpace::Serde::DeserializationError) do
        C.default.load(source("{not json"), Pet)
      end

      assert_kind_of(::JSON::JSONError, error.cause)
      assert_kind_of(::StandardError, error)
      refute_kind_of(::JSON::JSONError, error)
    end

    test "SERDE-9: a nesting-depth failure is the deserialization subtype chaining the library's" do
      error = assert_raises(Dexpace::Serde::DeserializationError) do
        C.build(max_nesting: 2).load(source("[[[1]]]"), Pet)
      end

      assert_kind_of(::JSON::NestingError, error.cause)
    end

    # SERDE-12, satisfied STRUCTURALLY by verified fact 4: JSON::JSONError's ancestry is
    # [JSON::ParserError, JSON::JSONError, StandardError, Exception] and IOError is nowhere in it,
    # so `rescue ::JSON::JSONError` CANNOT catch a Dexpace::StreamError. The codec writes no
    # `rescue StandardError` and this test is what proves the narrow rescue is load-bearing.
    test "SERDE-12: a genuine stream I/O error propagates UNWRAPPED" do
      failing = Object.new
      def failing.read_utf8(*) = raise Dexpace::StreamError, "connection reset"

      error = assert_raises(Dexpace::StreamError) { C.default.load(failing, Pet) }

      refute_kind_of(Dexpace::Serde::Error, error)
      assert_kind_of(::IOError, error)
    end

    test "SERDE-12: a raw IO's own failure propagates unwrapped as well" do
      broken = Object.new
      def broken.read(*) = raise ::IOError, "closed stream"

      assert_raises(::IOError) { C.default.load(broken, Pet) }
    end

    # R1 clause 3, and the observable behaviour a caller will meet: a body above IO-9's ceiling
    # raises a StreamError (an ::IOError), which propagates past the codec's rescue for the same
    # reason. No test allocates 64 MiB: the ceiling is 3a's and tested there; this stubs the
    # source's refusal.
    test "R1/P7-1: an over-ceiling body surfaces as a StreamError, not as a serde error" do
      over_ceiling = Object.new
      def over_ceiling.read_utf8(*)
        raise Dexpace::StreamError, "materialisation would exceed MAX_MATERIALIZED_BYTES"
      end

      assert_raises(Dexpace::StreamError) { C.default.load(over_ceiling, Pet) }
    end

    test "the source must be a stream: neither #read_utf8 nor #read means it is refused" do
      assert_raises(Dexpace::InvalidArgumentError) { C.default.load("{}", Pet) }
      assert_raises(Dexpace::InvalidArgumentError) { C.default.load(nil, Pet) }
    end
  end

  # SERDE-13, SERDE-20–SERDE-23 and P7-6: what the witness sees, and the UTF-8 guard.
  class ShapeTest < DexpaceTestCase
    include Fixtures

    # SERDE-13 across "every decode overload" -- which is one method here, so one test. Its
    # conformance clause decodes "the literal null into a non-null DTO" and asserts the message
    # names THE TARGET TYPE, so /Pet/ is the assertion and /Hash/ is the shape that rides beside it.
    # #load builds DecodeContext.root(target: witness) for exactly this.
    test "SERDE-13: a wire null into a non-null target names the target type" do
      error = assert_raises(Dexpace::Serde::DeserializationError) { C.default.load(source("null"), Pet) }

      assert_equal("expected DexpaceSerdeJSONCodecLoadTest::Pet (Hash) at /, got NilClass",
                   error.message,)
    end

    # And the repair is WITNESS-AWARE rather than a nil check in #load: SERDE-20 requires
    # "deserialize a top-level null -> Null", so a combinator that legitimately accepts nil must
    # still succeed. Neither of these calls ctx.object! on nil, so nothing raises and neither needs
    # an exemption -- which is the whole reason #load does not screen for nil itself.
    test "SERDE-20: a top-level null still decodes through Nullable and Tristate" do
      assert_nil(C.default.load(source("null"), S::Nullable.of(Pet)))
      assert_predicate(C.default.load(source("null"), S::Tristate.of(String)), :null?)
    end

    # SERDE-21/SERDE-22, through the REAL codec rather than through DecodeContext alone: JSON.parse
    # performs no coercion (verified), so the strictness burden is entirely the witness's.
    test "SERDE-21: the codec never coerces, so the witness sees the wire shape" do
      error = assert_raises(Dexpace::Serde::DeserializationError) do
        C.default.load(source("{\"name\":5}"), Pet)
      end

      assert_equal("expected String at /name, got Integer", error.message)
    end

    test "SERDE-22: an integer widens into a float target through the real decode path" do
      assert_in_delta(1.0, C.default.load(source("1"), S::List.of(Float).element))
      assert_equal([1.0, 2.5], C.default.load(source("[1, 2.5]"), S::List.of(Float)))
    end

    test "SERDE-23: an unknown field is ignored" do
      assert_equal("x", C.default.load(source("{\"name\":\"x\",\"new_field\":1}"), Pet).name)
    end

    # P7-6. Verified fact 7: #read_utf8 retags without validating (3a's stated contract) and
    # ::JSON.parse accepts invalid UTF-8 and returns a UTF-8-tagged String whose #valid_encoding? is
    # false. Without this guard a caller receives a String that claims an encoding it does not have.
    test "P7-6: invalid UTF-8 in the payload is a deserialization failure, not a corrupt String" do
      invalid = source("{\"name\":\"\xff\"}".b)

      error = assert_raises(Dexpace::Serde::DeserializationError) { C.default.load(invalid, Pet) }

      assert_match(/UTF-8/, error.message)
      assert_nil(error.cause, "the port's own guard, not the library's")
    end

    test "P7-6: well-formed non-ASCII survives the same path untouched, and a BOM is refused" do
      assert_equal("héllo wörld", C.default.load(source("{\"name\":\"héllo wörld\"}"), Pet).name)
      assert_raises(Dexpace::Serde::DeserializationError) do
        C.default.load(source("\xEF\xBB\xBF{\"name\":\"x\"}".b), Pet)
      end
    end

    test "an empty source is a deserialization failure chaining the parser's own end-of-input" do
      error = assert_raises(Dexpace::Serde::DeserializationError) { C.default.load(source(""), Pet) }

      assert_kind_of(::JSON::ParserError, error.cause)
    end

    test "the witness's own DeserializationError passes through unwrapped and unchained" do
      strict = Class.new do
        def self.dexpace_load(_parsed, ctx) = ctx.error!(expected: "Never", actual: 1)
      end

      error = assert_raises(Dexpace::Serde::DeserializationError) { C.default.load(source("1"), strict) }

      assert_equal("expected Never at /, got Integer", error.message)
      assert_nil(error.cause)
    end
  end
end
