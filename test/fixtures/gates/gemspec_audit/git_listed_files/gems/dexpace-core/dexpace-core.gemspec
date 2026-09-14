# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: a file list produced by `git ls-files`. Sorted, so the ordering check passes, but
# a .gem built from a source export has no repository to list, so the list depends on git rather
# than on the inputs (NFR-12).
Gem::Specification.new do |spec|
  spec.name = "dexpace-core"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: a git-listed file list."
  spec.required_ruby_version = ">= 3.2"
  spec.files = IO.popen(["git", "-C", __dir__, "ls-files", "-z"], &:read).split("\x0").sort
end
