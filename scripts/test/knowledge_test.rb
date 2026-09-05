# frozen_string_literal: true
#
# SPDX-License-Identifier: MIT
# scripts/test/knowledge_test.rb
#
# Run with `ruby scripts/test/knowledge_test.rb` (or `ruby -Iscripts
# scripts/test/knowledge_test.rb`). Stdlib only: minitest ships with Ruby.
#
# Everything here runs against `fixtures/knowledge/`, a hand-written miniature
# repository root — five appendix-C rows, three harvested topics, one note, one
# phase document. The real corpus lives in a sibling SDK and is deliberately not
# copied here: a test that pins live counts fails on every harvest.

$LOAD_PATH.unshift(File.expand_path("..", __dir__))

require "minitest/autorun"
require "fileutils"
require "open3"
require "stringio"
require "tmpdir"
require "knowledge"
require "knowledge_drift"
require "verify_knowledge_structure"

module KnowledgeFixture
  ROOT = File.expand_path("fixtures/knowledge", __dir__)
  SCRIPTS = File.expand_path("..", __dir__)

  # Entry keys the fixture pins. A key digests the entry's text, so editing a
  # fixture bullet moves its key — and the note that cites one has to move with
  # it, which is exactly the discipline the real corpus enforces.
  RULE_HTTP_1 = "http-domain-model/03726362"
  RULE_HTTP_70 = "http-domain-model/a81d135f"
  ROLLUP_HTTP_2 = "http-domain-model/2fa7d6f2"
  RULE_PAGE_1 = "pagination/b895b9ab"
  REFERENCE_PAGE_2 = "pagination/c7904f61"

  def paths
    @paths ||= Knowledge::Paths.new(ROOT)
  end

  def appendix
    @appendix ||= Knowledge::AppendixC.load(paths)
  end

  def corpus
    @corpus ||= Knowledge::Corpus.load(paths, appendix.prefixes)
  end

  def entry(key)
    corpus.entries.find { |candidate| candidate.key == key } ||
      raise("no fixture entry with key #{key}")
  end

  def query(**options)
    words = options.delete(:words) || []
    Knowledge::Query.build(options, words, appendix, warn: StringIO.new)
  end

  def select(**options)
    matcher = query(**options)
    corpus.entries.select { |candidate| matcher.match?(candidate) }
  end

  # The CLI in process, so a test can read what it wrote and what it exited.
  def cli(*argv)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Knowledge::CLI.new(stdout: stdout, stderr: stderr).run(["--root", ROOT] + argv)
    [stdout.string, stderr.string, status]
  end
end

class CanonicalIdsTest < Minitest::Test
  include KnowledgeFixture

  def test_appendix_c_parses_id_level_and_subsystem
    assert_equal 9, appendix.size
    assert_equal "MUST", appendix["HTTP-1"].level
    assert_equal "SHOULD", appendix["HTTP-7"].level
    assert_equal "Core HTTP domain model", appendix["HTTP-70"].subsystem
  end

  def test_prefix_allowlist_is_derived_from_the_table
    assert_equal %w[HTTP PAGE SEAM], appendix.prefixes.to_a.sort
  end

  def test_allowlist_rejects_the_shapes_a_bare_regex_claims
    text = "Encode as UTF-8, hash with SHA-256, per RFC-3986 and ISO-8601, see HTTP-1."
    assert_equal ["HTTP-1"], Knowledge::Ids.extract(text, appendix.prefixes)
    %w[UTF SHA RFC ISO].each do |prefix|
      refute_includes appendix.prefixes, prefix
    end
  end

  def test_extraction_is_exact_token_so_http_7_does_not_match_http_70
    found = Knowledge::Ids.extract("Covers HTTP-70 but not the short one.", appendix.prefixes)
    assert_equal ["HTTP-70"], found
  end

  def test_extraction_de_duplicates_and_keeps_first_seen_order
    found = Knowledge::Ids.extract("PAGE-2 then HTTP-1 then PAGE-2 again.", appendix.prefixes)
    assert_equal ["PAGE-2", "HTTP-1"], found
  end

  def test_ids_sort_numerically_within_a_prefix
    assert_equal %w[HTTP-1 HTTP-2 HTTP-7 HTTP-70 PAGE-1],
                 Knowledge::Ids.sort(%w[PAGE-1 HTTP-70 HTTP-7 HTTP-2 HTTP-1])
  end

  def test_ids_compress_runs_into_ranges
    assert_equal "PAGE-1..4", Knowledge::Ids.compress(%w[PAGE-4 PAGE-1 PAGE-2 PAGE-3])
    assert_equal "HTTP-1 HTTP-2 PAGE-1", Knowledge::Ids.compress(%w[PAGE-1 HTTP-1 HTTP-2])
  end
