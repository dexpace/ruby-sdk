# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_chunked"
require "dexpace"
require "stringio"

# IO-6, IO-11..IO-24, IO-37, IO-38, IO-41, IO-42, and design §10.2.
#
# StringIO and IO.pipe stand in for a real stream and are not stubs: they give genuine EOF, genuine
# blocking and the genuine IOError a closed handle raises. IO.pipe in particular is what makes the
# IO-38 test real rather than simulated -- a reader really does block.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: ownership
# here, then Bridge, Over, Close, Threads, Counts and Views below.
class DexpaceBufferedSourceTest < DexpaceTestCase
  # A pipe whose two ends are closed however the block leaves.
  module Pipes
    def pipe
      reader, writer = ::IO.pipe
      yield reader, writer
    ensure
      reader.close unless reader.nil? || reader.closed?
      writer.close unless writer.nil? || writer.closed?
    end
  end
  include Pipes

  # ---- IO-6: ownership -----------------------------------------------------------------------

  # IO-6: "the returned wrapper MUST take ownership of that stream: closing the wrapper closes the
  # underlying stream." There is deliberately no borrowing variant (P3-12).
  test "wrapping takes ownership: closing the source closes the wrapped stream" do
    stream = StringIO.new("abc")
    source = Dexpace::IO::BufferedSource.wrapping(stream)

    assert_predicate(source, :owns_upstream?)
    refute_predicate(source, :view?)
    source.close

    assert_predicate(stream, :closed?)
  end

  test "wrapping with a block closes on a normal exit and returns the block's value" do
    stream = StringIO.new("abc")

    result = Dexpace::IO::BufferedSource.wrapping(stream, &:read)

    assert_equal("abc", result)
    assert_predicate(stream, :closed?)
  end

  test "wrapping with a block closes on an exception too" do
    stream = StringIO.new("abc")

    assert_raises(RuntimeError) do
      Dexpace::IO::BufferedSource.wrapping(stream) { raise "boom" }
    end
    assert_predicate(stream, :closed?)
  end

  # IO-6's last sentence: "Wrapping a plain byte array owns no external resource."
  test "of_bytes owns nothing and takes an independent copy of the input" do
    original = +"abc"
    source = Dexpace::IO::BufferedSource.of_bytes(original)
    original << "def"

    refute_predicate(source, :owns_upstream?)
    assert_equal("abc", source.read)
  end

  test "of_bytes result is not affected by, and does not affect, the caller's String" do
    original = +"abc"
    source = Dexpace::IO::BufferedSource.of_bytes(original)

    assert_equal("abc", source.read)
    assert_equal("abc", original)
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::IO::BufferedSource.of_bytes(:sym) }
  end

  # R3's one stated exception, and it is design §3.1's rather than this phase's: .over takes no
  # ownership, because its callers are always downstream of something that already owns the
  # response. This is what removes the one 3a->3b edge that would have run backwards.
  test "over owns nothing and never closes what it wrapped" do
    closed = false
    body = Object.new
    body.define_singleton_method(:each) { |&block| block.call("ab") }
    body.define_singleton_method(:close) { closed = true }

    source = Dexpace::IO::BufferedSource.over(body)
    source.read
    source.close

    refute_predicate(source, :owns_upstream?)
    refute(closed)
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::IO::BufferedSource.over(Object.new) }
  end

  # R1's real mitigation, asserted rather than argued: core never writes is_a?(IO), so every one
  # of these works. A nominal test would be silently false inside `module Dexpace`.
  test "wrapping accepts a real IO, a StringIO and a bare readpartial-shaped object" do
    duck = Class.new do
      def initialize = @sent = false

      def readpartial(_maxlen, _outbuf = nil)
        raise ::EOFError if @sent

        @sent = true
        +"duck"
      end
    end.new

    pipe do |reader, writer|
      writer.write("pipe")
      writer.close

      assert_equal("pipe", Dexpace::IO::BufferedSource.wrapping(reader).read)
    end
    assert_equal("sio", Dexpace::IO::BufferedSource.wrapping(StringIO.new("sio")).read)
    assert_equal("duck", Dexpace::IO::BufferedSource.wrapping(duck).read)
  end

  test "wrapping rejects an object that reads no way at all" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::IO::BufferedSource.wrapping(Object.new)
    end

    assert_includes(error.message, "#readpartial")
  end

  # P3-11: ownership must not be settable through an unnamed argument, or a caller builds the
  # wrapper IO-6 forbids.
  test "new is private on the two wrapping classes and public on the two that own nothing" do
    assert_raises(::NoMethodError) { Dexpace::IO::BufferedSource.new }
    assert_raises(::NoMethodError) { Dexpace::IO::BufferedSink.new }
    assert_instance_of(Dexpace::IO::Buffer, Dexpace::IO::Buffer.new)
    assert_instance_of(Dexpace::IO::TeeSink, Dexpace::IO::TeeSink.new(primary: StringIO.new))
  end

  # ---- IO-16 and R4: the bridge, proved rather than restated ---------------------------------
  class Bridge < DexpaceTestCase
    include Pipes

    # THE bridge proof. This is the exact mechanism Net::HTTP#body_stream= uses:
    # Net::HTTP#send_request_with_body_stream is IO.copy_stream(f, sock). Not a mock of it.
    test "IO.copy_stream drives a wrapped source and the bytes arrive intact" do
      destination = StringIO.new(+"".b)

      pipe do |reader, writer|
        writer.write("héllo wörld" * 40)
        writer.close
        ::IO.copy_stream(Dexpace::IO::BufferedSource.wrapping(reader), destination)
      end

      assert_equal(("héllo wörld" * 40).b, destination.string)
    end

    # IO-6's second sentence -- "closing the bridge closes the owning source/sink" -- is trivially
    # true when the bridge IS the source, which is exactly why it gets an assertion: "trivially
    # true" is what a later refactor splitting the bridge into its own object would silently break.
    test "closing the source after IO.copy_stream closes the wrapped stream" do
      pipe do |reader, writer|
        writer.write("abc")
        writer.close
        source = Dexpace::IO::BufferedSource.wrapping(reader)
        ::IO.copy_stream(source, StringIO.new(+"".b))
        source.close

        assert_predicate(reader, :closed?)
      end
    end

    # A source with #read and no #readpartial is driven through read(len, buf) instead, which is
    # IO.copy_stream's own fallback; the source below has both, so both are the same object.
    test "IO.copy_stream drives a source over a body with no readpartial of its own" do
      destination = StringIO.new(+"".b)
      source = Dexpace::IO::BufferedSource.over(FakeChunked.new("ab", "", "cd"))

      ::IO.copy_stream(source, destination)

      assert_equal("abcd", destination.string)
    end

    # Verified fact 11: StringIO#read(n, buf)'s destination encoding changed at exactly Ruby 3.4
    # (ASCII-8BIT on 3.2.11, UTF-8 from 3.4.10) while IO#read preserves the destination's tag on
    # all three. This is a floor-straddler like URI::DEFAULT_PARSER, so it is pinned rather than
    # assumed: 3a never infers a tag from a destination or a source.
    test "a StringIO-backed source returns BINARY on every interpreter in the matrix" do
      source = Dexpace::IO::BufferedSource.wrapping(StringIO.new("héllo"))

      drained = source.read

      assert_equal(::Encoding::BINARY, drained.encoding)
      assert_equal("héllo".b, drained)
    end

    test "a pipe-backed source returns BINARY too" do
      pipe do |reader, writer|
        writer.write("héllo")
        writer.close

        assert_equal(::Encoding::BINARY,
                     Dexpace::IO::BufferedSource.wrapping(reader).read.encoding,)
      end
    end

    # A wrapped stream with only #read (no #readpartial) is filled through read(n), whose nil
    # is the second EOF sentinel #fill normalises.
    test "a read-only upstream's nil at EOF is normalised to the primitive's -1" do
      upstream = Object.new
      chunks = [+"ab", nil]
      upstream.define_singleton_method(:read) { |_n| chunks.shift }
      source = Dexpace::IO::BufferedSource.wrapping(upstream)

      assert_equal(2, source.read_into(+"".b, count: 8))
      assert_equal(-1, source.read_into(+"".b, count: 8))
      assert_equal(-1, source.read_into(+"".b, count: 8))
    end
  end

  # ---- §10.2 and .over -----------------------------------------------------------------------
  class Over < DexpaceTestCase
    # Verified fact 3: force_encoding on a frozen String raises FrozenError even when the target
    # encoding is already the string's own, and a Rack-style body's #each yields frozen literals.
    # String#b is the ingress idiom; force_encoding appears nowhere on this path.
    test "over survives a body that yields frozen literals, and stores them BINARY" do
      source = Dexpace::IO::BufferedSource.over(FakeChunked.frozen_utf8)

      drained = source.read

      assert_equal(::Encoding::BINARY, drained.encoding)
      assert_equal("héllo wörld".b, drained)
    end

    # Verified fact 4: appending a NON-ASCII UTF-8 String to a BINARY one silently retags the
    # result to UTF-8 while an ASCII-only one does not -- so an ASCII-only fixture would pass
    # under exactly the bug. Every encoding test in 3a therefore uses non-ASCII bytes.
    test "a non-ASCII chunk does not retag the buffer to UTF-8" do
      source = Dexpace::IO::BufferedSource.over(FakeChunked.new("é"))

      assert_equal(::Encoding::BINARY, source.read.encoding)
    end

    # A frozen BINARY chunk is kept without a copy; anything else is copied exactly once.
    test "over keeps an already-frozen BINARY chunk by identity and copies every other" do
      frozen_binary = "ab".b.freeze
      source = Dexpace::IO::BufferedSource.over(FakeChunked.new(frozen_binary, +"cd"))
      source.read_exactly(0)
      source.send(:ensure_buffered, 4)
      stored = source.instance_variable_get(:@dexpace_chunks)

      assert_same(frozen_binary, stored[0])
      assert_predicate(stored[1], :frozen?)
      assert_equal(::Encoding::BINARY, stored[1].encoding)
    end

    # .over preserves the wrapped body's own chunking, which is what BODY-17's byte-exact
    # mirroring needs. This is the plan's answer to the open question about #each's granularity.
    test "over preserves the wrapped body's chunk boundaries through each" do
      source = Dexpace::IO::BufferedSource.over(FakeChunked.new("ab", "cde", "f"))

      assert_equal(%w[ab cde f], source.each.to_a)
    end

    # IO-1's "at least 1 when byteCount>0 and the source is NOT exhausted". An empty chunk means
    # "no bytes this time", never "no bytes ever": Rack permits #each to yield "", and collapsing
    # the two truncates the body there -- silently, and with a well-formed short read that no
    # length check downstream would question. StopIteration is the only end-of-stream signal here.
    test "an empty chunk between two non-empty ones is not end of stream" do
      source = Dexpace::IO::BufferedSource.over(FakeChunked.new("ab", "", "cd"))

      assert_equal("abcd", source.read)
    end

    test "a leading empty chunk does not make the body look exhausted" do
      assert_equal("abc", Dexpace::IO::BufferedSource.over(FakeChunked.new("", "abc")).read)
    end

    test "an empty chunk truncates neither each nor read_exactly, and eof? stays false" do
      body = -> { FakeChunked.new("ab", "", "cd") }

      assert_equal(%w[ab cd], Dexpace::IO::BufferedSource.over(body.call).each.to_a)
      assert_equal("abcd", Dexpace::IO::BufferedSource.over(body.call).read_exactly(4))

      source = Dexpace::IO::BufferedSource.over(body.call)
      source.read_exactly(2)

      refute_predicate(source, :eof?)
    end

    test "over pulls on demand, so no read-ahead accumulates" do
      body = FakeChunked.new("ab", "cd", "ef")
      source = Dexpace::IO::BufferedSource.over(body)

      source.read_exactly(1)

      assert_equal(1, body.yielded)
    end

    # §7.1's residue, asserted rather than papered over: a source closed before exhaustion
    # abandons the enumerator, and an abandoned Enumerator never runs its ensure (verified on
    # 3.2.11, 3.4.10 and 4.0.6; #rewind does not run it either). Nothing core owns leaks,
    # because .over owns nothing -- the enumerator holds the caller's body, and the caller's body
    # is owned by whoever created it. .over's YARD block says so.
    test "closing an unexhausted over source leaves the wrapped body's own ensure unrun" do
      body = FakeChunked.new("ab", "cd", "ef")
      source = Dexpace::IO::BufferedSource.over(body)
      source.read_exactly(1)
      source.close

      refute_predicate(body, :ensure_ran)
    end

    test "draining an over source to exhaustion does run the body's ensure" do
      body = FakeChunked.new("ab", "cd")
      Dexpace::IO::BufferedSource.over(body).read

      assert_predicate(body, :ensure_ran)
    end

    test "a BufferedSource is itself a canonical body representation" do
      assert_respond_to(Dexpace::IO::BufferedSource.of_bytes("ab"), :each)
      assert_equal(["ab"], Dexpace::IO::BufferedSource.over(FakeChunked.new("ab")).to_enum.to_a)
    end
  end

  # ---- IO-41, IO-42: close ------------------------------------------------------------------
  class Close < DexpaceTestCase
    # IO-41: "a second (or later) close() MUST NOT throw, and the underlying resource MUST be
    # closed at most once."
    test "close is idempotent and closes the underlying resource at most once" do
      closes = 0
      stream = Object.new
      stream.define_singleton_method(:read) { |_n| nil }
      stream.define_singleton_method(:close) { closes += 1 }

      source = Dexpace::IO::BufferedSource.wrapping(stream)
      source.close
      source.close
      source.close

      assert_equal(1, closes)
    end

    # IO-42: "A buffered source/sink that wraps an external stream MUST reject read/write/flush/
    # emit attempts made after close() with an I/O error." P3-3: that error is phase 2's
    # Dexpace::ClosedError, whose first raise site is here.
    test "a stream-backed source rejects every read form after close" do
      source = Dexpace::IO::BufferedSource.wrapping(StringIO.new("abcdef"))
      source.close

      assert_raises(Dexpace::ClosedError) { source.read }
      assert_raises(Dexpace::ClosedError) { source.read_exactly(1) }
      assert_raises(Dexpace::ClosedError) { source.readpartial(1) }
      assert_raises(Dexpace::ClosedError) { source.read_into(+"".b, count: 1) }
      assert_raises(Dexpace::ClosedError) { source.read_into(+"".b, count: 0) }
      assert_raises(Dexpace::ClosedError) { source.eof? }
      assert_raises(Dexpace::ClosedError) { source.peek }
    end

    # The two directions of IO-42's asymmetry get two tests that fail in OPPOSITE ways, because
    # a single "it raises after close" test would pass over either error. This is the
    # stream-backed half; buffer_test.rb carries the in-memory half.
    test "the post-close failure is a state error and never an end-of-stream error" do
      source = Dexpace::IO::BufferedSource.of_bytes("abc")
      source.close

      error = assert_raises(Dexpace::ClosedError) { source.read }

      refute_kind_of(::EOFError, error)
      refute_kind_of(Dexpace::StreamError, error)
    end

    test "closed? stays public with the same arity after P3-6" do
      source = Dexpace::IO::BufferedSource.of_bytes("abc")

      assert_respond_to(source, :closed?)
      assert_equal(0, source.method(:closed?).arity)
      refute_predicate(source, :closed?)
      source.close

      assert_predicate(source, :closed?)
    end

    test "close drops the buffer, so a closed source retains nothing" do
      source = Dexpace::IO::BufferedSource.of_bytes("abcdef")
      source.read_exactly(1)
      source.close

      assert_empty(source.instance_variable_get(:@dexpace_chunks))
    end

    # A wrapped object with no #close is a legal upstream (a caller's own #readpartial-shaped
    # object); closing the source then releases only the buffer.
    test "closing a source over an upstream with no close is fine" do
      upstream = Object.new
      upstream.define_singleton_method(:readpartial) { |_n| raise ::EOFError }
      source = Dexpace::IO::BufferedSource.wrapping(upstream)

      assert_nil(source.close)
      assert_predicate(source, :closed?)
    end
  end

  # ---- IO-37, IO-38: the two threads on one flag ---------------------------------------------
  class Threads < DexpaceTestCase
    include Pipes

    # IO-37: "All streaming instances ... are single-threaded contracts". The proof that no lock
    # is held across a read is the LOCK'S ABSENCE, and it is testable: verified on all three
    # interpreters that a Thread::Mutex held across a fiber suspension raises ThreadError for a
    # second fiber of the same thread. So this test fails loudly under exactly the bug it exists
    # to catch, and it is driven with Fiber.new/Fiber.yield rather than a scheduler.
    test "two fibers of one thread interleave reads on one source without a ThreadError" do
      gate = Class.new do
        def initialize = @chunks = %w[ab cd ef gh]

        def readpartial(_maxlen, _outbuf = nil)
          raise ::EOFError if @chunks.empty?

          ::Fiber.yield
          +@chunks.shift
        end
      end.new
      source = Dexpace::IO::BufferedSource.wrapping(gate)
      read = []

      first = ::Fiber.new { read << source.read_exactly(2) }
      second = ::Fiber.new { read << source.read_exactly(2) }
      first.resume
      second.resume
      first.resume
      second.resume

      assert_equal(%w[ab cd], read)
    end

    # IO-38: "the CLOSE state of a source/buffer MUST be observable across threads to the slices
    # derived from it, so that a close on one thread reliably invalidates a slice being read on
    # another (no torn or stale reads)."
    #
    # Sequenced through a Thread::Queue handshake, never raced: phase 2's cancellation-stamp work
    # is the precedent for how a free-running race produces a flake nobody can reproduce. 3a's
    # design records that this passes with or without the lock on every CRuby row -- the
    # assertion that distinguishes mechanism from behaviour is the fiber-held-mutex test in
    # closeable_test.rb.
    test "a close on one thread invalidates a read blocked on another" do
      pipe do |reader, writer|
        source = Dexpace::IO::BufferedSource.wrapping(reader)
        inside = ::Thread::Queue.new
        outcome = ::Thread::Queue.new

        blocked = ::Thread.new do
          inside.push(:reading)
          begin
            source.read_exactly(4)
            outcome.push(:returned)
          rescue ::StandardError => error
            outcome.push(error)
          end
        end

        assert_equal(:reading, inside.pop)
        ::Thread.pass until blocked.status == "sleep" || !blocked.status
        source.close
        writer.close

        result = outcome.pop
        blocked.join

        # The blocked read fails loudly and never returns stale bytes. What it raises is Ruby's
        # own ::IOError ("stream closed in another thread"), forwarded unchanged -- IO-40's "MUST
        # NOT swallow OR duplicate the wrapped stream's cancellation/interrupt handling" honoured
        # by doing nothing to it. Every read AFTER the close is 3a's own Dexpace::ClosedError.
        refute_equal(:returned, result)
        assert_instance_of(::IOError, result)
        assert_raises(Dexpace::ClosedError) { source.read }
      end
    end

    test "a close on one thread invalidates a view being read on another" do
      source = Dexpace::IO::BufferedSource.of_bytes("abcdef")
      view = source.slice(offset: 0, count: 4)
      ready = ::Thread::Queue.new
      go = ::Thread::Queue.new
      outcome = ::Thread::Queue.new

      reader = ::Thread.new do
        ready.push(:ready)
        go.pop
        begin
          outcome.push(view.read)
        rescue ::StandardError => error
          outcome.push(error)
        end
      end

      assert_equal(:ready, ready.pop)
      source.close
      go.push(:go)
      result = outcome.pop
      reader.join

      assert_instance_of(Dexpace::ClosedError, result)
    end

    # IO-41 across threads: #release runs exactly once and both callers return.
    test "close called from two threads releases once and both callers return" do
      releases = ::Thread::Queue.new
      stream = Object.new
      stream.define_singleton_method(:read) { |_n| nil }
      stream.define_singleton_method(:close) { releases.push(:closed) }
      source = Dexpace::IO::BufferedSource.wrapping(stream)

      threads = Array.new(2) { ::Thread.new { source.close } }
      threads.each(&:join)

      assert_equal(1, releases.size)
    end
  end

  # ---- the count the upstream is asked for, and an IO-7-shaped round trip --------------------
  class Counts < DexpaceTestCase
    # Task 10's 2026-09-13 amendment. Phase 3b measured BufferedSource.wrapping(io) delivering ONE
    # BYTE per #read_into for any positive count: 200 000 bytes through 200 001 readpartial(1)
    # calls, ~0.21 s, on 3.2.11, 3.4.10 and 4.0.6 alike. Every IO requirement is met either way
    # -- IO-1 asks only for "at least 1" -- so no gate sees it and only this assertion does.
    test "wrapping passes the caller's own count through to the upstream" do
      asked = []
      upstream = Object.new
      upstream.define_singleton_method(:readpartial) do |want|
        asked << want
        raise ::EOFError if asked.size > 1

        "x" * want
      end

      Dexpace::IO::BufferedSource.wrapping(upstream) do |source|
        assert_equal(4096, source.read_into(+"".b, count: 4096))
      end

      assert_equal([4096], asked)
    end

    # #each and #drain_all have no caller count, so they carry READ_SEGMENT_BYTES instead of a 1.
    # Two asks: one that yields the chunk and one that finds the end.
    test "each and a count-less read ask the upstream for a segment, not a byte" do
      asked = []
      upstream = Object.new
      upstream.define_singleton_method(:readpartial) do |want|
        asked << want
        raise ::EOFError if asked.size > 1

        "y" * 10
      end

      Dexpace::IO::BufferedSource.wrapping(upstream) { |source| source.each { |_| nil } }

      assert_equal([64 * 1024, 64 * 1024], asked)
    end

    test "random BINARY chunks read back byte-for-byte in order through a wrapped stream" do
      sample(count: 32) do |rng|
        chunks = Array.new(rng.rand(1..6)) { rng.bytes(rng.rand(0..64)) }
        source = Dexpace::IO::BufferedSource.wrapping(StringIO.new(chunks.join.b))

        assert_equal(chunks.join.b, source.read)
      end
    end

    # A view over a wrapped stream drives the parent's fill and reads BINARY, on every row.
    test "a view over a StringIO-backed source reads ahead without consuming the parent" do
      source = Dexpace::IO::BufferedSource.wrapping(StringIO.new("héllo wörld"))

      assert_equal("héllo".b, source.slice(offset: 0, count: 6).read)
      assert_equal("héllo wörld".b, source.read)
    end
  end

  # ---- IO-1, IO-16, IO-19: a view over a LIVE stream returns what has arrived ------------------
  class Views < DexpaceTestCase
    include Pipes

    # Review round 0, R0-1: a view asked its parent to buffer `behind + count`, so a peek over a
    # pipe holding 10 bytes with the writer still open blocked on read_into(count: 100) where the
    # root returned the 10 at once. The pipe is what makes it real: a reader really does block.
    # If a view's read blocks for the count rather than the first byte, the watchdog closes the
    # writer after two seconds so this fails on `writer.closed?` instead of hanging the run.
    test "a view over a live pipe returns what has arrived, like the root" do
      pipe do |reader, writer|
        writer.write("0123456789")
        source = Dexpace::IO::BufferedSource.wrapping(reader)
        done = ::Thread::Queue.new
        watchdog = ::Thread.new { writer.close if done.pop(timeout: 2).nil? }
        dest = +"".b

        assert_equal(10, source.peek.read_into(dest, count: 100))
        assert_equal("0123456789".b, dest)
        assert_equal("0123456789".b, source.peek.readpartial(100))
        assert_equal("0123456789".b, source.peek.each.first)
        done.push(:done)
        watchdog.join

        refute_predicate(writer, :closed?)
        assert_equal("0123456789".b, source.read(10))
      end
    end

    # The plan's Task 10 amendment holds through a view: the upstream is asked for the view's
    # own count, and for a slice the bytes up to its offset on top, never for one byte.
    test "a view passes its own count through to the upstream, offset included" do
      asked = []
      upstream = Object.new
      upstream.define_singleton_method(:readpartial) do |want|
        asked << want
        raise ::EOFError if asked.size > 2

        "z" * want
      end
      source = Dexpace::IO::BufferedSource.wrapping(upstream)
      dest = +"".b

      assert_equal(100, source.peek.read_into(dest, count: 100))
      assert_equal(50, source.slice(offset: 150, count: 50).read_into(dest, count: 4096))
      assert_equal([100, 100], asked)
    end

    # The view constructor is internal (design: "internal -- no RBS signature, no YARD block"),
    # so a caller cannot reach it by name; #peek and #slice are the only way to a view.
    test "the view constructor is a private class method, not public surface" do
      assert_raises(NoMethodError) do
        Dexpace::IO::BufferedSource.__dexpace_view(parent: nil, pin: 0, window: nil)
      end
      refute_includes(Dexpace::IO::BufferedSource.singleton_methods, :__dexpace_view)
    end
  end
end
