# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# NFR-17: the gates are blocking and automatic, and the default rake task is what makes them so.
# The second case -- that every listed name is a real, separately invocable task -- was added
# once the last gate existed (phase 0's plan Task 19): asserted earlier it would have left `rake
# test:gates` red for seventeen tasks, and a suite that is expected to be red is a suite nobody
# reads.
class DefaultTaskTest < GateCase
  # Phase 0's seventeen, 7b's gates:serde_boundary and phase 9's three repository-wide invariant
  # scans -- twenty-one. A gate outside DEFAULT_GATES is off `task default:` and therefore
  # advisory, which NFR-17 forbids, so this list is what makes the count a fact.
  EXPECTED = %w[
    rubocop cops:test rbs:validate steep test:gems test:gates gates:gemspec_audit
    gates:require_allowlist gates:serde_boundary gates:cause_walk gates:bounded_map
    gates:seam_names gates:clean_bundle gates:rbs_surface
    gates:sig_diff gates:surface_snapshot gates:single_instance gates:versions
    gates:reproducible yard bundler_audit
  ].freeze

  # The COUNT, asserted against the repository and not only against the literal above: the three
  # tasks phase 9 added are gates because they are in `task default:`, and a count read off
  # EXPECTED alone would still pass if all three left DEFAULT_GATES together.
  test "there are twenty-one gates, and every one of them is blocking" do
    prerequisites = `bundle exec rake -s -P`.split("\n").drop_while { |l| l != "rake default" }
      .drop(1).take_while { |line| line.start_with?("    ") }.map(&:strip)

    assert_equal(21, EXPECTED.size)
    assert_equal(21, prerequisites.size, "the default task's prerequisite count drifted")
    %w[gates:cause_walk gates:bounded_map gates:seam_names].each do |gate|
      assert_includes(prerequisites, gate, "#{gate} is not blocking")
    end
  end

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
