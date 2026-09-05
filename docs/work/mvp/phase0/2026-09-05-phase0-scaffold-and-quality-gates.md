# Phase 0 — Scaffold and Quality Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the workspace root and six MVP gem skeletons at `0.0.0`, with seventeen blocking
quality gates wired into one default Rake task and a deliberately failing fixture proving each
one fires.

**Architecture:** One repository, one gemspec per published gem under `gems/`, a root `Gemfile`
and `Rakefile` that own the toolchain and the gate set, and a repository-root `VERSIONS` file that
every gemspec reads. Gates live in `tasks/*.rake` as separately invocable tasks and are tested
from `test/gates/` against fixtures under `test/fixtures/gates/`, so a gate is proven by watching
it reject something rather than by watching it pass over an empty tree.

**Tech Stack:** Ruby 3.2–4.0 (development on 4.0.6), Rake, Minitest, RuboCop with
`rubocop-minitest` and `rubocop-performance`, RBS + Steep, SimpleCov, YARD, bundler-audit,
GitHub Actions.

**Spec:** `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md`

## Global Constraints

Every task's requirements implicitly include this section. Values are copied verbatim from the
design and the governing documents.

- **Ruby floor is `>= 3.2`** in every gemspec (`NFR-10`). The CI matrix is exactly
  `3.2 / 3.3 / 3.4 / 4.0` and runs the **real suite**, not a syntax check. Development pin is
  **4.0.6**, the highest Ruby in the matrix.
- **`dexpace-core.gemspec` contains zero `add_dependency` lines.** That assertion *is* the
  `SEAM-1` dependency audit. Each adapter declares `dexpace-core` plus **at most one** other gem
  (`NFR-2`).
- **Core may `require` only** the twelve allowlisted names in Task 9. `json`, `net/http`,
  `net/protocol`, `open-uri`, `socket`, `resolv` and `timeout` are stable default gems and are
  **denied by name** (`SEAM-2`, design §8.3).
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1 and
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`;
  `docs/knowledge/notes/formatting-and-tooling.md`). **No `# typed:` sigil anywhere**, test files
  included (`docs/knowledge/notes/testing.md`).
- **RuboCop:** `plugins: [rubocop-minitest, rubocop-performance]`, `NewCops: enable`,
  `TargetRubyVersion: 3.2`, `--fail-level=convention`, no autocorrection in the gate, no
  `rubocop-airbnb`, no pre-commit hook. Waivers only as scoped inline directives carrying a
  reason (`NFR-7`; `tooling-and-quality-gates/cb18f9bd`).
- **Formatting:** double quotes, 2-space indent, 100 columns, `consistent_comma` trailing commas,
  leading-dot chains, `MethodLength: 25` with `CountAsOne: [array, hash, heredoc]`,
  `ParameterLists: 4`, `BlockNesting: 3`.
- **`Gemfile.lock` is not committed** and is in `.gitignore`; no `bundle install --frozen`
  anywhere (`docs/knowledge/notes/tooling-and-quality-gates.md`, key
  `tooling-and-quality-gates/f638625d`).
- **Tests:** Minitest only. `FooTest < Minitest::Test`, `test "..." do` blocks, `test/` mirroring
  `lib/` one file per file, `assert_equal(expected, actual)` in that order, every test passes
  alone and in any order, the random seed is never overridden.
- **No commit step appears in any task.** The manager commits once per phase. Every task ends
  with its gate green and the working tree staged by nobody.
- **Never edit** `docs/product-spec/`, `docs/product-spec.md`, `docs/sdk-design-ruby/`,
  `docs/sdk-design-ruby.md` or `docs/knowledge/harvested/`. Corrections to harvested knowledge are
  notes under `docs/knowledge/notes/`.

---

## File Structure

Grouped by responsibility. Every file below is created by exactly one task.

**The development environment (Task 1).** `.ruby-version`, `.gitattributes`, `.editorconfig`,
`.gitignore`. Responsibility: one interpreter pin, one line-ending policy, one ignore list.

**The build spine (Task 2).** `VERSIONS`, `tools/versions.rb`, `Gemfile`, `Rakefile`,
`tasks/quality.rake`, `tasks/gates.rake`, `tasks/versions.rake`. Responsibility: the single source
of truth and its only parser, plus the default task and the namespaces every later gate hangs on.
`VERSIONS` and `tools/versions.rb` are in this task rather than a later one because the `Gemfile`
reads the reader for every constraint, so a `Gemfile` written before it exists breaks every
`bundle exec` in Tasks 3 and 4. `tasks/gates.rake` holds the checks that read the repository's own
artifacts; `tasks/quality.rake` holds the wiring for third-party tools and the two test tasks;
`tasks/versions.rake` holds `VERSIONS` consistency alone, because it is the one gate that reads
every other artifact.

**Lint (Tasks 3–4).** `.rubocop.yml`, `.rubocop/cops/dexpace/*.rb`, `.rubocop/test/cop_case.rb`,
`.rubocop/test/cops_test.rb`. Responsibility: one cop per rule, and one data-driven suite over all
five. Split from the baseline because a reviewer can reject a cop's semantics while approving the
config.

**The six gems (Task 5).** `gems/<gem>/{<gem>.gemspec,README.md,LICENSE,Rakefile,lib/**,sig/**}`.
Responsibility: a publishable, requirable, signature-carrying skeleton per gem.

**The test convention (Tasks 6–7).** `test/support/dexpace_test_case.rb`,
`test/support/coverage.rb`, `gems/*/test/**`. Responsibility: the base class every gem suite
inherits, the warnings-fatal mechanism, and the coverage bootstrap. (`test/support/gate_case.rb`,
the base for a *gate* test, is Task 2's — the gate suites start in Task 2 and the gem suites do
not exist until Task 5.)

**The zero-dependency gates (Tasks 8–11).** Bodies in `tasks/gates.rake`, tests in
`test/gates/{gemspec_audit,require_allowlist,clean_bundle,single_instance}_test.rb`, fixtures in
`test/fixtures/gates/<gate>/`. Responsibility: one gate, one test file, one fixture directory.

**Typing and the surface lock (Tasks 12–15).** `Steepfile`, `rbs_collection.yaml`, plus
`gates:rbs_surface`, `gates:surface_snapshot`, `gates:sig_diff` and
`test/fixtures/surface/*.txt`.

**Documentation and artifact hygiene (Tasks 16–17).** `.yardopts`, `gates:reproducible`,
`bundler_audit`.

**CI and closing (Tasks 18–20).** `.github/workflows/ci.yml`, `gates:versions`, and the phase
record.

---

## Task 1: Development pin, repository hygiene, and toolchain verification

**Files:**
- Create: `.ruby-version`, `.gitattributes`, `.editorconfig`
- Modify: `.gitignore`
- Test: none — this task's test is the verification script it runs and records

**Interfaces:**
- Consumes: nothing.
- Produces: a working Ruby 4.0.6 development environment. Every later task assumes
  `ruby -v` reports `4.0.6` and that `bundle`, `rake`, `rubocop`, `rbs`, `steep`, `simplecov`,
  `yard` and `bundler-audit` resolve on it.

- [ ] **Step 1: Verify Ruby 4.0.6 is installed and re-derive the stdlib facts**

The design's allowlist rests on these three numbers. Confirm them before writing anything.

```bash
mise install ruby@4.0.6
~/.local/share/mise/installs/ruby/4.0.6/bin/ruby -v
~/.local/share/mise/installs/ruby/4.0.6/bin/ruby -e \
  'require "bundler"; p Gem::BUNDLED_GEMS::SINCE.size'
~/.local/share/mise/installs/ruby/4.0.6/bin/ruby -e \
  'p Gem::Specification.select(&:default_gem?).map(&:name).sort.size'
```

Expected: `ruby 4.0.6 ... +PRISM`; `23`; `46`. If any of the three differs, stop and record the
new value in `docs/knowledge/notes/package-and-dependency-layout.md` under `## Superseded`,
naming the interpreter, before continuing — the require-allowlist in Task 9 reads directly from
these.

- [ ] **Step 2: Write `.ruby-version`**

```
4.0.6
```

One line, with a trailing newline. mise, rbenv, chruby and `ruby/setup-ruby` all read it. This
follows styleguide rule 1.1 as resolved by `package-and-dependency-layout/35a6cd13`: the pin names
the **highest Ruby in the matrix**, not the floor, so the bundled-gem trap is caught on the
developer's machine before CI.

- [ ] **Step 3: Confirm the gate toolchain resolves on 4.0.6**

```bash
cd /tmp && mkdir -p dx-tool-probe && cd dx-tool-probe
cat > Gemfile <<'RUBY'
source "https://rubygems.org"
gem "rake"
gem "minitest"
gem "rubocop"
gem "rubocop-minitest"
gem "rubocop-performance"
gem "rbs"
gem "steep"
gem "simplecov"
gem "yard"
gem "bundler-audit"
RUBY
~/.local/share/mise/installs/ruby/4.0.6/bin/ruby -S bundle install
```

Expected: a clean resolve. If any gem refuses to install or its executable raises on `--version`,
**stop and apply the design's stated fallback**: change `.ruby-version` to `3.4.10`, add a bullet
to `docs/knowledge/notes/tooling-and-quality-gates.md` under `## Conflicts` naming the failing
tool and its version, and leave the CI matrix untouched. The matrix is the requirement; the
development pin is ergonomics.

- [ ] **Step 4: Write `.gitattributes`**

```
* text=auto eol=lf
*.rb text eol=lf
*.rbs text eol=lf
*.rake text eol=lf
*.gemspec text eol=lf
*.md text eol=lf
*.yml text eol=lf
*.svg text eol=lf
```

Styleguide rule 1.5 (`formatting-and-tooling/50032150`): the LF conversion belongs at the
repository boundary, not per developer. A CRLF `.rb` file also breaks the knowledge corpus parser,
which is why the boundary matters here specifically.

- [ ] **Step 5: Write `.editorconfig`**

```
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.{rb,rbs,rake,gemspec}]
indent_style = space
indent_size = 2
max_line_length = 100

[*.md]
trim_trailing_whitespace = false
```

- [ ] **Step 6: Append to `.gitignore`**

```
# Bundler resolves per-interpreter across the 3.2/3.3/3.4/4.0 matrix, so a single committed
# lockfile cannot be --frozen-installed on every row. See
# docs/knowledge/notes/tooling-and-quality-gates.md, key tooling-and-quality-gates/f638625d.
/Gemfile.lock
/.bundle/
/coverage/
/doc/
/.yardoc/
/pkg/
/tmp/

# Resolved per interpreter, like Gemfile.lock. `rbs collection install` runs fresh on every row.
/.gem_rbs_collection/
/rbs_collection.lock.yaml
```

- [ ] **Step 7: Verify the pin takes effect**

Run: `cd /home/mohammad/Projects/dexpace/ruby-sdk && ruby -v`
Expected: `ruby 4.0.6 ...`, overriding the user's global mise pin. If it still reports 3.4.10,
`mise install` did not register — re-run `mise install` in the repository directory.

---

## Task 2: The build spine — `VERSIONS`, its reader, `Gemfile`, `Rakefile`, and the rake namespaces

**Files:**
- Create: `VERSIONS`, `tools/versions.rb`, `Gemfile`, `Rakefile`, `tasks/quality.rake`,
  `tasks/gates.rake`, `tasks/versions.rake`
- Test: `test/support/gate_case.rb`, `test/gates/versions_reader_test.rb`,
  `test/gates/default_task_test.rb`

**Interfaces:**
- Consumes: Task 1's `.ruby-version`.
- Produces: `DexpaceVersions.gem_version(name) -> String`, `.gem_names -> Array[String]`,
  `.tools -> Hash[String, String]`, `.ruby_floor -> String`, `.ruby_dev -> String`,
  `.ruby_matrix -> Array[String]`, `.core_constraint -> String` (`"~> 0.0"` today), and
  `.records(path) -> Array[[kind, name, value]]`. Also `GateCase`, with `.test(name, &block)`,
  `#rake(task, env)` and `#assert_gate_rejects`. And `rake -T` listing every gate by name, plus
  the `DEFAULT_GATES` array that every later task appends exactly one entry to.

`VERSIONS` and its reader belong here, not in a later task: the `Gemfile` reads
`tools/versions.rb` for every constraint, so a `Gemfile` written before that file exists makes
every `bundle exec` in Tasks 3 and 4 raise `LoadError`. Nothing else in the repository parses
`VERSIONS`.

- [ ] **Step 1: Write `test/support/gate_case.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "minitest/autorun"
require "fileutils"
require "open3"
require "tempfile"
require "tmpdir"

# The base for a repository gate test. A gate is proven by running it as a subprocess against a
# fixture and reading its exit status, not by calling into its internals -- a gate that only
# passes when driven by its own test is a gate CI has never actually run.
class GateCase < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def self.test(name, &block)
    define_method("test_: #{name}", &block)
  end

  # Runs a rake task and returns [stdout, stderr, status]. Through `bundle exec`, because the
  # gates load rbs, steep and rubocop from the bundle and a bare `rake` would resolve whatever
  # happens to be installed globally.
  def rake(task, env = {})
    Open3.capture3(env, "bundle", "exec", "rake", "-s", task, chdir: ROOT)
  end

  def assert_gate_rejects(task, fixture_env, message_fragment)
    _out, err, status = rake(task, fixture_env)

    refute_predicate(status, :success?, "#{task} accepted #{fixture_env.inspect}")
    assert_includes(err, message_fragment)
  end
end
```

- [ ] **Step 2: Write the two failing tests**

`test/gates/versions_reader_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/versions"

# NFR-14: dependency versions, tool versions and project coordinates live in one source of
# truth. This suite is about the reader; `rake gates:versions` (Task 19) is about the consumers.
class VersionsReaderTest < GateCase
  test "reads every gem version" do
    assert_equal("0.0.0", DexpaceVersions.gem_version("dexpace-core"))
    assert_equal("0.0.0", DexpaceVersions.gem_version("dexpace-conformance"))
  end

  test "reads the runtime floor, the development pin and the matrix" do
    assert_equal("3.2", DexpaceVersions.ruby_floor)
    assert_equal("4.0.6", DexpaceVersions.ruby_dev)
    assert_equal(%w[3.2 3.3 3.4 4.0], DexpaceVersions.ruby_matrix)
  end

  test "derives the adapter constraint on core from the core version" do
    assert_equal("~> 0.0", DexpaceVersions.core_constraint)
  end

  test "raises a named error for a record that is not there" do
    error = assert_raises(KeyError) { DexpaceVersions.gem_version("dexpace-nonexistent") }

    assert_includes(error.message, "dexpace-nonexistent")
  end

  test "raises on a malformed line rather than skipping it" do
    Tempfile.create("VERSIONS") do |file|
      file.write("gem dexpace-core\n")
      file.flush
      error = assert_raises(ArgumentError) { DexpaceVersions.records(file.path) }

      assert_includes(error.message, "<kind> <name> <value>")
    end
  end
end
```

`test/gates/default_task_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# NFR-17: the gates are blocking and automatic, and the default rake task is what makes them so.
# The companion assertion -- that every listed name is a real, separately invocable task -- is
# added in Task 19, once the last gate exists. Asserting it here would leave `rake test:gates`
# red for seventeen tasks, and a suite that is expected to be red is a suite nobody reads.
class DefaultTaskTest < GateCase
  EXPECTED = %w[
    rubocop cops:test rbs:validate steep test:gems test:gates gates:gemspec_audit
    gates:require_allowlist gates:clean_bundle gates:rbs_surface gates:sig_diff
    gates:surface_snapshot gates:single_instance gates:versions gates:reproducible
    yard bundler_audit
  ].freeze

  test "the default task lists every gate, in the design's order" do
    listed = `bundle exec rake -s gates:list`.split("\n")

    assert_equal(EXPECTED, listed)
  end
end
```

- [ ] **Step 3: Run them to confirm they fail**

Run: `ruby -Itest test/gates/versions_reader_test.rb`
Expected: FAIL — `cannot load such file -- tools/versions`.

Run: `ruby -Itest test/gates/default_task_test.rb`
Expected: FAIL — `rake` reports `Don't know how to build task 'gates:list'`, so `listed` is empty.

- [ ] **Step 4: Write `VERSIONS`**

```
# NFR-14's single source of truth. Format: `<kind> <name> <value>`, one record per line.
#
#   gem   <gem name>   <semver>       read by that gem's gemspec and by tools/versions.rb
#   tool  <gem name>   <constraint>   read by the root Gemfile
#   ruby  floor        <version>      required_ruby_version in every gemspec (NFR-10)
#   ruby  matrix       <versions>     the CI matrix; asserted against .github/workflows/ci.yml
#   ruby  dev          <version>      the development pin; asserted against .ruby-version
#
# `rake gates:versions` asserts every consumer agrees with this file. A bump is one edit here
# and a failing gate everywhere it was not propagated.

gem  dexpace-core                 0.0.0
gem  dexpace-transport-net_http   0.0.0
gem  dexpace-transport-async_http 0.0.0
gem  dexpace-serde-json           0.0.0
gem  dexpace-async-thread         0.0.0
gem  dexpace-conformance          0.0.0

tool rake                         ~> 13.3
tool minitest                     ~> 5.25
tool rubocop                      ~> 1.90
tool rubocop-minitest             ~> 0.38
tool rubocop-performance          ~> 1.25
tool rbs                          ~> 3.9
tool steep                        ~> 1.10
tool simplecov                    ~> 0.22
tool yard                         ~> 0.9
tool bundler-audit                ~> 0.9

ruby floor                        3.2
ruby matrix                       3.2 3.3 3.4 4.0
ruby dev                          4.0.6
```

Adjust each `tool` constraint to the newest published minor at implementation time; the values
above are the shape, and the `bundle install` in Step 9 reports the real ones.

- [ ] **Step 5: Write `tools/versions.rb`**

```ruby
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
```

- [ ] **Step 6: Write the `Rakefile`**

```ruby
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
```

- [ ] **Step 7: Write the three empty namespace files**

