# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "invariant_case"
require_relative "runner"
require_relative "invariant_suite/outcomes"
require_relative "invariant_suite/models"
require_relative "invariant_suite/taxonomy"
require_relative "invariant_suite/classification"
require_relative "invariant_suite/memory"
require_relative "invariant_suite/security"
require_relative "invariant_suite/header_syntax"
require_relative "invariant_suite/credentials"
require_relative "invariant_suite/sharing"
require_relative "invariant_suite/concurrency"
require_relative "invariant_suite/resolution"

module Dexpace
  module Conformance
    # Appendix B.8, the cross-cutting invariants: twenty-eight assertions over all twenty-four
    # XCUT IDs, with XCUT-11, XCUT-13, XCUT-14 and XCUT-18 carrying two each.
    #
    # One Result per ASSERTION, assertions keyed by requirement ID, and an appendix-B item is a
    # view over the assertions for its IDs whose status is the worst among them (design P9-8) --
    # which is what lets XCUT-13's two clauses each have a check without a second ID. "One
    # assertion per ID" would forbid exactly that.
    #
    # Most of what this suite reaches is a core constant it can name itself. Six things it cannot,
    # and the driver supplies each as a factory: the closeable seam, a transport, a bounded map
    # and a reader for its private store, a cnonce draw and a redirect re-issue -- plus the
    # credential hop and the list of shared instances whose declared-mutable ivars only the driver
    # knows (P9-9). A factory left nil makes its assertions report :vacuous WITH A REASON, never
    # :passed; an un-waived MUST-level vacuity then blocks the report (Report#blocking_vacuities),
    # which is what stops "not supplied" from reading as "conforming".
    module InvariantSuite
      extend self

      # What a green run of this suite does NOT prove.
      PREAMBLE = "dexpace-conformance invariant suite: every assertion here is reached through " \
                 "the loaded core module and the factories the driver supplied. A factory left " \
                 "nil makes its assertions vacuous rather than passed, and a MUST-level vacuity " \
                 "blocks the report -- so read the vacuity list, not only the pass count."

      # @return [Array<Assertion>] the suite's assertions, frozen and ordered
      def assertions
        ASSERTIONS
      end

      # Runs the suite against one core module and the driver's factories.
      #
      # @param core [Module] the loaded core module under audit
      # @param seam [#call, nil] `->(client:) { … }` building a closeable component with
      #   `#call(request)` and `#release_count`
      # @param transport [#call, nil] a zero-argument factory for a transport seam
      # @param mutable [Array<Symbol>] the seam's declared-mutable ivars (design P9-9)
      # @param shared [Array<Array(String, Object, Array<Symbol>)>] every other shared instance
      #   under audit, as `[label, object, declared ivars]`
      # @param bounded_map [#call, nil] `->(cap:) { … }`
      # @param bounded_map_store [#call, nil] `->(map) { … }` returning the map's backing Hash
      # @param cnonce [#call, nil] `->(source) { … }` returning a rendered cnonce
      # @param redirect_hops [#call, nil] `->(from:, to:, headers:) { … }`
      # @param credential_hop [#call, nil] `->(url:, cross_origin:) { … }`
      # @param waive [Array<String>] requirement IDs recorded :waived without running
      # @param around [#call, nil] the suite contract's clause 9 wrapper
      # @param accepted_vacuous [Hash{String => String}] sanctioned MUST-level vacuities
      # @param would_fail [Array<String>] waived IDs whose assertion would have failed
      # @return [Report]
      def run(core: ::Dexpace, seam: nil, transport: nil, mutable: [], shared: [],
              bounded_map: nil, bounded_map_store: nil, cnonce: nil, redirect_hops: nil,
              credential_hop: nil, waive: [], around: nil, accepted_vacuous: {}, would_fail: [])
        Runner.run(assertions, waive: waive, around: around, preamble: PREAMBLE,
                               accepted_vacuous: accepted_vacuous, would_fail: would_fail,) do
          InvariantCase.new(core: core, seam: seam, transport: transport, mutable: mutable,
                            shared: shared, bounded_map: bounded_map,
                            bounded_map_store: bounded_map_store, cnonce: cnonce,
                            redirect_hops: redirect_hops, credential_hop: credential_hop,)
        end
      end

      # The ten groups, each a private module of its own file (one constant per file, and each
      # under RuboCop's module-length cap), concatenated in the order a reader meets the chapter.
      ASSERTIONS = (Models::ASSERTIONS + Taxonomy::ASSERTIONS + Classification::ASSERTIONS +
                    Memory::ASSERTIONS + Security::ASSERTIONS + HeaderSyntax::ASSERTIONS +
                    Credentials::ASSERTIONS + Sharing::ASSERTIONS + Concurrency::ASSERTIONS +
                    Resolution::ASSERTIONS).freeze
      private_constant :ASSERTIONS
    end
  end
end
