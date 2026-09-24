# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../failure"
require_relative "../runner"
require_relative "../shared_instance"

module Dexpace
  module Conformance
    module InvariantSuite
      # Group 8, XCUT-11's two clauses: the structural predicate plus sixteen threads, and the
      # two-fibers-on-one-thread shape 8b handed forward. A private_constant of InvariantSuite.
      module Sharing
        extend self

        # XCUT-11's own conformance shape: "invoke one shared instance from MANY threads".
        THREADS = 16
        # Two fibers on ONE thread: the only shape a per-fiber mutex deadlock is visible in.
        FIBERS = 2
        # Enough resumes for both fibers to finish, and a bound if one of them never does.
        RESUMES = 4
        # Seconds every concurrent call has, IN TOTAL, to return. A shared instance that holds a
        # lock across the call returns on one thread and never on the other fifteen, so the join
        # is bounded and an expired one is the failure. 8a fixed the rule for this gem with
        # `await_closed_connection`'s `timeout:`: a non-conforming subject fails the assertion
        # instead of hanging the run.
        CALL_BOUND = 1.0

        # XCUT-11, clause 1: the structural predicate over every shared instance the DRIVER
        # declares (design R8, P9-9), plus the requirement's own conformance shape -- "invoke one
        # shared step instance from many threads with distinct requests and assert no cross-talk".
        # The assertion is on the collected set, never on timing.
        def shared_instances_are_concurrent_safe(subject)
          audit_declared(subject)
          step = subject.seam
          SharedInstance.audit(step, mutable: subject.mutable)
          seen = drive_threads(step)

          Check.that(seen == expected_requests,
                     "a shared step crossed one call's request into another's",
                     expected: THREADS, actual: seen.uniq.size, ids: ["XCUT-11"],)
        end

        # XCUT-11, clause 2: TWO FIBERS ON ONE THREAD, which 8b handed forward as "the only shape
        # that proves a per-fiber mutex is not held across a suspension point". Thread::Mutex
        # ownership in Ruby is per-FIBER and non-reentrant, so a lock held across a yield
        # deadlocks two fibers of one thread and sixteen threads cannot see it.
        #
        # The deadlock must be CAUGHT, not merely outlived: the second fiber's resume raises
        # ThreadError ("deadlock; lock already owned by another fiber belonging to the same
        # thread"), and a ThreadError escaping the body would reach Runner's bare rescue and be
        # reported :error -- the status for "this assertion is broken", not for "the subject is
        # non-conformant". So the resume loop converts it into a Failure carrying the message.
        def shared_instances_are_fiber_safe(subject)
          step = subject.seam
          seen = [] #: Array[untyped]
          fibers = ::Array.new(FIBERS) { |index| fiber(step, index, seen) }
          RESUMES.times { fibers.each { |one| resume(one) } }

          Check.that(seen.size == FIBERS * 2,
                     "two fibers on one thread did not both complete; a lock is held across a " \
                     "suspension point",
                     expected: FIBERS * 2, actual: seen.size, ids: ["XCUT-11"],)
        end

        # Every shared instance the driver declared, put through R8's predicate.
        # @return [void]
        def audit_declared(subject)
          subject.shared_instances.each do |(label, object, declared)|
            SharedInstance.audit(object, mutable: declared)
          rescue Failure => error
            raise Failure.new("#{label}: #{error.message}", expected: error.expected,
                                                            actual: error.actual,
                                                            requirement_ids: ["XCUT-11"],)
          end
        end

        # @return [Array<String>] the requests the one shared step saw, sorted
        def drive_threads(step)
          results = ::Thread::Queue.new
          callers = ::Array.new(THREADS) do |index|
            ::Thread.new { results << step.call("request-#{index}") }
          end
          check_all_returned(callers)
          collected = [] #: Array[untyped]
          collected << results.pop until results.empty?
          collected.map(&:first).sort
        end

        # The bounded half of `drive_threads`, kept apart so the assertion reads as one thought.
        # The whole set shares ONE budget, so sixteen stuck callers cost one bound and not sixteen.
        # @return [nil]
        def check_all_returned(callers)
          deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + CALL_BOUND
          stuck = callers.count do |one|
            left = deadline - ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
            one.join(left.positive? ? left : 0).nil?
          end

          Check.that(stuck.zero?,
                     "a shared instance did not return on every thread; it serialises or holds " \
                     "a lock across the call",
                     expected: "#{THREADS} concurrent calls return",
                     actual: "#{stuck} still running", ids: ["XCUT-11"],)
        end

        # @return [Array<String>] what a step with no cross-talk must have seen
        def expected_requests
          ::Array.new(THREADS) { |index| "request-#{index}" }.sort
        end

        # @return [Fiber] one of the two, calling the step on either side of a yield
        def fiber(step, index, seen)
          ::Fiber.new do
            seen << step.call("fiber-#{index}")
            ::Fiber.yield
            seen << step.call("fiber-#{index}-again")
          end
        end

        # Converts Ruby's own deadlock report into a Failure, so the status is :failed rather
        # than :error -- which would read as a broken harness and not as a non-conformance.
        # @return [void]
        def resume(one)
          return unless one.alive?

          one.resume
        rescue ::ThreadError => error
          raise Failure.new(
            "two fibers on one thread deadlocked; a lock is held across a suspension " \
            "point: #{error.message}",
            expected: FIBERS * 2, actual: "#{error.class}: #{error.message}",
            requirement_ids: ["XCUT-11"],
          )
        end

        ROWS = [
          ["XCUT-11", "a shared component holds no per-call state and does not cross-talk",
           :shared_instances_are_concurrent_safe,],
          ["XCUT-11", "a shared component's lock is not held across a suspension point",
           :shared_instances_are_fiber_safe,],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Sharing
    end
  end
end
