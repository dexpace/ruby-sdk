# Phase 0 — Scaffold and Quality Gates: Checklist

**Written at execution time, 2026-09-14, from what was built** — not from the plan. A row whose
task did not do what the plan said is a row that says so, and the "Deviations from the plan"
section below is where each departure is stated with its reason.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

**One thing every ✅ below means, and one thing it does not.** Phase 0 builds the gate that will
answer each `NFR`; it dispositions none of them. A ✅ here says the gate exists, is wired into the
default Rake task, is blocking, and has been watched to go red on a deliberately failing input.
Whether the requirement is *satisfied* is phase 9's question
(`docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance.md`), which is the
roadmap's own division.

## Requirement rows

Plan: `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md`. Task numbers are
that plan's.

| ID | Level | Status | Task(s) | What was built, and the input that turns it red |
|---|---|---|---|---|
| `NFR-1` | MUST | ✅ machinery | 8, 9, 10 | `gates:gemspec_audit` (core's `runtime_dependencies` empty), `gates:require_allowlist` (twelve-name allowlist, scoped denylist, both `require` forms and `autoload`, parsed so every spelling that reaches `Kernel#require` is seen and a non-literal feature is refused), `gates:clean_bundle` (scratch `Gemfile`, `bundle exec ruby -e` smoke path). Red on: a core gemspec with one `add_dependency`; `require "base64"`/`"logger"`/`"tsort"`/`"json"`/`"timeout"`/`"socket"`, and `require("json")`, `Kernel.require "json"`, a mid-line `require "timeout"`, `autoload :JSON, "json"`, `require name`; a miniature workspace whose core requires `logger`, which Bundler refuses on every matrix row |
| `NFR-2` | SHOULD | ✅ machinery, budget **enforced** here and **spent** later | 5, 8 | Every adapter gemspec declares `dexpace-core` at `DexpaceVersions.core_constraint` (`~> 0.0`) and nothing else (design P0-9); the audit enforces "core plus at most one" in full. Red on: the `two_third_party` fixture (core + `net-http` + `logger`), the `stale_constraint` fixture (`~> 0.1` against a 0.0.0 core) |
| `NFR-3` | SHOULD | ✅ armed | 5, 12 | `sig/` mirrors `lib/` one file per file in all six gems and ships in `spec.files`; `rbs:validate` per gem with `--no-collection`; `steep check` over six named targets, `core` strict. Red on: an `.rbs` referencing `Nonexistent::Type`. Steep's own detection is not re-proven here (design, Testing) |
| `NFR-4` | SHOULD | ✅ armed, pre-release branch stated | 14, 15 | `gates:sig_diff` compares parsed declarations — one line per public declaration and per overload, `private` honoured, per gem — against the last `v*` tag and exits 0 with a named message while no tag exists (P0-8, asserted by test); `gates:surface_snapshot` diffs six committed manifests, each walked from `Dexpace` itself — an adapter's manifest is what its entry file adds to the tree with core already loaded, inside or beside its own namespace — and walks `Data.define`-generated readers and singleton methods as well as instance methods, one line per method. Red on: a removed declaration, a **narrowed** one (`VERSION: String` → `VERSION: "0.0.0"`), a removed signature file, a dropped overload on a continuation line, a public method moved under `private` by section or by modifier; an injected constant inside a gem's namespace, and one beside it (`Dexpace::Transport::Shared`) |
| `NFR-5` | SHOULD | ✅ armed and green (P0-10) | 7 | `test/support/coverage.rb`: `cover "gems/*/lib/**/*.rb"`, `minimum_coverage 80` unconditional, `merging false`. Twelve tracked files, 42/42 lines, 100% on its merits. Red on: an uncovered library file written into `tmp/` |
| `NFR-6` | SHOULD | ✅ | 6 | Two halves: the `Warning.warn` override in `DexpaceTestCase` and `SuiteRunner`'s stderr scan under `-w -W:deprecated` with `RUBYOPT` appended. Plus the thread-leak teardown (the Task 6 amendment). Red on: a redefinition before the override exists (scan) and one after it (override) |
| `NFR-7` | SHOULD | ✅ | 3, 4 | RuboCop at `--fail-level=convention`, no autocorrection in the gate, `NewCops: enable`, every override commented. One narrowly-scoped, documented exception with its re-enable condition: `scripts/**/*` and `.claude/**/*` (see deviation P0-11) |
| `NFR-8` | MUST | 🚫 retargeted (design §10 item 19) | 9, 10 | Ruby has no whole-program shrinker and `NFR-8` exempts itself by its own text ("in target ecosystems that support…"). The retarget is the require-allowlist audit and the clean-bundle run |
| `NFR-9` | SHOULD | 🚫 retargeted (design §10 item 19) | 9, 10 | As `NFR-8`: the regression check over shipped keep-rules becomes the clean-bundle run on every matrix row |
| `NFR-10` | MUST | ✅ machinery | 5, 8, 18, 19 | `required_ruby_version = ">= 3.2"` from `VERSIONS`' `ruby floor` in every gemspec, asserted by two gates; CI matrix `3.2 / 3.3 / 3.4 / 4.0` running `test:gems` and the four per-row gates; the matrix set verified locally on all four interpreters. Red on: a gemspec at `>= 4.0`; a dropped matrix row |
| `NFR-11` | SHOULD | ✅ armed | 13 | `gates:rbs_surface` loads every `.rbs` as one signature set, resolves every type name against it the way `rbs validate` does — so a relative `Headers` inside `module Dexpace` is `::Dexpace::Headers` and a type variable is not a constant — and walks each type tree: return, parameter and block types, superclass, mixin (name and type arguments), self-types, type alias, constant, class or module alias, class- and method-level generic bounds, and every constructor inside a type. Red on: eleven fixtures referencing `Async::` across those positions, one referencing `DexpaceX::`, and a class/module pair the set cannot resolve; a comment mentioning `Async::Task`, and a file of generics and relative references, are the positive controls |
| `NFR-12` | SHOULD | ✅ build half (P0-7) | 17 | `gates:reproducible` builds each gem twice under a fixed `SOURCE_DATE_EPOCH` and compares SHA-256; every `spec.files` is a sorted `Dir.glob`, and `gates:gemspec_audit` refuses a gemspec that runs a subprocess, itself or through a `require_relative` helper — RubyGems sorts `spec.files` in its own reader, so the ordering a gemspec can break is the one that depends on `git ls-files`. Red on: a gemspec that reads the clock at build time; a gemspec whose file list comes from `git ls-files`, in its own text or in a helper it loads; a gemspec that does not load, named as such. The release half is `docs/first-release.md` § Release path |
| `NFR-13` | SHOULD | ✅ mechanised (P0-1) | 4 | `Dexpace/SpdxHeader`: line 1 frozen-string-literal, line 2 SPDX, line 3 blank, three separate messages. Red on: five header shapes. Scope is `.rb` only; `sig/**/*.rbs` is phase 10's inbound item (`docs/knowledge/notes/tooling-and-quality-gates.md`) |
| `NFR-14` | SHOULD | ✅ | 2, 19 | `VERSIONS` with its only parser `tools/versions.rb`; `gates:versions` asserts `.ruby-version`, the CI matrix, six gemspec versions and floors and six `version.rb` literals against it. Red on: a stale pin, a dropped matrix row, a literal ahead of `VERSIONS`, a gemspec that does not load |
| `NFR-15` | SHOULD | ✅ machinery | 5 | `VERSION = "0.0.0"` literal in every gem's `version.rb`, shipped in the gem, asserted equal to the gemspec by each smoke suite and by `gates:single_instance`. The User-Agent that reads it is later phases' |
| `NFR-16` | SHOULD | ⏳ | — | Owned by `docs/first-release.md` § Release path, the signed-publication entry: there is no release path to enforce signing on |
| `NFR-17` | MUST | ✅ machinery | 2, 6, 18 | Seventeen blocking gates in one default task; `default_task_test.rb` asserts the list, that every name is a real task, and that `rake default` depends on exactly them in order; `ci_workflow_test.rb` asserts every gate appears in a CI job and no job may fail |
| `SEAM-1` | MUST | ✅ mechanised | 8, 9, 10 | The three zero-dependency gates above; `dexpace-core.gemspec` has zero `add_dependency` lines and the audit asserts it |
| `SEAM-2` | MUST | ✅ mechanised at the require level | 9 | `json`, `net/http`, `net/protocol`, `open-uri`, `socket`, `resolv` and `timeout` are denied by name with the requirement in the message. `socket` alone carries the scope `dexpace-core` + `dexpace-transport-*` (the Task 9 amendment's case: the conformance gem's wire server); the other transport names, `json` and `timeout` bind every gem |

Nineteen rows: 14 ✅, 2 🚫, 1 ⏳ (`NFR-16`), and `SEAM-1`/`SEAM-2` mechanised. No row is N/A.

## The seventeen gates, and the run that proved them

`bundle exec rake` on Ruby 4.0.6, 2026-09-14, after the round-3 review repairs: **2 min 47 s
wall-clock**, all seventeen green in `DEFAULT_GATES` order — `rubocop` (82 files, no offenses),
`cops:test` (65 runs), `rbs:validate`, `steep` (24 files, no type error), `test:gems` (20 runs,
42/42 lines covered), `test:gates` (126 runs, 513 assertions), the nine `gates:*` tasks, `yard`
(100.00% documented, 9 modules, 6 constants), `bundler_audit` (no vulnerabilities). After the
round-2 repairs the same run was 2 min 51 s, 64 cop runs and 119 gate runs; after round 1, 2 min
45 s, 46 and 111; before them, 2 min 42 s, 41 and 100. Every subprocess a gate starts now runs
on the interpreter running `rake` (deviation 33), which this machine's shim made worth proving:
with the mise `ruby` (3.4.10) first on `PATH` and only the outermost `bundle` the 4.0.6 one,
`gates:clean_bundle`, `gates:surface_snapshot` and `gates:single_instance` ran on 4.0.6 and the
smoke script's own `RUBY_VERSION` assertion held.

The matrix set — `test:gems gates:gemspec_audit gates:require_allowlist gates:clean_bundle
gates:single_instance` — green on **3.2.11, 3.3.12, 3.4.10 and 4.0.6**, each with its own
`Gemfile.lock` resolved fresh. `gates:require_allowlist` reports `no BUNDLED_GEMS table on this
Ruby` on 3.2.11 and `22`, `28` and `23 bundled gems known` on the other three; the
`require_allowlist_test.rb` suite on 3.2.11 skips exactly the four cases that read a bundled-since
reason and still refuses `base64`, `logger` and `tsort`.

Tool versions resolved on 4.0.6: rake 13.4.2, minitest 5.27.0, rubocop 1.91.0, rubocop-minitest
0.40.0, rubocop-performance 1.27.0, rbs 4.2.0, steep 2.1.0, simplecov 1.3.0, yard 0.9.45,
bundler-audit 0.9.3, prism 1.9.0 (the parser behind the require audit; 1.9.0 on the 3.2.11 floor
too). The 3.2.11 floor resolves rbs 4.1.3, steep 2.0.0 and simplecov 1.2.0, which is why those
three `tool` constraints in `VERSIONS` sit at the floor's minor.

## Deliberately failing inputs: 103

The success criterion was at least fifty-six. Counted from the suites, one per input that turns
a gate red on demand (62 before the round-1 review repairs, 80 before the round-2 ones, 99 before
the round-3 ones; the eighteen, nineteen and four added are named in deviations 17–22, 25–31 and
32–34 below):

| Gate | Inputs | Where |
|---|---|---|
| `cops:test` | 45 | `.rubocop/test/cops_test.rb` `REJECTED`: 5 header shapes, 5 `Time`/`Date`/`DateTime.parse` (`Time&.parse` among them), 10 `URI` default-parser forms (`URI(...)`, `Kernel.URI`, `::Kernel.URI`, `URI&.parse` and two `URI::Parser` spellings among them), 8 case-fold forms (two safe-navigated), 13 thread-interrupt forms (five safe-navigated, three block-passed), 4 keyword splats (plus 20 accepted controls) |
| `gates:gemspec_audit` | 7 | `test/fixtures/gates/gemspec_audit/{extra_core_dependency,two_third_party,stale_constraint,wrong_floor,git_listed_files,helper_shells_out,does_not_load}` (plus `unsorted_files` as the control that RubyGems sorts `spec.files` itself) |
| `gates:require_allowlist` | 16 | `test/fixtures/gates/require_allowlist/{base64,logger,tsort,json,timeout,socket,net_http,escaping_relative,parenthesised,kernel_receiver,mid_line,autoload,parenthesised_relative,dynamic,interpolated}.rb` and the `workspace/` tree (plus `internal_relative.rb`, `allowed.rb`, `core_entry.rb` and `comment_only.rb` as controls) |
| `gates:clean_bundle` | 1 | a miniature workspace built at test time whose core requires `logger` |
| `gates:rbs_surface` | 12 | `test/fixtures/gates/rbs_surface/gems/fixture/sig/{foreign,superclass,mixin,mixin_argument,type_alias,class_alias,module_alias,generic_bound,method_bound,nested_positions,sibling_namespace}.rbs` and the `conflict/` pair (plus `comment_only.rbs` and `relative_and_generic.rbs` as controls) |
| `gates:sig_diff` | 6 | a scratch tagged repository: removed declaration, narrowed declaration, removed file, dropped overload on a continuation line, public method moved under a `private` section, public method given the `private` modifier (plus unchanged, reindented, reordered, one-line-overload and removed-private-method trees as controls) |
| `gates:surface_snapshot` | 2 | `DEXPACE_SURFACE_EXTRA` injects a constant inside a gem's namespace (`Injected`) or, `::`-qualified, beside one (`Dexpace::Transport::Shared`, landing in the two transports' trees) |
| `gates:versions` | 4 | `test/fixtures/gates/versions/{stale_pin,dropped_matrix_row,ahead_literal,gemspec_does_not_load}` |
| `gates:single_instance` | 3 | `DEXPACE_FORCE_DUPLICATE`; core's `lib/` copied to a second directory and preloaded through `RUBYOPT`; `test/fixtures/gates/single_instance/version_skew` |
| `gates:reproducible` | 1 | `test/fixtures/gates/reproducible/gems/clock_dependent` |
| `test:gems` warnings-fatal | 2 | `test/fixtures/gates/warnings/{before_override,after_override}.rb` |
| SimpleCov floor | 1 | an uncovered file written into `tmp/` |
| `yard` | 2 | `test/fixtures/gates/yard/{undocumented,header_only}.rb` |
| `rbs:validate` | 1 | `VERSION: Nonexistent::Type` |

