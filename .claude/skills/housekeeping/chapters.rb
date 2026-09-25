# frozen_string_literal: true

# SPDX-License-Identifier: MIT
# .claude/skills/housekeeping/chapters.rb
#
# The probe's ninth check, `chapters` (phase 10's plan, Task 7; design R10 and addendum A10).
#
# A document asserting that a requirement ID is stated in a named `docs/product-spec/` chapter,
# where that chapter does not carry the ID. The unit is a CLAUSE, not a line: "A.md for X, Y;
# B.md for Z" pairs every ID with every chapter under a same-line rule, which is why a naive rule
# fires 23 times for 4 real defects (phase 10's Fact 6). So a line is split at `;`, each ID is
# associated with the NEAREST PRECEDING chapter reference in its clause -- or, for an ID run
# followed by "appears in", with the chapter that phrase introduces -- a range is expanded
# whether or not its endpoints are backticked, and a line whose two-line window carries a negation
# -- prose whose own subject is that the ID is NOT in that chapter -- is skipped. Appendix C
# carries every ID and can never be wrong about one, so it is exempt as a target.
#
# Two stated blind spots, printed in the check's own `GAPS` so a reader is never told the check
# saw something it did not: `continued_clause` (a chapter reference on the PRECEDING line is
# invisible to a line-oriented scanner -- 8c's design :70, `SEAM-15`, was caught by hand), and
# `dynamic_chapter_path` (a chapter named by an ellipsis such as `13-…md`, or by a variable,
# resolves to no file and is skipped).

