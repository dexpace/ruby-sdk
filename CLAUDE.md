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

**Nothing is implemented yet.** Zero gems exist under `gems/`; there is no `Gemfile`, `Rakefile`, `Steepfile`
or `.rubocop.yml`. What exists is the specification, the port design, the process tooling and the registers.
Ruby **>= 3.2** is the floor (`required_ruby_version` in every gemspec); CI runs a 3.2 / 3.3 / 3.4 / 4.0
matrix; every Ruby fact in the design was verified against 3.4.10.

Top-level namespace is `Dexpace`. Gem names are hyphenated and map segment-for-segment onto the constant path:
`dexpace-transport-net_http` → `lib/dexpace/transport/net_http.rb` → `Dexpace::Transport::NetHTTP`.

MVP gems (`docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.1):

| Gem | Namespace | Runtime dependencies |
|---|---|---|
| `dexpace-core` | `Dexpace` | **none** |
| `dexpace-transport-net_http` | `Dexpace::Transport::NetHTTP` | `dexpace-core`; `net-http` (a default gem) |
| `dexpace-transport-async_http` | `Dexpace::Transport::AsyncHTTP` | `dexpace-core`; `async-http` |
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

All run from the repository root. **This first set is everything that exists today.**

```bash
ruby .claude/skills/housekeeping/probe.rb                   # read-only documentation drift. Eight checks.
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

`docs/knowledge/` does not exist yet — the harvest runs next. Until it does, every corpus query exits 1 with a
message saying so; `--prefix-info` and `--gaps` answer from appendix C alone and work now, and the two verifiers
exit 0 stating there is nothing to check. Do not read an exit 1 here as "the corpus knows nothing".

The tooling has its own tests, and they are the only suites in the repository:

```bash
ruby -w scripts/test/knowledge_test.rb
ruby -w .claude/skills/housekeeping/test/run.rb
ruby -w .claude/skills/housekeeping/test/run.rb -n /guard/   # Minitest flags pass through
```

### After scaffold — planned, none of these exist yet

Do not run, cite or add these until the phase that scaffolds them has landed. That phase owns the exact task
names and rewrites this block from what it actually built.

```bash
bundle install
bundle exec rake                       # the default task: the whole gate set, locally (NFR-17)
bundle exec rubocop --fail-level=convention
bundle exec steep check
bundle exec rbs validate
bundle exec yard
bundle exec bundler-audit check --update
(cd gems/dexpace-core && bundle exec rake test)             # one suite per gem, under `ruby -w`
(cd gems/dexpace-transport-net_http && bundle exec rake test)  # runs dexpace-conformance's suite
```

The gate table is `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md`: RuboCop (`rubocop-minitest`,
`rubocop-performance`, findings fatal), `ruby -w` plus `RUBYOPT=-W:deprecated` with warnings failing the build,
`rbs validate` + `steep check`, `sig/**/*.rbs` diffed against the previous release tag, a runtime surface
snapshot, SimpleCov `minimum_coverage 80`, the three zero-dependency checks below, `bundler-audit`, YARD with an
undocumented-public-method gate, and a CI matrix that runs the **real suite** on each Ruby — not a syntax check,
because `TargetRubyVersion` catches syntax and not stdlib availability (§9.2).

### HARD RULE — core requires only stdlib that stays stdlib

**Ruby's standard library is not a fixed set; it shrinks between releases.** Verified from
`Gem::BUNDLED_GEMS::SINCE`: `base64` became a bundled gem in Ruby 3.4, and `logger`, `ostruct`, `benchmark`,
`fiddle` and `pstore` become bundled gems in Ruby 4.0. A bundled gem needs an explicit `Gemfile`/gemspec entry
under Bundler, so a core file that innocently writes `require "base64"` acquires an undeclared dependency that
fails on a supported Ruby.

The rule, stated exactly (§2.4): **`dexpace-core` may `require` only (a) non-gemified stdlib and (b) default
gems that remain default gems on every Ruby in the supported range, 3.2 through 4.0.** `dexpace-core.gemspec`
contains **zero `add_dependency` lines** — that assertion *is* the `SEAM-1` dependency audit, because Ruby has
no compile-versus-runtime dependency scope to lean on. The concrete consequences: Basic auth is
`["u:p"].pack("m0")` and never `Base64` (§6.3); the logging sink is a duck type and core never `require`s
`logger` (§8.1). `lib/dexpace.rb` issues explicit `require`s for the whole tree rather than using an autoloader,
because every autoloader worth using is a gem — which also makes the require audit a text scan rather than a
runtime trace.

Three mechanised checks enforce it (§9.2), and all three are blocking:

1. **Gemspec audit** — `runtime_dependencies` empty for core; `dexpace-core` plus at most one other gem for each
   adapter (`SEAM-1`, `NFR-1`, `NFR-2`).
2. **Require-allowlist audit** — scans core's `lib/**/*.rb` for every `require`/`require_relative` and fails on
   anything outside an explicit allowlist of non-gemified stdlib plus default gems that remain default on the
   *highest* Ruby in the matrix. This gate has no counterpart in the reference build.
3. **Clean-bundle isolation run** — a scratch `Gemfile` holding only `gem "dexpace-core", path: ...`, then
   `bundle exec ruby -e` requiring core and exercising a smoke path, on every Ruby in the matrix. Bundler refuses
   to activate a gem outside the bundle, which is what makes the Ruby 4.0 column load-bearing.

Adapter gems are exempt: an adapter that wants `logger` declares it, which is what `NFR-2`'s "core plus at most
one third-party library" budget is for. The `json >= 2.19.9` floor lives in `dexpace-serde-json`'s gemspec and
nowhere else — being able to state that floor at all is half the reason the codec is a separate gem (§3.4).

## Documentation hierarchy

`docs/README.md` is the index and the contract; this is the working summary, and it must not diverge from it.
Entries marked **(planned)** do not exist yet and are frozen the moment they appear, not the moment someone
remembers.

| Entry | Owns | Written by | Housekeeping may write? |
|---|---|---|---|
| `docs/product-spec/` + `docs/product-spec.md` | **Normative.** The numbered requirements — `HTTP-7`, `SEAM-1`, `RETRY-13`, `NFR-5`, … — the code exists to satisfy. The `.md` is its table of contents | A human, deliberately | **frozen** |
| `docs/sdk-design-ruby/` + `docs/sdk-design-ruby.md` | How each spec area maps to idiomatic Ruby. Non-normative but binding by convention. §10 is the **normative deviation ledger** | A human, deliberately | **frozen** |
| `docs/knowledge/harvested/` **(planned)** | Harvested styleguide and spec knowledge, topic-indexed. Generated; **never hand-edited** | The `knowledge-harvest` skill | **frozen** |
| `docs/knowledge/notes/` **(planned)** | What the implementation found, overriding a harvested entry. Role `review` | A human | **frozen** |
| `docs/sdk-documentation/` | **As-built.** How the gems compose, which one to install, worked cross-gem examples. `architecture.md` is the front door, and is a stub | A human, or a skill on request | yes |
| `docs/work/<delivery>/phaseN[/phaseNx]/` | Process records: per-(sub)phase design, plan and checklist | The phase that produced them; **collected** by `housekeeping` | yes — `git mv` only |
| `docs/superpowers/` | Nothing, for long. The **inbox** the Superpowers skills write into; never a citation target | `brainstorming`, `writing-plans` | yes — it drains it |
| `docs/open-items.md` | **Register.** The running find-list: permanent `OI-<n>` IDs, cited from anywhere in the repository | Whoever finds the item | yes — appends |
| `docs/deferred-items.md` | **Register.** Deferrals: `DEF-<n>`, each naming the phase that deferred it and the condition for picking it up | The phase that defers | yes — appends |
| `docs/deviations.md` | **Register.** The as-built audit of design §10, and where a deviation with no owning phase lands | A human, following a phase or review | no — judgment, not a mechanical append |
| `docs/first-release.md` | **Register.** Release readiness. Nothing is published; every gem is at 0.0.0 | A human, as blockers close | no |
| `docs/assets/` | Vendored wordmark SVGs the root `README.md` renders | Copied from `dexpace/morphic` | yes |
| `docs/README.md` | The index above | A human | yes |

**Frozen means a maintenance tool refuses to write there**, not merely that you should not. The list lives in one
constant — `Guard::FROZEN` in `.claude/skills/housekeeping/guard.rb` — and `.claude/skills/housekeeping/test/guard_test.rb` proves the four
ways a naive `start_with?` fails: a sibling directory whose name merely starts with a frozen one, a `..` segment
that lands inside after normalisation, an absolute path, and a symlink whose target is inside a frozen tree.

**Which register.** A finding you are not acting on now → `docs/open-items.md`, `OI-<n>`. Something consciously
postponed while building the SDK → `docs/deferred-items.md`, `DEF-<n>`, with the deferring phase and the
condition that picks it up. A place this port deliberately differs from the reference contract → the owning
phase document's own `## Deviation Ledger`, consolidated into design §10, audited by `docs/deviations.md`. A
release blocker → `docs/first-release.md`. **Never leave an aggregate register section inside a spec, design or
plan document** — the probe's `registers` check reports it, because a concern only a specification remembers is
a concern nothing acted on.

**Never renumber an item ID, and never reuse one.** They are cited from source comments, tests and the `docs/`
tree. `OI-<n>` and `DEF-<n>` are the registers' namespace; requirement IDs are a different one and the probe
does not confuse them. Do not write the *number* of items into any document; derive it:

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
naming the harvested rule it overrides, which makes that rule print `[overridden by notes/…]` in every query
result. `ruby scripts/verify_knowledge_structure.rb` keeps the trees apart; re-harvest with
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
  it as a deferral (`DEF-<n>`) or a deviation. A requirement in scope with no row is the failure mode this
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
  …)` reaches the generated constructor anyway, because `send` bypassing `private` is a documented Ruby feature;
  and any object responding to `#method`/`#url`/`#headers`/`#body` duck-types past the builder entirely. Neither
  hole can be closed. Do not build a fake proof that they are.
