# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../io"
require_relative "../error/stream_error"
require_relative "../error/invalid_argument_error"
require_relative "../error/closed_error"
require_relative "../error/seam_error"

module Dexpace
  module IO
    # The write vocabulary, symmetric to TypedReads and supplied over one private hook the
    # includer defines: #deliver(string) -> void, which pushes BINARY bytes one level toward the
    # includer's destination. An includer must also include Dexpace::Closeable.
    #
    # Public and not private_constant for TypedReads' two reasons (P3-8).
    #
    # It carries its own #validate_count! and #resolve_encoding rather than sharing TypedReads',
    # because each module must stand alone: a third-party sink that supplies #deliver gets the
    # whole write vocabulary by including this one and nothing else.
    #
    # The hook's contract, stated once: everything handed to #deliver is a FROZEN BINARY String.
    # #binary_of, #encode_to, #write_all and #write_from each freeze what they produce, so a
    # Buffer's #store_append keeps it with no second copy and a caller that reuses its own buffer
    # cannot reach what was already written.
    module TypedWrites # rubocop:disable Metrics/ModuleLength -- the whole write vocabulary by design; see above
      # The pump's read granularity. Private, so it is not NFR-4 surface and phase 5 is free to
      # make it a setting without widening a public signature.
      WRITE_ALL_SEGMENT_BYTES = 64 * 1024

      private_constant :WRITE_ALL_SEGMENT_BYTES

      # Call from the including class's #initialize, after #initialize_closeable.
      def initialize_typed_writes
        unless is_a?(Dexpace::Closeable)
          raise Dexpace::SeamError,
                "#{self.class} includes Dexpace::IO::TypedWrites and must also include " \
                "Dexpace::Closeable"
        end

        @dexpace_writes_ready = true
        nil
      end

      # IO-4: removes exactly `count` bytes from the HEAD of `buffer` and pushes them downstream.
      # If the buffer holds fewer, this fails with an I/O error rather than writing a short amount
      # -- and it consumes nothing, so the buffer is still usable after the rejection.
      def write_from(buffer, count:)
        ensure_typed_writes_initialized
        validate_count!(count, name: "count")
        unless buffer.is_a?(Dexpace::IO::Buffer)
          raise Dexpace::InvalidArgumentError,
                "write_from takes a Dexpace::IO::Buffer, got #{buffer.class}"
        end

        ensure_writable
        available = buffer.bytesize
        if available < count
          raise Dexpace::StreamError.short_transfer(transferred: available, expected: count)
        end
        return nil if count.zero?

        deliver(buffer.read_exactly(count).freeze)
        nil
      end

      # IO-16's host-native writable bridge: returns the byte count, which is what
      # IO.copy_stream requires of a destination. Positional splat, exactly like ::IO#write --
      # P3-9's stated exception, because a keyword here would make IO.copy_stream fail.
      def write(*strings)
        ensure_typed_writes_initialized
        ensure_writable
        total = 0
        strings.each do |string|
          bytes = binary_of(string)
          next if bytes.empty?

          deliver(bytes)
          total += bytes.bytesize
        end
        total
      end

      # IO-17: pumps `source` to exhaustion through IO-1's primitive and returns the total.
      # It terminates ONLY on a -1 read, and a read of 0 for a positive requested count is a
      # source-contract violation raised as an I/O error -- never tolerated as EOF, never spun on.
      #
      # The check is unconditional rather than scoped to a "foreign" source: design §10.1 retired
      # the adapter, so "adapter-native" has no subject in this port, and a correct source never
      # returns 0 for a positive count anyway.
      def write_all(source)
        ensure_typed_writes_initialized
        unless source.respond_to?(:read_into)
          raise Dexpace::InvalidArgumentError,
                "write_all takes a source responding to #read_into, got #{source.class}"
        end

        ensure_writable
        total = 0
        loop do
          chunk = (+"").b
          transferred = source.read_into(chunk, count: WRITE_ALL_SEGMENT_BYTES)
          break if transferred == -1

          if transferred.zero?
            raise Dexpace::StreamError.zero_read(requested: WRITE_ALL_SEGMENT_BYTES)
          end

          deliver(chunk.freeze)
          total += transferred
        end
        total
      end

      # IO-13. `range` is a CHARACTER range over the String, the reference's substring form.
      def write_utf8(string, range: nil)
        write_string(range.nil? ? string : sliced(string, range), encoding: ::Encoding::UTF_8)
      end

      # IO-13's symmetric explicit-charset write.
      def write_string(string, encoding:)
        ensure_typed_writes_initialized
        unless string.is_a?(::String)
          raise Dexpace::InvalidArgumentError, "string must be a String, got #{string.class}"
        end

        target = resolve_encoding(encoding)
        ensure_writable
        bytes = encode_to(string, target)
        deliver(bytes) unless bytes.empty?
        nil
      end

      # IO-5/IO-18. #emit is the cheap one-level hand-off -- staging buffer to underlying stream --
      # and does NOT force a system-level flush; #flush forces bytes all the way out. On a pure
      # in-memory buffer both are the no-ops IO-18 explicitly permits.
      def emit
        ensure_typed_writes_initialized
        ensure_writable
        push_one_level
        self
      end

      # IO-5: pushes what is staged all the way out, the underlying stream's own #flush included.
      def flush
        ensure_typed_writes_initialized
        ensure_writable
        push_all
        self
      end

      private

      # IO-42, through Closeable#closed? -- one Thread::Mutex acquisition per public entry point.
      def ensure_writable
        return unless closed?
        return if writes_survive_close?

        raise Dexpace::ClosedError, "#{self.class} is closed"
      end

      # IO-42's in-memory exemption. Only Dexpace::IO::Buffer answers true.
      def writes_survive_close?
        false
      end

      def ensure_typed_writes_initialized
        return if defined?(@dexpace_writes_ready) && @dexpace_writes_ready

        raise Dexpace::SeamError,
              "#{self.class} includes Dexpace::IO::TypedWrites but never called " \
              "#initialize_typed_writes"
      end

      def deliver(_string)
        raise NotImplementedError,
              "#{self.class} includes Dexpace::IO::TypedWrites and must define a private " \
              "#deliver(string)"
      end

      def push_one_level
        nil
      end

      def push_all
        push_one_level
      end

      def sliced(string, range)
        unless string.is_a?(::String)
          raise Dexpace::InvalidArgumentError, "string must be a String, got #{string.class}"
        end

        part = string[range]
        if part.nil?
          raise Dexpace::InvalidArgumentError, "range #{range.inspect} is outside the string"
        end

        part
      end

      def encode_to(string, target)
        string.encode(target).b.freeze
      rescue ::EncodingError => error
        raise Dexpace::InvalidArgumentError,
              "cannot encode the given String as #{target}: #{error.message}"
      end

      def binary_of(string)
        unless string.is_a?(::String)
          raise Dexpace::InvalidArgumentError, "write takes Strings, got #{string.class}"
        end

        return string if string.frozen? && string.encoding == ::Encoding::BINARY

        # Frozen, so the store keeps it without a second copy and a caller that reuses its own
        # buffer cannot reach what was already written.
        string.b.freeze
      end

      def validate_count!(value, name:)
        unless value.is_a?(::Integer)
          raise Dexpace::InvalidArgumentError, "#{name} must be an Integer, got #{value.class}"
        end
        return unless value.negative?

        raise Dexpace::InvalidArgumentError, "#{name} must not be negative, got #{value}"
      end

      def resolve_encoding(encoding)
        return encoding if encoding.is_a?(::Encoding)

        ::Encoding.find(encoding.to_s) ||
          raise(Dexpace::InvalidArgumentError, "unknown encoding #{encoding.inspect}")
      rescue ::ArgumentError => error
        raise Dexpace::InvalidArgumentError,
              "unknown encoding #{encoding.inspect}: #{error.message}"
      end
    end
  end
end