`tasks/gates.rake`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The gates that read this repository's own artifacts: gemspecs, require graphs, RBS
# signatures, the runtime constant tree and built .gem files. Third-party tool wiring is in
# tasks/quality.rake; VERSIONS consistency is in tasks/versions.rake.
namespace :gates do
end
```

`tasks/versions.rake` has the same shape and the same empty `namespace :gates do end`.
`tasks/quality.rake` has the header comment and no namespace block: its tasks are top-level
(`rubocop`, `cops:test`, `steep`, `yard`, `bundler_audit`) plus the `rbs` and `test` namespaces.

- [ ] **Step 8: Write the `Gemfile`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

source "https://rubygems.org"

# NFR-14: every constraint below comes from a `tool` record in the repository-root VERSIONS
# file, which tools/versions.rb is the only parser of.
require_relative "tools/versions"

group :development, :test do
  DexpaceVersions.tools.each { |name, constraint| gem name, constraint }
end

# The workspace's own gems, by path, so `bundle exec` resolves them without an install. Empty
# until Task 5 creates them.
Dir.glob("gems/*", base: __dir__).sort.each do |dir|
  gem File.basename(dir), path: dir
end
```

- [ ] **Step 9: Run the tests to confirm they pass**

Run: `bundle install`
Expected: a clean resolve of the ten development tools. `Dir.glob("gems/*")` is still empty, so
no path gems are added yet.

Run: `ruby -Itest test/gates/versions_reader_test.rb`
Expected: PASS, 5 runs.

Run: `ruby -Itest test/gates/default_task_test.rb`
Expected: PASS, 1 run — `gates:list` prints the seventeen names in `DEFAULT_GATES` order. Sixteen
of the seventeen are not yet real tasks; Task 19 adds the assertion that catches that, once the
last of them exists.

---

## Task 3: `.rubocop.yml` — the cop baseline and the RuboCop gate

**Files:**
- Create: `.rubocop.yml`
- Modify: `tasks/quality.rake`
- Test: `test/gates/rubocop_config_test.rb`

**Interfaces:**
- Consumes: Task 2's `tasks/quality.rake`.
- Produces: the `rubocop` rake task; a config every later `.rb` file in this repository is written
  against.

- [ ] **Step 1: Write the failing test**

Create `test/gates/rubocop_config_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require "yaml"

# The RuboCop baseline is fixed by docs/knowledge/notes/tooling-and-quality-gates.md, key
# tooling-and-quality-gates/cb18f9bd. These assertions are that note, mechanised.
class RubocopConfigTest < GateCase
  CONFIG = YAML.load_file(File.join(ROOT, ".rubocop.yml"))

  test "loads rubocop-minitest and rubocop-performance as plugins and nothing else" do
    assert_equal(%w[rubocop-minitest rubocop-performance], CONFIG.fetch("plugins").sort)
  end

  test "does not inherit rubocop-airbnb in any form" do
    refute(CONFIG.key?("inherit_gem"), "rubocop-airbnb's inherit_gem incantation does not run")
  end

  test "targets the declared Ruby floor, not the development pin" do
    assert_equal("3.2", CONFIG.dig("AllCops", "TargetRubyVersion").to_s)
  end

  test "enables new cops rather than silently skipping them" do
    assert_equal("enable", CONFIG.dig("AllCops", "NewCops"))
  end

  test "transcribes the styleguide's hand-named settings" do
    assert_equal("double_quotes", CONFIG.dig("Style/StringLiterals", "EnforcedStyle"))
    assert_equal(100, CONFIG.dig("Layout/LineLength", "Max"))
    assert_equal(25, CONFIG.dig("Metrics/MethodLength", "Max"))
    assert_equal(4, CONFIG.dig("Metrics/ParameterLists", "Max"))
    assert_equal(3, CONFIG.dig("Metrics/BlockNesting", "Max"))
    assert_equal("leading", CONFIG.dig("Layout/DotPosition", "EnforcedStyle"))
    assert_equal("nested", CONFIG.dig("Style/ClassAndModuleChildren", "EnforcedStyle"))
  end

  test "the gate itself runs at --fail-level=convention with no autocorrection" do
    body = File.read(File.join(ROOT, "tasks/quality.rake"))

    assert_includes(body, "--fail-level=convention")
    refute_includes(body, "--autocorrect")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/rubocop_config_test.rb`
Expected: FAIL at load — `Errno::ENOENT` for `.rubocop.yml`.

- [ ] **Step 3: Write `.rubocop.yml`**

Every override carries a comment naming the chapter and rule it came from
(`tooling-and-quality-gates/d39dd7c6`); an unexplained `Enabled: false` is rejected in review.

```yaml
# The baseline is fixed by docs/knowledge/notes/tooling-and-quality-gates.md, key
# `tooling-and-quality-gates/cb18f9bd`: rubocop + rubocop-minitest + rubocop-performance,
# --fail-level=convention, and rubocop-airbnb deliberately not inherited (its inherit_gem
# incantation does not run, and the baseline it delivers is weaker). Every cop setting the
# styleguide names by hand is transcribed here directly, so its rules are enforced even though
# its distribution mechanism is not used.
plugins:
  - rubocop-minitest
  - rubocop-performance

require:
  - ./.rubocop/cops/dexpace/spdx_header.rb
  - ./.rubocop/cops/dexpace/no_time_parse.rb
  - ./.rubocop/cops/dexpace/no_uri_default_parser.rb
  - ./.rubocop/cops/dexpace/no_locale_case_fold.rb
  - ./.rubocop/cops/dexpace/no_thread_interrupt.rb

AllCops:
  NewCops: enable
  # styleguide 01 rule 1.1, as resolved by package-and-dependency-layout/35a6cd13: the cop
  # targets the FLOOR (NFR-10), not .ruby-version's development pin.
  TargetRubyVersion: 3.2
  Exclude:
    - "vendor/**/*"
    - "tmp/**/*"
    - "doc/**/*"
    # Gate fixtures are deliberately non-conforming source; they are inputs to a gate, not code.
    - "test/fixtures/**/*"

# styleguide 01 rule 1.4 -- the frozen-string-literal comment is mandatory on every file.
Style/FrozenStringLiteralComment:
  EnforcedStyle: always

# styleguide 01 rule 1.7 -- double quotes always; %q/%Q/%{} banned for ordinary strings.
Style/StringLiterals:
  EnforcedStyle: double_quotes
Style/StringLiteralsInInterpolation:
  EnforcedStyle: double_quotes

# styleguide 01 rule 1.6 -- 100 columns, comments and YARD strings included.
Layout/LineLength:
  Max: 100

# styleguide 01 rule 1.10 -- trailing comma mandatory, chains break with a leading dot.
Style/TrailingCommaInArrayLiteral:
  EnforcedStyleForMultiline: consistent_comma
Style/TrailingCommaInHashLiteral:
  EnforcedStyleForMultiline: consistent_comma
Style/TrailingCommaInArguments:
  EnforcedStyleForMultiline: consistent_comma
Layout/DotPosition:
  EnforcedStyle: leading
Layout/MultilineMethodCallIndentation:
  EnforcedStyle: indented

# styleguide 01 rule 1.11 -- metric caps live in config, not in prose.
Metrics/MethodLength:
  Max: 25
  CountAsOne:
    - array
    - hash
    - heredoc
Metrics/ParameterLists:
  Max: 4
Metrics/BlockNesting:
  Max: 3

# styleguide 12 rule 12.3 -- nested module/class form, never the compact path syntax.
Style/ClassAndModuleChildren:
  EnforcedStyle: nested

# styleguide 06 -- `extend self` or `class << self`, never module_function
# (data-modeling/3775e9d7).
Style/ModuleFunction:
  EnforcedStyle: extend_self

# A rake task file is a DSL of long blocks; the metric cops measure the wrong thing there.
Metrics/BlockLength:
  Exclude:
    - "tasks/*.rake"
    - "Rakefile"
    - "*.gemspec"
    - "**/*_test.rb"

Dexpace/SpdxHeader:
  Enabled: true
Dexpace/NoTimeParse:
  Enabled: true
Dexpace/NoUriDefaultParser:
  Enabled: true
Dexpace/NoLocaleCaseFold:
  Enabled: true
Dexpace/NoThreadInterrupt:
  Enabled: true
```

- [ ] **Step 4: Add the `rubocop` task to `tasks/quality.rake`**

```ruby
desc "NFR-7: RuboCop, findings fatal, no autocorrection"
task :rubocop do
  sh("bundle", "exec", "rubocop", "--fail-level=convention", "--format", "progress")
end

desc "Safe autocorrections only, as a developer convenience -- never the gate"
task :"rubocop:fix" do
  sh("bundle", "exec", "rubocop", "--autocorrect")
end
```

`--autocorrect` (safe only), never `--autocorrect-all`: `-A` applies unsafe corrections too, and
an unsafe correction that silently changes semantics in a correctness-critical HTTP client is
exactly the risk `NFR-7` exists to surface.

- [ ] **Step 5: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/rubocop_config_test.rb`
Expected: PASS, 6 runs. `rake rubocop` still fails because the five custom cop files do not exist
— Task 4 creates them.

---

## Task 4: The five custom cops and their data-driven suite

**Files:**
- Create: `.rubocop/cops/dexpace/spdx_header.rb`, `.rubocop/cops/dexpace/no_time_parse.rb`,
  `.rubocop/cops/dexpace/no_uri_default_parser.rb`,
  `.rubocop/cops/dexpace/no_locale_case_fold.rb`,
  `.rubocop/cops/dexpace/no_thread_interrupt.rb`
- Create: `.rubocop/test/cop_case.rb`, `.rubocop/test/cops_test.rb`
- Modify: `tasks/quality.rake`

**Interfaces:**
- Consumes: Task 3's `.rubocop.yml`, which already `require`s these five paths.
- Produces: `RuboCop::Cop::Dexpace::SpdxHeader`, `::NoTimeParse`, `::NoUriDefaultParser`,
  `::NoLocaleCaseFold`, `::NoThreadInterrupt`; `CopCase#assert_offense(cop_class, source,
  message_fragment)` and `#assert_no_offense(cop_class, source)`; and the `cops:test` rake task,
  which is the second entry in `DEFAULT_GATES`.

One suite, not five. The five cops share one harness, one assertion pair and one shape of case —
a source string and the fragment its message must carry — so five files would be five copies of
the same four lines around a table. The table generates one Minitest method per row, so a failure
still names exactly one case (`testing/fc33f51b`).

- [ ] **Step 1: Write the Minitest cop harness**

RuboCop's own `ExpectOffense` helpers are RSpec-only, and this repository has no RSpec. Create
`.rubocop/test/cop_case.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "minitest/autorun"
require "rubocop"

Dir[File.expand_path("../cops/**/*.rb", __dir__)].sort.each { |file| require file }

# The Minitest equivalent of RuboCop::RSpec::ExpectOffense: parse a source string, run one cop
# over it through a Commissioner, and assert on the offenses it reported.
class CopCase < Minitest::Test
  # The same floor .rubocop.yml targets (NFR-10), so a cop is tested against the syntax it will
  # actually meet rather than against the development interpreter's.
  TARGET_RUBY = 3.2

  def self.test(name, &block)
    define_method("test_: #{name}", &block)
  end

  def offenses_for(cop_class, source, path: "lib/dexpace/example.rb")
    config = RuboCop::Config.new({ "AllCops" => { "TargetRubyVersion" => TARGET_RUBY } }, "/")
    cop = cop_class.new(config)
    processed = RuboCop::ProcessedSource.new(source, TARGET_RUBY, path)
    commissioner = RuboCop::Cop::Commissioner.new([cop], [], raise_error: true)

    commissioner.investigate(processed).offenses
  end

  def assert_offense(cop_class, source, message_fragment)
    found = offenses_for(cop_class, source)

    refute_empty(found, "expected #{cop_class} to register an offense on:\n#{source}")
    assert_includes(found.map(&:message).join("\n"), message_fragment)
  end

  def assert_no_offense(cop_class, source)
    assert_empty(offenses_for(cop_class, source).map(&:message))
  end
end
```

- [ ] **Step 2: Write the failing data-driven suite**

`.rubocop/test/cops_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "cop_case"

# The five cops that mechanise CLAUDE.md's ban list and NFR-13. One row per case, one generated
# Minitest method per row, so a failure names exactly one input.
class CopsTest < CopCase
  D = RuboCop::Cop::Dexpace
  HEADER = "# frozen_string_literal: true\n# SPDX-License-Identifier: MIT\n\n"

  # [cop, source, the fragment the message must carry]
  REJECTED = [
    # NFR-13, and the header shape in docs/knowledge/notes/formatting-and-tooling.md.
    [D::SpdxHeader, "# frozen_string_literal: true\n\nmodule Dexpace\nend\n",
     "SPDX-License-Identifier: MIT"],
    [D::SpdxHeader, "#{HEADER.sub("MIT", "Apache-2.0")}module Dexpace\nend\n",
     "SPDX-License-Identifier: MIT"],
    [D::SpdxHeader, "# frozen_string_literal: true\n", "SPDX-License-Identifier: MIT"],
    [D::SpdxHeader, "# SPDX-License-Identifier: MIT\n# frozen_string_literal: true\n\nX = 1\n",
     "frozen_string_literal"],
    [D::SpdxHeader,
     "# frozen_string_literal: true\n# SPDX-License-Identifier: MIT\nmodule Dexpace\nend\n",
     "must be blank"],

    # Design §3.5: Time.parse guesses at ambiguous input; HTTP dates are parsed explicitly.
    [D::NoTimeParse, "Time.parse(header)\n", "banned"],
    [D::NoTimeParse, "Date.parse(header)\n", "banned"],
    [D::NoTimeParse, "DateTime.parse(header)\n", "banned"],
    [D::NoTimeParse, "::Time.parse(header)\n", "banned"],

    # Design §3.5: DEFAULT_PARSER changed meaning at exactly Ruby 3.4.0, which straddles the
    # supported floor.
    [D::NoUriDefaultParser, "URI::DEFAULT_PARSER.parse(raw)\n", "RFC3986_PARSER"],
    [D::NoUriDefaultParser, "URI.parse(raw)\n", "RFC3986_PARSER"],
    [D::NoUriDefaultParser, "URI.join(base, rel)\n", "RFC3986_PARSER"],
    [D::NoUriDefaultParser, "URI.split(raw)\n", "RFC3986_PARSER"],

    # HTTP-13: header folding is ASCII. "I".downcase(:turkic) is "ı".
    [D::NoLocaleCaseFold, "name.downcase(:turkic)\n", "no argument"],
    [D::NoLocaleCaseFold, "name.upcase(:turkic)\n", "no argument"],
    [D::NoLocaleCaseFold, "name.capitalize(:turkic)\n", "no argument"],
    [D::NoLocaleCaseFold, "name.swapcase(:turkic)\n", "no argument"],
    [D::NoLocaleCaseFold, "name.downcase!(:fold)\n", "no argument"],
    [D::NoLocaleCaseFold, "a.casecmp?(b)\n", "ASCII-only"],

    # Design §8.3: an async interrupt can land inside an `ensure` releasing a pooled connection.
    [D::NoThreadInterrupt, "Timeout.timeout(5) { read }\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "worker_thread.raise(Interrupt)\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "worker_thread.kill\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "Thread.current.terminate\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "worker_thread.exit\n", "banned repository-wide"],
  ].freeze

  # [cop, source] -- the sanctioned form each ban points at.
  ACCEPTED = [
    [D::SpdxHeader, "#{HEADER}module Dexpace\nend\n"],
    [D::NoTimeParse, "Time.httpdate(header)\n"],
    [D::NoTimeParse, "MediaType.parse(header)\n"],
    [D::NoUriDefaultParser, "URI::RFC3986_PARSER.parse(raw)\n"],
    [D::NoLocaleCaseFold, "name.downcase\n"],
    [D::NoLocaleCaseFold, "a.casecmp(b).zero?\n"],
    [D::NoThreadInterrupt, "raise ArgumentError, \"url is required\"\n"],
    [D::NoThreadInterrupt, "http.read_timeout = deadline.remaining\n"],
  ].freeze

  REJECTED.each_with_index do |(cop, source, fragment), index|
    test "#{cop.badge} rejects case #{index}: #{source.lines.first.strip}" do
      assert_offense(cop, source, fragment)
    end
  end

  ACCEPTED.each_with_index do |(cop, source), index|
    test "#{cop.badge} accepts case #{index}: #{source.lines.first.strip}" do
      assert_no_offense(cop, source)
    end
  end
end
```

- [ ] **Step 3: Run the suite to confirm it fails**

Run: `ruby -I.rubocop/test .rubocop/test/cops_test.rb`
Expected: FAIL at load — `NameError: uninitialized constant RuboCop::Cop::Dexpace`.

- [ ] **Step 4: Write `spdx_header.rb`**

The cop enforces the whole header block, in this order and no other: **line 1
`# frozen_string_literal: true`, line 2 `# SPDX-License-Identifier: MIT`, line 3 blank.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # NFR-13, plus styleguide 1.4's header shape. The reference enforces the licence header as
      # a review convention; this port enforces it mechanically, because a SHOULD carried by
      # convention across six gems and ten phases is a SHOULD that decays.
      #
      # Line 2 is the SPDX identifier because there is no `# typed:` sigil in this repository to
      # occupy that slot (docs/knowledge/notes/formatting-and-tooling.md). Line 1 stays the
      # frozen-string-literal comment: Style/FrozenStringLiteralComment requires it to be present
      # but not to be first, and styleguide rule 1.4 requires it to be the very first line
      # (`formatting-and-tooling/bf14bf0e`), so pinning the position is this cop's job.
      class SpdxHeader < Base
        FROZEN = "# frozen_string_literal: true"
        SPDX = "# SPDX-License-Identifier: MIT"
        MSG_FROZEN = "Line 1 must be `#{FROZEN}` (styleguide 1.4)."
        MSG_SPDX = "Line 2 must be `#{SPDX}` (NFR-13)."
        MSG_BLANK = "Line 3 must be blank, separating the header block from the file's content."

        def on_new_investigation
          lines = processed_source.lines
          return if lines.empty?

          add_offense(line_range(1), message: MSG_FROZEN) if lines[0] != FROZEN
          add_offense(line_range(2), message: MSG_SPDX) if lines[1] != SPDX
          return if lines.length < 3 || lines[2].to_s.strip.empty?

          add_offense(line_range(3), message: MSG_BLANK)
        end

        private

        def line_range(number)
          processed_source.buffer.line_range([number, processed_source.lines.length].min)
        end
      end
    end
  end
