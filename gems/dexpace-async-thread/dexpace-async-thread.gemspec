# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../tools/versions"

Gem::Specification.new do |spec|
  spec.name = "dexpace-async-thread"
  spec.version = DexpaceVersions.gem_version("dexpace-async-thread")
  spec.authors = ["dexpace"]
  spec.email = ["oaljarrah@dexpace.org"]

  spec.summary = "The thread-based async-runtime adapter for dexpace."
  spec.description = <<~TEXT
    The async-runtime adapter for the dexpace HTTP-client toolkit that runs on plain Ruby
    threads. It depends on dexpace-core and nothing else, by design: a thread is the runtime
    every Ruby already has.
  TEXT
  spec.homepage = "https://github.com/dexpace/ruby-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= #{DexpaceVersions.ruby_floor}"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main/gems/dexpace-async-thread",
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
