# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The body of gates:ledger_audit (phase 10, design addendum A11; P10-2 made mechanical).
#
# docs/deviations.md is the as-built audit of design section 10, and a register audited once
# drifts: a chapter entry gains an ID the row never lists, two rows swap, or a verdict row stops
# pointing at anything real. Three decidable assertions keep it tied to the chapter:
#
# 1. Row N carries chapter entry N's subject -- the register title, emphasis stripped, is a WORD
#    SUBSEQUENCE of the entry's bolded lead. Equality is the wrong test (the register's titles
#    are deliberately shorter); a subsequence is decidable and a renamed or swapped entry still
#    breaks it.
# 2. Row N's `IDs touched` column, every range expanded, EQUALS the ID set extracted from entry
#    N's text. That is what makes phase 10's count of 124 reproducible from the tree.
# 3. A row whose status is anything but `design only -- not yet built` cites at least one
#    `gems/...` path that exists, every `gems/...` path it cites exists, and every `Dexpace::`
#    constant it names resolves. A row citing only `docs/...` fails: a design document is never
#    evidence.
#
# Every path is joined to `root` -- never read relative to the process CWD, which is the defect
# phase 9 shipped and repaired as P9-27: with DEXPACE_GATE_ROOT pointed at a fixture, a
# CWD-relative read opens the real repository's files and the gate can never be shown to reject
# its fixture.
#
# Assertion 3 needs the gems LOADED to resolve a constant; the rake task requires them and the
# resolver reads the running process. `const_get(name, false)` reaches a private_constant too, so
# a row naming one passes -- the rule is that the name is real, not that it is public.
module LedgerAudit
  PREFIXES = %w[SEAM HTTP IO BODY CTX PIPE RECOV RETRY REDIR AUTH PAGE SSE SERDE OBS CFG
                TRANSPORT ASYNC XCUT NFR].freeze
  CHAPTER = "docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md"
  REGISTER = "docs/deviations.md"
  UNBUILT = "design only — not yet built"
  ENTRY = /^(\d+)\.\s+\*\*(.+?)\*\*(.*?)(?=^\d+\.\s+\*\*|^Two things that are deliberately)/m
  RANGE = /\b([A-Z]+)-(\d+)\s*[–—]\s*([A-Z]+)-(\d+)\b/
  SINGLE = /\b([A-Z]+)-(\d+)\b/
  CITED_PATH = %r{gems/[\w./-]+}
  CONSTANT = /\bDexpace(?:::[A-Z]\w*)+/

  # Resolves a `Dexpace::A::B` path against the running process. A NameError anywhere on the
  # path (including an unloaded root) is "not defined".
  DEFAULT_RESOLVE = lambda do |path|
    path.split("::").reduce(::Object) { |scope, segment| scope.const_get(segment, false) }
    true
  rescue ::NameError
    false
  end

  class << self
    # @param root [String] the workspace every relative path is joined to
    # @param resolve [#call] answers whether a `Dexpace::` constant path is defined
    # @return [Array<String>] one line per offence
    def offences(root:, chapter: CHAPTER, register: REGISTER, resolve: DEFAULT_RESOLVE)
      entries = chapter_entries(File.read(File.join(root, chapter)))
      rows = register_rows(File.read(File.join(root, register)))
      count(rows, entries) + entries.zip(rows).each_with_index.flat_map do |(entry, row), index|
        row.nil? ? [] : check(index + 1, entry, row, root, resolve)
      end
    end

    # Every canonical ID in the text, each `A-n–A-m` range expanded. Public because the
    # checklist's own row count is read through it.
    def ids_in(text)
      plain = text.gsub(/[`*]/, "")
      (ranged(plain) + singles(plain)).uniq.sort
    end

    private

    def count(rows, entries)
      return [] if rows.size == entries.size

      ["row count #{rows.size} != chapter entry count #{entries.size}"]
    end

    def check(number, entry, row, root, resolve) # rubocop:disable Metrics/ParameterLists -- the module keeps no state (`class << self`), so the per-run root and resolver are threaded to every row check rather than held
      drift(number, entry, row) + evidence(number, row[:status], root, resolve)
    end

    def ranged(plain)
      plain.scan(RANGE).flat_map do |first, low, last, high|
        next [] unless first == last && PREFIXES.include?(first)

        (low.to_i..high.to_i).map { |number| "#{first}-#{number}" }
      end
    end

    def singles(plain)
      plain.scan(SINGLE).filter_map do |prefix, number|
        "#{prefix}-#{number}" if PREFIXES.include?(prefix)
      end
    end

    # Each entry is "N. **Subject.** ..." up to the next "N. **" or the closing note.
    def chapter_entries(text)
      text.scan(ENTRY).map do |_number, subject, body|
        { subject: normalise(subject), ids: ids_in(subject + body) }
      end
    end

    def register_rows(text)
      text.lines.grep(/^\|\s*\d+\s*\|/).map do |line|
        cells = line.split("|").map(&:strip)
        { subject: normalise(cells[2].to_s), ids: ids_in(cells[3].to_s), status: cells[4].to_s }
      end
    end

    # Assertions 1 and 2.
    def drift(number, entry, row)
      out = []
      unless subsequence?(row[:subject], entry[:subject])
        out << "row #{number} subject drifted from entry #{number}"
      end
      missing = entry[:ids] - row[:ids]
      extra = row[:ids] - entry[:ids]
      unless missing.empty?
        out << "row #{number} ID set differs: chapter-only #{missing.join(", ")}"
      end
      out << "row #{number} ID set differs: row-only #{extra.join(", ")}" unless extra.empty?
      out
    end

    # Assertion 3, for a row that carries a verdict.
    def evidence(number, status, root, resolve)
      return [] if status.include?(UNBUILT)

      paths = status.scan(CITED_PATH).map { |path| path.chomp(".") }
      real = paths.select { |path| File.exist?(File.join(root, path)) }
      if real.empty?
        return ["row #{number} carries a verdict and no resolvable as-built evidence (P10-2)"]
      end

      (paths - real).map { |path| "row #{number} cites #{path}, which does not exist" } +
        undefined(number, status, resolve)
    end

    def undefined(number, status, resolve)
      status.scan(CONSTANT).uniq.reject { |constant| resolve.call(constant) }
        .map { |constant| "row #{number} names #{constant}, which is not defined" }
    end

    def normalise(text) = text.gsub(/[`*]/, "").downcase.gsub(/[^a-z0-9 ]/, " ").split.join(" ")

    # A register title is shorter than the chapter's sentence, so equality is the wrong test; a
    # word subsequence is decidable and a renamed entry still breaks it.
    def subsequence?(short, long)
      words = long.split
      short.split.all? do |word|
        index = words.index(word)
        index && (words = words.drop(index + 1))
      end
    end
  end
end