end

class SubjectAndChapterTest < Minitest::Test
  include KnowledgeFixture

  def test_subsystem_and_owning_chapter_come_from_the_table_not_a_routing_map
    assert_equal "Core HTTP domain model", appendix.subsystem_for("HTTP")
    assert_equal "04-core-http-domain-model.md", appendix.chapter_for("HTTP")
    assert_equal "12-pagination.md", appendix.chapter_for("PAGE")
    # "Product vision, pluggable seams and extension model" -> chapter 03.
    assert_equal "03-pluggable-seams-and-extension-model.md", appendix.chapter_for("SEAM")
  end

  def test_levels_are_counted_per_prefix
    assert_equal({"MUST" => 3, "MAY" => 1}, appendix.levels_for("PAGE"))
  end
end

class SubLineTest < Minitest::Test
  def test_the_common_shape_is_role_source_confidence_sha
    parsed = Knowledge::SubLine.parse("spec · `docs/product-spec/04.md:9` · high · sha:abc123")
    assert_equal ["spec"], parsed.roles
    assert_equal ["docs/product-spec/04.md:9"], parsed.sources
    assert_equal "high", parsed.confidence
    assert_equal "abc123", parsed.sha
  end

  def test_a_conflicts_line_carries_two_role_source_pairs_and_no_sha
    parsed = Knowledge::SubLine.parse("design `a/b.md:1` · styleguide `/c/d.md:2` · unresolved 2026-01-01")
    assert_equal %w[design styleguide], parsed.roles
    assert_equal ["a/b.md:1", "/c/d.md:2"], parsed.sources
    assert_nil parsed.sha
    assert_equal "unresolved 2026-01-01", parsed.confidence
  end
end

class ParsingTest < Minitest::Test
  include KnowledgeFixture

  def test_entries_are_attributed_to_the_heading_above_them
    assert_equal "Rules", entry(RULE_HTTP_1).section
    assert_equal "Reference", entry(ROLLUP_HTTP_2).section
    assert_equal "Conflicts", corpus.entries.find { |e| e.section == "Conflicts" }.section
  end

  def test_an_entry_records_its_line_role_source_and_reqs
    found = entry(RULE_HTTP_1)
    assert_equal 4, found.line
    assert_equal "spec", found.role
    assert_equal "docs/product-spec/04-core-http-domain-model.md:9", found.source
    assert_equal ["HTTP-1"], found.reqs
  end

  def test_notes_are_loaded_from_the_second_tree_with_their_own_origin
    note = corpus.entries.find(&:note?)
    assert_equal "note", note.origin
    assert_equal "review", note.role
    assert_equal "notes/pagination.md:8", note.location
    assert_equal "manual-fixture-erratum", note.sha
  end

  def test_index_sources_and_readme_are_not_topic_files
    refute_includes corpus.topics, "INDEX"
    refute_includes corpus.topics, "SOURCES"
    refute_includes corpus.topics, "README"
    assert_equal %w[http-domain-model pagination testing], corpus.topics
  end

  def test_a_crlf_or_bom_topic_file_still_parses
    dir = Dir.mktmpdir
    path = File.join(dir, "windows.md")
    File.binwrite(path, "\xEF\xBB\xBF# t\r\n\r\n## Rules\r\n- A rule (HTTP-1).\r\n" \
                        "  <sub>spec · `docs/product-spec/04-core-http-domain-model.md:9` · high · sha:abc123456789</sub>\r\n")
    entries = Knowledge::TopicParser.new(appendix.prefixes).parse(path, "harvested")
    assert_equal 1, entries.size
    assert_equal "Rules", entries.first.section
    assert_equal ["HTTP-1"], entries.first.reqs
  ensure
    FileUtils.remove_entry(dir) if dir
  end
