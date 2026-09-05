# Phase 0 — Scaffold and Quality Gates

**Status:** Draft, approved for planning.

## Purpose

Phase 0 builds the workspace every later phase is written inside, and the gate set every later
phase is written under. It ships no domain code and satisfies no behavioural requirement. What it
ships is a repository in which the next nine phases cannot quietly do the wrong thing: a root
build that runs every gate in one command, six gem skeletons with real gemspecs, and seventeen
blocking checks — three of which exist only because Ruby's standard library shrinks between
releases and a zero-dependency core is otherwise a claim nobody can test.

The ordering rationale in `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` states the
reason the gem skeletons are here rather than deferred to the phase that first fills one: the
gemspec audit, the require-allowlist audit and the clean-bundle isolation run "are only proven
when they run against the artifact they are supposed to check." A gate standing over an empty
directory is a gate nobody has seen fail. So every gate that can be given a failing input gets
one, and the phase's own success criterion is that **fifty-two such inputs each turn a gate red
on demand.** Thirteen of the seventeen gates carry at least one of their own; the Testing section
below is the list, one row per gate, and it says for each of the remaining four — `rubocop`,
`test:gates`, `steep` and `bundler_audit` — why a fixture there would prove nothing.

Two things phase 0 explicitly does **not** do. It does not close any `NFR` requirement — `NFR-1`
through `NFR-17` are stood up here as machinery and dispositioned in phase 9, which is the
roadmap's own division. And it does not lower, disable or narrow any gate to make an empty tree
pass; where a gate is vacuous today the design says exactly what makes it non-vacuous and when,
rather than switching it off and leaving a comment.

## Governing documents

Five, in the roadmap's own order, all binding here:

- `docs/product-spec/20-non-functional-requirements-and-quality-bar.md` — the normative source of
  `NFR-1`–`NFR-17`, and `docs/product-spec/03-pluggable-seams-and-extension-model.md` for
  `SEAM-1` and `SEAM-2`. `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`
  is the ID index.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.1 (the six MVP gems), §2.3 (the layout
  and the `VERSIONS` file) and §2.4 (the zero-dependency invariant and what "standard library"
  means in Ruby); `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md` in full — its gate
  table, §9.1's API-surface lock, §9.2's three zero-dependency checks and §9.3's Minitest choice.
- The Ruby styleguide, `styleguide/ruby/`, chapters `01-formatting-and-tooling.md`,
  `11-testing.md`, `12-module-organization.md` and `14-documentation.md`, queried through the
  corpus rather than read wholesale. Binding except where a note under `docs/knowledge/notes/`
  records otherwise — and this phase files five such notes, listed below.
- `CLAUDE.md` — the hard rule on what core may `require`, the requirement-ID conventions, and the
  ban list under "Constraints that will bite" that this phase mechanises.
- `docs/README.md` — the ownership table and the `docs/work/` naming rules.

## Scope

### Requirement IDs in scope

**`NFR-1` through `NFR-17`, all seventeen, as machinery only.** Every gate the design §9 table
names is built and wired into the default Rake task here; none is dispositioned here. Phase 9
(`Cross-Cutting Invariants and Conformance`) owns the checklist rows that say whether each is
satisfied. Phase 0's checklist rows therefore record *the gate that will answer the question*,
not the answer.

The seventeen split three ways by what phase 0 can actually do to them:

| Disposition in phase 0 | IDs | What phase 0 ships |
|---|---|---|
| Gate built and **firing** on real inputs today | `NFR-1`, `NFR-2`, `NFR-6`, `NFR-7`, `NFR-10`, `NFR-12`, `NFR-13`, `NFR-14`, `NFR-15`, `NFR-17` | A check with a failing fixture proving it fires against the six gem skeletons |
| Gate built and **armed but not yet load-bearing** — it passes because there is nothing to catch, and becomes load-bearing without a code change | `NFR-3`, `NFR-5`, `NFR-11` | RBS signatures, the SimpleCov floor, the foreign-constant scan. Each has a failing fixture; each is green on the real tree because the real tree is two constants per gem |
| Gate built with a **stated pre-release branch** | `NFR-4`, `NFR-16` | The `sig` diff has no baseline until the first `v*` tag exists; signing has no release path to enforce on. Both are described below, and `NFR-16` is deferred |
| **Retargeted by design §9.2 and §10 item 19** | `NFR-8`, `NFR-9` | Ruby has no whole-program shrinker. `NFR-8` exempts itself by its own text; the retarget is the require-allowlist audit and the clean-bundle run |

