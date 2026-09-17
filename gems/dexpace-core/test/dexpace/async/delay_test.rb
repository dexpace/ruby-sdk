# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/parking_scheduler"

# CFG-18: the scheduled non-blocking delay, scheduler-conditional (R6, P5-9, P5-10). The void
# value the future settles with is `true`, not nil: SEAM-16 makes a nil-response Settlement
# unconstructible, so "completing with an empty/void value" is spelled `true` here.
module AsyncDelayTest
  # The three clauses that hold with no scheduler at all.
  class WithoutSchedulerTest < DexpaceTestCase
    test "CFG-18: a negative delay is rejected with InvalidArgumentError, nothing scheduled" do
      assert_nil(Fiber.scheduler)
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Async.delay(-1.0) }
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Async.delay(-0.001) }
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Async.delay(nil) }
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Async.delay("1") }
    end

    test "CFG-18: a zero delay returns a future already settled, with no scheduler consulted" do
      assert_nil(Fiber.scheduler)
      future = Dexpace::Async.delay(0)

      assert_kind_of(Dexpace::Async::Future, future)
      assert_predicate(future, :settled?)
      refute_predicate(future, :cancelled?)
      assert_same(true, future.value)
      assert_same(true, Dexpace::Async.delay(0.0).value)
    end

    # P5-9: no non-blocking path exists without a scheduler, and a thread-backed delay would
    # satisfy the three MUST clauses while violating the SHOULD's headline. Raising is the only
    # option that neither lies nor degrades silently, and the message says what to do instead.
    test "CFG-18 / P5-9: a positive delay without a registered scheduler raises SeamError" do
      assert_nil(Fiber.scheduler)
      error = assert_raises(Dexpace::SeamError) { Dexpace::Async.delay(0.05) }

      assert_match(/Fiber\.set_scheduler/, error.message)
      assert_match(/CFG-18/, error.message)
      assert_match(/Dexpace::Clock#sleep/, error.message)
      assert_kind_of(Dexpace::Error, error)
    end

    test "P5-10: the delay lives on Dexpace::Async, and Clock stays at three operations" do
      assert_respond_to(Dexpace::Async, :delay)
      refute_respond_to(Dexpace::Clock::SYSTEM, :delay)
      refute_includes(Dexpace::Async.constants, :ELAPSED)
    end
  end

  # The scheduler branch. The scheduler's event loop runs in ParkingScheduler#close, which the
  # interpreter calls when the scheduler's thread ends -- so every case drives it by joining that
  # thread, never by sleeping in the main fiber, which would neither run the loop nor reach a hook.
  class WithSchedulerTest < DexpaceTestCase
    test "CFG-18: with a scheduler the delay unmounts the fiber rather than blocking a thread" do
      scheduler = ParkingScheduler.new
      future = nil
      thread = Thread.new do
        Fiber.set_scheduler(scheduler)
        future = Dexpace::Async.delay(0.01)
      end
      thread.join

      assert_predicate(future, :settled?)
      assert_same(true, future.value)
      # The only assertion that tests "WITHOUT blocking a thread" rather than that a delay delays.
      assert_equal(1, scheduler.block_count)
      assert_equal(0, scheduler.kernel_sleep_count)
    end

    test "CFG-18: the future is unsettled while the duration runs, and settles once it elapses" do
      scheduler = ParkingScheduler.new
      settled_at_return = :unset
      future = nil
      thread = Thread.new do
        Fiber.set_scheduler(scheduler)
        future = Dexpace::Async.delay(0.02)
        settled_at_return = future.settled?
      end
      thread.join

      assert_same(false, settled_at_return)
      assert_predicate(future, :settled?)
    end

    # CFG-18's fourth clause, met by the mechanism CFG-15 already uses: the cancel hook pushes to
    # the parked fiber's queue, so the scheduler thread is not held for the full duration.
    test "CFG-18: cancelling the returned future cancels the scheduled wait promptly" do
      scheduler = ParkingScheduler.new
      future = nil
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      thread = Thread.new do
        Fiber.set_scheduler(scheduler)
        future = Dexpace::Async.delay(30.0)
        future.cancel(:test_cancel)
      end
      thread.join # returns promptly: the cancel hook pushed, so the parked fiber woke
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      assert_predicate(future, :cancelled?)
      assert_operator(elapsed, :<, 5.0)
      assert_equal(0, scheduler.kernel_sleep_count)
      assert_equal(1, scheduler.unblock_count)

      error = assert_raises(Dexpace::CancelledError) { future.value }

      assert_equal(:test_cancel, error.reason)
    end

    test "CFG-18: the zero-duration branch consults no scheduler even when one is registered" do
      scheduler = ParkingScheduler.new
      future = nil
      thread = Thread.new do
        Fiber.set_scheduler(scheduler)
        future = Dexpace::Async.delay(0)
      end
      thread.join

      assert_same(true, future.value)
      assert_equal(0, scheduler.block_count)
    end
  end
end
