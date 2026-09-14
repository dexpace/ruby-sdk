# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "open3"
require_relative "interpreter"

# NFR-5 / NFR-6: runs a set of Minitest files in ONE subprocess, warnings fatal.
#
# One subprocess so SimpleCov produces one aggregate number, which is what NFR-5 asks for
# ("computed across the library units"). The subprocess is `ruby -w -W:deprecated`, and its
# stderr is scanned for `warning:` afterwards: the Warning.warn override in
# test/support/dexpace_test_case.rb catches a warning raised while a test runs, but nothing
# emitted at require time, before that file has loaded -- a method redefinition in an entry
# file is exactly that case. NFR-6 needs both halves.
module SuiteRunner
  extend self

  # Raised when the suite fails or warns; the rake task turns it into a non-zero exit.
  class Failure < StandardError; end

  # `files` are paths relative to `chdir`; `libs` go on the load path; `coverage:` loads the
  # SimpleCov bootstrap, test/support/coverage.rb, ahead of every file.
  def run(files, libs, coverage:, chdir: Dir.pwd, out: $stdout, err: $stderr)
    stdout, stderr, status = Open3.capture3(
      environment(coverage), *command(files, libs, coverage), chdir: chdir,
    )
    out.puts(stdout)
    err.puts(stderr) unless stderr.empty?

    warnings = stderr.lines.grep(/warning:/)
    raise Failure, "NFR-6: #{warnings.length} warning(s) at load time:\n#{warnings.join}" \
      if warnings.any?
    raise Failure, "#{files.length} file(s): test failures (exit #{status.exitstatus})" \
      unless status.success?

    status
  end

  private

  # RUBYOPT is APPENDED, never replaced: bundler puts `-rbundler/setup` there, and overwriting it
  # unbundles the subprocess -- which would quietly undo `bundle exec`.
  def environment(coverage)
    env = { "RUBYOPT" => "#{ENV.fetch("RUBYOPT", nil)} -w -W:deprecated".strip }
    env["COVERAGE"] = "1" if coverage
    env
  end

  def command(files, libs, coverage)
    [
      Interpreter.ruby, *libs.map { |dir| "-I#{dir}" }, *(coverage ? ["-rsupport/coverage"] : []),
      *files.flat_map { |file| ["-r", "./#{file}"] }, "-e", "",
    ]
  end
end