end
```

- [ ] **Step 5: Write `no_time_parse.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # Design §3.5. `Time.parse` guesses at an ambiguous string and its behaviour is locale-
      # and version-sensitive; an HTTP date is a fixed grammar and is parsed with
      # `Time.httpdate` or an explicit format.
      class NoTimeParse < Base
        MSG = "`%<offender>s` is banned: parse HTTP dates explicitly with `Time.httpdate` " \
              "or a fixed format (design §3.5)."
        RESTRICT_ON_SEND = %i[parse].freeze

        # @!method banned_parse?(node)
        def_node_matcher :banned_parse?, <<~PATTERN
          (send (const {nil? cbase} {:Time :Date :DateTime}) :parse ...)
        PATTERN

        def on_send(node)
          return unless banned_parse?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end
      end
    end
  end
end
```

- [ ] **Step 6: Write `no_uri_default_parser.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # Design §3.5. What `URI::DEFAULT_PARSER` *is* changed at exactly Ruby 3.4.0, which
      # straddles the supported floor of 3.2, so a parse that relies on the default resolves
      # differently on two supported interpreters. Every parse and every resolution pins
      # `URI::RFC3986_PARSER`.
      class NoUriDefaultParser < Base
        MSG = "`%<offender>s` routes through URI::DEFAULT_PARSER, whose meaning changed at " \
              "Ruby 3.4.0. Pin URI::RFC3986_PARSER explicitly (design §3.5)."
        RESTRICT_ON_SEND = %i[parse join split extract regexp escape unescape].freeze

        # @!method default_parser_const?(node)
        def_node_matcher :default_parser_const?, <<~PATTERN
          (const (const {nil? cbase} :URI) :DEFAULT_PARSER)
        PATTERN

        # @!method uri_module_call?(node)
        def_node_matcher :uri_module_call?, <<~PATTERN
          (send (const {nil? cbase} :URI)
                {:parse :join :split :extract :regexp :escape :unescape} ...)
        PATTERN

        def on_const(node)
          return unless default_parser_const?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end

        def on_send(node)
          return unless uri_module_call?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end
      end
    end
  end
end
```

- [ ] **Step 7: Write `no_locale_case_fold.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # HTTP-13 folds header names with ASCII rules. Ruby's fold is opt-in-locale --
      # `"I".downcase(:turkic)` is `"ı"` -- and the locale symbol is the only argument the fold
      # family accepts, so any argument at all is the offence. `casecmp?` is banned for the same
      # reason one method along: it applies Unicode full case folding, where `casecmp` is
      # ASCII-only.
      class NoLocaleCaseFold < Base
        FOLD_MSG = "Call `%<method>s` with no argument: Ruby's fold is opt-in-locale and " \
                   "HTTP-13 needs ASCII folding."
        CASECMP_MSG = "Use `casecmp`, which is ASCII-only; `casecmp?` applies Unicode full " \
                      "case folding (HTTP-13)."
        FOLDS = %i[
          downcase downcase! upcase upcase! capitalize capitalize! swapcase swapcase!
        ].freeze
        RESTRICT_ON_SEND = (FOLDS + %i[casecmp?]).freeze

        def on_send(node)
          if node.method?(:casecmp?)
            add_offense(node, message: CASECMP_MSG)
          elsif FOLDS.include?(node.method_name) && !node.arguments.empty?
            add_offense(node, message: format(FOLD_MSG, method: node.method_name))
          end
        end
      end
    end
  end
end
```

- [ ] **Step 8: Write `no_thread_interrupt.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # Design §8.3, and CLAUDE.md's "Constraints that will bite". An asynchronous interrupt can
      # land on any bytecode instruction, including inside an `ensure` releasing a pooled
      # connection, so deadlines here are explicit values propagated to socket timeouts, never
      # ambient interrupts. Modelled on Airbnb/NoTimeout, and it shares that cop's limit: the
      # receiver is matched by name, so a Thread held in a variable named nothing like a thread
      # is missed. That is why the rule is also stated in CLAUDE.md and checked in review.
      class NoThreadInterrupt < Base
        MSG = "`%<offender>s` is banned repository-wide: an async interrupt can land on any " \
              "bytecode instruction, including inside an `ensure` releasing a pooled " \
              "connection. Propagate an explicit deadline instead (design §8.3)."
        INTERRUPTS = %i[raise kill terminate exit].freeze
        RESTRICT_ON_SEND = (INTERRUPTS + %i[timeout]).freeze
        THREADISH = /\A(::)?Thread\b|thread/i

        # @!method timeout_timeout?(node)
        def_node_matcher :timeout_timeout?, "(send (const {nil? cbase} :Timeout) :timeout ...)"

        def on_send(node)
          return unless timeout_timeout?(node) || thread_interrupt?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end

        private

        def thread_interrupt?(node)
          return false unless INTERRUPTS.include?(node.method_name)
          return false if node.receiver.nil? # a bare `raise` is ordinary Ruby

          THREADISH.match?(node.receiver.source)
        end
      end
    end
  end
end
```

- [ ] **Step 9: Wire `cops:test` into `tasks/quality.rake`**

Without this the cop suite runs nowhere: it lives outside `test/` and outside `gems/*/test/`, so
neither `test:gems` nor `test:gates` collects it, and a cop whose suite CI never runs is a cop
that silently stops working.

```ruby
namespace :cops do
  desc "NFR-13 and the ban list: the custom cops' own suite"
  task :test do
    sh("bundle", "exec", "ruby", "-w", "-I.rubocop/test", ".rubocop/test/cops_test.rb")
  end
end
```

- [ ] **Step 10: Run the suite to confirm it passes**

Run: `bundle exec rake cops:test`
Expected: PASS, 32 runs (24 rejected cases plus 8 accepted), 0 failures.

- [ ] **Step 11: Run RuboCop over the repository**

Run: `bundle exec rubocop --fail-level=convention`
Expected: no offenses. Every file written so far already carries the three-line header. If RuboCop
reports offenses in `tasks/`, `tools/`, `.rubocop/` or `test/`, fix the source — do not widen
`AllCops: Exclude`, and do not add an inline directive without a reason comment (`NFR-7`).

---

## Task 5: The six gem skeletons

**Files:**
- Create, for each of `dexpace-core`, `dexpace-transport-net_http`,
  `dexpace-transport-async_http`, `dexpace-serde-json`, `dexpace-async-thread`,
  `dexpace-conformance`: `gems/<gem>/<gem>.gemspec`, `gems/<gem>/README.md`,
  `gems/<gem>/LICENSE`, `gems/<gem>/Rakefile`, the entry file, `version.rb`, and the two `sig/`
  mirrors
- Test: `test/gates/gem_layout_test.rb`

**Interfaces:**
- Consumes: `DexpaceVersions` from Task 2.
- Produces: `Dexpace::VERSION`, `Dexpace::Transport::NetHTTP::VERSION`,
  `Dexpace::Transport::AsyncHTTP::VERSION`, `Dexpace::Serde::JSON::VERSION`,
  `Dexpace::Async::Thread::VERSION`, `Dexpace::Conformance::VERSION`, all `String`. The require
  paths are `dexpace`, `dexpace/transport/net_http`, `dexpace/transport/async_http`,
  `dexpace/serde/json`, `dexpace/async/thread`, `dexpace/conformance`.

- [ ] **Step 1: Write the failing test**

Create `test/gates/gem_layout_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/versions"

# Design §2.3's layout, asserted rather than assumed. The housekeeping probe's `readmes` check
# enforces the README half independently; this covers the rest.
class GemLayoutTest < GateCase
  ENTRIES = {
    "dexpace-core" => "lib/dexpace.rb",
    "dexpace-transport-net_http" => "lib/dexpace/transport/net_http.rb",
    "dexpace-transport-async_http" => "lib/dexpace/transport/async_http.rb",
    "dexpace-serde-json" => "lib/dexpace/serde/json.rb",
    "dexpace-async-thread" => "lib/dexpace/async/thread.rb",
    "dexpace-conformance" => "lib/dexpace/conformance.rb",
  }.freeze

  test "VERSIONS names exactly the six MVP gems, and each has a directory" do
    assert_equal(ENTRIES.keys.sort, DexpaceVersions.gem_names.sort)
    assert_equal(ENTRIES.keys.sort, Dir.children(File.join(ROOT, "gems")).sort)
  end

  test "every gem carries a gemspec, a README, a LICENSE and a Rakefile" do
    ENTRIES.each_key do |gem|
      %W[#{gem}.gemspec README.md LICENSE Rakefile].each do |file|
        assert_path_exists(File.join(ROOT, "gems", gem, file))
      end
    end
  end

  test "every gem's entry file exists and has a sig mirror, one file per file" do
    ENTRIES.each do |gem, entry|
      root = File.join(ROOT, "gems", gem)

      assert_path_exists(File.join(root, entry))
      lib = Dir.glob("lib/**/*.rb", base: root).sort
      sig = Dir.glob("sig/**/*.rbs", base: root).sort

      assert_equal(lib.map { |f| f.sub(%r{\Alib/}, "").sub(/\.rb\z/, "") },
                   sig.map { |f| f.sub(%r{\Asig/}, "").sub(/\.rbs\z/, "") })
    end
  end

  test "every gem's LICENSE is byte-identical to the repository's" do
    expected = File.read(File.join(ROOT, "LICENSE"))

    ENTRIES.each_key do |gem|
      assert_equal(expected, File.read(File.join(ROOT, "gems", gem, "LICENSE")), gem)
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/gem_layout_test.rb`
Expected: FAIL — `Dir.children` raises `Errno::ENOENT` for `gems`.

- [ ] **Step 3: Write `gems/dexpace-core/dexpace-core.gemspec`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../tools/versions"

Gem::Specification.new do |spec|
  spec.name = "dexpace-core"
  spec.version = DexpaceVersions.gem_version("dexpace-core")
  spec.authors = ["dexpace"]
  spec.email = ["oaljarrah@dexpace.org"]

  spec.summary = "The dexpace HTTP-client toolkit: domain model, pipeline and seams."
  spec.description = <<~TEXT
    An HTTP-client toolkit, not an HTTP client. dexpace-core carries the correctness-sensitive
    plumbing -- idempotency-aware retry, redirects that never leak a bearer token cross-origin,
    RFC 7235/7616 authentication, pagination, SSE and three-state PATCH -- and no concrete
    transport, codec or async runtime. Those are separate gems.
  TEXT
  spec.homepage = "https://github.com/dexpace/ruby-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= #{DexpaceVersions.ruby_floor}"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true",
  }

  # NFR-12: entry ordering is deterministic and does not depend on git.
  spec.files = Dir.glob(%w[lib/**/*.rb sig/**/*.rbs README.md LICENSE], base: __dir__).sort
  spec.require_paths = ["lib"]

  # SEAM-1 / NFR-1: this gemspec has no add_dependency line, and `rake gates:gemspec_audit`
  # asserts it. Ruby has no compile-versus-runtime dependency scope, so an empty
  # runtime_dependencies list IS the dependency audit.
end
```

- [ ] **Step 4: Write the five adapter gemspecs**

Identical to Step 3 except for `name`, `summary`, `description`, `files` and one added line:

```ruby
spec.add_dependency "dexpace-core", DexpaceVersions.core_constraint
```

**Every adapter declares `dexpace-core` and nothing else in phase 0.** The third-party
dependency each one is budgeted for under `NFR-2` lands with the code that needs it —
`json >= 2.19.9` in phase 7 with `dexpace-serde-json`'s codec, `net-http` and `async-http` in
phase 8 with the two transports. A dependency declared here would be a dependency nothing
requires: the require-allowlist audit would have nothing to permit it for, the clean-bundle run
would install a gem no line of code loads, and the `>= ` floor would be a number chosen without
a caller to justify it. Design §2.1's dependency table describes the gems as they will ship, not
as their skeletons start.

`gates:gemspec_audit` still enforces the full `NFR-2` budget — core plus at most one — and its
`two_third_party` fixture is the negative proof, because the budget is what the audit is for and
an audit that only ever sees one dependency has never been shown to reject two.

- [ ] **Step 5: Write the entry files**

`gems/dexpace-core/lib/dexpace.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "dexpace/version"

# The dexpace Ruby SDK: an HTTP-client toolkit, not an HTTP client.
#
# This file issues explicit `require_relative`s for the whole tree rather than using an
# autoloader. That is not stylistic: every Ruby autoloader worth using is a gem, and SEAM-1 bars
# core from depending on one (docs/knowledge/notes/module-organization.md). It also turns the
# require-graph audit into a text scan rather than a runtime trace. Adding a file under
# lib/dexpace/ means adding a line above.
module Dexpace
end
```

`gems/dexpace-core/lib/dexpace/version.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # This gem's own version.
  #
  # The literal lives here rather than being read from the repository root, because a built .gem
  # does not ship the repository and NFR-15 requires a runtime-emitted identifier -- the
  # User-Agent -- to report a real version rather than an "unknown" placeholder. VERSIONS at the
  # repository root is NFR-14's single source of truth, and `rake gates:versions` asserts the two
  # agree.
  VERSION = "0.0.0"
end
```

`gems/dexpace-serde-json/lib/dexpace/serde/json.rb` — note the shadowing hazard, which is real
and which phase 7 will otherwise walk into:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "json/version"

module Dexpace
  module Serde
    # The reference wire codec, over Ruby's `json` default gem.
    #
    # CAUTION: this module shadows ::JSON inside its own namespace. An unqualified `JSON.parse`
    # written anywhere under `Dexpace::Serde::JSON` resolves to this module, not to Ruby's, and
    # fails with a confusing NoMethodError. Every reference to Ruby's JSON from inside here is
    # written `::JSON`.
    module JSON
    end
  end
end
```

`gems/dexpace-async-thread/lib/dexpace/async/thread.rb` carries the same caution for `::Thread`.
The remaining three entry files follow the plain shape of `dexpace.rb`, each with its own
`require_relative "<name>/version"` and its namespace nested in full `module`/`class` form
(`Style/ClassAndModuleChildren: nested`).

- [ ] **Step 6: Write the `sig/` mirrors**

`gems/dexpace-core/sig/dexpace.rbs`:

```rbs
module Dexpace
end
```

`gems/dexpace-core/sig/dexpace/version.rbs`:

```rbs
module Dexpace
  VERSION: String
end
```

One `.rbs` per `.rb`, at the mirrored path, in every gem.

- [ ] **Step 7: Write the six READMEs, the LICENSE copies and the per-gem Rakefiles**

Each README opens with `# <exact gem name>` — the housekeeping probe's `readmes` check compares
that heading against the name the gemspec declares — and runs to at least 20 lines: what the gem
is, the one-line install, the smallest working snippet available today (`require "dexpace"; puts
Dexpace::VERSION`), what it depends on and why, and a pointer to
`docs/sdk-documentation/architecture.md`.

```bash
for gem in gems/*/; do cp LICENSE "$gem/LICENSE"; done
```

Each `gems/<gem>/Rakefile`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs = %w[lib test]
  task.test_files = FileList["test/**/*_test.rb"]
  task.warning = true
end

task default: :test
```

The coverage floor is deliberately **not** here: NFR-5 asks for an *aggregate* across the library
units, so it belongs to the root task (Task 7). This one exists for local iteration.

- [ ] **Step 8: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/gem_layout_test.rb`
Expected: PASS, 4 runs.

- [ ] **Step 9: Confirm every gem loads and every gemspec is valid**

```bash
bundle install
for g in gems/*; do
  ruby -e "name = File.basename('$g');
           spec = Gem::Specification.load(\"$g/#{name}.gemspec\");
           abort('invalid') unless spec.validate"
done
ruby -Igems/dexpace-core/lib -e 'require "dexpace"; puts Dexpace::VERSION'
```

Expected: no output from the validate loop, and `0.0.0` from the last line.

- [ ] **Step 10: Run the housekeeping probe's README check**

Run: `ruby .claude/skills/housekeeping/probe.rb --only readmes,claims`
Expected: the `readmes` check is clean; the `claims` check now reports that `CLAUDE.md` states
"Zero gems exist under `gems/`" while the repository has six. **Leave that finding standing** —
Task 20 fixes the sentence, and fixing it here would put the count edit in the wrong task.

---

## Task 6: The shared test convention and warnings-as-errors

**Files:**
- Create: `test/support/dexpace_test_case.rb`, `gems/*/test/test_helper.rb`,
  `gems/*/test/**/*_test.rb` (one smoke suite per gem)
- Modify: `tasks/quality.rake`
- Test: `test/gates/warnings_fatal_test.rb`, `test/fixtures/gates/warnings/redefinition.rb`

**Interfaces:**
- Consumes: Task 5's six gems.
- Produces: `DexpaceTestCase`, with `.test(name, &block)`, and `#sample(count:, seed:) { |rng| }`
  for bounded property-style tests. Every suite in `gems/*/test/` subclasses it. Also the
  `test:gems` and `test:gates` rake tasks and the `run_suite(files, libs, coverage:)` helper they
  share.

- [ ] **Step 1: Write the failing test**

Create `test/gates/warnings_fatal_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# NFR-6: warnings are errors, deprecations included. Two mechanisms, because each misses what
# the other catches -- the Warning.warn override cannot see a warning emitted at require time,
# before the helper installing it has loaded.
class WarningsFatalTest < GateCase
  FIXTURE = "test/fixtures/gates/warnings/redefinition.rb"

  test "a require-time warning fails the test task" do
    _out, err, status = Open3.capture3(
      { "RUBYOPT" => "-w -W:deprecated" },
      "ruby", "-Itest", FIXTURE, chdir: ROOT
    )

    refute_predicate(status, :success?)
    assert_includes(err, "method redefined")
  end

  test "the test tasks scan subprocess stderr rather than trusting the exit status" do
    body = File.read(File.join(ROOT, "tasks/quality.rake"))

    assert_includes(body, "-W:deprecated")
    assert_includes(body, "warning:")
  end

  test "RUBYOPT is appended to, so bundler's -rbundler/setup survives" do
    body = File.read(File.join(ROOT, "tasks/quality.rake"))

    assert_includes(body, %q(ENV.fetch("RUBYOPT", nil)))
  end
end
```

