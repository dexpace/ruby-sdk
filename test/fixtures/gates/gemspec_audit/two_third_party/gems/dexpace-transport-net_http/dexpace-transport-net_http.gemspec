# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: an adapter declaring core plus TWO third-party gems. NFR-2's budget is core plus
# at most one, and an audit that has only ever seen one has never been shown to reject two.
Gem::Specification.new do |spec|
  spec.name = "dexpace-transport-net_http"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: an adapter over its NFR-2 budget."
  spec.required_ruby_version = ">= 3.2"
  spec.files = []
  spec.add_dependency "dexpace-core", "~> 0.0"
  spec.add_dependency "net-http", "~> 0.6"
  spec.add_dependency "logger", "~> 1.6"
end
