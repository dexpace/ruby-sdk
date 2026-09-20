# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The gates that read this repository's own artifacts: gemspecs, require graphs, RBS
# signatures, the runtime constant tree and built .gem files. Third-party tool wiring is in
# tasks/quality.rake; VERSIONS consistency is in tasks/versions.rake.
#
# DEXPACE_GATE_ROOT points a repository-reading gate at another root -- a fixture workspace --
# so the gate suites can watch the TASK go red, not only the tool behind it. Nothing in the
# build sets it.
require_relative "../tools/interpreter"

def gate_root
  ENV.fetch("DEXPACE_GATE_ROOT") { __dir__.delete_suffix("/tasks") }
end

# The require path and namespace constant each gem's smoke path exercises. Reused by
# gates:single_instance and gates:surface_snapshot.
CLEAN_BUNDLE_ENTRIES = {
  "dexpace-core" => %w[dexpace Dexpace],
  "dexpace-transport-net_http" => %w[dexpace/transport/net_http Dexpace::Transport::NetHTTP],
  "dexpace-transport-async_http" => %w[dexpace/transport/async_http Dexpace::Transport::AsyncHTTP],
  "dexpace-serde-json" => %w[dexpace/serde/json Dexpace::Serde::JSON],
  "dexpace-async-thread" => %w[dexpace/async/thread Dexpace::Async::Thread],
  "dexpace-conformance" => %w[dexpace/conformance Dexpace::Conformance],
}.freeze

# Two subprocesses, no shell: `bundle install`, then `bundle exec ruby -e <smoke>`. Bundler
# refuses to activate a gem outside the bundle, and that refusal is the whole gate. `bash -lc`
# would source the developer's login profile and re-resolve `ruby` from PATH, which on a matrix
# row is exactly the wrong interpreter -- so `bundle` and `ruby` are the running interpreter's
# own (tools/interpreter.rb), and the smoke script asserts it landed on the same RUBY_VERSION.
#
# `core_path` is the ONLY entry permitted beside the gem under test, and only for an adapter,
# whose gemspec declares dexpace-core. It does not weaken the gate: a declared dependency
# resolved from the workspace is still a declared dependency, and Bundler goes on refusing every
# undeclared name -- verified on 4.0.6, where an adapter bundle carrying core by path still dies
# with `cannot load such file -- logger (LoadError)`.
def clean_bundle_check(name, path, entry, constant, core_path: nil)
  Dir.mktmpdir("dexpace-clean-bundle") do |dir|
    core_line = core_path.nil? ? "" : "gem \"dexpace-core\", path: #{core_path.inspect}\n"
    File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
      # frozen_string_literal: true
      source "https://rubygems.org"
      gem #{name.inspect}, path: #{path.inspect}
      #{core_line}
    GEMFILE
    env = { "BUNDLE_GEMFILE" => File.join(dir, "Gemfile") }

    Bundler.with_unbundled_env do
      bundle = Interpreter.executable("bundle")
      in_scratch_bundle(
        env, dir, bundle, "install", "--quiet", failing: "#{name} would not install",
      )
      in_scratch_bundle(
        env, dir, bundle, "exec", Interpreter.ruby, "-e", smoke_script(entry, constant),
        failing: "#{name} failed in isolation",
      )
    end
  end
end

def smoke_script(entry, constant)
  "abort(\"ran on \#{RUBY_VERSION}\") unless RUBY_VERSION == #{RUBY_VERSION.inspect}; " \
    "require #{entry.inspect}; " \
    "abort(\"no VERSION\") unless #{constant}::VERSION.match?(/\\A\\d+\\.\\d+\\.\\d+\\z/)"
end

def in_scratch_bundle(env, dir, *command, failing:)
  out, err, status = Open3.capture3(env, *command, chdir: dir)
  abort("gates:clean_bundle: #{failing}:\n#{out}\n#{err}") unless status.success?
end

# The runtime manifest of one gem: the lines its entry file adds to the `Dexpace` tree, produced
# in a subprocess that has only that gem and core on its load path, so the tree it walks is the
# tree a consumer of that gem alone would see. The walk is rooted at `Dexpace` for every gem and
# not at the gem's own constant (Surface.contribution says why), and an adapter's subprocess
# loads core first so that core's lines are the baseline and never part of an adapter's manifest.
# DEXPACE_SURFACE_EXTRA injects a constant, which is how the gate's own test turns it red.
def surface_for(root, name, constant)
  require "open3"
  out, err, status = Open3.capture3(
    Interpreter.ruby, "-I#{File.join(root, "gems", name, "lib")}",
    "-I#{File.join(root, "gems/dexpace-core/lib")}", "-e", surface_script(root, name, constant),
  )
  abort("gates:surface_snapshot: #{name} would not load:\n#{err}") unless status.success?
  out
end

def surface_script(root, name, constant)
  entry = CLEAN_BUNDLE_ENTRIES.fetch(name).first
  baseline = name == "dexpace-core" ? "" : 'require "dexpace"'
  <<~RUBY
    require #{File.join(root, "tools/surface.rb").inspect}
    #{baseline}
    manifest = Surface.contribution("Dexpace") do
      require #{entry.inspect}
      #{surface_injection(constant)}
    end
    print manifest
  RUBY
