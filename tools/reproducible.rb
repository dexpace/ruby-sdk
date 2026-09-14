# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "digest"
require "open3"
require "tmpdir"
require_relative "interpreter"

# NFR-12. `gem build` honours SOURCE_DATE_EPOCH, and spec.files ordering is the other half:
# the two together are what make identical source inputs produce identical bytes.
module Reproducible
  extend self

  # 2026-01-01T00:00:00Z. A fixed epoch, not Time.now: the point is that two builds of the same
  # source agree, and a moving epoch would make them agree only by accident.
  EPOCH = "1767225600"

  # Builds `gem_dir` twice and returns the two SHA-256 digests. A block, if given, runs between
  # the builds -- which is how the negative fixture perturbs a file's mtime.
  def digests(gem_dir, epoch: EPOCH)
    name = File.basename(Dir.glob(File.join(gem_dir, "*.gemspec")).first, ".gemspec")
    first = build(gem_dir, name, epoch)
    yield if block_given?
    [first, build(gem_dir, name, epoch)]
  end

  private

  def build(gem_dir, name, epoch)
    Dir.mktmpdir("dexpace-build") do |out|
      target = File.join(out, "#{name}.gem")
      # A nil value UNSETS the variable for the subprocess; an empty hash would inherit whatever
      # the developer's shell exported, and "unset" would then measure that shell instead.
      env = { "SOURCE_DATE_EPOCH" => epoch }
      stdout, stderr, status = Open3.capture3(
        env, Interpreter.executable("gem"), "build", "#{name}.gemspec", "--output", target,
        "--quiet", chdir: gem_dir,
      )
      raise "gem build failed for #{name}:\n#{stdout}\n#{stderr}" unless status.success?

      Digest::SHA256.file(target).hexdigest
    end
  end
end
