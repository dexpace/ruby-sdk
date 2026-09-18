# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Test isolation for the diagnostic context: runs a block and puts the current fiber's storage
# back afterwards, key by key over the union of what was there and what the block left, so a
# leaked `Fiber[:"trace.id"]` cannot reach a later test on the same thread (testing/4ef070df:
# every test runs alone, in any order, and `rake test` shares one process and one main fiber).
#
# One helper per idea: support/fiber_storage_facts.rb holds the two floor probes and the
# floor-aware key assertions, and this file holds only the save-and-restore block those do not
# cover. It restores through `Fiber[]=` alone, never `Fiber#storage=` (which warns per call and
# would fail the suite under DexpaceTestCase), so on the 3.2 floor a key the block introduced is
# left present with a nil value rather than removed -- the same residual Diagnostics.with has
# there (P5-72), and one no reader that skips nulls can see.
#
# Top level, like the tree's other helpers. Not public API.
module DiagnosticContext
  # @return [Object] the block's value
  def self.preserve
    prior = ::Fiber.current.storage || {}
    yield
  ensure
    current = ::Fiber.current.storage || {}
    (prior.keys | current.keys).each { |key| ::Fiber[key] = prior[key] }
  end
end
