# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"
require_relative "../../../support/fake_response_body"
require_relative "../../../support/fake_source"
require "stringio"

# BODY-22, BODY-23, BODY-24, BODY-25, BODY-26, BODY-27, BODY-28, BODY-29, BODY-34, IO-42.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: BODY-22's
# drain-once and the two regimes here, then Tail (BODY-24 over a live delegate, BODY-25), Failure
# (BODY-25, BODY-26), Close (BODY-27, BODY-28, IO-42), Length (BODY-29), Serialization (BODY-22),
# DelegateHandle (BODY-23, BODY-24 and BODY-27 over a fresh-view delegate) and Construction below.
class DexpaceResponseLoggingBodyTest < DexpaceTestCase
  # One shared factory set for every class below.
  module Wrappers
    def response_body(content = "héllo", **rest)
      Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(content), **rest)
    end

    def wrapper(delegate = response_body, preview_bytes: 64)
      Dexpace::ResponseLoggingBody.new(delegate, preview_bytes: preview_bytes)
    end

    def read_all(source)
      out = +"".b
      source.each { |chunk| out << chunk }
      out
    end

    def failing(content = "ab", error = Dexpace::StreamError.new("boom"))
      FakeResponseBody.new(FakeSource.new(content, error))
    end
  end
  include Wrappers

  # A delegate that counts how many times its source was drained, which is the only way to assert
  # "at most once" rather than "the answer looks right".
  class CountingDelegate
    attr_reader :drains, :media_type, :content_length

    def initialize(content, media_type: nil, content_length: -1)
      @content = content.b
      @media_type = media_type
      @content_length = content_length
      @drains = 0
      @source = nil
    end

    def source
      @drains += 1 if @source.nil?
      @source ||= Dexpace::IO::BufferedSource.of_bytes(@content)
    end

    def close = nil
  end

  # A source that suspends its fiber in the middle of the drain, which is what puts fiber A inside
  # the drain while fiber B runs.
  class SuspendingSource
    def initialize(content)
      @remaining = content.b
      @suspended = false
    end

    def read_into(dest, count:)
      return -1 if @remaining.empty?

      unless @suspended
        @suspended = true
        ::Fiber.yield
      end
      taken = [count, @remaining.bytesize].min
      dest << @remaining.byteslice(0, taken)
      @remaining = @remaining.byteslice(taken, @remaining.bytesize - taken)
      taken
    end
  end

  # ---- BODY-22: drain at most once, lazily, on first access --------------------------------

  test "does not touch the delegate until a first access" do
    delegate = response_body
    wrapper(delegate)

    assert_equal("héllo".b, read_all(delegate.source))
  end

  test "drains exactly once however many accessors are called" do
    delegate = CountingDelegate.new("héllo")
    subject = wrapper(delegate)
    subject.snapshot
    subject.source
    subject.error
    subject.snapshot

    assert_equal(1, delegate.drains)
  end

  test "a source, a snapshot and an error query each trigger the first drain" do
    %i[source snapshot error].each do |accessor|
      delegate = CountingDelegate.new("héllo")
      wrapper(delegate).public_send(accessor)

      assert_equal(1, delegate.drains, "#{accessor} did not trigger the drain")
    end
  end

  # ---- BODY-23: the fits-cap regime --------------------------------------------------------

  test "captures the whole body when it fits within the cap" do
    assert_equal("héllo".b, wrapper.snapshot)
  end

  test "closes the delegate as part of a successful full capture" do
    delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("héllo"))
    wrapper(delegate).snapshot

    assert_equal(1, delegate.closes)
  end

  test "serves every read as a fresh non-consuming view, each succeeding independently" do
    subject = wrapper
    three = Array.new(3) { read_all(subject.source) }

    assert_equal(["héllo".b] * 3, three)
  end

  test "a body exactly the size of the cap is treated as fully captured" do
    subject = wrapper(response_body("abcdef"), preview_bytes: 6)

    assert_equal("abcdef".b, subject.snapshot)
    assert_equal(6, subject.content_length)
    assert_predicate(subject, :closed?)
  end

  # ---- BODY-24: the over-cap regime --------------------------------------------------------

  test "buffers only the prefix and leaves the delegate open when the body exceeds the cap" do
    delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("0123456789"))
    subject = wrapper(delegate, preview_bytes: 4)
    subject.snapshot

    assert_equal(0, delegate.closes)
    refute_predicate(subject, :closed?)
  end

  test "serves the next read as the prefix followed by the still-live tail, complete" do
    subject = wrapper(response_body("0123456789"), preview_bytes: 4)

    assert_equal("0123456789".b, read_all(subject.source))
  end

  test "a second read in the over-cap regime fails, because the tail is single-consumer" do
    subject = wrapper(response_body("0123456789"), preview_bytes: 4)
    subject.source
    error = assert_raises(Dexpace::StreamError) { subject.source }

    assert_includes(error.message, "BODY-24")
  end

  # The regime probe reads one byte past the cap to tell BODY-23 from BODY-24. That byte is kept,
  # because the composite owes the consumer every byte -- but it is kept OUTSIDE the capture, or
  # BODY-22's "up to a configurable byte cap" is exceeded by one on every over-cap body.
  test "the over-cap capture is exactly the cap, and the probe byte is still served" do
    subject = wrapper(response_body("0123456789"), preview_bytes: 4)

    assert_equal("0123".b, subject.snapshot)
    assert_equal("0123456789".b, read_all(subject.source))
  end

  # BODY-24's composite over a LIVE delegate: the tail is the consumer's real byte path, so it
  # must deliver what has arrived, not block for a count (review round 0, R0-3).
  class TailTest < DexpaceTestCase
    include Wrappers

    # A real IO.pipe with its writer held open: ten bytes written, two captured, one probed, and a
    # partial read of 1000 must return the seven that are there while the connection is still
    # open. Forwarding the tail as BufferedSource#read(count) blocks here until EOF; the join's
    # five-second timeout turns that hang into a failure, and the ensure closes the writer so the
    # parked thread finishes either way.
    test "a partial read on the live tail returns the bytes available without waiting for EOF" do
      reader, writer = ::IO.pipe
      delegate = Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.wrapping(reader))
      subject = wrapper(delegate, preview_bytes: 2)
      writer.write("0123456789")
      subject.snapshot
      tail = subject.source

      assert_equal("01".b, tail.readpartial(4))
      assert_equal("2".b, tail.readpartial(4))
      got = nil
      thread = ::Thread.new { got = tail.readpartial(1000) }
      finished = thread.join(5)

      refute_nil(finished, "the tail's partial read blocked with seven bytes available")
      assert_equal("3456789".b, got)
    ensure
      writer&.close
      thread&.join(5)
      tail&.close
    end

    test "the live tail is forwarded through read_into and asks the delegate for nothing more" do
      recorder = ReadIntoOnly.new("0123456789")
      subject = wrapper(FakeResponseBody.new(recorder), preview_bytes: 4)

      assert_equal("0123456789".b, read_all(subject.source))
      assert_equal([4, 1], recorder.counts.first(2))
    end

    # BODY-25 reaches the tail too: a zero return for the positive count .wrapping asks with is
    # the contract violation, never end of stream, and never a latched empty composite.
    test "a zero read from the live delegate is a stream-contract violation on the tail" do
      subject = wrapper(FakeResponseBody.new(FakeSource.new("0123", "4", 0)), preview_bytes: 4)
      tail = subject.source

      assert_equal("01234".b, tail.read(5))
      error = assert_raises(Dexpace::StreamError) { tail.read(1) }
      assert_includes(error.message, "IO-17")
    end

    # Exactly Dexpace::IO::_Source -- #read_into and nothing else -- with the counts it was asked
    # for, so "nothing more than the primitive" is asserted rather than described.
    class ReadIntoOnly
      attr_reader :counts

      def initialize(content)
        @remaining = content.b
        @counts = []
      end

      def read_into(dest, count:)
        @counts << count
        return -1 if @remaining.empty?

        taken = [count, @remaining.bytesize].min
        dest << @remaining.byteslice(0, taken)
        @remaining = @remaining.byteslice(taken, @remaining.bytesize - taken)
        taken
      end
    end
  end

  # BODY-25 and BODY-26: a zero read, and a mid-drain failure's three behaviours.
  class FailureTest < DexpaceTestCase
    include Wrappers

    # No real Ruby stream returns 0 for a positive requested count, which is why FakeSource exists.
    test "a delegate read returning zero for a positive count is a contract violation, not EOF" do
      subject = wrapper(FakeResponseBody.new(FakeSource.new("ab", 0)), preview_bytes: 64)

      assert_instance_of(Dexpace::StreamError, subject.error)
      assert_includes(subject.error.message, "IO-17")
    end

    test "the bytes read before a zero read are retained rather than discarded" do
      assert_equal("ab".b, wrapper(FakeResponseBody.new(FakeSource.new("ab", 0))).snapshot)
    end

    test "a read after a mid-drain failure re-raises the cached error on every call" do
      subject = wrapper(failing)
      first = assert_raises(Dexpace::StreamError) { subject.source }
      second = assert_raises(Dexpace::StreamError) { subject.source }

      assert_same(first, second)
    end

    # A bare `raise` re-raises the SAME object with its #cause and its original backtrace intact,
    # verified on 3.2.11, 3.4.10 and 4.0.6 -- so no #exception dance and no backtrace juggling.
    test "the re-raised error keeps its cause and its original backtrace" do
      cause = ::RuntimeError.new("root cause")
      failure = begin
        begin
          raise cause
        rescue ::RuntimeError
          raise Dexpace::StreamError, "the drain failed"
        end
      rescue Dexpace::StreamError => error
        error
      end
      subject = wrapper(failing("ab", failure))
      raised = assert_raises(Dexpace::StreamError) { subject.source }

      assert_same(failure, raised)
      assert_same(cause, raised.cause)
      assert_equal(failure.backtrace, raised.backtrace)
    end

    test "snapshot returns the partial bytes without raising after a mid-drain failure" do
      assert_equal("ab".b, wrapper(failing).snapshot)
    end

    test "the error accessor surfaces the cached error without raising or draining again" do
      subject = wrapper(failing)

      assert_instance_of(Dexpace::StreamError, subject.error)
      assert_same(subject.error, subject.error)
    end

    test "the error accessor is nil after a clean drain" do
      assert_nil(wrapper.error)
    end

    test "a failed drain leaves the delegate open for the wrapper's own close to release" do
      delegate = failing
      subject = wrapper(delegate)
      subject.error

      assert_equal(0, delegate.closes)
      subject.close

      assert_equal(1, delegate.closes)
    end
  end

  # BODY-27 and BODY-28, with IO-42 in the two directions that fail in opposite ways.
  class CloseTest < DexpaceTestCase
    include Wrappers

    def raising_delegate(content = "0123456789")
      FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes(content),
                           close_error: ::IOError.new("already closed"),)
    end

    test "closes the delegate at most once across every close path" do
      delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("0123456789"))
      subject = wrapper(delegate, preview_bytes: 4)
      subject.source
      subject.close
      subject.close

      assert_equal(1, delegate.closes)
    end

    # BODY-27 names TWO close paths, and this is the second one. BODY-24 hands the tail to a
    # consumer as the rest of the body, so closing what you were handed is the idiomatic release;
    # it has to reach the same guard the wrapper's own close reaches, or BODY-15's release is lost
    # one layer up.
    test "closing the tail the consumer was handed closes the delegate, exactly once" do
      delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("0123456789"))
      subject = wrapper(delegate, preview_bytes: 4)
      tail = subject.source
      tail.close

      assert_equal(1, delegate.closes)
      assert_predicate(subject, :closed?)

      tail.close
      subject.close

      assert_equal(1, delegate.closes)
    end

    test "closing the wrapper first and then the tail is still one close" do
      delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("0123456789"))
      subject = wrapper(delegate, preview_bytes: 4)
      tail = subject.source
      subject.close
      tail.close

      assert_equal(1, delegate.closes)
    end

    test "a delegate whose close raises is still marked closed, and the failure propagates once" do
      subject = wrapper(raising_delegate, preview_bytes: 4)

      assert_raises(::IOError) { subject.close }
      assert_predicate(subject, :closed?)
      assert_nil(subject.close)
      assert_equal(1, subject.delegate.closes)
    end

    test "close from two threads closes the delegate once even when its close raises" do
      subject = wrapper(raising_delegate, preview_bytes: 4)
      start = ::Thread::Queue.new
      outcomes = ::Thread::Queue.new
      threads = Array.new(4) do
        ::Thread.new do
          start.pop
          subject.close
          outcomes << :quiet
        rescue ::IOError
          outcomes << :raised
        end
      end
      4.times { start << :go }
      threads.each(&:join)
      results = Array.new(4) { outcomes.pop }

      assert_equal(1, results.count(:raised))
      assert_equal(1, subject.delegate.closes)
      assert_predicate(subject, :closed?)
    end

    test "a close failure after a successful full capture is not reported as a drain error" do
      subject = wrapper(raising_delegate("héllo"))

      assert_equal("héllo".b, subject.snapshot)
      assert_nil(subject.error)
      assert_predicate(subject, :closed?)
    end

    test "a close failure after a successful capture does not stop the body being served" do
      assert_equal("héllo".b, read_all(wrapper(raising_delegate("héllo")).source))
    end

    # IO-42's in-memory exemption. This test and the tail test below fail in OPPOSITE directions,
    # which is why they are two tests: one "it still works after close" test would pass over either
    # error.
    test "the captured buffer keeps answering after the wrapper's close" do
      subject = wrapper
      subject.snapshot
      subject.close

      assert_equal("héllo".b, subject.snapshot)
      assert_equal("héllo".b, read_all(subject.source))
    end

    # The rule with no external symptom TODAY and a severe one after one refactor, so it is pinned
    # directly: #release closes the delegate and deliberately does NOT close the captured buffer.
    # Closing it would invalidate every outstanding BODY-23 view for no gain and would put BODY-28's
    # post-mortem snapshot one reordering away from breaking.
    test "the wrapper's close closes the delegate and deliberately not the captured buffer" do
      fits = wrapper
      fits.snapshot
      fits.close

      over = wrapper(response_body("0123456789"), preview_bytes: 4)
      over.snapshot
      over.close

      refute_predicate(fits.instance_variable_get(:@buffer), :closed?)
      refute_predicate(over.instance_variable_get(:@buffer), :closed?)
    end

    # IO-42's third surface: views derived from the captured buffer are invalidated by the BUFFER's
    # close, never by the wrapper's.
    test "a view taken from the captured buffer before the close still reads after it" do
      subject = wrapper
      view = subject.source
      subject.close

      assert_equal("héllo".b, read_all(view))
    end

    test "the over-cap tail raises ClosedError after the wrapper's close" do
      subject = wrapper(response_body("0123456789"), preview_bytes: 4)
      tail = subject.source
      subject.close

      assert_raises(Dexpace::ClosedError) { read_all(tail) }
    end
  end

  # BODY-29: the reported length.
  class LengthTest < DexpaceTestCase
    include Wrappers

    test "reports the captured size when the body was fully captured" do
      subject = wrapper(response_body("héllo", content_length: 6))
      subject.snapshot

      assert_equal(6, subject.content_length)
    end

    test "reports the captured size even when the delegate declared none" do
      subject = wrapper(response_body("héllo"))
      subject.snapshot

      assert_equal(6, subject.content_length)
    end

    test "reports the delegate's declared length when the capture is only a prefix" do
      subject = wrapper(response_body("0123456789", content_length: 10), preview_bytes: 4)
      subject.snapshot

      assert_equal(10, subject.content_length)
    end

    test "reports the delegate's declared length before any drain, and triggers none" do
      delegate = CountingDelegate.new("héllo", content_length: 6)
      subject = wrapper(delegate)

      assert_equal(6, subject.content_length)
      assert_equal(0, delegate.drains)
    end

    test "delegates the media type" do
      media = Dexpace::MediaType.parse("text/plain")

      assert_equal(media, wrapper(response_body("a", media_type: media)).media_type)
    end
  end

  # BODY-22's serialization, and the fiber proof.
  class SerializationTest < DexpaceTestCase
    include Wrappers

    test "concurrent first accesses drain the upstream exactly once" do
      delegate = CountingDelegate.new("0" * 512)
      subject = wrapper(delegate, preview_bytes: 512)
      start = ::Thread::Queue.new
      threads = Array.new(8) do
        ::Thread.new do
          start.pop
          subject.snapshot
        end
      end
      8.times { start << :go }
      threads.each(&:join)

      assert_equal(1, delegate.drains)
      assert_equal(512, subject.snapshot.bytesize)
    end

    # THE fiber proof, and it terminates. Fiber A suspends INSIDE the drain with the state flipped
    # to :running and the mutex NOT held; fiber B then calls #content_length, which takes the same
    # mutex briefly and returns. Under a mutex held across the drain, B raises "ThreadError:
    # deadlock; lock already owned by another fiber belonging to the same thread" -- verified -- so
    # this fails loudly under exactly the bug it exists to catch rather than restating the previous
    # test.
    test "two fibers of one thread interleave the drain without a ThreadError" do
      delegate = FakeResponseBody.new(SuspendingSource.new("0123456789"), content_length: 10)
      subject = wrapper(delegate, preview_bytes: 64)
      drainer = ::Fiber.new { subject.snapshot }
      drainer.resume

      observed = ::Fiber.new { subject.content_length }.resume
      drainer.resume

      assert_equal(10, observed)
      assert_equal("0123456789".b, subject.snapshot)
    end
  end

  # The wrapper's delegate contract is #source, #content_length, #media_type and #close, and the
  # three bodies that can occupy Response#body answer #source differently on purpose (P3-23):
  # ResponseBody with BODY-14's same handle every call, BufferBody with a FRESH #peek view per
  # call. Every row above drives a ResponseBody, over which asking three times is harmless; these
  # drive the second body and a fresh-view double, over which it was not (review round 1, R1-1).
  class DelegateHandleTest < DexpaceTestCase
    include Wrappers

    def bounded(content)
      Dexpace::Body.buffer_bounded(response_body(content), cap: 64)
    end

    def views(body)
      body.instance_variable_get(:@buffer).instance_variable_get(:@dexpace_views).length
    end

    # BODY-24's "the consumer receives the complete body" over a delegate whose every #source
    # starts at byte zero: three asks replayed the prefix twice and then the whole body.
    test "over a BufferBody delegate the over-cap composite delivers the body exactly once" do
      subject = wrapper(bounded("0123456789"), preview_bytes: 4)

      assert_equal("0123".b, subject.snapshot)
      assert_equal("0123456789".b, read_all(subject.source))
    end

    # "Every view core takes, core closes": the fill's view is a view the delegate's buffer
    # registers, and the wrapper's close is the only thing that can deregister it.
    test "over a BufferBody delegate the fits-cap capture closes the view it took" do
      delegate = bounded("0123")
      subject = wrapper(delegate, preview_bytes: 64)

      assert_equal("0123".b, subject.snapshot)
      assert_predicate(subject, :closed?)
      assert_equal(0, views(delegate))
      assert_equal("0123".b, read_all(delegate.source))
    end

    test "over a BufferBody delegate the over-cap composite's close deregisters its handle" do
      delegate = bounded("0123456789")
      subject = wrapper(delegate, preview_bytes: 4)
      tail = subject.source

      assert_equal(1, views(delegate))
      tail.close

      assert_equal(0, views(delegate))
    end

    test "asks the delegate for its source exactly once, in either regime" do
      over = FreshViewDelegate.new("0123456789")
      subject = wrapper(over, preview_bytes: 4)
      subject.snapshot
      read_all(subject.source)
      subject.close

      assert_equal(1, over.asks)

      fits = FreshViewDelegate.new("0123")
      subject = wrapper(fits, preview_bytes: 64)
      3.times { subject.source }
      subject.snapshot

      assert_equal(1, fits.asks)
    end

    test "closing an undrained wrapper closes the delegate and never asks it for a source" do
      delegate = FreshViewDelegate.new("0123456789")
      subject = wrapper(delegate, preview_bytes: 4)
      subject.close

      assert_equal(1, delegate.closes)
      assert_equal(0, delegate.asks)
    end

    # The handle is derived from the delegate, so it is closed first; and the delegate's close is
    # BODY-15's transport release, so it still runs when the handle's close raises, and the one
    # failure propagates once (BODY-27).
    test "closes the handle ahead of the delegate, and the delegate even when the handle raises" do
      delegate = LoggingHandleDelegate.new("0123456789", handle_error: ::IOError.new("handle"))
      subject = wrapper(delegate, preview_bytes: 4)
      subject.snapshot

      assert_raises(::IOError) { subject.close }
      assert_equal(%i[handle delegate], delegate.log)
      assert_predicate(subject, :closed?)
      assert_nil(subject.close)
      assert_equal(%i[handle delegate], delegate.log)
    end

    test "a handle whose close raises after a full capture is not reported as a drain error" do
      delegate = LoggingHandleDelegate.new("0123", handle_error: ::IOError.new("handle"))
      subject = wrapper(delegate, preview_bytes: 64)

      assert_equal("0123".b, subject.snapshot)
      assert_nil(subject.error)
      assert_equal(%i[handle delegate], delegate.log)
    end

    # A delegate that answers #source with a FRESH view per call, as BufferBody does, and counts
    # the asks -- CountingDelegate memoises its source, so it cannot see a second one.
    class FreshViewDelegate
      attr_reader :asks, :closes, :media_type, :content_length

      def initialize(content)
        @buffer = Dexpace::IO::Buffer.new
        @buffer.write(content.b)
        @media_type = nil
        @content_length = -1
        @asks = 0
        @closes = 0
      end

      def source
        @asks += 1
        @buffer.peek
      end

      def close
        @closes += 1
        nil
      end
    end

    # A delegate whose handle's close can RAISE, recording the order of the two closes.
    class LoggingHandleDelegate
      attr_reader :log, :media_type, :content_length

      def initialize(content, handle_error: nil)
        @content = content.b
        @handle_error = handle_error
        @media_type = nil
        @content_length = -1
        @log = []
      end

      def source
        Handle.new(Dexpace::IO::BufferedSource.of_bytes(@content), @log, @handle_error)
      end

      def close
        @log << :delegate
        nil
      end

      # The handle: a _Source over an of_bytes source, plus the recording close.
      class Handle
        def initialize(inner, log, error)
          @inner = inner
          @log = log
          @error = error
        end

        def read_into(dest, count:)
          @inner.read_into(dest, count: count)
        end

        def close
          @log << :handle
          raise @error unless @error.nil?

          nil
        end
      end
    end
  end

  # Construction and BODY-34's structural half.
  class ConstructionTest < DexpaceTestCase
    include Wrappers

    # BODY-22 names no default and an unbounded one would mean the over-cap regime never fires, so
    # the keyword is REQUIRED -- deliberately asymmetric with RequestLoggingBody (P3-18). Adding a
    # default in phase 5 widens the signature and cannot break NFR-4.
    test "requires its preview cap, because BODY-22 names no default" do
      assert_raises(::ArgumentError) { Dexpace::ResponseLoggingBody.new(response_body) }
      assert_includes(Dexpace::ResponseLoggingBody.instance_method(:initialize).parameters,
                      %i[keyreq preview_bytes],)
    end

    test "rejects a negative cap and a delegate with no source" do
      assert_raises(Dexpace::InvalidArgumentError) { wrapper(response_body, preview_bytes: -1) }
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::ResponseLoggingBody.new(Object.new, preview_bytes: 4)
      end
    end

    test "a cap of zero captures nothing and serves the whole body from the tail" do
      subject = wrapper(response_body("héllo"), preview_bytes: 0)

      assert_equal("".b, subject.snapshot)
      assert_equal("héllo".b, read_all(subject.source))
    end

    test "a cap of zero over an empty body is a complete capture" do
      subject = wrapper(response_body(""), preview_bytes: 0)

      assert_equal("".b, subject.snapshot)
      assert_equal("".b, read_all(subject.source))
      assert_predicate(subject, :closed?)
    end

    test "is a reader, so offering it as a request body fails loudly" do
      error = assert_raises(Dexpace::StreamError) { wrapper.write_to(Dexpace::IO::Buffer.new) }

      assert_includes(error.message, "#source")
    end

    test "nothing in the core library constructs a response-logging wrapper" do
      root = File.expand_path("../../../../lib", __dir__)
      sources = Dir.glob("#{root}/**/*.rb").grep_v(/response_logging_body\.rb\z/)
      constructions = sources.select do |path|
        File.read(path).include?("ResponseLoggingBody.new")
      end

      assert_empty(constructions)
    end

    test "compares by identity, because it holds a live delegate" do
      subject = wrapper
      same = subject

      assert_equal(subject, same)
      refute_equal(subject, wrapper)
    end
  end
end
