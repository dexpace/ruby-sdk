# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_sink"
require "dexpace"
require "stringio"

# IO-4, IO-5, IO-6, IO-16..IO-18, IO-41, IO-42.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: ownership
# and the bridge here, then Staging and Close below.
class DexpaceBufferedSinkTest < DexpaceTestCase
  # ---- IO-6: ownership -----------------------------------------------------------------------

  test "wrapping takes ownership: closing the sink closes the wrapped stream" do
    stream = StringIO.new(+"".b)
    sink = Dexpace::IO::BufferedSink.wrapping(stream)
    sink.write("ab")
    sink.close

    assert_predicate(stream, :closed?)
  end

  test "wrapping with a block closes on any exit path and returns the block's value" do
    stream = StringIO.new(+"".b)

    result = Dexpace::IO::BufferedSink.wrapping(stream) { |sink| sink.write("abc") }

    assert_equal(3, result)
    assert_predicate(stream, :closed?)
  end

  test "wrapping with a block closes when the block raises" do
    stream = StringIO.new(+"".b)

    assert_raises(RuntimeError) { Dexpace::IO::BufferedSink.wrapping(stream) { raise "boom" } }
    assert_predicate(stream, :closed?)
  end

  # R1's mitigation on the write side: respond_to?, never is_a?.
  test "wrapping accepts anything that responds to write" do
    assert_equal(2, Dexpace::IO::BufferedSink.wrapping(FakeSink.new).write("ab"))
  end

  test "wrapping rejects an object with no write" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::IO::BufferedSink.wrapping(Object.new)
    end

    assert_includes(error.message, "#write")
  end

  # ---- IO-16: the writable bridge ------------------------------------------------------------

  # IO-16's symmetric half: IO.copy_stream needs a destination whose #write returns the byte count.
  test "IO.copy_stream writes into a wrapped sink" do
    stream = StringIO.new(+"".b)
    sink = Dexpace::IO::BufferedSink.wrapping(stream)

    ::IO.copy_stream(StringIO.new("héllo wörld" * 40), sink)

    assert_equal(("héllo wörld" * 40).b, stream.string)
  end

  test "a non-ASCII write does not retag the underlying stream's buffer to UTF-8" do
    stream = StringIO.new(+"".b)
    Dexpace::IO::BufferedSink.wrapping(stream).write("é")

    assert_equal(::Encoding::BINARY, stream.string.encoding)
  end

  test "IO.copy_stream into a wrapped pipe end delivers every byte" do
    reader, writer = ::IO.pipe
    sink = Dexpace::IO::BufferedSink.wrapping(writer)

    ::IO.copy_stream(StringIO.new("héllo".b), sink)
    sink.close

    assert_predicate(writer, :closed?)
    assert_equal("héllo".b, reader.read.b)
  ensure
    reader&.close
  end

  # ---- IO-4, IO-17 over a real destination ---------------------------------------------------

  test "write_from moves bytes out of a Buffer and into the underlying stream" do
    stream = StringIO.new(+"".b)
    buffer = Dexpace::IO::Buffer.new
    buffer.write("abcdef")

    Dexpace::IO::BufferedSink.wrapping(stream).write_from(buffer, count: 4)

    assert_equal("abcd", stream.string)
    assert_equal("ef", buffer.read)
  end

  test "write_all pumps a BufferedSource into the underlying stream and returns the total" do
    stream = StringIO.new(+"".b)
    source = Dexpace::IO::BufferedSource.of_bytes("héllo wörld")

    total = Dexpace::IO::BufferedSink.wrapping(stream).write_all(source)

    assert_equal("héllo wörld".bytesize, total)
    assert_equal("héllo wörld".b, stream.string)
  end

  # ---- the staging buffer, the short-write rule and IO-5/IO-18 -------------------------------
  class Staging < DexpaceTestCase
    # IO-17's zero-read rule applied symmetrically on the write side: an underlying #write that
    # accepted fewer bytes than it was handed is a sink-contract violation. No real Ruby stream
    # produces this on a blocking write, which is why FakeSink is scriptable to.
    test "an underlying write that accepts fewer bytes than it was handed is an I/O error" do
      underlying = FakeSink.new(1)
      sink = Dexpace::IO::BufferedSink.wrapping(underlying)

      error = assert_raises(Dexpace::StreamError) { sink.write("abcd") }

      assert_includes(error.message, "1")
      assert_includes(error.message, "4")
    end

    test "a failed underlying write leaves no staged bytes to prepend to the next one" do
      underlying = FakeSink.new(::RuntimeError.new("boom"))
      sink = Dexpace::IO::BufferedSink.wrapping(underlying)

      assert_raises(::RuntimeError) { sink.write("abc") }
      sink.write("def")

      assert_equal("def", underlying.written)
    end

    test "an underlying write that returns no count is taken at its word" do
      underlying = FakeSink.new(nil)
      underlying.define_singleton_method(:write) do |*strings|
        @writes << strings.join.b
        :ok
      end
      sink = Dexpace::IO::BufferedSink.wrapping(underlying)

      assert_equal(3, sink.write("abc"))
      assert_equal("abc", underlying.written)
    end

    # IO-18: emit pushes one level "without forcing a system-level flush", flush forces bytes all
    # the way out. The distinction is real here rather than notional: emit never calls the
    # underlying #flush and flush always does.
    test "emit does not call the underlying flush and flush does" do
      flushes = 0
      underlying = FakeSink.new
      underlying.define_singleton_method(:flush) { flushes += 1 }
      sink = Dexpace::IO::BufferedSink.wrapping(underlying)

      sink.write("ab")
      sink.emit

      assert_equal(0, flushes)

      sink.flush

      assert_equal(1, flushes)
    end

    test "emit and flush return self, and flush tolerates an underlying stream with no flush" do
      sink = Dexpace::IO::BufferedSink.wrapping(FakeSink.new)

      assert_same(sink, sink.emit)
      assert_same(sink, sink.flush)
    end

    # The staging buffer is empty between calls: every delivered String pushes through at once,
    # so the underlying stream sees one call per String, in order, and never a coalesced tail.
    test "each delivered String reaches the underlying stream as its own call, in order" do
      underlying = FakeSink.new
      sink = Dexpace::IO::BufferedSink.wrapping(underlying)
      sink.write("ab", "cd")
      sink.write("ef")

      assert_equal(%w[ab cd ef], underlying.writes)
    end
  end

  # ---- IO-41, IO-42 --------------------------------------------------------------------------
  class Close < DexpaceTestCase
    test "close is idempotent and closes the underlying stream at most once" do
      closes = 0
      underlying = FakeSink.new
      underlying.define_singleton_method(:close) { closes += 1 }
      sink = Dexpace::IO::BufferedSink.wrapping(underlying)

      sink.close
      sink.close

      assert_equal(1, closes)
    end

    # IO-42: "MUST reject read/write/flush/emit attempts made after close() with an I/O error".
    test "a stream-backed sink rejects every write form after close" do
      sink = Dexpace::IO::BufferedSink.wrapping(FakeSink.new)
      sink.close

      assert_raises(Dexpace::ClosedError) { sink.write("ab") }
      assert_raises(Dexpace::ClosedError) { sink.write_utf8("ab") }
      assert_raises(Dexpace::ClosedError) { sink.write_string("ab", encoding: "UTF-8") }
      one_byte = Dexpace::IO::BufferedSource.of_bytes("a")
      assert_raises(Dexpace::ClosedError) { sink.write_all(one_byte) }
      assert_raises(Dexpace::ClosedError) { sink.write_from(Dexpace::IO::Buffer.new, count: 0) }
      assert_raises(Dexpace::ClosedError) { sink.emit }
      assert_raises(Dexpace::ClosedError) { sink.flush }
    end

    test "the post-close failure is a state error and never an end-of-stream error" do
      sink = Dexpace::IO::BufferedSink.wrapping(FakeSink.new)
      sink.close

      error = assert_raises(Dexpace::ClosedError) { sink.write("ab") }

      refute_kind_of(::EOFError, error)
      refute_kind_of(Dexpace::StreamError, error)
    end

    test "close flushes what is staged before closing the underlying stream" do
      stream = StringIO.new(+"".b)
      sink = Dexpace::IO::BufferedSink.wrapping(stream)
      sink.write("abc")
      sink.close

      assert_equal("abc", stream.string)
    end

    test "closing a sink over an underlying stream with no close is fine" do
      sink = Dexpace::IO::BufferedSink.wrapping(FakeSink.new)

      assert_nil(sink.close)
      assert_predicate(sink, :closed?)
    end

    # Phase 2's rule: a fake that has drifted from the seam is a suite that proves nothing.
    # FakeSink implements #write and nothing else, so it IS Dexpace::IO::_Sink.
    test "FakeSink is exactly the _Sink shape" do
      fake = FakeSink.new

      assert_respond_to(fake, :write)
      assert_equal(4, fake.write("abcd"))
      assert_equal("abcd", fake.written)
    end
  end
end
