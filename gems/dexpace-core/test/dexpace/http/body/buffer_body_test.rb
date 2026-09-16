# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"

# BODY-3, BODY-30, HTTP-37, HTTP-46, HTTP-52.
class DexpaceBufferBodyTest < DexpaceTestCase
  def buffer_of(*strings)
    buffer = Dexpace::IO::Buffer.new
    strings.each { |string| buffer.write(string.b) }
    buffer
  end

  def read_all(source)
    out = +"".b
    source.each { |chunk| out << chunk }
    out
  end

  test "is replayable and reports the buffer's byte count" do
    body = Dexpace::BufferBody.new(buffer_of("héllo"))

    assert_predicate(body, :replayable?)
    assert_equal(6, body.content_length)
  end

  # BODY-30's "readable independently and repeatably" is what makes this the materialize-once and
  # the error-copy product at once: the write goes through a fresh non-consuming peek view.
  test "never consumes its buffer, so every write produces the same bytes" do
    buffer = buffer_of("héllo")
    body = Dexpace::BufferBody.new(buffer)
    three = Array.new(3) do
      sink = Dexpace::IO::Buffer.new
      body.write_to(sink)
      sink.snapshot
    end

    assert_equal(["héllo".b] * 3, three)
    assert_equal(6, buffer.bytesize)
  end

  test "closes each peek view it takes, so a repeatedly written body does not grow the registry" do
    buffer = buffer_of("héllo")
    body = Dexpace::BufferBody.new(buffer)
    20.times { body.write_to(Dexpace::IO::Buffer.new) }

    assert_equal(0, buffer.instance_variable_get(:@dexpace_views).length)
  end

  test "closes its view even when the sink raises partway" do
    buffer = buffer_of("héllo")
    body = Dexpace::BufferBody.new(buffer)
    exploding = Class.new { def write(_string) = raise(Dexpace::StreamError, "boom") }.new

    assert_raises(Dexpace::StreamError) { body.write_to(exploding) }
    assert_equal(0, buffer.instance_variable_get(:@dexpace_views).length)
  end

  test "keeps reading after the buffer is closed, which is IO-42's in-memory exemption" do
    buffer = buffer_of("héllo")
    body = Dexpace::BufferBody.new(buffer)
    buffer.close
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)

    assert_equal("héllo".b, sink.snapshot)
  end

  # P3-23: #source is a FRESH non-consuming view per call, which is BODY-30's "decode it, then
  # snapshot it" -- and the difference from BODY-14's same-handle rule, which governs the
  # single-use response body and not a replayable in-memory copy.
  test "source hands out a fresh non-consuming view per call, so reads repeat independently" do
    body = Dexpace::BufferBody.new(buffer_of("héllo"))
    first = body.source
    second = body.source

    refute_same(first, second)
    assert_equal("héllo".b, read_all(first))
    assert_equal("héllo".b, read_all(second))
    assert_equal(6, body.content_length)
  end

  # BODY-30 requires #body_string's ensure-close to leave the copy readable, so #close is the
  # module's documented no-op and never touches the buffer.
  test "close is a no-op that leaves the copy readable, because it owns no transport resource" do
    body = Dexpace::BufferBody.new(buffer_of("héllo"))

    assert_nil(body.close)
    assert_equal("héllo".b, read_all(body.source))
  end

  test "rejects anything that is not a Dexpace::IO::Buffer" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::BufferBody.new("bytes") }

    assert_includes(error.message, "String")
  end

  test "compares by value over its snapshot and its media type" do
    assert_equal(Dexpace::BufferBody.new(buffer_of("a")), Dexpace::BufferBody.new(buffer_of("a")))
    refute_equal(Dexpace::BufferBody.new(buffer_of("a")), Dexpace::BufferBody.new(buffer_of("b")))
  end

  test "hashes over the length and media type, which equal bodies always share" do
    assert_equal(Dexpace::BufferBody.new(buffer_of("a")).hash,
                 Dexpace::BufferBody.new(buffer_of("a")).hash,)
  end
end
