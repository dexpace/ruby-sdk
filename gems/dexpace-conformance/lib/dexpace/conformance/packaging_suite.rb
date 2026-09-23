# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "packaging_case"
require_relative "runner"
require_relative "packaging_suite/dependencies"
require_relative "packaging_suite/surface"

module Dexpace
  module Conformance
    # Appendix B.9's PORTABLE half -- the properties of a UNIT, which a downstream porter can
    # check against their own reimplementation: NFR-1, NFR-2, NFR-3, NFR-10, NFR-11, NFR-13,
    # NFR-14 and NFR-15.
    #
    # The properties of a BUILD -- NFR-4, NFR-5, NFR-6, NFR-7, NFR-12, NFR-16 and NFR-17 -- are
    # recorded gate results and are deliberately not here: a portable assertion for NFR-5 would be
    # asserting that a stranger's gem has 80% coverage, which the requirement does not ask and
    # this suite has no way to know. NFR-10, NFR-13 and NFR-14 are in BOTH forms, which is not a
    # double disposition but two audiences (design R2): the gate answers "is THIS repository's CI
    # enforcing it", the assertion answers "can a porter check it against their own unit".
    #
    # NFR-8 and NFR-9 are in neither: both are vacuous by NFR-8's own text ("in ecosystems without
    # such a build step this requirement does not apply"), and the checks §9.2 retargets are
    # dispositioned under NFR-1 rather than counted twice (design P9-5).
    module PackagingSuite
      extend self

      # What a green run of this suite does NOT prove.
      PREAMBLE = "dexpace-conformance packaging suite: every assertion here reads a RESOLVED " \
                 "Gem::Specification. Inside `bundle exec` a path gem resolves to its SOURCE " \
                 "gemspec and its source tree, which is what a pre-publication gate already " \
                 "checks; the claim these assertions are written for -- published metadata -- " \
                 "needs a built .gem installed and a run outside the bundle. Record which " \
                 "environment produced a result."

      # @return [Array<Assertion>] the suite's assertions, frozen and ordered
      def assertions
        ASSERTIONS
      end

      # Runs the suite against one set of gem names.
      #
      # @param core [String] the core gem's name
      # @param adapters [Array<String>] the adapter gems' names
      # @param resolve [#call] name -> Gem::Specification or nil
      # @param constants [Hash{String => String}] gem name -> the constant path holding its VERSION
      # @param versions [Hash{String => String}] the single source of truth's entry per gem
      # @param sig_roots [Hash{String => String}] gem name -> a shipped sig/ root, where the
      #   resolved spec's own path is not it
      # @param waive [Array<String>] requirement IDs recorded :waived without running
      # @param around [#call, nil] the suite contract's clause 9 wrapper
      # @param accepted_vacuous [Hash{String => String}] sanctioned MUST-level vacuities
      # @param would_fail [Array<String>] waived IDs whose assertion would have failed
      # @return [Report]
      def run(core: "dexpace-core", adapters: [], resolve: PackagingCase::DEFAULT_RESOLVE,
              constants: {}, versions: {}, sig_roots: {}, waive: [], around: nil,
              accepted_vacuous: {}, would_fail: [])
        Runner.run(assertions, waive: waive, around: around, preamble: PREAMBLE,
                               accepted_vacuous: accepted_vacuous, would_fail: would_fail,) do
          PackagingCase.new(core_name: core, adapter_names: adapters, resolve: resolve,
                            constants: constants, versions: versions, sig_roots: sig_roots,)
        end
      end

      # The two groups, each a private module of its own file.
      ASSERTIONS = (Dependencies::ASSERTIONS + Surface::ASSERTIONS).freeze
      private_constant :ASSERTIONS
    end
  end
end
