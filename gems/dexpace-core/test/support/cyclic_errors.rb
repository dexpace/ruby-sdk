# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# R7's fixture classes for XCUT-9's cycle guard, and the one the plan's open question 3 added.
#
# Every cycle here is built through a caller-defined #cause override, never through `raise`:
# `raise y, cause: x` on a linked pair raises ArgumentError ("circular causes") and `raise s,
# cause: s` leaves the cause nil, so the route the design chapter names does not build a cycle at
# all (verified on 3.2.11, 3.4.10 and 4.0.6; docs/knowledge/notes/error-handling.md). A #cause
# override is the shape core cannot control, because Dexpace.each_cause walks caller-supplied
# errors by construction. None of these is ever raised.
module CyclicErrorFixtures
  # A one-node cycle: its cause is itself.
  class SelfCause < ::StandardError
    def cause
      self
    end
  end

  # One half of a two-node cycle; pair two of these through #other_cause=.
  class CyclicPair < ::StandardError
    attr_accessor :other_cause

    def cause
      @other_cause
    end
  end

  # Two distinct instances carrying one message are == by Ruby's own Exception#== (class,
  # message, backtrace -- and a never-raised error's backtrace is nil), which is what truncates
  # an Array-tracked visited set. This class ALSO overrides #hash and #eql? structurally, so a
  # Set-tracked visited set -- which a reader reaches for once told == is wrong, and which is
  # accidentally right for a bare exception -- is defeated by the same pair. Only a visited set
  # built with `{}.compare_by_identity` yields both (verified fact 7).
  #
  # Why the pair is chained through #cause and not by raising: a raise-built pair is == on 3.4.10
  # and 4.0.6 and NOT == on 3.2.11, whose backtrace carries a `rescue in <method>` frame the
  # parent's lacks, so the truncation the test exists to catch is simply absent on the floor and
  # the suite would be green there against the bug. Two never-raised instances are == on all
  # three.
  class StructurallyEqualError < ::StandardError
    attr_accessor :custom_cause

    def cause
      @custom_cause
    end

    def eql?(other)
      other.is_a?(StructurallyEqualError) && message == other.message
    end

    def hash
      [self.class, message].hash
    end
  end

  # Open question 3: a #cause that raises. As reachable as one that cycles, from the same source.
  class RaisingCauseError < ::StandardError
    def cause
      raise ::StandardError, "broken #cause"
    end
  end

  # A #cause that lies: it returns something that is not an Exception at all.
  class LyingCauseError < ::StandardError
    def cause
      "not an exception"
    end
  end
end
