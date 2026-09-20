# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# Design §9.3: "the gap stays visible rather than disappearing into a restated item" -- so #to_s
# names every waived ID on every run, not only on failure; and P8-9's two fixture omissions are
# printed in the preamble on every run, so a green run is never read as more than it proves.
class DexpaceConformanceReportTest < DexpaceTestCase
  Report = Dexpace::Conformance::Report

  def assertion(ids)
    Dexpace::Conformance::Assertion.build(ids: ids, name: "checks #{ids.join(",")}", body: ->(_) {})
  end

  def result(ids, status, detail: nil)
    Dexpace::Conformance::Result.build(assertion: assertion(ids), status: status, detail: detail)
  end

  test "partitions results by status and #to_s names every waived id and every failure" do
    report = Report.new([
                          result(["A"], :passed),
                          result(["B"], :failed, detail: "boom"),
                          result(["C"], :vacuous, detail: "no antecedent"),
                          result(["D"], :waived),
                          result(["E"], :error, detail: "RuntimeError: oops"),
                        ])

    refute_predicate(report, :passed?)
    assert_equal(5, report.results.size)
    assert_predicate(report.results, :frozen?)
    assert_equal(["B"], report.failures.map { |r| r.assertion.ids }.flatten)
    assert_equal(["C"], report.vacuous.map { |r| r.assertion.ids }.flatten)
    assert_equal(["D"], report.waived.map { |r| r.assertion.ids }.flatten)
    assert_equal(["E"], report.errors.map { |r| r.assertion.ids }.flatten)
    text = report.to_s

    assert_includes(text, "1 passed, 1 failed, 1 vacuous, 1 waived, 1 errored")
    assert_includes(text, "waived: D (checks D)")
    assert_includes(text, "FAILED: B: boom")
    assert_includes(text, "ERROR: E: RuntimeError: oops")
    assert_includes(text, "vacuous: C: no antecedent")
  end

  test "passed? is true only when nothing failed or errored; vacuous and waived do not fail it" do
    clean = Report.new([result(["A"], :passed), result(["B"], :vacuous), result(["C"], :waived)])

    assert_predicate(clean, :passed?)
    refute_predicate(Report.new([result(["E"], :error)]), :passed?)
    assert_predicate(Report.new([]), :passed?)
  end

  test "a waived id is named on every run, a passing one included" do
    report = Report.new([result(["A"], :passed), result(["TRANSPORT-28"], :waived)])

    assert_predicate(report, :passed?)
    assert_includes(report.to_s, "waived: TRANSPORT-28")
  end

  test "P8-9: the preamble names what the fixture does not exercise, on every run" do
    report = Report.new([result(["A"], :passed)], preamble: "plaintext only; no connect timeout")

    assert_equal("plaintext only; no connect timeout", report.preamble)
    assert_operator(report.to_s, :start_with?, "plaintext only; no connect timeout\n")
    assert_nil(Report.new([]).preamble)
  end
end
