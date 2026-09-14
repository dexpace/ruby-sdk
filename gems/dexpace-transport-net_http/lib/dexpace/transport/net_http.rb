# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "net_http/version"

module Dexpace
  # Transport adapters: the synchronous and asynchronous transport seams' shipped
  # implementations. The seam contracts themselves live in dexpace-core.
  module Transport
    # The reference synchronous transport, over Ruby's `net/http` default gem. Phase 0 ships the
    # namespace and VERSION only; the adapter itself lands in phase 8.
    module NetHTTP
    end
  end
end
