# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The appendix-B coverage map. Design R7, P9-7, P9-8.
#
# Three decidable checks; the map's own preamble states what they do NOT establish -- that a
# referenced test asserts the behaviour its item describes -- because nothing mechanical can,
# short of re-implementing the assertion.
require_relative "../support/gate_case"
require_relative "../../tools/appendix_b"

class AppendixBTest < GateCase
  SPEC = File.join(ROOT, "docs/product-spec/appendix-b-conformance-test-checklist.md")
  MAP = File.join(ROOT, "gems/dexpace-conformance/APPENDIX_B.md")
  SECTIONS = { "B.1" => 10, "B.2" => 6, "B.3" => 7, "B.4" => 8, "B.5" => 6,
               "B.6" => 5, "B.7" => 6, "B.8" => 6, "B.9" => 7, }.freeze

  test "the map carries exactly one row per checklist item" do
    assert_equal(61, AppendixB.spec_item_count(SPEC))
    assert_equal(AppendixB.spec_item_count(SPEC), AppendixB.rows(MAP).size)
  end

  test "the per-section counts match the specification's own" do
    assert_equal(SECTIONS, AppendixB.spec_counts_by_section(SPEC))
    assert_equal(SECTIONS, AppendixB.counts_by_section(MAP))
  end

  # Strictly stronger than "every row names at least one ID", and it makes the distinct-ID
  # coverage check hold BY CONSTRUCTION: the union of 61 equal sets is appendix B's own 276.
  test "every row's ID column equals the set parsed from that item's own text" do
    spec = AppendixB.spec_items(SPEC).to_h { |(s, i, t)| [[s, i.to_s], AppendixB.ids_in(t).sort] }
    wrong = AppendixB.rows(MAP).reject do |row|
      spec.fetch([row[:section], row[:item]], nil) == row[:ids].sort
    end

    assert_empty(wrong.map { |row| "#{row[:section]} item #{row[:item]}" })
  end

  test "the 61 items name 276 distinct ids, none repeated across items, at most 12 in one" do
    sets = AppendixB.spec_items(SPEC).map { |(_, _, text)| AppendixB.ids_in(text) }

    assert_equal(276, sets.flatten.uniq.size)
    assert_equal(sets.flatten.size, sets.flatten.uniq.size, "no ID appears in two items")
    assert_equal(12, sets.map(&:size).max)
  end

  test "the id scanner does not mistake ISO-8601 or an RFC number for a requirement id" do
    assert_empty(AppendixB.ids_in("ISO-8601 dates round-trip and RFC-3986 encoding applies"))
    assert_equal(%w[SERDE-24], AppendixB.ids_in("ISO-8601 dates round-trip (SERDE-24)"))
  end

  test "every row's evidence path exists on disk" do
    missing = AppendixB.rows(MAP).map { |row| row[:evidence] }
      .reject { |path| path.nil? || File.exist?(File.join(ROOT, path)) }

    assert_empty(missing)
  end

  test "every row carries one of the statuses the map's own table names" do
    unknown = AppendixB.rows(MAP).map { |row| row[:status] }.uniq - AppendixB::STATUSES

    assert_empty(unknown)
  end

  # `- [ ]` and never `- [`: an item ticked by hand would otherwise vanish from the count, which is
  # the drift this check exists to catch.
  test "the item scanner counts unticked boxes only" do
    ticked = "- [x] a ticked item (PAGE-1)\n- [ ] an unticked one (PAGE-2)\n"
    path = File.join(Dir.mktmpdir("appendix-b"), "spec.md")
    File.write(path, "### B.1 Pagination\n\n#{ticked}")

    assert_equal(1, AppendixB.spec_item_count(path))
  end

  # Regenerating must be a no-op on a current map: the generator carries every hand-written
  # evidence and status cell over, so a regeneration never silently rewrites a judgement.
  test "regenerating the map from the specification reproduces it byte for byte" do
    assert_equal(File.read(MAP), AppendixB.generate(SPEC, MAP))
  end
end
