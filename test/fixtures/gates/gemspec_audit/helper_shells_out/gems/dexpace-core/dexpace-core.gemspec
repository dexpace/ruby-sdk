# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../tools/gem_files"

# Gate fixture: a file list produced by a subprocess in a helper this gemspec loads, so the
# gemspec's own text carries no backtick and no popen; the audit follows the require_relative
# (NFR-12).
Gem::Specification.new do |spec|
  spec.name = "dexpace-core"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: a file list from a helper that shells out."
  spec.required_ruby_version = ">= 3.2"
  spec.files = FixtureGemFiles.list(__dir__)
end
