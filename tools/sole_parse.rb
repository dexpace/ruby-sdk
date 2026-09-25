# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "ast_scan"

# The body of gates:sole_parse (phase 10, design addendum A9; NFR-6, NFR-17).
#
# AstScan.parse opens a `$VERBOSE = nil` window around `RubyVM::AbstractSyntaxTree.parse_file`,
# because a SCANNED file's own -w diagnostics reach `Warning.warn` and fire phase 0's FatalWarnings.
# The rule that keeps that the single entry point was a comment in tools/ast_scan.rb ("nothing else
# in this file may call `parse_file`"); this is the assertion, over every repository tool.
#
# Scoped to a `parse_file` whose receiver is the constant `RubyVM::AbstractSyntaxTree` -- `Prism`'s
# `parse_file` (tools/gemspec_audit.rb, require_scan.rb, serde_boundary.rb) returns its diagnostics
# on the result and never routes them through `Warning.warn`, so it is not this hazard and a
# receiver-blind scan reports three false positives there. The reflective spellings
# (`send(:parse_file, …)`, `public_send("parse_file", …)`) on the same receiver are caught too, by
# Symbol on `:LIT` (3.2, 3.3) and `:SYM` (3.4, 4.0) alike.
#
# Deliberately NOT built on AstScan.receiver_calls: that helper records a direct hit only when the
# send carries no argument (5b's `Event#cause(error)` narrowing), and every `parse_file` carries a
# path. Its two private helpers the walk needs are re-stated here rather than made public, which
# would widen phase 9's interface.
#
# Stated gap: a receiver reached through a variable (`ast = RubyVM::AbstractSyntaxTree;
# ast.parse_file(p)`) and a method name held in a variable are undecidable statically, the residue
# phase 9 wrote down for gates:cause_walk.
module SoleParse
  TREES = ["tools/**/*.rb", "tasks/**/*.rake", "test/gates/**/*.rb",
           ".claude/skills/**/*.rb",].freeze
  TARGET = :parse_file
  RECEIVER = %w[RubyVM::AbstractSyntaxTree ::RubyVM::AbstractSyntaxTree].freeze
  OWNER_FILE = "tools/ast_scan.rb"
  OWNER_METHOD = :parse

  # Each entry is a file that calls `parse_file` bare ON PURPOSE, with the reason. Both are the
  # contrast that proves AstScan.parse's window: a bare parse of `warns_unused.rb` must emit the
  # warning the window suppresses, or the window's own test cannot discriminate. The integrity test
  # asserts every entry still names a file the scan reports, so a stale entry silences nothing.
  ALLOWED = {
    "test/gates/phase9_ruby_facts_test.rb" =>
      "the bare parse is the measured contrast for AstScan.parse's $VERBOSE window (phase 9)",
    "test/gates/invariant_gates_test.rb" =>
      "the bare parse proves the fixture is not inert before asserting the gate emits nothing",
    "test/gates/sole_parse_test.rb" =>
      "the reflective bare parse is this gate's own contrast: the window it protects still works",
  }.freeze

  class << self
    # @param root [String]
    # @param paths [Array<String>] absolute paths
    # @return [Array<String>] "path:line: ..." with absolute paths; the task relativises
    def offences(root:, paths: TREES.flat_map { |glob| Dir.glob(File.join(root, glob)) }.sort)
      allowed = ALLOWED.keys.map { |path| File.join(root, path) }
      owner = File.join(root, OWNER_FILE)
      scanned = paths.reject { |path| allowed.include?(path) }
      scanned.flat_map { |path| offences_in(path, owner: path == owner) }
    end

    def offences_in(path, owner: false)
      lines(AstScan.parse(path), owner: owner).map do |line|
        "#{path}:#{line}: RubyVM::AbstractSyntaxTree.parse_file outside AstScan.#{OWNER_METHOD} " \
          "(NFR-6)"
      end
    end

    private

    # Depth-first, carrying the owner flag down, so a block nested inside AstScan#parse is still
    # inside it. The exemption is the owner METHOD, not the owner file: the rule is about the
    # file's other methods, and a file-wide exemption could not enforce it.
    def lines(node, owner:, inside: false, out: [])
      return out unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

      inside ||= owner && defines_owner?(node)
      out << node.first_lineno if !inside && target?(node)
      node.children.each { |child| lines(child, owner: owner, inside: inside, out: out) }
      out
    end

    # `:DEFN` carries the method name first; `:DEFS` (`def self.parse`) carries the receiver first.
    def defines_owner?(node)
      case node.type
      when :DEFN then node.children[0] == OWNER_METHOD
      when :DEFS then node.children[1] == OWNER_METHOD
      else false
      end
    end

    def target?(node)
      return false unless %i[CALL QCALL].include?(node.type)
      return false unless RECEIVER.include?(render(node.children[0]))

      called = node.children[1]
      return true if called == TARGET

      AstScan::REFLECTIVE_SENDS.include?(called) && first_argument_name(node) == TARGET
    end

    def first_argument_name(node)
      args = node.children[2]
      return nil unless args.is_a?(::RubyVM::AbstractSyntaxTree::Node) && args.type == :LIST

      literal_name(args.children.first)
    end

    # A String or Symbol literal's name, nil for anything dynamic.
    def literal_name(node)
      return nil unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

      value = node.children.first
      return value.to_sym if node.type == :STR && value.is_a?(::String)

      AstScan::SYMBOL_TYPES.include?(node.type) && value.is_a?(::Symbol) ? value : nil
    end

    def render(node)
      return nil unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

      case node.type
      when :CONST then node.children[0].to_s
      when :COLON3 then "::#{node.children[0]}"
      when :COLON2
        left = render(node.children[0])
        left.nil? ? nil : "#{left}::#{node.children[1]}"
      end
    end
  end
end
