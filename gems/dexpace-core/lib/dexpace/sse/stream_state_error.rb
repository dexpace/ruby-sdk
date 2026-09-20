# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  module SSE
    # SSE-26's "a second attempt MUST fail loudly (e.g. an illegal-state error)" and SSE-27's
    # post-close refusal: raised by Stream#each and Stream#events when the one view has already
    # been taken, in either shape, or the stream is closed. A second view would resume
    # mid-stream and silently deliver a partial event, which is why this is an error and not a
    # second enumerator (sse-streaming/5f4803a0). Namespaced under SSE, because it is meaningless
    # outside this subsystem (6c's ProviderError precedent).
    class StreamStateError < ::StandardError
      include Dexpace::Error
    end
  end
end