Create `test/fixtures/gates/warnings/redefinition.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../support/dexpace_test_case"

# A method redefined at load time. Under `ruby -w` this warns before any test runs, which is
# exactly the case the Warning.warn override cannot catch.
class Redefiner
  def call = 1
  def call = 2
end

Redefiner.new.call
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/warnings_fatal_test.rb`
Expected: FAIL — the fixture cannot load `dexpace_test_case`, and `tasks/quality.rake` has no
`test:gems` or `test:gates` task.

- [ ] **Step 3: Write `test/support/dexpace_test_case.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "minitest/autorun"

# The base every suite in this repository inherits.
#
# Minitest does not ship `test "..." do`; ActiveSupport does, and there is no Rails here, so it
# is defined below. The description stays a freeform string in --verbose output and in CI logs,
# and the generated method name still begins with `test_`, which keeps Minitest/TestMethodName
# satisfied (styleguide 11.1).
class DexpaceTestCase < Minitest::Test
  # NFR-6: a warning raised by code under test fails the test that triggered it, with the file
  # and line. This catches nothing emitted before this file loads -- see the stderr scan in
  # tasks/quality.rake, which is the other half.
  module FatalWarnings
    def warn(message, category: nil)
      raise "warning treated as an error (NFR-6): #{message.strip}" \
            "#{category.nil? ? "" : " [#{category}]"}"
    end
  end
  Warning.singleton_class.prepend(FatalWarnings)

  def self.test(name, &block)
    define_method("test_: #{name}", &block)
  end

  # A bounded property-style sample (styleguide 11.7). The iteration count is a literal, the
  # generator is bounded, and the seed is printed on failure so the counterexample sequence is
  # reproducible. No generator gem: the styleguide's own examples are hand-rolled `rand` loops.
  def sample(count: 64, seed: 20_260_905)
    rng = Random.new(seed)
    count.times do |index|
      yield rng
    rescue Minitest::Assertion => error
      raise error.class, "#{error.message}\n(sample #{index} of #{count}, seed #{seed})"
    end
  end
end
```

- [ ] **Step 4: Write the six `test_helper.rb` files and six smoke suites**

`gems/dexpace-core/test/test_helper.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

# The workspace's shared test base. This reaches out of the gem directory into the repository's
# own test support, which is not the cross-gem require_relative styleguide 12.6 forbids -- that
# rule is about reaching into another *gem's* internals.
require_relative "../../../test/support/dexpace_test_case"
```

`gems/dexpace-core/test/dexpace_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "test_helper"
require "dexpace"

# NFR-15: the version a published artifact reports at runtime is the real one.
class DexpaceTest < DexpaceTestCase
  test "defines a semver VERSION string" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Dexpace::VERSION)
  end

  test "the VERSION matches the gemspec this gem is built from" do
    spec = Gem::Specification.load(
      File.expand_path("../dexpace-core.gemspec", __dir__)
    )

    assert_equal(spec.version.to_s, Dexpace::VERSION)
  end

  test "defines nothing outside the Dexpace namespace" do
    assert_equal(%i[VERSION], Dexpace.constants(false).sort)
  end
end
```

`gems/dexpace-serde-json/test/dexpace/serde/json_test.rb` adds the shadowing regression:

```ruby
  test "the shadowing namespace does not hide Ruby's own JSON" do
    assert_equal("JSON", ::JSON.name)
    assert_equal("Dexpace::Serde::JSON", Dexpace::Serde::JSON.name)
  end
```

and `gems/dexpace-async-thread/test/dexpace/async/thread_test.rb` the same for `::Thread`.

- [ ] **Step 5: Write the two test tasks in `tasks/quality.rake`**

