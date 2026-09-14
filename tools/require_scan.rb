# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "prism"

# Finds every call in a Ruby file that reaches Kernel#require -- `require`, `require_relative`
# and `autoload`, which registers a deferred require of its second argument -- and names the
# feature each one loads. Mechanism only: which features are permitted is RequireAllowlist's
# business.
#
# The scan reads PARSED call nodes, not lines. A line-anchored pattern sees `require "json"` and
# nothing else, and `require("json")`, `Kernel.require "json"`, a require after a `;` and
# `autoload :JSON, "json"` all reach the same feature -- every one of them is an ordinary
# spelling, and a gate that a parenthesis slips past is not the gate design §9.2 describes.
# Parsing also means a comment naming a feature is not a require, and a feature the scan cannot
# read -- an interpolated string, a variable, a `File.join` -- is reported with `feature: nil`
# rather than dropped, so the caller can refuse what it cannot see. A require reached through
# `send`, `method` or `eval` is not a spelling and not this scan's business: the gate it serves
# is against accidents, and a deliberate evasion is a review matter.
module RequireScan
  extend self

  # The loading verbs, and the argument position that names the feature.
  LOADERS = { require: 0, require_relative: 0, autoload: 1 }.freeze

  # One loader call. `feature` is nil when the argument is anything but a string literal;
  # `arguments` is the argument source text, for the message that says so.
  Call = Data.define(:verb, :feature, :line, :arguments)

  class ParseError < StandardError; end

  # Every loader call in the file, in source order.
  def calls(path)
    parsed = Prism.parse_file(path)
    if parsed.failure?
      raise ParseError, "does not parse (#{parsed.errors.map(&:message).join("; ")})"
    end

    collect(parsed.value).map { |node| call_of(node) }
  end

  private

  # Every call that reaches Kernel#require: a bare call, `self.`, `Kernel.` or `::Kernel.`. A
  # loader called on any other receiver is some other object's method.
  def collect(node, found = [])
    found << node if loader?(node)
    node.compact_child_nodes.each { |child| collect(child, found) }
    found
  end

  def loader?(node)
    node.is_a?(Prism::CallNode) && LOADERS.key?(node.name) && kernel?(node.receiver)
  end

  def kernel?(receiver)
    case receiver
    when nil, Prism::SelfNode then true
    when Prism::ConstantReadNode then receiver.name == :Kernel
    when Prism::ConstantPathNode then receiver.parent.nil? && receiver.name == :Kernel
    else false
    end
  end

  def call_of(node)
    Call.new(
      verb: node.name, feature: feature_of(node), line: node.location.start_line,
      arguments: node.arguments&.slice,
    )
  end

  def feature_of(node)
    argument = node.arguments&.arguments&.[](LOADERS.fetch(node.name))
    argument.unescaped if argument.is_a?(Prism::StringNode)
  end
end
