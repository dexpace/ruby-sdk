# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/versions"

# NFR-14: dependency versions, tool versions and project coordinates live in one source of
# truth. This suite is about the reader; `rake gates:versions` (Task 19) is about the consumers.
class VersionsReaderTest < GateCase
  test "reads every gem version" do
    assert_equal("0.0.0", DexpaceVersions.gem_version("dexpace-core"))
    assert_equal("0.0.0", DexpaceVersions.gem_version("dexpace-conformance"))
  end

  test "reads the runtime floor, the development pin and the matrix" do
    assert_equal("3.2", DexpaceVersions.ruby_floor)
    assert_equal("4.0.6", DexpaceVersions.ruby_dev)
    assert_equal(%w[3.2 3.3 3.4 4.0], DexpaceVersions.ruby_matrix)
  end

  test "derives the adapter constraint on core from the core version" do
    assert_equal("~> 0.0", DexpaceVersions.core_constraint)
  end

  test "raises a named error for a record that is not there" do
    error = assert_raises(KeyError) { DexpaceVersions.gem_version("dexpace-nonexistent") }

    assert_includes(error.message, "dexpace-nonexistent")
  end

  test "raises on a malformed line rather than skipping it" do
    Tempfile.create("VERSIONS") do |file|
      file.write("gem dexpace-core\n")
      file.flush
      error = assert_raises(ArgumentError) { DexpaceVersions.records(file.path) }

      assert_includes(error.message, "<kind> <name> <value>")
    end
  end
end
