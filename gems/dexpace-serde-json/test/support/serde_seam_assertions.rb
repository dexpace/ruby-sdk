# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "close_counting_source"
require_relative "close_counting_sink"

# The codec seam's adapter obligations as a plain module of Minitest assertion methods over a
# `codec` the includer supplies -- SEAM-20/SEAM-21/SERDE-3's close counts, SERDE-4's four-part
# buffer matrix, SERDE-9/SERDE-10's failure model, SERDE-12's I/O-error pass-through and SERDE-29's
# sharing -- written ONCE and against the seam, naming no adapter. This is the file phase 9 lifts
# into dexpace-conformance, re-pointing the raises at Dexpace::Conformance::Failure; the callable
# assertion shape is that gem's (phase 8a), so this stays ordinary Minitest and pre-empts nothing
# (phase 7a's R12). Everything a format decides -- a malformed payload, a value the format cannot
# carry -- is a parameter the includer supplies.
module SerdeSeamAssertions
  # The one witness the assertions need: the parsed value as it is.
  class Passthrough
    def self.dexpace_load(parsed, _ctx) = parsed
  end

  # SEAM-20, SEAM-21, SERDE-3: a codec closes nothing -- not the sink it writes, not the source it
  # reads to EOF -- with the count asserted as exactly zero through a counting tracker, and a
  # buffer it writes into left exactly as long as it was.
  def assert_closes_nothing(codec, value: { "a" => "é" })
    sink = CloseCountingSink.new
    codec.dump_to(value, sink)

    assert_equal(0, sink.close_count, "SERDE-3: #dump_to closed the caller's sink")
    assert_equal(codec.dump_bytes(value), sink.string, "#dump_to wrote other bytes")

    source = CloseCountingSource.new(codec.dump_string(value))
    codec.load(source, Passthrough)

    assert_equal(0, source.close_count, "SERDE-3: #load closed the caller's source")
    assert_predicate(source, :at_eof?, "SERDE-3: #load did not read to EOF")
  end

  # SERDE-4's conformance clause, all four parts: the return equals the standalone length, the
  # written region matches, the bytes before the offset are untouched, and a one-byte-short buffer
  # raises a range error that is not the serde type and chains nothing -- the last asserted from
  # inside a rescue, because a `cause: nil` is observable only with an exception in flight.
  def assert_buffer_profile(codec, value: { "a" => "é" })
    payload = codec.dump_bytes(value)

    assert_buffer_written(codec, value, payload)
    assert_buffer_overflow(codec, value, payload)
  end

  # The three positive parts: the count, the region, the untouched bytes on either side.
  def assert_buffer_written(codec, value, payload)
    size = payload.bytesize
    buffer = ("\0" * (size + 6)).b
    written = codec.dump_into(value, buffer, offset: 3)

    assert_equal(size, written)
    assert_equal(payload, buffer.byteslice(3, size))
    assert_equal("\0\0\0".b, buffer.byteslice(0, 3), "SERDE-4: bytes before the offset changed")
    assert_equal("\0\0\0".b, buffer.byteslice(3 + size, 3))
  end

  # The negative part, from inside a rescue so `cause: nil` is observable.
  def assert_buffer_overflow(codec, value, payload)
    short = ("\0" * (payload.bytesize - 1)).b
    error = assert_raises(::IndexError) do
      raise "in flight"
    rescue ::RuntimeError
      codec.dump_into(value, short, offset: 0)
    end

    refute_kind_of(Dexpace::Serde::Error, error, "SERDE-4: the range error is not the serde type")
    assert_nil(error.cause, "SERDE-4: the range error chains nothing")
    assert_equal(payload.bytesize - 1, short.bytesize, "SERDE-4: the buffer grew")
  end

  # SERDE-9, SERDE-10: an unencodable value raises the SERIALIZATION subtype and malformed input
  # the DESERIALIZATION subtype, both under Dexpace::Serde::Error, neither the library's own type,
  # and the malformed case chains the library's error as its cause.
  def assert_failure_model(codec, malformed:, unencodable: Object.new)
    write = assert_raises(Dexpace::Serde::SerializationError) { codec.dump_string(unencodable) }
    read = assert_raises(Dexpace::Serde::DeserializationError) do
      codec.load(Dexpace::IO::BufferedSource.of_bytes(malformed.b), Passthrough)
    end

    refute_kind_of(Dexpace::Serde::DeserializationError, write)
    refute_kind_of(Dexpace::Serde::SerializationError, read)
    refute_nil(read.cause, "SERDE-9: the library's failure is chained as the cause")
    refute_kind_of(Dexpace::Serde::Error, read.cause, "SERDE-9: the cause is the library's")
  end

  # SERDE-12: a genuine stream I/O error propagates unwrapped as an I/O error, from a source and
  # from a sink alike.
  def assert_io_error_passthrough(codec, value: { "a" => 1 })
    failing_source = Object.new
    def failing_source.read_utf8(*) = raise Dexpace::StreamError, "connection reset"
    def failing_source.read(*) = raise Dexpace::StreamError, "connection reset"

    error = assert_raises(Dexpace::StreamError) { codec.load(failing_source, Passthrough) }

    refute_kind_of(Dexpace::Serde::Error, error, "SERDE-12: the I/O error was re-wrapped")

    failing_sink = Object.new
    def failing_sink.write(*) = raise ::IOError, "broken pipe"

    assert_raises(::IOError) { codec.dump_to(value, failing_sink) }
  end

  # SERDE-29: one configured codec is safe to share across concurrent workers encoding and decoding
  # distinct values, with no corruption. Every thread is joined before the assertion.
  def assert_shareable(codec, workers: 8, rounds: 100)
    results = Array.new(workers) do |i|
      ::Thread.new do
        Array.new(rounds) do
          text = codec.dump_string({ "k" => i, "v" => "é#{i}" })
          [text, codec.load(Dexpace::IO::BufferedSource.of_bytes(text.b), Passthrough)]
        end.uniq
      end
    end.map(&:value)

    assert_equal(workers, results.flatten(1).uniq.size, "SERDE-29: a worker saw another's value")
    results.each_with_index do |(pair), i|
      assert_equal({ "k" => i, "v" => "é#{i}" }, pair.last)
    end
  end
end