end

# The injection DEXPACE_SURFACE_EXTRA asks for, as a line of the subprocess script. A bare name
# lands inside the gem's own namespace. A `::`-qualified name lands where it says, in each
# subprocess that already defines its owner and nowhere else: `Dexpace::Transport::Shared`
# reaches the two transports' trees and no other gem's, which is the shape of the leak it stands
# in for -- an export placed beside an adapter's namespace rather than inside it.
def surface_injection(constant)
  extra = ENV.fetch("DEXPACE_SURFACE_EXTRA", nil)
  return "" if extra.nil?

  *owner, name = extra.split("::")
  owner = owner.empty? ? constant : owner.join("::")
  "Object.const_get(#{owner.inspect}).const_set(#{name.inspect}, 1) " \
    "if Object.const_defined?(#{owner.inspect})"
end

# The message names the constants and methods that moved. A gate that says only "differs"
# sends the reader to a diff tool to find out what it already knows.
def surface_drift_message(name, expected, actual)
  before = expected.lines.map(&:chomp)
  after = actual.lines.map(&:chomp)
  added = (after - before).map { |line| "  + #{line}" }
  removed = (before - after).map { |line| "  - #{line}" }

  "#{name}: runtime surface differs from test/fixtures/surface/#{name}.txt.\n" \
    "#{(added + removed).join("\n")}\n" \
    "Changing exports means regenerating BOTH artifacts: run `rake surface:regenerate` and " \
    "update sig/ in the same change (design §9.1)."
end

namespace :surface do
  desc "Rewrite the committed runtime surface manifests -- a deliberate, reviewed act"
  task :regenerate do
    root = gate_root
    FileUtils.mkdir_p(File.join(root, "test/fixtures/surface"))
    CLEAN_BUNDLE_ENTRIES.each do |name, (_entry, constant)|
      File.write(
        File.join(root, "test/fixtures/surface/#{name}.txt"), surface_for(root, name, constant),
      )
    end
  end
end

