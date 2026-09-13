# frozen_string_literal: true

# SPDX-License-Identifier: MIT
# .claude/skills/housekeeping/guard.rb
#
# The frozen-path guard. Two trees, one corpus and two files in `docs/` are read-only to
# this skill, and that has to be a check rather than a paragraph of good intent: the apply
# stage moves files, and a glob that widens by one segment is exactly how a maintenance
# tool eats a normative document.
#
# Every write the skill performs goes through `assert_writable!` or `assert_all_writable!`
# first. `test/guard_test.rb` is what proves it, including the four ways a naive prefix
# test gets it wrong: a sibling whose name merely starts with a frozen one, a `..` segment
# that lands inside after normalization, an absolute path, and a symlink whose target is
# inside a frozen tree while its own path is not.

require 'pathname'

module Housekeeping
  # Path-level authority on what this skill may write.
  module Guard
    # The five entries this skill must never write to. ONE constant; widening it is a
    # reviewed diff rather than a silent change scattered across call sites.
    #
    # `docs/knowledge/` covers both `harvested/` and `notes/`. `harvested/` cannot absorb a
    # hand edit at all -- a `<sub>` sha digests the whole source file rather than the
    # entry, so an edit inside one changes no sha and the next harvest regenerates or
    # duplicates it silently. `notes/` is hand-written and could in principle be edited; it
    # is frozen here because the corpus is read as one tree and a note's key citation
    # couples the two.
    #
    # Both SHAPES are represented on purpose, and the matcher has to handle each: a
    # directory prefix (`docs/product-spec`) and an exact file (`docs/product-spec.md`).
    # The directory entries also freeze the identically named `.md` table of contents only
    # because it is listed separately -- `docs/product-spec` does NOT cover
    # `docs/product-spec.md`, because the comparison is segment-wise.
    FROZEN = %w[
      docs/knowledge
      docs/product-spec
      docs/sdk-design-ruby
      docs/product-spec.md
      docs/sdk-design-ruby.md
    ].freeze

    # Raised instead of writing. Carries the offending path so a caller can report it.
    class FrozenPathError < StandardError
      attr_reader :path, :entry

      def initialize(path, entry)
        @path = path
        @entry = entry
        super(
          "refusing to write #{path}: it is under the frozen entry '#{entry}'. " \
          'The housekeeping skill reads the normative and harvested trees; it never ' \
          'writes to them. See docs/README.md.'
        )
      end
    end

    module_function

    # Which frozen entry `candidate` falls under, or `nil`.
    #
    # Resolved against `repo_root` and compared SEGMENT-WISE, never as a raw string prefix:
    # `docs/product-spec-draft/x.md` starts with `docs/product-spec` as characters and is
    # not under it as a path. `..` is normalized away first, so a path that spells its way
    # in cannot spell its way past the check -- and symlinks are resolved, so a path that
    # *links* its way in cannot either.
    def frozen_entry_for(candidate, repo_root = Dir.pwd)
      root = File.expand_path(repo_root.to_s)
      target = segments(resolve_nearest(File.expand_path(candidate.to_s, root)))
      FROZEN.find do |entry|
        under?(target, segments(resolve_nearest(File.expand_path(entry, root))))
      end
    end

    # `true` when `candidate` is a frozen entry or lives under one.
    def frozen?(candidate, repo_root = Dir.pwd)
      !frozen_entry_for(candidate, repo_root).nil?
    end

    # Raises `FrozenPathError` when `candidate` is frozen; returns it otherwise, so a call
    # site reads `File.write(Guard.assert_writable!(p), text)` and cannot forget the check.
    def assert_writable!(candidate, repo_root = Dir.pwd)
      entry = frozen_entry_for(candidate, repo_root)
      raise FrozenPathError.new(candidate, entry) unless entry.nil?

      candidate
    end

    # Guards a whole batch before any of it is performed, so a run cannot half-apply and
    # leave the tree between two states.
    def assert_all_writable!(candidates, repo_root = Dir.pwd)
      candidates.each { |candidate| assert_writable!(candidate, repo_root) }
      candidates
    end

    # Frozen entries that exist and are symlinks.
    #
    # A frozen tree replaced by a link is the one way the guard can be correct and useless
    # at the same time: it would keep refusing the path while the bytes it protects live
    # somewhere the skill happily writes. The probe reports it; nothing here repairs it.
    def frozen_symlinks(repo_root = Dir.pwd)
      root = File.expand_path(repo_root.to_s)
      FROZEN.select { |entry| File.symlink?(File.join(root, entry)) }
    end

    # `path` with every symlink in it resolved, as far as the filesystem actually goes.
    #
    # `File.expand_path` is purely lexical, so on its own it answers the wrong question:
    # with `docs/work` a symlink to `docs/product-spec`, `docs/work/mvp/x.md` lexically
    # escapes the frozen tree and physically lands inside it -- and `mkdir_p` follows the
    # link, so a `git mv` would write there while the guard said yes.
    #
    # A target that does not exist yet is the normal case for a move, so this walks up to
    # the nearest ancestor that does, resolves that, and re-attaches the tail.
    def resolve_nearest(path)
      current = Pathname.new(path)
      tail = []
      loop do
        begin
          resolved = current.realpath
          return (tail.empty? ? resolved : resolved.join(*tail)).cleanpath.to_s
        rescue SystemCallError
          parent = current.parent
          # Root reached without anything existing: answer lexically.
          return Pathname.new(path).cleanpath.to_s if parent.to_s == current.to_s

          tail.unshift(current.basename.to_s)
          current = parent
        end
      end
    end

    # Absolute path to its path segments. `/repo/docs/x.md` -> `["repo", "docs", "x.md"]`.
    def segments(absolute)
      absolute.split(File::SEPARATOR).reject(&:empty?)
    end

    # Containment, segment-wise. Equal paths count as contained, which is what makes a
    # frozen entry refuse itself.
    def under?(target, entry)
      !entry.empty? && entry.length <= target.length && target.first(entry.length) == entry
    end

    private_class_method :resolve_nearest, :segments, :under?
  end
end
