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
    Ruby's net/http default gem. It depends on dexpace-core and on net-http and nothing else.
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

  # NFR-2: dexpace-core plus at most one third-party gem, and this is the one -- declared by phase
  # 8a with the code that needs it (design P0-9), the only place the floor is stated. `>= 0.4`
  # because Net::HTTPGenericRequest, the block form of #request and the `max_retries`,
  # `proxy_from_env` and `write_timeout` knobs the adapter sets are all present from that release,
  # which is the default gem on the 3.2 floor. No upper bound: under Bundler the NEWEST published
  # net-http resolves on every row (0.9.1 at the time of writing), and the adapter is written and
  # tested to be correct on 0.4.1, 0.6.0 and 0.9.1 alike -- `gates:require_allowlist` is what
  # makes `require "net/http"` permitted in this gem's lib/ because of this line.
  spec.add_dependency "net-http", ">= 0.4"
end
