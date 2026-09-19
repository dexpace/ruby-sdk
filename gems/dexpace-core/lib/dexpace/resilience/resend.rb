# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../http/method"
require_relative "../http/body"

module Dexpace
  module Resilience
    # RETRY-5, RETRY-6, RETRY-7, RETRY-8 and RECOV-18: the re-sendability gate, the second of
    # the two independent axes retry needs, single-sourced. Both retry stacks call this exact
    # method and neither restates the rule; 6b's REDIR-6 and 6c's AUTH-31 are its other two
    # callers, as phase 3b's forward table anticipated (R5, confirmed unchanged).
    #
    # The rule in one line: a body-less request is re-sendable iff its method is idempotent --
    # HTTP-9's single set, phase 1's Method::IDEMPOTENT read through #idempotent? and never
    # re-listed here, which is what makes RETRY-6's `{GET, HEAD, OPTIONS, PUT, DELETE}` one
    # constant and not two -- and a body-bearing request iff its body says it is replayable
    # (phase 3b's Body#replayable?, false by default). So a bare non-idempotent POST is NOT
    # re-sendable even though there is no payload to resend (RETRY-7), and a PUT with a
    # non-replayable body is not either (RETRY-8: both axes, neither implying the other).
    #
    # Phase 6b extends this module in place with the body-only question REDIR-6 asks
    # (.replayable_body?) and its NotReplayableError; nothing here anticipates them, and nothing
    # here is a "no-op if the file exists" skip (the plan's ownership note).
    module Resend
      extend self

      # Whether `request` may be sent to the wire a second time.
      #
      # @param request [Dexpace::Request]
      # @return [Boolean]
      def eligible?(request)
        body = request.body
        return request.method.idempotent? if body.nil?

        body.replayable?
      end
    end
  end
end
