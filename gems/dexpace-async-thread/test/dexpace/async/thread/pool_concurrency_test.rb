# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/pool_recording_sink"
require "dexpace/async/thread"

# XCUT-11, SEAM-12: concurrency safety asserted, not argued. Each property names what it would
# catch. No test here sleeps: every wait is a queue pop, a bounded join or a drained close.
class PoolConcurrencyTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool

  def teardown
    @pool&.close
    super
  end

  # Drains a queue that nothing pushes to any more: a count, not a wait for work.
  def drain(queue)
    count = 0
    count += 1 while queue.pop(timeout: 0.05)
    count
  end

  # #post and #close under contention.
  class SubmissionTest < PoolConcurrencyTest
    test "post from 16 threads: accepted + rejected == submitted, every accepted job runs once" do
      size = 2
      queue_limit = size * Pool::QUEUE_DEPTH_PER_WORKER
      @pool = Pool.build(size: size, queue_limit: queue_limit)
      submitted = size * queue_limit * 2
      ran = ::Thread::Queue.new
      accepted = 0
      rejected = 0
      mutex = ::Thread::Mutex.new

      ::Array.new(16) do
        ::Thread.new do
          (submitted / 16).times do
            @pool.post { ran << :one }
            mutex.synchronize { accepted += 1 }
          rescue Dexpace::Async::Thread::RejectedError
            mutex.synchronize { rejected += 1 }
          end
        end
      end.each(&:join)

      # Close FIRST: #close drains what is queued (ASYNC-16), so after it returns every accepted job
      # has run and the count below is a drain rather than a race against the workers.
      @pool.close

      assert_equal(accepted, drain(ran), "a lost job or a double-run")
      assert_equal(submitted, accepted + rejected)
      assert_operator(accepted, :>=, 1)
    end

    test "close from 16 threads at once: exactly one event, every call returns" do
      sink = PoolRecordingSink.new
      @pool = Pool.build(size: 2, logger: Dexpace::Instrumentation::Logger.build(sink: sink))

      results = ::Array.new(16) { ::Thread.new { @pool.close } }.map { |t| t.join(5) }

      refute_includes(results, nil, "a close call never returned -- the latch is not a real latch")
      assert_equal(1, sink.events_named(Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN).size)
    end

    # `errors` is an Array under a mutex, never a Queue popped inside an assertion message: a
    # message is evaluated eagerly, and a pop on the empty queue is a deadlock whenever the test
    # PASSES.
    test "post racing close: every call succeeds or raises ClosedError, never ::ClosedQueueError" do
      @pool = Pool.build(size: 2, queue_limit: 32)
      errors = []
      mutex = ::Thread::Mutex.new
      posting = ::Thread::Queue.new
      outcomes = Hash.new(0)
      poster = ::Thread.new do
        loop do
          @pool.post { nil }
          outcomes[:posted] += 1
          posting << :posted
        rescue Dexpace::ClosedError
          outcomes[:closed] += 1
          break
        rescue Dexpace::Async::Thread::RejectedError
          outcomes[:rejected] += 1
          next
        rescue ::StandardError => error
          mutex.synchronize { errors << error }
          break
        end
      end
      # Close only once the poster is provably in its loop -- a condition, not a sleep.
      posting.pop
      @pool.close
      poster.join(5)

      assert_empty(mutex.synchronize { errors.map(&:class) })
      assert_equal(1, outcomes[:closed], "the poster stopped on the translated ClosedError")
      assert_operator(outcomes[:posted], :>=, 1)
    end
  end

  # Re-entrant posts, thread accounting and a mixed load.
  class ReentryTest < PoolConcurrencyTest
    test "post from inside a task returns rather than deadlocking" do
      @pool = Pool.build(size: 1, queue_limit: 1)
      result = ::Thread::Queue.new

      @pool.post do
        @pool.post { nil } # the queue has room for exactly this one
        result << :accepted
      rescue Dexpace::Async::Thread::RejectedError
        result << :rejected
      end

      assert_includes(%i[accepted rejected], result.pop(timeout: 2))
    end

    test "a task posting into a full queue from a worker is rejected at once, not parked (P8-23)" do
      @pool = Pool.build(size: 1, queue_limit: 1)
      gate = ::Thread::Queue.new
      result = ::Thread::Queue.new

      @pool.post do
        @pool.post { gate.pop } # fills the one slot; only this worker could ever drain it
        @pool.post { nil } # the queue is full and the only worker is HERE
        result << :accepted
      rescue Dexpace::Async::Thread::RejectedError
        result << :rejected
      end

      assert_equal(:rejected, result.pop(timeout: 2))
      gate << :go
    end

    test "20 build-and-close cycles of a three-worker pool leave Thread.list.size unchanged" do
      before = ::Thread.list.size

      20.times do
        pool = Pool.build(size: 3)
        pool.post { nil }
        pool.delay(0.001).value(deadline: Dexpace::Clock.deadline_in(5))
        pool.close
      end

      assert_equal(before, ::Thread.list.size)
    end

    test "a hundred delays and a hundred posts interleaved from four threads all settle" do
      @pool = Pool.build(size: 2, queue_limit: 400)
      futures = ::Thread::Queue.new
      ran = ::Thread::Queue.new

      ::Array.new(4) do |t|
        ::Thread.new do
          25.times do |i|
            futures << @pool.delay(((t * 25) + i) * 0.0001)
            @pool.post { ran << :one }
          end
        end
      end.each(&:join)
      settled = Array.new(100) { futures.pop.value(deadline: Dexpace::Clock.deadline_in(5)) }
      @pool.close

      assert_equal([true] * 100, settled)
      assert_equal(100, drain(ran))
    end
  end
end