end

class RollupTest < Minitest::Test
  include KnowledgeFixture

  def test_an_entry_sourced_only_from_appendix_b_is_a_rollup
    assert_predicate entry(ROLLUP_HTTP_2), :rollup?
  end

  def test_an_entry_sourced_from_a_real_chapter_is_not
    refute_predicate entry(RULE_HTTP_1), :rollup?
    refute_predicate entry(REFERENCE_PAGE_2), :rollup?
  end

  def test_a_rollup_only_result_prints_the_warning_and_the_tag
    stdout, = cli("--req", "HTTP-2")
    assert_includes stdout, "[appendix-B roll-up]"
    assert_includes stdout, "WARNING: every result is an appendix-B conformance roll-up"
  end

  def test_a_substantive_result_prints_neither
    stdout, = cli("--req", "HTTP-1")
    refute_includes stdout, "roll-up"
  end
end

class OverrideTest < Minitest::Test
  include KnowledgeFixture

  def test_a_note_citing_a_key_links_both_ends
    reference = entry(REFERENCE_PAGE_2)
    assert_equal ["notes/pagination.md:8"], reference.overridden_by
    note = corpus.entries.find(&:note?)
    assert_equal [REFERENCE_PAGE_2], note.overrides
  end

  def test_the_overridden_entry_is_tagged_wherever_it_is_returned
    stdout, = cli("--key", REFERENCE_PAGE_2)
    assert_includes stdout, "[overridden by notes/pagination.md:8]"
  end

  def test_a_key_that_resolves_to_nothing_is_reported_as_dangling
    assert_empty corpus.dangling_keys
    reworded = Knowledge::TopicParser.new(appendix.prefixes)
      .parse(File.join(KnowledgeFixture::ROOT, "docs/knowledge/notes/pagination.md"), "note")
    assert_equal 1, Knowledge::Corpus.new(reworded).dangling_keys.size
  end
end

