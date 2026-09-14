# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: a core gemspec with ONE runtime dependency. SEAM-1 and NFR-1 require zero, and
# `logger` is exactly the innocent-looking name the rule exists for.
Gem::Specification.new do |spec|
  spec.name = "dexpace-core"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: core with a runtime dependency."
  spec.required_ruby_version = ">= 3.2"
  spec.files = []
  spec.add_dependency "logger", "~> 1.6"
end
