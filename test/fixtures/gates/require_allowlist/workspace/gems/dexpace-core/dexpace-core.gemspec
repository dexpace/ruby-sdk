# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: a core gemspec declaring nothing, as the real one does.
Gem::Specification.new do |spec|
  spec.name = "dexpace-core"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: a workspace whose core requires timeout."
  spec.required_ruby_version = ">= 3.2"
  spec.files = []
end
