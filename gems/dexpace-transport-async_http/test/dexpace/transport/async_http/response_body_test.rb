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
# yield, nothing read ahead. Three nested classes under Metrics/ClassLength: the pull and the
# close, the read surface with its failures, and #cancel_read -- TRANSPORT-7's body path, which
# wakes a parked reader rather than closing its connection under it.
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

    # The first chunk arrives tagged UTF-8, as a library that trusted a charset would hand it,
    # and the second BINARY: the retag is asserted on the one the native body did NOT already
    # tag, because a double handing over BINARY chunks alone cannot see `String#b` go missing
    # (review round 0's R0-3, a surviving mutant).
    test "#each yields one native #read per chunk, retagged BINARY, and stops at nil" do
      utf8 = +"a" # a source literal: UTF-8, and unfrozen as a native chunk is
      native = AsyncHTTPRecordingBody.new([utf8, "b".b])
      chunks = body(native).each.map { |chunk| chunk }

      assert_equal(::Encoding::UTF_8, utf8.encoding, "the fixture hands over a UTF-8 chunk")
      assert_equal(%w[a b], chunks)
      assert_equal([::Encoding::BINARY, ::Encoding::BINARY], chunks.map(&:encoding))
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

  # TRANSPORT-7's body path, on the watcher's side of the exchange. A native body whose close does
  # NOT wake a reader parked in its #read -- which is what the EPoll selector does with a
  # descriptor closed under a parked fiber: epoll drops it from the interest set and says nothing
  # -- so the only thing that can wake the reader is #cancel_read raising into it. The
  # regression this pins was green on io_uring (whose poll sees the close) and red on every
  # hosted CI runner, which has no liburing and so runs EPoll; a double that models the silent
  # drop makes the test independent of the host's selector.
  class CancelReadTest < DexpaceTestCase
    include ResponseBodyTestSupport

    BOUND = 5.0

    # Yields `first`, then parks the next #read on a scheduler-aware queue that only #unpark
    # feeds. Records whether a close ran while a read was still parked.
    class ParkingBody < Protocol::HTTP::Body::Readable
      attr_reader :close_count, :closed_while_parked, :parked

      def initialize(first)
        super()
        @chunks = [first]
        @gate = ::Thread::Queue.new
        @parked = ::Thread::Queue.new
        @in_read = false
        @close_count = 0
        @closed_while_parked = false
      end

      def read
        return @chunks.shift unless @chunks.empty?

        @in_read = true
        @parked.push(true)
        @gate.pop
      ensure
        @in_read = false
      end

      def close(error = nil)
        @close_count += 1
        @closed_while_parked ||= @in_read
        super
      end

      # The test's own release on every path: a reader a defect left parked is fed end of stream,
      # so its task finishes and the failure is reported instead of holding the reactor open.
      def unpark = @gate.push(nil)
    end

    test "#cancel_read with no reader parked closes the body, once" do
      native = ParkingBody.new("a".b)
      subject = body(native)

      subject.cancel_read
      subject.cancel_read

      assert_predicate(subject, :closed?)
      assert_equal(1, native.close_count)
    end

    test "TRANSPORT-7: #cancel_read wakes a reader parked in #each with CancelledError, and the " \
         "reader -- not the canceller -- closes the body once its read has unwound" do
      chunks = assert_woken(:each) { |subject, seen| subject.each { |chunk| seen << chunk } }

      assert_equal(["a"], chunks)
    end

    # Response#body_string and every BufferedSource read pull through `.over`'s Enumerator, so
    # the parked fiber is the enumerator's own and never the consumer's: the one #pull records.
    test "TRANSPORT-7: #cancel_read wakes a reader parked through #source's enumerator fiber" do
      assert_woken(:source) { |subject, chunks| chunks << subject.source.read }
    end

    private

    def assert_woken(path, &)
      native = ParkingBody.new("a".b)
      error, subject, chunks = wake_parked_reader(native, &)

      assert_kind_of(Dexpace::CancelledError, error, "the #{path} reader was not woken")
      assert_equal([:woken, ResponseBody::INTERRUPTED], [error.reason, error.cause&.message])
      assert_kind_of(::IOError, error.cause)
      assert_predicate(subject, :closed?)
      assert_equal(1, native.close_count)
      refute(native.closed_while_parked, "the body was closed under the parked read")
      chunks
    end

    # Parks a reader in a child task, cancels the token and calls #cancel_read from the parent,
    # and answers what the reader surfaced; bounded, and the gate fed on every path.
    def wake_parked_reader(native)
      source = Dexpace::Cancellation.source
      subject = body(native, cancellation: source.token)
      chunks = []
      error = Sync do |task|
        reader = task.async do
          yield subject, chunks
          nil
        rescue Dexpace::CancelledError => error
          error
        end
        native.parked.pop # the reader has taken "a" and is parked in the second native read
        source.cancel(:woken)
        subject.cancel_read
        task.with_timeout(BOUND) { reader.wait }
      ensure
        native.unpark
      end
      [error, subject, chunks]
    end
  end
end
