# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../tools/versions"

Gem::Specification.new do |spec|
  spec.name = "dexpace-transport-async_http"
  spec.version = DexpaceVersions.gem_version("dexpace-transport-async_http")
  spec.authors = ["dexpace"]
  spec.email = ["oaljarrah@dexpace.org"]

  spec.summary = "The asynchronous transport adapter for dexpace, over async-http."
  spec.description = <<~TEXT
    The reference asynchronous transport for the dexpace HTTP-client toolkit, implemented over
    the async-http gem. It depends on dexpace-core and on async-http and nothing else.
  TEXT
  spec.homepage = "https://github.com/dexpace/ruby-sdk"
  spec.license = "MIT"
  # P8-36: narrower than the repository's 3.2 floor, and the one gemspec that reads its OWN
  # `floor:<gem>` row of VERSIONS rather than the global one. async-http 0.95.0 and async 2.38.0
  # both raised required_ruby_version to >= 3.3, and the highest release that still admits 3.2 is
  # eleven minor versions behind the one every fact in this gem's design was verified against. A
  # floor a gem declares must be a floor it is tested on (8c's R15); the gates read the per-gem
  # row, and the 3.2 CI row leaves this gem out of the bundle, test:gems and gates:clean_bundle.
  spec.required_ruby_version = ">= #{DexpaceVersions.ruby_floor("dexpace-transport-async_http")}"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main/gems/dexpace-transport-async_http",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true",
  }

  # NFR-12: entry ordering is deterministic and does not depend on git.
  spec.files = Dir.glob(%w[lib/**/*.rb sig/**/*.rbs README.md LICENSE], base: __dir__).sort
  spec.require_paths = ["lib"]

  spec.add_dependency "dexpace-core", DexpaceVersions.core_constraint

  # NFR-2: dexpace-core plus at most one third-party gem, and this is the one (phase 8c). The
  # `~>` admits every 0.104.x and 0.105.x release; the adapter is proven on 0.105.0, whose closure
  # is fifteen further gems including io-event's C extension and, below Ruby 3.4's default
  # openssl 3.3, an installed openssl gem -- both stated in docs/first-release.md.
  spec.add_dependency "async-http", "~> 0.104"
end
