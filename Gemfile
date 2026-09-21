# frozen_string_literal: true
# SPDX-License-Identifier: MIT

source "https://rubygems.org"

# NFR-14: every constraint below comes from a `tool` record in the repository-root VERSIONS
# file, which tools/versions.rb is the only parser of.
require_relative "tools/versions"

group :development, :test do
  DexpaceVersions.tools.each { |name, constraint| gem name, constraint }
end

# The workspace's own gems, by path, so `bundle exec` resolves them without an install: the six
# MVP gems under gems/, and any gem a later phase adds there. A gem whose own VERSIONS floor this
# interpreter does not meet is left out rather than handed to Bundler, which refuses a path gem's
# required_ruby_version at install time for the whole workspace (phase 8c's P8-36: only
# dexpace-transport-async_http, on the 3.2 row).
Dir.glob("gems/*", base: __dir__).sort.each do |dir|
  next unless DexpaceVersions.gem_supported?(File.basename(dir))

  gem File.basename(dir), path: dir
end
