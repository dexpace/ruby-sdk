# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Reads the repository-root VERSIONS file, NFR-14's single source of truth.
#
# This file is loaded by every gemspec, so it must require nothing: a gemspec is evaluated by
# RubyGems and by Bundler in contexts where the load path is not this repository's.
module DexpaceVersions
  extend self

  PATH = File.expand_path("../VERSIONS", __dir__)
  RECORD = /\A(gem|tool|ruby)[ \t]+(\S+)[ \t]+(.+?)[ \t]*\z/

  # Every record, as [kind, name, value]. A line this cannot parse raises rather than being
  # skipped: a silently ignored record is a version that quietly stops being the source of
  # truth.
  def records(path = PATH)
    File.readlines(path, chomp: true).filter_map do |line|
      next if line.empty? || line.start_with?("#")

      match = RECORD.match(line)
      if match.nil?
        raise ArgumentError,
              "VERSIONS line is not `<kind> <name> <value>`: #{line.inspect}"
      end

      [match[1], match[2], match[3]]
    end
  end

  def value(kind, name, path = PATH)
    found = records(path).find do |record_kind, record_name, _|
      record_kind == kind && record_name == name
    end
    raise KeyError, "VERSIONS has no `#{kind} #{name}` record" if found.nil?

    found[2]
  end

  def gem_version(name) = value("gem", name)
  def gem_names = records.select { |kind, _, _| kind == "gem" }.map { |_, name, _| name }
  def ruby_floor = value("ruby", "floor")
  def ruby_dev = value("ruby", "dev")
  def ruby_matrix = value("ruby", "matrix").split

  def tools
    records.select { |kind, _, _| kind == "tool" }
      .to_h { |_, name, constraint| [name, constraint] }
  end

  # The `~> MAJOR.MINOR` constraint every adapter declares on core (design §2.3). Derived rather
  # than written down, so a core bump to 0.1.0 fails every adapter that was not updated.
  def core_constraint
    major, minor, = gem_version("dexpace-core").split(".")
    "~> #{major}.#{minor}"
  end
end
