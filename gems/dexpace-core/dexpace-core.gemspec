# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../tools/versions"

Gem::Specification.new do |spec|
  spec.name = "dexpace-core"
  spec.version = DexpaceVersions.gem_version("dexpace-core")
  spec.authors = ["dexpace"]
  spec.email = ["oaljarrah@dexpace.org"]

  spec.summary = "The dexpace HTTP-client toolkit: domain model, pipeline and seams."
  spec.description = <<~TEXT
    An HTTP-client toolkit, not an HTTP client. dexpace-core carries the correctness-sensitive
    plumbing -- idempotency-aware retry, redirects that never leak a bearer token cross-origin,
    RFC 7235/7616 authentication, pagination, SSE and three-state PATCH -- and no concrete
    transport, codec or async runtime. Those are separate gems.
  TEXT
  spec.homepage = "https://github.com/dexpace/ruby-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= #{DexpaceVersions.ruby_floor}"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main/gems/dexpace-core",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true",
  }

  # NFR-12: entry ordering is deterministic and does not depend on git.
  spec.files = Dir.glob(%w[lib/**/*.rb sig/**/*.rbs README.md LICENSE], base: __dir__).sort
  spec.require_paths = ["lib"]

  # SEAM-1 / NFR-1: this gemspec has no add_dependency line, and `rake gates:gemspec_audit`
  # asserts it. Ruby has no compile-versus-runtime dependency scope, so an empty
  # runtime_dependencies list IS the dependency audit.
end
