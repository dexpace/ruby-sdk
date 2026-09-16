# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"
require_relative "../../../support/fake_chunked"
require_relative "../../../support/fake_sink"

# HTTP-38, HTTP-46, BODY-1, BODY-4, BODY-6, BODY-7, BODY-8, BODY-35, and design §10.2.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# bytes here, then Latch and Construction below.
class DexpaceChunkedBodyTest < DexpaceTestCase
  # One shared drain for every class below.
  module Chunks
    def drain(body)
      sink = Dexpace::IO::Buffer.new
      body.write_to(sink)
      sink.snapshot
    end
  end
  include Chunks

  test "writes exactly the chunks the wrapped object yields, in order" do
    assert_equal("héllo".b, drain(Dexpace::Body.chunked(FakeChunked.new("hé", "llo"))))
  end

  # FakeChunked yields FROZEN literals under its own file's frozen_string_literal pragma, which is
  # the ordinary Rack shape and the exact input on which force_encoding raises.
  test "retags a frozen non-BINARY chunk without raising FrozenError" do
    sink = Dexpace::IO::Buffer.new
    Dexpace::Body.chunked(FakeChunked.frozen_utf8).write_to(sink)

    assert_equal("héllo wörld".b, sink.snapshot)
    assert_equal(::Encoding::BINARY, sink.snapshot.encoding)
  end

  # The #each half of the same retag, and it needs a REAL body: FakeBody calls #b itself, so the
  # body_test.rb each-yields-BINARY test passes with Body#emit_exactly's retag removed. Here the
  # chunk reaching the block is whatever emit_exactly handed the sink.
  test "each yields BINARY chunks even when the wrapped object yields frozen UTF-8 ones" do
    encodings = []
    chunks = []

    Dexpace::Body.chunked(FakeChunked.frozen_utf8).each do |chunk|
      encodings << chunk.encoding
      chunks << chunk
    end

    assert_equal([::Encoding::BINARY], encodings.uniq)
    assert_equal("héllo wörld".b, chunks.join)
  end

  # An empty chunk between two non-empty ones means "no bytes this time", never "no bytes ever",
  # and no StringIO or IO.pipe can produce it.
  test "an empty chunk between two non-empty ones does not truncate the body" do
    assert_equal("abcd".b, drain(Dexpace::Body.chunked(FakeChunked.new("ab", "", "cd"))))
  end

  # A sink that keeps the objects it was handed AS GIVEN -- FakeSink and every Dexpace::IO sink
  # retag on the way in, so only a raw recorder can see what #emit_exactly actually handed over.
  class RawSink
    attr_reader :received

    def initialize
      @received = []
    end

    def write(string)
      @received << string
      string.bytesize
    end
  end

  # The retag is #emit_exactly's, not the sink's: a raw #write-shaped destination -- a socket, a
  # caller's own object -- receives BINARY whatever the wrapped object yielded.
  test "hands a raw sink BINARY chunks even when the wrapped object yields frozen UTF-8 ones" do
    sink = RawSink.new
    Dexpace::Body.chunked(FakeChunked.frozen_utf8).write_to(sink)

    assert_equal([::Encoding::BINARY], sink.received.map(&:encoding).uniq)
    assert_equal("héllo wörld".b, sink.received.join)
  end

  test "reports the bytes it wrote, and writes them through the sink's own return" do
    sink = FakeSink.new

    assert_equal(4, Dexpace::Body.chunked(FakeChunked.new("ab", "", "cd")).write_to(sink))
    assert_equal(["ab".b, "cd".b], sink.writes)
  end

  test "detects a short write from the sink and names transferred-of-total" do
    error = assert_raises(Dexpace::StreamError) do
      Dexpace::Body.chunked(FakeChunked.new("héllo")).write_to(FakeSink.new(2))
    end

    assert_includes(error.message, "2")
    assert_includes(error.message, "6")
  end

  # P3-19, and it is a decision rather than an omission: BODY-1 permits replayable only when the
  # bytes are provably identical, and a keyword would let a caller ASSERT what BODY-4's three paths
  # then believe.
  test "is unconditionally single-use and Body.chunked takes no replayable keyword" do
    body = Dexpace::Body.chunked(["a"])

    refute_predicate(body, :replayable?)
    refute_includes(Dexpace::Body.method(:chunked).parameters.map(&:last), :replayable)
    refute_includes(Dexpace::ChunkedBody.instance_method(:initialize).parameters.map(&:last),
                    :replayable,)
  end

  test "a caller with a genuinely repeatable source pays one materialisation instead" do
    body = Dexpace::Body.chunked(%w[hé llo])
    materialized = body.to_replayable

    assert_predicate(materialized, :replayable?)
    assert_equal("héllo".b, drain(materialized))
    assert_equal("héllo".b, drain(materialized))
  end

  # BODY-6, BODY-7 and BODY-8.
  class LatchTest < DexpaceTestCase
    include Chunks

    test "a second write raises rather than emitting zero bytes" do
      body = Dexpace::Body.chunked(["a"])
      drain(body)
      error = assert_raises(Dexpace::StreamError) { drain(body) }

      assert_includes(error.message, "BODY-6")
    end

    test "under concurrent writes exactly one passes and every loser sees the same failure" do
      body = Dexpace::Body.chunked(Array.new(64) { "x" })
      start = ::Thread::Queue.new
      outcomes = ::Thread::Queue.new
      threads = Array.new(8) do
        ::Thread.new do
          start.pop
          drain(body)
          outcomes << :passed
        rescue Dexpace::StreamError => error
          outcomes << error.class
        end
      end
      8.times { start << :go }
      threads.each(&:join)
      results = Array.new(8) { outcomes.pop }

      assert_equal(1, results.count(:passed))
      assert_equal(7, results.count(Dexpace::StreamError))
    end

    # BODY-8: it opened nothing, so it closes nothing. An #each-shaped object holding a resource
    # must expose #close and be closed by its owner.
    test "closes nothing, and does not even look for a close method" do
      closeable = Class.new(FakeChunked) do
        attr_reader :closed

        def close = @closed = true
      end.new("a")
      drain(Dexpace::Body.chunked(closeable))

      assert_nil(closeable.closed)
    end
  end

  # Construction and HTTP-46.
  class ConstructionTest < DexpaceTestCase
    include Chunks

    test "declares an unknown length by default and carries a declared one through" do
      assert_equal(-1, Dexpace::Body.chunked(["a"]).content_length)
      assert_equal(9, Dexpace::Body.chunked(["a"], content_length: 9).content_length)
    end

    test "rejects an object that does not respond to each" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.chunked(Object.new) }

      assert_includes(error.message, "#each")
    end

    test "rejects a content_length below the -1 sentinel" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.chunked(["a"], content_length: -2)
      end
    end

    test "carries its media type" do
      media = Dexpace::MediaType.parse("application/octet-stream")

      assert_equal(media, Dexpace::Body.chunked(["a"], media_type: media).media_type)
    end

    test "has no readable source, because it is a request body" do
      assert_raises(Dexpace::StreamError) { Dexpace::Body.chunked(["a"]).source }
    end

    test "compares by identity, because two each-shaped objects are two values" do
      chunks = ["a"]

      refute_equal(Dexpace::Body.chunked(chunks), Dexpace::Body.chunked(chunks))
    end
  end
end
