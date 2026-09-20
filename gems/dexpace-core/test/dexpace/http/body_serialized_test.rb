# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_codec"
require "dexpace"
require "stringio"

# SERDE-2, whose own conformance clause is: "build a body via create(value, serde) with no explicit
# media type; assert the Content-Type equals the serde's declared media type." A ninth factory
# beside phase 3b's eight; adding one WIDENS, which NFR-4's "disappears or narrows" lock permits. An
# extra suite beside 3b's body_test.rb, the file's mirror, because it is phase 7a's one addition.
class DexpaceBodySerializedTest < DexpaceTestCase
  test "SERDE-2: the body's media type is the serde's declared one" do
    body = Dexpace::Body.serialized(:payload, serde: FakeCodec.new)

    assert_equal(Dexpace::MediaType.parse("application/vnd.dexpace.fake"), body.media_type)
  end

  test "SERDE-2: there is no format-agnostic default to fall back to" do
    forgetful = Class.new(FakeCodec) { def media_type = nil }.new
    blank = Class.new(FakeCodec) { def media_type = "" }.new

    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Body.serialized(:payload, serde: forgetful)
    end

    assert_match(/media type/, error.message)
    refute_match(%r{application/octet-stream}, error.message)
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.serialized(:payload, serde: blank) }
  end

  test "a MediaType-returning codec passes through and a String is coerced" do
    stringy = FakeCodec.new
    typed = Class.new(FakeCodec) do
      def media_type = Dexpace::MediaType.parse("application/json")
    end.new

    assert_instance_of(Dexpace::MediaType, Dexpace::Body.serialized(:v, serde: stringy).media_type)
    assert_equal(Dexpace::MediaType.parse("application/json"),
                 Dexpace::Body.serialized(:v, serde: typed).media_type,)
    assert_same(typed.media_type.class, Dexpace::Body.serialized(:v, serde: typed).media_type.class)
  end

  test "a media type the header grammar cannot carry is refused at the parse, naming the value" do
    hostile = Class.new(FakeCodec) { def media_type = "application/json\r\nX: y" }.new

    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.serialized(:v, serde: hostile) }
  end

  test "the bytes are the serde's dump_bytes and the body is replayable with an exact length" do
    codec = FakeCodec.new
    body = Dexpace::Body.serialized(:payload, serde: codec)
    sink = StringIO.new(+"".b)

    assert_instance_of(Dexpace::BytesBody, body)
    assert_predicate(body, :replayable?)
    assert_equal(codec.dump_bytes(:payload).bytesize, body.content_length)
    body.write_to(sink)
    body.write_to(sink) # replayable means byte-for-byte identical, twice

    assert_equal(codec.dump_bytes(:payload) * 2, sink.string)
  end

  test "non-ASCII content reaches the body as the codec's BINARY bytes" do
    body = Dexpace::Body.serialized("héllo", serde: FakeCodec.new)
    sink = StringIO.new(+"".b)
    body.write_to(sink)

    assert_equal("héllo".b, sink.string)
    assert_equal(6, body.content_length, "a byte count, never a character count")
  end

  test "a missing serde fails with SEAM-29's message form, and a non-codec by name" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.serialized(:v, serde: nil) }

    assert_equal("serde is required", error.message)
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.serialized(:v, serde: Object.new) }
  end

  test "a serialization failure propagates as the seam's write-side error" do
    exploding = Class.new(FakeCodec) do
      def dump_bytes(_value) = raise Dexpace::Serde::SerializationError, "no"
    end.new

    assert_raises(Dexpace::Serde::SerializationError) do
      Dexpace::Body.serialized(:v, serde: exploding)
    end
  end
end
