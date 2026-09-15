# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../io"
require_relative "../error/end_of_stream_error"
require_relative "../error/stream_error"
require_relative "../error/invalid_argument_error"
require_relative "../error/closed_error"
require_relative "../error/seam_error"

module Dexpace
  module IO
    # The read vocabulary, supplied over one private hook the includer defines:
    # #fill(min_bytes) -> Integer, the number of bytes it appended to the store (0 at end of
    # stream). Dexpace::Closeable set the initialize_*-plus-one-hook precedent in phase 2 and this
    # follows it exactly; an includer must also include Dexpace::Closeable, which
    # #initialize_typed_reads asserts.
    #
    # Public, and not private_constant, for two reasons that are each sufficient (P3-8). The
    # runtime surface snapshot walks each class's public_instance_methods(false), which does NOT
    # see a method reaching a class through an included module, so a private module would hide
    # almost the whole of 3a from the gate that exists to see it. And a third-party source that
    # supplies #fill gets the entire read vocabulary by including this, which is the Ruby shape of
    # the reference's BufferedSource interface.
    #
    # #slice and #peek name Dexpace::IO::BufferedSource at call time rather than requiring it,
    # because buffered_source.rb requires this file. lib/dexpace.rb requires the whole tree, so
    # the constant is always resolvable by the time a caller can reach these methods.
    module TypedReads # rubocop:disable Metrics/ModuleLength -- the whole read vocabulary by design; see above
      # The line machine reads these; they are here because a constant belongs at the top.
      NEWLINE = "\n".b.freeze
      CARRIAGE_RETURN = "\r".b.freeze

      # The read size for the two readers that have no caller count -- #each and #drain_all.
      # Symmetric to TypedWrites::WRITE_ALL_SEGMENT_BYTES and private for the same reason: it is
      # not NFR-4 surface, so phase 5 is free to make it a setting without widening a public
      # signature. It exists because a literal 1 here asks a wrapped stream for one byte per
      # readpartial call (the plan's Task 10, 2026-09-13 amendment).
      READ_SEGMENT_BYTES = 64 * 1024

      private_constant :NEWLINE, :CARRIAGE_RETURN, :READ_SEGMENT_BYTES

      # Call from the including class's #initialize, after #initialize_closeable.
      def initialize_typed_reads
        unless is_a?(Dexpace::Closeable)
          raise Dexpace::SeamError,
                "#{self.class} includes Dexpace::IO::TypedReads and must also include " \
                "Dexpace::Closeable"
        end

        @dexpace_chunks = [] #: Array[String]
        @dexpace_head = 0
        @dexpace_buffered = 0
        @dexpace_consumed = 0
        @dexpace_views = [] #: Array[Dexpace::IO::TypedReads]
        @dexpace_invalidated = false
        nil
      end

      # IO-1's primitive, and deliberately not called #read (P3-1). It APPENDS to the tail of
      # `dest`; #read and #readpartial overwrite, because IO.copy_stream hands them one buffer it
      # reuses across every call.
      #
      # Returns at least 1 when count is positive and the source is not exhausted, exactly 0 when
      # count is 0 (IO-2), -1 when exhausted before any byte, and never more than count.
      def read_into(dest, count:)
        ensure_typed_reads_initialized
        # IO-3 first, before any I/O and before the buffer is consulted.
        validate_destination!(dest)
        validate_count!(count, name: "count")
        # IO-42 next: a closed stream-backed source rejects every read attempt, count 0 included.
        # IO-2's clause is about an OPEN source's exhaustion, so it cannot swallow this.
        ensure_readable
        # IO-2: 0 for a zero count, never -1, without touching the buffer or the upstream.
        return 0 if count.zero?

        # The caller's own count reaches the upstream, so a wrapped stream is asked for `count`
        # bytes and not for one. Filling ONCE, not to `count`: blocking until `count` bytes or
        # end of stream is #read(n)'s contract, not the primitive's, and IO-1 asks only for
        # "at least 1 when the source is not exhausted".
        fill_once_if_empty(count)
        return -1 if @dexpace_buffered.zero?

        taken = [count, @dexpace_buffered].min
        dest << store_take(taken)
        taken
      end

      # IO-12: exactly count bytes or an EOF error. Never a short result, and never a partial
      # consumption -- the bytes stay buffered when it raises.
      def read_exactly(count)
        ensure_typed_reads_initialized
        validate_count!(count, name: "count")
        ensure_readable
        guard_materialization!(count)
        return (+"").b if count.zero?

        ensure_buffered(count)
        raise_end_of_stream("read_exactly(#{count})") if @dexpace_buffered < count

        store_take(count)
      end

      # IO-11/IO-16: the next byte as an unsigned 0..255, or nil at end of stream.
      def getbyte
        ensure_typed_reads_initialized
        ensure_readable
        fill_once_if_empty
        return nil if @dexpace_buffered.zero?

        store_take(1).getbyte(0)
      end

      # IO-11's readByte(): the next byte, or an EOF error when none remain.
      def readbyte
        ensure_typed_reads_initialized
        ensure_readable
        fill_once_if_empty
        raise_end_of_stream("readbyte") if @dexpace_buffered.zero?

        store_take(1).getbyte(0) || raise_end_of_stream("readbyte")
      end

      # IO-12/IO-13. `count` is a BYTE count, not a character count. With none, drains.
      def read_utf8(count: nil)
        read_string(::Encoding::UTF_8, count: count)
      end

      # IO-13. Retags the bytes with the encoding the caller named and validates nothing:
      # #valid_encoding? is the caller's question and HTTP-42's replacement policy is 3b's, at the
      # one decode boundary design §3.1 permits.
      def read_string(encoding, count: nil)
        ensure_typed_reads_initialized
        target = resolve_encoding(encoding)
        ensure_readable
        bytes =
          if count.nil?
            drain_all
          else
            validate_count!(count, name: "count")
            guard_materialization!(count)
            ensure_buffered(count)
            raise_end_of_stream("read_string(#{count})") if @dexpace_buffered < count

            store_take(count)
          end
        bytes.force_encoding(target)
      end

      # IO-15: exactly count bytes, an EOF error if fewer remain, and skip(0) a no-op even at or
      # after EOF.
      def skip(count)
        ensure_typed_reads_initialized
        validate_count!(count, name: "count")
        ensure_readable
        return nil if count.zero?

        ensure_buffered(count)
        raise_end_of_stream("skip(#{count})") if @dexpace_buffered < count

        store_drop(count)
        nil
      end

      # IO-11's exhausted(). May block while the upstream decides.
      def eof?
        ensure_typed_reads_initialized
        ensure_readable
        fill_once_if_empty
        @dexpace_buffered.zero?
      end

      # IO-14. Hand-implemented over the byte store, never #gets: $/ is global and universal
      # newline handling depends on how the IO was opened. "\n" and "\r\n" terminate, a lone "\r"
      # is content, a final unterminated line comes back as-is, nil when exhausted before a byte.
      #
      # Unbounded on purpose (P3-4): the one drain-style read MAX_MATERIALIZED_BYTES does not
      # guard, because a line has no count to check and no end but a terminator that may never
      # arrive. IO-14 fixes no line length; the caller that reads lines from a hostile stream is
      # phase 7's SSE machine, whose own documented cap SSE-11 requires (phase 7b's plan, Task 12).
      def read_line_utf8
        ensure_typed_reads_initialized
        ensure_readable
        scanned = 0
        loop do
          index = store_index_of(NEWLINE, scanned)
          return finish_line(store_take(index), terminated: true) unless index.nil?

          scanned = @dexpace_buffered
          break if ensure_buffered(scanned + 1) == scanned
        end
        return nil if @dexpace_buffered.zero?

        finish_line(store_take(@dexpace_buffered), terminated: false)
      end

      # IO-16's host-native bulk read: Ruby's semantics exactly, so IO.copy_stream can drive it.
      # It OVERWRITES outbuf where #read_into appends, keeps filling until it has `length` bytes
      # or the stream ends, and returns nil at EOF for a positive length and "" at EOF with no
      # length. With no length it is also IO-11's count-less byte-array read.
      #
      # P3-13: outbuf comes back tagged Encoding::BINARY whatever it arrived as. ::IO#read
      # preserves the destination's tag on all three interpreters and StringIO#read changed at
      # exactly Ruby 3.4, so Ruby's own readers disagree with each other and across this port's
      # floor; pinning BINARY is what makes 3a's answer the same on every matrix row and behind
      # every backing stream. IO.copy_stream does not read the tag, which is what keeps the
      # bridge claim true.
      def read(length = nil, outbuf = nil)
        ensure_typed_reads_initialized
        validate_count!(length, name: "length") unless length.nil?
        ensure_readable
        data = length.nil? ? drain_all : read_up_to(length)
        if data.nil?
          outbuf&.replace((+"").b)
          return nil
        end
        return data if outbuf.nil?

        outbuf.replace(data)
      end

      # IO-16's host-native partial read. Overwrites outbuf; raises at EOF, and the class is a
      # ::EOFError subclass so IO.copy_stream terminates on it rather than propagating it.
      def readpartial(maxlen, outbuf = nil)
        ensure_typed_reads_initialized
        validate_count!(maxlen, name: "maxlen")
        ensure_readable
        data =
          if maxlen.zero?
            (+"").b
          else
            fill_once_if_empty(maxlen)
            raise_end_of_stream("readpartial(#{maxlen})") if @dexpace_buffered.zero?

            store_take([maxlen, @dexpace_buffered].min)
          end
        return data if outbuf.nil?

        outbuf.replace(data)
      end

      # Design §10.2: yields BINARY chunks until exhausted, so a source IS a canonical body
      # representation. On the .over path the granularity is whatever the upstream produced --
      # .over must preserve the wrapped body's own chunking for BODY-17's byte-exact mirroring to
      # mean what it says. On the .wrapping path there is no caller chunking to preserve and no
      # caller count to pass, so the read size is READ_SEGMENT_BYTES; a literal 1 here asked a
      # wrapped stream for one byte per readpartial call (the plan's Task 10 amendment).
      #
      # §7.1: the resource lives on the instance and #close is on the instance, so an Enumerator
      # abandoned mid-#next leaks nothing #close would not still release.
      def each
        return to_enum(:each) unless block_given?

        ensure_typed_reads_initialized
        ensure_readable
        loop do
          chunk = store_take_chunk
          if chunk.nil?
            break if fill_once_if_empty(READ_SEGMENT_BYTES).zero?

            next
          end
          yield chunk
        end
        nil
      end

      # IO-19: a non-consuming view over the whole remaining source -- a length no stream-backed
      # source knows, so the window is unbounded (nil) and not "whatever happens to be buffered".
      def peek
        ensure_typed_reads_initialized
        ensure_readable
        build_view(offset: 0, window: nil)
      end

      # IO-20/IO-21/IO-23. Negative offset or count is rejected eagerly; an offset past the end is
      # detected LAZILY, on the first read, as an empty/EOF result.
      def slice(offset:, count:)
        ensure_typed_reads_initialized
        validate_count!(offset, name: "offset")
        validate_count!(count, name: "count")
        ensure_readable
        build_view(offset: offset, window: count)
      end

      protected

      # The view protocol. Protected rather than public because a view drives its parent and
      # nothing else may: these are not NFR-4 surface.
      def dexpace_consumed
        @dexpace_consumed
      end

      # The two entry points a view drives its parent through check the parent's own readability
      # first (IO-22, IO-42): a closed stream-backed parent, or an invalidated intermediate view,
      # serves nothing to a view derived from it, however the view was reached.
      def dexpace_ensure_buffered(target)
        ensure_readable
        ensure_buffered(target)
      end

      def dexpace_window_copy(offset, count)
        ensure_readable
        store_peek(offset, count)
      end

      def dexpace_register_view(view)
        @dexpace_views << view
        nil
      end

      def dexpace_forget_view(view)
        @dexpace_views.delete(view)
        nil
      end

      # Invalidation cascades: a view is itself a source with views of its own, and IO-22's
      # "every outstanding slice derived from it" reaches a slice of a slice.
      def dexpace_invalidate
        @dexpace_invalidated = true
        dexpace_release_views
      end

      # IO-22/IO-42: an includer's #release MUST call this, so a close on this object invalidates
      # every view derived from it and a later read on one of those views fails loudly rather than
      # returning stale or arbitrary bytes. Buffer and BufferedSource both do.
      #
      # The block form is load-bearing: #dexpace_invalidate is protected, and `&:dexpace_invalidate`
      # would send it publicly (NoMethodError: protected method called).
      def dexpace_release_views
        @dexpace_views.each { |view| view.dexpace_invalidate } # rubocop:disable Style/SymbolProc
        @dexpace_views.clear
        nil
      end

      # The bytes this object can still serve when it knows -- a length-bounded view -- and nil
      # when it does not, which is every root source and every peek.
      def dexpace_remaining_window
        nil
      end

      private

      # IO-22/IO-38/IO-42. One Thread::Mutex acquisition per public entry point, through
      # Closeable#closed?, and it is never held across a fill, a read, a drain or a #release.
      def ensure_readable
        if @dexpace_invalidated
          raise Dexpace::ClosedError,
                "this #{self.class} was invalidated by a close on the source it was derived from"
        end
        return unless closed?
        return if reads_survive_close?

        raise Dexpace::ClosedError, "#{self.class} is closed"
      end

      # IO-42's in-memory exemption. Only Dexpace::IO::Buffer answers true.
      def reads_survive_close?
        false
      end

      def ensure_typed_reads_initialized
        return if defined?(@dexpace_chunks) && @dexpace_chunks

        raise Dexpace::SeamError,
              "#{self.class} includes Dexpace::IO::TypedReads but never called " \
              "#initialize_typed_reads"
      end

      def fill(_min_bytes)
        raise NotImplementedError,
              "#{self.class} includes Dexpace::IO::TypedReads and must define a private " \
              "#fill(min_bytes)"
      end

      # Fills ONCE, with the count its caller has. The default of 1 is for the readers that
      # genuinely want one byte -- #getbyte, #readbyte and #eof?; #read_into passes its `count`
      # and #readpartial its `maxlen`, so the min_bytes reaching #fill, and therefore
      # readpartial(want) in BufferedSource, is the number the caller asked for.
      # It calls #fill ONCE and never loops: #ensure_buffered(min_bytes) would block until
      # min_bytes bytes or end of stream, which is #read(n)'s contract and not the primitive's.
      def fill_once_if_empty(min_bytes = 1)
        fill(min_bytes) if @dexpace_buffered.zero?
        @dexpace_buffered
      end

      def ensure_buffered(target)
        while @dexpace_buffered < target
          added = fill(target - @dexpace_buffered)
          break if added.nil? || added <= 0
        end
        @dexpace_buffered
      end

      # THE ingress retag, and the one place it happens. Verified facts 3 and 4: force_encoding on
      # a frozen String raises FrozenError even when the target encoding is already the string's
      # own, and a Rack-style body's #each yields frozen literals under this repository's own
      # frozen_string_literal pragma. String#b always returns a new, unfrozen copy. So: keep the
      # chunk when it is both frozen and already BINARY, and #b it otherwise. force_encoding
      # appears nowhere on this path.
      #
      # The compaction invariant this buys: every chunk in the store is a FROZEN BINARY String, so
      # a chunk is copied at most once on the way in -- and exactly zero times when the upstream
      # already yields frozen BINARY chunks, which is the ordinary Rack shape -- and no view can
      # ever see a chunk mutated behind its back. The upstream's own return is deliberately NOT
      # frozen in place: a duck-typed #readpartial that reuses one buffer would break if it were.
      def store_append(chunk)
        return 0 if chunk.nil? || chunk.empty?

        stored =
          if chunk.frozen? && chunk.encoding == ::Encoding::BINARY
            chunk
          else
            chunk.b.freeze
          end
        @dexpace_chunks << stored
        @dexpace_buffered += stored.bytesize
        stored.bytesize
      end

      # O(1) amortised: a fully consumed chunk is shifted off, a partially consumed head chunk is
      # left in place behind a moving @dexpace_head and is never bytesliced to compact it. The
      # byteslice that produces the caller's bytes is the only copy those bytes get -- a read that
      # fits inside the head chunk returns that one byteslice, with no second String and no `<<`.
      def store_take(count)
        return (+"").b if count.zero?

        out = take_from_head(count)
        out << take_from_head(count - out.bytesize) while out.bytesize < count
        @dexpace_buffered -= count
        @dexpace_consumed += count
        out
      end

      # Up to `count` bytes out of the head chunk alone, as a fresh unfrozen BINARY String
      # (String#byteslice of a frozen String is unfrozen, verified on 3.2.11, 3.4.10 and 4.0.6).
      def take_from_head(count)
        head = @dexpace_chunks.fetch(0)
        available = head.bytesize - @dexpace_head
        take = [count, available].min
        out = head.byteslice(@dexpace_head, take) || (+"").b
        advance_head(take, available)
        out
      end

      def store_drop(count)
        remaining = count
        while remaining.positive?
          head = @dexpace_chunks.fetch(0)
          available = head.bytesize - @dexpace_head
          take = [remaining, available].min
          advance_head(take, available)
          remaining -= take
        end
        @dexpace_buffered -= count
        @dexpace_consumed += count
        nil
      end

      def advance_head(taken, available)
        if taken == available
          @dexpace_chunks.shift
          @dexpace_head = 0
        else
          @dexpace_head += taken
        end
        nil
      end

      # Non-consuming: copies a window `offset` bytes ahead of the cursor. This is how a view
      # reads its parent without advancing the parent. A zero `count` copies nothing: the first
      # chunk's (possibly empty) byteslice fills the window and the loop leaves.
      def store_peek(offset, count)
        out = (+"").b
        skip = offset
        head_offset = @dexpace_head
        @dexpace_chunks.each do |chunk|
          available = chunk.bytesize - head_offset
          if skip < available
            # byteslice clamps the length to what the chunk holds past `start`.
            out << chunk.byteslice(head_offset + skip, count - out.bytesize).to_s
            break if out.bytesize >= count
          end
          skip = [skip - available, 0].max
          head_offset = 0
        end
        out
      end

      def validate_count!(value, name:)
        unless value.is_a?(::Integer)
          raise Dexpace::InvalidArgumentError,
                "#{name} must be an Integer, got #{value.class}"
        end
        return unless value.negative?

        raise Dexpace::InvalidArgumentError, "#{name} must not be negative, got #{value}"
      end

      # IO-3's eager rejection. A non-BINARY destination is rejected because appending a
      # non-ASCII UTF-8 payload to a BINARY String silently retags the RESULT to UTF-8 while an
      # ASCII-only one does not -- so a UTF-8 dest would produce a buffer whose tag depends on the
      # payload's content. A frozen dest is rejected because a FrozenError from deep inside is a
      # crash, not a rejection.
      def validate_destination!(dest)
        unless dest.is_a?(::String)
          raise Dexpace::InvalidArgumentError, "dest must be a String, got #{dest.class}"
        end
        if dest.frozen?
          raise Dexpace::InvalidArgumentError, "dest must not be frozen: #read_into appends to it"
        end
        return if dest.encoding == ::Encoding::BINARY

        raise Dexpace::InvalidArgumentError,
              "dest must be tagged #{::Encoding::BINARY}, got #{dest.encoding}"
      end

      def raise_end_of_stream(operation)
        raise Dexpace::EndOfStreamError,
              "#{operation} reached the end of the stream with #{@dexpace_buffered} " \
              "bytes buffered"
      end

      # #each's granularity: the whole remaining head chunk, so the wrapped body's own chunking
      # survives .over.
      def store_take_chunk
        return nil if @dexpace_buffered.zero?

        head = @dexpace_chunks.fetch(0)
        store_take(head.bytesize - @dexpace_head)
      end

      # IO-9 (P3-4). The ceiling is checked against the known count before anything is allocated,
      # and against the running total on a drain, so nothing over it is ever materialised.
      def drain_all
        guard_materialization!(materialization_hint)
        out = (+"").b
        loop do
          chunk = store_take_chunk
          if chunk.nil?
            break if fill_once_if_empty(READ_SEGMENT_BYTES).zero?

            next
          end
          out << chunk
          guard_materialization!(out.bytesize)
        end
        out
      end

      # The known remaining byte count when there is one -- a length-bounded view -- and nil
      # otherwise. IO-9's "length-bounded slice reads apply the same guarded, message-bearing cap".
      def materialization_hint
        dexpace_remaining_window
      end

      def guard_materialization!(count)
        return if count.nil?
        return if count <= Dexpace::IO::MAX_MATERIALIZED_BYTES

        raise Dexpace::StreamError,
              "refusing to materialize #{count} bytes as one String: the limit is " \
              "#{Dexpace::IO::MAX_MATERIALIZED_BYTES} bytes " \
              "(Dexpace::IO::MAX_MATERIALIZED_BYTES). Stream it instead -- #read_into, #each, " \
              "#slice or Buffer#copy_to."
      end

      def resolve_encoding(encoding)
        return encoding if encoding.is_a?(::Encoding)

        ::Encoding.find(encoding.to_s) ||
          raise(Dexpace::InvalidArgumentError, "unknown encoding #{encoding.inspect}")
      rescue ::ArgumentError => error
        raise Dexpace::InvalidArgumentError,
              "unknown encoding #{encoding.inspect}: #{error.message}"
      end

      # The byte offset (from the cursor) of the first `byte` at or after `from`, searching across
      # chunk boundaries and respecting a partially consumed head chunk, which is what makes the
      # line rule survive a slice window. nil when the buffered bytes hold none.
      def store_index_of(byte, from)
        position = 0
        head_offset = @dexpace_head
        @dexpace_chunks.each do |chunk|
          available = chunk.bytesize - head_offset
          if position + available > from
            start = head_offset + (from > position ? from - position : 0)
            found = chunk.byteindex(byte, start)
            return position + (found - head_offset) unless found.nil?
          end
          position += available
          head_offset = 0
        end
        nil
      end

      # The "\r" is stripped only when it immediately precedes the "\n" the scan found, which is
      # exactly IO-14's "a lone '\r' not followed by '\n' MUST be kept".
      def finish_line(bytes, terminated:)
        if terminated
          store_drop(1)
          bytes = bytes.byteslice(0, bytes.bytesize - 1).to_s if bytes.end_with?(CARRIAGE_RETURN)
        end
        bytes.force_encoding(::Encoding::UTF_8)
      end

      def read_up_to(length)
        return (+"").b if length.zero?

        ensure_buffered(length)
        return nil if @dexpace_buffered.zero?

        store_take([length, @dexpace_buffered].min)
      end

      # IO-23: the child's offset composes additively (the pin is measured from this object's own
      # cursor) and its window is capped at this object's remaining window, when it has one. A
      # nil window is unbounded -- a peek, or a peek of a peek.
      def build_view(offset:, window:)
        remaining = dexpace_remaining_window
        unless remaining.nil?
          headroom = [remaining - offset, 0].max
          window = window.nil? ? headroom : [window, headroom].min
        end
        view = Dexpace::IO::BufferedSource.__dexpace_view(
          parent: self, pin: @dexpace_consumed + offset, window: window,
        )
        dexpace_register_view(view)
        view
      end
    end
  end
end