Two tasks, not one, because they run in different places (design's CI split): `test:gems` runs on
every Ruby in the matrix, since `NFR-10`'s trap is a method present on the developer's 4.0 and
absent on the declared 3.2 floor and only running the real suite there catches it. `test:gates`
shells out to `rake`, `git` and `bundle` and is interpreter-independent, so CI runs it once.

```ruby
require "open3"

# NFR-5/NFR-6. The suites run in one subprocess so SimpleCov produces one aggregate number, which
# is what NFR-5 asks for ("computed across the library units"). That number is the gem suites'
# number: `test:gates` loads no gem library, so it runs with coverage off rather than reporting
# a spurious 0% against `minimum_coverage 80`.
def run_suite(files, libs, coverage:)
  # RUBYOPT is APPENDED, never replaced: bundler puts `-rbundler/setup` there, and overwriting it
  # unbundles the subprocess -- which would quietly undo `bundle exec`.
  env = {
    "RUBYOPT" => "#{ENV.fetch("RUBYOPT", nil)} -w -W:deprecated".strip,
  }
  env["COVERAGE"] = "1" if coverage
  command = ["ruby", *libs.map { |dir| "-I#{dir}" }, "-rsupport/coverage",
             *files.flat_map { |file| ["-r", "./#{file}"] }, "-e", ""]

  out, err, status = Open3.capture3(env, *command)
  $stdout.puts(out)
  warn(err)

  # The Warning.warn override catches what runs; this catches what loads, before the override
  # exists. NFR-6 needs both.
  warnings = err.lines.grep(/warning:/)
  abort("NFR-6: #{warnings.length} warning(s) at load time:\n#{warnings.join}") if warnings.any?
  abort("test failures") unless status.success?
end

namespace :test do
  desc "NFR-5/NFR-6/NFR-10: every gem's suite, warnings fatal, coverage floor enforced"
  task :gems do
    run_suite(FileList["gems/*/test/**/*_test.rb"], Dir.glob("gems/*/lib").sort + %w[test],
              coverage: true)
  end

  desc "The repository's gate suites: they drive rake, git and bundle, so CI runs them once"
  task :gates do
    run_suite(FileList["test/gates/**/*_test.rb"], Dir.glob("gems/*/lib").sort + %w[test],
              coverage: false)
  end
end
```

- [ ] **Step 6: Run the tests to confirm they pass**

Run: `ruby -Itest test/gates/warnings_fatal_test.rb`
Expected: PASS, 3 runs.

Run: `bundle exec rake test:gems test:gates`
Expected: both green. `test:gems` reports the six smoke suites; `test:gates` reports every
`test/gates/*_test.rb` written so far.

---

## Task 7: Coverage — the SimpleCov aggregate floor

**Files:**
- Create: `test/support/coverage.rb`
- Test: `test/gates/coverage_test.rb`

**Interfaces:**
- Consumes: Task 6's `run_suite` helper, which already passes `-rsupport/coverage`.
- Produces: nothing other code calls. The contract is the exit status of `rake test:gems` when
  aggregate coverage drops below 80.

- [ ] **Step 1: Write the failing test**

The negative fixture cannot live under `test/fixtures/` — `add_filter "/test/"` and
`add_filter "/fixtures/"` would both strip it, leaving an empty tracked set, and SimpleCov
reports an empty set as 100%. So the test writes the uncovered file into `tmp/`, which is
gitignored and matches no filter.

Create `test/gates/coverage_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# NFR-5: an aggregate line-coverage floor of 80% across the library units, wired into the
# default build. At phase 0 the tracked set is twelve files -- six entry files and six version
# files -- every one of them executed by its gem's smoke suite, so the floor is armed and passes
# on its merits rather than being switched off. It becomes load-bearing in phase 1.
class CoverageTest < GateCase
  test "the floor is 80 and is not conditioned on anything" do
    body = File.read(File.join(ROOT, "test/support/coverage.rb"))

    assert_includes(body, "minimum_coverage 80")
    refute_match(/if .*minimum_coverage|minimum_coverage.*if /, body)
  end

  test "test support, tasks and fixtures are excluded from the aggregate" do
    body = File.read(File.join(ROOT, "test/support/coverage.rb"))

    %w[/test/ /tasks/ /.rubocop/ /fixtures/].each { |path| assert_includes(body, path) }
  end

  test "an uncovered library file fails the floor" do
    # tmp/ is gitignored and matches none of the filters above, which is the point: a fixture
    # under test/fixtures/ would be filtered out, leaving an empty set that SimpleCov reports as
    # 100% -- a green gate over nothing.
    dir = File.join(ROOT, "tmp/coverage_fixture/lib")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "uncovered.rb"), <<~RUBY)
      # frozen_string_literal: true
      # SPDX-License-Identifier: MIT

      # Deliberately untested: the input that proves the floor fails rather than warns.
      module UncoveredFixture
        def self.never_called
          :unreachable
        end
      end
    RUBY

    _out, err, status = Open3.capture3(
      { "RUBYOPT" => "#{ENV.fetch("RUBYOPT", nil)}".strip,
        "COVERAGE" => "1",
        "COVERAGE_TRACK" => "tmp/coverage_fixture/lib/**/*.rb" },
      "ruby", "-Itest", "-rsupport/coverage", "-e", "", chdir: ROOT
    )

    refute_predicate(status, :success?)
    assert_includes(err, "minimum coverage")
  ensure
    FileUtils.rm_rf(File.join(ROOT, "tmp/coverage_fixture"))
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/coverage_test.rb`
Expected: FAIL — `Errno::ENOENT` for `test/support/coverage.rb`.

- [ ] **Step 3: Write `test/support/coverage.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

return unless ENV["COVERAGE"]

require "simplecov"

SimpleCov.start do
  # NFR-5: "computed across the library units", excluding sample/example code, test-only guards
  # and test fixtures. COVERAGE_TRACK exists so the gate's own negative fixture can point the
  # tracked set somewhere else; nothing in the build sets it.
  track_files(ENV.fetch("COVERAGE_TRACK", "gems/*/lib/**/*.rb"))
  add_filter "/test/"
  add_filter "/tasks/"
  add_filter "/.rubocop/"
  add_filter "/fixtures/"

  # Never conditioned, never lowered.
  minimum_coverage 80
end
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/coverage_test.rb`
Expected: PASS, 3 runs.

- [ ] **Step 5: Confirm the real aggregate**

Run: `bundle exec rake test:gems`
Expected: SimpleCov reports `12 files, 100.0% covered`. If it reports below 100, a version or
entry file is not being loaded by its smoke suite — add the missing `require`, do not adjust the
floor.

---

## Task 8: `gates:gemspec_audit`

**Files:**
- Modify: `tasks/gates.rake`
- Test: `test/gates/gemspec_audit_test.rb`
- Create: `test/fixtures/gates/gemspec_audit/` with three sub-trees —
  `extra_core_dependency/`, `two_third_party/` and `stale_constraint/`

**Interfaces:**
- Consumes: `DexpaceVersions.core_constraint`, `.ruby_floor`, `.gem_names` from Task 5; the six
  gemspecs from Task 5.
- Produces: the `gates:gemspec_audit` task, and `GemspecAudit.violations(root) -> Array[String]`,
  which the test calls directly against a fixture root.

- [ ] **Step 1: Write the failing test**

Create `test/gates/gemspec_audit_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/gemspec_audit"

# SEAM-1 / NFR-1 / NFR-2. Design §2.4: "that test IS the SEAM-1 dependency audit; there is no
# scope declaration to lean on instead."
class GemspecAuditTest < GateCase
  FIXTURES = File.join(ROOT, "test/fixtures/gates/gemspec_audit")

  test "the real repository is clean" do
    assert_empty(GemspecAudit.violations(ROOT))
  end

  test "rejects a core gemspec with any runtime dependency" do
    found = GemspecAudit.violations(File.join(FIXTURES, "extra_core_dependency"))

    assert_includes(found.join("\n"), "dexpace-core declares 1 runtime dependency")
  end

  test "rejects an adapter with two third-party dependencies" do
    found = GemspecAudit.violations(File.join(FIXTURES, "two_third_party"))

    assert_includes(found.join("\n"), "NFR-2 allows core plus at most one")
  end

  test "rejects an adapter whose core constraint disagrees with VERSIONS" do
    found = GemspecAudit.violations(File.join(FIXTURES, "stale_constraint"))

    assert_includes(found.join("\n"), "expected ~> 0.0")
  end
end
```

Each fixture directory is a minimal `gems/<name>/<name>.gemspec` tree plus its own `VERSIONS`,
so the fixture is a complete little repository and the audit needs no special mode to read it.

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/gemspec_audit_test.rb`
Expected: FAIL — `cannot load such file -- tools/gemspec_audit`.

- [ ] **Step 3: Write `tools/gemspec_audit.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "versions"

# SEAM-1's dependency audit. Ruby has no compile-versus-runtime dependency scope, so an empty
# runtime_dependencies list for core is not evidence of the invariant -- it IS the invariant.
module GemspecAudit
  extend self

  CORE = "dexpace-core"

  def violations(root)
    versions_path = File.join(root, "VERSIONS")
    expected_constraint = constraint_for(versions_path)
    expected_floor = ">= #{DexpaceVersions.value("ruby", "floor", versions_path)}"

    Dir.glob(File.join(root, "gems/*/*.gemspec")).sort.flat_map do |path|
      check(Gem::Specification.load(path), expected_constraint, expected_floor)
    end
  end

  private

  def constraint_for(versions_path)
    major, minor, = DexpaceVersions.value("gem", CORE, versions_path).split(".")
    "~> #{major}.#{minor}"
  end

  def check(spec, expected_constraint, expected_floor)
    found = []
    found.concat(dependency_violations(spec, expected_constraint))
    unless spec.required_ruby_version.to_s == expected_floor
      found << "#{spec.name}: required_ruby_version is #{spec.required_ruby_version}, " \
               "expected #{expected_floor} (NFR-10)."
    end
    found
  end

  def dependency_violations(spec, expected_constraint)
    names = spec.runtime_dependencies.map(&:name).sort
    return core_violations(spec, names) if spec.name == CORE

    adapter_violations(spec, names, expected_constraint)
  end

  def core_violations(spec, names)
    return [] if names.empty?

    ["#{spec.name} declares #{names.length} runtime dependency/dependencies " \
     "(#{names.join(", ")}); SEAM-1 and NFR-1 require zero."]
  end

  def adapter_violations(spec, names, expected_constraint)
    found = []
    found << "#{spec.name} does not depend on #{CORE}." unless names.include?(CORE)
    third_party = names - [CORE]
    if third_party.length > 1
      found << "#{spec.name} declares #{third_party.join(", ")}; NFR-2 allows core plus at most " \
               "one third-party library."
    end
    core = spec.runtime_dependencies.find { |dep| dep.name == CORE }
    if core && core.requirement.to_s != expected_constraint
      found << "#{spec.name} constrains #{CORE} as #{core.requirement}, expected " \
               "#{expected_constraint} from VERSIONS (design §2.3)."
    end
    found
  end
end
```

- [ ] **Step 4: Wire the rake task in `tasks/gates.rake`**

```ruby
  desc "SEAM-1/NFR-1/NFR-2: runtime dependencies, per gem"
  task :gemspec_audit do
    require_relative "../tools/gemspec_audit"
    found = GemspecAudit.violations(__dir__.sub(%r{/tasks\z}, ""))
    abort(found.join("\n")) unless found.empty?

    puts "gates:gemspec_audit: 6 gemspecs, dependency budget respected."
  end
```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/gemspec_audit_test.rb`
Expected: PASS, 4 runs.

Run: `bundle exec rake gates:gemspec_audit`
Expected: `gates:gemspec_audit: 6 gemspecs, dependency budget respected.`

---

## Task 9: `gates:require_allowlist`

**Files:**
- Modify: `tasks/gates.rake`
- Create: `tools/require_allowlist.rb`
- Test: `test/gates/require_allowlist_test.rb`, `test/fixtures/gates/require_allowlist/*.rb`

**Interfaces:**
- Consumes: the six gems from Task 5, each gemspec's declared dependencies from Task 8's loader.
- Produces: `RequireAllowlist::ALLOWED`, `::DENIED` (a name → reason `Hash`), `.bundled?`,
  `.bundled_since`, `.scan_file(path, permitted:, lib_root:)` and
  `.violations(root) -> Array[String]`.

- [ ] **Step 1: Write the failing test**

Create `test/gates/require_allowlist_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/require_allowlist"

# Design §9.2's require-allowlist audit, the one gate with no counterpart in the reference build.
# Extended here to every gem, not core alone -- an adapter's undeclared require is invisible
# until a Ruby where the name is bundled (design's §9 Addendum A2).
class RequireAllowlistTest < GateCase
  FIXTURES = "test/fixtures/gates/require_allowlist"

  # Three of the cases below assert the *reason* a name is refused, and that reason is read from
  # Gem::BUNDLED_GEMS::SINCE, which does not exist on Ruby 3.2. On that row the name is still
  # refused -- it is simply not allowlisted -- so the gate holds; only the message differs.
  def skip_without_bundled_table
    skip("Gem::BUNDLED_GEMS::SINCE is undefined on Ruby 3.2") unless RequireAllowlist.bundled?
  end

  test "the real repository is clean" do
    assert_empty(RequireAllowlist.violations(ROOT))
  end

  test "rejects a name that became bundled at 3.4" do
    skip_without_bundled_table

    assert_includes(scan("base64.rb"), "bundled since 3.4.0")
  end

  test "rejects a name that becomes bundled at 4.0" do
    skip_without_bundled_table

    assert_includes(scan("logger.rb"), "bundled since 4.0.0")
  end

  test "rejects tsort, which is default on every supported Ruby and bundled at 4.1" do
    skip_without_bundled_table

    assert_includes(scan("tsort.rb"), "bundled since 4.1.0")
  end

  test "refuses base64, logger and tsort on every Ruby, whatever the message says" do
    %w[base64.rb logger.rb tsort.rb].each { |fixture| refute_empty(scan(fixture), fixture) }
  end

  test "rejects json by name, with the requirement that forbids it" do
    assert_includes(scan("json.rb"), "SEAM-2")
  end

  test "rejects timeout by name, with the section that forbids it" do
    assert_includes(scan("timeout.rb"), "§8.3")
  end

  test "rejects a require_relative that escapes the gem's lib/" do
    assert_includes(scan("escaping_relative.rb"), "escapes")
  end

  test "accepts a require_relative that stays inside lib/" do
    assert_empty(scan("internal_relative.rb"))
  end

  test "every allowlisted name requires cleanly on this interpreter" do
    RequireAllowlist::ALLOWED.each { |name| require name }
  end

  test "no allowlisted name is a bundled gem on this interpreter" do
    skip_without_bundled_table

    overlap = RequireAllowlist::ALLOWED & RequireAllowlist.bundled_since.keys

    assert_empty(overlap, "allowlisted and bundled: #{overlap.join(", ")}")
  end

  private

  def scan(fixture)
    path = File.join(ROOT, FIXTURES, fixture)
    RequireAllowlist.scan_file(path, permitted: [], lib_root: File.dirname(path)).join("\n")
  end
end
```

The fixtures are one-line files under `test/fixtures/gates/require_allowlist/`, each carrying the
three-line header and one statement: `require "base64"`, `require "logger"`, `require "tsort"`,
`require "json"`, `require "timeout"`, `require_relative "../../../../Rakefile"` (the escaping
case) and `require_relative "internal_relative"` alongside an `internal_relative.rb` beside it.

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/require_allowlist_test.rb`
Expected: FAIL — `cannot load such file -- tools/require_allowlist`.

- [ ] **Step 3: Write `tools/require_allowlist.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "bundler"

# Design §9.2, extended to every gem. A text scan rather than a runtime trace, which is what
# lib/dexpace.rb's explicit requires buy.
#
# The Ruby 4.0.6 bundled-gem facts this list was built against are recorded once, in
# docs/knowledge/notes/package-and-dependency-layout.md, key
# `package-and-dependency-layout/70fbcaee`. They are not restated here: a second copy of a table
# that moves between releases is a second copy that goes stale silently. The category assertion
# below re-derives them from the running interpreter on every CI row instead.
module RequireAllowlist
  extend self

  # Deliberately narrower than "everything stable". The category is not the constraint; what core
  # actually needs is. Growing this list is a reviewed one-line diff naming the requirement that
  # motivated it. Every name was verified to require cleanly on 3.2.11, 3.4.10 and 4.0.6.
  ALLOWED = %w[
    date
    digest
    forwardable
    monitor
    openssl
    securerandom
    set
    singleton
    stringio
    strscan
    time
    uri
  ].freeze

  # Names that pass a category test and must still fail. Without this list the gate's message
  # would be "not in the allowlist", which says nothing about why.
  DENIED = {
    "json" => "SEAM-2: the wire codec is a seam. It lives in dexpace-serde-json, and the " \
              ">= 2.19.9 floor lives in that gemspec and nowhere else (design §3.4).",
    "net/http" => "SEAM-1/SEAM-2: core embeds no concrete transport.",
    "net/protocol" => "SEAM-1/SEAM-2: core embeds no concrete transport.",
    "open-uri" => "SEAM-1/SEAM-2: core embeds no concrete transport.",
    "socket" => "SEAM-1/SEAM-2: core embeds no concrete transport.",
    "resolv" => "SEAM-1/SEAM-2: core embeds no concrete transport.",
    "timeout" => "Design §8.3: Timeout.timeout can land an interrupt inside an `ensure` " \
                 "releasing a pooled connection. Deadlines are explicit values.",
  }.freeze

  REQUIRE = /^[ \t]*require[ \t]+["']([^"']+)["']/
  REQUIRE_RELATIVE = /^[ \t]*require_relative[ \t]+["']([^"']+)["']/

  def bundled? = defined?(Gem::BUNDLED_GEMS::SINCE) ? true : false
  def bundled_since = bundled? ? Gem::BUNDLED_GEMS::SINCE : {}

  def violations(root)
    Dir.glob(File.join(root, "gems/*")).sort.flat_map do |gem_dir|
      permitted = third_party_for(gem_dir)
      lib_root = File.join(gem_dir, "lib")
      Dir.glob(File.join(lib_root, "**/*.rb")).sort.flat_map do |file|
        scan_file(file, permitted: permitted, lib_root: lib_root)
      end
    end
  end

  # Both forms are scanned, as design §9.2 and CLAUDE.md both say. `require` can reach outside
  # the gem by name; `require_relative` can reach outside it by path, which is the cross-gem
  # reach styleguide 12.6 forbids and which would make the gem unbuildable once packaged.
  def scan_file(path, permitted:, lib_root:)
    File.readlines(path, chomp: true).filter_map do |line|
      if (name = REQUIRE.match(line)&.[](1))
        reason = reason_for(name, permitted)
        next if reason.nil?

        "#{path}: require \"#{name}\" -- #{reason}"
      elsif (target = REQUIRE_RELATIVE.match(line)&.[](1))
        next if inside?(path, target, lib_root)

        "#{path}: require_relative \"#{target}\" escapes #{lib_root}. A gem may not reach " \
          "outside its own lib/ (styleguide 12.6); the packaged gem would not contain it."
      end
    end
  end

  private

  def inside?(path, target, lib_root)
    resolved = File.expand_path(target, File.dirname(path))
    resolved.start_with?("#{File.expand_path(lib_root)}/")
  end

  def reason_for(name, permitted)
    return nil if permitted.include?(name) || name.start_with?("dexpace/")
    return DENIED[name] if DENIED.key?(name)

    since = bundled_since[name.split("/").first]
    return "bundled since #{since}; a gem must declare it explicitly under Bundler." if since
    return nil if ALLOWED.include?(name)

    "not in the require allowlist. Add it to RequireAllowlist::ALLOWED with the requirement " \
      "that motivated it, or declare it as a dependency if this is an adapter (NFR-2)."
  end

  # An adapter may require the one third-party gem its own gemspec declares. In phase 0 no
  # gemspec declares one, so this is empty for all six -- which is SEAM-1 restated at the require
  # level, and the reason the method exists now rather than in phase 7.
  def third_party_for(gem_dir)
    name = File.basename(gem_dir)
    spec = Gem::Specification.load(File.join(gem_dir, "#{name}.gemspec"))
    return [] if spec.nil?

    spec.runtime_dependencies.map(&:name).reject { |dep| dep == "dexpace-core" }
        .flat_map { |dep| [dep, dep.tr("-", "/")] }
  end
end
```

- [ ] **Step 4: Wire the rake task**

```ruby
  desc "SEAM-1/SEAM-2/NFR-1: every require in every gem, against the allowlist and the denylist"
  task :require_allowlist do
    require_relative "../tools/require_allowlist"
    root = __dir__.sub(%r{/tasks\z}, "")
    found = RequireAllowlist.violations(root)
    abort(found.join("\n")) unless found.empty?

    table = if RequireAllowlist.bundled?
              "#{RequireAllowlist.bundled_since.size} bundled gems known"
            else
              "no BUNDLED_GEMS table on this Ruby"
            end
    puts "gates:require_allowlist: clean on Ruby #{RUBY_VERSION} (#{table})."
  end
```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/require_allowlist_test.rb`
Expected: PASS, 11 runs.

- [ ] **Step 6: Run it on the floor interpreter, where the bundled table does not exist**

```bash
~/.local/share/mise/installs/ruby/3.2.11/bin/ruby -S bundle exec ruby -Itest \
  test/gates/require_allowlist_test.rb
```

Expected: PASS with four skips — the three "bundled since" message assertions and the
allowlist/bundled overlap check. The fifth test, "refuses base64, logger and tsort on every
Ruby", does **not** skip: it asserts the gate still refuses those names on 3.2, where the reason
is "not in the allowlist" rather than "bundled since". That split is why design §9.2 makes the
**highest** Ruby the authority for the *reason* while the *refusal* holds everywhere.

---

## Task 10: `gates:clean_bundle`

**Files:**
- Modify: `tasks/gates.rake`
- Test: `test/gates/clean_bundle_test.rb`

**Interfaces:**
- Consumes: the six gems from Task 5.
- Produces: the `gates:clean_bundle` task. `CLEAN_BUNDLE_ENTRIES`, a `Hash` from gem name to
  `[require path, constant]`, is reused by Tasks 11 and 14.

- [ ] **Step 1: Write the failing test**

The negative fixture has to be a **complete** miniature workspace, not just a copy of
`gems/dexpace-core`: the gemspec does `require_relative "../../tools/versions"` and reads the
repository-root `VERSIONS`, so a copy without those two would fail at `Gem::Specification.load`
before the undeclared `require "logger"` was ever reached — and the assertion on the word
`logger` would pass for the wrong reason, or not at all.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# Design §9.2's third check. The gemspec audit sees declarations and the allowlist audit sees
# text; only Bundler refusing to activate an undeclared gem catches a transitive require reached
# at load time.
class CleanBundleTest < GateCase
  test "every gem loads inside a bundle that holds only itself" do
    _out, err, status = rake("gates:clean_bundle")

    assert_predicate(status, :success?, err)
  end

  test "an undeclared require fails under Bundler" do
    Dir.mktmpdir("dexpace-clean-bundle-fixture") do |dir|
      # A complete miniature workspace: the gem, the VERSIONS file its gemspec reads, and the
      # reader that parses it. Without these two the gemspec raises before `logger` is reached.
      FileUtils.mkdir_p(File.join(dir, "gems"))
      FileUtils.cp_r(File.join(ROOT, "gems/dexpace-core"), File.join(dir, "gems"))
      FileUtils.cp_r(File.join(ROOT, "tools"), dir)
      FileUtils.cp(File.join(ROOT, "VERSIONS"), dir)

      target = File.join(dir, "gems/dexpace-core/lib/dexpace.rb")
      File.write(target, "#{File.read(target)}\nrequire \"logger\"\n")

      _out, err, status = Open3.capture3(
        { "DEXPACE_CLEAN_BUNDLE_GEM" => File.join(dir, "gems/dexpace-core") },
        "bundle", "exec", "rake", "-s", "gates:clean_bundle", chdir: ROOT
      )

      refute_predicate(status, :success?)
      assert_includes(err, "logger")
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/clean_bundle_test.rb`
Expected: FAIL — `Don't know how to build task 'gates:clean_bundle'`.

- [ ] **Step 3: Write the task**

Two plain `Open3.capture3` calls, no shell. `bash -lc` would source the developer's login profile
and re-resolve `ruby` from `PATH`, which on a matrix row is exactly the wrong interpreter — the
whole point of this gate is that it runs on the Ruby under test.

```ruby
  CLEAN_BUNDLE_ENTRIES = {
    "dexpace-core" => ["dexpace", "Dexpace"],
    "dexpace-transport-net_http" => ["dexpace/transport/net_http",
                                     "Dexpace::Transport::NetHTTP"],
    "dexpace-transport-async_http" => ["dexpace/transport/async_http",
                                       "Dexpace::Transport::AsyncHTTP"],
    "dexpace-serde-json" => ["dexpace/serde/json", "Dexpace::Serde::JSON"],
    "dexpace-async-thread" => ["dexpace/async/thread", "Dexpace::Async::Thread"],
    "dexpace-conformance" => ["dexpace/conformance", "Dexpace::Conformance"],
  }.freeze

  desc "SEAM-1/NFR-1/NFR-10: each gem loads inside a bundle holding only itself"
  task :clean_bundle do
    require "bundler"
    require "open3"
    require "tmpdir"

    root = __dir__.sub(%r{/tasks\z}, "")
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
      clean_bundle_check(name, path, entry, constant)
    end

    puts "gates:clean_bundle: #{targets.size} gem(s) load in isolation on Ruby #{RUBY_VERSION}."
  end
```

and the helper it calls, in the same file:

```ruby
  # Two subprocesses, no shell: `bundle install`, then `bundle exec ruby -e <smoke>`. Bundler
  # refuses to activate a gem outside the bundle, and that refusal is the whole gate.
  def clean_bundle_check(name, path, entry, constant)
    Dir.mktmpdir("dexpace-clean-bundle") do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        # frozen_string_literal: true
        source "https://rubygems.org"
        gem #{name.inspect}, path: #{path.inspect}
      GEMFILE
      smoke = "require #{entry.inspect}; " \
              "abort(\"no VERSION\") unless " \
              "#{constant}::VERSION.match?(/\\A\\d+\\.\\d+\\.\\d+\\z/)"
      env = { "BUNDLE_GEMFILE" => File.join(dir, "Gemfile") }

      Bundler.with_unbundled_env do
        out, err, status = Open3.capture3(env, "bundle", "install", "--quiet", chdir: dir)
        unless status.success?
          abort("gates:clean_bundle: #{name} would not install:\n#{out}\n#{err}")
        end

        out, err, status = Open3.capture3(env, "bundle", "exec", "ruby", "-e", smoke, chdir: dir)
        unless status.success?
          abort("gates:clean_bundle: #{name} failed in isolation:\n#{out}\n#{err}")
        end
      end
    end
  end
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/clean_bundle_test.rb`
Expected: PASS, 2 runs. The second test is the one that matters: it proves Bundler's refusal is
real rather than argued about, and its `stderr` names `logger` because the miniature workspace
carries `tools/` and `VERSIONS`, so nothing fails earlier.

- [ ] **Step 5: Run it on Ruby 4.0.6, where `logger` is bundled**

```bash
~/.local/share/mise/installs/ruby/4.0.6/bin/ruby -S bundle exec rake gates:clean_bundle
~/.local/share/mise/installs/ruby/4.0.6/bin/ruby -S bundle exec ruby -Itest \
  test/gates/clean_bundle_test.rb
```

Expected: `gates:clean_bundle: 6 gem(s) load in isolation on Ruby 4.0.6.`, then PASS with the
undeclared-`logger` case failing the gate under 4.0.6. This is the single check that makes the
4.0 matrix column load-bearing rather than aspirational — on 3.2 the same fixture would load
`logger` happily, because there it is still a default gem.

---

## Task 11: `gates:single_instance`

**Files:**
- Modify: `tasks/gates.rake`
- Test: `test/gates/single_instance_test.rb`

**Interfaces:**
- Consumes: `CLEAN_BUNDLE_ENTRIES` from Task 10.
- Produces: the `gates:single_instance` task.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# Design §2.4's single-instance guarantee, and §9's table row for it: "the auditable form of a
# claim §2.4 otherwise argues structurally." Type-identity checks -- XCUT-4's exception
# hierarchy, RECOV-1's Outcome variants, SERDE-14's Tristate -- break silently under duplication.
class SingleInstanceTest < GateCase
  test "one resolved path per core file, and VERSION agrees with the gemspec" do
    _out, err, status = rake("gates:single_instance")

    assert_predicate(status, :success?, err)
  end

  test "a duplicated feature path fails the gate" do
    _out, err, status = rake("gates:single_instance", "DEXPACE_FORCE_DUPLICATE" => "1")

    refute_predicate(status, :success?)
    assert_includes(err, "loaded twice")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/single_instance_test.rb`
Expected: FAIL — unknown task.

- [ ] **Step 3: Write the task**

```ruby
  desc "Design §2.4: one resolved path per core file; Dexpace::VERSION matches the gemspec"
  task :single_instance do
    require "open3"
    root = __dir__.sub(%r{/tasks\z}, "")
    gemspec_path = File.join(root, "gems/dexpace-core/dexpace-core.gemspec")
    script = <<~RUBY
      require "dexpace"

      # The duplicate a nested-resolution package manager would create; Ruby cannot produce it,
      # so the gate simulates one to prove it would be caught.
      if ENV["DEXPACE_FORCE_DUPLICATE"]
        $LOADED_FEATURES << $LOADED_FEATURES.grep(%r{/dexpace\\.rb\\z}).first
      end

      paths = $LOADED_FEATURES.grep(%r{/dexpace(/.*)?\\.rb\\z})
      duplicated = paths.tally.select { |_, count| count > 1 }.keys
      abort("loaded twice: \#{duplicated.join(", ")}") unless duplicated.empty?

      spec = Gem::Specification.load(#{gemspec_path.inspect})
      unless Dexpace::VERSION == spec.version.to_s
        abort("VERSION \#{Dexpace::VERSION} != gemspec \#{spec.version}")
      end
    RUBY
    _out, err, status = Open3.capture3(
      { "DEXPACE_FORCE_DUPLICATE" => ENV.fetch("DEXPACE_FORCE_DUPLICATE", nil) },
      "ruby", "-I#{File.join(root, "gems/dexpace-core/lib")}", "-e", script
    )
    abort(err) unless status.success?

    puts "gates:single_instance: one resolved path per core file; " \
         "VERSION agrees with the gemspec."
  end
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/single_instance_test.rb`
Expected: PASS, 2 runs.

---

## Task 12: Typing — `Steepfile`, `rbs_collection.yaml`, `rbs:validate` and `steep`

**Files:**
- Create: `Steepfile`, `rbs_collection.yaml`
- Modify: `tasks/quality.rake`
- Test: `test/gates/typing_test.rb`

**Interfaces:**
- Consumes: the twelve `.rbs` files from Task 5.
- Produces: the `rbs:validate` and `steep` tasks; six Steep targets named `core`, `net_http`,
  `async_http`, `serde_json`, `async_thread` and `conformance`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# NFR-3, and docs/knowledge/notes/type-system.md: RBS under sig/, gated by rbs validate and
# steep check, no Sorbet anywhere. Adoption is target-by-target so a relaxation is a named
# target rather than a blanket ignore.
class TypingTest < GateCase
  STEEPFILE = File.read(File.join(ROOT, "Steepfile"))

  test "names one Steep target per gem, from day one" do
    %w[core net_http async_http serde_json async_thread conformance].each do |name|
      assert_includes(STEEPFILE, "target :#{name}")
    end
  end

  test "core is configured strict" do
    assert_match(/target :core do.*D::Ruby\.strict/m, STEEPFILE)
  end

  test "no file in the repository carries a Sorbet sigil" do
    offenders = Dir.glob(File.join(ROOT, "{gems,test,tasks,tools,.rubocop}/**/*.rb"))
                   .select { |file| File.read(file).include?("# typed:") }

    assert_empty(offenders)
  end

  test "rbs validate and steep check both pass" do
    %w[rbs:validate steep].each do |task|
      _out, err, status = rake(task)

      assert_predicate(status, :success?, "#{task}: #{err}")
    end
  end

  test "rbs validate rejects a malformed signature" do
    Dir.mktmpdir("dexpace-rbs-fixture") do |dir|
      File.write(File.join(dir, "broken.rbs"), "module Dexpace\n  VERSION: Nonexistent::Type\n")
      _out, err, status = Open3.capture3("bundle", "exec", "rbs", "-I", dir, "validate",
                                         chdir: ROOT)

      refute_predicate(status, :success?)
      assert_includes(err, "Nonexistent")
    end
  end

  test "the rbs collection lock is not committed" do
    refute_path_exists(File.join(ROOT, "rbs_collection.lock.yaml"))
    assert_includes(File.read(File.join(ROOT, ".gitignore")), "rbs_collection.lock.yaml")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/typing_test.rb`
Expected: FAIL — `Errno::ENOENT` for `Steepfile`.

- [ ] **Step 3: Write the `Steepfile`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

D = Steep::Diagnostic

# NFR-3, and docs/knowledge/notes/type-system.md. Six targets from day one rather than one
# repository-wide target, because "target-by-target" is only a real discipline if the targets
# exist before anyone needs to relax one. Every future relaxation is a change to a named target
# with a comment, never a blanket ignore.
target :core do
  check "gems/dexpace-core/lib"
  signature "gems/dexpace-core/sig"
  library "uri", "stringio", "strscan", "time", "date", "digest", "securerandom", "monitor",
          "forwardable", "set", "singleton", "openssl"

  # Core's public surface is strict. This is the one target that never relaxes.
  configure_code_diagnostics(D::Ruby.strict)
end

target :net_http do
  check "gems/dexpace-transport-net_http/lib"
  signature "gems/dexpace-transport-net_http/sig", "gems/dexpace-core/sig"
  # `net-http` here is rbs's own stdlib signature set, not a gem dependency: the adapter
  # declares none until phase 8.
  library "net-http", "uri"
  configure_code_diagnostics(D::Ruby.default)
end

target :async_http do
  check "gems/dexpace-transport-async_http/lib"
  signature "gems/dexpace-transport-async_http/sig", "gems/dexpace-core/sig"
  configure_code_diagnostics(D::Ruby.default)
end

target :serde_json do
  check "gems/dexpace-serde-json/lib"
  signature "gems/dexpace-serde-json/sig", "gems/dexpace-core/sig"
  library "json"
  configure_code_diagnostics(D::Ruby.default)
end

target :async_thread do
  check "gems/dexpace-async-thread/lib"
  signature "gems/dexpace-async-thread/sig", "gems/dexpace-core/sig"
  configure_code_diagnostics(D::Ruby.default)
end

target :conformance do
  check "gems/dexpace-conformance/lib"
  signature "gems/dexpace-conformance/sig", "gems/dexpace-core/sig"
  configure_code_diagnostics(D::Ruby.default)
end
```

- [ ] **Step 4: Write `rbs_collection.yaml`**

```yaml
# Third-party RBS, resolved from the gems the bundle actually holds. The `gems:` list is empty
# in phase 0 because no gemspec declares a third-party dependency yet: json arrives with
# dexpace-serde-json's codec in phase 7, net-http and async-http with the transports in phase 8,
# and each adds its own row here then. Core never gets one -- its allowlist is stdlib only, and
# stdlib signatures ship with rbs itself.
sources:
  - type: git
    name: ruby/gem_rbs_collection
    remote: https://github.com/ruby/gem_rbs_collection.git
    revision: main
    repo_dir: gems

path: .gem_rbs_collection

gems: []
```

Add `/.gem_rbs_collection/` and `/rbs_collection.lock.yaml` to `.gitignore`. The lock is **not**
committed, for the same reason `Gemfile.lock` is not: it is a resolution against one bundle, and
every matrix row resolves its own. `rbs collection install` runs fresh on each row, before
`steep check`.

- [ ] **Step 5: Add the two tasks to `tasks/quality.rake`**

```ruby
namespace :rbs do
  desc "NFR-3: rbs validate, per gem"
  task :validate do
    Dir.glob("gems/*").sort.each do |dir|
      sh("bundle", "exec", "rbs", "-I", "#{dir}/sig", "validate")
    end
  end
end

desc "NFR-3: steep check, target by target"
task :steep do
  # Fresh, never --frozen: the lock is not committed, so each row resolves for itself.
  sh("bundle", "exec", "rbs", "collection", "install")
  sh("bundle", "exec", "steep", "check")
end
```

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec rbs collection install && ruby -Itest test/gates/typing_test.rb`
Expected: PASS, 5 runs. Do **not** commit `rbs_collection.lock.yaml` — it is gitignored, and
every CI row runs `rbs collection install` for itself, which is the same argument the lockfile
note makes about `Gemfile.lock`.

---

## Task 13: `gates:rbs_surface` — NFR-11's foreign-constant scan

**Files:**
- Modify: `tasks/gates.rake`
- Create: `tools/rbs_surface.rb`
- Test: `test/gates/rbs_surface_test.rb`, `test/fixtures/gates/rbs_surface/foreign.rbs`

**Interfaces:**
- Consumes: Task 12's `Steepfile` and the `rbs` gem.
- Produces: `RbsSurface::STDLIB_ALLOWED`, `RbsSurface.violations(paths) -> Array[String]`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/rbs_surface"

# NFR-11: the core is concurrency-model agnostic and leaks no async-framework type into its
# public surface. This is the gate that would have caught Async::Task appearing there, and it is
# why the async pivot had to be core-owned (design §3.3).
class RbsSurfaceTest < GateCase
  test "the real signatures reference nothing foreign" do
    assert_empty(RbsSurface.violations(Dir.glob(File.join(ROOT, "gems/*/sig/**/*.rbs"))))
  end

  test "rejects a signature referencing an async-framework type" do
    found = RbsSurface.violations([fixture("foreign.rbs")])

    assert_includes(found.join("\n"), "Async::Task")
  end

  test "rejects a foreign superclass, mixin, type alias and generic bound" do
    %w[superclass.rbs mixin.rbs type_alias.rbs generic_bound.rbs].each do |name|
      found = RbsSurface.violations([fixture(name)])

      assert_includes(found.join("\n"), "Async::Task", name)
    end
  end

  private

  def fixture(name)
    File.join(ROOT, "test/fixtures/gates/rbs_surface", name)
  end
end
```

Five fixtures under `test/fixtures/gates/rbs_surface/`, one per position a type name can occupy.
`foreign.rbs`:

```rbs
module Dexpace
  module Fixture
    def spawn: () -> Async::Task
  end
end
```

`superclass.rbs` is `class Dexpace::Fixture < Async::Task\nend`; `mixin.rbs` is a
`module Dexpace::Fixture` whose body is `include Async::Task`; `type_alias.rbs` is
`module Dexpace\n  type handle = Async::Task\nend`; and `generic_bound.rbs` is
`module Dexpace\n  class Box[T < Async::Task]\n  end\nend`. Each is a leak `NFR-11` forbids and
none of them is a method return type.

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/rbs_surface_test.rb`
Expected: FAIL — `cannot load such file -- tools/rbs_surface`.

- [ ] **Step 3: Write `tools/rbs_surface.rb`**

A signature leaks a foreign constant through more than a method return type. It leaks through a
superclass, through an `include`/`extend`/`prepend`, through a type alias, and through a generic
bound — and `Async::Task` appearing in any of those is exactly as much of an `NFR-11` violation
as it appearing in a return type. All five are collected.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "rbs"

# NFR-11, mechanised: no constant outside Dexpace:: and a fixed stdlib allowlist appears in any
# public signature under sig/.
#
# The scan works on PARSED declarations rather than raw text -- a comment mentioning Async::Task
# is not a leak -- and then matches constant paths in each collected node's canonical `to_s`.
# That is sound because the parser has already discarded comments and normalised the syntax, and
# it avoids hand-walking every RBS::Types constructor.
module RbsSurface
  extend self

  STDLIB_ALLOWED = %w[
    Array Bool Class Comparable Enumerable Enumerator Exception Float Hash IO Integer Method
    Module Mutex Numeric Object Proc Range Rational Regexp Set StandardError String StringIO
    Symbol Thread Time URI
  ].freeze

  CONSTANT_PATH = /\b([A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*)\b/

  def violations(paths)
    paths.sort.flat_map { |path| scan_file(path) }
  end

  def scan_file(path)
    buffer = RBS::Buffer.new(name: path, content: File.read(path))
    _, _, declarations = RBS::Parser.parse_signature(buffer)

    collect(declarations).flat_map { |source| foreign_names(source) }.uniq.map do |name|
      "#{path}: public signature references #{name}, which is outside Dexpace:: and the " \
        "stdlib allowlist (NFR-11)."
    end
  end

  private

  # Every position a type name can occupy in a signature, not just a method's return type.
  def collect(node, found = [])
    case node
    when Array
      node.each { |child| collect(child, found) }
    when RBS::AST::Declarations::Base, RBS::AST::Members::Base
      collect_declaration(node, found)
      collect(node.members, found) if node.respond_to?(:members)
    end
    found
  end

  def collect_declaration(node, found)
    # A method's or attribute's type, and every overload's full method type.
    found << node.type.to_s if node.respond_to?(:type) && node.type
    found.concat(node.overloads.map { |o| o.method_type.to_s }) if node.respond_to?(:overloads)
    # `class Foo < Bar` -- a superclass is a reference like any other.
    found << node.super_class.to_s if node.respond_to?(:super_class) && node.super_class
    # `include`, `extend`, `prepend`, and a module's self-type constraints.
    found << node.name.to_s if node.is_a?(RBS::AST::Members::Include) ||
                               node.is_a?(RBS::AST::Members::Extend) ||
                               node.is_a?(RBS::AST::Members::Prepend)
    found.concat(node.self_types.map(&:to_s)) if node.respond_to?(:self_types) && node.self_types
    # Generic bounds: `class Box[T < Async::Task]`.
    if node.respond_to?(:type_params) && node.type_params
      found.concat(node.type_params.filter_map { |param| param.upper_bound&.to_s })
    end
  end

  def foreign_names(source)
    source.to_s.scan(CONSTANT_PATH).flatten.uniq.reject do |name|
      name.start_with?("Dexpace") || STDLIB_ALLOWED.include?(name.split("::").first)
    end
  end
end
```

A type alias declaration (`type handle = Async::Task`) is an `RBS::AST::Declarations::TypeAlias`
and responds to `#type`, so the first line of `collect_declaration` already reaches it; the test
below asserts that rather than leaving it to be inferred.

- [ ] **Step 4: Wire the rake task**

```ruby
  desc "NFR-11: no foreign constant in any public signature under sig/"
  task :rbs_surface do
    require_relative "../tools/rbs_surface"
    root = __dir__.sub(%r{/tasks\z}, "")
    found = RbsSurface.violations(Dir.glob(File.join(root, "gems/*/sig/**/*.rbs")))
    abort(found.join("\n")) unless found.empty?

    puts "gates:rbs_surface: no foreign constant in any public signature."
  end
```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/rbs_surface_test.rb`
Expected: PASS, 3 runs.

---

## Task 14: `gates:surface_snapshot` — the runtime half of the API lock

**Files:**
- Modify: `tasks/gates.rake`
- Create: `tools/surface.rb`, `test/fixtures/surface/*.txt` (six manifests)
- Test: `test/gates/surface_snapshot_test.rb`

**Interfaces:**
- Consumes: `CLEAN_BUNDLE_ENTRIES` from Task 10.
- Produces: `Surface.manifest(constant) -> String`, the `gates:surface_snapshot` task, and
  `rake surface:regenerate`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# NFR-4, the half RBS cannot see. Design §9.1: "RBS describes what someone wrote, not what Ruby
# defines" -- Data.define's generated readers, define_method, method_missing and a require-time
# register call are all invisible to a signature file.
class SurfaceSnapshotTest < GateCase
  test "the committed manifests match the runtime tree" do
    _out, err, status = rake("gates:surface_snapshot")

    assert_predicate(status, :success?, err)
  end

  test "an unrecorded constant fails the gate" do
    _out, err, status = rake("gates:surface_snapshot", "DEXPACE_SURFACE_EXTRA" => "Injected")

    refute_predicate(status, :success?)
    assert_includes(err, "Injected")
  end

  test "the message says both artifacts must be regenerated" do
    _out, err, _status = rake("gates:surface_snapshot", "DEXPACE_SURFACE_EXTRA" => "Injected")

    assert_includes(err, "sig/")
    assert_includes(err, "surface:regenerate")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/surface_snapshot_test.rb`
Expected: FAIL — unknown task.

- [ ] **Step 3: Write `tools/surface.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# NFR-4's runtime surface snapshot. Walks a namespace's constant tree and each class's
# public_instance_methods(false), sorts, and renders one line per entry.
module Surface
  extend self

  def manifest(root_constant)
    lines = []
    walk(Object.const_get(root_constant), lines)
    lines.sort.join("\n") << "\n"
  end

  private

  def walk(mod, lines)
    lines << mod.name
    methods = mod.public_instance_methods(false).sort
    lines << "#{mod.name}# #{methods.join(" ")}" unless methods.empty?

    mod.constants(false).sort.each do |name|
      value = mod.const_get(name)
      if value.is_a?(Module) && value.name.to_s.start_with?("Dexpace")
        walk(value, lines)
      else
        lines << "#{mod.name}::#{name} : #{value.class}"
      end
    end
  end
end
```

- [ ] **Step 4: Write the task pair**

```ruby
# Both helpers and the task sit inside tasks/gates.rake's `namespace :gates do` block; the
# opener is shown so this snippet parses on its own.
namespace :gates do
  def surface_for(root, name, constant)
    require "open3"
    extra = ENV.fetch("DEXPACE_SURFACE_EXTRA", nil)
    script = "require #{CLEAN_BUNDLE_ENTRIES.fetch(name).first.inspect}; " \
             "#{constant}.const_set(#{extra.to_s.inspect}, 1) if #{!extra.nil?}; " \
             "require #{File.join(root, "tools/surface.rb").inspect}; " \
             "print Surface.manifest(#{constant.inspect})"
    out, err, status = Open3.capture3("ruby", "-I#{File.join(root, "gems", name, "lib")}",
                                      "-I#{File.join(root, "gems/dexpace-core/lib")}", "-e", script)
    abort("gates:surface_snapshot: #{name} would not load:\n#{err}") unless status.success?
    out
  end

  desc "NFR-4: the runtime constant/method manifest, per gem"
  task :surface_snapshot do
    root = __dir__.sub(%r{/tasks\z}, "")
    drift = CLEAN_BUNDLE_ENTRIES.filter_map do |name, (_entry, constant)|
      expected_path = File.join(root, "test/fixtures/surface/#{name}.txt")
      actual = surface_for(root, name, constant)
      expected = File.exist?(expected_path) ? File.read(expected_path) : ""
      next if expected == actual

      surface_drift_message(name, expected, actual)
    end
    abort(drift.join("\n\n")) unless drift.empty?

    puts "gates:surface_snapshot: 6 manifests match the runtime tree."
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
end

namespace :surface do
  desc "Rewrite the committed runtime surface manifests -- a deliberate, reviewed act"
  task :regenerate do
    root = __dir__.sub(%r{/tasks\z}, "")
    FileUtils.mkdir_p(File.join(root, "test/fixtures/surface"))
    CLEAN_BUNDLE_ENTRIES.each do |name, (_entry, constant)|
      File.write(File.join(root, "test/fixtures/surface/#{name}.txt"),
                 surface_for(root, name, constant))
    end
  end
end
```

- [ ] **Step 5: Generate the six manifests and check them in**

Run: `bundle exec rake surface:regenerate && cat test/fixtures/surface/dexpace-core.txt`
Expected:

```
Dexpace
Dexpace::VERSION : String
```

Two lines. That is not a weakness — it is the state from which every later addition is a
reviewed diff.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/surface_snapshot_test.rb`
Expected: PASS, 3 runs.

---

## Task 15: `gates:sig_diff` — the RBS half of the API lock

**Files:**
- Modify: `tasks/gates.rake`
- Create: `tools/sig_diff.rb`
- Test: `test/gates/sig_diff_test.rb`

**Interfaces:**
- Consumes: `git`, and the `sig/` trees from Task 5.
- Produces: `SigDiff.baseline(root) -> String | nil`, `SigDiff.tags?(root) -> bool`,
  `SigDiff.violations(root, baseline) -> Array[String]`, the `gates:sig_diff` task.

- [ ] **Step 1: Write the failing test**

The tagged case needs a repository whose tag actually contains `gems/*/sig`, and this repository
has no such commit — cloning it would produce a baseline with no signatures in it and a test that
passes because there was nothing to remove. So the fixture is a scratch `git init` repository the
test builds from scratch: two signature files, one commit, one `v0.0.0` tag.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/sig_diff"

# NFR-4. Design §9.1: a diff of sig/**/*.rbs against the previous release, failing when a public
# signature disappears **or narrows** without a major bump, with regeneration a deliberate act
# and never a way to silence an unintentional break.
class SigDiffTest < GateCase
  test "before the first release tag the gate says so and passes" do
    out, _err, status = rake("gates:sig_diff")

    assert_predicate(status, :success?)
    assert_includes(out, "no release tag yet")
  end

  test "the pre-release branch is reachable only with no v* tag at all" do
    assert_empty(`git -C #{ROOT} tag --list 'v*'`.split("\n"),
                 "a v* tag exists, so the vacuous branch must no longer be taken")
  end

  test "a removed signature fails against a tagged baseline" do
    in_tagged_fixture do |dir|
      write_sig(dir, "module Dexpace\nend\n")
      found = SigDiff.violations(dir, "v0.0.0")

      assert_includes(found.join("\n"), "VERSION: String")
    end
  end

  test "a narrowed signature fails, not just a removed one" do
    in_tagged_fixture do |dir|
      # Same declaration name, narrower type. A names-only comparison would call this unchanged.
      write_sig(dir, "module Dexpace\n  VERSION: \"0.0.0\"\nend\n")
      found = SigDiff.violations(dir, "v0.0.0")

      assert_includes(found.join("\n"), "VERSION: String")
    end
  end

  test "a removed signature file fails" do
    in_tagged_fixture do |dir|
      FileUtils.rm(File.join(dir, "gems/dexpace-core/sig/dexpace/version.rbs"))
      found = SigDiff.violations(dir, "v0.0.0")

      assert_includes(found.join("\n"), "signature file removed")
    end
  end

  test "an unchanged tree is clean" do
    in_tagged_fixture { |dir| assert_empty(SigDiff.violations(dir, "v0.0.0")) }
  end

  private

  # A scratch repository whose v0.0.0 tag genuinely contains signatures. Cloning this repository
  # would not: nothing under gems/ has been committed here yet.
  def in_tagged_fixture
    Dir.mktmpdir("dexpace-sig-diff") do |dir|
      FileUtils.mkdir_p(File.join(dir, "gems/dexpace-core/sig/dexpace"))
      File.write(File.join(dir, "gems/dexpace-core/sig/dexpace.rbs"), "module Dexpace\nend\n")
      write_sig(dir, "module Dexpace\n  VERSION: String\nend\n")

      %w[init].each { |cmd| system("git", "-C", dir, cmd, "--quiet", exception: true) }
      system("git", "-C", dir, "config", "user.email", "ci@example.invalid", exception: true)
      system("git", "-C", dir, "config", "user.name", "ci", exception: true)
      system("git", "-C", dir, "add", "-A", exception: true)
      system("git", "-C", dir, "commit", "--quiet", "-m", "sigs", exception: true)
      system("git", "-C", dir, "tag", "v0.0.0", exception: true)

      yield dir
    end
  end

  def write_sig(dir, content)
    File.write(File.join(dir, "gems/dexpace-core/sig/dexpace/version.rbs"), content)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/sig_diff_test.rb`
Expected: FAIL — `cannot load such file -- tools/sig_diff`.

- [ ] **Step 3: Write `tools/sig_diff.rb`**

Declarations are compared as **whole normalised lines**, not by name. `VERSION: String` narrowing
to `VERSION: "0.0.0"` keeps the name and changes the contract, and design §9.1 asks the gate to
fail when a signature "disappears **or narrows**"; a names-only comparison would see nothing.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "open3"
require_relative "versions"

# NFR-4's signature half. Compares every declaration under gems/*/sig against the previous
# release tag, as full normalised text: a declaration present at the baseline and absent at HEAD
# is either a removal or a narrowing, and both are breaks.
#
# There is no baseline in a repository that has never been released, so this gate has a
# pre-release branch. That branch is reachable ONLY while no v* tag exists, and the gate asserts
# that rather than assuming it -- so the first tag arms the gate with no code change and nobody
# having to remember.
module SigDiff
  extend self

  # A line that declares part of the public surface: a method, a constant or an attribute, a
  # class/module/interface header, a type alias, or a mixin.
  DECLARATION = /^\s*(?:def\s|attr_\w+\s|type\s|class\s|module\s|interface\s|include\s|
                       extend\s|prepend\s|[A-Z][A-Za-z0-9_]*\s*:)/x

  def baseline(root)
    out, _err, status = Open3.capture3("git", "-C", root, "describe", "--tags",
                                       "--match", "v*", "--abbrev=0")
    status.success? ? out.strip : nil
  end

  def tags?(root)
    !Open3.capture3("git", "-C", root, "tag", "--list", "v*").first.strip.empty?
  end

  def violations(root, tag)
    before = declarations_at(root, tag)
    after = declarations_now(root)

    removed_files(before, after, tag) + changed_declarations(before, after, tag)
  end

  private

  def removed_files(before, after, tag)
    (before.keys - after.keys).sort.map do |path|
      "#{path}: signature file removed since #{tag} (NFR-4)."
    end
  end

  def changed_declarations(before, after, tag)
    (before.keys & after.keys).sort.flat_map do |path|
      gone = before[path] - after[path]
      next [] if gone.empty?

      ["#{path}: #{gone.length} public declaration(s) removed or narrowed since #{tag}:\n" \
       "#{gone.map { |line| "  - #{line}" }.join("\n")}\n" \
       "Regenerating a signature to silence a break is not permitted (NFR-4); bump MAJOR in " \
       "VERSIONS or restore the declaration."]
    end
  end

  # Whole declaration lines, whitespace-normalised so reindentation is not a break.
  def declarations(content)
    content.lines.map(&:strip).select { |line| DECLARATION.match?(line) }.sort
  end

  def declarations_at(root, tag)
    listing, = Open3.capture3("git", "-C", root, "ls-tree", "-r", "--name-only", tag, "gems")
    listing.split("\n").grep(%r{\Agems/[^/]+/sig/.*\.rbs\z}).to_h do |path|
      content, = Open3.capture3("git", "-C", root, "show", "#{tag}:#{path}")
      [path, declarations(content)]
    end
  end

  def declarations_now(root)
    Dir.glob("gems/*/sig/**/*.rbs", base: root).to_h do |path|
      [path, declarations(File.read(File.join(root, path)))]
    end
  end
end
```

- [ ] **Step 4: Wire the rake task**

```ruby
  desc "NFR-4: sig/**/*.rbs against the previous release tag"
  task :sig_diff do
    require_relative "../tools/sig_diff"
    root = __dir__.sub(%r{/tasks\z}, "")
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
```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/sig_diff_test.rb`
Expected: PASS, 6 runs. The narrowing case is the one that matters: it is the difference between
a gate that catches a deleted method and a gate that catches `NFR-4`'s actual clause.

- [ ] **Step 6: Confirm the release blocker still stands**

Run: `grep -n 'sig-diff baseline' docs/first-release.md`
Expected: the blocker line is present and **unchecked**. Phase 0 builds the gate; it does not
close the blocker.

---

## Task 16: YARD and the undocumented-public gate

**Files:**
- Create: `.yardopts`
- Modify: `tasks/quality.rake`
- Test: `test/gates/yard_test.rb`, `test/fixtures/gates/yard/undocumented.rb`

**Interfaces:**
- Consumes: the twelve library files from Task 5.
- Produces: the `yard` task.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# Design §9's documentation row, and styleguide 14.1: YARD on every public class and method.
# YARD ships no failure mode for undocumented objects, so the gate is `yard stats --list-undoc`
# with a non-zero undocumented count failing the task.
class YardTest < GateCase
  test "the repository documents every public object" do
    _out, err, status = rake("yard")

    assert_predicate(status, :success?, err)
  end

  test "an undocumented public method fails the gate" do
    out = `bundle exec yard stats --list-undoc test/fixtures/gates/yard/undocumented.rb 2>&1`

    refute_includes(out, "100.00% documented")
    assert_includes(out, "Undocumented Objects")
  end
end
```

`test/fixtures/gates/yard/undocumented.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module UndocumentedFixture
  def self.no_yard_block
    :nothing
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/yard_test.rb`
Expected: FAIL — unknown task `yard`.

- [ ] **Step 3: Write `.yardopts`**

```
--markup markdown
--no-private
--output-dir doc
--exclude test/
--exclude tasks/
--exclude tools/
--exclude .rubocop/
gems/*/lib/**/*.rb
```

- [ ] **Step 4: Write the task**

```ruby
desc "Documentation, with an undocumented-public-object gate"
task :yard do
  sh("bundle", "exec", "yard", "doc", "--quiet")
  stats = `bundle exec yard stats --list-undoc`
  puts stats
  abort("undocumented public objects (styleguide 14.1)") unless stats.include?("100.00% documented")
end
```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/yard_test.rb`
Expected: PASS, 2 runs. If `yard stats` reports below 100%, add the missing YARD block — a block
explains *why*, and never restates a signature (styleguide 14.2).

---

## Task 17: `gates:reproducible` and `bundler_audit`

**Files:**
- Modify: `tasks/gates.rake`, `tasks/quality.rake`
- Test: `test/gates/reproducible_test.rb`,
  `test/fixtures/gates/reproducible/nondeterministic/`

**Interfaces:**
- Consumes: the six gemspecs from Task 5.
- Produces: the `gates:reproducible` and `bundler_audit` tasks, and
  `Reproducible.digests(gem_dir, epoch:) -> [String, String]`.

- [ ] **Step 1: Write the failing test**

Two things need proving, and only one of them is "the real gems agree". The other is that the
comparison is **sensitive** — that it would notice if the inputs were not normalised. The fixture
gem's `spec.files` is an unsorted `Dir.glob` and its build runs without `SOURCE_DATE_EPOCH`, with
one file's mtime moved between the two builds; the digests must then differ. Without that, a
gate that always compared two copies of the same byte string would pass identically.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/reproducible"

# NFR-12: identical source inputs yield byte-for-byte identical artifacts. Scope is one gem,
# built twice, on one interpreter -- cross-RubyGems-version container identity is the
# toolchain's business, not the source's, and is not claimed (design Deviation Ledger P0-7).
class ReproducibleTest < GateCase
  FIXTURE = File.join(ROOT, "test/fixtures/gates/reproducible/nondeterministic")

  test "building each gem twice under a fixed SOURCE_DATE_EPOCH gives identical bytes" do
    _out, err, status = rake("gates:reproducible")

    assert_predicate(status, :success?, err)
  end

  test "the comparison notices an unnormalised build" do
    # No SOURCE_DATE_EPOCH, unsorted spec.files, and a file touched between the two builds.
    first, second = Reproducible.digests(FIXTURE, epoch: nil) do
      FileUtils.touch(File.join(FIXTURE, "lib/nondeterministic.rb"),
                      mtime: Time.now + 3600)
    end

    refute_equal(first, second,
                 "two builds of an unnormalised gem agreed; the digest is not sensitive to " \
                 "timestamps and this gate proves nothing")
  end

  test "the same fixture is reproducible once the epoch is fixed" do
    first, second = Reproducible.digests(FIXTURE, epoch: Reproducible::EPOCH)

    assert_equal(first, second)
  end

  test "bundler-audit is wired into the default gate set and runs against a fresh resolve" do
    body = File.read(File.join(ROOT, "tasks/quality.rake"))

    assert_includes(body, "bundler-audit")
    assert_includes(body, "--update")
    assert_includes(File.read(File.join(ROOT, "Rakefile")), "bundler_audit")
  end
end
```

The third test is the pair of the second: it shows the same fixture becoming reproducible when
the epoch is fixed, so the difference is attributable to the normalisation rather than to the
fixture being broken.

`bundler_audit` is asserted as **wired**, not as passing. It resolves the RubyGems advisory
database over the network and its verdict changes when a CVE is published against a gem this
repository already depends on — a test that asserted a green exit would fail for a reason that
has nothing to do with the change under test, and the honest response to that failure is a
dependency bump, not a test edit.

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/reproducible_test.rb`
Expected: FAIL — `cannot load such file -- tools/reproducible`.

- [ ] **Step 3: Write the fixture gem**

`test/fixtures/gates/reproducible/nondeterministic/` holds a two-file gem whose gemspec is
deliberately wrong in the one way this gate exists to catch:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

Gem::Specification.new do |spec|
  spec.name = "nondeterministic"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: an unsorted file list and no normalised timestamp."
  spec.files = Dir.glob("lib/**/*.rb", base: __dir__) # deliberately unsorted -- NFR-12's trap
  spec.require_paths = ["lib"]
end
```

- [ ] **Step 4: Write `tools/reproducible.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "digest"
require "open3"
require "tmpdir"

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
      env = epoch.nil? ? {} : { "SOURCE_DATE_EPOCH" => epoch }
      stdout, stderr, status = Open3.capture3(env, "gem", "build", "#{name}.gemspec",
                                              "--output", target, "--quiet", chdir: gem_dir)
      raise "gem build failed for #{name}:\n#{stdout}\n#{stderr}" unless status.success?

      Digest::SHA256.file(target).hexdigest
    end
  end
end
```

- [ ] **Step 5: Write the two tasks**

In `tasks/gates.rake`:

```ruby
  desc "NFR-12: each gem builds twice to byte-identical output"
  task :reproducible do
    require_relative "../tools/reproducible"
    root = __dir__.sub(%r{/tasks\z}, "")

    Dir.glob(File.join(root, "gems/*")).sort.each do |gem_dir|
      first, second = Reproducible.digests(gem_dir)
      next if first == second

      abort("gates:reproducible: #{File.basename(gem_dir)} built two different artifacts: " \
            "#{first} != #{second}")
    end

    puts "gates:reproducible: 6 gems, byte-identical across two builds."
  end
```

In `tasks/quality.rake`:

```ruby
desc "Dependency CVE scan, against the lockfile this bundle just resolved"
task :bundler_audit do
  # There is no committed Gemfile.lock (see docs/knowledge/notes/tooling-and-quality-gates.md),
  # so the scan runs against the resolve on disk -- which is what CI actually installed.
  sh("bundle", "exec", "bundler-audit", "check", "--update")
end
```

- [ ] **Step 6: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/reproducible_test.rb`
Expected: PASS, 4 runs. If the second test's two digests agree, the fixture is not perturbing
anything — confirm the `FileUtils.touch` actually moved the mtime and that no
`SOURCE_DATE_EPOCH` is leaking in from the environment.

Run: `bundle exec rake bundler_audit`
Expected: `No vulnerabilities found`. A finding here is a real dependency problem and is fixed by
bumping the `tool` line in `VERSIONS`, never by narrowing the gate.

---

## Task 18: `.github/workflows/ci.yml`

**Files:**
- Create: `.github/workflows/ci.yml`
- Test: `test/gates/ci_workflow_test.rb`

**Interfaces:**
- Consumes: every rake task from Tasks 3–17; `DexpaceVersions.ruby_matrix`.
- Produces: nothing other code calls. Task 19's `gates:versions` reads this file's matrix.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/versions"
require "yaml"

# NFR-17 (blocking in CI, not only locally) and NFR-10 (the matrix runs the REAL suite --
# TargetRubyVersion catches syntax, not stdlib availability, design §9.2).
class CiWorkflowTest < GateCase
  WORKFLOW = YAML.load_file(File.join(ROOT, ".github/workflows/ci.yml"))

  test "the matrix is exactly what VERSIONS declares" do
    matrix = WORKFLOW.dig("jobs", "test", "strategy", "matrix", "ruby")

    assert_equal(DexpaceVersions.ruby_matrix, matrix.map(&:to_s))
  end

  test "the matrix job runs the real gem suites, not a syntax check" do
    steps = WORKFLOW.dig("jobs", "test", "steps").map { |step| step["run"].to_s }.join("\n")

    assert_includes(steps, "rake test:gems")
    refute_includes(steps, "ruby -c")
  end

  test "the interpreter-independent suites and the cop suite run once, in the gates job" do
    gates = WORKFLOW.dig("jobs", "gates", "steps").map { |step| step["run"].to_s }.join("\n")
    matrix = WORKFLOW.dig("jobs", "test", "steps").map { |step| step["run"].to_s }.join("\n")

    assert_includes(gates, "rake test:gates")
    assert_includes(gates, "rake cops:test")
    refute_includes(matrix, "rake test:gates")
  end

  test "every gate in DEFAULT_GATES appears in exactly one CI job" do
    listed = `bundle exec rake -s gates:list`.split("\n")
    steps = WORKFLOW.fetch("jobs").values
                    .flat_map { |job| job.fetch("steps") }
                    .map { |step| step["run"].to_s }.join("\n")

    listed.each { |gate| assert_includes(steps, "rake #{gate}", gate) }
  end

  test "the three zero-dependency checks run on every matrix row" do
    steps = WORKFLOW.dig("jobs", "test", "steps").map { |step| step["run"].to_s }.join("\n")

    %w[gates:gemspec_audit gates:require_allowlist gates:clean_bundle].each do |gate|
      assert_includes(steps, gate)
    end
  end

  test "no row is allowed to fail" do
    WORKFLOW.fetch("jobs").each_value do |job|
      refute(job["continue-on-error"], "a gate that may fail is not a gate (NFR-17)")
    end
  end

  test "bundler caching is off, because there is no committed lockfile" do
    uses = WORKFLOW.fetch("jobs").values.flat_map { |job| job.fetch("steps") }
                   .select { |step| step["uses"].to_s.include?("setup-ruby") }

    uses.each { |step| refute(step.dig("with", "bundler-cache")) }
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/ci_workflow_test.rb`
Expected: FAIL — `Errno::ENOENT`.

- [ ] **Step 3: Write the workflow**

```yaml
name: CI

on:
  push:
    branches: [main, mvp]
  pull_request:

jobs:
  # Interpreter-independent by construction -- they read text, signatures and build output --
  # so running them four times would buy nothing.
  gates:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # gates:sig_diff needs tags and history
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ".ruby-version"
          bundler-cache: false
      - run: bundle install
      - run: bundle exec rake rubocop
      - run: bundle exec rake cops:test
      - run: bundle exec rbs collection install
      - run: bundle exec rake rbs:validate
      - run: bundle exec rake steep
      - run: bundle exec rake test:gates
      - run: bundle exec rake gates:rbs_surface
      - run: bundle exec rake gates:sig_diff
      - run: bundle exec rake gates:surface_snapshot
      - run: bundle exec rake gates:versions
      - run: bundle exec rake gates:reproducible
      - run: bundle exec rake yard
      - run: bundle exec rake bundler_audit

  # NFR-10: the real suite on every supported Ruby. The 3.2 row is where a method present on the
  # developer's 4.0 and absent on the declared floor produces a NoMethodError that
  # TargetRubyVersion cannot see; the 4.0 row is where the bundled-gem trap fires.
  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        ruby: ["3.2", "3.3", "3.4", "4.0"]
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: false
      - run: bundle install
      - run: bundle exec rake test:gems
      - run: bundle exec rake gates:gemspec_audit
      - run: bundle exec rake gates:require_allowlist
      - run: bundle exec rake gates:clean_bundle
      - run: bundle exec rake gates:single_instance
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/ci_workflow_test.rb`
Expected: PASS, 7 runs. The "exactly one CI job" test is the one that keeps a gate from being
added to `DEFAULT_GATES` and then never running in CI — which is how `cops:test` was missed the
first time this plan was written.

---

## Task 19: `gates:versions` — the gate that reads every other artifact

**Files:**
- Modify: `tasks/versions.rake`
- Test: `test/gates/versions_gate_test.rb`,
  `test/fixtures/gates/versions/{stale_pin,dropped_matrix_row,ahead_literal}/`

**Interfaces:**
- Consumes: `VERSIONS`, `.ruby-version`, `.github/workflows/ci.yml`, all six gemspecs and all
  six `version.rb` files.
- Produces: `VersionsGate.violations(root) -> Array[String]`, the `gates:versions` task. This is
  the last of the seventeen; after it, Task 2's `default_task_test.rb` gains the assertion
  that every listed name is a real task.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/versions_gate"

# NFR-14. A single source of truth that nothing checks is a file, not a source of truth: Ruby
# gives no one file that a gemspec, a Gemfile, .ruby-version and a YAML matrix can all read, so
# the single source is enforced rather than shared.
class VersionsGateTest < GateCase
  FIXTURES = File.join(ROOT, "test/fixtures/gates/versions")

  test "the real repository agrees with VERSIONS everywhere" do
    assert_empty(VersionsGate.violations(ROOT))
  end

  test "rejects a .ruby-version that disagrees with the dev pin" do
    found = VersionsGate.violations(File.join(FIXTURES, "stale_pin"))

    assert_includes(found.join("\n"), ".ruby-version")
  end

  test "rejects a CI matrix row that VERSIONS does not declare" do
    found = VersionsGate.violations(File.join(FIXTURES, "dropped_matrix_row"))

    assert_includes(found.join("\n"), "matrix")
  end

  test "rejects a version.rb literal ahead of VERSIONS" do
    found = VersionsGate.violations(File.join(FIXTURES, "ahead_literal"))

    assert_includes(found.join("\n"), "VERSION")
  end
end
```

Each fixture is a miniature repository: a `VERSIONS`, a `.ruby-version`, a
`.github/workflows/ci.yml` and one `gems/dexpace-core/` tree, with exactly one value wrong.

- [ ] **Step 2: Run it to confirm it fails**

Run: `ruby -Itest test/gates/versions_gate_test.rb`
Expected: FAIL — `cannot load such file -- tools/versions_gate`.

- [ ] **Step 3: Write `tools/versions_gate.rb`**

```ruby
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

  def gem_violations(root, versions)
    floor = ">= #{DexpaceVersions.value("ruby", "floor", versions)}"

    Dir.glob(File.join(root, "gems/*")).sort.flat_map do |dir|
      name = File.basename(dir)
      declared = DexpaceVersions.value("gem", name, versions)
      spec = Gem::Specification.load(File.join(dir, "#{name}.gemspec"))
      version_rb = Dir.glob(File.join(dir, "lib/**/version.rb")).first
      literal = File.read(version_rb)[/VERSION\s*=\s*"([^"]+)"/, 1]

      found = []
      if spec.version.to_s != declared
        found << "#{name}.gemspec is #{spec.version}, VERSIONS says #{declared}."
      end
      if literal != declared
        found << "#{name}'s VERSION literal is #{literal}, VERSIONS says #{declared}."
      end
      if spec.required_ruby_version.to_s != floor
        found << "#{name}.gemspec required_ruby_version is " \
                 "#{spec.required_ruby_version}, expected #{floor}."
      end
      found
    end
  end
end
```

- [ ] **Step 4: Wire the rake task in `tasks/versions.rake`**

```ruby
namespace :gates do
  desc "NFR-14/NFR-10: VERSIONS against every consumer of it"
  task :versions do
    require_relative "../tools/versions_gate"
    root = __dir__.sub(%r{/tasks\z}, "")
    found = VersionsGate.violations(root)
    abort(found.join("\n")) unless found.empty?

    puts "gates:versions: .ruby-version, the CI matrix, six gemspecs and six VERSION literals " \
         "all agree with VERSIONS."
  end
end
```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/versions_gate_test.rb`
Expected: PASS, 4 runs.

- [ ] **Step 6: Close the loop — add the "every gate is real" assertion**

`gates:versions` is the last of the seventeen. Only now can `default_task_test.rb` assert that
every name in `DEFAULT_GATES` resolves to a task, so the assertion is added here rather than in
Task 2 — an assertion added earlier would have left `rake test:gates` red for seventeen tasks,
and a suite that is expected to be red is a suite nobody reads.

Append to `test/gates/default_task_test.rb`:

```ruby
  test "every listed gate is a real, separately invocable task" do
    known = `bundle exec rake -s -T -A`.scan(/^rake (\S+)/).flatten

    EXPECTED.each { |gate| assert_includes(known, gate) }
  end
```

- [ ] **Step 7: Run it to confirm the loop is closed**

Run: `ruby -Itest test/gates/default_task_test.rb`
Expected: PASS, 2 runs — every one of the seventeen names in `DEFAULT_GATES` is now a real,
separately invocable task. If any name is missing, the gate it names was never wired; find its
task and add it, do not remove the name.

---

## Task 20: Gates, unchanged API surface, and the checklist

**Files:**
- Create: `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-checklist.md`
- Modify: `CLAUDE.md`, `README.md`, `docs/README.md`,
  `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`, `docs/deferred-items.md`
- Test: the full gate set, plus the housekeeping probe

**Interfaces:**
- Consumes: everything Tasks 1–19 built.
- Produces: the phase record. Nothing consumes it in code.

- [ ] **Step 1: Run every gate, in one command**

Run: `bundle exec rake`
Expected: all seventeen gates green, in the `DEFAULT_GATES` order, ending with `bundler_audit`.
Record the wall-clock time in the checklist — a gate set nobody will wait for is a gate set that
gets skipped.

- [ ] **Step 2: Run every gate on the floor and the ceiling**

```bash
~/.local/share/mise/installs/ruby/3.2.11/bin/ruby -S bundle exec rake test:gems \
  gates:gemspec_audit gates:require_allowlist gates:clean_bundle gates:single_instance
~/.local/share/mise/installs/ruby/4.0.6/bin/ruby -S bundle exec rake
```

Expected: green on both. The 3.2 run skips four assertions in `require_allowlist_test.rb` — the
three that read a bundled-since *reason* out of `Gem::BUNDLED_GEMS::SINCE`, which is undefined
there, and the allowlist/bundled overlap check. Those skips are asserted, not tolerated, and the
"refuses base64, logger and tsort on every Ruby" case does not skip.

- [ ] **Step 3: Confirm the runtime surface and the signatures are unchanged**

Run: `bundle exec rake gates:surface_snapshot gates:rbs_surface gates:sig_diff`
Expected: `6 manifests match the runtime tree`, `no foreign constant in any public signature`,
`no release tag yet -- the first v* tag becomes the baseline`. Phase 0 adds public surface for
the first time, so "unchanged" here means *unchanged since the manifests were generated in Task
14* — if this reports drift, a later task added a constant and the manifest was not regenerated.

- [ ] **Step 4: Write the checklist**

Create `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-checklist.md`, one row
per requirement ID in scope, with the roadmap's legend: ✅ implemented and tested · 🚫 not built
(permanent simplification, named reason) · ⏳ deferred (`DEF-<n>` with its pick-up condition) ·
N/A not applicable in this port.

Nineteen rows: `NFR-1` … `NFR-17`, `SEAM-1`, `SEAM-2`. Each names the **numbered task above** that
satisfies it. `NFR-8` and `NFR-9` are 🚫 with design §10 item 19's reason (Ruby has no
whole-program shrinker; `NFR-8` exempts itself by its own text) and name Tasks 9 and 10 as the
retarget. `NFR-16` is ⏳ `DEF-20`. `NFR-2`'s row records that the budget is *enforced* here and
*spent* later: no adapter gemspec declares a third-party dependency in phase 0, and the audit's
`two_third_party` fixture is what proves the budget is real.

