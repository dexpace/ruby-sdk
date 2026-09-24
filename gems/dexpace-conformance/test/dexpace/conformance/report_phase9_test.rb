# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# Phase 9's additions to 8a's Report: the aggregate caller 8a deferred #to_h for, and the
# MUST-level vacuity blocker design R3's absent-artifact rule is only safe because of.
# NFR-4, NFR-17; ASYNC-3, ASYNC-4, XCUT-12, XCUT-22.
#
# 8a's own report_test.rb is left byte-identical: its two pinned renderings -- `waived: D (checks
# D)` and `waived: TRANSPORT-28` -- are what keep `waived (would fail)` a DRIVER's declaration
# rather than a blanket rename that would make the report lie about 8c's two waivers.
class DexpaceConformanceReportPhase9Test < DexpaceTestCase
  Report = Dexpace::Conformance::Report

  def result(ids, status, detail: nil)
    assertion = Dexpace::Conformance::Assertion.build(ids: ids, name: ids.join("+"),
                                                      body: ->(_s) {},)
    Dexpace::Conformance::Result.build(assertion: assertion, status: status, detail: detail)
  end

  test "merge flattens many reports into one passed? over the whole run" do
    merged = Report.merge([Report.new([result(["XCUT-15"], :passed)]),
                           Report.new([result(["NFR-1"], :failed)]),])

    assert_equal(2, merged.results.size)
    refute_predicate(merged, :passed?)
  end

  test "merge inherits every suite's acceptances and would-fail declarations" do
    one = Report.new([result(["ASYNC-4"], :vacuous)], accepted_vacuous: { "ASYNC-4" => "§10.5" })
    two = Report.new([result(["ASYNC-3"], :waived)], would_fail: ["ASYNC-3"])
    merged = Report.merge([one, two])

    assert_predicate(merged, :passed?)
    assert_includes(merged.to_s, "accepted MUST-level vacuity (design-sanctioned): ASYNC-4: §10.5")
    assert_includes(merged.to_s, "waived (would fail): ASYNC-3")
  end

  test "to_h carries one row per result with its ids, status and detail" do
    report = Report.new([result(%w[XCUT-13 XCUT-22], :passed)])

    assert_equal(1, report.to_h[:passed])
    assert_equal(%w[XCUT-13 XCUT-22], report.to_h[:results].first[:ids])
  end

  test "a SHOULD-level vacuity is recorded and does not fail the run" do
    report = Report.new([result(["XCUT-12"], :vacuous, detail: "no reactor")])

    assert_predicate(report, :passed?)
    assert_empty(report.blocking_vacuities)
    assert_includes(report.to_s, "vacuous: XCUT-12: no reactor")
  end

  # The failing fixture the blocker exists for: an unbuilt MUST is not a green run (design R3).
  test "an un-waived, un-accepted MUST-level vacuity is a report blocker and fails the run" do
    report = Report.new([result(["ASYNC-4"], :vacuous, detail: "no interrupt path")])

    refute_predicate(report, :passed?)
    assert_equal(["ASYNC-4"], report.blocking_vacuities.flat_map { |r| r.assertion.ids })
    assert_includes(report.to_s, "MUST-level vacuity (report blocker): ASYNC-4")
    assert_includes(report.to_s, "REPORT BLOCKED: 1 un-waived MUST-level vacuity (design R3)")
  end

  test "an accepted MUST-level vacuity carries its citation, renders apart, and does not block" do
    report = Report.new([result(["ASYNC-4"], :vacuous)],
                        accepted_vacuous: { "ASYNC-4" => "design §10.5: no interrupt ordering" },)

    assert_predicate(report, :passed?)
    assert_equal(1, report.accepted_vacuities.size)
    assert_includes(report.to_s,
                    "accepted MUST-level vacuity (design-sanctioned): ASYNC-4: design §10.5",)
    assert_equal(["ASYNC-4"], report.to_h[:accepted_vacuities].map { |row| row[:ids].first })
  end

  # Decision: acceptance is `all?` over the assertion's MUST-level IDs, never `any?`. An
  # acceptance of one ID must not silence a co-carried MUST -- that is the gap staying invisible,
  # and it is the exact shape ExecutorSuite's borrowed_executor_survives carries (XCUT-22 AND
  # ASYNC-15, both MUST in appendix C).
  test "an acceptance naming one of two MUST ids still blocks, because accepted? is all?" do
    partial = Report.new([result(%w[XCUT-22 ASYNC-15], :vacuous, detail: "no borrowing entry")],
                         accepted_vacuous: { "XCUT-22" => "8b files none" },)
    both = Report.new([result(%w[XCUT-22 ASYNC-15], :vacuous, detail: "no borrowing entry")],
                      accepted_vacuous: { "XCUT-22" => "8b files none",
                                          "ASYNC-15" => "clause (b) has no subject here", },)

    refute_predicate(partial, :passed?)
    assert_predicate(both, :passed?)
  end

  test "an acceptance with no citation is refused at construction, not rendered as a blank" do
    assert_raises(::ArgumentError) do
      Report.new([result(["ASYNC-4"], :vacuous)], accepted_vacuous: { "ASYNC-4" => "  " })
    end
  end

  test "a waived result is never counted as a vacuity, accepted or blocking" do
    report = Report.new([result(["ASYNC-3"], :waived)], would_fail: ["ASYNC-3"])

    assert_predicate(report, :passed?)
    assert_empty(report.blocking_vacuities)
    assert_empty(report.accepted_vacuities)
    assert_includes(report.to_s, "waived (would fail): ASYNC-3")
  end

  # 8a's rendering is the DEFAULT and stays the default: a waiver that means "this adapter does
  # not support the property" (8c's TRANSPORT-14, TRANSPORT-27) must not read as "this would
  # fail". The driver declares which is which.
  test "a waiver the driver did not declare would-fail keeps 8a's plain rendering" do
    report = Report.new([result(["TRANSPORT-14"], :waived)])

    assert_includes(report.to_s, "waived: TRANSPORT-14")
    refute_includes(report.to_s, "would fail")
  end

  test "an id appendix C does not hold is reported rather than silently never blocking" do
    report = Report.new([result(["XCUT-99"], :vacuous), result(["XCUT-4"], :passed)])

    assert_equal(["XCUT-99"], report.unknown_ids)
    assert_predicate(report, :passed?, "an unknown id never blocks; unknown_ids is what shows it")
  end

  test "the preamble still prints first, ahead of every phase-9 section" do
    report = Report.new([result(["ASYNC-4"], :vacuous)], preamble: "reads a socket")

    assert_operator(report.to_s, :start_with?, "reads a socket\n")
    assert_operator(report.to_s, :end_with?, "vacuity (design R3)")
  end
end
