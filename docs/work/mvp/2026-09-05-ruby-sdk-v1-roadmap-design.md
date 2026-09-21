# Ruby SDK — v1 Roadmap

**Status:** Draft, approved for planning (signed off 2026-09-05).

**Purpose:** An index of phases, not an implementation plan. Each row names a phase, the gem(s) it delivers,
the spec chapter and requirement IDs it satisfies, and the design chapter it maps to — and nothing else. Every
phase gets its own brainstorm → design → plan cycle when its turn comes, and the three documents that cycle
produces are where implementation detail lives. **This document never absorbs implementation detail as phases
complete.** It changes in exactly three ways: a phase's `sdk-design refs` cell gains a link to that phase's own
design document once one exists, **appended to the design citation and never replacing it**; a wrong cell is
corrected in place, with the correction stated; and a dated entry is appended to `## Phase Status Notes`. Nothing
else is edited, and no section here is ever allowed to become a register — there is one, `docs/deviations.md`,
and `docs/first-release.md` carries what the release must know (two more, for deferrals and for findings, were
retired on 2026-09-13 once every row had an owner; the second of them, the find-list, is where phase 10's
inbound list below got the fourteen audit-and-repair items it now states in full), and an aggregate findings
or deferral section inside this document is drift the `housekeeping` probe reports.

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
simplification, named reason) · ⏳ deferred (naming the plan task — phase, task number and path — that will do
it, or the `docs/first-release.md` entry that owns it) · N/A not applicable in this port.

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

**7. Register discipline** (corrected in place 2026-09-13, twice: as first written this named four registers and
a deferral sweep, and it then named a find-list retired later the same day). `docs/README.md` owns the register
boundary: one appendable register — `docs/deviations.md`, the audit of design §10 — plus `docs/first-release.md`
for what the release must know. **A finding is not registered either**: it is routed to its owner when it is
found — a numbered task in the plan of the phase whose scope it falls in, a bullet on phase 10's inbound list
below when it is audit or repair work against an already-planned phase, a `docs/first-release.md` entry when it
belongs to the release, or simply the fix. Work a phase postpones is not registered either: it is either scheduled as a numbered task in the plan of the
phase that will do it, cited by path and task number, or, when no v1 phase will do it, recorded in
`docs/first-release.md` under the fitting section — what v1 ships without, the release path, or a post-release
trigger. A deviation goes to the phase's own `## Deviation Ledger`, then design §10, then the audit in
`docs/deviations.md`, whose 19 rows read `design only — not yet built` until the phase that builds the gem flips one.

**8. Three MUSTs are known-unsatisfied; do not re-open the trade.** `ASYNC-3` and `PIPE-33`'s interrupt clause are
unsatisfied and `ASYNC-4` vacuous (design §10.5, stated for the release under `docs/first-release.md` § What v1
ships without › Unsatisfied MUSTs): phase 8 marks `ASYNC-3` and `PIPE-33`'s
interrupt clause ⏳ citing it and `ASYNC-4` **N/A**, per §10.5's own distinction between an unsatisfied MUST and a
vacuous one (**corrected in place 2026-09-11** by the phase-8 segmentation design; the earlier sentence summarised
all three as ⏳, and that release entry names only the first two — `ASYNC-4` belongs on no unsatisfied-MUST list
and should not be); phase 10 audits the ledger. The fenced-example executor for `.claude/skills/housekeeping/` is
release-gated — `docs/first-release.md` § Release path › After the first publish, closable by no phase.

**9. Pointers, not copies.** The domain-model construction pattern (`CLAUDE.md`, design §4) and the constraints that
will bite (`CLAUDE.md`, design §3.1, §3.7, §7.1, §8.2, §8.3) are cited from a phase document, never copied into one.

---

## Phase List

| Phase | Name | Gem(s) | Product-spec refs | sdk-design refs |
|---|---|---|---|---|
| 0 | Scaffold and Quality Gates | workspace root, plus all six MVP gems at `0.0.0` with empty `lib`/`sig`/`test`: `dexpace-core`, `dexpace-transport-net_http`, `dexpace-transport-async_http`, `dexpace-serde-json`, `dexpace-async-thread`, `dexpace-conformance` | §20 — `NFR-1`–`NFR-17`, every gate stood up as machinery and none closed here; phase 9 dispositions them. `NFR-5`'s SimpleCov `minimum_coverage 80` is wired here and inert until phase 1 lands code | §2.3, §2.4, §9 |
| 1 | Core HTTP Domain Model | `dexpace-core` | §4 — `HTTP-3`–`HTTP-35`, `HTTP-46`–`HTTP-50`, `HTTP-53` (39 IDs); `SEAM-29`'s construction contract honoured ahead of phase 2 | §4; §3.5's strict component encoder and `URI::RFC3986_PARSER` pin for `HTTP-29`/`HTTP-32` (the rest of §3.5 is `SEAM-26`/`SEAM-27`, phase 2's); phase design: [`phase1/2026-09-05-phase1-core-http-domain-model-design.md`](./phase1/2026-09-05-phase1-core-http-domain-model-design.md) |
| 2 | Seam Foundations | `dexpace-core` | §3 — `SEAM-1`–`SEAM-30` (30 IDs) | §2.4, §3.1–§3.7, §10.3, §10.8, §10.9; phase design: [`phase2/2026-09-06-phase2-seam-foundations-design.md`](./phase2/2026-09-06-phase2-seam-foundations-design.md) |
| 3 | I/O and Body Lifecycle | `dexpace-core` | §5 — `IO-1`–`IO-42` (42); ch.06 — `BODY-1`–`BODY-37` (37), plus `HTTP-36`–`HTTP-45`, `HTTP-51`, `HTTP-52` jointly numbered into that chapter | §3.1, §10.1, §10.2, §10.12; segmentation design: [`phase3/2026-09-08-phase3-segmentation-design.md`](./phase3/2026-09-08-phase3-segmentation-design.md); 3a design: [`phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md`](./phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md); 3b design: [`phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`](./phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md) |
| 4 | Execution Context and Pipelines | `dexpace-core` | §7 — `CTX-1`–`CTX-20` (20); §8.2 — `RECOV-1`–`RECOV-34` (34); §8.1 — `PIPE-1`–`PIPE-40` (40) | §5.1–§5.4, §8.1; segmentation design: [`phase4/2026-09-08-phase4-segmentation-design.md`](./phase4/2026-09-08-phase4-segmentation-design.md); 4a design: [`phase4/phase4a/2026-09-08-phase4a-execution-context-design.md`](./phase4/phase4a/2026-09-08-phase4a-execution-context-design.md); 4b design: [`phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`](./phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md); 4c design: [`phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`](./phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md) |
| 5 | Configuration and Observability | `dexpace-core` | §16 — `CFG-1`–`CFG-38` (38); §15 — `OBS-1`–`OBS-40` (40) | §8.1–§8.3, §10.16, §10.17; segmentation design: [`phase5/2026-09-09-phase5-segmentation-design.md`](./phase5/2026-09-09-phase5-segmentation-design.md); 5a design: [`phase5/phase5a/2026-09-09-phase5a-configuration-design.md`](./phase5/phase5a/2026-09-09-phase5a-configuration-design.md); 5b design: [`phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`](./phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md); 5c design: [`phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md`](./phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md) |
| 6 | Retry, Redirect and Authentication | `dexpace-core` | §9 — `RETRY-1`–`RETRY-45` (45); §10 — `REDIR-1`–`REDIR-28` (28); §11 — `AUTH-1`–`AUTH-38` (38) | §6.1–§6.3, §8.3, §10.15; segmentation design: [`phase6/2026-09-09-phase6-segmentation-design.md`](./phase6/2026-09-09-phase6-segmentation-design.md); 6a design: [`phase6/phase6a/2026-09-09-phase6a-retry-design.md`](./phase6/phase6a/2026-09-09-phase6a-retry-design.md); 6b design: [`phase6/phase6b/2026-09-09-phase6b-redirect-design.md`](./phase6/phase6b/2026-09-09-phase6b-redirect-design.md); 6c design: [`phase6/phase6c/2026-09-09-phase6c-authentication-design.md`](./phase6/phase6c/2026-09-09-phase6c-authentication-design.md) |
| 7 | Serde, SSE and Pagination | `dexpace-core`, `dexpace-serde-json` | §14 — `SERDE-1`–`SERDE-30` (30); §13 — `SSE-1`–`SSE-41` (41); §12 — `PAGE-1`–`PAGE-36` (36) | §3.4, §7.1–§7.3, §10.13, §10.14; segmentation design: [`phase7/2026-09-10-phase7-segmentation-design.md`](./phase7/2026-09-10-phase7-segmentation-design.md); 7a design: [`phase7/phase7a/2026-09-10-phase7a-serialization-design.md`](./phase7/phase7a/2026-09-10-phase7a-serialization-design.md); 7b design: [`phase7/phase7b/2026-09-10-phase7b-server-sent-events-design.md`](./phase7/phase7b/2026-09-10-phase7b-server-sent-events-design.md); 7c design: [`phase7/phase7c/2026-09-10-phase7c-pagination-design.md`](./phase7/phase7c/2026-09-10-phase7c-pagination-design.md) |
| 8 | Transports and Async Runtime | `dexpace-transport-net_http`, `dexpace-transport-async_http`, `dexpace-async-thread`, and `dexpace-conformance` — phase 8 owns that gem: its gemspec, its version and its first release, shipping the transport conformance suite | §17 — `TRANSPORT-1`–`TRANSPORT-30` (30); §18 — `ASYNC-1`–`ASYNC-22` (22) | §3.2, §3.3, §3.7, §9.3, §10.5; segmentation design: [`phase8/2026-09-11-phase8-segmentation-design.md`](./phase8/2026-09-11-phase8-segmentation-design.md); 8a design: [`phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md`](./phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md); 8b design: [`phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-design.md`](./phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-design.md); 8c design: [`phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md`](./phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md) |
| 9 | Cross-Cutting Invariants and Conformance | `dexpace-conformance` — adds the remaining suites to phase 8's gem, owning neither its gemspec nor its release; every gem audited | §19 — `XCUT-1`–`XCUT-24` (24); §20 — `NFR-1`–`NFR-17` (17); appendix B | §9, §9.3, §10.19; phase design: [`phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-design.md`](./phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-design.md) |
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
say so there. **The three pointers below were corrected in place on 2026-09-13**; as first written each named
the prefix's owning spec chapter, and for most of these IDs the chapter does not carry them at all —
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` is their only normative statement,
so a phase following the pointer literally either reads the wrong requirements or concludes the specification
is missing them — and for `SEAM-22` and `SEAM-28` the IDs carrying the pointer are precisely the two the
corpus cannot answer, so the phase reading them has no second source. The pointers now name the source that actually carries each ID. Phase 2: `SEAM-22`, `SEAM-28`,
read out of **appendix C** (`SEAM-22` is replaced by the witness protocol of §10.14, `SEAM-28` is a deferred
MAY). `docs/product-spec/03-pluggable-seams-and-extension-model.md` carries 22 of the 30 `SEAM` IDs and
`docs/product-spec/02-architectural-principles.md` three more; the remaining five — `SEAM-15`, `SEAM-20`,
`SEAM-22`, `SEAM-23` and `SEAM-28` — are appendix-C rows and nothing else, verified 2026-09-06 and re-verified
2026-09-07 with `grep -o 'SEAM-[0-9]*' docs/product-spec/*.md | grep -v appendix-c | sort -uV`, which lists
exactly 25. The other three escape this paragraph only because the *design* rescued them: `SEAM-15`, `SEAM-20`
and `SEAM-23` have substantive design-role corpus entries from
`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.4 and §3.7, so a phase querying the corpus gets
a good answer and never learns the design entry is the only prose between it and appendix C. Phase 2 read all
five out of appendix C directly. Phase 3: `IO-32`–`IO-35`, read out of
`docs/product-spec/05-i-o-contracts.md` — the byte-stream provider apparatus §10.1 retires, which is a decided
non-implementation and not unmapped spec — and **`IO-6` out of appendix C**, which is the sharper case, because
`IO-6` is neither retired nor a non-implementation but a **live MUST**: "the returned wrapper MUST take
ownership of that stream: closing the wrapper closes the underlying stream". §5.1 runs `IO-1`–`IO-5` and
`IO-18`; only the bridge half of `IO-6`'s obligation survives there, under `IO-16`, a SHOULD. Both places that
state `IO-6`'s content attribute it to **`SEAM-3`**, which design §10 item 1 retires and phase 2 shipped as 🚫
— §3.1's "Two ownership rules, deliberately different" paragraph and the corpus entry
`message-bodies/8a1e7a7b` — so a phase auditing `SEAM-3`'s retirement and finding no surviving citation could
reasonably conclude the ownership rule retires with the seam. It does not: `IO-6` is its surviving normative
home, design §10 item 12 depends on it, and `BODY-8` is the other half of that one decision. 3a read `IO-6`
out of appendix C. Phase 4: `RECOV-17`–`RECOV-31`, read out of **appendix C** — 15 IDs, the largest cluster in
the corpus and the one place a phase must plan for reading the specification directly rather than querying it.
`docs/product-spec/08-execution-pipelines.md` §8.2 states `RECOV-1` through `RECOV-16` and stops: verified
2026-09-08 by repository-wide grep, **`RECOV-17` through `RECOV-34` appear nowhere in `docs/product-spec/`
outside appendix C** — eighteen IDs, not fifteen, because `RECOV-32`, `RECOV-33` and `RECOV-34` escape the
count above only through design-role corpus entries (`pipeline/785eab36`, `pipeline/2e998896`,
`pipeline/7f286969`, `retry-and-resilience/58d2faad`, `retry-and-resilience/c9228a67`). "The corpus cannot
answer" and "the specification cannot answer" are independent facts here, and this paragraph measures only the
first. Phase 4's segmentation design read all eighteen out of appendix C and dispositioned each; fifteen travel
to phase 6a with the recovery-stack work, so the reading budget largely transfers with it. Every other prefix
has full corpus coverage. **At three occurrences across three prefixes this is a property of appendix C's
relationship to the prose chapters** — appendix C is the superset, and a chapter is not obliged to state every
row its prefix owns — rather than three separate omissions; `ruby scripts/knowledge.rb --gaps` derives its own
trailing pointer from appendix C's subsystem cell, is not wrong about the *subsystem*, and inherits the same
unfollowability, which is why the fix belongs to the derivation rather than to three roadmap sentences.

**Post-v1.** Seven gems are deliberately out of scope for v1 and are release-notes entries, not phases (listed in
`docs/first-release.md` § What v1 ships without › Post-v1 gems since 2026-09-13; design §2.2 is the authority):
`dexpace-async-async`, `dexpace-async-concurrent_ruby`, `dexpace-transport-httpx`, `dexpace-transport-excon`,
`dexpace-transport-typhoeus`, `dexpace-serde-oj` and `dexpace-instrumentation-otel`. The line is not usefulness but what would be unproven
without it: a seam ships in the MVP with at least one adapter exercising the property the seam exists for, and a
second adapter over an already-proven property waits (§2.2). Three postponed requirements ride on those gems and
so cannot close inside v1 either — `SEAM-24`'s cancellation-bridge half on `dexpace-async-async`,
`OBS-32`/`OBS-37` on `dexpace-instrumentation-otel` together with the async adapters, and `TRANSPORT-28`'s
zero-copy clause with `TRANSPORT-30`, which are per-adapter and wait for a transport beyond the two the MVP ships;
all three are entries under `docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level requirements
declined for v1.

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
  tee-on-write builds on the tee sink of `IO-25`–`IO-29` and on `IO-17`'s pump, so 3a leads 3b as a dependency,
  not a convenience. (**Corrected in place 2026-09-08** by the phase-3 segmentation design, which confirmed the
  dependency and eight more edges like it: this bullet formerly read "`IO-28`'s pump". `IO-28` is the tee's
  no-direct-backing-buffer prohibition, restated at the body layer by `BODY-37`; the pump is `IO-17`.)
- **Phase 4 (94 IDs), expected 4a execution context, 4b recovery-chain primitives, 4c stage-based pipeline.**
  4a leads both, and the order is a **convenience**. §8's two layers must not be collapsed into one — the design
  quotes the prohibition — so 4b and 4c stay separate segments even though `RECOV-32`/`RECOV-33` put
  header-stamping steps inside the recovery chain rather than in a pillar. (**Corrected in place 2026-09-08** by
  the phase-4 segmentation design, which adopted the three-way cut and the letters but found the stated reason
  false on both halves: this bullet formerly read "`PIPE`'s steps thread state through `CTX`'s promotion chain and
  `RECOV-10`/`RECOV-11` re-assert cancellation on the current context, so 4a leads both." `PIPE`'s steps thread
  state through their own **per-call cursor** (`PIPE-11` says so outright; `PIPE-13`, `PIPE-16`, `PIPE-17`,
  design §5.1's cursor-scoped state), and `CTX-<n>` is cited in no specification chapter outside ch.07 and in no
  design section outside §5.4, §8.1, §11.11 and §12 bar a single `CTX-9` **comparison** in §5.2 that reads
  nothing from it; `RECOV-10` carries no cancellation or context clause at all, and `RECOV-11`'s "current
  context" is rendered by design §5.2 as **the ambient cancellation token**, `Dexpace::Cancellation`, which phase
  2 already built. Nothing in `RECOV` or `PIPE` consumes `CTX`, so the three sub-phases are independent and each
  sub-phase design must say so in its own Prerequisite section.)
- **Phase 5 (78 IDs), expected 5a configuration, 5b instrumentation and observability.** The cut follows the
  §15/§16 line and the order is a real, if soft, dependency: `OBS-35`'s log-level resolution wants `CFG`'s layered
  lookup, which design §10.16 records alongside the configuration chain, so 5a leads deliberately. 5b is where
  `CTX-14`/`CTX-15`'s instrumentation bundle gets its `OBS-25`/`OBS-26` sentinels populated.
- **Phase 6 (111 prefix IDs of its own, the largest, plus the fifteen `RECOV` IDs phase 4 handed it), expected 6a retry, 6b redirect,
  6c authentication.** (**Corrected in place 2026-09-08** by the phase-4 segmentation design: this bullet
  formerly opened "Phase 6 (111 IDs, the largest)". The **count is unchanged and the phase-6 row above is
  unchanged** — no requirement ID moved, and `RETRY-1`–`RETRY-45`, `REDIR-1`–`REDIR-28` and `AUTH-1`–`AUTH-38`
  still sum to 111 — but the **scope** the number stood for is now stale. Phase 4's segmentation design moves the *work* of fifteen
  `RECOV` IDs into this phase: `RECOV-17`–`RECOV-30` and `RECOV-34`, the recovery-stack retry engine, whose
  checklist rows stay in phase 4 as ⏳ and whose implementation lands here. **Phase 6's segmentation design must
  budget for 111 + 15 and not for 111**, and it decides whether each of the fifteen is a separate checklist row
  or a cross-reference to its `RETRY` twin — the phase-4 segmentation design carries the twin-by-twin table in
  full, and the work landed in 6a's Tasks 3, 4, 5, 7 and 11
  (`docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry.md`), so the mapping does not have to be re-derived.
  The cluster phase 4 identified is *sixteen* IDs; the sixteenth, `RECOV-31`, is **not** among the fifteen and
  is **not** phase-6 work — it and its `RETRY-38` twin are declined for v1 (`docs/first-release.md` § What v1
  ships without › SHOULD- and MAY-level requirements declined for v1, the `RECOV-31`/`RETRY-38` entry) — so it
  may carry a row here but never a budget line. Phase 6 is by this margin the
  largest phase in the roadmap, and it was already the largest before the fifteen arrived.) Two spec-forced facts
  constrain the cut, and the hand-off of the fifteen is a direct consequence of the first. `RETRY` is two cooperating stacks over
  two different substrates — the recovery-chain half
  (§9.4 cites `RECOV-16`) and the stage-based pillar step (§8.3 cites `RETRY-27`/`RETRY-28`) — and they must not
  carry independent backoff formulas or duplicated constants, so the shared calculator lands before either stack
  and `RETRY` cannot be split along its two stacks. That is precisely why phase 4 cannot build the recovery
  half: a calculator built two phases early is the duplication `RETRY-13` forbids, so the recovery-stack engine
  waits for the phase that owns the shared calculator. `REDIR-24` fixes the redirect loop outer and auth stamping
  inner, per hop, and `REDIR-11`'s cross-origin suppression signal is consumed by `AUTH`'s stamping step, so
  neither pillar half finishes without the other's contract fixed. (**Corrected in place 2026-09-09** by the
  phase-6 segmentation design: this sentence formerly ended "phase 6's segmentation design settles whether that
  is one segment or two with a shared contract landed first." **That decision was already made, by phase 4c on
  2026-09-08**, and phase 6 inherits it rather than taking it.
  `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md` fixes the stage order —
  `PRE_REDIRECT` 100 → `REDIRECT` 200 → … → `AUTH` 800, `PIPE-2` — ships `Cursor#fork(state:)`,
  `Cursor#state(stage)` and the restriction that only the forking step's own stage may write state, and writes
  its `R11` negative assertions against `Stages::REDIRECT` by name. The redirect step forks per hop with
  `state: {cross_origin: …}`; the auth step reads `cursor.state(Stages::REDIRECT)`; **phase 6 adds no marker to
  the request and strips nothing**, which is design §10.15's claim. So the cut is **three independent
  segments** — 6a retry, 6b redirect, 6c authentication — with no shared-contract sub-phase, and the only thing
  needing both halves is an end-to-end credential-leak test, a convergence point rather than a build-order
  dependency. The `REDIR-24` and `REDIR-11` facts stated above are unchanged and still constrain the
  implementation.)
- **Phase 7 (107 IDs), expected 7a serde, 7b SSE, 7c pagination.** The cut is spec-forced and so is the
  independence: `SSE-37` is a MUST that core parsing and streaming hold no serialization dependency, and §12's
  chapter intro requires the pagination engine to be transport-agnostic and serde-agnostic, with `PAGE-8`
  keeping the engine stateless and shareable. No sub-phase may depend on another, order is convenience only, and
  each sub-phase's plan must say so in its own Prerequisite section rather than inheriting a chain by habit.
  This is also the phase that ships the workspace's second real gem, `dexpace-serde-json`.
- **Phase 8 (52 nominal IDs, effectively more), expected 8a transports, 8b async runtime.** Raw count
  alone would not force a split; shipping four gems does, and so does the per-gem conformance work the
  count does not see. The cut is the §17/§18 line, which is also the
  `SEAM-11`-versus-`SEAM-16`/`SEAM-17` line — a synchronous transport and an async-runtime bridge over
  the core pivot are genuinely different concerns. (**Corrected in place 2026-09-11** by the phase-8
  segmentation design, which took a **three-way** cut — `8a` synchronous transport and the conformance
  gem, `8b` async-runtime adapter, `8c` asynchronous transport — and found the stated reason false on
  the §17 side. **The count is unchanged and the phase-8 row above is unchanged**: `TRANSPORT-1`–`30`
  and `ASYNC-1`–`22` still sum to 52 and no ID moves. What is wrong is the claim that the chapter line
  *is* the seam line. Five of §17's thirty requirements — `TRANSPORT-7`, `TRANSPORT-8`,
  `TRANSPORT-9`, `TRANSPORT-21` and `TRANSPORT-23` — have an **async-only antecedent** and are
  `SEAM-16`'s, so a synchronous-transport segment cannot exercise them, and §17's own preamble names
  "§7 / **SEAM-11, SEAM-16**" together in its first sentence. In the other direction the pairing is too
  tidy rather than wrong: fifteen of §18's twenty-two impose an **executor, worker, pooled-thread or
  bridge** obligation — `SEAM-18` and `SEAM-25` — while §18's own preamble names **`SEAM-17`** as its
  interchange point, so the chapter line is not the seam line in either direction.
  `dexpace-transport-async_http` sits on neither side of the chapter line:
  it is a transport by chapter — §2.1 calls it "The reference *asynchronous* transport" — and is
  **not** an async-runtime adapter by §18's own definition, because
  it bridges nothing: it implements the SPI natively over a reactor. So it gets its own segment. The
  three sub-phases are **independent** and every boundary is a **convenience**; `dexpace-async-thread`
  declares `dexpace-core` and nothing else, `dexpace-transport-async_http` declares `async-http` and
  needs no thread pool, and the two shared artifacts — §9.3's `TCPServer` fixture and the conformance
  assertion protocol phase 0 postponed to this phase — are **assigned to `8a`**, with each design stating whether it wrote or consumed
  them if the sub-phases run out of order. One task is
  phase-level because it lands in a gem none of the three ships: `Dexpace::TransportError < ::IOError`
  in `dexpace-core`, which closes `docs/first-release.md`'s standing phase-8 blocker. Cross-cutting
  constraint 4's "phase 8 brings the first real socket" is confirmed and is worth narrowing: `8a` and
  `8c` bring it and `8b` brings none.)

---

## How Phases Get Executed

Each phase, when its turn comes, runs the same cycle.

**1. Read what is already known, before writing anything.** Invoke the `knowledge-lookup` skill at the start of
the phase and again at the start of every numbered task. The phase-start pair is not optional:
`ruby scripts/knowledge.rb --origin note --brief` and `--section conflicts --brief`, because a plan that assumes
an open conflict is settled is exactly what those two queries exist to catch. Then `--prefix-info <PREFIX>` and
`--gaps <PREFIXES>` for the phase's own prefixes, and `--phase <N>` on each predecessor to see what IDs its
documents already cite. A `--req` hit tagged `[appendix-B roll-up]` is not an answer; follow the skill's
three-step roll-up path. Then read what earlier phases scheduled against this phase (**corrected in place
2026-09-13**; as first written this step was a sweep of a deferral register — none of its 19 seeded rows named a
target phase, so a phase read the whole file and dispositioned every row — and that register was retired the same
day, once every row named an owner): grep the plans for this phase's name to find the tasks earlier phases
scheduled here, and read the three `docs/first-release.md` sections — what v1 ships without, the release path and
the post-release triggers — so nothing scheduled here is re-derived or dropped.

**2. Brainstorm on a branch off `main`** (**corrected in place 2026-09-14**; as first written this step branched
off `mvp`, an integration branch retired that day — `mvp` survives only as the delivery name under `docs/work/`).
`main` is the starting point for every phase. The `brainstorming` skill
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
`<issue>-phase-<N[letter]>-<slug>` off `main`, and **each sub-phase returns to `main` as its own stack of three
pull requests — code, tests, documentation — branched off `main`, each targeting the one below it and merged
bottom-up** (**corrected in place 2026-09-16**; as first written, "a phase returns to `main` as one phase-level
pull request, not one per sub-phase" — which no phase did: phases 1, 2, 3a and 3b each landed as their own
code → tests → docs stack, and 4a and 4b run as two parallel stacks, so the rule now states what the
repository does; and **corrected in place 2026-09-14** before that: as first written, off and back to `mvp`,
the integration branch retired that day).

**6. Write the checklist at execution time,** not at planning time — it records what was actually built. One row
per requirement ID in scope, with the legend fixed in cross-cutting constraint 3.

**7. Close the phase.** Record what it postponed (**corrected in place 2026-09-13**; as first written this step
appended deferrals to a register, since retired): work this phase postpones is either scheduled as a numbered task
in the plan of the phase that will do it, cited by path and task number, or, when no v1 phase will do it, recorded
in `docs/first-release.md` under the fitting section — and a task an earlier phase scheduled here that this phase
declines is recorded in its own design's postponed-work section with the reason, and in `docs/first-release.md`
if the decision means v1 ships without it. Then its findings to their owners — the plan task, phase 10's inbound
list or `docs/first-release.md`, per constraint 7 (**corrected in place 2026-09-13**; as first written this step
sent them to a find-list register, since retired) — its deviations to its own `## Deviation Ledger` for consolidation into design §10 and audit in
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
- **Every postponed item names its owner, never a bare id.** As first written this rule gave the deferral
  register a retirement path — a row whose pick-up condition a phase met without acting on it was marked
  UNSCHEDULED with that phase named, never silently carried as though still scheduled — because twenty items in
  the Node build named a phase that had already closed, and nothing noticed until someone re-audited every row
  against the shipped tree. What actually happened here: the register was reconciled against phases 0 through 9
  and retired on 2026-09-13, once every row had an owner — a numbered plan task or a `docs/first-release.md`
  entry. The durable lesson is the one the retirement enforced: a postponed item names the plan task (phase, task
  number, path) or the release entry that owns it, never a bare identifier, so auditing postponed work against
  the as-built tree means reading the plans and the release file — a closing step of every phase, not an annual
  event.

---

## Phase Status Notes

Append-only. One dated entry per event; never rewrite an earlier one. One correction in place, made once: on
2026-09-13 every citation of the deferral register in the notes below was rewritten in place to name the item's
owner — the plan task or the `docs/first-release.md` entry — because the register was retired that day.

**2026-09-05** — Roadmap drafted and signed off for planning the same day. Nothing is implemented: `gems/` does not exist, no phase
directory exists under `docs/work/mvp/`, and every gem is at `0.0.0` in `docs/first-release.md`. The six
styleguide-versus-design conflicts are resolved as notes under `docs/knowledge/notes/`; nineteen items stand
postponed by the MVP scope design rather than by a phase, none yet naming the phase or release entry that would
own it; no finding has been made yet; and all 19 rows of `docs/deviations.md` read `design only — not yet built`. The
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
Phase 0 read the nineteen items the MVP scope design had postponed and picked up none — the
fenced-example executor for `.claude/skills/housekeeping/` comes closest and its condition,
published gems to point at, is not met — the phase creates six gem directories, but nothing is
published and every gem stays at `0.0.0` (it now sits under `docs/first-release.md` § Release path ›
After the first publish). Four items were postponed: the release path (signed publication, `NFR-16`
and `NFR-12`'s release half — `docs/first-release.md` § Release path), the runtime version-skew
assertion (phase 2, which built it as `Dexpace::Registry#register(key, factory, core:)`, P2-7), the
conformance assertion objects (phase 8a, Tasks 4–8 and 20, with phase 9, Tasks 2–12a adding the
remaining suites) and a Steep target over a test tree (condition-gated; `docs/first-release.md`
§ Post-release triggers). Five knowledge notes were filed before the plan was
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
chapter. No segmentation design: one chapter, one gem, 39 IDs. Phase 1 read all twenty-three
postponed items and picked up none. It gave **the `HTTP-22`/`HTTP-48`–`HTTP-50` helpers a target
phase they never had — phase 6**, where `REDIR`/`AUTH` were expected to give the conditional-request
helpers their first caller (the target did not fire, and the decision now stands as the
`HTTP-22`/`48`/`49`/`50` line under `docs/first-release.md` § Blockers before first publish);
declining would have been wrong, because that is for a condition a phase met and declined and this
item's condition (convenience helpers prioritised over minimal public surface) never fired. The four
unmet SHOULDs and the MAY are also listed in `docs/first-release.md`. Three items were postponed:
the error root's suppressed trail (phase 4 — built by 4b, Task 1), wire-boundary re-validation
inside every transport (phase 8 — 8a Task 16 and 8c Task 9, with phase 9 Task 7's portable
assertion) and the `body` member's type and `HTTP-46`'s by-value half (phase 3 — built by 3b,
P3-15). Two decisions bind
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

**2026-09-07** — Phase 2 design and plan filed. The design landed a day earlier and was committed
on its own, at `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md`; the plan is
`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md`. Nothing is implemented; the checklist
is written at execution time, per execution step 6. Scope is the phase-2 row's thirty IDs,
`SEAM-1`–`SEAM-30`, one checklist row each — with **`SEAM-29`'s row a cross-reference to phase 1**,
which honoured both of its MUSTs ahead of this phase, because dropping the row would leave an ID
inside this phase's stated range with no row in the phase that owns the range. No segmentation
design: one chapter, one gem, thirty IDs, fewer than phase 1's forty-two rows. Phase 2 read all
twenty-six postponed items and **picked up the runtime half of the version-skew guard**, which
phase 0 had postponed to phase 2 explicitly: it is now a required `core:` keyword on
`Dexpace::Registry#register`. It gave **`SEAM-28` a target it never had — phase 5**, where an
operation identifier first has both the context chain it attaches to (phase 4's) and a consumer for
it (it landed as 5c, Task 4 over 4a's `RequestContext#operation_name`); declining would have been
wrong, because that item's condition — "picked up opportunistically" — is not a condition any phase
could meet. Five items were postponed: the two disposal routes for `close_quietly`'s rescued error
(phases 4 and 5 — 4b Task 2 and 5b Task 14), the pivot's `deadline:` keyword and the clock behind
it (phase 5 — 5a Task 8), moving the three in-memory fakes into `dexpace-conformance` (phase 8 —
declined there by 8a on the development-dependency cycle it would create), presence-gated
auto-activation, instrumentation only (post-v1 — `docs/first-release.md` § What v1 ships without)
and `SEAM-25`'s lifecycle event on the first close of an owned executor (phase 5 — emitted by 8b
Tasks 6 and 10, harnessed by phase 9 Task 11). **The first of the three unfollowable gap pointers was found**: five `SEAM` IDs —
`SEAM-15`, `SEAM-20`, `SEAM-22`, `SEAM-23` and `SEAM-28` — appear nowhere in the specification's
prose and exist only as appendix-C rows, so this document's own gap paragraph and
`scripts/knowledge.rb --gaps SEAM`, which both sent a reader to
`docs/product-spec/03-pluggable-seams-and-extension-model.md` for `SEAM-22` and `SEAM-28`, named a
chapter that does not carry them. The pointer is derived mechanically from appendix C's subsystem
cell and is not wrong about the subsystem; the instruction built on it was unfollowable. Phase 2
read all five out of appendix C directly, and the gap paragraph above now names appendix C as their
source (corrected 2026-09-13). Four knowledge notes were filed before the plan was
written: `module-organization` (require-time seam self-registration is the one load-time side
effect this repository permits, against the styleguide's "no global registry mutation at file
scope"), `data-modeling` (a seam is a duck type plus a `.conforms?` predicate plus an RBS interface,
never a Sorbet abstract module), `concurrency-and-async` — a new file — (core's shared mutable state
is a frozen `Data` snapshot swapped under a `Thread::Mutex`, because `concurrent-ruby` is a gem),
and `url-and-query-encoding` — a new file, under `## Superseded` — (`SEAM-27`'s base composition is
not RFC 3986 reference resolution, and `URI.join` is banned by a phase-0 cop). Three facts verified
against real interpreters during planning changed the design rather than being noted after it.
`URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets")` is `https://host/pets` on 3.2.11 and
4.0.6 alike, dropping both the base path segment and the base query that `SEAM-27`'s own
conformance example requires to survive — so the composition is hand-built and design §3.5's
sentence is superseded for this seam while staying correct for `REDIR-13` in phase 6. A bare
`Thread` inside `module Dexpace::Async` resolves to Ruby's `Thread` until `dexpace-async-thread` is
required and to `Dexpace::Async::Thread` afterwards, and core's own suite never requires that gem —
a bug that cannot fail in the tree that contains it, so the phase adds a **sixth custom cop**
alongside a behavioural test that defines the adapter's constant and re-runs the pivot. And `Gem` is
undefined under `ruby --disable-gems`, so the version-skew guard's comparison is hand-rolled and `Gem::Requirement`
appears only in the test that cross-checks it. Thirteen decisions are recorded as deviations P2-1
through P2-13, with a Design §3 addendum (two entries) and a Design §9 addendum (one), for
consolidation into design §10 and audit in `docs/deviations.md`. An independent review of both
documents reproduced four behavioural defects in the plan's own fences on all three interpreters —
a composed cancellation token reporting a reason different from the one it had just handed its
handler; a per-token rather than per-registration `#on_cancel` guard, which left a second waiter on
one token blocked forever and was a flat `SEAM-18` violation; a registry that called a factory and
the conformance predicate while holding a non-reentrant mutex; and a cop that flagged its own
accepted case — and every one is fixed in the filed plan. A second review found four more, all reproduced: a
resolution claim released only on the `StandardError` path, so a `LoadError` from a factory wedged
the registry into a silent spin; `#swap` restoring a captured snapshot that still carried a
completed resolution's closed gate, the same wedge through the seam every adapter suite uses; a
method-level `else` in the sync-to-async bridge that let a raise escape the posted block and leave
the future permanently unsettled; and three lock tests that passed under the very shape their
comments said they rejected. All four are fixed, and each guard was run red against the pre-fix
code first. The plan's **44 `ruby` fences are extracted, written to the 41 files they name and
run**: 169 runs, 537 assertions, 0 failures on 3.2.11 and 3.4.10 and 545 on 4.0.6, warning-free
under `ruby -w` and identical across six seeds. The RuboCop cop is the one fence that cannot run
against this project's toolchain — no RuboCop is installed until phase 0 — and was executed during
review on RuboCop 1.90.0 through phase 0's verbatim harness: 17 runs, 61 assertions, 0 failures.

**2026-09-08** — Phase 3 segmentation design filed, at
`docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md`. It is the first segmentation
design the rule above has produced; no sub-phase design or plan exists yet, and nothing is
implemented. **The cut is two ways, on the spec's own ch.05/ch.06 line, and 3a leads 3b as a
dependency** — the expectation in the segmentation bullet, adopted on evidence rather than
inherited: eight named edges run 3a→3b (`BODY-17`–`BODY-21`/`BODY-37` on the `IO-25`–`IO-29` tee,
`BODY-3` on the `IO-7`–`IO-10` buffer, `BODY-10` on `IO-12`/`IO-17`, `BODY-22`–`BODY-29` on
`IO-19`/`IO-20`/`IO-41`/`IO-42`, `BODY-32`/`BODY-33` on `IO-9`'s ceiling, `HTTP-41`/`BODY-14` on
`BufferedSource`, `HTTP-42` on `IO-13`, `BODY-8` on `IO-6`) and none runs back. The one edge that
would have — `BufferedSource.over(body)` is a 3a artifact taking a body — is removed by fixing the
canonical body *representation* (§10.2's `#each`-yielding-BINARY duck type) in 3a while the body
*production contract* (`HTTP-36`/`BODY-1`) stays 3b's; no ID moves. Three ways was considered twice
and rejected twice: a request-side/response-side pair, the only candidate offering real
independence, is crossed by four MUSTs (`HTTP-52`/`BODY-30` re-serving an error body as a
*replayable* body, `BODY-34`'s one shared preview size across both sides, `BODY-32`, and the shared
short-write/zero-read helper); a model-then-capture pair is coherent but strictly linear and buys no
merge, since a phase returns to `main` as one pull request. 3b at 49 IDs is the largest sub-phase the
expectations contain, and the mitigation is a stated constraint on 3b's plan — model before wrappers
— rather than a third document. Scope reconciles exactly: 42 + 49 = 91, the roadmap's 79 prefix IDs
plus 12 jointly numbered, verified mechanically against appendix C (`IO` 42 contiguous rows, `BODY`
37, `HTTP` 53, 645 total, no duplicate), with the `HTTP` family partitioning with no residue across
phases 1 and 3. **The roadmap's arithmetic is correct**; two spec-reading traps are recorded instead
— ch.06 §6.3's `HTTP-16-body` label is not a requirement ID (canonical `HTTP-16` is phase 1's header
insertion-order SHOULD), and `BODY-6`/`BODY-7` are two checklist rows although ch.06 states their
content inside `BODY-3`'s bullet. The gap-ID claim was checked and is half right: `IO-32`–`IO-35`
are the retired provider apparatus exactly as this document says, but **`IO-6` is a live MUST** —
ownership-on-wrap — that appears in no spec chapter and no design chapter, whose content §3.1 and the
corpus both attribute to the retired `SEAM-3`, and whose bridge half survives in ch.05 only under
`IO-16`, a SHOULD. The gap paragraph above now names appendix C as `IO-6`'s source (corrected
2026-09-13); 3a reads it from there. The body member's typing phase 1
postponed is **picked up by 3b** (it needs a body type to narrow `sig/` to, which 3a's duck type is
not), and the `NFR-4` narrowing is free because the lock diffs against a release tag that does not
exist. `BODY-12`/`BODY-36` stay postponed and gain what they lacked: `BODY-12`'s transport-dispatch
clause targets **phase 8** alongside `TRANSPORT-28`'s zero-copy clause (phase 8a later declined it,
its design's R5; `docs/first-release.md` § What v1 ships without, the `BODY-36`/`BODY-12` entry), its
body-side clause is 3b's to decide, and `BODY-36` gets an explicit pick-up condition — core's
dependency budget changing — in place of "no named trigger", because Ruby has no stdlib `mmap` and
both routes to one are barred by `SEAM-1`. No new deferral was filed: a segmentation design decides a
cut, not the interfaces whose absence a deferral records. Four facts verified on 3.2.11, 3.4.10 and
4.0.6 shaped the document rather than being noted after it. `IO#read(n, buf)` and
`StringIO#read(n, buf)` **overwrite** the destination buffer where `IO-1` requires a tail-append, so
3a's read primitive cannot delegate to Ruby's read-into form. `StringIO#read(n, buf)`'s encoding
behaviour **changed at exactly Ruby 3.4** — BINARY-forced on 3.2.11, destination-tag-preserving from
3.4 — the same floor-straddling shape as `URI::DEFAULT_PARSER`. Defining `Dexpace::IO` shadows
`::IO` for every file inside `module Dexpace`, and the dangerous case is silent: `x.is_a?(IO)` and
`IO === x` return **false** for a real `::IO` with no error, while phase 2's
`Dexpace/QualifiedCoreConstant` covers neither that constant nor any path phase 3 writes. And §7.1's
`Enumerator`-`ensure` asymmetry, verified there on 3.4.10 alone, holds on the floor and the ceiling
too, so the rule that resource acquisition and release never live inside an `Enumerator` block binds
phase 3 before it binds phase 7. **One knowledge note was filed** before the document was finished,
`docs/knowledge/notes/pagination.md` — a new file superseding `pagination/d626cf17` and widening
`pagination/731d9f17` with that last fact; the other three Ruby facts override no harvested rule and
so earned none. Ten risks are named for the sub-phase designs and none is decided
here; the Deviation Ledger is empty, since every mechanism substitution phase 3 relies on is already
catalogued in design §10 items 1, 2, 10, 11, 12 and 18.

**2026-09-08** — Phase 3a design filed, at
`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md`, the first
sub-phase design the segmentation rule has produced. Nothing is implemented; the plan and
the checklist are still to be written. Scope is the segmentation design's 42 `IO` IDs
unchanged — 34 implemented, eight 🚫 citing design §10.1 — plus the three things the
charter assigns 3a without a new ID: §10.2's canonical body **representation**,
`BufferedSource.over` with its no-ownership exception, and `MAX_MATERIALIZED_BYTES`.
**Three verified facts reshaped the design rather than being noted after it, and the first
is the largest.** `IO.copy_stream` — which is literally what
`Net::HTTP#send_request_with_body_stream` calls — drives a duck-typed source through
`readpartial(len, buf)`, or `read(len, buf)` when there is no `#readpartial`, with **one
buffer object reused across every call** and expected overwritten, on 3.2.11, 3.4.10 and
4.0.6 alike. `IO-1` requires the opposite, so `IO-1`'s primitive and `IO-16`'s host-native
bridge **cannot be the same Ruby method**: the primitive is `#read_into(dest, count:)` and
`#read`/`#readpartial`/`#getbyte`/`#each` keep Ruby's semantics, which is what makes design
§3.1's "`IO-16` is satisfied by construction" true rather than merely asserted (R2, R4).
Second, `IO.copy_stream` terminates cleanly on an `EOFError` **subclass** raised by a
duck-typed `#readpartial`, so `Dexpace::EndOfStreamError < ::EOFError` is load-bearing:
outside that family every streaming upload phase 8 performs would fail. Third,
`force_encoding` on a **frozen** `String` raises `FrozenError` even when the target encoding
is already the string's own, and a Rack-style body under `# frozen_string_literal: true`
yields frozen chunks — so the ingress retag is `String#b` and never `force_encoding`, and
every encoding test uses non-ASCII bytes because a BINARY string appended with an ASCII-only
UTF-8 one stays BINARY and passes under the bug. All four risks the segmentation design
assigned 3a are resolved: **R1** extends `Dexpace/QualifiedCoreConstant` with the constant
`IO` and a third watched namespace, the one-segment `Dexpace`, making the rule repository-wide
over every gem's `lib/` — `File`, `StringIO` and `Tempfile` are deliberately not added, under
a standing rule that a constant joins the list in the same change that creates its shadow —
and the mitigation that actually matters is that core never writes `is_a?(IO)` at all;
**R2** fixes `#read_into`'s four return values, its eager `IO-3` rejection and the fill hook
that normalises `readpartial`'s `EOFError` and `read`'s `nil` to `-1` at most once per stream;
**R3** states `IO-6`'s ownership rule once, citing `IO-6` and design §10.12 rather than the
retired `SEAM-3`, and names `.over`'s exception and the absence of any borrowing variant in
the same place; **R4** finds §3.1's "satisfied by construction" claim false as written and
true after the rename, and pins it with an end-to-end `IO.copy_stream` test rather than an
inference. R5–R10 are untouched and remain 3b's. The object model is
`Dexpace::IO::{Buffer, BufferedSource, BufferedSink, TeeSink, TypedReads, TypedWrites}` plus
`MAX_MATERIALIZED_BYTES`, two flat error classes `Dexpace::StreamError < ::IOError` and
`Dexpace::EndOfStreamError < ::EOFError`, and three RBS interfaces; `#peek` and `#slice`
return a `BufferedSource` rather than a new public type. **One change reaches back into a
phase-2 constant**: `Dexpace::Closeable#closed?` is changed to read the latch under the close
mutex, because `IO-38` is the first requirement that reads the flag from a second thread and
§3.1 declines to rely on the GVL "so the guarantee survives JRuby and TruffleRuby" — measured
at about 40 ns per call, paid once per public call and never per byte. Twelve deviations are
recorded as P3-1 through P3-12 with a Design §3 addendum carrying two entries. One item was
postponed — exercising `IO-38` on a Ruby without a GVL, now under `docs/first-release.md`
§ Post-release triggers, whose condition is an event rather than a phase because the matrix is CRuby-only and the GVL would hide a missing
lock on every row. **A finding now carried as a `docs/first-release.md` blocker — documenting the
`include Dexpace` constant shadow in `docs/sdk-documentation/` before publish**: phase 1's "verified
inert outside core" holds only for a *top-level* `include Dexpace`; a consumer's own
`class C; include Dexpace` puts `Dexpace` ahead of `Object` in the ancestry, so `x.is_a?(IO)`
is silently `false` there — a finding about every flat `Dexpace::` constant sharing a name
with a core class, not only about `Dexpace::IO`. Three knowledge notes were filed before the
document was finished — `io-and-byte-streams` (two `## Superseded` entries: the read split and
the frozen-chunk retag), `message-bodies` (`## Conflicts`: `IO-6` and not `SEAM-3` is the
ownership rule's home, the corpus half of the `IO-6` gap-pointer correction) and `resource-management` (`## Conflicts`:
the styleguide's per-call I/O timeout rules do not reach this layer, because `IO-40` forbids
it). A sixth audit group, **resource lifecycle and stream ownership**, was added to the
`knowledge-lookup` skill's table before it was run, per the first retrospective rule.

**2026-09-08** — Phase 3a plan filed, the same day as the phase-3 segmentation design and the 3a
design. `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts.md`. **Fifteen numbered TDD
tasks**, in build order: the cop extension; `Closeable#closed?` under the close mutex; the two error
classes; `Dexpace::IO` with the ceiling and the three RBS interfaces; `TypedReads` in five steps —
the `#read_into` primitive with the chunk store, the typed reads with the `IO-9` ceiling, the line
machine, the host-native bridge, the views; `BufferedSource`; `TypedWrites`; `Buffer`;
`BufferedSink`; `TeeSink`; and one deliberate closing task for the entry point, the two regenerated
artifacts and the checklist. Nothing is implemented; the checklist is written at execution time, per
execution step 6. Every `ruby` fence was extracted and run: **43 fences, on 3.2.11, 3.4.10 and 4.0.6,
203 runs / 819 assertions / 0 failures** (823 assertions on 4.0.6 for phase 2's Minitest-6 reason),
warning-free under `ruby -w` with `RUBYOPT=-W:deprecated`, identical across five seeds; the nine
`rbs` fences pass `rbs validate`; the cop's cases run **18 runs / 52 assertions / 0 failures** on
RuboCop 1.90.0, and the cop finds **0 offenses** over the eighteen files of the finished `lib/` tree.
The plan's own fences were then re-extracted from the filed document and the whole tree rebuilt from
them, which is how the five-fragment assembly of `typed_reads.rb` is known to reconstruct rather than
assumed to. **Task 2's guard was run red** against phase 2's unsynchronised `#closed?` on all three
interpreters — `ThreadError expected but nothing was raised` — because a one-line behaviour change
with no signature change is invisible to `gates:sig_diff`, so that assertion is the only thing
standing between P3-6 and a silent revert. The design's three open questions are answered in the
plan: the chunk store `shift`s a fully consumed chunk and never `byteslice`s a partially consumed
head one, so the fill path copies a chunk at most once and not at all when the upstream already
yields frozen BINARY chunks; `#each` yields whatever the upstream returned, because `.over` must
preserve the wrapped body's chunking for `BODY-17`; and the one allocating `IO-9` test runs on every
matrix row, measured at 0.0002–0.0006 s and under 20 MB peak RSS because the guard reads `#bytesize`
without touching the lazily mapped pages. **One deviation was added, `P3-13`** — `#read` and
`#readpartial` leave `outbuf` tagged `Encoding::BINARY`, because `::IO#read` preserves the
destination's tag while `StringIO#read` changed at exactly Ruby 3.4, so Ruby's own readers disagree
across this port's floor and only BINARY gives one answer on every row. **Nothing was postponed**,
and nothing earlier phases had postponed was picked up. **A cross-phase measurement was opened, now
3b's plan Task 13**: a
source retains every view derived from it until it closes and the deregistration is an `Array#delete`
— bounded everywhere 3a can see, and first non-obvious in phase 3b's per-attempt response-logging
drain. Planning also found the one way to ship the cop broken: `module Dexpace; module IO` is itself
a bare `IO` const inside `module Dexpace`, so without a definition-site guard the cop rejects
`lib/dexpace/io.rb`, the very file that creates the hazard — two accepted rows now pin it.

**2026-09-08** — Phase 3b design filed, at
`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`, the second and last
sub-phase design under the phase-3 segmentation. Scope is the charter's **49 IDs**: `BODY-1`–`BODY-11`,
`BODY-13`–`BODY-35`, `BODY-37`, `HTTP-36`–`HTTP-45`, `HTTP-51` and `HTTP-52`. It ships **twelve public
constants** — `Dexpace::Body`, a module that is simultaneously the production contract every body
includes, the one home `HTTP-38`'s factories need, and the type `sig/` narrows to; the seven request-body
variants `BytesBody`, `BufferBody`, `FileBody`, `StreamBody`, `ChunkedBody`, `FormBody` and
`MultipartBody`; `ResponseBody`; the two logging wrappers; and `TypedResponse` — plus three additions to
phase-1 types and the `+`-for-space form encoder phase 1 explicitly handed to phase 3. Constants are
**flat under `lib/dexpace/http/body/`** per P1-1: a `Dexpace::Body::` namespace was rejected rather than
merely not chosen, because its natural member names are `File`, `Buffer` and `Response`, three constants
the body code uses constantly, and the `include Dexpace` shadow finding (now a `docs/first-release.md` blocker) and P3-7 show that
shadowing is silent for `is_a?`.

The charter's six risks are all resolved. **R5**: three caps, not one — the 64 MiB ceiling stays a
constant with no keyword (a second ceiling is what boundary 8 pins), `BODY-30`'s 1 MiB is fixed by the
requirement, and only the logging preview size is a parameter, with its source postponed to phase 5
(the ceiling: 5a Task 13; the preview size and `BODY` gate: 5b Tasks 14–15).
**R6**: the twelve names, one ledger row. **R7**: `TypedResponse`'s handler is `#call(response)`, wide
enough that phase 7's status-aware handler drops *into* it rather than replacing it, and narrow enough
that a lambda is a test double. **R8**: the line against phase 4 is the argument type — `Body.buffer_bounded(body,
cap:)` and the one constant are phase 3b's, `Status#error?` is already phase 1's, and the step that reads
a *response* is phase 4's; `buffer_bounded` is deliberately status-blind so the body layer cannot get
`BODY-31` wrong. **R9**: `BODY-9`'s mark/reset is seekability, and it is implemented, not vacuous.
**R10**: `IO-42` governs surfaces — the captured buffer is exempt and survives the wrapper's close
(`BODY-28`), the over-cap tail is not and raises after it (`BODY-24`), and the wrapper's close does not
close the buffer.

**Three verified Ruby facts changed the document.** `String#encode` applied to the BINARY bytes the I/O
layer delivers replaces every byte at or above `0x80`, so design §3.1's decode recipe destroys every
non-ASCII payload; and the same call, having no target argument, follows the process-global
`Encoding.default_internal`. The boundary is retag-then-transcode with both encodings named — §3.1's decode
sentence is on phase 10's inbound list below, plus a corpus note. `respond_to?(:rewind)` is `true` for a pipe, a socket, a `StringIO` and a `File`
alike, so `BODY-9`'s antecedent is `pos` + `seek(pos)`, which raises `Errno::ESPIPE` on a pipe with
nothing consumed and is a genuine no-op on a seekable stream — and replay rewinds to the construction
position, not to byte 0. And §7.1's `Enumerator` rule reaches an **ordinary `#each` method**: driven
through `to_enum(:each)` and abandoned, its `ensure` does not run either, and `block_given?` is `true`
under that drive so no in-method guard helps — which is why `FileBody`'s residue is documented rather
than closed, on §10.10's precedent. Both findings earned corpus notes, superseding
`io-and-byte-streams/fbcb4d19` and `pagination/f57c50f6`; `harvested/` is untouched.

**Deviations `P3-14` through `P3-21`.** One item postponed: phase 5's configuration source for the
body-logging caps and the enablement predicate (5a Task 13; 5b Tasks 14–15). **The body typing phase 1
postponed is picked up** — `sig/` narrows `Request#body` and `Response#body` to `Dexpace::Body?` and
`HTTP-46` gets a cross-reference row, the treatment phase 2 gave `SEAM-29`. **The `BODY-12`/`BODY-36`
postponement is sharpened**, performing the two sharpenings the segmentation design stated and did not
perform: `BODY-12`'s first clause is discharged here through `::IO.copy_stream`, its second targets
phase 8 alongside `TRANSPORT-28`'s zero-copy clause, and `BODY-36` gets the explicit pick-up condition
it lacked. One cross-phase observation against 3a, routed to **3a's own plan, Task 14 — the
`#clear_tap` keep-or-drop decision** — rather than worked around: `TeeSink#clear_tap` was shipped for `BODY-18`, and 3b satisfies `BODY-18` by building a
fresh tee per write — which is strictly stronger, because `TeeSink` binds its primary at construction so
one tee cannot span two attempts — leaving the method public, `NFR-4`-locked and uncalled by core. 3a
stays as committed; the item names the window in which 3a's plan may drop the method without a break,
which is before either plan executes and before the first release tag.

**2026-09-08** — Phase 3b plan filed,
`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle.md`. Fourteen numbered tasks in build
order: the contract and `BytesBody`, then `BufferBody`, the form encoder, `StreamBody`,
`ChunkedBody`/`FormBody`, `FileBody`, `MultipartBody`, `ResponseBody` with the decode boundary,
`Body.buffer_bounded`, the two logging wrappers, `TypedResponse`, the view-retention measurement, and the
wiring that regenerates the surface snapshot and the RBS baseline once. Every `ruby` and `rbs` fence
was extracted, written to the file it names and run on **3.2.11, 3.4.10 and 4.0.6** over phase 3a's
own committed `lib/` fences: **266 runs, 767 assertions, 0 failures** (899 assertions on 4.0.6, for
phase 2's stated Minitest-6 counting reason), stable across five seeds, stderr empty on every row,
warning-free under `ruby -w` with `RUBYOPT=-W:deprecated`, and `rbs -I sig validate` exiting 0 on all
three. A tree rebuilt **from the filed document's own fences** reproduces every `lib/`, `sig/` and
`test/` file byte for byte and the same counts. A **fifty-mutation battery**, one edit per
requirement mechanism, was run and all fifty were caught; three were missed on the first pass and
each fixed a real weakness — a race-safe-rewind test that raced instead of overlapping, an `IO-42`
test that could not see the buffer being closed, and an `HTTP-45` test whose fibers never contended
for the lock.

The plan answers the design's five open questions: `MultipartBody#content_length` is lazy and
memoised (so the class is deliberately not frozen), `Body.string` encodes eagerly at construction,
the copy chunk size is whatever the source's own read returned with `FileBody` delegating to
`::IO.copy_stream`, task order is stated, and the view-retention measurement is Task 13, whose deliverable is
the number. That number: one view per `BODY-23` read, holding zero bytes, at 9 allocated objects (10 on
4.0.6), with quadratic deregistration that costs 0.005 s at 1 000 live views and 0.46–0.52 s at
10 000 — so the bound stops being obvious above roughly a thousand simultaneously-live unclosed
views, which nothing in `BODY-22`–`BODY-29` produces. The number stands recorded in that task, with phase 3a's
view registry unchanged, which is what the finding asked for.

**Two findings the design could not have had, both from running the code.** `Encoding.default_internal =`
emits a warning under `ruby -w`, so `DexpaceTestCase`'s `Warning.warn` override turns the design's own
mandated hostile-global decode test into a failure — both the set and the restore. The plan ships the
narrowest fix, `$VERBOSE = nil` around exactly those two assignments, plus a test asserting `-w` is
still live inside the block so the suppression cannot silently widen. And a second cross-phase
observation against 3a, routed to **3a's own plan, Task 10 — the `fill(count)` refill fix**: `BufferedSource.wrapping(io)` returns **one byte** per
`#read_into` and yields one-byte chunks from `#each` — 200 000 chunks for 200 000 bytes, ~0.21 s where
the in-memory paths are unmeasurable — because `#read_into` fills through a hard-coded
`ensure_buffered(1)` rather than the count the caller asked for. It is a throughput defect and not a
correctness one, so no gate catches it and 3a's suite stays green; the fix is one line in an
unexecuted plan, the window is the same one Task 14's `#clear_tap` decision names, and phase 3b is deliberately built so it costs nothing —
**no 3b test asserts a chunk granularity in either direction**. One deviation row added, **`P3-22`**,
for the per-variant accessors P3-14's constant list does not enumerate. Nothing new postponed: the
body-logging caps' configuration source stands as the design postponed it to phase 5, and the plan's
Task 14 records the `BODY-12` sharpening and the body-typing pick-up.

**2026-09-08** — Phase 4 segmentation design filed, at
`docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`, the second the segmentation rule has
produced. No sub-phase design or plan exists yet and nothing is implemented. **The cut is three ways,
on the specification's own §7 / §8.2 / §8.1 line — the letters the bullet above expects — and every
boundary is a CONVENIENCE, not a dependency.** The expectation is adopted; its stated reason is not,
and the bullet is corrected in place above. `CTX-<n>` is cited in no specification chapter outside
ch.07 and in no design section outside §5.4, §8.1, §11.11 and §12 — the one exception being a
`CTX-9` **comparison** in §5.2 that reads nothing from `CTX` and is what mis-files two
`error-handling` corpus entries under that ID. What `PIPE`'s steps thread state
through is their own per-call cursor (`PIPE-11`/`PIPE-13`/`PIPE-16`/`PIPE-17`, design §5.1's
cursor-scoped state), and `RECOV-10` has no cancellation or context clause while `RECOV-11`'s "current
context" is design §5.2's **ambient cancellation token**, phase 2's `Dexpace::Cancellation`. So nothing in
`RECOV` or `PIPE` consumes `CTX`, and each sub-phase design must state its independence in its own
Prerequisite section rather than inherit a chain by habit — the treatment this document already
prescribes for phase 7. The recommended order `4a → 4b → 4c` has three convenience reasons: `4a` is
smallest and carries the phase's one irreversible external handshake (cross-phase obligation 1's
`CTX-14`/`CTX-15` bundle shape); `4b` lands the error primitives the suppressed trail, `close_quietly`'s
first disposal route and `Hooks.notify`'s dropped failures all wait on, and the last changes behaviour
phase 2 shipped; `4c` is largest and benefits
from having real steps to install. Two other cuts were rejected: two ways (both pipeline layers in
one segment) on §8.3's prohibition and on 74 IDs being larger than any sub-phase the expectations
contain, and four ways (splitting `4c` into a sync runtime and an async mirror) on `PIPE-28`, which
requires one `Stages` module both runtimes flatten through — a boundary there would put at risk the
exact property `PIPE-28` exists to guarantee, and would be strictly linear besides.

**The scope finding is the document's largest, and it moves work rather than IDs.** Phase 4's
arithmetic reconciles exactly — verified mechanically against appendix C: `CTX` 20 contiguous rows,
`RECOV` 34, `PIPE` 40, 645 total, no duplicate, 20 + 34 + 40 = 94, level split 82 MUST / 10 SHOULD /
2 MAY — but **sixteen `RECOV` IDs are the recovery-stack retry engine and not recovery-chain
machinery**. `RECOV-17`–`RECOV-31` and `RECOV-34` each have a `RETRY` twin whose Ruby mapping is
written in design §6.1 (a phase-6 chapter), design §12's own `RECOV` row places `RECOV-34` there, and
`docs/sdk-design-ruby/` cites `RECOV-17` through `RECOV-30` nowhere at all. Two of them make the
disposition **forced rather than preferred**: `RECOV-27`'s cancellable, non-pinning inter-attempt
wait is §8.3's `Clock#sleep(duration, cancellation:)` behind `CFG-15`'s injectable time seam, which
is phase 5's and which phase 2 deliberately kept off the pivot (the `deadline:` keyword, 5a Task 8) — a phase-4 hand-roll is
technically reachable (`Thread::Queue#pop(timeout:)` is on the 3.2 floor) but would fix `CFG-15`'s
shape a phase early, which is exactly what phase 2 declined to do, and the shortcut a plain
`Kernel#sleep` would be is ruled out by `RECOV-27`'s own "not a plain sleep" and by `RETRY-26`'s
"non-conforming" — and `RETRY-13` forbids the two stacks
carrying independent backoff formulas, which is exactly what building the recovery half two phases
early would produce. Handed to **phase 6** — **fifteen** of them, landing in 6a's Tasks 3, 4, 5, 7 and
11 (`docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry.md`); the sixteenth, `RECOV-31`, was already declined for v1 and stays post-MVP
(`docs/first-release.md` § What v1 ships without). Nothing in this document's cells changes:
phase 4 still owns all 94 checklist rows and builds 76 outright, carrying 18 as ⏳ under the legend
cross-cutting constraint 3 already defines — one of the eighteen, `PIPE-33`, met in part rather than
not at all. Cross-phase obligation 3 reads as confirmation once its words are taken at face
value — the *substrates* are phase 4's, the *stacks* are phase 6's. **The consequence lands on phase
6, and it is stated in three places so its segmentation design does not have to count.** Phase 6 was
already the largest at 111 prefix IDs (`RETRY` 45, `REDIR` 28, `AUTH` 38); the hand-off adds the *work*
of fifteen more on top of that 111, so **phase 6's segmentation design budgets for 111 + 15, not
111** — `RECOV-31`, the cluster's sixteenth, is declined for v1 and is not phase-6 work. No
requirement ID moves — the fifteen keep their phase-4 rows as ⏳ and phase 6 carries its own rows or
cross-references, the two-rows-one-obligation treatment phase 2 gave `SEAM-29`. The
phase-6 segmentation bullet above is corrected in place accordingly; the **phase-6 row itself is
unchanged and correct**, because its three prefix ranges still sum to 111. The segmentation design
carries the twin-by-twin `RECOV`→`RETRY` mapping in full so phase 6 re-derives nothing.

**The gap-ID claim was checked and is right about the IDs and wrong about where to read them.**
`--gaps CTX,RECOV,PIPE` reports 20/20 `CTX` and 40/40 `PIPE` substantive with **zero roll-up-only
entries in any of the three prefixes** — so the appendix-B roll-up hazard does not fire for phase 4
at all — and exactly the fifteen uncited `RECOV-17`–`RECOV-31` this document's paragraph above names (a
different fifteen from the ones handed to phase 6: that set drops `RECOV-31` and adds `RECOV-34`).
But §8.2 states `RECOV-1` through `RECOV-16` and stops: verified by repository-wide grep,
**`RECOV-17` through `RECOV-34` appear nowhere in `docs/product-spec/` outside appendix C** —
eighteen IDs, not fifteen, and three of them (`RECOV-32`, `RECOV-33`, `RECOV-34`) escape `--gaps`
only because the *design* names them. **The third and largest instance of the same unfollowable gap
pointer** — the five `SEAM` IDs and `IO-6` are the other two, and all three are corrected in this
document's gap paragraph above; at three occurrences across three prefixes it is a property of
appendix C's relationship to the prose chapters rather than three omissions. The budget is also not
what the paragraph implies: fourteen of the fifteen uncited IDs move to phase 6 with the hand-off and
the fifteenth, `RECOV-31`, is declined for v1, so the *reading for implementation* leaves
phase 4 either way and what phase 4 owes is one disposition pass over eighteen appendix-C rows,
which this document performed.

**`PIPE-33` is phase 4's, and §10.5's trade is not re-opened.** Four of its five normative clauses
are met and phase 2 built most of the machinery: no default executor exists to fall into (core ships
the executor as a `#post`-shaped duck type), a built pipeline *is* a transport (`PIPE-26`) so
`Transport.async_over` runs it as one opaque unit, options are threaded, and cancel-without-interrupt
completes as cancelled. The interrupt clause is not met, for §8.3's reason, and `4c`'s row is ⏳
citing §10.5 (and `docs/first-release.md` § What v1 ships without › Unsatisfied MUSTs) with the four met clauses named. Phase 8's disposition of the same ID is a
re-assertion at the point the antecedent becomes real — `dexpace-async-thread` is what creates a
worker to fail to interrupt — not a second decision, the same two-rows-one-obligation treatment phase
2 gave `SEAM-29`. Phase 2's design also records a **binding obligation** honoured here: phase 4 wraps
a `Dexpace::Pipeline` with phase 2's two `SEAM-18` bridges and builds no second pair.

**Three facts verified on 3.2.11, 3.4.10 and 4.0.6 shaped the document, and two changed a decision.**
A `#full_message` override — which design §5.2 specifies for the suppressed trail — is **invisible to
Ruby's default uncaught-exception printer** on all three; `#detailed_message` reaches it, exists on
the 3.2 floor, and is what Ruby's own `#full_message` calls, so overriding `detailed_message` alone
satisfies **both** paths while `full_message` alone reaches only an explicit `#full_message` call and
misses the report a reader of a crashed process actually sees. That is the suppressed trail's content — phase 4b, Task 1. And the
`#cause` cycle `XCUT-9` guards against is **not reachable the way design §5.2 says it is**:
`raise y, cause: x` on an already-linked pair raises `ArgumentError: circular causes`,
`raise s, cause: s` leaves the cause `nil`, and `Exception#exception` returns a new object with a nil
cause — the cycle is reachable only through a caller-defined `#cause` override, which is exactly the
shape core cannot control, so the guard stays necessary and only the test that proves it changes. A
phase-4 implementer testing the stated route would get an `ArgumentError` and could reasonably drop
the guard. Third, `Fiber[:key]`'s inheritance holds across the whole supported range and is
**copy-on-write**, and it is the carrier for `OBS`/`ASYNC` diagnostic context and **not** for `CTX`,
whose store `CTX-7`/`CTX-11`/`CTX-19` require to be bounded and strongly reachable. Also recorded
without changing a decision: `ObjectSpace::WeakKeyMap` is undefined on 3.2.11 (`CTX-19`'s lint);
`NoMatchingPatternError` is inside `StandardError` while `LoadError` and `NotImplementedError` are
outside it, which sets `RECOV-2`'s conversion boundary; and a value-equality delete over the context
store evicts a structurally identical live sibling, reproducing `CTX-9`'s trap in one line.

**Three knowledge notes were filed before the document was finished** — two under
`docs/knowledge/notes/error-handling.md` (`## Superseded`: `error-handling/34f54b5e`'s
`#full_message` mechanism, and `error-handling/11c6f36c`'s cause-cycle route) and one new file,
`docs/knowledge/notes/observability.md` (`## Superseded`: widening `observability/e0f1e864` across
the range and drawing the fiber-storage-versus-`CTX` line). All three print
`[overridden by notes/…]`; `harvested/` is untouched. A **new audit group** was added to the
`knowledge-lookup` skill's table before it was run, per the first retrospective rule: **Pipeline
composition and execution context**. Fourteen risks are named for the sub-phase designs and none is
decided here; the Deviation Ledger is empty, since every mechanism substitution phase 4 relies on is
already catalogued in design §10 items 5, 6, 15, 17 and 18. One further citation slip was found and
**fixed in the same change**: `CLAUDE.md`'s constraints list cited design "§8.2" for `Fiber[:key]`
versus `Thread.current[:key]` and the passage is in §8.1, so the section number is corrected and
nothing else in that sentence is touched. A wrong section pointer in the working contract sends every
later phase to the wrong page, which is the same class of unfollowable pointer the gap paragraph's `IO-6`
and `RECOV-17`–`RECOV-34` corrections record.

**The document's adversarial review, same day, confirmed the three central claims and corrected the
counts they were stated with.** The `RECOV`→`RETRY` twin mapping was re-derived ID by ID against
appendix C and holds; the `CTX`-independence result holds, with the one exception now stated (a
`CTX-9` comparison in design §5.2 that reads nothing from `CTX`); the eighteen appendix-C-only `RECOV` rows and their
unfollowable pointer were re-verified by grep. Corrected: the hand-off to phase 6 is **fifteen** IDs and not
sixteen, so phase 6 budgets **111 + 15**; `PIPE-33` has **five** normative clauses of which four are
met, not four of which three are; phase 4 carries **18** ⏳ rows, not 17; and
`Dexpace/NoThreadInterrupt` is a **phase-0** cop, not phase 2's. The same off-by-one was corrected
everywhere the hand-off's cost was stated, so every place a phase-6 planner can enter from now says
111 + 15 and name `RECOV-31` as the excluded sixteenth. One
new corpus note under `docs/knowledge/notes/observability.md`, the one that sends a writer to per-key
writes: **`Fiber#storage=` — the write side of the carrier design §8.1 fixes for
`ASYNC-9`/`ASYNC-11` — warns on every call on all three interpreters at the default warning level,
against a gate set that fails on warnings, and `= nil` reads back `{}` on 3.2.11 and `nil` on the
other two.** Nothing in `CTX`, `RECOV` or `PIPE` touches fiber storage, so it is phases 5 and 8 that
will meet it.

**2026-09-08** — **Phase 4a's design filed**, `docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-design.md`,
the first sub-phase document under phase 4 and the third sub-phase design overall, after `3a`'s and
`3b`'s. Twenty `CTX` IDs, all implemented, none deferred and none carried as ⏳ — the only sub-phase so far whose whole scope ships. It
resolves the charter's `R1`–`R4` and leaves `R5`–`R14` to `4b` and `4c` untouched. **The phase's one
irreversible external handshake is now signed**: cross-phase obligation 1's instrumentation bundle is
`Dexpace::Instrumentation::Bundle`, a frozen `Data` with **eight** members exposing `CTX-14`'s ninth —
validity — as a derived `#valid?`, because `OBS-26` makes an all-zero identifier invalid by MUST and a
stored flag would let a bundle contradict its own identifiers. Beside it ship `Bundle::NONE`,
`TraceIdFlavour` with `NONE`/`W3C`/`DATADOG`, and the two frozen no-op singletons `NO_SPAN` and
`NO_TRACER_FACTORY`, the latter carrying the one method `CTX-20`'s embedded MUST forces. The no-op span and
tracer protocols are postponed to 5c, Tasks 3, 4 and 5
(`docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics.md`), with 4a's design recording the
five-clause contract phase 5 implements against and the six things it may not redo. The configuration source
for the store's cap is postponed to 5a, Task 13, `MAX_TRACKED_CONTEXTS = 1024` — `AUTH-19`'s number, because §5.4
requires one shared bounded-map implementation and two default bounds would make that claim two-valued.

Four decisions were forced by facts run on 3.2.11, 3.4.10 and 4.0.6 rather than by taste, and two of them
became corpus notes under the new `docs/knowledge/notes/execution-context.md`. **A frozen `Data` cannot carry
a close latch** — the ivar write raises `FrozenError` — so a context is not a `Dexpace::Closeable`, and it
needs no latch, because `CTX-9`'s identity-conditional eviction is already idempotent. **The cap-draining
loop is degenerate under one mutex** — and the proof is structural rather than measured: insert and drain
share one `synchronize`, so exactly one key arrives per critical section and the loop body can run at most
once. `CTX-12`'s stated convergence rationale is vacuous here. The note records the argument *and* the
count that fails to support it — 8000 inserts at cap 64 giving 7936 iterations is `inserts − final size`,
reproduced identically by a split-lock drain and by a bare `if` — because the inverse inference would
remove the lock, and a reader who trusted the count would have nothing to stop them.
**A `private_constant` on `Dexpace` is bare-name reachable from every full-nesting descendant and from
nothing else, per file and not per gem**, which is what makes `Dexpace::BoundedMap` shareable with phase 6's
`AUTH-19` and phase 9's `XCUT-14` without a public constant, conditional on
`module-organization/64e84d64`'s full nesting form — and which is why `NO_SPAN` and `NO_TRACER_FACTORY` are
public for the reference *form* a conformance assertion writes, never because they cross a gem boundary.
And **`ObjectSpace::WeakKeyMap.new` parses on 3.2.11 where the constant is undefined**, which is why
`CTX-19`'s prohibition becomes a seventh custom cop, `Dexpace/NoWeakReferences`, whose test table is a table
of source strings and needs no version guard; its behavioural counterpart discriminates a strong `Hash`
(1000 of 1000 registered contexts after three `GC.start`s) from an `ObjectSpace::WeakMap` (0 of 1000) and
deliberately not from an `ObjectSpace::WeakKeyMap`, which holds values strongly and so keeps every entry
alive — that spelling is the cop's to catch, and the two halves are scoped accordingly.

Eleven deviations are filed, `P4-1` through `P4-11`, opening phase 4's ledger. The one a later phase is most
likely to trip on is `P4-1`: the three context flavours are **flat** — `Dexpace::DispatchContext`,
`RequestContext`, `ExchangeContext` — and §5.4's "three distinct `Data` classes sharing a module" is read as
a module they *include*, because `Dexpace::Context::Request` would shadow phase 1's `Dexpace::Request` for
every file inside that namespace and `Dexpace/QualifiedCoreConstant` cannot express the fix. Two new tooling
findings. **A `scripts/knowledge.rb` fix, separating `[cited by …]` from `[overridden by …]`**, from the
design's review: the corpus CLI has one relation and derives it from any backtick, so `[overridden by notes/…]` now prints against `api-design/b0e18938` and
`module-organization/64e84d64` — two rules phase 4a's note *rests on* — and against three
`concurrency-and-async` rules a committed note says in words that it does not weaken; 77 of 2 166 harvested
entries carry the marker. And **a correction to the phase-4 charter's own exclusions row**: "the monotonic counter" names `CTX-4`'s
call-sequence counter and `CFG-16`'s elapsed-time counter, and the phase-4 segmentation design's own
exclusions table assigned the phrase to phase 5 — true of `CFG-16` and misleading about `CTX-4`, which is
phase 4a's to build. The row now reads "elapsed-time counter (`CFG-16`)", corrected 2026-09-13; 4a filed it
rather than fixing it at the time, because the charter was committed. **4a confirms the charter's independence result from the inside**: `--phase 2` and
`--phase 3` cite 70 and 152 distinct requirement IDs between them and **not one `CTX` ID**, and `4b` and
`4c` are obliged to consume nothing 4a ships.

**2026-09-08** — Phase 4b design filed, the third phase-4 document.
`docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`, with its plan and
checklist still to be written. Scope is the charter's: `RECOV-1`–`RECOV-16` plus `RECOV-32`/`RECOV-33`
built, fifteen ⏳ rows pointing at 6a and one (`RECOV-31`) at `docs/first-release.md`. **No backoff calculator, no
pacing-header parser and no wait of any kind**, cancellable or otherwise — `RETRY-13` forbids the
first and `CFG-15` owns the third, and the ⏳ rows are rows rather than work.

Five decisions were forced by facts run on 3.2.11, 3.4.10 and 4.0.6 rather than argued. **The
suppressed trail cannot live on `Dexpace::Error`**, because every primary `RECOV-12`, `close_quietly` and
`Hooks.notify` hand it is a *caller's* exception and a method defined only on the SDK's root raises
`NoMethodError` on the first one — so the trail is `Dexpace::Suppressible`, a separate module the root
includes and `Dexpace.attach_suppressed` `extend`s onto anything else. It has to be separate because
`rescue M` matches a module reached through a singleton class (verified), so extending a third-party
`IOError` with the rescue root would make `rescue Dexpace::Error` catch errors the SDK never raised.
A `#detailed_message` override reaches the default uncaught-exception printer through `extend` exactly
as through inclusion, and `super` preserves `did_you_mean`. **`RECOV-10`'s "rethrow UNCHANGED" is
broken by the obvious Ruby spelling**: `raise error` assigns `$!` as that error's `#cause`, and `$!` is
thread-scoped, so it is non-`nil` inside a method called from a *caller's* `rescue` — ordinary consumer
code, needing no `rescue` anywhere in core. Every unwrap is `raise error, cause: nil`, which suppresses
the assignment and does not clear a legitimate pre-existing cause. **`XCUT-9`'s visited set is
`{}.compare_by_identity` and not a `Set`**: `Exception#==` is structural by Ruby's own definition, so an
`Array`-tracked walk truncates a two-node chain to one entry, and a `Set` is right only until a
caller-supplied error class overrides `hash`/`eql?` — measured, `Set[a].include?(b)` is `true` there.
Core's errors are not `Data`, so the reason the corpus gave for that rule was false about this codebase
while the rule itself was load-bearing. The **fixture** that shows the truncation is part of the
finding: the pair must be two *never-raised* errors chained through a `#cause` override, because a
`raise`-built pair is not `==` on 3.2.11 — 3.2's backtrace carries a `rescue in <method>` frame the
parent's lacks — so a test built the obvious way passes on the matrix's floor against the very bug it
exists to catch. **`RECOV-11` has nothing to do**: phase 2's cancellation is
idempotent and latched with no clearable flag, so converting a `CancelledError` to a `Failure` cannot
swallow the signal, and the requirement's own words are "a port preserves whatever its cancellation
primitive is" — asserted on the token in a test rather than implemented as a wrapper. And **the
exhaustiveness `else` arm joins `RECOV-2`'s fatal-family passthrough** rather than becoming a `Failure`,
because `NoMatchingPatternError` is inside `StandardError` and converting a core defect into an outcome
a recovery step may swallow is the demotion `error-handling/3bfdf6f0` forbids.

Fourteen deviations are filed, `P4-12` through `P4-25`. The one a later phase is most likely to trip on
is `P4-20`: `Dexpace::ProtocolError` is **one class carrying `#status`** with no per-status subclass
tree, because `XCUT-4` names exactly two top-level branches and `XCUT-7` decides retry eligibility from
a configured status set and never from a class — a generated SDK that wants its own typed errors passes
`factory:` to the error-mapping step instead. One item postponed, to 6a Task 6 (`ProtocolError#retryable?`):
that class ships without
`XCUT-5`'s baked retryability flag, because the flag's "SINGLE shared status classifier" is `RETRY-1`'s
and phase 6's, and adding a method later widens. No new findings. Three corpus notes were filed
before the design was finished — two under `docs/knowledge/notes/error-handling.md` and a new
`docs/knowledge/notes/pipeline.md`.

**The suppressed trail and `Hooks.notify`'s dropped failures — postponed to this phase by phase 1 and
phase 2 — are discharged by this design, and `close_quietly`'s first disposal route is supplied** (4b's
Tasks 1 and 2). The `Hooks.notify` finding is worth recording here because it is a negative: **none of phase 2's three `Hooks.notify` tests changes its assertions.**
Each raises from exactly one handler, so the suppressed trail is empty and the behaviour is identical
before and after; what attaching the dropped failures actually costs is a **fourth** test at the
`Cancellation::Source#cancel` site with two raising handlers — the only case that distinguishes the two
behaviours — five prose statements in committed phase-2 documents that become false (three about the
dropped failures, two naming `Dexpace::Error#suppressed` as the carrier, which P4-12 disproves for
this call site), and one line of code the row does not mention: `Hooks.notify`'s trailing
`raise failure` becomes `raise failure, cause: nil`, because it re-raises an error it has been
carrying rather than one it just rescued, which is the scope the `pipeline` note claims. Its effect
is narrow and is stated narrowly — `cause: nil` suppresses an assignment the re-raise would make and
cannot undo one a hook's own `raise` already made — and the same measurement fixes the `RECOV-10`
test's fixture: the `Failure` must carry a **constructed** error, never a raised one, or
`assert_nil error.cause` fails against the correct implementation. **4b confirms
the charter's independence result from its own side**: it consumes nothing 4a ships, and the single
thing crossing the 4b/4c line is a contract rather than an ordering — the three shipped steps are one
`#apply(value)` transform each with a `#phase` of `:request` or `:response`, plus one default
`#call(value)` that forwards to `#apply` so a transform is a recovery-chain step with no adapter at
all, and 4c writes **one** generic adapter that reads `#phase` rather than a second implementation of
any transform. The charter's statement of the third shape is corrected in passing: the error-mapping
step is `response -> response` and raises, not `response -> outcome` — `RECOV-4`'s "(response→response)"
and `RECOV-15`'s "the status→typed-exception mapping **response step**" both say so, and it is what
lets a two-phase contract span every shape and keeps `Outcome` out of the `PIPE` layer entirely.

**2026-09-08** — Phase 4c design filed, the fourth and last phase-4 document.
`docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`, with its plan and checklist
still to be written. Scope is the charter's 40 `PIPE` IDs with **one row moved**: `PIPE-39` goes from ✅
to ⏳ against a new postponement — `Pipeline.standard`, built by phase 6 as 6b Task 13a — because R14's
resolution ships one of that requirement's two named constructors and defers the other. Thirty-seven
ship, three carry ⏳ — `PIPE-33` (§10.5, four of five clauses met), `PIPE-36` (declined for v1,
`docs/first-release.md` § What v1 ships without) and `PIPE-39` (6b Task 13a).

**Three decisions shape everything else in the document.** **4c ships no bridge**: a built pipeline is a
transport (`PIPE-26`), so `PIPE-33` and `PIPE-34` are phase 2's `Transport.async_over` and
`AsyncTransport.sync_over` composed with a pipeline, and the phase adds no wrapper, no wait and no
signature — which is the strongest available form of the charter's "no deadline-less unconditional
block" constraint and adds no second postponement beside the `deadline:` keyword's (P4-35). **Cursor-scoped state is keyed by
`(stage, key)` rather than by key alone**, and its only write is an argument to `#fork`: under a flat
namespace a `RETRY` pillar step sits between REDIRECT and AUTH, may fork, and could write the very key
AUTH reads — so §6.2's own sentence, "no step downstream of AUTH can [set the marker] either", and
§10.15's "structurally impossible rather than defended against" would be true of non-pillar steps only.
Namespacing by the writing step's stage, chosen by the runtime from the frozen entry table, makes both
literally true, and the five tests R11 demands assert the **negative** (P4-28, P4-29). And **the
standard-resilience preset ships as a mechanism with no step set**: `PIPE-24`'s all-or-nothing
installation is a general `Builder#install_preset`, real and tested against probe steps today, while the
redirect/retry/instrumentation set it would install defers to phase 6 (P4-34; 6b Task 13a).

**One fact was floor-only and changed a decision.** The cursor's single-use latch is an unsynchronised
instance variable, because a cursor is created per step invocation and never published. Measured: eight
threads through that latch let more than one caller past on **29 of 2000 runs on 3.2.11 and 0 of 2000 on
3.4.10 and 4.0.6**. So `PIPE-15`'s "reusing the handle MUST be treated as a defect" is honoured and the
detection is sequential-only — stated in the YARD as P4-33 — and **4c ships no test asserting the race**,
because at 29 in 2000 — 1.5 % — the single-shot form of that test is a flake on the floor as well, and only its
2000-run aggregate form is green there and red on the other three columns. Two other
facts license the object model: `Data` responds to `<=>` through `Kernel#<=>`, so `sort_by(&:stage)`
raises `ArgumentError` at the first two-stage pipeline and nothing sorts a stage at run time; and every
lambda's class is `Proc`, which is what 4c's plan Task 7 — the anchor name for lambda steps — rests on.

Fourteen deviations are filed, `P4-26` through `P4-39`. One item postponed — `Pipeline.standard` with
`redirect: :unsupported`, to phase 6 (6b Task 13a). Two findings,
both conjunction failures rather than the three unresolvable pointers this document's gap paragraph records.
**4c's own plan, Task 7 — an anchor name for lambda steps**: `PIPE-18`–`PIPE-21`'s surgical edits are keyed
by step type and every lambda step shares one type, so a pipeline holding two lambdas cannot address either
surgically. **Phase 2's plan, Task 11 — an `async_over` return-type check**, filed by the
design's review — the two transport seams share one `#parameters` predicate, so
`Transport.async_over(async_pipeline, executor:)` is accepted and silently yields a future of a future
with the inner response never closed, while `AsyncTransport.sync_over(sync_pipeline)` raises at the
first send; every object involved is phase 2's, and phase 4c neither introduces nor widens it, but
`Pipeline` and `AsyncPipeline` are what make it cheap to hit. One corpus note, under
`docs/knowledge/notes/pipeline.md`; `harvested/` untouched.

**2026-09-08** — Phase 4a plan filed,
`docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context.md`. **Nine numbered TDD tasks**,
in build order: `Dexpace::ContextConflictError`; `Dexpace::Context` and the `FakeContext` test
double; `Dexpace::BoundedMap` (private) and `Dexpace::ContextStore`; `Dexpace::Instrumentation::TraceIdFlavour`;
the two no-op singletons, `NO_SPAN` and `NO_TRACER`/`NO_TRACER_FACTORY`; `Dexpace::Instrumentation::Bundle`;
`Dexpace::CallKey` (private) and the promotion chain — `DispatchContext`, `RequestContext`,
`ExchangeContext` — with `CTX-9`'s trap added to the store's suite once a real `Data` context
exists to build it from; the seventh cop, `Dexpace/NoWeakReferences`; and one closing task for the
entry point, the two regenerated artifacts and the checklist. Nothing is implemented; the checklist
is written at execution time, per execution step 6. All twenty `CTX` IDs are covered.

The design's four open questions are all resolved, one against a fetched artefact rather than by
inference: **`#tracer`'s arity** does not match the design's own speculative recommendation —
`opentelemetry-api` 1.11.0's actual `TracerProvider#tracer`, read from the gem fetched from
rubygems.org during planning, is `(deprecated_name = nil, deprecated_version = nil, name: nil,
version: nil, attributes: nil)`, and the plan ships that shape rather than the two-positional-
argument guess, per the design's own "the gem's wins" rule. **`BoundedMap` needs no RBS**, confirmed
by running `rbs -I sig validate` against the whole sig tree this phase adds plus phase 1/2
stand-ins, clean. **The `CTX-19` reachability test runs on every matrix row**, at a measured cost of
noise (0.03 s of a 0.035 s suite). **`FakeContext` is required explicitly**, from the two suites
that use it, never from `test_helper.rb`.

Every `ruby` fence was extracted to a scratch tree outside the repository and run: **67 runs / 327
assertions / 0 failures** on 3.2.11 and 3.4.10, **345 assertions on 4.0.6** (Ruby 4.0.6's bundled
Minitest 6.0.0 counts some composite assertions more granularly than 5.25.x, the same shape phase
3a recorded), identical across five seeds, warning-free under `ruby -w` with
`RUBYOPT=-W:deprecated`; the seventh cop's own suite — 17 runs / 50 assertions / 0 failures — ran
against RuboCop 1.90.0 on the one interpreter with the gem installed, which is sufficient because
`CopCase` pins the parse target rather than following the host interpreter. Two facts were
re-verified directly rather than only cited from the design: a method on a frozen `Data` subclass
writing an ivar raises `FrozenError` on all three, and `ObjectSpace::WeakKeyMap` is undefined on
3.2.11 and defined on 3.4.10/4.0.6.

**One finding surfaced while deriving Task 9's own expected runtime-surface-snapshot content, and
it is routed to phase 0's plan, Task 14 — the `Data`-reader snapshot decision — rather than silently
corrected.** Loading this phase's classes and calling
phase 0's own walker method (`mod.public_instance_methods(false)`) directly shows that a
`Data`-generated reader — `DispatchContext#bundle`, `Bundle#trace_id`, and every one like them, in
every gem, since phase 1 — never appears in a regenerated runtime surface snapshot: the reader is
defined on the anonymous class `Data.define` returns, which is the named subclass's `superclass`,
and `public_instance_methods(false)` does not look there. This holds on all three interpreters and
contradicts `P4-11`'s and `CLAUDE.md`'s own stated reason for pairing the runtime snapshot with the
RBS diff ("each catches what the other cannot see") — the runtime half catches nothing for a
`Data`-generated reader specifically, and always has not, since phase 1's first regeneration. Not
fixed here: `tools/surface.rb` is phase 0's and every gem is affected identically. A second pair of findings
was filed by the plan's review, and each now has its own owner. The design's second discriminating drain
measurement — "the maximum size ever observed" — is not reachable through `ContextStore`'s public surface
(`#size` takes the same mutex as the insert, so a split-lock `BoundedMap` sampled by four
concurrent readers across 64 000 inserts never reports above the cap), so `CTX-7`'s and `CTX-8`'s drain
proof rides on the non-CRuby row under `docs/first-release.md` § Post-release triggers, beside `IO-38`'s.
And `Metrics/ParameterLists:
4` is unsatisfiable for a keywords-everywhere API, which seven methods in this phase demonstrate —
the measured count phase 0's plan Task 3 now carries into its reviewed `.rubocop.yml` baseline.
No deviation was filed and nothing postponed; nothing earlier phases had postponed was picked up here.

**2026-09-09** — **Catch-up entry, written 2026-09-12.** Phase 4b plan filed,
`docs/work/mvp/phase4/phase4b/2026-09-09-phase4b-recovery-primitives.md`. **Fifteen numbered TDD tasks**
in strict dependency order: `Suppressible` and the error root; the phase-2 error-trail integration that
attaches `Hooks.notify`'s dropped failures and supplies `close_quietly`'s first disposal route; the cycle-safe `Dexpace.each_cause`
with its cyclic fixtures; `OutcomeError`; `ProtocolError`; `Outcome` with `Success` and `Failure`;
`Recovery` and `buffer_error_body`; the `Transform` contract; the idempotency-key, client-identity and
error-mapping steps; `RequestChain`; `Ownership` (private) and `ResponseChain`; the `Orchestrator`; and
one closing task for the wiring, the two regenerated artifacts, the checklist and the status note that
says phase 1's and phase 2's postponed work has landed. All 34 `RECOV` IDs are accounted for — 18
implemented, 15 ⏳ handed to 6a, one (`RECOV-31`) declined for v1 — and
every ledger row `P4-12`–`P4-25` lands in a named task. The design's five open questions are resolved
in the front matter and carried through the tasks: `Ownership` gets its own file, so "the asymmetry
lives in one place" is verifiable by opening one; `ErrorMappingStep`'s default `factory:` is a frozen
private lambda rather than a `Method` allocated per `.build`; `Dexpace.each_cause` **stops** at a
raising `#cause` rather than propagating, because a classification walk must never be the thing that
crashes an application inspecting an ill-behaved third-party exception, with a fourth fixture class
asserting it; the fourth `Hooks.notify` test goes at **one** site, `Cancellation::Source#cancel`,
since all three sites delegate to the same private helper; and `ProtocolError`'s message carries **no
body preview**, because redaction is phase 5's and an exception message is the likeliest thing to be
logged. No new deviation, no new deferral and no new finding.

**2026-09-09** — **Catch-up entry, written 2026-09-12.** Phase 4c plan filed,
`docs/work/mvp/phase4/phase4c/2026-09-09-phase4c-stage-pipeline.md`, closing phase 4. **Eleven numbered
tasks**: `PipelineError`; `Stage` and `Stages`; the pipeline test doubles; the `Step` protocol and its
conformance predicate; the `Entry` model; `Cursor` with `SyncDriver` and `AsyncDriver`; `Builder`; the
sync runtime; `TransformStep` as the one generic 4b adapter; the async runtime and `map_response`; and
one closing wiring task. All 40 `PIPE` IDs are accounted for in a per-ID table naming the owning task
and its evidence, with `PIPE-33`, `PIPE-36` and `PIPE-39` ⏳ against §10.5, the v1 declines in
`docs/first-release.md`, and 6b Task 13a respectively.
Both of the design's open questions are resolved, and the first found a gap in the design's own count:
the nine `PipelineError` message forms `P4-37` enumerates are **eleven**, because `R10`'s precedence
table rejects two further install-time cases (a step declaring `#stage` installed with a different
`stage:`, and a step declaring neither) that no `PIPE` ID forces and that therefore cite `R10` rather
than a requirement — the shape claim is unaffected, only the count read low, so no new deviation was
filed. Every message form is asserted **at the site that raises it**, never against a hand-constructed
error. `Stages::ALL` and `::PILLARS` are merely frozen and not `Ractor.make_shareable`d, because a
response holds a body holding an `IO` and 4c makes no shareability claim for anything in the pipeline.

**2026-09-09** — **Catch-up entry, written 2026-09-12.** Phase 5 segmentation design filed, at
`docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`, the third the segmentation rule has
produced. **The cut is three ways, not the roadmap's two** — `5a` configuration and the clock (38 IDs),
`5b` the logging facade and redaction (27 as the charter counted them), `5c` tracing and metrics (13) —
**and every boundary is a CONVENIENCE**, which corrects the roadmap's phase-5 bullet twice over: its
`OBS-35` dependency argument rests on a SHOULD, and the `CFG`↔`OBS` edges run both ways, since
`CFG-24`/`CFG-25` require a **warning log** on invalid proxy configuration and `CFG-21`'s best-effort
close is `close_quietly`'s second disposal route, both of which need §8.1's facade. The second boundary falls
inside chapter 15 at the §15.4/§15.5 line; the sentinels `OBS-25`–`OBS-27` are populated in `5c`, not
`5b`, against the bullet's expectation. The phase-5 row's ranges and its total of 78 are confirmed
unchanged. `CFG-20` is argued at length **not** to be a fourth unsatisfied MUST: its cancel-with-interrupt
clause is `ASYNC-3`'s mechanism under a second ID, and §10.5's ledger is not widened. Of the work earlier
phases had postponed, phase 5 takes four items (the `deadline:` keyword, the context-store cap, the
body-logging caps' source and `SEAM-28`'s consumer), closes a fifth open since phase 2 (`close_quietly`'s
second route), half-supplies two (the lifecycle event's shape and the dropped-failure diagnostic) and
postpones **none** of its own — a segmentation design decides a cut, not the interfaces whose absence a
postponement records, and phase 5's one candidate of the phase-4 hand-off's shape (`CFG-35`'s classifier)
is answered "phase 5 builds it".
The Deviation Ledger is empty. A tenth audit group, *Observability, configuration and redaction*, was
added to the `knowledge-lookup` skill's table before the group was run.

**2026-09-09** — **Catch-up entry, written 2026-09-12.** Phase 5a design filed, at
`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md`. Thirty-eight `CFG` IDs, one
chapter, one gem: 34 implemented, `CFG-19` satisfied **by construction** (this port's pivot delivers the
caller's own exception, so there is no wrapper to unwrap and no `unwrap` method ships — `P5-11`, the shape of 3a's
unused-public-API finding, Task 14's `#clear_tap` decision), and `CFG-20`, `CFG-34` and `CFG-35` partially satisfied with the unmet clause named in
each row. Six decisions were forced by facts run on real interpreters rather than argued. `CFG-18`'s
non-blocking delay **raises `Dexpace::SeamError`** when no `Fiber.scheduler` is registered rather than
degrading to a thread-backed delay, because there is no non-blocking path without one and a degraded
delay would satisfy three MUST clauses while violating the SHOULD's headline (`P5-9`). `CFG-30`/`CFG-31`
are parsed by an owned anchored grammar, because `Time.httpdate` accepts RFC 850, asctime and a leading
space — two date formats with no `'Xxx, '` prefix, which is the exact prefix `CFG-31`'s strictness clause
is about (`P5-12`). `Dexpace::Proxy` overrides **both** `#to_s` and `#inspect`, because `#inspect` is what
`p`, a log interpolation and an assertion failure message print, and overriding only `#to_s` satisfies
`CFG-22`'s letter while leaking the password through the likeliest path (`P5-7`). `UUID`'s generator is
memoised in `Thread.current[:…]` — the carrier `CLAUDE.md`'s constraint list names as the *wrong* one —
because here non-inheritance is the property wanted, and the deviation is recorded precisely because the
`CLAUDE.md` sentence reads as a blanket rule (`P5-13`). Fifteen deviations, `P5-1`–`P5-15`, opening
phase 5's ledger. One item postponed, `CFG-35`'s throwable half, to phase 6 (6a Task 3,
`Policy.throwable_retryable?`, with `XCUT-6`'s
capability and `Dexpace::TransportError`). One tooling finding, now the `knowledge-lookup` skill's own repair —
diff a `--prefix` rules query against the canonical range: the skill's audit-group row
returns 36 of 38 `CFG` IDs while `--prefix-info` reports 38 of 38, because two are filed under
`Reference` rather than `Rules`. It is the family of the probe's unresolved backticked paths and
ID-to-chapter claims and the corpus CLI's conflation of `[cited by …]` with `[overridden by …]`: a
mechanism reporting clean over a set it never looked at.

**2026-09-09** — **Catch-up entry, written 2026-09-12.** Phase 5a plan filed,
`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md`. **Seventeen numbered TDD tasks**
shipping the four-tier configuration chain with its atomic process-wide publication slot, the injectable
`Clock` seam and its cancellable queue-backed sleep, `Dexpace::Async.delay`, RFC 1123 formatting and the
owned anchored parser, non-cryptographic UUIDs, deep value equality, the `XCUT-5` retryability status
classifier, the static build/runtime descriptor, and the proxy model with its non-throwing,
credential-masking resolver — all 38 `CFG` IDs, plus `XCUT-5`, picking up the `deadline:` keyword (Task 8),
the context-store cap (Task 13) and the body-logging ceiling (Task 13) that phases 2, 4a and 3b postponed
here. The design's open questions are resolved in the front matter and carried through the tasks;
the citation `CFG-20`'s checklist row carries — `docs/first-release.md`'s unsatisfied-MUSTs entry, which
now names `CFG-20`'s cancel-with-interrupt clause as the same unmet clause under a second ID — and the
`knowledge-lookup` audit-group gap are what it cites rather than re-derives. Nothing is implemented; the checklist is written at execution time.

**2026-09-09** — **Catch-up entry, written 2026-09-12.** Phase 5b design filed, at
`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`, **written
concurrently with `5c`'s and reconciled with it the same day** — every place the two segments meet was
drafted as an assumption marked *pending reconciliation* and each marker is resolved in place, with the
section saying which side won. **The reconciliation found something neither document had noticed:
`OBS-24` had a scope-table row in neither**, the one-row-per-ID failure the convention exists to prevent.
It is 5b's, making this segment **28** IDs and `5c` **12** against a charter whose arithmetic and whose
prose disagree — filed against the phase-5 charter rather than fixed by editing it at the time, on phase 4c's
precedent; the charter's `5b` and `5c` ID-set sentences were corrected on 2026-09-13 to put `OBS-24` in
`5b`. The segment ships the structured-logging facade the whole SDK writes through, the redaction
policy, the payload preview renderer and the instrumentation step at `Stages::LOGGING`. `R10` is the
decision a later phase trips on: `OBS-19`'s three-mode header-drop policy **does not ship**, because the
requirement's subject is a transport that drops and core has none — postponed to phase 8c (Tasks 7, 9 and
15, `DropPolicy`) with both halves it is built from (`Severity`'s two levels, the once-per-key latch) shipping and exercised.
Deviations `P5-16`–`P5-38` in the reserved block. Three findings, each with an owner now: **§8.1's unsourced
`Event#tag`**, on phase 10's inbound list below (§8.1 names `Event#tag(key, value)` and no chapter-15
requirement does, so a fourth field channel would have no precedence rule); **the bare-`Logger` cop
watch**, 5b's own plan Task 10 (`Instrumentation::Logger` shadows the stdlib `Logger` and the cop cannot
carry the name, because the sink duck type is deliberately that surface); and **the charter's `OBS-19`
cell**, corrected on 2026-09-13 to point at `R10` (the 5b scope table stated an outcome its own `R10`
leaves open).

**2026-09-09** — **Catch-up entry, written 2026-09-12.** Phase 5b plan filed,
`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction.md`. **Seventeen numbered tasks**
shipping the four-tier severity enum, the frozen `Keys`/`Events` vocabularies, the duck-typed sink with
its frozen `NULL_SINK`, the total rendering subsystem with 8 KiB byte-sliced truncation, the
`Fiber[]`-based diagnostic-context bridge with its per-key union restore, the redaction engine and the
`Stages::LOGGING` step with tracer and meter slots `5c` populates — 28 IDs, 26 implemented and two ⏳
(`OBS-19` to 8c's `DropPolicy`, `OBS-37` declined for v1 in `docs/first-release.md`) — discharging
`XCUT-19`, `XCUT-20` and `XCUT-11`, closing `close_quietly`'s second disposal route (Task 14), taking the
optional diagnostic half of `Hooks.notify`'s dropped failures, supplying the shutdown event's shape for
`SEAM-25` and picking up the body-logging preview size and `BODY` gate (Tasks 14–15). Its fences were re-executed against `5c`'s changed
fences after the reconciliation rather than left at the pre-reconciliation figures.

**2026-09-09** — **Catch-up entry, written 2026-09-12.** Phase 5c design filed, at
`docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md`, the other half of the
concurrent pair, reconciled with `5b`'s the same day. Twelve IDs, eleven implemented and `OBS-32` ⏳
declined for v1 (`docs/first-release.md` § What v1 ships without, the `OBS-32`/`OBS-37` entry): the span
and scope protocols behind phase 4a's three published
singletons, the current-span carrier, log correlation pushing and restoring `trace.id`/`span.id`,
W3C and Datadog trace-id generation with zero-draw coercion, `Bundle#sampled?`, `HTTPTracer`'s
HTTP-shaped vocabulary with its ordering contract, and the metrics SPI with an allocation-free no-op
meter. The deviation ledger starts at **`P5-40`** and is deliberately non-contiguous with `5a`'s;
`P5-39` is a deliberate unused number, not a lost row. One item postponed — `OBS-29`'s tracer wiring: its
vocabulary ships with **no emitter**: the per-attempt group has none until phase 6's retry step and the
transport milestones none until phase 8, and wiring only the operation-lifecycle triple was considered
and rejected because `OBS-29`'s exhausted→failed pairing is not honourable by a step that cannot see
attempts (the per-attempt group landed in 6a Task 9; the operation-lifecycle triple and the transport
milestones are both on phase 10's inbound list below, as one `OBS-29` surface decision). Two findings: **phase 0's plan Task 4 gains a keyword-splat cop** (a `**` keyword splat allocates a `Hash` per call even when
nothing is passed — independently reproduced at reconciliation, ~1 per call — which makes `OBS-25`'s and
`OBS-1`'s allocation MUSTs unsatisfiable for any method written with one, and nothing mechanised
distinguishes it from the named keyword the styleguide's rule is about) and **the HTTP-tracer
factory-versus-bundle decision on phase 10's inbound list below** ("per-operation
tracer factory" names two different objects, and phase 4a bound the bundle's member to the one that is
per-library; the filed row rests on the internal contradiction between `OBS-25` and `OBS-29` rather than
on a claim about a gem neither phase could install).

**2026-09-09** — **Catch-up entry, written 2026-09-12.** Phase 5c plan filed,
`docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics.md`, closing phase 5. **Twelve
numbered tasks** over the tracing and metrics SPI, bounded by `OBS-20`, `OBS-30`, `CTX-20`, `XCUT-11`
and `XCUT-20`, consuming `SEAM-28`'s stable operation identifier and closing the no-op span and tracer
protocols 4a postponed here and `SEAM-28`'s consumer phase 2 postponed here (Tasks 3–5 and 4). It carries the reconciliation's `OBS-24` finding in its own goal statement rather than
leaving it to the design alone, and cites the phase-5 charter's arithmetic, since corrected to put `OBS-24` in `5b`.

**2026-09-10** — **Catch-up entry, written 2026-09-12.** Phase 6 segmentation design filed, at
`docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md` (the file carries a `2026-09-09` prefix;
it was added to the repository on the 10th). **The cut is three ways — `6a` retry, `6b` redirect, `6c`
authentication — and every boundary is a CONVENIENCE.** The roadmap's phase-6 bullet left one question
open, whether the `REDIR-24`/`REDIR-11`/`AUTH-29` coupling makes redirect and auth one segment or two;
the answer is two, and the reason is that **phase 4c already fixed the contract on 2026-09-08** —
`Cursor#fork(state:)` and `Cursor#state(stage)`, with only the forking step's own stage able to write —
so there is nothing left for a shared-contract sub-phase to land. The budget is **111 own IDs plus the
fifteen `RECOV` rows phase 4 handed it**, which land in `6a` with their own checklist rows while their
phase-4 rows stay ⏳. Of the work earlier phases had postponed, phase 6 takes six items, closes three
outright, leaves three postponed with a correction owed to one, and postpones **none** of its own.
the `Cursor` context-bundle widening is assigned to `6a` (its Task 8), and `CFG-35`'s throwable half is picked up and closed there
(Task 3). The Deviation Ledger is empty.

**2026-09-10** — **Catch-up entry, written 2026-09-12.** Phase 6a design filed, at
`docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-design.md`. **Sixty requirement IDs — forty-five
`RETRY` plus the fifteen `RECOV` phase 4 handed it — the largest sub-phase in the roadmap.** It builds **one**
shared policy core (the classification consult, the re-sendability gate, the backoff calculator, the
pacing-header parser and the tuning constants) and the **two** stacks that consume it: the recovery-chain
retry installed beneath phase 4b's `Orchestrator` with a total-timeout budget, and the pillar step at
`Stages::RETRY` with a sync and an async driver. One calculator, because `RETRY-13` forbids two. Seven
deviations, `P6-1`–`P6-7`, of which **`P6-4`** is the one a later phase acts on: phase 8's first
transport adapter must wrap every stdlib I/O and timeout error it lets escape in something answering
`#retryable?`, because `RETRY-2`'s classification is a capability-only query and a bare `SocketError` or
`Errno::ETIMEDOUT` classifies as **not** retryable — filed as a `docs/first-release.md` blocker and
closed in design by phase 8. Nothing new postponed: `6a` closes the fifteen handed-off `RECOV` IDs,
`ProtocolError#retryable?` and `CFG-35`'s throwable half, and picks up half of `OBS-29`'s wiring (the
per-attempt group, Task 9), declining the operation-lifecycle triple under its `R15` because the site that works is
`Stages::PRE_REDIRECT` and that is a **new step**, not a slot — the finding now on phase 10's inbound
list as `OBS-29`'s operation-lifecycle triple.

**2026-09-10** — **Catch-up entry, written 2026-09-12.** Phase 6a plan filed,
`docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry.md`. **Fourteen numbered tasks** over one frozen
`Resilience::Policy` module and the two stacks it feeds — `RecoveryRetry` beneath phase 4b's
`Orchestrator`, and `RetryStep`/`AsyncRetryStep` at `Stages::RETRY` — satisfying all 45 `RETRY` IDs and
all fifteen handed-off `RECOV` IDs (Tasks 3, 4, 5, 7 and 11), picking up and closing
`ProtocolError#retryable?` (Task 6), `CFG-35`'s throwable half (Task 3) and `OBS-29`'s per-attempt group
(Task 9), and
**executing the `Cursor` context-bundle widening** (Task 8): a read-only per-call accessor on `Cursor`
plus one optional seeding keyword on the call path, both `NFR-4` widenings, which is the resolution the
finding records as decided in planning and closing at execution.

**2026-09-10** — **Catch-up entry, written 2026-09-12.** Phase 6b design filed, at
`docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect-design.md`, the shortest sub-phase design so
far. Twenty-eight `REDIR` IDs, one chapter, no second gem: one iterative follower at `Stages::REDIRECT`,
forking a fresh `Cursor` for **every** hop including the first, resolving `Location` through
`URI::RFC3986_PARSER`, and enforcing every credential-hygiene rule against the **seed** origin rather
than the previous hop. The correctness stake is named rather than assumed: `REDIR-7`'s unconditional
`Authorization` strip and `REDIR-11`'s cross-origin signal are what stop a bearer token surviving a
cross-origin redirect, and `REDIR-8`'s seed-origin comparison is what both rest on. One deviation
candidate — `REDIR-17`'s max-hops cap enforced as a hard ceiling checked **before** a configured
predicate is consulted, rather than folded into the decision `REDIR-20` lets a predicate override —
deliberately **left unnumbered**, because three sub-phases were writing ledgers concurrently and a number
assigned in isolation could collide. Its proposed corpus note became `docs/knowledge/notes/redirect-handling.md`,
filed by phase 6's follow-through under `redirect-handling` rather than the `url-and-query-encoding`
topic `6b` proposed: measured, assigning `userinfo = nil` and rendering gives the credential back
unchanged while `userinfo = ""` clears both — a silent failure, so the assertion is on the rendered URL
and never on `#userinfo` being `nil`.

**2026-09-10** — **Catch-up entry, written 2026-09-12.** Phase 6b plan filed,
`docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect.md`. **Fifteen numbered tasks** over one
iterative pillar step that never calls its own `#call`: per hop it classifies the status, fast-paths a
non-redirect with no allocation (`REDIR-21`), otherwise allocates a `ConditionSnapshot` and consults
either a configured predicate or the built-in decision. All 28 `REDIR` IDs, with `REDIR-27` ⏳ under the
v1 decline in `docs/first-release.md` § What v1 ships without and no code written for it, plus `6b`'s share of the shared
`Resilience::Resend` replayability predicate that `REDIR-6`, `RETRY-5` and `AUTH-31` all consult.

**2026-09-10** — **Catch-up entry, written 2026-09-12.** Phase 6c design filed, at
`docs/work/mvp/phase6/phase6c/2026-09-09-phase6c-authentication-design.md`. Thirty-eight `AUTH` IDs,
**all implemented, no ⏳ row and no deferral** — the only sub-phase of phase 6 with none, `AUTH-29`'s
stripping clause satisfied by construction because nothing is ever added to strip. It ships the
descriptor and tier resolver, the four credential types with variant-specific equality and redaction, the
RFC 7235 challenge parser, the Basic and Digest handlers with a bounded per-nonce counter store, the
composing challenge handler, static key stamping, and the AUTH pillar step with its HTTPS guard,
cross-origin suppression, 401 re-challenge replay and bearer cache, on both runtimes. Five deviations,
`P6-1`–`P6-5`, numbered in isolation and knowingly colliding with `6a`'s — resolved at consolidation into
design §10, which is the failure `6b` avoided by not numbering at all. One finding, now a
`docs/first-release.md` blocker decision — **the `AuthDescriptor` carrier**:
`AUTH-4`–`AUTH-7`'s tier resolution presupposes an `AuthDescriptor` producer that no phase names — no
field on `Request`, on `RequestOptions` or on any `Operation` construct, and no `AUTH` requirement asking
for one — so the resolver ships correct and, absent later Operation-level wiring, exercised only by its
own unit tests. The same family as the probe's blind spots, the phase-5 charter's `OBS-19` cell and its
arithmetic, and `6a`'s `Cursor` widening: a sentence that reads correctly and resolves to something that
is not there.

**2026-09-10** — **Catch-up entry, written 2026-09-12.** Phase 6c plan filed,
`docs/work/mvp/phase6/phase6c/2026-09-09-phase6c-authentication.md`, closing phase 6. **Sixteen
numbered tasks, plus the sub-numbered `11a`** that carries `AUTH-36`'s step-level half, opening with a
task that re-verifies on the 3.2 floor and the 4.0 column every fact the
design flags before anything depends on it. The zero-dependency rule is carried explicitly through a
chapter that invites breaking it: Basic is `["u:p"].pack("m0")` and never `Base64`, Digest is
`Digest::MD5`/`Digest::SHA256` and never `OpenSSL::Digest`, the cnonce is `SecureRandom.hex(16)` and
never `Random` — every one already on phase 0's allowlist, so the plan adds no require-allowlist diff.

**2026-09-11** — **Catch-up entry, written 2026-09-12.** Phase 7 segmentation design filed, at
`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md` (the file carries a `2026-09-10` prefix;
it was added on the 11th). **107 IDs, no ID moving in or out, cut three ways — `7a` serialization (30),
`7b` SSE (41), `7c` pagination (36) — and the independence is spec-forced rather than merely chosen**:
`SSE-37` is a MUST that core parsing and streaming hold no serialization dependency, and §12's chapter
intro requires the pagination engine to be transport- and serde-agnostic. Phase 7 is also the phase that
ships the workspace's **second real gem**, `dexpace-serde-json`, inside `7a`. Of the work earlier phases had
postponed, phase 7 touches four items: `SSE-41`'s reactive-adapter latitude is carried as a ⏳ row
**inside** `7b`'s 41 rather than picked up; the floated phase-7 target for the `HTTP-22`/`HTTP-48`–`50`
helpers is **declined**, with a re-target at an *event* proposed in its place (now the standing line under
`docs/first-release.md` § Blockers before first publish); and two items are left whose conditions the
phase's work bears on. It postpones **none** and its Deviation Ledger is empty. Spec-forced boundary 5 is the `SSE-37` require-and-constant audit, extended
over core's pagination layer, and it is assigned to whichever of `7b` and `7c` lands first.

**2026-09-11** — **Catch-up entry, written 2026-09-12.** Phase 7a design filed, at
`docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-design.md`. Thirty `SERDE` IDs, all
implemented, **no deferral**, across **two gems**: `dexpace-core`'s witness protocol — the
class-object-and-combinator shape design §10.14 substituted for the reference's reflective type token —
with its four combinators and decode context, the `Tristate` three-state PATCH type, the native-form
encode walk that makes `SERDE-15`/`SERDE-19`/`SERDE-20` structural rather than a per-model discipline,
the `SERDE-2` body factory, the two response handlers supplied into phase 3b's `TypedResponse`; and
`dexpace-serde-json`'s codec, which fills that gem's `lib/` and is the one place the `json >= 2.19.9`
floor is declared. Nine deviations, `7a P7-1`–`7a P7-9` (the sub-phase letter is load-bearing; see the
`7c` entry below on the knowingly shared numbering). Four findings, each now with an owner, the first
being that phase 2 declared `interface _Codec` and never wrote its body, so `SERDE-2`'s default
Content-Type crosses a type boundary nothing declares — settled here by typing the interface
`(Dexpace::MediaType | String)` and coercing at `Body.serialized`. One corpus note is drafted for
`docs/knowledge/notes/serde.md`, a `## Reference` entry beside `serde/b5e5efc8`: a decoded JSON `String`
can be UTF-8-tagged and **invalid**, and neither layer that produces it raises. The note is written by
the plan's final task at execution time and is not filed yet.

**2026-09-11** — **Catch-up entry, written 2026-09-12.** Phase 7a plan filed,
`docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization.md`. **Nineteen numbered tasks** across
the two gems, ending with the codec that declares the `json` floor. All thirty `SERDE` IDs, nine
touched by a deviation row and nine carrying a stated clause; no deferral is filed. (Counts corrected
in place 2026-09-13 in the final review of `7a`: the entry read "three carrying a deviation row and
six a stated clause", against a design section headed "Nine rows carry a clause the checklist must
state rather than tick". The task count went from eighteen to nineteen in the same review, when the
`SEAM-26`/`SEAM-27` composition slice was added as Task 18 — `Dexpace::Operation` shipped in phase 2
and was composed with the pipeline and the codec by no phase.)

**2026-09-11** — **Catch-up entry, written 2026-09-12.** Phase 7b design filed, at
`docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events-design.md`. Forty-one `SSE` IDs,
forty implemented and `SSE-41` carried as a ⏳ row as a v1 decline (`docs/first-release.md` § What v1
ships without, the `SSE-41` entry) — **the
second-largest sub-phase in the roadmap**, after `6a`'s sixty and phase 3b's forty-nine. It ships the
WHATWG line and field state machine, the immutable five-field event value, the resource-owning
single-pass streaming facade with its four termination paths, and the typed adapter with its three
caller-supplied mapper outcomes. It owns the resolution of **the SSE line-cap closure evidence, now its own plan's Task 12**, and
proposes three corrections to that finding, the third of which changes what its resolution says: the requirement obliging the line cap is
`SSE-19`, a MAY, not `SSE-11`, a MUST about the `retry` field's magnitude, and the row's premise —
that phase 7's SSE machine is the consumer that reads lines from a server-controlled stream — is false.
Seven findings, none carrying a number, each now with an owner. Two corpus notes are drafted, for
`docs/knowledge/notes/sse-streaming.md` and `resource-management.md`, written by the plan's final task at
execution time and not filed yet. It also builds spec-forced boundary 5's `SSE-37` require audit as a
mechanism rather than describing it.

**2026-09-11** — **Catch-up entry, written 2026-09-12.** Phase 7b plan filed,
`docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events.md`. **Thirteen numbered tasks** over
`SSE::LineReader`, `::Reader`, `::Event`, `::Stream` and `::TypedStream`, satisfying `SSE-1`–`SSE-40`,
carrying `SSE-41` ⏳ as a v1 decline, resolving the line-cap closure evidence in Task 12 with the
corrected requirement ID and a documented line cap, and building the `SSE-37` require-and-constant audit that boundary 5 extends over core's
pagination layer.

**2026-09-11** — **Catch-up entry, written 2026-09-12.** Phase 7c design filed, at
`docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md`. Thirty-six `PAGE` IDs, stated
wholly inside one chapter and satisfied wholly inside one sub-phase: the page value and its response
ownership, the strategy contract and three built-in strategies, the byte-for-byte query splice, the two
consumption views over **one** lazy drive routine, and the async engine driven through phase 2's
`Future#on_settle`. `dexpace-core` only — `7c` writes nothing into either other gem. Six deviations,
`P7-1`–`P7-6`, **knowingly sharing numbers with `7a`'s and `7b`'s**: the collision is stated rather than
discovered, and is resolved at consolidation into design §10, which is `6b`'s precedent and the failure
`6a` and `6c` walked into. `P7-1` is the one a reader should follow: `PAGE-15`'s re-throw-wrapped clause
is conditional on a terminal that cannot declare the underlying error type, measured four ways on
3.4.10 to be unreachable in a language with no checked exceptions — §11.15's "clauses with no Ruby
manifestation" family, which §12's `PAGE` row records for `PAGE-35` and not for this one, so the row is
owed an addition. One corpus note is drafted for `docs/knowledge/notes/pagination.md`, written by the
plan's final task at execution time.

**2026-09-11** — **Catch-up entry, written 2026-09-12.** Phase 7c plan filed,
`docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination.md`, closing phase 7. **Seventeen numbered
tasks** over a frozen `Page::Paginator` producing per-iteration `Walk` objects that own every live
response — all 36 `PAGE` IDs, 35 implemented outright and `PAGE-35` vacuous by construction on design
§12's own authority. No deferral, no ⏳ row and no unsatisfied MUST is created.

**2026-09-12** — **Phase 8's seven planning documents filed**, under `docs/work/mvp/phase8/`; the files
carry a `2026-09-11` prefix, which is the day they were written, and they were filed and reconciled on
the 12th. The segmentation design is
`docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`, with a design and a plan in each of
`phase8a/` (synchronous transport and the conformance gem), `phase8b/` (async-runtime adapter) and
`phase8c/` (asynchronous transport). **Three sub-phases, not the roadmap's two**; every boundary a
convenience; the segmentation bullet and cross-cutting constraint 8 both corrected in place above with
their reasons. 52 IDs, none moving in or out, split 23 / 19 / 10. Phase 8 is the phase that ships the
most gems in the roadmap, and the first whose sub-phases ship none of them `dexpace-core` — which is why
it has five phase-level tasks, the first being `Dexpace::TransportError < ::IOError` in core, landed by
`8a`'s Task 2 and cited by `8c`'s Task 4. **Four postponed items picked up** (the conformance assertion
protocol, wire-boundary re-validation, `SEAM-25`'s lifecycle event, the `OBS-19` drop policy), **one
partly** (`OBS-29`'s wiring, whose transport half is declined because no route exists by which an adapter
in another gem reaches a per-operation `HTTPTracer` through an `NFR-4`-locked three-argument seam), **two
declined with the condition met** (`BODY-12` clause 2, and the move of core's fakes into
`dexpace-conformance` — the literal move declined on a development-dependency-cycle argument), **one
corrected in place** (the drop-policy item named `TRANSPORT-8` where the subject is `TRANSPORT-12`, with
`TRANSPORT-13` the logging twin; phase 5b's forward table carried the same wrong ID and is corrected with
it), and **none postponed**. **Fifteen findings filed**, the largest block any phase has produced, of
which four record that a frozen design chapter is wrong about a library: `Net::HTTP` has a built-in retry
that is on by default and swallows a cancellation (measured end to end — §12's `Net::HTTP` retry rows, on
phase 10's inbound list below); §3.2's block-scoped
`read_body` construction yields a fully buffered body and a dead socket (§3.2's `read_body` sentence, the
same list); `Async::Task#stop` is
deprecated in favour of `#cancel` (a `docs/knowledge/notes/concurrency-and-async.md` entry); and
`TRANSPORT-8` is *satisfiable* on the async adapter
where §12 counts it vacuous (§12's `TRANSPORT-8` vacuity claim, the same list) — the inverse direction,
and equally a defect. `docs/deviations.md`
gains one attribution note against §10.5, and `docs/first-release.md` closes the standing phase-8
error-wrapping blocker in design, gains the supported-Ruby and native-extension lines
`dexpace-transport-async_http`'s 3.3 floor forces, and gains the blocker that a green conformance run's
omissions must be written down before the gem is published. **No new unsatisfied MUST**: `ASYNC-3` and
`PIPE-33`'s interrupt clause are §10.5's and `docs/first-release.md` § What v1 ships without › Unsatisfied
MUSTs carries both unchanged, while `ASYNC-4` is on no such list because §10.5 holds it vacuous. Four corpus notes were filed on 2026-09-12 — three under
`docs/knowledge/notes/transport-adapter.md`, a new file, and one appended to `observability.md`.
`CLAUDE.md`'s phase-directory count goes from eight to nine with this filing; the "Zero gems exist under
`gems/`" sentence is unaffected and stays true until phase 0's scaffold lands as code.

**2026-09-12** — **Phase 9's two planning documents filed**, under `docs/work/mvp/phase9/`:
`docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-design.md` and
`docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance.md`. Nothing is
implemented; the checklist is written at execution time, per execution step 6. **No segmentation
design, and the decision is argued rather than assumed**: this document's own rule reaches build
phases 1 through 8 and says "phases 9 and 10 are audit-led and segment only if their own design
finds it necessary", and phase 9's design finds it does not — 41 IDs against phase 1's 42
unsegmented checklist rows, one gem rather than phase 8's four, and a shared contract (phase 8a's
assertion protocol) that is already written in another phase, so a sub-phase for it would restate
an inherited contract rather than fix one. Scope is the phase-9 row's 41 IDs, one checklist row
each, with **no earlier phase's row moving**: `SEAM`, `SERDE`, `OBS`, `PAGE`, `TRANSPORT`, `ASYNC`
and `PIPE` IDs are cited as evidence and as suite content, never carried as rows. `--gaps XCUT,NFR`
reports 41 of 41 substantive, so the phase budgets **no ID-side specification reading** — and budgets
the whole of appendix B instead, which is not ID-indexed and is the source of the roll-up hazard
`CLAUDE.md` names; all 61 items across `B.1`–`B.9` were read directly, counted 10/6/7/8/6/5/6/6/7.

**The appendix-B scoping decision, stated here because it is the one a reader will check.** `B.8`
(6 items) and `B.9` (7) are phase 9's own and it writes `InvariantSuite` and `PackagingSuite` for
them. `B.3`'s seam half is a **lift** of the file 7a named in its checklist for exactly this,
`gems/dexpace-serde-json/test/support/serde_seam_assertions.rb`; `B.4`'s two items §9.3 names by
hand become assertions over 8a's `RecordingSpan` and `Allocations`; `B.7` gains `ExecutorSuite`,
which is the unwritten harness half of `SEAM-25`'s lifecycle event; `B.6` is 8a's, already written, and phase 9 only
aggregates and audits its waivers. `B.1`, `B.2` and `B.5` — 22 items — are dispositioned **by
reference** to the owning phase's suite and recorded as deviation `P9-1`, on §9.3's own criterion
that the gem exists for portability across implementations of one seam and those three subsystems
have one implementation each. The artefact that makes "by reference" honest is a committed 61-row
coverage map, `gems/dexpace-conformance/APPENDIX_B.md`, whose limit is stated in `P9-7`: a
by-reference row proves an ID is claimed and a file exists, not that the behaviour is asserted.

**The phase-9/phase-10 boundary, fixed in as many words:** phase 9 measures and reports, phase 10
repairs. An audit that fails reports `:failed`, marks the row, adds a
`docs/first-release.md` blocker if the ID is a MUST, and hands the repair to phase 10 — whose row
above carries the permission to ship code twice over. The one exception is a defect inside
`dexpace-conformance` itself that stops the suite running, because otherwise the phase has no
instrument. Recorded as `P9-6`, and expressed mechanically as a file list: phase 9 touches nothing
under `gems/dexpace-core/` or any adapter.

**Nine deviations `P9-1`–`P9-9`**, and **four gates added to §9's table as addenda A4–A7** —
`gates:cause_walk`, `gates:bounded_map`, `gates:seam_names` and the `PENDING`-empty assertion on
7b's `gates:serde_boundary` — all four built on `RubyVM::AbstractSyntaxTree` and all four blocking,
because a non-blocking addition while dispositioning `NFR-17` would be self-falsifying. **Two
postponed items picked up** (the conformance protocol's second half — the remaining suites — and
wire-boundary re-validation's portable-assertion clause, both conditions naming phase 9 in as many
words), **none declined with the condition met** — the Steep target over a `test/` tree is the item
that invites it and its condition is still unmet, because phase 9's suites go in `lib/`, which phase 0
already gave a Steep target — and **four postponed**: the require-allowlist regeneration guard and
lifting appendix `B.1`/`B.2`/`B.5` (both `docs/first-release.md` § Post-release triggers),
`PackagingSuite`'s `NFR-12`/`NFR-16` against a published artifact (§ Release path), and `XCUT-12` under
a fiber scheduler (phase 10's inbound list below). **Three findings**, of which the first is a measured interpreter fact with committed consequences:
**Minitest is 6.0.0 on Ruby 4.0.6 and ships no `minitest/mock`**, so `Object#stub` and
`Minitest::Mock` do not exist on the top matrix row, two of 8a's plan fences use `.stub`, and two
corpus rules name absent APIs — settled by pinning `minitest` to `~> 5.25` in the root `Gemfile`
(phase 0's plan, Task 2), with lifting the pin a `docs/first-release.md` post-release trigger. The other
two are on phase 10's inbound list below: `NFR-13`'s SPDX gate is a RuboCop cop and cannot reach
`sig/**/*.rbs`, and §9.3's waiver sentence assumes an appendix-B item is the report's unit. `docs/deviations.md` gains one completeness note against §12's
`PAGE` row (`PAGE-15`'s wrapping clause, 7c's `P7-1`, which the row does not record).
`docs/first-release.md` gains no new blocker: its two standing conformance lines are the two this
phase discharges. Three corpus notes were filed before the plan was written — `testing.md` and
`tooling-and-quality-gates.md` under `## Superseded`, and `cross-cutting-invariants.md`, a new
file, under `## Reference`. Every Ruby fact in both documents was verified on 3.2.11, 3.4.10 and
4.0.6, and one was found false as first written: a `:CALL`-only AST scan misses every
safe-navigated send, because `a&.cause` parses as `:QCALL` — a gate that would have reported clean
while `XCUT-9`'s invariant was broken. `CLAUDE.md`'s phase-directory count goes from nine to ten
with this filing; the "Zero gems exist under `gems/`" sentence is unaffected.

**2026-09-12** — **Phase 9's two documents revised after two independent reviews, in one fix round.**
The segmentation decision, `R1`, `R4`, `R5`, `R7` and deviations `P9-1`, `P9-2`, `P9-8` were confirmed
and stand. What did not: a 66-mutation battery over the plan found **only 8 of 33 mutations caught at
the requirement level**, with five of five fully-written assertions and all three AST gates reporting
green over the very defects they name, and one — `XCUT-9`'s — **hanging** rather than failing. Since
phase 10 acts on phase 9's verdicts, a green-over-live-defect assertion is worse than no assertion,
so the round rewrote them against measured behaviour. Recorded here because the failure had one
dominant cause, and it is the one this repository's standards already name: **five doubles and probe
targets were built from a predecessor's prose rather than from its filed code fences** —
`Headers.build(live)` positionally where phase 1 filed `build(values:, casing:, direction:)`;
`HeaderSyntax.validate_outbound_value!(value)` where `name:` is required; **`Dexpace::SerdeError`,
which exists nowhere**, where phase 2 filed `Dexpace::Serde::Error` with `SerializationError` and
`DeserializationError` under it; `Dexpace::Redactor` where 5b filed
`Dexpace::Instrumentation::Redactor`; and `Auth::Digest.cnonce` where 6c filed
`Auth::DigestHandler` with an injected `cnonce_source:`. The third is the instructive one: the
invented constant is **why that task's reported green run was green**, and against the real hierarchy
two of its four tests fail on all three interpreters.

**Corrections that changed a requirement's disposition rather than its prose.** `XCUT-9`'s cycle is
now **three nodes** and the walk is bounded by step count through `Enumerator#next` — a two-node cycle
cannot tell an identity-tracking walk from a depth-capped one, and `.to_a` over a non-terminating walk
hangs. `XCUT-21` asserts the **source** structurally (6c's `cnonce_source:`, `#hex(16)`) instead of
inferring entropy from a rendered string's length, which passed a `rand`-derived cnonce and failed a
conforming 128-bit `urlsafe_base64` one. `NFR-15` **compares the runtime `VERSION` to the gemspec**,
where a not-a-placeholder check passes at `0.0.0` — the version every gem here carries. `XCUT-14`'s
drain-loop clause **moved to an AST gate**, because a check-then-evict map measured indistinguishable
from a drain loop in 0 of 30 runs at 16 threads and 0 of 20 at 64 threads under the GVL. `XCUT-11`
takes its exemption list **from the driver, not the audited object**, which had condemned a conforming
latch and passed the identical bug. `XCUT-13` and `XCUT-11` each gained a **second assertion** for
their second clause — `P9-8` is reworded from "one assertion per ID" to "one `Result` per assertion,
assertions keyed by ID", which is what unblocked them — and `ExecutorSuite` gained `ASYNC-16` and
`ASYNC-17`, with `SEAM-18` and `ASYNC-15`'s clause (c) scoped out with reasons. `XCUT-17`, `XCUT-18`,
`XCUT-19` and `XCUT-23` are now written in full; the honest residue is **11 `XCUT` plus 5 `NFR`
specified by shape**, not the 14 plus 5 first stated. **`R3`'s absent-artifact case is now
`:vacuous` with a mandatory reason rather than `:failed`**, because before any code exists "not built"
and "built wrong" are different findings — with an un-waived MUST-level vacuity made a phase-9 report
blocker so nothing passes by not being built.

**One measured interpreter divergence was missed entirely and is now an entry in
`docs/knowledge/notes/cross-cutting-invariants.md`: a Symbol literal is a
`:LIT` AST node on Ruby 3.2.11 and a `:SYM` node on 3.4.10 and 4.0.6** — the reverse of the usual
direction. Every other AST fact is identical across the three; this one made the reflective-send gate
catch 6 of 7 shapes on the floor and 2 of 7 on both newer rows, which is a gate strictest exactly
where it runs least. Phase 9's plan, Task 14, states in the map's own preamble the two appendix-B map checks that are not
achievable (a 276-ID coverage check against 22 hand-written rows, and a ten-line-header check against
`B.5` items naming twenty `CFG` IDs) and the three that replace them. **The reassignment of `SEAM-25`'s lifecycle-event
harness is now stated as a correction to a committed record** rather than made silently: phase 2's
postponement assigned the harness half to `8a`, 8a wrote no executor suite, and phase 9 writes it
(Task 11, `ExecutorSuite`). Four other corrections of record: the
hand-forward table was rebuilt from the prescribed grep and is **33 rows in thirteen documents**, not
eleven — the two phase-6 files had gone missing, which is exactly the six rows the first table
dropped; the reading of postponed work now names all 42 items exactly once, where it had enumerated 36
and double-counted one; the note count is **43 at `HEAD`**, where the first draft "corrected" the
charter's correct 43 to `CLAUDE.md`'s harvested-topic count of 40; and `R6`'s file list gains
`.github/workflows/ci.yml`, without which phase 0's blocking `ci_workflow_test.rb` reddens, and each
adapter gem's `test/` tree, following 8a's own driver precedent. **All seventeen `git commit` steps
were deleted** — `CLAUDE.md` forbids them and all twenty-one preceding plans have none. Measured
after the round, on 3.2.11, 3.4.10 and 4.0.6 under `ruby -w`: **55 runs, 94 assertions, 0 failures on
each**, across seven prototype suites; the three AST gates catch 6 of 6, 4 of 4 and 4 of 4 decidable
shapes, with every undecidable shape written into the gate's own stated gap.

**2026-09-13** — **The deferral register reconciled against the ten phases planned so far, 0 through 9, and then
retired.** Every one of its 47 items was given a terminal disposition from a fixed vocabulary (picked-up,
scheduled against a numbered plan task, declined with the condition met, release-gated, post-v1, event-gated,
handed to phase 10), and once every item named an owner outside the register — a plan task cited by path and task
number, or a `docs/first-release.md` entry — the file itself was dropped, every citation of it across the
repository rewritten in place to name the owner, and cross-cutting constraints 3 and 7, execution steps 1 and 7
and the third retrospective rule corrected above. Counted by each item's primary disposition, the 47 fell as:
**2 already picked-up** (the runtime version-skew guard, phase 2; the body member's typing, phase 3b);
**18 scheduled** against a numbered plan task — the conformance assertion protocol (8a Tasks 4–8 and 20; phase 9
Tasks 2–12a), the suppressed trail (4b Task 1), wire-boundary re-validation (8a Task 16, 8c Task 9, phase 9 Task
7), `close_quietly`'s two disposal routes (4b Task 2, 5b Task 14), the pivot's `deadline:` keyword (5a Task 8),
`SEAM-25`'s lifecycle event (8b Tasks 6 and 10; phase 9 Task 11), `Hooks.notify`'s dropped failures (4b Task 2),
the body-logging caps (5a Task 13, 5b Tasks 14–15), the fifteen `RECOV` IDs (6a Tasks 3, 4, 5, 7 and 11), the
context-store cap (5a Task 13), the no-op span and tracer protocols (5c Tasks 3–5), `ProtocolError#retryable?`
(6a Task 6), `Pipeline.standard` (6b Task 13a), `CFG-35`'s throwable half (6a Task 3), the `OBS-19` drop policy
(8c Tasks 7, 9 and 15), the MUST-level vacuity blocker (phase 9 Task 12a), plus `SEAM-28`'s consumer (5c Task 4)
and `OBS-29`'s per-attempt group (6a Task 9) by their scheduled halves; **1 declined with the condition met**
(moving core's fakes into `dexpace-conformance`, 2026-09-12, phase 8a); **4 release-gated** (the
`HTTP-22`/`48`/`49`/`50` helpers, the housekeeping fence executor, signed publication with `NFR-16` and
`NFR-12`'s release half, `PackagingSuite` against a published artifact); **16 post-v1** (`PIPE-36`, `RECOV-31`,
`RETRY-29`/`38`/`43`, `REDIR-27`, `SSE-41`, `OBS-32`/`OBS-37`, `TRANSPORT-28`'s zero-copy clause with
`TRANSPORT-30`, the seven gems of design §2.2, the unsatisfied MUSTs `ASYNC-3` and `PIPE-33`'s interrupt clause,
and presence-gated auto-activation); **4 event-gated** (a Steep target over a `test/` tree, `IO-38` on a Ruby
without a GVL, the require-allowlist regeneration guard, lifting appendix `B.1`/`B.2`/`B.5`); **1 handed to
phase 10** (`XCUT-12` under a fiber scheduler); and **1 split three ways** (`BODY-12` clause 1 picked-up by 3b,
clause 2 declined by 8a, `BODY-36` post-v1). Where each class went: scheduled items live in the plan task named
and land when that task executes, the phase's status note saying so; release-gated items went to
`docs/first-release.md` § Release path (signed publication, `PackagingSuite`) and its `### After the first
publish` (the fence executor), with the `HTTP-22`/`48`/`49`/`50` decision annotating the standing blocker line,
whose reopening event is the first consumer that constructs a conditional request; post-v1 items went to
`docs/first-release.md` § What v1 ships without, whose three subsections the release notes must state in full
(the unsatisfied MUSTs, with `ASYNC-4` kept off the list; the SHOULD/MAY declines, including the restriction that
no transport or codec adapter may ever use presence-gated activation; the seven gems of design §2.2); event-gated
items went to `docs/first-release.md` § Post-release triggers, each as trigger → the one job. Execution step 1's
sweep sentence, step 7, constraints 3 and 7, the third retrospective rule and the Post-v1 paragraph above are
corrected in place, dated; cross-cutting constraint 8 stands as written with its two citations repointed.

**Plan edits made today so the scheduled items point at real tasks.** Phase 6:
`docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect.md` gains Task 13a (phase-level, `Pipeline.standard`
and `redirect: :unsupported`, inserted because no phase-6 plan carried it; moves verbatim to 6a if 6a lands
second), mirrored in `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry.md`'s Task 13, whose Task 3 header
now names `CFG-35` (its throwable half); the 6a design's `OBS-29` entry is corrected. Phase 7:
`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`'s sweep verb, and
`docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination.md`'s Task 17 gains the pointer to the
`HTTP-22`/`48`/`49`/`50` decision. Phase 5:
`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md` and
`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md` acknowledge the mechanisms the
original postponements described differently (the `deadline:` keyword's timed gate pop inside
`Completer#await`; the body-logging caps' caller-owned chain read with `preview_bytes:` still required);
`docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics.md`'s Task 12 gains date placeholders
and the `SEAM-28` wording. Phases 8 and 9, written by a third writer under the supervisor's decisions and
verified by the supervisor before handover:
`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance.md` Task 25's closing
step; `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport.md` Task 19 Step 5a's closing
edits and the correction at its line 4002, which had said that no postponed item applied to any of the ten and
is corrected, dated, to name the drop policy (its closing pick-up) and wire-boundary re-validation (the second
adapter's call site); `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance.md`
Task 7's portable forged-`Request` assertion (wire-boundary re-validation's portable clause), Task 11's
genuinely failing `ASYNC-3` assertion waived by ID, Task 12a inserted (the MUST-level vacuity blocker:
`Levels::OF` from appendix C, `Report#blocking_vacuities`, `accepted_vacuous:` with mandatory citations), Task
14's `P9-1` citation (lifting `B.1`/`B.2`/`B.5`) and Task 17 Step 3 rewritten as the closing step that records
the conformance protocol, wire-boundary re-validation, the lifecycle-event harness and the vacuity blocker as
landed.

**2026-09-13** — **The open-items register reconciled against the same ten phases, 0 through 9, and then
retired**, the second register to go the same day and for the same reason. Every one of its 59 items was given
an owner outside the register — a numbered task in the plan of the phase whose scope it falls in, a bullet on
phase 10's inbound list below, an entry in `docs/first-release.md`, a note under `docs/knowledge/notes/`, or a
fix made on the spot in the writable material it was about — and once every item named one, the file itself was
dropped and every `OI-<n>` citation across the repository was rewritten in place to name the owner. **There is
no `OI-<n>` namespace any more**, and the rule that replaces it is the one `CLAUDE.md` now states: a finding is
routed to its owner when it is found, not registered. Counted by each item's primary disposition, the 59 fell
as: **23 routed to a numbered plan task** — phase 0 takes seven (the reviewed `.rubocop.yml` baseline and its
measured `Metrics/ParameterLists` cost, the keyword-splat cop, the `minitest` Gemfile line and its `~> 5.25`
pin, the per-gem require-allowlist denylist scope, the thread-count teardown assertion, the `Data`-reader
surface-snapshot decision), phase 9 five, phase 3's two sub-phases three, and phases 1, 2, 4c, 5b, 6a, 7b and
8c the remaining eight; **14 to phase 10's inbound list** below, each restated there in full with its measured facts, because
eight of the fourteen are sentences in a chapter only a human may amend and seven of those also gain an interim
note under `docs/deviations.md` § Deviations found outside a phase; **4 to `docs/first-release.md`** — two
blockers before first publish (documenting the `include Dexpace` constant shadow in `docs/sdk-documentation/`,
and the `AuthDescriptor` carrier decision), `CFG-20`'s cancel-with-interrupt clause folded into the
`ASYNC-3`/`PIPE-33` unsatisfied-MUSTs entry as the same unmet clause under a second ID, and the `CTX-7`/`CTX-8`
drain proof folded into the non-CRuby `IO-38` post-release trigger; **17 fixed outright** in
`scripts/knowledge.rb`, `.claude/skills/housekeeping/probe.rb`, the `knowledge-lookup` skill, six corpus notes
under `docs/knowledge/notes/`, two committed phase charters and this document's own gap paragraph — one of the
seventeen needing no edit at all, because the two plan tasks it was about already cross-cite each other; and **1
already resolved** (phase 3b's `Body#source` and its no-op `#close`, 2026-09-08). Two items earn a second home
beside their primary one: the `minitest` pin gains a `docs/first-release.md` post-release trigger for lifting
it once no fence requires `minitest/mock`, and phase 10's uncapped `Clients#@by_origin` gains a
`docs/first-release.md` blocker, because `gates:bounded_map` stays red until it is fixed and `XCUT-14` is a
MUST. And three items leave a frozen-chapter half their primary owner could not take — the chapters
attributing `IO-6`'s ownership rule to the retired `SEAM-3`, the probe's unbuilt "this ID is stated in
chapter X" claim check, and §9.3's calling Minitest a default gem when it is a bundled one — so all three are
bullets on phase 10's inbound list beside the fourteen. The one
repair this document owes is the gap paragraph above, corrected in place and dated: it is three of the
seventeen, the three unfollowable gap pointers.

**Phase 10's inbound list, stated here because phase 10 has no design yet and this is the entry it will
read first.** **Restated as a list on 2026-09-13**, when the open-items register was retired: fourteen of that
register's items were audit-or-repair work against a phase that is already planned, which is this list, and
three more contribute a half each that no writable material could take. Every one is written out below **in full**,
with its measured facts, because the register body that carried them no longer exists. Each entry names what is
wrong, what the correct statement is, and where the code half already lives. **Entries added after that
restatement carry their own date**, so the list grows as later review passes route audit-or-repair work here
and the fourteen-plus-three provenance above stays readable as provenance rather than as a running count.

**2026-09-13 — phase 10 now has a design and a plan, and every bullet below is dispositioned in them.** The
sentence that opened this list — "stated here because phase 10 has no design yet and this is the entry it will
read first" — has been answered:
[`phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness-design.md`](./phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness-design.md)
carries a table mapping **all thirty-two bullets** — the twenty-four below plus the eight this planning pass
added — to a numbered task, an amendment, or the evidence that no repair is needed, and the plan is
[`phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness.md`](./phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness.md).
The per-bullet owners are **not** restated here, and the reason is this list's own job rather than a numbered
constraint: cross-cutting constraint 7 makes this list a place a finding is *routed to*, and the design's
disposition table is where each one's owner lives, so a copy beside the bullets is the second thing that would
have to be kept true. (An earlier draft of this paragraph cited cross-cutting constraint 9 for that, which is
wrong: constraint 9 is about not copying the domain-model construction pattern and the constraints that will
bite into a phase document. Corrected 2026-09-13.) The
counts, so this paragraph is checkable against the table: **12 bullets become repairs** shipping code or a
check, across **eight** tasks — 6 and 10 share Task 4, 29 and 30 share Task 3, and Task 3 also takes 5 —
**13 become one of thirteen written frozen-chapter amendments**, **2 are decided with no surface
change** (`OBS-29`'s wiring and `CTX-16`'s carrier, both closed by canonical text nobody had re-read), **3 are
audit-only**, and **2 were fixed on the spot in this pass** because they were in writable material — phase 5a's
substituted proxy IDs and phase 8a's half-stale `TRANSPORT-30` forward row. Bullets whose repair is expected to
be **moot** — the uncapped `Clients#@by_origin`, which `8c`'s plan Task 8 now bounds at planning time — stay
below unchanged, because a green `gates:bounded_map` run is what closes them and a sentence in a plan is not
evidence the work was done.

**From the reconciliation.**

- **The audit of the §10.5 ledger** — cross-cutting constraint 8: `ASYNC-3` and `PIPE-33`'s interrupt clause
  unsatisfied, `ASYNC-4` vacuous, and the trade not re-opened (`docs/first-release.md` § What v1 ships without
  › Unsatisfied MUSTs, which since 2026-09-13 also names `CFG-20`'s cancel-with-interrupt clause as the same
  unmet clause under a second ID).
- **`OBS-29`'s surface decision, which is three findings and one decision.** Its two residual halves — the
  operation-lifecycle triple and the transport-milestone group — are **one surface decision**: a
  `PRE_REDIRECT`-adjacent step and/or a deliberate `RequestOptions` widening. *(a) The triple cannot be emitted
  from `Stages::LOGGING`, which is where the phase-5 deferral's stated route puts it.* Verified 2026-09-09:
  `5b`'s `Dexpace::Instrumentation::Step` declares `#stage` returning `Dexpace::Pipeline::Stages::LOGGING` and
  is installed with no `stage:` argument, and phase 4c rejects with `Dexpace::PipelineError` any install
  supplying a different `stage:` for a step that declares one — **so the step cannot be moved**. `LOGGING` is
  order 1100 while `REDIRECT`, `RETRY` and `AUTH` are 200, 500 and 800, so once phase 6's pillars exist a step
  there runs once per redirect hop, per retry attempt and per auth replay, contradicting `OBS-29`'s "One
  tracer instance corresponds 1:1 to a single logical operation lifecycle". The site that satisfies the clause
  is `Stages::PRE_REDIRECT`, order 100, which phase 4c states is "outside every pillar's fork, so a step there
  is invoked once" and which `PIPE-37` already reserves for terminal-response-only steps — and that is a **new
  step**, not a slot. Phase 6a declined it under its `R15`: no phase-6 ID justifies the `NFR-4` surface, and
  `OBS-28`'s "Every event method SHOULD default to a no-op" is what makes wiring the per-attempt group alone
  safe. *(b) No route exists by which a transport adapter reaches an `HTTPTracer` at all.* Phase 5c shipped
  `Dexpace::Instrumentation::HTTPTracer` with five transport methods whose argument lists it fixed —
  `#request_url_resolved(context, url)`, `#connection_acquired(context, host, port)`,
  `#request_sent(context, byte_count)`, `#response_headers_received(context, status, headers)`,
  `#response_received(context, byte_count)`. The transport seam is `#call(request, options, cancellation)`;
  `Request`'s members are `(:method, :url, :headers, :body)` and `RequestOptions`'s are
  `(:timeout, :max_retries, :tags)` (phase 5b's `P5-33`); the adapter is in a different gem; `PIPE-11` forbids
  ambient carriage; and `NFR-4` locks the seam's three-argument shape. So an adapter reaches a tracer only
  through its own constructor — one tracer for the adapter's whole lifetime, not one per operation — or
  through a widening of `RequestOptions`, a core type and a phase-1 surface. 8a decided not to wire it.
  *(c) "Per-operation tracer factory" names two different objects, and the bundle's member is bound to the one
  that is per-library.* `CTX-14` (MUST) requires the correlation bundle to expose "a per-operation tracer
  factory" and `OBS-29` (MUST) says of the *HTTP-tracer* vocabulary that one tracer is "created by the factory
  per operation" — one object created once per operation. That reading is not available, and the proof needs
  nothing outside this repository's normative text: `OBS-25` (MUST) requires "a no-op HTTP-tracer /
  tracer-factory" and that "Selecting a no-op path MUST NOT allocate per call", so the no-op factory MUST
  return the same object every time, which is the opposite of one instance per operation. Phase 4a's `P4-8`
  then bound `Bundle#tracer_factory` to `opentelemetry-api`'s `TracerProvider` shape —
  `#tracer(name = nil, version = nil)`, positional — which is keyed by instrumentation-library name and
  version rather than by operation. (Its stated motive, that `OpenTelemetry.tracer_provider` can be passed
  straight into `Bundle.build(tracer_factory:)`, is an **unverified** claim about a gem neither phase 4a nor
  phase 5c could install — re-checked absent 2026-09-09 — and the argument above does not depend on it.) So
  the bundle's factory produces **span** tracers (`OBS-21`–`OBS-25`) and is legitimately shared or cached,
  while `OBS-29`'s produces **HTTP-tracers** (`OBS-28`'s eleven-method vocabulary) and is legitimately
  per-operation; appendix C, design §8.1, phase 5c's Tasks 3–5 and phase 4a's `R3` all read them as one
  object. Phase 5c's `P5-43` reconciles the no-op case only — `OBS-29`'s 1:1 clause binds stateful tracers, so
  a shared stateless `NO_TRACER` satisfies both MUSTs — and says nothing about a recording one. **What is
  owed:** the surface decision, and with it the cross-reference that makes the two factories two.
  Touches `CTX-14`, `CTX-20`, `OBS-25`, `OBS-28`, `OBS-29`, `PIPE-2`, `PIPE-11`, `PIPE-37`, `SEAM-11`,
  `SEAM-16`, `NFR-4`.
- **The probe's "this ID is stated in chapter X" claim check, which is not built.** Measured 2026-09-13,
  during the register retirement: the `links` check now catches a backticked normative chapter path that does
  not resolve (`Links#span_findings`, built the same day), but the second half — a document asserting that a
  requirement ID is *stated in* a named chapter when the chapter does not carry it — has no check, and that is
  exactly what the three gap pointers corrected above were. The measurement says why it is not a one-line rule:
  **43 lines under `docs/` name both a spec chapter and a canonical ID, 21 would fire under a naive same-line
  rule, and most of those are not claims at all** — a chapter and an unrelated ID that merely share a line, and
  appendix C, which carries every ID and so can never be wrong about one. **The job:** a claim grammar ("read
  out of X", "stated in X", an `X §N` adjacency), a vocabulary for ranges and placeholders, and an appendix-C
  special case, tuned against those roughly forty live candidates before it is allowed to gate anything.
- **The judgement whether the thread-only `XCUT-12` form phase 9 ships in Tasks 7–8 suffices**, with
  `dexpace-async-async`'s reactor adapter as the fallback trigger and `docs/first-release.md` § Post-release
  triggers as the fallback home.

**From phase 9's own hand-offs.**

- **The repairs of every audit phase 9 reports `:failed`**, each earning, for a MUST, a `docs/first-release.md`
  blocker (`P9-6`).
- **`dexpace-transport-async_http`'s `Clients#@by_origin` is an uncapped per-origin client cache, which
  `XCUT-14` (MUST) forbids.** `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/clients.rb`
  (8c plan:1683-1756, the ivar at 1715) is a plain `Hash` behind a `Thread::Mutex`, keyed by
  `Endpoints.origin_for(url)`, with a hard cap on neither its size nor its lifetime: `#fetch` inserts with
  `||=` (8c plan:1725-1732) and **nothing evicts** — `#close` (8c plan:1740-1744) reads `@by_origin.values`,
  closes each client's pool and leaves the map itself populated. `XCUT-14` covers "Every process/instance-lived
  map whose key space is influenced by callers or remote servers", and both influences are present: a caller's
  URLs choose origins, and a server's redirect `Location` chooses new ones. The map is instance-lived and an
  `Adapter` lives as long as the client (`Adapter#close` is `@clients&.close`, 8c plan:2825), so there is no
  other cleanup mechanism. It is the **one true positive** of the six `gates:bounded_map` reports over every
  filed Ruby fence of phases 0–8 naming a `lib/` path — 222 fences at 184 distinct `gems/*/lib/**/*.rb` paths,
  measured identically on 3.2.11, 3.3.12, 3.4.10 and 4.0.6; the other five, in four files, are adjudicated
  false positives, each carrying its reason in `InvariantGates::BOUNDED_MAP_ALLOWED` (phase 9 plan:4016-4029
  for the adjudication, 4504-4519 for the allowlist). The same sub-phase bounded its other caller-keyed map at
  64 distinct names for `TRANSPORT-13` — `DropPolicy::MAX_TRACKED_NAMES` (8c plan:1525, enforced at :1583,
  its test at 8c plan:1453-1462; all three citations corrected 2026-09-13, the originals having pointed at a
  Files block and a comment line) — so this is an omission rather than a decision. **The fix:**
  `Dexpace::BoundedMap` or an equivalent cap with drain-to-cap eviction, including a `#close` on each evicted
  client, since the values own pools. It is phase 10's because `8c` owns the file and has already run by the
  time phase 9's audit does, and because design `R6` ("a bug found in `Dexpace::BoundedMap` is filed here and
  fixed by phase 10", design:661) applies to another gem's map. `gates:bounded_map` stays red until it lands,
  and `XCUT-14` being a MUST is why `docs/first-release.md` carries a blocker line for it. **Amended
  2026-09-13 by the final pre-build review of phase 8c: `8c`'s plan Task 8 now bounds the map at planning
  time** — `Clients::MAX_ORIGINS` with a loop drain back to the cap after each insert and
  `Dexpace.close_quietly` on each evicted client's pool, plus two tests — so this entry is expected to be
  moot when `8c` lands and phase 10 to find nothing to repair. It stays on this list until a green
  `gates:bounded_map` run says so. What made the difference is only that `8c` had **not** in fact already
  run when phase 9's audit read its plan, which is the premise the phase-10 routing rested on. Touches `XCUT-14`,
  `TRANSPORT-13`, `NFR-17`.
- **~~8a's `Adapter#dispatch` leaves its rescue variable unused~~ — first half CLOSED 2026-09-13 — and every
  repository tool that parses a filed source carries the same exposure.** As filed, this bullet reported that
  `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance.md:4858`
  files `rescue ::StandardError => e` inside `Adapter#dispatch`, whose body calls
  `Dexpace.close_quietly(pump)` and re-`raise`s and never reads `e`; parsing that fence with
  `RubyVM::AbstractSyntaxTree.parse_file` under `-w` emits `assigned but unused variable - e`, re-measured
  2026-09-13 identically on 3.2.11, 3.3.12, 3.4.10 and 4.0.6, which is a lint finding rather than a
  correctness one — the rescue re-raises, so dropping `=> e` changes nothing at runtime. **That half is
  already repaired.** Commit **152ec6a**, the pre-build review of every MVP phase plan, dropped the binding:
  8a's `Adapter#dispatch` now reads `rescue ::StandardError` at that plan's **:5177** (the method at :5168),
  and the plan records the correction itself at :6337-6339 — "the binding is gone", with two further shapes
  corrected for the same reason. Line 4858 today is `body = res.body_string`, so **the citation above no
  longer resolves and is kept only as the provenance of the measurement.** Phase 10 ships no repair for it;
  the interpreter measurement survives as the fixture that proves `AstScan.parse`'s `$VERBOSE` window still
  works (phase 10's plan, Task 6 Step 5). **The generalisation is what outlives the
  one line, and it is the whole of what phase 10 now owns here:** any future repository tool that parses a filed source under the warnings-fatal test case has the
  same exposure, and nothing mechanises the rule that keeps it closed — "nothing else in this file may call
  `parse_file` directly" is a comment in `tools/ast_scan.rb` (phase 9 plan:4248-4249), not an assertion, and
  no gate asserts that `AstScan.parse` is the only caller of `parse_file` in the repository. Phase 9's own
  exposure is closed (`AstScan.parse` opens a `$VERBOSE = nil` window restored in `ensure`, phase 9
  plan:4285-4292, with Task 13's test at 4219-4227). **What would close the general case:** a check asserting
  sole use of `AstScan.parse`, or a shared parse helper the gates cannot bypass. Touches `NFR-6`, `NFR-17`.
- **`NFR-13`'s SPDX gate is a RuboCop cop, so it cannot reach `sig/**/*.rbs`, which ships inside every gem.**
  `NFR-13` (SHOULD) is "Every source file SHOULD carry the project's license/SPDX header block" and its
  conformance clause is "scan **all source files** for the required header"; phase 0 mechanises it as
  `Dexpace/SpdxHeader`, a **custom RuboCop cop** — a strengthening over the reference's review convention,
  recorded as `P0-1`. A cop inspects Ruby, and `.rbs` is not Ruby: no cop parses it. `sig/` mirrors `lib/` one
  file per file and ships inside each gem so a consumer's `steep check` sees it, so the signatures are shipped
  source, and by phase 8 roughly as many `.rbs` files ship as `.rb` files. Phase 0's own `.rbs` fences carry no
  header — checked: every `` ```rbs `` fence in
  `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md` opens with `module Dexpace`. RBS
  supports `#` comments, so the header is expressible; what is missing is a check. **The repair:** either a
  small Rake gate over `sig/**/*.rbs` beside the cop — the same three-line assertion over a different glob — or
  a deliberate, stated decision that `NFR-13` covers `lib/` only, put somewhere a reader will find it rather
  than left as the silent consequence of the mechanism phase 0 chose. Phase 9 records the gap in `NFR-13`'s
  disposition row rather than closing it, per its `P9-6`. Touches `NFR-13`, `NFR-3`, `NFR-17`.
- **The `PAGE-15`/`P7-1` and §10.5 attribution notes in `docs/deviations.md`**, to fold into design §10 —
  joined on 2026-09-13 by the seven interim notes the frozen-chapter corrections below carry.
- **Any `gates:bounded_map` that runs red.**

**Frozen-chapter corrections.** Each is a sentence in a chapter this repository may not edit; in every case
the phase that found it shipped the code half already, and what is owed is the corrected sentence the next
time that chapter is deliberately amended by a human. All but two — §8.3's scope clause and §9.3's
default-gem sentence — also carry an interim note under `docs/deviations.md` § Deviations found outside a phase, so each finding has a home until
then; the two against §12's `TRANSPORT` row share one note.

- **§3.1's decode recipe destroys every non-ASCII byte, and its target-less `#encode` follows a process
  global.** `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1 fixes one decode boundary and
  names the mechanism: `Response#body_string`, "which applies the media type's charset via
  `String#encode(invalid: :replace, undef: :replace)` and falls back to UTF-8 when absent or unknown". The
  **rule** is right and phase 3b implements it unchanged; the **mechanism** is wrong in two independent ways,
  each verified 2026-09-08 on 3.2.11, 3.4.10 and 4.0.6. *It mangles the payload*: the same paragraph requires
  every response body to be retagged `Encoding::BINARY` on ingress, and from BINARY every byte at or above
  `0x80` is an undefined character in the source encoding, which `undef: :replace` replaces —
  `"café".b.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace)` returns `"caf"` followed by two
  U+FFFD, one per byte of the two-byte `é`, and is not `==` to the correct answer on any of the three. *And
  its result depends on a process global the host controls*: the cited call passes no target encoding, so it
  converts to `Encoding.default_internal`; with `Encoding.default_internal = ::Encoding::ISO_8859_1` — a
  single line any host may have run — the same call on the same string returns an ISO-8859-1 result with the
  accented character destroyed, while the explicit-target form is unaffected, verified both ways on all three.
  That is the passes-where-you-look shape §3.5 pins `URI::RFC3986_PARSER` against. Nothing mechanical catches
  it: the result is a well-formed `String`, `rbs`/`steep` see a `String` either way, and an **ASCII-only test
  fixture passes under the bug**. **The correct statement:** retag to the declared charset first — phase 3a's
  `Dexpace::IO::TypedReads#read_string(encoding)` — then transcode with **both** encodings named,
  `#encode(enc, invalid: :replace, undef: :replace)`. **Code half:** phase 3b's `Response#body_string` does
  exactly that, resolving the charset from `Dexpace::MediaType#charset` (phase 1 returns `nil` for an absent
  **or** unknown-to-this-Ruby charset, so `HTTP-42`'s fallback needs no second validation and `Encoding.find`
  cannot raise), and `docs/knowledge/notes/io-and-byte-streams.md` overrides `io-and-byte-streams/fbcb4d19` so
  the next reader does not repeat the recipe. Not a deviation from the reference contract — `HTTP-42` is
  satisfied exactly. Interim note in `docs/deviations.md`. Touches `HTTP-42`, `HTTP-24`, `IO-13`, `BODY-16`.
- **§4's builder list drops the multipart body, which `HTTP-3` names.**
  `docs/sdk-design-ruby/04-domain-model-construction.md` §4 quotes `HTTP-3`'s own split and then restates the
  builder side as "`Request`, `Response`, `Headers`, `Query`, `RequestOptions` and `Configuration` get real
  mutable `Builder` classes". `HTTP-3`'s canonical text (appendix C) lists **seven** subjects — "Request,
  Response, Headers, QueryParams, RequestOptions, RequestConditions, **and the multipart body**" — each of
  which "MUST expose a newBuilder()-style derivation returning a builder pre-populated with the instance's
  current fields … the pre-filled builder MUST NOT alias the original's internal collections". §4 adds
  `Configuration`, which is fine, and silently drops the multipart body, which is not. **The cost of leaving
  it:** the omission already cost the clause an owner once. Phase 1 owns `HTTP-3` and builds no multipart
  body, so its checklist could only tick the six models §4 names; phase 3b ships
  `Dexpace::MultipartBody` and, reading §4 rather than appendix C, filed it with a plain `.new` and no
  derivation — a MUST with a named subject satisfied by nobody, found by review on 2026-09-13. Phase 3b now
  ships `MultipartBody#new_builder` and `MultipartBody::Builder` with the non-aliasing clause asserted
  (its plan, Task 7), and carries `HTTP-3` as a cross-reference row while phase 1 keeps the ID. **The
  addition owed:** the multipart body named in §4's builder sentence. Not a deviation — the port satisfies
  `HTTP-3` in full once 3b lands; only the design's restatement of the requirement is short. Touches
  `HTTP-3`, `HTTP-51`, `BODY-2`.
- **§3.1's ownership sentence and §10.12 attribute `IO-6`'s rule to the retired `SEAM-3`.**
  `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1's "Two ownership rules, deliberately
  different" paragraph reads "At the I/O layer, wrapping takes ownership: closing a `BufferedSource` built over
  a caller's `IO` closes that `IO` (**SEAM-3**)", and design §10 item 12 leans on the same rule. But `SEAM-3`
  is the ID design §10 item 1 **retires**, and phase 2 shipped it as 🚫. The live ID is **`IO-6`** (MUST):
  "When a provider wraps a caller-supplied underlying stream … the returned wrapper MUST take ownership of that
  stream: closing the wrapper closes the underlying stream" — and appendix C is its **only** normative
  statement, because `docs/product-spec/05-i-o-contracts.md` §5.1 runs `IO-1`–`IO-5` and `IO-18` and only the
  bridge half survives there, under `IO-16`, a SHOULD. **The cost of leaving it:** a phase auditing `SEAM-3`'s
  retirement finds no surviving citation and could reasonably conclude the ownership rule retires with the
  seam, which would leave every `BufferedSource` built over a caller's stream leaking that stream on close — a
  violation no gate catches, because the requirement it breaks is cited nowhere a reader looks. **The correct
  statement:** §3.1's ownership sentence and §10.12 cite `IO-6` rather than, or alongside, `SEAM-3`. **Code
  half:** 3a reads `IO-6` out of appendix C and implements ownership-on-wrap, and the gap paragraph above now
  names appendix C as its source. The corpus repeats the attribution at `message-bodies/8a1e7a7b`, where a note
  under `docs/knowledge/notes/message-bodies.md` marks it. Touches `IO-6`, `IO-16`, `SEAM-3`, `BODY-8`.
- **§8.1 names `Event#tag(key, value)` and no requirement in chapter 15 does.**
  `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1 fixes the event object's surface in a
  code block — `#field(key, value)`, `#tag(key, value)`, `#event(name)`, `#cause(error)`, `#emit`. Four are
  traceable to a requirement (`OBS-3`, `OBS-4`, `OBS-39`, `OBS-8`); **`#tag` is not.** No `OBS` requirement
  names a tag other than `OBS-4`'s reserved `event` tag, which the same block gives to `#event(name)`; §8.1's
  prose mentions `#tag` nowhere after the code block; and `OBS-5`'s precedence rule enumerates exactly three
  contributing sources — per-event field, global context, folded diagnostic context — so a fourth channel
  would have no precedence over any of them and no rule about collisions. The near miss is `OBS-8`'s
  "Field/tag/cause accumulation is not required to be thread-safe", but the tag it names is `OBS-4`'s single
  reserved categorisation tag, and nothing in the chapter gives a tag a **key**, which is what the
  two-argument signature is for. **Why it matters:** `NFR-4` locks a public signature at the first release
  tag, and §8.1 is the document a phase-5 implementer copies the surface from, so shipping `#tag` would give
  the SDK a public, YARD-documented, RBS-signed method with no requirement, no default, no precedence rule and
  no caller. **The correct statement:** either §8.1 names the requirement `#tag` serves and its precedence
  relative to `OBS-5`'s three sources, or the line goes. **Code half:** phase 5b ships `#field`, `#event`,
  `#cause` and `#emit` and not `#tag`, recorded as deviation `P5-18` — and not shipping it costs nothing
  before the first release, because adding a method widens. Interim note in `docs/deviations.md`. Touches
  `OBS-4`, `OBS-5`, `OBS-8`, `NFR-4`.
- **§3.2's block-scoped `read_body` construction cannot satisfy the two requirements it says it satisfies
  "literally".** `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:167-171` reads: "Streaming is
  preserved end to end: `dexpace-transport-net_http` issues the request inside
  `Net::HTTP#request(req) { |res| ... }` and exposes the response body as a `BufferedSource` over the
  block-scoped `Net::HTTPResponse#read_body` stream, so **SEAM-11**'s no-pre-buffering clause and
  **TRANSPORT-25**'s 'lazily-read stream, not pre-buffered … closing the SDK response cascades to close the
  native body and release the connection' are satisfied **literally**." Measured against a `TCPServer` that
  writes five body bytes, sleeps 400 ms and writes five more, on `net-http` 0.6.0 under Ruby 3.4.10:
  `#request` without a block returned after **401 ms** with `res.body == "aaaaabbbbb"`; the block form with a
  block that does not read returned with the body **already buffered**, because `Net::HTTPResponse#reading_body`
  ends with `self.body` and nils `@socket` in its `ensure`; and `res.read_body` after the block raised
  `IOError: Net::HTTPOK#read_body called twice`. So the prescribed construction yields a fully buffered body
  and a dead socket — `SEAM-11`'s "MUST NOT pre-buffer the body (caller owns read/close)" and `TRANSPORT-25`'s
  lazily-read stream both violated by the design's own recipe. **The correct statement:** §3.2 names a
  construction that works. **Code half:** 8a's `R1` ships a per-response producer `Thread` over a
  `Thread::SizedQueue(1)` drained through a `#readpartial`-shaped reader, deviation `P8-1`. The fiber
  alternative is disqualified by `FiberError: fiber called across threads` — `Fiber#resume` from a second
  thread raises, so a pump created on a `dexpace-async-thread` worker inside `Transport.async_over` could not
  have its body read on the caller's thread, and `TRANSPORT-29`'s "confined to the returned response graph"
  would narrow to "confined to one thread"; the abandoned-`Fiber` `ensure` is real and is *not* what decides
  it. Interim note in `docs/deviations.md`. Touches `SEAM-11`, `TRANSPORT-25`, `TRANSPORT-19`, `TRANSPORT-29`,
  `IO-41`, `BODY-15`, `HTTP-43`.
- **`Net::HTTP` has a built-in automatic retry that is on by default, and §3.2, §11.18 and §12 all record that
  it has none.** §3.2 says "The reference transport disables nothing for **TRANSPORT-1**/**TRANSPORT-2**
  because `Net::HTTP` follows no redirects and retries nothing on its own — those two requirements are vacuous
  for this adapter"; §11.18 says "`Net::HTTP` has no resend hook"; §12's `TRANSPORT` row lists `TRANSPORT-1`,
  `TRANSPORT-2`, `TRANSPORT-8` and `TRANSPORT-18` as "adapter-scoped and vacuous for `Net::HTTP`", and the
  MUST-level summary counts `TRANSPORT-2` and `TRANSPORT-18` among the eight MUSTs that hold vacuously. The
  redirect half is right; **the retry half is false.** Verified on `net-http` 0.6.0 under Ruby 3.4.10:
  `Net::HTTP#max_retries` **defaults to 1**, and `#transport_request` retries when
  `count < max_retries && IDEMPOTENT_METHODS_.include?(req.method)` on `Net::ReadTimeout`, `IOError`,
  `EOFError`, `Errno::ECONNRESET`, `Errno::ECONNABORTED`, `Errno::EPIPE`, `Errno::ETIMEDOUT`,
  `OpenSSL::SSL::SSLError` and `Timeout::Error`, where `IDEMPOTENT_METHODS_` is
  `["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]`. The retry re-runs `req.exec`, so it re-writes the
  request body, and PUT and DELETE are both in the set. Three consequences, none cosmetic: a pipeline that
  believes it is the single retry authority (`TRANSPORT-2`, `PIPE-2`) is not; a single-use body could be
  written twice (`TRANSPORT-17`); and a cancellation delivered by closing the socket under a blocked read
  surfaces as `IOError`, which is **on the rescue list**, so the library would swallow and retry a caller's
  cancellation (`TRANSPORT-3`). Phase 8a's design measured the third end to end rather than reading it out of
  a rescue list: against a server whose first connection hangs, with a second thread calling `conn.finish`
  250 ms in, the call **returned `200`** at the default `max_retries` and raised
  `IOError: stream closed in another thread` at `0` — so the swallow is observed, not inferred. Two clauses
  bound the hazard without removing it — `rescue Net::OpenTimeout; raise` means a connect timeout is never
  retried, and `count = max_retries` inside the `reading_body` block closes the window once the response head
  is read — and neither helps the connect-and-head phase, which is where a cancel lands. **The correct
  statement:** §12's `TRANSPORT` row and its MUST-level count stop recording `TRANSPORT-2` as vacuous for this
  adapter, and §3.2's and §11.18's sentences follow. **Code half:** one line, `http.max_retries = 0`, which
  phase 8a writes, its checklist stating the corrected reason. Interim note in `docs/deviations.md`. Touches
  `TRANSPORT-2`, `TRANSPORT-3`, `TRANSPORT-17`, `TRANSPORT-18`, `RETRY-13`, `PIPE-2`, `XCUT-4`.
- **`TRANSPORT-14`'s malformed-inbound-header-*name* clause is unreachable on
  `dexpace-transport-async_http`, and §12 records `TRANSPORT-14` as satisfied without qualification.**
  `TRANSPORT-14` (MUST): "Inbound response headers MUST be copied leniently enough that a single malformed
  header does not fail the whole response: a control byte in a value, **or a control/non-ASCII byte in a
  name**, MUST drop only that header (logged at verbose) while the body and remaining headers are still
  delivered." Verified 2026-09-11 against `protocol-http1` 0.41.0 under Ruby 3.4.10, driving a raw `TCPServer`
  that emits `X-B\xE9d: v`: the client raises
  `Protocol::HTTP1::BadHeader: Could not parse header: "X-B\xE9d: v"` out of the **read**, so no response
  object exists and the adapter has nothing to drop from. The other two clauses hold — an obs-text byte in a
  value came back as `["X-Obs", "caf\xE9"]` (both `ASCII-8BIT`), and a control byte in a value came back
  intact for the adapter to drop. The phase-8 charter's fact 6 measured `Net::HTTP` doing the opposite, it
  *preserves* a non-ASCII name as a key, so the requirement is satisfiable on one MVP adapter and not the
  other — the per-transport scoping §17's own preamble anticipates and which neither §12 nor §9.3 records for
  this ID (§9.3 scopes only `TRANSPORT-8` and `TRANSPORT-18` that way). The only route to satisfying it would
  be to parse the response head off the socket before `protocol-http1` does, i.e. to reimplement the HTTP/1.1
  response parser inside an adapter whose whole design is to be thin over one library. **The correct
  statement:** §12's `TRANSPORT` row gains `TRANSPORT-14` to its adapter-scoped list. **Code half:** phase 8c
  records deviation `P8-38` and the conformance run carries a **named waiver listing `TRANSPORT-14`** per
  §9.3's mechanism, so the gap is reported rather than restated. Interim note in `docs/deviations.md`. Touches
  `TRANSPORT-14`, `XCUT-18`, `HTTP-17`, `NFR-8`.
- **`TRANSPORT-8` is satisfiable on `dexpace-transport-async_http`, and §12 counts it among the eight MUSTs
  that hold vacuously — the inverse direction, and equally a defect.**
  `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:41` lists "TRANSPORT-1, TRANSPORT-2,
  TRANSPORT-8 and TRANSPORT-18 … adapter-scoped and vacuous for `Net::HTTP`", and the MUST-level summary at
  `:49-55` counts `TRANSPORT-8` among "eight [that] hold vacuously". §9.3 is more careful —
  "**TRANSPORT-8** and **TRANSPORT-18** vacuous for `Net::HTTP` and **mandatory for any adapter whose client
  has those paths**" — and the corpus carries that as `testing/9a56af9d`. Verified 2026-09-11 against `async`
  2.45.1 and `async-http` 0.104.0 under Ruby 3.4.10: cancelling a **parent** `Async::Task` delivers
  `Async::Cancel` into an in-flight child exchange while the SDK future is still live — measured event
  sequence `["outer-saw:Async::Cancel", "inner:Async::Cancel", "inner-ensure"]` — which is exactly
  `TRANSPORT-8`'s antecedent, "a cancellation that originates inside it (e.g. an internal cancel-all)", and is
  the ordinary shape of a consumer whose supervisor cancels its children on shutdown. The requirement's second
  clause is free here, because `async` puts the two exceptions in different halves of the tree —
  `Async::Cancel < Exception` and `Async::TimeoutError < StandardError` — so the terminal-versus-retryable
  discrimination is by class and never by message (`XCUT-2`). Two candidates were tested and **rejected** as
  the antecedent: a graceful HTTP/2 GOAWAY mid-stream did not abort the open stream (the client read it to
  completion), and `Protocol::HTTP::RefusedError` is a retryable transport failure rather than a cancellation.
  **The correct statement:** §12's `TRANSPORT` row and its MUST-level count record `TRANSPORT-8` as satisfied
  on the async adapter. **Code half:** phase 8c implements and asserts the discrimination, its checklist row
  stating it. Interim note in `docs/deviations.md`. Touches `TRANSPORT-8`, `TRANSPORT-3`, `TRANSPORT-4`,
  `XCUT-2`, `ASYNC-6`, `NFR-8`.
- **§8.3's prohibition is absolute and `net-http`'s connect phase uses `Timeout.timeout`, which the cop that
  enforces the ban cannot see.** `/usr/lib/ruby/3.4.0/net/http.rb:1657` is
  `s = Timeout.timeout(@open_timeout, Net::OpenTimeout) { TCPSocket.open(conn_addr, conn_port, @local_host, @local_port) }`.
  §8.3 states the ban as binding "every gem in this repository" and phase 0 mechanises it as
  `Dexpace/NoThreadInterrupt` over this repository's own `lib/`, so a library **dependency** using the
  primitive is outside both the words and the scan. The hazard §8.3 names — an asynchronous interrupt landing
  "inside an `ensure` block that is releasing a pooled connection" — is **not** reachable through this
  particular use: the interrupt can only land during `TCPSocket.open`, before any SDK object holds a socket,
  and the library converts it into a typed `Net::OpenTimeout` rather than letting a bare `Timeout::Error`
  escape. So the port's guarantee is narrower than §8.3's sentence and is still true of everything it claims.
  It is worth the row because the sentence is absolute, because a reader auditing the ban will grep `lib/` and
  find nothing, and because the same question is owed of `async-http`'s dependency closure. **The correct
  statement:** §8.3 gains one clause scoping the prohibition to code this repository writes. **Code half:**
  none is owed — the cop and the ban stand as written. Touches `ASYNC-3`, `PIPE-33`, `XCUT-13`,
  `TRANSPORT-4`, `NFR-2`.
- **Phase 5a's exclusions table hands proxy use to phase 8 under two requirement IDs that are about
  something else, and it is the second document to make that substitution** *(added 2026-09-13, phase 8a
  review)*. The row reads "`TRANSPORT-3`, `TRANSPORT-8` — proxy *use* and header-drop reporting on a real
  adapter | 8. 5a ships `CFG-22`–`CFG-28`'s proxy **model and resolver**; nothing in core opens a socket"
  (`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md:255`). Neither ID is about
  either subject: `TRANSPORT-3` is "on the synchronous send path a genuine caller-initiated cancellation
  MUST surface as a terminal, non-retryable interrupt-shaped IOException", and `TRANSPORT-8` is a
  cancellation "that originates inside" the native client. The IDs the row means are **`TRANSPORT-30`**
  (the proxy requirement, whose own text opens "When the SDK's proxy configuration carries a feature the
  native client cannot honor") and **`TRANSPORT-13`** (the header-drop logging policy, which is phase 8c's).
  This is the **same substitution** the phase-8 segmentation design already corrected in phase 5b's
  `OBS-19` condition — "phase 8, at the first adapter that drops a caller-set header rather than raising on
  it — which is `TRANSPORT-8`'s subject" — so two phase-5 documents made one error the same way, which is a
  pattern rather than a slip. **The correct statement:** the phase-5a row names `TRANSPORT-30` and
  `TRANSPORT-13`, corrected in place with the correction stated, in the shape phase 5b's was. **Code half:
  already owned** — phase 8a's `R17` and its plan Task 19b implement proxy use, wire
  `Dexpace::Proxy.resolve` into the per-call client and disposition `TRANSPORT-30`, so nothing waits on
  this row; what is wrong is only the pointer a later audit would follow. Touches `TRANSPORT-3`,
  `TRANSPORT-8`, `TRANSPORT-13`, `TRANSPORT-30`, `CFG-22`–`CFG-28`, `OBS-19`.
- **§9.3 calls Minitest a default gem; it is a bundled gem, and §2.4 is built on exactly that
  distinction.** §9.3's argument for choosing Minitest over RSpec is that "**it ships with the interpreter as
  a default gem**, so the same argument §2.4 makes about `base64` and `logger` applies to the test
  framework". Verified on 3.4.10: `Gem::Specification.find_by_name("minitest").default_gem?` is **`false`**,
  its gem directory is not the interpreter's, and `Gem::BUNDLED_GEMS::SINCE` does not name it either, because
  that table lists only gems that *became* bundled at a known version and Minitest was never a default gem.
  Minitest is **bundled** — available with the interpreter, and requiring an explicit `Gemfile`/gemspec entry
  under Bundler, which is the very property §2.4 spends a page warning about. **The conclusion survives
  unchanged**, which is why this is a correction and not a re-decision: an adapter author can still run the
  suite with nothing extra installed, and `dexpace-conformance` still declares nothing, because 8a's two
  drivers reference `::Minitest` and `::RSpec` at call time and `require` neither. **The correct statement:**
  §9.3 calls Minitest a bundled gem and draws the same conclusion from it. **Code half:** phase 0's plan
  Task 2 carries the root `Gemfile`'s explicit `minitest` line — and, since 2026-09-13, its `~> 5.25` pin,
  which the Minitest-6 measurement forced. Touches `NFR-2`, `NFR-17`, `SEAM-1`.
- **§9.3 fixes the requirement ID as the *waiver's* unit and leaves the *report's* unit unstated, and an
  appendix-B item cannot be it.** §9.3 reads: "A failing **item** that the port has decided not to satisfy is
  reported as a failure by the suite and suppressed in the port's own build through a named waiver listing
  **the requirement ID**." The waiver half is settled; what is unstated is the unit the report prints a status
  *for*, which the surrounding sentence implies is the item. It cannot be: phase 8a's protocol makes
  `Assertion` carry a **list** of requirement IDs and `Result` carry **one** status, and an appendix-B item is
  one `- [ ]` bullet naming up to a dozen IDs. `B.7`'s second item is the decisive case, and §9.3 itself
  creates it: the bullet reads "Two-mode cancellation with queued/finished tasks never interrupted
  (`ASYNC-3`); ordered interrupt delivery prevents pooled-thread poisoning under stress (`ASYNC-4`)", and §9.3
  then requires `ASYNC-4` to be **vacuous by construction** and `ASYNC-3`'s item to be **recorded as failing
  rather than vacuous** — one `Result` cannot be both, so no single result can represent that item. **The
  correct statement:** one clause in §9.3 naming the requirement ID as the unit of both the waiver and the
  report. **Code half:** phase 9 resolves it for this port as `P9-8` — the suite's unit is one assertion per
  requirement ID; an appendix-B item is a many-to-one view over them, and its status in the coverage map is
  the worst among its assertions with every contributing status listed — and the 61-row map phase 9 commits is
  the only place the real mapping is written down, which is why a porter reading §9.3 alone still builds the
  wrong granularity. Interim note in `docs/deviations.md`. Touches `NFR-17`, `ASYNC-3`, `ASYNC-4`.
- **Nothing in the MVP constructs or promotes an execution context, so `CTX-16`'s operation name never
  reaches the tracing seam it is defined to label.** Phase 4a ships the whole promotion chain — 20 `CTX` IDs,
  three flavours, the bounded store — and `CTX-16` makes the operation name "a schema-defined operation id
  such as 'GetUser'" that is "exposed to the tracing seam to label the operation", which is exactly what an
  OpenAPI generator fills from `operationId`. **No phase in the roadmap builds a call path that creates or
  promotes a context.** Verified 2026-09-13 by repository-wide grep over `docs/work/mvp/`: outside phase 4a's
  own documents, `DispatchContext`, `promote_to_request` and `promote_to_exchange` appear in **no** phase
  plan at all. Phase 4a's charter states the same property from the other side and treats it as a feature —
  "`CTX` is consumed by nothing in `RECOV` or `PIPE`" — and `4c` says "4c does not consume 4a at all". The
  consumers that do exist cannot reach one: phase 5b's `Dexpace::Instrumentation::Step` resolves its tracer
  factory and its operation name through `bundle_for(request)` and `operation_name_for(request)`, both of
  which probe `request.respond_to?(:context)` while `Dexpace::Request`'s members are
  `(:method, :url, :headers, :body)`, so both always take their fallback, and `PIPE-11` forbids the ambient
  route. Phase 6a's Task 8 closes **half** of it — `Cursor#bundle` seeded by a `bundle:` keyword on
  `Pipeline#call`/`AsyncPipeline#call` — and a `Bundle` carries no operation name, so `SEAM-28`'s identifier
  half stays unreachable after it lands; phase 7a separately rules the context out of the serde seam, for
  its own good reasons. The result is conforming — ch.07 never asks the pipeline to own the chain and ch.08
  names no `CTX` ID — and it is a purpose-fit gap rather than a spec gap: a generated client gets a
  correlation model it must drive by hand, and `ContextStore`'s cap, `CTX-19`'s reachability and `CTX-9`'s
  eviction are exercised only by tests. **The correct statement:** phase 4a's forward-obligations row now
  says phase 5c, Task 4 consumes `RequestContext#operation_name` **as a signature** and that no wired path
  delivers it; what is still unowned is the decision itself — whether v1 carries the operation name on the
  call path (a `Cursor#operation_name` beside phase 6a's `Cursor#bundle`, or an `operation_name:` keyword on
  `Pipeline#call` threaded into `Instrumentation::Step`), or whether driving the chain is documented as the
  SDK author's job in `docs/sdk-documentation/`. **Code half:** none written; phase 6a, Task 8 is the file
  and the widening shape either answer extends (`api-design/1d9e6e0b`, so `NFR-4` permits it). Touches
  `CTX-14`, `CTX-16`, `SEAM-28`, `OBS-34`, `PIPE-11`, `NFR-4`.
- **`PAGE-14` and `SSE-26`/`SSE-40` guard the identical single-use latch with two different error families,
  and the divergence has to be settled before `NFR-4` locks either.** Phase 7's own segmentation design pairs
  them — "**`PAGE-14` and `SSE-26`'s single-use guards are two flags on two objects**"
  (`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md:891`) — and the two
  sub-phase designs then answer the same question differently: `7c` raises `Dexpace::InvalidArgumentError` on
  a second `Pages#each` (`docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md`, *`Dexpace::Page::Pages`*),
  while `7b` ships a purpose-built `Dexpace::SSE::StreamStateError` for the second view
  (`docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events-design.md`, its module layout).
  `Dexpace::InvalidArgumentError < ::ArgumentError`
  (`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md:313`), so the pagination spelling
  puts a **state** violation — no argument is involved, the object was simply used twice — into the argument
  family, where a caller rescuing `ArgumentError` around a page loop now catches it and a caller rescuing the
  SSE shape cannot use the same clause for both. Neither requirement names a type: `PAGE-14` says only
  "re-iteration MUST fail rather than silently restart" and `SSE-26` says "a second attempt MUST fail loudly
  (e.g. an **illegal-state error**)", whose own example is a state error. **The correct statement:** one
  error family for the single-use latch across both subsystems — the `SSE-26`-shaped state error, with
  `PAGE-14` raising it too, or one shared core type both namespaces use. **Code half:** one `raise` line in
  each sub-phase's view task — `7c`'s is Task 12 — plus its `sig/`, and it is cheap only before the `NFR-4`
  diff records two families. Touches `PAGE-14`, `SSE-26`, `SSE-40`, `NFR-4`, `SEAM-29`.

**From phase 10's own planning read** *(all eight added 2026-09-13)*. Phase 10's design ran the sweep this
list was built from rather than trusting the list, `grep -rn -i -e 'phase 10' -e 'phase-10' docs/work/`, and
read phase 9's plan against phase 9's design. Four subjects are handed forward by phases 0–8 and four by phase
9, and none of the eight was on this list. Each is written out in full below and dispositioned in phase 10's
design.

- **Appendix C's `SSE-19` row drops the port sanction the chapter carries, and `docs/product-spec/` is
  frozen.** Handed forward by 7b. `docs/product-spec/13-server-sent-events-and-streaming.md:33` ends
  `SSE-19` with "a port MAY add a configurable cap and reject/truncate oversized lines, **documenting the
  divergence**"; appendix C's row for the same ID ends at "a growable byte accumulator expands by doubling"
  and carries no sanction. `CLAUDE.md` calls appendix C "the fastest way to locate a requirement ID", so a
  checklist author working from the index alone reads 7b's cap as unsanctioned. The asymmetry runs both ways
  in the same pair: appendix C says "no maximum line **or event** size" where the chapter says only
  "lines/values", and `P7-21` turns on the appendix-C half — so **the two rows together are the only complete
  statement of `SSE-19` and nothing says so.** This is the first correction on this list against the
  **normative** specification rather than the design, so it is also a recommendation to the specification
  author in §11's own idiom. **Code half: already shipped** — 7b's configurable cap, `P7-21`. Interim note in
  `docs/deviations.md`. Touches `SSE-19`, `SSE-11`, `SSE-12`.
- **Phase 2's three other declared-and-unwritten `sig/` files, which no gate can see.** Handed forward by 7a,
  which settled one clause of one of them. `docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:4899-4900`
  (Step 6, "Write the four `sig/` mirrors", header at :4897)
  says `sig/dexpace/serde.rbs` "carries `interface _Codec` with the six methods and the module's class
  methods" and gives no types, and that step declares **four** files in all — `serde.rbs` plus three error
  files — so the residue beside `serde.rbs` is **three**, not four; corrected 2026-09-13, as is the line
  citation, which pointed at that plan's SPDX header; 7a's plan Task 12 declares `#media_type` as `(Dexpace::MediaType | String)`
  and hands forward the question of whether the other four declared files are empty too. A shipped `.rbs`
  that declares nothing passes `rbs validate`, passes `steep check` and tells a consumer's typechecker
  nothing, which is the failure mode `NFR-3` exists to prevent and which nothing reports. **Code half:
  partial** — `#media_type`'s only. Touches `SERDE-2`, `NFR-3`, `NFR-13`. [2026-09-20, 7a: premise false on
  the tree — all four phase-2 `sig/` files have carried real bodies since c881f92 (#44):
  `sig/dexpace/serde.rbs` declared `interface _Codec` at `Dexpace::_Codec` with all six methods typed, and
  the three error files declare `class Error < ::StandardError; include Dexpace::Error` and its two
  subclasses; 7a edited `_Codec` in place (`#media_type` to `(Dexpace::MediaType | String)`, `#load` over
  `Dexpace::Serde::_Witness`, `#dump_to` to `Integer`) rather than writing a second one, so there is no
  empty declaration to find and the "no gate can see it" hazard has no instance here; no action for
  phase 10.]
- **`Dexpace::Protocol.parse` has no alias for `"http/1.0"`, so a real `HTTP/1.0` response makes
  `ResponseMapper` raise.** Handed forward by 8a, measured at its plan `:233` and restated at `:4323`. Only
  `http/1.1`, `http/2` and `http/2.0` fold into a recognised wire form, so `native.http_version` produces
  `"1.0"` and the mapper raises. No `TRANSPORT` ID requires 1.0 support and every `WireServer` script in 8a's
  plan answers `HTTP/1.1`, so the suite never exercises it — and any real server can reach it. 8a routed it
  here rather than fixing it because widening `Protocol::WIRE_FORMS` is a **phase-1 surface decision no
  sub-phase should take alone**; the widening is additive, so `NFR-4` permits it. **Code half: none** — 8a
  records one sentence in `ResponseMapper`'s YARD. Touches `HTTP-24`, `HTTP-43`, `NFR-4`.
- **8a's forward-obligations row for the two declined `TRANSPORT` SHOULDs is half stale.** Handed forward by
  8a at its design `:2219`, the only literal `| **Phase 10**, …` row in any phase document, naming
  `TRANSPORT-28`'s third clause **and `TRANSPORT-30`**. `TRANSPORT-30` is no longer declined: 8a's own `R17`
  and plan Task 19b implement proxy use, and `docs/first-release.md` narrowed it out of the ships-without
  entry on 2026-09-13. A forward row handing a later phase a decision already taken spends the audit budget
  on rediscovery. **Fixed in this pass**, dated, in 8a's design. Touches `TRANSPORT-28`, `TRANSPORT-30`.
- **`APPENDIX_B.md`'s check 2 is weaker than the prose that specifies it.** Found by reading phase 9's plan
  against phase 9's design. The design settles on **per-row ID-set equality** against the set parsed from each
  appendix-B item's own text — "decidable, strictly stronger, and it makes the distinct-ID coverage check hold
  **by construction**" (its design:1243-1245) — and the filed test (**phase 9 plan:5627-5631**, in the class
  at :5611-5644) asserts only that every row names at least one ID from the nineteen prefixes. `AppendixB`
  is not featureless here: it exposes `ids_in(text)` (:5668) and `spec_items(path)` (:5732-5741) and
  computes each item's IDs inside `generate` at :5722; what it lacks is an accessor **in the form the
  equality check needs**, per section and index, plus the assertion — and because `generate` carries
  hand-written rows over verbatim (:5726), the drift the check would catch is confined to those. Both the
  line citation and the size of the claim corrected 2026-09-13. So the 61-row map documents a check it does not perform, in the artifact that is "the only place
  the real mapping is written down". **Code half: none** — the accessor does not exist. Touches `NFR-17`.
- **`TransportSuite` is not on `Runner`, leaving two status-deciding paths in one gem.** Phase 9's `P9-10`
  records it and its reason: phase 8 owns that file, so phase 9 deliberately did not refactor it, and "a
  future change to the five statuses must be made twice." Phase 10 is the first phase that owns every gem, so
  the reason has expired. **Code half: none.** Touches `NFR-17`, `NFR-4`.
- **A design document that promised a shape the code did not take is phase 10's doc repair.** Phase 9's `R3`
  (its design:536-542) fixes the rule for the requirement half — assert against what arrived, record both
  shapes — and routes the document half here: "a document the next reader will trust wrongly". It is a
  **method rather than a subject**, which is why it is written out: phase 10's audit tasks each route their
  own instances, and a bullet that named none would read as though none existed. Touches every `XCUT`/`NFR`
  subject phase 9 probed.
- **The `minitest` pin's ownership.** Phase 9's own open question 1: the pin is phase 0's artifact and `R6`
  makes a repair to phase 0's tree phase 10's, so "the decision may not be phase 9's at all". Phase 10
  re-measured and the answer is that **the pin is right and its owner does not change** — what is owed is the
  corrected measurement, because two of the three per-interpreter versions phase 9 recorded are stale and the
  3.4 row is now affected in a different way from the 4.0 row. Carried to
  `docs/first-release.md` § Post-release triggers, the Minitest 6 entry, dated. Touches `NFR-6`, `NFR-17`,
  `NFR-10`, `NFR-2`.
- **The process tooling is outside the RuboCop baseline.** Found by phase 0's implementation on 2026-09-14,
  the first time `rubocop --fail-level=convention` ran against the whole tree: 303 of the 310 findings were in
  the four pre-existing files under `scripts/` — the knowledge CLI, its structure and drift verifiers and their
  test — against 7 in everything phase 0 wrote, and the hidden `.claude/skills/housekeeping/` tree was never
  inspected at all. Neither ships in a gem, both carry their own `ruby -w` suites, and both predate the
  baseline, so phase 0 excluded `scripts/**/*` and `.claude/**/*` in `.rubocop.yml` as `NFR-7`'s
  narrowly-scoped, documented exception, with the re-enable condition beside it (design ledger row P0-11).
  The exception is not a phase's product to close and no build phase's scope reaches it; bringing the tooling
  under the baseline is a change of its own — a `rubocop --autocorrect` pass over four files plus the
  findings that are not autocorrectable, including two `Dexpace/NoLocaleCaseFold` and two
  `Dexpace/NoKeywordSplat` hits — reviewed as such, after which the two `Exclude` lines are deleted.
  **Code half: the two lines and the four files.** Touches `NFR-7`, `NFR-13`. Added after phase 10's
  planning pass, so it is the thirty-third bullet and is not yet in its design's disposition table; phase 10
  dispositions it at execution.
- **`rake rubocop` passes vacuously in a worktree nested under the parent checkout's `.claude/`.** Found by
  phase 1's implementation on 2026-09-14, the first time the gate ran from such a worktree: RuboCop takes
  `AllCops/Exclude` from the topmost `.rubocop.yml` on the path — here the parent checkout's, whose
  `.claude/**/*` line (the P0-11 exception above) contains the whole worktree — so `bundle exec rake rubocop`
  inspected 8 files of 126 and reported no offenses on a tree that, inspected honestly with
  `--ignore-parent-exclusion`, had two. CI and a plain checkout have no parent `.rubocop.yml` and are
  unaffected; the exposure is the agent worktree layout this repository actually uses. The repair is one
  token in the strict direction — `--ignore-parent-exclusion` on the gate's command in `tasks/quality.rake`,
  with `test/gates/rubocop_config_test.rb` asserting it — and it is a change to a phase-0 gate, so it is
  phase 10's. **Code half: the one flag and its assertion.** Touches `NFR-7`, `NFR-17`. Added after phase
  10's planning pass, so it is the thirty-fourth bullet and is not yet in its design's disposition table;
  phase 10 dispositions it at execution.
- **Nine later-phase design documents cite a retired corpus key, `data-modeling/5bc538ba`, as narrowing the
  wire model's Ractor-shareability claim.** The phase 3, 4, 5 and 7 segmentation designs and the 4a, 4b, 5a,
  5b and 8a designs each lean on that note — "`data-modeling/5bc538ba` narrows the shareability claim" — and
  on phase 1's ledger row `P1-9`. Phase 1's build reversed both on 2026-09-15: `Request` and `Response` are
  `Ractor.shareable?` as built, `P1-9` is retired for `P1-13`, and the planning-time note is rewritten as built
  under `## Conflicts` in `docs/knowledge/notes/data-modeling.md` (key digested from the new text; the old key
  resolves to nothing, which is what `scripts/knowledge.rb --key` reports). Every one of those phases re-reads
  the notes at its start, so none is misled at execution; what is stale is the prose of nine already-planned
  documents, which is audit work against planned phases and therefore phase 10's. **Documentation half only:
  repoint each citation and reword each sentence to the as-built claim.** Touches `HTTP-1`, `XCUT-15`. Added
  after phase 10's planning pass, so it is the thirty-fifth bullet and is not yet in its design's disposition
  table; phase 10 dispositions it at execution.
- **`Dexpace::URL.parse!` accepts a host-less `http:` and any absolute non-HTTP URI, so a `Request` can carry a
  URL no transport can dispatch, and nothing owns the rejection.** Found by the round-3 review of phase 1's
  stack on 2026-09-15: `URI::Generic#absolute?` is only "a scheme is present", so `URL.parse!("http:")`
  yields a `URI::HTTP` with a `nil` host and `URL.parse!("mailto:x@y")` a `URI::MailTo`, while `"/rel"` and
  `"example.test/a"` are correctly refused. `HTTP-47`'s letter — malformed or non-absolute — is met; its
  rationale, failing at construction "rather than surfacing a lower-level or transport-specific error later",
  is not, for those two shapes, which today surface as whatever `Net::HTTP.new(nil, …)` raises inside phase
  8a's `Adapter`. Phase 1 changed nothing: which schemes and shapes are dispatchable is a transport's
  knowledge, not the wire model's, and the two candidate owners are both already planned — phase 8a's
  `RequestMapper` and `Adapter` (Tasks 16 and 19,
  `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance.md`), where a
  `TransportError` naming the URL would be the natural shape, or `URL.parse!` itself if a
  transport-independent "http or https with a host" rule is preferred and recorded against `HTTP-47`.
  **Code half: one check in one of those two places, with its negative tests; documentation half: the
  choice, in the owning phase's checklist row.** Touches `HTTP-47`. Added after phase 10's
  planning pass, so it is the thirty-sixth bullet and is not yet in its design's disposition table; phase 10
  dispositions it at execution.
- **`MultipartBody` refuses a non-ASCII part name or filename, because its part-header sweep is the outbound
  header grammar.** Found by phase 3b's implementation on 2026-09-16. Phase 3b's design has every assembled
  part-header line swept by phase 1's `HeaderSyntax.valid_outbound_value?` "as a second, whole-line sweep",
  which admits HTAB and printable ASCII only, so a `MultipartBody::Part` named `"résumé"` or with filename
  `"résumé.pdf"` raises `Dexpace::InvalidArgumentError` at write time and the caller must percent-encode
  first — RFC 7578 §4.2's own recommendation, while browsers send raw UTF-8 in that position. `HTTP-51`'s
  one MUST (a quote, a CR or an LF must not break the framing) is met either way; the question is whether the
  sweep should admit obs-text at or above `0x80` in a *multipart part header*, which is body bytes and not an
  HTTP header, and phase 1's inbound grammar (`HeaderSyntax.valid_inbound_value?`) already exists for exactly
  that shape. A widening that cannot break `NFR-4`. **Code half if taken: one predicate swap in
  `MultipartBody#sweep!` with a non-ASCII filename test; documentation half: `docs/sdk-documentation/body.md`'s
  multipart section and 3b's checklist row.** Touches `HTTP-51`. Added after phase 10's planning pass, so it
  is the thirty-seventh bullet and is not yet in its design's disposition table; phase 10 dispositions it at
  execution.
- **Phase 0's plan says the keyword-splat cop "carries no ordinal" and that phase 4a's cop is "the seventh";
  every as-built document counts it and calls phase 4a's the eighth.** Found 2026-09-16 by phase 4a's
  implementation. Phase 0's plan, Task 4 amendment of 2026-09-13 numbers the original five, calls phase 2's
  `Dexpace/QualifiedCoreConstant` "the sixth" and phase 4a's `Dexpace/NoWeakReferences` "the seventh", and
  says `Dexpace/NoKeywordSplat` is "named and never counted"; phase 0's own design table repeats it. On
  `main`, `CLAUDE.md`, `docs/sdk-documentation/quality-gates.md`, phase 2's checklist and
  `.rubocop/test/cops_test.rb`'s head comment all count the splat cop and call `QualifiedCoreConstant` the
  seventh, so phase 4a built and documented its cop as the **eighth** and did not edit phase 0's record.
  **Documentation half only:** phase 0's plan and design are that phase's records and only an audit pass
  rewrites them; the one true count is eight, and phase 0's two sentences should say so or say why the
  ordinal is retired. Touches no requirement ID. Added after phase 10's planning pass, so it is the
  thirty-eighth bullet and is not yet in its design's disposition table; phase 10 dispositions it at
  execution.
- **`Fiber[:k] = nil` retains the key with a `nil` value on Ruby 3.2, and `Fiber["k"]` raises `TypeError`
  on 3.2 and 3.3 — two carrier facts the phase-5 documents and phase 8b's plan state as facts of the
  range that are facts of 3.3+ and 3.4+ respectively.** Found 2026-09-17 by phase 5c's implementation,
  the first to run the charter's fact 1 and 5c's facts 3 and 4 on 3.2.11 and 3.3.12 (the charter and both
  designs ran 3.4.10 alone and said so). Measured: after `Fiber[:k] = "v"; Fiber[:k] = nil`,
  `Fiber.current.storage.key?(:k)` is `false` on 3.3.12, 3.4.10 and 4.0.6 and `true` on 3.2.11, where the
  floor's whole `Fiber` API is `[]`, `[]=`, `storage` and `storage=` and the only removal is the warned
  whole-map setter; `Fiber["k"] = 1` interns on 3.4.10 and 4.0.6 and raises on 3.2.11 and 3.3.12.
  Phase 5c built on it as measured — its per-key restore stays branchless, the floor's residual is a
  present-and-`nil` key that `Fiber[]` and `OBS-10`'s null-skip both read as absent (its as-built row
  `P5-72`, and the corpus note `docs/knowledge/notes/observability.md`, marker
  `sha:manual-phase5c-fiber-nil-and-string-key-floor`) — and neither 5b's nor 8b's plan is edited from
  5c. What is stale is prose: 5b's `P5-23` union restore and 8b's `ASYNC-9`/`ASYNC-11` pooled-worker
  restore are written on "`= nil` deletes", and on the floor each returns a worker to a map of nil-valued
  keys rather than an empty one — indistinguishable at every reader that skips nulls and visible only
  through `Fiber.current.storage` itself. Both phases re-read the notes at their start, so neither is
  misled at execution. **Documentation half only: the two plans' sentences and the charter's fact 1, to
  the as-built range.** Touches `OBS-10`, `OBS-23`, `OBS-24`, `ASYNC-9`, `ASYNC-11`. Added after phase
  10's planning pass, so it is the thirty-ninth bullet and is not yet in its design's disposition table;
  phase 10 dispositions it at execution.
- **Phase 5b's design states two verified facts that the as-built code no longer rests on: fact 6's
  rebuild route (`u.userinfo = "***:***"` and `#to_s`) and fact 13's "`Async::Future` offers `#on_settle`
  and no combinator".** Found 2026-09-17 by phase 5b's implementation. Measured on 3.2.11, 3.3.12, 3.4.10
  and 4.0.6: `URI::RFC3986_PARSER.parse("http://h:80/").to_s` is `"http://h/"` — `URI#to_s` drops a
  default port, which `OBS-14` forbids ("scheme, host, port and path MUST be preserved") — so the built
  redactor reassembles from `RFC3986_PARSER.split`'s nine raw components and assigns no component at all
  (5b's as-built row `P5-91`); the design's fact 6 and the mechanism it gives `P5-27` ("never assigns a
  component that was absent", stated against the setters' opaque-URI raise) describe a route not taken,
  and the raise they guard against is unreachable by construction. And phase 4c added `Future#then` and
  `AsyncPipeline.map_response` after the design was written, on which the async step's body level now
  rests (`P5-94`); fact 13's "no combinator" licensed a same-future shape that holds below `BODY` only.
  Neither is a corpus fact — both are the design's own — so no note is filed, and the design's ledger
  addendum records both beside the facts they correct. **Documentation half only: the two facts and
  `P5-27`'s mechanism sentence, to the as-built route.** Touches `OBS-14`, `OBS-15`, `OBS-36`. Added
  after phase 10's planning pass, so it is the fortieth bullet and is not yet in its design's disposition
  table; phase 10 dispositions it at execution.
- **The warnings-fatal gate runs every gem suite in one process, and Ruby 3.4+'s unused-block warning
  is suppressed process-wide once any same-named method that takes a block has been compiled — so the
  gate cannot see the warning on a method that declares no block and is called with one.** Found
  2026-09-17 by phase 5b's implementation, running each instrumentation suite alone under `ruby -w`:
  `NullSink#debug` and its three siblings, written as `def debug(message = nil)` with "the block never
  evaluated", warn "the block passed to 'Dexpace::Instrumentation::NullSink#debug' may be ignored" on
  3.4.10 and 4.0.6 (not on 3.2.11 or 3.3.12) when `null_sink_test.rb` runs alone, and never under
  `test:gems`, where `RecordingSink`'s block-taking `debug` is compiled first. Measured on all four
  interpreters: an anonymous `&` parameter that is never referenced materialises no Proc (0.0 objects
  per call), `block_given?` in the body does not count as use, and `-W:strict_unused_block` is the
  category that would warn regardless. Phase 5b fixed its four writers (an anonymous `&`, documented
  in `null_sink.rb`). **What is open is the gate's reach**: `tools/suite_runner.rb` could run with
  `-W:strict_unused_block` added to `RUBYOPT`, or run each suite file in its own process, and either
  is a change to phase 0's gate that `test/gates/` would have to prove against a fixture. Touches
  `NFR-6`, `OBS-1`. Added after phase 10's planning pass, so it is the forty-first bullet and is not
  yet in its design's disposition table; phase 10 dispositions it at execution.
- **Four phase-3b and phase-4b tests assert the default materialisation ceiling and read the live one,
  so an exported `MAX_MATERIALIZED_BYTES` fails them.** Found 2026-09-17 by phase 5b's implementation,
  running the whole core suite with the configuration environment exported to hostile values
  (`MAX_MATERIALIZED_BYTES=4096`): `DexpaceBodyTest::BufferBoundedHandlesTest` "clamps a cap above the
  ceiling down to it", `DexpaceBodyTest::BufferBoundedTest` "over a body larger than the cap, stops
  reading", `DexpaceResponseBodyTest::PreviewTest` "the clamp is applied before the first read" and
  `DexpaceRecoveryTest` "buffer_error_body truncates at MAX_BUFFERED_ERROR_BODY_BYTES" compare against
  `IO::MAX_MATERIALIZED_BYTES` while the code reads `Dexpace::IO.max_materialized_bytes` per call
  (5a's P5-56). Phase 5a's review round 0 (R0-7) repaired the same ambient reading in 5a's own ceiling
  and cap suites and did not reach these four, written before the ceiling was configurable. The
  repair is the same as R0-7's — build the configuration under test over `FakeConfigSource` and pass
  it, or pin the slot with `Dexpace.configure` inside the test — and is audit work against phases 3b
  and 4b. Every phase-5b suite is hermetic under the same environment. Touches `IO-9`, `BODY-19`,
  `BODY-22`, `BODY-30`, `RECOV-16`, `CFG-11`. Added after phase 10's planning pass, so it is the forty-second
  bullet and is not yet in its design's disposition table; phase 10 dispositions it at execution.
- **Phase 6a's design describes an async retry pump that recurses, and states the opposite.** Found
  2026-09-18 by phase 6a's implementation. The design's `AsyncRetryStep` sketch re-arms by calling
  `pump.call(attempt + 1)` from inside the delay future's `on_settle` callback and its `RETRY-30`
  paragraph beneath says this "does not grow the Ruby call stack across retries"; measured on 3.2.11,
  3.3.12, 3.4.10 and 4.0.6, `Future#on_settle` runs its block inline on an already-settled future — which
  every scripted downstream and every zero-length `Async.delay` is — so the sketch grows the stack seven
  frames per attempt and raises `SystemStackError` at roughly 1,500 attempts, while the plan's 200-attempt
  `RETRY-30` test passed vacuously. The built driver is a re-arm-flag trampoline whose test measures
  `caller.size` flat across 2,001 attempts (6a's as-built `P6-54`); the design's sketch and paragraph are
  what phase 10 corrects, so neither 6b's nor 6c's async work copies them. The same read found the
  design's `R2` paragraph right for the wrong reason: `Async.delay`'s `SeamError` is raised synchronously
  and is caught by the fence around the *caller*, never by a callback's rescue. Touches `RETRY-30`,
  `RETRY-31`, `RETRY-33`. Added after phase 10's planning pass, so it is the forty-third bullet and is not
  yet in its design's disposition table; phase 10 dispositions it at execution.
- **After phase 6 the body-replayability predicate has three spellings, two of them public and
  `NFR-4`-locked.** Found 2026-09-18 by phase 6c's implementation, reading the three sub-phase designs
  side by side: 6a's plan writes `Dexpace::Resilience::Resend.eligible?(request)` for `RETRY-5`'s
  idempotency-and-replayability gate, 6b's writes `Dexpace::Resilience::Resend.replayable_body?(request)`
  for `REDIR-6`'s, and 6c — cut from `main` with neither present — ships `AUTH-31`'s gate as one private
  `Step#replayable?` that `AsyncStep` inherits, declining the design's public `Auth::Replayability`
  module so as not to add a third public name (6c's P6-80). 6b's and 6c's are one predicate under two
  names — no body, or a body answering `#replayable?` truthfully — and 6a's differs only for a body-less
  request, where `RETRY-7` asks the method's idempotency instead. Whether one public predicate serves the three call
  sites, and which name it keeps, is phase 10's consolidation to decide once 6a and 6b have landed and
  the two public spellings are in `sig/`; 6c's private method is the one that costs nothing to fold.
  Touches `RETRY-5`, `REDIR-6`, `AUTH-31`, `NFR-4`. Added after phase 10's planning pass by phase 6c
  and referred to by date and content, never by ordinal, because phase 6a's lane is adding bullets to
  this list at the same time; it is not yet in phase 10's design's disposition table, and phase 10
  dispositions it at execution.
- **An explicit scheme-default port is elided at phase 1's model boundary, and a redirect target
  inherits it.** Found 2026-09-19 by phase 6b's implementation, re-running its `Location` facts on every
  interpreter: `URI#to_s` drops an explicit `:443` on `https` and `:80` on `http` on every supported
  Ruby, and phase 1's `Dexpace::URL.parse!` re-parses a URI argument from its text (XCUT-15's reason: a
  `dup` would alias the caller's component Strings), so `Location: https://h:443/y` reaches the wire
  as `https://h/y` — and so does a caller's own `Request.build(url: "https://h:443/y")`, which is what
  makes it phase 1's and not the redirect step's. `REDIR-13`'s "MUST preserve … explicit ports" holds
  for every non-default port and every IPv6 literal, the origin triple reads the parsed port and is
  unchanged, and 5b's redactor met the same elision (P5-91) and reassembles from the split components
  instead. Whether phase 1's model should keep an explicit default port in its external form — a
  `URL.parse!` that owns the components without `to_s`, and what `HTTP-46`'s textual comparison then
  says about `https://h:443/y` against `https://h/y` — is phase 10's `NFR-4`/`HTTP-46` audit to decide,
  since the answer changes what a caller's request renders and not only a redirect's. Touches
  `REDIR-13`, `HTTP-46`, `HTTP-47`, `XCUT-15`. Recorded as 6b's P6-96; added after phase 10's planning
  pass and referred to by date and content, never by ordinal; not yet in phase 10's design's disposition
  table, which dispositions it at execution.
- **After a mid-stream failure, `BufferedSource.over`'s enumerator restarts `#each` from its first
  chunk, so a further read re-delivers the body's first bytes rather than nil or a second failure.**
  Found 2026-09-20 by phase 7b's implementation, re-running its facts on every interpreter against a
  cross-check note that said the opposite ("the next `#getbyte` returns nil, the enumerator is
  finished"): on 3.2.11, 3.3.12, 3.4.10 and 4.0.6 alike, once an `Exception` escapes the `#each` an
  `Enumerator#next` drives, the enumerator's fiber is dead, the next `#next` creates a fresh one and
  `#each` runs again from its first entry — measured as `"d".ord` off a `ScriptedChunked` whose script
  was one event then a `StreamError`, and pinned in `gems/dexpace-core/test/dexpace/sse/matrix_facts_test.rb`.
  The SSE facade never meets it (`SSE-27`'s `closed?` check runs before every pull and the facade closed
  itself on the failure), a bare `Dexpace::SSE::Reader` driven again after a raise would, and so would
  any other consumer of a `.over` source that rescues a mid-stream error and reads on. Whether `.over`
  should latch exhaustion on a failure — `@dexpace_upstream_exhausted = true` in a rescue around
  `enumerator.next`, so a second read is EOF — or document the restart as `IO-1`'s "the source is not
  exhausted" read literally, is phase 10's `IO` audit to decide, since it changes what every `.over`
  consumer sees and not only the SSE reader's. Touches `IO-1`, `IO-16`, `IO-22`, `SSE-27`, `SSE-29`.
  Routed by 7b's checklist; referred to by date and content, never by ordinal; not in phase 10's design's
  disposition table, which dispositions it at execution.
- **The per-byte read path through `BufferedSource#getbyte` costs about 0.9 µs a byte, so the SSE line
  machine parses at roughly 1 MiB/s on 4.0.6.** Found 2026-09-20 by phase 7b's implementation, timing
  its at-scale cap battery: every `#getbyte` pays a `Closeable#closed?` mutex acquisition (`IO-38`,
  3a's P3-6, ~0.5 µs a call through `ensure_readable`) and a one-byte `String` allocation
  (`store_take(1).getbyte(0)`), and 16 MiB through `Dexpace::SSE::Reader` took 14 s on 4.0.6 and 21 s
  on 3.2.11 against 4.7 s over a plain duck whose `#getbyte` is three method calls. Phase 7b's design
  fixes `#getbyte` as the machine's primitive (P7-20, the `_ByteSource` interface) and the build kept it,
  moving only the two at-scale tests onto the duck. The lift is one of two: a `TypedReads#getbyte` that
  reads the head chunk in place without a slice, or a bulk path for the line machine (`read_into` into
  the line buffer, which puts a second accumulator under the source and changes P7-27's interface) —
  a performance decision across 3a and 7b, for phase 10's `IO` audit, with the numbers above as the
  baseline. Touches `IO-11`, `IO-38`, `SSE-2`, `SSE-39`. Routed by 7b's checklist; referred to by date
  and content, never by ordinal; not in phase 10's design's disposition table, which dispositions it at
  execution.
- **`gates:clean_bundle` installs into the interpreter's own gem directory, and the first adapter with a
  third-party dependency makes that a network fetch on two matrix rows.** Found 2026-09-20 by phase 7a's
  implementation, the first to run the gate against a gem whose gemspec declares a third-party gem
  (`json >= 2.19.9`). The gate's scratch `Gemfile` holds the adapter and core by `path:` and runs
  `bundle install --quiet` with no `--local` and no `BUNDLE_PATH`, so Bundler resolves `json` from
  rubygems.org into the running interpreter's gem directory whenever no installed `json` satisfies the
  floor — which on 2026-09-20 was true of 3.3.12 (default 2.7.2) and 3.4.10 (default 2.9.1), both of
  which now hold a downloaded json 3.0.2 they did not before the run, while 3.2.11 and 4.0.6 already
  held 3.0.2 beside their stock 2.6.3 / 2.18.0. Correct as the phase-0 gate's own behaviour (CI does the
  same) and permitted for that gate run alone, but a gate that writes into a developer's interpreter and
  needs the network on some rows and not others is a repair candidate: pin the scratch bundle's
  `BUNDLE_PATH` under a scratch directory (`Dir.mktmpdir` already holds the Gemfile) so the fetch lands
  beside the Gemfile and nothing outside the run changes. Phase 8a's Task 23 owns every edit to
  `clean_bundle_check` this wave and may fix it there, in which case this bullet is simply closed.
  Touches `NFR-1`, `NFR-2`, `NFR-10`, `NFR-12`. Recorded by 7a on its docs branch; referred to by date
  and content, never by ordinal. [closed by 8a's Task 23 on this tree, 2026-09-21: `clean_bundle_check`
  sets `BUNDLE_PATH` to a `vendor/` directory beside the scratch `Gemfile`, so the fetch lands inside the
  run's own `Dir.mktmpdir` and nothing outside it changes — run green for all six gems on 3.2.11, 3.3.12,
  3.4.10 and 4.0.6 by the reconciliation that landed 8a after phase 7]
- **`rbs_collection.yaml`'s header comment is stale: "json arrives with dexpace-serde-json's codec in
  phase 7", and phase 7a added no row.** Found 2026-09-20 by phase 7a's implementation and routed here
  by its review round 0 (R0-1): `json`'s signatures are rbs's own stdlib set — `rbs collection install`
  already resolves `json` with `source: type: stdlib` — and json 3.0.2 ships no `sig/`, so the codec's
  one `JSON::Coder` reference is settled in the Steepfile's `:serde_json` target and the collection file
  needs nothing from 7a. The file is a shared one outside 7a's bounds that phase 8a rewrites with its
  first row (`net-http`), so 7a's correction of the sentence was dropped rather than merged ahead of
  that row; whichever lane adds the first row rewrites the sentence and closes this bullet, and if none
  does before phase 10, the repair is a one-comment edit. No gate reads the comment. Touches nothing
  normative. Recorded by 7a on its docs branch; referred to by date and content, never by ordinal.
- **`net-http`'s connect-phase `Timeout.timeout` has an observable: the first connection in a process
  starts Ruby's process-wide `Timeout` thread, on the 3.2, 3.3 and 3.4 rows and not on 4.0.** Found
  2026-09-20 by phase 8a's implementation, running its adapter suite on every interpreter: below
  net-http 0.7 the connect is `Timeout.timeout(@open_timeout, Net::OpenTimeout) { TCPSocket.open(…) }`
  (the 2026-09-11 bullet above), and the first `Timeout.timeout` call anywhere in a process starts a
  singleton thread that lives for the process; on 0.9.1, the version 4.0.6 resolves, the connect is
  `TCPSocket.open(conn_addr, conn_port, open_timeout:)` and no thread starts. `DexpaceTestCase`'s
  teardown counts threads around every test, so the first test to connect on a 3.2, 3.3 or 3.4 row was
  charged with a thread it did not start and could not join — a red row the development interpreter never
  showed. Phase 8a parks it: `test/support/net_http_warmup.rb` opens one connection against a local
  `TCPServer` when either adapter gem's test helper loads, before any count is taken (8a's `P8-62`); the
  8c and 8b lanes' helpers, if they connect through `net-http`, must require it too. What is phase
  10's: the 2026-09-11 bullet's "**Code half:** none is owed" is still right about the ban and the cop,
  and its correct statement for §8.3 gains one clause — the dependency's primitive leaves a process-wide
  thread behind, which a host that counts threads will see once and never again. Touches `NFR-6`,
  `XCUT-11`, `XCUT-13`. Added after phase 10's planning pass by phase 8a and referred to by date and
  content, never by ordinal, because phases 7a, 7b and 7c are adding bullets to this list at the same
  time; not yet in phase 10's design's disposition table, which dispositions it at execution.
- **rbs 4.2.0 types `TCPServer#initialize` as `(?String host, Integer port)` — an optional positional
  before a required one — and Steep 2.1.0 refuses the two-argument call Ruby accepts.** Found 2026-09-20
  by phase 8a's implementation, running `steep check` over the conformance target for the first time:
  `TCPServer.new("127.0.0.1", 0)`, the one construction design §9.3's fixture needs, is reported as an
  arity error by the checker and by nothing at runtime, on every interpreter. `WireServer#initialize`
  routes the call through an `untyped` local (`server_class = ::TCPServer #: untyped`) with the reason
  in a comment, which is a relaxation inside one method rather than a named target relaxation in the
  `Steepfile`, so the target stays at `D::Ruby.default`. What is phase 10's: the `NFR-3` audit checks
  whether the rbs release the `rbs_collection.yaml` then resolves has corrected `stdlib/socket/0/
  tcp_server.rbs`, and removes the local when it has, or records the workaround in `docs/knowledge/notes/type-system.md`
  when it has not. Touches `NFR-3`. Added after phase 10's planning pass by phase 8a and referred to by
  date and content, never by ordinal; not yet in phase 10's design's disposition table, which
  dispositions it at execution.
- **Phase 6b's `REDIR-23` proof carries a ten-second wall-clock bound over 5,000 hops, and the bound
  fails under machine load while the stack-flatness half still passes.** Found 2026-09-20 by phase 8a's
  implementation, running `test:gems` on 4.0.6 while three other lanes ran their own gates on the same
  machine (load average above 10): `DexpaceRedirectStepTest::LifecycleTest` "a chain of 5,000 hops is
  followed iteratively -- flat on the stack, in under a few seconds" (`step_test.rb`) measured 10.6 s and
  12.6 s against its `assert_operator(elapsed, :<, 10.0)` in the 3,016-test process, and 8.8 s run alone
  under the same load; the same run on the same tree passed in 47 s total an hour earlier. The
  requirement's clause is "iteratively, without unbounded recursion", which the assertion's
  `depths.first == depths.last` comparison proves on its own and which phase 6a's `RETRY-30` test proves
  with `caller.size` and no clock; the clock bound is the "in under a few seconds" gloss and is the only
  load-sensitive assertion in the repository's suites. Phase 8a changed nothing in that file: it is
  6b's, and a bound loosened by the lane that happened to hit it would be a number with no reason.
  What is phase 10's: decide whether the bound goes — the flatness comparison is the proof — or becomes
  a per-hop budget measured against a warm-up drive, and apply the same reading to any wall-clock
  assertion its `NFR-6` audit finds. Touches `REDIR-23`, `NFR-6`. Added after phase 10's planning pass
  by phase 8a and referred to by date and content, never by ordinal; not yet in phase 10's design's
  disposition table, which dispositions it at execution.
- **Phase 6a's `RETRY-42` / `RECOV-28` eight-thread budget test is interleaving-dependent, and errors
  under the whole-repository process on a loaded machine.** Found 2026-09-20 by phase 8a's review round 1,
  on the same machine and under the same three concurrent lanes as the `REDIR-23` bullet above:
  `DexpaceResilienceRecoveryRetryTest` "RETRY-42 / RECOV-28: eight concurrent calls through one engine
  keep their budgets apart" (`recovery_retry_test.rb`) errored with `Dexpace::ProtocolError: HTTP 503` in
  two of five whole-process 3.2.11 `test:gems` runs pinned to net-http 0.4.1 (once in the code tip's
  matrix row, once in the docs tip's `SEED=31337` run), reran green with the same seed each time, and
  passed 70/70 alone and 5/5 in core's own `rake test`; every 4.0.6, 3.3.12, 3.4.10 and 3.2.11/0.9.1
  run passed. The fixture hands sixteen scripted responses (503 and 200 alternating) to eight threads in
  call order, so a thread switch landing between one thread's 503 and its retry hands that thread a
  second 503 and spends `max_retries: 1` — reachable only under the slower one-process coverage run
  and machine load, and a scheduling outcome rather than a seed's. The file and `RecoveryRetry` are
  byte-identical to `main`'s; phase 8a changed nothing there, for the same reason it left the
  `REDIR-23` bound. What is phase 10's: give each thread its own scripted sequence, or assert the
  budget invariant (sixteen calls, no thread past its cap) without assuming which response each thread
  draws, and read this together with the `REDIR-23` bullet as the same `NFR-6` class. Touches
  `RETRY-42`, `RECOV-28`, `NFR-6`. Added after phase 10's planning pass by phase 8a and referred to by
  date and content, never by ordinal; not yet in phase 10's design's disposition table, which
  dispositions it at execution.
- **`Dexpace::Status` guards `100`–`599` while `Net::HTTP` parses any three-digit code, so a `999` or a
  `600` head raises `Dexpace::InvalidArgumentError` out of the net-http adapter — a phase-1 model question
  in the shape of the `"http/1.0"` bullet above.** Found 2026-09-20 by phase 8a's review round 2 (R2-2),
  measured through the real adapter against `WireServer`: `Net::HTTP` reads any `\d\d\d` status line and
  delivers a `999` or a `600` as an `HTTPUnknownResponse` (`CODE_TO_OBJ['999']` and `CODE_CLASS_TO_OBJ['9']`
  both nil), phase 1's `Status#initialize` refuses an Integer outside `100..599` (`status.rb`, "the port's
  reading" of `HTTP-10`, recorded in phase 1's checklist row), and `ResponseMapper` raises that
  `InvalidArgumentError` after the head with the connection released and no thread left — the same path
  an `HTTP/1.0` head takes, while `520`, `499` and `599` map and a two-digit `99` is `Net::HTTP`'s own
  `HTTPBadResponse`, wrapped as a retryable `TransportError`. `TRANSPORT-24` says any code "including
  vendor/non-standard codes" is surfaced "rather than rejected", and LinkedIn's `999` is the canonical
  out-of-range vendor code; `HTTP-10` says construction is total over "any code". 8a routed it here rather
  than fixing it for the same reason as the `"http/1.0"` bullet: widening `Status`'s range is a phase-1
  surface decision no sub-phase should take alone, and the widening is additive, so `NFR-4` permits it.
  What is phase 10's: decide whether `100`–`599` is the port's reading of both IDs (then record it where
  phase 10 records the port's readings of frozen chapters, and the adapter's argument error is the
  documented outcome) or `Status` admits `000`–`999` (then the mapper needs no change), and in either case whether an
  adapter should surface an out-of-range head as a retryable `TransportError` rather than an argument
  error. **Code half: none owed by 8a** — 8a states the bound in its `TRANSPORT-24` checklist row, in
  `ResponseMapper`'s YARD beside its `HTTP/1.0` sentence, and in the as-built page. Touches `HTTP-10`,
  `TRANSPORT-24`, `TRANSPORT-22`, `NFR-4`. Added after phase 10's planning pass by phase 8a and referred
  to by date and content, never by ordinal; not yet in phase 10's design's disposition table, which
  dispositions it at execution.
- **Two child-process idioms prove one property — `seam_surface_test.rb`'s private
  `bare_require_report` and `test/support/bare_require.rb`'s `BareRequire#bare_require` each spawn a
  `ruby` that requires `dexpace` alone and read a seam registry back — and the tree should carry one.**
  Found 2026-09-21 by the pass that reconciled phase 8a's stack onto `main` after the whole of phase 7:
  7a converted `gems/dexpace-core/test/dexpace/seam_surface_test.rb`'s two seam-iterating pins ("every
  seam registry starts empty on a bare require", "no seam's zero-candidate error names a concrete gem")
  through a private helper inside the file — `IO.popen` over `RbConfig.ruby -w -Ilib -e` with a
  `BARE_REQUIRE` program printing one row per seam — and `serde_test.rb`'s three pins the same way,
  merged as #88; 8a, built one base apart, converted the same two `seam_surface_test.rb` lines through a
  new shared module, `gems/dexpace-core/test/support/bare_require.rb` (`Open3.capture3` over
  `RbConfig.ruby -w -W:deprecated -I <core lib> -e`, with `RUBYOPT` cleared, asserting a silent child),
  and moved `transport_test.rb`'s registry pins onto it in `transport_bare_require_test.rb`, which the
  adapter gems' smoke suites reuse. The reconciliation resolved `seam_surface_test.rb` to `main`'s
  content byte for byte — 7a's conversion, already merged and reviewed — dropped 8a's hunk to that
  file, and kept 8a's module and `transport_bare_require_test.rb` because 8a's own suites require
  them; so `main` now carries both spellings of one idiom, both green. What is phase 10's: unify
  `seam_surface_test.rb`'s private helper (and `serde_test.rb`'s copy of it) onto `BareRequire`, the
  more general of the two — it clears `RUBYOPT`, asserts the child exits 0 and writes nothing to
  stderr under `-w`, and takes an arbitrary program — so the "starts empty on a bare require"
  property has one spelling in `test/support/` and the next adapter's pins (8b's and 8c's, on
  `AsyncTransport`) inherit it. Touches `SEAM-1`, `SEAM-2`, `SEAM-6` (the IDs both spellings
  assert) and nothing normative in the code. Recorded by the 8a reconciliation on its docs branch;
  referred to by date and content, never by ordinal.
- **Under the one-process `rake test:gems` the main fiber's storage carries 5c's no-op span
  (`dexpace.current_span => Instrumentation::NO_SPAN`) into suites that never activated one, and the
  shared test case asserts nothing about fiber storage at `teardown`.** Found 2026-09-21 by phase 8b's
  first whole-repository run: the pool gem's diagnostics suite, green in its own process and on every
  interpreter alone, failed five of seven under `test:gems` because `Diagnostics.capture` on the main
  fiber — the caller's snapshot every `#post` takes — carried the reserved slot another gem's suite had
  left set, and the worker faithfully installed it (which is `ASYNC-8`'s purpose and not a defect of the
  pool). 8b's suite drops the reserved prefix before comparing, so it is green either way, and the
  residue is left where it lies. What is phase 10's: find which suite leaves the slot set — the
  candidates are core's `tracing_test.rb`, `scope_test.rb` and `diagnostics_test.rb`, whose `teardown`s
  reset it, and the suites that reach `Tracing.activate` through the instrumentation step without one —
  and decide whether `DexpaceTestCase` should assert the main fiber's storage unchanged at `teardown`
  beside its thread count, which is the same class of cross-suite leak `NFR-6` already guards for
  threads. Touches `OBS-23`, `OBS-24` and the 5c-owned `dexpace.current_span` carrier, and nothing
  normative in the code. Recorded by phase 8b on its docs branch; referred to by date and content,
  never by ordinal.
- **Core's two duration guards, `Dexpace::Async.validate_delay` and `Dexpace::Clock::Guard.duration`,
  admit a `NaN` and a `Complex`.** Found 2026-09-21 by phase 8b's review round 1 (R1-1), which found the
  same shape — `is_a?(::Numeric)` and `negative?` — in `Pool#delay`, where a `NaN` duration killed the
  pool's timer thread and turned every later `#delay` into a bare `ArgumentError`, and repaired it there
  (`P8-77`: `real?` before `negative?`, `finite?` after). 5a's guards are the precedent 8b's design cited
  and they share the hole: a `NaN` is a `Numeric` that answers false to both `negative?` and `zero?`, so
  `Clock#sleep(Float::NAN)` reaches `Thread::Queue#pop(timeout: Float::NAN)`, which parks indefinitely on
  every supported row (measured on 3.2.11, 3.3.12, 3.4.10 and 4.0.6) — a sleep no elapsed time ends and
  only the token can wake — and `Async.delay(Float::NAN)` schedules the same pop on the scheduler; a
  `Complex` is a bare `NoMethodError` from either. What is phase 10's: widen both guards the way `P8-77`
  did, with the same three tests, and decide whether `Future#value(deadline:)` and `Completer#await`'s
  deadline arithmetic want the same screen. Touches `CFG-15`, `CFG-17`, `CFG-18` and `XCUT-11`, and
  nothing normative beyond the messages. Recorded by phase 8b's review round 1 on its docs branch;
  referred to by date and content, never by ordinal.
- **Two of phase 8c's design facts are stale on `async` 2.46.0, and `async-http`'s server lets a
  peer's mid-head `EOFError` reach Console.** Found 2026-09-21 by phase 8c's implementation against
  the bundle's `async` 2.46.0 / `async-http` 0.105.0, where the design measured 0.104.0. Verified fact 8
  passes `cause: :sym` to `Task#cancel` and reads it back from the task's `$!.cause`: on 2.46.0 a
  non-`Exception` cause is replaced by the runtime's own `Async::Cancel::Cause` ("Cancelling task!"),
  so a reason travels only as an exception (the adapter wraps it in `Dexpace::CancelledError`; `P8-91`).
  Verified fact 10 says "`Async { }` inside a reactor is not a child of the caller": `Kernel#Async`
  inside a running task delegates to `Task.current.async`, `inner.parent.equal?(task)` measured true
  on 3.3.12, 3.4.10 and 4.0.6, so the reviewer's mutation 14 (the exchange spawned with `Async { }`)
  is an equivalent mutant and `caller_task.async` is the honest spelling rather than a distinction
  the runtime draws. Both are corrected in `docs/knowledge/notes/concurrency-and-async.md`'s new entry
  and the design's As-built addendum, and the design document itself — frozen to its phase — still
  states them; the `docs/deviations.md` flip should read the addendum, not the fact list. Separately,
  `Async::HTTP::Server#accept` rescues `Protocol::HTTP::BadRequest` and nothing else, so a peer that
  closes between the request line and the end of the headers — an exchange cancelled mid-send, which
  8c's suites do on purpose — raises `EOFError` out of the per-connection task, which Console reports
  to stderr as a task failure; seen once in a hundred-odd whole-suite runs on 4.0.6 under load and
  worked around in the test fixture (`AsyncHTTPServerFixture::QuietServer`), and worth an upstream
  report rather than an SDK change. Touches `TRANSPORT-8`, `ASYNC-6` and nothing normative in the
  code. Recorded by phase 8c on its docs branch; referred to by date and content, never by ordinal,
  because 8b's lane is writing to the same list.

**2026-09-13** — **Execution order amended by the roadmap-level generator-fitness review, which read the
plan end to end against one question: will a generated OpenAPI client be able to use this?** No cell of
the phase table changes and no requirement ID moves; what changes is the order the phases are *run* in,
which this document's own ordering rationale already leaves open in both places the amendment touches.

**`7a` runs before phase 6.** The rationale under the phase table states it outright — "per `SSE-37` and
§12's chapter intro, on nothing in phase 6 either, so **6 before 7 is a convenience order, not a
dependency**" — so this spends no dependency argument. What it buys: after phases 0–5 plus `7a`, the whole
synchronous slice a generator drives exists except the socket — `Dexpace::Operation#build_request`,
`Pipeline.direct`, `Body.serialized`, `StatusAwareHandler` over `TypedResponse` — and can be exercised
against cross-cutting constraint 4's in-memory fake transport, rather than first meeting each other after
phase 6, the largest phase in the roadmap at 111 + 15 IDs. The rest of phase 7 still follows phase 6;
only `7a` moves.

**Within phase 7 the order is `7a` → `7c` → `7b`.** The segmentation bullet above already fixes the
independence — "No sub-phase may depend on another, order is convenience only" — so this is a choice among
equals and not a new constraint. `7c`'s pagination is on the path a generated client takes for an ordinary
list endpoint; `7b`'s SSE is reached only by an API that streams, and at 41 IDs it is the second-largest
sub-phase in the roadmap. Running it last is what makes the convenience order pay.

**The end-to-end generator slice is split in two, and both halves are numbered plan tasks rather than
anything registered here.** The review's finding was that `Dexpace::Operation` — `SEAM-26`/`SEAM-27`, the
seam whose stated purpose is that operation arguments "flow through typed projections rather than being
spliced into a URL by string surgery" — is built by phase 2 and named by no later phase's documents at all,
so the composition a generator actually writes is never executed anywhere in the plan. **`7a` gains the
fake-transport half**: descriptor → `#build_request` → `Pipeline.direct` over the in-memory transport →
`StatusAwareHandler`, asserting the 200 decode, the 4xx typed error over `RECOV-15`'s buffered body, the
single-segment path parameter, and a `Tristate::ABSENT` field omitted on PATCH. **`8a` gains the socket
half**, the same slice over `Pipeline.standard` and the §9.3 `TCPServer` fixture with an AUTH step
pre-seeded through the documented `builder:` keyword. Each is written by the unit that owns it; neither is
a new requirement and neither changes a checklist row.

Two release entries were filed by the same review and are `docs/first-release.md`'s, not this document's:
a blocker requiring one worked end-to-end example in `docs/sdk-documentation/` — the artifact the
`AuthDescriptor` carrier line and the `HTTP-22`/`48`/`49`/`50` line both already name as their reopening
trigger, and which no phase produces — and a new *Behavioural asymmetries a consumer must know* subsection
under what v1 ships without, opened by `PIPE-32`/`REDIR-25`: `AsyncPipeline.standard` follows no redirects
while `Pipeline.standard` does, which is the requirement and is invisible to a consumer who reads neither
constant's YARD.

**2026-09-13** — **Phase 10's two planning documents filed**, under `docs/work/mvp/phase10/`:
[`phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness-design.md`](./phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness-design.md)
and its plan,
[`phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness.md`](./phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness.md).
**Every phase in the roadmap is now planned and none is built.** Nothing is implemented; the checklist is
written at execution time, per execution step 6.

**No segmentation design and no sub-phase, and the decision is argued against the number that looks like it
cuts the other way.** This document's rule reaches build phases 1 through 8 and leaves phases 9 and 10 to
segment "only if their own design finds it necessary". Phase 10's scope is **124 own rows** — the largest in
the roadmap, ahead of phase 6's 111-plus-15 — and the design's answer is that the ID is the wrong unit:
**fifty-one of the 124 are one entry's ID family**, because §10.1 retires the byte-stream provider seam and in
doing so names `SEAM-3`–`SEAM-10`, all forty-two `IO` IDs and `XCUT-23`, its own argument being that
`IO-1`–`IO-29` and `IO-37`–`IO-42` are implemented in full while only the pluggability apparatus is removed.
The unit of work is the **ledger entry**: 19 entries plus a closing note plus 32 inbound bullets is **52
units**, the same order as phase 1's 42 unsegmented rows and phase 9's 41. Of the rule's three triggers only
one fires, and maximally rather than usefully — phase 10 spans all nineteen ID-bearing chapters, because
design §10 does — while it ships **no new gem**: its repairs land in `dexpace-core`,
`dexpace-transport-net_http`, `dexpace-transport-async_http`, `dexpace-conformance` and the repository's own
tooling, all of which exist by the time it runs. Every candidate cut splits a ledger entry: prefix lines split
§10.1's `SEAM` half from its `IO` half, core-versus-adapters splits §10.4's cancellation claim across three
gems and §10.12's one ownership rule across three layers, and audit-versus-repair would recreate *inside*
phase 10 the boundary phase 9's `R6` drew between the two phases — which phase 10 exists to cross. Task
ordering carries what a cut would have: the plan builds and reads the instrument in Tasks 1–3, ships the
repairs in 4–10, re-derives the ledger in 11–15 and closes the registers and the phase in 16–19.

**Scope is 124 own rows plus 64 cross-reference rows — 188 checklist rows in all.** The 124 are every
requirement ID named by design §10's nineteen entries, extracted mechanically with every range expanded and
every member checked against appendix C (all 124 resolve), plus `RETRY-28` from §10's closing note, which is a
claim of the same kind and is audited with them: **108 MUST, 15 SHOULD, 1 MAY**. The 64 are every ID an inbound
bullet's *Touches* line or a newly-found hand-forward names, or one of phase 10's own repairs touches, that is
not among the 124 — 44 MUST, 16 SHOULD, 4 MAY — and they follow the two-rows-one-obligation discipline phase 2 gave `SEAM-29`: the owning phase keeps
the ID and **no earlier phase's row moves.** The spec-reading budget is **six appendix-C rows and no chapter
reading at all**: `--gaps` over all nineteen prefixes reports 21 uncited IDs, of which `SEAM-22` and
`IO-32`–`IO-35` are own rows and `SEAM-28` a cross-reference row, and for every one the CLI says appendix C is
its only normative statement. Appendix B is **out of scope** — phase 9 owns the 61-row map — so phase 10 is
not exposed to the roll-up hazard at all.

**The method, and the one decision it forced.** The roadmap states phase 10's method in half a sentence,
"re-deriving every ledger claim from as-built source, never from another document", and the design makes it
failable: an audit step names the artifact by path and constant, the promising phase document says where to
look and **is never evidence**, and a claim whose artifact cannot be named is *unverifiable* rather than
*confirmed*. That method immediately paid for itself. **`OBS-29`'s canonical text ends "This is a documented
emission contract; pipeline/transport wiring to emit it is a follow-up, so it is not yet runtime-enforced"** —
a clause design §8.1's restatement drops and no harvested corpus entry carries — so the "open surface
decision" that five documents across four phases carried, and that this list's second bullet frames as owed,
was **already closed by the requirement itself**. Nothing was built wrongly; every phase declined the wiring.
But the decision travelled as open through five documents and one register retirement, which is the shape of
error the re-derivation exists to catch, and it is why phase 10 files exactly one knowledge note and files it
there. `CTX-16` went the same way: all three of its modal clauses are met by phase 4a without a call path, and
"exposed to the tracing seam" is descriptive rather than modal, so the undriven correlation chain is a
purpose-fit gap and not a requirement gap. Both are now `docs/first-release.md` § What v1 ships without ›
*Behavioural asymmetries a consumer must know* entries rather than surface widenings, on the `Event#tag`
precedent — `NFR-4` locks a public keyword at the first tag and nothing in v1 would drive either one.

**Eleven deviations `P10-1`–`P10-11`, and four checks added to §9's table as addenda `A8`–`A11`** —
`gates:spdx_rbs` (the SPDX header on every shipped `sig/**/*.rbs`, which a RuboCop cop cannot reach because
`.rbs` is not Ruby, plus the assertion that no shipped signature declares nothing), `gates:sole_parse`
(asserting `AstScan.parse` is the only caller of `parse_file` in the repository, which was a comment and not an
assertion), the probe's **ninth** check, clause-scoped chapter attribution, and `gates:ledger_audit`, which
keeps `docs/deviations.md`'s nineteen rows tied to §10 by per-row ID-set equality and fails a verdict row that
cites no resolvable as-built evidence — `P10-2` made mechanical, and what stops a register audited once from
drifting after phase 10 closes. All four blocking. The addendum letters continue phase 9's `A4`–`A7`; the
thirteen frozen-chapter corrections are a **separate** series, `C1`–`C13`, because a first draft labelled both
`A` and they collided at `A8`. That set is thirteen and not eleven because two corrections already sitting in
`docs/deviations.md` — the §10.5 "an adapter" attribution and §12's `PAGE` row — had been left out of the
numbering and therefore out of the release blocker's enumeration; they are `C12` and `C13`, and `docs/deviations.md`
now carries the whole `C1`–`C13` mapping beside the notes so the two documents cannot drift. Phase 10
adds **no `dexpace-conformance` suite, assertion or gate**: a phase that reads an instrument and extends it
cannot say which of the two its verdict came from. Its two changes inside that gem are the residues phase 8's
ownership caused — `APPENDIX_B.md`'s check 2, which documents a per-row ID-equality check the filed test does
not perform, and `TransportSuite` left off `Runner` (`P9-10`) — and phase 10 is the first phase that owns
every gem.

**Repairs: twelve bullets, eight tasks.** The uncapped `Clients#@by_origin` (verify `8c`'s cap, repair if
`gates:bounded_map` is red, and **never** an allowlist entry); `NFR-13`'s SPDX header over every shipped
signature; 8a's unused rescue binding and the general `parse_file` exposure; the chapter-attribution check;
**`Dexpace::SingleUseError`** in core, with `SSE::StreamStateError` re-parented beneath it, because
`7c`'s `InvalidArgumentError < ::ArgumentError` puts `PAGE-14`'s state violation in the argument family where
`rescue ArgumentError` swallows it — measured on all four interpreters; **`XCUT-12`'s fiber-scheduler
single-flight assertion**, which phase 10 judges necessary and ships as a driver in
`dexpace-transport-async_http`'s `test/` tree, closing a post-release trigger rather than arming it; and
`Protocol::WIRE_FORMS` gaining `"http/1.0"`, a phase-1 surface decision 8a declined to take alone.

**Two things were fixed on the spot rather than filed**, because CLAUDE.md's rule is that a finding in
material you may write is not a finding: phase 5a's exclusions row, which named `TRANSPORT-3`/`TRANSPORT-8`
for proxy use and header-drop reporting where the IDs meant are `TRANSPORT-30` and `TRANSPORT-13` — the same
substitution phase 5b made and the phase-8 segmentation design corrected, so a pattern rather than a slip —
and 8a's forward row for the two declined `TRANSPORT` SHOULDs, half stale since its own `R17` implemented
`TRANSPORT-30`. **And three chapter attributions across two lines, which are the check's own justification**: phase 8a's and
8c's governing-documents lists name `docs/product-spec/03-pluggable-seams-and-extension-model.md` for
`SEAM-13`, `SEAM-15` and `SEAM-22`, and that chapter carries none of the three — `SEAM-13`'s only prose home
is `02-architectural-principles.md`, and `SEAM-15`, `SEAM-20`, `SEAM-22`, `SEAM-23` and `SEAM-28` appear in no
prose chapter at all, which phase 2 established on 2026-09-06 and phase 10 re-verified today. Corrected in
place, dated, with the pre-correction text preserved as the check's regression fixtures — a gate whose only
evidence is a live defect loses its evidence the moment the defect is fixed.

**Three items postponed, every one to `docs/first-release.md` because phase 10 has no later phase**: applying
the thirteen amendments (§3, §4, §8, §9, §10, §11, §12 and appendix C's `SSE-19` row are frozen and reserved to
a human, so what phase 10 can do is make the amendment a **transcription** — sentence, replacement,
measurement, verified code half — and file the blocker, whose alternative form is the release notes naming
which design sentences a reader should not trust); the chapter-attribution check's continued-clause blind
spot, whose trigger is a **second** instance because one is an anecdote; and an `NFR-4` **diff** as opposed to
a baseline, since `NFR-4`'s subject is a diff against a release tag and there is none — phase 10 establishes
both baselines and leaves the disposition ⏳, because establishing a baseline is not satisfying a requirement
about comparing against one. **Two items were picked up**: `XCUT-12` under a fiber scheduler, the one item
the deferral register handed phase 10 and phase 9's own postponement, and phase 9's three
`R6`/`P9-7`/`P9-10` hand-offs.

**Seven findings, all measured on 3.2.11, 3.3.12, 3.4.10 and 4.0.6.** Three contradicted the record — the
third being this design's own first draft, which reported 8a's unused rescue binding as a live defect after
commit 152ec6a had already removed it; that is the error class the re-derivation method exists to catch,
committed by the document that states the method, and it is recorded here rather than quietly fixed. **Minitest
resolution has moved again since phase 9 measured it on 2026-09-12** — 5.25.1 / 5.20.0 / **6.0.6** / 6.0.0,
with `default_gem?` `false` on all four — and not because an interpreter changed: 6.0.6 sits in the *user* gem
directory on the 3.4 row beside the 5.25.4 that interpreter ships, a bare `require "minitest"` resolves the
newest, and requiring `minitest/mock` then `minitest/autorun` there loads **both copies and emits 13
`already initialized constant` warnings**, which `NFR-6`'s gate turns into a failure. So phase 0's `~> 5.25`
pin is load-bearing for a second reason — the 3.4 row's determinism, by newest-wins resolution outside
Bundler — and the trigger's measurement is corrected. And **`net-http`'s connect-phase `Timeout.timeout` is on
every supported Ruby at a different line each time** (`:1601`, `:1601`, `:1657`, `:1791`), so the finding
strengthens while its single absolute-path citation resolves on one row of four. The half nothing had measured
is now measured: the resolved **`async-http` closure contains no `Timeout.timeout` call at all**, seven
`Fiber#raise` sites — one of them `async/task.rb:365`, which is how `Async::Task#cancel` delivers the
`Async::Cancel` phase 8c's `TRANSPORT-8` result rests on — one `Thread#raise` and one `Thread#kill`. The
`Thread#kill` is in `io-event`'s `Selector.process_wait`, on a helper thread the adapter never reaches. The
`Thread#raise` is reported rather than left out, because §8.3 names that primitive and a reader auditing the
ban will grep for it: it is `Thread.current.raise(error)` in the pure-Ruby fallback selector, a raise on the
**calling** thread and therefore an ordinary synchronous `raise` rather than the asynchronous cross-thread
interrupt §8.3 prohibits. `Fiber#raise` is not on §8.3's list and
the omission is principled: a fiber raise resumes at a **scheduler checkpoint**, which is the property §8.3's
own rationale distinguishes and §3.3 already relies on. Both facts widen §8.3's amendment from one clause to
that clause plus what the closures do. `docs/deviations.md` gains **two** interim notes — §8.3's scope clause
and appendix C's `SSE-19` row, the first entry there against the normative specification — has its
`C1`–`C13` mapping written beside the notes, and has the *IDs touched* column of rows 1, 3, 10 and 12 widened
to their §10 entry's full named set, with the column's convention stated where the column lives: every ID the
entry names, not only the IDs the deviation narrows. Those four rows were short by 34, 2, 3 and 1 IDs, which
is what `gates:ledger_audit`'s equality assertion reports against the register as it stood.
`docs/first-release.md` gains one blocker, two *Behavioural asymmetries* entries and one post-release trigger,
has one trigger annotated as closing when Task 9 lands, and has the Minitest trigger's measurement corrected.
**One corpus note**, filed before the plan: `docs/knowledge/notes/observability.md`, `OBS-29`'s follow-up
clause, taking the corpus to **52 entries across 21 files**. `CLAUDE.md`'s phase-directory count goes from ten
to eleven with this filing, and its phase-6 sentence loses "the largest phase in the roadmap" for "the
largest **build** phase", which phase 10's 124 own rows make true. Its "Eight checks" sentences stay at
eight until the ninth is built — phase 10's plan, Task 7 — because a count that anticipates a check is
the kind of claim this phase exists to catch. The "Zero gems exist under `gems/`" sentence is unaffected.

**2026-09-14** — **Phase 0 implemented**, as three stacked branches against issue #7: code and configuration,
tests, documentation. `gems/` now exists with the six MVP gem skeletons, every one at `0.0.0` — a gemspec
reading `VERSIONS`, `lib/` holding the namespace and a `VERSION` literal and nothing else, `sig/` mirroring it
one file per file, a README, a LICENSE copy and a per-gem `Rakefile` — and the root carries `VERSIONS`,
`Gemfile`, `Rakefile`, `Steepfile`, `rbs_collection.yaml`, `.rubocop.yml`, `.yardopts`, six custom cops under
`.rubocop/cops/dexpace/`, eight gate bodies and the require scanner under `tools/`, three rake files and
`.github/workflows/ci.yml`. **Seventeen gates**, all in the default task and all seen to go red: 99 deliberately
failing inputs against a floor of 56 (62 before the round-1 review, 80 before the round-2), counted in the
checklist at `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-checklist.md`. `bundle exec
rake` is green on 4.0.6 in 2 min 51 s; the matrix set is green on 3.2.11, 3.3.12, 3.4.10 and 4.0.6. No requirement is
dispositioned: the checklist's nineteen rows say which gate answers each `NFR`, with `NFR-8`/`NFR-9` 🚫
retargeted per design §10 item 19 and `NFR-16` ⏳ under `docs/first-release.md` § Release path. The four
postponed items keep the owners the design records. **One deviation added at implementation, P0-11**: the
RuboCop gate excludes `scripts/` and `.claude/` as `NFR-7`'s documented exception, and the repair is the new
thirty-third bullet on phase 10's inbound list above. Thirty-one departures from the plan's text are itemised
in the checklist, none narrowing a gate; the two worth reading first are that `gem build` writes every tar mtime
as the fixed `SOURCE_DATE_EPOCH` the gate sets (so `gates:reproducible`'s negative input is a clock-dependent
gemspec, not a touched file — and the fallback with the variable unset is fixed only from RubyGems 3.6, the 3.4
and 4.0 rows, which an earlier draft of this note got wrong), and that the rbs collection resolves the
workspace's own gems from the lockfile (so `rbs_collection.yaml` ignores all six by name and `rbs validate` runs
with `--no-collection`). The round-1 review of the three branches found six gates accepting an input the design
says they must refuse — a parenthesised or `Kernel.`-prefixed `require`, one core feature loaded from two
directories, `URI(...)`, a dropped RBS overload or a method moved under `private`, a class alias of
`Async::Task`, and a gemspec listing its files through `git ls-files` — and each was repaired on the branch that
owns it before merge, with a fixture that turns the gate red (checklist deviations 17–24). The round-2 review
found four more — the four ban cops blind to a safe-navigation call (`@thread&.kill`), `URI::Parser` unflagged
beside `URI::DEFAULT_PARSER`, `gates:rbs_surface` reporting a type variable and a relative `Headers` inside
`module Dexpace` as foreign (green only while every signature is `VERSION: String`; red on phase 1's first real
one), and `CLAUDE.md` still saying every checklist was unwritten — and four nits taken, each either in the
strict direction or back to the plan's text: `require "dexpace"` accepted for an adapter, the transport denial's
scope narrowed to `socket` alone, the gemspec audit following `require_relative` helpers, and
`Dexpace/NoKeywordSplat` scoped to `gems/*/lib` as the plan's Task 4 amendment states. Each was repaired on its
owning branch, every gate change with a fixture that turns it red (checklist deviations 25–31).
The two counts that changed: `gems/` from zero to six; the phase-directory count is unchanged at eleven, since
every directory already existed as planning documents. `CLAUDE.md`'s "After scaffold — planned" block is
rewritten from what was built.

**2026-09-15** — **Phase 1 implemented**, as three stacked branches against issue #8: code, tests,
documentation. `dexpace-core` now carries the HTTP domain model — twenty-two new `lib/` files under
`lib/dexpace/`, each with its `sig/` and `test/` mirror, exactly the layout the design's Module Layout
section names — and the other five gems are still phase-0 skeletons at `0.0.0`. The checklist is at
`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-checklist.md`: forty-two rows, 38 ✅ (two by
construction — `HTTP-1`, `HTTP-2` — and two split with a deferred half — `HTTP-3` three ways, `HTTP-46`'s body
half deferred to 3b), 4 ⏳ (`HTTP-22`, `HTTP-48`–`HTTP-50`, all under `docs/first-release.md`), none 🚫. `bundle exec rake` is green on 4.0.6 with 100% line coverage against the
80% floor; the matrix set is green on 3.2.11 and `test:gems` on 3.3.12 and 3.4.10 as well. **The two
interpreter findings the design was built on held**: `Model#with` is proven load-bearing by removing it and
watching the floor fail while 4.0.6 passes, and every validator reads bytes, so `"a\0"`, `"a\r\nb"` and
invalid UTF-8 are rejected with the SDK's error rather than the regexp engine's. **One finding reversed a
ledger row**: `Request` and `Response` *are* `Ractor.shareable?` as built, because `URL.parse!` had to freeze
the URI's component Strings anyway (`URI#freeze` is shallow and `URI#dup` shares them, an `XCUT-15` alias
the plan's `dup.freeze` left open) and `URI::RFC3986_PARSER` is already frozen by the uri gem on both
interpreters (given a `nil` or frozen body; the opaque body is carried as given, and the reason phrase is copied
and frozen at build) — `P1-9` is retired, `P1-13` records the ownership rule, and the corpus note that carried
`P1-9` is rewritten as built, under `## Conflicts`, confirming `data-modeling/996c0b12` rather than superseding
it. Two more ledger rows added at implementation: `P1-11`, `HeaderName`'s fold
is a derived attribute rather than a second member, and `P1-12`, `Query` equality compares encodings, which
is `HTTP-30` stated literally. Twenty-one departures from the plan's text are itemised in the checklist, none
lowering a gate; five are gate or tool corrections the first real signatures forced, each pinned by a fixture
on the tests branch: `gates:rbs_surface`'s stdlib list gains `Data`, `ArgumentError` and `StringScanner`;
`rbs:validate` loads the allowlisted stdlib signature sets; `gates:single_instance` survives — and names —
the `superclass mismatch` a second copy of a `Data.define` model raises; `tools/surface.rb` stops listing a
reader the model made private; and `.rubocop.yml` admits Steep's `#: Type` annotation, which strict Steep
requires on an empty literal. Three of the four notes the design filed stand and the fourth is rewritten;
the phase-10 inbound list gains two bullets, the thirty-fourth — the vacuous `rake rubocop` in a nested
worktree — and the thirty-fifth — nine later-phase design documents citing the retired note key
`data-modeling/5bc538ba`. The three postponed items keep their owners. The counts that changed: `gems/` is
still six but `dexpace-core` is no longer a skeleton; the phase-directory count is unchanged at eleven;
`CLAUDE.md`'s "no domain code" paragraph, its construction pattern and its gem sentence are rewritten from
what was built. **The round-1 review of the stack** found two
plan-level gaps the implementation had inherited — `Response` aliased the caller's `reason` String, and
`Headers.build` let a non-`Hash` reach the name walk as a `NoMethodError` — and one corpus mistake, the
planning-time note still marking `data-modeling/996c0b12` as superseded after the build had confirmed it; all
three are repaired on the branch they belong to (checklist deviations 15 and 18–19, the note above), with
`test:gems` at 256 runs and 100% line coverage on 4.0.6 and 3.2.11 afterwards. **The round-2 review**
found one more inherited gap and closed it the same way: a `Request` accepted a `Headers` the inbound
grammar had validated, so obs-text `HTTP-18` forbids could reach the model that represents an outbound
message through `.build`, `#with` or `headers=` followed by `#header` — `Request#initialize` and
`Request::Builder#headers=` now require the outbound direction (checklist deviation 20, the `HTTP-18` row).
Two nits were taken with it — `Model.own` moved from `.build` into each `initialize` after the shape
checks, so a non-copyable object is the SDK's error rather than `Ractor.make_shareable`'s `TypeError`
(deviation 21), and `Query.parse` refuses a non-`String` as its sibling factories do (deviation 17) — one
ledger row was added, `P1-14`, naming the `String`-only tag values of `RequestOptions` as a deliberate
reading of `HTTP-34`, and `URL.own`'s comment stopped asserting the retired `P1-9`. `test:gems` is at 260
runs and 100% line coverage on 4.0.6 and 3.2.11 afterwards. **The round-3 review** found the mirror image of
the design's finding 3: every validator reads bytes, so a String whose bytes are ASCII under a tag Ruby cannot
fold under — `"Accept".encode("ISO-2022-JP")`, the same bytes as the literal — passed every check and then
crashed the fold, the upcase or the scanner with `Encoding::CompatibilityError`, escaping `rescue
Dexpace::Error` from eight public entry points. `HeaderSyntax.ascii_compatible` is the one normalisation,
applied before every fold, upcase and scan in core (checklist deviation 22; one new public method, the
manifest regenerated deliberately); `HTTP-19`'s third clause — inbound names stay strict — gained the tests
the code already satisfied; the checklist's own roll-up sentence and this note's copy of it were recounted from
the table (38 ✅, not 36); two nits were taken — a non-finite or non-real timeout and a non-`Hash` argument to
`#with` are the SDK's error — and one was routed, `URL.parse!`'s host-less and non-HTTP shapes, as the
thirty-sixth phase-10 inbound bullet above. `test:gems` is at 273 runs and 100% line coverage on 4.0.6 and
3.2.11 afterwards.

**2026-09-15** — **Phase 2 implemented**, as three stacked branches against issue #9: code, tests,
documentation. `dexpace-core` now carries the seam layer beside phase 1's domain model — twenty new `lib/`
files under `lib/dexpace/`, exactly the design's Module Layout, each with its `sig/` mirror and each but the
`private_constant` `hooks.rb` with its `test/` mirror, plus five further suites, eight test-support files
(the three in-memory fakes the roadmap's constraint 4 asks for, three companions one class per file, the
probe scheduler and the warning capture) and the seventh custom cop, `Dexpace/QualifiedCoreConstant` — and
the other five gems are still phase-0 skeletons at `0.0.0`; nothing talks to a socket. The checklist is at
`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations-checklist.md`: thirty rows, 23 ✅ (`SEAM-15` and
`SEAM-25` with a named gap each — no raise site, no lifecycle event — and `SEAM-29` in phase 1), 3 ⏳
(`SEAM-12` to phase 8a's `TransportSuite`, `SEAM-24` post-v1, `SEAM-28` to phase 5c Task 4), 3 🚫 (`SEAM-3`,
`SEAM-4`, `SEAM-22`'s mechanism with its surviving clause ✅), 1 N/A (`SEAM-10`, the version-skew guard
phase 0 postponed to this phase built in its place as `Registry#register`'s required `core:` keyword, Tasks 7
and 8, and exercised under `ruby --disable-gems` on 4.0.6). `bundle exec rake` is green on 4.0.6 with 99.93%
line coverage against the 80% floor (the one uncovered line is the registry claim swap's race-only branch);
the matrix set is green on 3.2.11; the whole suite is green under three further seeds. **Every concurrency
guard the plan's verification table lists was run red** by reverting its fix in the built tree — the
re-entrant-resolve trio and the token-less bridge wait as hangs under the coreutils `timeout`, the rest as
the assertions the plan predicted — and the shadowing test fails `NameError: uninitialized constant
Dexpace::Async::Thread::Mutex` with one `::` removed, the same line the cop flags. **Two of the plan's proofs
were found vacuous as written and repaired in place**: the version-skew grid varied only the requirement,
and against a core at `0.0.0` that cannot tell `>=` from `==` on the minor — the plan's own break-it step
stayed green — so the test now swaps the running `Dexpace::VERSION` across six versions and adds an
exhaustive square (checklist deviation 8); and the method-level-`else` guard's `:not_a_token` scenario is
rescued in the body once the pre-dispatch check exists, so it drives a `nil`-returning transport instead,
which is `SEAM-16`'s null-success rule arriving as a real raise (deviation 12). Thirty departures from
the plan's text are itemised in the checklist, none lowering a gate; two are structural — `Completer#settle`
steals the abort hooks in the same swap that publishes the outcome, so a producer's abort hook fires only
when the cancellation actually won (deviation 2), and `Operation`'s checks and composition live in two
`private_constant` modules so each half is reviewable alone (deviation 7) — and one corrects a phase-0 gate
test that had pinned a phase-0 fact: adapter manifests began with the shared namespace line only because
core did not yet define `Dexpace::Transport`, `Serde` or `Async`, and the corrected assertion is the
property the test's own comment states (deviation 24, on the code branch because that branch's `test:gates`
must be green). `sig/dexpace/hooks.rbs` exists after all, because the strict `core` Steep target checks every
`lib/` file and never relaxes (deviation 1). The four notes the design filed stand; no fifth was needed. The
six postponed items keep their owners. The counts that changed: `gems/` is still six; `dexpace-core`'s
`lib/dexpace/` is forty-two phase-1 and phase-2 files beside phase 0's `version.rb`; `phase2/` now carries
its checklist, the third written; the surface manifest is 318 lines, and the four adapter manifests each
lost the one namespace line core now owns.
`CLAUDE.md`'s built-phases paragraph, its gem and phase-directory sentences and three new constraints-that-bite
lines are rewritten from what was built.

**2026-09-15** — **Phase 3a implemented**, as three stacked branches against issue #11: code, tests,
documentation. `dexpace-core` now carries the byte-streaming layer beside phase 1's domain model and phase 2's
seam layer — nine new `lib/` files under `lib/dexpace/`, exactly the design's Module Layout: two flat failure
types, `Dexpace::StreamError < ::IOError` and `Dexpace::EndOfStreamError < ::EOFError`, and seven under
`Dexpace::IO` — the namespace with `MAX_MATERIALIZED_BYTES`, the `TypedReads` and `TypedWrites` vocabularies,
`BufferedSource`, `Buffer`, `BufferedSink` and `TeeSink` — each with its `sig/` mirror declaring every method
and its `test/` mirror, plus three fakes (`fake_chunked.rb`, `fake_source.rb`, `fake_sink.rb`); two files
changed as the design said (`Closeable#closed?` reads the latch under the mutex, P3-6; the entry file's nine
`require_relative`s), the seventh cop gained `IO`, the one-segment `Dexpace` watch and a definition-site guard
over every gem's `lib/` (P3-7), and the other five gems are still phase-0 skeletons at `0.0.0`; nothing talks
to a socket. The checklist is at `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-checklist.md`:
forty-two rows, 34 ✅ and 8 🚫 (`IO-30`–`IO-36`, `IO-39`, the retired provider apparatus citing design
§10.1, with `IO-30`'s independent-copy clause kept as a property of `.of_bytes`), nothing ⏳, nothing N/A.
`bundle exec rake` is green on 4.0.6 at the tests tip with 99.95% line coverage against the 80% floor and
783 runs across the six gems; the matrix set is green on 3.2.11, 3.3.12 and 3.4.10; the core suite is green
under further seeds; the code tip is red on the SimpleCov floor alone (77.91%, 0 failures). **Every guard the
plan asks to be run red was run red** — P3-6's fiber-held-mutex assertion against phase 2's reader on all
three interpreters (`ThreadError expected but nothing was raised`), the cop's six new rejections before the
widening, the `fill(1)` amendment's count guards (`Expected: 4096 Actual: 1`), and the Tasks 5–9 ladder
against the finished suite (12/57, 4/47, 4/38, 1/20, 1/0, then 0/0 failures/errors). **One correctness defect
the plan's fences carried was found and closed by a test the plan did not have**: view invalidation did not
cascade, so a slice of a slice survived its root's close and could pull fresh bytes through an invalidated
outer view from a closed `.of_bytes` root; `#dexpace_invalidate` now releases a view's own views and the
parent-side entry points check readability first (checklist deviation 3). **Two decisions the plan left open
were taken in the open**: `TeeSink#clear_tap` is dropped — 3b builds a fresh tee per write, so the method had
no caller in core while being `NFR-4`-locked surface (deviation 1) — and `BufferedSource.__dexpace_view` is a
`private_class_method` with a `private def self.` RBS declaration, reached through `send`, so the underscore
name is in neither the manifest nor the `NFR-4` diff (deviation 7). **Review round 0 (2026-09-15) found a
view's fill blocking to the count where the root fills once** — a peek over a pipe holding ten bytes hung on
`read_into(count: 100)` — and it was closed on the code branch with `#dexpace_fill_beyond`, nine tests and a
guard run red (deviation 18). Nineteen departures from the plan's text are itemised in the checklist, none
lowering a gate; one widens
`tools/rbs_surface.rb`'s `NFR-11` allowlist by `EOFError`, `IOError` and `Encoding` — the false positive phase
1 fixed for `Data`, `ArgumentError` and `StringScanner`, fixed the same way with a fixture and a pinning gate
test (deviation 6) — and one moves phase 2's accepted cop row `module Dexpace; module Transport; Thread.new`
to rejected, a tightening the one-segment watch implies (deviation 2). The unbounded window is `nil` rather
than `Float::INFINITY` and three RBS interface-typed parameters are `untyped`, because strict Steep refused
the plan's shapes (deviations 4 and 5). The plan's RuboCop-baseline finding does not reproduce against the
built tree — 200 files, no offenses with `--ignore-parent-exclusion` — so phase 0's plan, Task 3 gains
nothing. The design's ledger gains P3-13 and an "As built" addendum; the one postponed item keeps its owner
(`IO-38` on a GVL-free Ruby, `docs/first-release.md` § Post-release triggers), the `include Dexpace` blocker's
documentation half is written in `docs/sdk-documentation/io.md` and the core README with the consumer case
pinned in `io_test.rb`, and its release-decision half stays open. The counts that changed: `gems/` is still
six; `dexpace-core`'s `lib/dexpace/` is fifty-one phase-1, phase-2 and phase-3a files beside phase 0's
`version.rb`; `phase3/phase3a/` now carries its checklist, the fourth written; the surface manifest is 366
lines. `CLAUDE.md`'s built-phases paragraph, its gem and phase-directory sentences and the constraints-that-bite
line on the seventh cop are rewritten from what was built. The consolidation of P3-1–P3-13 into design §10 is a
human's, as it was for phases 1 and 2: `docs/sdk-design-ruby/` is frozen, and `docs/deviations.md` is left as
phase 2 left it for phase 10 to flip.

**2026-09-16** — **Phase 3b implemented**, as three stacked branches against issue #12: code, tests,
documentation. `dexpace-core` now carries the body layer beside the domain model, the seam layer and the
byte-streaming layer — twelve new `lib/` files under `lib/dexpace/http/`, exactly the design's Module Layout:
`body.rb` with `Dexpace::Body`, its eight factories, `MAX_BUFFERED_ERROR_BODY_BYTES` and `.buffer_bounded`;
the ten variants under `body/` — `BytesBody`, `BufferBody`, `StreamBody`, `ChunkedBody`, `FormBody`,
`FileBody`, `MultipartBody` with its nested `Part` and `Builder`, `ResponseBody`, `RequestLoggingBody`,
`ResponseLoggingBody`; and `TypedResponse` — each with its `sig/` mirror declaring every method and its
`test/` mirror, plus two fakes (`fake_body.rb`, `fake_response_body.rb`); three `lib/` files changed as the
design said (the form encoder beside the RFC 3986 one in `PercentEncoding`, `Response#close`/`#body_string`/
`#body_bytes`, the entry file's twelve `require_relative`s), `sig/` narrows `Request#body` and
`Response#body` to `Dexpace::Body?` (P3-15 — **the body-member narrowing phase 1 postponed to phase 3 has
landed**, with `HTTP-46`'s body half tested), `tools/measure_view_retention.rb` is the Task 13 measurement,
and the other five gems are still phase-0 skeletons at `0.0.0`; nothing talks to a socket. **`BODY-12`'s
first clause is discharged** (`::IO.copy_stream` with the window, `#path`/`#offset`/`#count`, no
`#to_path`; P3-17) and clause 2 stays with `TRANSPORT-28` under `docs/first-release.md`. The checklist is at
`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-checklist.md`: fifty-one rows, the
forty-nine own IDs plus `HTTP-46`'s and `HTTP-3`'s cross-reference rows — 46 ✅, 4 ✅ in part with the
remainder ⏳ and its owner named (`BODY-12` clause 2, `BODY-34`'s source and predicate, `BODY-30`'s and
`HTTP-52`'s response-side clause), 1 ⏳ (`BODY-36`, no stdlib `mmap`), nothing 🚫, nothing N/A. `bundle exec rake` is
green on 4.0.6 at the tests tip with 99.96% line coverage against the 80% floor and 1,153 runs across the six
gems (323 of them the twelve body suites); the matrix set is green on 3.2.11, 3.3.12 and 3.4.10; the code tip
is green on all seventeen gates too, its `test:gems` at 84.21% above the floor. **Every guard the plan asks to be run red was run red, and fifty-five
single-edit mutations were run** — the plan's fifty, the adversarial review's two testable ones and the three
probes the brief names — fifty-four caught, with the two decode-recipe mutations exactly as the plan predicts:
the retag dropped fails the decode suite outright, the target dropped fails exactly the two hostile
`Encoding.default_internal` tests and nothing else. The one that survived — the `BODY-32` clamp *deleted*, as
distinct from the plan's "clamps up" spelling — was found by the stack's review round 0, whose four defects
(the readers and the bounded copy leaving the view they took registered, the over-cap tail forwarding as a
fill-to-count `#read`, `MultipartBody` equality blind to the subtype, and that unproven clamp) and two nits
were repaired on the owning branches the same day with twelve further mutations run red on 4.0.6 and 3.2.11;
the checklist's deviations 17–21 and its second battery table carry them. Review round 1 found one more,
from a hazard experiment the first round had not run — `ResponseLoggingBody` asked its delegate for `#source`
three times, right over `ResponseBody`'s same handle and wrong over `BufferBody`'s fresh view per call, which
is inside the wrapper's own stated contract — repaired the same way (one handle, taken once and closed by the
wrapper's release) with eight mutations run red on both interpreters; deviation 22 and the third battery
table carry it, and its nit corrected the row arithmetic here and in the checklist to 46 / 4 in part / 1. The review's R1 (`#emit_exactly`'s retag dropped) was
missed on the first pass for the reason the review gave and is now caught by a raw `#write` recorder that
keeps what it was handed as given. **One defect was found and closed while writing the as-built page**: a
`subtype:` carrying `;` parsed as a subtype plus a smuggled parameter, and the subtype is now validated as one
bare token through `MediaType.parse`. **Two things 3a as built changed under the plan**: `TeeSink#clear_tap`
does not exist and is never called — `BODY-18` is a fresh tee per write — and the one-byte-per-read finding
the plan reports against 3a is closed there (`READ_SEGMENT_BYTES`, `#dexpace_fill_beyond`), so Task 13's
measurement was re-run rather than copied: zero bytes retained per unread view, 7–8 objects per view, a
thousand views closing in about 0.012 s and ten thousand in 1.2–1.3 s on this machine, the same shape and
verdict as the plan's table. Strict Steep reshaped eight private mechanisms without changing behaviour and
put `HTTP-46`'s identity default on `Dexpace::Body` itself, so four stream-holding variants dropped their
copies (checklist deviations 3–6). Twenty-two departures from the plan's text are itemised in the checklist —
sixteen the build's, five review round 0's, one review round 1's — none lowering a gate. One finding is routed to phase 10's inbound list above, the thirty-seventh bullet:
`MultipartBody` refuses a non-ASCII part name or filename because its part-header sweep is the outbound
header grammar — kept as the design decided, stated as a limitation in `docs/sdk-documentation/body.md`.
The design's ledger gains an "As built" addendum; the one postponed item keeps its owner (the body-logging
caps' source and enablement predicate, phase 5a Task 13 and 5b Tasks 14–15), `close_quietly` has its first
call site (`BODY-28`) with neither disposal route yet built, and the fakes' move to `dexpace-conformance`
gains two more doubles without meeting its condition. The counts that changed: `gems/` is still six;
`dexpace-core`'s `lib/dexpace/` is sixty-three phase-1, phase-2, phase-3a and phase-3b files beside phase
0's `version.rb`; `phase3/phase3b/` now carries its checklist, the fifth written; the surface manifest is
515 lines. `CLAUDE.md`'s built-phases paragraph, its gem and phase-directory sentences and the
constraints-that-bite list are rewritten from what was built. The consolidation of P3-14–P3-29 into design
§10, and §3.1's and §5.1's addenda, are a human's, as they were for 3a: `docs/sdk-design-ruby/` is frozen, and
`docs/deviations.md` is left as phase 2 left it for phase 10 to flip.

**2026-09-16** — **Phase 4b implemented**, as three stacked branches against issue #15: code, tests,
documentation, cut from `main` at 419aace while phase 4a was built in parallel in another worktree — nothing of
4a's is on `main` at this build and 4b names no 4a constant anywhere. `dexpace-core` now carries the recovery
layer beside the domain model, the seam layer, the byte-streaming layer and the body layer — sixteen new `lib/`
files under `lib/dexpace/`, exactly the design's Module Layout: `suppressible.rb` (`Dexpace::Suppressible`,
`Dexpace.attach_suppressed`, `Dexpace.suppressed`), `each_cause.rb`, `error/outcome_error.rb`,
`error/protocol_error.rb`, `outcome.rb` with its two variants, `recovery.rb` (`Recovery.buffer_error_body`) and
under `recovery/` the `Transform` contract, the three shipped steps, `RequestChain`, the private `Ownership`,
`ResponseChain` and `Orchestrator` — each with its `sig/` mirror, `ownership.rbs` included for the strict Steep
target (P4-41), and every one but `ownership.rb` with a `test/` mirror; four `lib/` files changed as the design
said (`error.rb`'s `include`, `hooks.rb`'s attach-and-`cause: nil`, `closeable.rb`'s `onto:`, the entry file's
`suppressible` line above `error` and its fifteen-line block), two `sig/` files changed, three test-support files
are new (`recording_body.rb`, `cyclic_errors.rb`, `recovery_fixtures.rb`) and phase 2's `fake_transport.rb` is
reused unchanged, and the other five gems are still phase-0 skeletons at `0.0.0`; nothing talks to a socket.
The checklist is at `docs/work/mvp/phase4/phase4b/2026-09-09-phase4b-recovery-primitives-checklist.md`:
forty-one rows, the thirty-four own IDs plus seven cross-reference rows (`XCUT-4` (a), `XCUT-8`, `XCUT-9`,
`BODY-30`, `PIPE-37`, `RETRY-34`, `RETRY-25`) — 18 ✅, 15 ⏳ to phase 6a's recovery-stack retry engine with the
charter's twin `RETRY` ID per row, 1 ⏳ (`RECOV-31`, `docs/first-release.md`), nothing 🚫, nothing N/A. `bundle
exec rake` is green on 4.0.6 at the tests tip with 99.97% line coverage against the 80% floor and 1,289 runs
across the six gems (129 of them the fifteen new suites); the matrix set is green on 3.2.11 (99.97% line
coverage there too), 3.3.12 and 3.4.10; the code tip is green on all seventeen gates too, its `test:gems` at 1,154
runs and **94.64%**, above the floor, and on 3.2.11's matrix set. **Every guard the plan and the brief ask to be
run red was run red, and thirty-nine single-edit mutations were run** — thirty-eight caught, the one survivor a
`break`-for-`next` that does not change behaviour; the `XCUT-9` container guards (an `Array`, a `Set`) were red on
3.2.11 as well as 4.0.6 over the never-raised `#cause`-override pair the design says survives the floor, and the
`RECOV-10` bare-`raise` guard was red on all three interpreters with the caller's in-flight exception as the
cause. **The postponed work this phase picked up**: the suppressed-exception trail phase 1 postponed to phase 4
landed as `Dexpace::Suppressible` with `#detailed_message` — the carrier phase 1 named (`Dexpace::Error#suppressed`)
and the method it named (`#full_message`) both changed, P4-12 and R5; the handler failures `Hooks.notify` dropped
after the first are attached and re-raised with `cause: nil`, with the fourth test, `"two raising handlers surface
the first with the second on its suppressed trail"`, at the `Cancellation::Source#cancel` site; and
`close_quietly`'s **first** disposal route, `onto:`, landed with `Recovery::Ownership` as its first core caller —
the item stays open, the second route being phase 5b's (Task 14). **What stays postponed**: `XCUT-5`'s
retryability flag on `Dexpace::ProtocolError` (phase 6a, Task 6, `#retryable_by_status?`); the fifteen
recovery-stack IDs `RECOV-17`–`RECOV-30` and `RECOV-34` (phase 6a, Tasks 3, 4, 5, 7 and 11), and `RECOV-31`
(`docs/first-release.md`). One constraint the plan did not know bit: `Dexpace/NoKeywordSplat` forbids the
`**kwargs` the design gave `#detailed_message`, so it takes one optional positional `Hash`, `Model#with`'s
spelling, measured on all three interpreters (P4-40). Twenty-seven departures from the plan's text are itemised
in the checklist — eight where phases 1–3b as built overrode its assumptions, the rest this build's — none
lowering a gate, and the ten that touch public behaviour or a stated count are the design ledger's As-built rows
P4-40–P4-49, numbered from 40 so the two phase-4 lanes cannot collide. Two findings are routed: the two committed
phase-2 sentences 4b's change makes false (the "every handler runs" paragraph and the `Dexpace::Error#suppressed`
carrier) are recorded in the checklist as the manager's to rewrite, not edited; and design §10 item 6's carrier
sentence, with §5.2's placement of the trail, is `docs/first-release.md` § Blockers' fourteenth frozen-chapter
correction (`C14`), its replacement written out in the design's addendum. `docs/sdk-documentation/recovery.md`
is the as-built page, its ten fences run verbatim on 4.0.6, 3.4.10 and 3.2.11. The counts that changed: `gems/`
is still six; `dexpace-core`'s `lib/dexpace/` is seventy-nine phase-1, phase-2, phase-3a, phase-3b and phase-4b
files beside phase 0's `version.rb`, every one mirrored in `sig/` and every one but the two `private_constant`s
mirrored in `test/`; `phase4/phase4b/` now carries its checklist, the sixth written; the surface manifest is 586
lines. `CLAUDE.md`'s built-phases paragraph, its gem and phase-directory sentences and the constraints-that-bite
list are rewritten from what was built. The consolidation of P4-12–P4-25 and P4-40–P4-49 into design §10, and
§5.1's, §5.2's and §6.1's addenda, are a human's, as they were for 3a and 3b: `docs/sdk-design-ruby/` is frozen,
and `docs/deviations.md` is left as phase 2 left it for phase 10 to flip.

**2026-09-16** — **Phase 4c implemented**, as three stacked branches against issue #16: code, tests,
documentation, cut from phase 4b's docs tip (`15-phase-4b-recovery-primitives-docs` at 6099c66, still open as
#53 → #54 → #55) rather than from `main`, because the one thing 4c consumes — `Dexpace::Recovery::Transform` —
lives there; phase 4a was built in parallel in another worktree off `main`, nothing of 4a's is on this base and 4c
names no 4a constant anywhere. `dexpace-core` now carries the stage pipeline beside the domain model, the seam
layer, the byte-streaming layer, the body layer and the recovery layer — twelve new `lib/` files under
`lib/dexpace/`, exactly the design's Module Layout: `error/pipeline_error.rb`, `pipeline.rb` (`Dexpace::Pipeline`,
`.builder`, `.direct`), under `pipeline/` the closed `Stage`, the sixteen-constant `Stages` with `ALL`, `PILLARS` and
`.of`, the `Step` protocol with its `_Step`/`_AsyncStep` interfaces, `Entry` with its optional anchor name, the
forward-only `Cursor` with its pillar-only `#fork` and `(stage, key)` state, the two private drivers, the one
`Builder` both runtimes share, and the `TransformStep` adapter over 4b's `Transform`, then `async_pipeline.rb`
(`Dexpace::AsyncPipeline`, `.direct`, `.map_response`) — each with its `sig/` mirror, the two drivers' included for
the strict Steep target (P4-50), and every one but the two drivers with a `test/` mirror; two files changed as the
design said (the entry file's twelve-line block with `pipeline` first among the nested set, and the smoke suite's
`PIPELINE_LAYER`), `sig/dexpace.rbs` is untouched (P4-51), four test-support files are new (`probe_step.rb`,
`forking_probe.rb`, `state_probe.rb` — one class per file, which `Style/OneClassPerFile` decided — and the doubles'
own suite), phase 2's `fake_async_transport.rb` is reused unchanged and its `inline_executor.rb` extended
compatibly with a `#posts` counter (P4-54), and the other five gems are still phase-0 skeletons at `0.0.0`;
nothing talks to a socket. The checklist is at
`docs/work/mvp/phase4/phase4c/2026-09-09-phase4c-stage-pipeline-checklist.md`: forty-seven rows, the forty own
`PIPE` IDs plus seven cross-reference rows (`REDIR-11`, `AUTH-29`, `XCUT-11`, `NFR-11`, `SEAM-18`, `TRANSPORT-1`,
`TRANSPORT-2`) — 37 ✅, `PIPE-33` ✅ in part with clause 5 ⏳ under design §10.5 (`docs/first-release.md` §
Unsatisfied MUSTs, whose entry names this row; the four met clauses are named so the row is not read as unbuilt),
`PIPE-36` ⏳ declined (`docs/first-release.md` § SHOULD/MAY), `PIPE-39` ⏳ in half (phase 6b, Task 13a), nothing
🚫, nothing N/A. `bundle exec rake` is green on 4.0.6 at the tests tip with 99.97% line coverage against the 80%
floor and 1,434 runs across the six gems (144 of them the eleven new suites, one more the smoke suite gained),
re-run after review round 0's repair; the matrix set is green on 3.2.11 (99.97% line coverage there too — the
one uncovered line is the registry-claim race branch, reached nondeterministically), 3.3.12 and 3.4.10; the
code tip is green on all seventeen gates too, its `test:gems` at 1,290 runs and **95.02%** (94.96% on 3.2.11),
above the floor. **Every guard the plan and the brief ask to be run red was run red, and thirty-two
single-edit mutations were run** — thirty-one caught, the
one survivor a first attempt at "flatten by insertion order" that reproduced `ALL`'s order by accident and was
replaced by a genuine one; the `Stage#with` decision and the three identity-versus-`==` guards were red on 3.2.11
as well as 4.0.6, and six more mutations were run red after review round 0's repair, one per line it made
load-bearing, the three identity ones on both interpreters. **What shipped of `PIPE-39`**: `Pipeline.direct` / `AsyncPipeline.direct`, `Builder#install_preset`
(PIPE-24's all-or-nothing mechanism, real and tested against probe pillars) and `Builder.flattening` / `.nesting`;
**what stays postponed**: the standard-resilience constructors `Pipeline.standard` / `AsyncPipeline.standard` with
`PIPE-32`'s `redirect: :unsupported` argument — phase 6b, Task 13a, written over `#install_preset`, its Task 14
closing the row — `PIPE-33`'s interrupt clause (§10.5, re-asserted by phase 8b when the executor becomes real),
and `PIPE-36` (declined). The design's two findings were verified rather than re-recorded: the type-keyed surgical
edits are repaired by `Entry#name` and the four edits' name anchors, and `Transport.async_over`'s missing
return-type check was found already repaired on this base by phase 2's Task 11 (`Bridge::AsyncOver#deliver`
raises `Dexpace::SeamError` for a delivered `Future`). Twenty-six departures from the plan's text are itemised
in the checklist — nine where the built tree overrode its assumptions, three review round 0's, the rest this
build's — none lowering a gate, and the ten that touch public behaviour or a stated count are the design
ledger's As-built rows P4-50–P4-59: the drivers' `sig/` mirrors, every constant declared in its own mirror,
`AsyncDriver` returning a step's future as itself and refusing a non-`Future` with `SeamError`, `map_response`
written over `Future#then`, `InlineExecutor`'s counter, `Stage`'s raw readers private, **`Stage#with` refusing**
(the closed-set hole the brief's as-built point 9 named: `Data#with` would otherwise mint a seventeenth stage on
3.4 and 4.0, and `Model#with` would route to a `Stage.build` that does not exist), `Cursor`'s three refusals with
`#may_fork?` false on a spent cursor, and review round 0's two — every `Stage` the builder or an `Entry` holds
resolved to its constant by identity through `Stages.of`, because `Data#dup`, `#clone` and `Marshal` are public
and yield a `==`-but-not-`equal?` copy the builder's identity comparisons refused with a message naming the same
stage twice (P4-58), and a mistyped anchor refused with `InvalidArgumentError` before any comparison instead of
Ruby's `TypeError` once an entry existed (P4-59); the round's third fix, `PIPE-6`'s same-object no-op on the
surgical inserts, is a requirement met rather than a deviation. No frozen-chapter sentence is contradicted by
this build, so `docs/first-release.md`'s `C1`–`C14` paragraph gains no `C15` and that file is untouched.
`docs/sdk-documentation/pipelines.md` is the as-built page, its ten fences run verbatim on 4.0.6 and 3.2.11
(`Hash#inspect`'s spelling differing on the floor and nothing else). The counts that changed: `gems/` is still six; `dexpace-core`'s `lib/dexpace/` is ninety-one phase-1,
phase-2, phase-3a, phase-3b, phase-4b and phase-4c files beside phase 0's `version.rb`, every one mirrored in
`sig/` and every one but the four `private_constant`s mirrored in `test/`; `phase4/phase4c/` now carries its
checklist, the seventh written; the surface manifest is 665 lines. `CLAUDE.md`'s built-phases paragraph, its
lib-file and checklist counts and its constraints-that-bite list (the disjoint `#call`/`#fork`, the `(stage, key)`
state with no writer, the closed sixteen-stage set) are rewritten from what was built. The consolidation of
P4-26–P4-39 and P4-50–P4-59 into design §10, and §5.1's and §5.3's addenda, are a human's, as they were for 3a,
3b and 4b: `docs/sdk-design-ruby/` is frozen, and `docs/deviations.md` is left as phase 2 left it for phase 10 to
flip. This note goes after 4b's; the roadmap's execution-step-5 sentence is deliberately untouched, its
correction riding phase 4a's docs PR.

**2026-09-16** — **Phase 4a implemented**, as three stacked branches against issue #14: code, tests,
documentation, cut from `main` at 419aace and run as a stack parallel to phase 4b's — the first time two
sub-phases have run side by side, which is the shape execution step 5 now states. `dexpace-core` carries
the execution context beside the four layers before it — twelve new `lib/` files, exactly the design's
Module Layout: `error/context_conflict_error.rb`, `context.rb` (the module the three flavours include),
`bounded_map.rb` and `context/call_key.rb` (the two `private_constant`s), `context_store.rb`,
`instrumentation/trace_id_flavour.rb`, `instrumentation/no_span.rb`, `instrumentation/no_tracer.rb`,
`instrumentation/bundle.rb`, and `context/dispatch_context.rb`, `context/request_context.rb` and
`context/exchange_context.rb` — every one with a `sig/` mirror (the two private constants included, with
the comment `hooks.rbs` carries), ten with a `test/` mirror, plus one fake (`fake_context.rb`); the entry
file gains the twelve `require_relative`s as one block; the eighth custom cop, `Dexpace/NoWeakReferences`,
lands with its cases in a nested class of `cops_test.rb` and its scope in `.rubocop.yml`; the other five
gems are still phase-0 skeletons at `0.0.0`; nothing talks to a socket, and nothing in core promotes a
context — a generated client will. **Roadmap cross-phase obligation 1 is discharged**: the bundle's eight
stored members and derived `#valid?`, `Bundle::NONE`, `TraceIdFlavour`'s three values and the three no-op
singletons are fixed in core with their names `NFR-4`-locked, and the five-clause handshake in the design's
R3 is what phase 5c populates against. The checklist is at
`docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-checklist.md`: twenty rows, `CTX-1`–`CTX-20`,
**20 ✅**, nothing ⏳, nothing 🚫, nothing N/A. `bundle exec rake` is green on 4.0.6 at the tests tip with
99.96% line coverage against the 80% floor and 1,272 runs across the six gems (118 of them the ten
execution-context suites, on every interpreter, since Minitest is 5.27.0 on every row); the matrix set is
green on 3.2.11, 3.3.12 and 3.4.10; the code tip is green on all seventeen gates too, its `test:gems` above
the floor. **Every guard the brief asks to be run red was run red**, twenty-four single-edit mutations in all:
seventeen caught on the first run, one — a counter per flavour — survived the plan's `CTX-6` case,
whose three-key distinctness check a per-flavour counter satisfies whenever the shared counter has already
moved past it, so the case now asserts the suffix increases strictly across flavours in build order; and
two more that review round 0 found surviving — a promotion that releases its source before setting its
successor, and a memoised `.default` — are caught by the round-1 cases the checklist's guards 19 and 20
name, the first through a real chain and the second by asking a fresh process; and review round 1 found
no survivor but a gap — a pinned `call_key` or an `operation_name` that is a Symbol was accepted against
the `String`-typed signature and an Integer escaped as a `NoMethodError` — closed in round 2 by a
`must be a String` guard in `#validate_context!` and a shared private `#validate_operation_name!`, whose
four mutations are the checklist's guards 21–24. The `CTX-9` trap (`==` for
`equal?`), the `ObjectSpace::WeakMap` swap, the two round-1 guards and the four round-2 guards were run red
on 3.2.11 as well, where the swap also fails on the floor's `WeakMap` having no `#delete`. **Four things
phases 0–3b as built changed under the plan**: the cop is the eighth, not the seventh (`CLAUDE.md`,
`quality-gates.md`, phase 2's checklist and `cops_test.rb` all count the keyword-splat cop phase 0's plan
says is uncounted — routed to phase 10's inbound list above, the thirty-eighth bullet); phase 0's
`CountKeywordArgs: false` already applied the plan's `Metrics/ParameterLists` finding, so the fences'
inline disables are not written; `hooks.rbs` exists, so the two private constants get `sig/` mirrors; and
`tools/surface.rb` already walks `Data` readers, so the plan's Task 9 finding against phase 0 is closed by
phase 0 as built and the regenerated manifest — 515 to 580 lines, 65 rows read one by one against the
object model, none removed — holds every reader of the five value types. One public method fewer than the
plan's fence: `Context.validate!` is the private `#validate_context!`, since the design gives `Context`
exactly one public method. Seventeen departures from the plan's text are itemised in the checklist, none
lowering a gate. `_ContextHost`, the self-type interface strict Steep needs for `Context#close`, is the one
new ledger row, **P4-60** — numbered from the tree, because 4b's design filed P4-12–P4-25 and 4c's
P4-26–P4-39 before this phase executed, 4b's as-built addendum took P4-40–P4-49 and P4-50–P4-59 are
4c's; it was P4-40 while the two lanes ran in parallel and was renumbered before the push. `docs/sdk-documentation/execution-context.md` is the as-built
page, every fence run verbatim on 4.0.6 and 3.2.11 with identical output; `architecture.md`, the core
README, `README.md` and `docs/README.md` point at it. The design's ledger gains an "As built" addendum;
the two postponed items keep their owners (the cap's configuration source, phase 5a Task 13; the no-op
protocols, phase 5c Tasks 3–5); the `IO-38` post-release trigger's `CTX-7`/`CTX-8` sentence reads true of
what was built and is unchanged. **Execution step 5 and the phase 3, 4, 5, 6 and 8 segmentation designs
are corrected in place today**: "one phase-level pull request" is what no phase did, and each sub-phase
returns as its own code → tests → docs stack. The counts that changed: `gems/` is still six;
`dexpace-core`'s `lib/dexpace/` is seventy-five phase-1, phase-2, phase-3a, phase-3b and phase-4a files
beside phase 0's `version.rb`; `phase4/phase4a/` now carries its checklist, the sixth written; the surface
manifest is 580 lines; the cop suite is 129 cases. `CLAUDE.md`'s built-phases paragraph, its gem and
phase-directory sentences and the constraints-that-bite list are rewritten from what was built. The
consolidation of P4-1–P4-11 and P4-60 into design §10, and §5.4's and §8.1's addenda, are a human's, as
they were for 3a and 3b: `docs/sdk-design-ruby/` is frozen, and `docs/deviations.md` is left as phase 2
left it for phase 10 to flip. **Those counts are the build's, cut from `main` at 419aace.** Phases 4b and
4c merged first (#53–#55, #60–#62), so the stack was rebased onto their `main` on 2026-09-16 before it went
in: the entry file carries the three phase-4 blocks in sub-phase order, the surface manifest was regenerated
on the merged tree rather than merged by hand (665 + 65 = 730 lines, no row of 4b's or 4c's changed), the
smoke suite pins all three layers, and `CLAUDE.md`, the READMEs and `architecture.md` read one hundred and
three files, six `private_constant`s without a `test/` mirror and eight checklists — 4a's is the eighth
written, not the sixth, in merge order.

**2026-09-17** — **Phase 5a implemented**, as three stacked branches against issue #18: code, tests,
documentation, cut from `main` at 993c439 and run as a lane parallel to phase 5c's off the same base, with
phase 5b not started — the shape execution step 5 states, and the first time a lane ran beside one it shares
a chapter with: nothing of 5c's is on this base, 5a names no 5c constant, and 5a touches
`Dexpace::Instrumentation` not at all. `dexpace-core` carries the configuration layer beside the seven
layers before it — seventeen new `lib/` files, one more than the design's Module Layout: `build_info.rb`,
`uuid.rb`, `retryability.rb`, `http_date.rb`, `clock.rb`, `async/delay.rb`, `deep_value.rb`,
`configuration.rb` with `configuration/keys.rb`, `configuration/sources.rb`, `configuration/parsers.rb` and
`configuration/builder.rb` (the seventeenth, a file of its own as phase 1 files every builder, **P5-51**),
`config.rb`, and `proxy.rb` with `proxy/type.rb`, `proxy/host_pattern.rb` and `proxy/resolution.rb` — every
one with a `sig/` mirror (the three `private_constant`s included, with the comment `hooks.rbs` carries,
**P5-57**), fourteen with a `test/` mirror, plus three doubles (`fake_clock.rb`, `fake_config_source.rb`,
`parking_scheduler.rb` — top level, and two of them renamed from the plan because `fake_source.rb` is phase
3a's `IO-17` double and `probe_scheduler.rb` is phase 2's hook recorder, **P5-58**); the entry file gains
ten `require_relative`s as one block, because the seven nested files reopen their class and load from inside
its body; eight existing files change — `async/completer.rb` and `async/future.rb` for the `deadline:`
keyword, `context_store.rb` for the cap, `io.rb` for the ceiling function, and `http/body.rb`,
`http/body/stream_body.rb`, `http/body/buffer_body.rb` and `io/typed_reads.rb` as its readers — and three
earlier tests with them, phase 0's smoke suite, phase 2's `seam_surface_test.rb` and phase 4a's
`context_store_test.rb`, on the code branch because the code tip must be green; the other five gems are
still phase-0 skeletons at `0.0.0`; nothing talks to a socket, and nothing in core calls `Proxy.resolve` —
`CFG-28`'s prohibition met by the absence of a call site. **Three of the four items earlier phases postponed
to this window landed**: the pivot's `deadline:` keyword (phase 2's P2-5) as a timed gate pop inside
`Completer#await` ending in `request_cancel(:deadline_expired)` — not the `Cancellation.any` composition the
design's alternative named — with `clock:` beside it and the positional cancellation unchanged; the context
store's configured cap (phase 4a, Task 13), by **option (b)**: `ContextStore.default` is built on its FIRST
call, under one `::Thread::Mutex`, reading `Keys::MAX_TRACKED_CONTEXTS` then and falling back to the
constant on a non-positive value, because phase 4a's load-time assignment could never see a
`Dexpace.configure` at boot and an unsynchronised `||=` publishes sixteen stores for sixteen first callers
(**P5-55**; phase 4a's fresh-process case is rewritten to assert no store before the first call, on the code
branch, since the code tip must be green); and the ceiling half of the body-logging caps (phase 3b, Task
13), by **option B**: `Dexpace::IO.max_materialized_bytes` is a public function AND the five readers of
`MAX_MATERIALIZED_BYTES` read it per call, so the live configuration governs every materialisation and the
constant is the default and the fallback (**P5-56**). The fourth — the two logging-body wirings — needs 5b's
enablement setting and is 5b's: 5a declares no key for body-preview size or enablement, and the charter's
mark goes on 5b as the lane that lands second. The checklist is at
`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-checklist.md`: thirty-eight own rows,
`CFG-1`–`CFG-38`, **35 ✅ and 3 ✅-in-part** — `CFG-20`, whose fourth clause is the `docs/first-release.md`
Unsatisfied-MUSTs entry already names (no new line there); `CFG-34`, whose boxed-versus-primitive container
clause has no Ruby manifestation and is inapplicable per §11.15; and `CFG-35`, whose throwable half is phase
6a's Task 3 — nothing ⏳, nothing 🚫, nothing N/A, plus seven cross-reference rows (`XCUT-5`, `CTX-11`,
`IO-9`, `BODY-32`, `SEAM-18`, `XCUT-11`, `NFR-11`) for the IDs of other phases this build reached. `bundle
exec rake` is green on 4.0.6 at the tests tip with 99.97% line coverage against the 80% floor (4,703 of
4,704 lines after review round 0's repair; the one uncovered line is in phase 2's `registry.rb`) and 1,762
runs across the six gems; the matrix set is green on 3.2.11, 3.3.12 and 3.4.10; the code tip is green on
all seventeen gates too, its
`test:gems` above the floor, and the honest RuboCop claim rests on `--fail-level=convention
--ignore-parent-exclusion`. **Every guard the brief asks to be run red was run red**, thirty-six single-edit
mutations under twenty-five headings: all caught on the first run but one — the resolver's port bound raised
by one, indistinguishable from the model's refusal caught by the backstop until the suite carried `65536`
and asserted the warning's own text — and one that hangs by construction (the pop's `timeout:` dropped),
which the shell timeout reports at exit 124; guard 6, the mutex around the slot swap, is invisible to every
behavioural case under the GVL and is pinned by a text case that says why. Seven of the mutations were run
red on 3.2.11 as well, the `Kernel.sleep` and re-check guards among them. **Six floor-straddling facts were
re-verified on 3.2.11, 3.4.10 and 4.0.6 before any code** and are asserted on every row by
`matrix_facts_test.rb`, and the design's open question 2 — whether `Time#httpdate` follows the locale — was
settled rather than deferred, under a user-space `de_DE.UTF-8` built with `localedef` into a scratch
`LOCPATH`: CRuby's `strftime` never consults it. **Four other things the tree as built changed under the
design**: `Async.delay`'s future settles with `true`, because `SEAM-16` makes a `nil`-valued settlement
unconstructible (**P5-52**); `Proxy::HostPattern` is a one-member `Data` over `glob` with the compiled
`Regexp` a private instance variable set at construction (**P5-53**); `Proxy::Type` is a closed set in the
pipeline's `Stage` shape — `.of` the only lookup, `.new` and `.[]` private, no `.build`, `#with` refusing —
not phase 1's `Status` shape; and `HTTPDate.parse` checks every component against what `Time.utc` built,
because `Time.utc(1994, 11, 31)` is silently 1 December (**P5-54**). Twenty-three departures from the plan's
text are itemised in the checklist, none lowering a gate. The surface manifest is regenerated once, 730 to
814 lines, every one of the 84 new rows read against the object model and none removed.
`docs/sdk-documentation/configuration.md` is the as-built page, every fence run verbatim on 4.0.6 and 3.2.11
with identical output but the floor's `Hash#inspect` spelling and `BuildInfo::RUNTIME_VERSION`;
`architecture.md`, the core README, `README.md` and `docs/README.md` point at it. The design's ledger gains
an "As built" addendum, rows **P5-51–P5-58**, numbered from the tree so the parallel lanes cannot collide —
5c's as-built rows start at P5-71 and 5b's at P5-91. **Review round 0 (2026-09-17) found the `CFG-28`
case resolving against the empty slot's real `ENV`** — red on any host with `HTTPS_PROXY` set, the failure
the suite's own header warns about — and `Proxy#to_s`/`#inspect` printing the username in cleartext beside
a masked password, against `CFG-22`'s "never emit username/password in cleartext"; both were closed on the
owning branches, with the ceiling and cap suites made hermetic the same way, the store's seams moved
outside its mutex (P5-55 amended), `Completer#await` validating its keywords before the settled
short-circuit, `Builder.new` validating its seeds, and a blank `HTTPS_PROXY` no longer masking `HTTP_PROXY`
— nine mutations run red after the repair, the checklist's deviations 24–26 and its second guard table.
No corpus note was written: nothing this build found
contradicts a harvested rule. No frozen sentence is contradicted either — §8.2's chain and §8.3's queue wait
are built as described — so `docs/first-release.md` is untouched and its `C1`–`C14` paragraph gains no
`C15`; the §8.2, §8.3, §10.16 and §10.17 addenda that would state the substituted third source, the queue
wait, the first-call store construction and the configured ceiling as built, and the consolidation of
P5-1–P5-15 and P5-51–P5-58 into design §10, are a human's, as they were for 3a, 3b, 4a, 4b and 4c:
`docs/sdk-design-ruby/` is frozen, and `docs/deviations.md` is left as phase 2 left it for phase 10 to flip.
The counts that changed: `gems/` is still six; `dexpace-core`'s `lib/dexpace/` is one hundred and twenty
phase-1 through phase-5a files beside phase 0's `version.rb`, nine of them `private_constant`s without a
`test/` mirror; `phase5/phase5a/` now carries its checklist, the ninth written; the surface manifest is 814
lines. `CLAUDE.md`'s built-phases paragraph, its gem and phase-directory sentences and the
constraints-that-bite list are rewritten from what was built. **Those counts are the build's, cut from
`main` at 993c439**; phase 5c's lane, if it merges first, will regenerate the manifest on the merged tree as
4a did.

**2026-09-17** — **Phase 5c implemented**, as three stacked branches against issue #20: code, tests,
documentation, cut from `main` at 993c439 and run as a stack parallel to phase 5a's — the two lanes edit the
same `CLAUDE.md`, README and `architecture.md` sentences, each for its own phase on top of `main`, and the
merge's rebase-and-reprove pass reconciles them; phase 5b is not running and starts after both merge. **This
is the 5c-first execution the plan's Global Constraints anticipate**: `dexpace-core` carries the tracing and
metrics layer beside the seven layers before it — six new `lib/` files under `instrumentation/`, the design's
five plus `diagnostics.rb`, which 5c created with exactly 5b's three constants `TRACE_ID`, `SPAN_ID` and
`DEFAULT_KEYS` for 5b's Task 6 to extend rather than duplicate (ledger row **P5-71**) — `scope.rb` (`Scope`,
`NO_SCOPE`, the private slot key), `tracing.rb` (`Tracing`'s five functions), `meter.rb` (`NO_METER` and its
two private instruments), `http_tracer.rb` (`HTTPTracer`, `NULL`) and `callable_adapter.rb`; four phase-4a
files widened **in place** — `NoSpan`'s seven methods, `NoTracer`'s two, `TraceIdFlavour#generate_trace_id`,
`Bundle#sampled?` — with `_Span` and `_Tracer` filled where 4a declared them empty on purpose and the three
published singletons keeping the identity 4a gave them; every file with a `sig/` mirror and a `test/` mirror,
six test-support files (the four recording doubles, namespaced `Dexpace::Recording*` because 5b's plan
consumes three by those names, **P5-73**, plus two helpers), the entry file's six-line `# Phase 5c:` block,
and the surface manifest regenerated once from 730 to 772 lines with all 42 rows read against the object
model; the other five gems are still phase-0 skeletons at `0.0.0`; nothing emits a trace or a metric, no
logger, event or step exists, and nothing talks to a socket. **Roadmap cross-phase obligation 1 is honoured
from the populating side**: the five prohibitions of phase 4a's handshake hold item by item — no second
no-op span, tracer, factory or meter, neither singleton replaced, `Bundle.members` the same eight, `#valid?`
derived, `TraceIdFlavour` a `Data` with `NONE`'s sentinel unchanged — and **the postponed work phase 4a
handed phase 5 has landed**: the no-op span and tracer protocols (Tasks 3, 4 and 5) and `SEAM-28`'s consumer
(Task 4: the identifier is 4a's `RequestContext#operation_name`, the consumer `_TracerFactory#tracer`'s
`name`; the ID exists only as an appendix-C row and was read from there). **R15's condition was read and
found NOT met** — `SEAM-2` enumerates five seams and instrumentation is not one; 5c registers nothing and adds
no fourth registry — so presence-gated auto-activation stays post-v1 and is not met-and-declined.
**`OBS-29`'s wiring is NOT shipped**: the eleven-method vocabulary, `NULL`, `CallableAdapter` and the
ordering test over a conformant emitter fake ship, and nothing in phase 5 emits any of it, which the
requirement's own last sentence anticipates; the per-attempt group is phase 6a's retry step (Task 9), the
transport milestones phase 8's, the operation-lifecycle triple phase 10's inbound list. The checklist is at
`docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-checklist.md`: twelve own rows,
**11 ✅** (`OBS-29` ✅ with its unwired half named in the row; `OBS-30` ✅ by construction), **1 ⏳**
(`OBS-32`, post-v1 under `docs/first-release.md`'s `OBS-32`/`OBS-37` entry), nothing 🚫, nothing N/A, plus
thirteen cross-reference rows. `bundle exec rake` is green on 4.0.6 at the tests tip and the docs tip with
99.97% line coverage against the 80% floor and 1,640 runs across the six gems (86 of them the thirteen new or
widened instrumentation suites); the matrix set is green on 3.2.11, 3.3.12 and 3.4.10; the code tip is green
on all seventeen gates too, run one by one, its `test:gems` at 97.86% on 4.0.6 and 98.49% on 3.2.11, above
the floor. **Every guard the brief asks to be run red was run red**, twenty-three single-edit mutations,
twenty-two caught and one green by design (Task 11's subprocess with the entry point instead of the file
list, which stays green only because 5b is absent — the reason the assertion is written against the file
list); the floor-sensitive eleven were run on 3.2.11 as well and caught there, one through the floor branch
of the removed-key assertion; two allocation mutations had to be re-spelled because a literal in void
context is eliminated by the VM. **Two facts the design measured on 3.4.10 alone do not hold on the floor,
and both are recorded rather than worked around**: `Fiber[:k] = nil` deletes the key from 3.3 and **retains
it with a `nil` value on 3.2.11**, whose whole `Fiber` API offers no removal but the warned whole-map setter,
so `OBS-23`'s "remove it if previously unset" is a removal on 3.3+ and a nil-valued key on the floor that
`Fiber[]` and `OBS-10`'s null-skip both read as absent (as-built row **P5-72**, P5-49's own argument from
the other direction; the plan's fallback "delete explicitly" had nothing to delete with); and
`Fiber["k"]` raises `TypeError` on 3.2 and 3.3 and interns only from 3.4, which touches nothing built —
the keys are `Symbol`s — and settles R11 harder. Both are a new entry in
`docs/knowledge/notes/observability.md` (marker `sha:manual-phase5c-fiber-nil-and-string-key-floor`), the
matrix-facts suite pins both version boundaries, and the two later plans written on the 3.4.10 fact —
5b's union restore and 8b's pooled-worker restore — are the **thirty-ninth inbound bullet** above,
documentation half only. **The design's two findings were verified at their owners**: the keyword-splat
cop is closed as built — phase 0's `Dexpace/NoKeywordSplat` fired on a scratch `**attributes` method under
the honest RuboCop before any code was written — and the tracer-factory name collision stays on the inbound
list. Twenty-one departures from the plan's text are itemised in the checklist, none lowering a gate; the
ones that touch public behaviour are the as-built rows **P5-71–P5-76** (also: `Scope.build` public with
`@api private`, `CallableAdapter`'s construction check and nil returns, `NO_TRACER#in_span` without a
block). One order-dependent assertion was found by the 3.4.10 matrix row and fixed in the tests commit —
the openssl fact now measures in a scrubbed subprocess, because `bundle exec`'s `RUBYOPT` loads bundler's
own openssl into any child. `docs/sdk-documentation/tracing-and-metrics.md` is the as-built page, every
fence run verbatim on 4.0.6 and 3.2.11 with the three differences stated where they appear;
`architecture.md`, the core README, `README.md` and `docs/README.md` point at it. `docs/first-release.md` is
untouched — its `OBS-32`/`OBS-37` entry and its presence-gated auto-activation entry already read true —
and so is `docs/deviations.md`, for phase 10 to flip. The consolidation of P5-40–P5-50 and P5-71–P5-76 into
design §10 and the §8.1 addendum are a human's, as they were for 3a, 3b, 4a, 4b and 4c: `docs/sdk-design-ruby/`
is frozen, and no frozen sentence is contradicted, so no `C15`. The counts that changed, on top of `main`
at 993c439: `dexpace-core`'s `lib/dexpace/` is one hundred and nine phase-1 through phase-5c files beside
phase 0's `version.rb`, six `private_constant`s without a `test/` mirror (unchanged: 5c's private classes
live inside its six files), nine checklists, the surface manifest 772 lines, 53 corpus notes.
`CLAUDE.md`'s built-phases paragraph, its gem and phase-directory sentences and the constraints-that-bite
list are rewritten from what was built, for 5c only. **Those counts are the build's, cut from `main` at
993c439.** Phase 5a's stack lands first — one nine-PR stack, 5a, then 5c on 5a, then 5b on 5c — so this
stack was rebased onto 5a's docs tip on 2026-09-17, as 4a's was onto 4b's and 4c's: the entry file carries
the two phase-5 blocks in sub-phase order, the surface manifest was regenerated on the combined tree rather
than merged by hand (814 + 42 = 856 lines, no row of 5a's changed), the smoke suite pins both layers, and
`CLAUDE.md`, the READMEs and `architecture.md` read one hundred and twenty-six files, nine
`private_constant`s without a `test/` mirror, ten checklists and ten as-built pages — 5c's checklist is the
tenth written, not the ninth, in stack order.

**2026-09-17** — **Phase 5b implemented**, as three stacked branches against issue #19: code, tests,
documentation, cut from the **reconciled 5c docs tip** at `032986b` — which holds phase 5a's stack and
phase 5c's rebased onto it — so the plan's interleaved order (5b Tasks 1–14, 5c Tasks 1–7, 5b Tasks
15–16) collapsed to Tasks 1–16 straight through, and the three phase-5 stacks go up as one nine-PR
stack, 5a, then 5c on 5a, then 5b on 5c. `dexpace-core` carries the logging facade and redaction beside
the nine layers before it — fourteen new `lib/` files under `instrumentation/` (`severity.rb`,
`keys.rb`, `null_sink.rb`, `render.rb`, `redaction_policy.rb`, `redactor.rb`, `event.rb`,
`logger.rb`, `contain.rb`, `preview.rb`, `http_logging.rb`, `emitter.rb`, `step.rb`, `async_step.rb`)
and 5c's `diagnostics.rb` **extended in place** with the fold, the snapshot bridge and the reserved
prefix, no `require` added and 5c's load-time independence subprocess unchanged and green (P5-71
honoured from the adopting side); six earlier-phase files widened, each a designed widening —
`closeable.rb` and `hooks.rb` gain `logger:` and the two `http.instrumentation.*` diagnostics phase 2
postponed, `proxy.rb` and `proxy/resolution.rb` gain `logger:` and the config diagnostic beside every
`Kernel#warn` (5a's P5-8 discharged), `configuration/keys.rb` gains `LOG_PREVIEW_BYTES` — with their
`sig/` mirrors; every public file with a `test/` mirror, the two `private_constant`s `render.rb` and
`emitter.rb` with a `sig/` mirror and none in `test/` (asserted through `Event` and the two steps);
two top-level test-support doubles, `RecordingSink` and `DiagnosticContext` (**P5-98**); the entry
file's fourteen-line `# Phase 5b:` block after 5c's; and the surface manifest regenerated once from 856
to 956 lines with all 100 rows read against the object model. Five existing tests changed, all on the
code branch as pins the code invalidated: the smoke suite's instrumentation pin (thirteen constants
become twenty-six), 5a's `keys_test.rb` (the eighth key), phase 2's `closeable_test.rb` (the comment
that asserted the drop), and phase 3b's two "nothing constructs a wrapper" pins, which now read
"exactly `step.rb` does". **The postponed work three earlier phases handed here has landed**:
`close_quietly`'s second disposal route (phase 2), `Hooks.notify`'s per-dropped-failure diagnostic
(phase 2's option, taken), and the body-logging caps' two remaining wirings — the shared preview size
read into both phase-3b wrappers and the gating of their construction on `HTTPLogging::BODY`, completing
what 5a half-supplied. **`SEAM-25`'s lifecycle event is half-supplied and not claimed**: the name
(`Events::INSTRUMENTATION_SHUTDOWN`) and the shape (`Instrumentation.diagnostic`) ship; the emission is
phase 8b's Tasks 6 and 10 and the harness phase 9's Task 11. The checklist is at
`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-checklist.md`: twenty-eight
own rows, **26 ✅** (`OBS-24` and `OBS-10` ✅ with the floor's behaviour stated in the row), **2 ⏳** —
`OBS-19` to phase 8c's Tasks 7, 9 and 15 (P5-32, R10; both halves it is built from ship here) and
`OBS-37` post-v1 under `docs/first-release.md`'s `OBS-32`/`OBS-37` entry — nothing 🚫, nothing N/A,
plus fourteen cross-reference rows (`XCUT-19`'s five clauses, `XCUT-20`, `XCUT-11`, `CFG-24`/`CFG-25`,
`CFG-21`, `CFG-14`, `CFG-16`, `SEAM-25`, `BODY-19`/`BODY-22`/`BODY-34`, `BODY-20`, `OBS-23`, `PIPE-28`,
`NFR-11`). `bundle exec rake` is green on 4.0.6 at the tests tip and the docs tip with 99.98% line
coverage (5,655 / 5,656 after review round 2's repair, the registry-claim race branch every phase since 2
has recorded) against the 80% floor and 2,050 runs across the six gems (201 more than the base: the
fifteen new or rewritten instrumentation suites, the five repaired pins, round 0's eight added tests,
round 1's twelve and round 2's seven); the matrix set is green on 3.2.11, 3.3.12 and 3.4.10 — on 3.2.11
under three seeds, round 0 having found one assertion there that held by test order and round 2 one
that held by a one-time allocation's timing; the code tip is green on all seventeen gates
too, run one by one, and clean under the honest RuboCop command on its own tree, its `test:gems` above
the floor on 4.0.6 and on 3.2.11, so the one exception the layering rule allows was not needed; and every
instrumentation suite, 5b's and 5c's, was run standalone under `ruby -w` with `HTTPS_PROXY`, `HTTP_PROXY`,
`NO_PROXY`, `LOG_LEVEL`, `LOG_PREVIEW_BYTES`, `MAX_TRACKED_CONTEXTS` and `MAX_MATERIALIZED_BYTES` exported
to hostile values and stayed green, every configuration a 5b test consults being built over
`FakeConfigSource` seams — the standalone runs being what found Ruby 3.4+'s unused-block warning on
`NULL_SINK`'s writers, which the one-process gate cannot see (fixed: the four writers declare an
anonymous `&` they never yield, at zero allocation), and the four phase-3b and phase-4b tests that read
the live materialisation ceiling, both the **forty-first and forty-second inbound bullets** above. **Every guard the brief asks to be run red was run
red**, forty-eight single-edit mutations on 4.0.6 and again on 3.2.11: forty-four caught on the first
pass, two re-spelled because an unused-variable warning crashed the suite before the assertion could,
and **four found gaps in the suite** — a sink re-entering the logger from inside its own write, the
async path's header redaction, a recording cursor whose `#fork` raises, and the headers level with a cap
supplied — each closed by a test, the second of which exposed a real drift (**P5-95**: the plan's
`Step.build(redactor:)` gated header names on one policy while the logger's events redacted values on
another; there is now one redactor per path, the logger's, and `Logger#redactor` is public); on the
second pass all forty-eight are caught, the mutated event name by `keys_test.rb` as §8.1 asks, and the
floor's four through the floor branches of the floor-aware assertions. **The matrix facts were re-run
on all four interpreters** as a standing test (`logging_matrix_facts_test.rb`): 5c's two floor facts
hold as 5c found them, `Fiber.new(storage: nil)` reads `{}` on the floor and `nil` on 3.3+, and one
fact the design did not flag failed everywhere — `URI#to_s` drops a default port, which `OBS-14`
forbids — so the redactor reassembles from `RFC3986_PARSER.split`'s nine raw components and never
through the setters and `#to_s` (**P5-91**; the design's verified fact 6 and its fact 13, "no
combinator", are the **fortieth inbound bullet** above, documentation half only). The floor decision,
stated once in the checklist: `Diagnostics.capture` compacts nil-valued keys so a snapshot has one shape
on every row, the union restore stays branchless and leaves a snapshot-introduced key present-and-nil
on 3.2 (P5-72 applied to `OBS-24`, **P5-97**), and `OBS-10`'s null-skip is live for every cleared key
on the floor and asserted on every row. **The design's three findings were verified at their owners,
none re-recorded**: §8.1's unsourced `Event#tag` stays on the inbound list and `#tag` is not shipped;
the bare-`Logger` cop watch is closed as built — not expressible in `Dexpace/QualifiedCoreConstant`'s
shape and guarding nothing, since the shadow is confined to `module Instrumentation` (P5-38's
disposition; eight custom cops, 5b adds none); the charter's `OBS-19` cell and `OBS-24` arithmetic read
correct. Forty-one departures from the plan's text are itemised in the checklist, none lowering a
gate — twenty-seven the build's, four review round 0's, six review round 1's, four review round 2's; the
ones that touch public behaviour are the as-built rows **P5-91–P5-109** (also: `Instrumentation.diagnostic` public, the async scope closed at the
head with the `OBS-24` bridge into the settlement, a `Future#then`-derived future at `BODY`,
`Keys::MESSAGE` as the sixteenth key and an ASCII truncation marker, the span named by the method token
until 6a wires the context in). **Review round 0 (2026-09-17) found `OBS-11`'s unconditional userinfo
redaction missing from three routes of `Redactor#header_value`** — a network-path reference on the
relative route, an authority the parser rejected on the surgery route, and the sentinel fallback's raw
value, each reachable through the step at `HEADERS` from a hostile `Location`, which the default
allow-list admits — and `OBS-18`'s header-name gate living only in the private `Emitter`, so a
credential header written straight into `Event#field` reached the sink; both were closed on the code
branch (**P5-100**, **P5-102**), with the two redactor nits the review filed beside them — a bad
percent-encoding in a parameter NAME sentinelling a parseable URL, an opaque URI's query-shaped tail
written back — closed as **P5-101**, an order-dependent floor assertion in the matrix suite and a
102-character line the nested-worktree `rake rubocop` cannot see closed on their owning branches, ten
mutations run red after the repair on 4.0.6 and 3.2.11, the checklist's deviations 28–31 and its second
guard table. **Review round 1 (2026-09-17) found a credential the redactor never saw**: 5a's proxy
resolver interpolates the raw proxy URL into every malformed-URL warning and 5b's config diagnostic
carried that text under `Keys::MESSAGE`, which the reserved-key table does not reach, so
`HTTPS_PROXY=http://user:secret@proxy.corp` wrote `user:secret` into the sink through core's own code —
closed on the code branch by rendering the URL through the redactor's total form plus `CFG-24`'s own
grammar rule for the scheme-less spelling (**P5-103**); and three narrower readings closed beside it —
the reserved-key table ran at `Event#field` alone while the logger's context and the diagnostic fold were
merged raw, now the private `ReservedKeys` over all three of `OBS-5`'s sources (**P5-104**); the surgery
pattern anchored at the scheme let a `Location` with the leading OWS `HTTP-19` admits keep its userinfo
(**P5-105**); and `Preview.decode` raised `Encoding::ConverterNotFoundError` for a charset Ruby knows but
cannot convert, now a UTF-8 fallback (**P5-106**) — with the two mutations that survived the round (the
async failure event's `OBS-24` bridge, the `BODY-35` `-1` filter) given a test each, P5-100's closing
sentence naming the non-authority spellings, ten mutations run red after the repair on 4.0.6 and 3.2.11,
the checklist's deviations 32–37 and its third guard table. **Review round 2 (2026-09-17) found the
surgery route's tolerated-prefix reading one prefix short for the third round running** — RFC 3986
Appendix C's own `<…>` delimiters, quotes, a word, an NBSP, an obs-text byte before a real authority
carried a `Location`'s userinfo through the step, and a QUOTED `HTTPS_PROXY` (the dotenv and ConfigMap
misconfiguration) wrote the client's own credential into both channels — closed on the code branch by
substituting EVERY `//`-authority's userinfo wherever it sits, unanchored and linear, since a value the
parser rejected has no grammar left to honour and `HTTP-19` admits every printable byte (**P5-107**;
what the parser accepts without an authority stays `OBS-14`'s verbatim path); and two narrower readings
beside it — the `Emitter` joined a multi-valued `Location` before the per-value redaction, now redacted
per value at the reserved-key table and joined afterwards (**P5-108**), and the async step's settlement
work sat on the `Future#then`-derived future inside `#then`'s rescue at `BODY`, where a throwing meter
vanished, while the head's `ensure` re-ran the teardown after an inline settlement had raised, now
registered on the source future with the teardown owned by one side (**P5-109**). The round's fourth
finding was the suite's own on the floor: the `OBS-1` zero-allocation measurement came back negative in
about one whole-file run in fifteen on 3.2.11 — a one-time cost of 7 or 28 interpreter objects inside a
measured block — so 5c's shared `AllocationDelta` helper returns the figure two consecutive measurements
agree on, a recorded change to a 5c support file with its five suites re-run green; eight mutations run
red after the repair on 4.0.6 and 3.2.11, the checklist's deviations 38–41 and its fourth guard table.
`docs/sdk-documentation/logging-and-redaction.md` is the as-built page, every fence run verbatim on
4.0.6 and 3.2.11 with the three differences stated where they appear; `architecture.md`, the core
README, `README.md` and `docs/README.md` point at it, and the four earlier pages that described this
layer as unbuilt — `tracing-and-metrics.md`'s "no pipeline step exists yet", `configuration.md`'s
"waits for that layer" and its seven keys, `body.md`'s "nothing in core constructs either" — now read
what is true. `docs/first-release.md` changes in one line — its `CTX-16` entry described the step as
probing `request.respond_to?(:context)`, and the built step probes nothing and names its span by the
method token (P5-99), the conclusion unchanged; its `OBS-32`/`OBS-37` entry names this phase and reads
true, and 5b adds no registry — and `docs/deviations.md` is untouched, for phase 10 to flip; no
harvested rule was found wrong, so `docs/knowledge/notes/` gains nothing. The consolidation of
P5-16–P5-39 and P5-91–P5-106 into design §10 and the §8.1 addendum are a human's, as they were for 3a,
3b, 4a, 4b, 4c, 5a and 5c: `docs/sdk-design-ruby/` is frozen, and no frozen sentence is contradicted
(§8.1's redaction "leans on `URI` for userinfo and query" is honoured by the `split` parse), so no
`C15`. The counts that changed, on top of the 5c docs tip at `032986b`: `dexpace-core`'s `lib/dexpace/`
is one hundred and forty phase-1 through phase-5c files beside phase 0's `version.rb`, eleven
`private_constant`s without a `test/` mirror, eleven checklists, eleven as-built pages, the surface
manifest 956 lines, 53 corpus notes. `CLAUDE.md`'s built-phases paragraph, its gem and
phase-directory sentences and the constraints-that-bite list are rewritten from what was built, for
5b on top of 5a and 5c — the first phase-5 record whose counts need no rebase-and-reprove pass,
because its base already held both siblings.

**2026-09-18** — **Phase 6a implemented**, as three stacked branches against issue #22: code, tests,
documentation, cut from `main` at `f1fe848`, which holds every phase through 5b; phase 6c was built at the
same time off the same `main`, and nothing here describes anything of 6c's as landed. `dexpace-core`
carries the retry layer beside the ten layers before it — nine new `lib/` files: the flat
`error/retry_predicate_error.rb` and, under `resilience/`, `pacing_parsers.rb` (private), `policy.rb`,
`resend.rb`, `retry_settings.rb`, `retry_step_helpers.rb` (private), `retry_step.rb`,
`async_retry_step.rb` and `recovery_retry.rb` — with their `sig/` mirrors, every public one with a
`test/` mirror, and one test file with no `lib/` mirror (`budget_equivalence_test.rb`, the `RETRY-14`
convergence test across all three drivers); eleven earlier-phase files widened in place, each a designed
widening: `http_date.rb`'s day group `(\d{2})` → `(\d{1,2})` (R1: the single-digit day, the weekday still
required and still informational), `error/protocol_error.rb` gaining `#retryable_by_status?` (4b's
postponement, from 5a's `Retryability`, deliberately not `#retryable?`), and the context-bundle widening
across `pipeline/cursor.rb` (`#bundle`, `bundle:` on `.build`, copied by `#fork`), both private drivers,
`pipeline.rb` and `async_pipeline.rb` (`bundle:` on `#call`, still transports by the duck type) and 5b's
`instrumentation/step.rb` / `async_step.rb` (`#open_span(request, bundle)` and the correlation over the
cursor's bundle — 5b's `bundle_for`, which the 6a plan named, never existed); `interface _HTTPTracer`
declared inside 5c's existing `http_tracer.rbs` (R3), the entry file's nine-line `# Phase 6a:` block after
5b's, the surface manifest regenerated once from 956 to 1004 rows with all 48 read against the object
model, and three top-level test-support doubles (`ScriptedTransport`, `ScriptedAsyncTransport`,
`RetryFixtures`) beside phase 2's untouched `FakeTransport`. Five existing tests changed on the code
branch as pins the code invalidated: the smoke suite's layer table (a `RESILIENCE_LAYER`), 4c's
`cursor_test.rb` method-set pin (`bundle`), 5a's `http_date_test.rb` rejection element (the single-digit
day replaced by the bare-date row), and 5b's three `Object.new` cursor stand-ins in `step_test.rb` and
`async_step_test.rb` (each gains `#bundle`). **The postponed work four earlier phases handed here has
landed**: the recovery-stack retry engine — `RECOV-17`–`RECOV-30` and `RECOV-34`, phase 4's segmentation,
each with its own checklist row and its `RETRY` twin as an annotation, phase 4's fifteen ⏳ rows staying
as they are; `ProtocolError#retryable_by_status?`, phase 4b's; `CFG-35`'s throwable half, phase 5a's, as
`Policy.throwable_retryable?`; and the per-attempt half of `OBS-29`'s wiring, phase 5c's — all three
drivers emit `attempt_started`, `attempt_failed` and `retries_exhausted` through `http_tracer_factory:`,
called once per operation with the cursor (stage) or the request (recovery), and `retries_exhausted` only
when a RETRYABLE failure met a spent budget (5c's ordering test's third case). **What stays where it is**:
the operation-lifecycle triple and the transport milestones (phase 10's inbound list and
`docs/first-release.md`'s behavioural-asymmetries entry, both verified rather than re-filed);
`Pipeline.standard` / `AsyncPipeline.standard` — NOT claimed, 6b's Task 13a, over `RetryStep` and
`AsyncRetryStep` which declare `#stage`; `RECOV-31`, `RETRY-29`, `RETRY-38`, `RETRY-43` declined for v1;
`RETRY-4`'s flag on phase 8a's Task 2 (the `P6-4` entry, verified present). The design's R1, R2, R3, R4,
R5, R6 and R15 stand as decided, with R2's mechanism corrected in execution: the plan's async pump
RECURSED — `Future#on_settle` runs inline on a settled future, and the sketch overflowed at ~1,500
zero-length attempts on every interpreter — and the built `AsyncRetryStep::Pump` is a re-arm-flag
trampoline measured flat across 2,001 (P6-54, the forty-third inbound bullet above); a positive
`Async.delay` with no scheduler raises `SeamError` synchronously and the pump's fence fails the future
with it, never a blocking sleep. Three more execution findings, each a guard that would have stayed
green: `0.0 * Infinity` is `NaN` and `[NaN, 8.0].min` raises, so the calculator guards a zero initial
delay (P6-53); a fatal-family error that ARRIVES as an async settlement meets no rescue arm and was
retried until `Pump#delivered?` delivered it unclassified (P6-55); and RuboCop's `Minitest/AssertInDelta`
autocorrection had turned every exact float assertion into a 0.001-delta one, which the degenerate-jitter
guard exposed (the exact cases now carry `0.0`). The checklist is at
`docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-checklist.md`: sixty own rows — fifty-six ✅, one
owner-elsewhere (`RETRY-4`), three ⏳ — plus `RECOV-31` ⏳, the inherited `CFG-35` ✅, and twenty
cross-reference rows; thirty-one guards run red on 4.0.6 and 3.2.11 with one recorded as staying green
and why (the async attempt-boundary check sits behind the cancellation subscription); twenty-four
departures from the plan's text itemised; the design's As-built addendum adds P6-51–P6-58 (6c's rows
start at P6-71, 6b's at P6-91). Every one of the seventeen gates is green on the docs tip on 4.0.6
(2,259 runs, 64,742 assertions, line coverage 99.98 %), the matrix rows on 3.2.11 (100 %), 3.3.12 and
3.4.10, and RuboCop by the honest `--ignore-parent-exclusion` command; the code tip alone, without the
suites, is green on every one of the seventeen gates run individually on 4.0.6 at 95.05 % line coverage
and on the 3.2.11 matrix row, so no tip in the stack is red, not even on the coverage floor.
`docs/sdk-documentation/retry.md` is the twelfth as-built page, every example run on 4.0.6 and 3.2.11 and
identical on both; `architecture.md`, the two READMEs and `docs/README.md` point at it; `CLAUDE.md`'s
built-phases paragraph gains the retry layer, its counts move to one hundred and forty-nine `lib/dexpace/`
files, thirteen `private_constant`s without a `test/` mirror, twelve checklists and twelve pages, and its
constraints-that-bite list gains five lines. `docs/first-release.md` changes in no line — its `P6-4`
entry, its declined-IDs entry and its `OBS-29` entry each read true as built — and `docs/deviations.md` is
untouched, for phase 10 to flip; no harvested rule was found wrong, so `docs/knowledge/notes/` gains
nothing. The consolidation of P6-1–P6-12 and P6-51–P6-58 into design §10 is a human's, as it was for
every phase before: `docs/sdk-design-ruby/` is frozen and no frozen sentence is contradicted, so no `C15`.

**2026-09-18, review round 1 of the phase-6a stack.** Round 0 returned `changes_requested` with two
blocking and five should-fix findings, every one repaired on the branch that owns the file. Blocking:
the three driver suites built their default settings off the LIVE configuration slot (a host
`MAX_RETRY_ATTEMPTS=0` broke the recovery suite, `-1` all three) and now carry the `FakeConfigSource`
seam in their `Fixtures` modules, the seven suites answering identically with the variable set to `0`
and to `-1`; and the public `error/retry_predicate_error.rb` had no `test/` mirror, so
`retry_predicate_error_test.rb` exists and the count sentences read true. Should-fix, on the code
branch with the proof on the tests branch: the pacing parser converted an unbounded digit run (a 10 MB
value stalled the retry decision for seconds and a 400-digit one emitted a Ruby out-of-range warning
the suite's raiser and `parse_form`'s fence had hidden) and now bounds every run at fifteen digits behind
a 64-byte ceiling, answering `nil` in microseconds with no warning (`P6-61`); the sync `RetryStep` emitted
`attempt_failed` outside the `RETRY-35` fence and leaked the superseded response when a tracer raised,
where the async pump closed it — the emission is inside the fence on both; a caller's `should_retry`
answering `true` retried a downstream `CancelledError`, and `Policy.cancellation?` (a ninth public
function, the manifest at 1005 rows) now guards `Policy.retryable?` and the stage drivers' decision ahead
of the predicate and the capability, so a wrapped cancellation is terminal on all three drivers
(`P6-60`); a negative configured `MAX_RETRY_ATTEMPTS` raised at `RetrySettings.build`, leaving `RETRY-41`'s
clamp unreachable from any driver — `.build` takes `logger:` and clamps-and-logs at its one read of
the key, an explicit negative argument still `RECOV-34`'s refusal (`P6-59`); and the at-the-cap jitter
test now asserts samples on both sides of the cap, so round 0's one surviving mutation (jitter before
the cap, then clipped) is caught. Three nits closed: `step.rb`'s comment cites `P6-51`, not `P6-52`;
`RetrySettings#backoff_arguments` and `#header_order` are named in the design's As-built preamble beside
`P6-2`; the retry-after-ms exemption in the totality suite is gone with its cause. Guards 32–37 in the
checklist are the round's, each red on 4.0.6 and 3.2.11. One observation routed nowhere because it is
not a defect: phase 1's inbound `Headers` builder validates a 10 MB header value in about three
seconds, linearly, which is where the wire-value-sized cost now sits — a header-size cap is a transport
adapter's, phase 8's.

**2026-09-18, review round 2 of the phase-6a stack.** Round 1 returned `changes_requested` with one
blocking finding, two should-fix and one nit, every one repaired on the branch that owns the file.
Should-fix, on the code branch with the proof on the tests branch: the sync/async drift round 1 closed
for `attempt_failed` was still open on the terminal path — `RetryStep#settle` emitted `retries_exhausted`
outside any fence, so a tracer that raised there propagated with the terminal error-status response
still open while `Pump#finish` closed it — and the terminal path's emission now runs inside the sync
step's fence, both stage suites asserting the close (guard 38). Should-fix, on the tests branch alone:
round 1's one surviving mutation, a blocking `Clock#sleep` inserted beside `Async.delay`, had left the
async suite green because every async case runs on a `FakeClock` whose `#sleep` records and returns and
nothing read it; the inline, parked and no-scheduler cases now assert `clock.sleeps` empty and a text
scan refuses the token `sleep` in the driver's source (guard 39), with no `lib/` line changed. Blocking,
by the brief's definition, a one-row docs fix: the checklist's `NFR-13` row had claimed every new `.rbs`
opens with the SPDX header, and none does — no `.rbs` in the repository does, and the header reaches
`sig/` with phase 10's Task 5 (`gates:spdx_rbs`) — so the row now claims the twenty new `.rb` files and
points the `.rbs` half at its owner. The nit: three counts inside the checklist were stale after round 1
(48 manifest rows, 1004 rows, `P6-51`–`P6-58`) and read 49, 1005 and `P6-51`–`P6-61`. No ledger row is
added: the terminal fence, like round 1's `attempt_failed` fence, deviates from nothing the design states,
and the design's As-built addendum carries a round-2 paragraph saying so.

**2026-09-18** — **Phase 6c implemented**, as three stacked branches against issue #24: code, tests,
documentation, cut from **`main` at `f1fe848`** — the 5b docs merge, which holds all of phase 5 and
nothing of phase 6a, being built at the same time in another worktree off the same base — so the
`Cursor` context-bundle widening the charter assigns to 6a was **consumed not at all**, the steps
take their own `logger:` keyword, and `AUTH-31` calls phase 3b's `Body#replayable?` directly, as the
design's Independence section said it would when 6a was absent. Every one of the plan's sixteen
tasks plus 11a executed in order, TDD, with no task skipped. `dexpace-core` carries the
authentication layer beside the ten layers before it — twenty-five new `lib/` files: `auth.rb`,
`error/auth_resolution_error.rb` (flat, `AUTH-6`'s general failure) and twenty-three under `auth/`,
from `validation.rb` (the twelfth `private_constant`) and the closed `scheme.rb` through the four
credentials, `challenge.rb` and the `StringScanner` parser `challenges.rb`, `basic_handler.rb` and
`digest_handler.rb`, `challenge_handler_chain.rb`, `key_stamper.rb`, `bearer_provider.rb`,
`bearer_stamper.rb`, `async_bearer_stamper.rb`, the three namespaced errors filed under `auth/`
because the constant path decides the file path (6c's P6-82), and the pillar `step.rb` /
`async_step.rb`; three earlier files widened, each a designed widening — `bounded_map.rb` gains
`#update(key) { |old| new }`, phase 4a's own forward-table addition (the `AUTH-19` and `XCUT-14`
rows), `instrumentation/keys.rb` gains `Events::AUTH_REFRESH`, the ninth event and the first outside
the `http.instrumentation.` prefix (P6-77), and `lib/dexpace.rb` a twenty-five-line `# Phase 6c:`
block after 5b's — with their `sig/` mirrors (twenty-five new, two widened; the strict target green
with no relaxation, no `Digest`, `SecureRandom` or `Random` in any signature because `_Hasher` and
`_CnonceSource` are interfaces); every public file with a `test/` mirror, plus `bounded_map_test.rb`,
the first true mirror of a private constant, so `bounded_map.rb` leaves `CLAUDE.md`'s exception list
as `auth/validation.rb` joins it and the count stays eleven; eight top-level test-support doubles,
one class per file (`ChallengeFixtures`, `FixedCnonce`, `SequencedTransport` — named so as not to
collide with the `ScriptedTransport` 6a is writing at the same time, for the manager to reconcile
after both lanes land — `SequencedAsyncTransport`, `ScriptedBearerProvider`,
`ScriptedAsyncBearerProvider`, `SpyCursor` and `AuthFixtures`); and the surface manifest regenerated
once from 956 to 1 059 lines with all 103 rows read against the object model. Three existing tests
changed, all on the code branch as pins the code invalidated: the smoke suite's layer table and its
preloaded stdlib features (`digest`, or the top-level `Digest` reads as a leak), `seam_surface_test.rb`'s
require pin (four features become five) and 5b's `keys_test.rb` (eight events become nine). **The
postponed work phase 4a handed here has landed** — `BoundedMap#update` — and **6c postpones
nothing**: no ⏳ row, no `docs/first-release.md` entry filed, no deferral. The checklist is at
`docs/work/mvp/phase6/phase6c/2026-09-09-phase6c-authentication-checklist.md`: thirty-eight own
rows, **38 ✅**, nothing ⏳, nothing 🚫, nothing N/A, plus the Task 15 row — the end-to-end
cross-origin convergence test is **written and guarded** on `defined?(Dexpace::Redirect::Step)`, its
body proven against a scratch stub both ways, skipping on this base with a reason that names 6b as
the phase that un-guards it — and twelve cross-reference rows. At the implementer's tips (`528626a`),
`bundle exec rake` is green on 4.0.6
at the tests tip and the docs tip with 99.98% line coverage (6,578 / 6,579 — the registry-claim race
branch every phase since 2 has recorded; every auth file at 100%) against the 80% floor and 2,333
runs across the six gems (283 more than the base, one skip: Task 15's); the
matrix set is green on 3.2.11, 3.3.12 and 3.4.10; the code tip is green on all seventeen gates too,
run one by one, clean under the honest RuboCop command on its own tree, its `test:gems` above the
floor on 4.0.6 and on 3.2.11, so the one exception the layering rule allows was not needed. **The
matrix facts were re-run on all four interpreters** as a standing test (`matrix_facts_test.rb`), the
plan's eight and the design's two floor facts holding identically on every row, and **the four
Digest expectations were derived on every interpreter and never transcribed** — RFC 2617 §3.5's
`qop=auth` vector `6629fae4…`, its legacy no-qop form `670fd8c2…`, RFC 7616 §3.9.1's inputs under
SHA-256 `9fbf3e22…` and SHA-256-sess `a0316f89…`, identical on all four. Two facts neither the plan
nor the design stated were found by the build and hold on every row: **`pp` walks a `Data`'s
members and never calls an `#inspect` override**, so `pp token` printed the secret with `#to_s` and
`#inspect` alone — both `Data` credentials now override `#pretty_print` too (**P6-72**), and
`docs/knowledge/notes/authentication.md` is the corpus's first authentication note, correcting the
harvested two-rendering rule; and **a UTF-8-tagged String with an invalid byte makes
`StringScanner#scan` and `String#downcase` raise**, so the never-raising parser scans such a value
as bytes (**P6-74**). **Every guard the brief asks to be run red was run red**, sixty-one single-edit
mutations on 4.0.6 and again on 3.2.11 plus the cop and the require gate by hand: fifty-seven caught
on the first pass, two re-spelled because an unused-variable warning crashed the suite before the
assertion could, and **two found gaps in the suite, each closed** — the parameter-name fold survived
because the parser folded a second time on top of the model (the parser's duplicate fold is gone and
`Challenge.build` is the one fold point, **P6-83**), and the async step's frame rescue survived every
pipeline test because the driver's own `PIPE-30` normalisation catches a synchronous raise, which is
why `async_step_test.rb` now calls the step directly on a root cursor; one mutation hangs the suite
rather than failing it — a background refresh that waits on its own unsettled fetch — which is the
guard firing as the brief's "a hang there is a finding", reported as an assertion by the `R12 as
code` source scan; on the second pass all sixty-one are caught on both interpreters, the `base64`
mutation by the require gate reading "bundled since 3.4.0" on 4.0.6 and "not in the require
allowlist" on 3.2.11, and the `downcase(:turkic)` mutation by the cop. Twenty-eight departures from
the plan's text are itemised in the checklist, none lowering a gate; the ones that touch public
behaviour, the contract a later phase cites, or a statement the design makes are the as-built rows
**P6-71–P6-83** (6c's numbering, starting at 71 because the three phase-6 lanes are numbered
apart): `Step.build(stamper:, challenge_hook:, logger:)` with `.new` private and no `redactor:`,
`AsyncStep < Step` accepting a `#stamp`- or `#call`-shaped stamper (P6-71); the username redacted
beside the password on `PasswordCredential` (P6-73); `BasicHandler` refusing a colon in the username
and transcoding the pair to UTF-8 before `pack("m0")` (P6-75); `DigestHandler` sending a non-ASCII
username as RFC 7616 §3.4's `username*=UTF-8''…`, declining a challenge whose `realm`, `nonce` or
`opaque` `HTTP-18`'s outbound grammar cannot carry, and matching the algorithm token
case-insensitively (P6-76); the async hook allowed to answer a `Future` (P6-78); every inner future
the async step watches registered through one `observe` that forwards a cancellation as a
cancellation and cancels the inner future when the outer is (P6-79, found when the first draft wired
cancellation only on the cross-origin path); no `Auth::Replayability` module — `AUTH-31`'s gate is
one private `Step#replayable?` that `AsyncStep` inherits (P6-80); `BearerProvider.fetch_async` /
`.conforms?` shipped as `AUTH-11`'s real never-raising default, which the plan never wrote (P6-81);
`Scheme::ALL` public with `.[]` hidden beside `.new`, `Requirement.build(scheme:)` resolving a
String or Symbol through `Scheme.of`, `Descriptor.build(requirements:)` keyword-shaped (P6-83).
**The design's two findings were verified at their owner, `docs/first-release.md`, and not
re-filed** — the `AuthDescriptor` carrier under § Blockers and the query-/cookie-carried `apiKey`
under § What v1 ships without — with one phrase of the first corrected to what was built: the step
takes one `stamper:` and no `Scheme => credential` table. **One finding is new and routed above to
phase 10's inbound list**, by date and content and never by ordinal because 6a's lane is adding to
the same list: after phase 6 the body-replayability predicate has three spellings, two public and
`NFR-4`-locked. `docs/sdk-documentation/auth.md` is the as-built page, every fence run verbatim on
4.0.6 and 3.2.11 as one script (77 checks, identical on both) and no example printing a secret — the
only credential-bearing strings it prints are the header values the layer exists to produce, over
placeholder credentials and the RFCs' published vectors; `architecture.md`, the core README,
`README.md` and `docs/README.md` point at it. `docs/deviations.md` is untouched, for phase 10 to
flip. The consolidation of P6-1–P6-7 and P6-71–P6-87 into design §10 and the §6.3 addendum are a
human's, as they were for 3a through 5b: `docs/sdk-design-ruby/` is frozen, and no frozen sentence is
contradicted — §6.3's `Step.new(…)` spelling is honoured in substance by `.build`, and its
"raise a bare error" reading of `AUTH-21`'s Latin-1 branch by the typed
`UnencodableCredentialError` — so no `C15`. The counts that changed, on top of `main` at `f1fe848`:
`dexpace-core`'s `lib/dexpace/` is one hundred and sixty-five phase-1 through phase-6c files beside
phase 0's `version.rb`, eleven `private_constant`s without a `test/` mirror (`bounded_map.rb` out,
`auth/validation.rb` in), twelve checklists, twelve as-built pages, the surface manifest 1 059 lines
(1 060 after review round 1's one added reader), 55 corpus notes across 22 files. `CLAUDE.md`'s built-phases paragraph, its gem and phase-directory
sentences and the constraints-that-bite list are rewritten from what was built, for 6c on top of
5b — and, because 6a is landing off the same base at the same time, whichever of the two phase-6
lanes merges second rebases its counts and its `CLAUDE.md` sentences over the other's, the 4a
rebase-and-reprove recipe. **Review round 0 (2026-09-18) found one mutation surviving and three
edges in the Digest handler**: `AsyncStep`'s post-eviction routing — `#stamp_fresh`, never `#stamp`,
after an eviction — was asserted only through the real `AsyncBearerStamper`, which fetches through
either method once its cache is empty, so a retry routed through `#stamp` passed every test; a ninth
double, `SpyBearerStamper`, whose two stamps differ on the wire, now tells them apart and the mutation
runs red. `UnencodableCredentialError` named ISO-8859-1 and blamed the challenge for not advertising
`charset=UTF-8` even when the UTF-8 branch raised on a BINARY-tagged credential — the error now
names the branch that raised with a reason worded for it, and the UTF-8 branch also refuses a
UTF-8-tagged credential with an invalid sequence, which `encode` to the same encoding passes through
unvalidated (**P6-84**); `compute` took the nonce count before hashing, so a refused attempt consumed
an `nc`, and now materialises the credential first, the design's own order; the parser's eight
patterns are frozen and pinned with their per-pattern timeout, the plan-equivalent survivor now
caught; and the widening of 5b's `instrumentation/keys.rb` beside `bounded_map.rb` is recorded for
the 6a/6c merge to treat as a shared pair. Seven mutations run red after the repair on 4.0.6 and
3.2.11, the checklist's deviations 29 and 30 and its second guard table; at the repaired tips
(`a6c5bad`) the full rake reports 2,339 runs and 6,583 / 6,584 lines. **Review round 1 (2026-09-18)
found one shape the async step's own class comment claimed covered and a one-character leak the
round-0 checks did not reach**: a challenge hook answering a *future* that fulfilled with a
non-request failed the step's future with the 401 body left open, because the settled value was
checked outside the frame that closes it — `Step#consult`'s rescue is now one `closing_on_error`
frame both runtimes use and the settled value goes through it too; and `UnencodableCredentialError`
carried the rescued `Encoding::UndefinedConversionError` as its cause, per the design's own `R10`,
whose message names the offending character of the password (`U+65E5`) and which `#full_message`
renders on every supported Ruby — both encoding failures are now raised `cause: nil`, the error
carries the value's own encoding as `#source_encoding` instead, `BasicHandler` refuses a field UTF-8
cannot carry as a typed `InvalidArgumentError` in place of the bare conversion error it let escape
(**P6-85**), and `docs/knowledge/notes/error-handling.md` narrows the styleguide's "the original
exception object as the `cause:`" rule for a secret. The round's two suite findings are pinned: the
`AUTH-30` close-before-replay order is now read as the second drive reaches the transport, so a
close-after-drive mutation runs red on both runtimes, and the async stamper's "caches nothing" for a
rejected already-expired token is asserted through `#evict_if_matches`. Twelve mutations run red
after the repair on 4.0.6 and 3.2.11 (the checklist's third guard table, 69–80, and its deviations
31 and 32); at the repaired tips the full rake reports 2,343 runs, 60,129 assertions, one skip and
6,603 / 6,604 lines (99.98%) on 4.0.6, the code tip 92.61% with all seventeen gates green one by one,
and the matrix set 2,343 runs at 99.98% on 3.2.11; the surface manifest is 1 060 lines. **Review
round 2 (2026-09-18) found the async bearer stamper sharing one waiter's cancellation with every
other**: the expired zone derived each request's future from the single-flight slot through
`Future#then`, whose derived future cancels its source, and the source was the one slot every
coalesced request shares — so cancelling one request's future, which the async step forwards to its
stamp future, cancelled every other waiter and every new arrival until the provider settled. The
design's `R12` had prescribed "a second `#on_settle` and a second `Completer`" all along, and the
stamper now builds each waiter's future that way, settled from the slot's settlement and never wired
back to it; a provider cancelling its own fetch cancels the slot and every waiter as a cancellation
(**P6-86**). The round's two suite findings are pinned: the handler-level `AUTH-24` test, which a
read-then-set counter survived under the GVL, now narrows the frozen handler's store so every accessor
but `#update` raises; and the async `#evict_if_matches` carries the sync suite's exactness pins. Seven
mutations run red after the repair on 4.0.6 and 3.2.11 (the checklist's fourth guard table, 81–87, and
its deviations 33 and 34); at the repaired tips the full rake reports 2,348 runs, 60,175 assertions,
one skip and 6,615 / 6,616 lines (99.98%) on 4.0.6, the code tip 92.48% with all seventeen gates green
one by one, and the matrix set 2,348 runs at 99.98% on 3.2.11; the surface manifest is still 1 060
lines, the two methods the repair added being private. **Review round 3 (2026-09-18) found a provider
token both bearer stampers cached and could never send**: `AUTH-35`'s validation was the
requirement's own two checks plus the class check, so a token whose `Bearer <token>` wire form
`HTTP-18`'s outbound grammar refuses — a trailing newline read off a file, a CR — was written into
the cache, where no 401 could ever evict it (`AUTH-36` matches the value a 401 rejected, and the
token is never sent); the sync stamper raised `HTTP-18`'s `InvalidArgumentError` on every later call
with the provider never asked again, and the async stamper's fresh zone raised it synchronously out
of `#stamp`, a method that returns a `Future`, failing every later request through an `AsyncStep`
until the token expired — never, for a token with no expiry. Round 2's own cancellation test had fed
exactly such a token and asserted only that its waiter failed. The grammar check is now the fourth
rejection in `BearerStamper#validate` and `AsyncBearerStamper#invalid`, a `ProviderError` whose
message never names the token, caching nothing, so the next call fetches again; it lives where the
token arrives, as `KeyStamper`'s does at construction, and not in `BearerToken.build`, whose
contract is `AUTH-9`'s non-blank rule (**P6-87**). A cached token therefore always stamps and the
async `#stamp` cannot raise, so `#deliver`'s rescue is re-pinned through a request whose own
derivation refuses. Eight mutations run red after the repair on 4.0.6 and 3.2.11 (the checklist's
fifth guard table, 88–95, and its deviation 35); the round's one nit, two 73-character body lines in
the round-2 documentation commit's message, is deferred to the PR body because rewrapping them would
rewrite an earlier fixer's commit. At the repaired tips the full rake reports 2,353 runs, 60,235
assertions, one skip and 6,621 / 6,622 lines (99.98%) on 4.0.6, the code tip 92.43% with all
seventeen gates green one by one, and the matrix set 2,353 runs at 99.98% on 3.2.11; the surface
manifest is still 1 060 lines, no public method having been added.

**2026-09-19** — **Phase 6c reconciled onto `main` after phase 6a**, by a rebase-and-reprove pass. Phase 6a's
stack merged first (#72 `e437d11` → #73 `153c675` → #74 `905523c`), so 6c's three branches — built off
`f1fe848` and reviewed at `430c527` → `13fe732` → `2039060` — were rebased onto `main` `905523c` with
`git rebase --onto` (rerere disabled), every 6c commit preserved and none reordered. The re-proof's honest
RuboCop run found the one thing the rebase itself could not: the reconciled smoke suite's `Layers` class
carried both lanes' pins and reached 104 lines, over `Metrics/ClassLength`, which the nested-worktree rake
gate does not see — so one `fix:` commit on the code branch moves the two phase-6 cases into a sibling
`PhaseSixLayers` class (the shape phase 4a's reconciliation used), and the stack is `5a74e17` →
`a870f7e` → this paragraph's own commit. Nine files both lanes had changed were reconciled
inside the rebased commits and nowhere else: `gems/dexpace-core/lib/dexpace.rb` (6a's `# Phase 6a:` block,
then 6c's `# Phase 6c:` block, each verbatim), `gems/dexpace-core/test/dexpace_test.rb` (both layer pins,
`RESILIENCE_LAYER` then `AUTH_LAYER`, 6a's "retry layer resolves" case and 6c's `Auth.constants` pin),
`test/fixtures/surface/dexpace-core.txt` (regenerated, not merged: 1,005 rows on `main` plus 6c's 104,
1,109), `CLAUDE.md` (re-derived from the combined tree: "… 5c, 6a and 6c are built", one hundred and
seventy-four `lib/` files beside `version.rb`, thirteen `private_constant` test-mirror exceptions — 6a's
`resilience/pacing_parsers.rb` and `retry_step_helpers.rb` and 6c's `auth/validation.rb` beside the ten
`bounded_map.rb` left when 6c gave it a true mirror — thirteen checklists, both layers in the opening
paragraph, 6a's four and 6c's three "Constraints that will bite" lines), `README.md`, `docs/README.md`,
`docs/sdk-documentation/architecture.md` and `gems/dexpace-core/README.md` (both pages, `retry.md` and
`auth.md`), and this roadmap (both status notes in merge order, and both phase-10 inbound bullets — 6a's,
which numbers itself the forty-third, placed before 6c's dated one so the ordinal stays true). Every file
only one lane touched is byte-identical to that lane's reviewed tip. The 6c checklist's count sentences
describe its own base, `f1fe848`, and say so; the combined tree's counts are `CLAUDE.md`'s. Re-proven at
every rebased tip on 4.0.6 and the matrix rows before the push; the one skip in the suite is still 6c's
guarded end-to-end cross-origin test, which 6b un-guards.

**2026-09-19** — **Phase 6b implemented**, as three stacked branches against issue #23: code, tests,
documentation, cut from `main` at `e61864f`, which holds every phase through 6c — so this is the lane
that landed last and **phase 6 is complete**. `dexpace-core` carries the redirect layer beside the twelve
layers before it — ten new `lib/` files: the flat `error/not_replayable_error.rb` and, under `redirect/`,
`origin.rb` (private), `location.rb` (private), `condition_snapshot.rb`, `events.rb`,
`scheme_downgrade_error.rb`, `chain.rb` (private), `emitter.rb` (private), `reissue.rb` (private) and
`step.rb` — with their `sig/` mirrors, every public one with a `test/` mirror, and three test files with
no `lib/` mirror (`redirect/matrix_facts_test.rb`, `pipeline/standard_test.rb`, and 6c's
`auth/cross_origin_convergence_test.rb`, un-guarded); three earlier-phase files widened in place, each a
designed widening: 6a's `resilience/resend.rb` gains `.replayable_body?` beside `.eligible?` (the plan's
"EXISTS" branch), and 4c's `pipeline.rb` and `async_pipeline.rb` gain the two `standard` constructors
over `Builder#install_preset`; the entry file's ten-line `# Phase 6b:` block after 6c's; the surface
manifest regenerated once from 1 109 to 1 137 rows with all 28 read against the object model; and two
top-level test-support doubles (`RedirectFixtures`, `CredentialProbe`) beside 6a's `ScriptedTransport`,
reused as it is. Three existing tests changed on the code branch as pins the code invalidated — the smoke
suite's layer table (a `REDIRECT_LAYER`), 4c's `async_pipeline_test.rb` (`refute_respond_to` →
`assert_respond_to` on both `.standard`s) and the constructor line of 6c's
`cross_origin_convergence_test.rb` (`.new` → `.build`, forced by 6b's private constructor; its
`defined?` guard stops skipping the moment the code lands, so the test runs and passes on the code
tip) — and three on the tests branch: 6a's `resend_test.rb` (a nested `ReplayableBodyTest`), 6c's
`cross_origin_convergence_test.rb` again (the dead guard line removed, the header rewritten) and 6b's
own `step_test.rb` (a `Cookie` assertion the guards found missing). **The work three
owners handed to "whichever lands second" has landed here**: the `standard` constructors phase 4c
postponed — `Pipeline.standard(over, redirect: nil, settings:, http_tracer_factory:, logger:, level:,
preview_bytes:)` installing redirect + retry + instrumentation, and `AsyncPipeline.standard(over,
redirect:, …)` installing the async retry and instrumentation steps with `redirect: :unsupported` a
REQUIRED keyword admitting nothing else — written over `install_preset` and nothing else, `over` a
transport or a `Pipeline::Builder` so `PIPE-24`'s empty-pillars rule is reachable through the
constructor, closing 4c's `PIPE-39` ⏳ row here while 4c's row stays as its record, and making
`REDIR-25` substantive rather than vacuous; convergence point 1 — 6c's guarded end-to-end cross-origin
credential-leak test — un-guarded against the real step, after a scratch stub that followed the
`Location` but forked without the marker failed it on `Expected ["authorization"] to not include
"authorization"`, so the one skip every `test:gems` run on `main` carried is gone; and 6a's
`Cursor` context-bundle widening consumed **not at all** — a `Bundle` carries a span tracer factory and
trace ids, not a logger, and the step's `logger:` is its own. The design's R7, R8 and R9 stand as
decided, with two of R8's words corrected in execution: the step takes no `redactor:` (one redactor per
logging path, the logger's — 5b's P5-95, 6c's P6-71) and the emitter reads `logger.redactor`; and the
design's own ledger paragraph is corrected by its As-built addendum — the cap is applied OVER a
configured predicate's answer, as R9 argues, never "before a configured predicate is consulted" as the
paragraph and this roadmap's 6b note said (P6-91). Seven more execution findings, each a guard or a
fact: `join` resolves `http:foo` and `http:///p` to host-less URIs without raising, so
`Location.resolve` screens the host as well as the scheme (P6-95); `URI#to_s` elides an explicit `:443`
and `URL.parse!` re-parses from it, so `REDIR-13`'s explicit-port clause has a default-port residue
upstream of this layer, on phase 10's inbound list by date and content (P6-96); the design's
Set-of-URI rationale is false on every row (`URI::Generic` is `eql?` by value) and the `Set<String>`
stands on the external form alone; the plan's malformed fixture `https://user:pass@ht!tp://bad` is a
VALID URI; a raising predicate closes the current response (P6-99); `REDIR-15`'s refusal is emitted
before it is raised (P6-97); and the hop record's status key is 5b's (P6-98). The checklist is at
`docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect-checklist.md`: twenty-eight own rows —
twenty-seven ✅, `REDIR-27` ⏳ — plus the phase-level `PIPE-39`, `PIPE-32`, `PIPE-24` and
convergence-point rows and fifteen cross-reference rows; fifty guards run red on 4.0.6 and 3.2.11, one
recorded as staying green on both and why (an equivalent mutant: the strip is cumulative, so the
seed-versus-previous comparison is observable only through the marker, which its own guard catches);
thirty departures from the plan's text itemised; the design's As-built addendum adds P6-91–P6-100.
Every one of the seventeen gates is green on the docs tip on 4.0.6 (2,705 runs, 67,656 assertions,
0 skips, line coverage 99.98 %), the matrix rows on 3.2.11, 3.3.12 — where the default uri gem prints
a different `InvalidURIError` message and `gates:clean_bundle` loads it, which is why no assertion
matches one — and 3.4.10, and RuboCop by the honest `--ignore-parent-exclusion` command; the code tip
alone is green on every one of the seventeen gates run individually on 4.0.6 and on the 3.2.11 matrix
row, above the coverage floor, so no tip in the stack is red. `docs/sdk-documentation/redirect.md` is
the fourteenth as-built page, every example run on 4.0.6 and 3.2.11 and identical on both;
`pipelines.md`'s two "no `Pipeline.standard` yet" passages are repaired; `architecture.md`, the two
READMEs and `docs/README.md` point at it; `CLAUDE.md`'s built-phases paragraph gains the redirect layer
and the constructors, its counts move to one hundred and eighty-four `lib/dexpace/` files, eighteen
`private_constant`s without a `test/` mirror and fourteen checklists, and its constraints-that-bite list
gains four lines. `docs/first-release.md` changes in one entry — the `PIPE-32`/`REDIR-25`
behavioural-asymmetries line, future-tense about the constructors, now says they were built in that
shape — and its `REDIR-27` entry is cited, not rewritten; `docs/deviations.md` is untouched, for phase
10 to flip; `docs/knowledge/notes/redirect-handling.md` gains one Reference entry closing the userinfo
note's floor caveat on every row. The consolidation of P6-91–P6-100 into design §10 and §6.2's
`URI.join` spelling are a human's, as for every phase before: `docs/sdk-design-ruby/` is frozen, and
§6.2's sentence states the semantics that were built, so no `C15`.

**2026-09-19, review round 1 of the phase-6b stack.** Round 0 returned `changes_requested` with no
blocking finding, two should-fix and two nits, every one on the tests or the docs branch and none
touching `lib/`. Should-fix, both coverage gaps behind a checklist row whose cited test did not prove
the clause it claimed, each found by a mutation that survived on 4.0.6 and 3.2.11: dropping `settings:`
from the sync `Pipeline.standard`'s `RetryStep.build` left `standard_test.rb` green — the default
settings retry a 503 too, after a real backoff on `Clock::SYSTEM`, so the call count could not tell
the two schedules apart — and the sync wiring case now holds its `FakeClock` and asserts the retry's
one wait on it at the flat settings' zero delay, with a second case driving `max_retries: 0` and
asserting the 503 back unretried after one call (guard 51); and keeping `Cookie` and
`Proxy-Authorization` on a cross-origin 303 GET rebuild left the redirect suites green, since every
303 case was same-origin and carried neither header — `ReissueTest` gains the cross-origin 303 over
a `POST` carrying both, the rebuilt `GET` carrying none of the four headers `REDIR-9` and `REDIR-7`
name and keeping `Accept`, and the same-origin 303 keeping the two origin-scoped headers (guard 52).
The addition pushed `WiringTest` over `Metrics/ClassLength`, so the two `PIPE-24` cases and the
`install_preset` source scan moved to an `InstallationTest`, a split and not a disable. The battery is
fifty-two, fifty-one caught on both rows, guard 3 still the one equivalent mutant; the checklist's
`REDIR-9`, `PIPE-39`, `PIPE-24` and `NFR-13` rows and its guard table say so, and its departures from
the plan are thirty-two. The nits: the `NFR-13` row had counted ten new `test/` files where nine were
added (seven suites and two doubles) and reads nine; and the tests and docs commit subjects at 80 and
77 characters, with fifty-five body lines past 72, are left as they are — the fix rules forbid
amending the implementer's commits — and are the squash-merge's to shorten, every commit this round
adds keeping the 74/72 limits. No ledger row is added: the design's As-built addendum carries a
round-1 paragraph saying the round found no behaviour the document states that the code fails to
honour.

**2026-09-19, review round 2 of the phase-6b stack.** Round 1 returned `changes_requested` with one
should-fix on the tests branch and one nit on the docs branch, nothing touching `lib/`. The should-fix:
of fifty-nine mutations the round ran, one survived on 4.0.6 and 3.2.11 on a MUST clause with a real
gap — the fragment dropped from the resolved target left every redirect suite green, because `REDIR-13`
names "path, query, and fragment" and no test in the phase drove a fragment-carrying `Location`, while
the `REDIR-14` case titled "a query-only, a fragment-only and a network-path reference" carried no
fragment and the checklist's `REDIR-14` row claimed one (the code was right: the reviewer's probe showed
`/y#frag` reaching the transport as `https://h/y#frag`). `LocationTest`'s `REDIR-14` chain now carries
the fragment-only reference, which resolves against the current hop and keeps that hop's path and query
(`page=2#only`, never `page=1#only`), and a `REDIR-13` case sends a fragment, a percent-encoded fragment,
an empty query and an empty fragment, each asserted byte for byte on the URL the transport received —
the fragment dropped, the empty query dropped (the corner the round folded in), the empty fragment
dropped and a percent-encoded fragment decoded are guards 53–56, each red on both rows, the first on
two cases. The addition pushed `LocationTest` over `Metrics/ClassLength`, so `REDIR-15`'s three downgrade
cases and `REDIR-18`'s two screen cases moved to a `RefusedTargetTest`, a split by concern and not a
disable; the step suite is eleven nested classes and the checklist's rows, guard table, audit row and
departures cite the new class where a case moved. The battery is fifty-six, fifty-five caught on both
rows, guard 3 still the one equivalent mutant; the docs tip runs 2,708 tests and 67,685 assertions on
4.0.6 with every gate green. The nit — departure 32 said `step_test.rb` had "seven classes" where the
suite had ten — reads eleven now, and the two stale "two" counts for the constructors' suite, which has
been three nested classes since round 1's split, were corrected in the same pass. No ledger row is
added: the design's As-built addendum carries a round-2 paragraph saying the round found no behaviour
the document states that the code fails to honour.

**2026-09-19, review round 3 of the phase-6b stack.** Round 2 returned `changes_requested` with two
should-fix on the tests branch and one nit on the docs branch, nothing touching `lib/`. The
should-fixes: of seventy mutations the round ran, four survived on 4.0.6 and 3.2.11 on two MUST
clauses with real gaps, the code right by the reviewer's own probes on both interpreters. `REDIR-3`
says "there is deliberately NO automatic POST→GET rewrite for 301/302", and no test followed a 301
or a 302 on a non-`GET`/`HEAD` method and asserted the re-issued method or body — the only
method-and-body assertions on a method-preserving hop were `REDIR-4`'s 307/308 cases — so rewriting
the method, dropping the body, or both, on 301/302 alone left every suite green; `ReissueTest` now
follows a 301 and a 302 on a `POST` and on a `PUT` under an allowed set admitting the method and
asserts the original method token, the same body object and the `Content-Type` still travelling on
the transport's second call (guards 57–59). `REDIR-5` says "case-insensitively", and every 303 case
carried canonical casing, so a prefix test that dropped the fold survived; a new case whose `POST`
carries `content-type`, `CONTENT-LENGTH` and `cOnTeNt-Language`, in that casing on `Headers#names`,
asserts each gone from the rebuilt `GET` with `Accept` alone left (guard 60). `ReissueTest` was at
97 code lines, so its four 303 cases, two constants and two helpers moved unchanged to a
`RebuildTest`, which the new fold case joins — a split by concern and not a disable; the step suite
is twelve nested classes and the checklist's `REDIR-3`, `REDIR-5`, `REDIR-9` and `HTTP-13` rows, its
guard table, its audit row and its departures cite the new class where a case moved. The battery is
sixty, fifty-nine caught on both rows, guard 3 still the one equivalent mutant. The nit —
`docs/README.md` said "the thirteen pages written so far" while listing fourteen — reads fourteen.
No ledger row is added: the design's As-built addendum carries a round-3 paragraph saying the round
found no behaviour the document states that the code fails to honour.

**2026-09-20** — **Phase 7b implemented**, as three stacked branches against issue #27: code, tests,
documentation, cut from `main` at `c53638b`, which holds every phase through 6b and none of 7a or 7c —
the three phase-7 lanes were built concurrently off the same base, so nothing here describes a sibling's
work as landed and the one convergence point the charter names is built in full with the pagination
layer's globs on a printed `PENDING` list, their move to `GUARDED` being the reconcile pass's after both
lanes are on `main`. `dexpace-core` carries the server-sent-events layer beside the thirteen layers
before it — nine new `lib/` files: the namespace file `sse.rb` (the three limits and the two sentinel
constants) and, under `sse/`, `sentinel.rb`, `limit_exceeded_error.rb`, `stream_state_error.rb`,
`line_reader.rb`, `event.rb`, `reader.rb`, `stream.rb` and `typed_stream.rb` — every one public, with
its `sig/` and `test/` mirrors, and three test files with no `lib/` mirror (`sse/matrix_facts_test.rb`,
`sse/boundaries_test.rb`, `sse/documentation_test.rb`); the entry file's nine-line `# Phase 7b:` block
after 6b's; 3a's `io/typed_reads.rb` YARD on `#read_line_utf8` corrected in place (`SSE-11` → `SSE-19`,
and its false premise replaced — Task 12's code half); the surface manifest regenerated once from 1 137
to 1 180 rows with all 43 read against the object model; three top-level test-support files
(`SSEFixtures`, `ScriptedChunked`, `FakeByteSource`) beside the tree's own `FakeResponseBody`,
`FakeChunked`, `RecoveryFixtures` and `RecordingSink`, which answered four of the plan's five doubles
without a new file; the smoke suite's `SSE_LAYER` and `PhaseSevenLayers` case; and **the eighteenth
gate**, `gates:serde_boundary` — `tools/serde_boundary.rb`, a PARSED scan (prism for every require
spelling and every constant read or path, the RBS lexer for every type name) over `lib/dexpace/sse.rb`,
`lib/dexpace/sse/**` and their `sig/` mirrors, asserting every guarded glob matches a file and printing
its two pending pagination globs on every run — with `test/gates/serde_boundary_test.rb`, twenty-one
fixtures and two fixture workspaces, wired into `DEFAULT_GATES` after `gates:require_allowlist`,
`default_task_test.rb`'s `EXPECTED` and CI's once-per-run `gates` job (not the matrix; a text scan has
no interpreter dependence), so that "seventeen" reads "eighteen" in `CLAUDE.md`, `README.md` and
`docs/sdk-documentation/quality-gates.md`. **The four decisions the manager took on the cross-check's
open questions were applied as given**: the sentinel type is `Sentinel`, not the design's `Signal`,
because `::Signal` is a core module a bare `Signal` inside `module Dexpace::SSE` would shadow (P7-81);
7b built the boundary gate alone, with `page/**` pending (P7-84); the three `Stream` factories take
`logger:` and `SSE-30`'s swallowed release failure is a real `http.instrumentation.close` emission
through `Dexpace.close_quietly(self, logger:)` — never a second path (P7-83); and
`docs/knowledge/notes/sse-streaming.md` is filed, two supersessions (`2dba42b0`'s "current retry value,
last event id"; `8c25db7d`/`e98a0668`'s machine-over-the-primitive) and three references. The design's
R4, R5, R6 and R11 stand as decided: the two caps are `MAX_LINE_BYTES` (1 MiB) and `MAX_EVENT_BYTES`
(8 MiB), rejecting and never truncating, per-reader keywords and no configuration key, both strictly
below 3a's ceiling by assertion, and the line-cap finding phase 3a opened is closed with its three
corrections — the bound exists at the layer the finding named, the obliging ID is `SSE-19` and not
`SSE-11`, and `#read_line_utf8` ends v1 unbounded and with no in-repository caller because `IO-14` and
`SSE-2` disagree about a lone CR (P7-20, P7-21); `SKIP` and `DONE` are two frozen singletons compared by
identity and `Dexpace::Outcome` gains nothing (P7-23); `SSE-31`'s two shapes are both written and both
deterministic, the blocked-read one over `BufferedSource.wrapping` of an `IO.pipe` with the wrapping
source as its own resource, and the mechanism claim inherits `IO-38`'s deferral as the design said it
would. Execution found four things the design or the cross-check stated that the tree does not bear
out: `_ByteSource` needs a fourth method, `close`, because the reader closes its peek view (P7-82);
`Response#body` is typed `Dexpace::Body?`, not `ResponseBody?`; after a mid-stream failure
`BufferedSource.over`'s enumerator RESTARTS rather than answering nil, on every row (phase 3a's
residue, on phase 10's inbound list by date and content, with the throughput of the per-byte read path
— ~0.9 µs a byte, which is why the at-scale cap tests run over the duck source — beside it); and the
member named `retry` cannot be re-assigned or forwarded by name in Ruby, so `Event#initialize` forwards
with a bare `super` and validates the hint after it. The typed layer's block form is a plain loop over
`Stream#each` and its external form drives the raw enumerator taken eagerly at `#values`; the facade's
one failure path is `Stream#drive`'s `rescue ::Exception` in 6a's and 6b's spelling, and every
block-form exit — `Enumerable#first(n)` on `#events` and on `#values` alike — closes loudly through the
owning drive routine's `ensure` (P7-86). The checklist is at
`docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events-checklist.md`: forty-one own rows —
forty ✅, `SSE-41` ⏳ (declined for v1, cited) — plus the cross-reference rows, the matrix facts on every
interpreter, the guards run red, the audit groups, thirty-seven departures from the plan's text, the
findings routed and the postponed work; the design's ledger gains an "As built" addendum, P7-81–P7-86,
whose consolidation into design §10 and the §10.18 amendment for both cap constants are a human's, as
for every phase since 3a; `docs/sdk-documentation/sse.md` is the as-built page, every example run on
4.0.6 and 3.2.11; `docs/first-release.md` is untouched, its `SSE-41` entry still true as written.
`7a` and `7c` remain to land; the reconcile pass moves the boundary gate's `page/**` rows to `GUARDED`
once 7c's files are on the same base. **Review round 0 (2026-09-20)** found two defects the suites
could not see and one file the checklist cited that the tree did not hold, all three repaired on the
owning branch: `Reader#dispatch` returned nil for a fieldless block before resetting it, so a run of
unknown-field keep-alives, NUL ids or rejected retries accumulated into `SSE-19`'s event cap across the
blank lines that separate them (a fresh block per blank line is `SSE-1`'s own clause); the typed
layer's `#values` had `Stream#drive`'s rescue and not its `ensure`, so `values.first(1)` stranded the
resource where `events.first(1)` released it; and `stream_state_error_test.rb` was written. Guards 51
and 52 are the round's, red on both rows against the pre-fix `lib/`; no public name, signature or
manifest row changed.

**2026-09-20** — **Phase 7c implemented**, as three stacked branches against issue #28: code, tests,
documentation, cut from `main` at `c53638b`, which holds the whole of phase 6, concurrently with 7a and
7b on the same base — so nothing of theirs is on this tree, and phase 7's one convergence point, spec-forced
boundary 5's audit, went to 7b's Task 11 by the manager's decision of the same day: 7c builds no
`gates:serde_isolation`, no `tools/` file and no fixture, and `page_test.rb` scans the fifteen files under
`lib/dexpace/page/` and `page.rb` for the tokens `Serde` and `JSON` (comments included, because 7b's scan
reads them) until 7b's `PENDING` row for `page/**` flips to `GUARDED` on the second lane to rebase.
`dexpace-core` carries the pagination layer beside the thirteen layers before it — fifteen new `lib/`
files: `page.rb` (the page value, the namespace, `.next_request_from`) and, under `page/`,
`page_state_error.rb`, `info.rb`, `query_rewriter.rb`, `link_header.rb` (private), `cursor_strategy.rb`,
`page_number_strategy.rb`, `link_strategy.rb`, `walk.rb` (private), `closing.rb` (private), `items.rb`,
`pages.rb`, `paginator.rb`, `async_paginator.rb` and `fetchers.rb` — with their `sig/` mirrors (the three
interfaces `_Strategy`, `_Extractor` and `_Executor` nested in `sig/dexpace/page.rbs`, because a `sig/`-only
file fails the gem-layout gate), every public one with a `test/` mirror, two suites with no `lib/` mirror
(`page/matrix_facts_test.rb`, `page/lifetime_test.rb`); one earlier-phase file widened in place, a designed
widening: phase 1's `http/url.rb` gains `URL.resolve` beside `.parse!` (P7-3); the entry file's
fifteen-line `# Phase 7c:` block after 6b's; the surface manifest regenerated once from 1 137 to 1 214 rows
with all 77 read against the object model; and two top-level test-support doubles (`PageFixtures`,
`ProbeExecutor`) beside 6a's `ScriptedTransport` / `ScriptedAsyncTransport`, 3b's `FakeResponseBody`, 4b's
`RecordingBody` and phase 2's `InlineExecutor`, reused as they are — **no Response double**: every response
in the suite is a real `Dexpace::Response`. Two existing tests changed: the smoke suite's layer table (a
`PAGE_LAYER`) with a `PhaseSevenLayers` class (the eleven public constants under `Page`, the six private
names unreachable, the fourteen nested names shadowing nothing — the design's P7-2 audit as a standing
test) on the code branch, a pin the gates read; and phase 1's `http/url_test.rb` (a nested `ResolveTest`
over the widened `URL.resolve`) on the tests branch, a new test rather than an invalidated pin. **The
design's R7, R8, R9 and R10 stand as decided, with R8's prescription corrected in execution**: the measurement is right — a bare `ensure` inverts `PAGE-13`/`PAGE-32`'s primary —
but its `primary = $!` is wrong the other way, because `$!` is the CALLER's inside anything called from the
caller's `rescue` (`pipeline/7ce4431d`, re-measured on every row), so the frame that owns the walk records
the primary in a `rescue ::Exception => error` arm and hands the local to `Page::Closing.close_walk`, and
`$!` appears nowhere under `page/` (P7-105). **Every one of the 36 `PAGE` IDs is ✅** — 35 outright and
`PAGE-35` vacuous by construction on design §12's authority — and no ⏳ row is added. The other execution
findings, each a ledger row or a guard: the items are owned shallowly, never through `Model.own`, which
deep-copies and raises on a Proc (P7-101); the blocking engine passes `Cancellation.none` to the
transport and takes no per-walk token — a nil dies inside `Pipeline.standard`'s retry step (P7-102);
`PAGE-14` raises `Page::PageStateError`, a state error and never `InvalidArgumentError`, so **the
`PAGE-14`/`SSE-26` inbound bullet of 2026-09-13 above is half closed — the argument-family half — and its
shared-supertype half stays on this list** for phase 10 (P7-103); `Page.next_request_from` screens a
resolved target for an http/https scheme and a host, consistent with `REDIR-18` (P7-104); every private
constant has a `sig/` mirror and 8b's plan Task 9 is told the interface's real file (P7-106); the
extractors', a strategy's and a fetcher's answers are checked, never read as end-of-stream (P7-107); the
walk future settles with the page count (P7-109); the fatal family closes the response on a parse failure
too (P7-110); the `Walk` is generic over a per-walk drive so `Fetchers` reuses it (P7-111); the executor
runs the FIRST dispatch too (P7-112); a block-less `Pages#each` claims the latch on obtaining the
enumerator (P7-113); the page-number screen is ASCII `[0-9]+` (P7-114); and the link grammar's
malformed-input rule (P7-115); and, from review round 0 (2026-09-20), `Page.build` names a `next_link`
or `continuation_token` that is not a String the way `Info` already did (R0-1, P7-107) and `LinkHeader`
reads only the first `rel` parameter of a link-value, RFC 8288 §3.3's rule (R0-3, P7-116); and, from
review round 1 (2026-09-20), `Walk#release`'s slots-cleared-before-the-raise invariant is pinned — the
round's one surviving mutation, now guard 48 (R1-1) — and a fragment-only `rel=next` target (`<#>`,
`<#frag>`) is end-of-stream before resolution as the empty one already was, RFC 3986 §4.4's two
same-document forms read together and read syntactically, never off the resolved URL (R1-2, P7-117,
guard 49). The checklist
is at `docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-checklist.md`: thirty-six own rows,
all ✅, plus the boundary-5 row (owner 7b) and twelve cross-reference rows; forty-nine guards run red
on 4.0.6 and 3.2.11, none surviving; thirty-two departures from the plan's text itemised; the design's
As-built addendum adds P7-101–P7-117. Every one of the seventeen gates is green on the docs tip on 4.0.6
(2,925 runs, 68,978 assertions, 0 skips, line coverage 99.98 % — the one uncovered line is phase 2's
`registry.rb:253`, as on `main`; every line under `lib/dexpace/page/` and in `url.rb` is exercised,
the shape refusals included), the matrix rows on 3.2.11, 3.3.12 and
3.4.10, and RuboCop by the honest `--ignore-parent-exclusion` command; the code tip alone is green on
every one of the seventeen gates run individually on 4.0.6 and on the 3.2.11 matrix row, above the
coverage floor, so no tip in the stack is red. `docs/sdk-documentation/pagination.md` is the fifteenth
as-built page, every example run on 4.0.6 and 3.2.11 and identical on both; `architecture.md` retires the
planned `write-a-paging-strategy.md` into it; the two READMEs and `docs/README.md` point at it (the root
`README.md`'s built-phases sentence had omitted 6b, and `docs/README.md`'s layer sentence too — both now
name it beside 7c); `CLAUDE.md`'s built-phases paragraph gains the pagination layer, its counts move to
one hundred and ninety-nine `lib/dexpace/` files, nineteen `private_constant`s without a `test/` mirror
and fifteen checklists, its `SEAM-27` constraint line names `URL.resolve`, and its constraints-that-bite
list gains four lines. `docs/first-release.md` is untouched — the `PAGE-36` conformance test is 8a's Tasks
13 and 20 already, `C13` already carries `P7-1`, and the blocking engine's missing `cancellation:` keyword
has no ID to file under; `docs/deviations.md` is untouched, for phase 10 to flip;
`docs/knowledge/notes/pagination.md` gains four Reference entries (the SSE-under-`PAGE-14` pair, the
`BODY-11` attribution, §12's unharvested serde-agnosticism, and R8's `$!` finding). The consolidation of
P7-1–P7-6 and P7-101–P7-117 into design §10 — beside 7a's P7-1–P7-9, which collide with 7c's by number,
knowingly — and the `PAGE-15` addition to §12's `PAGE` row are a human's, as for every phase before:
`docs/sdk-design-ruby/` is frozen.

**2026-09-20** — **Phase 7c reconciled onto `main` after phase 7b (server-sent events)**, by a
rebase-and-reprove pass. Phase 7b's stack merged first (#81 `90abdb8` → #82 `eacf165` → #83 `34f52e8`),
so 7c's three branches — built off `c53638b` and reviewed at `d319e8a` → `58d45af` → `cd12764` — were
rebased onto `main` `34f52e8` with `git rebase --onto` (rerere disabled), every 7c commit preserved and
none reordered, and the stack is `3a1f0a4` → `549e683` → this paragraph's own commit. Two commits are
the pass's own, one per branch that needed one: on the code branch, `chore: guard page/ in
gates:serde_boundary now that 7c is on the same tree` — the flip 7b's tool said would happen "in the
change that lands the files": the two `page/**` rows move from `PENDING` to `GUARDED` and `page.rb` and
`page.rbs` gain rows beside them (a `**` under a directory cannot match the file beside it, the reason
`sse.rb` has its own row), each violation naming "spec-forced boundary 5"; `PENDING` is empty and stays
as the mechanism; the gate's test asserts nothing pending, the four rows and "8 guarded globs clean",
both fixture workspaces gain clean page files so `empty_glob` still reports exactly one empty glob, and
the guard was proven to bite by hand — a `Dexpace::Serde` read appended to `page/info.rb` and a
`require "json"` appended to `page.rb` each ran the gate red before being reverted. On the docs branch,
this paragraph's commit carries what no 7c commit could: `CLAUDE.md`'s and `quality-gates.md`'s
`PENDING` sentences now say guarded, 7b's checklist gains one dated line at its item 15, and 7c's
checklist a dated paragraph, its boundary-5 row's note and one line at its item 30. Eight files both
lanes had changed were reconciled inside the rebased 7c commits and nowhere else:
`gems/dexpace-core/lib/dexpace.rb` (7b's `# Phase 7b:` block, then 7c's `# Phase 7c:` block, each
verbatim — 7c's comment still says "after 6b's block", which stays true with 7b's between),
`gems/dexpace-core/test/dexpace_test.rb` (both layer pins, `SSE_LAYER` then `PAGE_LAYER`, and the two
same-named `PhaseSevenLayers` classes merged into one carrying 7b's SSE case then 7c's pagination case),
`test/fixtures/surface/dexpace-core.txt` (the auto-merge was already the regenerated manifest, confirmed
by a `surface:regenerate` that changed nothing: 1,180 rows on `main` plus 7c's 77, 1,257 — `URL#resolve`
and the seventy-six `Page` rows, nothing of `Walk`, `Closing` or `LinkHeader`), `CLAUDE.md` (re-derived
from the combined tree: "… 6c, 7b and 7c are built", two hundred and eight `lib/` files beside
`version.rb` with two hundred and eight `sig/` mirrors, nineteen `private_constant` test-mirror
exceptions — `main`'s eighteen and `page/closing.rb` — sixteen checklists, both layers in the opening
paragraph, 7b's four and 7c's four "Constraints that will bite" lines), `README.md` (both layer
sentences; its built-phases sentence, which `main` had left at "… 6a and 6c", names every built phase
in merge order), `docs/README.md` (both layers, both pages, sixteen pages),
`docs/sdk-documentation/architecture.md` and `gems/dexpace-core/README.md` (both pages, `sse.md` and
`pagination.md`), and this roadmap (both status notes in merge order; the phase-10 inbound list is
`main`'s forty-seven bullets — 7b's two, cited by date and content — and 7c adds none). Every file only
one lane touched is byte-identical to that lane's reviewed tip, the flip's tool and test excepted. The
7c checklist's and status note's count sentences describe its own base, `c53638b`, and now say so; the
combined tree's counts are `CLAUDE.md`'s: eighteen gates, the test suite at 3,146 runs, 70,084
assertions, 0 failures, 0 errors, 0 skips and 99.98 % line coverage on 4.0.6 at the tests tip. Re-proven
at every rebased tip on 4.0.6 and the matrix rows before the push, `gates:serde_boundary` with the
pagination rows guarded at every one of the three.

**2026-09-20** — **Phase 7a implemented**, as three stacked branches against issue #26: code, tests,
documentation, cut from `main` at `c53638b`, which holds every phase through 6b — the first of phase
7's three sub-phases to be built, in parallel with 7b, 7c and 8a on the same base, and the first phase
in the roadmap to write into two gems. `dexpace-core` carries the serialization layer beside the
thirteen layers before it — eleven new `lib/` files under `serde/`: `decode_context.rb`, `witness.rb`
(reopening phase 2's `Dexpace::Serde` for `WITNESS_METHOD`, `DUMP_METHOD`, `.witness?` and `.witness!`),
`native.rb` (`Native` and `OMIT`), `scalars.rb` (the private table and the public `BOOLEAN`),
`tristate.rb` (`ABSENT`, `NULL`, `Present`, the private `Combinator` behind `Tristate.of`), `list.rb`,
`map.rb`, `nullable.rb`, `instant.rb`, `decoding_handler.rb` and `status_aware_handler.rb` — every one
with a `sig/` mirror and a `test/` mirror (no new `private_constant` file: the layer's private constants
all live inside public files), plus `tristate_decode_test.rb`, `body_serialized_test.rb` and
`no_concrete_codec_test.rb` beside the mirrors; one earlier file widened in place, 3b's `http/body.rb`
gaining `Body.serialized(value, serde:)`, the ninth factory; phase 2's `sig/dexpace/serde.rbs` edited in
place — its `interface _Codec` was never empty (the design's headline finding rests on a false premise
and is withdrawn in the As-built addendum; the phase-10 inbound bullet at the `_Codec` residue carries a
dated bracketed correction) — with `#media_type` widened to `(Dexpace::MediaType | String)`, `#load`
narrowed over a new `Dexpace::Serde::_Witness` and `#dump_to` to `Integer`; and the entry file's
eleven-line `# Phase 7a:` block after 6b's, in dependency order. **`dexpace-serde-json` is the
workspace's second real gem**: `lib/dexpace/serde/json/codec.rb` (`Codec`, the six seam methods over one
private `::JSON::Coder` per instance, a five-key option allowlist over one positional Hash, `strict:
true` and `allow_duplicate_key: false` fixed by the codec, `encoders:` never forwarded), the entry file
rewritten with `MINIMUM_JSON_VERSION` asserted at require time as `SeamError`, `REQUIRED_CORE = "~> 0.0"`
on the registration under `:json`, and `.default` / `.build`; the gemspec's `json >= 2.19.9` line — the
first `NFR-2` third-party half spent, and the first time `gates:gemspec_audit`, `gates:require_allowlist`
and `gates:clean_bundle` ran against a gem carrying one, all three green on every matrix row; the
Steepfile's `:serde_json` target alone downgrading `Ruby::UnknownConstant` to `:information` (rbs 4.2.0
declares no `JSON::Coder` and json 3.0.2 ships no `sig/`, so the second route of the manager's decision
(1), with the ivar typed `untyped`); the smoke test reshaped to snapshot after `require "dexpace"`; and
four new suites beside it
(`codec_test.rb`, `codec_load_test.rb`, `defaults_test.rb`, `seam_conformance_test.rb` over the
phase-9 lift target `test/support/serde_seam_assertions.rb`, `composition_test.rb` walking
`Operation` → `Pipeline.standard` → `TypedResponse` over a recording lambda transport), with two new
close-counting doubles. The surface manifests were regenerated once, core 1 137 → 1 210 and the adapter
2 → 15, all 86 rows read against the object model and no private constant among them. **Five existing
core pins changed on the code branch as pins the registration invalidated** — an adapter that
self-registers at require time makes "starts empty on a bare require" false in `rake test:gems`'s one
process — `seam_surface_test.rb`'s two seam-iterating pins and `serde_test.rb`'s "starts empty" pin now
assert in a child process that requires `dexpace` alone (`instrumentation/independence_test.rb`'s
`IO.popen` shape; 8a is converting the same two `seam_surface_test.rb` lines, and the reconcile pass
keeps one copy), and `serde_test.rb`'s two swap pins assert the override is gone rather than that
nothing resolves. **What the plan did not know, and the tree decided** (the checklist's "Deviations from
the plan", thirty-one items; the design's As-built addendum P7-61–P7-72): the empty-body screen is
`BufferedSource#eof?`, never `#content_length` or a parser message; `FakeResponseBody` is the counting
body and no `CountingResponse` double exists; `.build` plus `private_class_method :new, :[]` with
validation in `#initialize` on every `Data`; `DecodeContext.build` is public; `StatusAwareHandler`'s
members are its three build keywords; a `#call`-shaped object is not a witness; the composition slice
runs `Pipeline.standard`, not `.direct`, over a lambda, since core's `FakeTransport` is out of another
gem's reach; the `SEAM-2` scan reads code through Ripper, because two core comments name the adapter;
and `JSON::Coder` is strict on its own account, so `strict: true` is documentation and `Native` is the
observable layer (guard 19 stays green on every row, an equivalent mutant). **Every guard the brief
lists was run**: thirty-four single-edit mutations on 4.0.6 and 3.2.11, thirty-one caught on both rows,
guard 3 (`Data#with` in place of `Model#with`) caught on 3.2.11 alone as predicted, and two equivalent
mutants recorded with their reasons (19, and 21 — the parse rescue's scope is the parse alone, so
widening it cannot reach the drain; 21.5 widens the drain and is red); plus the four gate mutations
(a second `add_dependency`, `require "json"` in a core file, a `::JSON::Coder` ivar type, a `::JSON`
type in a public signature), each red under its gate. **Postponed items that landed:** phase 3b's
`TypedResponse` has its two handlers; phase 2's `_Codec` clauses are settled; the knowledge-lookup
skill's thirteenth audit row gained `constraints,conclusions` (the design's narrowness finding, a
one-cell edit). **What stays where it is:** `SERDE-27`'s no-materialization clause (`7a P7-1`, the
`docs/first-release.md` entry, whose first owed half — the documented ceiling behaviour — closed with
`docs/sdk-documentation/serde.md` and whose second waits on phase 8); `dexpace-serde-oj`'s second motive
(already on its post-v1 entry); the `Present` fourth-state closure on the 3.2 floor is proven by
`test:gems` on 3.2.11, where the guard alone goes red. One new phase-10 inbound bullet, by date and
content: `gates:clean_bundle` installs into the interpreter's gem directory and fetched json 3.0.2 from
rubygems.org into 3.3.12's and 3.4.10's on this run. `CLAUDE.md` gains 7a's built-phase sentence, the
layer paragraph, 184 → 195 `lib/` files, fifteen checklists, the gem's `lib/` sentence and five
"Constraints that will bite" lines; `docs/sdk-documentation/serde.md` is the fifteenth page, every
example run on 4.0.6 and 3.2.11; `docs/knowledge/notes/serde.md` is new with two entries (the UTF-8
validation the design drafted, and the json 2.19.9 → 3.0 `Coder` option drift the build measured).
Gates at the docs tip on 4.0.6: all seventeen green, `test:gems` 2 944 runs / 68 966 assertions /
0 skips at 99.96% line coverage (the counts after review round 2's five added cases), the honest RuboCop clean, `rbs:validate` and `steep` clean, YARD
100%; the matrix subset green on 3.2.11, 3.3.12 and 3.4.10. The consolidation of P7-1–P7-9 and
P7-61–P7-72 into design §10 is phase 10's and a human's; `docs/deviations.md` is untouched.

**2026-09-20, review round 1 of the phase-7a stack.** Round 0 returned `changes_requested` with two
should-fix findings and three nits, nothing touching `lib/`. The first should-fix was a scope breach
on the code branch: the feat commit had rewritten three lines of `rbs_collection.yaml`'s header comment
to correct its stale "json arrives with the codec in phase 7" sentence — a shared file the brief lists
out of bounds for 7a, which phase 8a rewrites with its first row, and which no gate reads — so the
hunk is dropped in a `fix:` commit, the file is as `main` has it, and the stale sentence is one new
phase-10 inbound bullet by date and content, for whichever lane adds the first row to close. The second
was a survivor among the forty-two mutations the round ran: dropping the codec's explicit
`allow_duplicate_key: false` default left every suite green on 4.0.6 and 3.2.11, because json 3.0.2 —
the bundle's version on every row — refuses a duplicate key by default, and regressed to a
warning-plus-last-wins only at the 2.19.9 floor, which no gate row runs. The option is now pinned at
the keyword level: `codec_test.rb`'s fourth nested class, `CoderKeywordsTest`, runs a child process
that prepends a recorder onto `::JSON::Coder`'s singleton class (a permanent patch to a library class,
so never in the suite's own process — `context_store_config_test.rb`'s shape) and asserts every keyword
`.new` receives across four constructions. The battery is thirty-five, thirty-three caught on both rows,
guard 3 on 3.2.11 alone and guard 21 the one equivalent mutant: guard 34 is the round's, red on 4.0.6
with json 3.0.2 and on 3.4.10 with json 2.19.9 pinned unbundled, and guard 19 (`strict: true` dropped),
equivalent behaviourally, is red at the keyword level through the same pin. The nits — the five
response fixtures `serde.md`'s last example used without defining, now built in the block; the
`CLAUDE.md` sentence counting three serde pins in the child process where one is and two swap pins
assert the override gone; and the sentence above, which called the Steep relaxation "the manager's
route (1)" where it is the second route of decision (1) — are corrected in place. No ledger row is
added: the design's As-built addendum carries a round-1 paragraph saying the round found no behaviour
the document states that the code fails to honour.

**2026-09-20, review round 2 of the phase-7a stack.** Round 1 returned `changes_requested` with two
should-fix findings and two nits. Both should-fixes were survivors among the fifty-nine mutations the round
ran — behaviours the design states and the checklist claimed pinned, where the code was right and the proof
was not. The first: `DecodingHandler`'s empty-body screen (P7-67) reduced from `raise missing_body if
source.eof?` to a bare probe left every suite green on both rows, because the one empty-body case asserted
only that the message names `PetWitness`, which the witness's own shape failure over the drained `""`
names too; through the real codec an empty 200 then read `malformed JSON: unexpected end of input`, naming
no target. The case now asserts `no body` beside the target and `composition_test.rb` drives an empty 200
through `Pipeline.standard` and the real codec (guard 23.5; guard 23's row corrected — its third failure
was the `eof?`-probe case, not the empty body). The second: P7-7's require-time floor assertion was
exercised by nothing — every gate row runs the bundle's json 3.0.2 — so deleting the block left all six
adapter suites and every gate green while stock Ruby 4.0's json 2.18.0, which has a `JSON::Coder`, loaded
and registered. `json/floor_test.rb` now drives it in a child process with `RUBYOPT`, `RUBYLIB` and the
`BUNDLE_*`/`BUNDLER_*` keys cleared, pinning the interpreter's default json by exact version with `gem`
before the require (2.6.3 / 2.7.2 / 2.9.1 / 2.18.0 across the matrix, each refused with the `SeamError`
naming the floor and the active version) and the running json beside it (loads, registers under `:json`);
its expectation is computed from the entry file's own comparison, so a future Ruby whose default json clears
the floor keeps it meaningful (guard 35). The nits: the two handler messages rendered an anonymous witness
as an empty name ("decode into : the response carried none") and now read `an anonymous witness` through a
private `#target_name` in each — two `lib/` lines, two `sig/` lines, no public surface, P7-70's row amended
in place (guard 36); and the gate line above, which still carried round 0's run count. The battery is
thirty-eight, thirty-six caught on both rows, guard 3 on 3.2.11 alone and guard 21 the one equivalent
mutant. No ledger row is added.

**2026-09-20** — **Phase 7a reconciled onto `main` after phases 7b (server-sent events) and 7c
(pagination)**, by a rebase-and-reprove pass, which completes phase 7: its three sub-phases were built
concurrently off `c53638b` and landed 7b, 7c, 7a, so umbrella #25 closes by hand once this stack is
merged. Phase 7b's stack merged first (#81 `90abdb8` → #82 `eacf165` → #83 `34f52e8`) and 7c's reconciled
stack after it (`3a1f0a4` → `549e683` → `79877b5`), so 7a's three branches — built off `c53638b` and
reviewed at `ae15acb` → `04aad28` → `408698e` — were rebased onto 7c's reconciled docs tip `79877b5`,
whose tree is what `main` holds once those three squashes land, with `git rebase --onto` (rerere
disabled), every 7a commit preserved and none reordered; the stack is `e5a32ff` → `7a675c4` → this
paragraph's own commit, the pass's one commit of its own, on the docs branch, carrying what no 7a
commit could: this paragraph and the dated "Reconciled" note at the head of 7a's checklist. One
repair to the pass's own work: the conflict stop on the feat commit ran its message through git's
default comment cleanup, which dropped the three body lines that begin with `#media_type` and
`#read_utf8`, so that commit was reworded back to its original message verbatim (same tree, same
author and date) and the stack re-parented over it before any of the tips below were recorded; all
nine messages now equal the reviewed ones. No test needed a repair and nothing was built. Seven files both sides had changed were reconciled inside
the rebased 7a commits and nowhere else: `gems/dexpace-core/lib/dexpace.rb` (7b's `# Phase 7b:` block,
7c's `# Phase 7c:` block, then 7a's `# Phase 7a:` block, each verbatim — 7a's comment still says "after
6b's block", which stays true with the other two between), `test/fixtures/surface/dexpace-core.txt`
(the auto-merge was already the regenerated manifest, confirmed by a `surface:regenerate` on the rebased
code tip that changed nothing: 1,257 rows on the base plus 7a's 73, 1,330 — the same 73 rows 7a's own
delta added over `c53638b`, all under `Dexpace::Serde` and `Body.serialized`, none removed and no private
constant among them; `dexpace-serde-json.txt` 2 → 15 as before; the other four manifests unchanged),
`CLAUDE.md` (re-derived from the combined tree: "… 6c, 7b, 7c and 7a are built" and the whole of phase
7; two hundred and nineteen `lib/` files beside `version.rb` with two hundred and nineteen `sig/`
mirrors — 7b's nine, 7c's fifteen and 7a's eleven over phase 6's 184; the same nineteen
`private_constant` test-mirror exceptions, 7a adding none, every one of its eleven files mirrored on the
tests branch; seventeen checklists; every merged lane's layer sentence and 7a's in the opening
paragraph, in merge order; 7b's four, 7c's four and 7a's five "Constraints that will bite" lines;
eighteen gates everywhere the base says so), `README.md` (both layer sentences and 7a's, the gem table's
`json >= 2.19.9` row, "the other four are still skeletons"; its built-phases sentence, which 7a's own
branch had not touched, names 7a beside 7b and 7c), `docs/README.md` (all three layers and all three
pages, seventeen pages), `docs/sdk-documentation/architecture.md` (the `sse.md` and `serde.md` entries,
the `write-a-serde.md` placeholder pointing at `serde.md`, and its opening list, which 7a's own branch
had left at fourteen pages without `serde.md`, re-derived to seventeen), and this roadmap (every status
note in merge order — 7b's, 7c's, 7c's reconciliation, then 7a's with its two review-round paragraphs;
the phase-10 inbound list at forty-nine bullets, the base's forty-seven plus 7a's two, each cited by
date and content). Every file only one lane touched is byte-identical to that lane's tip: 7a's own
(`docs/first-release.md`, `.claude/skills/knowledge-lookup/SKILL.md`, `docs/knowledge/notes/serde.md`,
`docs/sdk-documentation/serde.md`, `gems/dexpace-serde-json/README.md`, 7a's checklist before this
pass's note, its design, the Steepfile's `:serde_json` block, every file under `lib/dexpace/serde/`,
`gems/dexpace-serde-json/` and the two gems' `sig/` and `test/` trees) to `408698e`, and the merged
lanes' (`gems/dexpace-core/README.md` among them — 7a's docs branch never touched it, so it names the
server-sent-events and pagination layers and not the serialization layer, a gap this pass records
rather than closes) to `79877b5`. 7a's checklist's and status note's count sentences describe its own
base, `c53638b`, and now say so. Re-proven at every rebased tip: the code tip green on every one of the
eighteen gates run individually on 4.0.6 (`test:gems` 3,151 runs, 70,100 assertions, 0 failures, 0
errors, 0 skips, 97.82 % line coverage — above the floor, so no tip in the stack is red) and on the
3.2.11 matrix row, `gates:serde_boundary` reporting its eight guarded globs clean with `serde/` beside
them; the tests tip green on the whole default task on 4.0.6 (3,380 runs, 71,339 assertions, 0 skips,
99.96 % line coverage), on the matrix set on 3.2.11, 3.3.12 and 3.4.10, and on the core suite under a
second seed on 4.0.6 and 3.2.11 with identical run counts (3,286), the five converted registry pins
re-run with all three phase-7 layers loaded in one process and `composition_test.rb` by name; the docs
tip green on the default task, the honest RuboCop run, the probe, the knowledge-structure verifier and
every `ruby` fence of `serde.md`, `sse.md` and `pagination.md` on 4.0.6 (`serde.md`'s tenth fence run
with `require "stringio"` prepended, the nit 7a's review recorded).

**2026-09-20** — **Phase 8a implemented**, as three stacked branches against issue #30: code, tests,
documentation, cut from `main` at `c53638b`, which holds every phase through 6 — concurrently with 7a, 7b
and 7c off the same base, so this is the phase-8 lane that landed **first** and the first code outside
`dexpace-core`. Three things the charter left to "whichever lands first" are this lane's:
`Dexpace::TransportError < ::IOError` in `lib/dexpace/error/transport_error.rb` (`#retryable?`
unconditionally true, `#phase` for the record and never a decision — `XCUT-4`'s retryable transport
failure and the answer to 6a's P6-4 blind spot), `Instrumentation::Events::TRANSPORT_HEADER_DROPPED` (the
tenth event) beside `Configuration::Keys::REQUEST_TIMEOUT`, and the require-allowlist's `tempfile` line;
`Transport.async_over` over a real socket stays 8b's. **`dexpace-transport-net_http`** carries
`Dexpace::Transport::NetHTTP`: the entry file's eight constants, `.build(timeout:, logger:, tls:)`,
`.using(client, logger:)`, `.default` and the require-time `Transport.register(:net_http, …)` — the
version-skew guard's first real registration — and eight files under `net_http/`, `adapter.rb` public
and the seven `private_constant`s `deadline.rb`, `failures.rb`, `request_mapper.rb`,
`response_mapper.rb`, `response_pump.rb`, `tls_settings.rb` and `proxy_route.rb`, every one mirrored in
`sig/` and in `test/`; its gemspec declares `net-http >= 0.4` with no upper bound, the first third-party
half of an `NFR-2` budget in the repository. **`dexpace-conformance`** carries `Dexpace::Conformance`:
the assertion protocol phase 0 postponed (`Failure`, `Vacuous`, `Assertion`, `Result`, `Report`), the
twenty-eight-assertion `TransportSuite` over its five private groups and `Checks`, `TransportCase` with
its `SettleOnly` guard, `BorrowedPair`, the `WireServer` fixture with `RecordedRequest` and the private
`RequestReader`, the fifteen `Scripts`, `MinitestDriver`, the opt-in `RSpecDriver` and the two doubles
5c and 5b assigned here, `RecordingSpan` and `Allocations` — twenty-two new files, every one mirrored in
`sig/`, the three with no test file of their own (`checks.rb`, `recorded_request.rb`,
`request_reader.rb`) proven through their owners' suites. The repository gains
`test/support/net_http_warmup.rb`, a `BUNDLE_PATH`-scoped `clean_bundle_check`, `library "socket",
"tempfile"` on the `Steepfile`'s `:conformance` target, and three surface manifests regenerated once —
core 1 137 → 1 142, net_http 2 → 17, conformance 2 → 100 — with every added row read against the object
model. Three earlier-phase test files changed on the code branch as pins the two new constants moved
(`keys_test.rb`, `instrumentation/keys_test.rb`, `downstream_wirings_test.rb`), the smoke suite's layer
table gained the phase, and core's `transport_test.rb` and `seam_surface_test.rb` moved their
registry-key assertions to a bare-`ruby` subprocess (`test/support/bare_require.rb`), because in one
`test:gems` process the adapter's require-time registration is visible to every suite. **The design's
fifteen rows stand; `R1`–`R7`, `R16`, `R17` and `R18` were built as written**, with the As-built addendum
adding `P8-51`–`P8-65`: the head is adapted on the caller's thread inside `head_or_raise { … }` before the
producer reads a byte of body, because `R4`'s deletion of an unparseable `Content-Length` needs an
ordering `R1` never stated — the `TRANSPORT-27` assertion was red against the real adapter until the
handshake existed (P8-51); the pump owns the cancellation subscription for the life of the response
(P8-52); on the borrowing construction the one permit is returned by the producer's own `ensure` and a
push through the closed queue, never a `break`, is what makes `Net::HTTP` close a half-read keep-alive
socket (P8-53); a closed-queue pop is classified through the token and is end of stream only when the
pump is open (P8-54); the shared suite carries no `TRANSPORT-12` or `TRANSPORT-13` row and `TRANSPORT-18`
is vacuous by measurement, so the Minitest driver reports one skip against the real adapter, not the
plan's four (P8-55); `await_closed_connection(count = 1, timeout:)` is bounded and `Scripts.fixed` /
`.large` take `hold:` (P8-56); a nil cancellation is the never-cancelled token and `.build` validates
`timeout:` (P8-57); `ResponseMapper` logs a `TRANSPORT-14` drop by name (P8-58); the public-surface
additions are listed (P8-59); and the two version-bound `net-http` facts — `supply_default_content_type`
absent on 0.9.1, the connect phase `Timeout.timeout` below 0.7 and `TCPSocket.open(open_timeout:)` on
0.9.1, whose first call starts a process-wide thread the warm-up parks (P8-60–P8-62); and, from review
round 1 (2026-09-20), the inbound `Content-Length` grammar is a bounded, timed `Regexp.new` in the adapter
and the fixture alike, core's spelling for a pattern a wire value reaches, superseding the design's
"carries no `timeout:`" sentence (P8-63); and, from review round 2 (2026-09-20), the pump asks the
token before it starts a producer, so a token already cancelled at construction gets a closed pump with
no thread, no socket and the borrowed permit straight back, where the reviewed pump had raised
`NoMethodError` on a nil subscription from inside its constructor after the request was on the wire
(P8-64); and, from review round 4 (2026-09-20, the manager-sanctioned targeted round after round 3), a
`Content-Length` beside `Transfer-Encoding: chunked` is the unknown-length sentinel, because `net-http`
frames such a response by the chunked coding and the header was never the number of bytes the pump
delivers — taken as one it truncated `#each`, `#write_to` and `#to_replayable` while `#body_string` read
the whole body (P8-65). The checklist is at
`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-checklist.md`:
twenty-three own rows — twenty-two ✅ and `TRANSPORT-28` ✅ on two clauses with its zero-copy clause ⏳
under `docs/first-release.md` — plus the phase-level `TransportError` row and sixteen cross-reference
rows; the reviewer's thirty mutations run red on 4.0.6 (net-http 0.9.1) and 3.2.11 (pinned to 0.4.1),
twenty-nine caught on both and the thirtieth an equivalent mutant with its measurement (`String#<<` into
an emptied UTF-8 buffer adopts BINARY on every row), and review round 0's three surviving mutations —
the `TRANSPORT-22` guard over a body that drained itself, the `TRANSPORT-6` clamp under `assert_in_delta`'s
default 0.001, and `P8-52`'s detach — made red in round 1 with three guards beside them (rows 31–36),
and round 2's two (the pre-cancelled pump, the proxy keys) with three more beside them (rows 37–41),
round 3's fixture clients (rows 42–44) and round 4's three — the chunked-length guard, the closed-pump
read round 3 found untested and the handler join it found unguarded (rows 45–47); the gem's suites
blank the three proxy keys the resolver reads around every owning-adapter test through the override
tier (`NetHTTPHermeticProxy`), because every `NetHTTP.build` resolves its proxy through the process-wide
chain and a host's `HTTPS_PROXY` routed fifteen of the adapter suite's thirty-four tests to it — and, from
review round 3 (2026-09-20, for round 2's R2-1), every raw `Net::HTTP` a suite starts passes an explicit
nil proxy, because the library's own `:ENV` default reaches uri's `find_proxy`, whose upper-case-`HTTP_PROXY`
warning the test base makes fatal, so both gems' suites are hermetic under `HTTP_PROXY`, `http_proxy`,
`HTTPS_PROXY` and `NO_PROXY` alike; the design's seventeen facts and the plan's eight
re-run on 3.2.11, 3.3.12, 3.4.10 and 4.0.6, twelve of them as `matrix_facts_test.rb` printing the row's
active `Net::HTTP::VERSION` (0.9.1 a default gem on 4.0.6, as on every row — review round 2's R2-3
corrected the checklist and the knowledge note, which had read this machine's installed copy beside it as
the gem having left the default set); forty-four departures from the plan's text itemised — thirty-six
from the build, two from review round 1, four from round 2, one from round 3 and one from round 4 —
among them the two the whole-repository `test:gems` process found and the gem's own `rake test` never
could: the adapter's sink double renamed `NetHTTPRecordingSink` because core's `test/support/` already
owns the bare name and a second `Entry =` is an `NFR-6`-fatal warning at load, and `RawWireTransport`'s
`leave_open` defect keeping its socket referenced, since an unreferenced `TCPSocket` is closed by GC inside
the release assertion's wait. One guarded test: the generator slice's codec half skips with `skip "phase 7a's
Dexpace::Serde::JSON::Codec is not on this base; 7a un-guards"`, so `test:gems` carries two skips until 7a
lands — that one and `TRANSPORT-18`'s measured vacuity. `docs/sdk-documentation/transport-net_http.md`
and `conformance.md` are the fifteenth and sixteenth as-built pages, every example run on 4.0.6 (0.9.1)
and 3.2.11 (0.4.1) and identical on both but for `Hash#inspect` and the Timeout thread's count;
`architecture.md`, both gem READMEs, `README.md` and `docs/README.md` point at them; `CLAUDE.md`'s
built-phases paragraph gains the two gems and core's three additions, its counts move to one hundred and
eighty-five `lib/dexpace/` files and fifteen checklists, its gem sentences say what each adapter gem's
`lib/` now holds, "Nothing talks to a socket yet" is gone, and its constraints-that-bite list gains six
lines. `docs/first-release.md` changes in existing entries only — the `P6-4` blocker ticked, the
conformance-suite and `P8-9` documentation blockers each gaining a dated status sentence, the Minitest 6
entry narrowed, the `BODY-12` clause-2 and `TRANSPORT-28` entries confirmed on all three `net-http`
versions; `docs/deviations.md` is untouched, for phase 10 to flip; `docs/knowledge/notes/transport-adapter.md`
gains one Reference entry with the two version-bound facts. Three dated bullets join phase 10's inbound
list above — the Timeout thread as the connect-phase finding's observable, rbs 4.2.0's
`TCPServer#initialize` signature Steep refuses, and 6b's `REDIR-23` wall-clock bound failing under
machine load in the whole-repository process — a fourth from review round 1, 6a's `RETRY-42` /
`RECOV-28` eight-thread test erring on an interleaving under the same load — and a fifth from review
round 2, `Status`'s `100`–`599` guard against `Net::HTTP`'s three-digit parse, a phase-1 model question
in the shape of the `"http/1.0"` one — each by date and content,
never by ordinal, because the three phase-7 lanes are writing to the same list. The consolidation of `P8-1`–`P8-15` and `P8-51`–`P8-64`
into design §10 is a human's, as for every phase before: `docs/sdk-design-ruby/` is frozen.

**2026-09-21** — **Phase 8a reconciled onto `main` after the whole of phase 7 — 7b (server-sent events),
7c (pagination) and 7a (serialization)**, by a rebase-and-reprove pass. Phase 7 merged first — 7b (#81
`90abdb8` → #82 `eacf165` → #83 `34f52e8`), 7c (#84 → #85 → #86) and 7a (#87 `4fa99d8` → #88 `1b38b25` → #89
`734e6b3`), `main` at `734e6b3` — so 8a's three branches, built off `c53638b` concurrently with the three
phase-7 lanes and reviewed at `20c00d0` → `4776940` → `6908c86`, were rebased onto `main` with `git rebase
--onto` (rerere disabled), every 8a commit preserved and none reordered or reworded: the stack is `bb909ba`
(code, six commits) → `a36a9d2` (tests, eight) plus `705d864`, the one test commit the pass added → `b458899`
(docs, six) plus this paragraph's own commit, the pass's one commit of its own on the docs branch, carrying
what no 8a commit could: this paragraph, the dated "Reconciled" note at the head of 8a's checklist, the
phase-10 bullet below it, the closure of 7a's `gates:clean_bundle` bullet, and the paragraph
`gems/dexpace-core/README.md` owed 7a. **Three decisions.** (1)
`gems/dexpace-core/test/dexpace/seam_surface_test.rb` was resolved to `main`'s content byte for byte:
7a converted its two seam-iterating pins through a private `bare_require_report` helper (merged as #88),
8a converted the same two lines through a new shared `test/support/bare_require.rb`, and the reviewed,
merged conversion wins; 8a's hunk to that file is dropped, its `BareRequire` module and
`transport_bare_require_test.rb` stay because 8a's own suites and both adapter gems' smoke suites use them,
and the two-spellings-of-one-idiom debt is a dated bullet on phase 10's inbound list above. (2) The
generator slice's codec half (8a's Task 19c) is un-guarded on the tests branch as `705d864`: with 7a's
`Dexpace::Serde::JSON::Codec` on the tree the `skip` is dead, and the case needed two repairs by the
minimum, both to the test alone — an explicit `require "dexpace/serde/json"`, and the three lines that
read the mapped error through 4b's design names (`error.headers`, `error.body.source.read_fully`) now
read `error.response.headers` and `error.response.body_string`, the as-built `ProtocolError` carrying the
buffered response; it runs green against the real codec (a 200 decodes to the witness, a 404's buffered
body reads twice after the socket is gone, an `ABSENT` field is omitted and a `NULL` one kept), and the
whole suite's skip count is **one**, `TRANSPORT-18`'s measured vacuity. (3) 7a's inbound bullet on
`gates:clean_bundle` installing into the interpreter's gem directory is closed by 8a's Task 23 on this
tree — the scratch bundle's `BUNDLE_PATH` sits under the gate's own scratch directory — and the bullet
says so in a dated bracket, deleted from nothing. **Reconciled inside the rebased 8a commits and nowhere
else**: `gems/dexpace-core/lib/dexpace.rb` (7b's, 7c's and 7a's blocks as `main` has them, then 8a's
`# Phase 8a:` block, each verbatim), `gems/dexpace-core/test/dexpace_test.rb` (`SSE_LAYER`, `PAGE_LAYER`,
then `TRANSPORT_LAYER` in the `LAYERS` table; the merged `PhaseSevenLayers` class untouched),
`test/fixtures/surface/dexpace-core.txt` (the auto-merge was already the regenerated manifest, confirmed by
a `surface:regenerate` on the rebased code tip that changed nothing: `main`'s 1,330 rows plus 8a's 5 —
`TransportError` and its two readers, `Keys::REQUEST_TIMEOUT`, `Events::TRANSPORT_HEADER_DROPPED` — 1,335,
none removed and no private constant among them; `dexpace-transport-net_http.txt` 2 → 17 and
`dexpace-conformance.txt` 2 → 100 as before; 7a's `dexpace-serde-json.txt` 15 and the other two at 2
unchanged), the `Steepfile` and `tasks/gates.rake` (auto-merged; each diff against `main` is exactly 8a's
own hunk — `library "socket", "tempfile"` on `:conformance` beside 7a's `:serde_json` block, and the
`BUNDLE_PATH` scoping beside 7b's `gates:serde_boundary` task), `CLAUDE.md` (re-derived from the combined
tree: "… 7b, 7c, 7a and 8a are built", the whole of phase 7 and the first of phase 8's sub-phases; **220**
`lib/dexpace/` files beside `version.rb` with 220 `sig/` mirrors — phase 7's thirty-five and 8a's one over
phase 6's 184 — and the same nineteen `private_constant` test-mirror exceptions, 8a adding none, the
mirror walk over all three gems it touched finding exactly the three named under `dexpace-conformance`;
eighteen checklists; every merged lane's layer sentence and 8a's in the opening paragraph, in merge order,
with "Nothing talks to a socket yet" replaced by 8a's sentence and 8a's two gems stated as the third and
fourth real ones, after 7a's codec; 7b's, 7c's, 7a's and 8a's "Constraints that will bite" lines; the
skeleton clause naming the two remaining skeletons; eighteen gates everywhere `main` says so, and the
`gates:serde_boundary` command line kept), `README.md` (every layer sentence and 8a's two gem sentences,
the gem table's `net-http >= 0.4` row beside 7a's `json >= 2.19.9`, "the other two are still skeletons";
its built-phases sentence names 8a beside 7b, 7c and 7a), `docs/README.md` (all four gems' contents,
**nineteen** pages), `docs/sdk-documentation/architecture.md` (the `transport-net_http.md` and
`conformance.md` entries after `serde.md`'s, the `write-a-transport.md` placeholder pointing at both, its
opening list re-derived to nineteen pages), `docs/first-release.md` (auto-merged: 8a's seven hunks in
existing entries beside 7a's `SERDE-27` half-closure, each verified to survive), and this roadmap (every
status note in merge order — 7b's, 7c's, 7c's reconciliation, 7a's with its two review-round paragraphs,
7a's reconciliation, then 8a's — and the phase-10 inbound list at **fifty-five** bullets: `main`'s
forty-nine, 8a's five and this pass's one, each cited by date and content). 8a's status note above says
this lane was "the first code outside `dexpace-core`" — true on `c53638b`, not on `main`, where 7a's
`dexpace-serde-json` landed first (#87) and holds the version-skew guard's first real registration; the
note is left as written and 8a's checklist note says so. Every file only one lane touched is byte-identical
to that lane's tip: 8a's own (the two adapter gems' `lib/`, `sig/`, `test/`, READMEs and gemspecs,
`lib/dexpace/error/transport_error.rb` with its `sig/` and `test/` mirrors, the two `keys.rb` widenings and
their moved pins, `test/support/bare_require.rb`, `transport_bare_require_test.rb`,
`test/support/net_http_warmup.rb`, `tools/require_allowlist.rb` and its fixture, the two surface manifests,
`docs/sdk-documentation/transport-net_http.md` and `conformance.md`, `docs/knowledge/notes/transport-adapter.md`,
8a's design, and its checklist before this pass's note — 84 code-branch files, 40 tests-branch files but
`generator_slice_test.rb`, and 8a's docs files but the six reconciled ones) to `6908c86`, and the merged
lanes' (206 files `main` changed since `c53638b` that 8a did not, `.claude/skills/knowledge-lookup/SKILL.md`
among them — its transport audit row has been there since the roadmap brainstorm, and 8a's docs branch
adds nothing to it) to `734e6b3`. `gems/dexpace-core/README.md` gains, in this paragraph's commit, the
serialization-layer paragraph 7a's reconciliation recorded as owed, a sentence for 8a's three core
additions, and `serde.md` in both of its page lists. Re-proven at every rebased tip: the code tip green on
every one of the eighteen gates run individually on 4.0.6 (`test:gems` 3,381 runs, 71,349 assertions,
0 failures, 0 errors, 0 skips, 93.02 % line coverage — above the floor, so no tip in the stack is red;
the honest RuboCop run over 630 files clean; `gates:clean_bundle` loading all six gems with three
declared third-party or default gems under the scoped `BUNDLE_PATH`) and on the 3.2.11 matrix row
(3,381 runs, 71,351 assertions); the tests tip green on the whole default task on 4.0.6 (3,698 runs,
72,656 assertions, 0 failures, 0 errors, **1 skip**, 99.88 % line coverage; the honest RuboCop run over
669 files clean), on the matrix set on 3.2.11 (net-http 0.9.1, 72,658 assertions), 3.3.12 (0.4.1) and
3.4.10 (0.6.0) at 3,698 runs and one skip each, and on the core suite under seed 31337 on 4.0.6 and
3.2.11 with identical run counts (3,295) — 8a's `transport_bare_require_test.rb` and both adapter gems'
smoke-suite registration proofs green with three registering adapter gems in one `test:gems` process,
and 6b's `REDIR-23` ten-second bound green in every whole-process run of this pass; the docs tip green
on the default task, the honest RuboCop run, the probe, the knowledge-structure verifier, the
housekeeping and knowledge test suites, and every `ruby` fence of `transport-net_http.md` and
`conformance.md` (with `require "dexpace/conformance"` and the lead's `NetHTTP`, `WireServer`, `Scripts`,
`EMPTY`, `req` and `headers` shorthand defined, the proxy keys blanked as the lead says the suites do) and
of `serde.md`, `sse.md` and `pagination.md` once more, on 4.0.6 — every `# =>` matching (`serde.md` 69,
`sse.md` 55, `pagination.md` 62, `conformance.md` 27) but the ephemeral port four of
`transport-net_http.md`'s fifty-five name, which its lead excepts, and with `conformance.md`'s fifth
fence, the consumer template over a fictional `MyAdapter` with `...` placeholders, not run, as it
cannot be. `main` is `734e6b3` before and after; 8b and 8c are not on it, and umbrella #29 stays open
for them.

**2026-09-21** — **Phase 8b implemented**, off `main` at `a7cfeb6` (the whole of phase 7 and 8a), concurrently
with 8c off the same base, as three local branches — `31-phase-8b-async-runtime-adapter` (code),
`-tests` and `-docs` — each cut from `main` and each green under every gate on its own tree, the code tip
above the coverage floor as well. `dexpace-async-thread` is the workspace's fifth real gem:
`Dexpace::Async::Thread::Pool` — `.build(size:, queue_limit:, shutdown_timeout:, name:, logger:, clock:)`
with `size:` required and no default, `#post` as `Dexpace::Page::_Executor` exactly and never blocking
(`RejectedError` on a full queue, `Dexpace::ClosedError` on a closed pool, both translated from the queue's
own errors at the one call site and routed to the failure channel by phase 2's bridge), `#delay` on one
lazily created timer thread settling with `true`, and `Dexpace::Closeable`'s latched `#close` draining
the workers and stopping the timer within one budget before emitting `Events::INSTRUMENTATION_SHUTDOWN`
once — the lifecycle event phase 2 postponed on 2026-09-07, **landed**; the harness half stays phase 9's
Task 11. The pooled worker clears its fiber storage at two boundaries (thread start and after every
task, `P8-20`) so 5b's `Diagnostics.with` installs the caller's snapshot rather than merging it onto
the pool builder's or the previous task's; `REQUIRED_CORE` and a direct require-time version-skew
assertion stand in for a registry the seam deliberately has none of (`P8-21`); the timer thread carries
the worker's `rescue ::Exception` net (`P8-22` extended). Nineteen rows: **seventeen ✅, `ASYNC-3` ⏳**
citing `docs/first-release.md`'s unsatisfied-MUST entry, **`ASYNC-4` N/A** on §10.5 alone, and the two
cross-reference rows the charter names — `PIPE-33`'s four met clauses re-asserted through a real pool
(a two-step pipeline posts exactly once) with clause 5 staying phase 4c's ⏳, and `ASYNC-6`'s thread-pool
half stated. The charter's convergence point 2 is this lane's, because 8a landed first:
`gems/dexpace-async-thread/test/dexpace/async/thread/composed_transport_test.rb` drives 8a's
`Dexpace::Transport::NetHTTP` through `Transport.async_over(adapter, executor: pool)` against
`dexpace-conformance`'s `WireServer` — the first time the async path touches a socket — and nothing under
the gem's `lib/` names either sibling (`P8-73`). **What the cross-check found and the build confirmed**:
phase 2's `Bridge::AsyncOver` checks the token before dispatch (#44), so the design's finding 2 was closed
before this phase began and a task cancelled while queued never reaches the transport; phase 0's
`DexpaceTestCase` already counts threads at `teardown` (#36), closing finding 3; `Completer#fulfil(nil)`
raises, so `#delay` settles with `true` (`P8-71`); the plan's `CORE_REQUIREMENT` is 7a's `REQUIRED_CORE`
(`P8-72`); on the 3.2 floor a cleared worker's raw storage is a map of nil-valued keys, so the suite reads
through `Diagnostics.capture` and its ensure-clear proof writes a never-held key (`P8-74`); and
`Timer#schedule` after `#stop` refuses the entry rather than spawning a thread `#close` never joins
(`P8-75`); and, from review round 0 the same day, a `#close` issued from the pool's own threads — a
`#delay` future's `#on_settle` handler on the timer thread, or a task on a worker — completes instead of
self-joining (`P8-76`: the first cut raised `ThreadError` past `#close` with the latch flipped, no event
and every other delay stranded, or burned the whole budget); and, from review round 1 the same day, a
`NaN`, an infinite or a `Complex` duration or `shutdown_timeout:` is refused with `InvalidArgumentError`
(`P8-77`: a `NaN` answers false to both `negative?` and `zero?`, reached the timer's deadline-ordered
list, killed its thread and turned every later `#delay` into a bare `ArgumentError`, and a `NaN` budget
raised one out of `#close` with the latch flipped — core's two duration guards share the shape and are
the second of this phase's bullets on phase 10's inbound list); and, from review round 2 the same day, the
timer thread behind `#delay` — the gem's second `::Thread.new` carrier, spawned lazily from the first
delay caller's fiber — carries each delay's diagnostic context the way a worker carries a task's (`P8-78`:
as first cut it inherited the first caller's storage and got neither of `P8-20`'s clears and no per-delay
snapshot, so every later delay's `#on_settle` and `#then` ran under a stale, foreign context — the design's
own finding 1 at the gem's own door); and, from review round 3 the same day, the `P8-22` defect
diagnostic — the one log event the gem emits on a caller's behalf after the hop — is emitted with the
caller's snapshot still installed on every carrier, so it carries the caller's `trace.id` (as first cut
both nets sat outside `Diagnostics.with` and the diagnostic was folded after the restore: no id on the
worker and the timer, the closer's id on the closing thread — `ASYNC-8`'s purpose clause, applied to
the gem's own event; `P8-22` extended a second time, no new row). Every fact the design measured on 3.4.10
alone was re-run on 3.2.11, 3.3.12, 3.4.10 and 4.0.6, the pool-specific dozen as a standing test.
Forty-three guards run red (two recorded as equivalent mutants with their measurement; the plan's
timer-mutex mutation among the red ones, by a cross-thread deadlock at `#close` that hangs the delay
suite and by two reported failures on the lock-scope test the round added — the first cut of this note
called it "measured false and dropped", review round 0's R0-1), `test:gems` at 3,818 runs with exactly
one skip (8a's `TRANSPORT-18` vacuity), the six manifests regenerated with only
`dexpace-async-thread.txt` changing (2 → 14 rows, no private constant among them), and the gate set
green on 4.0.6 with the four matrix gates green on 3.2.11, 3.3.12 and 3.4.10.
`docs/sdk-documentation/async-thread.md` is the twentieth as-built page, every example run on 4.0.6 and
3.2.11 as one script and identical but for `Hash#inspect`, a `NoMethodError`'s wording and the socket
block's Timeout thread on the floor; `architecture.md`, the gem README, `README.md` and `docs/README.md`
point at it; `CLAUDE.md`'s built-phases paragraph gains the gem, its skeleton clause loses it, the
checklist count moves to nineteen and its constraints list gains four lines. `docs/first-release.md`
changes in one existing entry only — the unsatisfied-MUST entry gains a dated status sentence — and the
gem table's row stays "no — 0.0.0"; `docs/knowledge/notes/observability.md`'s 8b entry is amended in
place under its own marker with the as-built facts; `docs/deviations.md` is untouched, for phase 10 to
flip. Two dated bullets join phase 10's inbound list by date and content, never by ordinal: under
the one-process `rake test:gems` the main fiber's storage held 5c's no-op span when this gem's
diagnostics suite ran — a residue of another gem's suite the per-file run cannot see, filtered here and
audit work on phase 5c's tests — and, from review round 1, core's two duration guards admitting a `NaN`
and a `Complex` (`Clock#sleep(Float::NAN)` parks on a `Queue#pop` no elapsed time ends), audit work on
phase 5a's. A further bullet the first cut of this note filed — that the plan's Task
7 Step 8 mutation stays green and the timer's lock scope rests on the source alone — was removed before
the stack merged: the premise was a false measurement (review round 0's R0-1), the mutation is red, and
the scope is asserted by a test. The design's fourth finding — §10.5's mitigation sentence names
`Completer#on_cancel` as something "an adapter" does, and on the thread path only the transport can —
stays a sentence here and in the checklist, never a row in `docs/deviations.md`. The consolidation of
`P8-20`–`P8-25` and `P8-71`–`P8-78` into design §10 is a human's:
`docs/sdk-design-ruby/` is frozen. `main` is `a7cfeb6` before and after; the stack is not on it, 8c is
being built beside it, and umbrella #29 stays open for both.

**2026-09-21** — **Phase 8c implemented**, as three stacked branches against issue #32: code, tests,
documentation, cut from `main` at `a7cfeb6`, which holds every phase through 7 and phase 8a —
concurrently with 8b off the same base, so this is the phase-8 lane that lands **second of the two**,
and the one that makes the wire-boundary re-validation phase 1 postponed complete in both adapters
(8a's Task 16 and this lane's Task 9; phase 9's Task 7 adds the portable assertion), and the one that
lands the header-drop policy phase 5b postponed to phase 8 as `OBS-19` (`DropPolicy`, the predicate at
dispatch, the both-protocols test, the antecedent confirmed on `protocol-http1` 0.41.0). The one core
widening is `Configuration::Keys::TRANSPORT_CONNECTION_LIMIT`; `Dexpace::TransportError`,
`Events::TRANSPORT_HEADER_DROPPED` and `Keys::REQUEST_TIMEOUT` were 8a's and on the base.
**`dexpace-transport-async_http`** carries `Dexpace::Transport::AsyncHTTP`: the entry file's six
constants, `.build(timeout:, logger:, drop_policy:, connection_limit:, ssl_context:, configuration:)`
over a client map the adapter owns — one `Async::HTTP::Client` per **(reactor, origin)**, bounded at
`MAX_ORIGINS` and drained after every insert — `.using(client, logger:, drop_policy:)` over a caller's
own client with `retries` already zero, `.default` and the require-time `AsyncTransport.register(:async_http, …)`,
and ten files under `async_http/`: `adapter.rb` and `drop_policy.rb` public and the eight
`private_constant`s `clients.rb`, `endpoints.rb`, `errors.rb`, `exchange.rb`, `request_body.rb`,
`request_mapper.rb`, `response_body.rb` and `response_mapper.rb`, every one mirrored in `sig/` and
every one but `exchange.rb` in `test/`; its gemspec declares `async-http ~> 0.104` and a Ruby floor of
3.3 read from `VERSIONS`' per-gem row (`P8-36`). **`dexpace-conformance`** gains two private groups,
`Asynchronous` (`TRANSPORT-7`, `-9`, `-21`, `-23`) and `HeaderDrops` (`TRANSPORT-12`, `-13`), so the
suite is thirty-four assertions in seven groups with `PREAMBLE` naming `TRANSPORT-8` as the third thing
a green run does not prove; `Scripts.write_response` takes `close:` and every head a script writes
carries `Connection: close`, with every 8a count unchanged. **The repository** gains the per-gem floor:
`VERSIONS`' `floor:<gem>` row, `DexpaceVersions.ruby_floor(gem)` and `.gem_supported?`, the two gates
and the three loaders (`Gemfile`, `test:gems`, `gates:clean_bundle`) reading it, and two gate fixtures;
the `Steepfile`'s `:async_http` target relaxed exactly as `:serde_json`'s; `test/support/async_http_warmup.rb`;
and two surface manifests regenerated once — core 1 335 → 1 336, `async_http` 2 → 24, `conformance`
unchanged. Four earlier-phase test files changed on the code branch as pins the code moved
(`keys_test.rb`, `downstream_wirings_test.rb`, 8a's driver's size pin, `lifecycle_test.rb`'s) plus
8a's `keep_alive_twice` fixture passing `close: false`, and core's `async_transport_test.rb` moved its
four in-process bare-require pins to `async_transport_bare_require_test.rb` (8a's shape on the other
seam). **The design's five rows stand; `R13`–`R16` were built as written**, with the As-built addendum
adding `P8-91`–`P8-102`: the cancellation bridge is queue-marshalled in both directions, because
`Async::Task#cancel` from a foreign OS thread raises and cancels nothing and `cause:` drops a Symbol
(P8-91); the client map is keyed by reactor, the manager's decision on the cross-check's open question
1 (P8-92); `TRANSPORT-8` stays an adapter's own row and the portable groups carry six assertions plus
the preamble sentence (P8-93); a response does not outlive the reactor that produced it — `Sync`'s exit
drains the pool and waits on every busy connection — so the driver's foreign-thread settle materialises
the body inside its reactor, found by `TRANSPORT-29`'s eight threads hanging (P8-94); the per-gem floor
is one `VERSIONS` row read everywhere (P8-95); `Connection: close` in `Scripts`, because a keep-alive
client re-used a connection the fixture had closed one time in two (P8-96); no `Content-Type` is
invented, since `async-http` stamps none and neither of 8a's `P8-4` reasons exists here (P8-97); the
4.0-only `IO::Buffer` warning parked at test-helper load (P8-98); the Steep relaxation beside an
`rbs_collection.yaml` row ignoring the collection's stale `async/2.12` by name — the first cut said the
collection carried none, and review round 0 measured it installing the moment the workspace gem's own
ignore was lifted (P8-99); `P8-37` as built
retires every pooled resource before `pool.close`, which alone would drain and wait exactly as
`Client#close` does (P8-100); the native HTTP/2 body closed through `close_quietly`, because
`async-http` writes `RST_STREAM` before it transitions the stream and an `END_STREAM` in that window
releases the pooled connection twice, five of five (P8-101); and the public surface as built against
the design's object model — `.build`/`.using` over `.owning`/`.borrowing`, `DropPolicy` public, no
`_Client` interface (P8-102). Two of the design's thirteen facts do not hold on `async` 2.46.0 —
`cause: :sym` and "`Async { }` inside a reactor is not a child of the caller" — corrected in a new
`docs/knowledge/notes/concurrency-and-async.md` entry beside a new `transport-adapter.md` entry for the
reactor-exit drain, `P8-37` as built, the h2 double release and the 4.0 warning; the design is frozen to
this phase and phase 10's inbound list carries the pointer, by date and content. The checklist is at
`docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-checklist.md`: ten own rows —
nine ✅ and `ASYNC-21` N/A with its one honourable property asserted — plus eleven cross-reference rows;
the reviewer's thirty mutations run as thirty-three rows on 4.0.6 and 3.3.12 (the gem's floor row;
3.2.11 has no bundle for it), thirty red on both and three equivalent mutants recorded with their
measurement (`Kernel#Async` is the current task's child; core's `Completer#fulfil` closes what a settled
pivot is handed, so check-after-resume is a shortcut; a raise inside `#dispatch`'s fence is still a
settlement) — thirty-five rows after review round 0, whose two surviving extra mutants (the `BINARY`
retag unobserved by a BINARY-only fixture; `Exchange#net`'s settle with no fixture reaching it) were
each given the guard that runs them red on 2026-09-21, thirty-two red in all — after five guards the
first pass found missing were added — the mutex scan reaching
`build_client`, `assert_exchange_released` over the watcher's annotation, `reactor_over` closing a
holding fixture inside the reactor so a blocked exchange fails instead of hanging, every wait bounded,
and `TRANSPORT-3`'s list carrying the SDK's own errors; the design's facts re-run on 3.3.12, 3.4.10 and
4.0.6, eight of them as `matrix_facts_test.rb` printing the row's versions; forty-one departures from
the plan's text itemised, among them the nine suites wrapped into modules of nested classes and the
conformance groups split in two under the metric cops, and the two found only by the whole-repository
`test:gems` process. The driver reports **four** skips, not the plan's three — two assertions carry
`TRANSPORT-14` and a waiver is by id — beside `TRANSPORT-27`'s waiver and `TRANSPORT-18`'s measured
vacuity; on the 3.2 row the gem is absent, five gems install, test and clean-bundle, and every gate is
green. Re-proven at every tip: the code tip green on every one of the
eighteen gates run individually on 4.0.6 (`test:gems` 3,713 runs, 72,711 assertions, 0 failures,
0 errors, 3 skips — 8a's — and 97.55 % line coverage, above the floor, so no tip in the stack is red; the
honest RuboCop run over 683 files clean; `gates:clean_bundle` loading all six gems) and on the 3.2.11
matrix row (3,704 runs, 72,677 assertions, 3 skips, `gates:clean_bundle` five gems — this gem absent by
its floor); the tests tip green on the whole default task on 4.0.6 (3,897 runs, 73,482 assertions,
0 failures, 0 errors, **7 skips** — 8a's three and this driver's four — 99.88 % line coverage; the honest
RuboCop run over 707 files clean; `steep check` over six targets clean), on the matrix set on 3.2.11
(3,712 runs, 72,726 assertions, 3 skips, five gems), 3.3.12 (3,897 runs, 73,482 assertions, 7 skips, six
gems, `openssl` 4.0.2 the bundle's on that row and on 3.4.10) and 3.4.10 (3,897 runs, 7 skips), with
`matrix_facts_test.rb` printing `async-http 0.105.0, async 2.46.0, protocol-http 0.72.0` on the two rows
that carry the gem; the docs tip green on the default task, the honest RuboCop run, the probe, the
knowledge-structure verifier, the housekeeping and knowledge test suites, and every `ruby` fence of
`transport-async_http.md` (as one script, on 4.0.6 and 3.3.12) and the changed fences of
`conformance.md`. `docs/sdk-documentation/transport-async_http.md` is the
twentieth as-built page, every example run on 4.0.6 and 3.3.12 and identical on both but for the
ephemeral port one `Host` line names; `conformance.md`'s counts, preamble and report examples re-run
on both; `architecture.md`, the gem README (with its `ASYNC-7` section, the reactor rule, the
`sync_over` caveat, the `async_over` hazard, `content-length: 0`, the timeout unit and the 4.0 warning
line), `README.md` and `docs/README.md` point at the page; `CLAUDE.md`'s built-phases paragraph gains
the gem and core's key, its floor sentence names this gem's 3.3, its counts move to nineteen checklists
and the two adapter gems' file counts, and its constraints-that-bite list gains one line;
`docs/first-release.md` changes in existing entries only — the conformance-suite line's second-driver
status, the `P8-9` documentation box ticked, the `gates:bounded_map` blocker's status and the
supported-Ruby note's 0.105.0; `docs/deviations.md` is untouched, for phase 10 to flip. One dated
bullet joins phase 10's inbound list above — the design's facts 8 and 10 stale on `async` 2.46.0, and
`async-http`'s server letting a mid-head `EOFError` reach Console — by date and content, never by
ordinal, because 8b's lane is writing to the same list. The consolidation of `P8-36`–`P8-40` and
`P8-91`–`P8-102` into design §10 is a human's, as for every phase before: `docs/sdk-design-ruby/` is
frozen.
