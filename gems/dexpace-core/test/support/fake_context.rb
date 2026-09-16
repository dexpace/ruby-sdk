# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../lib/dexpace/context"

# The one double CTX's store suite needs: every store rule (CTX-7 through CTX-13, CTX-18, CTX-19)
# is about a keyed occupant and nothing else, so driving them through a real chain would couple
# the store's suite to a Bundle, a Request and a Response per case. A real in-memory
# implementation of Dexpace::Context, not a recorder of calls -- a fake by testing/7ecef8e8's
# definition, named Fake* per testing/630ba094. Gets #close free from the module, which is what
# makes the CTX-9/CTX-10 cases readable. It has no value equality (plain Object#==), which is why
# the CTX-9 trap needs a real Data context and lives beside it in context_store_test.rb.
#
# It lives in dexpace-core's test tree and is not public API, for the reason fake_transport.rb
# gives: a published fake is NFR-4-locked surface, and the move to dexpace-conformance was
# declined by phase 8a.
class FakeContext
  include Dexpace::Context

  # @return [String] the store key this occupant registers under
  # @return [#set, #release] the store #close releases through
  attr_reader :call_key, :store

  def initialize(call_key:, store:)
    @call_key = call_key
    @store = store
  end
end
