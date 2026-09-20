# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/sse_fixtures"
require_relative "../../support/fake_chunked"
require_relative "../../support/recording_sink"

# Exercises: SSE-33 (the mapper receives the raw event name and the data lines joined by a single
# \n, and the decoded value is yielded), SSE-34 (the three outcomes), SSE-35 (lazy, per-element
# decoding), SSE-36 (a throwing mapper propagates at the pull but releases the resource first),
# SSE-23 and SSE-26/SSE-40 through the typed layer, SSE-30's done-sentinel clause, SSE-39's
# drain clause; P7-23. The two consumption shapes mirror Stream's exactly: #each takes the block,
# #values returns the Enumerator; TypedStream does NOT include Enumerable and #each never returns
# an enumerator, so every external-iteration assertion goes through #values. Split under
# Metrics/ClassLength: the mapper contract, and the lifecycle through the typed layer.
class DexpaceSSETypedStreamTest < DexpaceTestCase
  Logger = Dexpace::Instrumentation::Logger
  Events = Dexpace::Instrumentation::Events
  Keys = Dexpace::Instrumentation::Keys

  # SSE-33, SSE-34, SSE-35: what the mapper receives and what its three answers do.
  class MapperTest < DexpaceTestCase
    include SSEFixtures

    test "SSE-33: the mapper receives the data lines joined with a single newline" do
      seen = []
      stream, = stream_over("data: line1\ndata: line2\n\n")
      stream.typed { |name, data| seen << [name, data] }.each { |_v| nil }

      assert_equal([[nil, "line1\nline2"]], seen)
    end

    test "SSE-33: a no-data event gives the mapper the empty string, not nil" do
      seen = []
      stream, = stream_over("event: ping\n\n")
      stream.typed { |name, data| seen << [name, data] }.each { |_v| nil }

      assert_equal([["ping", ""]], seen)
    end

    test "SSE-33: the event name is the raw field -- present-but-empty is '', absent is nil" do
      seen = []
      stream, = stream_over("event:\ndata: x\n\ndata: y\n\nevent: Named\ndata: z\n\n")
      stream.typed { |name, _data| seen << name }.each { |_v| nil }

      assert_equal(["", nil, "Named"], seen)
    end

    test "SSE-33: an empty data line joins as an empty segment, so the join is exact" do
      seen = []
      stream, = stream_over("data: a\ndata:\ndata: c\n\n")
      stream.typed { |_name, data| seen << data }.each { |_v| nil }

      assert_equal(["a\n\nc"], seen)
    end

    test "SSE-33: the mapper's decoded value is what the consumer receives" do
      stream, = stream_over("data: 1\n\ndata: 2\n\n")

      assert_equal([10, 20], stream.typed { |_n, d| d.to_i * 10 }.values.to_a)
    end

    test "SSE-33: a mapper returning nil yields nil -- nil is a value, not a sentinel" do
      stream, = stream_over("data: x\n\n")

      assert_equal([nil], stream.typed { |_n, _d| nil }.values.to_a)
      other, = stream_over("data: x\n\n")

      assert_equal([nil], gathered(other.typed { |_n, _d| nil }))
    end

    test "SSE-33: a mapper may be a callable argument instead of a block" do
      mapper = ->(_name, data) { data.upcase }
      stream, = stream_over("data: a\n\n")

      assert_equal(["A"], stream.typed(mapper).values.to_a)
      other, = stream_over

      assert_raises(Dexpace::InvalidArgumentError) { other.typed }
      assert_raises(Dexpace::InvalidArgumentError) { other.typed(->(_one) {}) }
    end
  end

  # SSE-34, SSE-35 and SSE-39: the three outcomes and the laziness.
  class OutcomeTest < DexpaceTestCase
    include SSEFixtures

    test "SSE-34: SKIP drops the event and advances, never surfacing it" do
      stream, = stream_over("data: a\n\ndata: skipme\n\ndata: c\n\n")
      typed = stream.typed { |_n, d| d == "skipme" ? Dexpace::SSE::SKIP : d }

      assert_equal(%w[a c], typed.values.to_a)
    end

    test "SSE-34: DONE ends iteration cleanly, closes the stream, and yields no sentinel model" do
      resource = counting_resource
      stream, = stream_over("data: a\n\ndata: bye\n\ndata: never\n\n", resource: resource)
      typed = stream.typed { |_n, d| d == "bye" ? Dexpace::SSE::DONE : d }

      assert_equal(%w[a], typed.values.to_a)
      assert_equal(1, resource.closes)
      assert_predicate(stream, :closed?)
    end

    test "SSE-34: DONE through the block form closes the stream too; the block sees no sentinel" do
      resource = counting_resource
      stream, = stream_over("data: a\n\ndata: bye\n\ndata: never\n\n", resource: resource)
      seen = gathered(stream.typed { |_n, d| d == "bye" ? Dexpace::SSE::DONE : d })

      assert_equal(%w[a], seen)
      assert_equal(1, resource.closes)
    end

    test "SSE-34: events after a DONE sentinel are never decoded" do
      decoded = []
      stream, = stream_over("data: a\n\ndata: bye\n\ndata: never\n\n")
      stream.typed do |_n, d|
        decoded << d
        d == "bye" ? Dexpace::SSE::DONE : d
      end.values.to_a

      assert_equal(%w[a bye], decoded)
    end

    test "SSE-34: the outcome comparison is identity -- a value that == a sentinel is yielded" do
      lookalike = Dexpace::SSE::Sentinel.send(:new, name: :skip)
      stream, = stream_over("data: a\n\n")

      assert_equal([lookalike], stream.typed { |_n, _d| lookalike }.values.to_a)
    end

    test "SSE-35: decoding is lazy -- one mapper call per pull" do
      calls = 0
      stream, = stream_over("data: a\n\ndata: b\n\ndata: c\n\n")
      enum = stream.typed do |_n, d|
        calls += 1
        d
      end.values

      assert_equal(0, calls, "nothing decoded before the first pull")
      enum.next

      assert_equal(1, calls)
      enum.next

      assert_equal(2, calls)
    end

    test "SSE-35/SSE-39: draining Skips pulls only as many raw events as one element needs" do
      calls = 0
      stream, = stream_over("data: s\n\ndata: s\n\ndata: v\n\ndata: v2\n\n")
      typed = stream.typed do |_n, d|
        calls += 1
        d == "s" ? Dexpace::SSE::SKIP : d
      end

      assert_equal("v", typed.values.next)
      assert_equal(3, calls, "two skips drained, one value produced; v2 not touched")
    end

    test "SSE-39: the typed layer reads no further ahead than the raw one" do
      chunked = FakeChunked.new("data: a\n\n", "data: b\n\n")
      stream = Dexpace::SSE::Stream.owning(Dexpace::IO::BufferedSource.over(chunked),
                                           resource: counting_resource,)
      enum = stream.typed { |_n, d| d }.values

      assert_equal("a", enum.next)
      assert_equal(1, chunked.yielded)
    end
  end

  # SSE-36, SSE-23, SSE-26/SSE-40 and SSE-30 through the typed layer.
  class LifecycleTest < DexpaceTestCase
    include SSEFixtures

    test "SSE-36: a mapper that raises propagates at that pull and releases the resource first" do
      resource = counting_resource
      stream, = stream_over("data: a\n\ndata: boom\n\n", resource: resource)
      enum = stream.typed { |_n, d| d == "boom" ? raise(::ArgumentError, "nope") : d }.values

      assert_equal("a", enum.next)
      error = assert_raises(::ArgumentError) { enum.next }

      assert_equal("nope", error.message)
      assert_equal(1, resource.closes)
      assert_predicate(stream, :closed?)
    end

    test "SSE-36: the block form releases before the mapper's error reaches the caller too" do
      resource = counting_resource
      stream, = stream_over("data: a\n\ndata: boom\n\n", resource: resource)
      seen = []
      typed = stream.typed { |_n, d| d == "boom" ? raise(::ArgumentError, "nope") : d }
      assert_raises(::ArgumentError) do
        typed.each { |value| seen.push([value, resource.closes]) }
      end

      assert_equal([["a", 0]], seen)
      assert_equal(1, resource.closes)
    end

    test "SSE-36: a release failure during a mapper failure is attached as suppressed" do
      resource = counting_resource(close_error: ::IOError.new("close failed"))
      stream, = stream_over("data: boom\n\n", resource: resource)
      typed = stream.typed { |_n, _d| raise(::ArgumentError, "nope") }
      error = assert_raises(::ArgumentError) { typed.values.to_a }

      assert_equal(["close failed"], Dexpace.suppressed(error).map(&:message))
      other, = stream_over("data: boom\n\n",
                           resource: counting_resource(close_error: ::IOError.new("x")),)
      error = assert_raises(::ArgumentError) do
        other.typed { |_n, _d| raise(::ArgumentError, "nope") }.each { |_v| nil }
      end

      assert_equal(["x"], Dexpace.suppressed(error).map(&:message))
    end

    test "SSE-29/SSE-40: a raw read failure surfaces through the typed view at its pull" do
      resource = counting_resource
      stream = Dexpace::SSE::Stream.owning(failing_source("data: a\n\n", Dexpace::StreamError.new("boom")),
                                           resource: resource,)
      enum = stream.typed { |_n, d| d }.values

      assert_equal("a", enum.next)
      assert_raises(Dexpace::StreamError) { enum.next }
      assert_equal(1, resource.closes)
    end

    test "SSE-30: a release failure on the DONE path is swallowed and reported out of band" do
      sink = RecordingSink.new
      resource = counting_resource(close_error: ::IOError.new("close failed"))
      stream, = stream_over("data: a\n\ndata: bye\n\n", resource: resource,
                                                        logger: Logger.build(sink: sink),)
      values = stream.typed { |_n, d| d == "bye" ? Dexpace::SSE::DONE : d }.values.to_a

      assert_equal(%w[a], values, "the delivered values are not discarded")
      assert_equal(1, resource.closes)
      assert_equal([Events::INSTRUMENTATION_CLOSE], sink.payloads.map { |p| p[Keys::EVENT] })
      assert_equal("IOError: close failed", sink.payloads.first[Keys::CAUSE])
    end

    test "SSE-30: an explicit close through the typed view propagates a release failure" do
      resource = counting_resource(close_error: ::IOError.new("close failed"))
      stream, = stream_over(resource: resource)
      typed = stream.typed { |_n, d| d }

      assert_raises(::IOError) { typed.close }
      assert_predicate(typed, :closed?)
    end
  end

  # SSE-26, SSE-40, SSE-23, SSE-25 and SSE-24 through the typed layer.
  class ViewTest < DexpaceTestCase
    include SSEFixtures

    test "SSE-26/SSE-40: the typed view is single-pass across both shapes and the raw stream's" do
      # #each, #values and the underlying Stream's own two shapes compete for ONE view, so a
      # caller cannot take a second view by switching shapes.
      stream, = stream_over
      typed = stream.typed { |_n, d| d }
      typed.values

      assert_raises(Dexpace::SSE::StreamStateError) { typed.values }
      assert_raises(Dexpace::SSE::StreamStateError) { typed.each { |_v| nil } }
      assert_raises(Dexpace::SSE::StreamStateError) { stream.events }
      assert_raises(Dexpace::SSE::StreamStateError) { stream.each { |_e| nil } }
    end

    test "SSE-26: a typed view after the raw view, or after close, fails loudly too" do
      stream, = stream_over
      stream.events

      assert_raises(Dexpace::SSE::StreamStateError) { stream.typed { |_n, d| d }.values }
      other, = stream_over
      other.close

      assert_raises(Dexpace::SSE::StreamStateError) { other.typed { |_n, d| d }.each { |_v| nil } }
    end

    test "SSE-23: the typed view is not a second closeable -- close delegates to the stream" do
      resource = counting_resource
      stream, = stream_over("data: a\n\n", resource: resource)
      typed = stream.typed { |_n, d| d }
      typed.close
      typed.close

      assert_predicate(stream, :closed?)
      assert_predicate(typed, :closed?)
      assert_equal(1, resource.closes)
      refute_kind_of(Dexpace::Closeable, typed)
      refute_kind_of(::Enumerable, typed)
    end

    test "SSE-25: a partial typed consume through the block form releases on exit" do
      resource = counting_resource
      stream, = stream_over(resource: resource)
      consume_one(stream.typed { |_n, d| d })

      assert_equal(1, resource.closes)
    end

    test "SSE-24: a fully consumed typed view releases without an explicit close" do
      resource = counting_resource
      stream, = stream_over(resource: resource)

      assert_equal(%w[a b c], stream.typed { |_n, d| d }.values.to_a)
      assert_equal(1, resource.closes)
    end

    test "SSE-25: an Enumerable method that stops early on #values releases, as on #events" do
      # first(n), take, find and an `each { break }` leave the external form through its block
      # and never reach the Stream's own ensure -- the raw enumerator is parked mid-#next -- so
      # the typed drive carries an ensure of its own, the mirror the design promises (review
      # round 0's R0-2: it had the rescue and not the ensure, closes 0 against the raw form's 1).
      resource = counting_resource
      stream, = stream_over(resource: resource)

      assert_equal(["a"], stream.typed { |_n, d| d }.values.first(1))
      assert_equal(1, resource.closes)
      assert_predicate(stream, :closed?)
      taken, taker = stream_over
      taken.typed { |_n, d| d }.values.take(2)

      assert_equal(1, taker.closes)
      found, finder = stream_over

      assert_equal("b", found.typed { |_n, d| d }.values.find { |value| value == "b" })
      assert_equal(1, finder.closes)
      broken, breaker = stream_over

      assert_equal("a", consume_one(broken.typed { |_n, d| d }.values))
      assert_equal(1, breaker.closes)
    end

    test "SSE-30: a release failure on a typed block-form break propagates, as the raw form's" do
      resource = counting_resource(close_error: ::IOError.new("close failed"))
      stream, = stream_over(resource: resource)

      assert_raises(::IOError) { stream.typed { |_n, d| d }.values.first(1) }
      assert_equal(1, resource.closes)
      assert_predicate(stream, :closed?)
    end

    test "the typed view cannot be constructed by a caller; Stream#typed is the one way in" do
      assert_raises(::NoMethodError) { Dexpace::SSE::TypedStream.new(stream: nil, mapper: nil, logger: nil) }
    end
  end
end
