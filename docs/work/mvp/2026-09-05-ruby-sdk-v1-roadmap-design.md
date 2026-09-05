# Ruby SDK — v1 Roadmap

**Status:** Draft, approved for planning (signed off 2026-09-05).

**Purpose:** An index of phases, not an implementation plan. Each row names a phase, the gem(s) it delivers,
the spec chapter and requirement IDs it satisfies, and the design chapter it maps to — and nothing else. Every
phase gets its own brainstorm → design → plan cycle when its turn comes, and the three documents that cycle
produces are where implementation detail lives. **This document never absorbs implementation detail as phases
complete.** It changes in exactly three ways: a phase's `sdk-design refs` cell gains a link to that phase's own
design document once one exists, **appended to the design citation and never replacing it**; a wrong cell is
corrected in place, with the correction stated; and a dated entry is appended to `## Phase Status Notes`. Nothing
else is edited, and no section here is ever allowed to become a register — the four registers are
`docs/open-items.md`, `docs/deferred-items.md`, `docs/deviations.md` and `docs/first-release.md`, and an aggregate
findings or deferral section inside this document is drift the `housekeeping` probe reports.

**Governing documents.** Five, binding from phase 0 onward, for every phase without exception:

- `docs/product-spec/` — **normative.** 645 numbered requirements across 19 prefixes, in appendix-C order:
  `SEAM`, `HTTP`, `IO`, `BODY`, `CTX`, `PIPE`, `RECOV`, `RETRY`, `REDIR`, `AUTH`, `PAGE`, `SSE`, `SERDE`, `OBS`,
  `CFG`, `TRANSPORT`, `ASYNC`, `XCUT`, `NFR`. `docs/product-spec.md` is its table of contents;
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` is the canonical ID index and the
  fastest way to locate one.
- `docs/sdk-design-ruby/` — how each spec area maps to idiomatic Ruby. Non-normative but binding by convention.
  §10 is the **normative deviation ledger** (19 entries), §11 the reference-ambiguity appendix (21 items), §12
  the requirement-coverage index that maps every prefix to the design sections addressing it.
- The Ruby styleguide, the sibling repository's `styleguide/ruby/` — 15 chapters, harvested into
  `docs/knowledge/harvested/` and queried through `scripts/knowledge.rb`. Binding except where a note under
  `docs/knowledge/notes/` records otherwise.
- `CLAUDE.md` — the working contract: the hard rule on what core may `require`, the domain-model construction
  pattern, the constraints that will bite, the requirement-ID conventions and the phase workflow.
- `docs/README.md` — the ownership table, what is frozen to maintenance tooling, and the `docs/work/` naming
  rules every phase document follows.

---

## Cross-Cutting Constraints (apply to every phase, not their own phase)

Each is stated normatively elsewhere; this gives what it is, where that statement lives, and who stands it up.

**1. Quality gates, from phase 0 onward.** The set, and the 3.2 / 3.3 / 3.4 / 4.0 real-suite CI matrix, are design
§9's gate table (`docs/sdk-design-ruby/09-toolchain-and-quality-gates.md`). Phase 0 stands every gate up; every
later phase is written under them from its first line.

**2. Zero-dependency core and the bundled-gem rule.** `CLAUDE.md`'s hard rule and design §2.4, mechanised by §9.2's
gemspec audit, require-allowlist audit and clean-bundle isolation run — all three stood up by phase 0.

**3. Requirement-ID traceability, one checklist row per ID in scope** (`CLAUDE.md`'s conventions). **This roadmap
defines the legend**, used verbatim by every phase: ✅ implemented and tested · 🚫 not built (permanent
simplification, named reason) · ⏳ deferred (named `DEF-<n>` with its pick-up condition: target phase, gem, or
event) · N/A not applicable in this port.

**4. Phases 1 through 7 test against an in-memory fake transport** implementing only the `SEAM-11`/`SEAM-16` seams;
phase 8 brings the first real socket, where conformance uses a local `TCPServer` fixture, not a stub (design §9.3).

**5. The six styleguide-versus-design conflicts are resolved; the notes are canonical, not this list.** Each is
`docs/knowledge/notes/<topic>.md`, `<topic>` being the key's prefix, and all six print `[overridden by notes/…]`:
- `data-modeling/35fde90f` — `Data.define` is the base value type; `T::Struct` would need a gem.
- `module-organization/bf6411ad` — explicit `require`s from `lib/dexpace.rb`; no Zeitwerk.
- `package-and-dependency-layout/41b154a3` — `required_ruby_version >= 3.2`; matrix 3.2 / 3.3 / 3.4 / 4.0.
- `package-and-dependency-layout/8c0687bf` — one repository, one gemspec per published gem under `gems/`.
- `tooling-and-quality-gates/86d763f1` — `rubocop` + `-minitest` + `-performance`; no `rubocop-airbnb`, no hook.
- `type-system/93dc79aa` — RBS under `sig/`, gated by `rbs validate` and `steep check`; no Sorbet.

**6. The ban list, repository-wide, every gem.** `CLAUDE.md`'s "Constraints that will bite", argued in design §8.3,
§3.5 and §4. Phase 0 mechanises what a cop can catch; the `Timeout.timeout`/`Thread#raise`/`Thread#kill` cop is a
**roadmap decision** design §9's table does not yet carry, so phase 0 records it there as an addendum in its design doc.

