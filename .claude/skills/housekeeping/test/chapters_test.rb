# frozen_string_literal: true

# SPDX-License-Identifier: MIT
# .claude/skills/housekeeping/test/chapters_test.rb
#
# The probe's ninth check, `chapters` (phase 10's plan, Task 7). Measured over docs/ on
# 2026-09-25: the clause-scoped form fires on exactly the true positives, and the two blind spots
# are asserted here so the check never claims to have seen what it did not. The two
# phase-8 governing-documents lines it was designed against were corrected on 2026-09-13, so they
# live on as committed regression fixtures -- a check whose only evidence is a live defect loses
# its evidence the moment the defect is fixed.

require 'minitest/autorun'

require_relative '../probe'
require_relative 'fixture'

class ChaptersTest < Minitest::Test
  Fixture = Housekeeping::Fixture
  Chapters = Housekeeping::Checks::Chapters

  FIXTURES = File.expand_path('fixtures/chapters', __dir__)
  # Chapter 03 as the spec carries it, trimmed to the SEAM IDs that matter: 13, 15 and 22 are not
  # in it (02 carries SEAM-13; appendix C alone carries 15 and 22).
  CHAPTER_03 = "# 3\n\nSEAM-11 SEAM-12 SEAM-14 SEAM-16 SEAM-17 SEAM-24 SEAM-25 SEAM-29 SEAM-30\n"
  CHAPTER_02 = "# 2\n\nSEAM-13 SEAM-29\n"

  def run_over(document)
    overrides = {
      'docs/product-spec/03-pluggable-seams-and-extension-model.md' => CHAPTER_03,
      'docs/product-spec/02-architectural-principles.md' => CHAPTER_02,
      'docs/work/mvp/x-design.md' => document
    }
    Fixture.with(overrides: overrides) do |root|
      Housekeeping::Probe.new(Housekeeping::Repo.new(root), only: ['chapters']).run
    end
  end

  def ids(findings) = findings.map { |finding| finding.message[/SEAM-\d+/] }.sort

  def test_a_governing_documents_list_naming_an_appendix_c_only_id_is_a_finding
    findings = run_over("`docs/product-spec/03-pluggable-seams-and-extension-model.md` for `SEAM-11`, `SEAM-15`.\n")

    assert_equal %w[SEAM-15], ids(findings)
  end

  def test_prose_whose_subject_is_the_absence_is_not_a_finding
    assert_empty run_over(
      "`docs/product-spec/03-pluggable-seams-and-extension-model.md` carries 22 of the 30 IDs; " \
      "`SEAM-15` and `SEAM-22` appear nowhere in the specification's prose.\n"
    )
  end

  def test_a_clause_boundary_reassigns_the_chapter
    findings = run_over("`docs/product-spec/03-pluggable-seams-and-extension-model.md` for `SEAM-11`; " \
                        "`docs/product-spec/02-architectural-principles.md` for `SEAM-13`.\n")

    assert_empty findings
  end

  # 8a's design :67, verbatim: the backticked range is what hid SEAM-13 from a pattern written for
  # bare text, and with the range read all three wrong IDs are found.
  def test_the_phase8a_pre_correction_line_fires_on_all_three_wrong_ids
    findings = run_over(File.read(File.join(FIXTURES, 'phase8a_design_67_pre_correction.md')))

    assert_equal %w[SEAM-13 SEAM-15 SEAM-22], ids(findings)
  end

  # 8c's design :69-70, verbatim: SEAM-13 is on the chapter's own line and is found; SEAM-15 is
  # too. A clause continued onto the NEXT line would be the stated blind spot -- see below.
  def test_the_phase8c_pre_correction_line_fires_on_both_wrong_ids
    findings = run_over(File.read(File.join(FIXTURES, 'phase8c_design_69_pre_correction.md')))

    assert_equal %w[SEAM-13 SEAM-15], ids(findings)
  end

  def test_a_clause_continued_onto_the_next_line_is_a_stated_blind_spot
    findings = run_over("- `docs/product-spec/03-pluggable-seams-and-extension-model.md` for\n  `SEAM-15`.\n")

    assert_empty findings
    assert_includes Chapters::GAPS, :continued_clause
  end

  def test_the_range_vocabulary_tolerates_backticks_and_a_bare_upper_bound
    assert_equal [%w[03-x.md SEAM-11], %w[03-x.md SEAM-12], %w[03-x.md SEAM-13]],
                 Chapters.pairs('docs/product-spec/03-x.md for `SEAM-11`–`SEAM-13`').first(3)
    assert_equal 3, Chapters.pairs('docs/product-spec/03-x.md for SEAM-11–13').size
  end

  # Phase 10's review round 0 (R0-8): "appears in" was listed as a negation, which silenced the
  # usual positive attribution. It is a FORWARD binding now: the IDs before it belong to the
  # chapter after it, so a wrong one fires and a right one does not.
  def test_an_appears_in_attribution_binds_forward_and_fires_when_wrong
    wrong = "`SEAM-15` appears in `docs/product-spec/03-pluggable-seams-and-extension-model.md`.\n"
    right = "`SEAM-11` appears in `docs/product-spec/03-pluggable-seams-and-extension-model.md`.\n"

    assert_equal %w[SEAM-15], ids(run_over(wrong))
    assert_empty run_over(right)
  end

  # The phase-5 segmentation design's :538-539 shape, the line the negation entry was hiding: a
  # second run followed by "appears in" and a chapter on the NEXT line must not bind backward to
  # the first run's chapter (40 false fires under the backward rule).
  def test_a_second_appears_in_run_does_not_bind_backward
    document = "every one of `SEAM-11`–`SEAM-12` appears in\n" \
               "`docs/product-spec/03-pluggable-seams-and-extension-model.md` and every one of `SEAM-13` appears in\n" \
               "`docs/product-spec/02-architectural-principles.md`.\n"

    assert_empty run_over(document)
    assert_equal [%w[03-x.md SEAM-11]], Chapters.pairs('`SEAM-11` appears in docs/product-spec/03-x.md')
  end

  # Phase 10's review round 1 (R1-4): the forward binding matched "appear in" inside a negative
  # sentence, so a correct statement that an ID is ABSENT from a chapter fired as a wrong
  # attribution. Each spelling of the negated verb is a negation, not a binding. Round 2 (R2-2)
  # added the two it still bound forward: 'never appears in' and "doesn't appear in".
  def test_a_negated_appears_in_is_not_an_attribution
    ['does not appear in', 'do not appear in', 'did not appear in', 'never appears in',
     "doesn't appear in", "don't appear in", 'appears nowhere in'].each do |verb|
      document = "`SEAM-15` #{verb} `docs/product-spec/03-pluggable-seams-and-extension-model.md`.\n"

      assert_empty run_over(document), verb
    end
  end

  def test_appendix_c_is_never_a_target
    document = "`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for `SEAM-99`.\n"

    assert_empty run_over(document)
  end
end
