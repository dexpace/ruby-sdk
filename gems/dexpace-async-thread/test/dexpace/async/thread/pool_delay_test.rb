# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/pool_probe_scheduler"
require_relative "../../../support/pool_recording_sink"
require "dexpace/async/thread"

# ASYNC-18's four clauses, R11's fifth (a closed pool fails the future), the timer's own
# lifecycle (P8-25) and its containment (P8-22 extended to the timer thread). Every wait that
# could hang carries a deadline through Future#value(deadline:), so a timer that never fires fails
# the test instead of parking the suite; every "elapsed" assertion has a lower bound and no upper
# one, because an upper bound is what makes a timing test flaky on a loaded machine.
class PoolDelayTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool

  def teardown
    @pool&.close
    super
  end

  def build(**)
    @pool = Pool.build(size: 1, **)
  end

  def timer_threads
    ::Thread.list.select { |t| t.name&.end_with?(" timer") }
  end

  def timer_entries(pool)
    pool.instance_variable_get(:@timer).instance_variable_get(:@entries)
  end

  def within(seconds) = Dexpace::Clock.deadline_in(seconds)

  # The timer thread names itself INSIDE its body, so a name read straight after #delay can miss
  # it; wait for the name on a deadline-bounded condition, never a sleep.
  def await_timer_thread
    deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 5.0
    ::Thread.pass until !timer_threads.empty? ||
                        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) > deadline
    timer_threads
  end

  # ASYNC-18's four clauses.
  class ClausesTest < PoolDelayTest
    test "a negative delay raises Dexpace::InvalidArgumentError before any timer thread exists" do
      pool = build
      before = ::Thread.list.size

      error = assert_raises(Dexpace::InvalidArgumentError) { pool.delay(-1) }

      assert_match(/duration must not be negative/, error.message)
      assert_equal(before, ::Thread.list.size)
      assert_empty(timer_threads)
    end

    test "a non-Numeric delay raises Dexpace::InvalidArgumentError naming the class" do
      pool = build

      error = assert_raises(Dexpace::InvalidArgumentError) { pool.delay("0.5") }

      assert_match(/duration must be Numeric, got String/, error.message)
      error = assert_raises(Dexpace::InvalidArgumentError) { pool.delay(nil) }

      assert_match(/got NilClass/, error.message)
    end

    # Review round 1's R1-1. A NaN answers false to negative? AND zero?, so the design's two checks
    # let it through to the timer, whose list is ordered by deadline: the NaN entry made next_wait
    # raise inside the timer thread's net (one diagnostic, the thread gone for good with its slot
    # still set, the future never settled) and every later #delay on the pool raised a bare
    # ArgumentError from the sort. Refused before anything is scheduled, and the pool stays usable.
    test "P8-77: a NaN duration is refused before any timer exists; a later delay still fires" do
      pool = build
      before = ::Thread.list.size

      error = assert_raises(Dexpace::InvalidArgumentError) { pool.delay(Float::NAN) }

      assert_match(/\Aduration must be finite, got NaN\z/, error.message)
      assert_equal(before, ::Thread.list.size)
      assert_empty(timer_entries(pool))
      assert_equal(true, pool.delay(0.01).value(deadline: within(5))) # rubocop:disable Minitest/AssertTruthy -- the settled VALUE
    end

    # finite? is Numeric's own protocol and covers NaN and both infinities in one call, so an
    # infinite duration is refused with NaN rather than admitted as an entry that never fires;
    # the negative one is caught by the negative check first, whichever the caller meant.
    test "P8-77: an infinite duration is refused as non-finite; a negative infinity as negative" do
      pool = build

      error = assert_raises(Dexpace::InvalidArgumentError) { pool.delay(Float::INFINITY) }

      assert_match(/\Aduration must be finite, got Infinity\z/, error.message)
      error = assert_raises(Dexpace::InvalidArgumentError) { pool.delay(-Float::INFINITY) }

      assert_match(/\Aduration must not be negative, got -Infinity\z/, error.message)
      assert_empty(timer_threads)
      assert_empty(timer_entries(pool))
    end

    # A Complex is a Numeric with no order and no #negative?: the design's check raised a bare
    # NoMethodError from a method whose contract is InvalidArgumentError.
    test "P8-77: a Complex duration raises InvalidArgumentError, never NoMethodError" do
      pool = build

      error = assert_raises(Dexpace::InvalidArgumentError) { pool.delay(Complex(1, 1)) }

      assert_match(/\Aduration must be a real number, got \(1\+1i\)\z/, error.message)
      assert_empty(timer_threads)
    end

    test "a zero delay settles with true before #delay returns and spawns no timer thread" do
      pool = build

      future = pool.delay(0)

      assert_predicate(future, :settled?)
      assert_equal(true, future.value) # rubocop:disable Minitest/AssertTruthy -- the settled VALUE is the boolean true, matching Async.delay (P5-52)
      assert_empty(timer_threads)
      assert_empty(timer_entries(pool))
    end

    test "a positive delay settles with true after the interval, on one named timer thread" do
      pool = build(name: "delaying")
      started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

      future = pool.delay(0.05)
      value = future.value(deadline: within(5))
      elapsed = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started

      assert_equal(true, value) # rubocop:disable Minitest/AssertTruthy -- the settled VALUE is the boolean true
      assert_operator(elapsed, :>=, 0.05)
      assert_equal(["delaying timer"], timer_threads.map(&:name))
      assert_empty(timer_entries(pool))
    end

    test "a Rational and an Integer duration are Numeric and schedule" do
      pool = build

      assert_equal(true, pool.delay(Rational(1, 100)).value(deadline: within(5))) # rubocop:disable Minitest/AssertTruthy -- the settled VALUE
      assert_equal(true, pool.delay(0).value) # rubocop:disable Minitest/AssertTruthy -- the settled VALUE
    end

    test "three concurrent delays fire in deadline order on one shared timer thread" do
      pool = build
      order = ::Thread::Queue.new

      pool.delay(0.10).on_settle { order << :b }
      pool.delay(0.05).on_settle { order << :a }
      pool.delay(0.15).on_settle { order << :c }

      # Three blocking pops, no sleep: the queue IS the wait, and the order they arrive in is the
      # assertion; a bound on each pop turns a timer that never fires into a failure, not a hang.
      assert_equal(%i[a b c], Array.new(3) { order.pop(timeout: 5) })
      assert_equal(1, timer_threads.size)
    end

    test "#on_settle on a delay future runs on the timer thread, not on a pool worker" do
      pool = build(name: "where")
      seen = ::Thread::Queue.new

      pool.delay(0.01).on_settle { seen << ::Thread.current.name }

      assert_equal("where timer", seen.pop(timeout: 5))
    end
  end

  # ASYNC-18's last clause: a cancelled delay holds no scheduler thread.
  class CancelTest < PoolDelayTest
    # A cancelled future stays cancelled whether or not the entry fires late (a late
    # fulfil(true) loses the race and returns false), so the future alone proves nothing about
    # the timer: the observable is the timer's entry list, which the cancel hook must empty so no
    # scheduler thread is held for a delay nobody wants (ASYNC-18's last clause).
    test "cancelling a future removes the timer's entry at once and the future stays cancelled" do
      pool = build
      future = pool.delay(10.0)

      assert_equal(1, timer_entries(pool).size)

      future.cancel(:no_longer_needed)

      assert_empty(timer_entries(pool))
      assert_predicate(future, :cancelled?)
      error = assert_raises(Dexpace::CancelledError) { future.value }

      assert_equal(:no_longer_needed, error.reason)
    end

    test "a cancelled entry never fires: a later delay on the same timer passes its deadline" do
      pool = build
      fired = ::Thread::Queue.new
      cancelled = pool.delay(0.05)
      cancelled.on_settle { |settlement| fired << settlement.cancelled }
      cancelled.cancel(:gone)
      # Waiting past the cancelled entry's deadline WITHOUT a sleep: a later delay on the same
      # timer, awaited, proves the one timer thread ran through that deadline.
      pool.delay(0.10).value(deadline: within(5))

      assert_equal(true, fired.pop(timeout: 1)) # rubocop:disable Minitest/AssertTruthy -- Settlement#cancelled, a boolean
      assert_nil(fired.pop(timeout: 0.05), "the removed entry settled the future a second time")
      assert_predicate(cancelled, :cancelled?)
    end

    test "cancelling one of several delays leaves the others to fire in order" do
      pool = build
      order = ::Thread::Queue.new
      pool.delay(0.05).on_settle { order << :first }
      middle = pool.delay(0.08)
      middle.on_settle { order << :middle }
      pool.delay(0.11).on_settle { order << :last }
      middle.cancel(:skip)

      assert_equal(:middle, order.pop(timeout: 1)) # the cancellation settles it at once
      assert_equal(%i[first last], Array.new(2) { order.pop(timeout: 5) })
    end
  end

  # The timer under #close, and R11's fifth clause.
  class LifecycleTest < PoolDelayTest
    # ASYNC-2, not ASYNC-18: "worker-pool rejection (a saturated/shut-down executor)" MUST arrive
    # through the failure channel, "never thrown synchronously from the method that promised a
    # future". #delay promises one, so a closed pool is a failed future and not a raise (R11's
    # fifth clause). The negative-duration test above is the contrast: that one IS a raise.
    test "delay on a closed pool returns a failed future rather than raising" do
      pool = build(name: "shut")
      pool.close

      future = pool.delay(0.05) # a raise here is the failure this test exists to catch

      assert_predicate(future, :settled?)
      error = assert_raises(Dexpace::ClosedError) { future.value }

      assert_equal("shut is closed", error.message)
      assert_empty(timer_threads)
    end

    test "close fails every outstanding delay with ClosedError, and stops the timer thread" do
      pool = build
      futures = [pool.delay(10.0), pool.delay(20.0)]

      assert_equal(1, await_timer_thread.size)

      pool.close

      futures.each do |future|
        assert_predicate(future, :settled?)
        assert_raises(Dexpace::ClosedError) { future.value(deadline: within(2)) }
      end
      assert_empty(timer_threads)
      assert_empty(timer_entries(pool))
    end

    test "a pool that never scheduled a positive delay has no timer thread to stop" do
      pool = build
      pool.delay(0)
      pool.close

      assert_empty(timer_threads)
    end

    # The handler is provably running ON the timer thread before close is called (an `entered`
    # queue, not a guess): a close that raced the entry would fail it through on_shutdown on the
    # closing thread instead, where a stuck handler is the caller's own doing, as on any
    # Completer#fail.
    test "the timer join is inside close's budget: a stuck on_settle handler cannot hang #close" do
      pool = build(shutdown_timeout: 0.5)
      entered = ::Thread::Queue.new
      release = ::Thread::Queue.new
      pool.delay(0.01).on_settle do
        entered << ::Thread.current.name
        release.pop # parks the timer thread inside a callback
      end

      assert_equal("#{pool.name} timer", entered.pop(timeout: 5))

      started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      closer = ::Thread.new { pool.close }

      assert(closer.join(5), "close waited past its budget on the timer thread")
      assert_operator(::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started, :>=, 0.5)
      assert_predicate(pool, :closed?)
      release << :go
      timer_threads.each { |t| t.join(2) }
    end

    test "an entry close fails settles on the closing thread; a schedule after stop is refused" do
      pool = build
      seen = ::Thread::Queue.new
      pool.delay(10.0).on_settle { seen << ::Thread.current }
      pool.close

      assert_same(::Thread.current, seen.pop(timeout: 1))

      # The backstop for a #delay that read the latch open a moment before #close ran: the timer
      # refuses the entry through its own on_shutdown and spawns nothing.
      timer = pool.instance_variable_get(:@timer)
      failed = ::Thread::Queue.new
      timer.schedule(10.0, on_fire: -> { failed << :fired }, on_shutdown: -> { failed << :refused })

      assert_equal(:refused, failed.pop(timeout: 1))
      assert_empty(timer_threads)
    end

    # The README's grace-period idiom -- a delay whose handler closes the pool -- runs #close ON
    # the timer thread. Thread#join on the current thread raises ThreadError, so a stop that joined
    # unconditionally escaped #close with the latch already flipped, no event emitted and every
    # other outstanding delay stranded (review round 0's R0-2); the stop skips the self-join and
    # the thread exits by itself once the handler returns (P8-76). The rescue is what turns the
    # ThreadError into a reported value rather than a diagnostic swallowed by the timer's net.
    test "P8-76: close from a delay's on_settle handler returns nil, emits once, fails the rest" do
      sink = PoolRecordingSink.new
      pool = build(name: "grace", logger: Dexpace::Instrumentation::Logger.build(sink: sink))
      other = pool.delay(10.0)
      outcome = ::Thread::Queue.new
      pool.delay(0.01).on_settle do
        outcome << [::Thread.current.name, pool.close]
      rescue ::StandardError => error
        outcome << [::Thread.current.name, error]
      end

      assert_equal(["grace timer", nil], outcome.pop(timeout: 5))
      assert_predicate(pool, :closed?)
      error = assert_raises(Dexpace::ClosedError) { other.value(deadline: within(2)) }

      assert_equal("grace is closed", error.message)
      assert_equal(1, sink.events_named(Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN).size)
      timer_threads.each { |t| t.join(2) }

      assert_empty(timer_threads)
    end
  end

  # The timer's lock scope, asserted rather than argued: its mutex is held across a list mutation
  # and never across its queue wait (design, "Thread-safety proof obligations").
  class LockScopeTest < PoolDelayTest
    # The timer thread is provably parked in its wait (status "sleep", on a bounded condition)
    # before a cancel and then a close are issued from helper threads with bounded joins. A mutex
    # held across that wait -- the plan's Task 7 Step 8 mutation -- blocks both until the parked
    # pop times out, and both joins answer nil in 2 s: red by two reported failures and a leaked
    # thread count, where every other test in this file is red by a hang under the same mutant
    # (teardown's close parks on the mutex). The close goes through a helper for that reason:
    # Closeable's latch flips before #release runs, so teardown's own close is a no-op either way.
    test "a cancel and a close issued while the timer is parked return: the wait holds no mutex" do
      pool = build
      future = pool.delay(10.0)
      timer = await_timer_thread.first
      deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 5.0
      ::Thread.pass until timer.status == "sleep" ||
                          ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) > deadline

      assert_equal("sleep", timer.status, "the timer thread never parked")
      canceller = ::Thread.new { future.cancel(:no_longer_needed) }
      cancel_returned = canceller.join(2)
      closer = ::Thread.new { pool.close }
      close_returned = closer.join(2)

      refute_nil(cancel_returned, "the cancel blocked on the timer's mutex while it was parked")
      refute_nil(close_returned, "close blocked on the timer's mutex while it was parked")
      assert_predicate(future, :cancelled?)
      assert_empty(timer_entries(pool))
      assert_empty(timer_threads)
    end
  end

  # P8-22 extended to the timer thread.
  class ContainmentTest < PoolDelayTest
    # Hooks.notify RE-RAISES a raising #on_settle handler out of Completer#fulfil, on the timer
    # thread; without the timer's own net one caller's handler would kill it, strand every later
    # delay and turn the next #close into a raise through the join.
    test "P8-22: a raising on_settle handler on a delay future is reported; the timer survives" do
      sink = PoolRecordingSink.new
      pool = build(logger: Dexpace::Instrumentation::Logger.build(sink: sink))
      pool.delay(0.01).on_settle { raise "handler boom" }
      later = pool.delay(0.03)

      assert_equal(true, later.value(deadline: within(5))) # rubocop:disable Minitest/AssertTruthy -- the settled VALUE
      hook = sink.events_named(Dexpace::Instrumentation::Events::INSTRUMENTATION_HOOK)

      assert_equal(1, hook.size)
      assert_includes(hook.first.payload.to_s, "handler boom")
      assert_nil(pool.close)
    end

    test "P8-22: a raising on_shutdown settlement handler is reported and #close still returns" do
      sink = PoolRecordingSink.new
      pool = build(logger: Dexpace::Instrumentation::Logger.build(sink: sink))
      pool.delay(10.0).on_settle { raise "shutdown handler boom" }

      assert_nil(pool.close)
      hook = sink.events_named(Dexpace::Instrumentation::Events::INSTRUMENTATION_HOOK)

      assert_equal(1, hook.size)
      assert_includes(hook.first.payload.to_s, "shutdown handler boom")
    end
  end

  # Liveness under a registered Fiber.scheduler.
  class SchedulerTest < PoolDelayTest
    # A liveness check under a registered Fiber.scheduler: two fibers of one thread, one awaiting
    # a delay and one cancelling another, both settle and no ThreadError surfaces. It is NOT the
    # proof of the timer's lock scope the plan wrote it as: the wait runs on the TIMER thread,
    # which has no scheduler, so a mutex held across it never raises the per-fiber ThreadError the
    # plan predicted -- it deadlocks instead, cross-thread, when #close's stop parks on the mutex
    # the parked timer holds (the checklist's guard 29 has the thread dump), and this test is red
    # by that hang through teardown's close. LockScopeTest below is the guard that fails instead.
    test "two fibers of one thread call #delay and #cancel under a probe scheduler; both settle" do
      pool = build
      scheduler = PoolProbeScheduler.new
      outcomes = ::Thread::Queue.new

      ::Thread.new do
        ::Fiber.set_scheduler(scheduler)
        ::Fiber.schedule do
          future = pool.delay(0.05)
          # A DEADLINED wait: the probe scheduler parks an untimed gate pop with a nil deadline and
          # its run loop breaks out before the timer's cross-thread unblock arrives.
          future.value(deadline: Dexpace::Clock.deadline_in(2))
          outcomes << :first_settled
        end
        ::Fiber.schedule do
          future = pool.delay(0.20)
          future.cancel(:no_longer_needed)
          outcomes << :second_cancelled
        end
        ::Fiber.scheduler.close
      end.join

      assert_equal(%i[first_settled second_cancelled], Array.new(2) do
        outcomes.pop(timeout: 5)
      end.sort,)
      assert_operator(scheduler.block_count, :>=, 1)
    end
  end
end
