# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "rake/clean"

Dir.glob("tasks/*.rake", base: __dir__).sort.each do |file|
  load File.expand_path(file, __dir__)
end

# NFR-17: every gate is blocking, automatic and part of an ordinary build. The order is by cost
# and blast radius -- the ones that read only text run first, so a formatting mistake does not
# wait behind a `bundle install`.
#
# `test:gems` and `test:gates` are separate because they run in different places: the gem suites
# run on every Ruby in the matrix (NFR-10 needs the real suite on the floor), while the gate
# suites shell out to rake and to git and are interpreter-independent, so CI runs them once.
DEFAULT_GATES = %w[
  rubocop
  cops:test
  rbs:validate
  steep
  test:gems
  test:gates
  gates:gemspec_audit
  gates:require_allowlist
  gates:serde_boundary
  gates:cause_walk
  gates:bounded_map
  gates:seam_names
  gates:ledger_audit
  gates:spdx_rbs
  gates:sole_parse
  gates:clean_bundle
  gates:rbs_surface
  gates:sig_diff
  gates:surface_snapshot
  gates:single_instance
  gates:versions
  gates:reproducible
  yard
  bundler_audit
].freeze

namespace :gates do
  desc "Print the default gate list, one per line (the order CI and `rake` both use)"
  task :list do
    puts DEFAULT_GATES
  end
end

desc "Every quality gate, in order (NFR-17)"
task default: DEFAULT_GATES
