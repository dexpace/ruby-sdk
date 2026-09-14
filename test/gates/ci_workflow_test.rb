# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/versions"
require "yaml"

# NFR-17 (blocking in CI, not only locally) and NFR-10 (the matrix runs the REAL suite --
# TargetRubyVersion catches syntax, not stdlib availability, design §9.2).
class CiWorkflowTest < GateCase
  WORKFLOW = YAML.load_file(File.join(ROOT, ".github/workflows/ci.yml"))

  test "the matrix is exactly what VERSIONS declares" do
    matrix = WORKFLOW.dig("jobs", "test", "strategy", "matrix", "ruby")

    assert_equal(DexpaceVersions.ruby_matrix, matrix.map(&:to_s))
  end

  test "the matrix job runs the real gem suites, not a syntax check" do
    steps = WORKFLOW.dig("jobs", "test", "steps").map { |step| step["run"].to_s }.join("\n")

    assert_includes(steps, "rake test:gems")
    refute_includes(steps, "ruby -c")
  end

  test "the interpreter-independent suites and the cop suite run once, in the gates job" do
    gates = WORKFLOW.dig("jobs", "gates", "steps").map { |step| step["run"].to_s }.join("\n")
    matrix = WORKFLOW.dig("jobs", "test", "steps").map { |step| step["run"].to_s }.join("\n")

    assert_includes(gates, "rake test:gates")
    assert_includes(gates, "rake cops:test")
    refute_includes(matrix, "rake test:gates")
  end

  test "every gate in DEFAULT_GATES appears in exactly one CI job" do
    listed = `bundle exec rake -s gates:list`.split("\n")
    steps = WORKFLOW.fetch("jobs").values
      .flat_map { |job| job.fetch("steps") }
      .map { |step| step["run"].to_s }.join("\n")

    listed.each { |gate| assert_includes(steps, "rake #{gate}", gate) }
  end

  test "the three zero-dependency checks run on every matrix row" do
    steps = WORKFLOW.dig("jobs", "test", "steps").map { |step| step["run"].to_s }.join("\n")

    %w[gates:gemspec_audit gates:require_allowlist gates:clean_bundle].each do |gate|
      assert_includes(steps, gate)
    end
  end

  test "no row is allowed to fail" do
    WORKFLOW.fetch("jobs").each_value do |job|
      refute(job["continue-on-error"], "a gate that may fail is not a gate (NFR-17)")
    end
  end

  test "bundler caching is off, because there is no committed lockfile" do
    uses = WORKFLOW.fetch("jobs").values.flat_map { |job| job.fetch("steps") }
      .select { |step| step["uses"].to_s.include?("setup-ruby") }

    refute_empty(uses)
    uses.each { |step| refute(step.dig("with", "bundler-cache")) }
  end

  test "the gates job checks out full history, because gates:sig_diff reads tags" do
    checkout = WORKFLOW.dig("jobs", "gates", "steps")
      .find { |step| step["uses"].to_s.include?("actions/checkout") }

    assert_equal(0, checkout.dig("with", "fetch-depth"))
  end
end
