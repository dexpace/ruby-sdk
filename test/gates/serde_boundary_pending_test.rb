# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SSE-37's handed-forward clause, which 7b could not assert while phase 7 was still running: "the
# repository-wide check that its PENDING list is empty by the end of phase 7". Phase 9 asserts it,
# and the `list:` keyword below is the one-line widening of 7b's tool that lets this test drive a
# NON-empty list -- `PENDING` is a frozen constant, and reading it directly gave the fixture
# nothing to inject.
require_relative "../support/gate_case"
require_relative "../../tools/serde_boundary"

class SerdeBoundaryPendingTest < GateCase
  FIXTURES = File.join(ROOT, "test/fixtures/gates/serde_boundary")
  PENDING_FIXTURE = [["gems/dexpace-core/lib/dexpace/nowhere/**/*.rb",
                      "a layer built beside a gate that predates it",]].freeze

  test "the committed PENDING list is empty, which is what SSE-37 handed forward" do
    assert_empty(SerdeBoundary::PENDING)
    assert_empty(SerdeBoundary.pending(ROOT))
  end

  # The failing state: with one pending row the gate must abort, naming the row and its reason.
  test "a non-empty PENDING list produces the abort message the task aborts on" do
    rows = SerdeBoundary.pending(ROOT, list: PENDING_FIXTURE)

    assert_equal(1, rows.size)
    assert_equal(0, rows.first.last, "the fixture glob matches nothing, which is why it pends")
    message = SerdeBoundary.pending_message(rows)

    assert_includes(message, "SerdeBoundary::PENDING is not empty")
    assert_includes(message, "a layer built beside a gate that predates it")
    assert_includes(message, "SSE-37")
  end

  test "the gate itself is green and says so" do
    out, _err, status = rake("gates:serde_boundary")

    assert_predicate(status, :success?)
    assert_includes(out, "the pending list is empty (SSE-37)")
  end

  # The TASK's abort branch, not just the message builder's. Without this, deleting the abort line
  # outright left every test here green -- measured by mutation in this phase. PENDING is a frozen
  # constant with no root or env that can make the task see a non-empty one, so the fixture is a
  # RUBYOPT prelude that prepends one row onto `.pending`, which is this repository's
  # deliberately-failing-fixture rule applied to the one gate clause that had no other route in.
  test "the task aborts on a non-empty pending list, naming the row" do
    probe = File.join(FIXTURES, "pending_probe.rb")
    _out, err, status = rake("gates:serde_boundary", "RUBYOPT" => "-r#{probe}")

    refute_predicate(status, :success?, "the task accepted a non-empty PENDING list")
    assert_includes(err, "SerdeBoundary::PENDING is not empty")
    assert_includes(err, "a fixture row, so the task's abort branch is driven")
  end
end
