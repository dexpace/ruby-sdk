# frozen_string_literal: true

# SPDX-License-Identifier: MIT
# .claude/skills/housekeeping/test/probe_test.rb
#
# Tests the CHECKS, not a copy of their logic, and not the live tree's cleanliness.
#
# Asserting only that each check returns nothing against the real repository passes just as
# happily over a check whose body has become `[]` -- and the real repository is clean most
# of the time, so such a suite stays green while the checks rot. Every check therefore has
# a PAIR here: a fixture it must be silent over, and a mutation of that fixture it must
# fire on.

require 'minitest/autorun'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'

require_relative '../probe'
require_relative 'fixture'

class ProbeTest < Minitest::Test
  Fixture = Housekeeping::Fixture
  Probe = Housekeeping::Probe
  Repo = Housekeeping::Repo

  PROBE_SCRIPT = File.expand_path('../probe.rb', __dir__)

  # --- helpers ---------------------------------------------------------------------------

  def on_fixture(only: nil, overrides: {}, untracked: {})
    Fixture.with(overrides: overrides, untracked: untracked) do |root|
      Probe.new(Repo.new(root), only: only).run
    end
  end

  def messages(findings)
    findings.map(&:message)
  end

  def assert_fires(findings, pattern)
    assert findings.any? { |f| pattern.match?(f.message) },
           "expected a finding matching #{pattern.inspect}, got: #{messages(findings).inspect}"
  end

  # --- the clean tree --------------------------------------------------------------------

  def test_a_clean_fixture_reports_nothing_on_every_check
    assert_empty on_fixture
  end

  def test_check_names_are_the_eight_the_documentation_states
    assert_equal %w[inbox root claims readmes links registers citations guard], Probe::NAMES
  end

  # --- numerals --------------------------------------------------------------------------

  def test_parse_numeral_reads_digits_words_and_compounds_and_rejects_prose
    parse = Housekeeping::Numeral.method(:parse)

    assert_equal 0, parse.call('0')
    assert_equal 20, parse.call('20')
    assert_equal 9, parse.call('nine')
    assert_equal 11, parse.call('Eleven')
    assert_equal 20, parse.call('Twenty')
    assert_equal 24, parse.call('twenty-four')
    assert_equal 99, parse.call('ninety-nine')
    # The words that make a digits-only matcher protect one sentence per repository.
    assert_nil parse.call('published')
    assert_nil parse.call('several')
    assert_nil parse.call('twenty-zero')
  end

  # --- inbox -----------------------------------------------------------------------------

  def test_inbox_catches_an_untracked_phase_document
    # The inbox's NORMAL state: a file a global skill just wrote and nobody staged.
    found = on_fixture(only: ['inbox'], untracked: { 'docs/superpowers/specs/2026-09-05-x-design.md' => "# x\n" })

    assert_fires found, /still in the inbox/
    assert_equal 'docs/superpowers/specs/2026-09-05-x-design.md', found.first.path
  end

  def test_inbox_catches_a_tracked_phase_document_too
    found = on_fixture(only: ['inbox'], overrides: { 'docs/superpowers/plans/2026-09-05-x.md' => "# x\n" })

    assert_fires found, /still in the inbox/
  end

  def test_inbox_never_reports_the_readme_or_the_gitkeep
    assert_empty on_fixture(only: ['inbox'])
  end

  # --- root ------------------------------------------------------------------------------

  def test_root_catches_a_stray_register_at_the_repository_root
    found = on_fixture(only: ['root'], overrides: { 'open-items.md' => "# open items\n" })

    assert_fires found, /sits at the repository root/
  end

  def test_root_permits_the_community_health_files
    found = on_fixture(only: ['root'], overrides: {
                         'CONTRIBUTING.md' => "# contributing\n",
                         'SECURITY.md' => "# security\n",
                         'CHANGELOG.md' => "# changelog\n",
                         'CODE_OF_CONDUCT.md' => "# conduct\n"
                       })

    assert_empty found
  end

  # --- claims ----------------------------------------------------------------------------

  def test_claims_catches_a_count_stated_as_a_WORD
    found = on_fixture(only: ['claims'],
                       overrides: { 'CLAUDE.md' => "# CLAUDE.md\n\nSeven gems live here.\n" })

    assert_fires found, /states "Seven gems" but the repository has 2 gems/
  end

  def test_claims_catches_a_count_stated_as_a_DIGIT
    found = on_fixture(only: ['claims'],
                       overrides: { 'README.md' => "# fixture\n\nThere are 9 gems.\n" })

    assert_fires found, /states "9 gems" but the repository has 2 gems/
  end

  def test_claims_catches_a_stale_phase_and_topic_count
    found = on_fixture(only: ['claims'],
                       overrides: { 'docs/README.md' => "# docs\n\nFour phase directories, six harvested topics.\n" })

    assert_fires found, /Four phase directories.*repository has 1 phase directories/m
    assert_fires found, /six harvested topics.*repository has 1 topics/m
  end

  def test_claims_topic_count_excludes_sources_md
    found = on_fixture(only: ['claims'],
                       overrides: {
                         'docs/knowledge/harvested/SOURCES.md' => "# sources\n\nNot a topic.\n",
                         'docs/knowledge/harvested/pagination.md' => "# pagination\n\nHarvested.\n",
                         'docs/README.md' => "# docs\n\nOne phase directory, five harvested topics.\n"
                       })

    assert_fires found, /five harvested topics.*repository has 2 topics/m
  end

  def test_claims_treats_a_quoted_historical_count_as_reported_speech
    found = on_fixture(only: ['claims'],
                       overrides: { 'CLAUDE.md' => %(# CLAUDE.md\n\nThis once said "seven gems" and was wrong.\n) })

    assert_empty found
  end

  def test_claims_ignores_a_count_inside_a_fenced_block
    fenced = "# CLAUDE.md\n\n```\nSeven gems, in a code sample.\n```\n"
    found = on_fixture(only: ['claims'], overrides: { 'CLAUDE.md' => fenced })

    assert_empty found
  end

  def test_claims_no_ops_when_the_file_is_absent
    found = on_fixture(only: ['claims'], overrides: { 'CLAUDE.md' => nil })

    assert_empty found
  end

  def test_claims_no_ops_when_the_pattern_is_absent
    found = on_fixture(only: ['claims'], overrides: { 'CLAUDE.md' => "# CLAUDE.md\n\nNo counts at all.\n" })

    assert_empty found
  end

  def test_claims_counts_gems_from_the_tree_not_from_a_document
    found = on_fixture(only: ['claims'], overrides: {
                         'gems/dexpace-async-thread/dexpace-async-thread.gemspec' =>
                           Fixture.gemspec('dexpace-async-thread'),
                         'gems/dexpace-async-thread/README.md' => Fixture.readme('dexpace-async-thread')
                       })

    assert_fires found, /repository has 3 gems/
  end

  # --- readmes ---------------------------------------------------------------------------

  def test_readmes_catches_a_gem_with_no_readme
    found = on_fixture(only: ['readmes'], overrides: { 'gems/dexpace-core/README.md' => nil })

    assert_fires found, %r{gems/dexpace-core/README\.md.*is missing|is missing}
    assert_equal 'gems/dexpace-core/README.md', found.first.path
  end

  def test_readmes_reports_a_thin_readme_as_a_note
    found = on_fixture(only: ['readmes'], overrides: { 'gems/dexpace-core/README.md' => "# dexpace-core\n\nThin.\n" })

    assert_fires found, /is 3 lines\. The bar is 20/
    assert_equal ['note'], found.map(&:severity)
  end

  def test_readmes_catches_a_readme_whose_heading_names_another_gem
    found = on_fixture(only: ['readmes'],
                       overrides: { 'gems/dexpace-core/README.md' => Fixture.readme('dexpace-serde-json') })

    assert_fires found, /opens with "dexpace-serde-json" but its gemspec declares dexpace-core/
  end

  def test_readmes_catches_a_gem_directory_with_no_gemspec
    found = on_fixture(only: ['readmes'], overrides: { 'gems/dexpace-core/dexpace-core.gemspec' => nil })

    assert_fires found, /has no gemspec/
  end

  def test_readmes_no_ops_when_there_is_no_gems_directory
    Fixture.with do |root|
      FileUtils.rm_rf(File.join(root, 'gems'))

      assert_empty Probe.new(Repo.new(root), only: ['readmes']).run
    end
  end

  # --- links -----------------------------------------------------------------------------

  def test_links_catches_a_broken_link_in_a_nested_docs_file
    found = on_fixture(only: ['links'],
                       overrides: { 'docs/sdk-documentation/architecture.md' => "# a\n\n[gone](./nowhere.md)\n" })

    assert_fires found, %r{links \./nowhere\.md, which resolves to docs/sdk-documentation/nowhere\.md}
    assert_equal 3, found.first.line
  end

  def test_links_catches_a_broken_link_at_the_top_of_docs
    found = on_fixture(only: ['links'], overrides: { 'docs/README.md' => "# docs\n\n[gone](missing.md)\n" })

    assert_fires found, %r{resolves to docs/missing\.md}
  end

  def test_links_catches_a_broken_link_in_a_gem_readme
    broken = "#{Fixture.readme('dexpace-core')}\n[gone](./CHANGELOG.md)\n"
    found = on_fixture(only: ['links'], overrides: { 'gems/dexpace-core/README.md' => broken })

    assert_fires found, %r{gems/dexpace-core/CHANGELOG\.md}
  end

  def test_links_does_not_treat_a_fenced_line_as_a_link
    fenced = "# docs\n\n```md\n[gone](nowhere.md)\n```\n"
    found = on_fixture(only: ['links'], overrides: { 'docs/README.md' => fenced })

    assert_empty found
  end

  def test_links_skips_external_anchor_and_mailto_targets
    text = "# docs\n\n[a](https://example.invalid/x) [b](#section) [c](mailto:x@example.invalid)\n"
    found = on_fixture(only: ['links'], overrides: { 'docs/README.md' => text })

    assert_empty found
  end

  def test_links_resolves_a_percent_encoded_target
    found = on_fixture(only: ['links'], overrides: {
                         'docs/README.md' => "# docs\n\n[x](open%2Ditems.md)\n"
                       })

    assert_empty found
  end

  def test_links_ignores_a_link_inside_an_inline_code_span
    text = "# docs\n\nSee `[gone](nowhere.md)` for the old syntax.\n\n[real](also-gone.md)\n"
    found = on_fixture(only: ['links'], overrides: { 'docs/README.md' => text })

    assert_equal 1, found.length
    assert_fires found, /also-gone\.md/
  end

  def test_links_ignores_a_link_inside_an_indented_code_block
    text = "# docs\n\n    [gone](nowhere.md)\n\n[real](also-gone.md)\n"
    found = on_fixture(only: ['links'], overrides: { 'docs/README.md' => text })

    assert_equal 1, found.length
    assert_fires found, /also-gone\.md/
  end

  def test_links_catches_a_broken_reference_style_definition
    text = "# docs\n\nSee [the guide][guide].\n\n[guide]: nowhere.md\n"
    found = on_fixture(only: ['links'], overrides: { 'docs/README.md' => text })

    assert_fires found, %r{references \[guide\], which resolves to docs/nowhere\.md}
  end

  def test_links_catches_an_undefined_reference
    text = "# docs\n\nSee [the guide][missing].\n"
    found = on_fixture(only: ['links'], overrides: { 'docs/README.md' => text })

    assert_fires found, /references \[missing\], which has no \[missing\]: definition/
  end

  def test_links_resolves_a_reference_style_link_that_is_defined_and_valid
    text = "# docs\n\nSee [the inbox][ref].\n\n[ref]: superpowers/README.md\n"
    found = on_fixture(only: ['links'], overrides: { 'docs/README.md' => text })

    assert_empty found
  end

  def test_links_ignores_a_reference_style_link_inside_code
    text = "# docs\n\n`[the guide][missing]`\n"
    found = on_fixture(only: ['links'], overrides: { 'docs/README.md' => text })

    assert_empty found
  end

  # --- registers -------------------------------------------------------------------------

  def test_registers_catches_an_aggregate_register_in_a_phase_document
    found = on_fixture(only: ['registers'], overrides: {
                         'docs/work/mvp/phase1/2026-01-01-phase1-thing.md' =>
                           "# phase 1\n\nBody.\n\n## Deferred Items Log\n\n| ID | Item |\n"
                       })

    assert_fires found, /carries "## Deferred Items Log"/
    assert_equal 5, found.first.line
  end

  def test_registers_catches_open_findings_in_an_inbox_document
    found = on_fixture(only: ['registers'],
                       untracked: { 'docs/superpowers/specs/x-design.md' => "# x\n\n## Open Findings\n" })

    assert_fires found, /carries "## Open Findings"/
  end

  def test_registers_does_not_report_a_moved_out_pointer_stub
    found = on_fixture(only: ['registers'], overrides: {
                         'docs/work/mvp/phase1/2026-01-01-phase1-thing.md' =>
                           "# phase 1\n\n## Open Items\n\n**Moved out on 2026-09-05** to docs/open-items.md.\n"
                       })

    assert_empty found
  end

  # --- citations -------------------------------------------------------------------------

  def test_citations_catches_a_dangling_register_id
    found = on_fixture(only: ['citations'], overrides: {
                         'docs/work/mvp/phase1/2026-01-01-phase1-thing.md' => "# phase 1\n\nSee OI-9 and DEF-2.\n"
                       })

    assert_fires found, /cites OI-9, which has no entry in docs\/open-items\.md/
    refute_includes messages(found).join, 'DEF-2'
  end

  def test_citations_is_quiet_when_every_id_resolves
    assert_empty on_fixture(only: ['citations'])
  end

  def test_citations_resolves_both_a_heading_and_a_table_row
    found = on_fixture(only: ['citations'], overrides: {
                         'docs/README.md' => "# docs\n\nOI-1 and DEF-2 both resolve.\n"
                       })

    assert_empty found
  end

  def test_citations_no_ops_when_the_register_is_absent
    found = on_fixture(only: ['citations'], overrides: {
                         'docs/open-items.md' => nil,
                         'docs/README.md' => "# docs\n\nOI-9 cited with no register at all.\n"
                       })

    assert_empty found
  end

  def test_citations_does_not_claim_a_requirement_id_is_a_register_item
    found = on_fixture(only: ['citations'], overrides: {
                         'docs/README.md' => "# docs\n\nHTTP-7, SEAM-1, RETRY-13 and NFR-5 are requirements.\n"
                       })

    assert_empty found
  end

  def test_citations_ignores_a_dangling_id_inside_a_fenced_block
    found = on_fixture(only: ['citations'], overrides: {
                         'docs/README.md' => "# docs\n\n```\nSee OI-99 in this example.\n```\n"
                       })

    assert_empty found
  end

  def test_citations_catches_the_same_dangling_id_outside_a_fence
    found = on_fixture(only: ['citations'], overrides: {
                         'docs/README.md' => "# docs\n\nSee OI-99 in prose.\n"
                       })

    assert_fires found, /cites OI-99, which has no entry in docs\/open-items\.md/
  end

  def test_citations_def_resolves_against_deferred_items_only
    found = on_fixture(only: ['citations'], overrides: {
                         'docs/README.md' => "# docs\n\nSee DEF-2 for the deferral.\n"
                       })

    assert_empty found
  end

  def test_citations_oi_style_heading_inside_deferred_items_does_not_resolve_oi
    found = on_fixture(only: ['citations'], overrides: {
                         'docs/deferred-items.md' =>
                           "# Deferred items\n\n| ID | State |\n|---|---|\n| `DEF-2` | deferred |\n\n### OI-5 — wrong file\n",
                         'docs/README.md' => "# docs\n\nSee OI-5.\n"
                       })

    assert_fires found, /cites OI-5, which has no entry in docs\/open-items\.md/
  end

  def test_citations_catches_a_dangling_deferred_item
    found = on_fixture(only: ['citations'], overrides: {
                         'docs/README.md' => "# docs\n\nSee DEF-99, which does not exist.\n"
                       })

    assert_fires found, /cites DEF-99, which has no entry in docs\/deferred-items\.md/
  end

  # --- guard -----------------------------------------------------------------------------

  def test_guard_is_quiet_when_the_two_lists_do_not_overlap
    assert_empty on_fixture(only: ['guard'])
  end

  def test_guard_catches_a_frozen_entry_that_became_a_symlink
    Fixture.with do |root|
      FileUtils.rm_rf(File.join(root, 'docs/knowledge'))
      FileUtils.mkdir_p(File.join(root, 'docs/elsewhere'))
      File.symlink(File.join(root, 'docs/elsewhere'), File.join(root, 'docs/knowledge'))

      found = Probe.new(Repo.new(root), only: ['guard']).run

      assert found.any? { |f| /is a symlink/.match?(f.message) }, messages(found).inspect
    end
  end

  # --- the read-only contract ------------------------------------------------------------

  def test_the_probe_writes_nothing
    Fixture.with(untracked: { 'docs/superpowers/specs/2026-09-05-x-design.md' => "# x\n" }) do |root|
      before = Fixture.git(root, 'status', '--porcelain')
      Probe.new(Repo.new(root)).run
      after = Fixture.git(root, 'status', '--porcelain')

      assert_equal before, after
    end
  end

  # --- selection -------------------------------------------------------------------------

  def test_only_selects_a_subset_and_an_unknown_check_is_refused
    Fixture.with do |root|
      repo = Repo.new(root)

      assert_equal ['links'], Probe.new(repo, only: ['links']).checks.map { |c| c::NAME }
      assert_equal Probe::NAMES, Probe.new(repo).checks.map { |c| c::NAME }
      error = assert_raises(ArgumentError) { Probe.new(repo, only: %w[links nope]) }
      assert_match(/unknown check\(s\): nope/, error.message)
    end
  end

  # --- the command line ------------------------------------------------------------------

  def run_cli(root, *args)
    Open3.capture3(RbConfig.ruby, '-w', PROBE_SCRIPT, '--root', root, *args)
  end

  def test_cli_exits_zero_and_says_so_on_a_clean_tree
    Fixture.with do |root|
      out, err, status = run_cli(root)

      assert_equal '', err
      assert_includes out, 'no drift found.'
      assert_equal 0, status.exitstatus
    end
  end

  def test_cli_exits_one_on_a_finding_and_zero_under_warn_only
    Fixture.with(untracked: { 'docs/superpowers/specs/2026-09-05-x-design.md' => "# x\n" }) do |root|
      out, _err, status = run_cli(root)

      assert_equal 1, status.exitstatus
      assert_includes out, '## inbox (1)'
      assert_includes out, 'docs/superpowers/specs/2026-09-05-x-design.md:1: [act]'
      assert_includes out, '1 finding(s) across 1 check(s).'

      _out, _err, lenient = run_cli(root, '--warn-only')

      assert_equal 0, lenient.exitstatus
    end
  end

  def test_cli_emits_json
    Fixture.with(untracked: { 'docs/superpowers/plans/2026-09-05-x.md' => "# x\n" }) do |root|
      out, _err, status = run_cli(root, '--json', '--only', 'inbox')
      payload = JSON.parse(out)

      assert_equal 1, status.exitstatus
      assert_equal ['inbox'], payload['checks']
      assert_equal 'docs/superpowers/plans/2026-09-05-x.md', payload['findings'].first['path']
      assert_equal 1, payload['summary']['findings']
    end
  end

  def test_cli_refuses_an_unknown_check_by_name
    Fixture.with do |root|
      _out, err, status = run_cli(root, '--only', 'nope')

      assert_equal 2, status.exitstatus
      assert_match(/unknown check/, err)
    end
  end
end
