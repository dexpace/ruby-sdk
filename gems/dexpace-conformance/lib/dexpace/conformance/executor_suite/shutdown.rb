# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../runner"
require_relative "../vacuous"

module Dexpace
  module Conformance
    module ExecutorSuite
      # Group 2, the no-op default, the lifecycle event and the interrupt MUST: ASYNC-17, SEAM-25
      # and ASYNC-3. A private_constant of ExecutorSuite.
      module Shutdown
        extend self

        # Seconds a cancelled worker has to be released in. The requirement's own shape is "within
        # a bound"; this is one, and it is generous.
        BLOCKED_WORKER_BOUND = 1.0

        # ASYNC-17 (SHOULD): "the async transport SPI SHOULD provide a NO-OP DEFAULT close so
        # lightweight/functional implementations need not implement lifecycle management." A no-op
        # close shuts nothing down, so it emits no lifecycle event -- the same recorder, read for
        # zero rather than for one.
        def default_close_is_a_no_op(subject)
          functional = subject.functional
          Check.that(functional.respond_to?(:close),
                     "a functional implementation has no close at all",
                     expected: "#close", actual: "absent", ids: ["ASYNC-17"],)
          functional.close
          functional.close

          return nil unless subject.events?

          shutdowns = subject.shutdowns
          Check.that(shutdowns.zero?,
                     "a resource-free implementation's close shut something down",
                     expected: 0, actual: shutdowns, ids: ["ASYNC-17"],)
        end

        # SEAM-25, the harness half phase 2 postponed and 8b's design assigned to 8a, which wrote
        # no executor suite: one lifecycle event on the FIRST close of an owned executor, and none
        # on the second. The event name is core's; the two field keys around it are the adapter's
        # private constants and are never read.
        def one_shutdown_event(subject)
          raise Vacuous, "no event recorder supplied to ExecutorSuite.run" unless subject.events?

          pool = subject.executor
          pool.close
          pool.close
          shutdowns = subject.shutdowns

          Check.that(shutdowns == 1,
                     "an owned executor's close did not emit exactly one event",
                     expected: 1, actual: shutdowns, ids: ["SEAM-25"],)
        end

        # ASYNC-3, an UNSATISFIED MUST (design §10.5): "cancel-with-interrupt against a blocking
        # worker". Written so it genuinely FAILS on every executor this repository can build --
        # the thread pool cannot interrupt a worker, because §8.3 bans Thread#raise, Thread#kill
        # and Timeout.timeout outright -- and the first-party drivers waive it BY ID so the report
        # prints `waived (would fail): ASYNC-3`, never passed and never vacuous. That is appendix
        # B.7's "recorded as FAILING rather than vacuous" item given a runnable subject.
        #
        # The pivot is core's `Transport.async_over`, which is how a cancellation token reaches a
        # posted unit at all: the executor SPI's `#post` takes none. The wait is the requirement's
        # own shape, "within a bound", observed through queues -- the worker's ENTRY is a queue
        # push, so no sleep guesses that it started -- and the ensure frees the gate so a failed
        # run leaks no worker and no thread.
        def blocked_worker_is_released_on_cancel(subject)
          probe!
          gate = ::Thread::Queue.new
          transport = BlockingTransport.new(gate: gate)
          pool = subject.executor
          source = ::Dexpace::Cancellation.source
          poster = dispatch(transport, pool, source)
          begin
            check_release(transport, source)
          ensure
            gate << :free
            poster.join(BLOCKED_WORKER_BOUND)
            pool.close
          end
        end

        # The bounded wait ASYNC-3 names, observed through the poster rather than slept on.
        #
        # BOTH pops carry the bound, and the ENTRY one is the load-bearing addition. An executor
        # that REFUSES the post -- ASYNC-2's saturated queue, or a closed pool -- pushes nothing
        # onto `entered` and the poster rescues the refusal, so an unbounded pop there parks the
        # whole run for ever. An expired entry pop is :vacuous and not :failed: with no unit
        # started there is no "blocking task on a worker thread", which is the antecedent
        # ASYNC-3's own sentence opens with, and a MUST-level vacuity blocks the report anyway.
        # 8a fixed the rule for this gem with `await_closed_connection`'s `timeout:` -- every wait
        # carries a bound, so a non-conforming subject fails the assertion instead of hanging.
        # @return [nil]
        def check_release(transport, source)
          if transport.entered.pop(timeout: BLOCKED_WORKER_BOUND).nil?
            raise Vacuous, "the executor did not start the posted unit within " \
                           "#{BLOCKED_WORKER_BOUND}s, so no worker was ever blocked to cancel"
          end

          source.cancel(:interrupt_requested)
          freed = transport.released.pop(timeout: BLOCKED_WORKER_BOUND)

          Check.that(!freed.nil?,
                     "a worker blocked in an uninterruptible call was not released after cancel",
                     expected: "released within #{BLOCKED_WORKER_BOUND}s of cancel",
                     actual: "still blocked", ids: ["ASYNC-3"],)
        end

        def probe!
          if defined?(::Dexpace::Transport) && ::Dexpace::Transport.respond_to?(:async_over)
            return nil
          end

          raise Vacuous, "Dexpace::Transport.async_over is absent; phase 2 committed to it"
        end

        # @return [Thread] the poster, which the assertion's own ensure joins
        def dispatch(transport, pool, source)
          bridge = ::Dexpace::Transport.async_over(transport, executor: pool)
          ::Thread.new do
            bridge.call(:request, nil, source.token).value
          rescue ::StandardError
            nil
          end
        end

        # The blocking subject: it answers the transport seam's #call, parks on a gate with NO
        # timeout, and reports its own entry and release. It returns a closeable so the pivot's
        # orphan-close path has something to close when the cancelled caller is refused the
        # result.
        class BlockingTransport
          attr_reader :entered, :released

          def initialize(gate:)
            @gate = gate
            @entered = ::Thread::Queue.new
            @released = ::Thread::Queue.new
          end

          # The transport seam's `#call`, parked on a gate with no timeout of its own.
          # @return [Closeable] what the pivot closes when the cancelled caller is refused
          def call(_request, _options, _cancellation)
            @entered << :in
            @gate.pop
            Closeable.new
          ensure
            @released << :out
          end

          # What the pivot closes when nobody is left to take the result.
          class Closeable
            # @return [nil]
            def close = nil
          end
        end
        private_constant :BlockingTransport

        ROWS = [
          ["ASYNC-17", "a resource-free implementation inherits a no-op close",
           :default_close_is_a_no_op,],
          ["SEAM-25", "closing an owned executor emits exactly one shutdown event",
           :one_shutdown_event,],
          ["ASYNC-3", "cancelling a task blocked on a worker releases the worker within a bound",
           :blocked_worker_is_released_on_cancel,],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Shutdown
    end
  end
end
