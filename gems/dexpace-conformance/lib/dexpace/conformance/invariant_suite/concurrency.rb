# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../runner"
require_relative "outcomes"

module Dexpace
  module Conformance
    module InvariantSuite
      # Group 9, cancellation and the inter-attempt wait: XCUT-1, XCUT-2 and XCUT-3.
      # A private_constant of InvariantSuite.
      module Concurrency
        extend self

        # A wait this long has not been "promptly cancellable" by any reading of XCUT-3.
        WAKE_BOUND_SECONDS = 0.5
        # Long enough that an uncancelled wait would blow the bound by an order of magnitude.
        WAIT_SECONDS = 30.0

        # Each assertion below is one requirement's CLAUSES, and each clause is one Check, so the
        # metric is counting the requirement's own size. Splitting by count would split by
        # arithmetic rather than by behaviour -- which is .rubocop.yml's own recorded argument for
        # turning Minitest/MultipleAssertions off, applied to the assertions that mirror them.
        # rubocop:disable Metrics/AbcSize
        # XCUT-1: "a cancellation MUST be surfaced as a distinct, TERMINAL, NON-retryable signal,
        # kept separate from a timeout ... and never let a cancelled operation be automatically
        # retried."
        #
        # The non-retryability is checked through the classifier AND through a wrapper, because a
        # transport that wrapped the token's raise in its own always-retryable error is the case
        # the requirement exists for: a check reading only the outermost error would retry it.
        def cancellation_is_terminal(subject)
          subject.probe!(:Cancellation, "phase 2's seam layer")
          subject.probe!(:CancelledError, "phase 2's seam layer")
          policy = subject.core.const_get(:Resilience).const_get(:Policy)
          source = subject.core.const_get(:Cancellation).source
          source.cancel(:interrupt_requested)
          raised = Outcomes.raised_by(-> { source.token.check! })

          Check.that(raised.is_a?(subject.core.const_get(:CancelledError)),
                     "a cancelled token did not surface the distinct cancellation type",
                     expected: "Dexpace::CancelledError", actual: raised&.class, ids: ["XCUT-1"],)
          Check.that(!policy.throwable_retryable?(raised),
                     "a cancellation classified retryable, so a cancelled operation can be retried",
                     expected: false, actual: true, ids: ["XCUT-1"],)
          Check.that(policy.cancellation?(wrap(raised)),
                     "a cancellation wrapped in a retryable transport error was not recognised, " \
                     "so the wrapper makes it retryable again",
                     expected: true, actual: false, ids: ["XCUT-1"],)
        end

        # XCUT-2: "a TIMEOUT MUST be classified as a RETRYABLE transport failure and MUST NOT set
        # the cancellation flag. Timeout and cancellation MUST be told apart BY THE AMBIENT
        # CANCELLATION STATE, not by matching an error message string, even when the timeout type
        # is a SUBTYPE of the cancellation type -- the timeout branch must be checked first to
        # stay reachable."
        def timeout_is_retryable_and_distinct(subject)
          policy = subject.core.const_get(:Resilience).const_get(:Policy)
          timeout = subject.core.const_get(:TransportError).new("read timed out", phase: :read)
          subtype = Class.new(subject.core.const_get(:CancelledError))

          Check.that(policy.throwable_retryable?(timeout),
                     "a read timeout did not classify as a retryable transport failure",
                     expected: true, actual: false, ids: ["XCUT-2"],)
          Check.that(!subject.core.const_get(:Cancellation).none.cancelled?,
                     "a timeout set the ambient cancellation flag",
                     expected: false, actual: true, ids: ["XCUT-2"],)
          Check.that(policy.cancellation?(subtype.new("elapsed")),
                     "a cancellation SUBTYPE was not recognised, so the two are told apart by a " \
                     "message string rather than by the type",
                     expected: true, actual: false, ids: ["XCUT-2"],)
        end

        # XCUT-3: "inter-attempt waits MUST be promptly cancellable: a pending wait MUST abort
        # near-immediately when the operation is cancelled, surface the cancellation signal (not a
        # spurious timeout), and cancel any timer it armed."
        #
        # A thirty-second wait cancelled from another thread, bounded at half a second. The wait
        # must RAISE the cancellation rather than return a value, which is the "not a spurious
        # timeout" half. Kernel#sleep would fail this: it cannot be woken without Thread#raise,
        # which §8.3 bans.
        def interruptible_waits(subject)
          subject.probe!(:Clock, "5a's configuration layer")
          source = subject.core.const_get(:Cancellation).source
          settled, elapsed, parked = wait_and_cancel(subject, source)

          # The cancel must land while the wait is PENDING, which is what "a pending wait aborts"
          # means. Without this the cancel could beat the waiter into Clock#sleep, whose own entry
          # check then raises -- and an implementation that ignores the token entirely passes.
          # Measured: it did. So the barrier is asserted rather than assumed.
          Check.that(parked, "the waiter never reached the wait, so the cancel was not delivered " \
                             "to a PENDING wait and this assertion could not discriminate",
                     expected: "parked", actual: "never parked", ids: ["XCUT-3"],)
          Check.that(!settled.nil?,
                     "a pending inter-attempt wait was not released by a cancellation",
                     expected: "released within #{WAKE_BOUND_SECONDS}s", actual: "still waiting",
                     ids: ["XCUT-3"],)
          Check.that(settled.is_a?(subject.core.const_get(:CancelledError)),
                     "a cancelled wait surfaced something other than the cancellation signal",
                     expected: "Dexpace::CancelledError", actual: settled.class, ids: ["XCUT-3"],)
          Check.that(elapsed < WAKE_BOUND_SECONDS, "the wait was not released near-immediately",
                     expected: "< #{WAKE_BOUND_SECONDS}s", actual: elapsed.round(3),
                     ids: ["XCUT-3"],)
        end

        # @return [Array(untyped, Float, bool)] what the wait surfaced, how long the cancel took,
        #   and whether the waiter was parked in the wait when the cancel was issued
        def wait_and_cancel(subject, source)
          outcome = ::Thread::Queue.new
          waiter = ::Thread.new do
            subject.core.const_get(:Clock)::SYSTEM.sleep(WAIT_SECONDS, cancellation: source.token)
            outcome << :returned
          rescue ::StandardError => error
            outcome << error
          end
          parked = parked?(waiter)
          started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          source.cancel(:interrupt_requested)
          settled = outcome.pop(timeout: WAKE_BOUND_SECONDS)
          elapsed = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started
          waiter.join(WAKE_BOUND_SECONDS)
          [settled, elapsed, parked]
        end

        # Spins until the thread is blocked, bounded. `Thread#status` is "sleep" for a thread
        # parked on a queue, a mutex or a sleep on every supported interpreter, and `false` for one
        # that has already finished -- which is NOT parked and is reported as such. A spin and not
        # a sleep-and-hope: the bound is what makes it terminate, and the return value is what the
        # assertion checks rather than assumes.
        def parked?(thread, bound: WAKE_BOUND_SECONDS)
          deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + bound
          until ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) > deadline
            return true if thread.status == "sleep"
            break unless thread.status

            ::Thread.pass
          end
          false
        end

        # An adapter's own retryable wrapper around the token's raise: the shape a check that read
        # only the outermost error would retry.
        def wrap(inner)
          raise inner
        rescue ::StandardError
          begin
            raise "an adapter's own retryable wrapper"
          rescue ::StandardError => outer
            outer
          end
        end

        # rubocop:enable Metrics/AbcSize

        ROWS = [
          ["XCUT-1", "a cancellation is terminal and never retried", :cancellation_is_terminal],
          ["XCUT-2", "a timeout is retryable and is told apart from a cancellation by state",
           :timeout_is_retryable_and_distinct,],
          ["XCUT-3", "a pending inter-attempt wait is promptly cancellable", :interruptible_waits],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Concurrency
    end
  end
end