- **The mitigation that matters is wire-boundary re-validation.** Header name and outbound value validation
  (`HTTP-17`, `HTTP-18`, `XCUT-18`) runs **again** immediately before dispatch, inside every transport adapter,
  so a forged model cannot smuggle a CRLF into a header name even if it never met a builder. That makes the
  residual gap a correctness-of-shape gap, not a request-splitting gap. Recorded in design §10.
- **`downcase` is called with no arguments, everywhere in core.** Ruby's fold is opt-in-locale
  (`"I".downcase(:turkic)` → `"ı"`), and the same lint rule that forbids `Time.parse` forbids a locale symbol on
  `downcase`/`upcase`/`casecmp` repository-wide, so `HTTP-13` is enforced rather than assumed.

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
  `public_instance_methods(false)`, sorts, and diffs against a committed manifest. Each catches what the other
  cannot see; changing exports means regenerating **both**.
- `NFR-11` is mechanised as an RBS scan asserting that no constant outside `Dexpace::` and a fixed stdlib
  allowlist appears in any public signature under `sig/` — which is why the async pivot had to be core-owned.
- YARD has an undocumented-public-method gate. A YARD block explains *why*; it never restates a signature.

## Phase workflow

The roadmap under `docs/work/mvp/` is an **index of phases, not a design** — it names each phase, its scope and
its requirement prefixes, and nothing else. The real work is per-phase: **brainstorm → plan → implement**, and
all three read the corpus first.

