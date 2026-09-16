# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"
require_relative "../../../support/fake_sink"

# HTTP-36, HTTP-38, HTTP-46, BODY-1, BODY-13, BODY-35.
class DexpaceBytesBodyTest < DexpaceTestCase
  test "is replayable, because HTTP-38 classifies a byte array and a string alike" do
    assert_predicate(Dexpace::BytesBody.new("a"), :replayable?)
  end

  test "reports the exact byte count, not the character count" do
    assert_equal(6, Dexpace::BytesBody.new("héllo").content_length)
  end

  test "writes the same bytes on every write" do
    body = Dexpace::BytesBody.new("héllo")
    first = Dexpace::IO::Buffer.new
    second = Dexpace::IO::Buffer.new

    body.write_to(first)
    body.write_to(second)

    assert_equal("héllo".b, first.snapshot)
    assert_equal(first.snapshot, second.snapshot)
  end

  test "keeps an independent copy, so a later mutation of the caller's String cannot reach it" do
    text = +"héllo"
    body = Dexpace::BytesBody.new(text)
    text << "!"

    assert_equal(6, body.content_length)
  end

  test "stores its bytes as BINARY whatever encoding the caller handed in" do
    sink = Dexpace::IO::Buffer.new
    Dexpace::BytesBody.new("héllo").write_to(sink)

    assert_equal(::Encoding::BINARY, sink.snapshot.encoding)
  end

  test "writes nothing and returns 0 for an empty body" do
    sink = FakeSink.new

    assert_equal(0, Dexpace::BytesBody.new("").write_to(sink))
    assert_empty(sink.writes)
  end

  test "detects a short write from the sink and names transferred-of-total" do
    error = assert_raises(Dexpace::StreamError) do
      Dexpace::BytesBody.new("héllo").write_to(FakeSink.new(2))
    end

    assert_includes(error.message, "2")
    assert_includes(error.message, "6")
  end

  test "rejects a non-String rather than coercing it" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::BytesBody.new(42) }

    assert_includes(error.message, "Integer")
  end

  # HTTP-46, and all three together: phase 1's Request#hash folds the body in, so a body with a
  # value #== and an identity #hash breaks the hash/eql? contract for every Request used as a key.
  test "compares by value over its bytes and its media type" do
    media = Dexpace::MediaType.parse("text/plain")

    assert_equal(Dexpace::BytesBody.new("a"), Dexpace::BytesBody.new("a"))
    refute_equal(Dexpace::BytesBody.new("a"), Dexpace::BytesBody.new("b"))
    refute_equal(Dexpace::BytesBody.new("a"), Dexpace::BytesBody.new("a", media_type: media))
  end

  test "hashes equal bodies equally, so a Request carrying one works as a Hash key" do
    assert_equal(Dexpace::BytesBody.new("a").hash, Dexpace::BytesBody.new("a").hash)
    assert(Dexpace::BytesBody.new("a").eql?(Dexpace::BytesBody.new("a")))
  end

  test "is frozen, so nothing can mutate it after construction" do
    assert_predicate(Dexpace::BytesBody.new("a"), :frozen?)
  end

  # P3-23: a request-body variant has no read handle, and says so by name.
  test "has no readable source, and the failure names the class" do
    error = assert_raises(Dexpace::StreamError) { Dexpace::BytesBody.new("a").source }

    assert_includes(error.message, "Dexpace::BytesBody")
  end
end
