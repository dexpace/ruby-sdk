# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "codec_case"
require_relative "runner"
require_relative "codec_suite/seam"

module Dexpace
  module Conformance
    # Appendix B.3's seam half: the two properties a wire codec must have whatever library it
    # wraps -- SEAM-20 with SERDE-3 (it never closes a target it was handed) and SERDE-9 (no
    # library exception type escapes the seam).
    #
    # **These assertions are RE-DERIVED from the requirement text, not lifted out of
    # `dexpace-serde-json`'s own suite, and that gem's files are left byte-identical.** A lift
    # would have moved `assert_closes_nothing`, whose body is the only evidence SEAM-21 has in
    # that suite, and `assert_failure_model`, which carries SERDE-10 and the ENCODE half of
    # SERDE-9 as well -- so a lift that took the portable halves would have dropped three
    # properties on its way out. The relationship here is TransportSuite's to the net_http suite's
    # instead: a portable assertion beside a gem-local one, both alive.
    #
    # The post-v1 `dexpace-serde-oj` is the second subject these two exist for.
    module CodecSuite
      extend self

      # What a green run of this suite does NOT prove.
      PREAMBLE = "dexpace-conformance codec suite: two SEAM properties, re-derived from the " \
                 "requirement text. The offset matrix (SERDE-4), the I/O-error pass-through " \
                 "(SERDE-12), the explicit type token (SEAM-21), the encode half of SERDE-9 and " \
                 "SERDE-10's mapping are asserted in the adapter's own suite and are NOT among " \
                 "the things a green run here proves."

      # @return [Array<Assertion>] the suite's assertions, frozen and ordered
      def assertions
        ASSERTIONS
      end

      # @param build [#call] a zero-argument codec factory
      # @param witness [Object] a witness the codec's #load accepts
      # @param source [#call] text -> the source type this codec's #load reads
      # @param waive [Array<String>] requirement IDs recorded :waived without running
      # @param around [#call, nil] the suite contract's clause 9 wrapper
      # @param accepted_vacuous [Hash{String => String}] sanctioned MUST-level vacuities
      # @param would_fail [Array<String>] waived IDs whose assertion would have failed
      # @return [Report]
      def run(build:, witness:, source:, waive: [], around: nil, accepted_vacuous: {},
              would_fail: [])
        Runner.run(assertions, waive: waive, around: around, preamble: PREAMBLE,
                               accepted_vacuous: accepted_vacuous, would_fail: would_fail,) do
          CodecCase.new(build: build, witness: witness, source: source)
        end
      end

      # The one group, a private module of its own file, so the assertion bodies are not public
      # surface.
      ASSERTIONS = Seam::ASSERTIONS
      private_constant :ASSERTIONS
    end
  end
end
