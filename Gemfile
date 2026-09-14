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
# MVP skeletons under gems/, and any gem a later phase adds there.
Dir.glob("gems/*", base: __dir__).sort.each do |dir|
  gem File.basename(dir), path: dir
end
