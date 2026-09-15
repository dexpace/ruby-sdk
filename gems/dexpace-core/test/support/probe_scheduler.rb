# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A minimal Fiber scheduler that records which hooks a blocking operation routed through. It is a
# probe, not an implementation: #block runs other ready fibers in a nested loop rather than
# suspending the calling fiber, which is the shape that stays well-behaved when the blocker is a
# Thread::Mutex.
#
# #fiber_interrupt is defined because Ruby 4.0.6 warns "Scheduler should implement #fiber_interrupt"
# without it, and the shared test case turns a warning into a failure for the test that triggered
# it. Verified on 4.0.6 that defining it silences the warning.
class ProbeScheduler
  attr_reader :hooks

  def initialize
    @hooks = []
    @ready = []
    @unblocked = {}
  end

  # The name and the boolean return are Ruby's Fiber::Scheduler interface, not a choice.
  def block(blocker, _timeout = nil) # rubocop:disable Naming/PredicateMethod -- the scheduler hook's own name
    @hooks << [:block, blocker.class.name]
    me = Fiber.current
    until @unblocked.delete(me)
      runnable = @ready.shift
      return false if runnable.nil?

      runnable.resume if runnable.alive?
    end
    true
  end

  def unblock(blocker, fiber)
    @hooks << [:unblock, blocker.class.name]
    @unblocked[fiber] = true
    @ready << fiber
  end

  def kernel_sleep(_duration = nil) = nil
  def io_wait(_io, events, _timeout) = events
  def fiber_interrupt(_fiber, _exception) = nil

  def fiber(&)
    created = Fiber.new(blocking: false, &)
    @ready << created
    created
  end

  def close
    until @ready.empty?
      runnable = @ready.shift
      runnable.resume if runnable.alive?
    end
  end
end
