# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Two Markdown files compared: the specification's appendix B, and the coverage map beside the
# conformance gem. Plain text operations -- no AST, no gem.
#
# The map is phase 9's answer to "appendix B is phase 9's scope" without re-owning seven phases'
# work: one row per checklist item, naming the section, the item's requirement IDs, the suite or
# test file that covers it, and a status. A `by reference` row proves an ID is CLAIMED and a file
# EXISTS, never that the behaviour is tested (design P9-7), and the map says so in its own voice.
module AppendixB
  # CLAUDE.md's nineteen prefixes, in appendix-C order. A bare /[A-Z]+-\d+/ matches `ISO-8601`,
  # which appears in B.3's real text, and RFC-3986-shaped tokens elsewhere.
  PREFIXES = %w[SEAM HTTP IO BODY CTX PIPE RECOV RETRY REDIR AUTH PAGE SSE SERDE OBS CFG
                TRANSPORT ASYNC XCUT NFR].freeze
  ID = /\b(?:#{PREFIXES.join("|")})-\d+\b/
  # `- [ ]` and never `- [`: an item ticked by hand would otherwise vanish from the count.
  ITEM = "- [ ]"
  SECTION = /^### (B\.\d)/
  # The statuses a row may carry. `suite` is an assertion in this gem; `by reference` is another
  # gem's test file; `restated per §9.3` is an item the design restates; `scoped out` is an item
  # or clause this port declines with its reason in the row.
  STATUSES = ["suite", "by reference", "restated per §9.3", "scoped out", "unmapped"].freeze

  extend self

  # @param text [String]
  # @return [Array<String>] every requirement ID in it, deduplicated, in order
  def ids_in(text) = text.scan(ID).uniq

  # @param path [String] the specification's appendix B
  # @return [Integer] how many checklist items it holds
  def spec_item_count(path) = ::File.readlines(path).count { |line| line.start_with?(ITEM) }

  # @param path [String] the specification's appendix B
  # @return [Hash{String => Integer}] items per section
  def spec_counts_by_section(path)
    spec_items(path).each_with_object({}) do |(section, _, _), counts|
      counts[section] = counts.fetch(section, 0) + 1
    end
  end

  # `[[section, 1-based item number, item line]]` in the specification's order.
  #
  # @param path [String]
  # @return [Array<Array(String, Integer, String)>]
  def spec_items(path)
    section = nil
    ::File.readlines(path).each_with_object([]) do |line, items|
      if (match = SECTION.match(line))
        section = match[1]
      elsif line.start_with?(ITEM) && section
        items << [section, items.count { |(existing, _, _)| existing == section } + 1, line]
      end
    end
  end

  # The map's own table: `| section | item | ids | evidence | status |`.
  #
  # @param path [String] the coverage map
  # @return [Array<Hash>] one row per line, parsed
  def rows(path)
    ::File.readlines(path).filter_map do |line|
      next unless line.start_with?("| B.")

      cells = line.split("|").map(&:strip).reject(&:empty?)
      next if cells.size < 5

      { section: cells[0], item: cells[1], ids: ids_in(cells[2]),
        evidence: evidence(cells[3]), status: cells[4], }
    end
  end

  # @param path [String] the coverage map
  # @return [Hash{String => Integer}] rows per section
  def counts_by_section(path)
    rows(path).each_with_object({}) do |row, counts|
      counts[row[:section]] = counts.fetch(row[:section], 0) + 1
    end
  end

  # One row per specification item, in the specification's order, with the ID column parsed from
  # the item's own text. An item's evidence and status are HAND-WRITTEN and carried over from the
  # existing map; an item with neither is emitted `unmapped` with `unmapped` in the evidence
  # column -- not a path, so the map's own evidence check names it until someone writes the row.
  #
  # @param spec_path [String] the specification's appendix B
  # @param map_path [String] the coverage map, read BEFORE it is written
  # @return [String] the whole map
  def generate(spec_path, map_path)
    hand = hand_written(map_path)
    body = spec_items(spec_path).map do |(section, item, text)|
      evidence, status = hand.fetch([section, item.to_s], %w[unmapped unmapped])
      "| #{section} | #{item} | #{ids_in(text).join(", ")} | #{evidence} | #{status} |"
    end
    "#{header(map_path)}#{body.join("\n")}\n"
  end

  # The map's hand-written evidence and status per row, keyed by `[section, item]`. Read BEFORE
  # the caller writes the file, which is why the CLI takes the map's PATH rather than redirecting
  # stdout into it: a shell redirect truncates the file before the generator reads it.
  def hand_written(path)
    return {} unless ::File.exist?(path)

    rows(path).to_h do |row|
      [[row[:section], row[:item]], [row[:evidence] || "--", row[:status]]]
    end
  end

  # Everything above the table, preserved verbatim from the existing map so the preamble is
  # hand-written prose the generator never rewrites.
  def header(path)
    return DEFAULT_HEADER unless ::File.exist?(path)

    lines = ::File.readlines(path)
    cut = lines.index { |line| line.start_with?("| B.") }
    cut.nil? ? DEFAULT_HEADER : lines.take(cut).join
  end

  DEFAULT_HEADER = <<~MARKDOWN
    # Appendix B coverage map

    | Section | Item | IDs | Evidence | Status |
    |---|---|---|---|---|
  MARKDOWN

  private

  def evidence(cell)
    stripped = cell.delete("`")
    stripped == "--" ? nil : stripped
  end
end

if $PROGRAM_NAME == __FILE__
  spec = ARGV.fetch(0, "docs/product-spec/appendix-b-conformance-test-checklist.md")
  map = ARGV.fetch(1, "gems/dexpace-conformance/APPENDIX_B.md")
  File.write(map, AppendixB.generate(spec, map))
  puts "wrote #{map} (#{AppendixB.spec_item_count(spec)} rows)"
end