Four gates carry no fixture of their own, for the design's stated reasons: `rubocop` runs the cops
`cops:test` proves; `test:gates` runs the fixtures above; `steep` is proven by Steep's own suite
and asserted wired, blocking and target-by-target; `bundler_audit` is asserted wired with
`--update` because its verdict depends on a live advisory database.

## Audit groups run

Per the roadmap's execution rules, the four groups the design named were re-run at the start of
implementation through `scripts/knowledge.rb`, and the phase-start pair was run first: all six
harvested conflicts print `[overridden by notes/…]`; `--origin note` returns the notes and nothing
open. The five notes the design filed during planning are unchanged by implementation — the
stdlib facts they rest on were re-derived on 4.0.6 as Task 1's first step (`+PRISM`, 23 entries in
`Gem::BUNDLED_GEMS::SINCE`, 46 default gems) and matched.

| Group | Result at implementation |
|---|---|
| Gem layout, zero-dependency core | Clean. Six gemspecs, core with no dependency, `~> 0.0` on every adapter, twelve-name allowlist verified to `require` on every matrix row |
| RuboCop and formatting | The plan's Task 3 amendment called for one reviewed diff; it is `.rubocop.yml` as committed. Per cop: `Layout/EmptyLineAfterMagicComment` off (the SPDX line occupies line 2; `Dexpace/SpdxHeader` owns line 3), `Style/DataInheritance` off (design §4's `class X < Data.define` idiom), `Minitest/MultipleAssertions` off (styleguide 11 counts behaviours and mandates pair-asserting), `Naming/RescuedExceptionsVariableName: error` (styleguide 08), `Metrics/ParameterLists` keeps `Max: 4` with `CountKeywordArgs: false` (`api-design/1d9e6e0b`; phase 4a's seven measured methods); `Metrics/AbcSize`, `CyclomaticComplexity`, `PerceivedComplexity`, `ClassLength`, `ModuleLength` left at defaults per styleguide 01 ("unless a specific exception is recorded") and the code was split to meet them; `Minitest/AssertPredicate`/`RefutePredicate` kept on, with the private-predicate case written with `respond_to?`. Hidden `.rubocop/` added to `Include` so the cops are themselves linted |
| RBS / Steep typing | Clean for this phase. rbs 4 ships `Set` under `core/`, so `set` is not a `library` line in the Steepfile; the workspace's own gems are `ignore: true` in `rbs_collection.yaml` because the collection resolves them from the lockfile and would load every signature twice |
| Minitest conventions | Clean. `test "..." do` on three base classes, `test/` mirrors `lib/`, expected before actual, seed never overridden, every suite runs alone (each was run alone before `test:gates` ran them together) |

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate.

1. **`rubocop_config_test.rb` scopes its no-autocorrect assertion to the `:rubocop` task block**,
   not the whole of `tasks/quality.rake` — the plan's Step 4 writes `rubocop:fix` (which
   autocorrects) into the same file its Step 1 test refutes `--autocorrect` over.
