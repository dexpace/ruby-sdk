# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/async_http_recording_body"
require "dexpace/transport/async_http"

# The design's verified fact 6: lazy, pull-shaped, BINARY, unfrozen; close does not drain.
# Protocol::HTTP::Body::Readable's own #each closes in its own ensure, which is why this class
# drives the native #read directly and closes through its OWN latch -- one close path, never two
# racing ones. P3-3: a native failure mid-stream is a Dexpace::StreamError, the token asked first.
# ASYNC-21's property, asserted on 7b's precedent although the ID is N/A: one native read per
# yield, nothing read ahead. Two nested classes under Metrics/ClassLength: the pull and the close,
# and the read surface with its failures.
module DexpaceTransportAsyncHTTPResponseBodyTest
  # The one constructor both classes share.
  module ResponseBodyTestSupport
    ResponseBody = Dexpace::Transport::AsyncHTTP.const_get(:ResponseBody, false)

    def body(native, cancellation: Dexpace::Cancellation.none, on_release: nil, length: -1)
      ResponseBody.new(native: native, media_type: nil, content_length: length,
                       cancellation: cancellation, on_release: on_release,)
    end
  end

  # One native read per yield, and one close through the body's own latch whichever path took it.
  class PullAndCloseTest < DexpaceTestCase
    include ResponseBodyTestSupport

    test "#each yields one native #read per chunk, retagged BINARY, and stops at nil" do
      native = AsyncHTTPRecordingBody.new(["a".b, "b".b])
      chunks = body(native).each.map { |chunk| chunk }

      assert_equal(%w[a b], chunks)
      assert(chunks.all? { |chunk| chunk.encoding == ::Encoding::BINARY })
      assert_equal(3, native.reads, "two chunks plus one read for end of stream")
    end

    test "ASYNC-21's property: exactly one native read per yield, nothing read ahead of demand" do
      native = AsyncHTTPRecordingBody.new(["a".b, "b".b, "c".b])
      remaining = body(native).each.map { |_chunk| native.remaining }

      assert_equal([2, 1, 0], remaining)
    end

    test "#each closes the native body exactly once, on natural exhaustion, and an explicit " \
         "#close afterwards is a no-op" do
      native = AsyncHTTPRecordingBody.new(["a".b])
      subject = body(native)

      subject.each { |_chunk| nil }
      subject.close

      assert_equal(1, native.close_count)
      assert_predicate(subject, :closed?)
    end

    test "#close before consumption releases the native body exactly once, idempotently " \
         "(TRANSPORT-16)" do
      native = AsyncHTTPRecordingBody.new(["a".b, "b".b])
      subject = body(native)

      subject.close
      subject.close

      assert_equal(1, native.close_count)
      assert_equal(0, native.reads, "close does not drain")
    end

    test "a read after #close raises ClosedError rather than re-opening anything" do
      subject = body(AsyncHTTPRecordingBody.new(["a".b]))
      subject.close

      assert_raises(Dexpace::ClosedError) { subject.each { |_chunk| nil } }
    end

    test "the release hook runs once, after the native close, whichever path closed it" do
      calls = []
      native = AsyncHTTPRecordingBody.new(["a".b])
      subject = body(native, on_release: -> { calls << native.close_count })

      subject.each { |_chunk| nil }
      subject.close

      assert_equal([1], calls)
    end
  end

  # #source, #content_length and #write_to, then the failures: mid-stream, under a cancelled
  # token, and a cancel between chunks.
  class ReadSurfaceTest < DexpaceTestCase
    include ResponseBodyTestSupport

    test "#source is built with BufferedSource.over and is the same handle every call (BODY-14)" do
      subject = body(AsyncHTTPRecordingBody.new(["ab".b, "cd".b]))

      assert_instance_of(Dexpace::IO::BufferedSource, subject.source)
      assert_same(subject.source, subject.source)
      source = subject.source
      refute_predicate(source, :owns_upstream?) if source.respond_to?(:owns_upstream?)
    end

    # A fresh view per call would strand the bytes the first view had buffered.
    test "reading through #source twice continues where the first read stopped" do
      subject = body(AsyncHTTPRecordingBody.new(["ab".b, "cd".b]))

      assert_equal("a", subject.source.read(1))
      assert_equal("bcd", subject.source.read)
    end

    test "#content_length is the -1 sentinel for an unknown length and exact otherwise (BODY-35)" do
      assert_equal(-1, body(AsyncHTTPRecordingBody.new([], length: nil)).content_length)
      exact = body(AsyncHTTPRecordingBody.new(["hi".b], length: 2), length: 2)

      assert_equal(2, exact.content_length)
    end

    test "#write_to copies every chunk once and is single-use (BODY-6)" do
      subject = body(AsyncHTTPRecordingBody.new(["ab".b, "cd".b]))
      buffer = Dexpace::IO::Buffer.new

      assert_equal(4, subject.write_to(buffer))
      assert_equal("abcd", buffer.read)
      assert_raises(Dexpace::StreamError) { subject.write_to(Dexpace::IO::Buffer.new) }
    end

    # A body shorter than its Content-Length raises a bare EOFError from the library (measured):
    # the consumer sees phase 3a's contract, with the original as the cause, and the body is closed.
    test "P3-3: a native failure mid-stream surfaces as StreamError with the cause, and closes" do
      native = AsyncHTTPRecordingBody.new(["ab".b, "cd".b], raise_after: 1)
      subject = body(native)
      chunks = []

      error = assert_raises(Dexpace::StreamError) { subject.each { |chunk| chunks << chunk } }

      assert_equal(["ab"], chunks)
      assert_kind_of(::EOFError, error.cause)
      assert_equal(1, native.close_count)
      refute_respond_to(error, :retryable?)
    end

    test "TRANSPORT-3 on the body path: a native failure under a cancelled token is the " \
         "cancellation, not a stream failure" do
      source = Dexpace::Cancellation.source
      native = AsyncHTTPRecordingBody.new(["ab".b, "cd".b], raise_after: 1,
                                                            error: ::IOError.new("closed stream"),)
      subject = body(native, cancellation: source.token)
      source.cancel(:reader_gave_up)

      error = assert_raises(Dexpace::CancelledError) { subject.each { |_chunk| nil } }

      assert_equal(:reader_gave_up, error.reason)
      assert_equal(1, native.close_count)
    end

    # Check-after-resume on the body path: a chunk that arrived after the token was cancelled is
    # not yielded.
    test "a token cancelled between chunks is honoured before the next chunk is yielded" do
      source = Dexpace::Cancellation.source
      native = AsyncHTTPRecordingBody.new(["ab".b, "cd".b])
      subject = body(native, cancellation: source.token)
      chunks = []

      assert_raises(Dexpace::CancelledError) do
        subject.each do |chunk|
          chunks << chunk
          source.cancel(:between_chunks)
        end
      end

      assert_equal(["ab"], chunks)
      assert_equal(1, native.close_count)
    end

    test "is a Dexpace::Body that answers #source and #close, as anything in Response#body must" do
      subject = body(AsyncHTTPRecordingBody.new(["x".b]))

      assert_kind_of(Dexpace::Body, subject)
      assert_respond_to(subject, :source)
      assert_respond_to(subject, :close)
      refute_predicate(subject, :replayable?)
    end
  end
end