class FilterTest < Minitest::Test
  include KnowledgeFixture

  def test_req_is_exact_token
    assert_equal [RULE_HTTP_70], select(req: ["HTTP-70"]).map(&:key)
    assert_empty select(req: ["HTTP-7"])
  end

  def test_values_within_one_filter_or
    keys = select(req: ["HTTP-1,PAGE-1"]).map(&:key)
    assert_equal [RULE_HTTP_1, RULE_PAGE_1].sort, keys.sort
  end

  def test_different_filters_and
    assert_empty select(req: ["HTTP-1"], topic: ["pagination"])
    assert_equal 1, select(req: ["PAGE-1"], topic: ["pagination"]).size
  end

  def test_prefix_takes_a_whole_family
    assert_equal 3, select(prefix: ["HTTP"]).size
    # Five: the four harvested pagination entries plus the note that cites PAGE-2.
    assert_equal 5, select(prefix: ["PAGE"]).size
  end

  def test_prefix_is_validated_against_appendix_c
    error = assert_raises(Knowledge::UsageError) { select(prefix: ["UTF"]) }
    assert_includes error.message, "not a requirement-ID prefix in appendix C"
  end

  def test_section_is_case_insensitive_and_validated
    assert_equal 6, select(section: ["rules"]).size
    assert_raises(Knowledge::UsageError) { select(section: ["rulez"]) }
  end

  def test_origin_splits_the_two_trees
    assert_equal 1, select(origin: ["note"]).size
    assert_equal 9, select(origin: ["harvested"]).size
    assert_raises(Knowledge::UsageError) { select(origin: ["harvest"]) }
  end

  def test_role_matches_any_role_on_the_entry
    assert_equal 1, select(role: ["review"]).size
    assert_equal 2, select(role: ["design"]).size
    assert_equal 3, select(role: ["styleguide"]).size
  end

  def test_topic_is_a_substring_of_the_file_name
    assert_equal 5, select(topic: ["pagination"]).size
    assert_equal 2, select(topic: ["testing"]).size
  end

  def test_chapter_matches_only_styleguide_sources
    assert_equal 2, select(chapter: ["11"]).size
    assert_equal 1, select(chapter: ["6"]).size
    # The spec chapter 04 is a numbered file too, and must not answer "chapter 4".
    assert_empty select(chapter: ["4"])
  end

  def test_a_chapter_with_a_section_number_drops_the_section_number
    warn = StringIO.new
    matcher = Knowledge::Query.build({chapter: ["6.7"]}, [], appendix, warn: warn)
    assert_equal ["6"], matcher.chapters
    assert_includes warn.string, "ignoring .7"
  end

  def test_bare_words_and_grep_are_case_insensitive_and_all_must_match
    assert_equal 1, select(words: %w[minitest header]).size
    assert_empty select(words: %w[minitest pagination])
    assert_equal 3, select(grep: ["closeable|eager-close"]).size
  end

  def test_a_key_must_look_like_a_key
    assert_raises(Knowledge::UsageError) { select(key: ["not-a-key"]) }
  end

  def test_an_all_empty_filter_is_refused_rather_than_matching_everything
    error = assert_raises(Knowledge::UsageError) { select(topic: [""]) }
    assert_includes error.message, "would print the whole corpus"
    assert_raises(Knowledge::UsageError) { select(topic: [","]) }
  end

  def test_a_trailing_comma_keeps_the_real_values
    assert_equal 5, select(topic: ["pagination,"]).size
  end
end

class GapsTest < Minitest::Test
  include KnowledgeFixture

  def test_gaps_separates_rollup_only_from_uncited
    stdout, _, status = cli("--gaps", "HTTP")
    assert_equal 0, status
    assert_includes stdout, "4 canonical IDs: 2 substantive, 1 roll-up only, 1 uncited"
    assert_match(/roll-up only .*\n\s+HTTP-2$/, stdout)
    assert_match(/uncited .*\n\s+HTTP-7$/, stdout)
    assert_includes stdout, "read these out of docs/product-spec/04-core-http-domain-model.md"
  end

  def test_gaps_all_covers_every_prefix_in_id_order
    stdout, _, status = cli("--gaps", "all")
    assert_equal 0, status
    assert_includes stdout, "HTTP — Core HTTP domain model"
    assert_includes stdout, "PAGE — Pagination"
    assert_includes stdout, "SEAM — Product vision, pluggable seams and extension model"
    assert_includes stdout, "4 of 9 IDs in 3 prefixes have no substantive entry"
  end

  def test_gaps_lists_a_prefix_with_no_corpus_entry_at_all_as_uncited
    stdout, = cli("--gaps", "SEAM")
    assert_includes stdout, "1 canonical IDs: 0 substantive, 0 roll-up only, 1 uncited"
    assert_includes stdout, "SEAM-1"
  end

  def test_gaps_takes_several_prefixes_at_once
    stdout, _, status = cli("--gaps", "HTTP,SEAM")
    assert_equal 0, status
    assert_includes stdout, "HTTP — Core HTTP domain model"
    assert_includes stdout, "SEAM — Product vision"
    refute_includes stdout, "PAGE — Pagination"
    assert_includes stdout, "3 of 5 IDs in 2 prefixes have no substantive entry"
  end

  def test_an_unknown_prefix_exits_2
    _, stderr, status = cli("--gaps", "UTF")
    assert_equal 2, status
    assert_includes stderr, "not a requirement-ID prefix in appendix C"
  end
