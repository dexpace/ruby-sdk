# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/close_counting_sink"
require "dexpace/serde/json"

# SEAM-20's four allocation profiles, SERDE-4's buffer contract, SERDE-9/SERDE-10's failure model,
# SERDE-25's factory, SERDE-26's private engine and SERDE-29's sharing. Every reference to Ruby's
# JSON is ::JSON -- phase 2's Dexpace/QualifiedCoreConstant, and this is the first code it bites.
# Split under Metrics/ClassLength: the encode profiles, the failure model, the construction.
class DexpaceSerdeJSONCodecTest < DexpaceTestCase
  C = Dexpace::Serde::JSON::Codec

  # Codec#load runs Dexpace::Serde.witness! on its second argument, so a bare lambda is NOT a
  # witness. A named class answering .dexpace_load is the smallest thing that is one.
  class Identity
    def self.dexpace_load(parsed, _ctx) = parsed
  end

  # The BufferedSource every decode case reads from.
  module Fixtures
    def source(text) = Dexpace::IO::BufferedSource.of_bytes(text.b)
  end

  # SEAM-20's four profiles, SERDE-3's encode half and SERDE-4's buffer contract.
  class EncodeProfilesTest < DexpaceTestCase
    include Fixtures

    test "SERDE-1: the seam's six methods are all present, so .conforms? accepts it" do
      assert(Dexpace::Serde.conforms?(C.default))
      assert_empty(Dexpace::Serde.missing_methods(C.default))
    end

    test "SEAM-19/SERDE-2: it declares its own media type as a MediaType" do
      assert_equal(Dexpace::MediaType.parse("application/json"), C.default.media_type)
      assert_same(C.default.media_type, C.default.media_type, "one frozen constant, never a parse")
    end

    # §10.13: a String tagged Encoding::BINARY *is* Ruby's byte array, so these two differ exactly
    # in the encoding tag -- and both ship because the tag is load-bearing at §3.1's boundary.
    test "SEAM-20: dump_string and dump_bytes differ exactly in the encoding tag" do
      codec = C.default

      assert_equal(::Encoding::UTF_8, codec.dump_string({ "a" => "é" }).encoding)
      assert_equal(::Encoding::BINARY, codec.dump_bytes({ "a" => "é" }).encoding)
      assert_equal(codec.dump_string({ "a" => "é" }).b, codec.dump_bytes({ "a" => "é" }))
      assert_equal("{\"a\":\"é\"}", codec.dump_string({ "a" => "é" }))
    end

    test "dump_string answers a fresh String each call, never a shared one" do
      codec = C.default

      refute_same(codec.dump_string([1]), codec.dump_string([1]))
      refute_predicate(codec.dump_string([1]), :frozen?)
    end

    test "SERDE-3: dump_to writes the bytes, answers the count, and never closes the sink" do
      sink = CloseCountingSink.new
      written = C.default.dump_to({ "a" => "é" }, sink)

      assert_equal(sink.string.bytesize, written)
      assert_equal(C.default.dump_bytes({ "a" => "é" }), sink.string)
      assert_equal(0, sink.close_count)
    end

    # SERDE-4's conformance clause, all four parts.
    test "SERDE-4: encode into an oversized buffer at an offset" do
      payload = C.default.dump_bytes({ "a" => "é" })
      buffer = ("\0" * (payload.bytesize + 8)).b
      written = C.default.dump_into({ "a" => "é" }, buffer, offset: 4)

      assert_equal(payload.bytesize, written)
      assert_equal(payload, buffer.byteslice(4, payload.bytesize))
      assert_equal("\0\0\0\0".b, buffer.byteslice(0, 4), "bytes before the offset are untouched")
      assert_equal("\0\0\0\0".b, buffer.byteslice(4 + payload.bytesize, 4), "and after it")
      assert_equal(payload.bytesize + 8, buffer.bytesize)
    end

    # Verified fact 12 is why the explicit fit check exists: String#[]= with an in-range offset and
    # an over-long payload silently GROWS the string rather than raising, which is the one behaviour
    # SERDE-4 exists to forbid. The overflow is raised `cause: nil`, and that is observable only
    # when an exception is in flight -- so the call is made from inside a rescue.
    test "SERDE-4: a one-byte-short buffer raises a range error, NOT the serde type, unchained" do
      payload = C.default.dump_bytes({ "a" => 1 })
      buffer = ("\0" * (payload.bytesize - 1)).b

      error = assert_raises(::IndexError) do
        raise "in flight"
      rescue ::RuntimeError
        C.default.dump_into({ "a" => 1 }, buffer, offset: 0)
      end

      refute_kind_of(Dexpace::Serde::Error, error)
      assert_nil(error.cause)
      assert_equal(payload.bytesize - 1, buffer.bytesize, "the buffer must not have grown")
      assert_equal("\0" * (payload.bytesize - 1), buffer, "and must be untouched")
    end

    test "SERDE-4: an out-of-range offset raises IndexError and leaves the buffer untouched" do
      buffer = ("\0" * 4).b

      assert_raises(::IndexError) { C.default.dump_into(1, buffer, offset: 9) }
      assert_raises(::IndexError) { C.default.dump_into(1, buffer, offset: -1) }
      assert_raises(::IndexError) { C.default.dump_into(1, buffer, offset: 4) }
      assert_equal("\0\0\0\0".b, buffer)
    end

    test "SERDE-4: an exact fit at offset 0 and at the last possible offset both succeed" do
      payload = C.default.dump_bytes(1)
      exact = ("\0" * payload.bytesize).b

      assert_equal(payload.bytesize, C.default.dump_into(1, exact, offset: 0))
      assert_equal(payload, exact)

      tail = ("\0" * (payload.bytesize + 3)).b

      assert_equal(payload.bytesize, C.default.dump_into(1, tail, offset: 3))
      assert_equal(payload, tail.byteslice(3, payload.bytesize))
    end

    # P7-5. Ruby's IO::Buffer is excluded by measurement, not by taste: it warns through
    # Warning.warn at every level and phase 0's shared test case overrides Warning.warn TO RAISE,
    # so a test constructing one fails the build -- and a requirement whose conformance clause
    # cannot be tested is not satisfied. Also, its set_string raises ArgumentError where
    # String#[]= raises IndexError.
    test "P7-5: a frozen or non-BINARY buffer is refused as an argument error, not a range error" do
      assert_raises(Dexpace::InvalidArgumentError) { C.default.dump_into(1, "    ".b.freeze, offset: 0) }
      assert_raises(Dexpace::InvalidArgumentError) { C.default.dump_into(1, +"    ", offset: 0) }
      assert_raises(Dexpace::InvalidArgumentError) { C.default.dump_into(1, [], offset: 0) }
      assert_raises(Dexpace::InvalidArgumentError) { C.default.dump_into(1, ("\0" * 4).b, offset: 1.0) }
    end

    test "the suite constructs no Ruby IO::Buffer (P7-5), asserted over its own source" do
      own = File.expand_path(__FILE__)
      # Ruby's IO::Buffer, bare or ::-rooted -- never Dexpace::IO::Buffer, core's own FIFO.
      ruby_io_buffer = /(?<!Dexpace::)\bIO::Buffer\.(new|for|map)/
      offenders = Dir.glob(File.expand_path("../../../**/*.rb", __dir__))
        .reject { |path| File.expand_path(path) == own }
        .select { |path| File.read(path).match?(ruby_io_buffer) }

      assert_empty(offenders, "a Ruby IO::Buffer constructed in the suite")
    end
  end

  # SERDE-9 and SERDE-10: the SDK's types escape, never the library's, and the cause is chained.
  class FailureModelTest < DexpaceTestCase
    include Fixtures

    # Verified fact 3 is why this is a real test rather than a formality:
    # ::JSON.generate(Object.new) RETURNS "\"#<Object:0x…>\"" instead of raising. Two layers stop it
    # -- core's Native walk rejects a non-native value first, and strict: true makes the generator
    # itself raise.
    test "SERDE-9/SERDE-10: an unserializable value raises the SERIALIZATION subtype, not json's" do
      error = assert_raises(Dexpace::Serde::SerializationError) { C.default.dump_string(Object.new) }

      refute_kind_of(::JSON::JSONError, error)
      assert_match(/Object/, error.message)
      assert_raises(Dexpace::Serde::SerializationError) { C.default.dump_string([Object.new]) }
      assert_raises(Dexpace::Serde::SerializationError) { C.default.dump_bytes(:sym) }
    end

    test "SERDE-10: the write-path subtype is distinct from the read-path one under one root" do
      write = assert_raises(Dexpace::Serde::SerializationError) { C.default.dump_string(Object.new) }
      read = assert_raises(Dexpace::Serde::DeserializationError) { C.default.load(source("{"), Identity) }

      assert_kind_of(Dexpace::Serde::Error, write)
      assert_kind_of(Dexpace::Serde::Error, read)
      refute_kind_of(Dexpace::Serde::DeserializationError, write)
      refute_kind_of(Dexpace::Serde::SerializationError, read)
    end

    test "SERDE-9: a library failure is caught and chained rather than escaping the SPI" do
      error = assert_raises(Dexpace::Serde::SerializationError) { C.default.dump_string(::Float::NAN) }

      assert_kind_of(::JSON::JSONError, error.cause)
      assert_match(/NaN/, error.message)
    end

    # `strict: true` is belt and braces: Native.of refuses every non-native value before the Coder
    # sees it, so the option is observable only past the walk. This drives the private engine
    # directly, past Native, and asserts the generator is strict on its own account.
    test "the private engine is strict on its own account, past the walk" do
      coder = C.default.instance_variable_get(:@coder)

      assert_raises(::JSON::GeneratorError) { coder.dump(Object.new) }
      assert_raises(::JSON::GeneratorError) { coder.dump(::Time.at(0)) }
    end

    test "the generator never round-trips a bare Object as its inspect string" do
      refute_match(/#<Object/, C.default.dump_string({ "a" => 1 }))
      assert_raises(Dexpace::Serde::SerializationError) { C.default.dump_string({ "a" => Object.new }) }
    end

    test "a BINARY String holding invalid UTF-8 is a serialization failure, not silent bytes" do
      error = assert_raises(Dexpace::Serde::SerializationError) { C.default.dump_string("\xff".b) }

      assert_kind_of(::JSON::JSONError, error.cause)
    end
  end

  # SERDE-25's factory, SERDE-26's private engine, SERDE-29's sharing, and the option allowlist.
  class ConstructionTest < DexpaceTestCase
    include Fixtures

    # SERDE-25's conformance clause: "invoke the factory twice and assert distinct instances".
    test "SERDE-25: .default returns a fresh, independent instance on every call" do
      refute_same(C.default, C.default)
      refute_same(C.default, Dexpace::Serde::JSON.default)
      refute_same(Dexpace::Serde::JSON.default, Dexpace::Serde::JSON.default)
    end

    # SERDE-26 (P7-4). The antecedent is false by construction -- .build takes OPTIONS, never a
    # ::JSON::Coder -- and each instance owns a private engine built from its own frozen options,
    # so no engine is shared and no reconfiguration of one reaches another. Two codecs, one with
    # max_nesting: 4, read the same five-deep document differently.
    test "SERDE-26: two codecs share no engine and neither exposes one" do
      a = C.build(max_nesting: 4)
      b = C.default

      refute_respond_to(a, :coder)
      refute_respond_to(a, :options)
      assert_predicate(a, :frozen?)
      assert_predicate(b, :frozen?)
      assert_raises(Dexpace::Serde::DeserializationError) { a.load(source("[[[[[1]]]]]"), Identity) }
      assert_equal([[[[[1]]]]], b.load(source("[[[[[1]]]]]"), Identity))
      refute_same(a.instance_variable_get(:@coder), b.instance_variable_get(:@coder))
    end

    test "SERDE-26: max_nesting bounds the encode side too" do
      deep = [[[[[1]]]]]

      assert_raises(Dexpace::Serde::SerializationError) { C.build(max_nesting: 4).dump_string(deep) }
      assert_equal("[[[[[1]]]]]", C.default.dump_string(deep))
    end

    # json 2.19.9 SWALLOWED an unknown Coder option and 3.0 refuses it with a keyword error, so a
    # forwarded typo would configure a codec differently from what the caller wrote on one version
    # and raise a library error on the other. The allowlist makes it one InvalidArgumentError on
    # both (the plan's resolved question 4).
    test "an unknown option is refused rather than forwarded silently, on every json version" do
      error = assert_raises(Dexpace::InvalidArgumentError) { C.build(max_nestng: 4) }

      assert_match(/max_nestng/, error.message)
      assert_match(/max_nesting/, error.message, "the accepted set is named")
      assert_raises(Dexpace::InvalidArgumentError) { C.build(strict: false) }
      assert_raises(Dexpace::InvalidArgumentError) { C.build("max_nesting" => 4) }
      assert_raises(Dexpace::InvalidArgumentError) { C.build(4) }
    end

    test "the accepted options are the five, and nil means the default" do
      codec = C.build(max_nesting: nil, allow_nan: nil, allow_duplicate_key: nil, script_safe: nil,
                      encoders: nil,)

      assert_equal("[[[[[1]]]]]", codec.dump_string([[[[[1]]]]]))
      assert_equal(C.default.dump_string({ "t" => ::Time.at(0).utc }),
                   codec.dump_string({ "t" => ::Time.at(0).utc }),)
    end

    test "allow_nan: true lets NaN through both ways; the default refuses it" do
      lax = C.build(allow_nan: true)

      assert_equal("NaN", lax.dump_string(::Float::NAN))
      assert_predicate(lax.load(source("NaN"), Identity), :nan?)
      assert_raises(Dexpace::Serde::DeserializationError) { C.default.load(source("NaN"), Identity) }
    end

    test "script_safe: true escapes the forward slash; the default does not" do
      assert_equal("\"<\\/\"", C.build(script_safe: true).dump_string("</"))
      assert_equal("\"</\"", C.default.dump_string("</"))
    end

    # A duplicate key is accepted-last-wins on json 2.9, a WARNING on 2.19.9 (which the suite's
    # fatal-warnings base turns into an error) and a ParserError on 3.0: passing the option
    # explicitly makes it one DeserializationError across the whole range.
    test "a duplicate key is one deserialization failure by default, opt-in accepted last-wins" do
      assert_raises(Dexpace::Serde::DeserializationError) do
        C.default.load(source("{\"a\":1,\"a\":2}"), Identity)
      end
      lax = C.build(allow_duplicate_key: true)

      assert_equal({ "a" => 2 }, lax.load(source("{\"a\":1,\"a\":2}"), Identity))
    end

    test "encoders: replaces the default table and is validated" do
      custom = C.build(encoders: { ::Time => :to_i.to_proc })

      assert_equal("[0]", custom.dump_string([::Time.at(0)]))
      assert_raises(Dexpace::Serde::SerializationError) { custom.dump_string(::Date.new(2026, 9, 10)) }
      assert_raises(Dexpace::InvalidArgumentError) { C.build(encoders: { "Time" => ->(t) { t } }) }
      assert_raises(Dexpace::InvalidArgumentError) { C.build(encoders: [::Time]) }
    end

    test "the codec is frozen and its constructor is private" do
      assert_predicate(C.default, :frozen?)
      refute_respond_to(C, :new)
    end

    # SERDE-29's conformance clause: "exercise one serde from many concurrent workers encoding and
    # decoding distinct values and assert no corruption." Every thread is joined (map(&:value)).
    test "SERDE-29: one frozen codec is safe from many concurrent workers" do
      codec = C.default
      workers = Array.new(8) do |i|
        ::Thread.new do
          Array.new(200) do
            text = codec.dump_string({ "k" => i, "v" => "é#{i}" })
            [text, codec.load(source(text), Identity)]
          end.uniq
        end
      end
      results = workers.map(&:value)

      assert_equal(8, results.flatten(1).uniq.size)
      results.each_with_index do |(pair), i|
        assert_equal(["{\"k\":#{i},\"v\":\"é#{i}\"}", { "k" => i, "v" => "é#{i}" }], pair)
      end
    end

    test "SERDE-29: there is no per-type cache to audit -- the witness is supplied per call" do
      codec = C.default

      assert_empty(codec.instance_variables.grep(/cache|memo/i))
    end
  end
end
