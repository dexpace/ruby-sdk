# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/fake_clock"

# CFG-15 (the three-operation time seam and its shared default), CFG-16 (the elapsed-time counter)
# and CFG-17 (the cancellable sleep), plus Clock.deadline_in, the helper the deadline: keyword
# phase 2 postponed names its scale with.
module ClockTest
  # CFG-15 and CFG-16.
  class SeamTest < DexpaceTestCase
    test "CFG-15: Clock::SYSTEM is a frozen shared instance exposing exactly three operations" do
      clock = Dexpace::Clock::SYSTEM

      assert_instance_of(Dexpace::Clock, clock)
      assert_predicate(clock, :frozen?)
      assert_same(clock, Dexpace::Clock::SYSTEM)
      assert_equal(%i[monotonic now sleep], Dexpace::Clock.public_instance_methods(false).sort)
    end

    test "CFG-15: #now is the wall clock, a Time close to Time.now" do
      now = Dexpace::Clock::SYSTEM.now

      assert_kind_of(Time, now)
      assert_in_delta(Time.now.to_f, now.to_f, 1.0)
    end

    # CFG-16: non-decreasing across its own readings, seconds as a Float, and measured against
    # CLOCK_MONOTONIC rather than the wall clock -- a guard that reads Time.now here runs red.
    test "CFG-16: #monotonic is a non-decreasing Float of seconds on CLOCK_MONOTONIC's scale" do
      clock = Dexpace::Clock::SYSTEM
      readings = Array.new(10_000) { clock.monotonic }

      assert_kind_of(Float, readings.first)
      assert_equal(readings, readings.sort)
      assert_in_delta(Process.clock_gettime(Process::CLOCK_MONOTONIC), clock.monotonic, 1.0)
      refute_in_delta(Time.now.to_f, clock.monotonic, 86_400.0)
    end

    test "Clock.deadline_in: a monotonic instant `duration` ahead, on the given clock's scale" do
      fake = FakeClock.new(monotonic: 100.0)

      assert_in_delta(102.5, Dexpace::Clock.deadline_in(2.5, clock: fake), 1e-9)
      assert_in_delta(100.0, Dexpace::Clock.deadline_in(0, clock: fake), 1e-9)
      assert_in_delta(Dexpace::Clock::SYSTEM.monotonic + 2.5, Dexpace::Clock.deadline_in(2.5), 0.1)
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Clock.deadline_in(-1, clock: fake) }
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Clock.deadline_in("2", clock: fake) }
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Clock.deadline_in(nil, clock: fake) }
    end

    test "CFG-15: a fake satisfies the seam exactly where the real clock does" do
      fake = FakeClock.new

      %i[now monotonic sleep].each { |operation| assert_respond_to(fake, operation) }
      assert_in_delta(2.0, Dexpace::Clock.deadline_in(2.0, clock: fake) - fake.monotonic, 1e-9)
    end
  end

  # CFG-17, clause by clause.
  class SleepTest < DexpaceTestCase
    # The guard is 5a's and not inherited: Queue#pop(timeout: -1) returns nil at once and raises
    # nothing (fact 8), so a test asserting "returns promptly" passes against a missing guard.
    test "CFG-17: a negative duration is refused with InvalidArgumentError before any wait" do
      clock = Dexpace::Clock::SYSTEM

      assert_raises(Dexpace::InvalidArgumentError) { clock.sleep(-0.5) }
      assert_raises(Dexpace::InvalidArgumentError) { clock.sleep(-1) }
      assert_raises(Dexpace::InvalidArgumentError) { clock.sleep(nil) }
      assert_raises(Dexpace::InvalidArgumentError) { clock.sleep("1") }
      assert_raises(Dexpace::InvalidArgumentError) { clock.sleep(1, cancellation: :token) }
    end

    test "CFG-17: a zero duration returns nil promptly, allocating no queue and no subscription" do
      clock = Dexpace::Clock::SYSTEM
      source = Dexpace::Cancellation.source
      start = clock.monotonic

      assert_nil(clock.sleep(0, cancellation: source.token))
      assert_nil(clock.sleep(0.0))
      assert_operator(clock.monotonic - start, :<, 0.05)
    end

    # The elapsing branch cannot be faked -- no fake clock makes a real Thread::Queue wake early --
    # so it is a short real interval with a monotonic-difference assertion and a generous upper
    # bound, the shape phase 2's own wait tests use.
    test "CFG-15 / CFG-17: a positive duration elapses in full, measured on the monotonic clock" do
      clock = Dexpace::Clock::SYSTEM
      start = clock.monotonic

      assert_nil(clock.sleep(0.05))

      elapsed = clock.monotonic - start

      assert_operator(elapsed, :>=, 0.05)
      assert_operator(elapsed, :<, 2.0)
    end

    # CFG-17's sub-millisecond clause (SHOULD): the wait honours a 2 ms request as 2 ms, not as a
    # tick of some coarser scheduler.
    test "CFG-17: sub-millisecond precision -- a 2 ms sleep does not round to zero or to a tick" do
      clock = Dexpace::Clock::SYSTEM
      start = clock.monotonic
      clock.sleep(0.002)
      elapsed = clock.monotonic - start

      assert_operator(elapsed, :>=, 0.002)
      assert_operator(elapsed, :<, 0.5)
    end

    test "CFG-17: an already-cancelled token raises CancelledError at once, carrying the reason" do
      source = Dexpace::Cancellation.source
      source.cancel("aborted")
      clock = Dexpace::Clock::SYSTEM
      start = clock.monotonic

      error = assert_raises(Dexpace::CancelledError) { clock.sleep(5.0, cancellation: source.token) }

      assert_equal("aborted", error.reason)
      assert_operator(clock.monotonic - start, :<, 1.0)
      # CFG-17's re-assertion clause: a downstream handler observes the cancelled state.
      assert_predicate(source.token, :cancelled?)
    end

    # THE discriminator against Kernel#sleep and against a pop with its timeout: a cancel from
    # another thread must wake the wait long before the duration elapses. A sleep, or a pop that
    # cannot be woken, holds this for the full 30 s -- and the suite's own shell timeout is what
    # would report that.
    test "CFG-15 / CFG-17: a cancel DURING the wait wakes it promptly and raises CancelledError" do
      source = Dexpace::Cancellation.source
      clock = Dexpace::Clock::SYSTEM
      started = Thread::Queue.new
      canceller = Thread.new do
        started.pop
        sleep(0.05)
        source.cancel(:mid_sleep)
      end

      start = clock.monotonic
      started << true
      error = assert_raises(Dexpace::CancelledError) { clock.sleep(30.0, cancellation: source.token) }
      elapsed = clock.monotonic - start
      canceller.join

      assert_equal(:mid_sleep, error.reason)
      assert_operator(elapsed, :<, 5.0)
      assert_operator(elapsed, :>=, 0.05)
      assert_predicate(source.token, :cancelled?)
    end

    # P2-14 made Subscription#detach public for exactly this: the hook lives on the caller's
    # token, which may outlive the wait by the life of a client, and a wait that returned without
    # detaching would retain one closure per sleep on that token forever.
    test "CFG-17: the cancellation hook is detached after the wait, elapsed or cancelled" do
      source = Dexpace::Cancellation.source
      clock = Dexpace::Clock::SYSTEM

      clock.sleep(0.001, cancellation: source.token)

      assert_empty(source.instance_variable_get(:@hooks))

      cancelled = Dexpace::Cancellation.source
      cancelled.cancel(:late)
      assert_raises(Dexpace::CancelledError) { clock.sleep(1.0, cancellation: cancelled.token) }

      assert_empty(cancelled.instance_variable_get(:@hooks))
    end

    test "CFG-17: Cancellation.none is accepted and never wakes the wait" do
      clock = Dexpace::Clock::SYSTEM
      start = clock.monotonic

      assert_nil(clock.sleep(0.01, cancellation: Dexpace::Cancellation.none))
      assert_operator(clock.monotonic - start, :>=, 0.01)
    end

    # §8.3, mechanised: the wait is a Thread::Queue#pop, and the whole file names none of the
    # three forbidden primitives and no Kernel#sleep.
    test "§8.3 / §10.17: the wait is a queue pop -- no Kernel#sleep, no Timeout, no Thread#raise" do
      path = File.expand_path("../../lib/dexpace/clock.rb", __dir__)
      code = File.readlines(path).grep_v(/\A\s*#/).join

      assert_match(/Thread::Queue/, code)
      assert_match(/\.pop\(timeout:/, code)
      refute_match(/Kernel\.sleep|Timeout|\.raise\(|\.kill\b/, code)
      # The one `sleep(` in the file is the seam's own definition, never a call.
      definitions = code.lines.grep(/\bsleep\(/).map(&:strip)

      assert_equal(["def sleep(duration, cancellation: nil)"], definitions)
    end
  end
end