end

class PrefixInfoTest < Minitest::Test
  include KnowledgeFixture

  def test_prefix_info_reports_subsystem_chapter_and_counts
    stdout, _, status = cli("--prefix-info", "http")
    assert_equal 0, status
    assert_includes stdout, "HTTP — Core HTTP domain model"
    assert_includes stdout, "4 canonical IDs (HTTP-1..HTTP-70), 3 MUST, 1 SHOULD"
    assert_includes stdout, "owning chapter: docs/product-spec/04-core-http-domain-model.md"
    assert_includes stdout, "2 of 4 IDs have a substantive entry, 1 are roll-up only, 1 are uncited"
    assert_includes stdout, "topics carrying HTTP knowledge: http-domain-model"
  end
end

class PhaseTest < Minitest::Test
  include KnowledgeFixture

  def test_phase_reports_which_document_contributed_which_ids_then_queries_them
    stdout, _, status = cli("--phase", "1a", "--brief")
    assert_equal 0, status
    assert_includes stdout, "phase 1a: 1 document"
    assert_includes stdout, "docs/work/mvp/phase1/phase1a/2026-01-01-phase1a-http.md — 3: HTTP-1 HTTP-2 PAGE-1"
    assert_includes stdout, "3 distinct requirement IDs cited by phase 1a"
    # The union of the three IDs: two HTTP entries plus the PAGE-1 rule.
    assert_includes stdout, "3 entries across 2 topic files"
  end

  def test_a_bare_phase_number_walks_the_sub_phase_directories_too
    stdout, = cli("--phase", "1", "--brief")
    assert_includes stdout, "phase 1: 2 documents"
    assert_includes stdout, "2026-01-01-phase1-segmentation.md — 1: SEAM-1"
    assert_includes stdout, "4 distinct requirement IDs cited by phase 1"
  end

  def test_phase_composes_with_the_other_filters
    stdout, = cli("--phase", "1a", "--section", "rules", "--brief")
    assert_includes stdout, "2 entries across 2 topic files"
  end

  def test_an_unwritten_phase_says_so_and_exits_0
    stdout, _, status = cli("--phase", "9")
    assert_equal 0, status
    assert_includes stdout, "no phase documents found for phase 9"
    assert_includes stdout, "--prefix-info and --gaps"
  end

  def test_a_malformed_phase_exits_2
    _, stderr, status = cli("--phase", "nope")
    assert_equal 2, status
    assert_includes stderr, "expected a phase like 5 or 5a"
  end
end

class DriftWarningTest < Minitest::Test
  include KnowledgeFixture

  def test_a_query_touching_a_drifted_source_warns_on_stderr_without_failing
    stdout, stderr, status = cli("--topic", "pagination", "--section", "rules", "--brief")
    assert_equal 0, status
    assert_includes stderr, "warning: stale docs/product-spec/12-pagination.md"
    assert_includes stderr, "harvested at sha 000000000000"
    refute_includes stdout, "warning"
  end

  def test_the_warning_is_one_line_per_source_however_many_entries_touch_it
    _, stderr, = cli("--topic", "pagination", "--brief")
    assert_equal 1, stderr.lines.count { |line| line.start_with?("warning: stale") }
  end

  def test_no_drift_check_silences_it
    _, stderr, = cli("--topic", "pagination", "--brief", "--no-drift-check")
    assert_empty stderr
  end

  def test_an_undrifted_source_says_nothing_and_a_missing_one_is_not_drift
    _, stderr, = cli("--topic", "http-domain-model,testing", "--brief")
    assert_empty stderr
  end
end

