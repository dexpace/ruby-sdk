# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# Design §9's documentation row, and styleguide 14.1: YARD on every public class and method.
# YARD ships no failure mode for undocumented objects, so the gate is `yard stats --list-undoc`
# with a non-zero undocumented count failing the task.
class YardTest < GateCase
  test "the repository documents every public object" do
    out, err, status = rake("yard")

    assert_predicate(status, :success?, err)
    assert_includes(out, "100.00% documented")
  end

  test "an undocumented public method fails the gate" do
    out = yard_stats("test/fixtures/gates/yard/undocumented.rb")

    refute_includes(out, "100.00% documented")
    assert_includes(out, "Undocumented Objects")
  end

  # The SPDX header this repository mandates on line 2 is absorbed by YARD as a docstring for
  # whatever declaration follows it, so the FIRST declaration in every file is counted as
  # documented whether or not anyone documented it. Measured on 0.9.45: with only
  # `# frozen_string_literal: true` -- a magic comment YARD skips -- the module reports
  # `0.00% documented`; adding `# SPDX-License-Identifier: MIT` reports it documented. Under
  # Style/ClassAndModuleChildren: nested that first declaration is always the outer `module
  # Dexpace`, never the type the file is about, so the gate is narrowed rather than defeated.
  # Pin it here so phase 1 meets a recorded behaviour instead of a surprise.
  test "the SPDX header documents only the outermost declaration, never a nested one" do
    out = yard_stats("test/fixtures/gates/yard/header_only.rb")

    refute_includes(out, "100.00% documented")
    assert_includes(out, "HeaderOnlyFixture::Nested")
  end

  test "the gate task goes red on the fixture tree" do
    _out, err, status = rake("yard", "DEXPACE_YARD_FILES" => "test/fixtures/gates/yard/*.rb")

    refute_predicate(status, :success?)
    assert_includes(err, "undocumented public objects")
  end

  private

  # Bypasses .yardopts, whose `--exclude test/` would drop the fixture and report the gems.
  def yard_stats(file)
    `bundle exec yard stats --list-undoc --no-yardopts --no-save #{file} 2>&1`
  end
end
