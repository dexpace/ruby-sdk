# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "conformance/version"

module Dexpace
  # The conformance suite every adapter is proven against. Phase 0 ships the namespace and
  # VERSION only; the assertion objects and their Minitest and RSpec drivers land in phase 8a,
  # and phase 9 adds the remaining suites.
  module Conformance
  end
end