**`SEAM-1` and `SEAM-2`**, the two seam requirements the gem layout itself touches. `SEAM-1`'s
dependency audit *is* the gemspec assertion (§2.4: "that test *is* the **SEAM-1** dependency
audit; there is no scope declaration to lean on instead"), so it is mechanised here even though
phase 2 owns the seam chapter. `SEAM-2`'s "the core MUST NOT reference any concrete
implementation of a seam by name" is what puts `json`, `net/http` and `socket` on the require
**denylist** below, alongside the bundled-gem trap. No other `SEAM` ID is in scope; `SEAM-3`
through `SEAM-30` are phase 2's, and `SEAM-22`/`SEAM-28` — the two the corpus cannot answer — are
phase 2's reading budget, not this phase's.

**SPDX carries exactly one ID, and it is `NFR-13`.** The brief anticipated an `XCUT` counterpart;
there is none. `grep -niE 'spdx|license header'` over appendix C returns the single `NFR-13` row,
which is SHOULD-level and which the reference enforces "as a review convention rather than a
mechanical gate" (`tooling-and-quality-gates/d43d1b03`). This port enforces it with a custom
RuboCop cop, which is a strengthening and is recorded in the Deviation Ledger.

### Out of scope, explicitly

No `HTTP`, `IO`, `BODY`, `CTX`, `PIPE`, `RECOV`, `RETRY`, `REDIR`, `AUTH`, `PAGE`, `SSE`, `SERDE`,
`OBS`, `CFG`, `TRANSPORT`, `ASYNC` or `XCUT` requirement is in scope. The segmentation rule in the
roadmap does not reach this phase — "Phase 0 carries no requirement scope, so the rule does not
reach it" — so there is no segmentation design and no sub-phase.

The conformance suite itself is out of scope. Phase 0 creates `gems/dexpace-conformance` as a
skeleton because the roadmap's phase-0 row lists all six MVP gems; phase 8 owns that gem's
gemspec, its version and its first release, and phase 9 adds the remaining suites. What phase 0
lays is the test-directory convention and one shared test case class, not an assertion object.

## Prerequisite

**None.** Phase 0 is the first phase; nothing precedes it. `docs/work/mvp/` holds only the v1
roadmap, `gems/` does not exist, and there is no `Gemfile`, `Rakefile`, `Steepfile` or
`.rubocop.yml` to build on. Every file this phase names is a file it creates.

The one dependency that runs the other way is worth stating: phases 1 through 10 each inherit
this phase's gate set from their first line, so a gate this phase gets wrong is a gate nine
phases are written under. That is the reason for the failing-fixture discipline in Testing below.

## Corpus reading, and what it settled

The phase-start pair was run before anything here was written.
`ruby scripts/knowledge.rb --section conflicts --brief` returns six styleguide-versus-design
conflicts and **all six print `[overridden by notes/…]`**; none is open, so this phase inherits
six settled decisions rather than owning any of them. `--origin note --brief` returns the same
six notes and nothing else.

`ruby scripts/knowledge.rb --gaps NFR,SEAM`: `NFR` is 17 of 17 substantive with zero gaps, so
this phase reads the specification through the corpus rather than directly. `SEAM` has two
uncited IDs, `SEAM-22` and `SEAM-28`, and **neither is in this phase's scope** — both are phase
2's reading budget. **This phase therefore budgets no direct specification reading.**

Four audit groups from the `knowledge-lookup` skill's table were run in full, because phase 0 is
where the styleguide-derived areas that carry no requirement ID first bind:

| Audit group | Result |
|---|---|
| *Gem layout, zero-dependency core* — `--topic package-and-dependency-layout --section rules,constraints` and `--prefix SEAM --section rules` | Clean. Every rule is either adopted verbatim or already resolved by `package-and-dependency-layout/35a6cd13` and `/9ca4d273`. One correction filed: see the bundled-gem note below |
| *RuboCop and formatting* — `--chapter 1 --section rules` and `--topic tooling-and-quality-gates --section rules` | Two rules with no note: `tooling-and-quality-gates/f37d7536` and `/e00c3fc5`. One rule resolved only by inference from another topic: `formatting-and-tooling/82fd4af5`. Three notes filed |
| *RBS / Steep typing* — `--chapter 3 --section rules` and `--topic type-system,data-modeling --section rules` | Clean for this phase. Every Sorbet-conditional rule is resolved by `type-system/169c8f38` and `data-modeling/677b01de`. `type-system/4a058b71` (`T::Enum` for closed domain sets) has no replacement named and is **routed to phase 1**, which owns the domain model |
| *Minitest conventions* — `--chapter 11 --section rules` and `--topic testing,assertions --section rules` | Two rules with no note: `assertions/df75bd2e` and `testing/de6fe7e3` (with `testing/79254878` in the same family). Two notes filed. `testing/180b5f41`'s `test "..." do` form needs a helper Minitest does not ship; phase 0 builds it |
| *Public API surface* — `--topic api-design,http-domain-model,documentation,module-organization,error-handling --section rules` | Run because phase 0 builds `NFR-3`/`NFR-4`/`NFR-11`'s machinery even though it exports almost nothing. Clean for this phase, with two rules routed onward and one already answered. `documentation/80beb95e` ("YARD-document every public class and every public method") is what the `yard stats --list-undoc` gate mechanises, and `documentation/42d8cbf4` ("never restate a `sig`'s type information") governs the two YARD blocks this phase writes. `api-design/3279c12e` (a Sorbet `sig` on every public method) is Sorbet-conditional and already resolved by `type-system/169c8f38`. Routed onward, with no phase-0 obligation because phase 0 ships no domain code: `error-handling/51261878` (one project-level base exception with domain trees hanging off it) and `error-handling/75571c73` (`Assert::InvariantViolation` for programmer errors) go to **phase 1** alongside `assertions/df75bd2e`; `api-design/948e4368`'s deprecation protocol is what `gates:sig_diff` will enforce once a release exists, so it goes with `DEF-20`. `documentation/ff82e7b7`'s `# TODO(Full Name):` format has no cop and no TODO to police yet; recorded here rather than mechanised |

**Five notes were filed against the corpus by this phase**, before the plan was written, because
a resolution recorded only in a design document is re-litigated by whoever reads the corpus next:

- `docs/knowledge/notes/tooling-and-quality-gates.md`, key `tooling-and-quality-gates/f638625d` —
  no committed `Gemfile.lock`, no `bundle install --frozen`. Resolves
  `tooling-and-quality-gates/f37d7536` and `/e00c3fc5`.
- `docs/knowledge/notes/formatting-and-tooling.md`, key `formatting-and-tooling/840bbd43` —
  the file header is `# frozen_string_literal: true` then `# SPDX-License-Identifier: MIT`;
  there is no `# typed:` sigil to place second. Resolves `formatting-and-tooling/82fd4af5`.
- `docs/knowledge/notes/testing.md`, key `testing/f8994c72` — `# typed: strict` applies
  nowhere, test files included, and `srb tc` is not a suite here. Resolves `testing/de6fe7e3`
  and `testing/79254878`.
- `docs/knowledge/notes/assertions.md`, key `assertions/e8c05720` — the production assertion
  primitive is the domain model's own shared validation helper, landing in phase 1; phase 0
  ships no production assertions.
  Resolves `assertions/df75bd2e`.
- `docs/knowledge/notes/package-and-dependency-layout.md`, `## Superseded`, key
  `package-and-dependency-layout/70fbcaee` — the Ruby 4.0 bundled-gem list, re-verified against
  a real 4.0.6 interpreter. Supersedes
  `package-and-dependency-layout/934983a1` and corrects `/a50018cc`. This one is `## Superseded`
  rather than `## Conflicts` because it is not two documents disagreeing: it is one verified fact
  that has moved, and following the harvested version would build a wrong allowlist.

### The verified stdlib facts this phase is built on

The harvested facts were verified on Ruby 3.4.10 only, when the 4.0 column of
`Gem::BUNDLED_GEMS::SINCE` was still a forward-looking table. Ruby 4.0 has since shipped, so they
were re-verified on 2026-09-05 against three installed interpreters — 3.2.11, 3.4.10 and 4.0.6
(`ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +PRISM`). The require-allowlist depends on these
directly, so they are recorded here rather than left to be re-derived:

`Gem::BUNDLED_GEMS::SINCE` on **4.0.6** holds 23 entries, not the six the harvested entry implies:

| Bundled since | Names |
|---|---|
| 3.3.0 | `racc` |
| 3.4.0 | `abbrev`, `base64`, `bigdecimal`, `csv`, `drb`, `getoptlong`, `mutex_m`, `nkf`, `observer`, `resolv-replace`, `rinda`, `syslog` |
| 4.0.0 | `benchmark`, `fiddle`, `irb`, `logger`, `ostruct`, `pstore`, `rdoc`, `reline`, `win32ole` |
| 4.1.0 | `tsort` |

Four consequences, each load-bearing for a check below:

1. **`tsort` is a trap that today's rule does not catch.** It is a default gem on every Ruby in
   the supported range, so an allowlist derived from "default on the highest Ruby in the matrix"
   admits it — and it leaves the default set at 4.1, one release beyond the range. The allowlist
   is therefore filtered against the whole `SINCE` table, not against the supported range.
2. **`Gem::BUNDLED_GEMS::SINCE` is undefined on Ruby 3.2.11.** The audit cannot read it on the
   floor interpreter, which makes design §9.2's "the *highest* Ruby in the matrix" a hard
   constraint rather than a preference.
3. **`set` stops being a gem at 4.0.** `Set` is a core class there — `Set.instance_method(:add)
   .source_location` is `nil` — while `require "set"` still succeeds as a no-op. `pathname` and
   `cgi` move the other way, from default gem on 3.2/3.4 to non-gemified stdlib on 4.0. So
   category membership is not stable across the range and the allowlist cannot be a category
   query; it is a name list, cross-checked by require-ability.
4. Default-gem counts across the range: **3.2.11 ships 71, 3.4.10 ships 58, 4.0.6 ships 46.**
   Forty-four names are default on all three and bundled on none. Eight names are non-gemified
   stdlib on all three: `coverage`, `expect`, `mkmf`, `monitor`, `objspace`, `ripper`, `rubygems`,
   `socket`.

## Module Layout

Every file phase 0 creates. Nothing here is a placeholder; a file listed is a file with content
that a gate reads.

### Repository root

```
.ruby-version                     4.0.6 — the highest Ruby in the matrix
.gitattributes                    *.rb text eol=lf, and the binary/LF boundary
.editorconfig                     2-space, final newline, no trailing whitespace
.gitignore                        += Gemfile.lock, rbs_collection.lock.yaml, coverage/, tmp/
VERSIONS                          NFR-14's single source of truth
Gemfile                           the development toolchain and six path references
Rakefile                          the default task: the whole gate set (NFR-17)
Steepfile                         six named targets, core strict
rbs_collection.yaml               empty `gems:` in phase 0; the lock is not committed
.rubocop.yml                      the cop set, the metric caps, the five custom cops
.yardopts                         YARD options shared by the doc task and the gate
.rubocop/cops/dexpace/spdx_header.rb
.rubocop/cops/dexpace/no_time_parse.rb
.rubocop/cops/dexpace/no_uri_default_parser.rb
.rubocop/cops/dexpace/no_locale_case_fold.rb
.rubocop/cops/dexpace/no_thread_interrupt.rb
.rubocop/test/cop_case.rb         the Minitest harness for a cop
.rubocop/test/cops_test.rb        one data-driven suite over all five cops
tools/versions.rb                 the only parser of VERSIONS; every gemspec loads it
tools/gemspec_audit.rb            }
tools/require_allowlist.rb        }  the gate bodies, so a gate is unit-testable without rake
tools/rbs_surface.rb              }
tools/sig_diff.rb                 }
tools/surface.rb                  }
tools/reproducible.rb             }
tools/versions_gate.rb            }
tasks/gates.rake                  the zero-dependency and surface gates
tasks/versions.rake               the VERSIONS consistency gate
tasks/quality.rake                rubocop, cops:test, rbs, steep, test:*, yard, audit wiring
test/support/dexpace_test_case.rb the shared Minitest base every gem's suite uses
test/support/gate_case.rb         the base for a repository gate test
test/support/coverage.rb          the SimpleCov bootstrap: tracked set, filters, 80 floor
test/gates/*_test.rb              one suite per gate
test/fixtures/gates/**            the deliberately failing input for each gate
test/fixtures/surface/*.txt       the committed runtime surface manifests
.github/workflows/ci.yml          the gates job plus the 3.2/3.3/3.4/4.0 matrix
```

### Per gem, six times

Shown for `dexpace-core`; the other five differ only in the namespace path and the gemspec's
dependency line.

```
gems/dexpace-core/
  dexpace-core.gemspec            reads VERSIONS; zero add_dependency lines
  README.md                       >= 20 lines, heading names the gem
  LICENSE                         a byte copy of the root LICENSE, so gem build is self-contained
  Rakefile                        the per-gem test task
  lib/dexpace.rb                  the single entry point: explicit requires, defines Dexpace
  lib/dexpace/version.rb          Dexpace::VERSION, the literal
  sig/dexpace.rbs                 mirrors lib/dexpace.rb
  sig/dexpace/version.rbs         mirrors lib/dexpace/version.rb
  test/test_helper.rb             loads the shared case, puts this gem's lib on $LOAD_PATH
  test/dexpace_test.rb            mirrors lib/dexpace.rb
```

The five adapters, with their entry file and what their gemspec declares **in phase 0**:

| Gem | Entry file | Constant | Declared here | Its `NFR-2` budget, spent by |
|---|---|---|---|---|
| `dexpace-transport-net_http` | `lib/dexpace/transport/net_http.rb` | `Dexpace::Transport::NetHTTP` | `dexpace-core` | `net-http`, phase 8 |
| `dexpace-transport-async_http` | `lib/dexpace/transport/async_http.rb` | `Dexpace::Transport::AsyncHTTP` | `dexpace-core` | `async-http`, phase 8 |
| `dexpace-serde-json` | `lib/dexpace/serde/json.rb` | `Dexpace::Serde::JSON` | `dexpace-core` | `json >= 2.19.9`, phase 7 |
| `dexpace-async-thread` | `lib/dexpace/async/thread.rb` | `Dexpace::Async::Thread` | `dexpace-core` | nothing — core only, by design |
| `dexpace-conformance` | `lib/dexpace/conformance.rb` | `Dexpace::Conformance` | `dexpace-core` | nothing — core only, by design |

**Every adapter gemspec declares `dexpace-core` and nothing else in phase 0.** Design §2.1's
dependency table describes these gems as they will ship, not as their skeletons start, and a
dependency declared before any line of code requires it is a dependency nothing can justify: the
require-allowlist audit would have nothing to permit it for, the clean-bundle run would install a
gem no `require` reaches, and the `>= ` floor would be a version number chosen without a caller.
The third-party half of each budget arrives with the code that needs it — `json >= 2.19.9` in
phase 7, `net-http` and `async-http` in phase 8. `gates:gemspec_audit` still enforces the whole
`NFR-2` rule (core plus at most one) and its `two_third_party` fixture is the negative proof,
because an audit that has only ever seen one dependency has never been shown to reject two.
Recorded in the Deviation Ledger as P0-9.

`sig/` mirrors `lib/` one file per file in every gem and **ships inside the gem**, so a consumer's
own `steep check` sees it. `test/` mirrors `lib/` one file per file and does not ship.

## `VERSIONS` (`VERSIONS`)

**Satisfies:** `NFR-14`, and is the input to `NFR-10` and `NFR-15`.
**Design:** §2.3 — "`NFR-14`'s single source of truth is a repo-root `VERSIONS` file read by every
gemspec, so a tool-version or coordinate bump happens in one place."

A line-oriented text file, deliberately not YAML, because a gemspec must parse it with no
`require` beyond what Ruby always has and because a three-line regex is auditable in a way a
schema is not. Four record kinds:

```
gem  dexpace-core                  0.0.0
tool rubocop                       ~> 1.90
ruby floor                         3.2
ruby matrix                        3.2 3.3 3.4 4.0
ruby dev                           4.0.6
```

`NFR-14` asks for one source of truth for three different things — dependency versions, tool
versions and project coordinates — and Ruby gives no single file that all three consumers read.
Each gemspec reads `gem` and `ruby floor`; the root `Gemfile` reads `tool`; `.ruby-version` and
the CI matrix cannot read anything, because one is a bare version string and the other is YAML.
So the single source is enforced rather than shared: `rake gates:versions` asserts that
`.ruby-version` equals the `ruby dev` line, that `.github/workflows/ci.yml`'s matrix equals the
`ruby matrix` line, that every gemspec's `version` equals its `gem` line, that every gemspec's
`required_ruby_version` equals `>= ` plus the `ruby floor` line, and that each gem's
`lib/**/version.rb` literal equals the same. A bump is one edit in `VERSIONS` and a failing gate
everywhere it was not propagated — which is what "one-line edit that applies uniformly" can
honestly mean in Ruby.

The version literal exists in two places on purpose. `lib/dexpace/version.rb` carries it so a
**built gem** is self-contained — a `.gem` does not ship the repository root, and `NFR-15`
requires the User-Agent to read a real version at runtime, not a placeholder
(`tooling-and-quality-gates/2ea5cd2e`). `VERSIONS` carries it so the bump has one home. The gate
ties them together; neither is derived from the other at load time, because a gemspec that
`require`s the library it describes is a load-order hazard.

## Root `Gemfile` and `.gitignore` (`Gemfile`, `.gitignore`)

**Satisfies:** `NFR-2` (by keeping the toolchain out of every gemspec), `NFR-14`.
**Corpus:** `tooling-and-quality-gates/f37d7536`, `/e00c3fc5`, both resolved by
`docs/knowledge/notes/tooling-and-quality-gates.md`.

One root `Gemfile` — design §9's gate table names it — holding the development toolchain
(`rake`, `minitest`, `rubocop`, `rubocop-minitest`, `rubocop-performance`, `rbs`, `steep`,
`simplecov`, `yard`, `bundler-audit`) and a `path:` reference to each of the six gems, so
`bundle exec` resolves the workspace without any gem being installed. Every version constraint
comes from a `tool` line in `VERSIONS`.

**`Gemfile.lock` is not committed and is in `.gitignore`.** This is a deliberate departure from
styleguide rule 1.1 and it is recorded as a note, not left implicit. The reason is the matrix: a
lockfile is a resolution against one interpreter, and the supported range spans a boundary where
26 names stop being default gems, so one lockfile cannot be `--frozen`-installed on every row
without either pinning the toolchain to the intersection or failing a row for a reason unrelated
to the change under test. Every matrix row runs a plain `bundle install`; `bundler-audit check
--update` runs against the lockfile that install just produced on disk, which makes the CVE gate
report the versions CI actually installed. What is lost — the drift signal `--frozen` gives on an
unreviewed `bundle update` — is stated in the note and mitigated by every gate being blocking on
every row.

## `Rakefile` and the gate tasks (`Rakefile`, `tasks/*.rake`)

**Satisfies:** `NFR-17` (blocking, automatic, not advisory), and it is the vehicle for all the
rest.
**Design:** §9 preamble — "The default `rake` task runs the whole set locally, so a gate cannot be
an opt-in job nobody runs" (`tooling-and-quality-gates/f1bc6c10`).

The default task is the full set, in this order, each blocking. The order is by cost and blast
radius, not by importance: the ones that read only text run first, so a formatting mistake does
not wait behind a `bundle install`.

| # | Task | Gate | IDs | Where CI runs it |
|---|---|---|---|---|
| 1 | `rubocop` | RuboCop, `--fail-level=convention`, no autocorrection | `NFR-7`, `NFR-13` | gates |
| 2 | `cops:test` | the five custom cops' own suite | `NFR-13` | gates |
| 3 | `rbs:validate` | `rbs validate` per gem | `NFR-3` | gates |
| 4 | `steep` | `steep check`, target-by-target | `NFR-3` | gates |
| 5 | `test:gems` | every gem's Minitest suite, warnings fatal, SimpleCov floor | `NFR-5`, `NFR-6`, `NFR-10` | every matrix row |
| 6 | `test:gates` | the repository's gate suites | `NFR-17` | gates |
| 7 | `gates:gemspec_audit` | runtime dependencies per gem | `SEAM-1`, `NFR-1`, `NFR-2` | every matrix row |
| 8 | `gates:require_allowlist` | the require scan over core and the adapters | `SEAM-1`, `SEAM-2`, `NFR-1`, `NFR-8` | every matrix row |
| 9 | `gates:clean_bundle` | the scratch-`Gemfile` isolation run | `SEAM-1`, `NFR-1`, `NFR-10` | every matrix row |
| 10 | `gates:rbs_surface` | no foreign constant in a public signature | `NFR-11` | gates |
| 11 | `gates:sig_diff` | `sig/**/*.rbs` against the previous release tag | `NFR-4` | gates |
| 12 | `gates:surface_snapshot` | the runtime constant/method manifest | `NFR-4` | gates |
| 13 | `gates:single_instance` | one resolved path per core file; version agreement | §2.4 | every matrix row |
| 14 | `gates:versions` | `VERSIONS` against every consumer of it | `NFR-14`, `NFR-10` | gates |
| 15 | `gates:reproducible` | two builds under a fixed `SOURCE_DATE_EPOCH`, byte-compared | `NFR-12` | gates |
| 16 | `yard` | documentation build plus the undocumented-public gate | — | gates |
| 17 | `bundler_audit` | `bundler-audit check --update` | — | gates |

Two of the seventeen exist because a gate that runs nowhere is a configuration file.
**`cops:test`** is the custom cops' own suite: it lives at `.rubocop/test/`, outside both `test/`
and `gems/*/test/`, so neither test task would collect it and a cop that silently stopped
matching would stay silent. And **`test:gems` and `test:gates` are separate tasks** because they
belong in different CI jobs: the gem suites must run on every Ruby in the matrix, since `NFR-10`'s
trap is a method present on the developer's 4.0 and absent on the declared 3.2 floor, while the
gate suites shell out to `rake`, `git` and `bundle` and are interpreter-independent. The "Where
CI runs it" column above is asserted by a test, not maintained by hand: `ci_workflow_test.rb`
reads `rake gates:list` and fails if any listed gate appears in no job.

Each of the seventeen is a separately invocable task, because a gate you cannot run alone is a
gate you debug by running everything.

Per-gem `rake test` (`gems/<gem>/Rakefile`) exists alongside the root tasks for local iteration
and is what `CLAUDE.md`'s command block will document. It runs that gem's suite without the
coverage floor. The floor is an **aggregate** across the library units by `NFR-5`'s own wording,
so it belongs to `test:gems`, which runs every gem's suite in one process and therefore produces
one coverage number.

## The zero-dependency gate, part 1: gemspec audit (`tasks/gates.rake`)

**Satisfies:** `SEAM-1`, `NFR-1`, `NFR-2`.
**Design:** §2.4 — "`dexpace-core.gemspec` contains **zero `add_dependency` lines**, asserted by a
test in the default Rake task that loads the gemspec and requires `runtime_dependencies` to be
empty. That test *is* the **SEAM-1** dependency audit; there is no scope declaration to lean on
instead." Corpus: `package-and-dependency-layout/fa303aa7`.

The audit loads each of the six gemspecs with `Gem::Specification.load` and asserts:

- `dexpace-core`: `runtime_dependencies` is empty. Not "contains no transport" — **empty**, because
  Ruby has no compile-versus-runtime dependency scope and any non-empty set is a claim someone has
  to adjudicate.
- Each adapter: `runtime_dependencies` is `dexpace-core` plus **at most one** other gem, which is
  `NFR-2`'s budget stated exactly. In phase 0 all five have exactly one — `dexpace-core` — because
  no adapter has code needing a third-party gem yet (Module Layout above, and P0-9). The rule is
  still the whole rule, and the `two_third_party` fixture is what proves the audit rejects a
  second: an audit whose real inputs never exercise its upper bound has not been tested against
  it.
- Each adapter's `dexpace-core` requirement string is `~> MAJOR.MINOR` derived from the `gem
  dexpace-core` line in `VERSIONS`. Today that is `~> 0.0`; the audit computes the expected string
  rather than matching a literal, so a bump to `0.1.0` fails every adapter that was not updated,
  and a bump to `1.0.0` yields `~> 1.0`. This is the static half of §2.3's version-skew guard.
- `required_ruby_version` on every gem is `>= ` plus the `ruby floor` line (`NFR-10`).
- `spec.files` is produced by `Dir.glob(...).sort` and not by shelling out to `git ls-files`, so
  entry ordering is deterministic without depending on git (`NFR-12`).

The runtime half of the version-skew guard — the registration-time assertion each adapter runs
against `Dexpace::VERSION` (§2.3) — is **designed here and lands in phase 2**, because the call it
hangs on is require-time seam self-registration, which is design §10 item 8 and phase 2's scope.
Building a public `Dexpace.register` in phase 0 would fix an API phase 2 must be free to shape.
Deferred as `DEF-21`.

## The zero-dependency gate, part 2: require-allowlist audit (`tasks/gates.rake`)

**Satisfies:** `SEAM-1`, `SEAM-2`, `NFR-1`; and is `NFR-8`/`NFR-9`'s retarget per design §10
item 19.
**Design:** §9.2 — "a test scans core's `lib/**/*.rb` for every `require`/`require_relative` and
fails on anything outside an explicit allowlist … the one gate here with no counterpart in the
reference build." Corpus: `package-and-dependency-layout/86fc9241`, `/2b7ab9dc`.

A text scan, not a runtime trace, which is why `lib/dexpace.rb` issues explicit requires rather
than using an autoloader (`module-organization/2a4cc61d`).

**Both forms are scanned**, as §9.2 and `CLAUDE.md` both say. `require` reaches outside the gem by
*name*, and the three lists below decide it. `require_relative` reaches outside the gem by *path*,
which no allowlist can see: the audit resolves each relative target against the requiring file and
fails when it lands outside that gem's `lib/`. That is the cross-gem reach styleguide 12.6 forbids,
and it is worse than a style violation here — a packaged `.gem` contains only its own `lib/` and
`sig/`, so a `require_relative` that escapes works in the workspace and raises `LoadError` for
every consumer.

Three lists, all committed constants:

**The allowlist — what core may `require`.** Deliberately narrower than "everything stable",
because the category is not the constraint; what core actually needs is. Every name below was
verified to `require` cleanly on 3.2.11, 3.4.10 and 4.0.6, and to be absent from
`Gem::BUNDLED_GEMS::SINCE` on 4.0.6:

`monitor`, `uri`, `stringio`, `strscan`, `time`, `date`, `securerandom`, `digest`, `openssl`,
`forwardable`, `set`, `singleton`.

Growing this list is a reviewed one-line diff with the requirement that motivated it, which is the
whole point of it being explicit.

**The denylist — stable, permanently forbidden, with the reason attached.** These would pass a
category test and must still fail, so the gate reports them with the requirement rather than a
generic "not allowlisted":

| Name | Why |
|---|---|
| `json` | `SEAM-2`: the wire codec is a seam. The codec lives in `dexpace-serde-json` and the `>= 2.19.9` floor lives in that gemspec and nowhere else |
| `net/http`, `net/protocol`, `open-uri`, `socket`, `resolv` | `SEAM-1`/`SEAM-2`: core embeds no concrete transport |
| `timeout` | `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.3 and `CLAUDE.md`'s ban list: `Timeout.timeout` can land an interrupt inside an `ensure` releasing a pooled connection. The gem is a stable default gem, so only a denylist catches it |
| `base64`, `logger`, `ostruct`, `benchmark`, `fiddle`, `pstore`, `irb`, `rdoc`, `reline`, `racc`, `tsort` | Bundled, or bundled at 4.1. Listed by name so the failure message says *when* each left, not just that it is not allowed |

**The category assertion — the gate that keeps the two lists honest.** A third check runs on the
interpreter under test and asserts that every allowlisted name is require-able and is not in
`Gem::BUNDLED_GEMS::SINCE`. It skips the `SINCE` half when the constant is undefined, which is
Ruby 3.2 — so on the floor row it checks require-ability only, and on the 4.0 row, where the
constant exists and is authoritative, it checks both. That is why design §9.2 says *the highest*
Ruby, and it is now a hard constraint rather than a stylistic one.

**Extended to the adapters, which §9.2 does not require.** The design scopes this audit to core.
Phase 0 extends it: for each adapter, every `require` must be allowlisted, or under `dexpace/`, or
the single third-party gem that adapter's gemspec declares. The failure mode it catches is exactly
`NFR-2`'s budget being exceeded silently — an adapter writing `require "logger"` without declaring
it works on the author's machine and fails on 4.0. Recorded in the Design §9 Addendum below.

## The zero-dependency gate, part 3: clean-bundle isolation run (`tasks/gates.rake`)

**Satisfies:** `SEAM-1`, `NFR-1`, `NFR-10`.
**Design:** §9.2 — "a scratch `Gemfile` containing only `gem "dexpace-core", path: ...`, then
`bundle exec ruby -e` requiring core and exercising a smoke path, since Bundler refuses to
activate a gem outside the bundle, run on every Ruby in the matrix, which is what makes the Ruby
4.0 column load-bearing rather than aspirational."

The task writes a scratch directory holding a `Gemfile` whose only content is a `path:` reference
to the gem under test, runs `bundle install` there, then `bundle exec ruby -e` with a smoke
script that `require`s the gem and asserts its `VERSION` constant is present and matches. A
non-zero exit, or a `LoadError` naming a bundled gem, fails the gate with the offending
`require` in the message.

This is the check that catches what neither of the other two can: the gemspec audit sees
declarations and the allowlist audit sees text, but only Bundler refusing to activate an
undeclared gem catches a transitive require reached at load time. It runs against **all six**
gems, not just core — an adapter's single declared dependency is exactly as testable this way —
and on every Ruby in the matrix in CI, on the development Ruby locally.

The Ruby 4.0 column is where it actually bites, because that is where `logger`, `ostruct`,
`benchmark`, `fiddle`, `pstore`, `irb`, `rdoc`, `reline` and `win32ole` leave the default set.
Ruby 4.0.6 is released and `ruby/setup-ruby` resolves `4.0`, so this is an ordinary required
matrix row with no fallback.

## `.rubocop.yml` and the five custom cops (`.rubocop.yml`, `.rubocop/cops/dexpace/*.rb`)

**Satisfies:** `NFR-7` (findings fatal), `NFR-13` (SPDX), and mechanises `CLAUDE.md`'s ban list.
**Corpus:** `tooling-and-quality-gates/cb18f9bd` fixes the baseline —
`plugins: [rubocop-minitest, rubocop-performance]`, `NewCops: enable`, `TargetRubyVersion: 3.2`,
`--fail-level=convention`, no `rubocop-airbnb`, no pre-commit hook, waivers only as scoped inline
directives carrying a reason. Every cop setting the styleguide names by hand is transcribed
directly: double quotes, 2-space indent, 100 columns, `consistent_comma`, leading dot,
`MethodLength: 25` with `CountAsOne`, `ParameterLists: 4`, `BlockNesting: 3`
(`formatting-and-tooling/eb933cb2`, `/d839bdc1`, `/41256847`, `/69f1e744`,
`function-design/746002cc`). Every override in the file carries a comment naming the chapter and
rule it came from (`tooling-and-quality-gates/d39dd7c6`).

Five custom cops, in `RuboCop::Cop::Dexpace`, loaded by `require:` from `.rubocop.yml`. They live
at `.rubocop/cops/` rather than under `gems/` because every directory under `gems/` is a published
gem — the housekeeping probe's `readmes` check enforces exactly that — and a seventh directory
there would be a seventh gem nobody publishes.

| Cop | Bans | Source of the rule |
|---|---|---|
| `Dexpace/SpdxHeader` | The whole header block, in this order and no other: **line 1 `# frozen_string_literal: true`, line 2 `# SPDX-License-Identifier: MIT`, line 3 blank.** Three separate offences, three separate messages | `NFR-13`; `tooling-and-quality-gates/3085561e`; `formatting-and-tooling/bf14bf0e`; the header shape in `docs/knowledge/notes/formatting-and-tooling.md` |
| `Dexpace/NoTimeParse` | `Time.parse`, `Date.parse`, `DateTime.parse` | Design §3.5; `CLAUDE.md` "Constraints that will bite" |
| `Dexpace/NoUriDefaultParser` | `URI::DEFAULT_PARSER`, and the `URI.parse`/`URI.join`/`URI.split` family that routes through it | Design §3.5 — what `DEFAULT_PARSER` *is* changed at exactly Ruby 3.4.0, which straddles the floor. `URI::RFC3986_PARSER` is pinned explicitly for every parse and every resolution |
| `Dexpace/NoLocaleCaseFold` | Any argument to `downcase`, `upcase`, `capitalize`, `swapcase` and their `!` forms — the locale symbol is the only argument they take — plus `casecmp?`, which applies Unicode full case folding where `casecmp` is ASCII-only | `HTTP-13`; `CLAUDE.md`'s domain-model section — `"I".downcase(:turkic)` is `"ı"`, and header-name folding must be ASCII |
| `Dexpace/NoThreadInterrupt` | `Timeout.timeout`, `Thread#raise`, `Thread#kill`, `Thread#terminate`, `Thread#exit` | Design §8.3; modelled on `Airbnb/NoTimeout`. An async interrupt can land on any bytecode instruction, including inside an `ensure` releasing a pooled connection |

`Dexpace/NoThreadInterrupt` is the one gate design §9's table does not carry. The roadmap made it
a decision — cross-cutting constraint 6, "the `Timeout.timeout`/`Thread#raise`/`Thread#kill` cop
is a **roadmap decision** design §9's table does not yet carry, so phase 0 records it there as an
addendum in its design doc" — and the Design §9 Addendum section below is where it is recorded.

Each cop ships a Minitest suite. RuboCop's own cop-testing helpers are RSpec-only, so
`.rubocop/test/cop_case.rb` is a thin harness: parse a source string into a
`RuboCop::ProcessedSource`, run the cop through a `Commissioner`, and assert on the offense list.
That is roughly forty lines and it keeps `NFR-2`'s spirit — no RSpec anywhere in this repository —
without giving up cop tests.

## Warnings as errors (`test/support/dexpace_test_case.rb`, `tasks/quality.rake`)

**Satisfies:** `NFR-6`.
**Design:** §9 table — "`ruby -w` for the test task plus `RUBYOPT=-W:deprecated`, with warnings
failing the build." Corpus: `tooling-and-quality-gates/872a2d77`.

Ruby prints warnings; it does not fail on them. Two mechanisms, because each misses what the other
catches:

1. **`Warning.warn` is overridden in the shared test case to raise.** A warning triggered by code
   under test then fails *the test that triggered it*, with the file and line, which is the
   signal a developer can act on. An allowlist of zero entries is the starting state; adding one
   requires a comment naming why (`NFR-7`'s "narrowly-scoped, documented exception" applied to
   warnings).
2. **The root test tasks run their suites in a subprocess with `-w -W:deprecated` **appended** to
   `RUBYOPT`, and scan stderr for `warning:`.** This catches what the override cannot: a warning
   emitted at `require` time, before the helper that installs the override has loaded. A method
   redefinition in an entry file is exactly that case. `RUBYOPT` is appended to rather than
   replaced, because Bundler puts `-rbundler/setup` there and overwriting it would silently
   unbundle the subprocess — undoing the `bundle exec` the task is running under and letting a
   globally installed gem satisfy a `require` the bundle does not.

## Typing: `sig/`, `Steepfile`, `rbs_collection.yaml`

**Satisfies:** `NFR-3`; feeds `NFR-4` and `NFR-11`.
**Corpus:** `type-system/169c8f38` — RBS under `sig/`, `rbs validate` plus `steep check` as
blocking gates, no Sorbet anywhere, adoption target-by-target rather than a blanket ignore
(`tooling-and-quality-gates/c716331a`).

`sig/` mirrors `lib/` one file per file in every gem and ships inside the gem. At phase 0 that is
two signature files per gem: the namespace and `VERSION`. `rbs validate` runs per gem with that
gem's `sig/` on the load path.

The `Steepfile` names **six targets from day one**, one per gem, rather than one repository-wide
target — because "target-by-target" is only a real discipline if the targets exist before anyone
needs to relax one. `dexpace-core` is configured strict; the five adapters start at Steep's
default diagnostics, and each future relaxation is a change to a named target with a comment,
never a blanket ignore. `rbs_collection.yaml` is present with an **empty `gems:` list**: no
gemspec declares a third-party dependency yet (P0-9), and stdlib signatures ship with `rbs`
itself, so there is nothing to resolve until phase 7 and phase 8 add their rows.
`rbs_collection.lock.yaml` is **not** committed — it is gitignored and every CI row runs `rbs
collection install` for itself, which is the same argument the lockfile note makes about
`Gemfile.lock`.

`test/` gets no Steep target in phase 0. The testing note records why and what changes it: a test
tree is added as its own named target when its helpers become production-quality code worth
checking, which is phase 8's conformance helpers at the earliest. Deferred as `DEF-23`.

## The API-surface lock: `gates:sig_diff` and `gates:surface_snapshot`

**Satisfies:** `NFR-4`.
**Design:** §9.1 — the diff of `sig/**/*.rbs` against the previous release, paired with a runtime
surface snapshot, because "**RBS describes what someone wrote, not what Ruby defines**":
`Data.define`'s generated readers, `define_method`, `method_missing` and a require-time
`register` call are invisible to it. Corpus: `api-design/46c8b5fc`.

**`gates:sig_diff` before the first tag.** There is no `v*` tag in this repository and no release
path, so the gate has a pre-release branch that must not become a permanent silent pass. It
resolves the baseline with `git describe --tags --match 'v*' --abbrev=0`. With no tag it prints
`no release tag yet — the first v* tag becomes the baseline` and exits 0. With a tag it diffs
every `sig/**/*.rbs` against that tag and fails when a public signature disappears **or narrows**
without a major bump.

The comparison is over **whole normalised declaration lines**, not declaration names. `NFR-4`'s
clause is "disappears or narrows", and narrowing is the half a name-keyed comparison cannot see:
`VERSION: String` becoming `VERSION: "0.0.0"` keeps the name and breaks every consumer who
assigned it to a `String`. Whitespace is normalised so reindenting a signature file is not a
break, and the declarations are sorted so reordering is not one either; anything else that changed
is reported with the old line quoted. The vacuous branch is reachable **only** while the
repository has no `v*` tag at all, and the gate asserts that rather than assuming it — so the
moment a tag is pushed the gate becomes load-bearing with no code change and no one remembering.
`docs/first-release.md` already carries "An RBS sig-diff baseline established" as a publish
blocker; phase 0 does not close it.

**`gates:surface_snapshot` on a near-empty tree.** A test walks `Dexpace`'s constant tree and each
class's `public_instance_methods(false)`, sorts, and diffs against
`test/fixtures/surface/<gem>.txt`.
At phase 0 each manifest is two or three lines. That is not a weakness: a manifest that is two
lines and *checked* is the state from which every later addition is a reviewed diff, and the
alternative — introducing the manifest in phase 1 alongside forty new constants — is the case
where nobody reads it. Changing exports means regenerating **both** this manifest and the RBS;
that is stated in the gate's failure message, not only in `CLAUDE.md`.

## `gates:rbs_surface` — no foreign constant in a public signature

**Satisfies:** `NFR-11`.
**Design:** §9 table — "An RBS scan asserting that no constant outside `Dexpace::` and a fixed
stdlib allowlist appears in any public signature under `sig/` — which is what mechanises 'leaks no
async-framework types into the core public surface' and is why the pivot of §3.3 had to be
core-owned." Corpus: `concurrency-and-async/ed059b87`.

The scan parses every `sig/**/*.rbs` in every gem, collects each referenced type name, and fails
on anything that is neither under `Dexpace::` nor in a fixed stdlib type allowlist (`String`,
`Integer`, `Symbol`, `Hash`, `Array`, `IO`, `URI`, and the handful that follow).

**Five positions, not one.** A method's return type is the obvious place a foreign constant
leaks, and it is not the only one: a superclass (`class Runner < Async::Task`), an
`include`/`extend`/`prepend`, a type alias (`type handle = Async::Task`), and a generic upper
bound (`class Box[T < Async::Task]`) each put the same constant in the same public surface. All
five are collected, and there is a fixture per position — because a scan that reads only return
types would report a leaking superclass as clean. At phase
0 the signatures reference `String` and nothing else, so the gate is green because there is
nothing to catch — and it is exactly the gate that would have caught `Async::Task` appearing in
core's public surface, which is the failure mode design §3.3 is shaped to prevent. The failing
fixture is an `.rbs` referencing `Async::Task`.

## `gates:single_instance` — a regression guard, not a live check

**Satisfies:** design §2.4's single-instance guarantee, and §9's table row for it: "the auditable
form of a claim §2.4 otherwise argues structurally."

**This gate cannot fail today, and that is the point.** §2.4 argues the guarantee structurally —
Bundler activates exactly one version of a gem per process, `require` de-duplicates by resolved
feature path, and constants live in one process-global namespace — so two copies of
`dexpace-core` cannot produce two distinct `Dexpace::TransportError` classes. Ruby offers no way
to make it fail from inside a normal build, which is why the gate ships with an environment
switch that fabricates a duplicate entry in `$LOADED_FEATURES` and a test that asserts the gate
then rejects it.

What it guards against is a **future change to how this repository is vendored or loaded**: a
`path:` reference that resolves the same file twice under two names, a consumer vendoring core
into their own tree alongside a gem-installed copy, or a later phase adding a load-path
manipulation that reopens the question §2.4 closed. Type-identity checks break silently under
duplication — `XCUT-4`'s exception hierarchy, `RECOV-1`'s `Outcome` variants, `SERDE-14`'s
`Tristate` are all `is_a?`/`==` on a constant — so the failure mode is a wrong answer, not a
crash, and a cheap standing assertion is worth more than a comment saying it cannot happen. It
also carries the `Dexpace::VERSION`-versus-gemspec assertion, which *can* fail today and does,
the moment `VERSIONS` and a `version.rb` literal disagree.

## Coverage (`test/support/dexpace_test_case.rb`, `tasks/quality.rake`)

**Satisfies:** `NFR-5`.
**Design:** §9 table — SimpleCov `minimum_coverage 80` wired into the default Rake task, samples
and test support excluded. Corpus: `tooling-and-quality-gates/1a046d20`.

`minimum_coverage 80` is set unconditionally. `track_files` is `gems/*/lib/**/*.rb`; `test/`,
`.rubocop/`, `tasks/` and the gate fixtures are filtered out, which is the specification's own
"excluding sample/example code, test-only guards, and test fixtures."

**How it stays inert without being disabled, stated exactly.** The roadmap's phase-0 row says the
floor is "wired here and inert until phase 1", and that is right about the effect and loose about
the mechanism, so this is the mechanism: the gate is **wired, armed on the entry files only, and
therefore effectively inert until phase 1 lands domain code.** The tracked set at phase 0 is
twelve files — six entry files and six `version.rb` files — every one of them executed by the
smoke test in its own gem's suite, so measured coverage is 100% and the floor passes on its
merits rather than being skipped. It is never lowered, never `Enabled: false`, never conditioned
on a file count and never wrapped in a guard. What changes in phase 1 is not the gate but the
denominator: the first real code makes 80% a number someone has to work for. Recorded in the
Deviation Ledger as P0-10, because "inert" and "armed and green" are the same observable state
today and a reader is entitled to know which one the build actually implements.

The negative fixture cannot live under `test/fixtures/`: `add_filter "/test/"` and
`add_filter "/fixtures/"` both strip it, leaving an empty tracked set, and SimpleCov reports an
empty set as 100%. So the test writes its uncovered file into `tmp/`, which is gitignored and
matches no filter — a detail worth stating because the obvious placement produces a gate that
passes over nothing.

## YARD and the undocumented-public gate (`.yardopts`, `tasks/quality.rake`)

**Satisfies:** the design §9 table's documentation row; corpus
`tooling-and-quality-gates/31809d47`. Styleguide chapter 14 governs the content
(`14.1` YARD on every public class and method, `14.2` never restate a signature, `14.3`
why-comments explain reasoning).

YARD ships no failure mode for undocumented objects, so the gate is `yard stats --list-undoc` with
a non-zero undocumented count failing the task. At phase 0 the public surface is `Dexpace` and
`Dexpace::VERSION` per gem, and each carries a YARD block — which is the smallest honest way to
prove the gate rejects an undocumented public constant rather than merely being configured.

The `Dexpace::VERSION` block is also where two constant-shadowing hazards this phase creates are
recorded, because phase 0 is what names them and phases 7 and 8 are what walk into them:
`Dexpace::Serde::JSON` shadows `::JSON` and `Dexpace::Async::Thread` shadows `::Thread` inside
their own namespaces. Any reference to the Ruby class from inside those modules must be written
`::JSON` / `::Thread`; an unqualified `Thread.new` inside `Dexpace::Async::Thread` resolves to the
module itself and fails with a confusing `NoMethodError`. The entry files carry the note and the
smoke tests assert the qualified form resolves to the core class.

## Reproducible builds (`gates:reproducible`)

**Satisfies:** `NFR-12`.
**Design:** §9 table — "`SOURCE_DATE_EPOCH` honoured by `gem build`; `spec.files` sorted
deterministically." Corpus: `tooling-and-quality-gates/8bf23626`.

The task builds each gem twice under a fixed `SOURCE_DATE_EPOCH` into two directories and compares
SHA-256 digests. `spec.files` is `Dir.glob(...).sort` for the same reason. The scope is
byte-identity **for one gem, built twice, on one interpreter** — cross-RubyGems-version identity
is not claimed, because `gem build`'s container format is the RubyGems version's business and the
requirement asks for identical inputs to give identical outputs, not for two toolchains to agree.
That reading is recorded in the Deviation Ledger.

## The test convention (`test/support/dexpace_test_case.rb`, `gems/*/test/test_helper.rb`)

**Satisfies:** design §9.3's Minitest choice; styleguide chapter 11.
**Corpus:** `testing/180b5f41` (`test "..." do` blocks, helpers required explicitly),
`testing/0286ed1d` (`FooTest < Minitest::Test`, `test/` mirroring `lib/`), `testing/f3a0462e`
(expected before actual), `testing/4ef070df` (every test runs alone, in any order; fixtures built
fresh; the random seed never overridden).

Minitest does not ship `test "..." do`; ActiveSupport does, and this repository has no Rails.
So the shared base class defines it — `define_method("test_: #{name}", &block)`, which keeps the
`Minitest/TestMethodName` cop satisfied and keeps the description a freeform string in `--verbose`
output. The base class also installs the `Warning.warn` override described above and a small
bounded-sample helper for the property-style tests styleguide 11.7 makes mandatory for value
objects with parse-constructor invariants — bounded iteration count, seed pinned and printed on
failure, no generator gem.

Each gem's `test/test_helper.rb` requires the shared base by relative path and puts that gem's
`lib/` on `$LOAD_PATH`. Crossing out of a gem directory to the workspace's shared support is not
the cross-gem `require_relative` styleguide 12.6 forbids — that rule is about reaching into
another *gem's* internals — but the direction is stated here so a later reader does not have to
re-derive it.

Phase 0 lays the convention and the base class. It does not lay a conformance assertion object;
that is `dexpace-conformance`'s, it is phase 8's, and it is deferred as `DEF-22`.

## The gem entry files and `sig/` mirrors (`gems/*/lib/**`, `gems/*/sig/**`)

**Satisfies:** `NFR-3`, `NFR-15`; and `module-organization/2a4cc61d`'s explicit-require rule.
**Design:** §2.3 — "`lib/dexpace.rb` issues explicit `require`s for the whole tree rather than
using an autoloader. This is not stylistic: every Ruby autoloader worth using is a gem, and
**SEAM-1** bars core from depending on one."

The roadmap describes these gems as having "empty `lib`/`sig`/`test`". **"Empty" means no domain
code, not zero bytes**, and the difference matters: a literally empty entry file gives the
clean-bundle smoke path nothing to require, the surface snapshot nothing to snapshot, `NFR-15`'s
runtime version metadata nowhere to live, and the YARD gate nothing to prove it rejects. Each
entry file therefore defines exactly two things — the namespace module in nested `module`/`class`
form (`Style/ClassAndModuleChildren: nested`, styleguide 12.3) and a `VERSION` constant — with
`require_relative` to its `version.rb` and nothing else. This is recorded in the Deviation Ledger
as a scoped reading of the roadmap's wording, not as a change to it.

No file has a load-time side effect beyond defining constants (styleguide 12.4), no constant is
defined outside `Dexpace::` (12.7), and one constant lives per file (12.2).

## `.github/workflows/ci.yml`

**Satisfies:** `NFR-17` (blocking in CI, not only locally), `NFR-10` (the matrix).
**Design:** §9.2 — "only actually running the suite on 3.2 catches it — which is why the matrix
runs tests, not a syntax check." Corpus: `package-and-dependency-layout/35a6cd13` fixes the matrix
at 3.2 / 3.3 / 3.4 / 4.0.

Two jobs.

**`gates`** runs once on the development Ruby (`.ruby-version`, so 4.0.6): RuboCop, `cops:test`,
`rbs validate`, `steep check`, `test:gates`, YARD, `bundler-audit`, `gates:sig_diff`,
`gates:surface_snapshot`, `gates:rbs_surface`, `gates:versions`, `gates:reproducible`. These are
interpreter-independent by construction — they read text, signatures, git history and build
output, and the gate suites drive `rake` and `bundle` as subprocesses — so running them four
times would buy nothing and cost three quarters of the CI budget.

**`test`** runs the real gem suites on the full matrix, `ruby: ["3.2", "3.3", "3.4", "4.0"]`, via
`test:gems`, plus the three zero-dependency checks and `gates:single_instance` on every row:
`gates:gemspec_audit`, `gates:require_allowlist`, `gates:clean_bundle`. That placement is the
whole argument of §9.2 — the 4.0 row is where the bundled-gem trap fires and the 3.2 row is where
a method present on the developer's 4.0 and absent on the declared floor produces a
`NoMethodError` that `TargetRubyVersion` cannot see. It is also where `gates:require_allowlist`'s
behaviour genuinely differs: `Gem::BUNDLED_GEMS::SINCE` is undefined on 3.2, so the *reason* a
bundled name is refused is unavailable there while the refusal itself still holds, and the suite
asserts both halves rather than skipping the row.

**The split is checked, not maintained.** `ci_workflow_test.rb` reads `rake gates:list` and fails
if any of the seventeen appears in no job — which is how a gate added to `DEFAULT_GATES` and
forgotten in CI gets caught.

`ruby/setup-ruby` with `bundler-cache: false`, because there is no committed lockfile to cache
against and each row must resolve for itself.

`rake gates:versions` asserts the matrix in this file equals the `ruby matrix` line in `VERSIONS`,
so the two cannot drift.

## Design §9 Addendum — gates this phase adds to §9's table

Design §9's gate table is frozen and is not edited by this phase. Three gates below are additions
or strengthenings that the table does not carry, recorded here as the roadmap's cross-cutting
constraint 6 directs, and each has a corresponding Deviation Ledger row for consolidation into
design §10.

| Addendum | What §9's table says | What phase 0 builds |
|---|---|---|
| **A1 — the interrupt-ban cop** | Nothing. §8.3 argues the ban in prose; §9's table has no row | `Dexpace/NoThreadInterrupt`, a blocking custom cop banning `Timeout.timeout`, `Thread#raise`, `Thread#kill`, `Thread#terminate` and `Thread#exit` repository-wide, plus `timeout` on the require denylist so the module cannot arrive by the back door |
| **A2 — the require audit covers adapters, and both require forms** | "scans **core's** `lib/**/*.rb`" for "every `require`/`require_relative`" (§9.2) | The same scan runs on all six gems. For an adapter, the permitted set is the allowlist plus `dexpace/…` plus the single third-party gem its own gemspec declares — which in phase 0 is nothing, since no adapter declares one (P0-9), making the audit strictest exactly while the tree is emptiest. And `require_relative` is resolved rather than assumed internal: a relative target landing outside the gem's own `lib/` fails, because a packaged `.gem` would not contain it |
| **A3 — an explicit denylist alongside the allowlist** | An allowlist only | Names that pass the category test and must still fail — `json`, `net/http`, `socket`, `timeout` — are listed by name with the requirement that forbids each, so the failure message says `SEAM-2` or §8.3 rather than "not in the allowlist" |

## Testing

The phase's deliverable is seventeen gates. A gate that has never been seen to fail is a
configuration file, so **every gate that can be given a failing input gets one, and a test that
asserts the gate rejects it.** The fixtures live under `test/fixtures/gates/`, outside every
gate's own scope — a fixture that fails RuboCop must not fail the repository's RuboCop run — and
each gate test invokes the gate against the fixture as a subprocess and asserts a non-zero exit
and a message naming the offending input. Two fixtures deliberately sit elsewhere and say why in
the table: the coverage fixture (SimpleCov filters `/fixtures/`) and the `sig_diff` fixture (it
has to be a git repository with a tag).

| Gate | Fixture that must make it fail |
|---|---|
| `cops:test` (the five custom cops) | Twenty-four rejected sources and eight accepted ones, as one data-driven suite: five header shapes (missing SPDX, wrong licence, one-line file, transposed lines 1 and 2, no blank line 3); `Time.parse` / `Date.parse` / `DateTime.parse` / `::Time.parse`; `URI::DEFAULT_PARSER` and `URI.parse` / `.join` / `.split`; `downcase` / `upcase` / `capitalize` / `swapcase` / `downcase!` with a locale symbol and a bare `casecmp?`; `Timeout.timeout` and `raise` / `kill` / `terminate` / `exit` on a Thread. The accepted half is the sanctioned form each ban points at, so a cop that rejects everything fails too |
| `gates:gemspec_audit` | A gemspec with one `add_dependency`; an adapter with two third-party dependencies; an adapter whose core constraint is `~> 0.1` while `VERSIONS` says `0.0.0` |
| `gates:require_allowlist` | `require "base64"` (bundled at 3.4); `require "logger"` (bundled at 4.0); `require "tsort"` (bundled at 4.1, default today — the case a range-based rule misses); `require "json"` (stable and denied by `SEAM-2`); `require "timeout"` (stable and denied by §8.3); plus a `require_relative` that escapes the gem's `lib/` and one that does not |
| `gates:clean_bundle` | A **complete** miniature workspace — the gem plus `tools/` and `VERSIONS`, because the gemspec reads both — whose core file requires `logger` with no declaration. Must fail under Bundler on **4.0**, and is the fixture that proves the 4.0 row is load-bearing. Without the two copied files the gemspec would raise first and the assertion would pass for the wrong reason |
| `gates:rbs_surface` | Five `.rbs` fixtures, one per position a type name can occupy: a return type, a superclass, an `include`, a type alias and a generic upper bound — each referencing `Async::Task` |
| `gates:sig_diff` | A scratch `git init` repository whose `v0.0.0` tag genuinely contains signatures — cloning this one would not, since nothing under `gems/` is committed yet. Four cases: a removed declaration, a **narrowed** one (`VERSION: String` → `VERSION: "0.0.0"`, which a name-keyed comparison would call unchanged), a removed signature file, and an unchanged tree; plus the no-tag case asserting the pre-release branch prints its message and exits 0 |
| `gates:surface_snapshot` | A constant added to a gem with the manifest unchanged — proving the gate catches what RBS cannot see |
| `gates:versions` | `.ruby-version` disagreeing with `ruby dev`; a CI matrix row removed; a `version.rb` literal ahead of `VERSIONS` |
| `gates:single_instance` | Two resolved paths for one core feature |
| `gates:reproducible` | A fixture gem whose `spec.files` is an unsorted `Dir.glob`, built twice with no `SOURCE_DATE_EPOCH` and one file's mtime moved between the builds: the digests must differ. Paired with the same fixture built twice under the fixed epoch, which must agree — so the difference is attributable to the normalisation and not to a broken fixture |
| `test:gems` warnings-fatal | A source triggering a method-redefinition warning at require time, proving the stderr scan catches what the `Warning.warn` override cannot |
| SimpleCov floor | An uncovered library file written into `tmp/`, outside every `add_filter`, asserting the floor fails below 80. It cannot live under `test/fixtures/`: both `/test/` and `/fixtures/` are filtered, and SimpleCov reports an empty tracked set as 100% |
| `yard` | A public method with no YARD block |
| `rbs:validate` | An `.rbs` referencing an undeclared type (`VERSION: Nonexistent::Type`), asserted to exit non-zero |
| `bundler_audit` | **No fixture.** It resolves a live advisory database and its verdict changes when a CVE is published against a gem this repository already depends on, so a green-exit assertion would fail for a reason unrelated to the change under test. The test asserts the task is *wired* — present in `tasks/quality.rake`, carrying `--update`, and listed in `DEFAULT_GATES` — and the honest response to a real finding is a version bump in `VERSIONS`, not a test edit |

**Fifty-two deliberately failing inputs**, counted from the rows above. Thirteen of the seventeen
gates carry at least one of their own — `cops:test` (24 cop sources), `gates:gemspec_audit` (3),
`gates:require_allowlist` (6 refusals, plus one positive control), `gates:clean_bundle` (1),
`gates:rbs_surface` (5), `gates:sig_diff` (3 breaking changes, plus the no-tag and unchanged-tree
controls), `gates:surface_snapshot` (1), `gates:versions` (3), `gates:single_instance` (1),
`gates:reproducible` (1), `test:gems` (1 load-time warning and 1 uncovered file for the SimpleCov
floor), `yard` (1) and `rbs:validate` (1).

**Four gates carry no fixture of their own, and each has a reason.** `rubocop` is the runner for
the five cops `cops:test` already proves case by case. `test:gates` is the runner for the gate
suites themselves — the fixtures in this table *are* what it runs. `steep` and `bundler_audit`
are the two below.

**`steep check`.** Steep's own suite is what proves Steep
detects a type error; a fixture here would assert that a third-party type checker still
type-checks, which is that project's job and not a claim this repository can usefully make. What
phase 0 owes `NFR-3` is that `steep check` is *wired, blocking and configured target-by-target* —
and `typing_test.rb` asserts exactly that: six named targets, `core` strict, no Sorbet sigil
anywhere in the tree, and both `rbs:validate` and `steep` exiting zero on the real signatures.

**Three verifications that are not fixtures, and that the plan runs against real interpreters.**

1. **The clean-bundle run on 4.0.** Not a mock and not a fixture: `bundle install` in a scratch
   directory under Ruby 4.0.6, then `bundle exec ruby -e 'require "dexpace"'`. This is the only
   check in the repository that proves Bundler's refusal actually happens rather than being
   argued about.
2. **The runtime surface snapshot on an effectively empty tree.** Generating the manifest for six
   gems that define two constants each, committing it, and then proving a third constant turns
   the gate red. The point is the *mechanism*, established while it is cheap.
3. **The stdlib facts, re-verified.** The design's Ruby facts were verified against **3.4.10**;
   the facts this phase's allowlist depends on were re-verified during planning against
   **3.2.11, 3.4.10 and 4.0.6** and are recorded above and in
   `docs/knowledge/notes/package-and-dependency-layout.md`. The implementation re-runs them under
   4.0.6 as its first task, because `.ruby-version` names 4.0.6 and a fact that was true in
   planning and false at implementation time is exactly what this repository's note mechanism
   exists to catch.

**One fallback, stated so it does not have to be invented later.** `.ruby-version` is `4.0.6`
because developing on the highest supported Ruby catches the bundled-gem trap before CI does. If
a gate tool — `steep`, `rbs`, `rubocop`, `simplecov` or `yard` — turns out not to resolve or not
to run on 4.0.6, the implementation pins `.ruby-version` to `3.4.10`, files a note under
`docs/knowledge/notes/tooling-and-quality-gates.md` naming the failing tool and its version, and
leaves the CI matrix untouched. The matrix is the requirement; the development pin is
ergonomics.

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P0-1 | `NFR-13`'s SPDX header is a **mechanical gate**, not a review convention | `NFR-13`; `tooling-and-quality-gates/d43d1b03` | The reference enforces it by review. A custom RuboCop cop is strictly stronger and costs one file; a SHOULD enforced by convention across six gems and ten phases is a SHOULD that decays |
| P0-2 | `Gemfile.lock` is **not committed** and CI does not run `bundle install --frozen` | styleguide 1.1; `tooling-and-quality-gates/f37d7536`, `/e00c3fc5` | One lockfile cannot be frozen-installed across a range where 26 names stop being default gems. Recorded as a corpus note; the drift signal is replaced by every gate being blocking on every row |
| P0-3 | The interrupt-ban cop is a gate design §9's table does not carry | design §9 table; §8.3; roadmap cross-cutting constraint 6 | The ban is argued in §8.3 and listed in `CLAUDE.md` but has no mechanised row. Addendum A1 |
| P0-4 | The require-allowlist audit covers **all six gems**, not core alone | design §9.2 | An adapter's undeclared `require` is invisible until a Ruby where the name is bundled. Addendum A2 |
| P0-5 | The allowlist is paired with an explicit **denylist** of stable-but-forbidden names | design §9.2 | `json`, `net/http`, `socket` and `timeout` all pass a category test and must all fail. Addendum A3 |
| P0-6 | "Empty `lib`/`sig`/`test`" is read as **no domain code**, not zero bytes | roadmap phase-0 row | A zero-byte entry file leaves the clean-bundle smoke path, the surface snapshot, `NFR-15` and the YARD gate with nothing to stand on. Each entry file defines a namespace and a `VERSION` and nothing else |
| P0-7 | `NFR-12` is read as byte-identity **for one gem built twice on one interpreter** | `NFR-12` | Cross-RubyGems-version container identity is the toolchain's business, not the source's. "Identical source inputs yield identical outputs" is satisfied; "two toolchains agree" is not claimed |
| P0-8 | `NFR-4`'s `sig` diff has a **pre-release branch** that exits 0 with no `v*` tag | `NFR-4`; design §9.1 | There is no previous release to diff against. The branch is reachable only while no `v*` tag exists, and the gate asserts that rather than assuming it, so the first tag arms it with no code change |
| P0-9 | Every adapter gemspec declares **`dexpace-core` only**; the third-party half of each `NFR-2` budget is declared by the phase that writes the code needing it | `NFR-2`; design §2.1's dependency table | A dependency declared before any line of code requires it is a dependency nothing can justify: the require-allowlist would have nothing to permit it for, the clean-bundle run would install a gem no `require` reaches, and the `>= ` floor would be a version chosen without a caller. `json >= 2.19.9` lands in phase 7, `net-http` and `async-http` in phase 8. The audit still enforces the full budget, and its `two_third_party` fixture is the negative proof |
| P0-10 | `NFR-5`'s coverage floor is **armed and green**, not switched off, where the roadmap says "inert until phase 1" | `NFR-5`; the roadmap's phase-0 row | Both describe the same observable state and a reader is entitled to know which the build implements. `minimum_coverage 80` is unconditional; the tracked set is the twelve entry and version files, all executed by the smoke suites, so it passes at 100% on its merits. What phase 1 changes is the denominator, not the gate |

## Deferrals Filed by Phase 0

Filed against `docs/deferred-items.md`; each names a target phase or an explicit pick-up
condition, per the roadmap's step 7. (The heading avoids the literal words the housekeeping
probe's `registers` check reserves for the aggregate register, which is where these rows live.)

| ID | Deferral | Target / condition |
|---|---|---|
| `DEF-20` | The release path: signed `gem push` (`NFR-16`) and the release half of `NFR-12` | No phase owns it. Condition: `docs/first-release.md`'s RubyGems-ownership and trusted-publishing blockers close |
| `DEF-21` | The **runtime** half of the version-skew guard — the registration-time assertion on `Dexpace::VERSION` each adapter runs | Phase 2. It hangs on require-time seam self-registration (design §10 item 8), which is phase 2's to shape |
| `DEF-22` | `dexpace-conformance`'s framework-agnostic assertion objects and their Minitest/RSpec drivers | Phase 8, which owns that gem's gemspec, version and first release; phase 9 adds the remaining suites |
| `DEF-23` | A Steep target over a `test/` tree | Condition: a gem's test support becomes production-quality code worth checking — phase 8's conformance helpers at the earliest |

### Deferral-register sweep

The roadmap's execution step 1 requires every phase to read the whole register and disposition
every row, not to scan for its own name. All nineteen seeded rows were read.

**Phase 0 picks up none and marks none UNSCHEDULED.** `DEF-1` through `DEF-10` and `DEF-18` are
requirement-level deferrals whose conditions are behavioural and cannot be met by a phase that
ships no domain code. `DEF-11` through `DEF-17` are post-v1 gems and are out of the MVP's scope
by construction. `DEF-19` — the fenced-example executor for `.claude/skills/housekeeping/` —
comes closest, since its stated pick-up condition is "needs published gems to point at": phase 0
creates six gem *directories*, but nothing is published and every gem is at `0.0.0`, so the
condition is not met and the row is left untouched rather than marked UNSCHEDULED. It becomes
answerable at the first release, alongside `DEF-20`.
