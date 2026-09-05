# frozen_string_literal: true

# SPDX-License-Identifier: MIT
# .claude/skills/housekeeping/test/apply_test.rb
#
# The apply stage is the only one that writes, so its refusals matter more than its moves.
# Every refusal here is a batch refusal: the tree is untouched, not half-collected.
#
# `test_the_guard_call_is_load_bearing` exists because deleting the equivalent call in the
# Node original once left that whole suite green.

require 'minitest/autorun'
require 'fileutils'
require 'open3'
require 'rbconfig'

require_relative '../apply'
require_relative 'fixture'

class ApplyTest < Minitest::Test
  Apply = Housekeeping::Apply
  Fixture = Housekeeping::Fixture
  Guard = Housekeeping::Guard

  APPLY_SCRIPT = File.expand_path('../apply.rb', __dir__)

  # --- helpers ---------------------------------------------------------------------------

  # A fixture whose inbox holds `files`, staged unless `staged: false`.
  def with_inbox(files, staged: true)
    key = staged ? :overrides : :untracked
    Fixture.with(**{ key => files }) { |root| yield root }
  end

  def apply_for(root, **kwargs)
    Apply.new(root: root, **kwargs)
  end

  def run_cli(root, *args)
    Open3.capture3(RbConfig.ruby, '-w', APPLY_SCRIPT, '--root', root, *args)
  end

  # --- where a document belongs ----------------------------------------------------------

  def test_a_sub_phase_document_nests_under_its_phase
    Fixture.with do |root|
      apply = apply_for(root)

      assert_equal 'docs/work/mvp/phase5/phase5a',
                   apply.target_directory('docs/superpowers/specs/2026-09-05-phase5a-transport-design.md')
    end
  end

  def test_a_whole_phase_document_sits_at_the_phase_level
    Fixture.with do |root|
      apply = apply_for(root)

      assert_equal 'docs/work/mvp/phase6',
                   apply.target_directory('docs/superpowers/specs/2026-09-05-phase6-segmentation-design.md')
      assert_equal 'docs/work/mvp/phase6',
                   apply.target_directory('docs/superpowers/plans/2026-09-05-phase6.md')
    end
  end

  def test_phase10_is_not_read_as_phase1
    Fixture.with do |root|
      assert_equal 'docs/work/mvp/phase10',
                   apply_for(root).target_directory('docs/superpowers/plans/2026-09-05-phase10-release.md')
    end
  end

  def test_a_document_belonging_to_no_phase_sits_directly_under_the_delivery
    Fixture.with do |root|
      assert_equal 'docs/work/mvp',
                   apply_for(root).target_directory('docs/superpowers/specs/2026-09-05-roadmap-design.md')
    end
  end

  def test_the_phase_flag_overrides_the_filename
    Fixture.with do |root|
      apply = apply_for(root, phase: '5a')

      assert_equal 'docs/work/mvp/phase5/phase5a',
                   apply.target_directory('docs/superpowers/specs/2026-09-05-anything.md')
      assert_equal 'docs/work/mvp/phase7',
                   apply_for(root, phase: '7').target_directory('docs/superpowers/specs/2026-09-05-phase2-x.md')
    end
  end

  def test_the_delivery_is_a_parameter_so_a_later_effort_is_a_sibling_of_mvp
    Fixture.with do |root|
      assert_equal 'docs/work/v2/phase1',
                   apply_for(root, delivery: 'v2').target_directory('docs/superpowers/plans/2026-09-05-phase1-x.md')
    end
  end

  def test_a_malformed_phase_is_refused_at_construction
    Fixture.with do |root|
      error = assert_raises(ArgumentError) { apply_for(root, phase: 'five-a') }

      assert_match(/--phase must look like 5 or 5a/, error.message)
    end
  end

  # --- the plan --------------------------------------------------------------------------

  def test_the_plan_keeps_the_filename_date_prefix_included
    with_inbox({ 'docs/superpowers/specs/2026-09-05-phase5a-x-design.md' => "# x\n" }) do |root|
      moves = apply_for(root).plan

      assert_equal 1, moves.length
      assert_equal 'docs/superpowers/specs/2026-09-05-phase5a-x-design.md', moves.first.from
      assert_equal 'docs/work/mvp/phase5/phase5a/2026-09-05-phase5a-x-design.md', moves.first.to
    end
  end

  # A filename beginning with `-` (or looking like one) must not be read as a flag by
  # `git mv`; `--` before the paths is what stops that.
  def test_move_command_separates_paths_from_flags_with_a_double_dash
    move = Housekeeping::Move.new('docs/superpowers/specs/x.md', 'docs/work/mvp/x.md')

    assert_equal 'git mv -- docs/superpowers/specs/x.md docs/work/mvp/x.md', move.command
  end

  def test_the_plan_sees_an_untracked_inbox_file
    with_inbox({ 'docs/superpowers/plans/2026-09-05-phase2-x.md' => "# x\n" }, staged: false) do |root|
      assert_equal 1, apply_for(root).plan.length
    end
  end

  def test_the_plan_never_collects_the_readme_or_the_gitkeep
    Fixture.with { |root| assert_empty apply_for(root).plan }
  end

  def test_rename_maps_a_basename_as_it_moves
    with_inbox({ 'docs/superpowers/specs/2026-09-05-x-design.md' => "# x\n" }) do |root|
      renames = { '2026-09-05-x-design.md' => '2026-09-05-phase5a-x-design.md' }
      moves = apply_for(root, phase: '5a', renames: renames).plan

      assert_equal 'docs/work/mvp/phase5/phase5a/2026-09-05-phase5a-x-design.md', moves.first.to
    end
  end

  # --- batch refusals --------------------------------------------------------------------

  def test_refuses_the_batch_when_a_target_already_exists
    with_inbox({
                 'docs/superpowers/specs/2026-01-01-phase1-thing.md' => "# again\n"
               }) do |root|
      apply = apply_for(root)
      moves = apply.plan
      refusals = apply.refusals(moves)

      assert_equal 1, refusals.length
      assert_match(%r{docs/work/mvp/phase1/2026-01-01-phase1-thing\.md already exists}, refusals.first)
    end
  end

  def test_refuses_the_batch_when_two_inbox_files_collide_on_one_target
    with_inbox({
                 'docs/superpowers/specs/2026-09-05-phase5-x.md' => "# design\n",
                 'docs/superpowers/plans/2026-09-05-phase5-x.md' => "# plan\n"
               }) do |root|
      refusals = apply_for(root).then { |a| a.refusals(a.plan) }

      assert(refusals.any? { |r| /both land on/.match?(r) }, refusals.inspect)
    end
  end

  def test_refuses_the_batch_when_the_delivery_escapes_into_a_frozen_tree
    with_inbox({ 'docs/superpowers/specs/2026-09-05-phase1-x.md' => "# x\n" }) do |root|
      apply = apply_for(root, delivery: '../product-spec')
      refusals = apply.refusals(apply.plan)

      assert(refusals.any? { |r| /frozen entry 'docs\/product-spec'/.match?(r) }, refusals.inspect)
    end
  end

  def test_refuses_an_untracked_inbox_file_with_the_git_add_to_run
    with_inbox({ 'docs/superpowers/plans/2026-09-05-phase2-x.md' => "# x\n" }, staged: false) do |root|
      apply = apply_for(root)
      refusals = apply.refusals(apply.plan)

      assert(refusals.any? { |r| /is not tracked; `git mv` cannot move it/.match?(r) }, refusals.inspect)
      assert(refusals.any? { |r| r.include?('git add docs/superpowers/plans/2026-09-05-phase2-x.md') })
    end
  end

  # The guard is asserted AGAIN immediately before the first write, so deleting the
  # refusal-collecting call cannot leave this stage unguarded.
  def test_the_guard_call_is_load_bearing
    with_inbox({ 'docs/superpowers/specs/2026-09-05-phase1-x.md' => "# x\n" }) do |root|
      apply = apply_for(root, delivery: '../product-spec')

      assert_raises(Guard::FrozenPathError) { apply.perform(apply.plan) }
      # Nothing was created inside the normative tree, and the source is still in the inbox.
      refute_path_exists File.join(root, 'docs/product-spec')
      assert_path_exists File.join(root, 'docs/superpowers/specs/2026-09-05-phase1-x.md')
    end
  end

  # --- performing ------------------------------------------------------------------------

  def test_perform_moves_with_git_mv_so_history_follows
    with_inbox({ 'docs/superpowers/specs/2026-09-05-phase5a-x-design.md' => "# x\n" }) do |root|
      apply = apply_for(root)
      done = apply.perform(apply.plan)
      target = 'docs/work/mvp/phase5/phase5a/2026-09-05-phase5a-x-design.md'

      assert_equal 1, done.length
      assert_path_exists File.join(root, target)
      refute_path_exists File.join(root, 'docs/superpowers/specs/2026-09-05-phase5a-x-design.md')
      # Staged as a rename, which is what makes `git log --follow` resolve across the move.
      assert_match(/^R/, Fixture.git(root, 'status', '--porcelain').lines.first)
    end
  end

  # --- the command line ------------------------------------------------------------------

  def test_cli_dry_run_prints_the_exact_git_mv_commands_and_moves_nothing
    with_inbox({ 'docs/superpowers/specs/2026-09-05-phase5a-x-design.md' => "# x\n" }) do |root|
      before = Fixture.git(root, 'status', '--porcelain')
      out, err, status = run_cli(root, '--dry-run')

      assert_equal '', err
      assert_equal 0, status.exitstatus
      assert_includes out, 'git mv -- docs/superpowers/specs/2026-09-05-phase5a-x-design.md ' \
                           'docs/work/mvp/phase5/phase5a/2026-09-05-phase5a-x-design.md'
      assert_includes out, '1 move(s) planned. Re-run with --write to perform them.'
      assert_path_exists File.join(root, 'docs/superpowers/specs/2026-09-05-phase5a-x-design.md')
      assert_equal before, Fixture.git(root, 'status', '--porcelain')
    end
  end

  def test_cli_is_dry_by_default
    with_inbox({ 'docs/superpowers/specs/2026-09-05-phase1-x.md' => "# x\n" }) do |root|
      run_cli(root)

      assert_path_exists File.join(root, 'docs/superpowers/specs/2026-09-05-phase1-x.md')
    end
  end

  def test_cli_write_performs_the_batch_and_says_what_it_did_not_do
    with_inbox({ 'docs/superpowers/plans/2026-09-05-phase3-x.md' => "# x\n" }) do |root|
      out, err, status = run_cli(root, '--write', '--delivery', 'mvp')

      assert_equal '', err
      assert_equal 0, status.exitstatus
      assert_includes out, '1 file(s) collected.'
      assert_includes out, 'Repoint references'
      assert_path_exists File.join(root, 'docs/work/mvp/phase3/2026-09-05-phase3-x.md')
    end
  end

  def test_cli_honours_phase_and_rename_together
    with_inbox({ 'docs/superpowers/specs/2026-09-05-x-design.md' => "# x\n" }) do |root|
      out, _err, status = run_cli(root, '--phase', '5a', '--rename',
                                  '2026-09-05-x-design.md=2026-09-05-phase5a-x-design.md', '--write')

      assert_equal 0, status.exitstatus
      assert_includes out, 'docs/work/mvp/phase5/phase5a/2026-09-05-phase5a-x-design.md'
      assert_path_exists File.join(root, 'docs/work/mvp/phase5/phase5a/2026-09-05-phase5a-x-design.md')
    end
  end

  def test_cli_says_the_inbox_is_empty
    Fixture.with do |root|
      out, _err, status = run_cli(root, '--write')

      assert_equal 0, status.exitstatus
      assert_includes out, 'the inbox is empty; nothing to collect.'
    end
  end

  def test_cli_refuses_the_whole_batch_and_leaves_the_tree_untouched
    with_inbox({
                 'docs/superpowers/specs/2026-01-01-phase1-thing.md' => "# collides\n",
                 'docs/superpowers/plans/2026-09-05-phase2-fine.md' => "# fine\n"
               }) do |root|
      before = Fixture.git(root, 'status', '--porcelain')
      _out, err, status = run_cli(root, '--write')

      assert_equal 1, status.exitstatus
      assert_match(/refusing: .*already exists/, err)
      assert_match(/the whole batch was declined, so the tree is untouched/, err)
      # The second file was movable and must NOT have moved.
      refute_path_exists File.join(root, 'docs/work/mvp/phase2/2026-09-05-phase2-fine.md')
      assert_equal before, Fixture.git(root, 'status', '--porcelain')
    end
  end

  def test_cli_refuses_a_frozen_delivery
    with_inbox({ 'docs/superpowers/specs/2026-09-05-phase1-x.md' => "# x\n" }) do |root|
      _out, err, status = run_cli(root, '--write', '--delivery', '../product-spec')

      assert_equal 1, status.exitstatus
      assert_match(/frozen entry 'docs\/product-spec'/, err)
    end
  end

  def test_cli_refuses_a_malformed_rename
    Fixture.with do |root|
      _out, err, status = run_cli(root, '--rename', 'nope')

      assert_equal 1, status.exitstatus
      assert_match(/--rename wants FROM=TO/, err)
    end
  end

  # optparse prefixes an OptionParser::InvalidArgument message with the option name itself;
  # a message that also spells out "--rename" reads as "--rename --rename wants FROM=TO".
  def test_cli_rename_error_does_not_double_the_option_name
    Fixture.with do |root|
      _out, err, status = run_cli(root, '--rename', 'foo.md')

      assert_equal 1, status.exitstatus
      refute_match(/--rename --rename/, err)
      assert_match(/--rename wants FROM=TO, got foo\.md/, err)
    end
  end
end
