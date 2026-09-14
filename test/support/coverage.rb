# frozen_string_literal: true
# SPDX-License-Identifier: MIT

return unless ENV["COVERAGE"]

require "simplecov"

SimpleCov.start do
  # NFR-5: "computed across the library units", excluding sample/example code, test-only guards
  # and test fixtures. `cover` restricts the report to the glob AND counts a matching file that
  # was never required at 0%, so an untested library file lowers the number rather than vanishing
  # from it. COVERAGE_TRACK exists so the gate's own negative fixture can point the tracked set
  # somewhere else; nothing in the build sets it.
  cover ENV.fetch("COVERAGE_TRACK", "gems/*/lib/**/*.rb")
  skip "/test/"
  skip "/tasks/"
  skip "/.rubocop/"
  skip "/fixtures/"

  # One process, one aggregate number. Merging would fold a stale resultset from an earlier run
  # -- the negative fixture's, for one -- into this one.
  merging false

  # Never conditioned, never lowered.
  minimum_coverage 80
end
