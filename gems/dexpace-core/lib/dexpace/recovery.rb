# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/invalid_argument_error"
require_relative "http/body"
require_relative "http/response"

module Dexpace
  # §8.2's resilience layer: the two folds over frozen step lists, the orchestrator that lets no
  # throwable past it, the transform contract the three shipped steps implement, and this one
  # function. The namespace is design §5.1's own, and it keeps the layer's boundary visible in
  # the constant path: nothing under Dexpace::Recovery names a stage, a cursor or a pillar,
  # because spec §8.3 forbids either pipeline layer expressing itself in the other's terms, and
  # Dexpace::Outcome sits beside this module rather than inside it because phase 7's SSE adapter
  # reuses the outcome type with no recovery chain in sight (R9).
  module Recovery
    # RECOV-16 and BODY-30: before an error-status response becomes a typed exception, its body
    # is buffered into a bounded, replayable in-memory copy so the transport connection is
    # released promptly and the body stays readable on the resulting Failure.
    #
    # Phase 3b fixed the contract and this implements it without re-deciding: a response whose
    # status is not an error, or whose body is nil, comes back by identity; otherwise the body
    # goes through Body.buffer_bounded at Body::MAX_BUFFERED_ERROR_BODY_BYTES -- the ONE bound,
    # declared there and nowhere else, which is what RECOV-16's "the same bound MUST be shared
    # across all error-body-buffering paths" makes a requirement rather than tidiness -- and the
    # response comes back carrying the BufferBody. The original body's close happens inside
    # buffer_bounded's own `ensure`, unguarded, which is BODY-30's close-guaranteeing scope and,
    # for the error-mapping step, RECOV-13's ownership discharge: the step drops the original
    # response and the buffering already released it. The status test is Status#error?, phase
    # 1's, and this file writes no second predicate. This is the one buffering call site; phase
    # 6a's per-attempt re-classification calls it too and adds no second.
    #
    # @param response [Dexpace::Response]
    # @return [Dexpace::Response] the same object, or a copy whose body is the bounded buffer
    # @raise [Dexpace::InvalidArgumentError] when `response` is not a Dexpace::Response
    def self.buffer_error_body(response)
      unless response.is_a?(Response)
        raise InvalidArgumentError, "response must be a Dexpace::Response"
      end
      return response unless response.status.error?

      body = response.body
      return response if body.nil?

      buffered = Body.buffer_bounded(body, cap: Body::MAX_BUFFERED_ERROR_BODY_BYTES)
      response.with(body: buffered)
    end
  end
end
