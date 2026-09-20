# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module NetHTTP
      # R1 (P8-1): a per-response producer Thread over a Thread::SizedQueue(1), not a Fiber --
      # Fiber#resume from a second thread raises FiberError, which would break
      # Transport.async_over's composition and confine TRANSPORT-29's "returned response graph"
      # to one thread. The producer runs the whole Net::HTTP exchange; the consumer pops the head
      # on the caller's thread and then chunks through a #readpartial-shaped reader that
      # BufferedSource.wrapping owns and closes, so `Response#close` cascades down to `#close`
      # here. One thread per in-flight response, alive until the body is drained or the response
      # is closed; a response nobody closes and nobody drains strands one thread and one
      # connection, which is the documented consequence of breaking SEAM-11's "the caller owns
      # reading and closing it". A private_constant of NetHTTP.
      class ResponsePump # rubocop:disable Metrics/ClassLength -- one mechanism with two halves, the producer's and the consumer's, which share the queue, the latch and the token and split by nothing but which thread runs them
        include ::Dexpace::Closeable

        # @param http [Net::HTTP] the client to exchange through
        # @param native [Net::HTTPGenericRequest] the mapped request
        # @param deadline [Deadline, nil] this call's budget, refreshed into read_timeout after
        #   every chunk (R3); nil on the borrowing construction, whose client is never touched
        # @param cancellation [Dexpace::Cancellation] the token this call was given, asked FIRST
        #   by every failure classification (TRANSPORT-3)
        # @param owns_connection [Boolean] false on the borrowing construction (P8-15), where the
        #   client is neither started nor finished here: Net::HTTP#request opens and closes its
        #   own session on an unstarted client and reuses an already-started one
        # @param permit [Thread::SizedQueue, nil] the one-permit queue a borrowed call took,
        #   returned when the PRODUCER is done with the client -- the exchange, not the #call, is
        #   what must not overlap
        def initialize(http:, native:, deadline:, cancellation:, owns_connection: true, permit: nil)
          @http = http
          @native = native
          @deadline = deadline
          @cancellation = cancellation
          @owns_connection = owns_connection
          @permit = permit
          @queue = ::Thread::SizedQueue.new(1)
          @proceed = ::Thread::Queue.new
          @residue = (+"").b
          initialize_closeable(owned: true)
          @thread = nil
          @subscription = nil
          start_producer(cancellation)
        end

        # Blocks on the first pop and returns the native head -- or, with a block, yields it and
        # returns what the block returns. The producer does not touch the body until the head has
        # been adapted: R4 deletes an unparseable Content-Length from the native head so that
        # read_body never parses it, and that deletion must land BEFORE read_body starts, on the
        # thread that adapts. The block is that window; the producer is resumed when it ends,
        # whatever it did. A failure before the head is re-raised on THIS thread with the carried
        # error as its cause, spelled explicitly: the pump is CARRYING a failure from another
        # thread, not rescuing one of its own, so `$!` here may be an unrelated exception in
        # flight on the caller's own stack.
        #
        # @yieldparam head [Net::HTTPResponse] the head, before any body byte is read
        # @return [Net::HTTPResponse, Object] the head, or the block's value
        # @raise [Dexpace::TransportError, Dexpace::CancelledError] the classified failure
        def head_or_raise
          kind, payload = @queue.pop
          case kind
          when :head
            begin
              block_given? ? yield(payload) : payload
            ensure
              resume_producer
            end
          when :error then carry(payload, phase: :connect)
          else
            # The queue closed with no head and no error: the pump was closed under the
            # producer, by a cancel or by the caller. The token decides which.
            ended = ::Dexpace::TransportError.new("the exchange ended before a response",
                                                  phase: :connect,)
            raise Failures.wrap(ended, phase: :connect, cancellation: @cancellation)
          end
        end

        # The #readpartial-shaped reader BufferedSource.wrapping owns. Pops when the residue is
        # empty; raises Dexpace::EndOfStreamError -- an ::EOFError subclass, load-bearing:
        # IO.copy_stream and BufferedSource both terminate cleanly on it -- at end of stream;
        # re-raises a carried producer failure the way #head_or_raise does; and writes into
        # `outbuf` with #replace, so the destination carries BINARY whatever the caller's buffer
        # had before.
        #
        # @param maxlen [Integer]
        # @param outbuf [String, nil]
        # @return [String] BINARY bytes, at most maxlen of them
        def readpartial(maxlen, outbuf = nil)
          raise closed_failure if closed?

          fill if @residue.empty?
          chunk = @residue.byteslice(0, maxlen).to_s
          @residue = (@residue.byteslice(maxlen..) || "").b # a fresh, unfrozen, BINARY tail
          return chunk if outbuf.nil?

          outbuf.replace(chunk)
        end

        private

        # A token already cancelled when the pump is built gets a closed pump and no exchange:
        # #close with no producer to join and no subscription to detach, and the permit -- the
        # producer's to return once it exists -- returned here instead, exactly once (P8-64).
        # Otherwise the caller's cancellation closes this pump for the whole life of the
        # response, not only for the head: a cancel under a blocked body read is what finishes
        # the owned connection and wakes the producer (TRANSPORT-3). Registered AFTER the thread
        # exists, because Cancellation::Source runs an already-cancelled hook inline -- a cancel
        # landing between the check and the registration closes the pump from inside this frame,
        # and that #release joins the thread and finds the still-nil subscription slot. Detached
        # in #release, so a client-lifetime token retains this closure only until the response
        # is closed.
        def start_producer(cancellation)
          if cancellation.cancelled?
            close
            @permit&.push(:permit)
          else
            @thread = ::Thread.new { produce }
            @subscription = cancellation.on_cancel { close }
          end
          nil
        end

        def resume_producer
          @proceed.push(true)
          nil
        rescue ::ClosedQueueError
          nil
        end

        def fill
          kind, payload = @queue.pop
          case kind
          when :chunk then @residue << payload.b
          when :error then carry(payload, phase: :read)
          else
            # A closed queue is the end of the body only when the PRODUCER closed it; closed
            # under a read by #release it is a truncation, never a clean end of stream.
            raise closed_failure if closed?

            raise ::Dexpace::EndOfStreamError, "the response body is exhausted"
          end
        end

        # Use after close (3a's rule), classified through the token first so a response closed
        # by a cancel reads as the cancellation it was (TRANSPORT-3).
        def closed_failure
          closed = ::Dexpace::ClosedError.new("the response was already closed")
          Failures.wrap(closed, phase: :read, cancellation: @cancellation)
        end

        # `cause:` is spelled at every carried raise: the original when the error was wrapped,
        # and `nil` when Failures.wrap handed the payload back unchanged -- raising an error with
        # itself as its cause is refused by Ruby, and `cause: nil` never clears a cause the
        # producer's own raise already made.
        def carry(payload, phase:)
          error = Failures.wrap(payload, phase: phase, cancellation: @cancellation)
          raise error, cause: nil if error.equal?(payload)

          raise error, cause: payload
        end

        # Runs on the PRODUCER's thread. A failure is pushed rather than raised, the queue is
        # closed in the ensure (never in a rescue) so a consumer blocked on pop ends rather than
        # hangs, and the permit goes back only here, once the client is free. The latch is read
        # first: a pump closed before its producer was scheduled -- a cancel racing the
        # construction -- exchanges nothing, so the socket is never opened for a response nobody
        # can receive and the join in #release is not spent waiting out a server that holds
        # (P8-64).
        def produce
          return if closed?

          if @owns_connection
            @http.start { |connected| exchange(connected) }
          else
            exchange(@http)
          end
        rescue ::StandardError => error
          begin
            @queue.push([:error, error])
          rescue ::ClosedQueueError
            nil
          end
        ensure
          @queue.close
          @permit&.push(:permit)
        end

        # A push onto a closed queue raises ClosedQueueError, and that raise is the check-after-
        # resume this producer relies on: it is DELIBERATELY not a `break`. Raising out of the
        # read_body block makes Net::HTTP close its own socket on the way out, where a break
        # would leave a half-read connection open and, on a borrowed client, keep it alive for
        # the caller's next request to read the remainder as a corrupt status line.
        def exchange(connected)
          refresh_read_timeout
          connected.request(@native) do |res|
            @queue.push([:head, res])
            @proceed.pop # until the head is adapted, or the pump is closed (nil either way)
            refresh_read_timeout
            res.read_body do |chunk|
              @queue.push([:chunk, chunk])
              refresh_read_timeout
            end
          end
        end

        # R3: the remaining budget into read_timeout after every chunk this pump receives, when
        # a deadline was supplied at all. An expired budget raises here rather than being handed
        # over as zero, which Net::HTTP reads as "poll once".
        def refresh_read_timeout
          deadline = @deadline
          return if deadline.nil?

          if deadline.expired?
            raise ::Dexpace::TransportError.new("the per-call budget expired mid-exchange",
                                                phase: :read,)
          end
          @http.read_timeout = deadline.clamped
        end

        # R1's release, in order: the latch is already flipped by Closeable#close; close the
        # queue, waking a producer blocked on push; finish the connection this pump opened,
        # waking one blocked in a socket read with IOError -- which works only because
        # `max_retries = 0` keeps Net::HTTP from retrying through it; join with a BOUNDED
        # deadline (XCUT-13). On the borrowing construction the socket is the caller's and is
        # not finished: the producer is left to the caller's own read_timeout, the stated
        # narrowing of TRANSPORT-19's prompt unblock there. Both wakeups are wrapped so a close
        # cannot raise over a primary failure.
        def release
          begin
            @queue.close
            @proceed.close
            @http.finish if @owns_connection && @http.started?
          rescue ::StandardError
            nil
          end
          @thread&.join(JOIN_DEADLINE_SECONDS) # nil when the token was cancelled at construction
          @subscription&.detach # nil there too, and under a cancel racing the registration
          nil
        end
      end

      private_constant :ResponsePump
    end
  end
end