namespace :gates do
  desc "SEAM-1/NFR-1/NFR-2: runtime dependencies, per gem"
  task :gemspec_audit do
    require_relative "../tools/gemspec_audit"
    root = gate_root
    found = GemspecAudit.violations(root)
    abort(found.join("\n")) unless found.empty?

    count = Dir.glob(File.join(root, "gems/*/*.gemspec")).length
    puts "gates:gemspec_audit: #{count} gemspecs, dependency budget respected."
  end

  desc "SEAM-1/SEAM-2/NFR-1: every require in every gem, against the allowlist and the denylist"
  task :require_allowlist do
    require_relative "../tools/require_allowlist"
    found = RequireAllowlist.violations(gate_root)
    abort(found.join("\n")) unless found.empty?

    table = if RequireAllowlist.bundled?
              "#{RequireAllowlist.bundled_since.size} bundled gems known"
            else
              "no BUNDLED_GEMS table on this Ruby"
            end
    puts "gates:require_allowlist: clean on Ruby #{RUBY_VERSION} (#{table})."
  end

  desc "SEAM-1/NFR-1/NFR-10: each gem loads inside a bundle holding only itself"
  task :clean_bundle do
    require "bundler"
    require "open3"
    require "tmpdir"

    root = gate_root
    override = ENV.fetch("DEXPACE_CLEAN_BUNDLE_GEM", nil)
    targets =
      if override
        name = File.basename(override)
        { name => CLEAN_BUNDLE_ENTRIES.fetch(name) }
      else
        CLEAN_BUNDLE_ENTRIES
      end

    targets.each do |name, (entry, constant)|
      path = override || File.join(root, "gems", name)
      # An adapter's gemspec declares `dexpace-core`, and nothing is published, so a scratch
      # Gemfile naming the adapter alone cannot resolve: Bundler resolves a path gem's own
      # dependencies and would look for dexpace-core 0.0.0 on rubygems.org. So core goes in by
      # `path:` too, from beside the gem under test -- which is also the right source under
      # DEXPACE_CLEAN_BUNDLE_GEM, whose fixture is already a complete miniature workspace.
      core_path = name == "dexpace-core" ? nil : File.join(File.dirname(path), "dexpace-core")
      clean_bundle_check(name, path, entry, constant, core_path: core_path)
    end

    puts "gates:clean_bundle: #{targets.size} gem(s) load in isolation on Ruby #{RUBY_VERSION}."
  end

  desc "NFR-11: no foreign constant in any public signature under sig/"
  task :rbs_surface do
    require_relative "../tools/rbs_surface"
    found = RbsSurface.violations(Dir.glob(File.join(gate_root, "gems/*/sig/**/*.rbs")))
    abort(found.join("\n")) unless found.empty?

    puts "gates:rbs_surface: no foreign constant in any public signature."
  end

  desc "NFR-4: sig/**/*.rbs against the previous release tag"
  task :sig_diff do
    require_relative "../tools/sig_diff"
    root = gate_root
    tag = SigDiff.baseline(root)

    if tag.nil?
      if SigDiff.tags?(root)
        abort("gates:sig_diff: v* tags exist but `git describe` found none reachable from HEAD.")
      end
      puts "gates:sig_diff: no release tag yet -- the first v* tag becomes the baseline."
      next
    end

    found = SigDiff.violations(root, tag)
    abort(found.join("\n\n")) unless found.empty?
    puts "gates:sig_diff: no public signature removed or narrowed since #{tag}."
  end

  desc "NFR-4: the runtime constant/method manifest, per gem"
  task :surface_snapshot do
    root = gate_root
    drift = CLEAN_BUNDLE_ENTRIES.filter_map do |name, (_entry, constant)|
      expected_path = File.join(root, "test/fixtures/surface/#{name}.txt")
      actual = surface_for(root, name, constant)
      expected = File.exist?(expected_path) ? File.read(expected_path) : ""
      next if expected == actual

      surface_drift_message(name, expected, actual)
    end
    abort(drift.join("\n\n")) unless drift.empty?

    puts "gates:surface_snapshot: #{CLEAN_BUNDLE_ENTRIES.size} manifests match the runtime tree."
  end

  desc "NFR-12: each gem builds twice to byte-identical output"
  task :reproducible do
    require_relative "../tools/reproducible"
    gems = Dir.glob(File.join(gate_root, "gems/*"))

    gems.each do |gem_dir|
      first, second = Reproducible.digests(gem_dir)
      next if first == second

      abort("gates:reproducible: #{File.basename(gem_dir)} built two different artifacts: " \
            "#{first} != #{second}")
    end

    puts "gates:reproducible: #{gems.size} gems, byte-identical across two builds."
  end

  desc "Design §2.4: one resolved path per core file; Dexpace::VERSION matches the gemspec"
  task :single_instance do
    require "open3"
    root = gate_root
    gemspec_path = File.join(root, "gems/dexpace-core/dexpace-core.gemspec")
    script = <<~RUBY
      # A second copy of core cannot even finish loading: every model is
      # `class X < Data.define(...)`, and re-opening one from another copy of its file hands
      # Ruby a fresh anonymous superclass, which it refuses with `superclass mismatch`. That
      # refusal is the single-instance violation itself, one file earlier than the tally below
      # would see it, so it is caught and reported in the tally's own terms rather than as a
      # stack trace -- the features loaded before it are already on $LOADED_FEATURES twice.
      reopened = nil
      begin
        require "dexpace"
      rescue TypeError => error
        raise unless error.message.include?("superclass mismatch")

        reopened = error.message
      end

      # The duplicate a nested-resolution package manager would create; Ruby cannot produce it,
      # so the gate simulates one to prove it would be caught.
      if ENV["DEXPACE_FORCE_DUPLICATE"]
        $LOADED_FEATURES << $LOADED_FEATURES.grep(%r{/dexpace\\.rb\\z}).first
      end

      # Keyed on the feature, not the resolved path: `require` never records one path twice,
      # so the case §2.4 argues against -- one core file reached from two directories, a
      # vendored copy beside a gem-installed one -- shows up as two paths for one feature.
      feature_key = %r{(?:\\A|/lib/)(dexpace(?:/.*)?\\.rb)\\z}
      paths = $LOADED_FEATURES.grep(%r{/dexpace(/.*)?\\.rb\\z})
      duplicated = paths.group_by { |path| path[feature_key, 1] || path }
        .select { |_, found| found.length > 1 }
      unless duplicated.empty? && reopened.nil?
        listed = duplicated.map { |feature, found| "\#{feature} from \#{found.join(" and ")}" }
        listed << "a model re-opened from the second copy (\#{reopened})" unless reopened.nil?
        abort("loaded twice: \#{listed.join("; ")}")
      end

      spec = Gem::Specification.load(#{gemspec_path.inspect})
      unless Dexpace::VERSION == spec.version.to_s
        abort("VERSION \#{Dexpace::VERSION} != gemspec \#{spec.version}")
      end
    RUBY
    _out, err, status = Open3.capture3(
      { "DEXPACE_FORCE_DUPLICATE" => ENV.fetch("DEXPACE_FORCE_DUPLICATE", nil) },
      Interpreter.ruby, "-I#{File.join(root, "gems/dexpace-core/lib")}", "-e", script,
    )
    abort(err) unless status.success?

    puts "gates:single_instance: one resolved path per core file; " \
         "VERSION agrees with the gemspec."
  end

  desc "SSE-37 and spec-forced boundary 5: no serialization dependency under the guarded paths"
  task :serde_boundary do
    require_relative "../tools/serde_boundary"
    root = gate_root
    found = SerdeBoundary.violations(root)
    abort(found.join("\n")) unless found.empty?

    SerdeBoundary.pending(root).each do |glob, reason, matched|
      puts "gates:serde_boundary: PENDING #{glob} (#{matched} file(s) today) -- #{reason}"
    end
    puts "gates:serde_boundary: #{SerdeBoundary::GUARDED.size} guarded globs clean."
  end
end
