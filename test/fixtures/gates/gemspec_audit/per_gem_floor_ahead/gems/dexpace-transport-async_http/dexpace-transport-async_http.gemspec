# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: a gemspec that declares the global floor where VERSIONS gives the gem its own,
# narrower one -- the audit must read the per-gem row (phase 8c's P8-36).
Gem::Specification.new do |spec|
  spec.name = "dexpace-transport-async_http"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: a gemspec below its own per-gem Ruby floor."
  spec.required_ruby_version = ">= 3.2"
  spec.files = []
  spec.add_dependency "dexpace-core", "~> 0.0"
end
