# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/transport/async_http"

# A Protocol::HTTP::Body::Readable over a Dexpace::Body, pulled through phase 3a's
# BufferedSource.over, so an outbound body is never materialised -- the design's verified fact 7
# measured exactly one #read per chunk plus one for end of stream over the reference library,
# and chunked framing on the wire for an unknown length. TRANSPORT-17's second guarantee: a
# single-use body refuses to rewind, so the library's own Request#retry! never re-reads it.
class DexpaceTransportAsyncHTTPRequestBodyTest < DexpaceTestCase
  RequestBody = Dexpace::Transport::AsyncHTTP.const_get(:RequestBody, false)

  def two_chunk_body
    Class.new do
      include Dexpace::Body

      def write_to(sink)
        sink.write("ab".b)
        sink.write("cd".b)
        4
      end
    end.new
  end

  test "is a Protocol::HTTP::Body::Readable, so the library pulls it and never materialises it" do
    assert_kind_of(::Protocol::HTTP::Body::Readable, RequestBody.new(Dexpace::Body.bytes("x".b)))
  end

  test "reads chunks on demand, BINARY, then nil at end of stream" do
    body = RequestBody.new(two_chunk_body)
    chunks = []
    while (chunk = body.read)
      chunks << chunk
    end

    assert_equal("abcd", chunks.join)
    assert(chunks.all? { |chunk| chunk.encoding == ::Encoding::BINARY })
    assert_nil(body.read)
  end

  test "#length reports the wrapped body's own content_length, or nil for the -1 sentinel" do
    assert_equal(3, RequestBody.new(Dexpace::Body.bytes("abc".b)).length)
    assert_nil(RequestBody.new(two_chunk_body).length)
  end

  test "#rewindable? mirrors the wrapped body's #replayable?, and #rewind resets the read" do
    replayable = RequestBody.new(Dexpace::Body.bytes("abc".b))

    assert_predicate(replayable, :rewindable?)
    assert_equal("abc", replayable.read)
    assert(replayable.rewind)
    assert_equal("abc", replayable.read)
  end

  test "a single-use (non-replayable) body refuses to rewind (TRANSPORT-17)" do
    single_use = RequestBody.new(two_chunk_body)
    single_use.read

    refute_predicate(single_use, :rewindable?)
    refute(single_use.rewind)
  end

  test "the library's own retry gate refuses a POST and a non-rewindable body alike" do
    request = ::Protocol::HTTP::Request.new("http", "h", "POST", "/", nil,
                                            ::Protocol::HTTP::Headers.new,
                                            RequestBody.new(Dexpace::Body.bytes("abc".b)),)
    get = ::Protocol::HTTP::Request.new("http", "h", "GET", "/", nil, ::Protocol::HTTP::Headers.new,
                                        RequestBody.new(two_chunk_body),)

    refute(request.retry!)
    refute(get.retry!)
  end

  test "#close releases the pull source and never closes the caller's Dexpace::Body" do
    closes = 0
    source = Class.new do
      include Dexpace::Body

      define_method(:write_to) { |sink| sink.write("x".b) }
      define_method(:close) { closes += 1 }
    end.new
    body = RequestBody.new(source)
    body.read

    assert_nil(body.close)
    assert_equal(0, closes)
  end
end
