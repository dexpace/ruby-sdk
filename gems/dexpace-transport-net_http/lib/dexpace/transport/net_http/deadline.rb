# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module NetHTTP
      # R3: RequestOptions#timeout is a TOTAL per-call budget, not one value assigned to three
      # per-operation knobs -- a call with `timeout: 5` must be bounded by five seconds in all,
      # not five seconds per read. The budget is carried as an absolute monotonic instant over
      # phase 5a's injectable clock (CFG-15: never Time.now), and the adapter reads `#clamped`
      # into the knobs before the connection exists and again after every chunk the pump
      # receives. `#clamped` is TRANSPORT-6's one-line clamp, carried here so the ID appears in
      # exactly one place. A private_constant of NetHTTP.
      class Deadline
        private_class_method :new

        # The one construction entry point: the budget is converted to an instant NOW.
        #
        # @param clock [#monotonic] phase 5a's Dexpace::Clock or a fake
        # @param budget [Numeric] seconds from now; a non-positive budget is already expired
        # @return [Deadline]
        def self.build(clock:, budget:)
          new(clock, clock.monotonic + budget)
        end

        def initialize(clock, instant)
          @clock = clock
          @instant = instant
        end

        # Seconds left, negative once the instant has passed.
        #
        # @return [Float]
        def remaining
          @instant - @clock.monotonic
        end

        # Whether the budget is spent: the adapter's own check, taken BEFORE `#clamped` is
        # consulted, so an expired budget raises rather than dispatching with a near-zero knob
        # (zero means "poll once" on Net::HTTP, not "no timeout").
        #
        # @return [Boolean]
        def expired?
          remaining <= 0
        end

        # TRANSPORT-6: a strictly positive remaining below MIN_TIMEOUT_SECONDS is clamped UP to
        # it; an already-expired remaining is returned as it is, never clamped up past zero, so
        # the caller's `#expired?` decision is the one that decides whether to raise.
        #
        # @return [Float]
        def clamped
          value = remaining
          return value if value <= 0
          return MIN_TIMEOUT_SECONDS if value < MIN_TIMEOUT_SECONDS

          value
        end
      end

      private_constant :Deadline
    end
  end
end
