# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The two reflective spellings on the same receiver, by Symbol and by String. The cop directives
# are the fixture's own: the reflective spelling is what the gate must see.
module RogueReflective
  # rubocop:disable Style/SendWithLiteralMethodName, Performance/StringIdentifierArgument
  def self.by_symbol(path) = ::RubyVM::AbstractSyntaxTree.send(:parse_file, path)
  def self.by_string(path) = RubyVM::AbstractSyntaxTree.public_send("parse_file", path)
  # rubocop:enable Style/SendWithLiteralMethodName, Performance/StringIdentifierArgument
end
