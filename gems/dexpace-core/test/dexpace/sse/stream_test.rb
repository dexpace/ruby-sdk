# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/sse_fixtures"
require_relative "../../support/recovery_fixtures"
require_relative "../../support/fake_chunked"
require_relative "../../support/recording_sink"

# Exercises: SSE-23 (exactly one closeable resource, closed exactly once across every termination
# path), SSE-24 (clean end releases), SSE-25 (partial consume must not strand), SSE-26
# (single-pass), SSE-27 (post-close iteration fails; an in-flight iterator ends cleanly), SSE-28
# (idempotent close), SSE-29 (mid-stream failure releases before propagating, with the release
# failure suppressed), SSE-30 (the swallow-versus-propagate split, and the swallowed half's
# out-of-band report), SSE-31 (cross-thread close, both shapes), SSE-32 (the response convenience),
# SSE-39 (no eager read-ahead), SSE-40 (the lazy single-pass view); P7-25. Every source is a real
# BufferedSource and every resource a FakeResponseBody whose `#closes` counts. Split under
# Metrics/ClassLength: construction, the lifecycle, the failure paths, and the two threads.
class DexpaceSSEStreamTest < DexpaceTestCase
  Stream = Dexpace::SSE::Stream
  Logger = Dexpace::Instrumentation::Logger
  Events = Dexpace::Instrumentation::Events
  Keys = Dexpace::Instrumentation::Keys

  # The three factories and their refusals (P7-25).
  class ConstructionTest < DexpaceTestCase
    include SSEFixtures

    test "P7-25: owning owns, borrowing borrows, and resource: defaults to the source" do
      source = byte_source
      owning = Stream.owning(source)
      borrowing = Stream.borrowing(byte_source)

      assert_predicate(owning, :owned?)
      refute_predicate(borrowing, :owned?)
      owning.each { |_e| nil }

      assert_predicate(source, :closed?, "one argument owns the object it reads from")
    end

    test "P7-25: none of the three is called .over, whose polarity in IO is the opposite" do
      refute_respond_to(Stream, :over)
      refute_respond_to(Stream, :wrapping)
      refute_respond_to(Stream, :new)
    end

    test "P7-25: the caps and the logger reach the reader and the release paths as keywords" do
      stream = Stream.owning(byte_source("data: #{"x" * 64}\n\n"), max_line_bytes: 32)

      assert_raises(Dexpace::SSE::LimitExceededError) { stream.each { |_e| nil } }
      stream = Stream.borrowing(byte_source("data: a\ndata: b\n\n"), max_event_bytes: 8)

      assert_raises(Dexpace::SSE::LimitExceededError) { stream.events.next }
    end

    test "a source without the three reader methods is refused by name" do
      assert_raises(Dexpace::InvalidArgumentError) { Stream.owning(::Object.new) }
    end

    test "SSE-23: an owned resource must be closeable; a borrowed one need not be" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Stream.owning(byte_source, resource: ::Object.new)
      end

      assert_match(/close/, error.message)
      borrowing = Stream.borrowing(byte_source, resource: ::Object.new)

      refute_predicate(borrowing, :closed?)
      assert_nil(borrowing.close, "a borrowed resource is never released, so it need not close")
    end

    test "logger: takes an Instrumentation::Logger and nothing else" do
      assert_raises(Dexpace::InvalidArgumentError) { Stream.owning(byte_source, logger: ::Object.new) }
      assert_raises(Dexpace::InvalidArgumentError) { Stream.borrowing(byte_source, logger: nil) }
    end

    test "SSE-32: Stream.open takes a Dexpace::Response and nothing else" do
      assert_raises(Dexpace::InvalidArgumentError) { Stream.open(::Object.new) }
    end
  end

  # SSE-23 through SSE-28, SSE-39 and SSE-40: the lifecycle on the happy paths.
  class LifecycleTest < DexpaceTestCase
    include SSEFixtures

    test "SSE-23/SSE-24: iterating to completion without close releases the resource once" do
      stream, resource = stream_over
      delivered = []
      stream.each { |event| delivered.concat(event.data) }

      assert_equal(%w[a b c], delivered)
      assert_equal(1, resource.closes)
      assert_predicate(stream, :closed?)
    end

    test "SSE-24: the external form releases on the pull that finds the end" do
      stream, resource = stream_over
      enum = stream.events
      3.times { enum.next }

      assert_equal(0, resource.closes, "three events pulled, the end not yet seen")
      assert_raises(::StopIteration) { enum.next }
      assert_equal(1, resource.closes)
    end

    test "SSE-23/SSE-28: three explicit closes release once" do
      stream, resource = stream_over

      3.times { assert_nil(stream.close) }

      assert_equal(1, resource.closes)
    end

    test "SSE-28: an explicit close after an automatic release leaves the count at one" do
      stream, resource = stream_over
      stream.each { |_event| nil }
      stream.close

      assert_equal(1, resource.closes)
    end

    test "SSE-25: a partial consume through the block form releases on exit" do
      stream, resource = stream_over

      assert_equal(["a"], consume_one(stream).data)
      assert_equal(1, resource.closes)
      assert_predicate(stream, :closed?)
    end

    test "SSE-25: a partial consume through the enumerator releases on explicit close" do
      # verified fact 6: an Enumerator abandoned mid-#next never runs its ensure and GC is not a
      # cleanup hook. This asserts BOTH halves -- the absence of a release after abandonment and
      # its presence after the documented remedy -- because asserting only the second would hide
      # the rule the design is built on. The enumerator is dropped inside a helper so no reference
      # to it survives into the assertions.
      stream, resource = stream_over
      pull_one_and_abandon(stream)
      2.times { GC.start }

      assert_equal(0, resource.closes, "abandonment released nothing")
      stream.close

      assert_equal(1, resource.closes)
    end

    def pull_one_and_abandon(stream)
      stream.events.next
      nil
    end
  end

  # SSE-26, SSE-27, SSE-39 and SSE-40: the one view.
  class ViewTest < DexpaceTestCase
    include SSEFixtures

    test "SSE-26: obtaining an iterator twice fails loudly" do
      stream, = stream_over
      stream.events
      error = assert_raises(Dexpace::SSE::StreamStateError) { stream.events }

      assert_match(/single-pass|already/, error.message)
    end

    test "SSE-26/SSE-40: #each after #events also fails -- one view, either shape" do
      stream, = stream_over
      stream.events

      assert_raises(Dexpace::SSE::StreamStateError) { stream.each { |_e| nil } }
      other, = stream_over
      consume_one(other)

      assert_raises(Dexpace::SSE::StreamStateError) { other.events }
    end

    test "SSE-27: requesting an iterator after close fails loudly" do
      stream, = stream_over
      stream.close
      error = assert_raises(Dexpace::SSE::StreamStateError) { stream.events }

      assert_match(/closed/, error.message)
      assert_raises(Dexpace::SSE::StreamStateError) { stream.each { |_e| nil } }
    end

    test "SSE-27/SSE-31: a close observed between pulls ends iteration cleanly" do
      stream, resource = stream_over
      enum = stream.events

      assert_equal(["a"], enum.next.data)
      stream.close
      assert_raises(::StopIteration) { enum.next }
      assert_equal(1, resource.closes)
    end

    test "SSE-27: a close between pulls never reads the torn-down source" do
      # The source is CLOSED by the stream (it is the resource here), and a read on a closed
      # BufferedSource raises ClosedError -- a StandardError, which would take the SSE-29 path
      # and surface instead of the clean end. The closed? check runs before every read.
      source = byte_source
      stream = Stream.owning(source)
      enum = stream.events
      enum.next
      stream.close

      assert_predicate(source, :closed?)
      assert_raises(::StopIteration) { enum.next }
    end

    test "SSE-39: pulling one event does not read ahead into the next" do
      chunked = FakeChunked.new("data: a\n\n", "data: b\n\n")
      stream = Stream.owning(Dexpace::IO::BufferedSource.over(chunked), resource: counting_resource)
      enum = stream.events

      assert_equal(["a"], enum.next.data)
      assert_equal(1, chunked.yielded)
      assert_equal(["b"], enum.next.data)
      assert_equal(2, chunked.yielded)
    end

    test "SSE-39: a stream built and never pulled touches its source zero times" do
      chunked = FakeChunked.new("\xEF\xBB\xBFdata: a\n\n".b)
      stream = Stream.owning(Dexpace::IO::BufferedSource.over(chunked), resource: counting_resource)
      stream.events

      assert_equal(0, chunked.yielded)
      stream.close
    end

    test "SSE-40: the view reuses one reader instance, so the BOM is consumed once" do
      stream, = stream_over("\xEF\xBB\xBFdata: a\n\ndata: \xEF\xBB\xBFb\n\n")
      parsed = stream.events.to_a

      assert_equal(["a"], parsed.first.data)
      assert_equal(["\u{FEFF}b"], parsed.last.data)
    end

    test "SSE-40: the view is an Enumerator over Events, lazy until pulled" do
      stream, resource = stream_over
      enum = stream.events

      assert_kind_of(::Enumerator, enum)
      assert_equal(0, resource.closes)
      assert_kind_of(Dexpace::SSE::Event, enum.first)
    end
  end

  # SSE-29, SSE-30 and SSE-40: the failure paths and the swallow-versus-propagate split.
  class FailureTest < DexpaceTestCase
    include SSEFixtures

    test "SSE-29: a mid-stream read failure releases before propagating" do
      resource = counting_resource
      stream = Stream.owning(failing_source("data: a\n\n", Dexpace::StreamError.new("boom")),
                             resource: resource,)
      enum = stream.events

      assert_equal(["a"], enum.next.data)
      error = assert_raises(Dexpace::StreamError) { enum.next }

      assert_equal("boom", error.message)
      assert_equal(1, resource.closes)
      assert_predicate(stream, :closed?)
    end

    test "SSE-29: the block form releases before the failure reaches the caller too" do
      resource = counting_resource
      stream = Stream.owning(failing_source("data: a\n\n", Dexpace::StreamError.new("boom")),
                             resource: resource,)
      seen_closes = nil
      assert_raises(Dexpace::StreamError) do
        stream.each { |_e| seen_closes = resource.closes }
      end

      assert_equal(0, seen_closes, "the first event was delivered before the failure")
      assert_equal(1, resource.closes)
    end

    test "SSE-29: a release failure during a mid-stream failure is attached as suppressed" do
      resource = counting_resource(close_error: ::IOError.new("close failed"))
      stream = Stream.owning(failing_source("", Dexpace::StreamError.new("boom")),
                             resource: resource,)
      error = assert_raises(Dexpace::StreamError) { stream.each { |_e| nil } }

      assert_equal(["close failed"], Dexpace.suppressed(error).map(&:message))
      assert_equal(1, resource.closes)
    end

    test "SSE-29: a failure raised by the caller's own block releases before it propagates" do
      resource = counting_resource(close_error: ::IOError.new("close failed"))
      stream, = stream_over(resource: resource)
      error = assert_raises(::ArgumentError) do
        stream.each { |event| raise ::ArgumentError, "mine" if event.data == ["b"] }
      end

      assert_equal(1, resource.closes)
      assert_equal(["close failed"], Dexpace.suppressed(error).map(&:message))
    end

    test "SSE-29: a LimitExceededError travels the same path -- released, then raised" do
      resource = counting_resource
      stream = Stream.owning(byte_source("data: #{"x" * 64}\n\n"), resource: resource,
                                                                   max_line_bytes: 32,)
      error = assert_raises(Dexpace::SSE::LimitExceededError) { stream.events.next }

      assert_equal(:line, error.kind)
      assert_equal(1, resource.closes)
    end

    test "SSE-30: a release failure on the automatic terminal path is swallowed" do
      resource = counting_resource(close_error: ::IOError.new("close failed"))
      stream, = stream_over(resource: resource)
      delivered = []
      stream.each { |event| delivered.concat(event.data) }

      assert_equal(%w[a b c], delivered)
      assert_equal(1, resource.closes)
      assert_predicate(stream, :closed?)
    end

    test "SSE-30: the swallowed release failure is reported out of band, through the logger" do
      # The mechanism is 5b's: Dexpace.close_quietly's onto:-absent route emits one WARNING
      # http.instrumentation.close diagnostic carrying the cause -- never the event payload, never
      # a data byte -- and under the default Logger::NULL emits nothing at all.
      sink = RecordingSink.new
      resource = counting_resource(close_error: ::IOError.new("close failed"))
      stream, = stream_over(resource: resource, logger: Logger.build(sink: sink))
      stream.each { |_event| nil }

      assert_equal(1, sink.entries.size)
      assert_equal(:warn, sink.entries.first.severity)
      payload = sink.payloads.first

      assert_equal(Events::INSTRUMENTATION_CLOSE, payload[Keys::EVENT])
      assert_equal("IOError: close failed", payload[Keys::CAUSE])
      refute_match(/data: /, payload.inspect)
    end

    test "SSE-30: a release failure during an EXPLICIT close propagates" do
      resource = counting_resource(close_error: ::IOError.new("close failed"))
      stream, = stream_over(resource: resource)
      error = assert_raises(::IOError) { stream.close }

      assert_equal("close failed", error.message)
      assert_equal(1, resource.closes)
      assert_predicate(stream, :closed?, "the latch flipped although the release raised")
      assert_nil(stream.close, "and it does not release a second time")
    end

    test "SSE-30: a release failure on a block-form break propagates, as an explicit close does" do
      resource = counting_resource(close_error: ::IOError.new("close failed"))
      stream, = stream_over(resource: resource)

      assert_raises(::IOError) { consume_one(stream) }
      assert_equal(1, resource.closes)
    end

    test "SSE-40: the view is lazy and propagates a read failure at the offending pull" do
      stream = Stream.owning(failing_source("data: a\n\ndata: b\n\n", Dexpace::StreamError.new("boom")),
                             resource: counting_resource,)
      enum = stream.events

      assert_equal(["a"], enum.next.data)
      assert_equal(["b"], enum.next.data)
      assert_raises(Dexpace::StreamError) { enum.next }
    end

    test "SSE-27: after a failure released the stream, a further pull is a clean end" do
      stream = Stream.owning(failing_source("data: a\n\n", Dexpace::StreamError.new("boom")),
                             resource: counting_resource,)
      enum = stream.events
      enum.next
      assert_raises(Dexpace::StreamError) { enum.next }
      assert_raises(::StopIteration) { enum.next }
    end
  end

  # SSE-31 (the blocked-read shape) and SSE-32 (the response convenience).
  class ThreadAndResponseTest < DexpaceTestCase
    include SSEFixtures
    include RecoveryFixtures

    test "SSE-31: a close that tears down an in-flight blocked read surfaces as an I/O error" do
      # verified fact 7: closing the read end of an IO.pipe from another thread while a thread is
      # parked in a read raises IOError in the parked thread. Sequenced through a Queue and a
      # status poll, never a sleep -- phase 3a's IO-38 shape. The wrapping source is its OWN
      # resource (the `resource: source` default), and that is the whole test: #close releases
      # the RESOURCE, so a stream reading from the pipe while owning some unrelated close-counter
      # would close the counter, leave the read parked, and HANG on Thread#value rather than fail.
      reader_end, writer_end = ::IO.pipe
      source = Dexpace::IO::BufferedSource.wrapping(reader_end)
      stream = Stream.owning(source)
      started = ::Thread::Queue.new
      reader = ::Thread.new do
        started << :ready
        begin
          stream.each { |_e| nil }
          :returned
        rescue ::StandardError => error
          error
        end
      end
      started.pop
      ::Thread.pass until reader.status == "sleep" || !reader.status
      stream.close

      assert_kind_of(::IOError, reader.value)
      assert_predicate(source, :closed?)
      assert_predicate(reader_end, :closed?, "IO-6: closing the wrapping source closed the pipe")
      assert_predicate(stream, :closed?)
      writer_end.close
    end

    test "SSE-32: opening over a response binds the stream's lifecycle to the response" do
      # Stream.open passes response.body.source as the SOURCE and the response as the RESOURCE:
      # the two are different objects, which is why the facade takes two parameters at all. A
      # real Dexpace::Response over a real ResponseBody, whose Closeable latch is what closing the
      # response flips (HTTP-43).
      response = build_response(200, body: response_body(SSEFixtures::FIXTURE))
      stream = Stream.open(response)
      delivered = []
      stream.each { |event| delivered.concat(event.data) }

      assert_equal(%w[a b c], delivered)
      assert_predicate(response.body, :closed?)
      assert_predicate(stream, :owned?)
    end

    test "SSE-32: closing the stream closes the response, once" do
      response = build_response(200, body: response_body(SSEFixtures::FIXTURE))
      stream = Stream.open(response)
      stream.events.next
      stream.close
      stream.close

      assert_predicate(response.body, :closed?)
      assert_raises(Dexpace::ClosedError) { response.body.source.getbyte }
    end

    test "SSE-32: opening over a bodyless response fails loudly" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Stream.open(build_response(200)) }

      assert_match(/no body/, error.message)
    end

    test "SSE-32: the caps and the logger reach the reader through Stream.open too" do
      response = build_response(200, body: response_body("data: #{"x" * 64}\n\n"))

      assert_raises(Dexpace::SSE::LimitExceededError) do
        Stream.open(response, max_line_bytes: 32).each { |_e| nil }
      end
      assert_predicate(response.body, :closed?, "released on the failure path")
    end
  end
end
