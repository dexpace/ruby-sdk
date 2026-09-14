# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# VERSIONS consistency alone: the one gate that reads every other artifact -- .ruby-version, the
# CI matrix, every gemspec and every version.rb literal -- and asserts each agrees with the
# repository-root VERSIONS file (NFR-14). `gate_root` is defined in tasks/gates.rake, which the
# Rakefile loads first.
namespace :gates do
  desc "NFR-14/NFR-10: VERSIONS against every consumer of it"
  task :versions do
    require_relative "../tools/versions_gate"
    root = gate_root
    found = VersionsGate.violations(root)
    abort(found.join("\n")) unless found.empty?

    count = Dir.glob(File.join(root, "gems/*")).length
    puts "gates:versions: .ruby-version, the CI matrix, #{count} gemspecs and #{count} VERSION " \
         "literals all agree with VERSIONS."
  end
end
