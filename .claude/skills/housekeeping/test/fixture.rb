# frozen_string_literal: true

# SPDX-License-Identifier: MIT
# .claude/skills/housekeeping/test/fixture.rb
#
# Builds a throwaway repository the probe and the apply stage can be pointed at, so a test
# can assert a check FIRES rather than asserting the live tree happens to be clean.
#
# The distinction is not academic. A suite that only asserts the real repository is clean
# passes just as happily over a check whose body has become `[]` -- and the real repository
# is clean most of the time, so the suite would be green for years while the checks rotted.
#
# `git init` runs here because the tree is a `Dir.mktmpdir` that this file also deletes.

require 'fileutils'
require 'open3'
require 'tmpdir'

module Housekeeping
  # A minimal Ruby-SDK-shaped repository the probe reports clean over.
  module Fixture
    # The counts the fixture's own documents state, and which its tree must satisfy:
    # two gems, one phase directory, one harvested topic.
    CLEAN_CLAIMS = <<~TEXT
      Two gems live under `gems/`, both published.

      One phase directory under docs/work/ so far, and one harvested topic in the corpus.
    TEXT

    module_function

    # `overrides` replaces or adds files after the clean tree is written; a value of `nil`
    # deletes. `untracked` is written after `git add`, so it stays untracked.
    def make(overrides: {}, untracked: {})
      root = File.realpath(Dir.mktmpdir('housekeeping-fixture-'))
      clean_tree.each { |path, text| write(root, path, text) }
      overrides.each { |path, text| text.nil? ? FileUtils.rm_rf(File.join(root, path)) : write(root, path, text) }
      commit(root)
      untracked.each { |path, text| write(root, path, text) }
      root
    end

    # Yields a fixture root and removes it afterwards, however the block leaves.
    def with(overrides: {}, untracked: {})
      root = make(overrides: overrides, untracked: untracked)
      begin
        yield root
      ensure
        remove(root)
      end
    end

    def remove(root)
      FileUtils.rm_rf(root)
    end

    def write(root, path, text)
      absolute = File.join(root, path)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, text)
      absolute
    end

    def symlink(root, target, link)
      absolute = File.join(root, link)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.symlink(File.join(root, target), absolute)
      absolute
    end

    def git(root, *args)
      out, err, status = Open3.capture3(
        { 'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_SYSTEM' => '/dev/null' },
        'git', '-c', 'user.email=fixture@example.invalid', '-c', 'user.name=fixture',
        '-c', 'commit.gpgsign=false', '-c', 'core.quotePath=false', *args, chdir: root
      )
      raise "git #{args.join(' ')} failed in #{root}: #{err}#{out}" unless status.success?

      out
    end

    def commit(root)
      git(root, 'init', '-q')
      git(root, 'add', '-A')
      git(root, 'commit', '-qm', 'fixture')
    end

    def gemspec(name)
      <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          spec.name = "#{name}"
          spec.version = "0.1.0"
          spec.summary = "fixture"
          spec.authors = ["fixture"]
          spec.files = []
        end
      RUBY
    end

    def readme(name)
      body = (1..24).map { |n| "Line #{n} of a README long enough to clear the thin-README floor." }
      "# #{name}\n\n#{body.join("\n")}\n"
    end

    def clean_tree
      {
        'README.md' => "# fixture\n\n#{CLEAN_CLAIMS}\n",
        'CLAUDE.md' => "# CLAUDE.md\n\n#{CLEAN_CLAIMS}\n\nSee [docs](docs/README.md).\n",
        'docs/README.md' => docs_readme,
        'docs/open-items.md' => "# Open items\n\n### OI-1 — a real item\n\nBody.\n",
        'docs/deferred-items.md' => "# Deferred items\n\n| ID | State |\n|---|---|\n| `DEF-2` | deferred |\n",
        'docs/superpowers/README.md' => "# the inbox\n\nNew documents land here and do not stay.\n",
        'docs/superpowers/specs/.gitkeep' => '',
        'docs/superpowers/plans/.gitkeep' => '',
        'docs/work/mvp/phase1/2026-01-01-phase1-thing.md' => "# phase 1\n\nSatisfies OI-1.\n",
        'docs/sdk-documentation/architecture.md' => "# architecture\n\nAs built.\n",
        'docs/knowledge/harvested/documentation.md' => "# documentation\n\nHarvested.\n",
        'docs/knowledge/harvested/INDEX.md' => "# index\n\nNot a topic.\n",
        'docs/knowledge/notes/pagination.md' => "# pagination\n\nHand written.\n",
        'gems/dexpace-core/dexpace-core.gemspec' => gemspec('dexpace-core'),
        'gems/dexpace-core/README.md' => readme('dexpace-core'),
        'gems/dexpace-serde-json/dexpace-serde-json.gemspec' => gemspec('dexpace-serde-json'),
        'gems/dexpace-serde-json/README.md' => readme('dexpace-serde-json')
      }
    end

    def docs_readme
      <<~TEXT
        # `docs/`

        #{CLEAN_CLAIMS}
        The index. See [the inbox](superpowers/README.md) and [DEF-2](deferred-items.md).
      TEXT
    end
  end
end
