# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: an adapter constraining core as `~> 0.1` while the fixture's VERSIONS says core
# is 0.0.0. The audit derives the expected constraint from VERSIONS rather than matching a
# literal, which is what makes a core bump fail every adapter that was not updated.
Gem::Specification.new do |spec|
  spec.name = "dexpace-serde-json"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: an adapter with a stale core constraint."
  spec.required_ruby_version = ">= 3.2"
  spec.files = []
  spec.add_dependency "dexpace-core", "~> 0.1"
end
