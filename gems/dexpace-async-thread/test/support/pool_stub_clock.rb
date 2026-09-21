# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Drives the shutdown budget's spent branch with no real waiting (design open question 5):
# answers only #monotonic, the one method the pool's own arithmetic uses. Clock#now and #sleep
# have no consumer in the pool, so both raise -- a later edit that reaches for either fails
# loudly rather than silently using a stub never designed for it. Not phase 5a's FakeClock,
# which lives in core's test/ and is unreachable from this gem's test_helper (core's fakes stay
# in core; 8a's decline). Named for its gem, as every top-level double here is.
class PoolStubClock
  def initialize(start: 0.0)
    @monotonic = start
    @mutex = ::Thread::Mutex.new
  end

  def monotonic
    @mutex.synchronize { @monotonic }
  end

  def advance(seconds)
    @mutex.synchronize { @monotonic += seconds }
    nil
  end

  def now
    raise ::NotImplementedError, "PoolStubClock answers only #monotonic"
  end

  def sleep(*)
    raise ::NotImplementedError, "PoolStubClock answers only #monotonic"
  end
end
