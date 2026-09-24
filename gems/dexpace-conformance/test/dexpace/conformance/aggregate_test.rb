# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# One report over every suite, and the preamble docs/first-release.md's standing blocker requires.
# NFR-4, NFR-17; ASYNC-3, ASYNC-4.
class DexpaceConformanceAggregateTest < DexpaceTestCase
  Aggregate = Dexpace::Conformance::Aggregate

  def report(*rows)
    results = rows.map do |(ids, name, status)|
      assertion = Dexpace::Conformance::Assertion.build(ids: ids, name: name, body: ->(_s) {})
      Dexpace::Conformance::Result.build(assertion: assertion, status: status)
    end
    Dexpace::Conformance::Report.new(results)
  end

  test "merging two suites keeps one passed? over the whole run" do
    merged = Aggregate.run([report([["XCUT-15"], "immutable", :passed]),
                            report([["NFR-1"], "zero deps", :failed]),])

    assert_equal(2, merged.results.size)
    refute_predicate(merged, :passed?)
  end

  test "vacuous and waived are counted apart; a SHOULD-level vacuity does not fail the run" do
    merged = Aggregate.run([report([["XCUT-12"], "wait-free reads", :vacuous],
                                   [["ASYNC-3"], "two-mode cancellation", :waived],)])

    assert_predicate(merged, :passed?)
    assert_equal(1, merged.vacuous.size)
    assert_equal(1, merged.waived.size)
  end

  test "an un-accepted MUST-level vacuity blocks the aggregate, and an accepted one does not" do
    reports = [report([["ASYNC-4"], "ordered interrupt", :vacuous])]

    refute_predicate(Aggregate.run(reports), :passed?)
    assert_predicate(Aggregate.run(reports, accepted_vacuous: { "ASYNC-4" => "design §10.5" }),
                     :passed?,)
  end

  test "the rendered report states what a green run does not prove" do
    rendered = Aggregate.render(Aggregate.run([report([["XCUT-15"], "immutable", :passed])]))

    assert_includes(rendered, "It does not prove")
    assert_includes(rendered, "by reference")
    assert_includes(rendered, "design R3")
  end

  test "the rendered report names the blocker section when one stands" do
    rendered = Aggregate.render(Aggregate.run([report([["ASYNC-4"], "ordered interrupt",
                                                       :vacuous,])]))

    assert_includes(rendered, "MUST-level vacuity (report blocker): ASYNC-4")
    assert_includes(rendered, "REPORT BLOCKED")
  end

  test "an aggregate-level would-fail declaration reaches every suite's waivers" do
    rendered = Aggregate.render(
      Aggregate.run([report([["ASYNC-3"], "two-mode cancellation", :waived])],
                    would_fail: ["ASYNC-3"],),
    )

    assert_includes(rendered, "waived (would fail): ASYNC-3")
  end

  # Design R7: the generated half of the coverage map reads each suite's DECLARED assertions. A
  # Report holds only the ones that RAN, so reading one would let a suite skipped in a given
  # invocation silently shorten the map.
  test "by_requirement_id reads each suite's DECLARED assertions, not a report's results" do
    map = Aggregate.by_requirement_id([Dexpace::Conformance::InvariantSuite])

    assert_equal(2, map["XCUT-13"].size, "XCUT-13 carries two assertions, one per clause")
    assert_equal(%i[not_run not_run], map["XCUT-13"].map { |row| row[:status] })
  end

  test "by_requirement_id marks an assertion with no result :not_run rather than omitting it" do
    ran = Dexpace::Conformance::InvariantSuite.run(core: Module.new)
    map = Aggregate.by_requirement_id([Dexpace::Conformance::InvariantSuite], statuses: ran)

    refute_includes(map.values.flatten.map { |row| row[:status] }, :not_run)
  end

  test "each row names both the suite and the assertion, which are different things" do
    map = Aggregate.by_requirement_id([Dexpace::Conformance::InvariantSuite])
    row = map["XCUT-15"].first

    assert_equal("Dexpace::Conformance::InvariantSuite", row[:suite])
    refute_equal(row[:suite], row[:assertion])
  end

  test "every suite phase 9 ships contributes to the map" do
    suites = [Dexpace::Conformance::InvariantSuite, Dexpace::Conformance::PackagingSuite,
              Dexpace::Conformance::CodecSuite, Dexpace::Conformance::ExecutorSuite,
              Dexpace::Conformance::TransportSuite,]
    map = Aggregate.by_requirement_id(suites)

    assert_empty(map.keys.reject { |id| Dexpace::Conformance::Levels.known?(id) },
                 "every id any suite declares is one appendix C knows",)
    assert_operator(map.size, :>, 40)
  end
end
