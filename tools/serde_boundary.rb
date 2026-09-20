# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "prism"
require "rbs"
require_relative "require_scan"

# SSE-37: "Core parsing/streaming MUST remain format- and API-agnostic: no built-in
# done-sentinel, no error-envelope recognition, no serialization dependency". Design §7.2
# mechanises the third clause as a require audit rather than leaving it to review, and the phase-7
# segmentation design's spec-forced boundary 5 extends the same mechanism over core's pagination
# layer, whose serde-agnosticism carries no requirement ID and would otherwise be enforced by
# nothing: `gates:require_allowlist` denies `json` by name, but the boundary at issue is INTERNAL
# -- core's own Dexpace::Serde seam, which that gate cannot see.
#
# The scan is PARSED, never pattern-matched, for the same reason phase 0's require audit is: a
# guarded file's YARD is required to say "names no Dexpace::Serde constant", and a regex over raw
# text would fail the gate on the sentence the requirement asks for. Ruby files are read with
# prism -- every `require`/`require_relative`/`autoload` spelling through RequireScan, and every
# constant read or constant path through its own walk -- and RBS files are read with the RBS
# lexer, whose comments and string literals are tokens of their own; an RBS naming Dexpace::Serde
# is a type-level dependency and is refused the same way.
#
# Two lists, and the assertion that makes them a gate: every GUARDED glob must match at least one
# file, because a glob with a typo scans nothing and reports clean forever, which is precisely the
# way a boundary gate stops being a gate. PENDING holds a path whose files do not exist on this
# base yet; it is not silent -- the task prints every pending row and its reason on every run --
# and a row moves to GUARDED in the change that lands the files. The pagination layer's rows made
# that move on 2026-09-20, in the reconcile pass that put 7c's tree on the same base as 7b's gate,
# and PENDING has been empty since; it stays as the mechanism for the next layer built beside a
# gate that predates it.
module SerdeBoundary
  extend self

  # A guarded glob, relative to the workspace root, and the requirement that guards it. The
  # pagination rows carry spec-forced boundary 5 (phase-7 segmentation design): §12's pagination
  # serde-agnosticism carries no requirement ID, so the SSE-37 mechanism is extended one path
  # wider, and the entry file has a row of its own for the same reason sse.rb has one -- `**`
  # under a directory cannot match the file beside it.
  GUARDED = [
    ["gems/dexpace-core/lib/dexpace/sse.rb", "SSE-37"],
    ["gems/dexpace-core/lib/dexpace/sse/**/*.rb", "SSE-37"],
    ["gems/dexpace-core/sig/dexpace/sse.rbs", "SSE-37"],
    ["gems/dexpace-core/sig/dexpace/sse/**/*.rbs", "SSE-37"],
    ["gems/dexpace-core/lib/dexpace/page.rb", "spec-forced boundary 5"],
    ["gems/dexpace-core/lib/dexpace/page/**/*.rb", "spec-forced boundary 5"],
    ["gems/dexpace-core/sig/dexpace/page.rbs", "spec-forced boundary 5"],
    ["gems/dexpace-core/sig/dexpace/page/**/*.rbs", "spec-forced boundary 5"],
  ].freeze

  # A path whose files do not exist on this base yet, with the reason it is pending: printed on
  # every run, never silent. Empty since the pagination rows moved to GUARDED on 2026-09-20.
  PENDING = [].freeze

  # The constant names a guarded file may not read, wherever they sit in a path: `Serde`,
  # `Dexpace::Serde`, `Dexpace::Serde::JSON`, `JSON` and `::JSON` -- the last being the spelling
  # phase 2's Dexpace/QualifiedCoreConstant cop pushes an author toward everywhere else in core.
  FORBIDDEN_CONSTANTS = %i[Serde JSON].freeze

  # A required feature is forbidden when it is `json` or under `json/`, or names a serde path --
  # `dexpace/serde`, `dexpace/serde/json`, a relative `../serde/json`.
  def forbidden_feature?(feature)
    feature == "json" || feature.start_with?("json/") || feature.split("/").include?("serde")
  end

  # Every violation across the GUARDED list, each naming the file, the line and the requirement.
  def violations(root)
    GUARDED.flat_map do |glob, requirement|
      files = Dir.glob(File.join(root, glob))
      next [empty_glob(glob, requirement)] if files.empty?

      files.flat_map { |path| scan_file(path, requirement: requirement) }
    end
  end

  # The PENDING rows with how many files each currently matches, for the task to print.
  def pending(root)
    PENDING.map { |glob, reason| [glob, reason, Dir.glob(File.join(root, glob)).size] }
  end

  # One file's violations. A Ruby file that does not parse is a violation in itself: a file the
  # scan cannot read is a file it cannot vouch for (RequireAllowlist's rule).
  def scan_file(path, requirement:)
    return scan_rbs(path, requirement) if path.end_with?(".rbs")

    scan_ruby(path, requirement)
  rescue RequireScan::ParseError => error
    ["#{path}: #{error.message}, so the serde boundary cannot read it (#{requirement})."]
  end

  private

  def empty_glob(glob, requirement)
    "#{glob}: matches no file, so #{requirement}'s boundary would be checked against nothing. " \
      "Fix the glob or move the row to SerdeBoundary::PENDING with its reason."
  end

  def scan_ruby(path, requirement)
    requires = RequireScan.calls(path).filter_map do |call|
      next unreadable(path, call, requirement) if call.feature.nil?
      next unless forbidden_feature?(call.feature)

      "#{path}:#{call.line}: #{call.verb} #{call.feature.inspect} -- a serialization dependency " \
        "in a guarded file (#{requirement})."
    end
    requires + constants(path).map do |name, line|
      "#{path}:#{line}: names the constant #{name} -- a serialization dependency in a guarded " \
        "file (#{requirement})."
    end
  end

  def unreadable(path, call, requirement)
    "#{path}:#{call.line}: #{call.verb} #{call.arguments || "with no argument"} -- the feature " \
      "is not a string literal, so the serde boundary cannot see it (#{requirement})."
  end

  # Every forbidden constant read in the file, as [rendered name, line]: a bare read
  # (ConstantReadNode) or a path (ConstantPathNode) any of whose segments is forbidden, so
  # `Dexpace::Serde::JSON` is reported once, at the path, with both names visible. A reported
  # path's children are not walked again; every other node's are, so a forbidden read inside a
  # dynamic parent (`JSON.parse(x)::Foo`) is still found.
  def constants(path)
    parsed = Prism.parse_file(path)
    raise RequireScan::ParseError, "does not parse" if parsed.failure?

    found = []
    collect_constants(parsed.value, found)
    found
  end

  def collect_constants(node, found)
    if forbidden_constant?(node)
      found << [render(node), node.location.start_line]
      return
    end

    node.compact_child_nodes.each { |child| collect_constants(child, found) }
  end

  def forbidden_constant?(node)
    case node
    when Prism::ConstantReadNode then FORBIDDEN_CONSTANTS.include?(node.name)
    when Prism::ConstantPathNode then forbidden_path?(node)
    else false
    end
  end

  # `self::Serde` or `x::Serde` has a dynamic parent prism cannot name; the last segment is still
  # a read of a forbidden name when it is one, and the parent is walked as a child either way.
  def forbidden_path?(node)
    node.full_name_parts.any? { |part| FORBIDDEN_CONSTANTS.include?(part) }
  rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError,
         Prism::ConstantPathNode::MissingNodesInConstantPathError
    FORBIDDEN_CONSTANTS.include?(node.name)
  end

  def render(node)
    node.is_a?(Prism::ConstantPathNode) ? node.slice : node.name.to_s
  end

  # The RBS lexer's token stream: a constant is a tUIDENT, while a comment and a string literal
  # are tokens of their own kinds, so neither can trip the scan.
  def scan_rbs(path, requirement)
    buffer = RBS::Buffer.new(name: path, content: File.read(path))
    RBS::Parser.lex(buffer).value.filter_map do |token|
      next unless token.type == :tUIDENT

      name = token.location.source
      next unless FORBIDDEN_CONSTANTS.include?(name.to_sym)

      "#{path}:#{token.location.start_line}: names the type #{name} -- a serialization " \
        "dependency in a guarded signature (#{requirement})."
    end
  end
end
