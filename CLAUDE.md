# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The Ruby port of the dexpace SDK: **an HTTP-client toolkit, not an HTTP client**. It targets authors of
generated or hand-written service-client SDKs who need the correctness-sensitive plumbing — idempotency-aware
retry, redirects that never leak a bearer token cross-origin, RFC 7235/7616 authentication, pagination, SSE,
three-state PATCH — solved exactly once, and it deliberately does not compete with `faraday` or `httpx` on
"easiest way to fetch a JSON endpoint" (`docs/sdk-design-ruby/01-overview.md`).

Work here is **spec-driven, not feature-driven**. `docs/product-spec/` is normative: 645 numbered requirements
across 19 prefixes. Before implementing anything, find the requirement IDs it must satisfy.

**The v1 roadmap is complete, and nothing is published.** All eleven phases are built and merged — 0 through
10, with phases 3 to 8 each split into sub-phases (3a/3b, 4a–4c, 5a–5c, 6a–6c, 7a–7c, 8a–8c); phase 9
audited the tree and repaired nothing, and phase 10 repaired what phase 9 and every review found, re-derived
design §10 from as-built source into `docs/deviations.md`, and emptied the roadmap's inbound list. Six gems
exist under `gems/`, every one at `0.0.0`, with no tag cut. **The next step is the release path in
`docs/first-release.md`** — its blockers before first publish, what v1 ships without, and the post-release
triggers; work found now is routed there (see "Where a finding goes" below), because there is no later phase.

What each gem carries, with the as-built page under `docs/sdk-documentation/` and the checklist under
`docs/work/mvp/` that maps every requirement ID to the task that satisfied it:

| Gem | Layer (phase) | As-built page |
|---|---|---|
| `dexpace-core` | HTTP domain model — `Request`, `Response`, `Headers`, the `Data` value types, `Model` / `Builder`, the `Dexpace::Error` root (1) | `http.md` |
| | seam layer — `Registry`, the `Transport` / `AsyncTransport` / `Serde` seams, the `SEAM-18` bridges, the async pivot `Async::Future`, `Cancellation`, `Closeable`, `Operation` (2) | `seams.md` |
| | byte streaming under `Dexpace::IO` — `Buffer`, `BufferedSource`, `BufferedSink`, `TeeSink` (3a) | `io.md` |
| | body layer — `Body` and its request variants, `ResponseBody`, the logging wrappers, `TypedResponse`, the one decode boundary (3b) | `body.md` |
| | execution context — the three context flavours, `ContextStore`, `Instrumentation::Bundle` (4a) | `execution-context.md` |
| | recovery layer — `Outcome`, `Recovery` chains and `Orchestrator`, `ProtocolError`, `Suppressible`, `Dexpace.each_cause` (4b) | `recovery.md` |
| | stage pipeline — `Pipeline` with its sixteen `Stages`, `Cursor`, `Builder`, and `AsyncPipeline` (4c) | `pipelines.md` |
| | configuration — `Configuration`, `Dexpace.configure`, `Clock`, `Proxy`, `HTTPDate`, `UUID` (5a) | `configuration.md` |
| | logging facade and redaction — `Instrumentation::Logger`, `Redactor`, `HTTPLogging`, the logging `Step` / `AsyncStep` (5b) | `logging-and-redaction.md` |
| | tracing and metrics — `Tracing`, `Scope`, `HTTPTracer`, the meter SPI and the no-op singletons (5c) | `tracing-and-metrics.md` |
| | retry — `Resilience::Policy`, `Resend`, `RetrySettings`, `RetryStep` / `AsyncRetryStep`, `RecoveryRetry` (6a) | `retry.md` |
| | redirect — `Redirect::Step`, `Pipeline.standard` / `AsyncPipeline.standard` (6b) | `redirect.md` |
| | authentication — `Auth`'s credentials, challenge parser, Basic / Digest handlers, key and bearer stampers, `Auth::Step` (6c) | `auth.md` |
| | serialization — the witness protocol, `DecodeContext`, `Tristate`, `Native`, the two response handlers, `Body.serialized` (7a) | `serde.md` |
| | server-sent events — `SSE::LineReader`, `Reader`, `Event`, `Stream`, `TypedStream` (7b) | `sse.md` |
| | pagination — `Page`, its three strategies, `Items` / `Pages`, `Paginator` / `AsyncPaginator`, `URL.resolve` (7c) | `pagination.md` |
| | `TransportError` and the transport configuration keys (8a, 8c) | `transport-net_http.md` |
| `dexpace-serde-json` | `Serde::JSON::Codec` over one private `::JSON::Coder` per instance, registered under `:json` (7a) | `serde.md` |
| `dexpace-transport-net_http` | the synchronous transport over a fresh-per-call or a borrowed `Net::HTTP` (8a) | `transport-net_http.md` |
| `dexpace-async-thread` | `Async::Thread::Pool`, the fixed-size executor over a bounded queue, with its timer (8b) | `async-thread.md` |
| `dexpace-transport-async_http` | the asynchronous transport over `async-http`, needing a running reactor on the calling thread and creating none (8c) | `transport-async_http.md` |
| `dexpace-conformance` | `TransportSuite` (34 assertions, 8a and 8c), and `InvariantSuite`, `PackagingSuite`, `CodecSuite` and `ExecutorSuite` (9) | `conformance.md` |

The checklists are one per (sub)phase, `docs/work/mvp/phaseN[/phaseNx]/…-checklist.md`; a constant named in
this file and not in the table is in its owning checklist and its gem's `sig/`. The synchronous transport is
the first thing here that talks to a socket and the pool the first executor on the async path; the two meet in
`dexpace-async-thread`'s composed suite over a real socket. The workspace root
carries the `Gemfile`, `Rakefile`, `Steepfile`, `rbs_collection.yaml`, `.rubocop.yml`, `.yardopts`, `VERSIONS` and
the twenty-four blocking gates — phase 0's seventeen
(`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-checklist.md`), phase 7b's
`gates:serde_boundary`, phase 9's three repository-wide invariant scans, `gates:cause_walk`,
`gates:bounded_map` and `gates:seam_names`, over one `RubyVM::AbstractSyntaxTree` walker in
`tools/ast_scan.rb`, and phase 10's three, `gates:ledger_audit` (`docs/deviations.md` against design §10),
`gates:spdx_rbs` (the SPDX header on every shipped `.rbs`) and `gates:sole_parse` (`AstScan.parse` is the
one `parse_file`).
Beyond that, what exists is the specification, the port design, the process tooling and the register,
`docs/deviations.md`. Ruby **>= 3.2** is the floor (`required_ruby_version` in every gemspec but one, asserted by
`gates:versions`; `dexpace-transport-async_http` alone declares **>= 3.3**, read from `VERSIONS`' per-gem
`floor:` row, because `async-http`'s whole closure does — phase 8c's `P8-36` — and the 3.2 row installs, tests
and clean-bundles the other five); CI runs a 3.2 / 3.3 / 3.4 / 4.0 matrix; every Ruby fact in the design was verified against
3.4.10 and the ones the gates and the domain model rest on were re-verified against 3.2.11, 3.4.10 and 4.0.6.

Top-level namespace is `Dexpace`. Gem names are hyphenated and map segment-for-segment onto the constant path:
`dexpace-transport-net_http` → `lib/dexpace/transport/net_http.rb` → `Dexpace::Transport::NetHTTP`.

