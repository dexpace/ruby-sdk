# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"
require_relative "cancellation"
require_relative "error/invalid_argument_error"
require_relative "error/cancelled_error"

module Dexpace
  # The injectable time seam (CFG-15): the wall clock, the monotonic ELAPSED-TIME counter (CFG-16
  # -- not CTX-4's call-sequence counter, which shares nothing with it but the adjective) and the
  # cancellable sleep (CFG-17), with SYSTEM as the shared platform-backed default. Time-dependent
  # logic routes through a clock so a test can drive time deterministically; every phase-8 adapter
  # takes `clock:` rather than calling Time.now.
  #
  # EXACTLY three instance methods, because CFG-15 says "exposing three operations" and a fake
  # owes the seam what the seam declares. CFG-18's delay is Dexpace::Async.delay and not a fourth
  # method here (P5-10); .deadline_in is a class method for the same reason. The clock is an
  # injected object with a shared default and NOT a discovered seam: SEAM-2 enumerates five seams
  # and this is none of them, so there is no fourth registry.
  #
  # A class, not a module: it implements behaviour (data-modeling/3e37c086). SYSTEM is frozen and
  # stateless, which is what makes it XCUT-11's audited shared instance.
  class Clock
    # The two argument checks #sleep and .deadline_in share. A private module rather than two
    # private class methods, because an instance method cannot call a private singleton method
    # with the explicit receiver it needs.
    module Guard
      extend self

      # @return [Float] the duration as seconds
      def duration(value)
        Model.required!("duration", value)
        unless value.is_a?(::Numeric)
          raise InvalidArgumentError, "duration must be a number of seconds, got #{value.class}"
        end
        raise InvalidArgumentError, "duration must be non-negative, got #{value}" if value.negative?

        # rbs's Numeric declares no #to_f (its subclasses do), so the conversion reads the value
        # untyped after the check above has done the typing.
        seconds = value #: untyped
        seconds.to_f
      end

      # @return [Dexpace::Cancellation, nil] nil for no token or the never-cancelled one
      def token(cancellation)
        return nil if cancellation.nil?

        unless cancellation.is_a?(Dexpace::Cancellation)
          raise InvalidArgumentError,
                "cancellation: takes a Dexpace::Cancellation, got #{cancellation.class}"
        end
        cancellation.equal?(Dexpace::Cancellation.none) ? nil : cancellation
      end
    end
    private_constant :Guard

    # The current wall-clock instant. CFG-16 forbids using it for elapsed time: it may move
    # backwards.
    #
    # @return [Time]
    def now
      ::Time.now
    end

    # The elapsed-time counter (CFG-16): CLOCK_MONOTONIC in seconds, non-decreasing across its
    # own readings (100 000 successive readings verified so, at 1 ns resolution), meaningful only
    # as a difference between two of them. Never Time.now.
    #
    # @return [Float] seconds on a scale whose absolute value means nothing
    def monotonic
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    # The blocking interruptible sleep (CFG-15, CFG-17): a bounded wait on a per-call
    # Thread::Queue that the cancellation token pushes to on cancel (design §10.17). Never
    # Kernel#sleep, which nothing can wake; never Timeout.timeout, Thread#raise or Thread#kill,
    # which §8.3 forbids because an asynchronous interrupt lands on any bytecode. Under a
    # registered Fiber.scheduler the pop routes through the scheduler's block/unblock hooks and
    # unmounts the fiber (verified on 3.2.11, 3.4.10 and 4.0.6); with none it blocks only the
    # calling thread, by design, never a shared pool thread.
    #
    # Clause by clause: a negative duration is refused with InvalidArgumentError -- the guard is
    # this method's, because Queue#pop(timeout: -1) returns nil at once and raises nothing; zero
    # returns promptly with no queue and no subscription, and CFG-17's "possibly yielding" MAY is
    # not taken, since a Thread.pass would make a zero sleep a scheduling event; a cancelled token
    # raises Dexpace::CancelledError at the caller's own next instruction, through
    # Cancellation#check!, which is CFG-17's "re-assert the cancellation status before
    # propagating" met structurally -- the token's #cancelled? was set before the push that woke
    # this wait, so a downstream handler inspecting the token observes the cancelled state.
    # XCUT-3's "surfacing the cancellation signal rather than a spurious timeout" is the same
    # clause from the other end.
    #
    # @param duration [Numeric] seconds; zero returns at once
    # @param cancellation [Dexpace::Cancellation, nil] the token that can cut the wait short
    # @return [nil]
    # @raise [Dexpace::InvalidArgumentError] on a negative or non-numeric duration, or a
    #   cancellation that is not a token
    # @raise [Dexpace::CancelledError] when the token is or becomes cancelled
    def sleep(duration, cancellation: nil)
      seconds = Guard.duration(duration)
      token = Guard.token(cancellation)
      return nil if seconds.zero?

      token&.check!
      queue = ::Thread::Queue.new
      subscription = token&.on_cancel { queue.push(:cancel) }
      begin
        # nil means the duration elapsed and :cancel means the token fired. Sound ONLY because this
        # queue is per-call, private and never closed -- a closed queue pops nil too (fact 8).
        token&.check! if queue.pop(timeout: seconds) == :cancel
      ensure
        # P2-14 made Subscription#detach public for exactly this: the hook lives on the caller's
        # token, which may outlive the wait by the life of a client.
        subscription&.detach
      end
      nil
    end

    # The monotonic instant `duration` seconds ahead on `clock`'s scale -- what the `deadline:`
    # keyword on Future#value, #wait and Completer#await takes. It exists because computing a
    # deadline off Time.now is the exact mistake CFG-16 forbids, and a helper that names the scale
    # is the cheapest way to make it hard. A class method, deliberately: _Clock declares three
    # instance methods and a fake owes the seam exactly those.
    #
    # @param duration [Numeric] seconds ahead
    # @param clock [#monotonic] the seam the deadline is measured against
    # @return [Float] an instant on Clock#monotonic's scale, not a duration
    # @raise [Dexpace::InvalidArgumentError] on a negative or non-numeric duration
    def self.deadline_in(duration, clock: SYSTEM)
      clock.monotonic + Guard.duration(duration)
    end

    # CFG-15's "shared default backed by the platform clock MUST be provided".
    SYSTEM = new.freeze
  end
end
