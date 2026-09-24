# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../executor_case"
require_relative "../runner"

module Dexpace
  module Conformance
    module ExecutorSuite
      # Group 1, the executor's lifecycle: SEAM-12 with XCUT-11, XCUT-13 with ASYNC-15's clauses
      # (a) and (b), XCUT-22 with the same, and ASYNC-16. A private_constant of ExecutorSuite.
      module Lifecycle
        extend self

        # How many units the graceful-shutdown assertion posts before it closes.
        DRAIN = 8
        # Seconds every poster has, in total, to return from `#post`. Submission is not the work:
        # an executor whose `#post` blocks is the shape that would park this assertion for ever,
        # so the join is bounded and an expired one is the failure (8a's "every wait carries a
        # bound" rule, which `await_closed_connection` fixed for this gem).
        POST_BOUND = 1.0

        # SEAM-12 / XCUT-11: "invoke one shared instance from many threads and assert no
        # cross-talk." Sixteen threads each post a distinct value; the assertion is on the
        # collected set, never on timing, so the test runs alone in any order.
        def concurrent_post(subject)
          pool = subject.executor
          seen = ::Thread::Queue.new
          posters = ::Array.new(ExecutorCase::THREADS) do |index|
            ::Thread.new { pool.post { seen << index } }
          end
          check_posters_returned(posters)
          pool.close
          collected = drain(seen)

          Check.that(collected == (0...ExecutorCase::THREADS).to_a,
                     "work posted from many threads was lost or duplicated",
                     expected: ExecutorCase::THREADS, actual: collected.size,
                     ids: %w[SEAM-12 XCUT-11],)
        end

        # The bounded half of `concurrent_post`, kept apart so the assertion reads as one thought.
        # A poster still running when the budget is spent has a `#post` that blocks, which is a
        # non-conformance to report and not a run to hang; the whole set shares ONE budget, so
        # sixteen stuck posters cost one bound and not sixteen.
        # @return [nil]
        def check_posters_returned(posters)
          stuck = still_running(posters, POST_BOUND)

          Check.that(stuck.zero?, "posting work from many threads did not return",
                     expected: "every #post returns", actual: "#{stuck} still posting",
                     ids: %w[SEAM-12 XCUT-11],)
        end

        # @return [Integer] how many of the threads were still alive when the budget ran out
        def still_running(threads, budget)
          deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + budget
          threads.count do |one|
            left = deadline - ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
            one.join(left.positive? ? left : 0).nil?
          end
        end

        # XCUT-13 / ASYNC-15 clauses (a) and (b): close is latched and ownership-aware. Clause
        # (c), interrupt-safety, is SCOPED OUT with its reason -- §8.3 bans every primitive that
        # could arrange a pending interrupt, so the clause holds by the flag never being touched
        # and there is nothing observable to assert.
        #
        # Two halves, because only one needs a recorder. `Closeable#close` answers nil on the
        # winning AND the losing call, which is assertable against any adapter; that the shutdown
        # WORK ran once is visible only in the lifecycle event, so that half runs when the driver
        # declared `record_events:` and is SKIPPED -- not failed -- when it did not. What is lost
        # without a recorder is worth naming: an UNLATCHED executor passes this assertion, because
        # "the shutdown ran twice" is visible nowhere else.
        def close_is_latched(subject)
          pool = subject.executor
          pool.close
          second = outcome_of(-> { pool.close })
          Check.that(second.nil?,
                     "a second close raised or returned a value instead of latching",
                     expected: nil, actual: second, ids: %w[XCUT-13 ASYNC-15],)

          return nil unless subject.events?

          shutdowns = subject.shutdowns
          Check.that(shutdowns == 1, "close shut the executor more than once",
                     expected: 1, actual: shutdowns, ids: %w[XCUT-13 ASYNC-15],)
        end

        # XCUT-22 / ASYNC-15 clause (b): the SDK closes only what it created. So the borrowed
        # executor must still be USABLE afterwards -- observable with no recorder at all -- and
        # must have emitted no shutdown event.
        def borrowed_executor_survives(subject)
          underlying = subject.executor
          subject.borrowed(underlying).close
          alive = ::Thread::Queue.new
          still_open = outcome_of(-> { underlying.post { alive << :ok } }).nil?

          Check.that(still_open, "the SDK shut down an executor it borrowed",
                     expected: "still accepting work", actual: "refused work",
                     ids: %w[XCUT-22 ASYNC-15],)
          check_no_shutdown(subject)
          underlying.close
          nil
        end

        # XCUT-22's event half, which runs only when the driver declared `record_events:`.
        # @return [nil]
        def check_no_shutdown(subject)
          return nil unless subject.events?

          shutdowns = subject.shutdowns
          Check.that(shutdowns.zero?,
                     "the SDK emitted a shutdown event for an executor it borrowed",
                     expected: 0, actual: shutdowns, ids: %w[XCUT-22 ASYNC-15],)
        end

        # ASYNC-16 (SHOULD): "shut it down gracefully on close -- stop accepting new work and WAIT
        # for in-flight tasks to finish rather than interrupting them." Both halves are observable
        # without an interrupt.
        def graceful_shutdown(subject)
          pool = subject.executor
          done = ::Thread::Queue.new
          DRAIN.times { |index| pool.post { done << index } }
          pool.close
          drained = drain(done)

          Check.that(drained == (0...DRAIN).to_a,
                     "close did not wait for in-flight work to finish",
                     expected: DRAIN, actual: drained.size, ids: ["ASYNC-16"],)
          check_refusal(pool, done)
        end

        # ASYNC-16's second half: nothing new is accepted after close.
        # @return [nil]
        def check_refusal(pool, done)
          refused = !outcome_of(-> { pool.post { done << :after } }).nil?

          Check.that(refused || done.empty?, "the executor accepted new work after close",
                     expected: "refused", actual: "accepted", ids: ["ASYNC-16"],)
        end

        # @return [Array<untyped>] everything the queue holds, sorted, taken without blocking
        def drain(queue)
          collected = [] #: Array[untyped]
          collected << queue.pop until queue.empty?
          collected.sort
        end

        # The error a call raised, or nil when it returned. Vacuous and Failure are re-raised:
        # both are ::StandardError descendants, so a bare rescue would swallow this suite's own.
        def outcome_of(callable)
          callable.call
          nil
        rescue Vacuous, Failure
          raise
        rescue ::StandardError => error
          error
        end

        ROWS = [
          [%w[SEAM-12 XCUT-11], "a shared executor takes work from many threads", :concurrent_post],
          [%w[XCUT-13 ASYNC-15], "an owned executor's close is idempotent", :close_is_latched],
          [%w[XCUT-22 ASYNC-15], "a caller-supplied executor survives its holder's close",
           :borrowed_executor_survives,],
          ["ASYNC-16", "close drains in-flight work and refuses new work", :graceful_shutdown],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Lifecycle
    end
  end
end
