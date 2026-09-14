# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../tools/versions"

Gem::Specification.new do |spec|
  spec.name = "dexpace-conformance"
  spec.version = DexpaceVersions.gem_version("dexpace-conformance")
  spec.authors = ["dexpace"]
  spec.email = ["oaljarrah@dexpace.org"]

  spec.summary = "The conformance suite every dexpace adapter is tested against."
  spec.description = <<~TEXT
    The conformance suite for the dexpace HTTP-client toolkit: the assertions every transport,
    codec and async-runtime adapter must satisfy, so a third-party adapter is proven against the
    same contract the shipped ones are. It depends on dexpace-core and nothing else.
  TEXT
  spec.homepage = "https://github.com/dexpace/ruby-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= #{DexpaceVersions.ruby_floor}"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main/gems/dexpace-conformance",
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
