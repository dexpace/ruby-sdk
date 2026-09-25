# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# gates:ledger_audit keeps docs/deviations.md tied to design section 10 (phase 10's plan, Task 2;
# design addendum A11; P10-2). NFR-17: the gate is proven against deliberately failing fixtures and
# through its RAKE TASK pointed at a fixture workspace, not only by calling the module.
require_relative "../support/gate_case"
require_relative "../../tools/ledger_audit"

class LedgerAuditTest < GateCase
  FIXTURES = File.expand_path("../fixtures/gates/ledger", __dir__)
  RESOLVE = ->(constant) { constant == "Dexpace::Probe" }

  def offences(register)
    LedgerAudit.offences(root: FIXTURES, chapter: "chapter.md", register: register,
                         resolve: RESOLVE,)
  end

  test "a conforming register -- one verdict row with real evidence, one unbuilt row -- is clean" do
    assert_empty(offences("register_ok.md"))
  end

  test "a row whose ID set is narrower than its chapter entry is an offence naming the ID" do
    found = offences("register_wrong_ids.md")

    assert_equal(["row 1 ID set differs: chapter-only IO-6"], found)
  end

  test "a row whose ID set is WIDER than its entry is an offence: equality, not a subset" do
    assert_equal(["row 2 ID set differs: row-only BODY-9"], offences("register_extra_ids.md"))
  end

  test "two swapped rows drift on subject and on IDs, both rows named" do
    found = offences("register_swapped.md").join("\n")

    assert_includes(found, "row 1 subject drifted")
    assert_includes(found, "row 2 subject drifted")
  end

  test "a verdict row citing only a design document has no as-built evidence (P10-2)" do
    assert_equal(["row 1 carries a verdict and no resolvable as-built evidence (P10-2)"],
                 offences("register_docs_only.md"),)
  end

  test "a verdict row naming a constant that does not exist is an offence" do
    assert_equal(["row 1 names Dexpace::Completer, which is not defined"],
                 offences("register_undefined.md"),)
  end

  test "the default resolver reaches a private constant and refuses an unknown one" do
    require "dexpace"

    assert(LedgerAudit::DEFAULT_RESOLVE.call("Dexpace::BoundedMap"))
    assert(LedgerAudit::DEFAULT_RESOLVE.call("Dexpace::Async::Completer"))
    refute(LedgerAudit::DEFAULT_RESOLVE.call("Dexpace::Completer"))
  end

  test "an A–B range in either document expands, and an unknown prefix is not an ID" do
    assert_equal(%w[IO-1 IO-2 IO-3 SEAM-29],
                 LedgerAudit.ids_in("**IO-1**–**IO-3**, ISO-8601, `SEAM-29`"),)
  end

  # The live register against the frozen chapter: 19 rows, 123 distinct IDs (124 with the closing
  # note's RETRY-28, which is not a row), every verdict's evidence resolvable.
  test "the live register matches design section 10" do
    %w[dexpace dexpace/transport/net_http dexpace/serde/json dexpace/async/thread
       dexpace/conformance].each { |feature| require feature }

    assert_empty(LedgerAudit.offences(root: ROOT))
  end

  test "the rake task, pointed at a failing fixture workspace, exits non-zero with the offence" do
    workspace = { "DEXPACE_GATE_ROOT" => File.join(FIXTURES, "workspace") }

    assert_gate_rejects("gates:ledger_audit", workspace,
                        "row 1 ID set differs: chapter-only IO-6",)
  end
end
