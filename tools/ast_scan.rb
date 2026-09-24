# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The shared walker behind gates:cause_walk, gates:bounded_map and gates:seam_names.
#
# `RubyVM::AbstractSyntaxTree` rather than a regex, because `grep '\.cause'` matches a comment, a
# string, an `# XCUT-9` citation in a test header and the requirement ID itself. Verified present
# on 3.2.11, 3.3.12, 3.4.10 and 4.0.6.
#
# **Why not `prism`, since `tools/require_scan.rb` uses it and the bundle carries it on every
# row.** `prism` is a default gem only from 3.3 and the version the require gate was written
# against is the bundle's, not the interpreter's; `RubyVM::AbstractSyntaxTree` needs no gem at
# all, so these three gates run on any row with no bundle and no conditional require. That is the
# real reason, and it is not "consistency with the existing parsed scan" -- which, now that prism
# IS in the bundle on every row, would argue the other way.
#
# The PARSER emits no warning of its own for well-formed input; the SCANNED FILE's own `-w`
# diagnostics are a different thing and DO reach `Warning.warn`, which is load-bearing here.
# Every parse below goes through #parse, and nothing else in this file may call `parse_file`.
# rubocop:disable Metrics/ModuleLength -- one parsed-scan vocabulary over one parser. Every
# method here is knowledge about ONE thing, the shape of a `RubyVM::AbstractSyntaxTree` node on
# the four supported interpreters, and splitting it by line count would put half of that
# knowledge in a second file that has to be read with this one to mean anything.
module AstScan
  # Node types a send can take. `:CALL` is `a.cause`, `:QCALL` is `a&.cause`, `:VCALL` is a bare
  # `cause` and `:FCALL` is `cause()` or a receiverless `send(:cause)`. Measured identical on
  # 3.2.11, 3.3.12, 3.4.10 and 4.0.6; a scan checking only `:CALL` misses every safe-navigated
  # send.
  SEND_TYPES = %i[CALL QCALL VCALL FCALL].freeze

  # A Symbol literal is a `:LIT` node on Ruby 3.2 and 3.3 and a `:SYM` node on 3.4 and 4.0.
  # Measured on all four, and it is the reverse of the usual direction -- the NEWER interpreters
  # diverge. A scan naming only `:LIT` caught 6 of 7 reflective shapes on the floor and 2 of 7 on
  # the newer rows: strictest exactly where it runs least.
  SYMBOL_TYPES = %i[LIT SYM].freeze

  # Sends that reach a method by NAME rather than by call syntax. All four bypass a scan that
  # looks only at call syntax.
  REFLECTIVE_SENDS = %i[send __send__ public_send method].freeze

  extend self

  # `parse_file` with the SCANNED FILE's own `-w` diagnostics suppressed, which is the whole
  # reason this method exists rather than five direct `parse_file` calls.
  #
  # A file's `-w` diagnostics are emitted AT PARSE TIME and routed through `Warning.warn` exactly
  # as they are at require time. Phase 0's shared test case prepends `FatalWarnings` to Warning's
  # singleton class, and `test/gates/invariant_gates_test.rb` requires it, so a bare `parse_file`
  # raises on the first such file.
  #
  # Which mechanism, measured on all four rows: `Warning[:deprecated] = false` does NOT reach it
  # (the warning carries no category); `$VERBOSE = false` silences the `-w` class but not the
  # always-on parse warnings, and `key :a is duplicated` still fires under it; only
  # `$VERBOSE = nil` silences both. It is process-global, so the window is this one call and
  # `ensure` closes it -- outside it, NFR-6's gate is armed exactly as before.
  #
  # @param path [String]
  # @return [RubyVM::AbstractSyntaxTree::Node, nil]
  def parse(path)
    previous = $VERBOSE
    $VERBOSE = nil
    ::RubyVM::AbstractSyntaxTree.parse_file(path)
  ensure
    $VERBOSE = previous
  end

  # Every send whose method name is in `names`, whatever the call syntax, plus every reflective
  # send naming one of them as a Symbol literal, plus `&:name` block passes.
  #
  # @param path [String]
  # @param names [Array<Symbol>]
  # @return [Array<Array(String, Integer, Symbol)>] path, line, method name
  def receiver_calls(path, names)
    hits = [] #: Array[untyped]
    walk(parse(path)) { |node| collect_call(node, names, path, hits) }
    hits
  end

  # Every instance-variable assignment whose value is a Hash by a statically decidable route: a
  # literal `{}`, a `Hash.new` / `::Hash.new` call, a chained call on either
  # (`{}.compare_by_identity`), or an `||=` of any of those.
  #
  # **Stated gap:** `@h = build_map`, `@h = OTHER.dup`, a Hash arriving through a parameter, a
  # class variable, a bare constant, `instance_variable_set(:@h, {})` and a Hash held inside a
  # value object rather than directly on the ivar are undecidable from one file and are NOT
  # reported. The gate is a FLOOR on the invariant rather than proof of it.
  #
  # @param path [String]
  # @return [Array<Array(String, Integer, Symbol)>] path, line, ivar name
  def hash_ivar_assignments(path)
    hits = [] #: Array[untyped]
    walk(parse(path)) do |node|
      next unless %i[IASGN OP_ASGN_OR].include?(node.type)

      name, value = ivar_assignment(node)
      hits << [path, node.first_lineno, name] if !name.nil? && hash_valued?(value)
    end
    hits
  end

  # Every constant path written in the file, rendered as `Dexpace::Serde::JSON`.
  #
  # @param path [String]
  # @return [Array<Array(String, Integer, String)>] path, line, constant path
  def constant_paths(path)
    hits = [] #: Array[untyped]
    walk(parse(path)) do |node|
      next unless %i[CONST COLON2 COLON3].include?(node.type)

      rendered = render_const(node)
      hits << [path, node.first_lineno, rendered] unless rendered.nil?
    end
    hits
  end

  # Every String and Symbol literal, so `const_get("Dexpace::Serde::JSON")` and
  # `const_get(:"Dexpace::Serde::JSON")` are both reachable by the same match the constant scan
  # uses.
  #
  # @param path [String]
  # @return [Array<Array(String, Integer, String)>] path, line, literal
  def string_literals(path)
    hits = [] #: Array[untyped]
    walk(parse(path)) do |node|
      text = literal_text(node)
      hits << [path, node.first_lineno, text] unless text.nil?
    end
    hits
  end

  def walk(node, &block)
    return unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

    yield(node)
    node.children.each { |child| walk(child, &block) }
  end

  private

  # The text of a String or Symbol literal node, nil for every other node. Both spellings answer
  # here because `const_get("Dexpace::X")` and `const_get(:"Dexpace::X")` reach the same constant.
  def literal_text(node)
    return node.children.first if node.type == :STR
    return nil unless SYMBOL_TYPES.include?(node.type)

    value = node.children.first
    value.is_a?(::Symbol) ? value.to_s : nil
  end

  def collect_call(node, names, path, hits)
    if node.type == :BLOCK_PASS # `errors.map(&:cause)`: BLOCK_PASS(nil, SYM/LIT)
      passed = symbol_value(node.children[1])
      hits << [path, node.first_lineno, passed] if names.include?(passed)
      return
    end
    return unless SEND_TYPES.include?(node.type)

    record_send(node, names, path, hits)
  end

  def record_send(node, names, path, hits)
    called = method_name(node)
    if names.include?(called)
      # A walk sends #cause with NO argument; a send carrying one is some other #cause -- 5b's
      # filed `Event#cause(error)` builder is the case that made this gate red over conforming
      # code.
      hits << [path, node.first_lineno, called] if arguments(node).nil?
      return
    end
    return unless REFLECTIVE_SENDS.include?(called)

    reflected = named_argument(node)
    hits << [path, node.first_lineno, reflected] if names.include?(reflected)
  end

  # `:VCALL` and `:FCALL` carry the name first; `:CALL` and `:QCALL` carry the receiver first.
  def method_name(node) = %i[VCALL FCALL].include?(node.type) ? node.children[0] : node.children[1]

  # The argument node, or nil when there is none (a `:VCALL` has no slot at all).
  def arguments(node)
    index = { CALL: 2, QCALL: 2, FCALL: 1 }[node.type]
    index.nil? ? nil : node.children[index]
  end

  # The SOLE argument of a send when it names a method: a Symbol literal OR a String literal, so
  # `e.send("cause")` is caught beside `e.send(:cause)`. `nil` for anything dynamic --
  # `send(name)` where `name` is a variable is undecidable statically and is one of the shapes
  # the stated gap covers.
  def named_argument(node)
    args = arguments(node)
    return nil unless args.is_a?(::RubyVM::AbstractSyntaxTree::Node) && args.type == :LIST

    values = args.children.compact
    values.size == 1 ? literal_name(values.first) : nil
  end

  def literal_name(node)
    return nil unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)
    return node.children.first.to_sym if node.type == :STR && node.children.first.is_a?(::String)

    symbol_value(node)
  end

  def symbol_value(node)
    unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node) && SYMBOL_TYPES.include?(node.type)
      return nil
    end

    value = node.children.first
    value.is_a?(::Symbol) ? value : nil
  end

  # `@h = …` is `:IASGN`; `@h ||= …` is `:OP_ASGN_OR` whose second child is the `:IASGN`.
  def ivar_assignment(node)
    return [node.children[0], node.children[1]] if node.type == :IASGN

    inner = node.children[1]
    return [nil, nil] unless inner.is_a?(::RubyVM::AbstractSyntaxTree::Node) && inner.type == :IASGN

    [inner.children[0], inner.children[1]]
  end

  def hash_valued?(node)
    return false unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

    case node.type
    when :HASH then true
    when :CALL, :QCALL
      return true if node.children[1] == :new && const_name(node.children[0]) == :Hash

      hash_valued?(node.children[0])
    else false
    end
  end

  # `Hash` is a `:CONST` and `::Hash` is a `:COLON3`; a check naming only the first missed
  # `@h = ::Hash.new` on every interpreter (measured).
  def const_name(node)
    return nil unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

    %i[CONST COLON3].include?(node.type) ? node.children[0] : nil
  end

  def render_const(node)
    case node.type
    when :CONST then node.children[0].to_s
    when :COLON3 then "::#{node.children[0]}"
    when :COLON2
      left = node.children[0]
      return node.children[1].to_s if left.nil?

      inner = render_const(left)
      inner.nil? ? nil : "#{inner}::#{node.children[1]}"
    end
  end
end
# rubocop:enable Metrics/ModuleLength
