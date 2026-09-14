# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require "yaml"

# The RuboCop baseline is fixed by docs/knowledge/notes/tooling-and-quality-gates.md, key
# tooling-and-quality-gates/cb18f9bd. These assertions are that note, mechanised.
class RubocopConfigTest < GateCase
  CONFIG = YAML.load_file(File.join(ROOT, ".rubocop.yml"))

  test "loads rubocop-minitest and rubocop-performance as plugins and nothing else" do
    assert_equal(%w[rubocop-minitest rubocop-performance], CONFIG.fetch("plugins").sort)
  end

  test "does not inherit rubocop-airbnb in any form" do
    refute(CONFIG.key?("inherit_gem"), "rubocop-airbnb's inherit_gem incantation does not run")
  end

  test "targets the declared Ruby floor, not the development pin" do
    assert_equal("3.2", CONFIG.dig("AllCops", "TargetRubyVersion").to_s)
  end

  test "enables new cops rather than silently skipping them" do
    assert_equal("enable", CONFIG.dig("AllCops", "NewCops"))
  end

  test "transcribes the styleguide's hand-named settings" do
    assert_equal("double_quotes", CONFIG.dig("Style/StringLiterals", "EnforcedStyle"))
    assert_equal(100, CONFIG.dig("Layout/LineLength", "Max"))
    assert_equal(25, CONFIG.dig("Metrics/MethodLength", "Max"))
    assert_equal(4, CONFIG.dig("Metrics/ParameterLists", "Max"))
    assert_equal(3, CONFIG.dig("Metrics/BlockNesting", "Max"))
    assert_equal("leading", CONFIG.dig("Layout/DotPosition", "EnforcedStyle"))
    assert_equal("nested", CONFIG.dig("Style/ClassAndModuleChildren", "EnforcedStyle"))
  end

  test "the gate itself runs at --fail-level=convention with no autocorrection" do
    body = File.read(File.join(ROOT, "tasks/quality.rake"))
    # The `rubocop:fix` convenience in the same file is allowed to autocorrect; the gate is not.
    gate = body[/^task :rubocop do.*?^end$/m]

    refute_nil(gate, "tasks/quality.rake defines no `task :rubocop`")
    assert_includes(gate, "--fail-level=convention")
    refute_includes(gate, "--autocorrect")
  end
end
