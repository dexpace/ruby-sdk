# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# OBS-25's "Selecting a no-op path MUST NOT allocate per call", measured the one way that is
# insensitive to the caller: the block is driven 1000 and then 2000 times under GC.disable, and
# the per-call figure is the difference of the two deltas over 1000 -- so a fixed cost (the first
# call's method cache, an inline cache warming) cancels and only a per-iteration cost survives.
# What makes it insensitive to the CALLER is the precondition the block must meet, not the
# arithmetic: every argument the block passes must be one that cannot allocate -- a frozen
# constant, a Symbol, an Integer, nil -- because an inline String or Hash literal at the call
# site allocates per iteration whether or not the callee does (5b's R8, 5c's testing strategy).
# The repository's `# frozen_string_literal: true` is a rule, not this measurement's
# precondition; a copy into another gem (phase 8a's dexpace-conformance) must keep the
# argument discipline and may not rely on the comment.
#
# The figure returned is the one two consecutive measurements AGREE on (phase 5b's review round
# 2, R2-4). On the 3.2.11 floor a one-time cost of 7 or 28 objects -- interpreter-internal
# objects that `GC.stat(:total_allocated_objects)` counts -- can land inside a measured block
# after the 100-iteration warm-up, once per process and dependent on which test ran first, so a
# single measurement came back NEGATIVE (-0.007, -0.028) in about one whole-file run in fifteen
# and an exact `assert_in_delta(0.0, x, 0.0)` failed it; it could as easily land in the second
# block and come back positive. A one-time cost cannot appear in two consecutive measurements,
# while a real per-call cost -- an Integer number of objects, or a fractional one from a
# collection growing every Nth call -- is exactly what every clean measurement returns. So the
# measurement is repeated until two in a row agree (at most ATTEMPTS, then the last figure is
# returned and the assertion reports it), which keeps the assertion exact rather than clamping a
# negative figure to zero or widening the delta, either of which would also hide a real
# fractional cost.
module AllocationDelta
  # How many measurements may disagree before the helper gives up and reports the last.
  ATTEMPTS = 5

  # @return [Float] objects allocated per call of the block, to one thousandth: the figure two
  #   consecutive measurements agree on
  def allocations_per_call(&)
    ::GC.disable
    previous = measure_allocations_per_call(&)
    ATTEMPTS.times do
      current = measure_allocations_per_call(&)
      return current if current == previous

      previous = current
    end
    previous
  ensure
    ::GC.enable
  end

  private

  # One two-loop measurement: a warm-up, then 1000 and 2000 iterations, the difference of the
  # two deltas over 1000.
  def measure_allocations_per_call(&)
    100.times(&)
    first = ::GC.stat(:total_allocated_objects)
    1000.times(&)
    second = ::GC.stat(:total_allocated_objects)
    2000.times(&)
    third = ::GC.stat(:total_allocated_objects)
    ((third - second) - (second - first)) / 1000.0
  end
end
