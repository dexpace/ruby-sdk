# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/cancelled_error"
require_relative "error/invalid_argument_error"

module Dexpace
  # A cancellation token: the third argument of both transport seams, the state SEAM-13 asks a
  # blocking transport to honour, and the trigger for SEAM-30's orphaned-response close.
  #
  # The reason is a typed object and never a message string, because XCUT-2 requires a timeout and
  # a cancellation to be told apart by ambient state "even when the runtime represents both with
  # the same exception type" -- which matters in Ruby, where Net::ReadTimeout is distinguishable
  # but Errno::* and IOError are not reliably. Phase 6 classifies on #reason's class.
  #
  # A token is a facade over a frozen list of Sources; the mutable state is theirs. That makes
  # .any a concatenation of source lists rather than a subscription graph, and makes .none a
  # singleton over the empty list that can never be cancelled and allocates nothing per call.
  #
  # What is deliberately absent: deadline-derived tokens and the clock behind them. Those are
  # CFG-15..CFG-21 and phase 5a's (Task 8); .any is the composition point they will use.
  class Cancellation
    private_class_method :new

    # The handle #on_cancel returns. #detach removes that one registration from every source the
    # token observes.
    #
    # A handle rather than `self`, because a registration that cannot be withdrawn is a leak with
    # a polite name: Completer#await registers one per wait on a token the caller may hold for the
    # life of a client, and the closure reaches the Completer and therefore the response it
    # settled with. #detach is idempotent, and a no-op on a source that has already cancelled and
    # cleared its list.
    class Subscription
      # Built by Cancellation#on_cancel and by nothing else.
      def initialize(sources, hook)
        @sources = sources
        @hook = hook
      end

      # @return [nil] always, so a caller cannot branch on a detach outcome
      def detach
        hook = @hook
        @sources.each { |source| source.off_cancel(hook) } unless hook.nil?
        nil
      end
    end

    # @return [Cancellation] the shared, frozen token that is never cancelled
    def self.none = NONE

    # @return [Cancellation::Source] a fresh write side, with its token
    def self.source = Source.new

    # Builds a token over sources directly. Public because phase 5's deadline source composes here
    # and because #merged_with needs a class-level constructor that is not `new`.
    #
    # Public API validates its arguments. Without this guard `Cancellation.over(:nope)` builds a
    # token that raises NoMethodError from inside #cancelled? at some later point, while .any and
    # #merged_with -- the two other composition entry points -- both name the offending class at
    # the call that made the mistake.
    #
    # @raise [Dexpace::InvalidArgumentError] when handed anything but a Source
    def self.over(*sources)
      sources.each do |source|
        next if source.is_a?(Source)

        raise Dexpace::InvalidArgumentError,
              "Cancellation.over accepts Dexpace::Cancellation::Source objects, " \
              "got #{source.class}"
      end
      return NONE if sources.empty?

      new(sources)
    end

    # A token cancelled when any of the inputs is.
    #
    # @raise [Dexpace::InvalidArgumentError] when handed anything but a token
    def self.any(*tokens)
      tokens.each do |token|
        next if token.is_a?(Cancellation)

        raise Dexpace::InvalidArgumentError,
              "Cancellation.any accepts Dexpace::Cancellation tokens, got #{token.class}"
      end
      return NONE if tokens.empty?

      tokens.fetch(0).merged_with(*tokens.drop(1))
    end

    # A token is a frozen list of sources and holds no state of its own: #cancelled? and #reason
    # are computed from the sources on every call.
    #
    # The winner is the cancelled source with the earliest #cancelled_at -- a monotonic nanosecond
    # stamp each Source takes when it cancels -- not the first in list order. Reading the reason
    # off the first cancelled source in list order would make #reason disagree with the reason
    # #on_cancel was just handed for the whole life of the token, which is the one thing a composed
    # token must not do.
    #
    # Ordering by that stamp rather than by a subscription is what lets a token subscribe to
    # NOTHING at construction. The alternative -- subscribe to every source and latch the winner --
    # is also correct and leaks: a token retains one closure on every source for as long as that
    # source lives, and composing a client-lifetime token with a per-call deadline token, which is
    # what .any is for and what phase 5a's deadline: keyword will do on every request, retained 201
    # closures on one source over 200 compositions (measured on 3.2.11 and 4.0.6).
    #
    # What the stamp buys is convergence, not atomicity, and the residual is stated rather than
    # claimed away. A Source takes its stamp BEFORE it takes its own mutex, so a source with the
    # earlier stamp can publish its state after a handler has already fired on a later-stamped one,
    # and #reason then flips to the earlier one. Demonstrated deterministically on 3.2.11, 3.4.10
    # and 4.0.6 by holding one source's mutex across the other's #cancel, and observed in a
    # free-running race 2 times in 120,000 on 3.2.11. No stamp placement closes it: the two sources
    # hold two different mutexes and there is no order between them, so moving the read inside the
    # lock narrows the window without removing it. What holds unconditionally is what a caller may
    # rely on -- the token is cancelled, every reason it ever reports belongs to a source that
    # really was cancelled, and the value converges once every racing source has published.
    #
    # Ties are not the problem and are not treated as one: 0 same-nanosecond collisions in 100,000
    # stamps, with a 50 ns median gap between successive CLOCK_MONOTONIC reads at 1 ns resolution,
    # measured on all three interpreters. Two sources stamped inside one nanosecond tie-break on
    # list order.
    def initialize(sources)
      @sources = sources.freeze
      freeze
    end

    # Composition is an instance method so that #sources can stay protected: a class method has the
    # class as `self` and cannot call a protected instance method, which is what forces #sources
    # public if `.any` does the work itself.
    def merged_with(*others)
      others.each do |other|
        next if other.is_a?(Cancellation)

        raise Dexpace::InvalidArgumentError,
              "merged_with accepts Dexpace::Cancellation tokens, got #{other.class}"
      end
      combined = others.each_with_object(sources.dup) { |other, all| all.concat(other.sources) }
      Cancellation.over(*combined.uniq)
    end

    # Whether any observed source has cancelled.
    def cancelled? = @sources.any?(&:cancelled?)

    # The reason of the source that cancelled first in time. A deliberate `nil` reason is still a
    # cancellation, because #cancelled? is the question and this is not.
    def reason = winner&.reason

    # The check-after-resume primitive: a producer calls this after any operation that may have
    # suspended and before acting on the value it produced (design §3.3).
    #
    # @raise [Dexpace::CancelledError] carrying #reason
    def check!
      raise Dexpace::CancelledError, reason if cancelled?

      nil
    end

    # Each registered block is invoked **exactly once**, whether the token observes one source or
    # several, and the guard is a flag private to that registration. A flag shared across the token
    # would silently drop every registration after the first, which is what makes a second waiter
    # on one token block forever -- a SEAM-18 violation no single-waiter test can see.
    #
    # The guard mutex is held across the flag flip and across nothing else; the block runs outside
    # it, so a handler that blocks cannot deadlock a second fiber of one thread. The handler is
    # handed #reason rather than the firing source's own, so a handler and a later #reason read
    # agree in every ordering the handler itself can observe; #initialize states the window across
    # which they can still disagree, and why no stamp placement closes it.
    #
    # Subscribing happens here and only here: a token nobody registers a callback on subscribes to
    # nothing, so composition costs nothing that outlives the token.
    #
    # @return [Dexpace::Cancellation::Subscription] the handle that detaches this registration.
    #   Returning a handle rather than `self` is what makes a bounded subscription possible at all.
    #   Composition subscribing to nothing is only half the leak: the other half is a registration
    #   that outlives what it was made for. `.any(client_token, per_call_token)` with
    #   `future.value(cancellation:)` -- what phase 5a's deadline: keyword does on every request --
    #   retained one closure, and through it one response, per request on the client-lifetime
    #   source: measured 200 of 200 on all three interpreters before #await detached. A caller
    #   registering for the life of the token ignores the value.
    def on_cancel(&block)
      raise Dexpace::InvalidArgumentError, "on_cancel requires a block" unless block
      return Subscription.new(@sources, nil) if @sources.empty?

      once = once_only { yield reason }
      @sources.each { |source| source.on_cancel(&once) }
      Subscription.new(@sources, once)
    end

    protected

    # Protected, not public: only another token composes on it, and that is #merged_with.
    attr_reader :sources

    private

    # The per-registration guard: a lambda that runs the block on its first call and never again.
    # The guard mutex is held across the flag flip and across nothing else.
    def once_only
      fired = false
      guard = ::Thread::Mutex.new
      lambda do |_source_reason|
        run = guard.synchronize do
          if fired
            false
          else
            fired = true
          end
        end
        yield if run
      end
    end

    def winner = @sources.select(&:cancelled?).min_by { |source| source.cancelled_at || 0 }

    NONE = new([])
    private_constant :NONE
  end
end