2. **`.rubocop.yml` excludes `scripts/**/*` and `.claude/**/*`** with the reason and re-enable
   condition in the file (303 of 310 measured findings were in four pre-existing process-tooling
   files that ship in no gem and carry their own `ruby -w` suites). Ledger row P0-11. It also adds
   `.rubocop/**/*.rb` to `Include`, since RuboCop skips hidden directories and would otherwise
   never lint the cops.
3. **`run_suite` lives in `tools/suite_runner.rb`** (`SuiteRunner.run`) rather than as a global
   method in `tasks/quality.rake`, so the stderr scan is unit-testable — and the warnings fixture
   is **two files**, one warning before the override loads (caught only by the scan) and one after
   (caught by the override), because the plan's single fixture required the test case first and so
   proved only the override. `-rsupport/coverage` is passed only when `coverage:` is requested.
4. **The smoke suites snapshot the namespace around the `require`.** The plan's
   `assert_equal(%i[VERSION], Dexpace.constants(false).sort)` fails under `test:gems`, where all
   six gems load in one process and `Dexpace` also holds `Serde`, `Transport`, `Async` and
   `Conformance`. Each suite asserts instead that its entry file added nothing top-level but
   `Dexpace` and nothing under `Dexpace` but its own namespace (or `VERSION`, for core) — and,
   since deviation 32, nothing beside its own namespace either.
