# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# IO-1, IO-2, IO-3, IO-9, IO-11..IO-16, IO-19..IO-24, and §10.2's #each.
#
# Written against a trivial in-test includer that supplies #fill from a fixed chunk list, so the
# read vocabulary is exercised with no upstream at all. BufferedSource's own suite covers the same
# vocabulary over a real stream.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# primitive here, then Typed, Ceiling, Lines, Bridge, Each, Views, ViewFills, ViewLifecycle and
# Includer below.
class DexpaceTypedReadsTest < DexpaceTestCase
  # The Ruby shape of the reference's BufferedSource interface: supply #fill, get everything.
  class Scripted
    include Dexpace::IO::TypedReads
    include Dexpace::Closeable

    attr_reader :fills

    def initialize(*chunks)
      @pending = chunks
      @fills = 0
      initialize_closeable(owned: true)
      initialize_typed_reads
    end

    private

    def fill(_min_bytes)
      @fills += 1
      chunk = @pending.shift
      return 0 if chunk.nil?

      store_append(chunk)
    end

    # IO-22: an includer's #release invalidates every view derived from it. Buffer and
    # BufferedSource both do exactly this.
    def release
      dexpace_release_views
    end
  end

  # One shared factory for every class below, so every source under test is shaped the same.
  module Sources
    def source(*chunks)
      Scripted.new(*chunks)
    end
  end
  include Sources

  # ---- IO-1, IO-2, IO-3: the primitive -------------------------------------------------------

  # IO-1: "MUST append the bytes it reads to the TAIL of the caller-provided destination buffer
  # (never overwrite existing content)".
  test "read_into appends to the tail and never overwrites" do
    dest = +"seed".b

    transferred = source("abc").read_into(dest, count: 3)

    assert_equal(3, transferred)
    assert_equal("seedabc", dest)
  end

  # IO-1's four return values, and the -1 sentinel rather than Ruby's nil: IO-17's pump reads it,
  # and a foreign source implementing IO-1 literally would return it.
  test "read_into returns -1 when the source is exhausted before any byte" do
    assert_equal(-1, source.read_into(+"".b, count: 4))
  end

  test "read_into never returns more than count" do
    assert_equal(2, source("abcdef").read_into(+"".b, count: 2))
  end

  # IO-2: "A read of byteCount==0 MUST return 0 and MUST NOT report end-of-stream (-1), even when
  # the source is already exhausted." Ruby's own readers do not collapse this, but IO-2 is a
  # statement about 3a's surface.
  test "read_into returns 0 for a zero count on an exhausted source, never -1" do
    exhausted = source
    exhausted.read_into(+"".b, count: 1)

    assert_equal(0, exhausted.read_into(+"".b, count: 0))
  end

  test "read_into with a zero count touches neither the buffer nor the upstream" do
    subject = source("abc")

    assert_equal(0, subject.read_into(+"".b, count: 0))
    assert_equal(0, subject.fills)
  end

  test "read_into fills at most once before serving, and serves from the buffer after that" do
    subject = source("ab", "cd")

    assert_equal(2, subject.read_into(+"".b, count: 4))
    assert_equal(1, subject.fills)
  end

  # Task 10's 2026-09-13 amendment, seen from the vocabulary's side: the count the caller asked
  # for is the count the fill hook receives, so a wrapping source can ask its upstream for it.
  test "read_into hands its own count to the fill hook" do
    asked = []
    subject = Class.new(Scripted) do
      define_method(:fill) do |min_bytes|
        asked << min_bytes
        super(min_bytes)
      end
    end.new("abc")

    subject.read_into(+"".b, count: 4096)

    assert_equal([4096], asked)
  end

  # IO-3: rejected BEFORE any I/O and with no partial side effect.
  class Rejections < DexpaceTestCase
    include Sources

    test "read_into rejects a negative count naming the argument, before any I/O" do
      subject = source("abc")

      error = assert_raises(Dexpace::InvalidArgumentError) { subject.read_into(+"".b, count: -1) }

      assert_includes(error.message, "count")
      assert_includes(error.message, "-1")
      assert_equal(0, subject.fills)
      assert_equal("abc", subject.read_exactly(3))
    end

    test "read_into rejects a non-Integer count" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        source("abc").read_into(+"".b, count: 2.5)
      end

      assert_includes(error.message, "count")
    end

    # A UTF-8 destination is rejected because appending a non-ASCII payload to a BINARY String
    # silently retags the RESULT to UTF-8 while an ASCII-only one does not, so the destination's
    # final tag would depend on the payload's content.
    test "read_into rejects a non-BINARY destination before any I/O" do
      subject = source("abc")

      error = assert_raises(Dexpace::InvalidArgumentError) { subject.read_into(+"", count: 3) }

      assert_includes(error.message, "ASCII-8BIT")
      assert_equal(0, subject.fills)
    end

    # A FrozenError from deep inside is a crash, not a rejection.
    test "read_into rejects a frozen destination before any I/O" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        source("abc").read_into("seed".b.freeze, count: 3)
      end

      assert_includes(error.message, "frozen")
    end

    test "read_into rejects a destination that is not a String" do
      assert_raises(Dexpace::InvalidArgumentError) { source("abc").read_into(:nope, count: 1) }
    end
  end

  # ---- IO-11..IO-13, IO-15: the typed reads --------------------------------------------------
  class Typed < DexpaceTestCase
    include Sources

    test "read_exactly returns exactly count bytes across a chunk boundary" do
      assert_equal("abcd", source("ab", "cd", "ef").read_exactly(4))
    end

    # IO-12: "MUST NOT return a short result". And it consumes nothing when it raises, so the
    # source is still usable -- the no-partial-side-effect rule.
    test "read_exactly raises at end of stream and consumes nothing" do
      subject = source("abc")

      assert_raises(Dexpace::EndOfStreamError) { subject.read_exactly(4) }
      assert_equal("abc", subject.read_exactly(3))
    end

    test "read_exactly(0) is an empty BINARY String" do
      result = source.read_exactly(0)

      assert_equal("", result)
      assert_equal(::Encoding::BINARY, result.encoding)
    end

    test "read_exactly returns BINARY and never a frozen store chunk" do
      result = source("héllo".b).read_exactly(3)

      assert_equal(::Encoding::BINARY, result.encoding)
      refute_predicate(result, :frozen?)
    end

    test "readbyte returns an unsigned 0..255 and raises at end of stream" do
      subject = source("\xFF".b)

      assert_equal(255, subject.readbyte)
      assert_raises(Dexpace::EndOfStreamError) { subject.readbyte }
    end

    test "getbyte returns nil at end of stream, which is Ruby's own spelling" do
      subject = source("A")

      assert_equal(65, subject.getbyte)
      assert_nil(subject.getbyte)
    end

    # IO-11: readByteArray() with no count returns all remaining bytes, and an empty result when
    # already exhausted.
    test "read with no length drains everything and returns an empty String at end of stream" do
      subject = source("ab", "cd")

      assert_equal("abcd", subject.read)
      assert_equal("", subject.read)
    end

    # IO-15, including the explicit "skip(0) MUST be a no-op even at/after EOF".
    test "skip advances past exactly count bytes" do
      subject = source("abcdef")
      subject.skip(2)

      assert_equal("cdef", subject.read)
    end

    test "skip raises when fewer bytes remain, and skip(0) is a no-op at and after EOF" do
      subject = source("ab")

      assert_raises(Dexpace::EndOfStreamError) { subject.skip(5) }
      subject.read

      assert_nil(subject.skip(0))
    end

    test "skip spans a chunk boundary and consumes nothing when it raises" do
      subject = source("ab", "cd")

      assert_raises(Dexpace::EndOfStreamError) { subject.skip(5) }
      subject.skip(3)

      assert_equal("d", subject.read)
    end

    test "eof? is false while bytes remain and true once they are gone" do
      subject = source("a")

      refute_predicate(subject, :eof?)
      subject.read_exactly(1)

      assert_predicate(subject, :eof?)
    end

    # Phase 1's finding: Minitest's assert_predicate sends past `private` on the 3.2 floor, so
    # visibility is asserted with respond_to?.
    test "eof? is public and the hooks are not" do
      subject = source("a")

      assert_respond_to(subject, :eof?)
      refute_respond_to(subject, :fill)
      refute_respond_to(subject, :store_append)
      refute_respond_to(subject, :dexpace_release_views)
    end
  end

  # ---- IO-13: the explicit-charset reads -----------------------------------------------------
  class Charsets < DexpaceTestCase
    include Sources

    # IO-13, and the only decode in 3a is a retag: no replacement policy and no charset default,
    # because HTTP-42's single decode boundary is 3b's Response#body_string.
    test "read_utf8 retags the drained bytes as UTF-8, non-ASCII round trip" do
      result = source("héllo".b).read_utf8

      assert_equal(::Encoding::UTF_8, result.encoding)
      assert_equal("héllo", result)
    end

    # count is a BYTE count, not a character count -- P3-9's keyword, and the design's own word.
    test "read_utf8 takes a byte count, not a character count" do
      assert_equal(2, source("héllo".b).read_utf8(count: 2).bytesize)
    end

    test "read_string retags with the encoding the caller named" do
      result = source("caf\xE9".b).read_string(::Encoding::ISO_8859_1)

      assert_equal(::Encoding::ISO_8859_1, result.encoding)
      assert_equal("café", result.encode(::Encoding::UTF_8))
    end

    test "read_string accepts an encoding name and rejects an unknown one" do
      assert_equal(::Encoding::UTF_8, source("ab").read_string("UTF-8").encoding)
      error = assert_raises(Dexpace::InvalidArgumentError) { source("ab").read_string("no-such") }

      assert_includes(error.message, "no-such")
    end

    test "read_string rejects the encoding before it touches the stream" do
      subject = source("ab")

      assert_raises(Dexpace::InvalidArgumentError) { subject.read_string("no-such") }
      assert_equal(0, subject.fills)
    end

    test "read_string with a count raises at end of stream rather than returning short" do
      assert_raises(Dexpace::EndOfStreamError) { source("ab").read_string("UTF-8", count: 5) }
    end

    test "read_string validates nothing: an invalid sequence is the caller's question" do
      result = source("\xFF".b).read_utf8

      assert_equal(::Encoding::UTF_8, result.encoding)
      refute_predicate(result, :valid_encoding?)
    end
  end

  # ---- IO-9: the ceiling ---------------------------------------------------------------------
  class Ceiling < DexpaceTestCase
    include Sources

    # The guard is checked against the requested or known count BEFORE anything is allocated, so
    # these refuse while allocating nothing at all.
    test "read_exactly refuses a count over the ceiling without allocating" do
      subject = source("ab")

      error = assert_raises(Dexpace::StreamError) do
        subject.read_exactly(Dexpace::IO::MAX_MATERIALIZED_BYTES + 1)
      end

      assert_includes(error.message, "MAX_MATERIALIZED_BYTES")
      assert_includes(error.message, "#read_into")
      assert_equal(0, subject.fills)
    end

    test "read_string and read_utf8 refuse a count over the ceiling" do
      over = Dexpace::IO::MAX_MATERIALIZED_BYTES + 1

      assert_raises(Dexpace::StreamError) { source("ab").read_string("UTF-8", count: over) }
      assert_raises(Dexpace::StreamError) { source("ab").read_utf8(count: over) }
    end

    # IO-21 makes over-range slice CONSTRUCTION lazy, so the ceiling fires on the read and never
    # on the construction (P3-4). This asserts exactly that ordering.
    test "an over-ceiling slice constructs successfully and refuses on the read" do
      subject = source("ab")
      view = subject.slice(offset: 0, count: Dexpace::IO::MAX_MATERIALIZED_BYTES + 1)

      assert_instance_of(Dexpace::IO::BufferedSource, view)
      assert_raises(Dexpace::StreamError) { view.read }
    end

    test "a slice inside the ceiling drains normally" do
      assert_equal("ab", source("ab").slice(offset: 0, count: 1024).read)
    end
  end

  # ---- IO-14: the line machine ---------------------------------------------------------------
  class Lines < DexpaceTestCase
    include Sources

    test "read_line_utf8 treats \\n as a terminator and does not return it" do
      subject = source("one\ntwo\n")

      assert_equal("one", subject.read_line_utf8)
      assert_equal("two", subject.read_line_utf8)
      assert_nil(subject.read_line_utf8)
    end

    test "read_line_utf8 treats \\r\\n as a terminator" do
      assert_equal("one", source("one\r\ntwo").read_line_utf8)
    end

    # IO-14: "a lone '\\r' not followed by '\\n' MUST be kept as part of the line's content".
    test "read_line_utf8 keeps a lone carriage return as content" do
      assert_equal("a\rb", source("a\rb\n").read_line_utf8)
    end

    test "read_line_utf8 returns a final unterminated line as-is" do
      subject = source("tail")

      assert_equal("tail", subject.read_line_utf8)
      assert_nil(subject.read_line_utf8)
    end

    test "read_line_utf8 returns nil when exhausted before any byte" do
      assert_nil(source.read_line_utf8)
    end

    test "read_line_utf8 returns an empty line for a bare terminator" do
      assert_equal("", source("\nx").read_line_utf8)
    end

    test "read_line_utf8 spans chunk boundaries and returns UTF-8" do
      subject = source("hél".b, "lo\nrest")

      line = subject.read_line_utf8

      assert_equal(::Encoding::UTF_8, line.encoding)
      assert_equal("héllo", line)
    end

    # The terminator split across two chunks: the "\\r" arrives, the "\\n" has not yet.
    test "read_line_utf8 sees a CR and LF split across chunks as one terminator" do
      subject = source("ab\r", "\ncd")

      assert_equal("ab", subject.read_line_utf8)
      assert_equal("cd", subject.read_line_utf8)
    end

    test "read_line_utf8 consumes the terminator, so the next read starts after it" do
      subject = source("ab\r\ncd")
      subject.read_line_utf8

      assert_equal("cd", subject.read)
    end

    # A bounded property test (styleguide 11.7, phase 0's #sample). The generator mixes every
    # terminator IO-14 names, so the machine is exercised on inputs nobody wrote by hand.
    test "read_line_utf8 reconstructs any mix of terminators" do
      # No pool entry ends with a carriage return, because "x\\r" + "\\n" is a \\r\\n terminator by
      # IO-14 and would make the generator, not the machine, wrong.
      pool = ["", "a", "ab", "a\rb", "\rx", "x\ry", "é", "hé\rllo"].freeze

      sample(count: 48) do |rng|
        lines = Array.new(rng.rand(1..5)) { pool.sample(random: rng) }
        terminators = Array.new(lines.length) { ["\n", "\r\n"].sample(random: rng) }
        text = lines.zip(terminators).map(&:join).join
        expected = lines.dup
        if rng.rand(2).zero?
          text = text[0...-terminators.last.length]
          expected.pop if expected.last.empty?
        end

        subject = source(*text.b.chars.each_slice(rng.rand(1..4)).map(&:join))
        read = []
        while (line = subject.read_line_utf8)
          read << line
        end

        assert_equal(expected, read)
      end
    end
  end

  # ---- IO-16: the host-native bridge ---------------------------------------------------------
  class Bridge < DexpaceTestCase
    include Sources

    # THE assertion the whole sub-phase turns on. IO.copy_stream hands #readpartial ONE buffer
    # that it reuses on every call and expects overwritten; IO-1's primitive appends. Both are
    # asserted here against the same non-empty BINARY buffer in one test, so a later
    # "simplification" that merges them turns red.
    test "read overwrites outbuf while read_into appends to it" do
      buffer = +"seed".b

      source("abcd").read(2, buffer)

      assert_equal("ab", buffer)

      source("wxyz").read_into(buffer, count: 2)

      assert_equal("abwx", buffer)
    end

    test "readpartial overwrites outbuf too" do
      buffer = +"seed".b

      source("abcd").readpartial(2, buffer)

      assert_equal("ab", buffer)
    end

    # P3-2: the bridge signals end of stream the host-native way, because IO-16's own word is
    # "host-native" and -1 is the reference host's InputStream convention.
    test "read returns nil at end of stream for a positive length, and clears outbuf" do
      buffer = +"seed".b

      assert_nil(source.read(4, buffer))
      assert_equal("", buffer)
    end

    test "readpartial raises Dexpace::EndOfStreamError at end of stream" do
      assert_raises(Dexpace::EndOfStreamError) { source.readpartial(4) }
    end

    # P3-13. Ruby's own readers disagree with each other and across the supported floor:
    # ::IO#read PRESERVES the destination's tag on 3.2.11, 3.4.10 and 4.0.6, while StringIO#read
    # changed at exactly Ruby 3.4 -- ASCII-8BIT on 3.2.11, UTF-8 from 3.4.10. 3a pins BINARY
    # instead, so the answer is the same on every matrix row and behind every backing stream.
    # IO.copy_stream does not care, which is what keeps the bridge claim true.
    test "read and readpartial leave outbuf tagged BINARY whatever it arrived as" do
      utf8_buffer = +""
      source("héllo".b).read(2, utf8_buffer)

      assert_equal(::Encoding::BINARY, utf8_buffer.encoding)

      other = +""
      source("héllo".b).readpartial(2, other)

      assert_equal(::Encoding::BINARY, other.encoding)
    end

    test "read(0) is an empty String and readpartial(0) never raises" do
      assert_equal("", source.read(0))
      assert_equal("", source.readpartial(0))
    end

    # Ruby's own split, which is what makes the bridge a bridge: #read(n) keeps filling until it
    # has n bytes or the stream ends, while #readpartial returns what is already available.
    test "read fills up to length while readpartial returns what is available" do
      assert_equal("abcd", source("ab", "cd").read(4))
      assert_equal("ab", source("ab", "cd").readpartial(4))
    end

    test "read returns a short result at end of stream and nil only when nothing remained" do
      subject = source("ab")

      assert_equal("ab", subject.read(4))
      assert_nil(subject.read(4))
    end

    test "readpartial hands its maxlen to the fill hook and read rejects a negative length" do
      asked = []
      subject = Class.new(Scripted) do
        define_method(:fill) do |min_bytes|
          asked << min_bytes
          super(min_bytes)
        end
      end.new("abc")
      subject.readpartial(512)

      assert_equal([512], asked)
      assert_raises(Dexpace::InvalidArgumentError) { subject.read(-1) }
      assert_raises(Dexpace::InvalidArgumentError) { subject.readpartial(-1) }
    end
  end

  # ---- §10.2: #each --------------------------------------------------------------------------
  class Each < DexpaceTestCase
    include Sources

    # The granularity is whatever the upstream produced, because .over must preserve the wrapped
    # body's own chunking for BODY-17's byte-exact mirroring to mean what it says.
    test "each yields the upstream's own chunks, in order, tagged BINARY" do
      chunks = []
      encodings = []

      source("ab", "cde", "f").each do |chunk|
        chunks << chunk.dup
        encodings << chunk.encoding
      end

      assert_equal(%w[ab cde f], chunks)
      assert_equal([::Encoding::BINARY] * 3, encodings)
    end

    test "each without a block returns an Enumerator" do
      assert_kind_of(::Enumerator, source("ab").each)
      assert_equal(%w[ab cd], source("ab", "cd").each.to_a)
    end

    test "each resumes from the cursor when bytes were already consumed" do
      subject = source("abcd", "ef")
      subject.read_exactly(1)

      assert_equal(%w[bcd ef], subject.each.to_a)
    end

    test "each consumes what it yields, so a second pass yields nothing" do
      subject = source("ab", "cd")
      subject.each { |_| nil }

      assert_empty(subject.each.to_a)
      assert_predicate(subject, :eof?)
    end

    # The two count-less readers ask the fill hook for a segment, never for one byte (Task 10's
    # 2026-09-13 amendment); 64 KiB is READ_SEGMENT_BYTES, private and not NFR-4 surface.
    test "each and a count-less read ask the fill hook for a segment, not a byte" do
      asked = []
      subject = Class.new(Scripted) do
        define_method(:fill) do |min_bytes|
          asked << min_bytes
          super(min_bytes)
        end
      end.new("ab")
      subject.each { |_| nil }
      subject.read

      assert_equal([64 * 1024, 64 * 1024, 64 * 1024], asked)
    end
  end

  # ---- IO-19..IO-21, IO-23: the views' shape -------------------------------------------------
  class Views < DexpaceTestCase
    include Sources

    # IO-19: "a non-consuming view over the whole remaining source such that reads from the peek
    # view do not advance the original source's cursor".
    test "peek does not advance the parent cursor" do
      subject = source("abcdef")

      assert_equal("abcdef", subject.peek.read)
      assert_equal("abcdef", subject.read)
    end

    test "peek is a BufferedSource in view mode, not a new public type" do
      view = source("ab").peek

      assert_instance_of(Dexpace::IO::BufferedSource, view)
      assert_predicate(view, :view?)
      refute_predicate(view, :owns_upstream?)
    end

    # IO-19's "whole remaining source" reaches past what is currently buffered: the view drives
    # the parent's fill (three chunks, plus the probes that find the end) without advancing the
    # parent's cursor.
    test "peek reaches bytes the parent has not yet pulled from its upstream" do
      subject = source("ab", "cd", "ef")

      assert_equal("abcdef", subject.peek.read)
      assert_operator(subject.fills, :>=, 3)
      assert_equal("abcdef", subject.read)
    end

    # IO-20.
    test "slice exposes at most count bytes starting offset bytes ahead of the cursor" do
      subject = source("abcdef")

      assert_equal("cd", subject.slice(offset: 2, count: 2).read)
      assert_equal("abcdef", subject.read)
    end

    test "reading past a slice window behaves as end of window" do
      subject = source("abcdef")
      view = subject.slice(offset: 0, count: 2)

      assert_equal("ab", view.read)
      assert_equal("", view.read)
      assert_raises(Dexpace::EndOfStreamError) { view.read_exactly(1) }
      assert_nil(view.read_line_utf8)
      assert_predicate(view, :eof?)
    end

    # IO-21: overflow is LAZY. Construction succeeds; the overflow surfaces on first read.
    test "a slice whose offset exceeds the source constructs successfully and is empty on read" do
      subject = source("abc")
      view = subject.slice(offset: 99, count: 5)

      assert_instance_of(Dexpace::IO::BufferedSource, view)
      assert_equal("", view.read)
      assert_nil(view.read_line_utf8)
      assert_raises(Dexpace::EndOfStreamError) { view.readbyte }
    end

    test "slice rejects a negative offset or count eagerly at construction" do
      subject = source("abc")

      assert_raises(Dexpace::InvalidArgumentError) { subject.slice(offset: -1, count: 1) }
      assert_raises(Dexpace::InvalidArgumentError) { subject.slice(offset: 0, count: -1) }
      assert_raises(Dexpace::InvalidArgumentError) { subject.slice(offset: 0.5, count: 1) }
    end

    # IO-23: mutually independent cursors and budgets.
    test "two slices of one source are mutually independent" do
      subject = source("abcdef")
      first = subject.slice(offset: 0, count: 4)
      second = subject.slice(offset: 0, count: 4)

      assert_equal("ab", first.read(2))
      assert_equal("abcd", second.read)
      assert_equal("cd", first.read)
    end

    # IO-23: "a slice-of-a-slice MUST compose offsets additively and cap its window at the outer
    # slice's remaining bytes".
    test "a slice of a slice composes additively and is capped by the outer window" do
      subject = source("abcdefgh")
      outer = subject.slice(offset: 1, count: 4)

      assert_equal("cd", outer.slice(offset: 1, count: 2).read)
      assert_equal("cde", outer.slice(offset: 1, count: 99).read)
    end

    test "a view's own views compose over a partially read outer view" do
      subject = source("abcdefgh")
      outer = subject.slice(offset: 1, count: 5)
      outer.read_exactly(2)

      assert_equal("de", outer.slice(offset: 0, count: 2).read)
      assert_equal("def", outer.read)
    end
  end

  # ---- IO-1, IO-16, IO-19, IO-20: the one-fill contract holds through a view -----------------
  #
  # The primitive fills ONCE and returns what arrived (design R2), and the bridge carries Ruby's
  # semantics through a view (R4). Before review round 0's R0-1 a view asked its parent to
  # buffer `behind + count`, so #read_into, #readpartial and #each on a view blocked until the
  # whole count had arrived where the root returned at once. The parent's #fills counter is the
  # assertion: one fill for one read, however large the count.
  class ViewFills < DexpaceTestCase
    include Sources

    test "read_into on a view fills the parent once and returns what arrived" do
      subject = source("0123456789", "abc")
      dest = +"".b

      assert_equal(10, subject.peek.read_into(dest, count: 100))
      assert_equal("0123456789", dest)
      assert_equal(1, subject.fills)
    end

    # IO-16: #readpartial on a view returns what is available, never blocking to maxlen.
    test "readpartial on a view returns what the parent has, not maxlen" do
      subject = source("0123456789", "abc")

      assert_equal("0123456789", subject.peek.readpartial(100))
      assert_equal(1, subject.fills)
    end

    test "each on a view yields the parent's first chunk before filling again" do
      subject = source("ab", "cd")

      assert_equal("ab", subject.peek.each.first)
      assert_equal(1, subject.fills)
    end

    # A slice whose offset lies past what is buffered fills until its first byte is reachable,
    # and no further: two fills reach byte 3, the read returns the one byte that arrived with it,
    # and a third fill -- for the rest of the window -- would be the count-blocking shape.
    test "a slice fills its parent past its offset before serving, never reporting a false EOF" do
      subject = source("ab", "cd", "ef")
      dest = +"".b
      view = subject.slice(offset: 3, count: 2)

      assert_equal(1, view.read_into(dest, count: 100))
      assert_equal("d", dest)
      assert_equal(2, subject.fills)
      assert_equal(1, view.read_into(dest, count: 100))
      assert_equal("de", dest)
      assert_equal(3, subject.fills)
    end

    # Ruby's contract on the bridge's bulk read is untouched: #read(n) on a view blocks to n
    # through the view's own #ensure_buffered loop, one parent fill per pass.
    test "read(n) on a view still fills to n, which is Ruby's contract" do
      subject = source("ab", "cd", "ef")

      assert_equal("abcd", subject.peek.read(4))
      assert_equal(2, subject.fills)
    end

    test "read_exactly on a view still fills to the count" do
      subject = source("ab", "cd", "ef")

      assert_equal("abcde", subject.peek.read_exactly(5))
      assert_equal(3, subject.fills)
    end
  end

  # ---- IO-22, IO-23 (property), IO-24: the views' lifecycle ----------------------------------
  class ViewLifecycle < DexpaceTestCase
    include Sources

    test "slice composition holds over random offsets and budgets" do
      sample(count: 48) do |rng|
        text = ("a".."z").to_a.join
        outer_offset = rng.rand(0..6)
        outer_count = rng.rand(0..8)
        inner_offset = rng.rand(0..4)
        inner_count = rng.rand(0..8)

        outer = source(text.b).slice(offset: outer_offset, count: outer_count)
        window = text.byteslice(outer_offset, outer_count).to_s
        # Not #clamp: the window can be shorter than the inner offset, and clamp raises when its
        # own maximum is below its minimum. IO-23 caps at the outer slice's REMAINING bytes,
        # which is zero once the offset is past the end.
        available = [window.bytesize - inner_offset, 0].max
        expected = window.byteslice(inner_offset, [inner_count, available].min).to_s

        assert_equal(expected, outer.slice(offset: inner_offset, count: inner_count).read)
      end
    end

    # P3-5 applied recursively, which it is because a view IS a BufferedSource: reading the OUTER
    # slice moves that slice's own cursor past the inner slice's pin, so the inner slice fails
    # loudly -- even though the underlying source has consumed nothing. Pinned rather than left
    # to be discovered, because IO-23's "mutually independent" is about slices of the SAME source
    # and a reader can take it further than it goes.
    test "reading an outer slice invalidates an inner slice taken from it" do
      subject = source("abcdefgh")
      outer = subject.slice(offset: 1, count: 4)
      inner = outer.slice(offset: 1, count: 2)

      assert_equal("bcde", outer.read)
      assert_raises(Dexpace::ClosedError) { inner.read }
    end

    # IO-22, first half.
    test "closing a slice closes neither the parent nor its cursor" do
      subject = source("abcdef")
      view = subject.slice(offset: 0, count: 2)
      view.read
      view.close

      refute_predicate(subject, :closed?)
      assert_equal("abcdef", subject.read)
    end

    # IO-24: "Reading from a slice AFTER it has been explicitly closed MUST fail loudly (a state
    # error) for every read form, distinct from normal EOF."
    test "every read form on an explicitly closed slice raises ClosedError, not an EOF error" do
      view = source("abcdef").slice(offset: 0, count: 4)
      view.close

      assert_raises(Dexpace::ClosedError) { view.read }
      assert_raises(Dexpace::ClosedError) { view.read_exactly(1) }
      assert_raises(Dexpace::ClosedError) { view.readbyte }
      assert_raises(Dexpace::ClosedError) { view.getbyte }
      assert_raises(Dexpace::ClosedError) { view.readpartial(1) }
      assert_raises(Dexpace::ClosedError) { view.read_line_utf8 }
      assert_raises(Dexpace::ClosedError) { view.read_utf8 }
      assert_raises(Dexpace::ClosedError) { view.skip(1) }
      assert_raises(Dexpace::ClosedError) { view.eof? }
      assert_raises(Dexpace::ClosedError) { view.read_into(+"".b, count: 1) }
      assert_raises(Dexpace::ClosedError) { view.each { |_| nil } }
      assert_raises(Dexpace::ClosedError) { view.peek }
      assert_raises(Dexpace::ClosedError) { view.slice(offset: 0, count: 1) }
    end

    # IO-22, second half: "closing the parent source MUST invalidate every outstanding slice
    # derived from it so that subsequent reads on those slices fail loudly ... never returning
    # stale or arbitrary bytes".
    test "closing the parent invalidates every outstanding slice" do
      subject = source("abcdef")
      first = subject.slice(offset: 0, count: 2)
      second = subject.peek
      subject.close

      assert_raises(Dexpace::ClosedError) { first.read }
      assert_raises(Dexpace::ClosedError) { second.read }
    end

    test "closing the parent invalidates a slice of a slice, transitively" do
      subject = source("abcdef")
      inner = subject.slice(offset: 0, count: 4).slice(offset: 1, count: 2)
      subject.close

      assert_raises(Dexpace::ClosedError) { inner.read }
    end

    # P3-5, which the specification does not state and 3a therefore does. IO-22's "never
    # returning stale or arbitrary bytes" is the only normative anchor and it points one way.
    test "a parent read past a live view's pin fails that view loudly, never serving other bytes" do
      subject = source("abcdef")
      view = subject.slice(offset: 0, count: 4)
      subject.read_exactly(3)

      error = assert_raises(Dexpace::ClosedError) { view.read }

      assert_includes(error.message, "behind")
    end

    test "a view that has already pulled its window is unaffected by a later parent read" do
      subject = source("abcdef")
      view = subject.slice(offset: 0, count: 4)

      assert_equal("abcd", view.read)
      subject.read_exactly(5)

      assert_equal("", view.read)
    end

    test "a closed view releases its registration with the parent" do
      subject = source("abcdef")
      view = subject.slice(offset: 0, count: 2)
      view.close
      registered = subject.instance_variable_get(:@dexpace_views)

      assert_empty(registered)
    end
  end

  # ---- the includer contract -----------------------------------------------------------------
  class Includer < DexpaceTestCase
    test "an includer that never calls initialize_typed_reads fails loudly" do
      unready = Class.new do
        include Dexpace::IO::TypedReads
        include Dexpace::Closeable

        def initialize = initialize_closeable(owned: true)
      end.new

      assert_raises(Dexpace::SeamError) { unready.read }
    end

    test "an includer that supplies no fill hook fails loudly" do
      hookless = Class.new do
        include Dexpace::IO::TypedReads
        include Dexpace::Closeable

        def initialize
          initialize_closeable(owned: true)
          initialize_typed_reads
        end
      end.new

      assert_raises(::NotImplementedError) { hookless.read }
    end

    test "an includer without Closeable fails loudly at initialisation" do
      klass = Class.new do
        include Dexpace::IO::TypedReads

        def initialize = initialize_typed_reads
      end

      error = assert_raises(Dexpace::SeamError) { klass.new }

      assert_includes(error.message, "Dexpace::Closeable")
    end
  end
end
