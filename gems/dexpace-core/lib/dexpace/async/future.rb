# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "completer"
require_relative "../error/seam_error"

module Dexpace
  module Async
    # The read side of the canonical async pivot: a facade over one Completer, which is where every
    # piece of state lives.
    #
    # .new stays public and type-checks its argument rather than being made private. A second
    # facade over the same completer is harmless -- both observe one future -- and the alternative,
    # a private constructor the completer reaches through send, would put a send hole in exactly
    # the read/write boundary this pair exists to draw.
    class Future
      def initialize(completer)
        unless completer.is_a?(Completer)
          raise Dexpace::InvalidArgumentError,
                "a future is built over a Dexpace::Async::Completer, got #{completer.class}"
        end

        @completer = completer
      end

      # Whether an outcome has been published.
      def settled? = @completer.settled?

      # Whether the outcome is a cancellation; false while unsettled.
      def cancelled? = @completer.outcome&.cancelled ? true : false

      # Settles-or-returns; never raises the failure.
      def wait(cancellation: nil)
        @completer.await(cancellation)
        self
      end

      # Blocks, then delivers the response or raises the failure. `deadline:` is deliberately
      # absent: SEAM-18's interruption clause is about cancellation, and deadlines need phase 5's
      # clock and interruptible-delay primitives (CFG-15..CFG-21; phase 5a, Task 8 adds it).
      # Adding the keyword later widens this signature rather than narrowing it, so NFR-4's API
      # lock is not prejudiced.
      def value(cancellation: nil)
        wait(cancellation: cancellation)
        settlement = @completer.outcome
        # Steep cannot see that #wait only returns once the outcome is written.
        raise Dexpace::SeamError, "the future returned from its wait unsettled" if settlement.nil?

        error = settlement.error
        raise error unless error.nil?

        settlement.response
      end

      # Invoked exactly once with the Settlement, on the settling thread-or-fiber; at once when
      # the future has already settled, so a late registration is never lost.
      def on_settle(&)
        @completer.on_settle(&)
        self
      end

      # Cooperative cancellation: settles the future promptly and asks the producer to notice
      # through Completer#on_cancel. A no-op once settled -- a delivered response is never closed
      # (SEAM-16's last clause, ASYNC-20).
      def cancel(reason = nil)
        @completer.request_cancel(reason)
        self
      end

      # Derives a future from this one's value, so a caller can adapt a response without blocking a
      # thread to do it -- the shape every core consumer of the pivot already hand-rolls out of
      # #on_settle plus a second Completer.
      #
      # Four rules, and none of them is new: the block runs only on a success and the derived
      # future settles with what it returns; a failure is forwarded as **the same object**, because
      # this port never wraps; a cancellation is forwarded as a *cancellation* rather than as a
      # plain failure, so `#cancelled?` stays true one link down and RETRY/XCUT-2 classification
      # still reads #reason's class; and cancelling the derived future cancels the one it came
      # from, which is the bidirectional half SEAM-18 and ASYNC-6 ask for. Neither direction loops:
      # Completer#request_cancel returns false on an already-settled completer.
      #
      # It settles through Completer#fulfil, so **SEAM-30 applies to a derived future exactly as to
      # any other**: a mapped value that loses the completion race is closed through
      # Dexpace.close_quietly rather than leaked. That is the whole reason the block's result is
      # not written to the outcome directly.
      #
      # A block that raises fails the derived future instead of escaping the settling thread, and a
      # block returning nil fails it through Settlement's "exactly one of response or error" rule
      # rather than leaving it unsettled -- both because the call sits inside the rescue.
      #
      # The name shadows Kernel#then (yield_self) on this class deliberately: on a future the
      # promise-combinator reading is the only one a caller means, and leaving Kernel#then
      # reachable here would hand back the block's value rather than a Future.
      def then(&block)
        raise Dexpace::InvalidArgumentError, "then requires a block" unless block

        derived = Completer.new
        derived.on_cancel { |reason| cancel(reason) }
        on_settle { |settlement| forward(settlement, derived, block) }
        derived.future
      end

      private

      # The three forwarding rules #then states, in the order a settlement is classified: a
      # cancellation, a failure, a success.
      def forward(settlement, derived, block)
        failure = settlement.error
        if failure.nil?
          map(settlement.response, derived, block)
        elsif settlement.cancelled && failure.is_a?(Dexpace::CancelledError)
          derived.request_cancel(failure.reason)
        else
          derived.fail(failure)
        end
      end

      # The rescue is what keeps a raising block on the settling thread's side of the boundary.
      def map(response, derived, block)
        derived.fulfil(block.call(response))
      rescue ::StandardError => error
        derived.fail(error)
      end
    end
  end
end
