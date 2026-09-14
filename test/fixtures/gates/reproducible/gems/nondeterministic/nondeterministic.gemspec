# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: a gemspec that is deliberately wrong in the one way this gate exists to catch --
# an unsorted file list and, when built without SOURCE_DATE_EPOCH, a timestamp from the clock.
Gem::Specification.new do |spec|
  spec.name = "nondeterministic"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: an unsorted file list and no normalised timestamp."
  spec.files = Dir.glob("lib/**/*.rb", base: __dir__) # deliberately unsorted -- NFR-12's trap
  spec.require_paths = ["lib"]
end
