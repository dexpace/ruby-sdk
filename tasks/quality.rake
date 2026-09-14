# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The wiring for third-party tools -- rubocop, the custom cops' suite, rbs, steep, yard and
# bundler-audit -- plus the two test tasks. The gates that read this repository's own artifacts
# are in tasks/gates.rake; VERSIONS consistency is in tasks/versions.rake.
#
# Every tool runs through the running interpreter's own `bundle` (tools/interpreter.rb), never
# a `bundle` resolved from PATH: a nested `bundle exec` inherits the outer PATH unchanged, and
# on a machine with a version-manager shim that is not necessarily the Ruby running rake.
require_relative "../tools/interpreter"

def bundle = Interpreter.executable("bundle")

desc "NFR-7: RuboCop, findings fatal, no autocorrection"
task :rubocop do
  sh(bundle, "exec", "rubocop", "--fail-level=convention", "--format", "progress")
end

# `--autocorrect` (safe only), never `--autocorrect-all`: `-A` applies unsafe corrections too, and
# an unsafe correction that silently changes semantics in a correctness-critical HTTP client is
# exactly the risk NFR-7 exists to surface.
desc "Safe autocorrections only, as a developer convenience -- never the gate"
task :"rubocop:fix" do
  sh(bundle, "exec", "rubocop", "--autocorrect")
end

namespace :cops do
  desc "NFR-13 and the ban list: the custom cops' own suite"
  task :test do
    sh(bundle, "exec", Interpreter.ruby, "-w", "-I.rubocop/test", ".rubocop/test/cops_test.rb")
  end
end

require_relative "../tools/require_allowlist"

namespace :rbs do
  desc "NFR-3: rbs validate, per gem"
  task :validate do
    # `--no-collection`: the collection is resolved from the whole Gemfile.lock, development
    # group included, and a dev tool's own shipped sig/ is not this repository's to validate.
    # A gem's environment is its own sig/, core's sig/ for an adapter (as the Steepfile's targets
    # say), and rbs's stdlib -- nothing else. The stdlib half is the signature sets for the
    # features the require allowlist admits, loaded explicitly with `-r` because `--no-collection`
    # loads none of them; `set` is left out as the Steepfile's core target leaves it out, since
    # rbs 4 ships Set under core/ rather than stdlib/.
    stdlib = (RequireAllowlist::ALLOWED - %w[set]).flat_map { |name| ["-r", name] }
    Dir.glob("gems/*").each do |dir|
      core = dir.end_with?("/dexpace-core") ? [] : ["-I", "gems/dexpace-core/sig"]
      sh(bundle, "exec", "rbs", "-I", "#{dir}/sig", *core, *stdlib, "--no-collection", "validate")
    end
  end
end

desc "NFR-3: steep check, target by target"
task :steep do
  # Fresh, never --frozen: the lock is not committed, so each row resolves for itself.
  sh(bundle, "exec", "rbs", "collection", "install")
  sh(bundle, "exec", "steep", "check")
end

desc "Documentation, with an undocumented-public-object gate"
task :yard do
  # DEXPACE_YARD_FILES points the gate at another tree -- the gate's own fixtures -- in place of
  # .yardopts, so its test can watch the task go red. Nothing in the build sets it.
  files = ENV.fetch("DEXPACE_YARD_FILES", nil)
  scope = files.nil? ? [] : ["--no-yardopts", "--no-save", *Dir.glob(files)]
  sh(bundle, "exec", "yard", "doc", "--quiet", *scope) if files.nil?
  stats = IO.popen([bundle, "exec", "yard", "stats", "--list-undoc", *scope], &:read)
  puts stats
  abort("undocumented public objects (styleguide 14.1)") unless stats.include?("100.00% documented")
end

desc "Dependency CVE scan, against the lockfile this bundle just resolved"
task :bundler_audit do
  # There is no committed Gemfile.lock (see docs/knowledge/notes/tooling-and-quality-gates.md),
  # so the scan runs against the resolve on disk -- which is what CI actually installed.
  sh(bundle, "exec", "bundler-audit", "check", "--update")
end

require_relative "../tools/suite_runner"

namespace :test do
  desc "NFR-5/NFR-6/NFR-10: every gem's suite, warnings fatal, coverage floor enforced"
  task :gems do
    SuiteRunner.run(
      FileList["gems/*/test/**/*_test.rb"], Dir.glob("gems/*/lib") + %w[test], coverage: true,
    )
  rescue SuiteRunner::Failure => error
    abort(error.message)
  end

  desc "The repository's gate suites: they drive rake, git and bundle, so CI runs them once"
  task :gates do
    SuiteRunner.run(
      FileList["test/gates/**/*_test.rb"], Dir.glob("gems/*/lib") + %w[test], coverage: false,
    )
  rescue SuiteRunner::Failure => error
    abort(error.message)
  end
end
