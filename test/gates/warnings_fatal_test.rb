# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/suite_runner"
require "stringio"

# NFR-6: warnings are errors, deprecations included. Two mechanisms, because each misses what
# the other catches -- the Warning.warn override cannot see a warning emitted at require time,
# before the helper installing it has loaded, and the stderr scan cannot name the test that
# warned. One fixture per half.
class WarningsFatalTest < GateCase
  LOAD_TIME = "test/fixtures/gates/warnings/before_override.rb"
  IN_PROCESS = "test/fixtures/gates/warnings/after_override.rb"

  test "a warning emitted before the override exists fails the suite through the stderr scan" do
    error = assert_raises(SuiteRunner::Failure) do
      SuiteRunner.run(
        [LOAD_TIME], %w[test], coverage: false, chdir: ROOT, out: StringIO.new, err: StringIO.new,
      )
    end

    assert_includes(error.message, "NFR-6")
    assert_includes(error.message, "method redefined")
  end

  test "a warning emitted after the override exists fails the test that triggered it" do
    _out, err, status = Open3.capture3(
      { "RUBYOPT" => "-w -W:deprecated" },
      "ruby", "-Itest", IN_PROCESS, chdir: ROOT,
    )

    refute_predicate(status, :success?)
    assert_includes(err, "warning treated as an error (NFR-6)")
    assert_includes(err, "method redefined")
  end

  test "a clean suite passes the runner" do
    SuiteRunner.run(
      ["test/fixtures/gates/warnings/clean.rb"], %w[test],
      coverage: false, chdir: ROOT, out: StringIO.new, err: StringIO.new,
    )
  end

  test "the runner scans subprocess stderr rather than trusting the exit status" do
    body = File.read(File.join(ROOT, "tools/suite_runner.rb"))

    assert_includes(body, "-W:deprecated")
    assert_includes(body, "warning:")
  end

  test "RUBYOPT is appended to, so bundler's -rbundler/setup survives" do
    body = File.read(File.join(ROOT, "tools/suite_runner.rb"))

    assert_includes(body, 'ENV.fetch("RUBYOPT", nil)')
  end

  test "both test tasks run through the runner" do
    body = File.read(File.join(ROOT, "tasks/quality.rake"))

    assert_includes(body, "SuiteRunner.run")
    assert_match(/task :gems do.*coverage: true/m, body)
    assert_match(/task :gates do.*coverage: false/m, body)
  end
end