class OutputTest < Minitest::Test
  include KnowledgeFixture

  def test_a_result_carries_location_section_and_key
    stdout, _, status = cli("--req", "HTTP-1", "--no-drift-check")
    assert_equal 0, status
    assert_includes stdout, "http-domain-model.md:4 (Rules) #{RULE_HTTP_1}"
    assert_includes stdout, "<sub>spec · `docs/product-spec/04-core-http-domain-model.md:9`"
    assert_includes stdout, "1 entry across 1 topic file"
  end

  def test_brief_drops_the_provenance_line
    stdout, = cli("--req", "HTTP-1", "--brief", "--no-drift-check")
    refute_includes stdout, "<sub>"
  end

  def test_json_is_records_with_origin_key_and_rollup
    stdout, _, status = cli("--req", "HTTP-2", "--json", "--no-drift-check")
    assert_equal 0, status
    records = JSON.parse(stdout)
    assert_equal 1, records.size
    assert_equal ROLLUP_HTTP_2, records.first["key"]
    assert_equal "harvested", records.first["origin"]
    assert_equal true, records.first["rollup"]
  end

  def test_list_topics_counts_entries_ids_and_notes
    stdout, = cli("--list-topics")
    assert_includes stdout, "http-domain-model\t3\t3\t0"
    assert_includes stdout, "pagination\t4\t3\t1"
    assert_includes stdout, "testing\t2\t0\t0"
    assert_includes stdout, "1 harvested topics carry no requirement ID at all"
  end

  def test_coverage_splits_substantive_rollup_and_uncited
    stdout, = cli("--coverage")
    assert_includes stdout, "HTTP\t2\t1\t1\t4\tHTTP-7"
    assert_includes stdout, "SEAM\t0\t0\t1\t1\tSEAM-1"
    assert_includes stdout, "5/9 canonical IDs have a substantive entry"
  end

  def test_list_reqs_maps_every_cited_id_to_its_locations
    stdout, = cli("--list-reqs")
    assert_includes stdout, "HTTP-1\thttp-domain-model.md:4"
    assert_includes stdout, "6 requirement IDs cited across the corpus"
  end

  def test_no_filter_prints_the_usage_rather_than_the_corpus
    stdout, _, status = cli
    assert_equal 0, status
    assert_includes stdout, "Usage: scripts/knowledge.rb"
  end
end

class NoMatchTest < Minitest::Test
  include KnowledgeFixture

  def test_zero_matches_exits_1_and_names_the_barren_filter
    stdout, _, status = cli("--req", "HTTP-7")
    assert_equal 1, status
    assert_includes stdout, "HTTP-7 is canonical but no entry cites it yet."
    assert_includes stdout, "nearest cited HTTP IDs:"
  end

  def test_a_non_canonical_id_warns_and_is_named_as_such
    stdout, stderr, status = cli("--req", "ZZZ-1")
    assert_equal 1, status
    assert_includes stderr, "ZZZ-1 is not in appendix C"
    assert_includes stdout, "not a canonical requirement ID"
  end

  def test_a_filter_combination_that_cannot_hold_says_so_instead_of_blaming_one_side
    stdout, _, status = cli("--prefix", "HTTP", "--req", "PAGE-1")
    assert_equal 1, status
    assert_includes stdout, "every filter matches something on its own"
    assert_includes stdout, "Filters AND together"
  end

  def test_an_unknown_topic_lists_the_topics_that_exist
    stdout, = cli("--topic", "nosuchtopic")
    assert_includes stdout, "available: http-domain-model pagination testing"
  end

  def test_an_unresolvable_key_says_the_rule_was_reworded
    stdout, = cli("--key", "pagination/deadbeef")
    assert_includes stdout, "A key digests the entry's text"
  end
end

