# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"
require_relative "../error/invalid_argument_error"

module Dexpace
  module SSE
    # SSE-19: raised from the pull on which a line, or the bytes accumulated into one event
    # block, cross the documented bound -- Dexpace::SSE::MAX_LINE_BYTES or ::MAX_EVENT_BYTES, or
    # the per-reader value that replaced it.
    #
    # The port takes SSE-19's MAY and REJECTS rather than truncates: a truncated data line reaches
    # the caller's mapper as a parse failure at a place the caller cannot relate to the cause, and
    # design section 10.18's own sanction is "fails or ignores loudly" (P7-21). `kind` is :line or
    # :event and `limit` is the value that was crossed, so a caller raising the cap knows which
    # keyword to raise. Through the facade it travels SSE-29's mid-stream-failure path: the
    # resource is released before it surfaces, and a release failure rides on its suppressed
    # trail. Namespaced under SSE rather than flat, because it is meaningless outside this
    # subsystem (6c's ProviderError precedent).
    class LimitExceededError < ::StandardError
      include Dexpace::Error

      # The two bounds a reader enforces, and the only values `kind` takes. Private: it is not
      # NFR-4 surface (6b's RECOGNIZED_CODES precedent).
      KINDS = %i[line event].freeze
      private_constant :KINDS

      # Which bound was crossed: :line or :event.
      attr_reader :kind

      # The bound's value in bytes, as the reader that raised was configured.
      attr_reader :limit

      # @param kind [Symbol] :line or :event
      # @param limit [Integer] the bound in bytes
      # @raise [Dexpace::InvalidArgumentError] for a kind that is neither bound
      def initialize(kind:, limit:)
        unless KINDS.include?(kind)
          raise InvalidArgumentError, "kind must be :line or :event, got #{kind.inspect}"
        end

        @kind = kind
        @limit = limit
        super("an SSE #{kind} exceeded its #{limit}-byte limit and was rejected, not " \
              "truncated (SSE-19)")
      end
    end
  end
end
