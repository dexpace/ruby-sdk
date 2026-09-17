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
module AllocationDelta
  # @return [Float] objects allocated per call of the block, to one thousandth
  def allocations_per_call(&)
    ::GC.disable
    100.times(&)
    first = ::GC.stat(:total_allocated_objects)
    1000.times(&)
    second = ::GC.stat(:total_allocated_objects)
    2000.times(&)
    third = ::GC.stat(:total_allocated_objects)
    ((third - second) - (second - first)) / 1000.0
  ensure
    ::GC.enable
  end
end