class MissingCorpusTest < Minitest::Test
  # A checkout that has the specification but has never been harvested — the
  # state every port is in on its first day.
  def setup
    @root = Dir.mktmpdir("knowledge-unharvested-")
    FileUtils.mkdir_p(File.join(@root, "docs"))
    FileUtils.cp_r(File.join(KnowledgeFixture::ROOT, "docs/product-spec"), File.join(@root, "docs"))
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def cli(*argv)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Knowledge::CLI.new(stdout: stdout, stderr: stderr).run(argv)
    [stdout.string, stderr.string, status]
  end

  def test_help_works_with_nothing_set_up_at_all
    stdout, _, status = cli("--root", "/nonexistent", "--help")
    assert_equal 0, status
    assert_includes stdout, "Usage: scripts/knowledge.rb"
  end

  def test_a_missing_appendix_c_is_explained_and_exits_1
    _, stderr, status = cli("--root", "/nonexistent", "--req", "HTTP-1")
    assert_equal 1, status
    assert_includes stderr, "cannot read the canonical requirement index"
    assert_includes stderr, "--root"
  end

  def test_a_missing_corpus_is_explained_and_exits_1_for_a_query
    _, stderr, status = cli("--root", @root, "--req", "HTTP-1")
    assert_equal 1, status
    assert_includes stderr, "does not exist under"
    assert_includes stderr, "harvested/"
  end

  def test_gaps_still_answers_from_appendix_c_alone
    stdout, stderr, status = cli("--root", @root, "--gaps", "HTTP")
    assert_equal 0, status
    assert_includes stderr, "reporting against appendix C alone"
    assert_includes stdout, "4 canonical IDs: 0 substantive, 0 roll-up only, 4 uncited"
  end
end

class CompanionScriptTest < Minitest::Test
  include KnowledgeFixture

  def report(klass)
    stdout = StringIO.new
    stderr = StringIO.new
    status = klass.new(paths, stdout: stdout, stderr: stderr).run
    [stdout.string, stderr.string, status]
  end

  def test_the_drift_report_states_ok_drift_and_not_verifiable
    stdout = StringIO.new
    status = Knowledge::DriftReport.new(paths, stdout: stdout).run
    assert_equal 0, status
    assert_includes stdout.string, "DRIFT\tdocs/product-spec/12-pagination.md"
    assert_includes stdout.string, "6 harvested sources: 3 OK, 1 DRIFT, 2 NOT VERIFIABLE, 0 UNREADABLE."
    assert_includes stdout.string, "1 note citation(s) resolve, 0 do not."
  end

  def test_the_structure_gate_passes_on_the_fixture
    stdout, _, status = report(Knowledge::StructureGate)
    assert_equal 0, status
    assert_includes stdout, "knowledge structure OK: 9 harvested entries"
  end

  def test_the_structure_gate_rejects_a_review_role_under_harvested
    with_extra_harvested_file(<<~MARKDOWN) do |stderr, status|
      # smuggled

      ## Rules
      - What the implementation found, written into the wrong tree.
        <sub>review · `docs/product-spec/04-core-http-domain-model.md:1` · high · sha:manual-x</sub>
    MARKDOWN
      assert_equal 1, status
      assert_includes stderr, "role `review` under harvested/"
    end
  end

  def test_the_structure_gate_rejects_a_superseded_section_and_an_off_root_source
    with_extra_harvested_file(<<~MARKDOWN) do |stderr, status|
      # smuggled

      ## Superseded
      - A judgement that belongs in notes/.
        <sub>spec · `docs/work/mvp/phase1/phase1a/2026-01-01-phase1a-http.md:1` · high · sha:abc123456789</sub>
    MARKDOWN
      assert_equal 1, status
      assert_includes stderr, "a Superseded entry under harvested/"
      assert_includes stderr, "which is under none of the harvested source roots"
    end
  end

  def test_the_structure_gate_rejects_a_bullet_with_no_provenance_line
    with_extra_harvested_file("# smuggled\n\n## Rules\n- A bullet somebody typed.\n") do |stderr, status|
      assert_equal 1, status
      assert_includes stderr, "no source."
    end
  end

  def test_the_structure_gate_rejects_a_topic_file_stranded_at_the_root
    path = File.join(KnowledgeFixture::ROOT, "docs/knowledge/stray.md")
    File.write(path, "# stray\n\n## Rules\n- Written by a --corpus-less harvest run.\n")
    _, stderr, status = report(Knowledge::StructureGate)
    assert_equal 1, status
    assert_includes stderr, "a topic file at the root of docs/knowledge/"
  ensure
    FileUtils.rm_f(path)
  end

  # The gate is only meaningful over a corpus that parsed; this is the floor,
  # derived from INDEX.md rather than from a hand-maintained magic number.
  def test_the_structure_gate_refuses_to_pass_over_a_parse_hole
    path = File.join(KnowledgeFixture::ROOT, "docs/knowledge/harvested/testing.md")
    original = File.read(path)
    File.write(path, "# testing\n\nEvery bullet lost to a bad edit.\n")
    error = assert_raises(Knowledge::UsageError) { report(Knowledge::StructureGate) }
    assert_includes error.message, "parses to zero"
  ensure
    File.write(path, original)
  end

  def with_extra_harvested_file(body)
    path = File.join(KnowledgeFixture::ROOT, "docs/knowledge/harvested/smuggled.md")
    File.write(path, body)
    _, stderr, status = report(Knowledge::StructureGate)
    yield(stderr, status)
  ensure
    FileUtils.rm_f(path)
  end
