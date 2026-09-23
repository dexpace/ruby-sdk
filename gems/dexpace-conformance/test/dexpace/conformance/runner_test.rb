# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# The five result statuses of 8a's assertion protocol, decided in ONE place for every suite phase
# 9 adds. NFR-17; design P9-10.
class DexpaceConformanceRunnerTest < DexpaceTestCase
  Runner = Dexpace::Conformance::Runner

  def assertion(ids, name, &body)
    Dexpace::Conformance::Assertion.build(ids: ids, name: name, body: body)
  end

  test "an assertion that returns cleanly is passed" do
    report = Runner.run([assertion(["X-1"], "clean") { |_s| nil }]) { :subject }

    assert_equal(:passed, report.results.first.status)
  end

  test "a Failure is failed and its expected and actual both reach the detail" do
    body = lambda do |_s|
      raise Dexpace::Conformance::Failure.new("no", expected: 1, actual: 2,
                                                    requirement_ids: ["X-1"],)
    end
    report = Runner.run([assertion(["X-1"], "fails", &body)]) { :subject }

    assert_equal(:failed, report.results.first.status)
    assert_includes(report.results.first.detail, "expected 1, got 2")
  end

  test "a Vacuous is vacuous and carries its reason, never passed" do
    body = ->(_s) { raise Dexpace::Conformance::Vacuous, "no adapter has this path" }
    report = Runner.run([assertion(["X-1"], "vacuous", &body)]) { :subject }

    assert_equal(:vacuous, report.results.first.status)
    assert_equal("no adapter has this path", report.results.first.detail)
  end

  # The rescue order is load-bearing: Vacuous and Failure are both ::StandardError descendants, so
  # a bare rescue placed above either turns a vacuity into an :error.
  test "any other StandardError is errored, never silently a failure and never a vacuity" do
    report = Runner.run([assertion(["X-1"], "boom") { |_s| raise TypeError, "nope" }]) { :subject }

    assert_equal(:error, report.results.first.status)
    assert_includes(report.results.first.detail, "TypeError")
  end

  test "a waiver matches by requirement id and never by assertion name" do
    by_id = Runner.run([assertion(%w[X-1 X-2], "waived") { |_s| raise "never reached" }],
                       waive: ["X-2"],) { :subject }
    by_name = Runner.run([assertion(%w[X-1 X-2], "waived") { |_s| raise "reached" }],
                         waive: ["waived"],) { :subject }

    assert_equal(:waived, by_id.results.first.status)
    assert_equal(:error, by_name.results.first.status, "a name is not a requirement id")
  end

  # testing/4ef070df applied to a subject the RUNNER constructs: a fixture shared across a run is
  # what made this phase's own conforming executor double fail during planning.
  test "the subject block is called once per assertion, never shared across the run" do
    built = 0
    Runner.run([assertion(["X-1"], "a") { |_s| nil }, assertion(["X-2"], "b") { |_s| nil }]) do
      built += 1
      :subject
    end

    assert_equal(2, built)
  end

  test "an around wrapper wraps every invocation and the assertion still runs inside it" do
    order = []
    around = lambda do |&blk|
      order << :before
      blk.call
      order << :after
    end
    Runner.run([assertion(["X-1"], "a") { |_s| order << :body }], around: around) { :subject }

    assert_equal(%i[before body after], order)
  end

  test "the preamble, the acceptances and the would-fail declarations reach the Report" do
    report = Runner.run([assertion(["ASYNC-3"], "a") { |_s| nil }],
                        waive: ["ASYNC-3"], preamble: "reads a socket",
                        accepted_vacuous: { "ASYNC-4" => "design §10.5" },
                        would_fail: ["ASYNC-3"],) { :subject }

    assert_equal("reads a socket", report.preamble)
    assert_equal({ "ASYNC-4" => "design §10.5" }, report.accepted_vacuous)
    assert_includes(report.to_s, "waived (would fail): ASYNC-3")
  end
end
