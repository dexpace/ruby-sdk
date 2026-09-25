# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# An owner file: the parse method is exempt, a second method in the same file is not.
module AstScan
  def parse(path)
    [1].each { RubyVM::AbstractSyntaxTree.parse_file(path) }
  end

  def sneaky(path) = RubyVM::AbstractSyntaxTree.parse_file(path)
end