The checklist is written **now, from what was actually built**, not from this plan — a row whose
task did not do what the plan said is a row that says so.

Add the audit-group section the roadmap's execution rules require: the four groups this phase ran
(*Gem layout, zero-dependency core*; *RuboCop and formatting*; *RBS / Steep typing*; *Minitest
conventions*), and the result of each, including the five notes filed.

- [ ] **Step 5: Verify the deferral rows are present, and add any the implementation found**

Run: `grep -n '^### DEF-2' docs/deferred-items.md`
Expected: `DEF-20`, `DEF-21`, `DEF-22` and `DEF-23`, appended during planning. If the
implementation deferred anything else, append it as `DEF-24` onward with the deferring phase, the
reason, the pick-up condition and the IDs it cites — and update the `next id:` line at the foot of
the register.

- [ ] **Step 6: Append the roadmap status note**

Append one dated entry to `## Phase Status Notes` in
`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`. Never rewrite an earlier one. It states
what landed, the gate count, the Rubies it was verified on, and the two counts that changed —
six gems, one phase directory.

- [ ] **Step 7: Rewrite `CLAUDE.md`'s command block**

Replace the whole `### After scaffold — planned, none of these exist yet` section, heading
included, with a section naming what was actually built. The exact commands, from what Tasks 2–19
created:

