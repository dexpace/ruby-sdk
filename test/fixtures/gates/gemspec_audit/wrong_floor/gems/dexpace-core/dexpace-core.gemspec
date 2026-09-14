# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: a gemspec whose required_ruby_version is the development pin rather than the
# declared floor. NFR-10 targets the floor for every general-purpose unit.
Gem::Specification.new do |spec|
  spec.name = "dexpace-core"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: a gemspec above the declared Ruby floor."
  spec.required_ruby_version = ">= 4.0"
  spec.files = []
end