5. **`test/support/coverage.rb` uses `cover`/`skip`/`merging false`**, not the plan's
   `track_files`/`add_filter`, which SimpleCov 1.3 deprecates; both API names exist on the 1.2.0
   the floor resolves. `merging false` was found necessary: the negative fixture's resultset was
   merged into the next `test:gems` run and reported as a missing source file.
6. **Three `DEXPACE_GATE_ROOT`-style switches were added** — `DEXPACE_GATE_ROOT` (gemspec_audit,
   require_allowlist, rbs_surface, sig_diff, versions, reproducible, single_instance),
   `DEXPACE_YARD_FILES` — beside the plan's `DEXPACE_CLEAN_BUNDLE_GEM`, `DEXPACE_FORCE_DUPLICATE`
   and `DEXPACE_SURFACE_EXTRA`, so each gate's *task* is watched to go red, not only the tool
   behind it. Several fixtures are therefore laid out as miniature workspaces (`gems/<x>/…`).
7. **Extra fixtures beyond the plan's list**: `gemspec_audit/wrong_floor` (the audit's
   `required_ruby_version` check had no fixture), `require_allowlist/socket.rb` plus the scope
   pair (the Task 9 amendment), `single_instance/version_skew` (the design says the VERSION half
   "can fail today"; now it is seen to), `rbs_surface/comment_only.rbs`, `warnings/clean.rb` and
   `require_allowlist/allowed.rb` as positive controls.
