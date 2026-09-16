# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # RECOV-1's closed sum type: the response-side outcome is a Success carrying a response or a
  # Failure carrying a throwable, mutually exclusive and jointly exhaustive, and nothing else.
  #
  # A module the two variants include, so `outcome.is_a?(Dexpace::Outcome)` is the one type test
  # the chains need and the RBS union has a name. It declares no factory and no method: there is
  # exactly one way to build each variant, its own `.build`, and the derivable surface RECOV-1
  # enumerates -- #success?, #failure?, #response_or_nil, #error_or_nil and #fold -- lives on
  # each variant, where the answer is a constant rather than a branch.
  #
  # Two variants and never a third: phase 7's SSE typed adapter reuses this type with a third
  # variant in its own namespace (SSE-33..SSE-36), and the charter's spec-forced boundary 6 keeps
  # it out of this one. Flat under Dexpace:: rather than under Recovery, because §5.2 names it
  # here and because that SSE reuse has nothing to do with the recovery chain (R9).
  module Outcome
  end
end
