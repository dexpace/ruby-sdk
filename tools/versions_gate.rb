# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "yaml"
require_relative "versions"

# NFR-14 enforced across the four consumers that cannot share a file: a gemspec (Ruby), the
# Gemfile (Ruby), .ruby-version (a bare string) and the CI matrix (YAML).
module VersionsGate
  extend self

  def violations(root)
    versions = File.join(root, "VERSIONS")

    pin_violations(root, versions) + matrix_violations(root, versions) +
      gem_violations(root, versions)
  end

  private

  def pin_violations(root, versions)
    expected = DexpaceVersions.value("ruby", "dev", versions)
    actual = File.read(File.join(root, ".ruby-version")).strip
    return [] if actual == expected

    [".ruby-version is #{actual}, VERSIONS says `ruby dev #{expected}` (NFR-14)."]
  end

  def matrix_violations(root, versions)
    expected = DexpaceVersions.value("ruby", "matrix", versions).split
    workflow = YAML.load_file(File.join(root, ".github/workflows/ci.yml"))
    actual = workflow.dig("jobs", "test", "strategy", "matrix", "ruby").to_a.map(&:to_s)
    return [] if actual == expected

    ["ci.yml's test matrix is #{actual.inspect}, VERSIONS says `ruby matrix " \
     "#{expected.join(" ")}` (NFR-14, NFR-10)."]
  end

  # The floor each gemspec must declare is the gem's OWN when VERSIONS carries a `floor:<gem>`
  # row and the global one otherwise (phase 8c's P8-36); the gemspec reads the same row, so a
  # disagreement is a gemspec that stopped reading VERSIONS.
  def gem_violations(root, versions)
    Dir.glob(File.join(root, "gems/*")).flat_map do |dir|
      name = File.basename(dir)
      declared = DexpaceVersions.value("gem", name, versions)
      floor = ">= #{DexpaceVersions.ruby_floor(name, versions)}"
      spec = Gem::Specification.load(File.join(dir, "#{name}.gemspec"))
      next ["#{name}.gemspec did not load."] if spec.nil?

      gemspec_violations(name, spec, declared, floor) + literal_violations(dir, name, declared)
    end
  end

  def gemspec_violations(name, spec, declared, floor)
    found = []
    if spec.version.to_s != declared
      found << "#{name}.gemspec is #{spec.version}, VERSIONS says #{declared} (NFR-14)."
    end
    if spec.required_ruby_version.to_s != floor
      found << "#{name}.gemspec required_ruby_version is #{spec.required_ruby_version}, " \
               "expected #{floor} (NFR-14, NFR-10)."
    end
    found
  end

  # The literal in lib/**/version.rb, which a built gem carries and the repository root does
  # not reach (NFR-15): the one place the version is written twice on purpose.
  def literal_violations(dir, name, declared)
    version_rb = Dir.glob(File.join(dir, "lib/**/version.rb")).first
    literal = File.read(version_rb)[/VERSION\s*=\s*"([^"]+)"/, 1]
    return [] if literal == declared

    ["#{name}'s VERSION literal is #{literal}, VERSIONS says #{declared} (NFR-14)."]
  end
end
