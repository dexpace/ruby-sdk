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

**Phases 0, 1, 2, 3a, 3b and 4b are built; the domain model, the seam layer, the byte-streaming layer, the
body layer and the recovery layer are the only domain code.** Six gems exist under `gems/`, every one at `0.0.0`. `dexpace-core` carries the HTTP domain model — `Dexpace::Request`,
`Response`, `Headers`, `Status`, `Method`, `Protocol`, `MediaType`, `Query`, `RequestOptions`, `HeaderName`, the
`HeaderSyntax`, `PercentEncoding` and `URL` function modules, and the construction contract `Dexpace::Model` /
`Dexpace::Builder` under one error root, `Dexpace::Error`
(`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-checklist.md`) — and the seam layer: the
provider registry `Dexpace::Registry`, the three seams `Dexpace::Transport`, `Dexpace::AsyncTransport` and
`Dexpace::Serde` with their `.conforms?` predicates and RBS interfaces, the two `SEAM-18` bridges under
`Dexpace::Bridge`, the core-owned async pivot `Dexpace::Async::Future` / `Completer` / `Settlement`, the
cooperative `Dexpace::Cancellation` token and its `Source`, `Dexpace::Closeable` with `Dexpace.close_quietly`,
the seam failure types `SeamError` / `ClosedError` / `CancelledError` and the `Serde::Error` hierarchy, and the
operation projection `Dexpace::Operation`
(`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations-checklist.md`) — and the byte-streaming layer under
`Dexpace::IO`: the FIFO `Buffer`, `BufferedSource` and `BufferedSink` with the `TypedReads` and `TypedWrites`
vocabularies, `TeeSink`, `MAX_MATERIALIZED_BYTES`, the three RBS interfaces `_Source`/`_Sink`/`_Chunked`, and the
two failure types `Dexpace::StreamError < ::IOError` and `Dexpace::EndOfStreamError < ::EOFError`
(`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-checklist.md`) — and the body layer, flat under
`Dexpace::` and filed under `lib/dexpace/http/`: the contract and factory home `Dexpace::Body` with
`MAX_BUFFERED_ERROR_BODY_BYTES` and `.buffer_bounded`, the seven request-body variants `BytesBody`,
`BufferBody`, `StreamBody`, `ChunkedBody`, `FormBody`, `FileBody` and `MultipartBody` (with its `Part` and
`Builder`), the single-use `ResponseBody`, the two logging wrappers `RequestLoggingBody` and
`ResponseLoggingBody`, the lazy `TypedResponse` over the RBS interface `_ResponseHandler`, the form encoder
beside the RFC 3986 one in `PercentEncoding`, and `Response#close` / `#body_string` / `#body_bytes` — the one
decode boundary (`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-checklist.md`) — and the
recovery layer, §8.2's resilience primitives: the closed two-variant outcome `Dexpace::Outcome::Success` /
`Failure`, the `Dexpace::Recovery` namespace holding `RequestChain`, `ResponseChain`, the `Orchestrator` that
lets no throwable past it, the `Transform` contract with the three shipped steps `IdempotencyKeyStep`,
`ClientIdentityStep` and `ErrorMappingStep`, the private `Ownership` helper and `Recovery.buffer_error_body`,
the two flat errors `Dexpace::ProtocolError` and `Dexpace::OutcomeError`, and the three error primitives every
later phase uses — the suppressed-exception trail `Dexpace::Suppressible` (which `Dexpace::Error` includes) with
`Dexpace.attach_suppressed` / `Dexpace.suppressed`, and the cycle-safe `Dexpace.each_cause`
(`docs/work/mvp/phase4/phase4b/2026-09-09-phase4b-recovery-primitives-checklist.md`); every other
gem's `lib/` still holds its namespace module and a `VERSION` constant and nothing else. Nothing talks to a
socket yet. The workspace root
carries the `Gemfile`, `Rakefile`, `Steepfile`, `rbs_collection.yaml`, `.rubocop.yml`, `.yardopts`, `VERSIONS` and
the seventeen blocking gates (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-checklist.md`).
Beyond that, what exists is the specification, the port design, the process tooling and the register,
`docs/deviations.md`. Ruby **>= 3.2** is the floor (`required_ruby_version` in every gemspec, asserted by
`gates:versions`); CI runs a 3.2 / 3.3 / 3.4 / 4.0 matrix; every Ruby fact in the design was verified against
3.4.10 and the ones the gates and the domain model rest on were re-verified against 3.2.11, 3.4.10 and 4.0.6.

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

All run from the repository root. The build is Bundler-driven: `bundle install` first, on the Ruby you mean to
test with. `Gemfile.lock` is **not committed** and is gitignored — a lockfile is a resolution against one
interpreter and the supported range spans a boundary where 26 names stop being default gems, so every
interpreter resolves its own (`docs/knowledge/notes/tooling-and-quality-gates.md`, key
`tooling-and-quality-gates/f638625d`). Remove the lock before switching interpreters: one written by Bundler 4
makes an older Bundler try to install Bundler 4.

```bash
bundle install
bundle exec rake                                  # the default task: all seventeen gates, in order (NFR-17)
bundle exec rake gates:list                       # the seventeen names, in the order CI and `rake` both use
bundle exec rake rubocop                          # NFR-7, findings fatal, no autocorrection
bundle exec rake rubocop:fix                      # safe autocorrections only, never the gate
bundle exec rake cops:test                        # the custom cops' own suite (.rubocop/test/)
bundle exec rake rbs:validate steep               # NFR-3: per-gem rbs validate, then steep over six targets
bundle exec rake test:gems                        # gem suites: warnings fatal, SimpleCov floor (NFR-5, NFR-6)
bundle exec rake test:gates                       # the repository's gate suites (test/gates/)
bundle exec rake gates:gemspec_audit              # SEAM-1, NFR-1, NFR-2
bundle exec rake gates:require_allowlist          # SEAM-1, SEAM-2: the allowlist and the denylist
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

`docs/knowledge/` was harvested on 2026-09-05 (see "Querying `docs/knowledge/`" below); `--prefix-info` and
`--gaps` answer from appendix C alone, and the two verifiers exit 0 when the trees are sound.

```bash
ruby -w scripts/test/knowledge_test.rb
ruby -w .claude/skills/housekeeping/test/run.rb
ruby -w .claude/skills/housekeeping/test/run.rb -n /guard/   # Minitest flags pass through
```

`scripts/` and `.claude/` are outside the RuboCop gate — `NFR-7`'s one documented exception, with its re-enable
condition in `.rubocop.yml` and its repair on phase 10's inbound list in the roadmap.

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
phase 10's inbound list in `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`. Anything that belongs to
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
  (phase 2's design, §3 addendum A1, deviation P2-3).
- **`Response#body_string` is the SDK's one decode boundary, and it is three steps, not one** — resolve the
  charset through `MediaType#charset` (already `nil` for absent or unknown), **retag** the BINARY bytes with
  3a's `#read_string(encoding)`, then transcode with the target **named**,
  `encode(encoding, invalid: :replace, undef: :replace)`. Design §3.1's one-step sentence mangles every
  non-ASCII byte and a target-less `#encode` follows the host's `Encoding.default_internal`; the sentence is on
  phase 10's inbound list, and the suite's hostile-global tests are what catch a revert (phase 3b's Task 8).
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
- **A public `Data` follows the construction pattern without exception; only a `private_constant` snapshot is
  exempt** — `Registry::State`, `Registry::Claim` and `Cancellation::Source::State` are `Data` without `Model`
  and without `.build`, because a snapshot has no public constructor and no derivation (phase 2's P2-9).

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
   already-planned phase, or to `docs/first-release.md` when it belongs to the release — and when it is in
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

- Six gems exist under `gems/`, all at `0.0.0` and none published: `dexpace-core`,
  `dexpace-transport-net_http`, `dexpace-transport-async_http`, `dexpace-serde-json`, `dexpace-async-thread`
  and `dexpace-conformance`. Each has a gemspec reading `VERSIONS`, a `sig/` mirroring its `lib/` one file
  per file, a smoke suite, a README, a LICENSE copy and a per-gem `Rakefile`. `dexpace-core`'s `lib/` holds
  the phase-1 HTTP domain model, the phase-2 seam layer, the phase-3a byte-streaming layer, the phase-3b
  body layer and the phase-4b recovery layer — seventy-nine phase-1, phase-2, phase-3a, phase-3b and
  phase-4b files under `lib/dexpace/` beside phase 0's `version.rb`, every one mirrored in `sig/`, and every
  one of the seventy-nine but the two `private_constant`s `hooks.rb` and `recovery/ownership.rb` mirrored
  in `test/`; every other
  gem is a phase-0 skeleton whose `lib/` holds the namespace module and a `VERSION` constant and nothing
  else. Every adapter gemspec declares `dexpace-core` and no third-party gem yet
  (design P0-9); the third-party half of each `NFR-2` budget arrives with the phase that writes the code
  needing it.
- There are eleven phase directories under `docs/work/*/`; `mvp/` is the only delivery, and it holds
  the v1 roadmap, `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`, plus `phase0/`,
  `phase1/`, `phase2/`, `phase3/`, `phase4/`, `phase5/`, `phase6/`, `phase7/`, `phase8/`, `phase9/` and `phase10/`. `phase0/`, `phase1/` and `phase2/` each
  carry that phase's design, plan and checklist; `phase3/` carries its segmentation design,
  `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md`, and two sub-phase directories —
  `phase3/phase3a/` and `phase3/phase3b/`, each holding that sub-phase's design, plan and checklist — six
  checklists written so far, each at implementation; `phase4/`
  carries its segmentation design,
  `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`, and three sub-phase
  directories — `phase4/phase4a/`, `phase4/phase4b/` and `phase4/phase4c/`; each holds a design
  and a plan, and `phase4/phase4b/` its checklist too. `phase5/` carries its segmentation design,
  `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`, and three sub-phase
  directories — `phase5/phase5a/`, `phase5/phase5b/` and `phase5/phase5c/`; each holds a design
  and a plan. `phase6/` carries its segmentation design,
  `docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`, and three sub-phase
  directories — `phase6/phase6a/` (retry), `phase6/phase6b/` (redirect) and `phase6/phase6c/`
  (authentication); each holds a design and a plan. Phase 6 is the largest **build** phase in the
  roadmap — only the audit-led phase 10, at 124, carries more requirement IDs:
  111 own IDs (`RETRY-1`–`45`, `REDIR-1`–`28`, `AUTH-1`–`38`) plus the fifteen `RECOV` IDs phase 4 handed it
  (`RECOV-17`–`RECOV-30` and `RECOV-34`), which land in `6a` with their own checklist rows while
  their phase-4 rows stay ⏳. Its three sub-phases are independent — phase 4c already fixed the
  `REDIR-11`/`AUTH-29` cross-origin contract the roadmap left open — so their order is convenience.
  `phase7/` carries its segmentation design,
  `docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`, and three sub-phase
  directories — `phase7/phase7a/` (serialization), `phase7/phase7b/` (server-sent events) and
  `phase7/phase7c/` (pagination); each holds a design and a plan. Phase 7 is 107 IDs
  (`SERDE-1`–`30`, `SSE-1`–`41`, `PAGE-1`–`36`) and ships the workspace's second real gem,
  `dexpace-serde-json`, inside `7a`. Its three sub-phases are independent — `SSE-37` makes `7b`'s
  serde-independence a mechanised MUST, and §12's chapter intro states the same property for
  pagination — so their order is convenience.
  `phase8/` carries its segmentation design,
  `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`, and three sub-phase
  directories — `phase8/phase8a/` (synchronous transport and the conformance gem),
  `phase8/phase8b/` (async-runtime adapter) and `phase8/phase8c/` (asynchronous transport);
  each holds a design and a plan. Phase 8 is 52 IDs (`TRANSPORT-1`–`30`, `ASYNC-1`–`22`) and is
  the phase that ships the most gems in the roadmap — `dexpace-transport-net_http`,
  `dexpace-async-thread`, `dexpace-transport-async_http` and `dexpace-conformance`, whose
  gemspec, version and first release phase 8 owns. Its three sub-phases are independent, so
  their order is convenience; one task is phase-level because it lands in `dexpace-core`, which
  none of the three ships.
  `phase9/` carries **no segmentation design and no sub-phase** — it holds its design and its
  plan directly, `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-design.md`
  and `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance.md`. The
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
  `phase10/` likewise carries **no segmentation design and no sub-phase** — its design and plan sit
  directly at `docs/work/mvp/phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness-design.md`
  and `docs/work/mvp/phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness.md`.
  Its scope is the largest in the roadmap by ID count and its design argues that the ID is the wrong
  unit: **124 own rows** — every ID design §10's nineteen entries name, plus `RETRY-28` from its
  closing note, 108 MUST / 15 SHOULD / 1 MAY — of which **fifty-one come from §10.1 alone**, whose
  retirement of the byte-stream provider seam names `SEAM-3`–`SEAM-10`, all forty-two `IO` IDs and
  `XCUT-23` in one argument. Counted by ledger entry the phase is 19 entries plus a closing note plus
  32 inbound bullets — **52 units**, the same order as phase 1's 42 unsegmented rows — and it ships
  **no new gem**, so only one of the segmentation rule's three triggers fires. It carries **64
  cross-reference rows** beside the 124, one per ID an inbound bullet touches or a phase-10 repair reaches
  whose row belongs to an earlier phase, for 188 in all. It is the phase that flips all nineteen rows of `docs/deviations.md`
  from `design only — not yet built`, by the method the roadmap fixes for it — **re-deriving every
  claim from as-built source, never from another document** — and the phase that writes the thirteen
  frozen-chapter amendments `C1`–`C13` out, because `docs/sdk-design-ruby/` and `docs/product-spec/` are
  frozen and only a human may apply them. It ships repair code in `dexpace-core`,
  `dexpace-transport-async_http` and `dexpace-conformance`, reaches
  `dexpace-transport-net_http` only through the `sig/` header its `NFR-13` repair adds to every gem,
  plans three further blocking gates (`gates:ledger_audit`, `gates:spdx_rbs`,
  `gates:sole_parse`) and a ninth probe check for chapter attribution — none of the four built yet —
  and closes or narrows five `docs/first-release.md` lines while publishing nothing: every gem stays
  at `0.0.0`.
  Every checklist but phase 0's, phase 1's, phase 2's, phase 3a's, phase 3b's and phase 4b's is still to be
  written at execution time.
- There are 40 harvested topics under `docs/knowledge/harvested/`; the harvest ran here on 2026-09-05.
