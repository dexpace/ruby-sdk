# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # A Dexpace::Body over the native `Protocol::HTTP::Body::Readable`: lazy, pull-shaped,
      # BINARY, one native `#read` per unit of consumer demand (the design's verified fact 6, and
      # SSE-39's backpressure surviving the transport). Not core's own Dexpace::ResponseBody: that
      # class closes the Dexpace::IO::BufferedSource it was handed, which is right for a source
      # built with `.wrapping` and wrong for one built with `.over`, which owns nothing. This class
      # holds the native body itself, closes IT through its own Closeable latch, and hands out one
      # memoised `.over` source -- a fresh view per call would strand the bytes the first view had
      # buffered.
      #
      # The include order is Dexpace::Body THEN Dexpace::Closeable, so Closeable#close sits nearer
      # the class than the module's no-op default and wins (P3-23). Every failure out of the native
      # read is classified through the token first and is a Dexpace::StreamError otherwise (P3-3):
      # a body shorter than its Content-Length raises a bare EOFError from the library, and a body
      # closed under a blocked read -- which is what a cancellation does, from inside the reactor
      # -- a bare IOError.
      #
      # The native close goes through Dexpace.close_quietly, the one sanctioned quiet exit, and
      # never bare: on HTTP/2, closing a body before it was read to the end resets the stream, and
      # async-http 0.105.0 writes the RST_STREAM frame BEFORE transitioning the stream's state, so
      # a peer's END_STREAM landing during that write closes the stream twice and releases the
      # pooled connection twice -- `RuntimeError: Trying to reuse unacquired resource` out of
      # `Input#close`, measured through a response obtained in a child task and closed unread by
      # its parent, five of five. The connection is retired rather than reused, the client stays
      # sound, and the raise is a library artefact a caller can do nothing with, so it is reported
      # as one `http.instrumentation.close` WARNING through the adapter's logger and never reaches
      # Response#close (TRANSPORT-16's idempotent, non-raising close). A private_constant of
      # AsyncHTTP.
      class ResponseBody
        include ::Dexpace::Body
        include ::Dexpace::Closeable

        # The message of the IOError #cancel_read raises into a parked reader: the cause of the
        # CancelledError that reader surfaces.
        INTERRUPTED = "the response body was cancelled under a blocked read"

        attr_reader :media_type, :content_length

        # @param native [Protocol::HTTP::Body::Readable] the native body, owned from here on
        # @param media_type [Dexpace::MediaType, nil]
        # @param content_length [Integer] the native length, or -1 when unknown (BODY-35)
        # @param cancellation [Dexpace::Cancellation] the token the response was obtained under
        # @param logger [Dexpace::Instrumentation::Logger] where a native close failure is reported
        # @param on_release [#call, nil] run once, after the native body is closed, whichever path
        #   closed it -- the exchange's watcher hands its own release over through this
        def initialize(native:, media_type:, content_length:, cancellation:,
                       logger: ::Dexpace::Instrumentation::Logger::NULL, on_release: nil)
          @native = native
          @media_type = media_type
          @content_length = content_length
          @cancellation = cancellation
          @logger = logger
          @on_release = on_release
          @source = nil
          @reader = nil
          @reader_scheduler = nil
          initialize_closeable(owned: true)
          initialize_single_use
        end

        # One native `#read` per yield, retagged BINARY, closed through the latch on natural
        # exhaustion so a later explicit `#close` is a no-op. Check-after-resume: a token cancelled
        # while a read was blocked is honoured before the chunk it returned is yielded. A read
        # after `#close` raises rather than re-opening anything.
        #
        # @yield [String] each chunk
        # @return [nil]
        def each
          return to_enum(:each) unless block_given?

          loop do
            chunk = pull
            break if chunk.nil?

            yield chunk.b
          end
          close
          nil
        end

        # HTTP-36's single write, over `#each`; single-use, as every response body is (BODY-6).
        #
        # @param sink [#write]
        # @return [Integer] the byte count written
        def write_to(sink)
          claim_single_use!
          written = 0
          each do |chunk|
            sink.write(chunk)
            written += chunk.bytesize
          end
          written
        end

        # The exchange watcher's entry for a cancellation that lands after delivery (TRANSPORT-7's
        # body path), run on the reactor's thread. A consumer parked inside the native read is
        # WOKEN, never closed under: the watcher raises an IOError into the reader's fiber through
        # the scheduler -- a scheduler checkpoint, the fiber provably suspended inside #pull's own
        # read, which is the mechanism Async::Task#cancel and #with_timeout use -- and the reader's
        # own #pull closes this body on its own fiber once the native wait has unwound; with no
        # reader parked the body is closed here. Closing the connection under a parked reader
        # wakes it only by accident of the selector: io_uring's poll sees the close, but epoll
        # silently drops a closed descriptor from its interest set, so on the EPoll selector
        # (io-event's choice wherever liburing is absent -- every hosted CI runner) the reader
        # stayed parked until something else fired, and on Ruby 4.0 IO#close's own interrupt of
        # the parked fiber is deferred through Fiber::Scheduler#fiber_interrupt and lands in the
        # caller's fiber at whatever suspension point it reaches next. A reader on another thread
        # or another reactor is not this scheduler's to interrupt, and gets the close.
        #
        # @return [nil]
        def cancel_read
          reader = @reader
          scheduler = ::Fiber.scheduler
          if reader&.alive? && !scheduler.nil? && scheduler.equal?(@reader_scheduler)
            scheduler.raise(reader, ::IOError, INTERRUPTED)
          else
            ::Dexpace.close_quietly(self, logger: @logger)
          end
          nil
        rescue ::FiberError
          # The reader was resumed between the check and the raise; there is nothing parked to
          # wake, and the close is what a read after this one meets.
          ::Dexpace.close_quietly(self, logger: @logger)
          nil
        end

        # The same handle every call (BODY-14), built with `.over`, never `.wrapping`, so no byte
        # is read ahead of demand and no one-byte-per-read defect is inherited (3a's residue).
        #
        # @return [Dexpace::IO::BufferedSource]
        def source
          @source ||= ::Dexpace::IO::BufferedSource.over(self)
        end

        private

        def pull
          raise ::Dexpace::ClosedError, "the response body is closed" if closed?

          chunk = parked { @native.read }
          if @cancellation.cancelled?
            close
            raise ::Dexpace::CancelledError, @cancellation.reason
          end
          chunk
        rescue ::Dexpace::Error
          raise
        rescue ::StandardError => error
          ::Dexpace.close_quietly(self, logger: @logger)
          raise Errors.classify_read(error, cancellation: @cancellation)
        end

        # Records the fiber blocked in the native read, and the scheduler it is blocked under, for
        # #cancel_read; cleared on every exit, so a recorded reader is always one inside the read.
        def parked
          @reader_scheduler = ::Fiber.scheduler
          @reader = ::Fiber.current
          yield
        ensure
          @reader = nil
          @reader_scheduler = nil
        end

        # BODY-15: releases the native body -- which returns its connection to the pool, or resets
        # the stream when the body was not read to the end -- idempotent through Closeable's latch,
        # quietly (see the class comment), and then the exchange's own release hook.
        def release
          ::Dexpace.close_quietly(@native, logger: @logger)
        ensure
          @on_release&.call
        end
      end

      private_constant :ResponseBody
    end
  end
end
