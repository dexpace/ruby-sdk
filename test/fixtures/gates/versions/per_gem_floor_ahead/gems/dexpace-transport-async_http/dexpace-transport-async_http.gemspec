# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: the gem VERSIONS gives its own 3.3 floor, whose gemspec still declares the global
# 3.2 -- the one mismatch a gate reading only the global row cannot see (phase 8c's P8-36).
Gem::Specification.new do |spec|
  spec.name = "dexpace-transport-async_http"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: a gemspec below its own per-gem Ruby floor."
  spec.required_ruby_version = ">= 3.2"
  spec.files = []
end
