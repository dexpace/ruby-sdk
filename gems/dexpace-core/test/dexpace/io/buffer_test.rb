# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# IO-7, IO-8, IO-9, IO-10, IO-18, IO-41, IO-42.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the FIFO
# here, then Snapshot, CopyTo and Close below.
class DexpaceBufferTest < DexpaceTestCase
  # One shared factory for every class below.
  module Buffers
    def buffer(*strings)
      Dexpace::IO::Buffer.new.tap { |subject| subject.write(*strings) unless strings.empty? }
    end
  end
  include Buffers

  # ---- IO-7: the FIFO ------------------------------------------------------------------------

  # IO-7: "a FIFO byte queue that is simultaneously a source and a sink: bytes written through
  # its sink surface MUST be read back through its source surface in the exact order written, and
  # its size MUST reflect the number of bytes currently held."
  test "bytes written through the sink surface read back in order through the source surface" do
    subject = buffer("ab", "cd", "ef")

    assert_equal(6, subject.bytesize)
    assert_equal("abcdef", subject.read)
    assert_equal(0, subject.bytesize)
  end

  test "bytesize reflects what is currently held, not what was ever written" do
    subject = buffer("abcdef")
    subject.read_exactly(2)

    assert_equal(4, subject.bytesize)
  end

  test "it is simultaneously a source and a sink" do
    subject = buffer

    assert_kind_of(Dexpace::IO::TypedReads, subject)
    assert_kind_of(Dexpace::IO::TypedWrites, subject)
    assert_kind_of(Dexpace::Closeable, subject)
    refute_kind_of(Dexpace::IO::BufferedSource, subject)
  end

  # The mandatory property test (styleguide 11.7): N random BINARY chunks written through the
  # sink surface and read back through the source surface, asserting FIFO order and byte equality.
  test "random chunks round trip through the sink and source surfaces in order" do
    sample(count: 64) do |rng|
      chunks = Array.new(rng.rand(1..8)) { rng.bytes(rng.rand(0..96)) }
      subject = buffer
      chunks.each { |chunk| subject.write(chunk) }

      assert_equal(chunks.join.b.bytesize, subject.bytesize)
      assert_equal(chunks.join.b, subject.read)
    end
  end

  test "interleaved writes and reads keep FIFO order" do
    sample(count: 48) do |rng|
      subject = buffer
      written = +"".b
      read = +"".b
      rng.rand(1..10).times do
        if rng.rand(2).zero?
          chunk = rng.bytes(rng.rand(0..32))
          written << chunk
          subject.write(chunk)
        else
          taken = subject.read(rng.rand(0..16))
          read << taken unless taken.nil?
        end
      end
      read << subject.read

      assert_equal(written, read)
    end
  end

  # IO-18's explicit MAY for a pure in-memory buffer.
  test "emit and flush are no-ops that return self" do
    subject = buffer("abc")

    assert_same(subject, subject.emit)
    assert_same(subject, subject.flush)
    assert_equal("abc", subject.read)
  end

  # ---- IO-8, IO-9: snapshot ------------------------------------------------------------------
  class Snapshot < DexpaceTestCase
    include Buffers

    # IO-8: "a fresh, independent byte-array copy of the buffer's current contents without
    # consuming or otherwise mutating the buffer, such that later mutations of the buffer do not
    # affect a previously returned snapshot and vice versa."
    test "snapshot neither consumes nor mutates the buffer" do
      subject = buffer("abc")

      assert_equal("abc", subject.snapshot)
      assert_equal(3, subject.bytesize)
      assert_equal("abc", subject.read)
    end

    test "a later write does not reach a snapshot already handed out" do
      subject = buffer("abc")
      taken = subject.snapshot
      subject.write("def")

      assert_equal("abc", taken)
    end

    # P3-10: the snapshot comes back UNFROZEN, because IO-8's "and vice versa" presumes the
    # caller may mutate it. The styleguide's freeze-every-returned-collection rule names
    # collections, hashes and structs, and a String is none of the three.
    test "a snapshot is unfrozen and mutating it does not reach the buffer" do
      subject = buffer("abc")
      taken = subject.snapshot

      refute_predicate(taken, :frozen?)
      taken << "zzz"

      assert_equal("abc", subject.snapshot)
    end

    test "a snapshot is BINARY even for non-ASCII content" do
      assert_equal(::Encoding::BINARY, buffer("héllo").snapshot.encoding)
    end

    test "a snapshot of an empty buffer is an empty BINARY String" do
      taken = buffer.snapshot

      assert_equal("", taken)
      assert_equal(::Encoding::BINARY, taken.encoding)
    end

    test "a snapshot starts at the cursor, not at the first byte ever written" do
      subject = buffer("abcdef")
      subject.read_exactly(2)

      assert_equal("cdef", subject.snapshot)
    end

    # The only test in 3a that allocates anything large: a Buffer built just over the ceiling,
    # so #snapshot's size guard is exercised for real. It costs one ~64 MiB String allocation,
    # once per run per matrix row, and it runs on EVERY row -- skipping it somewhere would leave
    # the ceiling's only size-based assertion untested exactly where it might first break.
    test "snapshot refuses a buffer over the ceiling and names the streaming alternatives" do
      subject = buffer
      over = Dexpace::IO::MAX_MATERIALIZED_BYTES + 1
      subject.write("\0".b * over)

      assert_equal(over, subject.bytesize)
      error = assert_raises(Dexpace::StreamError) { subject.snapshot }

      assert_includes(error.message, "MAX_MATERIALIZED_BYTES")
      assert_includes(error.message, "#each")
      assert_includes(error.message, "#copy_to")
    end

    test "snapshot of a buffer at the ceiling is not refused for its size" do
      subject = buffer

      # No allocation: the guard reads #bytesize, so an empty buffer proves the comparison is <=.
      assert_equal("", subject.snapshot)
    end
  end

  # ---- IO-10 ---------------------------------------------------------------------------------
  class CopyTo < DexpaceTestCase
    include Buffers

    test "clear discards every byte" do
      subject = buffer("abcdef")
      subject.clear

      assert_equal(0, subject.bytesize)
      assert_equal("", subject.read)
    end

    test "a cleared buffer accepts new writes and reads them back" do
      subject = buffer("abc")
      subject.clear
      subject.write("xyz")

      assert_equal("xyz", subject.read)
    end

    # IO-10: "copyTo(out, offset, byteCount) MUST copy the specified window into another buffer
    # WITHOUT consuming or mutating the source buffer, defaulting to 'from offset through end'".
    test "copy_to copies a window without consuming or mutating the source" do
      source = buffer("abcdef")
      target = buffer

      source.copy_to(target, offset: 1, count: 3)

      assert_equal("bcd", target.read)
      assert_equal("abcdef", source.read)
    end

    test "copy_to defaults to from offset through end, and to the whole buffer" do
      source = buffer("abcdef")
      target = buffer

      source.copy_to(target, offset: 2)
      source.copy_to(target)

      assert_equal("cdefabcdef", target.read)
    end

    test "copy_to measures its offset from the cursor and appends to the target" do
      source = buffer("ab", "cdef")
      source.read_exactly(1)
      target = buffer("x")

      source.copy_to(target, offset: 1, count: 3)

      assert_equal("xcde", target.read)
    end

    # IO-10: "rejecting out-of-range windows (negative offset/byteCount or offset+byteCount>size)".
    # P3-4: copy_to is NOT a ceiling case at all -- it materialises nothing contiguous of its own,
    # so an out-of-range window here is IO-10's argument error and never IO-9's StreamError.
    test "copy_to rejects an out-of-range window and leaves both buffers untouched" do
      source = buffer("abc")
      target = buffer

      assert_raises(Dexpace::InvalidArgumentError) { source.copy_to(target, offset: 0, count: 9) }
      assert_raises(Dexpace::InvalidArgumentError) { source.copy_to(target, offset: 9, count: 1) }
      assert_raises(Dexpace::InvalidArgumentError) { source.copy_to(target, offset: -1, count: 1) }
      assert_raises(Dexpace::InvalidArgumentError) { source.copy_to(target, offset: 0, count: -1) }
      assert_raises(Dexpace::InvalidArgumentError) { source.copy_to(target, offset: 4) }
      assert_raises(Dexpace::InvalidArgumentError) { source.copy_to("nope") }
      assert_equal(0, target.bytesize)
      assert_equal("abc", source.read)
    end

    test "copy_to of an over-ceiling window is an argument error, never a ceiling error" do
      source = buffer("abc")

      error = assert_raises(Dexpace::InvalidArgumentError) do
        source.copy_to(buffer, offset: 0, count: Dexpace::IO::MAX_MATERIALIZED_BYTES + 1)
      end

      refute_kind_of(Dexpace::StreamError, error)
    end

    test "copy_to with an empty window at the end copies nothing and is not an error" do
      source = buffer("abc")
      target = buffer

      assert_nil(source.copy_to(target, offset: 3))
      assert_equal(0, target.bytesize)
    end
  end

  # ---- IO-41, IO-42 --------------------------------------------------------------------------
  class Close < DexpaceTestCase
    include Buffers

    test "close is idempotent" do
      subject = buffer("abc")

      subject.close
      subject.close

      assert_predicate(subject, :closed?)
    end

    # IO-42: "A purely in-memory buffer is exempt on its OWN read/write surface (an in-memory
    # close frees nothing and may remain readable so snapshot-after-close logging still works)".
    # This is one of the two tests that fail in OPPOSITE directions; buffered_source_test.rb has
    # the other, and a single "it raises after close" test would pass over either error.
    test "a closed buffer stays readable and writable on its own surface" do
      subject = buffer("abc")
      subject.close

      assert_equal("abc", subject.snapshot)
      assert_equal(3, subject.bytesize)
      assert_equal(3, subject.write("def"))
      assert_same(subject, subject.emit)
      assert_same(subject, subject.flush)
      assert_equal("abcdef", subject.read)
    end

    # IO-42's other half, which the exemption does NOT cover: "its close() MUST still invalidate
    # every slice derived from it (see IO-22/IO-38)."
    test "closing a buffer still invalidates every view derived from it" do
      subject = buffer("abcdef")
      view = subject.slice(offset: 0, count: 3)
      peeked = subject.peek

      subject.close

      assert_raises(Dexpace::ClosedError) { view.read }
      assert_raises(Dexpace::ClosedError) { peeked.read }
    end

    test "a view over a buffer reads without consuming it" do
      subject = buffer("abcdef")

      assert_equal("abc", subject.slice(offset: 0, count: 3).read)
      assert_equal("abcdef", subject.peek.read)
      assert_equal("abcdef", subject.read)
    end

    # A view over a buffer is length-bounded by the buffer's own contents at the time it is
    # driven, and its read never pulls from anywhere else (a buffer has no upstream).
    test "a peek over a buffer sees bytes written after it was taken" do
      subject = buffer("ab")
      peeked = subject.peek
      subject.write("cd")

      assert_equal("abcd", peeked.read)
    end
  end
end
