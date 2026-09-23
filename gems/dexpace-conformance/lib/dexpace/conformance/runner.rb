# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "assertion"
require_relative "failure"
require_relative "vacuous"
require_relative "result"
require_relative "report"

module Dexpace
  module Conformance
    # The one loop every phase-9 suite's `.run` delegates to, so the five statuses are decided in
    # one place. Four suites would otherwise carry four copies of one status loop, which is
    # §11.12's "four reference sync/async drifts" reappearing inside the port's own suite.
    #
    # TransportSuite (phase 8a) predates this and is deliberately NOT refactored onto it: phase 8
    # owns that file and phase 9 reports rather than refactors (design R6, P9-10). The residue is
    # real -- two status-deciding paths in one gem -- and is stated rather than hidden.
    module Runner
      extend self

      # @param assertions [Array<Assertion>] ordered, frozen
      # @param waive [Array<String>] requirement IDs, never assertion names (design §9.3)
      # @param around [#call, nil] wraps each invocation; an async driver passes
      #   `->(&blk) { Sync { blk.call } }`, which is the suite contract's clause 9
      # @param accepted_vacuous [Hash{String => String}] MUST-level IDs whose vacuity the port
      #   has sanctioned, each with its citation (design R3)
      # @param would_fail [Array<String>] waived IDs whose assertion WOULD have failed, rendered
      #   `waived (would fail): ID` (design R5)
      # @param preamble [String, nil] what this suite's green run does not prove
      # @yield a subject built fresh per assertion (testing/4ef070df)
      # @return [Report]
      def run(assertions, waive: [], around: nil, accepted_vacuous: {}, would_fail: [],
              preamble: nil, &subject)
        results = assertions.map { |assertion| one(assertion, waive, around, subject) }
        Report.new(results, preamble: preamble, accepted_vacuous: accepted_vacuous,
                            would_fail: would_fail,)
      end

      # Builds a group's frozen assertion list from a table of `[ids, name, method_name]` rows --
      # 8a's `Checks.registry` shape, in the file phase 9's suites can all reach. The table is what
      # keeps an assertion's IDs, its human name and its body in one readable place, which is what
      # a third-party suite author writing their own group needs too.
      #
      # @param group [Module] the module whose singleton methods the rows name
      # @param rows [Array<Array(String | Array[String], String, Symbol)>]
      # @return [Array<Assertion>] frozen
      def registry(group, rows)
        rows.map do |ids, name, function|
          Assertion.build(ids: Array(ids), name: name,
                          body: ->(subject) { group.public_send(function, subject) },)
        end.freeze
      end

      private

      # Rescue order is load-bearing and is not alphabetical: Vacuous and Failure are both
      # ::StandardError descendants (8a), so the bare rescue must come last or every vacuity
      # becomes an error.
      def one(assertion, waive, around, subject)
        return Result.build(assertion: assertion, status: :waived) if waived?(assertion, waive)

        invoke(assertion, around, subject)
        Result.build(assertion: assertion, status: :passed)
      rescue Vacuous => error
        Result.build(assertion: assertion, status: :vacuous, detail: error.reason)
      rescue Failure => error
        Result.build(assertion: assertion, status: :failed, detail: detail_for(error))
      rescue ::StandardError => error
        Result.build(assertion: assertion, status: :error,
                     detail: "#{error.class}: #{error.message}",)
      end

      def waived?(assertion, waive) = assertion.ids.intersect?(waive)

      def detail_for(error)
        "#{error.message} (expected #{error.expected.inspect}, got #{error.actual.inspect})"
      end

      # A FRESH subject per assertion: a fixture shared across a run is what made the conforming
      # executor double fail during this phase's own planning (testing/4ef070df).
      def invoke(assertion, around, subject)
        body = -> { assertion.call(subject.call) }
        around.nil? ? body.call : around.call(&body)
      end
    end
  end
end
