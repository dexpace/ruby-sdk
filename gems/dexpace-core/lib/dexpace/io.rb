# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # The byte-streaming layer: one FIFO buffer, one buffered source/sink pair with typed reads and
  # non-consuming views, and one tee sink. Design §10.1 retired the provider seam that used to make
  # this pluggable, so the behavioural contract is the whole deliverable -- there is no registry,
  # no factory and no installation call here.
  #
  # HAZARD, stated where a reader meets it. This constant shadows ::IO for every file inside
  # `module Dexpace` AND inside a consumer's own `class C; include Dexpace`, because `include`
  # inserts Dexpace ahead of Object in C.ancestors. `x.is_a?(IO)` is then silently false for a
  # real ::IO, with no error and no warning, and a `case/when IO` falls through. A top-level
  # `include Dexpace` is unaffected, because Object's own constant table is searched first. Core
  # never writes `is_a?(IO)`: every stream this layer accepts is checked with respond_to?, and
  # Dexpace/QualifiedCoreConstant makes a bare `IO` inside `module Dexpace` a RuboCop offense.
  # No gate this repository owns reaches a consumer's file, which is why the same warning is owed
  # in docs/sdk-documentation/ before anything is published (docs/first-release.md).
  module IO
    # IO-9's ceiling. Design §10.18 substitutes it for a host maximum single-array allocation Ruby
    # does not have, and §3.1 fixes the default at 64 MiB -- "chosen, not derived". Every
    # operation that produces one contiguous String reads this constant directly; nothing takes
    # it as a keyword. Phase 5 owns the configuration source (R5; phase 2's deadline: precedent,
    # P2-5): adding an optional keyword later widens a signature rather than narrowing one, so
    # NFR-4 is not prejudiced.
    MAX_MATERIALIZED_BYTES = 64 * 1024 * 1024
  end
end
