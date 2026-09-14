# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../tools/versions"

Gem::Specification.new do |spec|
  spec.name = "dexpace-transport-net_http"
  spec.version = DexpaceVersions.gem_version("dexpace-transport-net_http")
  spec.authors = ["dexpace"]
  spec.email = ["oaljarrah@dexpace.org"]

  spec.summary = "The synchronous transport adapter for dexpace, over Ruby's net/http."
  spec.description = <<~TEXT
    The reference synchronous transport for the dexpace HTTP-client toolkit, implemented over
    Ruby's net/http default gem. It depends on dexpace-core and, once the adapter lands, on
    net-http and nothing else.
  TEXT
  spec.homepage = "https://github.com/dexpace/ruby-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= #{DexpaceVersions.ruby_floor}"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main/gems/dexpace-transport-net_http",
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
