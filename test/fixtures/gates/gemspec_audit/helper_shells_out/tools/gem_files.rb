# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: a helper a gemspec loads by require_relative, the way the real gemspecs load
# tools/versions, whose file list comes from a subprocess. The gemspec's own text stays clean.
module FixtureGemFiles
  def self.list(dir) = IO.popen(["git", "-C", dir, "ls-files", "-z"], &:read).split("\x0").sort
end