```bash
bundle install
bundle exec rake                                  # the default task: all seventeen gates (NFR-17)
bundle exec rake rubocop                          # NFR-7, findings fatal, no autocorrection
bundle exec rake rubocop:fix                      # safe autocorrections only, never the gate
bundle exec rake rbs:validate steep               # NFR-3
bundle exec rake cops:test                        # the five custom cops' own suite
bundle exec rake test:gems                        # gem suites: warnings fatal, coverage floor
bundle exec rake test:gates                       # the repository's gate suites
bundle exec rake gates:gemspec_audit              # SEAM-1, NFR-1, NFR-2
bundle exec rake gates:require_allowlist          # SEAM-1, SEAM-2 -- the allowlist and the denylist
bundle exec rake gates:clean_bundle               # the scratch-Gemfile isolation run
bundle exec rake gates:rbs_surface                # NFR-11
bundle exec rake gates:sig_diff                   # NFR-4, RBS half
bundle exec rake gates:surface_snapshot           # NFR-4, runtime half
bundle exec rake surface:regenerate               # deliberate: regenerate BOTH this and sig/
bundle exec rake gates:single_instance            # design §2.4
bundle exec rake gates:versions                   # NFR-14, NFR-10
bundle exec rake gates:reproducible               # NFR-12
bundle exec rake yard bundler_audit
(cd gems/dexpace-core && bundle exec rake test)   # one suite per gem, under `ruby -w`
```

