#!/usr/bin/env ruby
# frozen_string_literal: true

# SPDX-License-Identifier: MIT
# .claude/skills/housekeeping/probe.rb
#
# Read-only. Reports documentation drift; never writes.
#
#   ruby .claude/skills/housekeeping/probe.rb
#   ruby .claude/skills/housekeeping/probe.rb --only links,citations
#   ruby .claude/skills/housekeeping/probe.rb --json
#   ruby .claude/skills/housekeeping/probe.rb --warn-only     # report, exit 0
#   ruby .claude/skills/housekeeping/probe.rb --root /tmp/a-fixture-tree
#
# The checks are deliberately independent, and each derives a repository fact ONCE, from
# the repository, then compares every document that states it against that one derivation.
# Nothing here reads a number out of one document and compares it to another.
#
# `--root` exists for `test/probe_test.rb`, which builds throwaway fixture trees and
# asserts each check FIRES. A suite that only asserts the live tree is clean passes just as
# happily over a check whose body has become `[]`.

require 'json'
require 'open3'
require 'optparse'
require 'pathname'
require 'set'

require_relative 'guard'

module Housekeeping
  # One thing a check found. `line` is 1 for a finding about a file as a whole.
  Finding = Struct.new(:check, :severity, :path, :line, :message) do
    def to_s
      "#{path}:#{line}: [#{severity}] #{message}"
    end
  end

  # Everything a check is allowed to do to a repository: read it and list it.
  #
  # The root is a constructor argument rather than a constant so a fixture tree can be
  # probed; that is the only reason this indirection exists.
  class Repo
    attr_reader :root

    def initialize(root)
      @root = File.expand_path(root.to_s)
    end

    def abs(rel)
      File.join(@root, rel)
    end

    def exist?(rel)
      File.exist?(abs(rel))
    end

    def dir?(rel)
      File.directory?(abs(rel))
    end

    def read(rel)
      File.read(abs(rel), encoding: 'UTF-8')
    end

    # Immediate child names of a directory, sorted; `[]` when it is absent.
    def children(rel)
      return [] unless dir?(rel)

      Dir.children(abs(rel)).sort
    end

    # Tracked paths matching `pathspecs`.
    #
    # `-c core.quotePath=false` because `git ls-files` C-quotes any path with a non-ASCII
    # byte by default (`"docs/caf\303\251.md"`), and a quoted path fed back to `File.read`
    # is an ENOENT that takes the whole run down with a backtrace instead of a finding.
    #
    # `ls-files` lists the INDEX, so a file deleted in the working tree and not yet staged
    # is still listed; every caller goes on to read what it gets back, so the result is
    # filtered to what is actually on disk.
    def tracked(*pathspecs)
      list('ls-files', '--', *pathspecs)
    end

    # Tracked paths PLUS untracked, non-ignored ones.
    #
    # The inbox's NORMAL state is a file a global skill has just written and nobody has
    # staged, so a tracked-only sweep reports the empty tree this skill exists to notice.
    def present(*pathspecs)
      list('ls-files', '--cached', '--others', '--exclude-standard', '--', *pathspecs)
    end

    def git(*args)
      out, _err, status = Open3.capture3('git', '-c', 'core.quotePath=false', *args, chdir: @root)
      status.success? ? out : ''
    end

    private

    def list(*args)
      git(*args).split("\n").reject(&:empty?).uniq.select { |path| exist?(path) }
    end
  end

  # Spelled-out numerals.
  #
  # Count claims in prose are written as English words at least as often as digits --
  # "eleven gems", "nine phase directories". A digits-only matcher protects roughly one
  # sentence per repository, which is the same as protecting none.
  module Numeral
    ONES = %w[
      zero one two three four five six seven eight nine ten eleven twelve thirteen
      fourteen fifteen sixteen seventeen eighteen nineteen
    ].freeze
    TENS = {
      'twenty' => 20, 'thirty' => 30, 'forty' => 40, 'fifty' => 50,
      'sixty' => 60, 'seventy' => 70, 'eighty' => 80, 'ninety' => 90
    }.freeze

    # A digit run, or a word that might be a numeral; `parse` decides which.
    TOKEN = /(\d+|[A-Za-z]+(?:-[A-Za-z]+)?)/

    module_function

    # The number `token` denotes, or `nil` when it is not a numeral at all.
    def parse(token)
      word = token.to_s.downcase
      return Integer(word, 10) if /\A\d+\z/.match?(word)

      ones = ONES.index(word)
      return ones unless ones.nil?
      return TENS[word] if TENS.key?(word)

      compound = /\A([a-z]+)-([a-z]+)\z/.match(word)
      return nil if compound.nil? || !TENS.key?(compound[1])

      unit = ONES.index(compound[2])
      return nil if unit.nil? || unit.zero? || unit >= 10

      TENS[compound[1]] + unit
    end
  end

  # Text helpers shared by the checks that read prose.
  module Prose
    module_function

    # A line indented 4+ spaces or led by a tab: a Markdown indented code block.
    INDENTED_LINE = /\A(?: {4,}|\t)/
    # An inline code span: `` `like this` ``.
    INLINE_CODE = /`[^`\n]+`/

    # `text` with fenced code blocks blanked and double-quoted spans blanked, preserving
    # every line break so a match's line number is still the file's line number.
    #
    # Fenced code is not prose, and a double-quoted span is reported speech: a document
    # that quotes the historical drift it fixed -- `"two published gems" against eleven` --
    # is describing a past claim, not making a present one. Matching inside either turns a
    # document that explains its own history into a document that fails its own check.
    def asserted(text)
      fenced_blanked(text).gsub(/"[^"\n]*"/) { |span| ' ' * span.length }
    end

    # `text` with all the code a document can carry blanked -- fenced blocks, inline code
    # spans and 4-space/tab-indented blocks -- so a link or a citation ID that appears only
    # as an EXAMPLE, inside code, is not read as an actual link or citation. Quoted prose
    # spans are left alone; line count is preserved throughout.
    def unfenced(text)
      strip_inline_code(strip_indented(fenced_blanked(text)))
    end

    def line_at(text, index)
      text[0, index].count("\n") + 1
    end

    # `text` with ``` ... ``` fences blanked, one line per line.
    def fenced_blanked(text)
      in_fence = false
      text.each_line.map do |line|
        if line.start_with?('```')
          in_fence = !in_fence
          "\n"
        else
          in_fence ? "\n" : line
        end
      end.join
    end

    # `text` with every 4-space/tab-indented line blanked whole, so the line count survives
    # a multi-line indented block untouched.
    def strip_indented(text)
      text.each_line.map { |line| INDENTED_LINE.match?(line) ? "\n" : line }.join
    end

    # `text` with every inline code span replaced by same-length blanks, so a link or ID
    # next to one keeps its position and the line count never changes.
    def strip_inline_code(text)
      text.gsub(INLINE_CODE) { |span| ' ' * span.length }
    end
  end

  # The eight read-only checks. Each is a class with `name` and `run(repo) -> [Finding]`.
  module Checks
    # Base class: supplies `name` from the subclass's `NAME` and a `Finding` factory.
    class Check
      def name
        self.class::NAME
      end

      def run(_repo)
        raise NotImplementedError, "#{self.class} must implement #run"
      end

      private

      def act(path, line, message)
        Finding.new(name, 'act', path, line, message)
      end

      def note(path, line, message)
        Finding.new(name, 'note', path, line, message)
      end
    end

    # 1. `docs/superpowers/{specs,plans}/` is an inbox. Anything in it is unfiled.
    class Inbox < Check
      NAME = 'inbox'
      INBOX = ['docs/superpowers/specs', 'docs/superpowers/plans'].freeze
      # A directory's placeholder and its explainer are furniture, not documents.
      FURNITURE = ['README.md', '.gitkeep'].freeze

      def run(repo)
        repo.present(*INBOX)
            .reject { |file| FURNITURE.include?(File.basename(file)) }
            .map do |file|
              act(file, 1,
                  'is still in the inbox. It belongs under ' \
                  'docs/work/<delivery>/phaseN[/phaseNx]/ -- see docs/README.md, then run ' \
                  'apply.rb.')
            end
      end
    end

    # 2. Markdown at the repository root that belongs under `docs/`.
    class Root < Check
      NAME = 'root'
      ALLOWED = %w[
        README.md CLAUDE.md CONTRIBUTING.md CHANGELOG.md CODE_OF_CONDUCT.md
        SECURITY.md LICENSE.md
      ].freeze

      def run(repo)
        # A pathspec glob crosses `/`, so `*.md` matches at any depth; the root is what
        # this check is about, so files with a directory component are filtered out.
        repo.present('*.md')
            .reject { |file| file.include?('/') || ALLOWED.include?(file) }
            .map do |file|
              act(file, 1,
                  'sits at the repository root. A register belongs in docs/, a phase ' \
                  'record under docs/work/. The root carries README.md, CLAUDE.md and the ' \
                  'community-health files only.')
            end
      end
    end

    # 3. Counts stated in the three index documents, against the repository.
    #
    # The table below is the whole check. A new claim is one row: the file that states it,
    # the pattern whose first capture is the number, a label, and a lambda that derives the
    # real value from the repository. A file that does not exist, or that does not carry
    # the pattern at all, is a no-op -- this reports a WRONG count, not a missing sentence.
    class Claims < Check
      NAME = 'claims'
      Claim = Struct.new(:file, :pattern, :label, :actual)

      def run(repo)
        table(repo).flat_map { |claim| check(repo, claim) }
      end

      private

      def table(repo)
        gems = -> { gem_count(repo) }
        phases = -> { phase_count(repo) }
        topics = -> { topic_count(repo) }
        [
          Claim.new('CLAUDE.md',      numbered(/(?:\*\*)?gems\b/),              'gems under gems/', gems),
          Claim.new('README.md',      numbered(/(?:\*\*)?gems\b/),              'gems under gems/', gems),
          Claim.new('docs/README.md', numbered(/(?:\*\*)?gems\b/),              'gems under gems/', gems),
          Claim.new('CLAUDE.md',      numbered(/phase\s+director(?:y|ies)\b/),  'phase directories under docs/work/', phases),
          Claim.new('docs/README.md', numbered(/phase\s+director(?:y|ies)\b/),  'phase directories under docs/work/', phases),
          Claim.new('CLAUDE.md',      numbered(/harvested\s+topics?\b/),        'topics under docs/knowledge/harvested/', topics),
          Claim.new('docs/README.md', numbered(/harvested\s+topics?\b/),        'topics under docs/knowledge/harvested/', topics)
        ]
      end

      # `<numeral> <tail>`, case-insensitive, first capture holding the numeral.
      def numbered(tail)
        Regexp.new("#{Numeral::TOKEN.source}\\s+#{tail.source}", Regexp::IGNORECASE)
      end

      def check(repo, claim)
        return [] unless repo.exist?(claim.file)

        prose = Prose.asserted(repo.read(claim.file))
        actual = claim.actual.call
        findings = []
        offset = 0
        while (match = claim.pattern.match(prose, offset))
          offset = match.end(0)
          stated = Numeral.parse(match[1])
          next if stated.nil? || stated == actual # an adjective, not a numeral

          findings << act(claim.file, Prose.line_at(prose, match.begin(0)),
                          "states \"#{match[0].strip}\" but the repository has " \
                          "#{actual} #{claim.label}.")
        end
        findings
      end

      # Every directory under `gems/` that carries a gemspec. Absent `gems/` is 0, not an
      # error: the monorepo grows into this shape and every check must no-op until it does.
      def gem_count(repo)
        repo.children('gems').count do |dir|
          repo.dir?("gems/#{dir}") && !Dir.glob(repo.abs("gems/#{dir}/*.gemspec")).empty?
        end
      end

      # `phaseN` directories directly under a delivery. Sub-phases nest INSIDE one of these
      # and are deliberately not counted twice.
      def phase_count(repo)
        repo.children('docs/work').sum do |delivery|
          repo.children("docs/work/#{delivery}")
              .count { |entry| /\Aphase\d+\z/.match?(entry) && repo.dir?("docs/work/#{delivery}/#{entry}") }
        end
      end

      # Topic files in the harvested corpus. `INDEX.md`, `SOURCES.md` and `README.md` are
      # furniture of the corpus, not topics themselves.
      NON_TOPIC_FILES = %w[INDEX.md SOURCES.md README.md].freeze

      def topic_count(repo)
        repo.children('docs/knowledge/harvested')
            .count { |file| file.end_with?('.md') && !NON_TOPIC_FILES.include?(file) }
      end
    end

    # 4. A README on every gem, naming the gem its gemspec declares.
    class Readmes < Check
      NAME = 'readmes'
      # The bar is zero to one working call in about 30 seconds without reading source.
      # Lines rather than bytes, because a Ruby README's first working example is a fenced
      # block and a line count is what a writer can see.
      MIN_LINES = 20
      GEMSPEC_NAME = /^\s*\w+\.name\s*=\s*["']([^"']+)["']/
      FIRST_HEADING = /^\#\s+(.+)$/

      def run(repo)
        return [] unless repo.dir?('gems')

        repo.children('gems').select { |dir| repo.dir?("gems/#{dir}") }
            .flat_map { |dir| check_gem(repo, dir) }
      end

      private

      def check_gem(repo, dir)
        gemspec = Dir.glob(repo.abs("gems/#{dir}/*.gemspec")).sort.first
        return [act("gems/#{dir}", 1, 'has no gemspec. Every directory under gems/ is a published gem.')] if gemspec.nil?

        name = GEMSPEC_NAME.match(File.read(gemspec, encoding: 'UTF-8'))&.[](1) || dir
        readme = "gems/#{dir}/README.md"
        return [act(readme, 1, "is missing. Every gem ships a README (#{name}).")] unless repo.exist?(readme)

        text = repo.read(readme)
        findings = []
        if text.lines.count < MIN_LINES
          findings << note(readme, 1,
                           "is #{text.lines.count} lines. The bar is #{MIN_LINES}: zero to one " \
                           'working call in about 30 seconds, without reading source.')
        end
        heading = FIRST_HEADING.match(text)
        if heading.nil?
          findings << act(readme, 1, 'has no top-level `# ` heading.')
        elsif !heading[1].include?(name)
          findings << act(readme, Prose.line_at(text, heading.begin(0)),
                          "opens with \"#{heading[1].strip}\" but its gemspec declares #{name}.")
        end
        findings
      end
    end

    # 5. Broken relative links.
    class Links < Check
      NAME = 'links'
      LINK = /\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/
      # `[text][ref]`, or the collapsed `[text][]` that reuses `text` as the ref.
      REFERENCE = /\[([^\]]+)\]\[([^\]]*)\]/
      # `[ref]: target`, optionally titled -- a reference-style link's definition.
      DEFINITION = /^\[([^\]]+)\]:\s*(\S+)(?:\s+"[^"]*")?\s*$/
      # Anything the filesystem cannot answer for.
      EXTERNAL = %r{\A(?:https?:|mailto:|#)}

      def run(repo)
        files(repo).flat_map { |file| check_file(repo, file) }
      end

      private

      def files(repo)
        (repo.present('docs') +
         repo.present('*.md').reject { |file| file.include?('/') } +
         repo.present('gems/*/README.md')).uniq.select { |file| file.end_with?('.md') }
      end

      def check_file(repo, file)
        text = Prose.unfenced(repo.read(file))
        definitions = reference_definitions(text)
        findings = []
        text.each_line.with_index(1) do |line, number|
          findings.concat(inline_findings(repo, file, line, number))
          findings.concat(reference_findings(repo, file, line, number, definitions))
        end
        findings
      end

      def inline_findings(repo, file, line, number)
        line.scan(LINK).filter_map do |(raw)|
          resolved = resolve(file, raw)
          next if resolved.nil? || repo.exist?(resolved)

          act(file, number, "links #{raw}, which resolves to #{resolved} -- a path that does not exist.")
        end
      end

      def reference_findings(repo, file, line, number, definitions)
        line.scan(REFERENCE).filter_map do |(text_part, raw_ref)|
          key = (raw_ref.empty? ? text_part : raw_ref).strip.downcase
          target = definitions[key]
          if target.nil?
            next act(file, number, "references [#{key}], which has no [#{key}]: definition in this file.")
          end

          resolved = resolve(file, target)
          next if resolved.nil? || repo.exist?(resolved)

          act(file, number, "references [#{key}], which resolves to #{resolved} -- a path that does not exist.")
        end
      end

      # Every `[ref]: target` definition in the file, keyed the way Markdown resolves a
      # reference -- case-insensitively, trimmed.
      def reference_definitions(text)
        text.each_line.with_object({}) do |line, definitions|
          match = DEFINITION.match(line)
          next if match.nil?

          definitions[match[1].strip.downcase] = match[2]
        end
      end

      # The repository-relative path `raw` points at, or `nil` when it is not a path.
      def resolve(file, raw)
        return nil if EXTERNAL.match?(raw)

        target = raw.split('#').first.to_s
        return nil if target.empty?

        Pathname.new(File.join(File.dirname(file), percent_decode(target))).cleanpath.to_s
      end

      def percent_decode(str)
        str.gsub(/%([0-9A-Fa-f]{2})/) { [::Regexp.last_match(1)].pack('H2') }
      end
    end

    # 6. An aggregate register living inside a specification, design or plan document.
    class Registers < Check
      NAME = 'registers'
      REGISTER = 'docs/open-items.md'
      TREES = %w[
        docs/work docs/superpowers docs/sdk-documentation
        docs/product-spec docs/sdk-design-ruby
      ].freeze
      HEADINGS = [
        /^\#\#\s+Open Findings\b.*$/,
        /^\#\#\s+Deferred Items\b.*$/,
        /^\#\#\s+Open Items\s*$/
      ].freeze
      # A pointer stub is a paragraph saying where the register went, not a register.
      STUB = /^\*\*Moved out on /

      def run(repo)
        repo.present(*TREES).select { |file| file.end_with?('.md') }
            .flat_map { |file| check_file(repo, file) }
      end

      private

      def check_file(repo, file)
        text = repo.read(file)
        HEADINGS.filter_map do |heading|
          match = heading.match(text)
          next if match.nil? || STUB.match?(text[match.begin(0), 600].to_s)

          act(file, Prose.line_at(text, match.begin(0)),
              "carries \"#{match[0].strip}\". An aggregate register belongs in #{REGISTER}. " \
              "A phase's own dated section stays with the phase; the aggregate does not.")
        end
      end
    end

    # 7. Every register item ID cited anywhere resolves to an item in ITS OWN register.
    #
    # There are two registers, not one: `OI-<n>` resolves only against `docs/open-items.md`,
    # `DEF-<n>` only against `docs/deferred-items.md`. A prefix's definitions are scanned
    # from its own file only, so a heading or table row with the wrong prefix's shape sitting
    # in the wrong file (an `OI-5` heading accidentally left in `deferred-items.md`, say)
    # resolves nothing -- the file, not just the pattern, has to match.
    #
    # The ID namespace is a declared list of prefixes rather than `[A-Z]+-\d+`, which would
    # swallow every requirement ID in the spec (`HTTP-7`, `SEAM-1`, `NFR-5`) and report the
    # entire corpus as dangling. Adding a register prefix is one entry in REGISTERS.
    class Citations < Check
      NAME = 'citations'
      REGISTERS = { 'OI' => 'docs/open-items.md', 'DEF' => 'docs/deferred-items.md' }.freeze
      ID = "(?:#{REGISTERS.keys.join('|')})-\\d+"
      CITATION = Regexp.new('\b(' + ID + ')\b')
      TREES = ['docs', '*.md', 'gems', 'lib', 'scripts', '.claude'].freeze
      READABLE = /\.(?:md|rb|rake)\z/
      # A skill's own test fixtures invent a register and cite it. Those IDs are literals in
      # a throwaway tree, not citations of this repository's register.
      EXCLUDED = %r{\A\.claude/skills/[^/]+/test/}

      def run(repo)
        active = REGISTERS.select { |_prefix, file| repo.exist?(file) }
        return [] if active.empty?

        known = known_ids(repo, active)
        cited_files(repo).flat_map { |file| check_file(repo, file, known, active) }
      end

      private

      # `### OI-12`, or a table row whose first cell is the ID, backticked or not. Both
      # shapes, so a register can be a list of sections or a table of rows without this
      # check caring which -- that is the generalisation of a hard-coded archive filename.
      def definition_pattern(prefix)
        Regexp.new('^(?:#{2,6}\s+|\|\s*)`?(' + prefix + '-\d+)`?\b')
      end

      # Every defined ID, scanned from its OWN register file only -- an `active` map of
      # prefix => file, each read once.
      def known_ids(repo, active)
        active.each_with_object(Set.new) do |(prefix, file), ids|
          ids.merge(repo.read(file).scan(definition_pattern(prefix)).flatten)
        end
      end

      def cited_files(repo)
        (repo.present(*TREES).select { |file| READABLE.match?(file) && !EXCLUDED.match?(file) }) - REGISTERS.values
      end

      def check_file(repo, file, known, active)
        findings = []
        Prose.unfenced(repo.read(file)).each_line.with_index(1) do |line, number|
          line.scan(CITATION) do |(id)|
            prefix = id.split('-', 2).first
            register = active[prefix]
            next if register.nil? # that prefix's register does not exist yet: no-op, as before
            next if known.include?(id)

            findings << act(file, number,
                            "cites #{id}, which has no entry in #{register}. Item IDs are " \
                            'permanent; a dangling one means the citation, not the register, is wrong.')
          end
        end
        findings
      end
    end

    # 8. The guard itself: the frozen list and the writable surface must not overlap, and a
    #    frozen entry must not have become a symlink out of its own tree.
    class GuardCheck < Check
      NAME = 'guard'
      # Every surface this skill, or a routine edit, is allowed to write.
      WRITABLE_SURFACE = %w[
        docs/README.md docs/open-items.md docs/deferred-items.md docs/sdk-documentation docs/work
        docs/superpowers docs/assets CLAUDE.md README.md
      ].freeze
      # Paths the guard must refuse, whether or not they exist yet. A guard that has
      # quietly stopped refusing is worse than no guard: the apply stage would still say
      # it checked.
      MUST_REFUSE = %w[
        docs/product-spec/04.md docs/product-spec.md docs/knowledge/notes/x.md
        docs/knowledge/harvested/documentation.md docs/sdk-design-ruby.md
        docs/sdk-design-ruby/10-deviations.md
      ].freeze

      def run(repo)
        overlaps(repo) + gaps(repo) + symlinks(repo)
      end

      private

      def overlaps(repo)
        WRITABLE_SURFACE.filter_map do |path|
          entry = Guard.frozen_entry_for(path, repo.root)
          next if entry.nil?

          act(path, 1, "is on the writable surface AND under the frozen entry '#{entry}'. " \
                       'One of the two lists is wrong; until it is fixed the apply stage could eat a normative document.')
        end
      end

      def gaps(repo)
        MUST_REFUSE.filter_map do |path|
          next if Guard.frozen?(path, repo.root)

          act(path, 1, 'is not refused by the guard. Run test/guard_test.rb.')
        end
      end

      def symlinks(repo)
        Guard.frozen_symlinks(repo.root).map do |entry|
          act(entry, 1, 'is a symlink. A frozen entry must be a real path, or the guard ' \
                        'protects a name while the bytes live somewhere writable.')
        end
      end
    end
  end

  # Runs the checks and collects their findings.
  class Probe
    ALL = [
      Checks::Inbox, Checks::Root, Checks::Claims, Checks::Readmes,
      Checks::Links, Checks::Registers, Checks::Citations, Checks::GuardCheck
    ].freeze
    NAMES = ALL.map { |check| check::NAME }.freeze

    attr_reader :repo

    def initialize(repo, only: nil)
      @repo = repo
      unknown = Array(only) - NAMES
      raise ArgumentError, "unknown check(s): #{unknown.join(', ')}. Known: #{NAMES.join(', ')}" unless unknown.empty?

      @selected = only.nil? || only.empty? ? NAMES : Array(only)
    end

    def checks
      ALL.select { |check| @selected.include?(check::NAME) }
    end

    def run
      checks.flat_map { |check| check.new.run(@repo) }
    end
  end

  # `probe.rb`'s command line: argument parsing, rendering and the exit code.
  class ProbeCLI
    def self.run(argv, out: $stdout, err: $stderr)
      new(argv).run(out, err)
    end

    def initialize(argv)
      @argv = argv.dup
      @options = { only: nil, json: false, warn_only: false, root: nil }
    end

    def run(out, err)
      parser.parse!(@argv)
      repo = Repo.new(@options[:root] || self.class.repo_root)
      findings = Probe.new(repo, only: @options[:only]).run
      @options[:json] ? render_json(out, repo, findings) : render_text(out, repo, findings)
      findings.empty? || @options[:warn_only] ? 0 : 1
    rescue ArgumentError, OptionParser::ParseError => e
      err.puts(e.message)
      2
    end

    # The repository this script lives in, so it can be run from anywhere.
    def self.repo_root
      out, _err, status = Open3.capture3('git', 'rev-parse', '--show-toplevel', chdir: __dir__)
      status.success? ? out.strip : File.expand_path('../../..', __dir__)
    end

    private

    def parser
      OptionParser.new do |opts|
        opts.banner = 'usage: ruby .claude/skills/housekeeping/probe.rb [options]'
        opts.on('--only CHECKS', Array, "run only these checks (#{Probe::NAMES.join(',')})") do |v|
          @options[:only] = v.map(&:strip).reject(&:empty?)
        end
        opts.on('--json', 'emit findings as JSON') { @options[:json] = true }
        opts.on('--warn-only', 'report findings but exit 0') { @options[:warn_only] = true }
        opts.on('--root PATH', 'probe this tree instead of the enclosing repository') { |v| @options[:root] = v }
        opts.on('-h', '--help', 'this message') do
          puts opts
          exit 0
        end
      end
    end

    def render_json(out, repo, findings)
      out.puts(JSON.pretty_generate(
                 root: repo.root,
                 checks: @options[:only] || Probe::NAMES,
                 findings: findings.map(&:to_h),
                 summary: { findings: findings.length, checks_with_findings: findings.map(&:check).uniq.length }
               ))
    end

    def render_text(out, repo, findings)
      out.puts('housekeeping probe -- read-only')
      out.puts("repository: #{repo.root}")
      out.puts
      if findings.empty?
        out.puts('no drift found.')
        return
      end
      findings.group_by(&:check).each do |check, items|
        out.puts("## #{check} (#{items.length})")
        items.each { |item| out.puts("  #{item}") }
        out.puts
      end
      out.puts("#{findings.length} finding(s) across #{findings.map(&:check).uniq.length} check(s). " \
               'This stage writes nothing -- read them, then run apply.rb for the one mechanical repair.')
    end
  end
end

exit(Housekeeping::ProbeCLI.run(ARGV)) if $PROGRAM_NAME == __FILE__
