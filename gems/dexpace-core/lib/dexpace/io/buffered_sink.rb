# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "typed_writes"
require_relative "../closeable"
require_relative "../error/stream_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  module IO
    # The writer: IO-4, IO-5, IO-6, IO-16..IO-18, IO-41, IO-42.
    #
    # #deliver stages the bytes and pushes them one level immediately, so the staging buffer is
    # empty between calls and a failed underlying write cannot leave stale bytes to prepend. That
    # keeps IO-18's distinction real without inventing a flush threshold this port would then
    # have to configure: #emit pushes staged bytes toward the underlying stream and never calls
    # the underlying #flush, and #flush does both.
    class BufferedSink
      include Dexpace::IO::TypedWrites
      include Dexpace::Closeable

      private_class_method :new

      # IO-6: the returned wrapper TAKES OWNERSHIP -- closing it closes `io`. No borrowing variant
      # (P3-12), and .new is private so ownership cannot be set through an unnamed argument
      # (P3-11). `io` is anything responding to #write; checked with respond_to?, never is_a?.
      #
      # With a block, closes on any exit path and returns the block's value; without one the
      # caller owns the close.
      def self.wrapping(io)
        unless io.respond_to?(:write)
          raise Dexpace::InvalidArgumentError,
                "a wrapped stream must respond to #write, got #{io.class}"
        end

        sink = new(io)
        return sink unless block_given?

        begin
          yield sink
        ensure
          sink.close
        end
      end

      def initialize(io)
        @dexpace_underlying = io
        @dexpace_staged = (+"").b
        initialize_closeable(owned: true)
        initialize_typed_writes
      end

      private

      def deliver(string)
        @dexpace_staged << string
        push_one_level
      end

      def push_one_level
        return nil if @dexpace_staged.empty?

        payload = @dexpace_staged
        check_full_write(write_through(payload), payload.bytesize)
      end

      # The staging buffer is cleared in an ensure, so a failed underlying write leaves nothing
      # behind for the next one to prepend -- and an ensure rather than a rescue, so nothing the
      # underlying stream raises is swallowed or duplicated (IO-40).
      def write_through(payload)
        @dexpace_underlying.write(payload)
      ensure
        @dexpace_staged = (+"").b
      end

      # IO-17's rule, applied symmetrically on the write side: an underlying #write that accepted
      # fewer bytes than it was handed is a sink-contract violation. A destination that reports
      # no count at all -- a caller's own #write-shaped object returning something else -- is
      # taken at its word.
      def check_full_write(reported, expected)
        return nil unless reported.is_a?(::Integer)
        return nil if reported >= expected

        raise Dexpace::StreamError.short_transfer(transferred: reported, expected: expected)
      end

      def push_all
        push_one_level
        @dexpace_underlying.flush if @dexpace_underlying.respond_to?(:flush)
        nil
      end

      # IO-6/IO-41: flush what is staged, then close the underlying stream, exactly once.
      def release
        push_one_level
        @dexpace_underlying.close if @dexpace_underlying.respond_to?(:close)
        nil
      end
    end
  end
end
