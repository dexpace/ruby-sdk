# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../closeable"
require_relative "../registry"
require_relative "../error/invalid_argument_error"
require_relative "../http/response"
require_relative "../instrumentation/logger"
require_relative "../sse"
require_relative "reader"
require_relative "stream_state_error"
require_relative "typed_stream"

module Dexpace
  module SSE
    # The streaming facade, §13.5: one Reader over a byte source, and exactly ONE closeable
    # resource this stream releases exactly once across every termination path (SSE-23) -- clean
    # end (SSE-24), explicit #close (SSE-28), block-form exit and partial consume (SSE-25),
    # mid-stream failure (SSE-29) and a typed DONE (SSE-34). The latch, its idempotence and its
    # ownership flag are phase 2's Dexpace::Closeable, included and never rebuilt.
    #
    # A stream reads from one thing and owns (or borrows) one thing, and they are two parameters:
    # `source` is what the Reader pulls bytes from and `resource` is the single closeable the
    # facade releases, defaulting to the source itself so the common case reads as one argument
    # (P7-25). The three factories are named against a trap: Dexpace::IO::BufferedSource.over
    # means BORROWING and .wrapping means OWNING, so none of them is called `.over` --
    # `Stream.owning` owns, `Stream.borrowing` borrows, and `Stream.open(response)` is SSE-32's
    # convenience, reading the response body's source and owning the RESPONSE.
    #
    # Two consumption shapes, both single-pass and both taking the same one view (SSE-26, SSE-40):
    # `#each { |event| }` and `#events -> Enumerator`. The resource lives on this object and never
    # inside the enumerator's block or an owning #each -- an Enumerator abandoned mid-#next never
    # runs its ensure, and neither does a `def each` reached through to_enum (design §7.1) -- so
    # external iteration gets its release from the clean end or from #close, which the block form
    # calls in its own scope on every exit. No `block_given?` guard is written anywhere: it is
    # true inside #each reached through to_enum and #next, so it would forbid nothing.
    #
    # SSE-30's asymmetry is two call sites into ONE close-once helper, never two closes: the
    # automatic terminal paths go through Dexpace.close_quietly(self, logger:), whose swallowed
    # release failure is reported out of band as an `http.instrumentation.close` WARNING through
    # `logger:` (nothing under the default Logger::NULL); an explicit #close and a block-form
    # break go through Closeable#close, whose release failure propagates once. Both flip the same
    # latch, so SSE-28's "even after an automatic release" holds by construction. SSE-31's
    # cross-thread #close is the latch's mutex, held across the flip only; the drive routine reads
    # closed? before every pull, so a close between pulls ends the iteration cleanly (SSE-27) and
    # a close during a blocked read tears the resource down under the reader, which surfaces as
    # the source's own I/O error. The stream imposes no timeout of its own (IO-40).
    class Stream
      include Dexpace::Closeable

      private_class_method :new

      # SSE-32: a stream over an HTTP response, reading `response.body.source` and OWNING the
      # response, so closing the stream closes the response (HTTP-43 forwards to the body).
      #
      # @param response [Dexpace::Response] a response whose body is present
      # @param max_line_bytes [Integer] SSE-19's line cap for this stream's reader
      # @param max_event_bytes [Integer] SSE-19's event cap for this stream's reader
      # @param logger [Instrumentation::Logger] where a swallowed release failure is reported
      # @return [Stream] owning the response
      # @raise [Dexpace::InvalidArgumentError] for anything but a Response, or one with no body
      def self.open(response, max_line_bytes: MAX_LINE_BYTES, max_event_bytes: MAX_EVENT_BYTES,
                    logger: Instrumentation::Logger::NULL)
        unless response.is_a?(Response)
          raise InvalidArgumentError, "open takes a Dexpace::Response, got #{response.class}"
        end

        body = response.body
        raise InvalidArgumentError, "the response has no body to stream (SSE-32)" if body.nil?

        new(source: body.source, resource: response, owned: true, max_line_bytes: max_line_bytes,
            max_event_bytes: max_event_bytes, logger: logger,)
      end

      # A stream that OWNS `resource` -- the source itself unless another closeable is named --
      # and releases it exactly once.
      #
      # @param source [Dexpace::SSE::_ByteSource] what the reader pulls bytes from
      # @param resource [#close] the one closeable this stream releases; the source by default
      # @param max_line_bytes [Integer] SSE-19's line cap
      # @param max_event_bytes [Integer] SSE-19's event cap
      # @param logger [Instrumentation::Logger] where a swallowed release failure is reported
      # @return [Stream]
      # @raise [Dexpace::InvalidArgumentError] for a source missing #getbyte, #peek or #skip, a
      #   resource with no #close, a cap that is not a positive Integer or a logger that is not one
      def self.owning(source, resource: source, max_line_bytes: MAX_LINE_BYTES,
                      max_event_bytes: MAX_EVENT_BYTES, logger: Instrumentation::Logger::NULL)
        new(source: source, resource: resource, owned: true, max_line_bytes: max_line_bytes,
            max_event_bytes: max_event_bytes, logger: logger,)
      end

      # A stream that BORROWS `resource`: #close flips the latch and releases nothing, because the
      # caller owns its lifecycle (SEAM-14, XCUT-22).
      #
      # @param source [Dexpace::SSE::_ByteSource] what the reader pulls bytes from
      # @param resource [Object] the caller's object, never closed here; the source by default
      # @param max_line_bytes [Integer] SSE-19's line cap
      # @param max_event_bytes [Integer] SSE-19's event cap
      # @param logger [Instrumentation::Logger] kept for the typed layer's DONE path
      # @return [Stream]
      # @raise [Dexpace::InvalidArgumentError] as for .owning, a resource with no #close excepted
      def self.borrowing(source, resource: source, max_line_bytes: MAX_LINE_BYTES,
                         max_event_bytes: MAX_EVENT_BYTES, logger: Instrumentation::Logger::NULL)
        new(source: source, resource: resource, owned: false, max_line_bytes: max_line_bytes,
            max_event_bytes: max_event_bytes, logger: logger,)
      end

      def initialize(source:, resource:, owned:, max_line_bytes:, max_event_bytes:, logger:)
        @reader = Reader.new(source, max_line_bytes: max_line_bytes,
                                     max_event_bytes: max_event_bytes,)
        if owned && !resource.respond_to?(:close)
          raise InvalidArgumentError,
                "an owned resource must respond to #close (SSE-23), got #{resource.class}"
        end
        unless logger.is_a?(Instrumentation::Logger)
          raise InvalidArgumentError,
                "logger: takes an Instrumentation::Logger, got #{logger.class}"
        end

        @resource = resource
        @logger = logger
        @viewed = false
        initialize_closeable(owned: owned)
      end

      # The block form: every event to the block, in the stream's own scope, and the resource
      # released on every exit -- the clean end quietly, a break or a raise through #close.
      #
      # @yieldparam event [Event]
      # @return [nil]
      # @raise [Dexpace::SSE::StreamStateError] when the view was already taken or the stream is
      #   closed (SSE-26, SSE-27)
      def each(&)
        take_view!
        drive(&)
        nil
      end

      # The external form: a lazy single-pass Enumerator over the same one view (SSE-40), reusing
      # this stream's one reader so the BOM flag persists. An abandoned enumerator releases
      # nothing; #close is the documented remedy (SSE-25).
      #
      # @return [Enumerator<Event>]
      # @raise [Dexpace::SSE::StreamStateError] as for #each
      def events
        take_view!
        to_enum(:drive)
      end

      # The typed adapter over this stream (§13.6): a TypedStream whose mapper is called with
      # `(event_name, joined_data)` per pulled event and answers a decoded value, SKIP or DONE
      # (SSE-33, SSE-34). The mapper is the callable or the block; the typed view shares this
      # stream's one view and its one resource.
      #
      # @param mapper [#call, nil] `(String?, String) -> Object`; the block when omitted
      # @return [TypedStream]
      # @raise [Dexpace::InvalidArgumentError] without a mapper callable with two positionals
      def typed(mapper = nil, &block)
        callable = mapper.nil? ? block : mapper
        unless Registry.callable?(callable, arity: 2)
          raise InvalidArgumentError,
                "typed takes a mapper callable with (event_name, data), as an argument or a block"
        end

        TypedStream.send(:new, stream: self, mapper: callable, logger: @logger)
      end

      private

      # SSE-26 and SSE-27: the one view, refused after close and refused twice. The flag is an
      # unsynchronised boolean and detects a SEQUENTIAL second call (P4-33's precedent): a
      # stream is driven from one thread at a time (SSE-18), and only #close crosses threads.
      def take_view!
        if closed?
          raise StreamStateError, "this stream is closed; no iterator can be requested (SSE-27)"
        end
        if @viewed
          raise StreamStateError,
                "this stream is single-pass and its one view was already taken (SSE-26)"
        end

        @viewed = true
        nil
      end

      # The drive routine both shapes share, and the whole lifecycle: pull until the end, and
      # release on every exit. It holds no resource -- the resource is the stream's -- so being
      # abandoned as an Enumerator's body leaks nothing #close would not still release.
      #
      # A raise -- the reader's, the source's, or the caller's own block's -- releases BEFORE it
      # propagates, with a release failure attached to it as suppressed through
      # Dexpace.attach_suppressed (SSE-29). That helper silently no-ops on a FROZEN primary
      # (P4-13), so the attachment is made for every error the SDK or a caller normally raises and
      # silently not for a frozen one; there is no second mechanism to reach for. The ensure's
      # #close is a block-form break's loud release; on every other path the latch has already
      # flipped and it returns nil.
      def drive
        while (event = advance)
          yield event
        end
        nil
      rescue ::Exception => error # rubocop:disable Lint/RescueException -- release, then re-raise unchanged
        Dexpace.close_quietly(self, onto: error)
        raise
      ensure
        close
      end

      # One pull. SSE-27 first: an in-flight iterator observes the closed state before it could
      # read from the torn-down resource. The clean end releases quietly (SSE-24, SSE-30).
      def advance
        return nil if closed?

        event = @reader.next_event
        return event unless event.nil?

        finish
        nil
      end

      # The automatic release, SSE-30's swallowing half: the one quiet-close route, reporting a
      # release failure out of band through the logger and swallowing it, so delivered events are
      # never discarded by a close that failed after them. The typed layer's DONE path is the same
      # call on the same logger, from TypedStream.
      def finish
        Dexpace.close_quietly(self, logger: @logger)
      end

      # Closeable's hook: release the one resource. Only reached when owned.
      def release
        @resource.close
        nil
      end
    end
  end
end
