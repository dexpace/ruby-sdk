# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "typed_writes"
require_relative "buffer"
require_relative "../closeable"
require_relative "../error/stream_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  module IO
    # The mirror: IO-25..IO-29, IO-40.
    #
    # Its own class rather than a BufferedSink subclass. IO-29 makes its flush, close and emit
    # forward to the primary only, so inheriting a sink's lifecycle and then overriding three
    # quarters of it would be inheritance used as a shortcut. Design §3.1 already says the tee is
    # hand-built rather than assembled from IO.pipe or IO.copy_stream.
    #
    # There is no #clear_tap (the plan's Task 14 decision, taken in the open): phase 3b satisfies
    # BODY-18 by building a fresh tee per write of the wrapped body, which this class binding its
    # primary at construction forces -- a retry writes to a different sink -- so the method had no
    # caller anywhere in core while being NFR-4-locked surface. A caller reusing a tee across
    # attempts builds a new one; the tap is reachable only through #tap_snapshot's fresh copy.
    class TeeSink
      include Dexpace::IO::TypedWrites
      include Dexpace::Closeable

      # IO-26: the default limit MUST be effectively unbounded (nil here), and a limit of 0
      # mirrors nothing while still forwarding everything. `primary` is anything responding to
      # #write, checked with respond_to?, never is_a?.
      def initialize(primary:, tap_limit: nil)
        unless primary.respond_to?(:write)
          raise Dexpace::InvalidArgumentError,
                "primary must respond to #write, got #{primary.class}"
        end

        @dexpace_primary = primary
        @dexpace_tap_limit = validated_tap_limit(tap_limit)
        @dexpace_tap = Dexpace::IO::Buffer.new
        @dexpace_staged = (+"").b
        initialize_closeable(owned: true)
        initialize_typed_writes
      end

      # IO-8 over the tap: a fresh, independent copy. The tap is readable only through this.
      def tap_snapshot
        @dexpace_tap.snapshot
      end

      # How many bytes the tap currently holds -- at most the limit, and never the payload's
      # length once the limit is reached.
      def tap_bytesize
        @dexpace_tap.bytesize
      end

      # IO-28. Defined rather than absent, so the failure is this message and not a NoMethodError.
      # Design §10.10 records the honest position: the prohibition cannot be language-enforced --
      # instance_variable_get reaches anything -- and 3a does not build a fake proof that it can.
      def buffer
        raise Dexpace::StreamError,
              "a TeeSink exposes no backing buffer: a direct buffer write would reach only the " \
              "tap or only the primary and silently corrupt the wire body (IO-28). Use the typed " \
              "write methods -- #write, #write_from, #write_all, #write_utf8, #write_string."
      end

      private

      # IO-26's limit: a non-negative Integer, or nil for unbounded. Float::INFINITY is accepted
      # as the spelling of "unbounded" a caller may reach for; any other Float is a mistake.
      def validated_tap_limit(limit)
        return nil if limit.nil? || limit == ::Float::INFINITY
        return limit if limit.is_a?(::Integer) && !limit.negative?

        raise Dexpace::InvalidArgumentError,
              "tap_limit must be a non-negative Integer or nil, got #{limit.inspect}"
      end

      # IO-27: the attempted bytes are mirrored into the tap BEFORE they are forwarded, so a
      # primary write that fails mid-stream still leaves them captured.
      def deliver(string)
        @dexpace_staged << string
        mirror(@dexpace_staged)
        payload = @dexpace_staged
        check_full_write(forward(payload), payload.bytesize)
      end

      # The staging buffer is cleared in an ensure -- not a rescue, so nothing is swallowed, which
      # is also how IO-40's "MUST NOT swallow OR duplicate the wrapped stream's cancellation/
      # interrupt handling" is honoured structurally: the primary's own failure propagates once,
      # as the identical object.
      def forward(payload)
        @dexpace_primary.write(payload)
      ensure
        @dexpace_staged = (+"").b
      end

      # IO-17's rule on the write side, as BufferedSink applies it: a primary that accepted fewer
      # bytes than it was handed is a sink-contract violation; one reporting no count is taken at
      # its word.
      def check_full_write(reported, expected)
        return nil unless reported.is_a?(::Integer)
        return nil if reported >= expected

        raise Dexpace::StreamError.short_transfer(transferred: reported, expected: expected)
      end

      # IO-25/IO-26: once the limit is reached the tap stops copying while the FULL untruncated
      # payload still goes to the primary.
      def mirror(payload)
        limit = @dexpace_tap_limit
        headroom = limit.nil? ? payload.bytesize : limit - @dexpace_tap.bytesize
        return nil if headroom <= 0

        @dexpace_tap.write(payload.byteslice(0, headroom).to_s)
        nil
      end

      # IO-29: forward to the PRIMARY only, leaving the tap intact for later snapshotting.
      def push_one_level
        @dexpace_primary.emit if @dexpace_primary.respond_to?(:emit)
        nil
      end

      def push_all
        @dexpace_primary.flush if @dexpace_primary.respond_to?(:flush)
        nil
      end

      def release
        @dexpace_primary.close if @dexpace_primary.respond_to?(:close)
        nil
      end
    end
  end
end
