# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "typed_reads"
require_relative "typed_writes"
require_relative "../closeable"
require_relative "../error/stream_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  module IO
    # The FIFO: IO-7..IO-10, IO-41, IO-42. An Array of BINARY String chunks behind a head byte
    # offset, so draining is O(1) amortised (§3.1).
    #
    # It includes BOTH vocabularies, which is what makes it "simultaneously a source and a sink"
    # (IO-7). It is deliberately NOT a BufferedSource subclass: it would inherit .wrapping,
    # .of_bytes and .over, and Buffer.wrapping(io) is a nonsense factory that would appear in the
    # surface manifest. .new is public because a Buffer has exactly one construction meaning and
    # needs no factory to name it (P3-11); phase 1's private .new plus a validating .build is a
    # rule about Data value types and does not reach a mutable, stateful object.
    #
    # IO-42's asymmetry, in both directions: the in-memory read/write surface stays live after
    # close, because an in-memory close frees nothing and snapshot-after-close body logging
    # (BODY-28) depends on it; and the close still invalidates every view derived from the buffer.
    # Neither direction may be simplified into the other.
    class Buffer
      include Dexpace::IO::TypedReads
      include Dexpace::IO::TypedWrites
      include Dexpace::Closeable

      def initialize
        initialize_closeable(owned: true)
        initialize_typed_reads
        initialize_typed_writes
      end

      # IO-7's size. Named for bytes because everything here is bytes and String#bytesize is the
      # precedent.
      def bytesize
        @dexpace_buffered
      end

      # IO-8: a fresh, independent, UNFROZEN BINARY copy that neither consumes nor mutates the
      # buffer. Unfrozen deliberately (P3-10) -- IO-8's "and vice versa" presumes the caller may
      # mutate it, and the styleguide's freeze-every-returned-collection rule names collections,
      # hashes and structs, which a String is none of.
      #
      # Guarded by MAX_MATERIALIZED_BYTES (IO-9): the size is known here, so an over-ceiling
      # snapshot refuses having allocated nothing.
      def snapshot
        guard_materialization!(@dexpace_buffered)
        store_peek(0, @dexpace_buffered)
      end

      # IO-10.
      def clear
        @dexpace_chunks.clear
        @dexpace_head = 0
        @dexpace_consumed += @dexpace_buffered
        @dexpace_buffered = 0
        nil
      end

      # IO-10: copies a window into another Buffer WITHOUT consuming or mutating this one,
      # defaulting to "from offset through end", and rejecting an out-of-range window eagerly.
      # Not a ceiling case (P3-4): it materialises nothing contiguous of its own -- the window
      # goes into `other`'s chunk store as one chunk.
      def copy_to(other, offset: 0, count: nil)
        unless other.is_a?(Dexpace::IO::Buffer)
          raise Dexpace::InvalidArgumentError,
                "copy_to takes a Dexpace::IO::Buffer, got #{other.class}"
        end

        span = validate_window!(offset, count)
        other.write(store_peek(offset, span)) unless span.zero?
        nil
      end

      private

      # IO-10's out-of-range rule, IO-3's eager rejection: a negative offset or count, or a window
      # reaching past the end, is an argument error before anything is copied. Returns the
      # window's length, which defaults to "from offset through end".
      def validate_window!(offset, count)
        validate_count!(offset, name: "offset")
        validate_count!(count, name: "count") unless count.nil?
        span = count.nil? ? @dexpace_buffered - offset : count
        return span unless span.negative? || offset + span > @dexpace_buffered

        raise Dexpace::InvalidArgumentError,
              "window offset #{offset}, count #{count.inspect} is outside a buffer of " \
              "#{@dexpace_buffered} bytes"
      end

      # A Buffer has no upstream, so there is nothing to fill from. IO-7's source surface reads
      # exactly what its sink surface wrote.
      def fill(_min_bytes)
        0
      end

      # IO-7: bytes written through the sink surface land in the same store the source surface
      # reads, in the exact order written.
      def deliver(string)
        store_append(string)
        nil
      end

      # IO-42's in-memory exemption, in both directions. An in-memory close frees nothing, so
      # snapshot-after-close body logging still works.
      def reads_survive_close?
        true
      end

      def writes_survive_close?
        true
      end

      # IO-42's other half, which the exemption does NOT cover: close still invalidates every
      # view derived from this buffer (IO-22, IO-38).
      def release
        dexpace_release_views
      end
    end
  end
end
