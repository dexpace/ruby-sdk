# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: a core gemspec with literal values, so the fixture needs no tools/.
Gem::Specification.new do |spec|
  spec.name = "dexpace-core"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: one value in this workspace disagrees with VERSIONS."
  spec.required_ruby_version = ">= 3.2"
  spec.files = []
end
