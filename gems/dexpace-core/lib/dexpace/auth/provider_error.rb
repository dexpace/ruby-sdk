# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../error"

module Dexpace
  module Auth
    # AUTH-35, AUTH-11: a bearer token provider misbehaved -- it returned nil, a token already
    # expired at fetch time (evaluated with no margin), something that is not a BearerToken, or
    # (on the async path) something that is not a Future from #fetch_async. A provider that
    # RAISES is not wrapped: its own error propagates, as AUTH-35 requires. Never cached: the
    # stamper leaves its cache untouched on this error, so a later request retries the fetch.
    class ProviderError < ::StandardError
      include Dexpace::Error
    end
  end
end
