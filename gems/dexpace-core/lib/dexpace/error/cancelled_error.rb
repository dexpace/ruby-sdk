# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # Raised when a cancelled operation is observed: Cancellation#check!, Future#value on a cancelled
  # future, and the blocking half of SEAM-18's bridge.
  #
  # The reason is carried as an object rather than folded into the message because XCUT-2 requires
  # a timeout and a cancellation to be told apart by ambient state, never by matching a string.
  # Phase 6's RETRY-23/RETRY-24 classification reads #reason, not #message. It stays outside
  # Ruby's IOError family deliberately: XCUT-4's I/O family is for transport failures, and a
  # cancellation is not one (design P2-4).
  class CancelledError < ::StandardError
    include Dexpace::Error

    # @return [Object, nil] whatever the canceller supplied, untouched
    attr_reader :reason

    # The one-argument shape is what `raise Dexpace::CancelledError, reason` needs: Ruby hands
    # the second argument of `raise` to the class's constructor, so the reason travels as itself.
    def initialize(reason = nil)
      @reason = reason
      super(reason.nil? ? "the operation was cancelled" : "the operation was cancelled: #{reason}")
    end
  end
end
