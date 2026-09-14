# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "rbconfig"

# The running interpreter's own executables. Every subprocess the build starts spells `ruby`,
# `gem` and `bundle` through here rather than through PATH, so a gate runs its subprocesses on
# the interpreter running rake and never on whichever `ruby` a version-manager shim resolves
# first. On a machine whose shim ignores `.ruby-version` the difference is silent -- the 4.0
# row, where the bundled-gem refusal bites, would be reported on one Ruby and run on another.
# In CI this changes nothing: ruby/setup-ruby puts the matrix interpreter's bindir first on
# PATH, which is exactly the directory these paths name.
module Interpreter
  extend self

  def ruby = RbConfig.ruby

  # `gem` and `bundle`: the wrappers RubyGems and Bundler (a default gem) install beside the
  # interpreter, each of which execs the `ruby` in its own directory.
  def executable(name) = File.join(RbConfig::CONFIG["bindir"], name)
end
