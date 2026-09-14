# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../tools/versions"

Gem::Specification.new do |spec|
  spec.name = "dexpace-serde-json"
  spec.version = DexpaceVersions.gem_version("dexpace-serde-json")
  spec.authors = ["dexpace"]
  spec.email = ["oaljarrah@dexpace.org"]

  spec.summary = "The reference wire codec for dexpace, over Ruby's json."
  spec.description = <<~TEXT
    The reference wire codec for the dexpace HTTP-client toolkit, implemented over Ruby's json
    gem. It depends on dexpace-core and, once the codec lands, on json >= 2.19.9 and nothing
    else.
  TEXT
  spec.homepage = "https://github.com/dexpace/ruby-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= #{DexpaceVersions.ruby_floor}"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main/gems/dexpace-serde-json",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true",
  }

  # NFR-12: entry ordering is deterministic and does not depend on git.
  spec.files = Dir.glob(%w[lib/**/*.rb sig/**/*.rbs README.md LICENSE], base: __dir__).sort
  spec.require_paths = ["lib"]

  spec.add_dependency "dexpace-core", DexpaceVersions.core_constraint

  # NFR-2: dexpace-core plus at most one third-party gem. The third-party half of this
  # adapter's budget is declared by the phase that writes the code needing it (design P0-9);
  # `rake gates:gemspec_audit` enforces the whole budget either way.
end