**7. Register discipline.** `docs/README.md` owns the four-register boundary; execution step 1 below owns the
deferral sweep. A deviation goes to the phase's own `## Deviation Ledger`, then design §10, then the audit in
`docs/deviations.md`, whose 19 rows read `design only — not yet built` until the phase that builds the gem flips one.

**8. Three MUSTs are known-unsatisfied; do not re-open the trade.** `ASYNC-3` and `PIPE-33`'s interrupt clause are
unsatisfied and `ASYNC-4` vacuous (design §10.5, carried as `DEF-18`): phase 8 marks all three ⏳ citing it, phase
10 audits the ledger. `DEF-19` is release-gated — to be tracked in `docs/first-release.md`, closable by no phase.

**9. Pointers, not copies.** The domain-model construction pattern (`CLAUDE.md`, design §4) and the constraints that
will bite (`CLAUDE.md`, design §3.1, §3.7, §7.1, §8.2, §8.3) are cited from a phase document, never copied into one.

---

## Phase List

| Phase | Name | Gem(s) | Product-spec refs | sdk-design refs |
|---|---|---|---|---|
| 0 | Scaffold and Quality Gates | workspace root, plus all six MVP gems at `0.0.0` with empty `lib`/`sig`/`test`: `dexpace-core`, `dexpace-transport-net_http`, `dexpace-transport-async_http`, `dexpace-serde-json`, `dexpace-async-thread`, `dexpace-conformance` | §20 — `NFR-1`–`NFR-17`, every gate stood up as machinery and none closed here; phase 9 dispositions them. `NFR-5`'s SimpleCov `minimum_coverage 80` is wired here and inert until phase 1 lands code | §2.3, §2.4, §9 |
| 1 | Core HTTP Domain Model | `dexpace-core` | §4 — `HTTP-3`–`HTTP-35`, `HTTP-46`–`HTTP-50`, `HTTP-53` (39 IDs); `SEAM-29`'s construction contract honoured ahead of phase 2 | §4; §3.5's strict component encoder and `URI::RFC3986_PARSER` pin for `HTTP-29`/`HTTP-32` (the rest of §3.5 is `SEAM-26`/`SEAM-27`, phase 2's); phase design: [`phase1/2026-09-05-phase1-core-http-domain-model-design.md`](./phase1/2026-09-05-phase1-core-http-domain-model-design.md) |
| 2 | Seam Foundations | `dexpace-core` | §3 — `SEAM-1`–`SEAM-30` (30 IDs) | §2.4, §3.1–§3.7, §10.3, §10.8, §10.9 |
| 3 | I/O and Body Lifecycle | `dexpace-core` | §5 — `IO-1`–`IO-42` (42); ch.06 — `BODY-1`–`BODY-37` (37), plus `HTTP-36`–`HTTP-45`, `HTTP-51`, `HTTP-52` jointly numbered into that chapter | §3.1, §10.1, §10.2, §10.12 |
| 4 | Execution Context and Pipelines | `dexpace-core` | §7 — `CTX-1`–`CTX-20` (20); §8.2 — `RECOV-1`–`RECOV-34` (34); §8.1 — `PIPE-1`–`PIPE-40` (40) | §5.1–§5.4, §8.1 |
| 5 | Configuration and Observability | `dexpace-core` | §16 — `CFG-1`–`CFG-38` (38); §15 — `OBS-1`–`OBS-40` (40) | §8.1–§8.3, §10.16, §10.17 |
| 6 | Retry, Redirect and Authentication | `dexpace-core` | §9 — `RETRY-1`–`RETRY-45` (45); §10 — `REDIR-1`–`REDIR-28` (28); §11 — `AUTH-1`–`AUTH-38` (38) | §6.1–§6.3, §8.3, §10.15 |
| 7 | Serde, SSE and Pagination | `dexpace-core`, `dexpace-serde-json` | §14 — `SERDE-1`–`SERDE-30` (30); §13 — `SSE-1`–`SSE-41` (41); §12 — `PAGE-1`–`PAGE-36` (36) | §3.4, §7.1–§7.3, §10.13, §10.14 |
| 8 | Transports and Async Runtime | `dexpace-transport-net_http`, `dexpace-transport-async_http`, `dexpace-async-thread`, and `dexpace-conformance` — phase 8 owns that gem: its gemspec, its version and its first release, shipping the transport conformance suite | §17 — `TRANSPORT-1`–`TRANSPORT-30` (30); §18 — `ASYNC-1`–`ASYNC-22` (22) | §3.2, §3.3, §3.7, §9.3, §10.5 |
| 9 | Cross-Cutting Invariants and Conformance | `dexpace-conformance` — adds the remaining suites to phase 8's gem, owning neither its gemspec nor its release; every gem audited | §19 — `XCUT-1`–`XCUT-24` (24); §20 — `NFR-1`–`NFR-17` (17); appendix B | §9, §9.3, §10.19 |
| 10 | Deviation Reconciliation and Release Readiness | every gem (audit-led; ships code where the audit finds a defect) | appendix C — every ID named by design §10's 19 entries | §10, §11, §12 |

**Ordering rationale:** Toolchain first, so every subsequent phase is written under the gates from its first line
— and phase 0 creates all six gem skeletons with real gemspecs rather than a workspace alone, because the gemspec
audit, the require-allowlist audit and the clean-bundle isolation run are only proven when they run against the
artifact they are supposed to check. From there, dependency order. The HTTP domain model (1) is the base every
other prefix builds on and depends on nothing. The seams (2) are the interface layer `TRANSPORT`, `ASYNC` and
`SERDE` later implement, and they too have no prerequisite among the 19 prefixes. I/O and bodies (3) sit on the
domain model. Context, recovery chain and pipeline (4) sit on those and are what every pillar step attaches to.

**Configuration and observability come next (5), before the resilience layer, and this amends the order suggested
in issue #2** — which had resilience at 5, serde at 6 and configuration/observability at 7. Three reasons, all
observed rather than theorised. The Node build found configuration and observability to be prerequisites of
retry and had to execute its own retry phase out of numeric order to get them; that is the one edge its stated
bottom-up ordering inverted, and it is cheaper to fix here than to rediscover. `RETRY`'s policy defaults — budgets,
caps, the clock and the interruptible delay primitive of `CFG-15`–`CFG-21` — come from Configuration, and its
per-attempt events come from instrumentation. And the `CTX-14`/`CTX-15` ↔ `OBS-25`/`OBS-26` shared sentinel shape,
fixed by phase 4, is then implemented in the phase immediately after the one that fixed it rather than three
phases later.

Retry, redirect and auth (6) are pillar steps and cannot precede their substrate. Serde, SSE and pagination (7)
are outer layers that consume everything underneath while depending on no concrete codec or transport — and, per
`SSE-37` and §12's chapter intro, on nothing in phase 6 either, so **6 before 7 is a convenience order, not a
dependency**. Transports and async adapters (8) come late because a transport cannot be conformance-tested until
it knows what authority it is deferring to: `TRANSPORT-1` and `TRANSPORT-2` require it to disable the native
client's own redirect and retry, which presupposes `PIPE`, `REDIR` and `RETRY` as the single authority. Conformance
(9) and deviation reconciliation (10) close the roadmap by construction — they audit what phases 0–8 built rather
than building anything new, and phase 10's method, re-deriving every ledger claim from as-built source, is why it
may ship code even though its scope is an audit.

Five cross-phase obligations are stated here because no single phase owns them:

1. **`CTX-14`/`CTX-15` and `OBS-25`/`OBS-26` are one shape.** The instrumentation bundle's trace id, span id,
   trace flags and trace state are the same W3C-shaped sentinels the tracing chapter defines. **Phase 4 fixes
   the shape and ships the bundle in core; phase 5 implements the sentinels and populates rather than replaces
   it.** Phase 4 cannot defer the decision to phase 5, and phase 5 cannot redefine it.
2. **`REDIR-11`/`REDIR-24` and `AUTH`'s stamping step are coupled.** The redirect loop is outer, auth stamping is
   inner and per hop, `REDIR-7` strips `Authorization` before every re-issue because re-attaching is auth's job,
   and the cross-origin re-issue carries an out-of-band signal auth must honour — in this port on the per-hop
   cursor rather than the request (§10.15). Both sides land in phase 6, under one contract.
3. **`RETRY` needs `RECOV` and `PIPE`, and then Configuration.** Its two stacks depend on two different substrates
   from phase 4, both of which must exist before either stack is built, and its pacing depends on phase 5's clock
   and interruptible-delay primitives (`CFG-15`–`CFG-21`) and its events on phase 5's instrumentation.
4. **`TRANSPORT` needs `SEAM`, `PIPE`, `REDIR` and `RETRY` fixed first** — phases 2, 4 and 6. Not as call targets,
   but as the authority contracts a transport defers to and disables its native equivalents for.
5. **`ASYNC` adapters implement the `SEAM`-owned pivot.** The canonical dependency-free future is core's, decided
   in phase 2 (§10.3); phase 8's adapters bridge to it and never replace it, which is also what keeps `NFR-11`'s
   RBS surface scan satisfiable.

A stated bottom-up order is not self-enforcing, and moving configuration forward pre-empts one known inversion
rather than all of them. If a later phase discovers another dependency edge that inverts this order, record it in
a dated status note here **and** in each affected phase's own Prerequisite section, and execute in the real order
rather than the numeric one.

The eleven rows account for all 645 canonical IDs: 631 in the per-prefix sums above, plus the twelve
body-lifecycle `HTTP` IDs jointly numbered into spec ch.06 that phase 3 carries, and `HTTP-1`/`HTTP-2`, the ch.02
framing pair phase 1 satisfies by construction.

**Gap IDs each phase must read from the spec chapter itself.** 22 of the 645 have no substantive corpus entry,
and a `--req` query on one returns nothing useful — budget the reading time in the phase's design document and
say so there. Phase 2: `SEAM-22`, `SEAM-28`, read out of `docs/product-spec/03-pluggable-seams-and-extension-model.md`
(`SEAM-22` is replaced by the witness protocol of §10.14, `SEAM-28` is a deferred MAY). Phase 3: `IO-6`,
`IO-32`–`IO-35`, read out of `docs/product-spec/05-i-o-contracts.md` — four of the five are the byte-stream
provider apparatus §10.1 retires, which is a decided non-implementation and not unmapped spec. Phase 4:
`RECOV-17`–`RECOV-31`, read out of `docs/product-spec/08-execution-pipelines.md` §8.2 — 15 IDs, the largest
cluster in the corpus and the one place a phase must plan for reading the specification directly rather than
querying it. Every other prefix has full corpus coverage.

**Post-v1.** Seven gems are deliberately out of scope for v1 and are register entries, not phases:
`dexpace-async-async` (`DEF-11`), `dexpace-async-concurrent_ruby` (`DEF-12`), `dexpace-transport-httpx`
(`DEF-13`), `dexpace-transport-excon` (`DEF-14`), `dexpace-transport-typhoeus` (`DEF-15`), `dexpace-serde-oj`
(`DEF-16`) and `dexpace-instrumentation-otel` (`DEF-17`). The line is not usefulness but what would be unproven
without it: a seam ships in the MVP with at least one adapter exercising the property the seam exists for, and a
second adapter over an already-proven property waits (§2.2). Three deferrals ride on those gems and so cannot
close inside v1 either — `DEF-1`'s `SEAM-24` half on `DEF-11`, `DEF-9`'s `OBS-32`/`OBS-37` on `DEF-17` together
with the async adapters, and `DEF-10`'s `TRANSPORT-28`/`TRANSPORT-30`, which are per-adapter and wait for a
transport beyond the two the MVP ships.

**Segmentation rule.** A **build phase** — phases 1 through 8 — whose ID count clearly exceeds earlier phases', or
that spans more than one ID-bearing spec chapter, or that ships more than one gem, gets a **segmentation design at
the `phaseN/` level before any sub-phase design**: `docs/work/mvp/phaseN/<date>-phaseN-segmentation-design.md`. It
decides how many ways the cut goes and in what order, and says for each sub-phase whether that order is a
dependency or a convenience, because a sub-phase plan that silently reimposes a linear chain the split existed to
avoid is a real and observed failure. Phase 0 carries no requirement scope, so the rule does not reach it; phases
9 and 10 are audit-led and segment only if their own design finds it necessary. Sub-phase letters below are
**expected until the segmentation design decides**; the boundaries named as spec-forced are not open to it.

- **Phase 3 (79 prefix IDs plus 12 jointly numbered), expected 3a I/O contracts and 3b body lifecycle.** The cut
  follows the spec's own ch.05/ch.06 line. `IO-40` forbids the streaming contracts from owning any timeout or
  deadline — enforcement belongs to the transport — which keeps I/O free of transport concerns; `BODY-17`'s
  tee-on-write builds on `IO-28`'s pump, so 3a leads 3b as a dependency, not a convenience.
- **Phase 4 (94 IDs), expected 4a execution context, 4b recovery-chain primitives, 4c stage-based pipeline.**
  `PIPE`'s steps thread state through `CTX`'s promotion chain and `RECOV-10`/`RECOV-11` re-assert cancellation on
  the current context, so 4a leads both. §8's two layers must not be collapsed into one — the design quotes the
  prohibition — so 4b and 4c stay separate segments even though `RECOV-32`/`RECOV-33` put header-stamping steps
  inside the recovery chain rather than in a pillar.
- **Phase 5 (78 IDs), expected 5a configuration, 5b instrumentation and observability.** The cut follows the
  §15/§16 line and the order is a real, if soft, dependency: `OBS-35`'s log-level resolution wants `CFG`'s layered
  lookup, which design §10.16 records alongside the configuration chain, so 5a leads deliberately. 5b is where
  `CTX-14`/`CTX-15`'s instrumentation bundle gets its `OBS-25`/`OBS-26` sentinels populated.
- **Phase 6 (111 IDs, the largest), expected 6a retry, 6b redirect, 6c authentication.** Two spec-forced facts
  constrain the cut. `RETRY` is two cooperating stacks over two different substrates — the recovery-chain half
  (§9.4 cites `RECOV-16`) and the stage-based pillar step (§8.3 cites `RETRY-27`/`RETRY-28`) — and they must not
  carry independent backoff formulas or duplicated constants, so the shared calculator lands before either stack
  and `RETRY` cannot be split along its two stacks. `REDIR-24` fixes the redirect loop outer and auth stamping
  inner, per hop, and `REDIR-11`'s cross-origin suppression signal is consumed by `AUTH`'s stamping step, so
  neither pillar half finishes without the other's contract fixed; phase 6's segmentation design settles whether
  that is one segment or two with a shared contract landed first.
- **Phase 7 (107 IDs), expected 7a serde, 7b SSE, 7c pagination.** The cut is spec-forced and so is the
  independence: `SSE-37` is a MUST that core parsing and streaming hold no serialization dependency, and §12's
  chapter intro requires the pagination engine to be transport-agnostic and serde-agnostic, with `PAGE-8`
  keeping the engine stateless and shareable. No sub-phase may depend on another, order is convenience only, and
  each sub-phase's plan must say so in its own Prerequisite section rather than inheriting a chain by habit.
  This is also the phase that ships the workspace's second real gem, `dexpace-serde-json`.
- **Phase 8 (52 nominal IDs, effectively more), expected 8a transports, 8b async runtime.** Raw count alone
  would not force a split; shipping four gems does, and so does the per-gem conformance work the count does not
  see. The cut is the §17/§18 line, which is also the `SEAM-11`-versus-`SEAM-16`/`SEAM-17` line — a synchronous
  transport and an async-runtime bridge over the core pivot are genuinely different concerns.

---

## How Phases Get Executed

Each phase, when its turn comes, runs the same cycle.

**1. Read what is already known, before writing anything.** Invoke the `knowledge-lookup` skill at the start of
the phase and again at the start of every numbered task. The phase-start pair is not optional:
`ruby scripts/knowledge.rb --origin note --brief` and `--section conflicts --brief`, because a plan that assumes
an open conflict is settled is exactly what those two queries exist to catch. Then `--prefix-info <PREFIX>` and
`--gaps <PREFIXES>` for the phase's own prefixes, and `--phase <N>` on each predecessor to see what IDs its
documents already cite. A `--req` hit tagged `[appendix-B roll-up]` is not an answer; follow the skill's
three-step roll-up path. Then the deferral sweep: **no row in `docs/deferred-items.md` currently names a target
phase** — all 19 were seeded by the MVP scope design — so a phase does not scan for its own name. It **reads the
whole register and dispositions every row**: it picks up any row whose pick-up condition this phase can meet or
whose gem this phase ships, and a row whose condition this phase meets but does not act on is marked
**UNSCHEDULED** with the phase named. Rows whose condition this phase cannot meet are left untouched.

**2. Brainstorm on a branch off `mvp`.** `mvp` is the starting point for every phase. The `brainstorming` skill
writes the design document; if the segmentation rule applies, the segmentation design comes first and the
sub-phase designs follow it.

**3. Plan.** The `writing-plans` skill writes the plain plan: numbered tasks, each citing the requirement IDs it
satisfies and the design sections it implements.

**4. File the documents.** Both skills hard-code `docs/superpowers/{specs,plans}/`, which is an inbox this
repository cannot reconfigure. Run `ruby .claude/skills/housekeeping/probe.rb`, fix what it reports, then
`ruby .claude/skills/housekeeping/apply.rb --delivery mvp --phase <N[x]> --write`, which is a `git mv` so
`git log --follow` resolves across the move. Re-run `--only links,citations` and repair anything the move staled,
in the same change. **Cite the `docs/work/` path, never the staging path.** Naming, exactly:
`docs/work/mvp/phaseN[/phaseNx]/<date>-phaseN[x]-<slug>-design.md`, the plan
`<date>-phaseN[x]-<slug>.md`, the checklist `<date>-phaseN[x]-<slug>-checklist.md`, and a segmentation design at
`docs/work/mvp/phaseN/<date>-phaseN-segmentation-design.md`. A phase directory is `phaseN` with no hyphen; a
sub-phase nests one deeper as `phaseN/phaseNx`.

**5. Implement against the plan's numbered tasks, TDD.** Write the failing test, confirm it fails, implement,
confirm it passes. Read design, plan and checklist before touching code. The implementation branch is
`<issue>-phase-<N[letter]>-<slug>` off `mvp`, and a phase returns to `mvp` as **one phase-level pull request**,
not one per sub-phase.

**6. Write the checklist at execution time,** not at planning time — it records what was actually built. One row
per requirement ID in scope, with the legend fixed in cross-cutting constraint 3.

**7. Close the phase.** Append its deferrals to `docs/deferred-items.md` — **every `DEF-<n>` appended from now on
names a target phase or an explicit pick-up condition**, because a deferral with neither is what forced the
whole-register sweep in step 1. Then its findings to `docs/open-items.md` (currently empty; the register names the
next id), its deviations to its own `## Deviation Ledger` for consolidation into design §10 and audit in
`docs/deviations.md`, and a dated status note to `## Phase Status Notes` below. Run the probe once more before
handover.

**Three rules this port adopts from the Node build's retrospectives, because each cost that build real rework:**

- **A checklist must check the plan against the styleguide as well as against the requirement IDs.** Requirement
  IDs are the only thing a spec-keyed checklist can see, and most styleguide rules carry no ID — twelve such
  drifts survived four signed-off phases there. The mechanism here is the audit-group table in the
  `knowledge-lookup` skill: each phase names the groups it ran and records the result. The groups are *public
  API surface*; *gem layout, zero-dependency core*; *RBS / Steep typing*; *RuboCop and formatting*; *Minitest
  conventions*; *encoding and binary strings*; *Fiber scheduler, thread safety*; and *styleguide-vs-design
  conflicts*. A group not in that table is added to it before the audit runs, because an audit whose group is
  not written down cannot be repeated. Precedence when a corpus rule and a plan disagree: a rule carrying a
  requirement ID beats a general styleguide default; otherwise the narrower repository-specific rule wins; and
  if both readings are satisfiable at once, satisfy both.
- **A resolution recorded only in a roadmap status note is not recorded.** Back-port it to the corpus as a note
  under `docs/knowledge/notes/<topic>.md` — role `review`, a manual `sha:` marker, and the backticked
  `<topic>/<8 hex>` key of the harvested rule it overrides — or to the register that owns it. A resolution that
  lives only here will be re-litigated by whoever reads the corpus next. `docs/knowledge/harvested/` is never
  hand-edited, and `ruby scripts/verify_knowledge_structure.rb` is the gate that keeps the two trees apart.
- **Registers need a retirement path.** A row whose pick-up condition a phase met without acting on it is marked
  **UNSCHEDULED** in `docs/deferred-items.md`, with that phase named — never silently carried as though still
  scheduled. That status exists because twenty items in the Node build named a phase that had already closed, and
  nothing noticed until someone re-audited every row against the shipped tree. Auditing the register against the
  as-built tree is a closing step of every phase, not an annual event.

---

## Phase Status Notes

Append-only. One dated entry per event; never rewrite an earlier one.

**2026-09-05** — Roadmap drafted and signed off for planning the same day. Nothing is implemented: `gems/` does not exist, no phase
directory exists under `docs/work/mvp/`, and every gem is at `0.0.0` in `docs/first-release.md`. The six
styleguide-versus-design conflicts are resolved as notes under `docs/knowledge/notes/`; the deferral register
holds 19 entries, all seeded by the MVP scope design rather than by a phase and none naming a target phase; the
open-items register is empty; and all 19 rows of `docs/deviations.md` read `design only — not yet built`. The
phase order here **amends the order suggested in issue #2**: configuration and observability move from 7 to 5,
resilience from 5 to 6, and serde/SSE/pagination from 6 to 7 — the rationale is under the phase table and is not
repeated here. Two documentation consequences, both outside this document's own scope to fix. Filing this roadmap
falsified `CLAUDE.md`'s former sentence "`mvp/` is the only delivery and it is empty"; no mechanical check catches
that, since the probe's `claims` check reads numerals and the phase-directory count is still zero, so it is
corrected by hand in the change that files this document. And phase 0 owns rewriting `CLAUDE.md`'s "After scaffold
— planned, none of these exist yet" command block from what it actually built, along with the gem-count and
phase-directory-count sentences the `claims` check does read.

**2026-09-05** — Phase 0 design and plan filed, on the same day as the roadmap.
`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md` and
`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md`. Nothing is implemented;
the checklist is written at execution time, per execution step 6. Scope is `NFR-1`–`NFR-17` as
machinery plus `SEAM-1` and `SEAM-2`; no ID is dispositioned here and phase 9 owns the answers.
The deferral sweep read all nineteen seeded rows and picked up none — `DEF-19` comes closest and
its condition, published gems to point at, is not met — the phase creates six gem
directories, but nothing is published and every gem stays at `0.0.0`. Four rows
were filed: `DEF-20` (the release path, release-gated), `DEF-21` (the runtime version-skew
assertion, phase 2), `DEF-22` (the conformance assertion objects, phase 8) and `DEF-23` (a Steep
target over a test tree, condition-gated). Five knowledge notes were filed before the plan was
written, because a resolution recorded only in a design document is re-litigated by whoever reads
the corpus next: no committed `Gemfile.lock` and no `bundle install --frozen`; the file header is
frozen-string-literal then SPDX with no Sorbet sigil to place second; `# typed: strict` applies
nowhere, test files included; the production assertion primitive is the domain model's own
validation helper and lands in phase 1; and — under `## Superseded` — the Ruby 4.0 bundled-gem
list, re-verified against a real 4.0.6 interpreter, which is 23 entries rather than the six the
corpus recorded from 3.4.10, with `tsort` leaving the default set at 4.1 and
`Gem::BUNDLED_GEMS::SINCE` undefined on the 3.2 floor. Ruby 4.0 has shipped since the roadmap was
written, so the 4.0 matrix column is an ordinary required row and the development pin is 4.0.6.

**2026-09-05** — Phase 1 design and plan filed, the same day as the roadmap and phase 0.
`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` and
`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md`. Nothing is implemented; the
checklist is written at execution time, per execution step 6. Scope is the phase-1 row's 39 IDs
plus `HTTP-1`/`HTTP-2` and `SEAM-29` as three further checklist rows — 42 in all: appendix C rows
37 and 38 assign the framing pair to the **Core HTTP domain model** subsystem, phase 2's row is
`SEAM-1`–`SEAM-30` alone, and this document's own accounting already reads "the ch.02 framing pair
phase 1 satisfies by construction", so the pair is carried here rather than treated as seam work;
`SEAM-29` is a row because this phase honours **both** its MUSTs, the uniform `<name> is required`
message and the shared generic builder contract that lets a helper accept any builder (spec ch.03
§3.8). `--gaps HTTP` reports 53 of 53 substantive, so the phase budgets no reading beyond its own
chapter. No segmentation design: one chapter, one gem, 39 IDs. The deferral sweep read all
twenty-three rows and picked up none. It gave **`DEF-2` a target phase it never had — phase 6**,
where `REDIR`/`AUTH` give `HTTP-48`–`HTTP-50`'s conditional-request helpers their first caller;
UNSCHEDULED would have been wrong, because that status is for a condition a phase met and declined
and this row's condition (convenience helpers prioritised over minimal public surface) never fired.
The four unmet SHOULDs and the MAY are also listed in `docs/first-release.md`. Three rows were
filed: `DEF-24` (the error root's suppressed trail, phase 4), `DEF-25` (wire-boundary re-validation
inside every transport, phase 8) and `DEF-26` (the `body` member's type and `HTTP-46`'s by-value
half, phase 3). Two decisions bind
every later phase and are recorded as deviations P1-1 and P1-2 with a Design §4 and a Design §5
addendum: public wire-model constants are **flat** (`Dexpace::Request`, defined under
`lib/dexpace/http/`), and `Dexpace::Error` is a **module** included by every core error class,
because `XCUT-4` puts transport errors in Ruby's `IOError` family and single inheritance makes a
class root and that requirement mutually exclusive. Two facts verified against real interpreters
during planning changed the design rather than being noted after the fact: `Data#with` **does not
call an `initialize` override on Ruby 3.2.11** (it does on 3.4.10 and 4.0.6), so the design's
derivation path would skip every `HTTP-4`/`SEAM-29` check on the declared floor — closed by a
shared `#with` in `Dexpace::Model`; and `String#strip` strips trailing NUL and raises on invalid
UTF-8, so `HTTP-17`'s trim is SP and HTAB only and every validator reads bytes. An independent
review of both documents added a third rule that binds every later phase: **no `.build` is a bare
`new` wrapper** — validation lives in each `Data` type's `initialize`, because `.build` is public,
`#with` routes every derivation through it and `send(:new, …)` reaches the constructor regardless,
so a rule enforced only in a `Builder` is a rule three callers walk around. Four knowledge
notes were filed before the plan was written: `module-organization` (the flat-constant departure),
`error-handling` (the module root and the absent `Assert` facade), `type-system` (no `T::Enum`;
closed sets are frozen `Data` types over a frozen table) and `data-modeling` (`## Superseded`: the
`Data#with` behaviour, verified per interpreter).
