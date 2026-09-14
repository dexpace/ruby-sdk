# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# NFR-17: the gates are blocking and automatic, and the default rake task is what makes them so.
# The second case -- that every listed name is a real, separately invocable task -- was added
# once the last gate existed (plan Task 19): asserted earlier it would have left `rake
# test:gates` red for seventeen tasks, and a suite that is expected to be red is a suite nobody
# reads.
class DefaultTaskTest < GateCase
  EXPECTED = %w[
    rubocop cops:test rbs:validate steep test:gems test:gates gates:gemspec_audit
    gates:require_allowlist gates:clean_bundle gates:rbs_surface gates:sig_diff
    gates:surface_snapshot gates:single_instance gates:versions gates:reproducible
    yard bundler_audit
  ].freeze

  test "the default task lists every gate, in the design's order" do
    listed = `bundle exec rake -s gates:list`.split("\n")

    assert_equal(EXPECTED, listed)
  end

  test "every listed gate is a real, separately invocable task" do
    known = `bundle exec rake -s -T -A`.scan(/^rake (\S+)/).flatten

    EXPECTED.each { |gate| assert_includes(known, gate) }
  end

  test "the default task depends on exactly the listed gates, in order" do
    prerequisites = `bundle exec rake -s -P`.split("\n").drop_while { |l| l != "rake default" }
      .drop(1).take_while { |line| line.start_with?("    ") }.map(&:strip)

    assert_equal(EXPECTED, prerequisites)
  end
end
