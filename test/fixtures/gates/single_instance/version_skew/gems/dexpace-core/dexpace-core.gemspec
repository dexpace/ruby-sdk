# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: the gemspec says 0.0.0 while lib/dexpace/version.rb says 9.9.9.
Gem::Specification.new do |spec|
  spec.name = "dexpace-core"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: a version literal that disagrees with its gemspec."
  spec.required_ruby_version = ">= 3.2"
  spec.files = []
end
