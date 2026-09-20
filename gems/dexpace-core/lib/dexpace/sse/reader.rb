# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error/invalid_argument_error"
require_relative "../sse"
require_relative "limit_exceeded_error"
require_relative "line_reader"
require_relative "event"

module Dexpace
  module SSE
    # SSE-1's field state machine over LineReader: lines accumulate into one block until a blank
    # line dispatches them as one Event (SSE-13's permissive dispatch), end of stream dispatches a
    # pending block once (SSE-14) and then reports end for good (SSE-15).
    #
    # Everything below the decode is a BYTE operation on the BINARY line -- SSE-3's split at the
    # first colon, SSE-5's one-space strip, SSE-6's comment test, SSE-7's exact field-name match,
    # SSE-9's NUL screen and SSE-11's digit screen -- and each extracted value crosses the one
    # decode boundary once, retag-then-transcode with both encodings named (P7-26), so a NUL or a
    # non-digit cannot be lost to a replacement character first and the caps count bytes.
    #
    # Field names are compared CASE-SENSITIVELY (P7-24): WHATWG compares them exactly and SSE-7
    # names four lowercase tokens, so `DATA:` is an unknown field, silently discarded. The event
    # name is never defaulted to "message" (SSE-10). The retry value is screened by an anchored
    # digits-only pattern and not by Integer(), which accepts "+5", "0x10", "1_0" and " 5", and
    # is ignored above MAX_RETRY_MS rather than wrapped (SSE-11) -- a MUST about the retry field's
    # value, and NOT the line cap, which is SSE-19's and LineReader's.
    #
    # SSE-16: the reader is single-pass and the ONE thing that persists across calls is the
    # "BOM already consumed" flag. No last-event-id is carried forward (SSE-38) and no retry value
    # is: every accumulator resets at dispatch. The BOM is consumed on the FIRST pull, never at
    # construction, through the source's non-consuming #peek (SSE-12): a reader built and never
    # pulled touches its source zero times, and a non-BOM prefix is left intact.
    #
    # The reader owns nothing and closes nothing (SSE-17); ownership arrives with Stream. It is
    # single-threaded by contract and holds no lock (SSE-18, the MAY taken): a reader instance is
    # driven from one thread at a time, and the facade's cross-thread close is a different object
    # guarding a different thing.
    class Reader # rubocop:disable Metrics/ClassLength -- the field machine in one auditable class: the BOM, the five accumulators and the four field rules; see above
      BOM = [0xEF, 0xBB, 0xBF].freeze
      COLON = 0x3A
      SPACE = 0x20
      COLON_BYTES = ":".b.freeze
      NUL_BYTES = "\x00".b.freeze
      EMPTY_BYTES = "".b.freeze
      FIELD_ID = "id".b.freeze
      FIELD_EVENT = "event".b.freeze
      FIELD_DATA = "data".b.freeze
      FIELD_RETRY = "retry".b.freeze
      # SSE-11: "accepted only if it consists solely of ASCII digits 0-9". Anchored, per-pattern
      # timeout (design §4), never the process-global Regexp.timeout. A run longer than the cap's
      # own ten digits is refused before it is parsed at all.
      DIGITS_ONLY = ::Regexp.new("\\A[0-9]+\\z", timeout: 1.0).freeze
      MAX_RETRY_DIGITS = MAX_RETRY_MS.to_s.bytesize
      private_constant :BOM, :COLON, :SPACE, :COLON_BYTES, :NUL_BYTES, :EMPTY_BYTES, :FIELD_ID,
                       :FIELD_EVENT, :FIELD_DATA, :FIELD_RETRY, :DIGITS_ONLY, :MAX_RETRY_DIGITS

      # SSE-19's line cap, as this reader's LineReader was configured.
      attr_reader :max_line_bytes

      # SSE-19's event cap, as this reader was configured: the raw bytes of every line of one
      # block, comments and unknown fields included, reset at every blank line -- dispatching
      # or not -- so the total is one block's and never a run of fieldless blocks'.
      attr_reader :max_event_bytes

      # @param source [Dexpace::SSE::_ByteSource] anything answering #getbyte, #peek and #skip --
      #   a Dexpace::IO::BufferedSource, or a duck; checked with respond_to?, never is_a?
      # @param max_line_bytes [Integer] SSE-19's line cap; MAX_LINE_BYTES by default
      # @param max_event_bytes [Integer] SSE-19's event cap; MAX_EVENT_BYTES by default
      # @raise [Dexpace::InvalidArgumentError] for a source missing one of the three methods or a
      #   cap that is not a positive Integer
      def initialize(source, max_line_bytes: MAX_LINE_BYTES, max_event_bytes: MAX_EVENT_BYTES)
        unless %i[getbyte peek skip].all? { |name| source.respond_to?(name) }
          raise InvalidArgumentError,
                "a reader's source must respond to #getbyte, #peek and #skip (SSE-12), got " \
                "#{source.class}"
        end
        unless max_event_bytes.is_a?(::Integer) && max_event_bytes.positive?
          raise InvalidArgumentError,
                "max_event_bytes must be a positive Integer, got #{max_event_bytes.inspect}"
        end

        @source = source
        @lines = LineReader.new(source, max_line_bytes: max_line_bytes)
        @max_line_bytes = @lines.max_line_bytes
        @max_event_bytes = max_event_bytes
        @bom_checked = false
        @ended = false
        reset_block
      end

      # The next event, or nil once the source is exhausted with nothing pending -- Ruby's
      # stream-terminator sentinel, stable because an Event is never nil and sticky because the
      # end is a latch on the reader (SSE-15, P7-22). The source is pulled only as far as this
      # event's terminating blank line (SSE-39).
      #
      # @return [Event, nil]
      # @raise [Dexpace::SSE::LimitExceededError] when a line or the block crosses its cap
      def next_event
        return nil if @ended

        consume_bom_once unless @bom_checked
        loop do
          line = @lines.next_line
          if line.nil?
            @ended = true
            return dispatch # SSE-14: a pending block, or nil
          end
          if line.empty?
            event = dispatch
            return event unless event.nil? # SSE-13: a fieldless block is skipped
          else
            apply_line(line)
          end
        end
      end

      private

      # SSE-12: one non-consuming lookahead through #peek, the view closed before the parent
      # advances (open question 2); #skip(3) only after all three bytes matched, since #skip on a
      # shorter source raises rather than skipping what is there.
      def consume_bom_once
        @bom_checked = true
        @source.skip(BOM.size) if bom_ahead?
        nil
      end

      # Up to three bytes off a peek view, closed whatever they were; `all?` stops at the first
      # mismatch or at the view's nil, so a shorter stream is never over-read.
      def bom_ahead?
        view = @source.peek
        begin
          BOM.each { |expected| return false unless view.getbyte == expected }
          true
        ensure
          view.close
        end
      end

      # SSE-13: an Event when any field was seen, nil otherwise -- and the block resets EITHER
      # way, its five accumulators and SSE-19's byte total alike, because a blank line ends a
      # block whether or not it dispatched (SSE-1). A run of fieldless blocks -- unknown-field
      # keep-alives, NUL ids, rejected retries -- is a run of blocks and not one block, so their
      # bytes must not add up across the blank lines that separate them into a spurious event-cap
      # failure -- which a nil branch that returned before the reset would produce.
      def dispatch
        event = build_event if @seen
        reset_block
        event
      end

      def build_event
        Event.build(id: @id, event: @event, data: @data, comment: @comment, retry: @retry)
      end

      def reset_block
        @seen = false
        @id = nil
        @event = nil
        @data = [] #: Array[String]
        @comment = nil
        @retry = nil
        @block_bytes = 0
        nil
      end

      # One BINARY line into the block: SSE-19's event count first, then SSE-6's comment test on
      # the first byte, then SSE-3's split at the first colon.
      def apply_line(line)
        @block_bytes += line.bytesize
        if @block_bytes > @max_event_bytes
          raise LimitExceededError.new(kind: :event, limit: @max_event_bytes)
        end

        if line.getbyte(0) == COLON
          @comment = decode(value_after(line, 0))
          @seen = true
          return
        end

        colon = line.index(COLON_BYTES)
        if colon.nil?
          apply_field(line, EMPTY_BYTES)
        else
          apply_field(line.byteslice(0, colon) || EMPTY_BYTES, value_after(line, colon))
        end
      end

      # SSE-7: the four names, exactly; anything else sets no state and counts as nothing.
      def apply_field(name, value)
        case name
        when FIELD_DATA
          @data << decode(value) # SSE-8: unjoined, in wire order
          @seen = true
        when FIELD_EVENT
          @event = decode(value) # SSE-10: raw, latest-wins, never defaulted
          @seen = true
        when FIELD_ID then apply_id(value)
        when FIELD_RETRY then apply_retry(value)
        end
      end

      # SSE-9: a NUL anywhere in the RAW value ignores the field entirely -- no id, no "field
      # seen", no overwrite of a valid id -- before the decode could turn the NUL into anything.
      def apply_id(value)
        return if value.include?(NUL_BYTES)

        @id = decode(value)
        @seen = true
      end

      # SSE-11: digits only, at most the cap's own width, at most the cap; else ignored, and an
      # ignored retry does not count as a field seen.
      def apply_retry(value)
        return if value.bytesize > MAX_RETRY_DIGITS || !DIGITS_ONLY.match?(value)

        milliseconds = Integer(value, 10)
        return if milliseconds > MAX_RETRY_MS

        @retry = milliseconds
        @seen = true
      end

      # SSE-5: the bytes after position `after`, minus exactly one leading U+0020.
      def value_after(line, after)
        rest = line.byteslice(after + 1, line.bytesize - after - 1) || EMPTY_BYTES
        return rest unless rest.getbyte(0) == SPACE

        rest.byteslice(1, rest.bytesize - 1) || EMPTY_BYTES
      end

      # P7-26: the one decode boundary, retag then transcode, both encodings named.
      # `String#b` first because a frozen slice refuses force_encoding; `invalid: :replace`
      # because WHATWG decodes with replacement and a raise would fail a stream on one byte.
      def decode(bytes)
        retagged = bytes.b.force_encoding(::Encoding::UTF_8)
        retagged.encode(::Encoding::UTF_8, ::Encoding::UTF_8, invalid: :replace, undef: :replace)
          .freeze
      end
    end
  end
end
