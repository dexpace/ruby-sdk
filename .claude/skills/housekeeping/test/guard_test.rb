# frozen_string_literal: true

# SPDX-License-Identifier: MIT
# .claude/skills/housekeeping/test/guard_test.rb
#
# The guard is the one part of this skill that must not be wrong, because everything it
# protects is a document no other copy of exists. These cases are the four ways a naive
# `start_with?` implementation fails -- sibling prefix, `..` traversal, absolute path and
# symlink -- plus proof that the mutable half stays mutable.

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

require_relative '../guard'
require_relative 'fixture'

class GuardTest < Minitest::Test
  Guard = Housekeeping::Guard
  ROOT = '/repo'

  def test_every_frozen_entry_is_itself_refused
    Guard::FROZEN.each do |entry|
      assert_equal entry, Guard.frozen_entry_for(entry, ROOT), entry
    end
  end

  def test_a_file_under_a_frozen_tree_is_refused_at_any_depth
    assert_equal 'docs/product-spec', Guard.frozen_entry_for('docs/product-spec/04-core.md', ROOT)
    assert_equal 'docs/knowledge', Guard.frozen_entry_for('docs/knowledge/harvested/documentation.md', ROOT)
    assert_equal 'docs/knowledge', Guard.frozen_entry_for('docs/knowledge/notes/pagination.md', ROOT)
    assert_equal 'docs/sdk-design-ruby', Guard.frozen_entry_for('docs/sdk-design-ruby/10-deviations.md', ROOT)
  end

  # Bypass 1. The failure a raw string prefix test would produce, and the reason the
  # comparison is segment-wise.
  def test_a_sibling_whose_name_merely_starts_with_a_frozen_one_is_writable
    refute Guard.frozen?('docs/product-specs/04-core.md', ROOT)
    refute Guard.frozen?('docs/product-spec-draft/04-core.md', ROOT)
    refute Guard.frozen?('docs/knowledge-notes.md', ROOT)
    refute Guard.frozen?('docs/sdk-design-ruby-old/01.md', ROOT)
    refute Guard.frozen?('docs/product-spec.md.bak', ROOT)
  end

  # Bypass 2. A path that spells its way in must not spell its way past the check.
  def test_a_dotdot_segment_that_lands_inside_is_refused
    assert_equal 'docs/product-spec', Guard.frozen_entry_for('docs/work/../product-spec/04-core.md', ROOT)
    assert_equal 'docs/knowledge', Guard.frozen_entry_for('docs/sdk-documentation/../knowledge/x.md', ROOT)
    assert_equal 'docs/product-spec', Guard.frozen_entry_for('docs/work/mvp/../../product-spec/x.md', ROOT)
  end

  def test_a_dotdot_segment_that_escapes_upward_is_not_mistaken_for_containment
    refute Guard.frozen?('docs/product-spec/../work/mvp/phase1/x.md', ROOT)
    refute Guard.frozen?('docs/knowledge/../README.md', ROOT)
  end

  # Bypass 3. An absolute path is resolved against nothing; it is already resolved.
  def test_an_absolute_path_is_resolved_not_treated_as_relative
    assert_equal 'docs/product-spec', Guard.frozen_entry_for(File.join(ROOT, 'docs/product-spec/04.md'), ROOT)
    # Outside the repository is nobody's business, but is certainly not frozen.
    refute Guard.frozen?('/elsewhere/docs/product-spec/04.md', ROOT)
    refute Guard.frozen?('/docs/knowledge/x.md', ROOT)
  end

  # Bypass 4. Lexically `docs/work/...` escapes every frozen entry; physically it lands
  # inside `docs/product-spec`, and `mkdir_p` follows the link, so a purely lexical guard
  # says yes and `git mv` writes into the normative tree.
  def test_a_symlink_into_a_frozen_tree_is_refused
    Dir.mktmpdir('guard-symlink-') do |dir|
      root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(root, 'docs/product-spec'))
      File.symlink(File.join(root, 'docs/product-spec'), File.join(root, 'docs/work'))

      assert_equal 'docs/product-spec', Guard.frozen_entry_for('docs/work/mvp/phase9/x.md', root)
      assert_raises(Guard::FrozenPathError) { Guard.assert_writable!('docs/work/mvp/phase9/x.md', root) }
    end
  end

  def test_a_real_docs_work_directory_stays_writable
    # The other half: resolving symlinks must not make the ordinary tree frozen.
    Dir.mktmpdir('guard-real-') do |dir|
      root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(root, 'docs/product-spec'))
      FileUtils.mkdir_p(File.join(root, 'docs/work/mvp/phase9'))

      refute Guard.frozen?('docs/work/mvp/phase9/x.md', root)
      assert Guard.frozen?('docs/product-spec/04.md', root)
    end
  end

  def test_a_target_whose_ancestors_do_not_exist_yet_is_still_judged
    # The normal case for a move: nothing at the destination.
    Dir.mktmpdir('guard-absent-') do |dir|
      root = File.realpath(dir)

      assert_equal 'docs/product-spec', Guard.frozen_entry_for('docs/product-spec/new/deep/x.md', root)
      refute Guard.frozen?('docs/work/mvp/phase1/x.md', root)
    end
  end

  def test_everything_the_skill_is_allowed_to_write_stays_writable
    [
      'docs/README.md',
      'docs/open-items.md',
      'docs/sdk-documentation/architecture.md',
      'docs/work/mvp/phase1/2026-09-05-phase1-core-design.md',
      'docs/work/mvp/phase5/phase5a/2026-09-05-phase5a-plan.md',
      'docs/superpowers/specs/2026-09-05-x-design.md',
      'docs/assets/dexpace-wordmark-dark.svg',
      'CLAUDE.md',
      'README.md',
      'gems/dexpace-core/README.md'
    ].each do |path|
      refute Guard.frozen?(path, ROOT), path
      assert_equal path, Guard.assert_writable!(path, ROOT)
    end
  end

  def test_assert_writable_raises_a_frozen_path_error_naming_both_paths
    error = assert_raises(Guard::FrozenPathError) { Guard.assert_writable!('docs/product-spec/04-core.md', ROOT) }

    assert_equal 'docs/product-spec/04-core.md', error.path
    assert_equal 'docs/product-spec', error.entry
    assert_match(/refusing to write/, error.message)
  end

  def test_assert_all_writable_refuses_the_whole_batch
    batch = ['docs/README.md', 'docs/product-spec/04-core.md', 'CLAUDE.md']

    assert_raises(Guard::FrozenPathError) { Guard.assert_all_writable!(batch, ROOT) }
    assert_equal ['docs/README.md', 'CLAUDE.md'],
                 Guard.assert_all_writable!(['docs/README.md', 'CLAUDE.md'], ROOT)
  end

  def test_the_frozen_list_is_pinned
    # Widening this list is a decision about what a maintenance tool may edit. It has to be
    # a reviewed diff here rather than a silent constant change.
    assert_equal %w[
      docs/knowledge
      docs/product-spec
      docs/sdk-design-ruby
      docs/product-spec.md
      docs/sdk-design-ruby.md
    ], Guard::FROZEN
  end

  def test_frozen_symlinks_reports_a_frozen_entry_that_became_a_link
    Dir.mktmpdir('guard-frozen-link-') do |dir|
      root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(root, 'elsewhere'))
      FileUtils.mkdir_p(File.join(root, 'docs'))
      File.symlink(File.join(root, 'elsewhere'), File.join(root, 'docs/knowledge'))

      assert_equal ['docs/knowledge'], Guard.frozen_symlinks(root)
    end
  end

  def test_a_real_fixture_tree_has_no_frozen_symlinks
    Housekeeping::Fixture.with { |root| assert_empty Guard.frozen_symlinks(root) }
  end
end
