# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "settlement"
require_relative "../closeable"
require_relative "../cancellation"
require_relative "../hooks"
require_relative "../clock"
require_relative "../error/cancelled_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Async
    # The deadline: keyword's two argument checks, shared by Completer#await and, through it,
    # Future#wait and #value. A private module because the checks are the same at every entry.
    module Deadline
      extend self

      # @return [Float, nil] the deadline as a Float instant, or nil for no deadline
      def validate(deadline, clock)
        return nil if deadline.nil?

        unless deadline.is_a?(::Numeric)
          raise Dexpace::InvalidArgumentError,
                "deadline: takes a monotonic instant (Numeric), got #{deadline.class}"
        end
        unless clock.respond_to?(:monotonic)
          raise Dexpace::InvalidArgumentError,
                "clock: takes a Dexpace::_Clock answering #monotonic, got #{clock.class}"
        end

        instant = deadline #: untyped
        instant.to_f
      end

      # The wait itself: pops `gate` until the block answers settled -- phase 2's unbounded loop
      # when `limit` is nil, and otherwise with a timeout recomputed from `clock` on every
      # iteration until `limit` passes. A closed gate pops nil at once, so a settlement that lands
      # between two iterations ends the loop on the next read.
      #
      # @return [Boolean] whether the limit passed with the block still answering false
      def expired?(gate, limit, clock)
        until yield
          if limit.nil?
            gate.pop
            next
          end

          remaining = limit - clock.monotonic
          return true if remaining <= 0

          gate.pop(timeout: remaining)
        end
        false
      end
    end
    private_constant :Deadline

    # The write side of the canonical async pivot, and where the pivot's state lives.
    #
    # Design §10.3: the pivot is core-owned because Ruby's async ecosystem is fragmented across
    # Async::Task, Concurrent::Promises::Future, Thread plus Thread::Queue and EventMachine
    # descendants, none in the standard library and all with different cancellation semantics.
    # Adopting one would put a third-party type in core's public surface, which SEAM-1 and NFR-11
    # forbid. SEAM-17 is a SHOULD naming the pattern, not the type.
    #
    # A Completer is handed only to the producer, so a consumer cannot settle someone else's
    # future. Every constant reached from this namespace is written ::-qualified: once
    # dexpace-async-thread is required, a bare `Thread` here is Dexpace::Async::Thread, and core's
    # own suite never requires that gem (verified on 3.2.11 and 4.0.6).
    #
    # #fulfil, #fail and #request_cancel are commands that report whether they took effect, not
    # queries: the design fixes those names, and a `?` suffix would misname a mutator.
    class Completer
      def initialize
        @mutex = ::Thread::Mutex.new
        @gate = ::Thread::Queue.new
        @outcome = nil
        @on_settle = [] #: Array[^(Dexpace::Async::Settlement) -> void]
        @on_cancel = [] #: Array[^(untyped) -> void]
        @future = nil
      end

      # @return [Dexpace::Async::Future] the read side, memoised
      def future = @future ||= Future.new(self)

      # Whether an outcome has been published.
      def settled? = !@outcome.nil?

      # @return [Dexpace::Async::Settlement, nil]
      attr_reader :outcome

      # Deliver a response. Returns false when the race was already lost, and closes the response
      # it was handed on that path -- SEAM-30, implemented once here so it holds for every adapter
      # that settles through a Completer rather than depending on each one remembering.
      def fulfil(response)
        delivered = settle(Settlement.success(response))
        Dexpace.close_quietly(response) unless delivered
        delivered
      end

      # Deliver a failure; #value re-raises the identical object, so there is no wrapper to unwrap
      # (SEAM-18).
      def fail(error)
        unless error.is_a?(::Exception)
          raise Dexpace::InvalidArgumentError, "fail requires an exception, got #{error.class}"
        end

        settle(Settlement.failure(error))
      end

      # Cooperative: this cannot pre-empt a producer, because Ruby's only pre-emption primitives
      # are Thread#raise and Thread#kill and design §8.3 forbids them. The producer's obligation is
      # check-after-resume (design §3.3), and #on_cancel is how it can abort sooner.
      #
      # **The outcome is published before the hooks run**, and the hooks are stolen under the same
      # lock that publishes it. Written the other way round -- notify, then settle -- one raising
      # hook aborts the method and the future is left permanently unsettled, so every #value on it
      # blocks forever. Reachable through the public API alone, and reproduced on 3.2.11, 3.4.10
      # and 4.0.6: `completer.on_cancel { raise }` followed by `completer.future.cancel(:stop)`
      # left #settled? false. That is the same "the future never settled and #value would block"
      # failure Bridge::AsyncOver#deliver's rescue closes, arriving from the other side, so it
      # gets the same answer: a cancellation always publishes an outcome. Stealing the hooks in
      # the publishing step, rather than before it, also means a producer's abort hook fires only
      # when the cancellation actually won the race against its own #fulfil.
      def request_cancel(reason = nil)
        settle(Settlement.cancellation(Dexpace::CancelledError.new(reason)))
      end

      # The producer's hook to abort promptly rather than only at its next resume point. Runs at
      # once when the future was already cancelled, and never when it settled any other way.
      def on_cancel(&block)
        raise Dexpace::InvalidArgumentError, "on_cancel requires a block" unless block

        already = @mutex.synchronize do
          if @outcome
            @outcome
          else
            @on_cancel << block
            nil
          end
        end
        yield cancel_reason(already) if already&.cancelled
        self
      end

      # Invoked exactly once with the Settlement, on the settling thread-or-fiber; at once, on the
      # calling one, when the future has already settled.
      def on_settle(&block)
        raise Dexpace::InvalidArgumentError, "on_settle requires a block" unless block

        settled = @mutex.synchronize do
          if @outcome
            @outcome
          else
            @on_settle << block
            nil
          end
        end
        yield settled if settled
        self
      end

      # Blocks the calling thread-or-fiber on a Thread::Queue pop, never a spin and never a
      # Kernel#sleep poll: under a registered Fiber.scheduler a blocking queue pop routes through
      # the scheduler's block/unblock hooks instead of parking the OS thread (verified on 3.2.11,
      # 3.4.10 and 4.0.6; Task 6 asserts it).
      #
      # `deadline:` is the keyword phase 2 postponed to phase 5 (P2-5): an INSTANT on
      # Clock#monotonic's scale, never a duration, so a wait resumed spuriously cannot extend it
      # -- `remaining` is recomputed from `clock` on every iteration and the TOTAL wait is what is
      # bounded. Clock.deadline_in is how a caller names the scale; computing one off Time.now is
      # the mistake CFG-16 forbids. On expiry this cancels the future through #request_cancel --
      # one settlement, published before the hooks run, so the producer's abort hook fires and
      # SEAM-30's lost-race close applies to whatever it later delivers -- and returns. It does
      # not raise: #await never raised and Future#wait is documented never to raise the failure,
      # so raising here would narrow two signatures NFR-4 locks. Future#value raises on its next
      # line, because the settlement it finds is a cancellation carrying :deadline_expired, a
      # Symbol and not a sentence (XCUT-2: a deadline and a cancel are told apart by #reason,
      # never by a string match). A deadline bounds a wait; it aborts nothing in the background,
      # and nothing fires when nobody is waiting. The mechanism is a timed gate pop, not a
      # deadline-derived token composed through Cancellation.any as phase 2 anticipated.
      #
      # The two keywords are validated BEFORE the settled short-circuit: a settled future ignores
      # an expired deadline, not an invalid one, and a wrong argument type is the caller's error
      # whichever state the completer is in. The positional token keeps phase 2's order -- it is
      # armed only when there is a wait to arm it for.
      #
      # @param cancellation [Dexpace::Cancellation, nil] positional, as phase 2 shipped it
      # @param deadline [Numeric, nil] a monotonic instant; nil is phase 2's unbounded wait
      # @param clock [_Clock] the seam the deadline is measured against
      # @return [self]
      # @raise [Dexpace::InvalidArgumentError] on a non-Numeric deadline or a clock without
      #   #monotonic, settled or not
      def await(cancellation = nil, deadline: nil, clock: Dexpace::Clock::SYSTEM)
        limit = Deadline.validate(deadline, clock)
        return self if settled?

        subscription = arm(cancellation)
        begin
          # An expiry that loses the race to a real settlement is a no-op: #request_cancel
          # returns false on a settled completer.
          request_cancel(:deadline_expired) if Deadline.expired?(@gate, limit, clock) { settled? }
        ensure
          subscription&.detach
        end
        self
      end

      private

      # The registration is detached in #await's `ensure`, whichever way the wait ends.
      #
      # It has to be. The hook lives on the caller's token, which a caller may hold for the life of
      # a client, and the closure reaches this Completer and through it the response the future
      # settled with. `.any(client_token, per_call_token)` with `future.value(cancellation:)` --
      # what phase 5a's deadline: keyword will do on every request -- retained one closure and one
      # response per request on the client-lifetime source: measured 200 of 200 on 3.2.11, 3.4.10
      # and 4.0.6, and 500 100 KB responses still reachable after GC.start. Per-call tokens narrow
      # the blast radius and do not close it, because the whole point of .any is composing a
      # per-call token with a long-lived one.
      #
      # The reason a cancelled settlement carries; nil for any other settlement.
      def cancel_reason(settlement)
        error = settlement.error
        error.is_a?(Dexpace::CancelledError) ? error.reason : nil
      end

      # @return [Dexpace::Cancellation::Subscription, nil] nil when there was nothing to arm
      def arm(cancellation)
        return nil if cancellation.nil?

        unless cancellation.is_a?(Dexpace::Cancellation)
          raise Dexpace::InvalidArgumentError,
                "cancellation: takes a Dexpace::Cancellation, got #{cancellation.class}"
        end
        return nil if cancellation.equal?(Dexpace::Cancellation.none)

        cancellation.on_cancel { |reason| request_cancel(reason) }
      end

      # The queue is a wake-up signal and never the value channel: Thread::Queue#pop returns nil
      # for a timeout, for a closed queue and for a pushed nil alike (verified on all three
      # interpreters), so a pivot that carried its value through the queue could not tell
      # "settled with nothing" from "not settled".
      #
      # The mutex is held across the outcome write and the callback-list steal and across nothing
      # else. Callbacks run outside it, so an #on_settle handler that blocks cannot deadlock a
      # second fiber of the same thread, and they go through Hooks.notify so that one raising
      # handler cannot drop the rest of the list. On a cancellation the producer's abort hooks run
      # first and the settle callbacks run whatever the abort hooks did.
      def settle(settlement) # rubocop:disable Naming/PredicateMethod -- a command reporting whether it won the race, like the three public commands above it
        taken = @mutex.synchronize do
          if @outcome
            nil
          else
            @outcome = settlement
            both = [@on_settle, @on_cancel] #: stolen
            @on_settle = []
            @on_cancel = []
            both
          end
        end
        return false if taken.nil?

        @gate.close
        callbacks, abort_hooks = taken
        begin
          Hooks.notify(abort_hooks, cancel_reason(settlement)) if settlement.cancelled
        ensure
          Hooks.notify(callbacks, settlement)
        end
        true
      end
    end
  end
end