8. **`gates:reproducible`'s negative case is a clock-dependent gemspec, not a touched mtime.**
   `gem build` writes every tar entry's mtime as `Gem.source_date_epoch`, so under the fixed epoch
   the gate always sets, the plan's "unnormalised build" cannot differ by timestamp; the test pins
   that fact and proves sensitivity with a gemspec that reads the clock. What the epoch falls back
   to when the variable is *unset* is RubyGems' business and differs across the matrix: from
   RubyGems 3.6 (the 3.4 and 4.0 rows) it is the fixed `Gem::DEFAULT_SOURCE_DATE_EPOCH`,
   1980-01-02; on 3.4.19 and 3.5.22 (the 3.2 and 3.3 rows) `Gem::DEFAULT_SOURCE_DATE_EPOCH` is
   undefined and the fallback is `Time.now`, memoised per process, so two `gem build` subprocesses
   a second apart differ. As first written this deviation claimed the fixed fallback for every
   supported Ruby; the round-1 review measured otherwise on 3.2.11 and 3.3.12, and the test now
   asserts the unset case only where `Gem::DEFAULT_SOURCE_DATE_EPOCH` is defined and skips with
   the reason elsewhere. Design reading P0-7 is unaffected: the gate sets the epoch.
9. **`tools/surface.rb` walks `Data.define`-generated readers and public singleton methods.** The
   Task 14 amendment asked for a decision; this is the first of its two repairs, so the gate's
   stated rationale ("catches what RBS cannot see") stays true rather than being narrowed in two
   documents. Pinned by an in-process fixture. Descent is relative to the walked root, not to a
   hard-coded `Dexpace` — and the root every gem's subprocess walks is `Dexpace` itself, since
   deviation 32.
10. **`rbs:validate` runs with `--no-collection`** and adds core's `sig/` for each adapter. With
    the collection lock present, `rbs validate` otherwise loads every gem in the dev bundle,
    including SimpleCov's own broken shipped signature.
11. **`rbs_collection.yaml` lists the six workspace gems as `ignore: true`** rather than the plan's
    `gems: []`: the collection resolves them from `Gemfile.lock` and loaded every signature twice
    (`RBS::DuplicatedDeclaration` on all six `VERSION`s). The Steepfile drops `set` from core's
    `library` line — rbs 4 ships `Set` under `core/`, and naming it is an `UnknownLibraryError`.
12. **`typing_test.rb` asserts the lockfiles are untracked (`git ls-files`), not absent**: the
    plan's `refute_path_exists` fails on any machine that has run `rake steep`. The malformed
    signature fixture gained its missing `end` (a parse error would have hidden the type error the
    test names), and the sigil scan matches `# typed:` at column 0 only.
13. **`yard_test.rb`'s direct fixture cases pass `--no-yardopts --no-save`**: `.yardopts`'
    `--exclude test/` would otherwise drop the fixture and report the gems. `ci.yml` has no separate
    `rbs collection install` step — the `steep` task runs it.
14. **`.gitignore` gained only the three entries not already present** (`/Gemfile.lock`,
    `/.gem_rbs_collection/`, `/rbs_collection.lock.yaml`); the plan's block repeated six ignores
    the file already carried.
15. **`.rubocop.yml` sets `SuggestExtensions: false`**: the plugin set is fixed by the note the
    file cites, and a per-run tip proposing more is noise in a gate.
