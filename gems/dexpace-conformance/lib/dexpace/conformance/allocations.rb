# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace/error/invalid_argument_error"

module Dexpace
  module Conformance
    # OBS-25's "Selecting a no-op path MUST NOT allocate per call", measured the one way that is
    # insensitive to the caller (5b's R8): the block is driven `iterations` and then
    # `2 * iterations` times under GC.disable, and the per-call figure is the difference of the two
    # deltas over `iterations` -- so a fixed cost (a method cache, an inline cache warming) cancels
    # and only a per-iteration cost survives. What makes it insensitive to the CALLER is the
    # precondition the block must meet, not the arithmetic: every argument the block passes must be
    # one that cannot allocate -- a frozen constant, a Symbol, an Integer, nil -- because an inline
    # String or Hash literal at the call site allocates per iteration whether or not the callee
    # does. The file's `frozen_string_literal` is a rule of this repository, not this measurement's
    # precondition.
    #
    # The figure returned is the one two consecutive measurements AGREE on -- core's own
    # `AllocationDelta` shape, which this copies rather than the single loop 8a's plan sketched.
    # On the 3.2.11 floor a one-time interpreter cost of 7 or 28 objects can land inside a measured
    # block after the warm-up, once per process, and a single measurement came back NEGATIVE about
    # one whole-file run in fifteen; an integer division of that is -1 and an exact zero assertion
    # fails on it. A one-time cost cannot appear in two consecutive measurements, while a real
    # per-call cost is exactly what every clean measurement returns, so the measurement repeats
    # until two in a row agree (at most ATTEMPTS, then the last figure is returned and the
    # assertion reports it) -- which keeps the assertion exact rather than clamping a negative
    # figure or widening the delta, either of which would also hide a real fractional cost.
    module Allocations
      extend self

      # How many measurements may disagree before the helper gives up and reports the last.
      ATTEMPTS = 5

      # The iterations run before the first measurement, so the first call's one-time costs --
      # block object creation, method dispatch caches -- do not land in the measured block.
      # Measured: `GC.stat(:total_allocated_objects)` around an empty block reports 2 and around
      # `{ nil }` 3 or 4 on the four supported interpreters, so the harness's own overhead is
      # caller-shaped and the two-loop difference is what removes it.
      WARMUP_ITERATIONS = 100
      private_constant :WARMUP_ITERATIONS

      # Objects allocated per call of the block, to one thousandth: the figure two consecutive
      # two-loop measurements agree on. `iterations:` is REQUIRED (8a's open question 5): OBS-25's
      # "MUST NOT allocate per call" is a per-iteration claim, and dividing by an unstated count is
      # not a claim about anything.
      #
      # @param iterations [Integer] the first loop's count; the second loop runs twice as many
      # @yield the call under measurement, over arguments that cannot allocate
      # @return [Float] objects per call
      # @raise [Dexpace::InvalidArgumentError] unless iterations is a positive Integer
      def delta(iterations:, &block)
        unless iterations.is_a?(::Integer) && iterations.positive?
          raise ::Dexpace::InvalidArgumentError, "iterations must be a positive Integer"
        end

        # `GC.disable` answers whether the collector was ALREADY disabled, and this is published
        # library code a host may call with the collector off: the state it found is the state it
        # leaves, so a host that disabled GC around the call does not find it re-enabled.
        was_disabled = ::GC.disable
        begin
          previous = measure(iterations, &block)
          ATTEMPTS.times do
            current = measure(iterations, &block)
            return current if current == previous

            previous = current
          end
          previous
        ensure
          ::GC.enable unless was_disabled
        end
      end

      private

      # One two-loop measurement: the warm-up, then `iterations` and `2 * iterations` calls, the
      # difference of the two deltas over `iterations`.
      #
      # `{ yield }` and never `times(&)`: Integer#times hands its index to the block it is given,
      # and the caller's block -- a lambda, say -- may take no argument.
      # rubocop:disable-next Style/ExplicitBlockArgument -- see above
      def measure(iterations)
        WARMUP_ITERATIONS.times { yield }
        first = ::GC.stat(:total_allocated_objects)
        iterations.times { yield }
        second = ::GC.stat(:total_allocated_objects)
        (iterations * 2).times { yield }
        third = ::GC.stat(:total_allocated_objects)
        ((third - second) - (second - first)) / iterations.to_f
      end
    end
  end
end
