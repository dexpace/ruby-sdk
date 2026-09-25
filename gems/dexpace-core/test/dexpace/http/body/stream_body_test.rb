# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"
require_relative "../../../support/fake_sink"
require "stringio"
require "tempfile"

# HTTP-37, HTTP-38, HTTP-39, BODY-1, BODY-6, BODY-7, BODY-8, BODY-9, BODY-10, BODY-35.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: BODY-9's
# probe and its conditions here, then Ownership, Latch, Copy and Construction below.
class DexpaceStreamBodyTest < DexpaceTestCase
  # One shared drain for every class below.
  module Streams
    def drain(body)
      sink = Dexpace::IO::Buffer.new
      body.write_to(sink)
      sink.snapshot
    end
  end
  include Streams

  # A sink that parks inside its first write until it is released, which is what makes two writes
  # genuinely overlap instead of merely being started at about the same time.
  class BlockingSink
    def initialize(inside, release)
      @inside = inside
      @release = release
      @entered = false
    end

    def write(string)
      unless @entered
        @entered = true
        @inside << :inside
        @release.pop
      end
      string.bytesize
    end
  end

  # A StringIO that counts its seeks, which is the only way to assert BODY-9's "at most one reset".
  class CountingStringIO < StringIO
    attr_reader :seeks

    def initialize(*)
      super
      @seeks = 0
    end

    def seek(*)
      @seeks += 1
      super
    end
  end

  # ---- BODY-9's antecedent, on real streams -------------------------------------------------

  # respond_to?(:rewind) is true for a pipe, a socket, a StringIO and a File alike, so the probe
  # cannot be that. A REAL IO.pipe raising a REAL Errno::ESPIPE is what makes this meaningful.
  test "a pipe is not rewindable, even though it answers respond_to?(:rewind)" do
    reader, writer = ::IO.pipe
    writer.write("héllo")
    writer.close
    body = Dexpace::Body.stream(reader, content_length: 6)

    assert_respond_to(reader, :rewind)
    refute_predicate(body, :rewindable?)
    refute_predicate(body, :replayable?)
  ensure
    reader.close
  end

  test "a pipe stays fully readable after the probe, so the probe is non-destructive" do
    reader, writer = ::IO.pipe
    writer.write("héllo")
    writer.close
    body = Dexpace::Body.stream(reader, content_length: 6)

    assert_equal("héllo".b, drain(body))
  ensure
    reader.close
  end

  test "a StringIO is rewindable and a known short length makes it replayable" do
    body = Dexpace::Body.stream(StringIO.new(+"héllo"), content_length: 6)

    assert_predicate(body, :rewindable?)
    assert_predicate(body, :replayable?)
  end

  test "a File is rewindable and the probe leaves its cursor exactly where it was" do
    ::Tempfile.create("stream") do |file|
      file.write("0123456789")
      file.flush
      file.rewind
      file.read(4)
      body = Dexpace::Body.stream(file, content_length: 6)

      assert_equal(4, file.pos)
      assert_equal(4, body.origin)
    end
  end

  # THE finding the probe exists for: a body over a pre-positioned handle rewinds to where it
  # started, not to byte 0, so a replay cannot send bytes the caller never offered.
  test "replay rewinds to the construction position rather than to byte 0" do
    ::Tempfile.create("stream") do |file|
      file.write("0123456789")
      file.flush
      file.rewind
      file.read(4)
      body = Dexpace::Body.stream(file, content_length: 6)

      assert_equal("456789".b, drain(body))
      assert_equal("456789".b, drain(body))
    end
  end

  # ---- BODY-9's three conditions -----------------------------------------------------------

  test "an unknown length makes a rewindable stream single-use, per BODY-9's 'of known length'" do
    body = Dexpace::Body.stream(StringIO.new(+"héllo"))

    assert_predicate(body, :rewindable?)
    refute_predicate(body, :replayable?)
  end

  test "a length over MAX_MATERIALIZED_BYTES makes a rewindable stream single-use" do
    over = Dexpace::IO::MAX_MATERIALIZED_BYTES + 1
    body = Dexpace::Body.stream(StringIO.new(+"a"), content_length: over)

    refute_predicate(body, :replayable?)
  end

  # BODY-8's own sentence: "the rewindable variant must keep it open to replay". A body that closes
  # its stream as part of its one write cannot rewind it for a second.
  test "transferring close ownership forces single-use even on a rewindable stream" do
    body = Dexpace::Body.stream(StringIO.new(+"héllo"), content_length: 6, close: true)

    assert_predicate(body, :rewindable?)
    refute_predicate(body, :replayable?)
    assert_predicate(body, :owns_stream?)
  end

  # BODY-8's ownership rule.
  class OwnershipTest < DexpaceTestCase
    include Streams

    test "closes nothing by default, because it opened nothing" do
      io = StringIO.new(+"héllo")
      drain(Dexpace::Body.stream(io, content_length: 6))

      refute_predicate(io, :closed?)
      refute_predicate(Dexpace::Body.stream(io), :owns_stream?)
    end

    test "closes the stream as part of the single write when ownership was transferred" do
      io = StringIO.new(+"héllo")
      drain(Dexpace::Body.stream(io, content_length: 6, close: true))

      assert_predicate(io, :closed?)
    end

    test "closes an owned stream even when the write fails partway" do
      io = StringIO.new(+"héllo")
      body = Dexpace::Body.stream(io, content_length: 6, close: true)
      exploding = FakeSink.new(Dexpace::StreamError.new("the socket went away"))

      assert_raises(Dexpace::StreamError) { body.write_to(exploding) }
      assert_predicate(io, :closed?)
    end

    test "a second write on an owned single-use body raises before touching the closed stream" do
      io = StringIO.new(+"héllo")
      body = Dexpace::Body.stream(io, close: true)
      drain(body)
      error = assert_raises(Dexpace::StreamError) { drain(body) }

      assert_includes(error.message, "BODY-6")
    end
  end

  # BODY-6, BODY-7 and BODY-9's race-safe rewind: the two latches.
  class LatchTest < DexpaceTestCase
    include Streams

    test "a second write on a single-use body raises rather than emitting zero bytes" do
      body = Dexpace::Body.stream(StringIO.new(+"héllo"))
      drain(body)
      error = assert_raises(Dexpace::StreamError) { drain(body) }

      assert_includes(error.message, "BODY-6")
    end

    # BODY-7 is a separate row from BODY-6 and a separate proof: not "a second write raises" but
    # "under concurrent writes at most one passes".
    test "under concurrent writes exactly one passes and every loser sees the consumed failure" do
      # An UNKNOWN length, so the body is single-use: a rewindable StringIO of known length would
      # be replayable and would take the other branch entirely.
      body = Dexpace::Body.stream(StringIO.new(+"0" * 512))
      start = ::Thread::Queue.new
      outcomes = ::Thread::Queue.new
      threads = Array.new(8) do
        ::Thread.new do
          start.pop
          outcomes << (drain(body) && :passed)
        rescue Dexpace::StreamError => error
          outcomes << error
        end
      end
      8.times { start << :go }
      threads.each(&:join)
      results = Array.new(8) { outcomes.pop }

      assert_equal(1, results.count(:passed))
      assert_equal(7, results.count { |r| r.is_a?(Dexpace::StreamError) })
    end

    # BODY-9's "at most one reset between any two writes", proved with the two writes made to
    # OVERLAP deterministically rather than raced and hoped for: the first write blocks inside the
    # sink until the second has been attempted, so a missing guard means two seeks and two readers
    # sharing one cursor -- which is exactly the corruption the clause exists to prevent.
    test "a write that overlaps another on a replayable body is refused, and seeks once" do
      io = CountingStringIO.new(+"0" * 512)
      body = Dexpace::Body.stream(io, content_length: 512)
      # The construction probe seeks once by design, so the count that matters is the delta.
      after_construction = io.seeks
      inside = ::Thread::Queue.new
      release = ::Thread::Queue.new
      first = ::Thread.new { body.write_to(BlockingSink.new(inside, release)) }
      inside.pop

      second = assert_raises(Dexpace::StreamError) { drain(body) }
      release << :go
      first.join

      assert_includes(second.message, "BODY-9")
      assert_equal(1, io.seeks - after_construction)
    end

    # §7.1's residue, and it is this class's own rather than FileBody's (P3-28): BODY-9's rewind
    # guard is released in an `ensure`, and an abandoned enumerator never runs one, so the body
    # stays claimed for good. Stated as a fact rather than as a claim that it is prevented --
    # nothing in Ruby closes it, and design §10.10's precedent is that an admitted hole beats a
    # fake proof.
    test "abandoning a replayable body's enumerator leaves the rewind guard held for good" do
      body = Dexpace::Body.stream(StringIO.new(+"0123456789"), content_length: 10)
      enumerator = body.each
      enumerator.next

      error = assert_raises(Dexpace::StreamError) { drain(body) }

      assert_includes(error.message, "BODY-9")
    end

    test "draining that enumerator to exhaustion releases it, so only abandonment is affected" do
      body = Dexpace::Body.stream(StringIO.new(+"0123456789"), content_length: 10)
      body.each.to_a

      assert_equal("0123456789".b, drain(body))
    end
  end

  # HTTP-39/BODY-10's exact-length copy through a stream.
  class CopyTest < DexpaceTestCase
    include Streams

    test "a declared length shorter than the stream writes exactly that many bytes" do
      body = Dexpace::Body.stream(StringIO.new(+"0123456789"), content_length: 3)

      assert_equal("012".b, drain(body))
    end

    test "a declared length longer than the stream raises naming delivered-of-total" do
      body = Dexpace::Body.stream(StringIO.new(+"012"), content_length: 10)
      error = assert_raises(Dexpace::StreamError) { drain(body) }

      assert_includes(error.message, "3")
      assert_includes(error.message, "10")
    end

    test "a declared length of zero is a legitimate empty write" do
      sink = FakeSink.new

      assert_equal(0, Dexpace::Body.stream(StringIO.new(+"abc"), content_length: 0).write_to(sink))
      assert_empty(sink.writes)
    end

    test "an unknown length drains the stream to end of stream" do
      assert_equal("héllo".b, drain(Dexpace::Body.stream(StringIO.new(+"héllo"))))
    end

    test "delivers BINARY bytes whatever the stream's own tag" do
      sink = FakeSink.new
      Dexpace::Body.stream(StringIO.new(+"héllo")).write_to(sink)

      assert_equal([::Encoding::BINARY], sink.writes.map(&:encoding).uniq)
    end
  end

  # Construction and HTTP-46.
  class ConstructionTest < DexpaceTestCase
    include Streams

    test "rejects a stream that responds to neither readpartial nor read" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.stream(Object.new) }

      assert_includes(error.message, "#readpartial")
    end

    # Phase 3b's review R2-1, repaired by phase 10: the rewind probe read #pos off a closed stream
    # and a bare IOError ("closed stream") escaped `rescue Dexpace::Error` at construction.
    test "rejects an already-closed stream with the SDK's error, closed StringIO and File alike" do
      io = StringIO.new(+"a")
      io.close
      file = Tempfile.new("closed")
      file.close

      [io, file].each do |closed|
        error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.stream(closed) }

        assert_includes(error.message, "already closed")
      end
    ensure
      file&.unlink
    end

    test "rejects a content_length below the -1 sentinel" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.stream(StringIO.new(+"a"), content_length: -2)
      end
    end

    test "leaves the stream usable after a rejected construction argument" do
      io = StringIO.new(+"a")
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.stream(io, content_length: -2)
      end

      assert_equal("a".b, drain(Dexpace::Body.stream(io)))
    end

    # A #read-shaped object with no #pos or #seek is single-use rather than a NoMethodError out of
    # a probe whose whole job is to answer a question.
    test "a stream with read but neither pos nor seek is simply not rewindable" do
      reader = Class.new { def read(_length = nil) = nil }.new
      body = Dexpace::Body.stream(reader, content_length: 0)

      refute_predicate(body, :rewindable?)
      assert_equal(0, body.origin)
    end

    test "has no readable source, because it is a request body" do
      assert_raises(Dexpace::StreamError) { Dexpace::Body.stream(StringIO.new(+"a")).source }
    end

    # HTTP-46: two different open streams are two different values, correctly.
    test "compares by identity, because two live streams are never interchangeable" do
      io = StringIO.new(+"a")
      first = Dexpace::Body.stream(io)
      same = first
      second = Dexpace::Body.stream(io)

      assert_equal(first, same)
      refute_equal(first, second)
      refute_equal(first.hash, second.hash)
    end
  end
end
