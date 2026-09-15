# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../async/completer"
require_relative "../async/future"
require_relative "../closeable"
require_relative "../error/seam_error"

module Dexpace
  # The two sync<->async bridges SEAM-18 requires, each in its own file.
  #
  # Not under Dexpace::Transport: deviation P2-1 argues that a seam constant must not sit beside
  # the adapter namespaces Dexpace::Transport::NetHTTP and ::AsyncHTTP, and a bridge is no more
  # entitled to that seat than a seam is (deviation P2-13).
  module Bridge
    # A blocking transport presented as an asynchronous one. This is the one place phase 2 itself
    # can produce a response no caller will take delivery of, so it is where SEAM-30 is exercised
    # rather than merely stated.
    #
    # Closeable and **not owning**: it holds a caller-supplied transport and a caller-supplied
    # executor and creates neither, so close latches and releases nothing. That is SEAM-14's
    # ownership clause and XCUT-22's "a caller-supplied client or executor is NEVER closed by the
    # SDK", and it is why close does not cascade to the wrapped transport.
    class AsyncOver
      include Dexpace::Closeable

      def initialize(transport, executor)
        @transport = transport
        @executor = executor
        initialize_closeable(owned: false)
      end

      # The future is returned before anything fallible reaches the caller. A raise from
      # #post itself -- a shut-down pool, a rejected task -- is routed to the failure channel
      # exactly as a raise from the wrapped transport is, because ASYNC-2 and PIPE-30 require one
      # normalisation and a caller of an async seam should never have to rescue around #call.
      def call(request, options, cancellation)
        completer = Dexpace::Async::Completer.new
        begin
          @executor.post { deliver(completer, request, options, cancellation) }
        rescue ::StandardError => error
          completer.fail(error)
        end
        completer.future
      end

      private

      # Check-BEFORE-dispatch, then check-after-resume (design §3.3).
      #
      # The worker's ::Thread::Queue#pop is one of the four suspension points
      # concurrency-and-async/611b9392 enumerates, so this block begins executing immediately after
      # a resume -- the earliest check-after-resume point a queued task has -- and one test at the
      # top turns a wasted round trip into no round trip. Nothing is *broken* without it: ASYNC-3's
      # third clause asks only that a queued task not be interrupted, and SEAM-30/ASYNC-5 close the
      # orphan through Completer#fulfil's losing-race branch either way. What is lost is one
      # connection and, on a non-idempotent method, one server-side side effect a caller believed
      # they had cancelled. It belongs to core rather than to the runtime adapter, because
      # dexpace-async-thread cannot see the token: the pool posts an opaque block by design
      # (concurrency-and-async/08a0e08d), which is also what lets the same object serve
      # Dexpace::Page::_Executor.
      #
      # After the send the state is re-read before acting on the value it produced. If cancelled,
      # the response is closed and the future settles through the failure channel rather than
      # delivering. Completer#fulfil closes the orphan on a lost race too, so SEAM-30 holds even if
      # that branch is missed.
      #
      # The delivered value is type-checked the way Bridge::SyncOver#call checks the future it is
      # handed, and for the mirror-image reason. Both seams' .conforms? is
      # Dexpace::Registry.callable?(object, arity: 3) and #parameters cannot see a return type, so
      # an ASYNC transport handed to Transport.async_over is accepted at construction. Without this
      # branch #deliver hands a Dexpace::Async::Future to Completer#fulfil, whose only validation
      # is "exactly one of response or error": the outer Future#value then returns the INNER
      # future, nothing raises anywhere, and the real response is never closed because nothing on
      # that path knows there is one inside. Phase 4c's Pipeline/AsyncPipeline pair is what makes
      # that cheap to hit, and the finding is 4c's, routed here.
      #
      # The whole body is inside the rescue, deliberately -- the raise above included, so it
      # settles the future instead of escaping the posted block. Written with a method-level `else`
      # the delivery branch sits OUTSIDE the rescue's protection, so anything raised between the
      # send returning and the future settling -- reading #cancelled? off an argument that is not a
      # token is the cheapest example -- escapes the posted block, kills the worker under a real
      # threaded executor, and leaves the future permanently unsettled with every #value blocked
      # on it. Reproduced on 3.2.11, 3.4.10 and 4.0.6.
      def deliver(completer, request, options, cancellation)
        return completer.request_cancel(cancellation.reason) if cancellation&.cancelled?

        response = @transport.call(request, options, cancellation)
        if response.is_a?(Dexpace::Async::Future)
          raise Dexpace::SeamError,
                "Transport.async_over wraps a SYNCHRONOUS transport; the one it was given " \
                "delivered a #{response.class}. Call that transport directly, or present it " \
                "through Dexpace::AsyncTransport.sync_over first."
        end

        if cancellation&.cancelled?
          Dexpace.close_quietly(response)
          completer.request_cancel(cancellation.reason)
        else
          completer.fulfil(response)
        end
      rescue ::StandardError => error
        completer.fail(error)
      end
    end
  end
end