MVP gems (`docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.1):

| Gem | Namespace | Runtime dependencies |
|---|---|---|
| `dexpace-core` | `Dexpace` | **none** |
| `dexpace-transport-net_http` | `Dexpace::Transport::NetHTTP` | `dexpace-core`; `net-http` (a default gem) |
| `dexpace-transport-async_http` | `Dexpace::Transport::AsyncHTTP` | `dexpace-core`; `async-http ~> 0.104` |
| `dexpace-serde-json` | `Dexpace::Serde::JSON` | `dexpace-core`; `json >= 2.19.9` |
| `dexpace-async-thread` | `Dexpace::Async::Thread` | `dexpace-core` |
| `dexpace-conformance` | `Dexpace::Conformance` | `dexpace-core` |

Later, in rough priority order (§2.2): `dexpace-async-async`, `dexpace-async-concurrent_ruby`,
`dexpace-transport-httpx`, `dexpace-transport-excon`, `dexpace-transport-typhoeus`, `dexpace-serde-oj`,
`dexpace-instrumentation-otel`. The line between the lists is not "how useful" but "what would be unproven
without it": a seam ships in the MVP with at least one adapter that exercises the property the seam exists for.

Unlike the Node port, `dexpace-core` is a **dependency** of each adapter (`add_dependency "dexpace-core",
"~> MAJOR.MINOR"`), not a peer. Ruby has no dual-package hazard — Bundler activates one version per process and
constants are process-global — so the residual risk is version skew, caught by a registration-time assertion on
`Dexpace::VERSION` (§2.4). `NFR-14`'s single source of truth is a repo-root `VERSIONS` file read by every gemspec.

## Commands

All run from the repository root. The build is Bundler-driven: `bundle install` first, on the Ruby you mean to
test with. `Gemfile.lock` is **not committed** and is gitignored — a lockfile is a resolution against one
interpreter and the supported range spans a boundary where 26 names stop being default gems, so every
interpreter resolves its own (`docs/knowledge/notes/tooling-and-quality-gates.md`, key
`tooling-and-quality-gates/f638625d`). Remove the lock before switching interpreters: one written by Bundler 4
makes an older Bundler try to install Bundler 4.

```bash
bundle install
bundle exec rake                                  # the default task: all twenty-four gates, in order (NFR-17)
bundle exec rake gates:list                       # the twenty-four names, in the order CI and `rake` both use
bundle exec rake rubocop                          # NFR-7, findings fatal, no autocorrection
bundle exec rake rubocop:fix                      # safe autocorrections only, never the gate
bundle exec rake cops:test                        # the custom cops' own suite (.rubocop/test/)
bundle exec rake rbs:validate steep               # NFR-3: per-gem rbs validate, then steep over six targets
bundle exec rake test:gems                        # gem suites: warnings fatal, SimpleCov floor (NFR-5, NFR-6)
bundle exec rake test:gates                       # the repository's gate suites (test/gates/)
bundle exec rake gates:gemspec_audit              # SEAM-1, NFR-1, NFR-2
bundle exec rake gates:require_allowlist          # SEAM-1, SEAM-2: the allowlist and the denylist
bundle exec rake gates:serde_boundary             # SSE-37, spec-forced boundary 5: no serde under lib/dexpace/{sse,page}/**
bundle exec rake gates:cause_walk                 # XCUT-9: Dexpace.each_cause is the only walk of a cause chain
bundle exec rake gates:bounded_map                # XCUT-14: only Dexpace::BoundedMap holds a caller-keyed map
bundle exec rake gates:seam_names                 # SEAM-2: core never names a concrete seam implementation
bundle exec rake gates:ledger_audit               # NFR-17: docs/deviations.md still describes design §10
bundle exec rake gates:spdx_rbs                   # NFR-13, NFR-3: every shipped .rbs has the header and declares something
bundle exec rake gates:sole_parse                 # NFR-6: AstScan.parse is the one RubyVM::AbstractSyntaxTree.parse_file
bundle exec rake gates:clean_bundle               # the scratch-Gemfile isolation run, all six gems
bundle exec rake gates:rbs_surface                # NFR-11
bundle exec rake gates:sig_diff                   # NFR-4, RBS half (vacuous until the first v* tag)
bundle exec rake gates:surface_snapshot           # NFR-4, runtime half
bundle exec rake surface:regenerate               # deliberate: regenerate BOTH this and sig/
bundle exec rake gates:single_instance            # design §2.4
bundle exec rake gates:versions                   # NFR-14, NFR-10
bundle exec rake gates:reproducible               # NFR-12
bundle exec rake yard bundler_audit
(cd gems/dexpace-core && bundle exec rake test)   # one suite per gem, under `ruby -w`, no coverage floor
```

The matrix rows run `test:gems gates:gemspec_audit gates:require_allowlist gates:clean_bundle
gates:single_instance` on every Ruby; everything else runs once on the development Ruby
(`.github/workflows/ci.yml`, whose split `test/gates/ci_workflow_test.rb` asserts). Every gate body that is more
than a subprocess and a message lives in `tools/` — `gates:clean_bundle` and `gates:single_instance` are inline in
`tasks/gates.rake` — and every gate is tested from `test/gates/` against a deliberately failing fixture under
`test/fixtures/gates/`; a repository-reading gate accepts `DEXPACE_GATE_ROOT` to point it at such a fixture.

The process tooling has its own commands and its own tests:

```bash
ruby .claude/skills/housekeeping/probe.rb                   # read-only documentation drift. Nine checks.
ruby .claude/skills/housekeeping/probe.rb --only claims,links
ruby .claude/skills/housekeeping/apply.rb                   # dry run: prints the git mv commands
ruby .claude/skills/housekeeping/apply.rb --delivery mvp --phase 5a --write
```

```bash
ruby scripts/knowledge.rb --prefix-info RETRY               # subsystem, owning spec chapter, ID count, level split
ruby scripts/knowledge.rb --gaps RETRY,RECOV                # canonical IDs the corpus cannot answer
ruby scripts/knowledge.rb --req HTTP-13,HTTP-14,HTTP-15     # a whole task's IDs in one call
ruby scripts/knowledge.rb --prefix HTTP --section rules     # an audit group: a whole ID family, uncapped
ruby scripts/knowledge.rb --phase 5a --brief                # every ID a past phase's documents cite
ruby scripts/verify_knowledge_structure.rb                  # the gate: harvested/ and notes/ stay separate
ruby scripts/knowledge_drift.rb                             # hand-run: source drift and stale note citations
```

`docs/knowledge/` was harvested on 2026-09-05 (see "Querying `docs/knowledge/`" below); `--prefix-info` and
`--gaps` answer from appendix C alone, and the two verifiers exit 0 when the trees are sound.

```bash
ruby -w scripts/test/knowledge_test.rb
ruby -w .claude/skills/housekeeping/test/run.rb
ruby -w .claude/skills/housekeeping/test/run.rb -n /guard/   # Minitest flags pass through
```

`scripts/` and `.claude/` are outside the RuboCop gate — `NFR-7`'s one documented exception, with its re-enable
condition in `.rubocop.yml` and its repair a post-release trigger in `docs/first-release.md` (phase 10's file
list did not reach either tree). The `rubocop` gate runs with `--ignore-parent-exclusion`, so a worktree nested
under a checkout whose `.rubocop.yml` excludes `.claude/**` is still linted (phase 10's repairs).

The gate table is `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md`: RuboCop (`rubocop-minitest`,
`rubocop-performance`, findings fatal), `ruby -w` plus `RUBYOPT=-W:deprecated` with warnings failing the build,
`rbs validate` + `steep check`, `sig/**/*.rbs` diffed against the previous release tag, a runtime surface
snapshot, SimpleCov `minimum_coverage 80`, the three zero-dependency checks below, `bundler-audit`, YARD with an
undocumented-public-method gate, and a CI matrix that runs the **real suite** on each Ruby — not a syntax check,
because `TargetRubyVersion` catches syntax and not stdlib availability (§9.2). Phase 0's design adds three the
table does not carry: the interrupt-ban cop, the require audit over every gem and both require forms, and an
explicit denylist beside the allowlist.

### HARD RULE — core requires only stdlib that stays stdlib

**Ruby's standard library is not a fixed set; it shrinks between releases.** Verified from
`Gem::BUNDLED_GEMS::SINCE` on a real 4.0.6 interpreter (`docs/knowledge/notes/package-and-dependency-layout.md`,
key `package-and-dependency-layout/70fbcaee`): the table has 23 entries, not the five or six usually cited.
`racc` left the default set at 3.3; `abbrev`, `base64`, `bigdecimal`, `csv`, `drb`, `getoptlong`, `mutex_m`,
`nkf`, `observer`, `resolv-replace`, `rinda` and `syslog` at 3.4; `benchmark`, `fiddle`, `irb`, `logger`,
`ostruct`, `pstore`, `rdoc`, `reline` and `win32ole` at 4.0; and `tsort` leaves at **4.1** — default on every
Ruby in the supported range and still a trap, which is why the allowlist is a name list checked against the
whole table rather than a category query. `Gem::BUNDLED_GEMS::SINCE` is undefined on the 3.2 floor, so the
4.0 row is the authority for the *reason* a name is refused while the refusal holds on every row. A bundled gem
needs an explicit `Gemfile`/gemspec entry under Bundler, so a core file that innocently writes
`require "base64"` acquires an undeclared dependency that fails on a supported Ruby.

The rule, stated exactly (§2.4): **`dexpace-core` may `require` only (a) non-gemified stdlib and (b) default
gems that remain default gems on every Ruby in the supported range, 3.2 through 4.0.** `dexpace-core.gemspec`
contains **zero `add_dependency` lines** — that assertion *is* the `SEAM-1` dependency audit, because Ruby has
no compile-versus-runtime dependency scope to lean on. The concrete consequences: Basic auth is
`["u:p"].pack("m0")` and never `Base64` (§6.3); the logging sink is a duck type and core never `require`s
`logger` (§8.1). `lib/dexpace.rb` issues explicit `require`s for the whole tree rather than using an autoloader,
because every autoloader worth using is a gem — which also makes the require audit a static scan of the source
rather than a runtime trace. The scan is parsed, not pattern-matched (`tools/require_scan.rb`): `require("json")`,
`Kernel.require "json"`, a require after a `;` and `autoload :JSON, "json"` all reach the same feature and are all
seen.

Three mechanised checks enforce it (§9.2), and all three are blocking:

1. **Gemspec audit** — `runtime_dependencies` empty for core; `dexpace-core` plus at most one other gem for each
   adapter (`SEAM-1`, `NFR-1`, `NFR-2`).
2. **Require-allowlist audit** — scans core's `lib/**/*.rb` for every `require`/`require_relative`/`autoload`,
   in every spelling that reaches `Kernel#require`, and fails on anything outside an explicit allowlist of
   non-gemified stdlib plus default gems that remain default on the *highest* Ruby in the matrix — and on any
   feature it cannot read as a string literal. This gate has no counterpart in the reference build.
3. **Clean-bundle isolation run** — a scratch `Gemfile` holding only `gem "dexpace-core", path: ...`, then
   `bundle exec ruby -e` requiring core and exercising a smoke path, on every Ruby in the matrix. Bundler refuses
   to activate a gem outside the bundle, which is what makes the Ruby 4.0 column load-bearing.

Adapter gems are exempt: an adapter that wants `logger` declares it, which is what `NFR-2`'s "core plus at most
one third-party library" budget is for. The `json >= 2.19.9` floor lives in `dexpace-serde-json`'s gemspec and
nowhere else — being able to state that floor at all is half the reason the codec is a separate gem (§3.4).

## Documentation hierarchy

`docs/README.md` is the index and the contract; this is the working summary, and it must not diverge from it.
An entry is listed before it exists, marked **(planned)**, and is frozen the moment it appears, not the moment
someone remembers; every entry below exists today.

| Entry | Owns | Written by | Housekeeping may write? |
|---|---|---|---|
| `docs/product-spec/` + `docs/product-spec.md` | **Normative.** The numbered requirements — `HTTP-7`, `SEAM-1`, `RETRY-13`, `NFR-5`, … — the code exists to satisfy. The `.md` is its table of contents | A human, deliberately | **frozen** |
| `docs/sdk-design-ruby/` + `docs/sdk-design-ruby.md` | How each spec area maps to idiomatic Ruby. Non-normative but binding by convention. §10 is the **normative deviation ledger** | A human, deliberately | **frozen** |
| `docs/knowledge/harvested/` | Harvested styleguide and spec knowledge, topic-indexed. Generated; **never hand-edited** | The `knowledge-harvest` skill | **frozen** |
| `docs/knowledge/notes/` | What the implementation found, overriding a harvested entry. Role `review` | A human | **frozen** |
| `docs/sdk-documentation/` | **As-built.** How the gems compose, which one to install, worked cross-gem examples. `architecture.md` is the front door, and is a stub | A human, or a skill on request | yes |
| `docs/work/<delivery>/phaseN[/phaseNx]/` | Process records: per-(sub)phase design, plan and checklist | The phase that produced them; **collected** by `housekeeping` | yes — `git mv` only |
| `docs/superpowers/` | Nothing, for long. The **inbox** the Superpowers skills write into; never a citation target | `brainstorming`, `writing-plans` | yes — it drains it |
| `docs/deviations.md` | **Register.** The as-built audit of design §10, and where a deviation with no owning phase lands | A human, following a phase or review | no — judgment, not a mechanical append |
| `docs/first-release.md` | **Register.** Release readiness, plus what v1 ships without and the post-release triggers. Nothing is published; every gem is at 0.0.0 | A human, as blockers close | no |
| `docs/assets/` | Vendored wordmark SVGs the root `README.md` renders | Copied from `dexpace/morphic` | yes |
| `docs/README.md` | The index above | A human | yes |

**Frozen means a maintenance tool refuses to write there**, not merely that you should not. The list lives in one
constant — `Guard::FROZEN` in `.claude/skills/housekeeping/guard.rb` — and `.claude/skills/housekeeping/test/guard_test.rb` proves the four
ways a naive `start_with?` fails: a sibling directory whose name merely starts with a frozen one, a `..` segment
that lands inside after normalisation, an absolute path, and a symlink whose target is inside a frozen tree.

**Where a finding goes.** Nothing is registered and looked up later. A finding is **routed to its owner when
it is found**, and there are four owners. Work that falls inside a phase's scope → a numbered task in that
phase's plan, cited by path and task number. Audit-or-repair work against a phase that is already planned →
phase 10's inbound list in `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — until phase 10 drained it
on 2026-09-25; phase 10 is the roadmap's last phase, so such work found now takes the release owner below, the
way phase 10's own unrepaired residues did. Anything that belongs to
the release — a blocker, something v1 ships without, a step on the release path, a post-release trigger →
`docs/first-release.md`. And if the thing it reports is in material you may write, it is not a finding at all:
fix it. Something consciously postponed while building the SDK takes the first or the third of those, and the
postponing document says which, with the reason and the pick-up condition. A place this port deliberately
differs from the reference contract → the owning phase document's own `## Deviation Ledger`, consolidated into
design §10, audited by `docs/deviations.md` — the only register left at the `docs/` root. **Never leave an
aggregate register section inside a spec, design or plan document** — the probe's `registers` check reports it,
because a concern only a specification remembers is a concern nothing acted on.

**Both item-ID namespaces are retired.** `OI-<n>`, the find-list, and `DEF-<n>`, the deferrals, were retired on
2026-09-13; neither resolves to anything any more, and neither prefix is reused for a new namespace. Requirement
IDs are a different namespace and the probe does not confuse them. Every surviving citation of either — from a
source comment, a test or anywhere under `docs/` — is a finding, and so is either register file reappearing:

```bash
ruby .claude/skills/housekeeping/probe.rb --only citations
```

`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` is the fastest way to locate a
requirement ID.

### Querying `docs/knowledge/`

The corpus was harvested on 2026-09-05 — 40 topics under `docs/knowledge/harvested/` — and `docs/knowledge/` is
now the corpus; `scripts/knowledge.rb` is the only sane way in — a filtered query answers a question for a
fraction of the tokens a topic file costs, and `grep` is not a substitute because it has no section, role or
exact-token ID matching. The `.claude/skills/knowledge-lookup` skill carries the full workflow: the two entry
points (ID-first via appendix C, topic-first for the styleguide-derived areas that carry no IDs), the audit-group
table, and the note-writing shape. Invoke it, do not improvise queries from memory.

**Two trees, and the split is a gate.** `harvested/` is `knowledge-harvest`'s output and is **never hand-edited**:
a `<sub>` sha digests the whole source file rather than the entry, so an edit inside an entry changes no sha and
the next harvest regenerates or duplicates it with nothing to notice. A correction is a **note** —
`docs/knowledge/notes/<topic>.md`, role `review`, a manual `sha:` marker, and a backticked `<topic>/<8 hex>` key
naming the harvested rule it answers. **Which relation that key carries is the note's own verb.** A key preceded
by `Supersedes`, `Resolves`, `Answers`, `Narrows`, `Corrects`, `Overrides` or `Replaces` is an override and makes
that rule print `[overridden by notes/…]` in every query result; every other backticked key in the entry is a
citation in support and prints `[cited by notes/…]`, which is what a rule the note *rests on* must say — marking
a correct, load-bearing rule as overruled is the expensive direction to get wrong.
`ruby scripts/verify_knowledge_structure.rb` keeps the trees apart; re-harvest with
`--corpus docs/knowledge/harvested`, never the default.

Six cross-role conflicts between the styleguide and the design (`--section conflicts`) are recorded in the
corpus — Ruby floor, Sorbet vs RBS/Steep, `T::Struct` vs `Data.define`, single gemspec vs `gems/` monorepo,
Zeitwerk vs explicit requires, and the rubocop baseline — and each is resolved by a note under
`docs/knowledge/notes/` or a styleguide amendment, never by editing `harvested/`.

When citing, drop `--brief` and copy the `<sub>` line as it is. A styleguide `<sub>` is an absolute path to a
sibling repository (`/home/…/styleguide/ruby/11-testing.md:110-114`) — strip the machine prefix to
`styleguide/ruby/11-testing.md:110-114` before committing it, or the citation resolves on one laptop.

## Requirement-ID conventions

The 19 prefixes, in appendix-C order: `SEAM`, `HTTP`, `IO`, `BODY`, `CTX`, `PIPE`, `RECOV`, `RETRY`, `REDIR`,
`AUTH`, `PAGE`, `SSE`, `SERDE`, `OBS`, `CFG`, `TRANSPORT`, `ASYNC`, `XCUT`, `NFR`.

- **Cite by ID, everywhere.** A test file's header comment names the IDs it exercises; a non-obvious branch
  names the ID that forced it; a design doc quotes the ID rather than paraphrasing the rule. Traceability has to
  exist *before* the conformance pass, not be reconstructed for it.
- **Appendix C is the index.** `grep -n '^| HTTP-10 ' docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`
  gives the canonical text; the leading `| ` and the trailing space are load-bearing, because `grep 'HTTP-1'`
  matches HTTP-10 through HTTP-19. `ruby scripts/knowledge.rb --prefix-info HTTP` names the owning chapter.
- **A checklist maps IDs to tasks, one row per ID.** Every (sub)phase ships `…-checklist.md` alongside its design
  and plan, and it names, for each requirement ID in scope, the numbered plan task that satisfies it — or records
  it as postponed, naming the other phase's plan task or the `docs/first-release.md` entry that now owns it, or
  as a deviation. A requirement in scope with no row is the failure mode this
  project is structured to prevent.
- **The roll-up hazard.** A `--req` hit is not proof the corpus knows anything: appendix B rolls several IDs into
  one "the suite verifies X, Y, Z" sentence that states none of them, the CLI tags these `[appendix-B roll-up]`
  and it still exits 0 — when you see the warning, follow the knowledge-lookup skill's three-step roll-up path
  rather than treating the hit as an answer.
- **Every source file opens with an SPDX header** (`NFR-13`), checked by a custom RuboCop cop; every file carries
  `# frozen_string_literal: true`.

## Domain model construction pattern

`docs/sdk-design-ruby/04-domain-model-construction.md`. Every core model follows one shape; deviating breaks
invariants no tool catches.

- **`Data.define` is the base.** A `Data` instance is frozen on construction, `#with` copies with changes, and
  `==`/`eql?`/`hash` are generated over all members. `Data` also permits an `initialize` override that validates
  and calls `super`, so `HTTP-4`'s field-named validation lives in the type. One shared helper raises one error
  type with the one message form `<name> is required` that `SEAM-29` fixes.
- **Builder or `#with`, per `HTTP-3`'s own split.** `Request`, `Response`, `Headers`, `Query`, `RequestOptions`
  and `Configuration` get real mutable `Builder` classes, because their validation is cross-field (`HTTP-7`
  rejects a body on GET/HEAD/TRACE/CONNECT; `HTTP-8` defaults the method to GET only when there is no body).
  `MediaType`, `Status`, `Protocol`, `Method`, `HeaderName` and the conditional helpers are `Data` types with
  `parse`/`of` factories and `#with`, and expose no builder.
- **`#new_builder` `dup`s every collection**, never aliases the source (`HTTP-3`), so later builder mutation
  cannot reach back into the model it came from.
- **Collections are duplicated and frozen exactly once, at construction**, and the same frozen reference is
  returned from every accessor — `HTTP-5` needs no per-access wrapper because the model is genuinely immutable.
  `freeze` is **shallow**, so every nested collection is frozen independently at that same step.
  `Ractor.make_shareable` deep-freezes but **freezes in place and returns the same object**, so it is applied
  only to a collection the model has already `dup`ed and therefore owns — never to a caller's live hash.
- **`private_class_method :new` plus a validating `.build`**, and the gap stated honestly (P8): `Req.send(:new,
  …)` bypasses `.build` because `send` bypassing `private` is a documented Ruby feature — but not validation,
  because every model's `#initialize` override validates and calls `super`; what stays open is `.allocate`,
  which yields an instance whose members are all nil, and any object responding to
  `#method`/`#url`/`#headers`/`#body`, which duck-types past the builder entirely (phase 10's amendment `C19`).
  Neither hole can be closed. Do not build a fake proof that they are.
- **The mitigation that matters is wire-boundary re-validation.** Header name and outbound value validation
  (`HTTP-17`, `HTTP-18`, `XCUT-18`) runs **again** immediately before dispatch, inside every transport adapter,
  so a forged model cannot smuggle a CRLF into a header name even if it never met a builder. That makes the
  residual gap a correctness-of-shape gap, not a request-splitting gap. Recorded in design §10.
- **`downcase` is called with no arguments, everywhere in core.** Ruby's fold is opt-in-locale
  (`"I".downcase(:turkic)` → `"ı"`), and the same lint rule that forbids `Time.parse` forbids a locale symbol on
  `downcase`/`upcase`/`casecmp` repository-wide, so `HTTP-13` is enforced rather than assumed.
- **`#with` routes through the type's validating `.build`, never through `Data#with`.** `Data#with` does not call
  an `initialize` override on Ruby 3.2 (it does on 3.4 and 4.0), so the inherited derivation skips every
  `HTTP-4`/`SEAM-29` check on the declared floor; `Dexpace::Model#with` is the one override, every model gets it by
  `include Model`, and `test:gems` on 3.2.11 is the run that proves it (phase 1's design, addendum A1).
- **`Dexpace::Error` is a module, included by every core error class, not a base class**, so `XCUT-4`'s
  `Dexpace::TransportError < ::IOError` stays reachable under single inheritance; `rescue Dexpace::Error` matches
  through `Module#===`. Phase 1's only error is `Dexpace::InvalidArgumentError < ::ArgumentError`, and
  `Dexpace::ArgumentError` is never defined, because it would shadow Ruby's inside `module Dexpace` (phase 1's
  design, addendum A3).

## Constraints that will bite

Each is one line plus the chapter to read before touching the area.

- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden in every gem here** — an async interrupt
  can land on any bytecode instruction, including inside an `ensure` releasing a pooled connection (§8.3).
- **Deadlines are explicit values, not ambient interrupts** — propagated to
  `open_timeout`/`read_timeout`/`write_timeout` on the sync path and to the task's own timeout on the async path,
  where they interrupt only at a scheduler checkpoint (§8.3, §3.3). This is the direct cause of the port's three
  unsatisfied MUSTs (`ASYNC-3`, `ASYNC-4`, `PIPE-33`); §10.5 splits them, do not silently re-open the trade.
- **`Thread::Mutex` ownership is per-fiber, not per-thread, and it is non-reentrant** — hold it across the flag
  flip only and never across a drain, a parse or any suspension point, or two fibers deadlock (§3.1, §3.7, §7.2).
- **An `Enumerator` abandoned mid-`#next` never runs its `ensure`** — verified, and GC is not a cleanup hook. So
  **resource acquisition and release never live inside an `Enumerator` block**; the engine owns the resource in
  its own scope and exposes `#close` (§7.1).
- **`Fiber[:key]` is the diagnostic-context carrier, not `Thread.current[:key]`** — `Fiber[]` is inherited by a
  child fiber, a new `Thread` and an `Enumerator`'s internal fiber; `Thread.current[]`, despite the name, is
  fiber-local and visible in none of them (§8.1).
- **Bytes on the wire are always `Encoding::BINARY`** — a streaming body yields BINARY `String` chunks (Rack's de
  facto protocol, P14), and core retags to BINARY on ingress rather than trusting a declared charset (§3.1).
- **Pin `URI::RFC3986_PARSER` explicitly for every parse and every resolution; never rely on `DEFAULT_PARSER`** —
  what `DEFAULT_PARSER` *is* changed at exactly Ruby 3.4.0, which straddles the supported floor. Enforced by the
  same lint rule that forbids `Time.parse` (§3.5).
- **The bundled-gem rule** — core never `require`s `base64`, `logger`, `ostruct`, `benchmark`, `fiddle` or
  `pstore`; see the hard rule above and §2.4.
- **The `json >= 2.19.9` floor lives in `dexpace-serde-json`'s gemspec**, and `bundler-audit` is what enforces it
  over time (§3.4, §9).
- **`Ractor` is never load-bearing** — deep-freezing at construction makes the wire model Ractor-shareable as a
  free side effect, and that is the whole claim; the runtime floor keeps Ractor out of the supported surface
  (§4, §9).
- **Regexp timeouts are per-pattern** — `Regexp.new(source, timeout:)`, never the process-global
  `Regexp.timeout`; a library must not impose a process-wide regexp budget on its host (§4, §6.3).
- **Inside `module Dexpace`, anywhere, write `::Thread`, `::Queue`, `::Mutex`, `::SizedQueue`,
  `::ConditionVariable`, `::JSON` and `::IO`** — a bare name resolves to Ruby's class until `dexpace-async-thread`
  or `dexpace-serde-json` is required and to that gem's module afterwards, and core's own suite never requires
  either; `Dexpace::IO` is defined by core itself, so a bare `IO` is that module from the first `require`, and
  `x.is_a?(IO)` is silently `false` for a real `::IO` — inside a consumer's own `class C; include Dexpace` too.
  The seventh custom cop, `Dexpace/QualifiedCoreConstant`, enforces it over every gem's `lib/` and skips a
  constant's own definition site (`module Dexpace; module IO`); a stand-in `Dexpace::Async::Thread` in
  `future_shadowing_test.rb` proves the adapter half behaviourally and `io_test.rb` the core half (phase 2's
  design, §9 addendum A1; phase 3a's P3-7). Core never writes `is_a?(IO)`: every caller-supplied stream is
  checked with `respond_to?`.
- **`IO-1`'s read primitive is `#read_into(dest, count:)`, and `#read`/`#readpartial`/`#getbyte`/`#each` keep
  Ruby's semantics** — `IO.copy_stream`, which is what `Net::HTTP#body_stream=` uses, hands `#readpartial` one
  buffer it reuses across every call and expects overwritten, so a tail-appending `#read` would corrupt every
  streamed upload; `Dexpace::EndOfStreamError < ::EOFError` is load-bearing for the same reason, because
  `copy_stream` terminates only on an `EOFError` subclass (phase 3a's P3-1, P3-2). The ingress retag is
  `String#b`, never `force_encoding`, which raises on the frozen chunks a Rack body yields (phase 3a's design).
- **`SEAM-27`'s base-URL composition is a concatenation, not RFC 3986 reference resolution** —
  `URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets")` is `https://host/pets`, dropping the base path
  segment and the query the requirement keeps; `Dexpace::Operation` composes by hand. Reference resolution is
  `REDIR-13`'s, phase 6, and its spelling there is `URI::RFC3986_PARSER.join`, because `URI.join` is cop-banned
  (phase 2's design, §3 addendum A1, deviation P2-3); phase 7c's `Dexpace::URL.resolve(base, reference)`
  wraps the same call for `PAGE-19` and answers `nil` where the reference cannot resolve — reference
  resolution, never composition, and `Operation` must never call it (7c's P7-3).
- **`Response#body_string` is the SDK's one decode boundary, and it is three steps, not one** — resolve the
  charset through `MediaType#charset` (already `nil` for absent or unknown), **retag** the BINARY bytes with
  3a's `#read_string(encoding)`, then transcode with the target **named**,
  `encode(encoding, invalid: :replace, undef: :replace)`. Design §3.1's one-step sentence mangles every
  non-ASCII byte and a target-less `#encode` follows the host's `Encoding.default_internal`; the sentence's
  correction is amendment `C1` in `docs/deviations.md`'s amendment set, and the suite's hostile-global tests
  are what catch a revert (phase 3b's Task 8).
- **A body closes exactly the sources it opened, and `close: true` at `Body.stream` forces single-use** —
  the body layer's ownership rule (design §10.12, `BODY-8`) is deliberately not the I/O layer's
  wrapping-takes-ownership rule (`IO-6`); a body that closes its stream cannot rewind it, so
  `StreamBody#replayable?` needs the `pos`/`seek(pos)` probe to have said yes, a known length within the
  ceiling, **and** no ownership transfer. `ChunkedBody` takes no `replayable:` keyword and never will
  (P3-19), and `FileBody` defines no `#to_path`, which would make `IO.copy_stream` ignore its window (P3-17).
- **Every body that can occupy `Response#body` answers `#source` and `#close`** — `ResponseBody` with the
  same handle every call, `ResponseLoggingBody` with its regime's accessor, `BufferBody` with a fresh view per
  call and a no-op close — because `Response#close`, `#body_string` and `#body_bytes` and
  `Body.buffer_bounded` are written against exactly those two members (P3-23). A fourth thing put in that
  slot answers both or does not go there.
- **Every place core re-raises an error it is carrying rather than one it just rescued spells it
  `raise error, cause: nil`** — a bare `raise error` on an error whose `#cause` is `nil` assigns whatever
  exception is in flight as its cause, and `$!` is non-`nil` inside anything called from a *caller's* `rescue`,
  so `RECOV-10`'s "unchanged" rethrow, the error-mapping step's raise and `Hooks.notify`'s re-raise all carry
  it; `cause: nil` suppresses the assignment and never clears a cause a caller's own `raise` already made
  (phase 4b's design, verified fact 5; `docs/knowledge/notes/pipeline.md`).
- **The suppressed-exception trail lives on `Dexpace::Suppressible`, not on `Dexpace::Error`, and
  `Dexpace.attach_suppressed` `extend`s a caller's exception with it** — every primary `RECOV-12`,
  `close_quietly(onto:)` and `Hooks.notify` hand it is a caller's error, `rescue M` matches a module reached
  through a singleton class, so extending with the rescue root would widen `rescue Dexpace::Error`; the trail
  is a frozen array replaced on every attach, rendered through `#detailed_message` (never `#full_message`,
  which the default printer does not call), read off anything with `Dexpace.suppressed(error)`, and a frozen
  primary is a documented no-op (P4-12, P4-13, P4-14).
- **`Dexpace.each_cause` is the one cause walk, and its visited set is `{}.compare_by_identity`** — never an
  `Array` (`Exception#==` is structural and truncates a chain of two equal-looking errors) and never a `Set`
  (a caller's `hash`/`eql?` override defeats it); the cycle it guards is reachable only through a caller's
  `#cause` override, so the fixture is two never-raised instances chained through one, because a raise-built
  pair is not `==` on 3.2.11 and stops discriminating there (`XCUT-9`; phase 4b's design, verified fact 7).
- **A step either drives once through `Cursor#call` or forks for every drive through `Cursor#fork`, never
  both on one cursor** — `#call` is single-use and `#fork` after it raises `Dexpace::PipelineError`, so a
  pillar step that re-drives (redirect, retry) forks for the first drive too; a fork is what writes
  cursor-scoped state, and a first drive on the un-forked handle would have no stage slot to write. The
  reuse guard is an unsynchronised flag and detects a *sequential* second call only (P4-33, P4-39).
- **Cursor-scoped state is keyed by `(stage, key)`, written only as `Cursor#fork(state:)` into the forking
  pillar's own slot, and read as a frozen `Hash` through `#state(stage)`** — there is no state-setting
  method on the cursor, so a `RETRY` step between `REDIRECT` and `AUTH` cannot write the value `AUTH`
  reads under `Stages::REDIRECT`; that is what makes phase 6's cross-origin marker structurally
  unforgeable (P4-28, P4-29; `docs/knowledge/notes/pipeline.md`).
- **The stage set is closed at sixteen, structurally** — `Dexpace::Pipeline::Stage` has no public
  constructor and its `#with` refuses, so `Stages.of` and the sixteen constants are the whole population,
  a caller cannot add a pillar, and both runtimes flatten through one `Stages::ALL` (P4-32; `PIPE-28`).
  `Data#dup`, `#clone` and `Marshal` stay public and yield a copy that is `==` a constant and not `equal?`
  to it, so `Entry.build` and `Builder#resolve` resolve every `Stage` they are handed through `Stages.of`
  and the builder's identity comparisons over stages hold (P4-58). The runtimes are deliberately not
  `Object#freeze`d: `PIPE-27`'s close latch writes an ivar.
- **A public `Data` follows the construction pattern without exception; only a `private_constant` snapshot is
  exempt** — `Registry::State`, `Registry::Claim` and `Cancellation::Source::State` are `Data` without `Model`
  and without `.build`, because a snapshot has no public constructor and no derivation (phase 2's P2-9).
- **A frozen `Data` cannot carry a close latch, and a context needs none** — `Dexpace::Closeable`'s flag flip
  raises `FrozenError` on every supported Ruby, so `Context#close` is `store.release(self)` and idempotent
  through the store: `ContextStore#release` clears a slot only when its occupant is the closing context by
  **`equal?`**, never by `==`, because the call key participates in value equality and two contexts with one
  pinned key are `==` and not `equal?` (`CTX-9`, phase 4a's P4-4). The store is a strong `Hash` under one
  `::Thread::Mutex` with the drain inside the same `synchronize` as the insert; the eighth custom cop,
  `Dexpace/NoWeakReferences`, refuses `ObjectSpace::WeakMap`, `ObjectSpace::WeakKeyMap` and `WeakRef` in every
  gem's `lib/`, because `CTX-19` makes the cap and not the collector the leak backstop (P4-10). Construction
  registers nothing; only the two promotions call `#set` (`CTX-17`).
- **The configuration chain's precedence inverts Ruby's convention: an explicit override, then the
  environment, then a property, then the default (`CFG-1`)** — a property set through `Dexpace.configure`
  is the *third* tier, below a process environment variable of the same normalised name, and the key
  normalisation is `downcase.tr("_", ".")` on the property side only (`CFG-3`); `Configuration#string` is
  the one lookup every typed accessor routes through, and an empty override or property value is an
  answer while an empty environment value is absent (`CFG-2`, which names that tier alone).
  `Dexpace.configuration` is a lock-free read of a frozen snapshot; `Dexpace.configure` builds outside the
  mutex and swaps inside it, so a block that reads the slot cannot deadlock the non-reentrant mutex
  (`CFG-13`, `XCUT-11`; phase 5a's design).
- **`Dexpace::Clock#sleep` is a per-call `::Thread::Queue#pop(timeout:)` woken by the cancellation
  token's `#on_cancel` push, never `Kernel#sleep`** — `Kernel#sleep` cannot be woken without
  `Thread#raise`, which is banned; the token is re-asserted after the wake, so a cancel during the wait
  raises `Dexpace::CancelledError` and a wait that elapsed returns `nil` (`CFG-15`, `CFG-17`). The same
  timed pop is the deadline on `Future#wait` / `#value` / `Completer#await`, which expire by
  `request_cancel(:deadline_expired)` — settling the completer, never raising past it — and
  `Dexpace::Async.delay` raises `SeamError` without a `Fiber.scheduler` rather than blocking a thread
  (`CFG-18`; phase 5a's P5-9, and P5-52 for the `true` it settles with).
- **`Time#httpdate` formats and `Dexpace::HTTPDate.parse` parses; `Time.httpdate`, `Time.parse` and
  `Time.rfc2822` are never called in core** — the stdlib parser accepts the obsolete RFC 850 and asctime
  forms `CFG-31` refuses, and `Time.utc` silently normalises `31 Nov` and `29 Feb 1995` to the next day, so
  the parser round-trips every component it built (`CFG-30`, `CFG-31`; phase 5a's P5-54). The formatter's
  English names are CRuby's own tables and never the locale — verified under a `de_DE.UTF-8` `LOCPATH` on
  3.2.11, 3.4.10 and 4.0.6.
- **`Dexpace::UUID.generate` draws from a `::Random` in `Thread.current[:dexpace_prng]`, never
  `SecureRandom`** — `securerandom` is allowlisted, so the require gate would not catch the substitution;
  `uuid_test.rb`'s text scan does. `Thread.current[]` is fiber-local, which is the point: one generator per
  execution context and none shared (`CFG-32`).
- **`ContextStore.default` is built on its FIRST call, under one `::Thread::Mutex`, reading the configured
  cap then — and reading it OUTSIDE the lock** — phase 4a's load-time assignment could never see a
  `Dexpace.configure` at boot, and an unsynchronised `@default ||= new` publishes one store per first
  caller under a slow construction (sixteen for sixteen; `context_store_config_test.rb`); the two seams are
  caller-supplied callables and never run under the non-reentrant mutex, only the `||=` does, and the
  published reference is read lock-free after that. A configure after the first promotion does not resize
  the store, and neither does `reset_config!` (`CTX-11`; phase 5a's P5-55). The materialisation ceiling is the
  other way round: `Dexpace::IO.max_materialized_bytes` is read per call, so the live configuration governs
  every materialisation and `IO::MAX_MATERIALIZED_BYTES` is only the default and the fallback (P5-56).
- **The no-op instrumentation singletons are frozen instances of private classes, and every method on
  them works on a frozen receiver** — `NO_SPAN`, `NO_TRACER`, `NO_TRACER_FACTORY`, `NO_SCOPE`, `NULL`,
  `NO_METER` and its two instruments write no ivar and answer a constant or `self` from arguments already
  on the stack, which is also what `OBS-25`'s "selecting a no-op path MUST NOT allocate per call" wants;
  the suite asserts it as a two-loop `GC.stat` delta of exactly zero, with only frozen constants, Symbols
  and Integers crossing the loop, because an inline literal at the call site allocates whether or not the
  callee does (`test/support/allocation_delta.rb`; phase 5c's design, verified fact 1).
- **No SPI method in the instrumentation subsystem takes a `**` keyword splat — every attributes parameter
  is one named optional keyword (`attributes: nil`)** — a splat allocates a `Hash` on every call including
  one passing nothing, which is the spelling `opentelemetry-api` and every Ruby metrics library uses;
  the phase-0 cop `Dexpace/NoKeywordSplat` refuses it over every gem's `lib/` (P5-42).
- **The diagnostic context is written per key with `Fiber[k] = v` and never with `Fiber#storage=`**, which
  warns on every call at the default level on every supported Ruby; the keys are `Symbol`s because
  `Fiber["k"]` raises `TypeError` on 3.2 and 3.3 and only interns from 3.4; and **`Fiber[:k] = nil` deletes
  the key on 3.3 and later but retains it with a `nil` value on the 3.2 floor**, whose whole `Fiber` API
  is `[]`, `[]=`, `storage` and `storage=` — so `OBS-23`'s "remove it if previously unset" is a removal on
  3.3+ and a nil-valued key on 3.2, which `Fiber[]` and `OBS-10`'s null-skip both read as absent
  (P5-49, P5-72; `docs/knowledge/notes/observability.md`). The current-span slot holds one immutable span
  reference and the previously-active span lives in `Scope`'s ivars on the call stack, never in a stack in
  fiber storage: copy-on-write protects the slot, not the object in it (R13).
- **Core wraps no tracer, meter or HTTP-tracer callback in a `rescue`** — `OBS-20` carves those calls out
  of the log-emission containment, so a throwing tracer propagates and can fail the request (`OBS-30`), and
  the two block forms in `Tracing` restore through `ensure` regardless; a `rescue` added there is a guard
  the suite runs red. `Tracing.activate` returns the cached `NO_SCOPE` on an **identity** test — the span is
  already current — never on the recording flag, which would leave a recording span un-restored under a
  non-recording one (P5-47).
- **Redaction happens on the way into the record, by the field's NAME, and never at the sink** —
  `url.full` goes through `Redactor#url` and every `http.request.header.*` / `http.response.header.*`
  key through `OBS-18`'s name gate first (a name outside the allow-list stores the `REDACTED` marker or,
  in omit mode, nothing) and then, for an allow-listed name, through `#header_value`; the table is the
  private `ReservedKeys` and all three of `OBS-5`'s sources meet it — a per-event field at `Event#field`,
  the logger's global context once at `Logger.build`, the folded diagnostic context at `Event#emit` — so
  a caller who writes `logger.event(Severity::INFO).field(Keys::URL_FULL, raw)`, puts a credential
  header in `context:` or sets `Fiber[:"url.full"]` gets exactly what the step gets, whatever the sink
  does with it, and a sink is never trusted to redact (`OBS-11`–`OBS-18`, `OBS-39`; P5-102, P5-104 —
  the private `Emitter` writes every header and gates nothing). The redactor reassembles from
  `URI::RFC3986_PARSER.split`'s nine raw components and never through `URI#to_s`, which drops a default
  port `OBS-14` forbids dropping (P5-91); `#url` is total and answers `"[malformed url]"` on any
  `StandardError`, `#header_value` always a String and never the sentinel (P5-25, P5-26), and userinfo
  is `***:***@` on every route of both — a network-path reference's authority, and in a value the
  parser rejected EVERY `//`-authority wherever it sits, whatever `HTTP-19`-admitted bytes precede it
  (a leading OWS, RFC 3986 Appendix C's own `<…>`, quotes, a word, an NBSP, obs-text, a first URL),
  because a rejected value has no grammar left to honour and a tolerated prefix set is always one prefix
  short — where `OBS-11`'s "unconditionally" overrules `OBS-16`'s "returned verbatim" (P5-100, P5-105,
  P5-107); what the parser accepts without an authority (`http:///u:p@h/p`, a path spelling a second
  authority) is `OBS-14`'s verbatim path. A multi-valued header is redacted per value before the `", "`
  join — the `Emitter` hands the list over unjoined (P5-108). A warning that names a URL names it through
  the redactor too: the proxy resolver's `Kernel#warn` and its config diagnostic show
  `http://***:***@proxy.corp`, never the raw `HTTPS_PROXY`, a quoted or bracketed one included (P5-103,
  P5-107). The default header
  allow-list is twenty-six names with every credential and challenge header absent, the query
  allow-list is exactly `{api-version}`, and userinfo is redacted with no policy member able to reach it
  (`XCUT-19`).
- **The logging sink is a duck type — `#debug`/`#info`/`#warn`/`#error` and their four predicates —
  and core never `require`s `logger`** — `NULL_SINK` is a frozen instance of a private class, the RBS
  interface is `_Sink`, and the stdlib `Logger` is a structural superset a host passes in; the bare
  name `Logger` inside `module Instrumentation` is this SDK's facade (P5-38), which is why every
  reference from outside that namespace is written `Instrumentation::Logger`. `NullSink`'s four writers
  declare an anonymous `&` they never yield: a method that declares no block and is handed one warns
  "the block passed to … may be ignored" under `-w` on 3.4+, and that warning is suppressed
  process-wide once any same-named block-taking method is compiled, so `test:gems` cannot see it and
  only a per-file `ruby -w` can; an unreferenced `&` allocates nothing and `block_given?` does not
  count as use (phase 5b's checklist, item 27).
- **`Event#emit` claims its once-only latch under the logger's `::Thread::Mutex` and releases it BEFORE
  calling the sink** — the mutex is non-reentrant, and a sink that logs through the same logger from
  inside its own write is a second event on the same mutex; the suite drives exactly that sink (`OBS-8`).
  A disabled severity returns the shared `Event::INERT`, whose builders return `self` and write nothing,
  measured at `0.0` allocations per chained call (`OBS-1`); the collision warning is once per logger and
  gated on `sink.debug?` before the latch is claimed (`OBS-40`).
- **Every log emission in core runs inside `Instrumentation.contain`, and no tracer, scope or meter
  call ever does** — `contain` swallows `StandardError` only, reports it as one WARNING
  `http.instrumentation.log` diagnostic and swallows a failure of that report with no second attempt
  (`OBS-20`, `XCUT-20`); the step's `Tracing.correlate`, `span.finish`, `counter.add` and
  `histogram.record` sit outside it, in the `ensure`, so a throwing meter fails the request and a
  raising sink cannot. The async step closes its scope on the caller's fiber at the end of the head and
  carries the diagnostic context into the settlement with `Diagnostics.capture` / `.with` (P5-93);
  `.capture` compacts nil-valued keys so the floor's retained nils never travel (P5-97). Its settlement
  work is registered on the SOURCE future at every level and never on the `Future#then`-derived one,
  whose callbacks run inside `#then`'s own rescue where a meter's raise would vanish; and the span's
  finish and the two instruments have exactly one owner — the head's `ensure` only when the head raised
  before the chain handed back its future, the settlement callback otherwise — so an inline settlement
  that raises is never torn down twice (P5-109).
- **One calculator, two budget policies, split by file** — `Resilience::Policy.backoff_delay` takes no
  total-timeout parameter and `Policy.budget_remaining` is a separate function that only
  `RecoveryRetry` names; `retry_step.rb`, `async_retry_step.rb` and `retry_step_helpers.rb` never spell
  `budget_remaining` or `total_timeout`, and a text scan in `retry_step_test.rb` is the guard, so
  `RETRY-28`'s prohibition on the stage stack is a property of the source and not a runtime check
  (P6-5). The configured retryable-status set is consulted alone — `Policy.retry_eligible?(status,
  set:)` has no baked-flag parameter, so the AND `RETRY-37` forbids is a method that does not exist —
  and every delay literal lives in `Policy` (`RETRY-13`; the same suite scans for a second one).
- **The baked flag is `ProtocolError#retryable_by_status?` and never `#retryable?`** — `#retryable?` is
  `XCUT-6`'s open capability, the one `Policy.throwable_retryable?` probes over every cause; a
  `ProtocolError` answering it would let the baked set override the configured set whenever the error
  is wrapped, so the two questions carry two names (P6-10). The capability query has a stated blind
  spot: a bare stdlib I/O or timeout error escaping an adapter *unwrapped* classifies not retryable,
  which is why phase 8's adapters must wrap what they let escape in something answering `#retryable?`
  (P6-4; `docs/first-release.md`'s release-path entry).
- **Every pillar step forks for every drive, the first included, and the two retry drivers are the
  first two built that way** — `RetryStep` and `AsyncRetryStep` never call their own cursor's `#call`
  (a fork is what has a stage slot to write; `RetryFixtures::RecordingWrapper` counts forks and calls
  through the real driver), re-send the same frozen request through a fresh fork, check the
  cancellation token at the top of every attempt (a zero-length `Clock#sleep` returns before its own
  token check), resolve the delay from the still-open response and close it before the wait, and
  attach the whole prior trail to the surfaced instance through `Dexpace.attach_suppressed` — the
  carried raise spelled `raise error, cause: nil`. `retries_exhausted` fires only when a RETRYABLE
  failure met a spent budget; a failure that was never retryable is not an exhausted retry (5c's
  `ordering_test.rb`, third case; P6-58).
- **The async retry driver's delay needs a scheduler, and a zero delay completes inline** —
  `AsyncRetryStep` waits through `Async.delay`, which raises `SeamError` SYNCHRONOUSLY for a positive
  delay with no `Fiber.scheduler`; the pump's fence turns that into a failed future carrying the trail,
  never a blocking sleep (R2's third route). Its loop is a re-arm-flag trampoline, not a callback that
  calls the next attempt: `Future#on_settle` runs inline on a settled future, so every scripted
  downstream and every zero-length delay settles inline and a recursive pump overflows at ~1,500
  attempts on every interpreter; `async_retry_step_test.rb` measures `caller.size` flat across 2,001
  (P6-54). A fatal-family error that ARRIVES as a settlement meets no rescue arm and is delivered
  unclassified before the decision runs (P6-55). The driver installs, reads and closes no scheduler.
- **`Pipeline#call` and `AsyncPipeline#call` take one optional `bundle:` keyword beside the transport
  SPI's three positionals, and `Cursor#bundle` carries it across every fork** — `Bundle::NONE` by
  default, validated a `Bundle` at `Cursor.build`; 5b's `Step#open_span(request, bundle)` takes the
  bundle's tracer factory when it is not `NONE` and correlates over the same bundle, while the meter has
  no bundle source (P6-51). It is NOT the retry step's HTTP-tracer source: `OBS-29`'s per-operation
  tracer comes from `http_tracer_factory:`, called once per operation with the cursor (or the request
  on the recovery stack), because `Bundle#tracer_factory` produces span tracers (P6-7).
- **`0.0 * Float::INFINITY` is `NaN`, and `[NaN, 8.0].min` raises** — Ruby's float saturation covers
  every backoff overflow but a zero initial delay at a large attempt, so `Policy.backoff_delay` answers
  zero before taking the power (P6-53), and `Random#rand` raises `Errno::EDOM` over an infinite bound,
  so the reset jitter is drawn only over a finite band. `RetrySettings#random` defaults to the
  `::Random` CLASS, not a shared instance (P6-52).
- **A cancellation is never retryable, structurally; a negative CONFIGURED retry count is clamped where
  it is read; and the pacing parser's digit runs are bounded** — `Policy.cancellation?` walks the cause
  chain for a `CancelledError` and is consulted by `Policy.retryable?` and by the stage drivers' decision
  BEFORE the re-sendability gate and before a caller's `should_retry`, so a predicate answering `true`
  never sees a cancellation and a transport that wrapped the token's raise in its own retryable error is
  terminal on all three drivers (P6-60). `RetrySettings.build` clamps a negative `MAX_RETRY_ATTEMPTS`
  to the default through `Policy.effective_max_retries` and logs it once through its `logger:`
  keyword — read at build, never held — while an explicit negative `max_retries:` is `RECOV-34`'s
  refusal (P6-59). `PacingParsers`' grammars admit at most fifteen digits per run and a 64-byte value:
  an unbounded `String#to_f` over a 10 MB header cost seconds and, past ~309 digits, emitted Ruby's
  out-of-range warning that the `-w` suite turned into an error `Policy#parse_form`'s fence swallowed —
  `WarningCapture`, not the raiser, is what a no-warning assertion needs (P6-61). The sync `RetryStep`
  emits `attempt_failed` inside the same `RETRY-35` fence as the delay resolution and `retries_exhausted`
  inside the same fence as the decision, as the async pump always did on both of its paths, so a
  throwing tracer never leaves a superseded or a terminal error-status response open; and the async
  driver's "never a blocking sleep" is asserted, not stated — the async wait tests read `clock.sleeps`
  off the recording `FakeClock`, which is the only thing that turns a `Clock#sleep` slipped in beside
  `Async.delay` red, since that clock records and returns.
- **A `private_constant` of `Dexpace` is reachable only by its BARE name from a full-nesting body** —
  `Dexpace::BoundedMap` raises `NameError` even from inside `module Dexpace`, and the compact
  `module Dexpace::Auth::X` form cannot see it at all, so `DigestHandler` writes `BoundedMap.new(cap:)`
  inside `module Dexpace; module Auth; class DigestHandler` and nothing else works on any supported Ruby
  (`docs/knowledge/notes/execution-context.md`; 6c's P6-4). The nonce counter is one per handler, its cap
  a constructor keyword defaulting to `AUTH-19`'s 1024 and read from no configuration chain, and the
  increment is `BoundedMap#update` — one read-modify-write under the map's own mutex, which is what makes
  `AUTH-24`'s non-duplicated counts true; `bounded_map_test.rb` proves it deterministically with a forced
  interleaving, never with a race that "usually" fails.
- **`BearerStamper#call` reads its cached token with NO lock, and `#refresh!` calls the provider WHILE
  HOLDING the credential's mutex** — the reference is written once under the lock and the `BearerToken` it
  points to is frozen, so the lock-free read is safe by publication on every Ruby; and the lock-across-fetch
  is `XCUT-12`'s one sanctioned exception to "never hold a mutex across a suspension point", because
  serialising the fetch is what single-flight means and the lock is this credential's own (`AUTH-34`). The
  async stamper holds the same lock only to register a `Completer` and fetches outside it; `AUTH-37`'s three
  zones are fresh (settled, no fetch), expiring (stamped now, background refresh never awaited, a failure
  logged as `Events::AUTH_REFRESH` and nothing else) and expired (a `Completer` of the request's own, settled
  from the one coalesced fetch's `#on_settle` and never a `Future#then` derivation of it — `#then` wires the
  derived future's cancellation back to its source, and the source is the slot every coalesced request
  shares, so one request giving up would cancel them all; a cancelled waiter is detached alone and only the
  provider's own settlement settles the slot, a cancellation there forwarded as a cancellation; 6c's P6-86).
  A nil, non-token or already-expired token, or one whose `Bearer <token>` wire form the outbound header
  grammar refuses — a trailing newline read off a file, which could never be sent and so never be evicted
  by a 401 — raises `Auth::ProviderError` from inside the lock with the cache untouched, and fails the
  async waiters the same way with the slot freed, so the next call fetches again (`AUTH-35`; the fourth
  rejection is 6c's P6-87).
- **Basic is `["u:p"].pack("m0")` over the UTF-8 bytes and Digest is `::Digest::MD5` / `::Digest::SHA256`
  with `::SecureRandom.hex(16)` for the cnonce** — `base64` is bundled from 3.4 and refused by the
  require allowlist; `digest` and `securerandom` stay default through 4.0 and are allowlisted, and the
  smoke-suite constant snapshot preloads `digest` so the top-level `Digest` it defines is not read as a
  leak (`AUTH-14`, `AUTH-20`; design §10 entry 7). A Digest challenge whose `realm`, `nonce` or `opaque`
  the outbound grammar cannot carry is declined, never raised from the header write, and a non-ASCII
  username goes out as RFC 7616 §3.4's `username*=UTF-8''…` (6c's P6-76). Digest hash inputs are
  transcoded to UTF-8 under `charset=UTF-8` and to ISO-8859-1 otherwise, and a credential either branch
  cannot represent raises `Auth::UnencodableCredentialError` naming THAT branch's encoding — never
  `:replace`, and never a UTF-8-tagged value with an invalid sequence hashed as it is, which `encode` to
  the same encoding passes through unvalidated (`AUTH-21`; 6c's P6-1, P6-84); the credential is
  materialised BEFORE the nonce count is taken, so a refused attempt consumes no `nc`. **That failure,
  and `BasicHandler`'s `InvalidArgumentError` for a field UTF-8 cannot carry, are raised `cause: nil`
  with the value's own encoding as `#source_encoding` / in the message instead** — Ruby's conversion
  error names the offending character (`U+65E5 from UTF-8 to ISO-8859-1`) or byte of the secret, and
  `#full_message` renders a cause on every supported Ruby, so the styleguide's "the original as the
  `cause`" rule yields to `AUTH-8` for a credential (6c's P6-85, `docs/knowledge/notes/error-handling.md`).
- **A `Data` that carries a secret overrides `#pretty_print` beside `#to_s` and `#inspect`** — pp.rb gives
  `Data` its own `#pretty_print` over `members` and never consults an `#inspect` override, so
  `pp credential` printed the token with the two overrides alone; a plain class pretty-prints through
  `#inspect` and needs no third (`AUTH-8`; 6c's P6-72, `docs/knowledge/notes/authentication.md`). The
  real fields stay intact: `#to_h`, `#members` and `#deconstruct_keys` still expose them, which `AUTH-8`
  permits.
- **The AUTH step forks for every drive and reads the cross-origin marker off `cursor.state(Stages::REDIRECT)`,
  never off a header** — the check runs FIRST, before the HTTPS guard and before any stamp or fetch, so a
  plaintext foreign hop goes out credential-free instead of raising `Auth::HTTPSRequiredError`
  (`AUTH-28`, `AUTH-29`; design §10 entry 15). A 401 is replayed at most once, after the replacement
  body's `#replayable?` said yes and the 401 was closed, and a 401 with no `WWW-Authenticate` is returned
  unchanged without consulting the hook (`AUTH-30`–`AUTH-33`); `Step.build(stamper:, challenge_hook:,
  logger:)` is the whole constructor and `AsyncStep < Step` shares every branch through one private
  `#replayable?` — there is no `Auth::Replayability` module (6c's P6-71, P6-80).
- **The cross-origin marker is `cursor.fork(state: { cross_origin: bool })` on EVERY drive of the redirect
  step, `false` on the seed's own and on a same-origin hop, and never a request header** — only the
  REDIRECT pillar's fork can write the slot `Auth::Step` reads, so a server-supplied `Location` has no path
  to it and nothing on the request needs stripping (`REDIR-11`; design §10 entry 15). "Cross-origin" is
  `[scheme.downcase, host.downcase, port]` compared against the **seed** request's origin and never the
  previous hop's (`REDIR-8`), which is what keeps a same-origin sub-redirect on a foreign host from
  re-exposing the credential; `Authorization` is stripped before every re-issue regardless, as a
  `Headers::Builder#remove` and never a second add (`REDIR-7`), and the strip is cumulative — once a hop
  is cross-origin, `Cookie` and `Proxy-Authorization` are gone for every later hop, so the seed-versus-
  previous distinction is observable only through the marker.
- **A `Location` is resolved with `URI::RFC3986_PARSER.join` against the CURRENT hop, screened for an
  `http`/`https` scheme AND a host, and its userinfo cleared with `userinfo = ""` — never `= nil`, which is
  a silent no-op that forwards the server's credential** — `join` raises `URI::InvalidURIError` on a
  malformed reference and on nothing else: `mailto:`, `ftp:`, `javascript:`, `http:foo` and `http:///p`
  all resolve to something with no host or a scheme this client cannot dispatch, so the screen is what
  makes `REDIR-18`'s third trigger real; the raise is converted BY CLASS at the one site that logs the RAW
  value, never by message, which differs between uri 0.13 and 1.x (`REDIR-12`, `REDIR-14`, `REDIR-18`;
  `docs/knowledge/notes/redirect-handling.md`). `URI#to_s` elides an explicit scheme-default port and
  `URL.parse!` re-parses from it, so `Location: https://h:443/y` reaches the wire as `https://h/y` — the
  origin is unchanged; never assert that `:443` survives (P5-91, 6b's P6-96).
- **On a recognised 3xx the redirect step ALWAYS allocates the snapshot and consults a configured
  predicate, even with no usable `Location`, and `REDIR-17`'s cap is applied OVER the predicate's answer,
  never before it** — a nil target returns the response unfollowed whatever the predicate said
  (`REDIR-18`/`REDIR-19` are MUSTs no predicate waives), and a predicate cannot lift the cap (R9, 6b's
  P6-91). Every "return current" outcome hands the response back OPEN; the current response is closed
  BEFORE the next fork goes out (an ordering the suite reads through a callable transport entry as the
  follow-up arrives, since close counts pass for either ordering), and inside a frame that closes it
  before any raise — a downgrade, a non-replayable body, or a raising predicate — propagates
  (`REDIR-22`). `REDIR-6`'s gate is `Resend.replayable_body?` and never `.eligible?`, which folds in
  `RETRY-7` and would refuse a body-less `POST` 307 the allowed set admits.
- **`Pipeline.standard` and `AsyncPipeline.standard` are written over `Builder#install_preset` and nothing
  else, take a transport OR a `Pipeline::Builder` as their one positional, and the async one's
  `redirect: :unsupported` is a required keyword admitting nothing else** — `PIPE-24`'s empty-pillars rule
  is reachable through the constructor only because a builder can be handed in; the presets thread
  `settings:` and `http_tracer_factory:` to the retry step, `logger:` to every step, `level:` and
  `preview_bytes:` to the instrumentation step, and the async preset installs `Instrumentation::AsyncStep`,
  never the sync `Step`, whose `#call` would treat the future as a response (`PIPE-32`, `PIPE-39`,
  `REDIR-25`; 4c's R14).
- **The SSE line machine reads `BufferedSource#getbyte` and never `#read_line_utf8`, and `_ByteSource` is
  four methods** — `IO-14` keeps a lone `\r` as content where `SSE-2` makes it terminate a line, so
  `Dexpace::SSE::LineReader` recognises LF, CR and CRLF itself with a one-byte pushback (a lone CR cannot be
  handed back until the next byte says it was not CRLF), and `#read_line_utf8` ends v1 with no in-repository
  caller; `SSE-19`'s two caps are `MAX_LINE_BYTES` (1 MiB, checked before each append) and `MAX_EVENT_BYTES`
  (8 MiB of a block's raw lines, comments and unknown fields included), both REJECTING with
  `LimitExceededError` and never truncating, both per-reader keywords and no configuration key, and
  neither is `SSE-11`'s `MAX_RETRY_MS` — two caps, two constants, two checklist rows, because the line-cap
  finding conflated them once (P7-20, P7-21). The reader's source contract is the RBS interface
  `_ByteSource` (`getbyte`, `skip`, `peek`, `close`), never the class.
- **Inside `module Dexpace::SSE` the sentinel type is `Sentinel`, never `Signal`** — `::Signal` is a core
  module on every row and a bare `Signal` there would shadow it; `SKIP` and `DONE` are the two instances,
  `.new`/`.[]` private, `#with` refusing, `#pretty_print` overridden, and every outcome comparison is
  `equal?`, so a decoded model that `==` a sentinel is a value (P7-81, P7-23). `Event`'s member is `retry`:
  Ruby parses `retry = …` as the `retry` statement and refuses `super(retry: retry)`, so `Event#initialize`
  forwards with a bare `super` and validates the hint AFTER it through its own reader.
- **`Stream` owns exactly one `resource:` (the source by default) and its automatic release closes `self`,
  never `@resource`** — the clean end and a typed `DONE` go through `Dexpace.close_quietly(self, logger:)`,
  swallowing a release failure and reporting it as one `http.instrumentation.close` WARNING through the
  factory's `logger:` (nothing under `Logger::NULL`), while an explicit `#close` and every block-form exit
  (`break`, `Enumerable#first(n)` on `#events` and on the typed `#values` alike — the typed drive carries
  its own `ensure`, because the raw enumerator it runs is parked mid-`#next` and the Stream's never fires)
  go through `Closeable#close` and propagate; both flip one
  latch, which is `SSE-28`'s "even after an automatic release". The one failure path is `Stream#drive`'s
  `rescue ::Exception` → `close_quietly(self, onto:)` → bare `raise`; `#advance` reads `closed?` BEFORE
  every pull, which is what keeps a cross-thread close a clean end and the torn-down source unread. The
  facade is `.open`/`.owning`/`.borrowing` and deliberately not `.over`, whose polarity in
  `Dexpace::IO::BufferedSource` is the opposite (P7-25, P7-83, P7-86).
- **After a mid-stream failure, `BufferedSource.over`'s enumerator RESTARTS `#each`** — `Enumerator#next` on
  a fiber that died by exception starts over, so a second `#getbyte` re-delivers the body's first byte
  rather than nil or a second raise, on every row; the SSE facade never gets there because it closed itself
  first, and a bare `Reader` driven again after a raise would (phase 3a's residue, moved by phase 10 to
  `docs/first-release.md`). And the per-byte read path costs ~0.9 µs a byte through `BufferedSource#getbyte` — a mutex
  acquisition and a one-byte String per call — against ~0.3 µs through a plain duck, which is why the
  at-scale cap tests run over `FakeByteSource` and why a bulk path is a post-release trigger in
  `docs/first-release.md`.
- **A bare `ensure` that closes a page INVERTS `PAGE-13`/`PAGE-32`'s primary, and `$!` cannot repair it** —
  a close raised from an `ensure` replaces the in-flight consumer error as the primary (its `#cause`),
  and `$!` is thread-dynamically scoped, so it is a CALLER's unrelated error inside anything called from
  the caller's `rescue`; the pagination layer records the primary in a `rescue ::Exception => error` arm
  that re-raises unchanged and hands the local to `Page::Closing.close_walk`, which surfaces a close
  failure when nothing is in flight (`PAGE-15`) and attaches it otherwise; `$!` appears nowhere under
  `lib/dexpace/page/`, and `lifetime_test.rb` drives a walk from inside a caller's rescue (7c's P7-105).
  `Dexpace.close_quietly` is reached only where a requirement says swallow: `PAGE-26`'s drop, `PAGE-32`'s
  already-failed drain, `PAGE-30`'s rejected carry.
- **Every live page a walk holds is an ivar on the private `Page::Walk` — `@current` and the one-slot
  `@buffered` — never a local of an `Enumerator` block or a `#each` method** — `Items#each` opens a fresh
  walk per call and closes every page BEFORE yielding its first item (`PAGE-11`), so it is safe under an
  abandoned `#next`; `Pages` is single-use (a second `#each`, block or none, raises `Page::PageStateError`,
  a state error and never `InvalidArgumentError` — the roadmap's 2026-09-13 inbound bullet) and holds up to
  two pages, which `#each_page` or `#close` releases; `Walk#hold` writes the new page into its slot before
  closing the previous, `Walk#buffer` never displaces a staged page, and the engines' `Data`s hold no
  per-walk state at all (`PAGE-8`, `PAGE-12`, `PAGE-14`; 7c's P7-103, P7-111).
- **The built-in strategies take an extractor, `#call(response)`, and the words `Serde` and `JSON` appear
  NOWHERE under `lib/dexpace/page/` or in `page.rb` — YARD and strings included** — 7b's
  `tools/serde_boundary.rb` scans without stripping comments and its `page/**` rows went `GUARDED` on
  2026-09-20, when 7c was reconciled onto the tree that holds the gate — `page.rb`, `page/**` and both
  `sig/` mirrors, each violation naming "spec-forced boundary 5"; `page_test.rb` scans the fifteen files
  for the two tokens as 7c's own guard beside it (7c's P7-6, P7-108). The blocking engine passes `Cancellation.none` to the transport, never `nil`, which dies inside
  `Pipeline.standard`'s retry step (P7-102); `Page.next_request_from` screens a resolved target for an
  http/https scheme and a host, 6b's screen copied because `Redirect::Location` is private (P7-104), and
  reads RFC 3986 §4.4's two same-document forms — `<>` and `<#…>` — off the RAW target before resolving,
  never off the resolved URL, so `<//>` and the current URL spelled out are followed and the cap bounds
  them (P7-5, P7-117).
- **`AsyncPaginator`'s pump is a re-arm trampoline whose every callback is total, and its future settles
  with the page count, never nil** — a raising `on_settle` block escapes `Completer#fulfil` through
  `Hooks.notify`'s re-raise, so every body runs inside `Pump#guarded`; a pump re-entering itself from the
  settlement overflows at ~2,600 pages through the real `Completer`; with an `executor:` the FIRST dispatch
  is posted too, so a queued executor fetches nothing until it runs (`PAGE-29`, `PAGE-31`; 7c's P7-109,
  P7-112). `Future#value(deadline:)` is the bounded wait a test uses where "hangs" is the failure mode.
- **A witness answers `.dexpace_load(parsed, ctx)` and NOTHING ELSE makes one — `Serde.witness?` is a
  `respond_to?` on that one name, never on `#call`** — a `#call` fallback would make every lambda a witness
  and `SERDE-5`'s explicit witness and `SERDE-8`'s fail-fast construction both unenforceable; phase 2's
  `FakeCodec#load` drives its witness through `#call` because it predates the protocol, so a core handler
  test uses a named class answering BOTH. `ctx` is `Serde::DecodeContext`, never phase 4a's `Context`; the
  root frame names the decode's TARGET (`expected Pet (Hash) at /, got NilClass`) and `Codec#load` builds it
  with `DecodeContext.root(target: witness)` and screens nothing for nil, because `Tristate.of` and
  `Nullable.of` legitimately want a top-level null (`SERDE-13`, `SERDE-20`; 7a's design, `R2`).
- **The tri-state omission is core's `Native` walk, not each model's `#dexpace_dump`** — `Absent` dumps to
  the `OMIT` sentinel, a Hash entry that walks to `OMIT` is dropped, an Array element or a top-level value
  that does is `nil`, and anything non-native raises `SerializationError` naming the class, because
  `::JSON.generate(Object.new)` returns the object's `#inspect` as a JSON string rather than raising
  (`SERDE-15`, `SERDE-19`, `SERDE-20`; 7a's P7-9). `Present` validates in `#initialize` with `.new` AND `.[]`
  private, so `Present[value: nil]` is not a fourth state either, and `Model#with` keeps it closed on 3.2.
- **`Codec#load` reads UTF-8 unconditionally, validates it, and rescues `::JSON::JSONError` around the
  parse ALONE** — 3a's `#read_utf8` retags without validating and `::JSON.parse` accepts invalid UTF-8,
  returning a String whose `#valid_encoding?` is false (7a's P7-6); a `Dexpace::StreamError` is an
  `::IOError` and structurally outside `JSONError`'s ancestry, so `SERDE-12` holds without a discipline —
  and a `rescue StandardError` anywhere on that path is a guard the suite runs red. The whole text IS
  materialised under `Dexpace::IO.max_materialized_bytes` (`SERDE-27`'s clause is deviated, 7a's P7-1); a
  body above the ceiling is a `StreamError`, unwrapped, and the handler screens an empty body with
  `BufferedSource#eof?` — never `#content_length` (`-1` when unknown) and never a parser message, which
  differs between json 2.19.9 and 3.0. Both halves of that error's message are pinned — the target AND
  `no body` — because a witness's own shape failure over the drained `""` names the target too, so a
  target-only assertion passes with the screen gone (review round 1); an anonymous witness reads
  `an anonymous witness`, never an empty name.
- **`JSON::Coder` is constructed with keywords only, `strict: true` and `allow_duplicate_key: false` fixed by
  the codec, and `encoders:` NEVER forwarded** — json 2.19.9 takes a positional options Hash and SWALLOWS an
  unknown key, json 3.0 takes keywords and refuses one, a duplicate key is last-wins on 2.9, a warning on
  2.19.9 and a `ParserError` on 3.0, and `encoders:` is a keyword error on 3.0; the codec's own allowlist
  is what makes a typo one `InvalidArgumentError` and a duplicate key one `DeserializationError` across the
  range. The two fixed options are pinned at the KEYWORD level, never through the engine's behaviour —
  json 3.0.2, the bundle's version on every row, refuses a duplicate key by default, so a codec that
  dropped the option would stay green on every gate row and regress only at the 2.19.9 floor; a child
  process prepends a recorder onto `::JSON::Coder`'s singleton class and reads what `.new` receives
  (`codec_test.rb`'s `CoderKeywordsTest`). P7-7's require-time floor is likewise observable only OUTSIDE
  the bundle — every gate row runs the bundle's json, above the floor — so `json/floor_test.rb` drives it
  in a child process with `RUBYOPT` and the `BUNDLE_*`/`BUNDLER_*` keys cleared, pinning the
  interpreter's stock json (2.6.3 / 2.7.2 / 2.9.1 / 2.18.0 across the matrix, every one below the floor)
  with `gem` before the require; stock 4.0's 2.18.0 HAS a `JSON::Coder` and loads clean without the
  assertion, which is the silently-unpatched case it exists for. rbs 4.2.0 declares no `JSON::Coder` and
  json 3.0.2 ships no `sig/`, so the Steepfile's `:serde_json` target alone downgrades `Ruby::UnknownConstant` to
  `:information` and the ivar is typed `untyped` (NFR-11 admits no `::JSON` type in the gem's `sig/`
  either).
- **An adapter's require-time registration breaks every "starts empty on a bare require" pin in ONE
  `rake test:gems` process** — the runner loads every gem's suite together, so `Dexpace::Serde.resolve`
  answers the JSON codec in core's own suite; the two seam-iterating pins and `serde_test.rb`'s "starts
  empty" pin are asserted in a CHILD process that requires `dexpace` alone
  (`instrumentation/independence_test.rb`'s `IO.popen` shape), and `Registry#swap` restores `resolved` but
  never `factories`, so `serde_test.rb`'s two swap pins assert the override is GONE, never that nothing
  resolves (five pins the code invalidated, converted on 7a's code branch).
- **`Net::HTTP` holds one socket and one response state per instance, so the owning transport builds a
  fresh one for EVERY call and the borrowing one serialises** — `.build` constructs per call with
  `max_retries = 0`, an explicit nil `p_addr` AND `proxy_from_env = false` (`Net::HTTP.new`'s default is
  `:ENV`, which reads a lower-case `http_proxy` the SDK never resolved; `find_proxy` exempts loopback
  targets, so a proxy test names `192.0.2.1`, and it WARNS on an upper-case `HTTP_PROXY` with no
  lower-case one before that exemption — a warning the test base makes fatal, so every raw `Net::HTTP` a
  suite starts passes the same nil and the two R17 controls set `http_proxy` themselves), and applies
  this call's budget to all three knobs;
  `.using` asserts `max_retries == 0` and never assigns anything — endpoint, `use_ssl`, a knob — refusing
  a request that names another origin and a per-call `timeout:` instead (`TRANSPORT-15`, `XCUT-22`;
  8a's P8-15). The borrowed permit is a one-slot `::Thread::SizedQueue`, never a `Mutex`, because it is
  released on the producer's thread and `Mutex#unlock` from a non-owner raises; it is returned by the
  producer's own `ensure`, never by the bounded join, or a producer still holding the caller's socket
  past `JOIN_DEADLINE_SECONDS` would share it with the next exchange (P8-53).
- **The response pump adapts the head on the CALLER's thread before the producer reads a byte of body,
  and the producer never `break`s out of `read_body`** — `ResponsePump#head_or_raise { |head| … }`
  yields the native head and resumes the producer through a second `Queue` only when the block returns
  or raises; `ResponseMapper` deletes an unparseable `Content-Length` from the native head inside that
  block, because `Net::HTTPResponse#content_length` raises `Net::HTTPHeaderSyntaxError` on the producer
  the moment `read_body` runs (`TRANSPORT-27`; P8-51). A close makes the next push raise through the
  closed queue, which is what makes `Net::HTTP`'s own `transport_request` rescue close a half-read
  keep-alive socket; a `break` would leave the remainder to be read as the next response's status line.
  A pop that finds the queue closed is classified through the token — `CancelledError` when cancelled,
  `ClosedError` after a close, a retryable `TransportError` before any head — and is end of stream
  ONLY when the pump itself is open (P8-54). The cancellation subscription belongs to the pump for the
  life of the response, detached in `#release`, never to `Adapter#call`'s frame (P8-52) — and the pump
  asks the token BEFORE it starts a producer: `Cancellation::Source` runs an already-cancelled hook
  inline, so a token cancelled at construction gets a closed pump with no thread, no socket and the
  borrowed permit straight back, `#release` joins and detaches nil-safely, and `#produce` reads the
  latch before it exchanges (P8-64).
- **Every failure with no response goes through one classifier, and the token is asked FIRST** — a
  cancel delivered by closing the socket and a peer reset arrive as the same `IOError` with the same
  message, so no class or message test can tell them apart; then an SDK error passes unchanged; then a
  catch-all wrap as a retryable `Dexpace::TransportError` with the original as `#cause`, never a class
  list — of the families `Net::HTTP` raises only `EOFError` and `IOError` are `::IOError`, and
  `Socket::ResolutionError` does not exist on 3.2.11 (`TRANSPORT-3`, `TRANSPORT-4`, `TRANSPORT-20`; P6-4).
  `decode_content` is switched off by `[]=` re-assignment — `add_field` does not flip it — and the three
  auto-stamps `Accept`, `Accept-Encoding` and `User-Agent` are deleted, because `HTTP-6` makes the
  four-member `Request` the whole truth about what goes out (P8-2, P8-3).
- **`net-http`'s connect phase is `Timeout.timeout` below 0.7 and `TCPSocket.open(open_timeout:)` on
  0.9.1, and the first `Timeout.timeout` in a process starts a thread that lives for the process** — so
  on the 3.2, 3.3 and 3.4 rows the first test to open a connection was charged with a thread
  `DexpaceTestCase`'s teardown could not join; `test/support/net_http_warmup.rb` opens one connection at
  both adapter gems' test-helper load, before any count is taken, and a new gem's test helper that
  connects must require it too (P8-62). `supply_default_content_type` is absent on 0.9.1 and warns under
  `-w` on 0.4.1 and 0.6.0, so the adapter stamps `application/octet-stream` itself for a body-permitted
  method with no header and no media type — never `Net::HTTP`'s `application/x-www-form-urlencoded`
  (P8-4, P8-61). The gemspec's `net-http >= 0.4` has no upper bound: a default gem's version follows
  the interpreter, and the suite prints the active `Net::HTTP::VERSION` per row instead (P8-60).
- **`test:gems` loads every gem's test files into ONE `ruby -w` process, so a top-level test-support
  constant must be unique across all six gems' `test/support/` directories** — `tools/suite_runner.rb`
  runs them together so SimpleCov reports one aggregate figure (`NFR-5`), and a second
  `class RecordingSink` in an adapter gem re-assigns core's `RecordingSink::Entry`, an "already
  initialized constant" warning `NFR-6` makes fatal at load time; the gem's own `rake test` never sees
  it. The adapter gem's double is `NetHTTPRecordingSink` for that reason (8a's checklist, departure 35).
- **Under `async-http` a response does not outlive the reactor that produced it, every call needs a
  reactor on the calling thread, and a cancellation from another OS thread is marshalled through a queue**
  — `Sync { }` returns only when the reactor has no non-transient work left, and on its way out it stops
  the pool's transient gardener, whose `ensure` drains the pool and waits on every busy connection; the
  connection behind an unread body is busy, so a `Sync` that hands a streaming response out past its own
  end never returns (`TRANSPORT-29`'s eight-thread assertion found it; the 8c driver materialises the body
  inside its per-thread reactor, `P8-94`). `Adapter#call` outside `Async::Task.current?` settles
  `SeamError` through the future and creates no reactor (`P8-39`); `Async::Task#cancel` from a foreign
  thread raises `NoMethodError` and cancels nothing, so the token's hook pushes onto a `Thread::Queue`
  that a transient watcher task under the caller's task pops and acts on from the reactor's thread
  (`P8-91`) — the push total over the queue's close, because the source and the completer both run
  their hooks after stealing them and an exchange that finished in between has closed the queue,
  and the reason wrapped in `CancelledError` for the task's own `Async::Cancel` alone (`cause:`
  drops anything but an `Exception`; the adapter reads none back, the pivot being settled before
  the watcher acts); the owning adapter's clients are keyed by `(Fiber.scheduler, origin)` because one
  `Async::HTTP::Client` cannot serve two reactors on two threads (`P8-92`); `Adapter#close` retires every
  pooled resource **before** `pool.close`, which alone would drain and wait exactly as `Client#close`
  does (`P8-100`); and a native HTTP/2 body is closed through `close_quietly`, because `async-http`
  writes `RST_STREAM` before it transitions the stream and an `END_STREAM` in that window releases the
  pooled connection twice (`P8-101`). `Kernel#Async` inside a task IS that task's child on async 2.46
  (the design's fact 10 is stale), and on Ruby 4.0 alone the first `IO::Buffer` under a scheduler prints
  a once-per-process experimental warning that `test/support/async_http_warmup.rb` spends before the
  fatal hook can see it (`P8-98`).
- **A conformance assertion sends through `kase.settle(transport, request, options, cancellation)` and
  never `transport.call`, names no adapter, and waits with a bound** — what `TransportCase#transport`
  returns is the `SettleOnly` guard, whose `#call` raises, because the default `settle` IS
  `transport.call` and an assertion that called it would pass every synchronous run and fail only under
  an async driver; `borrow:` takes the fixture's PORT and returns a `BorrowedPair`, so the caller's own
  client is built in the driver and never in this gem; an adapter-specific vacuity is raised by
  measurement from the assertion, never written into the shared suite ("vacuous here, real there"
  breaks R16's "unchanged against both"); and `await_closed_connection` always carries a `timeout:`, so
  an adapter that never releases fails the assertion instead of hanging the run (`TRANSPORT-18`,
  `TRANSPORT-19`, `TRANSPORT-25`; P8-55, P8-56). `WireServer`'s `TCPServer.new("127.0.0.1", 0)` goes
  through an `untyped` local: rbs 4.2.0's `tcp_server.rbs` types the constructor
  `(?String host, Integer port)`, an optional positional before a required one, which Steep 2.1.0
  refuses for the two-argument call Ruby accepts.
- **A pooled worker clears its fiber storage at TWO boundaries — once at thread start and again after
  every task — and the suite reads a worker's context through `Diagnostics.capture`, never the raw
  map** — `::Thread.new` inherits the pool builder's `Fiber[]` at construction and `Diagnostics.with`
  merges on install, so without the first clear a caller's task runs with the builder's `tenant`
  underneath its own snapshot, and `.with` restores only `(prior.keys | snapshot.keys)`, so without the
  second a key the block itself wrote survives onto the next caller's task; on the 3.2 floor a cleared
  worker's raw storage is a map of nil-valued keys, which `Fiber[]`, `OBS-10`'s fold and `.capture` all
  read as empty, and a proof that the second clear is present must write a key the worker has never held
  (`ASYNC-9`, `ASYNC-10`; 8b's P8-20, P8-74). `.capture` carries core's `dexpace.current_span` slot with
  the diagnostic keys, so a span active on the caller is current on the worker — `ASYNC-8`'s purpose —
  and under the one-process `rake test:gems` another suite can leave a no-op span on the main fiber.
  **The floor is EVERY `::Thread.new` a gem keeps, the lazily spawned ones included**: the pool's timer
  thread is spawned by the first positive `#delay` from THAT caller's fiber, so without the same two
  clears and a per-delay `Diagnostics.capture` on the `Timer::Entry` every later delay's `#on_settle` and
  `#then` ran under the first caller's context — the design's own finding 1 at the gem's own door
  (`ASYNC-8` names callbacks beside work; 8b's P8-78, review round 2). A callback the timer runs on
  another thread's behalf — the shutdown handler on the closing thread — is installed and restored
  through `Diagnostics.with` and never cleared, because that thread's storage is not the timer's.
- **`Pool#post` never blocks and never lets a bare stdlib error escape, and `#delay` settles with `true`**
  — the submission queue is a `::Thread::SizedQueue` used with the NON-blocking push, so a full queue is
  `RejectedError` (backpressure) and a closed pool `Dexpace::ClosedError` (a lifecycle bug), both
  translated from the `ThreadError` and `ClosedQueueError` the queue raises at the one call site, which
  is what makes `ASYNC-2`'s "saturated executor" a case this adapter has at all and lets a worker re-post
  to its own pool without parking (P8-23); `Completer#fulfil(nil)` raises SEAM-16's refusal, so a
  `#delay` future settles with `ELAPSED = true` as 5a's `Async.delay` does, and a zero delay settles
  inline with no timer touched (P8-71). `#delay` and `.build` refuse a NaN, an infinite and a `Complex`
  duration or `shutdown_timeout:` with `InvalidArgumentError` — `real?` before `negative?`, `finite?` after
  it, `Numeric`'s own protocol — because a NaN answers false to both `negative?` and `zero?`, and one that
  reached the timer's deadline-ordered list killed its thread and turned every later `#delay` into a bare
  `ArgumentError`, while a NaN budget raised one out of `#close` with the latch flipped (P8-77; core's
  `Async.validate_delay` and `Clock::Guard.duration` shared the hole and phase 10 closed it the same way). Phase 2's
  `Bridge::AsyncOver` checks the token BEFORE dispatch as well as after, so a task cancelled while queued
  never reaches the transport — every "window" test gates on the double's `entered` queue before
  cancelling, or it is red three runs in twelve.
- **Both threads the pool owns rescue `::Exception` and never die, and `#close` is one bounded budget
  for the timer stop and the worker drain** — a worker's `SystemExit`, `Interrupt` or `ScriptError` is
  reported as an ERROR `http.instrumentation.hook` diagnostic inside `Instrumentation.contain` and the
  pool is never one worker smaller (P8-22, which departs from `RECOV-2`'s re-raise because on a worker
  "re-raise" means a silent death `report_on_exception` prints past every gate); the timer runs every
  callback under the same net, because `Hooks.notify` re-raises a caller's raising `#on_settle` out of
  `Completer#fulfil` on the timer thread; **both nets sit INSIDE `Diagnostics.with`, never around it**,
  so the diagnostic is folded with the caller's snapshot still installed and carries the caller's
  `trace.id` — a net around the `with` reports after the restore, with no id on the worker and the
  timer and the CLOSER's id on the closing thread (review round 3's R3-1); `Timer#schedule` after
  `#stop` refuses the entry through
  `on_shutdown` so a close racing a delay spawns no thread; the drain carries a non-nil exit sentinel and
  re-reads the clock because `Queue#pop` answers nil for a timeout, a close and a pushed nil alike; and
  `#close` takes no `cancellation:` because `Dexpace.close_quietly` calls it with none (P8-24, P8-25,
  P8-75). An `#on_settle` on a delay future runs on the TIMER thread, or on the closing thread when
  `#close` fails it — and a `#close` issued THERE, or from inside a posted task, completes: neither
  `Timer#stop` nor the drain ever joins the thread it is running on (`Thread#join` on the current
  thread raises `ThreadError`, which as first cut escaped `#close` with the latch flipped, no event and
  every other delay stranded; and a worker waiting for its own exit sentinel burned the whole budget),
  so the timer thread exits once the handler returns and the closing worker counts as drained and
  finishes its task afterwards (P8-76). The timer's mutex is never held across its `Queue#pop` wait, and
  the hazard is NOT the per-fiber one the plan named — the wait runs on the timer thread, which has no
  scheduler — but a cross-thread deadlock: `Timer#stop` parks on the mutex the parked thread holds and
  `#close` hangs, which `pool_delay_test.rb`'s `LockScopeTest` turns into two bounded-join failures.
- **`test:gems`' one process makes every top-level test CLASS name unique across the six gems too, not
  only the doubles** — core's `matrix_facts_test.rb` owns the bare `MatrixFactsTest` as a module, and a
  second `class MatrixFactsTest` in an adapter gem aborts the whole run at load with "is not a module";
  the pool gem's is `PoolMatrixFactsTest` and its doubles `PoolFakeTransport`, `PoolRecordingSink`,
  `PoolStubClock` and `PoolProbeScheduler` (8a's checklist item 35, widened by 8b).
- **`docs/deviations.md` is a gate input, not only a register** — `gates:ledger_audit` reads it against
  design §10 on every `rake`: row N's `IDs touched` must EQUAL the IDs §10 entry N names (a range
  expanded), and a row carrying a verdict must cite a `gems/…` path that exists and name only
  `Dexpace::` constants that resolve with core and every floor-admitted adapter loaded — so renaming a
  constant or moving a file a verdict cites turns the gate red, and a verdict citing only `docs/…` never
  passes (phase 10's `P10-2`, `P10-33`). A shipped `.rbs` likewise opens with the SPDX line on line 1
  and declares something (`gates:spdx_rbs`); an `.rbs` file with only comments is an offence.

## Public API surface

**Public means: a `Dexpace::` constant that has a YARD block and an RBS signature in its gem's `sig/`.** Anything
else is internal, whatever its Ruby visibility. `sig/` mirrors `lib/` one file per file and **ships inside each
gem**, so a consumer's `steep check` sees it.

- `rbs validate` and `steep check` gate it (`NFR-3`). Steep adoption is **target-by-target**, not
  repository-wide: core's public surface is strict, internal modules are added incrementally, and every
  relaxation is a named target in the `Steepfile` rather than a blanket ignore.
- The API lock (`NFR-4`) is a **diff of `sig/**/*.rbs` against the previous release tag**, failing when a public
  signature disappears or narrows without a major bump. Regeneration is a deliberate, reviewed act, never a way
  to silence an unintentional break.
- **RBS describes what someone wrote, not what Ruby defines.** `Data.define`'s generated readers,
  `define_method`, `method_missing` and a require-time `register` call are all invisible to it. So the RBS diff is
  paired with a **runtime surface snapshot**: a test that walks `Dexpace`'s constant tree and each class's
  `public_instance_methods(false)`, sorts, and diffs against a committed manifest — one per gem, each walked
  from `Dexpace` itself, so an adapter's manifest is what its entry file adds inside *or beside* its own
  namespace. Each catches what the other cannot see; changing exports means regenerating **both**.
- `NFR-11` is mechanised as an RBS scan asserting that no constant outside `Dexpace::` and a fixed stdlib
  allowlist appears in any public signature under `sig/` — which is why the async pivot had to be core-owned.
- YARD has an undocumented-public-method gate. A YARD block explains *why*; it never restates a signature.

## Phase workflow

The roadmap under `docs/work/mvp/` is an **index of phases, not a design** — it names each phase, its scope and
its requirement prefixes, and nothing else. The real work is per-phase: **brainstorm → plan → implement**, and
all three read the corpus first.

Every phase of the `mvp` delivery followed it, and the roadmap is done; a post-v1 delivery — one of §2.2's later
gems, say — follows it again under its own `docs/work/<delivery>/`, while release work and anything found
against the built tree go to `docs/first-release.md`.

1. **Start with what is already known.** Invoke the `knowledge-lookup` skill at the start of every phase and
   every numbered task, before writing a design doc, a plan or code. Its phase-start pair —
   `--origin note --brief` and `--section conflicts --brief` — is not optional: a plan that assumes an open
   design-versus-styleguide conflict is settled is the failure both queries exist to catch. Before the harvest,
   `--prefix-info` and `--gaps` are the substitutes, and a phase whose IDs come back as gaps must budget for
   reading the specification itself and say so in its design doc.
2. **Brainstorm on a branch off `main`.** `main` is the starting point for every phase — the `mvp` integration
   branch was retired on 2026-09-14, and `mvp` is now only the delivery name under `docs/work/`; brainstorming
   happens on its own branch so an exploratory design does not land on `main`.
3. **Three documents per (sub)phase**, all under `docs/work/<delivery>/phaseN[/phaseNx]/`, each keeping its
   `YYYY-MM-DD-` prefix: `…-design.md`, the plain plan `….md`, and `…-checklist.md`. A phase directory is
   `phaseN` with no hyphen; a sub-phase nests one deeper as `phaseN/phaseNx`. A document spanning a whole phase
   sits at the `phaseN/` level; one belonging to no phase sits directly under the delivery.
4. **They are written into `docs/superpowers/` and do not stay there.** The `brainstorming` and `writing-plans`
   skills hard-code `docs/superpowers/{specs,plans}/`, they are installed globally, and this repository cannot
   change them — so that directory is an inbox and `housekeeping` drains it. Cite the `docs/work/` path, the one
   the document will carry for the rest of its life, never the staging path.
5. **Implement against the plan's numbered tasks**, TDD: write the failing test, confirm it fails, implement,
   confirm it passes. Read design, plan and checklist before touching code.
6. **Record what the phase decided, in the right place.** A deviation goes in the phase document's own
   `## Deviation Ledger`, is consolidated into design §10, and is audited by `docs/deviations.md`. Work the
   phase postpones goes to no register: either the plan of the phase that will do it gains a numbered task,
   cited by path and task, or `docs/first-release.md` gains an entry under what v1 ships without, the release
   path or the post-release triggers — and the phase document records the reason and the pick-up condition
   beside that pointer. A finding the phase is not acting on is not registered either: it goes to the plan task
   whose scope it falls in, to phase 10's inbound list in the roadmap when it is audit-or-repair work against an
   already-planned phase (drained by phase 10; after it, `docs/first-release.md`), or to `docs/first-release.md`
   when it belongs to the release — and when it is in
   material the phase may write, it is simply fixed. **Never leave an aggregate register section inside the spec
   or the plan.**
7. **Housekeeping before handover.** Run the probe, fix what it reports, then apply.

Agents do not commit, push, or touch the remote unless the user asks for that specific action in that message.

## Documentation upkeep

Nothing gates `CLAUDE.md` or `README.md`. The `housekeeping` skill is the check, and it is hand-run, not a CI
step: run it after landing a phase, whenever `docs/superpowers/` has something in it, and before claiming the
documentation is current.

```bash
ruby .claude/skills/housekeeping/probe.rb                              # always first. Read-only, tested to be.
ruby .claude/skills/housekeeping/apply.rb                              # dry run
ruby .claude/skills/housekeeping/apply.rb --delivery mvp --phase 5a --write
```

The probe derives each repository fact **once, from the repository**, then checks every document that states it
against that one derivation — never one document against another. Nine checks: `inbox`, `root`, `claims`,
`readmes`, `links`, `registers`, `citations`, `guard`, `chapters` — the last, phase 10's, a requirement ID
attributed to a `docs/product-spec/` chapter that does not carry it. Exit code is 1 when anything is found.

The apply stage does exactly one thing: `git mv` from the inbox into `docs/work/`, so `git log --follow`
resolves each file across the move. It refuses the **whole batch** if any source or target is under a frozen
entry, if a target exists, if two inbox files land on one target, or if a source is untracked. It does not
repoint references and it does not commit — re-run `--only links,citations` and fix what they report in the same
change that staled them.

**Never rewrite prose to satisfy a check.** A tool that rewrites prose to make its own check pass produces
documentation that is true and useless at the same time. The probe says what is wrong and where; the judgement
about what the sentence should say is yours.

Frozen to every maintenance tool: `docs/knowledge/`, `docs/product-spec/`, `docs/product-spec.md`,
`docs/sdk-design-ruby/`, `docs/sdk-design-ruby.md`. That is a tested guard (`guard.rb`), not a stated intention.

**The counts the `claims` check reads out of this file.** Keep these sentences here and keep them true; the
probe compares each against the live tree, and a count written anywhere else in this file must match.

- Six gems exist under `gems/`, all at `0.0.0` and none published: `dexpace-core`,
  `dexpace-transport-net_http`, `dexpace-transport-async_http`, `dexpace-serde-json`, `dexpace-async-thread`
  and `dexpace-conformance`. Each has a gemspec reading `VERSIONS`, a `sig/` mirroring its `lib/` one file
  per file, a smoke suite, a README, a LICENSE copy and a per-gem `Rakefile`. `dexpace-core`'s `lib/` holds
  the phase-1 HTTP domain model, the phase-2 seam layer, the phase-3a byte-streaming layer, the phase-3b
  body layer, the phase-4a execution context, the phase-4b recovery layer, the phase-4c stage pipeline,
  the phase-5a configuration layer, the phase-5b logging facade and redaction, the phase-5c tracing and
  metrics layer, the phase-6a retry layer, the phase-6c authentication layer, the phase-6b redirect
  layer, the phase-7b server-sent-events layer, the phase-7c pagination layer, the phase-7a
  serialization layer and phase 8a's transport error — two hundred and twenty phase-1, phase-2,
  phase-3a, phase-3b, phase-4a, phase-4b, phase-4c, phase-5a, phase-5b, phase-5c, phase-6a, phase-6b,
  phase-6c, phase-7b, phase-7c, phase-7a and phase-8a files under `lib/dexpace/` beside phase 0's
  `version.rb` (7b's nine are `sse.rb` and the eight under `sse/`; 7c's fifteen are `page.rb` and the
  fourteen under `page/`; 7a's eleven are all under `serde/`, beside phase 2's three files there; 8a's one
  is `error/transport_error.rb`), every one mirrored in `sig/`, and every one of
  the two hundred and twenty but the nineteen `private_constant`s `hooks.rb`, `context/call_key.rb`,
  `recovery/ownership.rb`, `pipeline/sync_driver.rb`, `pipeline/async_driver.rb`,
  `configuration/parsers.rb`, `deep_value.rb`, `proxy/resolution.rb`, `instrumentation/render.rb`,
  `instrumentation/emitter.rb`, `resilience/pacing_parsers.rb`, `resilience/retry_step_helpers.rb`,
  `auth/validation.rb`, `redirect/origin.rb`, `redirect/location.rb`, `redirect/chain.rb`,
  `redirect/emitter.rb`, `redirect/reissue.rb` and `page/closing.rb` mirrored
  in `test/` (phase 7a's private constants all live inside public files and add none, and 8a's one core
  file is public with a mirror). `dexpace-serde-json`'s
  `lib/` holds the phase-7a JSON codec — `dexpace/serde/json.rb` and `dexpace/serde/json/codec.rb` beside
  phase 0's `version.rb`, both mirrored in `sig/`, the entry file mirrored in `test/` (with `floor_test.rb`
  beside it) and the codec by its five suites there — and its gemspec declares `json >= 2.19.9`, the one
  place that floor is stated. `dexpace-transport-net_http`'s `lib/` holds the phase-8a synchronous
  transport — nine files, the entry file and eight under `net_http/`, seven of them `private_constant`s,
  every one mirrored in `sig/` and in `test/` — and its gemspec declares `net-http >= 0.4`, a default gem
  declared as the `NFR-2` third-party half; `dexpace-transport-async_http`'s `lib/` holds the phase-8c
  asynchronous transport — eleven files, the entry file and ten under `async_http/` beside phase 0's
  `version.rb`, eight of them `private_constant`s, every one mirrored in `sig/` and every one but
  `async_http/exchange.rb` mirrored in `test/` (the per-call exchange is proven through the three
  behavioural suites that drive it) — and its gemspec declares `async-http ~> 0.104` as the `NFR-2`
  third-party half and a Ruby floor of 3.3 read from `VERSIONS`; `dexpace-async-thread`'s `lib/` holds the
  phase-8b async-runtime adapter — the entry file and three files under `thread/`, `rejected_error.rb`,
  `pool.rb` and `timer.rb`, the last a `private_constant`, every one mirrored in `sig/` and the two public
  ones in `test/` (`timer.rb` is proven through `pool_delay_test.rb` and `pool_test.rb`'s source scans) —
  and its gemspec declares `dexpace-core` alone, by design: the gem spends none of its `NFR-2` budget;
  `dexpace-conformance`'s holds the phase-8a conformance suite with phase 8c's two groups and phase 9's
  four further suites — **fifty-four** files beside phase 0's `version.rb`, twenty-five of them
  `private_constant`s, every one mirrored in `sig/` and every public one but `check.rb`, `levels.rb`,
  the four `*_case.rb` files and `wire_server/recorded_request.rb` mirrored in `test/` (each of those six
  is driven through the suite it serves, and `levels.rb` through `test/gates/requirement_levels_test.rb`)
  — and its gemspec declares `dexpace-core` alone, its
  `socket` and `tempfile` requires carried by the allowlist's exceptions. Every gem under `gems/` is real:
  no phase-0 skeleton remains, and the third-party half of each `NFR-2` budget arrived with the phase that
  wrote the code needing it — 7a's, 8a's and 8c's (8b's spends none).
- There are eleven phase directories under `docs/work/*/`; `mvp/` is the only delivery, and it holds
  the v1 roadmap, `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`, plus `phase0/`,
  `phase1/`, `phase2/`, `phase3/`, `phase4/`, `phase5/`, `phase6/`, `phase7/`, `phase8/`, `phase9/` and `phase10/`. `phase0/`, `phase1/` and `phase2/` each
  carry that phase's design, plan and checklist; `phase3/` carries its segmentation design,
  `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md`, and two sub-phase directories —
  `phase3/phase3a/` and `phase3/phase3b/`, each holding that sub-phase's design, plan and checklist;
  `phase4/`
  carries its segmentation design,
  `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`, and three sub-phase
  directories — `phase4/phase4a/`, `phase4/phase4b/` and `phase4/phase4c/`; each holds that sub-phase's
  design, plan and checklist. `phase5/` carries its segmentation design,
  `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`, and three sub-phase
  directories — `phase5/phase5a/`, `phase5/phase5b/` and `phase5/phase5c/`; each holds that sub-phase's
  design, plan and checklist.
  `phase6/` carries its segmentation design,
  `docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`, and three sub-phase
  directories — `phase6/phase6a/` (retry), `phase6/phase6b/` (redirect) and `phase6/phase6c/`
  (authentication); each holds that sub-phase's design, plan and checklist, the checklists written at
  implementation on 2026-09-18 (6a, 6c) and 2026-09-19 (6b). Phase 6 is the largest **build** phase in the
  roadmap — only the audit-led phase 10, at 124, carries more requirement IDs:
  111 own IDs (`RETRY-1`–`45`, `REDIR-1`–`28`, `AUTH-1`–`38`) plus the fifteen `RECOV` IDs phase 4 handed it
  (`RECOV-17`–`RECOV-30` and `RECOV-34`), which land in `6a` with their own checklist rows while
  their phase-4 rows stay ⏳. Its three sub-phases are independent — phase 4c already fixed the
  `REDIR-11`/`AUTH-29` cross-origin contract the roadmap left open — so their order is convenience.
  `phase7/` carries its segmentation design,
  `docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`, and three sub-phase
  directories — `phase7/phase7a/` (serialization), `phase7/phase7b/` (server-sent events) and
  `phase7/phase7c/` (pagination); each holds a design, a plan and a checklist, the three checklists all
  written at implementation on 2026-09-20 — 7b's and 7c's landed first, 7a's last, reconciled onto the
  tree that holds the other two. Phase 7 is 107 IDs
  (`SERDE-1`–`30`, `SSE-1`–`41`, `PAGE-1`–`36`) and ships the workspace's second real gem,
  `dexpace-serde-json`, inside `7a`. Its three sub-phases are independent — `SSE-37` makes `7b`'s
  serde-independence a mechanised MUST, and §12's chapter intro states the same property for
  pagination — so their order is convenience.
  `phase8/` carries its segmentation design,
  `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`, and three sub-phase
  directories — `phase8/phase8a/` (synchronous transport and the conformance gem),
  `phase8/phase8b/` (async-runtime adapter) and `phase8/phase8c/` (asynchronous transport);
  each holds a design and a plan, and `phase8/phase8a/`, `phase8/phase8b/` and `phase8/phase8c/` checklists
  too, written at implementation on 2026-09-20, 2026-09-21 and 2026-09-21. Phase 8 is 52 IDs (`TRANSPORT-1`–`30`, `ASYNC-1`–`22`) and is
  the phase that ships the most gems in the roadmap — `dexpace-transport-net_http`,
  `dexpace-async-thread`, `dexpace-transport-async_http` and `dexpace-conformance`, whose
  gemspec, version and first release phase 8 owns. Its three sub-phases are independent, so
  their order is convenience; one task is phase-level because it lands in `dexpace-core`, which
  none of the three ships.
  `phase9/` carries **no segmentation design and no sub-phase** — it holds its design, its plan
  and its checklist directly, `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-design.md`,
  `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance.md` and
  `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-checklist.md`,
  the last written at implementation on 2026-09-23. The
  roadmap's segmentation rule reaches build phases 1 through 8 and leaves phases 9 and 10 to
  segment "only if their own design finds it necessary"; phase 9's design finds it does not, at
  41 IDs (`XCUT-1`–`24`, `NFR-1`–`17`) against phase 1's 42 unsegmented rows, and one gem rather
  than phase 8's four. It is the phase that dispositions **all seventeen `NFR`s**, which phase 0
  stood up as machinery and closed none of, and it adds the remaining suites to
  `dexpace-conformance` while owning neither that gem's gemspec nor its release — those are phase
  8's. Appendix B's 61 items are scoped explicitly rather than absorbed: `B.8` and `B.9` are
  phase 9's own suites, `B.3`, `B.4`, `B.6` and `B.7` are lifted, extended or driven, and `B.1`,
  `B.2` and `B.5` are dispositioned by reference to the owning phase's suite with a committed
  61-row coverage map as the artifact. Phase 9 reports and phase 10 repairs.
  `phase10/` likewise carries **no segmentation design and no sub-phase** — its design, plan and checklist sit
  directly at `docs/work/mvp/phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness-design.md`,
  `docs/work/mvp/phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness.md` and
  `docs/work/mvp/phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness-checklist.md`,
  the last written at implementation on 2026-09-25.
  Its scope is the largest in the roadmap by ID count and its design argues that the ID is the wrong
  unit: **124 own rows** — every ID design §10's nineteen entries name, plus `RETRY-28` from its
  closing note, 108 MUST / 15 SHOULD / 1 MAY — of which **fifty-one come from §10.1 alone**, whose
  retirement of the byte-stream provider seam names `SEAM-3`–`SEAM-10`, all forty-two `IO` IDs and
  `XCUT-23` in one argument. Counted by ledger entry the phase was designed at 19 entries plus a closing note
  plus 32 inbound bullets — **52 units** (the list had grown to sixty-five bullets by implementation), the same order as phase 1's 42 unsegmented rows — and it ships
  **no new gem**, so only one of the segmentation rule's three triggers fires. It carries **64
  cross-reference rows** beside the 124, one per ID an inbound bullet touches or a phase-10 repair reaches
  whose row belongs to an earlier phase, for 188 in all; its checklist carries seventeen more cross-reference
  rows the as-built list reached, for 205. It is the phase that flips all nineteen rows of `docs/deviations.md`
  from `design only — not yet built`, by the method the roadmap fixes for it — **re-deriving every
  claim from as-built source, never from another document** — and the phase that writes the
  frozen-chapter amendments out, the design's thirteen `C1`–`C13`, `C14` reconciled from phase 4b's filing
  and five the as-built audit found, `C15`–`C19`, in `docs/deviations.md`'s amendment set, because `docs/sdk-design-ruby/` and `docs/product-spec/` are
  frozen and only a human may apply them. It ships repair code in `dexpace-core`,
  `dexpace-transport-async_http` and `dexpace-conformance`, reaches
  `dexpace-transport-net_http` through the `sig/` header its `NFR-13` repair adds to every gem, two YARD
  comments in its `lib/` and two tests the `Protocol` repair invalidated, per its design's R1 addendum,
  builds three further blocking gates (`gates:ledger_audit`, `gates:spdx_rbs`,
  `gates:sole_parse`) and a ninth probe check for chapter attribution, dispositions every one of the
  inbound list's sixty-five bullets (repaired, verified already fixed, moved to `docs/first-release.md`,
  or withdrawn — none carried forward), and closes or narrows `docs/first-release.md` lines while
  publishing nothing: every gem stays at `0.0.0`.
  Every phase and sub-phase of the v1 roadmap has its checklist — twenty-two, each written at
  implementation from what was built, not from the plan.
- There are 40 harvested topics under `docs/knowledge/harvested/`; the harvest ran here on 2026-09-05.