1. **Start with what is already known.** Invoke the `knowledge-lookup` skill at the start of every phase and
   every numbered task, before writing a design doc, a plan or code. Its phase-start pair —
   `--origin note --brief` and `--section conflicts --brief` — is not optional: a plan that assumes an open
   design-versus-styleguide conflict is settled is the failure both queries exist to catch. Before the harvest,
   `--prefix-info` and `--gaps` are the substitutes, and a phase whose IDs come back as gaps must budget for
   reading the specification itself and say so in its design doc.
2. **Brainstorm on a branch off `mvp`.** `mvp` stays the starting point for every phase; brainstorming happens on
   its own branch so an exploratory design does not land on the delivery branch.
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
   `## Deviation Ledger`, is consolidated into design §10, and is audited by `docs/deviations.md`. A deferral
   goes to `docs/deferred-items.md` as `DEF-<n>` with the deferring phase and the pick-up condition. A finding
   nobody is acting on yet goes to `docs/open-items.md` as `OI-<n>`. A release blocker goes to
   `docs/first-release.md`. **Never leave an aggregate register section inside the spec or the plan.**
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
against that one derivation — never one document against another. Eight checks: `inbox`, `root`, `claims`,
`readmes`, `links`, `registers`, `citations`, `guard`. Exit code is 1 when anything is found.

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

- Zero gems exist under `gems/` — the directory itself does not exist yet.
- There are seven phase directories under `docs/work/*/`; `mvp/` is the only delivery, and it holds
  the v1 roadmap, `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`, plus `phase0/`,
  `phase1/`, `phase2/`, `phase3/`, `phase4/`, `phase5/` and `phase6/`. The first three carry that phase's
  design and plan; `phase3/` carries its segmentation design,
  `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md`, and two sub-phase directories —
  `phase3/phase3a/` and `phase3/phase3b/`, each holding that sub-phase's design and plan; `phase4/`
  carries its segmentation design,
  `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`, and three sub-phase
  directories — `phase4/phase4a/`, `phase4/phase4b/` and `phase4/phase4c/`; each holds a design
  and a plan. `phase5/` carries its segmentation design,
  `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`, and three sub-phase
  directories — `phase5/phase5a/`, `phase5/phase5b/` and `phase5/phase5c/`; each holds a design
  and a plan. `phase6/` carries its segmentation design,
  `docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`, and three sub-phase
  directories — `phase6/phase6a/` (retry), `phase6/phase6b/` (redirect) and `phase6/phase6c/`
  (authentication); each holds a design and a plan. Phase 6 is the largest phase in the roadmap:
  111 own IDs (`RETRY-1`–`45`, `REDIR-1`–`28`, `AUTH-1`–`38`) plus `DEF-35`'s fifteen `RECOV` IDs
  (`RECOV-17`–`RECOV-30` and `RECOV-34`), which land in `6a` with their own checklist rows while
  their phase-4 rows stay ⏳. Its three sub-phases are independent — phase 4c already fixed the
  `REDIR-11`/`AUTH-29` cross-origin contract the roadmap left open — so their order is convenience.
  Every checklist is still to be written at execution time.
- There are 40 harvested topics under `docs/knowledge/harvested/`; the harvest ran here on 2026-09-05.
