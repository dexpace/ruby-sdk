# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"
require_relative "../../closeable"
require_relative "../../io/buffer"
require_relative "../../io/buffered_source"

module Dexpace
  # BODY-22..BODY-29: the drain-once response capture wrapper, in two regimes behind one close-once
  # guard.
  #
  # IO-42 governs SURFACES, not objects, and this holds three of them with three different answers
  # (R10). The captured Dexpace::IO::Buffer is EXEMPT and keeps answering after any close, because
  # it wraps no external stream (BODY-28, and 3a expresses it as Buffer#reads_survive_close?). The
  # over-cap composite is NOT exempt: it holds the live delegate, so a read after close raises
  # Dexpace::ClosedError (BODY-24). And views derived from the buffer are invalidated by the
  # BUFFER's close, never by the wrapper's -- which is why #release closes the DELEGATE and
  # deliberately does not close the buffer.
  #
  # Nothing in core constructs one of these: BODY-34's enablement clause is satisfied structurally,
  # and phase 5b's instrumentation layer is the thing that will build one (its Tasks 14-15).
  #
  # The include order is Dexpace::Body THEN Dexpace::Closeable, so Closeable#close wins (P3-23).
  class ResponseLoggingBody # rubocop:disable Metrics/ClassLength -- two regimes, one close-once guard and the private Tail, one class by design; see above
    include Dexpace::Body
    include Dexpace::Closeable

    # BODY-22 says "buffering up to a configurable byte cap" and names NO default, and an unbounded
    # default would mean BODY-24's over-cap regime never fires and a multi-gigabyte response is
    # fully buffered by the wrapper whose whole purpose is to bound it. Required, therefore --
    # deliberately asymmetric with RequestLoggingBody (P3-18). Adding a default in phase 5 widens
    # the signature and cannot break NFR-4 (phase 2's deadline: precedent, P2-5; the source is
    # phase 5b's, Tasks 14-15).
    def initialize(delegate, preview_bytes:)
      unless delegate.respond_to?(:source)
        raise Dexpace::InvalidArgumentError,
              "a response-logging wrapper takes a body responding to #source, " \
              "got #{delegate.class}"
      end
      unless preview_bytes.is_a?(::Integer) && !preview_bytes.negative?
        raise Dexpace::InvalidArgumentError,
              "preview_bytes must be a non-negative Integer, got #{preview_bytes.inspect}"
      end

      @delegate = delegate
      @preview_bytes = preview_bytes
      @buffer = Dexpace::IO::Buffer.new
      @upstream = nil
      @pending = nil
      @state = :unstarted
      @error = nil
      @complete = false
      @tail_taken = false
      @mutex = ::Thread::Mutex.new
      @condition = ::Thread::ConditionVariable.new
      initialize_closeable(owned: true)
    end

    # The wrapped body, and the cap it was built with.
    attr_reader :delegate, :preview_bytes

    # BODY-23/BODY-24's read surface, under Dexpace::Body's contract name (P3-23): it triggers the
    # drain on first access and then serves the regime the drain landed in, and it is what
    # Response#body_string and #body_bytes read through when a wrapper occupies Response#body.
    # Fits-cap: a fresh non-consuming view of the capture, fully repeatable. Over-cap: R10's
    # composite, once, continuing from the ONE handle the drain took (see #drain).
    def source
      ensure_drained
      error = @error
      raise error unless error.nil?
      return @buffer.peek if @complete

      claim_tail!
      Dexpace::IO::BufferedSource.wrapping(Tail.new(self, @buffer, @pending, @upstream))
    end

    # BODY-26: the partial bytes, without raising, whatever happened during the drain. BINARY --
    # Response#body_string is the SDK's only decode boundary and this is not it.
    def snapshot
      ensure_drained
      @buffer.snapshot
    end

    # BODY-26's exception-query accessor: the cached error, or nil. It triggers the FIRST drain
    # (BODY-22 lists the exception query among the first-access triggers) and never a second one.
    # Spelled without a "?" on purpose: it returns the error or nil, not a boolean.
    def error
      ensure_drained
      @error
    end

    # BODY-29: the captured size ONLY when the capture was complete, otherwise the delegate's
    # declared length -- the true length, since the capture is a bounded prefix. It never triggers a
    # drain, which is also what makes the interleaved-fibers proof terminate.
    def content_length
      captured = @mutex.synchronize { @complete ? @buffer.bytesize : nil }
      captured.nil? ? @delegate.content_length : captured
    end

    # The delegate's: capturing changes no header-visible fact about the body.
    def media_type
      @delegate.media_type
    end

    # A response-logging wrapper is a reader, not a request body. Offering it as one would have to
    # choose between truncating at the cap and re-consuming the tail, and both are wrong.
    def write_to(_sink)
      raise Dexpace::StreamError,
            "#{self.class} is a response capture wrapper and produces no request body; use " \
            "#source"
    end

    # HTTP-46 is Dexpace::Body's identity default: a wrapper holds a live delegate and a drain
    # state.

    private

    # BODY-24's composite: the captured prefix from a FRESH non-consuming #peek view, then the
    # regime probe's byte, then the still-live tail, so the consumer receives the complete body.
    #
    # It is #read(count)-shaped and handed to BufferedSource.WRAPPING, not .over, and that is
    # BODY-27's second close path made real. BODY-27 names two paths -- "the wrapper's own close
    # AND the one-shot tail stream's close MUST route through a single shared close-once guard" --
    # and .over owns nothing, so the tail's #close would be a public, callable method that
    # released no transport resource. BODY-24 hands this stream to a consumer AS THE REST OF THE
    # BODY; closing what you were handed is the idiomatic release, and under .over that close
    # would lose BODY-15's guarantee one layer up. .wrapping owns this object (IO-6), so
    # source.close -> Tail#close -> the wrapper's own Closeable latch: one guard, both paths,
    # either order, and a delegate whose close raises is still marked closed.
    #
    # The wrapper's #release closes the DELEGATE and not this object, so there is no cycle.
    class Tail
      def initialize(wrapper, buffer, pending, source)
        @wrapper = wrapper
        @view = buffer.peek
        @pending = pending
        @source = source
      end

      # BufferedSource.wrapping drives #read(count) and reads nil as end of stream; it never
      # receives "" from here, because "" latches exhaustion on that path (3a's
      # fill_from_upstream) and an empty prefix must not end the composite before the tail has
      # been read.
      #
      # The live tail is forwarded through #read_into, IO-1's primitive, and NOT through the
      # delegate source's #read(count): #read is IO-16's host-native bulk read and "keeps filling
      # until it has `length` bytes or the stream ends", so on a still-open connection the
      # composite would deliver the rest of the body in .wrapping's 64 KiB segments or at EOF,
      # where the delegate on its own returns what has arrived (review round 0, R0-3). #read_into
      # fills ONCE and returns what is there, which is what a partial read is, and it is also the
      # only member the regime probe asks of the delegate's source (plan decision 9), so the
      # delegate's source contract stays Dexpace::IO::_Source's single method. A zero return for
      # the positive count .wrapping always asks with is BODY-25's contract violation, and 3a's
      # helper keeps the message form in one place.
      def read(count)
        if @wrapper.closed?
          raise Dexpace::ClosedError,
                "the over-cap tail of a #{@wrapper.class} cannot be read after the wrapper is " \
                "closed: it replays a captured prefix and then continues from the delegate, and " \
                "the delegate is gone (BODY-24, IO-42)"
        end

        prefix = @view.read(count)
        return prefix unless prefix.nil? || prefix.empty?

        pending = @pending
        return take_pending unless pending.nil? || pending.empty?

        read_tail(count)
      end

      # BODY-27's second path, and the reason this is .wrapping's upstream rather than .over's
      # body: it routes to the wrapper's own close-once guard, so a consumer that closes the
      # stream it was handed releases the connection exactly as one that closes the wrapper does,
      # and the two together are still one close.
      def close
        @view.close
        @wrapper.close
      end

      private

      def take_pending
        taken = @pending
        @pending = nil
        taken
      end

      # One fill of the live delegate: what is there, nil at its end, and BODY-25's violation
      # for a zero return on a positive count (see #read).
      def read_tail(count)
        chunk = (+"").b
        got = @source.read_into(chunk, count: count)
        return nil if got.negative?
        raise Dexpace::StreamError.zero_read(requested: count) if got.zero?

        chunk
      end
    end

    private_constant :Tail

    # BODY-24: "A second read in this regime MUST fail (the tail is single-consumer)."
    def claim_tail!
      taken = @mutex.synchronize do
        if @tail_taken
          true
        else
          @tail_taken = true
          false
        end
      end
      return nil unless taken

      raise Dexpace::StreamError,
            "the over-cap tail of a #{self.class} is single-consumer and has already been taken " \
            "(BODY-24)"
    end

    # BODY-22: at most once, lazily, with concurrent first accesses serialized so the upstream is
    # read exactly once. The Thread::Mutex is held across the STATE FLIP and across nothing else --
    # never across the drain. Ruby's Mutex is per-fiber-owned and non-reentrant, so a mutex held
    # across the drain raises ThreadError for a second fiber of the same thread; that is what makes
    # the interleaved-fibers test a proof rather than a restatement. The same P3-27 residue as
    # TypedResponse: with no Fiber scheduler installed, a second fiber of the same thread arriving
    # mid-drain parks the carrier thread in #wait.
    def ensure_drained
      mine = @mutex.synchronize do
        @condition.wait(@mutex) while @state == :running
        if @state == :unstarted
          @state = :running
          true
        else
          false
        end
      end
      return nil unless mine

      begin
        drain
      ensure
        @mutex.synchronize do
          @state = :done
          @condition.broadcast
        end
      end
      nil
    end

    # The delegate's #source is asked ONCE per wrapper, here, and the handle it answers with is
    # what the prefix fill, the regime probe and the over-cap tail all read from, in that order,
    # and what #release closes ahead of the delegate. The wrapper's delegate contract is #source,
    # #content_length, #media_type and #close, and the three bodies that can occupy Response#body
    # answer #source differently on purpose (P3-23): ResponseBody hands out BODY-14's same handle
    # every call, but BufferBody hands out a FRESH non-consuming #peek view per call. Asking three
    # times is correct over the first and wrong over the second -- each view starts at byte zero,
    # so the over-cap composite would replay the prefix twice and then the whole body, and the
    # fill view would never be closed (review round 1, R1-1). One handle, read to wherever the
    # drain left it, is the shape BODY-24's "the still-live tail" describes for both.
    def drain
      upstream = @delegate.source
      @upstream = upstream
      taken = fill_prefix(upstream)
      @complete = capture_complete?(upstream, taken)
      # BODY-28: on the fits-cap path the delegate close is BEST EFFORT. Dexpace.close_quietly's
      # first call site in this SDK (neither of phase 2's two disposal routes exists yet -- phase
      # 4b, Task 2 and phase 5b, Task 14 -- so the rescued error is still dropped). It routes
      # through this wrapper's own #close, so BODY-27's close-once guard still owns the only close
      # path, and a delegate whose close raises is still marked closed.
      Dexpace.close_quietly(self) if @complete
      nil
    rescue ::StandardError => error
      # BODY-26: retain the bytes read before the failure and cache the error.
      @error = error
      nil
    end

    def fill_prefix(upstream)
      taken = 0
      while taken < @preview_bytes
        wanted = @preview_bytes - taken
        chunk = (+"").b
        got = upstream.read_into(chunk, count: wanted)
        break if got.negative?
        # BODY-25: zero bytes for a POSITIVE requested count is a stream-contract violation, never
        # end of stream. 3a's helper, so the message form cannot diverge from BODY-10's.
        raise Dexpace::StreamError.zero_read(requested: wanted) if got.zero?

        @buffer.write(chunk)
        taken += got
      end
      taken
    end

    # BODY-23 is "end-of-stream reached before the cap" and BODY-24 is "cap hit with bytes still
    # pending", so the two are told apart by ONE more byte (plan decision 9). Reading it rather
    # than peeking keeps the delegate's source contract to #read_into alone.
    def capture_complete?(upstream, taken)
      return true if taken < @preview_bytes

      probe = (+"").b
      got = upstream.read_into(probe, count: 1)
      return true if got.negative?

      # The byte is KEPT but it is NOT part of the capture. BODY-22 caps what the wrapper buffers,
      # so writing it into @buffer would make every over-cap snapshot cap+1 bytes long -- and a cap
      # of 0 capture one byte of a payload the caller asked not to capture. It is replayed by the
      # composite between the captured prefix and the still-live tail instead, so the consumer
      # still receives every byte the delegate had.
      @pending = probe
      false
    end

    # BODY-27: ONE close-once guard, Closeable's latch, shared by the wrapper's own close, by the
    # capture path's best-effort close and by the tail's close. It closes the handle the drain
    # took from the delegate and then the DELEGATE, and deliberately NOT the captured buffer: the
    # buffer holds only memory, closing it would invalidate every outstanding BODY-23 view for no
    # gain, and BODY-28 requires it to survive this close.
    #
    # The handle first, because it is derived from the delegate (a BufferBody's is a view its
    # buffer registers, and closing it is what deregisters it -- "every view core takes, core
    # closes"), and over a ResponseBody it IS the delegate's own source, whose second close under
    # the delegate is a no-op through its latch. The delegate's close sits in an ensure so the
    # transport release BODY-15 names is attempted whatever the handle's close did. One
    # respond_to? guard covers both handles that cannot be closed: a Dexpace::IO::_Source declares
    # no #close, and before a drain has asked -- or when it failed before the delegate answered
    # #source -- there is no handle at all, only nil.
    def release
      upstream = @upstream
      begin
        upstream.close if upstream.respond_to?(:close)
      ensure
        @delegate.close if @delegate.respond_to?(:close)
      end
      nil
    end
  end
end
