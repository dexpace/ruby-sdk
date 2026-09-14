# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "minitest/autorun"
require "fileutils"
require "open3"
require "tempfile"
require "tmpdir"
require_relative "../../tools/interpreter"

# The base for a repository gate test. A gate is proven by running it as a subprocess against a
# fixture and reading its exit status, not by calling into its internals -- a gate that only
# passes when driven by its own test is a gate CI has never actually run.
class GateCase < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def self.test(name, &)
    define_method("test_: #{name}", &)
  end

  # Runs a rake task and returns [stdout, stderr, status]. Through `bundle exec`, because the
  # gates load rbs, steep and rubocop from the bundle and a bare `rake` would resolve whatever
  # happens to be installed globally -- and through the running interpreter's own `bundle`, so
  # the gate under test runs on the Ruby running its test.
  def rake(task, env = {})
    Open3.capture3(env, Interpreter.executable("bundle"), "exec", "rake", "-s", task, chdir: ROOT)
  end

  def assert_gate_rejects(task, fixture_env, message_fragment)
    _out, err, status = rake(task, fixture_env)

    refute_predicate(status, :success?, "#{task} accepted #{fixture_env.inspect}")
    assert_includes(err, message_fragment)
  end
end