16. **Task 1's shim check.** `ruby -v` through the mise shim reports 3.4.10 on this machine
    regardless of `.ruby-version` (the user's mise has no idiomatic-version-file support enabled,
    and the shims are not this repository's to configure). Every run above went through the
    interpreter's own `bin/` on `PATH`, which is what `ruby/setup-ruby` does in CI; the pin file is
    correct and `gates:versions` asserts it.

The eight below were made after the round-1 review of the three branches, on 2026-09-14, each
against a finding that a gate accepted an input the design says it must refuse. None narrows a
gate; every one is a fixture the gate now refuses and did not before.

17. **The require audit parses; it does not match lines.** The plan's Task 9 prescribed
    `^[ \t]*require[ \t]+["']…`, which sees a bare `require` at the head of a line and nothing
    else: `require("json")`, `Kernel.require "json"`, `x = 1; require "timeout"`,
    `autoload :JSON, "json"` and `require_relative("../../../Rakefile")` all scanned clean, and for
    the `SEAM-2` denylist names nothing else in the gate set backstopped the scan (they are default
    gems on every matrix Ruby, so `gates:clean_bundle` accepts them). `tools/require_scan.rb` now
    walks Prism call nodes for every `require`, `require_relative` and `autoload` whose receiver is
    nothing, `self`, `Kernel` or `::Kernel`; a comment naming a feature is not a require, and a
    feature that is not a string literal — a variable, an interpolation, a `File.join` — is refused
    as unreadable rather than passed. `prism` is a declared `tool` line in `VERSIONS` (it is a
    default gem only from 3.3, and the bundle carried it only through rubocop-ast). The message now
    names the line. A require reached through `send`, `method` or `eval` is not a spelling and stays
    a review matter, as design §4's P8 says of the constructor.
18. **`gates:single_instance` keys its tally on the feature, not the resolved path.** Ruby's
    `require` never records one path twice, so the design's own fixture row — "two resolved paths
    for one core feature", a vendored copy beside a gem-installed one — passed with a message saying
    it had not; only the gate's `DEXPACE_FORCE_DUPLICATE` switch reddened it. The tally now groups
    `$LOADED_FEATURES` by the path after `/lib/`, and the second fixture is real: core's `lib/`
    copied to a second directory and preloaded through `RUBYOPT=-r`, which yields two paths for each
    of `dexpace.rb` and `dexpace/version.rb`. The forced-duplicate switch stays as the first.
19. **`Dexpace/NoUriDefaultParser` flags `URI(...)` and `Kernel.URI(...)`.** `Kernel#URI` is
    `URI.parse(uri)` for a String argument (`uri/common.rb`), which routes through
    `URI::DEFAULT_PARSER` — the most common spelling of the parse design §3.5 bans, and the cop's
    matcher saw only the `URI.` constant receiver. Three rejected rows and two accepted controls
    (`URI::RFC3986_PARSER.join`, `URI::HTTP.build`) were added to `cops_test.rb`.
20. **`gates:sig_diff` compares parsed declarations, not declaration lines.** A method type
    written across overload continuation lines (`| (URI url) -> String`) matched no declaration
    pattern, so dropping the overload left `before - after` empty; and a `private` line is not a
    declaration, so moving a public `def` under it changed no compared line. Ruby has no overloads
    for `gates:surface_snapshot` to catch the first. `SigDiff::Surface` now flattens each parsed
    signature to one line per public declaration with its full constant path — one per overload,
    one per receiver of a `self?.` method, `private` sections and `private def` honoured, class and
    module aliases included — and compares per gem, `NFR-4`'s unit, so a declaration moved between
    two signature files of one gem is not a break. The "signature file removed" case is kept as its
    own report. Reindenting, reordering, commenting, rewriting an overload on one line and removing
    a private method are all clean, and the suite asserts each.
21. **`gates:rbs_surface` reads a class or module alias, and a mixin's type arguments.** The six
    extractors read `type`, overloads, superclass, mixin name, self-types and generic bounds, and
    none of them `RBS::AST::Declarations::ClassAlias#old_name`, so `class Runner = Async::Task`
    inside `Dexpace::` — the `NFR-11` leak in its most direct form — scanned clean; nor did a mixin's
    arguments, so `include Enumerable[Async::Task]` did too. Both are read now, with a fixture each,
    which is why the design's "five positions" is six as built.
22. **`gates:gemspec_audit` refuses a gemspec that runs a subprocess.** The design lists "`spec.files`
    is produced by `Dir.glob(...).sort` and not by shelling out to `git ls-files`" among the audit's
    assertions and the plan dropped it. Building it found that RubyGems sorts `spec.files` in its
    own reader (`Specification#files`, on every matrix Ruby), so sortedness is not a property a
    gemspec can lose and an assertion of it would pass over nothing; what a gemspec can lose is
    independence from git, which lists nothing in a `.gem` built from a source export. The audit
    parses each gemspec and refuses a backtick, a `%x`, or a `system`/`spawn`/`popen`/`capture*`
    call; `git_listed_files` is the fixture and `unsorted_files` the control that loads sorted.
23. **The clean-bundle negative names its condition.** `logger` is a default gem on 3.2 and 3.3, so
    the scratch bundle loads it there and the negative could only fail; the case now skips, with the
    reason, on any Ruby where `Gem::BUNDLED_GEMS::SINCE` does not put `logger` at or below the
    running version, which keeps "the gate suites are interpreter-independent" true on the floor.
24. **The reproducible suite's unset-epoch half is guarded**, as deviation 8 above now records.

The seven below were made after the round-2 review, on 2026-09-14. Four are gates that accepted an
input the design says they must refuse; three are the review's nits, taken because each was a
one-token or one-fixture change in the strict direction. None narrows a gate over anything a gem
ships.

25. **The four ban cops see a safe-navigation call.** RuboCop delivers `a&.m` as a `csend` node,
    and `NoThreadInterrupt`, `NoLocaleCaseFold`, `NoTimeParse` and `NoUriDefaultParser` defined
    only `on_send` (as the plan's Task 4 code does), so `@thread&.kill` in a `close` — the ordinary
    spelling of the design §8.3 ban, and exactly where an interrupt lands inside an `ensure` — and
    `name&.downcase(:turkic)` (`HTTP-13`) passed the lint gate, with nothing else in the gate set to
    catch them. Each cop now aliases `on_csend` to `on_send` and its node patterns accept either
    node. `NoThreadInterrupt` also flags `threads.each(&:kill)` and `(&:terminate)`, the block-pass
    spelling with no receiver for its name match to see; `sockets.each(&:close)` is the control.
    Thirteen rejected rows and five accepted controls, every rejected one confirmed failing on the
    previous cops.
26. **`Dexpace/NoUriDefaultParser` flags `URI::Parser`.** It is `URI::RFC2396_Parser` on 3.2 and
    3.3 and `URI::RFC3986_Parser` from 3.4 — the same straddle of the floor as `DEFAULT_PARSER`,
    under another name — and the constant matcher saw only `DEFAULT_PARSER`. `URI::RFC2396_Parser`
    and `URI::RFC2396_PARSER` name a grammar explicitly and are the accepted controls.
27. **`gates:rbs_surface` resolves type names before it compares them.** The scan matched constant
    paths in each node's `to_s`, which renders a signature as written, so a generic parameter `T`
    and a relative `Headers` inside `module Dexpace` — the normal RBS style, and what `rbs validate`
    accepts — were reported as foreign; the gate was green only because the six signatures hold
    nothing but `VERSION: String`, and phase 1's first `def headers: () -> Headers` would have turned
    it red with no honest fix but qualifying every reference. The paths are now loaded into one
    `RBS::Environment` and resolved with `resolve_type_names`, the absolutisation `rbs validate`
    performs, so a relative Dexpace type becomes `::Dexpace::Headers` and a name declared nowhere in
    the set stays as written; each type tree is then walked constructor by constructor, collecting
    `ClassInstance`, `ClassSingleton`, `Alias` and `Interface` names and skipping `Variable`. A
    method-level bound `[T < Async::Task]` reports `Async::Task` and not `T`; `Dexpace` is matched
    exactly or as a `Dexpace::` prefix, so `DexpaceX::Thing` is foreign; and a set the environment
    cannot resolve — a class and a module of one name across two files — is reported as a violation
    rather than raised, since a set the scan cannot read is one it cannot vouch for. The `superclass`
    fixture took its own name for that reason: the fixture tree now resolves as one set. Deviation
    21's "six positions" reads as "every position in the resolved tree" from here.
28. **`Dexpace/NoKeywordSplat` is scoped to `gems/*/lib/**/*.rb`**, as the plan's Task 4 amendment
    states it, where the round-1 branches had enabled it repository-wide without recording the
    widening. `OBS-25` and `OBS-1` are allocation assertions on the SDK's own no-op paths; a test
    helper's or a tool's `**opts` is not one. The cop's docstring now states the scope.
29. **The require allowlist accepts `require "dexpace"`.** `reachable?` accepted only the `dexpace/`
    prefix, so an adapter's require of core's own entry point — which every adapter will write the
    moment it has code, and whose gemspec already declares the dependency — was refused as not
    allowlisted. One token, and `core_entry.rb` is the control.
30. **Only `socket` carries the transport denial's scope.** A scoped-out denial is an implicit
    permission for every gem outside the scope, and one scope covered five names, so
    `dexpace-serde-json`, `dexpace-async-thread` and `dexpace-conformance` could require `net/http`,
    `net/protocol`, `open-uri` and `resolv` with none allowlisted. The case the Task 9 amendment
    and phase 8a's `P8-14` argued is the conformance gem's wire server and `socket`; that name keeps
    the `dexpace-core` + `dexpace-transport-*` scope, and the other four bind every gem
    (`net_http.rb`, refused for core, a transport, `serde-json` and `conformance` alike). What
    remains is that a gem outside the scope may require `socket`, which is what the amendment's own
    pair test asserts.
31. **`gates:gemspec_audit` follows `require_relative`.** The subprocess check parsed the gemspec
    file alone, so a helper that shells out on the gemspec's behalf — the pattern the six gemspecs
    already use for `tools/versions` — kept the gemspec's own text clean. The audit now follows
    every literal `require_relative` transitively from the gemspec and names the file that shells
    out; `helper_shells_out` is the fixture.

The three below were made after the round-3 review, on 2026-09-14: one gate that accepted an
input `NFR-4` says it must refuse, and the review's nits, taken because each was a one-line
change in the strict direction or a fact the gates rest on. None narrows a gate.

32. **`gates:surface_snapshot` walks `Dexpace`, not each gem's own constant.** The plan's Task 14
    script printed `Surface.manifest(<the gem's constant>)`, so an export an adapter placed
    *beside* its namespace — `Dexpace::Transport::Shared`, a method on `Dexpace::Transport`, a
    constant directly under `Dexpace` — was in no manifest: core's is produced in a process that
    never loads the adapter, and the adapter's never looked above its own constant. Verified red
    on none of the three before the repair and on all three after. Every subprocess now walks
    `Dexpace`; an adapter's manifest is `Surface.contribution` — the lines its entry file adds,
    measured around the `require` with core loaded first — so core's lines are in core's
    manifest only and a change to core regenerates one manifest rather than six. The manifest
    renders **one line per method** (`Dexpace::Foo#call`, `Dexpace::Foo.build`) rather than one
    per module, so that the subtraction is a set difference even when an adapter adds a method to
    a module core already populates, and a drift message names the one method that moved.
    `DEXPACE_SURFACE_EXTRA` accepts a `::`-qualified owner, injected in each subprocess that
    defines it; the six manifests were regenerated (each adapter's now begins at the namespace it
    shares, `Dexpace::Transport`, `Dexpace::Serde` or `Dexpace::Async`), the suite pins the root,
    the sibling case and the subtraction, and the four adapter smoke suites snapshot their
    intermediate namespace around the `require`, so the same sibling fails `test:gems` too.
33. **Every subprocess the build starts runs on the interpreter running `rake`.** `tools/`,
    `tasks/` and `test/support/` spelled `ruby`, `gem` and `bundle` as bare names, resolved from
    `PATH` — harmless in CI, where `ruby/setup-ruby` puts the matrix interpreter first, and wrong
    exactly on this machine, where deviation 16 records that the mise shim reports 3.4.10 whatever
    `.ruby-version` says: `gates:clean_bundle`, `gates:surface_snapshot`, `gates:single_instance`,
    `test:gems`, `test:gates` and `gates:reproducible` could run on one Ruby and report another,
    and the 4.0 row is the one the bundled-gem refusal needs. `tools/interpreter.rb` names the
    running interpreter's own `ruby` (`RbConfig.ruby`) and the `gem` and `bundle` wrappers beside
    it in `bindir`; every subprocess goes through it, and the clean-bundle smoke script asserts the
    `RUBY_VERSION` it landed on equals the parent's. Plan-inherited: Tasks 6, 11, 14 and 17 spell
    `"ruby"` too.
34. **Three nits, each a one-line change.** `Dexpace/NoThreadInterrupt`'s block-pass matcher names
    `:exit` beside `:kill` and `:terminate` — `Thread#exit` is `Thread#kill` under another name
    and was already in `INTERRUPTS`; `threads.map(&:exit)` is the rejected row. `Reproducible`
    passes `"SOURCE_DATE_EPOCH" => nil` for the unset case, which unsets the variable for the
    subprocess where an empty env hash inherited whatever the developer's shell exported; the
    suite exports the gate's own epoch and proves an unset build does not see it. A gemspec that
    raises while evaluating loads as `nil` under `Gem::Specification.load`, and both
    `gates:gemspec_audit` and `gates:versions` now name the file (`does_not_load`,
    `gemspec_does_not_load`) rather than failing through a `NoMethodError` on `nil`.

## Findings routed

- **`sig/**/*.rbs` carry no SPDX header and no gate reaches them** — already phase 10's inbound
  item (`docs/knowledge/notes/tooling-and-quality-gates.md`, `## Superseded`). Nothing to add.
- **`scripts/` and `.claude/skills/` are outside the RuboCop baseline** — recorded in
  `.rubocop.yml` with its re-enable condition and as ledger row P0-11. Bringing the process
  tooling under the baseline is a change of its own; it is not a phase's product, so it is routed to
  phase 10's inbound list in the roadmap rather than to any build phase.
- **`docs/deviations.md` rows 7 and 19** describe mechanisms phase 0 now ships (the stdlib
  narrowing; the `NFR-8`/`NFR-9` retarget). Flipping them from `design only` is phase 10's method
  (re-derive from as-built source), so they are left as they stand.
- **Phase 8a's plan quotes the require audit's planned line-matching shape** (its `P8-14` step,
  `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance.md`) —
  already superseded by the Task 9 amendment's scoped denials before this round, and now by the
  parsed scan (deviation 17) and by the scope's narrowing to `socket` alone (deviation 30), which
  is exactly `P8-14`'s case. That plan is phase 8a's to reconcile when it executes against the
  as-built tool; nothing in it is load-bearing for phase 0.

## Postponed work

The four items phase 0 postponed are recorded in the design's "Work Phase 0 Postponed, and Who
Owns It Now" section with their owners, and were re-checked on 2026-09-14: `docs/first-release.md`
still carries the signed-publication entry under § Release path (`NFR-16`) and the
Steep-target-over-a-`test/`-tree entry under § Post-release triggers; phase 2 built the runtime
version-skew half; phase 8a and phase 9 own the conformance assertion objects. The
implementation postponed nothing further.
