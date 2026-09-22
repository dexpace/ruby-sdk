# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Async
    module Thread
      # Raised by Pool#post when the bounded submission queue is full -- ASYNC-2's "saturated"
      # half of "worker-pool rejection (a saturated/shut-down executor)". A closed pool raises
      # Dexpace::ClosedError instead (SEAM-15, phase 2's class): two classes because a caller's
      # two sensible responses differ -- a closed pool is a lifecycle bug, a full queue is
      # backpressure to retry or shed. Phase 2's bridge routes either to Completer#fail, which is
      # how the raise reaches the caller as a failed future and never as a synchronous raise.
      #
      # A ::StandardError including Dexpace::Error, phase 1's module root, so `rescue
      # Dexpace::Error` catches it and it is not an ::IOError: a rejection is not a transport
      # failure and XCUT-4's two-branch taxonomy is not widened. It answers no #retryable?
      # predicate, deliberately: that protocol belongs to Dexpace::TransportError (phase 8a's),
      # and a pool rejection never crosses a retry boundary -- it happens at the bridge, above
      # the pipeline, where no RETRY step can see it (design, "RejectedError").
      class RejectedError < ::StandardError
        include Dexpace::Error
      end
    end
  end
end
