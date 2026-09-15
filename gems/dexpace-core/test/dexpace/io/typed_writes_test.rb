# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_source"
require "dexpace"

# IO-4, IO-5, IO-13 (write side), IO-16 (writable bridge), IO-17, IO-18.
#
# Written against a trivial in-test includer whose #deliver appends to a String, so the write
# vocabulary is exercised with no destination at all.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# bridge and #write_from here, then Pump, Charsets and Includer below.
class DexpaceTypedWritesTest < DexpaceTestCase
  # The Ruby shape of the reference's BufferedSink interface: supply #deliver, get everything.
  class Collector
    include Dexpace::IO::TypedWrites
    include Dexpace::Closeable

    attr_reader :delivered

    def initialize
      @delivered = []
      initialize_closeable(owned: true)
      initialize_typed_writes
    end

    def written = @delivered.join.b

    private

    def deliver(string)
      @delivered << string
      nil
    end

    def release = nil
  end

  # One shared factory for every class below, so every sink under test is shaped the same.
  module Sinks
    def sink = Collector.new
  end
  include Sinks

  # ---- IO-16: the writable bridge ------------------------------------------------------------

  # IO-16's writable half, and P3-9's stated exception: a positional splat exactly like ::IO#write,
  # because being call-compatible with ::IO is the bridge's entire purpose -- a keyword here would
  # make IO.copy_stream fail.
  test "write takes a splat of Strings and returns the byte count" do
    subject = sink

    assert_equal(5, subject.write("ab", "cde"))
    assert_equal("abcde", subject.written)
  end

  test "write returns the BYTE count, not the character count" do
    assert_equal("é".bytesize, sink.write("é"))
  end

  test "write hands the hook frozen BINARY bytes even for a non-ASCII UTF-8 argument" do
    subject = sink
    subject.write("é")

    assert_equal(::Encoding::BINARY, subject.delivered.first.encoding)
    assert_predicate(subject.delivered.first, :frozen?)
  end

  test "write copies a caller-mutable String, so a reused buffer cannot corrupt what was written" do
    subject = sink
    buffer = +"ab".b
    subject.write(buffer)
    buffer.replace("zz")

    assert_equal("ab", subject.written)
  end

  test "write keeps an already-frozen BINARY String by identity and skips an empty one" do
    subject = sink
    frozen = "ab".b.freeze

    assert_equal(2, subject.write(frozen, ""))
    assert_same(frozen, subject.delivered.first)
    assert_equal(1, subject.delivered.length)
  end

  test "write rejects a non-String argument" do
    assert_raises(Dexpace::InvalidArgumentError) { sink.write(42) }
  end

  # ---- IO-4: write_from ----------------------------------------------------------------------
  class WriteFrom < DexpaceTestCase
    include Sinks

    # IO-4: "MUST remove exactly byteCount bytes from the HEAD of the source buffer and push them
    # downstream".
    test "write_from removes exactly count bytes from the head of the buffer" do
      subject = sink
      buffer = Dexpace::IO::Buffer.new
      buffer.write("abcdef")

      subject.write_from(buffer, count: 3)

      assert_equal("abc", subject.written)
      assert_equal(3, buffer.bytesize)
      assert_equal("def", buffer.read)
    end

    # IO-4: "if the source holds fewer than byteCount bytes this MUST fail with an I/O error rather
    # than write a short/partial amount." And nothing is consumed, so the buffer is still usable.
    test "write_from fails with an I/O error rather than writing short, and consumes nothing" do
      subject = sink
      buffer = Dexpace::IO::Buffer.new
      buffer.write("ab")

      error = assert_raises(Dexpace::StreamError) { subject.write_from(buffer, count: 5) }

      assert_includes(error.message, "2")
      assert_includes(error.message, "5")
      assert_empty(subject.written)
      assert_equal("ab", buffer.read)
    end

    test "write_from rejects a negative or non-Integer count before touching the buffer" do
      buffer = Dexpace::IO::Buffer.new
      buffer.write("abc")

      assert_raises(Dexpace::InvalidArgumentError) { sink.write_from(buffer, count: -1) }
      assert_raises(Dexpace::InvalidArgumentError) { sink.write_from(buffer, count: 1.5) }
      assert_equal(3, buffer.bytesize)
    end

    test "write_from with a zero count is a no-op" do
      subject = sink
      buffer = Dexpace::IO::Buffer.new

      assert_nil(subject.write_from(buffer, count: 0))
      assert_empty(subject.written)
    end

    test "write_from rejects something that is not a Buffer" do
      assert_raises(Dexpace::InvalidArgumentError) { sink.write_from("abc", count: 1) }
    end
  end

  # ---- IO-17: the pump -----------------------------------------------------------------------
  class Pump < DexpaceTestCase
    include Sinks

    # IO-17: "MUST pump the source to exhaustion into the sink and return the total number of
    # bytes transferred; it MUST terminate only on a -1 (EOF) read."
    test "write_all pumps to exhaustion and returns the total" do
      subject = sink
      source = FakeSource.new("ab", "cde", -1)

      assert_equal(5, subject.write_all(source))
      assert_equal("abcde", subject.written)
    end

    test "write_all terminates on -1 and does not keep asking" do
      source = FakeSource.new("ab", -1)
      sink.write_all(source)

      assert_equal(2, source.calls.length)
      assert_equal([64 * 1024] * 2, source.calls)
    end

    # IO-17: "a read that returns 0 for a non-zero requested count MUST be treated as a source
    # contract violation and raised as an I/O error (not tolerated as EOF and not spun on
    # forever)." No real Ruby stream produces this, which is why FakeSource exists.
    #
    # The check is UNCONDITIONAL rather than scoped to a "foreign" source: design §10.1 retired
    # the adapter, so "adapter-native" has no subject in this port, and a correct source never
    # returns 0 for a positive count anyway.
    test "write_all raises on a zero read for a positive count and does not spin" do
      subject = sink
      source = FakeSource.new("ab", 0, "cd")

      error = assert_raises(Dexpace::StreamError) { subject.write_all(source) }

      assert_includes(error.message, "IO-17")
      assert_equal(2, source.calls.length)
      assert_equal("ab", subject.written)
    end

    test "write_all lets a source's own failure propagate unchanged" do
      boom = Class.new(::StandardError)

      assert_raises(boom) { sink.write_all(FakeSource.new("ab", boom.new("no"))) }
    end

    test "write_all rejects an object that is not a source" do
      error = assert_raises(Dexpace::InvalidArgumentError) { sink.write_all(Object.new) }

      assert_includes(error.message, "#read_into")
    end

    test "write_all drives a real BufferedSource end to end" do
      subject = sink

      assert_equal(6, subject.write_all(Dexpace::IO::BufferedSource.of_bytes("abcdef")))
      assert_equal("abcdef", subject.written)
    end

    test "write_all of an already exhausted source transfers nothing and returns 0" do
      assert_equal(0, sink.write_all(FakeSource.new(-1)))
    end
  end

  # ---- IO-13: the write-side encodings, and IO-5/IO-18 ---------------------------------------
  class Charsets < DexpaceTestCase
    include Sinks

    test "write_utf8 writes the UTF-8 bytes of the string" do
      subject = sink
      subject.write_utf8("héllo")

      assert_equal("héllo".b, subject.written)
    end

    # P3-9: `range` is a CHARACTER range over the String -- the reference's substring form --
    # while every count elsewhere in 3a is a byte count. The non-ASCII fixture tells them apart.
    test "write_utf8 range is a character range, not a byte range" do
      subject = sink
      subject.write_utf8("héllo", range: 0..1)

      assert_equal("hé".b, subject.written)
    end

    test "write_utf8 rejects a range outside the string, and a non-String with or without one" do
      assert_raises(Dexpace::InvalidArgumentError) { sink.write_utf8("ab", range: 9..12) }
      assert_raises(Dexpace::InvalidArgumentError) { sink.write_utf8(:ab) }
      assert_raises(Dexpace::InvalidArgumentError) { sink.write_utf8(:ab, range: 0..1) }
    end

    test "write_string encodes into the charset the caller named" do
      subject = sink
      subject.write_string("café", encoding: ::Encoding::ISO_8859_1)

      assert_equal("caf\xE9".b, subject.written)
    end

    test "write_string accepts an encoding name and rejects an unknown one" do
      subject = sink
      subject.write_string("é", encoding: "UTF-8")

      assert_equal("é".b, subject.written)
      assert_raises(Dexpace::InvalidArgumentError) { sink.write_string("ab", encoding: "no-such") }
    end

    test "write_string rejects text the target charset cannot represent" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        sink.write_string("→", encoding: ::Encoding::ISO_8859_1)
      end

      assert_includes(error.message, "ISO-8859-1")
    end

    test "write_string of an empty string delivers nothing" do
      subject = sink

      assert_nil(subject.write_string("", encoding: "UTF-8"))
      assert_empty(subject.delivered)
    end

    # IO-18: "On a pure in-memory buffer both MAY be no-ops that simply return self."
    test "emit and flush return self" do
      subject = sink

      assert_same(subject, subject.emit)
      assert_same(subject, subject.flush)
    end
  end

  # ---- the includer contract -----------------------------------------------------------------
  class Includer < DexpaceTestCase
    include Sinks

    test "an includer that never calls initialize_typed_writes fails loudly" do
      unready = Class.new do
        include Dexpace::IO::TypedWrites
        include Dexpace::Closeable

        def initialize = initialize_closeable(owned: true)
      end.new

      assert_raises(Dexpace::SeamError) { unready.write("ab") }
    end

    test "an includer that supplies no deliver hook fails loudly" do
      hookless = Class.new do
        include Dexpace::IO::TypedWrites
        include Dexpace::Closeable

        def initialize
          initialize_closeable(owned: true)
          initialize_typed_writes
        end
      end.new

      assert_raises(::NotImplementedError) { hookless.write("ab") }
    end

    test "an includer without Closeable fails loudly at initialisation" do
      klass = Class.new do
        include Dexpace::IO::TypedWrites

        def initialize = initialize_typed_writes
      end

      assert_raises(Dexpace::SeamError) { klass.new }
    end

    test "the write hooks are private and the vocabulary is public" do
      subject = sink

      assert_respond_to(subject, :write_all)
      refute_respond_to(subject, :deliver)
      refute_respond_to(subject, :push_one_level)
      refute_respond_to(subject, :push_all)
    end

    # A closed includer that does not exempt itself refuses every write form (IO-42); Buffer is
    # the one that does, and buffer_test.rb proves that side.
    test "a closed includer refuses to write unless it exempts itself" do
      subject = sink
      subject.close

      assert_raises(Dexpace::ClosedError) { subject.write("ab") }
      assert_raises(Dexpace::ClosedError) { subject.emit }
      assert_raises(Dexpace::ClosedError) { subject.flush }
    end
  end
end
