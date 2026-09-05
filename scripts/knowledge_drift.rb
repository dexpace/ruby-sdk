#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SPDX-License-Identifier: MIT
# scripts/knowledge_drift.rb
#
# Reports what has gone stale in `docs/knowledge/`, in two dimensions:
#
#   sources — every sha256 recorded in `harvested/SOURCES.md` against the file
#             on disk, so you can see which harvested entries describe a
#             document that has since changed.
#   keys    — every `<topic>/<8 hex>` a note cites, against the corpus, so you
#             can see which notes name a rule whose text no longer exists. A key
#             digests entry text; a re-harvest that rewords a rule breaks the
#             citation, and that is precisely when the note needs revisiting.
#
# Named for its subject rather than a verb, like `knowledge.rb`: a `verify_*`
# name in this directory belongs to the blocking gates, and this is a report.
#
# A report, not a gate, and deliberately not in CI: no drift state fails it.
# (A manifest that is missing or malformed still exits 2 — that is the report
# being unable to run, not a state it reports.) Two reasons. The styleguide root
# is a sibling repository addressed by an absolute path on the harvest machine,
# so those sources simply do not exist in a CI checkout — they are NOT
# VERIFIABLE, never a failure. And drift is normal: a design chapter that a
# phase edits to record an outcome SHOULD drift, and the fix is a re-harvest,
# which is a user-invoked skill rather than something CI can do.
#
# The states are OK, DRIFT, NOT VERIFIABLE and UNREADABLE.

require "optparse"
require_relative "knowledge"

module Knowledge
  # The per-source sha comparison and the per-note key comparison, printed.
  class DriftReport
    STATES = ["OK", "DRIFT", "NOT VERIFIABLE", "UNREADABLE"].freeze

    Result = Struct.new(:state, :actual, :detail)

    def initialize(paths, stdout: $stdout)
      @paths = paths
      @stdout = stdout
    end

    def run
      return no_corpus unless Dir.exist?(@paths.knowledge_dir)

      report_sources(SourceManifest.load(@paths).rows)
      report_keys
      0
    end

    private

    def no_corpus
      @stdout.puts("#{@paths.relative(@paths.knowledge_dir)} does not exist under #{@paths.root}; " \
                   "nothing has been harvested here yet, so nothing can have drifted.")
      0
    end

    def report_sources(rows)
      counts = STATES.to_h { |state| [state, 0] }
      rows.each do |row|
        result = state_of(row)
        counts[result.state] += 1
        next if result.state == "OK"

        @stdout.puts("#{result.state}\t#{row.path}\t#{detail_for(row, result)}")
      end

      @stdout.puts("\n#{rows.size} harvested sources: #{counts["OK"]} OK, #{counts["DRIFT"]} DRIFT, " \
                   "#{counts["NOT VERIFIABLE"]} NOT VERIFIABLE, #{counts["UNREADABLE"]} UNREADABLE.")
      if counts["DRIFT"].positive?
        @stdout.puts("A drifted source means the harvested entries derived from it describe an " \
                     "older revision. Re-harvest that source, or record what changed as a note " \
                     "under docs/knowledge/notes/. This check never fails the build.")
      end
      return unless counts["NOT VERIFIABLE"].positive?

      @stdout.puts("NOT VERIFIABLE is expected off the harvest machine: the styleguide root is a " \
                   "sibling repository at an absolute path. It is not a failure.")
    end

    # The manifest records a truncated digest, so compare at the recorded width.
    #
    # Only a missing file is NOT VERIFIABLE. An unreadable or wrong-typed path
    # reported as "not present" would hide inside the one state this report
    # teaches the reader to ignore — off the harvest machine, the styleguide
    # sources are legitimately absent.
    def state_of(row)
      path = @paths.resolve(row.path)
      digest = Digest::SHA256.file(path).hexdigest[0, row.sha.length]
      Result.new(digest == row.sha ? "OK" : "DRIFT", digest, nil)
    rescue Errno::ENOENT
      Result.new("NOT VERIFIABLE", nil, nil)
    rescue SystemCallError => error
      Result.new("UNREADABLE", nil, error.class.name)
    end

    def detail_for(row, result)
      case result.state
      when "DRIFT" then "recorded #{row.sha}, actual #{result.actual}"
      when "UNREADABLE" then "read failed: #{result.detail}"
      else "file not present in this checkout"
      end
    end

    # A note names the rule it overrides by key. Report every citation that no
    # longer resolves — the rule was reworded, so the note is describing
    # something that is not there any more.
    def report_keys
      corpus = Corpus.load(@paths, AppendixC.load(@paths).prefixes)
      dangling = corpus.dangling_keys
      dangling.each do |entry|
        @stdout.puts("STALE KEY\t#{entry[:note]}\tcites #{entry[:cited]}, which no entry carries")
      end

      resolved = corpus.entries.select(&:note?).sum { |note| note.overrides.size }
      @stdout.puts("\n#{resolved} note citation(s) resolve, #{dangling.size} do not.")
      return if dangling.empty?

      @stdout.puts("A stale key means the harvested rule was reworded or re-harvested. Re-read the " \
                   "rule, then update the note to the key it prints now.")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = nil
  begin
    OptionParser.new do |opts|
      opts.banner = "Usage: scripts/knowledge_drift.rb [options]"
      opts.separator ""
      opts.separator "Reports what has gone stale in docs/knowledge/: harvested sources whose"
      opts.separator "sha256 no longer matches the file on disk, and notes whose cited key no"
      opts.separator "longer resolves to an entry. A report, not a gate -- no drift state fails it."
      opts.separator ""
      opts.on("--root VALUE", "repository root (default: the parent of scripts/)") { |value| root = value }
      opts.on("-h", "--help", "print this message") do
        puts opts
        exit 0
      end
    end.parse!(ARGV)
    paths = root ? Knowledge::Paths.new(root) : Knowledge::Paths.default
    exit(Knowledge::DriftReport.new(paths).run)
  rescue Knowledge::UsageError, Knowledge::NotHarvested, OptionParser::ParseError => error
    warn(error.message)
    exit 2
  end
end
