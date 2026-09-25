# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# gates:spdx_rbs (phase 10's plan, Task 5; design addendum A8). NFR-13's header on shipped
# signatures, NFR-3's declared-but-empty residue, NFR-17's blocking fixture.
require_relative "../support/gate_case"
require_relative "../../tools/spdx_rbs"

class SpdxRbsTest < GateCase
  FIXTURES = File.expand_path("../fixtures/gates/spdx_rbs", __dir__)

  def offences(name) = SpdxRbs.offences_in(File.join(FIXTURES, name))

  test "a signature without the header is an offence" do
    found = offences("missing_header.rbs")

    assert_equal(1, found.size)
    assert_includes(found.first, "SPDX-License-Identifier")
  end

  # PackagingSuite's spdx_header_coverage reads the first TWO lines, so it passes this file; the
  # gate is the stricter of the two on purpose -- line 1 is where NFR-13's header block starts.
  test "a header that is present but not on line 1 is an offence" do
    assert_includes(offences("header_on_line_three.rbs").first, "line 1 is not")
  end

  # rbs 4.2.0 returns [buffer, directives, declarations]; `.flatten.compact.empty?` keeps the Buffer
  # and is never true, so this is the test that pins the third element being read.
  test "a signature with no declarations is an offence" do
    assert_equal(["#{File.join(FIXTURES, "empty.rbs")}: declares nothing (NFR-3)"],
                 offences("empty.rbs"),)
  end

  test "the conforming fixture is clean" do
    assert_empty(offences("ok.rbs"))
  end

  test "every shipped signature in the six gems is clean" do
    assert_empty(SpdxRbs.offences(root: ROOT))
    assert_operator(Dir.glob(File.join(ROOT, SpdxRbs::GLOB)).size, :>=, 300)
  end

  test "the rake task, pointed at a failing fixture workspace, exits non-zero naming the file" do
    workspace = { "DEXPACE_GATE_ROOT" => File.join(FIXTURES, "workspace") }

    assert_gate_rejects("gates:spdx_rbs", workspace,
                        "gems/dexpace-probe/sig/dexpace/probe.rbs: line 1 is not",)
  end
end