module Housekeeping
  module Checks
    # 9. A requirement ID attributed to a spec chapter that does not carry it.
    class Chapters < Check
      NAME = 'chapters'
      PREFIXES = %w[SEAM HTTP IO BODY CTX PIPE RECOV RETRY REDIR AUTH PAGE SSE SERDE OBS CFG
                    TRANSPORT ASYNC XCUT NFR].freeze
      ID = /\b(#{PREFIXES.join('|')})-(\d+)\b/
      # `SEAM-11`–`SEAM-15`, SEAM-11–SEAM-15, SEAM-11–15: backticks tolerated on either end,
      # which is what hid 8a's `SEAM-13` from a range pattern written for bare text.
      RANGE = /`?\b(#{PREFIXES.join('|')})-(\d+)`?\s*[–—]\s*`?(?:\1-)?(\d+)\b`?/
      CHAPTER = %r{docs/product-spec/(\d\d-[a-z0-9-]+\.md)}
      BOUNDARY = ';'
      # Prose whose subject is that the ID is NOT in the named chapter, over the line and the
      # next one, because such a sentence routinely crosses a line break.
      # A union of plain phrases, never an /x pattern: under /x the spaces inside a phrase are
      # stripped and "appears nowhere" silently becomes "appearsnowhere" (found writing this).
      NEGATION = Regexp.union(
        'appear nowhere', 'appears nowhere', 'harvested nowhere', 'appear in no', 'appears in no',
        'appendix C is their only', 'appendix C is its only', 'appendix C alone',
        'does not carry', 'do not carry', 'carries neither', 'carries none', 'carries no ',
        'carry none', 'no prose chapter', 'appendix-C row', 'unfollowable', 'from appendix C',
        'read out of appendix C', 'read out of **appendix C', 'neither ID appears', 'is not in',
        'are not in', 'not stated in', 'only normative statement', 'only prose home',
        'not appear in', 'does not appear', 'do not appear', 'never appear', "n't appear"
      ).then { |union| Regexp.new(union.source, Regexp::IGNORECASE) }
      # "X appears in <chapter>": the one verb that puts the chapter AFTER the IDs it is about.
      # An ID run followed by it binds FORWARD, to the chapter the verb introduces, instead of to
      # the nearest preceding one. Phase 10's review round 0 (R0-8) found the phrase listed as a
      # negation, which silenced this -- the usual positive attribution -- to hide one line of the
      # phase-5 segmentation design (:538-539) whose second run bound backward to the first
      # run's chapter; binding forward is what that line needed.
      FORWARD = /\bappears?\s+in\b/i
      EXEMPT_TARGET = 'appendix-c-consolidated-normative-requirement-index.md'
      # Documents that quote the pre-correction attributions ON PURPOSE, as the record of the
      # defect this check exists for: phase 10's own design, plan and checklist.
      EXEMPT_DOCUMENTS = %r{\Adocs/work/mvp/phase10/}
      SCANNED = ['docs'].freeze
      SKIPPED = %r{\Adocs/(?:product-spec|knowledge/harvested)/}
      GAPS = %i[continued_clause dynamic_chapter_path].freeze

      def run(repo)
        carried = chapter_ids(repo)
        documents(repo).flat_map { |path| scan(path, repo.read(path).lines, carried) }
      end

      # The pairs a single line asserts, [chapter, id], in clause order. Public so a test can
      # read the clause scoping directly.
      def self.pairs(line)
        line.split(BOUNDARY).flat_map { |clause| clause_pairs(clause) }
      end

      # A run of consecutive IDs binds to the nearest preceding chapter, unless the run is
      # followed by FORWARD, when it binds to the chapter immediately after the verb (or to
      # nothing, when the chapter is on the next line: the continued-clause gap).
      def self.clause_pairs(clause)
        list = tokens(clause)
        chapter = nil
        pairs = []
        index = 0
        while index < list.length
          kind, value = list[index]
          if kind == :chapter
            chapter = value
            index += 1
          elsif kind == :forward
            index += 1
          else
            run_end = index
            run_end += 1 while run_end < list.length && list[run_end][0] == :id
            target = run_target(list, run_end, chapter)
            list[index...run_end].each { |_kind, id| pairs << [target, id] } if target
            index = run_end
          end
        end
        pairs
      end

      def self.run_target(list, after, chapter)
        return chapter unless list.dig(after, 0) == :forward

        list.dig(after + 1, 0) == :chapter ? list.dig(after + 1, 1) : nil
      end

      # Chapters and IDs in textual order, every range expanded in place.
      def self.tokens(clause)
        found = []
        clause.scan(CHAPTER) { found << [Regexp.last_match.begin(0), :chapter, Regexp.last_match[1]] }
        clause.scan(FORWARD) { found << [Regexp.last_match.begin(0), :forward, nil] }
        covered = []
        clause.scan(RANGE) do
          match = Regexp.last_match
          covered << (match.begin(0)...match.end(0))
          (match[2].to_i..match[3].to_i).each { |n| found << [match.begin(0), :id, "#{match[1]}-#{n}"] }
        end
        clause.scan(ID) do
          match = Regexp.last_match
          next if covered.any? { |span| span.cover?(match.begin(0)) }

          found << [match.begin(0), :id, "#{match[1]}-#{match[2]}"]
        end
        found.sort_by.with_index { |(position, _kind, _value), index| [position, index] }
             .map { |_position, kind, value| [kind, value] }
      end

      private

      def chapter_ids(repo)
        repo.tracked('docs/product-spec/*.md').to_h do |path|
          [File.basename(path), repo.read(path).scan(ID).map { |prefix, n| "#{prefix}-#{n}" }.uniq]
        end
      end

      def documents(repo)
        repo.tracked(*SCANNED).select { |path| path.end_with?('.md') }
            .reject { |path| SKIPPED.match?(path) || EXEMPT_DOCUMENTS.match?(path) }
      end

      def scan(path, lines, carried)
        lines.each_with_index.flat_map do |line, index|
          next [] if NEGATION.match?(line + lines.fetch(index + 1, ''))

          self.class.pairs(line).filter_map do |chapter, id|
            next if chapter == EXEMPT_TARGET || !carried.key?(chapter) || carried[chapter].include?(id)

            act(path, index + 1, "attributes #{id} to docs/product-spec/#{chapter}, which does not " \
                                 "carry it (gaps: #{GAPS.join(', ')})")
          end
        end
      end
    end
  end
end
