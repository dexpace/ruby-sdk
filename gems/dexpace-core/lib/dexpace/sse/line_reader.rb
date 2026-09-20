# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error/invalid_argument_error"
require_relative "../sse"
require_relative "limit_exceeded_error"

module Dexpace
  module SSE
    # SSE-2's line machine: LF, CR and CRLF all terminate, CRLF as ONE terminator, terminators
    # stripped, a lone CR terminating by itself; a final line without a terminator comes back as
    # content (SSE-14); nil once the source is exhausted before any byte.
    #
    # Built over a byte source's #getbyte and NOT over phase 3a's #read_line_utf8, because the
    # two grammars disagree on the one clause that matters: IO-14 requires a lone "\r" be KEPT AS
    # CONTENT and SSE-2 requires it TERMINATE a line (P7-20). Post-processing 3a's result would
    # not do either: a conforming server that terminates with lone CRs sends no "\n" at all, so
    # #read_line_utf8 would buffer the whole stream before returning anything -- the read-ahead
    # SSE-39 forbids and the unbounded allocation the line cap exists to prevent.
    #
    # The one item of state beyond the source is a one-byte pushback: after a CR the machine reads
    # one further byte to tell CR from CRLF, and holds it for the next line when it is not LF.
    # That gives the grammar an inherent property WHATWG shares: a line terminated by a lone CR
    # cannot be handed back until one further byte arrives, because nothing else distinguishes
    # CR from the first half of CRLF. LF- and CRLF-terminated streams are unaffected, since the
    # byte the machine needs is the terminator that has already arrived.
    #
    # SSE-19's cap is checked as the accumulator grows, before each append, so an over-long line
    # is rejected the moment it crosses the bound rather than after it is materialised; the
    # accumulator is one BINARY buffer reused across lines, which keeps the machine
    # allocation-flat on a long stream. Lines are BINARY: decoding is the reader's, per field
    # value (P7-26). The line reader owns nothing and closes nothing (SSE-17).
    class LineReader
      LF = 0x0A
      CR = 0x0D
      private_constant :LF, :CR

      # SSE-19's line cap as this reader was configured, in bytes.
      attr_reader :max_line_bytes

      # @param source [Dexpace::SSE::_ByteSource] anything answering #getbyte -- a
      #   Dexpace::IO::BufferedSource, or a duck; checked with respond_to?, never is_a?
      # @param max_line_bytes [Integer] SSE-19's cap for this reader; MAX_LINE_BYTES by default
      # @raise [Dexpace::InvalidArgumentError] for a source without #getbyte or a cap that is not a
      #   positive Integer
      def initialize(source, max_line_bytes: MAX_LINE_BYTES)
        unless source.respond_to?(:getbyte)
          raise InvalidArgumentError,
                "a line reader's source must respond to #getbyte (SSE-2), got #{source.class}"
        end
        unless max_line_bytes.is_a?(::Integer) && max_line_bytes.positive?
          raise InvalidArgumentError,
                "max_line_bytes must be a positive Integer, got #{max_line_bytes.inspect}"
        end

        @source = source
        @max_line_bytes = max_line_bytes
        @buffer = ::String.new(capacity: 4096, encoding: ::Encoding::BINARY)
        @pushback = nil
      end

      # The next line's content as a fresh frozen BINARY String with its terminator stripped, or
      # nil when the source is exhausted before any byte of it arrived.
      #
      # @return [String, nil]
      # @raise [Dexpace::SSE::LimitExceededError] with `kind: :line` from the pull on which the
      #   line crosses `max_line_bytes`
      def next_line
        buffer = @buffer.clear
        byte = take_byte
        return nil if byte.nil?

        loop do
          break if terminator?(byte)
          raise LimitExceededError.new(kind: :line, limit: @max_line_bytes) if
            buffer.bytesize >= @max_line_bytes

          buffer << byte
          following = take_byte
          break if following.nil? # SSE-14: exhaustion ends an unterminated line as content

          byte = following
        end
        buffer.dup.freeze
      end

      private

      # The pushback first, then the source.
      def take_byte
        held = @pushback
        return @source.getbyte if held.nil?

        @pushback = nil
        held
      end

      # Whether `byte` ends the line. LF does. CR does too, after one further byte decides
      # whether it was CRLF: that byte is consumed when it is LF, held back for the next line
      # otherwise, and a CR at the very end of the stream terminates on its own.
      def terminator?(byte)
        return true if byte == LF
        return false unless byte == CR

        following = @source.getbyte
        @pushback = following unless following.nil? || following == LF
        true
      end
    end
  end
end