Also update, in the same edit:
- The "**Nothing is implemented yet.**" paragraph — a `Gemfile`, `Rakefile`, `Steepfile` and
  `.rubocop.yml` now exist. State what phase 0 built and what is still empty (every gem's `lib/`
  holds a namespace and a `VERSION` and nothing else).
- The lockfile rule: `Gemfile.lock` is not committed, and why, citing
  `docs/knowledge/notes/tooling-and-quality-gates.md`.
- The bundled-gem paragraph: the verified Ruby 4.0.6 list is longer than the five names currently
  stated, and `tsort` leaves at 4.1. Cite
  `docs/knowledge/notes/package-and-dependency-layout.md`.

- [ ] **Step 8: Fix the count sentences the `claims` check reads**

In `CLAUDE.md`'s "**The counts the `claims` check reads out of this file.**" list:

- `Zero gems exist under `gems/` — the directory itself does not exist yet.` becomes a sentence
  stating **six** gems, naming what each contains.
- The phase-directory sentence states **two** phase directories once phase 1 lands; at the end of
  phase 0 it states **one**, and names `docs/work/mvp/phase0/`.
- The harvested-topic sentence is unchanged: 40.

Add a gem-count sentence to `README.md` and `docs/README.md` too — the `claims` check has a row
for each and currently no-ops because neither states a count.

- [ ] **Step 9: Run the probe and fix what it reports**

Run: `ruby .claude/skills/housekeeping/probe.rb`
Expected: exit 0, `no drift found.` If `claims` still reports a mismatch, the numeral in the
sentence is wrong — fix the sentence, never the check. If `readmes` reports a gem README under 20
lines, write the missing content; do not trim the bar.

- [ ] **Step 10: Run the four repository gate commands**

```bash
ruby .claude/skills/housekeeping/probe.rb
ruby -w .claude/skills/housekeeping/test/run.rb
ruby -w scripts/test/knowledge_test.rb
ruby scripts/verify_knowledge_structure.rb
```

Expected: all four exit 0. The last one confirms the five notes this phase filed are structurally
sound and that every key they cite is still live — a re-harvest that reworded a rule would show
up here as an orphaned key.

- [ ] **Step 11: Hand over**

Do not commit. Report to the manager: the seventeen gates and their wall-clock time, the six gems
at `0.0.0`, the deliberately failing fixture list with the gate each one turns red, the Rubies
each gate was verified on, the `DEF-` rows appended, and the `CLAUDE.md` diff.

---

## Self-Review

**Spec coverage.** Every `## <Component>` section of the design maps to at least one task:

| Design section | Task |
|---|---|
| `VERSIONS` | 2 (the file and its only reader), 19 (the gate over every consumer of it) |
| Root `Gemfile` and `.gitignore` | 1 (`.gitignore`), 2 (`Gemfile`) |
| `Rakefile` and the gate tasks | 2 |
| Zero-dependency gate part 1: gemspec audit | 8 |
| Zero-dependency gate part 2: require-allowlist | 9 |
| Zero-dependency gate part 3: clean-bundle | 10 |
| `.rubocop.yml` and the five custom cops | 3 (config), 4 (cops, their suite and `cops:test`) |
| Warnings as errors | 6 |
| Typing: `sig/`, `Steepfile`, `rbs_collection.yaml` | 5 (`sig/`), 12 (`Steepfile`, the tasks) |
| The API-surface lock | 14 (runtime snapshot), 15 (RBS diff) |
| `gates:rbs_surface` | 13 |
| Coverage | 7 |
| YARD and the undocumented-public gate | 16 |
| Reproducible builds | 17 |
| The test convention | 6 |
| The gem entry files and `sig/` mirrors | 5 |
| `.github/workflows/ci.yml` | 18 |
| Design §9 Addendum A1 (the interrupt cop) | 4 |
| Design §9 Addendum A2 (adapters in the require audit) | 9 |
| Design §9 Addendum A3 (the denylist) | 9 |
| Testing: a deliberately failing input per gate | every gate task's Step 1 |
| Single-instance guarantee (§2.4) | 11 |
| Deferrals `DEF-20`–`DEF-23` | filed during planning; verified in Task 20, Step 5 |
| The checklist, the registers and `CLAUDE.md` | 20 |

One design element deliberately has no task of its own: the five knowledge notes were written
during planning rather than during implementation, at the coordinator's direction, and Task 20
Step 10 verifies them structurally.

**Placeholder scan.** No "TBD", no "implement later", no "add appropriate error handling", no
"similar to Task N". One set of values is stated as a shape to be read from the environment at
implementation time rather than invented here — the `tool` constraints in `VERSIONS` (Task 2,
Step 4) — and the step names the exact command that produces the real ones. That is a
measurement, not a placeholder. The `>= ` floors on `net-http`, `async-http` and `json` are no
longer among them: no adapter declares a third-party dependency in phase 0, so there is no floor
to choose until the phase that writes the code needing it.

**Type consistency.**

- `DexpaceVersions.core_constraint`, `.gem_version`, `.gem_names`, `.tools`, `.ruby_floor`,
  `.ruby_dev`, `.ruby_matrix` and `.value(kind, name, path)` are defined in Task 2 and consumed
  by name in Tasks 5 (gemspecs), 8 (`GemspecAudit`) and 19 (`VersionsGate`).
- `CLEAN_BUNDLE_ENTRIES` is defined in Task 10 and consumed in Tasks 11 and 14.
- `GateCase#rake(task, env)` and `GateCase.test` are defined in Task 2 and used by every gate
  suite from Task 2 onward.
- `run_suite(files, libs, coverage:)` is defined in Task 6 and called by both `test:gems`
  (`coverage: true`) and `test:gates` (`coverage: false`).
- `CopCase#assert_offense(cop_class, source, message_fragment)` and `#assert_no_offense` are
  defined in Task 4, Step 1 and used by the single data-driven suite in Step 2.
- `RequireAllowlist.scan_file(path, permitted:, lib_root:)` is called with all three keywords in
  both the test (Task 9, Step 1) and the implementation (Step 3).
- `Reproducible.digests(gem_dir, epoch:)` is defined in Task 17, Step 4 and called by that task's
  test with `epoch: nil` and `epoch: Reproducible::EPOCH`, and by its rake task with the default.
- `SigDiff.baseline(root)`, `.tags?(root)` and `.violations(root, tag)` are defined in Task 15,
  Step 3 and called with the same arity in that task's test and rake task.
- `Surface.manifest(root_constant)` is defined in Task 14 and called by `surface_for` in the same
  task.
- `DexpaceTestCase.test`, `GateCase.test` and `CopCase.test` are three separate definitions of
  the same idiom in three separate base classes, deliberately: the three trees load
  independently, and `.rubocop/test/` cannot reach `test/support/` without putting the
  repository's test tree on a cop suite's load path.

**Gate wiring.** All seventeen names in `DEFAULT_GATES` are created by a numbered task — `rubocop`
(3), `cops:test` (4), `rbs:validate` and `steep` (12), `test:gems` and `test:gates` (6),
`gates:gemspec_audit` (8), `gates:require_allowlist` (9), `gates:clean_bundle` (10),
`gates:rbs_surface` (13), `gates:sig_diff` (15), `gates:surface_snapshot` (14),
`gates:single_instance` (11), `gates:versions` (19), `gates:reproducible` and `bundler_audit`
(17), `yard` (16) — and every one of them appears in exactly one CI job, which Task 18's own test
asserts mechanically rather than leaving to this list.
