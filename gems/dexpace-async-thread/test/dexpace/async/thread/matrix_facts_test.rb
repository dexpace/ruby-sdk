# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# The pool-specific interpreter facts the design (facts 2, 3, 4, 10, 11, 16, 19) and the plan
# (its facts 1, 2, 3, 5, 6, 8, 9) measured, re-run as a standing test on every Ruby in the matrix
# rather than trusted from one interpreter. The Fiber facts the diagnostic hop rests on --
# inheritance by a new ::Thread, `Fiber[:k] = nil` deleting on 3.3+ and retaining on the 3.2
# floor, `Fiber["k"]` interning from 3.4 -- are pinned per RUBY_VERSION by core's
# `tracing_matrix_facts_test.rb` and are deliberately not pinned a second time here.
#
# No file under lib/ is required: these are facts about the interpreter alone. The class is named
# for its gem: `rake test:gems` loads every gem's suite into one process, and core's
# matrix_facts_test.rb already owns the bare `MatrixFactsTest` (8a's is prefixed the same way).
class PoolMatrixFactsTest < DexpaceTestCase
  # The queue primitives the pool's submission and exit channels rest on.
  class QueueFactsTest < PoolMatrixFactsTest
    test "fact 1: a non-blocking push on a full SizedQueue raises ThreadError; timed, it is nil" do
      queue = ::Thread::SizedQueue.new(1)
      queue.push(:a)

      error = assert_raises(::ThreadError) { queue.push(:b, true) }
      assert_match(/queue full/, error.message)
      assert_nil(queue.push(:b, timeout: 0.02))
    end

    test "fact 2: a worker loop over queue.pop drains a closed queue and exits exactly once" do
      queue = ::Thread::Queue.new
      exits = ::Thread::Queue.new
      ran = ::Thread::Queue.new
      worker = ::Thread.new do
        while (job = queue.pop)
          ran << job
        end
      ensure
        exits << :worker_exited
      end
      queue << :job_a
      queue.close
      worker.join

      assert_equal(:job_a, ran.pop)
      assert_equal(:worker_exited, exits.pop)
      assert_nil(exits.pop(timeout: 0.05), "the sentinel is pushed exactly once")
    end

    test "fact 3: Queue#pop answers nil for a timeout, a closed queue and a pushed nil alike" do
      timed = ::Thread::Queue.new
      closed = ::Thread::Queue.new
      closed.close
      pushed = ::Thread::Queue.new
      pushed << nil

      assert_nil(timed.pop(timeout: 0.01))
      assert_nil(closed.pop)
      assert_nil(pushed.pop)
    end

    test "fact 4: Proc.new with no block raises ArgumentError, so #post takes an explicit &block" do
      poster = Object.new
      def poster.post = ::Proc.new

      assert_raises(::ArgumentError) { poster.post }
    end

    test "fact 5: push on a closed queue raises ClosedQueueError, never a ThreadError" do
      queue = ::Thread::SizedQueue.new(1)
      queue.close

      error = assert_raises(::ClosedQueueError) { queue.push(:late, true) }
      assert_kind_of(::StandardError, error)
      refute_kind_of(::ThreadError, error)
    end

    test "fact 6: Queue#pop(timeout: nil) blocks indefinitely and wakes with nil on close" do
      queue = ::Thread::Queue.new
      result = :unset
      entered = ::Thread::Queue.new
      worker = ::Thread.new do
        entered << :about_to_block
        result = queue.pop(timeout: nil)
      end
      entered.pop
      # Wait for the BLOCKED state on a condition with a deadline, never on a sleep.
      deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 2.0
      ::Thread.pass until worker.status == "sleep" ||
                          ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) > deadline

      assert_equal("sleep", worker.status)

      queue.close
      worker.join

      assert_nil(result)
    end

    test "fact 7: SizedQueue.new(0) and .new(-1) both refuse to construct" do
      assert_raises(::ArgumentError) { ::Thread::SizedQueue.new(0) }
      assert_raises(::ArgumentError) { ::Thread::SizedQueue.new(-1) }
    end
  end

  # The thread facts the worker net, the naming and the timer rest on.
  class ThreadFactsTest < PoolMatrixFactsTest
    test "fact 8: a frozen Data value crosses a thread boundary with a callable member intact" do
      job_class = ::Data.define(:snapshot, :block)
      job = job_class.new(snapshot: { a: 1 }.freeze, block: -> { :ran })

      assert_predicate(job, :frozen?)
      assert_predicate(job.snapshot, :frozen?)
      assert_equal(:ran, ::Thread.new { job.block.call }.value)
    end

    test "fact 9: a thread that rescues ::Exception survives the whole fatal family and exit" do
      swallowed = ::Thread::Queue.new
      tasks = ::Thread::Queue.new
      worker = ::Thread.new do
        ::Thread.current.report_on_exception = false
        while (task = tasks.pop)
          begin
            task.call
          rescue ::Exception => error # rubocop:disable Lint/RescueException -- the fact under test
            swallowed << error.class
          end
        end
      end
      tasks << -> { exit(3) }
      tasks << -> { raise ::NoMemoryError }
      tasks << -> { raise ::Interrupt }
      tasks << -> { raise ::NotImplementedError }
      tasks.close
      worker.join

      assert_equal([::SystemExit, ::NoMemoryError, ::Interrupt, ::NotImplementedError],
                   Array.new(4) { swallowed.pop },)
    end

    test "fact 10: a thread named inside its own body reads back by name from Thread.list" do
      named = ::Thread::Queue.new
      release = ::Thread::Queue.new
      thread = ::Thread.new do
        ::Thread.current.name = "matrix-facts probe"
        named << :named
        release.pop
      end
      named.pop

      assert_includes(::Thread.list.map(&:name), "matrix-facts probe")

      release << :go
      thread.join
    end

    test "fact 11: a worker sees Fiber.scheduler as nil whatever the caller's thread installed" do
      scheduler_seen = ::Thread.new { ::Fiber.scheduler }.value

      assert_nil(scheduler_seen)
    end

    test "fact 12: report_on_exception defaults to true: a dying worker prints past every gate" do
      assert_predicate(::Thread, :report_on_exception)
    end
  end
end
