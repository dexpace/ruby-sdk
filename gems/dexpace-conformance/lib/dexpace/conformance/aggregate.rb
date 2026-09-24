# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "report"

module Dexpace
  module Conformance
    # One report over every suite in a run. This is the caller phase 8a deferred `Report#to_h`
    # for, and the place `docs/first-release.md`'s standing blocker -- "before release,
    # `docs/sdk-documentation/` must state what a green run does and does not prove, and the run's
    # own report preamble must name the same omissions" -- is made mechanical: PREAMBLE prints on
    # every render rather than sitting in a document nobody re-reads.
    module Aggregate
      # §12 distinguishes "not satisfied" from "holds vacuously", and §9.3 requires a waived gap
      # to stay visible. So this states, on every run, what a green result does NOT prove.
      PREAMBLE = [
        "A pass here proves the assertions below ran green. It does not prove:",
        "  - TLS verification or connect-timeout classification: the wire fixture speaks",
        "    plaintext only and there is no portable way to make a local listener accept slowly,",
        "    so both are asserted in dexpace-transport-net_http's own suite and not here (8a's",
        "    P8-9), as is TRANSPORT-8, whose antecedent only an adapter's own suite can name",
        "  - anything covered 'by reference' in APPENDIX_B.md, where the evidence is another",
        "    gem's test file: the row proves the ID is claimed and the file exists, never that",
        "    the behaviour is asserted (phase 9's P9-7)",
        "  - any requirement whose assertion is listed below as waived or vacuous",
        "  - a MUST-level requirement whose assertion is vacuous and that no accepted_vacuous:",
        "    citation names: such a result is listed below as a report blocker, fails this run,",
        "    and earns a docs/first-release.md line (design R3)",
      ].freeze

      extend self

      # @param reports [Array<Report>] one per suite run
      # @param accepted_vacuous [Hash{String => String}] acceptances that apply to the whole run,
      #   merged over each suite's own
      # @param would_fail [Array<String>] waived IDs whose assertion would have failed
      # @return [Report] one report with ONE #passed? over the whole run
      def run(reports, accepted_vacuous: {}, would_fail: [])
        Report.merge(reports, preamble: PREAMBLE.join("\n"),
                              accepted_vacuous: accepted_vacuous, would_fail: would_fail,)
      end

      # @param report [Report]
      # @return [String] the preamble and the report, in that order
      def render(report)
        report.to_s
      end

      # The generated half of the appendix-B coverage map: every assertion each suite DECLARES,
      # keyed by requirement ID.
      #
      # It takes the SUITES and not a Report, and that is load-bearing: a Report holds only the
      # assertions that actually RAN, so reading one would let a suite skipped in a given
      # invocation silently shorten the map -- and the map's own row-count check would then fail
      # for a reason that has nothing to do with a dropped row (design R7).
      #
      # `statuses:` is an optional Report: when given, each row carries the status that run
      # produced, and an assertion with no result is marked `:not_run` rather than omitted.
      #
      # @param suites [Array<#assertions>] every suite whose declarations belong in the map
      # @param statuses [Report, nil] one run's results
      # @return [Hash{String => Array<Hash>}] requirement ID -> its rows
      def by_requirement_id(suites, statuses: nil)
        ran = statuses.nil? ? [] : statuses.results #: Array[Result]
        observed = ran.to_h { |result| [result.assertion.name, result.status] }
        rows = {} #: Hash[String, Array[untyped]]
        suites.each_with_object(rows) { |suite, map| add_rows(suite, observed, map) }
      end

      private

      def add_rows(suite, observed, map)
        suite.assertions.each do |assertion|
          row = { suite: suite.name, assertion: assertion.name,
                  status: observed.fetch(assertion.name, :not_run), }
          assertion.ids.each { |id| (map[id] ||= []) << row }
        end
      end
    end
  end
end
