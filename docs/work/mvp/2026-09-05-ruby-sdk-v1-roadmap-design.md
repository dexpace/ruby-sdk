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
| 2 | Seam Foundations | `dexpace-core` | §3 — `SEAM-1`–`SEAM-30` (30 IDs) | §2.4, §3.1–§3.7, §10.3, §10.8, §10.9; phase design: [`phase2/2026-09-06-phase2-seam-foundations-design.md`](./phase2/2026-09-06-phase2-seam-foundations-design.md) |
| 3 | I/O and Body Lifecycle | `dexpace-core` | §5 — `IO-1`–`IO-42` (42); ch.06 — `BODY-1`–`BODY-37` (37), plus `HTTP-36`–`HTTP-45`, `HTTP-51`, `HTTP-52` jointly numbered into that chapter | §3.1, §10.1, §10.2, §10.12; segmentation design: [`phase3/2026-09-08-phase3-segmentation-design.md`](./phase3/2026-09-08-phase3-segmentation-design.md); 3a design: [`phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md`](./phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md); 3b design: [`phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`](./phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md) |
| 4 | Execution Context and Pipelines | `dexpace-core` | §7 — `CTX-1`–`CTX-20` (20); §8.2 — `RECOV-1`–`RECOV-34` (34); §8.1 — `PIPE-1`–`PIPE-40` (40) | §5.1–§5.4, §8.1; segmentation design: [`phase4/2026-09-08-phase4-segmentation-design.md`](./phase4/2026-09-08-phase4-segmentation-design.md); 4a design: [`phase4/phase4a/2026-09-08-phase4a-execution-context-design.md`](./phase4/phase4a/2026-09-08-phase4a-execution-context-design.md); 4b design: [`phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`](./phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md); 4c design: [`phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`](./phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md) |
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
- **Phase 6 (111 prefix IDs of its own, the largest, plus `DEF-35`'s fifteen), expected 6a retry, 6b redirect,
  6c authentication.** (**Corrected in place 2026-09-08** by the phase-4 segmentation design: this bullet
  formerly opened "Phase 6 (111 IDs, the largest)". The **count is unchanged and the phase-6 row above is
  unchanged** — no requirement ID moved, and `RETRY-1`–`RETRY-45`, `REDIR-1`–`REDIR-28` and `AUTH-1`–`AUTH-38`
  still sum to 111 — but the **scope** the number stood for is now stale. `DEF-35` moves the *work* of fifteen
  `RECOV` IDs into this phase: `RECOV-17`–`RECOV-30` and `RECOV-34`, the recovery-stack retry engine, whose
  checklist rows stay in phase 4 as ⏳ and whose implementation lands here. **Phase 6's segmentation design must
  budget for 111 + 15 and not for 111**, and it decides whether each of the fifteen is a separate checklist row
  or a cross-reference to its `RETRY` twin — `DEF-35` carries the twin-by-twin table so the mapping does not
  have to be re-derived. The cluster phase 4 identified is *sixteen* IDs; the sixteenth, `RECOV-31`, is **not**
  in `DEF-35` and is **not** phase-6 work — `DEF-5` defers it post-MVP and `DEF-6` defers its `RETRY-38` twin
  with no named trigger — so it may carry a row here but never a budget line. Phase 6 is by this margin the
  largest phase in the roadmap, and it was already the largest before the fifteen arrived.) Two spec-forced facts
  constrain the cut, and `DEF-35` is a direct consequence of the first. `RETRY` is two cooperating stacks over
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

**2026-09-07** — Phase 2 design and plan filed. The design landed a day earlier and was committed
on its own, at `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md`; the plan is
`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md`. Nothing is implemented; the checklist
is written at execution time, per execution step 6. Scope is the phase-2 row's thirty IDs,
`SEAM-1`–`SEAM-30`, one checklist row each — with **`SEAM-29`'s row a cross-reference to phase 1**,
which honoured both of its MUSTs ahead of this phase, because dropping the row would leave an ID
inside this phase's stated range with no row in the phase that owns the range. No segmentation
design: one chapter, one gem, thirty IDs, fewer than phase 1's forty-two rows. The deferral sweep
read all twenty-six rows and **picked up `DEF-21`**, whose pick-up condition named phase 2
explicitly: the runtime half of the version-skew guard is now a required `core:` keyword on
`Dexpace::Registry#register`. It gave **`DEF-1`'s `SEAM-28` half a target it never had — phase 5**,
where an operation identifier first has both the context chain it attaches to (phase 4's) and a
consumer for it; UNSCHEDULED would have been wrong, because that row's condition — "picked up
opportunistically" — is not a condition any phase could meet. Five rows were filed: `DEF-27` (the
two disposal routes for `close_quietly`'s rescued error, phases 4 and 5), `DEF-28` (the pivot's
`deadline:` keyword and the clock behind it, phase 5), `DEF-29` (moving the three in-memory fakes
into `dexpace-conformance`, phase 8), `DEF-30` (presence-gated auto-activation, instrumentation
only, post-v1) and `DEF-31` (`SEAM-25`'s lifecycle event on the first close of an owned executor,
phase 5). The **open-items register gained its first entry, `OI-1`**: five `SEAM` IDs —
`SEAM-15`, `SEAM-20`, `SEAM-22`, `SEAM-23` and `SEAM-28` — appear nowhere in the specification's
prose and exist only as appendix-C rows, so this document's own gap paragraph and
`scripts/knowledge.rb --gaps SEAM`, which both send a reader to
`docs/product-spec/03-pluggable-seams-and-extension-model.md` for `SEAM-22` and `SEAM-28`, name a
chapter that does not carry them. The pointer is derived mechanically from appendix C's subsystem
cell and is not wrong about the subsystem; the instruction built on it is unfollowable. Phase 2
read all five out of appendix C directly. Four knowledge notes were filed before the plan was
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
undefined under `ruby --disable-gems`, so `DEF-21`'s comparison is hand-rolled and `Gem::Requirement`
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
merge, since a phase returns to `mvp` as one pull request. 3b at 49 IDs is the largest sub-phase the
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
`IO-16`, a SHOULD. Filed as `OI-2`; 3a reads it from appendix C. `DEF-26` is **picked up by 3b** (it
needs a body type to narrow `sig/` to, which 3a's duck type is not), and the `NFR-4` narrowing is
free because the lock diffs against a release tag that does not exist. `DEF-3` stays deferred and
gains what it lacked: `BODY-12`'s transport-dispatch clause targets **phase 8** with `DEF-10`, its
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
recorded as P3-1 through P3-12 with a Design §3 addendum carrying two entries. One deferral
was filed, **`DEF-33`** — exercising `IO-38` on a Ruby without a GVL, whose condition is an
event rather than a phase because the matrix is CRuby-only and the GVL would hide a missing
lock on every row. The **open-items register gained `OI-3`**: phase 1's "verified inert
outside core" holds only for a *top-level* `include Dexpace`; a consumer's own
`class C; include Dexpace` puts `Dexpace` ahead of `Object` in the ancestry, so `x.is_a?(IO)`
is silently `false` there — a finding about every flat `Dexpace::` constant sharing a name
with a core class, not only about `Dexpace::IO`. Three knowledge notes were filed before the
document was finished — `io-and-byte-streams` (two `## Superseded` entries: the read split and
the frozen-chunk retag), `message-bodies` (`## Conflicts`: `IO-6` and not `SEAM-3` is the
ownership rule's home, the corpus half of `OI-2`) and `resource-management` (`## Conflicts`:
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
across this port's floor and only BINARY gives one answer on every row. **No deferral was filed**;
the register was read in full and no row is picked up. The **open-items register gained `OI-4`**: a
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
the body code uses constantly, and `OI-3`/P3-7 show that shadowing is silent for `is_a?`.

The charter's six risks are all resolved. **R5**: three caps, not one — the 64 MiB ceiling stays a
constant with no keyword (a second ceiling is what boundary 8 pins), `BODY-30`'s 1 MiB is fixed by the
requirement, and only the logging preview size is a parameter, with `DEF-34` filed for its source.
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
`Encoding.default_internal`. The boundary is retag-then-transcode with both encodings named — `OI-7`,
plus a corpus note. `respond_to?(:rewind)` is `true` for a pipe, a socket, a `StringIO` and a `File`
alike, so `BODY-9`'s antecedent is `pos` + `seek(pos)`, which raises `Errno::ESPIPE` on a pipe with
nothing consumed and is a genuine no-op on a seekable stream — and replay rewinds to the construction
position, not to byte 0. And §7.1's `Enumerator` rule reaches an **ordinary `#each` method**: driven
through `to_enum(:each)` and abandoned, its `ensure` does not run either, and `block_given?` is `true`
under that drive so no in-method guard helps — which is why `FileBody`'s residue is documented rather
than closed, on §10.10's precedent. Both findings earned corpus notes, superseding
`io-and-byte-streams/fbcb4d19` and `pagination/f57c50f6`; `harvested/` is untouched.

**Deviations `P3-14` through `P3-21`.** One deferral, **`DEF-34`** (phase 5's configuration source for
the body-logging caps and the enablement predicate). **`DEF-26` is picked up** — `sig/` narrows
`Request#body` and `Response#body` to `Dexpace::Body?` and `HTTP-46` gets a cross-reference row, the
treatment phase 2 gave `SEAM-29`. **`DEF-3` is amended in place**, performing the two sharpenings the
segmentation design stated and did not perform: `BODY-12`'s first clause is discharged here through
`::IO.copy_stream`, its second targets phase 8 with `DEF-10`, and `BODY-36` gets the explicit pick-up
condition it lacked. One cross-phase observation against 3a, filed as **`OI-8`** rather than
worked around: `TeeSink#clear_tap` was shipped for `BODY-18`, and 3b satisfies `BODY-18` by building a
fresh tee per write — which is strictly stronger, because `TeeSink` binds its primary at construction so
one tee cannot span two attempts — leaving the method public, `NFR-4`-locked and uncalled by core. 3a
stays as committed; the item names the window in which 3a's plan may drop the method without a break,
which is before either plan executes and before the first release tag.

**2026-09-08** — Phase 3b plan filed,
`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle.md`. Fourteen numbered tasks in build
order: the contract and `BytesBody`, then `BufferBody`, the form encoder, `StreamBody`,
`ChunkedBody`/`FormBody`, `FileBody`, `MultipartBody`, `ResponseBody` with the decode boundary,
`Body.buffer_bounded`, the two logging wrappers, `TypedResponse`, `OI-4`'s measurement, and the
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
`::IO.copy_stream`, task order is stated, and `OI-4`'s measurement is a task whose deliverable is the
number. That number: one view per `BODY-23` read, holding zero bytes, at 9 allocated objects (10 on
4.0.6), with quadratic deregistration that costs 0.005 s at 1 000 live views and 0.46–0.52 s at
10 000 — so the bound stops being obvious above roughly a thousand simultaneously-live unclosed
views, which nothing in `BODY-22`–`BODY-29` produces. `OI-4` stays open with the measurement in its
Resolution field and phase 3a's view registry unchanged, which is what the item asked for.

**Two findings the design could not have had, both from running the code.** `Encoding.default_internal =`
emits a warning under `ruby -w`, so `DexpaceTestCase`'s `Warning.warn` override turns the design's own
mandated hostile-global decode test into a failure — both the set and the restore. The plan ships the
narrowest fix, `$VERBOSE = nil` around exactly those two assignments, plus a test asserting `-w` is
still live inside the block so the suppression cannot silently widen. And a second cross-phase
observation against 3a, filed as **`OI-9`**: `BufferedSource.wrapping(io)` returns **one byte** per
`#read_into` and yields one-byte chunks from `#each` — 200 000 chunks for 200 000 bytes, ~0.21 s where
the in-memory paths are unmeasurable — because `#read_into` fills through a hard-coded
`ensure_buffered(1)` rather than the count the caller asked for. It is a throughput defect and not a
correctness one, so no gate catches it and 3a's suite stays green; the fix is one line in an
unexecuted plan, the window is `OI-8`'s, and phase 3b is deliberately built so it costs nothing —
**no 3b test asserts a chunk granularity in either direction**. One deviation row added, **`P3-22`**,
for the per-variant accessors P3-14's constant list does not enumerate. No new deferral: `DEF-34`
stands as the design filed it, and the plan's Task 14 amends `DEF-3` and marks `DEF-26` picked up.

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
`CTX-14`/`CTX-15` bundle shape); `4b` lands the error primitives `DEF-24`, `DEF-27`'s first route and
`DEF-32` all wait on, and `DEF-32` changes behaviour phase 2 shipped; `4c` is largest and benefits
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
is phase 5's and which phase 2 deliberately kept off the pivot (`DEF-28`) — a phase-4 hand-roll is
technically reachable (`Thread::Queue#pop(timeout:)` is on the 3.2 floor) but would fix `CFG-15`'s
shape a phase early, which is exactly what `DEF-28` declined to do, and the shortcut a plain
`Kernel#sleep` would be is ruled out by `RECOV-27`'s own "not a plain sleep" and by `RETRY-26`'s
"non-conforming" — and `RETRY-13` forbids the two stacks
carrying independent backoff formulas, which is exactly what building the recovery half two phases
early would produce. Filed as **`DEF-35`** — **fifteen** of them, target **phase 6**; the sixteenth,
`RECOV-31`, was already `DEF-5`'s and stays post-MVP. Nothing in this document's cells changes:
phase 4 still owns all 94 checklist rows and builds 76 outright, carrying 18 as ⏳ under the legend
cross-cutting constraint 3 already defines — one of the eighteen, `PIPE-33`, met in part rather than
not at all. Cross-phase obligation 3 reads as confirmation once its words are taken at face
value — the *substrates* are phase 4's, the *stacks* are phase 6's. **The consequence lands on phase
6, and it is stated in three places so its segmentation design does not have to count.** Phase 6 was
already the largest at 111 prefix IDs (`RETRY` 45, `REDIR` 28, `AUTH` 38); `DEF-35` adds the *work*
of fifteen more on top of that 111, so **phase 6's segmentation design budgets for 111 + 15, not
111** — `RECOV-31`, the cluster's sixteenth, is `DEF-5`'s post-MVP row and is not phase-6 work. No
requirement ID moves — the fifteen keep their phase-4 rows as ⏳ and phase 6 carries its own rows or
cross-references, the two-rows-one-obligation treatment phase 2 gave `SEAM-29`. The
phase-6 segmentation bullet above is corrected in place accordingly; the **phase-6 row itself is
unchanged and correct**, because its three prefix ranges still sum to 111. `DEF-35` carries the
twin-by-twin `RECOV`→`RETRY` mapping so phase 6 re-derives nothing.

**The gap-ID claim was checked and is right about the IDs and wrong about where to read them.**
`--gaps CTX,RECOV,PIPE` reports 20/20 `CTX` and 40/40 `PIPE` substantive with **zero roll-up-only
entries in any of the three prefixes** — so the appendix-B roll-up hazard does not fire for phase 4
at all — and exactly the fifteen uncited `RECOV-17`–`RECOV-31` this document's paragraph above names (a
different fifteen from `DEF-35`'s: that set drops `RECOV-31` and adds `RECOV-34`).
But §8.2 states `RECOV-1` through `RECOV-16` and stops: verified by repository-wide grep,
**`RECOV-17` through `RECOV-34` appear nowhere in `docs/product-spec/` outside appendix C** —
eighteen IDs, not fifteen, and three of them (`RECOV-32`, `RECOV-33`, `RECOV-34`) escape `--gaps`
only because the *design* names them. Filed as **`OI-12`**, the third instance of `OI-1`'s and
`OI-2`'s shape and the largest; at three occurrences across three prefixes it is a property of
appendix C's relationship to the prose chapters rather than three omissions. The budget is also not
what the paragraph implies: fourteen of the fifteen uncited IDs move to phase 6 with `DEF-35` and
the fifteenth, `RECOV-31`, is `DEF-5`'s post-MVP row, so the *reading for implementation* leaves
phase 4 either way and what phase 4 owes is one disposition pass over eighteen appendix-C rows,
which this document performed.

**`PIPE-33` is phase 4's, and §10.5's trade is not re-opened.** Four of its five normative clauses
are met and phase 2 built most of the machinery: no default executor exists to fall into (core ships
the executor as a `#post`-shaped duck type), a built pipeline *is* a transport (`PIPE-26`) so
`Transport.async_over` runs it as one opaque unit, options are threaded, and cancel-without-interrupt
completes as cancelled. The interrupt clause is not met, for §8.3's reason, and `4c`'s row is ⏳
citing `DEF-18` and §10.5 with the four met clauses named. Phase 8's disposition of the same ID is a
re-assertion at the point the antecedent becomes real — `dexpace-async-thread` is what creates a
worker to fail to interrupt — not a second decision, the same two-rows-one-obligation treatment phase
2 gave `SEAM-29`. Phase 2's design also records a **binding obligation** honoured here: phase 4 wraps
a `Dexpace::Pipeline` with phase 2's two `SEAM-18` bridges and builds no second pair.

**Three facts verified on 3.2.11, 3.4.10 and 4.0.6 shaped the document, and two changed a decision.**
A `#full_message` override — which design §5.2 specifies for the suppressed trail — is **invisible to
Ruby's default uncaught-exception printer** on all three; `#detailed_message` reaches it, exists on
the 3.2 floor, and is what Ruby's own `#full_message` calls, so overriding `detailed_message` alone
satisfies **both** paths while `full_message` alone reaches only an explicit `#full_message` call and
misses the report a reader of a crashed process actually sees. That is `DEF-24`'s content. And the
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
later phase to the wrong page, which is the same class of unfollowable pointer `OI-2` and `OI-12`
record.

**The document's adversarial review, same day, confirmed the three central claims and corrected the
counts they were stated with.** The `RECOV`→`RETRY` twin mapping was re-derived ID by ID against
appendix C and holds; the `CTX`-independence result holds, with the one exception now stated (a
`CTX-9` comparison in design §5.2 that reads nothing from `CTX`); `OI-12`'s eighteen and its
unfollowable pointer were re-verified by grep. Corrected: `DEF-35` defers **fifteen** IDs and not
sixteen, so phase 6 budgets **111 + 15**; `PIPE-33` has **five** normative clauses of which four are
met, not four of which three are; phase 4 carries **18** ⏳ rows, not 17; and
`Dexpace/NoThreadInterrupt` is a **phase-0** cop, not phase 2's. `DEF-35`'s own register row carried
the same off-by-one in its cost bullet and was corrected with the rest, so all three places a
phase-6 planner can enter from now say 111 + 15 and name `RECOV-31` as the excluded sixteenth. One
new open item, **`OI-13`**: `Fiber#storage=` — the write side of the carrier design §8.1 fixes for
`ASYNC-9`/`ASYNC-11` — warns on every call on all three interpreters at the default warning level,
against a gate set that fails on warnings, and `= nil` reads back `{}` on 3.2.11 and `nil` on the
other two. Nothing in `CTX`, `RECOV` or `PIPE` touches fiber storage, so it is phases 5 and 8 that
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
`NO_TRACER_FACTORY`, the latter carrying the one method `CTX-20`'s embedded MUST forces. `DEF-37` records
the five-clause contract phase 5 implements against and the six things it may not redo. `DEF-36` defers the
configuration source for the store's cap, `MAX_TRACKED_CONTEXTS = 1024` — `AUTH-19`'s number, because §5.4
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
every file inside that namespace and `Dexpace/QualifiedCoreConstant` cannot express the fix. Two new open
items. **`OI-16`**, from the design's review: the corpus CLI has one relation and derives it from any
backtick, so `[overridden by notes/…]` now prints against `api-design/b0e18938` and
`module-organization/64e84d64` — two rules phase 4a's note *rests on* — and against three
`concurrency-and-async` rules a committed note says in words that it does not weaken; 77 of 2 166 harvested
entries carry the marker. And **`OI-15`**: "the monotonic counter" names `CTX-4`'s call-sequence counter
and `CFG-16`'s elapsed-time counter, and the phase-4 segmentation design's own exclusions table assigns the phrase to phase 5 — true of
`CFG-16` and misleading about `CTX-4`, which is phase 4a's to build. Filed rather than fixed, because the
charter is committed. **4a confirms the charter's independence result from the inside**: `--phase 2` and
`--phase 3` cite 70 and 152 distinct requirement IDs between them and **not one `CTX` ID**, and `4b` and
`4c` are obliged to consume nothing 4a ships.

**2026-09-08** — Phase 4b design filed, the third phase-4 document.
`docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`, with its plan and
checklist still to be written. Scope is the charter's: `RECOV-1`–`RECOV-16` plus `RECOV-32`/`RECOV-33`
built, fifteen ⏳ rows citing `DEF-35` and one citing `DEF-5`. **No backoff calculator, no
pacing-header parser and no wait of any kind**, cancellable or otherwise — `RETRY-13` forbids the
first and `CFG-15` owns the third, and the ⏳ rows are rows rather than work.

Five decisions were forced by facts run on 3.2.11, 3.4.10 and 4.0.6 rather than argued. **The
suppressed trail cannot live on `Dexpace::Error`**, because every primary `RECOV-12`, `DEF-27` and
`DEF-32` hand it is a *caller's* exception and a method defined only on the SDK's root raises
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
`factory:` to the error-mapping step instead. One deferral, **`DEF-38`**: that class ships without
`XCUT-5`'s baked retryability flag, because the flag's "SINGLE shared status classifier" is `RETRY-1`'s
and phase 6's, and adding a method later widens. No new open items. Three corpus notes were filed
before the design was finished — two under `docs/knowledge/notes/error-handling.md` and a new
`docs/knowledge/notes/pipeline.md`.

**`DEF-24` and `DEF-32` are discharged by this design and `DEF-27`'s first route is supplied**, with
the register edits left to 4b's plan on phase 3b's precedent. `DEF-32`'s finding is worth recording
here because it is a negative: **none of phase 2's three `Hooks.notify` tests changes its assertions.**
Each raises from exactly one handler, so the suppressed trail is empty and the behaviour is identical
before and after; what `DEF-32` actually costs is a **fourth** test at the
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
to ⏳ against a new `DEF-39`, because R14's resolution ships one of that requirement's two named
constructors and defers the other. Thirty-seven ship, three carry ⏳ — `PIPE-33` (`DEF-18`, four of five
clauses met), `PIPE-36` (`DEF-4`) and `PIPE-39` (`DEF-39`).

**Three decisions shape everything else in the document.** **4c ships no bridge**: a built pipeline is a
transport (`PIPE-26`), so `PIPE-33` and `PIPE-34` are phase 2's `Transport.async_over` and
`AsyncTransport.sync_over` composed with a pipeline, and the phase adds no wrapper, no wait and no
signature — which is the strongest available form of the charter's "no deadline-less unconditional
block" constraint and files no second row beside `DEF-28` (P4-35). **Cursor-scoped state is keyed by
`(stage, key)` rather than by key alone**, and its only write is an argument to `#fork`: under a flat
namespace a `RETRY` pillar step sits between REDIRECT and AUTH, may fork, and could write the very key
AUTH reads — so §6.2's own sentence, "no step downstream of AUTH can [set the marker] either", and
§10.15's "structurally impossible rather than defended against" would be true of non-pillar steps only.
Namespacing by the writing step's stage, chosen by the runtime from the frozen entry table, makes both
literally true, and the five tests R11 demands assert the **negative** (P4-28, P4-29). And **the
standard-resilience preset ships as a mechanism with no step set**: `PIPE-24`'s all-or-nothing
installation is a general `Builder#install_preset`, real and tested against probe steps today, while the
redirect/retry/instrumentation set it would install defers to phase 6 (P4-34, `DEF-39`).

**One fact was floor-only and changed a decision.** The cursor's single-use latch is an unsynchronised
instance variable, because a cursor is created per step invocation and never published. Measured: eight
threads through that latch let more than one caller past on **29 of 2000 runs on 3.2.11 and 0 of 2000 on
3.4.10 and 4.0.6**. So `PIPE-15`'s "reusing the handle MUST be treated as a defect" is honoured and the
detection is sequential-only — stated in the YARD as P4-33 — and **4c ships no test asserting the race**,
because at 29 in 2000 — 1.5 % — the single-shot form of that test is a flake on the floor as well, and only its
2000-run aggregate form is green there and red on the other three columns. Two other
facts license the object model: `Data` responds to `<=>` through `Kernel#<=>`, so `sort_by(&:stage)`
raises `ArgumentError` at the first two-stage pipeline and nothing sorts a stage at run time; and every
lambda's class is `Proc`, which is what `OI-17` records.

Fourteen deviations are filed, `P4-26` through `P4-39`. One deferral, **`DEF-39`**. Two open items,
both conjunction failures rather than the unresolvable pointers `OI-1`, `OI-2` and `OI-12` record.
**`OI-17`** — `PIPE-18`–`PIPE-21`'s surgical edits are keyed by step type and every lambda step shares
one type, so a pipeline holding two lambdas cannot address either surgically. **`OI-18`**, filed by the
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
it is filed as `OI-19` rather than silently corrected.** Loading this phase's classes and calling
phase 0's own walker method (`mod.public_instance_methods(false)`) directly shows that a
`Data`-generated reader — `DispatchContext#bundle`, `Bundle#trace_id`, and every one like them, in
every gem, since phase 1 — never appears in a regenerated runtime surface snapshot: the reader is
defined on the anonymous class `Data.define` returns, which is the named subclass's `superclass`,
and `public_instance_methods(false)` does not look there. This holds on all three interpreters and
contradicts `P4-11`'s and `CLAUDE.md`'s own stated reason for pairing the runtime snapshot with the
RBS diff ("each catches what the other cannot see") — the runtime half catches nothing for a
`Data`-generated reader specifically, and always has not, since phase 1's first regeneration. Not
fixed here: `tools/surface.rb` is phase 0's and every gem is affected identically. A second item,
`OI-20`, was filed by the plan's review: the design's second discriminating drain measurement —
"the maximum size ever observed" — is not reachable through `ContextStore`'s public surface
(`#size` takes the same mutex as the insert, so a split-lock `BoundedMap` sampled by four
concurrent readers across 64 000 inserts never reports above the cap), and `Metrics/ParameterLists:
4` is unsatisfiable for a keywords-everywhere API, which seven methods in this phase demonstrate.
No deviation and no deferral were filed; the registers were read and no row was picked up.
