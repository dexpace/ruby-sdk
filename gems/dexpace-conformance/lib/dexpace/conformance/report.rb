# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "result"

module Dexpace
  module Conformance
    # A frozen list of Results, partitioned by status, with the one renderer this sub-phase ships.
    # `#to_s` is the only renderer (8a's open question 6): a structured `#to_h` is NFR-4-locked
    # surface with no caller until phase 9 aggregates three suites, and phase 9 is the phase with
    # the caller.
    #
    # Two things print on EVERY run and not only on failure, because a green run is the run a
    # reader is most likely to over-read. Design §9.3: "the gap stays visible rather than
    # disappearing into a restated item" -- so every waived ID is named. And P8-9: the suite's
    # fixture speaks plaintext only and exercises no connect timeout, so the suite hands its
    # preamble in and it prints first, which is what makes a third-party adapter author's green run
    # honest about TLS and connect-timeout classification.
    class Report
      # @return [Array<Result>] every result, frozen, in the suite's order
      attr_reader :results
      # @return [String, nil] what the run does not prove, printed first (P8-9)
      attr_reader :preamble

      # @param results [Enumerable<Result>] the run's results, in order
      # @param preamble [String, nil] the suite's stated omissions
      def initialize(results, preamble: nil)
        @results = results.to_a.freeze
        @preamble = preamble
      end

      # True when nothing failed and nothing errored. A vacuous or a waived result does not fail a
      # run -- the first has no antecedent to fail on and the second is a gap the port has named --
      # and both are printed so neither reads as a pass.
      #
      # @return [Boolean]
      def passed?
        failures.empty? && errors.empty?
      end

      # @return [Array<Result>] the results whose assertion raised a Failure
      def failures
        by_status(:failed)
      end

      # @return [Array<Result>] the results whose assertion raised a Vacuous
      def vacuous
        by_status(:vacuous)
      end

      # @return [Array<Result>] the results a named waiver suppressed before they ran
      def waived
        by_status(:waived)
      end

      # @return [Array<Result>] the results whose assertion raised anything else
      def errors
        by_status(:error)
      end

      # The rendering: the preamble when there is one, a count line, then every waived, vacuous,
      # failed and errored result named by its IDs -- the waived ones on every run.
      #
      # @return [String]
      def to_s
        [preamble, counts_line, *waived_lines, *detail_lines].compact.join("\n")
      end

      private

      def by_status(status)
        @results.select { |result| result.status == status }
      end

      def counts_line
        "#{by_status(:passed).size} passed, #{failures.size} failed, #{vacuous.size} vacuous, " \
          "#{waived.size} waived, #{errors.size} errored"
      end

      def waived_lines
        waived.map { |result| "  waived: #{ids(result)} (#{result.assertion.name})" }
      end

      def detail_lines
        { "vacuous" => vacuous, "FAILED" => failures,
          "ERROR" => errors, }.flat_map do |label, results|
          results.map { |result| "  #{label}: #{ids(result)}: #{result.detail}" }
        end
      end

      def ids(result)
        result.assertion.ids.join(", ")
      end
    end
  end
end
