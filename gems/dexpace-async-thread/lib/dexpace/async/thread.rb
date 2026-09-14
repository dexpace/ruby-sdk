# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "thread/version"

module Dexpace
  # Async-runtime adapters: the async seam's shipped implementations. The seam contract itself
  # lives in dexpace-core.
  module Async
    # The async-runtime adapter over plain Ruby threads. Phase 0 ships the namespace and VERSION
    # only; the adapter itself lands in phase 8.
    #
    # CAUTION: this module shadows ::Thread inside its own namespace. An unqualified
    # `Thread.new` written anywhere under `Dexpace::Async::Thread` resolves to this module, not
    # to Ruby's, and fails with a confusing NoMethodError. Every reference to Ruby's Thread from
    # inside here is written `::Thread`.
    module Thread
    end
  end
end