end

# One end-to-end run of the executable itself: the shebang, the exit code and
# the argument plumbing are not exercised by the in-process tests above.
class ExecutableTest < Minitest::Test
  def test_the_script_runs_as_a_program_and_exits_1_on_no_match
    script = File.join(KnowledgeFixture::SCRIPTS, "knowledge.rb")
    stdout, _, status = Open3.capture3(script, "--root", KnowledgeFixture::ROOT, "--req", "HTTP-7")
    assert_equal 1, status.exitstatus
    assert_includes stdout, "HTTP-7 is canonical but no entry cites it yet."
  end

  def test_the_script_runs_clean_under_warnings
    script = File.join(KnowledgeFixture::SCRIPTS, "knowledge.rb")
    _, stderr, status = Open3.capture3(RbConfig.ruby, "-w", script, "--root", KnowledgeFixture::ROOT,
                                       "--req", "HTTP-1", "--no-drift-check")
    assert_equal 0, status.exitstatus
    assert_empty stderr
  end
end

# `-h`/`--help` on the two companion scripts: a banner naming the script and a short usage
# description, printed and exited 0 -- not the bare "no such option" OptionParser gives an
# unrecognised flag when nothing declares `-h`/`--help` at all.
class CompanionScriptHelpTest < Minitest::Test
  def test_knowledge_drift_help_prints_a_short_usage_and_exits_0
    script = File.join(KnowledgeFixture::SCRIPTS, "knowledge_drift.rb")
    stdout, stderr, status = Open3.capture3(script, "--help")

    assert_equal 0, status.exitstatus
    assert_includes stdout, "Usage: scripts/knowledge_drift.rb"
    lines = stdout.lines.reject { |line| line.strip.empty? || line.match?(/^\s*(-h|--root)/) }
    assert_operator lines.length, :>=, 4
    assert_operator lines.length, :<=, 6 # banner line + a 3-5 line description
    assert_empty stderr
  end

  def test_verify_knowledge_structure_help_prints_a_short_usage_and_exits_0
    script = File.join(KnowledgeFixture::SCRIPTS, "verify_knowledge_structure.rb")
    stdout, stderr, status = Open3.capture3(script, "--help")

    assert_equal 0, status.exitstatus
    assert_includes stdout, "Usage: scripts/verify_knowledge_structure.rb"
    lines = stdout.lines.reject { |line| line.strip.empty? || line.match?(/^\s*(-h|--root)/) }
    assert_operator lines.length, :>=, 4
    assert_operator lines.length, :<=, 6 # banner line + a 3-5 line description
    assert_empty stderr
  end
end
