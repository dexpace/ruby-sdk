# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "async_http/version"

module Dexpace
  # Transport adapters: the synchronous and asynchronous transport seams' shipped
  # implementations. The seam contracts themselves live in dexpace-core.
  module Transport
    # The reference asynchronous transport, over the `async-http` gem. Phase 0 ships the
    # namespace and VERSION only; the adapter itself lands in phase 8.
    #
    # CAUTION: once dexpace-async-thread is loaded in the same process, `Dexpace::Async` exists,
    # and an unqualified `Async::HTTP` written anywhere under this module resolves through the
    # lexical scope to `Dexpace::Async` before it ever reaches the socketry gem. Every reference
    # to that gem from inside here is written `::Async::HTTP`.
    module AsyncHTTP
    end
  end
end
