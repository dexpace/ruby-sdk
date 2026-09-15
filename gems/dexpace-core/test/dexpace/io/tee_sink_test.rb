# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_sink"
require "dexpace"

# IO-25, IO-26, IO-27, IO-28, IO-29, IO-40, IO-41, IO-42.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# mirror and its limit here, then Failure, Lifecycle and Vocabulary below.
class DexpaceTeeSinkTest < DexpaceTestCase
  # One shared factory for every class below.
  module Tees
    def tee(primary = FakeSink.new, **)
      Dexpace::IO::TeeSink.new(primary: primary, **)
    end
  end
  include Tees

  # ---- IO-25 ---------------------------------------------------------------------------------

  # IO-25: "MUST mirror the bytes written through it into an in-memory tap buffer AND forward the
  # full, untruncated payload to its primary sink; the bytes delivered to the primary (the wire
  # body) MUST never be reduced or altered by the presence of the tap."
  test "the wire body reaches the primary byte for byte and the tap mirrors it" do
    primary = FakeSink.new
    sink = tee(primary)

    sink.write("héllo ", "wörld")

    assert_equal("héllo wörld".b, primary.written)
    assert_equal("héllo wörld".b, sink.tap_snapshot)
  end

  test "the primary sees the same writes with or without a tap limit" do
    unlimited = FakeSink.new
    limited = FakeSink.new
    tee(unlimited).write("abcdef")
    tee(limited, tap_limit: 2).write("abcdef")

    assert_equal(limited.writes, unlimited.writes)
  end

  test "tap_snapshot is a fresh independent copy, like Buffer#snapshot" do
    sink = tee
    sink.write("abc")
    taken = sink.tap_snapshot
    sink.write("def")

    assert_equal("abc", taken)
    assert_equal("abcdef", sink.tap_snapshot)
    assert_equal(::Encoding::BINARY, taken.encoding)
  end

  test "tap_bytesize reports what the tap currently holds" do
    sink = tee
    sink.write("abcd")

    assert_equal(4, sink.tap_bytesize)
  end

  # ---- IO-26 ---------------------------------------------------------------------------------

  # IO-26: "once the limit is reached, further writes MUST stop copying into the tap while still
  # forwarding the FULL payload to the primary."
  test "the tap stops at its limit while the full payload still reaches the primary" do
    primary = FakeSink.new
    sink = tee(primary, tap_limit: 4)

    sink.write("abcdef")
    sink.write("ghij")

    assert_equal("abcd", sink.tap_snapshot)
    assert_equal("abcdefghij", primary.written)
  end

  # IO-26: "The default limit MUST be effectively unbounded".
  test "the default limit is effectively unbounded" do
    sink = tee
    sink.write("x" * 100_000)

    assert_equal(100_000, sink.tap_bytesize)
    assert_includes(Dexpace::IO::TeeSink.instance_method(:initialize).parameters,
                    %i[key tap_limit],)
  end

  # IO-26: "a limit of 0 MUST mirror nothing while still forwarding everything."
  test "a limit of zero mirrors nothing and forwards everything" do
    primary = FakeSink.new
    sink = tee(primary, tap_limit: 0)

    sink.write("abcdef")

    assert_equal(0, sink.tap_bytesize)
    assert_equal("abcdef", primary.written)
  end

  test "a mid-write limit truncates the tap exactly at the limit" do
    sink = tee(FakeSink.new, tap_limit: 3)
    sink.write("abcdef")

    assert_equal("abc", sink.tap_snapshot)
  end

  test "a negative or non-numeric tap limit is rejected at construction" do
    assert_raises(Dexpace::InvalidArgumentError) { tee(FakeSink.new, tap_limit: -1) }
    assert_raises(Dexpace::InvalidArgumentError) { tee(FakeSink.new, tap_limit: "lots") }
    assert_raises(Dexpace::InvalidArgumentError) { tee(FakeSink.new, tap_limit: 1.5) }
  end

  test "a primary with no write is rejected at construction" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::IO::TeeSink.new(primary: Object.new) }
  end

  # ---- IO-27, IO-40: the primary's failure ---------------------------------------------------
  class Failure < DexpaceTestCase
    include Tees

    # IO-27: "MUST mirror the attempted bytes into the tap BEFORE forwarding them to the primary
    # sink, so that if the primary write fails mid-stream the attempted bytes are still captured
    # in the tap". Only a scriptable FakeSink can raise partway through.
    test "a failed primary write still leaves the attempted bytes in the tap" do
      primary = FakeSink.new(nil, ::RuntimeError.new("boom"))
      sink = tee(primary)

      sink.write("abc")
      assert_raises(::RuntimeError) { sink.write("def") }

      assert_equal("abcdef", sink.tap_snapshot)
    end

    # IO-27: "its staging buffer MUST be cleared even on a failed primary write so a later write
    # does not prepend stale bytes." An ensure and not a rescue, so nothing is swallowed -- which
    # is also how IO-40's "MUST NOT swallow OR duplicate the wrapped stream's cancellation/
    # interrupt handling" is honoured structurally.
    test "the staging buffer is cleared even on a failed primary write" do
      primary = FakeSink.new(::RuntimeError.new("boom"))
      sink = tee(primary)

      assert_raises(::RuntimeError) { sink.write("abc") }
      sink.write("def")

      assert_equal("def", primary.written)
    end

    # IO-40: the primary's own failure propagates as the identical object, once.
    test "the primary's failure propagates unchanged and unwrapped" do
      boom = ::IOError.new("connection reset")
      sink = tee(FakeSink.new(boom))

      error = assert_raises(::IOError) { sink.write("abc") }

      assert_same(boom, error)
    end

    test "a short primary write is a sink-contract violation" do
      error = assert_raises(Dexpace::StreamError) { tee(FakeSink.new(1)).write("abcd") }

      assert_includes(error.message, "4")
    end
  end

  # ---- IO-28, IO-29, IO-41, IO-42: the lifecycle ---------------------------------------------
  class Lifecycle < DexpaceTestCase
    include Tees

    # IO-28: "MUST NOT expose direct access to a backing buffer (attempting it MUST fail with a
    # clear error directing callers to the typed write methods)". Defined rather than absent so
    # the failure is that message and not a NoMethodError. Design §10.10 records the honest
    # position: the prohibition cannot be language-enforced and 3a builds no fake proof that it can.
    test "buffer is defined and raises with a message naming the typed write methods" do
      sink = tee

      assert_respond_to(sink, :buffer)
      error = assert_raises(Dexpace::StreamError) { sink.buffer }

      assert_includes(error.message, "IO-28")
      assert_includes(error.message, "#write_all")
    end

    # #clear_tap is deliberately NOT here (the plan's Task 14 decision): 3b satisfies BODY-18 by
    # building a fresh tee per write, which TeeSink binding its primary at construction forces,
    # so the method had no caller anywhere in core while being NFR-4-locked surface.
    test "no other route to the backing store is exposed" do
      sink = tee

      refute_respond_to(sink, :primary)
      refute_respond_to(sink, :staged)
      refute_respond_to(sink, :tap_buffer)
      refute_respond_to(sink, :clear_tap)
    end

    # IO-29: "A TeeSink's own flush(), close(), and emit() MUST forward to the PRIMARY sink only
    # (not the tap), so lifecycle/flush semantics of the real destination are preserved and the
    # in-memory tap is left intact for later snapshotting."
    test "flush, emit and close forward to the primary only and leave the tap intact" do
      events = []
      primary = FakeSink.new
      primary.define_singleton_method(:flush) { events << :flush }
      primary.define_singleton_method(:emit) { events << :emit }
      primary.define_singleton_method(:close) { events << :close }
      sink = tee(primary)
      sink.write("abc")

      sink.emit
      sink.flush
      sink.close

      assert_equal(%i[emit flush close], events)
      assert_equal("abc", sink.tap_snapshot)
    end

    test "flush and emit return self, and tolerate a primary with neither" do
      sink = tee

      assert_same(sink, sink.emit)
      assert_same(sink, sink.flush)
    end

    test "the tap survives close, so a snapshot can still be taken afterwards" do
      sink = tee
      sink.write("abc")
      sink.close

      assert_equal("abc", sink.tap_snapshot)
      assert_equal(3, sink.tap_bytesize)
    end

    test "close is idempotent and closes the primary at most once" do
      closes = 0
      primary = FakeSink.new
      primary.define_singleton_method(:close) { closes += 1 }
      sink = tee(primary)

      sink.close
      sink.close

      assert_equal(1, closes)
    end

    # IO-42: a tee wraps an external stream, so it is not exempt.
    test "a closed tee rejects every write form" do
      sink = tee
      sink.close

      assert_raises(Dexpace::ClosedError) { sink.write("ab") }
      assert_raises(Dexpace::ClosedError) { sink.write_utf8("ab") }
      one_byte = Dexpace::IO::BufferedSource.of_bytes("a")
      assert_raises(Dexpace::ClosedError) { sink.write_all(one_byte) }
      assert_raises(Dexpace::ClosedError) { sink.write_from(Dexpace::IO::Buffer.new, count: 0) }
      assert_raises(Dexpace::ClosedError) { sink.emit }
      assert_raises(Dexpace::ClosedError) { sink.flush }
    end
  end

  # ---- the whole write vocabulary reaches both sides -------------------------------------------
  class Vocabulary < DexpaceTestCase
    include Tees

    test "write_all, write_from and write_utf8 all mirror and forward" do
      primary = FakeSink.new
      sink = tee(primary)
      buffer = Dexpace::IO::Buffer.new
      buffer.write("cd")

      sink.write_utf8("é")
      sink.write_from(buffer, count: 2)
      sink.write_all(Dexpace::IO::BufferedSource.of_bytes("ef"))

      assert_equal("écdef".b, primary.written)
      assert_equal("écdef".b, sink.tap_snapshot)
    end

    test "IO.copy_stream drives a tee as a destination" do
      primary = FakeSink.new
      sink = tee(primary, tap_limit: 3)

      ::IO.copy_stream(Dexpace::IO::BufferedSource.of_bytes("héllo"), sink)

      assert_equal("héllo".b, primary.written)
      assert_equal("héllo".b.byteslice(0, 3), sink.tap_snapshot)
    end

    test "the tap and the primary agree byte for byte over random chunk sequences" do
      sample(count: 48) do |rng|
        primary = FakeSink.new
        sink = tee(primary)
        chunks = Array.new(rng.rand(1..6)) { rng.bytes(rng.rand(0..48)) }
        chunks.each { |chunk| sink.write(chunk) }

        assert_equal(chunks.join.b, primary.written)
        assert_equal(chunks.join.b, sink.tap_snapshot)
      end
    end

    test "a bounded tap holds exactly the first limit bytes over random chunk sequences" do
      sample(count: 32) do |rng|
        limit = rng.rand(0..40)
        primary = FakeSink.new
        sink = tee(primary, tap_limit: limit)
        chunks = Array.new(rng.rand(1..6)) { rng.bytes(rng.rand(0..32)) }
        chunks.each { |chunk| sink.write(chunk) }

        assert_equal(chunks.join.b, primary.written)
        assert_equal(chunks.join.b.byteslice(0, limit), sink.tap_snapshot)
      end
    end
  end
end
