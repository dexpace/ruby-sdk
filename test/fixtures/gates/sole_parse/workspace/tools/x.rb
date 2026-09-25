# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A tool that parses a file directly, outside AstScan.parse: gates:sole_parse must report it.
module RogueDirect
  def self.scan(path) = RubyVM::AbstractSyntaxTree.parse_file(path)
end
