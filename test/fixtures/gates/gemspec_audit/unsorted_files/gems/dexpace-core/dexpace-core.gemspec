# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture, positive control: a file list written unsorted. RubyGems sorts spec.files in its
# own reader (Specification#files) on every Ruby in the matrix, so this loads sorted and the
# audit accepts it; the ordering a gemspec CAN break is the one that depends on git.
Gem::Specification.new do |spec|
  spec.name = "dexpace-core"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: an unsorted file list."
  spec.required_ruby_version = ">= 3.2"
  spec.files = %w[lib/zeta.rb lib/alpha.rb]
end
