# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A deterministic Dexpace::_Clock (CFG-15): #now and #monotonic return values the test advances,
# and #sleep records its arguments and advances both readings without waiting. Exactly the three
# operations the seam declares, and nothing else -- a fake owes the seam what the seam declares,
# which is why CFG-18's delay is not a fourth method here (P5-10).
#
# Top level, like every double under test/support/ since phase 2; the plan namespaced it under
# Dexpace and the tree's convention won (phase 5a's checklist, "Deviations from the plan").
class FakeClock
  attr_reader :sleeps

  def initialize(now: ::Time.utc(2026, 1, 1, 0, 0, 0), monotonic: 1000.0)
    @now = now
    @monotonic = monotonic.to_f
    @sleeps = []
    @mutex = ::Thread::Mutex.new
  end

  def now
    @mutex.synchronize { @now }
  end

  def monotonic
    @mutex.synchronize { @monotonic }
  end

  # Records the call, advances the clock by the duration, and honours the token the way the real
  # clock does: a cancelled token raises through #check! rather than being ignored.
  def sleep(duration, cancellation: nil)
    raise Dexpace::InvalidArgumentError, "sleep duration must be non-negative" if duration.negative?

    @mutex.synchronize do
      @sleeps << { duration: duration, cancellation: cancellation }.freeze
      @monotonic += duration.to_f
      @now += duration.to_f
    end
    cancellation&.check!
    nil
  end

  def advance(seconds)
    @mutex.synchronize do
      @monotonic += seconds.to_f
      @now += seconds.to_f
    end
    nil
  end
end
