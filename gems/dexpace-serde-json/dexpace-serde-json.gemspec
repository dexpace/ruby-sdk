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
    gem. It depends on dexpace-core and on json >= 2.19.9 and nothing else.
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

  # NFR-2: dexpace-core plus at most one third-party gem, and this is the one. The floor is the
  # first json version with JSON::Coder -- the per-instance, freezable, thread-safe engine
  # SERDE-26 and SERDE-29 rest on (phase 7a's P7-4) -- and the one carrying the 2026 advisories.
  # THIS LINE IS THE ONLY PLACE IN THE REPOSITORY THAT FLOOR MAY BE STATED (CLAUDE.md's hard rule,
  # design §3.4): core's require allowlist denies `json` by name, `rake gates:gemspec_audit`
  # enforces the budget, and `rake gates:require_allowlist` permits `require "json"` under this
  # gem's lib/ only because this line declares it. The entry file re-asserts the same number at
  # require time for an unbundled consumer (P7-7).
  spec.add_dependency "json", ">= 2.19.9"
end
