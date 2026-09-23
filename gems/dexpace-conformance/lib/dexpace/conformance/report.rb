# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "levels"
require_relative "result"

module Dexpace
  module Conformance
    # A frozen list of Results, partitioned by status, with the one renderer 8a shipped and the
    # structured form it deferred ("NFR-4-locked surface with no caller until phase 9 aggregates
    # three suites" -- phase 9 is the phase with the caller).
    #
    # Three things print on EVERY run and not only on failure, because a green run is the run a
    # reader is most likely to over-read. Design §9.3: "the gap stays visible rather than
    # disappearing into a restated item" -- so every waived ID is named. P8-9: the suite's fixture
    # speaks plaintext only and exercises no connect timeout, so the suite hands its preamble in
    # and it prints first. And design R3: nothing passes by not being built, so an un-waived,
    # un-accepted MUST-level vacuity is a REPORT BLOCKER -- `#passed?` is false while one stands.
    #
    # `waived (would fail)` is a DRIVER's declaration, never a blanket rename of 8a's rendering: a
    # waiver can mean "the adapter does not support the property" (8c waives TRANSPORT-14 and
    # TRANSPORT-27 for exactly that) or "this would fail and the port has named the gap"
    # (ASYNC-3, design R5). Renaming every waiver would make the report lie about the first kind,
    # so the second kind names itself through `would_fail:`.
    class Report # rubocop:disable Metrics/ClassLength -- one report: the five statuses, the two vacuity sections design R3 adds and the two renderings are one value's faces; a split would invent a second constant for half a report
      # Merging Results rather than Reports keeps ONE #passed? over the whole run, which is what a
      # CI step needs. The acceptances and the would-fail declarations merge too: a suite-level
      # one survives aggregation and an aggregate-level one applies to every suite.
      #
      # @param reports [Array<Report>]
      # @param preamble [String, nil]
      # @param accepted_vacuous [Hash{String => String}]
      # @param would_fail [Array<String>]
      # @return [Report]
      def self.merge(reports, preamble: nil, accepted_vacuous: {}, would_fail: [])
        inherited = reports.map(&:accepted_vacuous).reduce({}, :merge)
        new(reports.flat_map(&:results), preamble: preamble,
                                         accepted_vacuous: inherited.merge(accepted_vacuous),
                                         would_fail: reports.flat_map(&:would_fail) | would_fail,)
      end

      # @return [Array<Result>] every result, frozen, in the suite's order
      attr_reader :results
      # @return [String, nil] what the run does not prove, printed first (P8-9)
      attr_reader :preamble
      # @return [Hash{String => String}] sanctioned MUST-level vacuities, each with its citation
      attr_reader :accepted_vacuous
      # @return [Array<String>] waived IDs whose assertion would have failed (design R5)
      attr_reader :would_fail

      # @param results [Enumerable<Result>] the run's results, in order
      # @param preamble [String, nil] the suite's stated omissions
      # @param accepted_vacuous [Hash{String => String}] ID => citation. Every citation is
      #   mandatory and non-empty: an acceptance is a claim that design §12 or §10.5 sanctions the
      #   vacuity, and a blank claim is the silent pass this mechanism exists to remove.
      # @param would_fail [Array<String>] IDs whose waiver the driver declares as would-fail
      # @raise [ArgumentError] on an acceptance with no citation
      def initialize(results, preamble: nil, accepted_vacuous: {}, would_fail: [])
        @results = results.to_a.freeze
        @preamble = preamble
        @accepted_vacuous = accepted_vacuous.transform_keys(&:to_s).freeze
        @would_fail = would_fail.map(&:to_s).freeze
        @accepted_vacuous.each { |id, citation| validate_citation!(id, citation) }
      end

      # True when nothing failed, nothing errored and no un-waived, un-accepted MUST-level
      # vacuity stands. A waived result never fails a run -- it is a gap the port has named -- and
      # a SHOULD- or MAY-level vacuity is recorded and does not block.
      #
      # @return [Boolean]
      def passed?
        failures.empty? && errors.empty? && blocking_vacuities.empty?
      end

      # @return [Array<Result>] the results whose assertion returned cleanly
      def passed = by_status(:passed)

      # @return [Array<Result>] the results whose assertion raised a Failure
      def failures = by_status(:failed)

      # @return [Array<Result>] the results whose assertion raised a Vacuous
      def vacuous = by_status(:vacuous)

      # @return [Array<Result>] the results a named waiver suppressed before they ran
      def waived = by_status(:waived)

      # @return [Array<Result>] the results whose assertion raised anything else
      def errors = by_status(:error)

      # Design R3: an absent artifact is :vacuous rather than :failed so phase 10 can tell "not
      # built" from "built wrong" -- and that is safe only because nothing passes by not being
      # built. These are the vacuities on a MUST that no acceptance names.
      #
      # @return [Array<Result>]
      def blocking_vacuities
        must_level_vacuities.reject { |result| accepted?(result) }
      end

      # @return [Array<Result>] MUST-level vacuities a driver sanctioned, with a citation
      def accepted_vacuities
        must_level_vacuities.select { |result| accepted?(result) }
      end

      # @return [Array<String>] every ID in this run that appendix C does not hold -- a typo in an
      #   assertion's `ids:` is otherwise invisible, because an unknown ID never blocks
      def unknown_ids
        @results.flat_map { |result| result.assertion.ids }.uniq.reject { |id| Levels.known?(id) }
      end

      # The rendering: the preamble when there is one, a count line, then every waived, accepted,
      # vacuous, blocking, failed and errored result named by its IDs -- and, last, the blocker
      # verdict, so a reader who sees only the tail sees it.
      #
      # @return [String]
      def to_s
        [preamble, counts_line, *waived_lines, *accepted_lines, *vacuous_lines,
         *blocking_lines, *detail_lines, blocked_line,].compact.join("\n")
      end

      # The structured form 8a deferred for phase 9's aggregate caller.
      #
      # @return [Hash{Symbol => Object}]
      def to_h # rubocop:disable Metrics/AbcSize -- one structured row per section, and the sections are the report's own
        counts.merge(
          blocking_vacuities: blocking_vacuities.map do |r|
            { ids: r.assertion.ids, detail: r.detail }
          end,
          accepted_vacuities: accepted_vacuities.map do |r|
            { ids: r.assertion.ids, citation: citation_for(r) }
          end,
          unknown_ids: unknown_ids,
          results: @results.map do |result|
            { ids: result.assertion.ids, name: result.assertion.name, status: result.status,
              detail: result.detail, }
          end,
        )
      end

      private

      def validate_citation!(id, citation)
        return if citation.is_a?(::String) && !citation.strip.empty?

        raise ::ArgumentError,
              "accepted_vacuous[#{id.inspect}] needs a citation (design §12 or §10.5)"
      end

      def by_status(status)
        @results.select { |result| result.status == status }
      end

      def must_level_vacuities
        vacuous.select { |result| must_level?(result) }
      end

      def must_level?(result)
        result.assertion.ids.any? { |id| Levels.must?(id) }
      end

      # Every MUST-level ID the assertion carries must be named, never just one: an acceptance of
      # one ID would otherwise silence a co-carried MUST, which is the gap staying invisible.
      def accepted?(result)
        result.assertion.ids.all? { |id| !Levels.must?(id) || @accepted_vacuous.key?(id) }
      end

      def citation_for(result)
        result.assertion.ids.filter_map { |id| @accepted_vacuous[id] }.uniq.join("; ")
      end

      def counts
        { passed: passed.size, failed: failures.size, vacuous: vacuous.size,
          waived: waived.size, errored: errors.size, }
      end

      def counts_line
        "#{passed.size} passed, #{failures.size} failed, #{vacuous.size} vacuous, " \
          "#{waived.size} waived, #{errors.size} errored"
      end

      def waived_lines
        waived.map do |result|
          label = result.assertion.ids.intersect?(@would_fail) ? "waived (would fail)" : "waived"
          "  #{label}: #{ids(result)} (#{result.assertion.name})"
        end
      end

      def accepted_lines
        accepted_vacuities.map do |result|
          "  accepted MUST-level vacuity (design-sanctioned): " \
            "#{ids(result)}: #{citation_for(result)}"
        end
      end

      def vacuous_lines
        (vacuous - must_level_vacuities).map { |r| "  vacuous: #{ids(r)}: #{r.detail}" }
      end

      def blocking_lines
        blocking_vacuities.map do |result|
          "  MUST-level vacuity (report blocker): #{ids(result)}: #{result.detail}"
        end
      end

      def blocked_line
        return nil if blocking_vacuities.empty?

        count = blocking_vacuities.size
        "REPORT BLOCKED: #{count} un-waived MUST-level " \
          "#{count == 1 ? "vacuity" : "vacuities"} (design R3)"
      end

      def detail_lines
        { "FAILED" => failures, "ERROR" => errors }.flat_map do |label, results|
          results.map { |result| "  #{label}: #{ids(result)}: #{result.detail}" }
        end
      end

      def ids(result)
        result.assertion.ids.join(", ")
      end
    end
  end
end
