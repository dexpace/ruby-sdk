# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The minimal Fiber::Scheduler CFG-18's suite needs, and nothing else: a fiber that blocks on a
# Thread::Queue#pop(timeout:) is PARKED with its deadline and the carrier thread is free, which is
# the only observation that tests "WITHOUT blocking a thread" rather than that a delay delays.
#
# Not phase 2's ProbeScheduler, and not a replacement for it: that double records which hooks a
# blocking operation routed through and runs other ready fibers in a nested loop rather than
# suspending the caller, which is the shape that stays well-behaved when the blocker is a
# Thread::Mutex -- and its #kernel_sleep is a no-op, so it cannot drive a timed wait. One double
# per file; phase 2's suite is untouched (phase 5a's checklist, "Deviations from the plan").
#
# A hook must NEVER sleep on the carrier thread: #block and #kernel_sleep are called from inside a
# non-blocking fiber, and Kernel.sleep there re-enters #kernel_sleep, which re-enters Kernel.sleep,
# until SystemStackError. Both hooks therefore park the current fiber with a deadline and yield;
# the only real sleep in this file is in #run_loop, which runs on the carrier thread's root fiber
# with nothing non-blocking mounted. #close is what the interpreter calls when the scheduler's
# thread ends, so a suite drives the loop by joining that thread.
#
# #fiber_interrupt is defined because Ruby 4.0.6 warns "Scheduler should implement
# #fiber_interrupt" without it, and the shared test case turns a warning into a failure.
class ParkingScheduler
  attr_reader :block_count, :unblock_count, :kernel_sleep_count

  def initialize
    @block_count = 0
    @unblock_count = 0
    @kernel_sleep_count = 0
    @waiting = {}
    @ready = []
    @mutex = ::Thread::Mutex.new
  end

  # The name and the boolean return are Ruby's Fiber::Scheduler interface, not a choice.
  def block(_blocker, timeout = nil) # rubocop:disable Naming/PredicateMethod -- the scheduler hook's own name
    @block_count += 1
    park(timeout)
    true
  end

  # Called when a queue the parked fiber waits on is pushed to -- possibly from another thread,
  # so the bookkeeping takes the mutex.
  def unblock(_blocker, fiber)
    @mutex.synchronize do
      @unblock_count += 1
      @waiting.delete(fiber)
      @ready << fiber
    end
  end

  def kernel_sleep(duration = nil) # rubocop:disable Naming/PredicateMethod -- the scheduler hook's own name
    @kernel_sleep_count += 1
    park(duration)
    true
  end

  def io_wait(_io, events, _timeout) = events
  def fiber_interrupt(_fiber, _exception) = nil

  def fiber(&)
    created = ::Fiber.new(blocking: false, &)
    created.resume
    created
  end

  def close
    run_loop
  end

  private

  # The mutex is held across the bookkeeping write and never across Fiber.yield: Thread::Mutex
  # ownership is per-fiber, so a lock held across a yield is a lock the resuming fiber cannot take.
  def park(timeout)
    @mutex.synchronize { @waiting[::Fiber.current] = timeout ? monotonic + timeout : nil }
    ::Fiber.yield
  end

  def monotonic
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end

  def run_loop
    until @waiting.empty? && @ready.empty?
      resumable = take_resumable
      if resumable.empty?
        break unless sleep_until_nearest?

        next
      end

      resumable.each { |fiber| fiber.resume if fiber.alive? }
    end
  end

  # The fibers a push woke, plus the parked ones whose deadline has passed.
  def take_resumable
    @mutex.synchronize do
      taken = @ready
      @ready = []
      expired = @waiting.select { |_fiber, at| at && at <= monotonic }.keys
      expired.each { |fiber| @waiting.delete(fiber) }
      taken + expired
    end
  end

  # False when every remaining fiber waits forever and there is nothing left to drive.
  def sleep_until_nearest?
    nearest = @mutex.synchronize { @waiting.values.compact.min }
    return false if nearest.nil?

    ::Kernel.sleep([nearest - monotonic, 0.0].max)
    true
  end
end
