#!/usr/bin/env ruby
# frozen_string_literal: true

# SPDX-License-Identifier: MIT
# .claude/skills/housekeeping/apply.rb
#
# The only stage that writes, and it does exactly one mechanical thing: drain the
# `docs/superpowers/{specs,plans}/` inbox into `docs/work/<delivery>/phaseN[/phaseNx]/`
# with `git mv`, so `git log --follow` resolves each file across the move.
#
#   ruby .claude/skills/housekeeping/apply.rb                          # dry run
#   ruby .claude/skills/housekeeping/apply.rb --delivery mvp --phase 5a --write
#   ruby .claude/skills/housekeeping/apply.rb --phase 5a \
#        --rename 2026-09-05-thing.md=2026-09-05-phase5a-thing.md --write
#
# Dry by default. `--write` performs; `--dry-run` states the default and prints the exact
# `git mv` commands it would run.
#
# Everything the probe reports that is NOT a file move -- a stale count, a missing gem
# README, a broken link, a dangling citation -- is prose, and prose is edited by whoever
# ran the probe. A tool that rewrites prose to make its own check pass produces
# documentation that is true and useless at the same time.

require 'fileutils'
require 'open3'
require 'optparse'

require_relative 'guard'

module Housekeeping
  # One `git mv`, unperformed.
  Move = Struct.new(:from, :to) do
    def command
      "git mv -- #{from} #{to}"
    end
  end

  # Plans and performs the inbox drain. Never rewrites prose; never repoints a link.
  class Apply
    INBOX = ['docs/superpowers/specs', 'docs/superpowers/plans'].freeze
    FURNITURE = ['README.md', '.gitkeep'].freeze
    PHASE = /\A(\d+)([a-z])?\z/
    # `2026-09-05-phase5a-transport-design.md` -> phase 5, sub-phase a.
    SUB_PHASE_IN_NAME = /-phase(\d+)([a-z])-/
    WHOLE_PHASE_IN_NAME = /-phase(\d+)[-.]/

    attr_reader :root, :delivery, :phase, :renames

    def initialize(root:, delivery: 'mvp', phase: nil, renames: {})
      @root = File.expand_path(root.to_s)
      @delivery = delivery
      @phase = phase
      raise ArgumentError, "--phase must look like 5 or 5a, got #{phase.inspect}" unless phase.nil? || PHASE.match?(phase)

      @renames = renames
    end

    # The moves this run would perform.
    def plan
      inbox_files.map { |from| Move.new(from, File.join(target_directory(from), renamed(from))) }
    end

    # Where a document belongs. `--phase` wins; otherwise the filename is read.
    #
    # A file naming a whole phase with no sub-phase letter -- a segmentation design, a
    # shared checklist -- sits at the `phaseN/` level. A file naming no phase at all sits
    # directly under the delivery.
    def target_directory(from)
      base = File.basename(from)
      if (match = PHASE.match(@phase.to_s))
        return phase_directory(match[1], match[2])
      end
      if (match = SUB_PHASE_IN_NAME.match(base))
        return phase_directory(match[1], match[2])
      end
      if (match = WHOLE_PHASE_IN_NAME.match(base))
        return phase_directory(match[1], nil)
      end

      "docs/work/#{@delivery}"
    end

    # Every reason this batch cannot be performed, as messages.
    #
    # All of them, not the first: an operator who fixes one refusal and is handed the next
    # one runs the tool four times to learn what it knew on the first run.
    def refusals(moves)
      frozen_paths(moves) + collisions(moves) + occupied(moves) + untracked(moves)
    end

    # Performs the batch. Returns the moves completed; raises with the completed list
    # attached if `git mv` fails part-way through.
    def perform(moves)
      # The whole batch is guarded again here, immediately before the first write, so
      # deleting the refusal-collecting call above cannot leave this stage unguarded.
      # `--delivery ../product-spec` is what this stops.
      Guard.assert_all_writable!(moves.flat_map { |move| [move.from, move.to] }, @root)
      done = []
      moves.each do |move|
        FileUtils.mkdir_p(File.join(@root, File.dirname(move.to)))
        out, err, status = git('mv', '--', move.from, move.to)
        raise HalfApplied.new("#{move.command} failed: #{(err + out).strip}", done) unless status.success?

        done << move
      end
      done
    end

    # Raised when `git mv` fails mid-batch. Carries how far it got, because an operator
    # left with a backtrace and an index in an unknown state has to reconstruct it by hand.
    class HalfApplied < StandardError
      attr_reader :done

      def initialize(message, done)
        @done = done
        super(message)
      end
    end

    private

    def phase_directory(number, letter)
      base = "docs/work/#{@delivery}/phase#{number}"
      letter.nil? ? base : "#{base}/phase#{number}#{letter}"
    end

    def renamed(from)
      base = File.basename(from)
      @renames[from] || @renames[base] || base
    end

    # The inbox, tracked and untracked alike: its NORMAL state is a file a global skill has
    # just written and nobody has staged.
    def inbox_files
      lines(git('ls-files', '--cached', '--others', '--exclude-standard', '--', *INBOX).first)
        .reject { |file| FURNITURE.include?(File.basename(file)) }
        .select { |file| file.end_with?('.md') }
        .sort
    end

    def frozen_paths(moves)
      moves.flat_map { |move| [move.from, move.to] }.filter_map do |path|
        entry = Guard.frozen_entry_for(path, @root)
        next if entry.nil?

        "#{path} is under the frozen entry '#{entry}'; this stage never writes there."
      end
    end

    # Two inbox files landing on ONE target. `specs/` and `plans/` are the two directories
    # the inbox uses, and a design and its plan can share a basename, so this is the likely
    # collision rather than the exotic one.
    def collisions(moves)
      moves.group_by(&:to).filter_map do |to, group|
        next if group.length < 2

        "#{group.map(&:from).join(' and ')} both land on #{to}. Rename one with --rename before collecting."
      end
    end

    def occupied(moves)
      moves.filter_map do |move|
        next unless File.exist?(File.join(@root, move.to))

        "#{move.to} already exists (from #{move.from})."
      end
    end

    def untracked(moves)
      cached = lines(git('ls-files', '--cached', '--', *INBOX).first)
      moves.map(&:from).reject { |from| cached.include?(from) }.map do |from|
        "#{from} is not tracked; `git mv` cannot move it. Run `git add #{from}` first -- a " \
        'phase document is worth a commit of its own before it moves, so history follows it.'
      end
    end

    def git(*args)
      Open3.capture3('git', '-c', 'core.quotePath=false', *args, chdir: @root)
    end

    def lines(text)
      text.split("\n").reject(&:empty?)
    end
  end

  # `apply.rb`'s command line.
  class ApplyCLI
    def self.run(argv, out: $stdout, err: $stderr)
      new(argv).run(out, err)
    end

    def initialize(argv)
      @argv = argv.dup
      @options = { delivery: 'mvp', phase: nil, renames: {}, write: false, root: nil }
    end

    def run(out, err)
      parser.parse!(@argv)
      apply = Apply.new(root: @options[:root] || self.class.repo_root,
                        delivery: @options[:delivery], phase: @options[:phase],
                        renames: @options[:renames])
      moves = apply.plan
      return empty(out) if moves.empty?

      stop = apply.refusals(moves)
      return refuse(err, stop) unless stop.empty?

      @options[:write] ? write(out, err, apply, moves) : dry_run(out, moves)
    rescue ArgumentError, OptionParser::ParseError, Guard::FrozenPathError => e
      err.puts("refusing: #{e.message}")
      1
    end

    def self.repo_root
      out, _err, status = Open3.capture3('git', 'rev-parse', '--show-toplevel', chdir: __dir__)
      status.success? ? out.strip : File.expand_path('../../..', __dir__)
    end

    private

    def parser
      OptionParser.new do |opts|
        opts.banner = 'usage: ruby .claude/skills/housekeeping/apply.rb [options]'
        opts.on('--delivery NAME', 'unit of delivery under docs/work/ (default: mvp)') { |v| @options[:delivery] = v }
        opts.on('--phase N[x]', 'file everything under phaseN, or phaseN/phaseNx') { |v| @options[:phase] = v }
        opts.on('--rename FROM=TO', 'rename one file as it moves; repeatable') do |v|
          from, to = v.split('=', 2)
          raise OptionParser::InvalidArgument, "wants FROM=TO, got #{v}" if to.nil? || to.empty?

          @options[:renames][from] = to
        end
        opts.on('--write', 'perform the moves (default is a dry run)') { @options[:write] = true }
        opts.on('--dry-run', 'print the git mv commands and stop (the default)') { @options[:write] = false }
        opts.on('--root PATH', 'operate on this tree instead of the enclosing repository') { |v| @options[:root] = v }
        opts.on('-h', '--help', 'this message') do
          puts opts
          exit 0
        end
      end
    end

    def empty(out)
      out.puts('the inbox is empty; nothing to collect.')
      0
    end

    def refuse(err, stop)
      stop.each { |message| err.puts("refusing: #{message}") }
      err.puts("#{stop.length} refusal(s); the whole batch was declined, so the tree is untouched.")
      1
    end

    def dry_run(out, moves)
      moves.each { |move| out.puts(move.command) }
      out.puts
      out.puts("#{moves.length} move(s) planned. Re-run with --write to perform them.")
      0
    end

    def write(out, err, apply, moves)
      done = apply.perform(moves)
      done.each { |move| out.puts(move.command) }
      out.puts
      out.puts("#{done.length} file(s) collected. Two things this stage did NOT do:")
      out.puts('  1. Repoint references to the old paths. Re-run the probe\'s links and citations')
      out.puts('     checks and fix what they report, in the same commit as this move.')
      out.puts('  2. Commit. A migration is its own commit, git mv only, so `git log --follow` works.')
      0
    rescue Apply::HalfApplied => e
      err.puts("#{e.done.length} of #{moves.length} move(s) were performed before this failed:")
      e.done.each { |move| err.puts("  #{move.command}") }
      err.puts(e.message)
      err.puts('The tree is half-collected. `git status` shows the completed moves; finish or revert them.')
      1
    end
  end
end

exit(Housekeeping::ApplyCLI.run(ARGV)) if $PROGRAM_NAME == __FILE__
