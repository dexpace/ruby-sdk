# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# gates:sole_parse (phase 10's plan, Task 6; design addendum A9). NFR-6: AstScan.parse's $VERBOSE
# window is the one route to RubyVM::AbstractSyntaxTree.parse_file; NFR-17: blocking, and proven
# red through its rake task against a fixture workspace.
require_relative "../support/gate_case"
require_relative "../support/gate_warning_capture"
require_relative "../../tools/sole_parse"

class SoleParseTest < GateCase
  include GateWarningCapture

  FIXTURES = File.expand_path("../fixtures/gates/sole_parse", __dir__)

  def fixture(name) = File.join(FIXTURES, name)

  test "a direct parse_file outside AstScan.parse is an offence, carrying its path argument" do
    found = SoleParse.offences_in(fixture("direct.rb"))

    assert_equal(1, found.size)
    assert_includes(found.first, "direct.rb:6")
  end

  test "the reflective spellings on the same receiver are offences, by Symbol and by String" do
    assert_equal(2, SoleParse.offences_in(fixture("reflective.rb")).size)
  end

  test "Prism.parse_file is not the hazard and is not reported" do
    assert_empty(SoleParse.offences_in(fixture("prism.rb")))
  end

  test "the owner METHOD is exempt, a nested block included; the file's other methods are not" do
    found = SoleParse.offences_in(fixture("owner.rb"), owner: true)

    assert_equal(1, found.size)
    assert_includes(found.first, "owner.rb:10")
  end

  test "every allowlist entry names a live file the scan still reports, with a reason" do
    SoleParse::ALLOWED.each do |path, reason|
      refute_empty(reason.strip)
      refute_empty(SoleParse.offences_in(File.join(ROOT, path)),
                   "#{path} is allowlisted and silences nothing",)
    end
  end

  test "the repository's tooling has exactly one parse_file, AstScan.parse's own" do
    assert_empty(SoleParse.offences(root: ROOT))
  end

  # The window the gate protects, still working: a bare parse of the unused-binding fixture warns
  # and the same parse through AstScan.parse does not. Under -w only (SuiteRunner appends it).
  test "AstScan.parse's window still suppresses what a bare parse emits" do
    unless $VERBOSE
      skip("the fixture's diagnostic is only emitted under -w; SuiteRunner appends it")
    end

    path = File.expand_path("../fixtures/gates/invariants/warns_unused.rb", __dir__)

    assert_equal(1, capture_warnings { ::RubyVM::AbstractSyntaxTree.send(:parse_file, path) }.size)
    assert_empty(capture_warnings { AstScan.parse(path) })
  end

  test "the rake task, pointed at a failing fixture workspace, exits non-zero naming the file" do
    assert_gate_rejects("gates:sole_parse", { "DEXPACE_GATE_ROOT" => fixture("workspace") },
                        "tools/x.rb:6: RubyVM::AbstractSyntaxTree.parse_file outside AstScan",)
  end
end
