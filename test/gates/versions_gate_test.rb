# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/versions_gate"

# NFR-14. A single source of truth that nothing checks is a file, not a source of truth: Ruby
# gives no one file that a gemspec, a Gemfile, .ruby-version and a YAML matrix can all read, so
# the single source is enforced rather than shared.
class VersionsGateTest < GateCase
  FIXTURES = File.join(ROOT, "test/fixtures/gates/versions")

  test "the real repository agrees with VERSIONS everywhere" do
    assert_empty(VersionsGate.violations(ROOT))
  end

  test "rejects a .ruby-version that disagrees with the dev pin" do
    found = VersionsGate.violations(File.join(FIXTURES, "stale_pin"))

    assert_includes(found.join("\n"), ".ruby-version")
  end

  test "rejects a CI matrix row that VERSIONS does not declare" do
    found = VersionsGate.violations(File.join(FIXTURES, "dropped_matrix_row"))

    assert_includes(found.join("\n"), "matrix")
  end

  test "rejects a version.rb literal ahead of VERSIONS" do
    found = VersionsGate.violations(File.join(FIXTURES, "ahead_literal"))

    assert_includes(found.join("\n"), "VERSION")
  end

  # As in the gemspec audit: a gemspec that raises while it evaluates loads as nil, and the
  # finding names it rather than dereferencing nil.
  test "names a gemspec that does not load instead of dereferencing nil" do
    found = nil
    capture_io { found = VersionsGate.violations(File.join(FIXTURES, "gemspec_does_not_load")) }

    assert_equal(["dexpace-core.gemspec did not load."], found)
  end

  test "each fixture is wrong in exactly one place" do
    %w[stale_pin dropped_matrix_row ahead_literal gemspec_does_not_load].each do |fixture|
      found = nil
      capture_io { found = VersionsGate.violations(File.join(FIXTURES, fixture)) }

      assert_equal(1, found.length, "#{fixture}: #{found.inspect}")
    end
  end

  test "the gate task goes red on a fixture and passes on the repository" do
    stale_pin = File.join(FIXTURES, "stale_pin")
    _out, err, status = rake("gates:versions", "DEXPACE_GATE_ROOT" => stale_pin)

    refute_predicate(status, :success?)
    assert_includes(err, "NFR-14")

    out, err, status = rake("gates:versions")

    assert_predicate(status, :success?, err)
    assert_includes(out, "all agree with VERSIONS")
  end
end
