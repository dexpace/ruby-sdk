# Phase 8 — Segmentation Design

**Status:** Draft, for review. Written 2026-09-11, before any phase-8 sub-phase design exists.

**Path:** `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`. That is the path this document
carries for the rest of its life and the one every citation of it should use — including the link the
roadmap's phase-8 row is owed, matching the segmentation-design links phases 3 through 7 already carry.

**What this document is.** The segmentation design the roadmap's **Segmentation rule**
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:173-181`) requires of a build phase that spans
more than one ID-bearing spec chapter or ships more than one gem. Phase 8 does both, and it spends more
gem budgets than any other phase in the roadmap — `dexpace-transport-net_http`, `dexpace-async-thread`,
`dexpace-transport-async_http` and `dexpace-conformance`, which is more than any phase since phase 0
created the six skeletons. It decides how many ways the cut goes and in what order,
says for each boundary whether that order is a **dependency** or a **convenience**, assigns every
requirement ID to exactly one sub-phase, and names the boundaries that are spec-forced and therefore not
open to the sub-phase designs to revisit.

**What this document is not.** It is not a phase design, a plan or a checklist, and it names no numbered
task and writes no code. Where it names a decision as belonging to a sub-phase it stops there
deliberately; a segmentation design that settles the sub-phases' content is the same failure as a
sub-phase plan that re-imposes a chain the split existed to avoid, arriving from the other direction.

**The headline, stated once at the top because everything else depends on it.** Phase 8's scope is
`TRANSPORT-1`–`TRANSPORT-30` and `ASYNC-1`–`ASYNC-22` — **52 requirement IDs, and no ID moves in from
another phase and none moves out.** **The cut is three ways — `8a` the synchronous transport and the
conformance gem, `8b` the async-runtime adapter, `8c` the asynchronous transport — and every boundary is
a CONVENIENCE.** The roadmap's two-way forecast
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:248-251`) is **corrected, not confirmed**, and
the correction is stated in full under *The roadmap's forecast, tested rather than deferred to*: the
bullet's claim that the §17/§18 chapter line "is also the `SEAM-11`-versus-`SEAM-16`/`SEAM-17` line"
fails at ID level on the §17 side — five of §17's thirty requirements have an **async-only antecedent**
and are `SEAM-16`'s, so a synchronous-transport segment cannot exercise them. The §18 side survives:
§18's own preamble names `SEAM-17` as its interchange point, and the correction does not claim otherwise.

Phase 8 adds **no new unsatisfied MUST** — `ASYNC-3` and `PIPE-33`'s interrupt clause are §10.5's and
`DEF-18` carries both unchanged; `ASYNC-4` is on no register row at all, because §10.5 holds it
**vacuous** rather than deferred and `DEF-18`'s `Cites:` line is `ASYNC-3, PIPE-33`. It **picks up four
register rows** (`DEF-22`, `DEF-25`, `DEF-31`, `DEF-41`), **partly picks up one** (`DEF-42`), **marks two
UNSCHEDULED** (`DEF-3`'s `BODY-12` clause 2, and `DEF-29`), **closes one release blocker**
(`docs/first-release.md`'s phase-8 transport-adapter line), and proposes **four new open items** and
**three register amendments**. Its
spec-reading budget is **zero**: `ruby scripts/knowledge.rb --gaps TRANSPORT,ASYNC` reports 0 of 52 with
no substantive corpus entry. Both chapters were read in full anyway (51 and 46 lines), for the
`*Conformance:*` clauses appendix C does not carry.

---

## Governing documents

- `docs/product-spec/17-transport-adapter-conformance-contract.md` (51 lines) and
  `docs/product-spec/18-asynchronous-runtime-adapter-contract.md` (46 lines) — normative, both read in
  full for this document, together with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md:559-610` for the canonical
  text and modal level of all 52 IDs. Appendix C is a convenience here, not a necessity: every one of the
  52 appears in its own prose chapter with a `*Conformance:*` clause appendix C drops, and several of
  those clauses are load-bearing (named in the scope tables below).
- `docs/product-spec/03-pluggable-seams-and-extension-model.md` for `SEAM-11`–`SEAM-18`, `SEAM-24`,
  `SEAM-25` and `SEAM-30` — the seams phase 8's gems implement and phase 2 built.
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.2 (`:155-188`, the sync transport seam
  as a duck-typed `#call`), §3.3 (`:189-294`, the async seam, the core-owned pivot, the
  check-after-resume rule, cancellation and deadlines end to end) and §3.7 (`:452-518`, the close
  contract, the `@owned` construction-time distinction, `close_quietly`'s two disposal routes).
- `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.3 (`:195-231`) — the clock, the
  cancellable queue wait, and the prohibition on `Timeout.timeout`, `Thread#raise` and `Thread#kill`
  that causes §10.5's three MUSTs.
- `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md` §9.3 (`:65-113`) — Minitest as the framework,
  `dexpace-conformance`'s framework-agnostic assertion objects, the `TCPServer` fixture rather than a
  stubbing library, and appendix B's per-prefix restatements (B.6 and B.7 are phase 8's).
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.1 (`:16-25`, the six MVP gems and their
  dependency budgets), §2.2 (`:27-37`, the later gems and the "what would be unproven without it" line)
  and §2.4 (`:71-105`, the zero-dependency rule and the version-skew assertion).
- `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items **3** (`:18-22`,
  the core-owned pivot), **4** (`:23-29`, cooperative cancellation and the orphaned-response close),
  **5** (`:30-57`, the three unsatisfied MUSTs and their exact split — phase 8's, and not re-opened),
  **7** (`:63-67`, the narrowed stdlib), **10** (`:77-81`, the wire-boundary re-validation that is
  `DEF-25`) and **12** (`:87-91`, the stream-ownership rule).
- `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` items
  2 (`:10-12`, `NFR-11` versus `SEAM-17`), 5 (`:20-22`, `SEAM-30`'s pre-emptible-future presumption), 8
  (`:31-32`, `XCUT-23` needs one instance per seam), 12 (`:42-44`, the four sync/async drifts), 18
  (`:59-62`, `SERDE-26` and `TRANSPORT-18` as conditional obligations) and 21 (`:73-78`, `ASYNC-21`'s
  adapter-scoped MUST).
- `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md` — the `TRANSPORT` row (`:41`) and the
  `ASYNC` row (`:42`), and the MUST-level summary (`:49-55`). **The `TRANSPORT` row and the MUST-level
  summary carry a factual error this document corrects** (see verified fact 1); the `ASYNC` row is
  accurate as written and is cited for `ASYNC-3`'s and `ASYNC-21`'s dispositions.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-8 row (`:93`), the phase-9 row
  (`:94`, which bounds what phase 8 owns of `dexpace-conformance`), the ordering rationale (`:97-124`,
  whose last paragraph is specifically about why transports come late), cross-cutting constraints 3
  (`:47-50`, the checklist legend), 4 (`:52-53`, the fake transport through phase 7 and the first real
  socket here) and 8 (`:72-74`, the three MUSTs), cross-phase obligations 4 and 5 (`:138-142`), the
  gap-ID paragraph (`:153-161`), the Post-v1 paragraph (`:163-170`) and the segmentation rule's phase-8
  bullet (`:248-251`).
- `docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md` as the closest worked example of this
  document's form, and `docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md` as the closest
  example of a phase inheriting many obligations. Phases 3, 4 and 5's segmentation designs likewise.
- The predecessor designs whose forward tables this document cites rather than re-derives:
  `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md`,
  `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md`,
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md`,
  `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md`,
  `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`,
  `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`,
  `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`,
  `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md`,
  `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`,
  `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md`,
  `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-design.md`,
  `docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-design.md`,
  `docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events-design.md`.
- `docs/deferred-items.md`, `docs/open-items.md`, `docs/deviations.md`, `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

---

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run first.
`ruby scripts/knowledge.rb --origin note --brief` returns **38 entries across 19 note files**;
`ruby scripts/knowledge.rb --section conflicts --brief` returns **24 entries across 17 topic files, 18 of
them notes and six harvested** — the six harvested ones being the styleguide-versus-design conflicts
themselves, and **every one of them prints `[overridden by notes/…]`** (`data-modeling/35fde90f`,
`module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and `/8c0687bf`,
`tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`). **None is open**, so phase 8 inherits no
unresolved conflict and owns no conflict decision of its own. Narrowed to this phase's prefixes,
`--section conflicts --prefix TRANSPORT,ASYNC --brief` returns **nothing at all** — the CLI's
no-matching-entries message, with the two filters matching 129 and 24 entries separately — which is a
stronger result than phase 7's and is worth stating: **no recorded styleguide-versus-design conflict
touches a `TRANSPORT` or an `ASYNC` ID.**

**Corpus coverage: complete.** `--prefix-info` reports `TRANSPORT` **30 of 30 substantive** and `ASYNC`
**22 of 22** — zero roll-up-only and zero uncited in both. `ruby scripts/knowledge.rb --gaps
TRANSPORT,ASYNC` closes with "0 of 52 IDs in 2 prefixes have no substantive entry". **Phase 8 budgets no
read-the-specification-directly time**, the same position phase 7 reported and the inverse of phases 2, 3
and 4. The gap paragraph's closing sentence — "Every other prefix has full corpus coverage"
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:161`) — is confirmed for both prefixes.

**The appendix-B roll-up hazard fires hard on this phase, harder than on any earlier one.**
`--prefix TRANSPORT --brief` returns 66 entries of which **29** carry `[appendix-B roll-up]`;
`--prefix ASYNC --brief` returns 64 of which **22** do. That is 44% and 34% — above phase 7's third, and
it is structural rather than accidental: appendix B's §B.6 and §B.7 are *the transport and async
conformance checklists*, so every phase-8 ID has a roll-up entry by construction. Two consequences point
in opposite directions and both are stated:

- **No ID is roll-up-*only*** (`--gaps` says so for both prefixes), so a `--req` on any phase-8 ID
  returns at least one substantive entry and the CLI's all-roll-up WARNING never fires.
- **A bare `--req` on a phase-8 ID is close to half noise.** A sub-phase author should reach for
  `--req <ids> --section rules,constraints,conclusions`, which is the reading mode phase 7 first
  recommended and which this phase needs more than phase 7 did.

**Two notes bind phase 8 through its own prefixes, and both are about the same carrier.**
`--origin note --prefix TRANSPORT,ASYNC` returns exactly two entries, both in `notes/observability.md`,
and together they are the sharpest inherited constraint on `8b`:

- **`observability/698552b4`** — fiber storage's range across the supported interpreters, and the write
  side's warning. The half that binds `8b` is the one `OI-13` carries: `Fiber#storage=` is the only
  whole-map write API, it warns on every call at the default warning level, and this repository's gate
  set fails the build on warnings.
  <sub>review · `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md` · high · sha:manual-phase4-fiber-storage-range</sub>
- **`observability/65191069`** — the half a `8b` author would otherwise get wrong twice. First,
  **copy-on-write protects the slot, not the object in it**: a mutable collection in a `Fiber[]` slot is
  one shared object across every thread and child fiber descended from the fiber that created it, which
  is `XCUT-11`'s "any shared mutable state MUST be synchronized" with no synchronisation and is invisible
  in a single-threaded test. Second, **`Fiber.current.storage = {"trace.id" => "x"}` raises `TypeError:
  wrong argument type String (expected Symbol)` while `Fiber["trace.id"] = "x"` succeeds** — the per-key
  setter coerces, the whole-map setter refuses. The entry names `ASYNC-8`–`ASYNC-12` explicitly as the
  consumers. It also carries its own caveat: it was verified on 3.4.10 only and **must be re-run on
  3.2.11 and 4.0.6** before anything rests on it.
  <sub>review · `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md` · high · sha:manual-phase5-fiber-slot-and-key-type</sub>

**Three more notes bind phase 8 through the surfaces it consumes.** Cited by key, not restated.

- **`concurrency-and-async/f414b864`** — the `concurrent-ruby` substitution note, and the one that
  routes work *to* this phase by name. Quoted, because the routing is the point:

  > The bounded-pool and deterministic-teardown rules in the same chapter
  > (`concurrency-and-async/6764e0b5`, `/dc345cae`, `/df658d73`, `/3692970f`, `/047644ea`, `/dd8e6d2d`)
  > are **not** resolved here and are not weakened: they bind `dexpace-async-thread`, an adapter gem
  > whose `NFR-2` budget permits one third-party library, and they are that gem's to answer in phase 8.

  Six harvested rules, routed to `8b` by phase 2, with no phase-2 obligation because phase 2 shipped no
  pool. `8b`'s design must read all six and say what it does with each. Two rules from the same chapter
  that the note *does* adopt and that bind `8b` just as hard: `/c0fab747` (protect only the smallest
  critical section) and `/ee54cb68` with `/f261a143` (never hold a lock across I/O).
  <sub>review · `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` · high · sha:manual-phase2-no-concurrent-ruby</sub>
- **`resource-management/d1f16cad`** — the note that says where the styleguide's per-call I/O timeout
  rules are actually paid: "**phase 8's transports, which own the socket and set
  `open_timeout`/`read_timeout`/`write_timeout` per call … with the values coming from phase 5's layered
  configuration chain as named settings rather than literals** — which is `2b9040ef` satisfied by a
  configuration key instead of a constant." That is a direct instruction to `8a`, and it is `IO-40`'s
  other half.
  <sub>review · `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` · high · sha:manual-phase3a-io40-no-timeouts</sub>
- **`pipeline/f02559b9`** — `raise error, cause: nil` is the spelling for re-raising an error a component
  is *carrying* rather than one it just rescued, because a bare `raise` silently assigns whatever is in
  `$!` — possibly the **caller's** in-flight exception — as the error's `#cause`. Every place `8a`, `8b`
  or `8c` surfaces a stored failure through `Completer#fail` or out of a `rescue` is that shape, and
  `ASYNC-13`'s unwrap is the requirement that makes it normative.
  <sub>review · `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` · high · sha:manual-phase4b-reraise-cause</sub>

**The audit group was run, and the skill's table is owed a row this document cannot add.** The
`knowledge-lookup` audit-group table carries **twelve** rows — phase 7's thirteenth is still owed and has
not been added — and the nearest existing row, *Fiber scheduler, thread safety*, is the `ASYNC` half only
and reaches no `TRANSPORT` topic. The group that was run is
`ruby scripts/knowledge.rb --prefix TRANSPORT,ASYNC --section rules --brief` — **55 entries across 4 topic
files** (`transport-adapter`, `cancellation-and-timeouts`, `concurrency-and-async`,
`cross-cutting-invariants`), **zero of them roll-up-tagged**, which is the same shape phase 7 reported:
the roll-ups live entirely in the `Reference` section, so the audit group is clean even where `--req` is
noisy. The wider topic form, `--topic transport-adapter,cancellation-and-timeouts,concurrency-and-async
--section rules --brief`, returns **125 entries across 3 topic files** and is the form a sub-phase should
run, because it reaches the styleguide-derived concurrency rules that carry no ID — including the six
`8b` inherits by name. **The row is owed**, and its exact content is:

| Audit group | Query (once harvested) | Today | Status |
|---|---|---|---|
| Transport and async-runtime adapters | `--topic transport-adapter,cancellation-and-timeouts,concurrency-and-async --section rules --brief` and `--prefix TRANSPORT,ASYNC --section rules --brief` | `--prefix-info TRANSPORT`, `--gaps TRANSPORT,ASYNC` | live |

Whoever files this document adds that row to `.claude/skills/knowledge-lookup/SKILL.md` in the same
change, **and adds phase 7's still-owed row beside it**. It is not a frozen tree.

**`--phase 0` through `--phase 7` were all run** to see what the predecessors already cite. The phase-8
prefixes are cited by six of the eight, and the pattern is informative:

| Predecessor | `TRANSPORT`/`ASYNC` IDs its documents cite |
|---|---|
| 0, 1 | none |
| 2 | `ASYNC-2`, `ASYNC-3`, `ASYNC-4`, `ASYNC-15`, `ASYNC-17`, `ASYNC-20` |
| 3 | `ASYNC-3`, `ASYNC-4`, `TRANSPORT-25`, `TRANSPORT-28` |
| 4 | `ASYNC-3`, `ASYNC-4`, `ASYNC-8`, `ASYNC-9`, `ASYNC-11`, `ASYNC-12`, `TRANSPORT-1`, `TRANSPORT-2` |
| 5 | `ASYNC-3`, `ASYNC-4`, `ASYNC-8`, `ASYNC-9`, `ASYNC-11`, `ASYNC-12`, `TRANSPORT-3`, `TRANSPORT-8` |
| 6 | `ASYNC-3`, `ASYNC-4`, `TRANSPORT-1`, `TRANSPORT-2` |
| 7 | `ASYNC-3`, `ASYNC-4`, `ASYNC-13`, `ASYNC-21`, `TRANSPORT-1`, `TRANSPORT-18` |

**`ASYNC-3` and `ASYNC-4` are cited by every phase from 2 onward and by none of them as work** — they are
§10.5's, every phase says "do not re-open", and phase 8 is the first phase whose gem makes `ASYNC-3`'s
antecedent real. That is six phases of consistent hand-off and it is the strongest evidence in the
repository that §10.5's split is settled.

**No knowledge note is filed by this document.** Four candidates are recorded under *Verified Ruby facts*
and each belongs to the sub-phase that acts on it: `Net::HTTP`'s built-in retry (`8a`), the
response-body-lifetime problem (`8a`), `Async::Cancel`'s non-`StandardError` ancestry (`8c`), and
`protocol-http1`'s field-name grammar against `HTTP-17`'s (`8c`). Recorded here so their absence is a
decision rather than an omission. **The `observability/65191069` note's own caveat is a phase-8
obligation**: it must be re-run on 3.2.11 and 4.0.6 by `8b`, and a note that stays single-interpreter
after `8b` has shipped a pooled-worker context restore is a note nobody paid for.

---

## The cut

**Three ways. Every boundary is a CONVENIENCE.**

| Sub-phase | Name | Spec chapter | Gems | Own IDs | Order |
|---|---|---|---|---|---|
| **8a** | Synchronous transport and the conformance harness | §17 | `dexpace-transport-net_http` **and** `dexpace-conformance` | 23 (`TRANSPORT`) | first, **convenience** |
| **8b** | The async-runtime adapter | §18 | `dexpace-async-thread` | 19 (`ASYNC`) | second, **convenience** |
| **8c** | Asynchronous transport | §17 + §18 | `dexpace-transport-async_http` | 10 (7 `TRANSPORT`, 3 `ASYNC`) | third, **convenience** |

Exact file names, which the sub-phase designs and plans must carry:

| Sub-phase | Design | Plan | Checklist (written at execution time) |
|---|---|---|---|
| **8a** | `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md` | `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance.md` | `…-phase8a-synchronous-transport-and-conformance-checklist.md` |
| **8b** | `docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-design.md` | `docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter.md` | `…-phase8b-async-runtime-adapter-checklist.md` |
| **8c** | `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md` | `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport.md` | `…-phase8c-asynchronous-transport-checklist.md` |

A sub-phase design written on a later day carries that day's `YYYY-MM-DD-` prefix; every other component
of the name is fixed here. Directory names are `phase8a`, `phase8b`, `phase8c`, nested one level under
`phase8/`, per `docs/README.md`'s naming rule.

### The roadmap's forecast, tested rather than deferred to

The bullet reads, in full:

> **Phase 8 (52 nominal IDs, effectively more), expected 8a transports, 8b async runtime.** Raw count
> alone would not force a split; shipping four gems does, and so does the per-gem conformance work the
> count does not see. The cut is the §17/§18 line, which is also the `SEAM-11`-versus-`SEAM-16`/`SEAM-17`
> line — a synchronous transport and an async-runtime bridge over the core pivot are genuinely different
> concerns.

**Four claims, tested one at a time.**

**1. "52 nominal IDs, effectively more" — confirmed, and the margin is larger than the phrase suggests.**
`TRANSPORT` 30 plus `ASYNC` 22 is 52 and nothing moves. What the count does not see is that **every one
of `8a`'s *assertable* `TRANSPORT` IDs — 21 of the 23, the two `DEF-10` ⏳ rows excepted — is re-asserted
against `8c`'s adapter** through the same `dexpace-conformance` assertion, because §9.3's whole argument
for shipping that gem is that "the *same* assertions could not run unchanged against
`dexpace-transport-async_http` or a future `httpx` adapter". Two of the twenty-one are re-asserted
through a **different route on each adapter** rather than by the same assertion: `TRANSPORT-1` is the
absence of a knob on `Net::HTTP` and a do-not-install obligation on `async-http`, and `TRANSPORT-18` is
vacuous on each for a different reason. So `8c`'s real budget is 10 own IDs plus 21 second-adapter
conformance rows, and `8a`'s is 23 own IDs plus the assertion objects, the `TCPServer` fixture and a gem's
first release. The phrase is right; the factor is roughly three, not roughly one.

**2. "Shipping four gems does [force a split]" — confirmed, and it is the trigger that actually fires.**
Phase 7's second gem fell *inside* `7a` and changed nothing about that cut. Phase 8's do not:
`dexpace-transport-net_http` spends its `NFR-2` budget on a **default gem**, `dexpace-transport-async_http`
spends its on a **third-party gem with a native extension and a fourteen-gem transitive closure**
(verified fact 7), `dexpace-async-thread` spends **nothing**, and `dexpace-conformance` spends **nothing**
and is the only one of them that is not an adapter. Four different dependency stories, three different
`rbs_collection.yaml` positions. That is a real segmentation trigger and not an arithmetic one. (Phase 0's
row creates six gem skeletons, so this is the phase that spends the most gem *budgets*, not the phase that
creates the most gem directories.)

**3. "The cut is the §17/§18 line" — confirmed as a *starting* line and rejected as the *whole* line.**
Five of §17's thirty requirements have an **async-only antecedent** and cannot be satisfied, let alone
tested, by a synchronous transport:

- `TRANSPORT-7` — "Cancelling **the async response future** MUST propagate cancellation into the in-flight
  native exchange".
- `TRANSPORT-8` — a native-internal cancellation "**while the SDK future is still live**".
- `TRANSPORT-9` — "a native response is delivered **after the SDK future** has already been completed or
  cancelled (the adaptation race)".
- `TRANSPORT-21` — "**On the async path**, a failure … MUST be delivered through the returned future".
- `TRANSPORT-23` — "**The async send** MUST NOT complete its future with a null response on success".

A two-way cut on the chapter line puts all five in `8a`, where `dexpace-transport-net_http` supplies no
future and no adaptation race, so `8a` would carry five IDs it cannot exercise and would have to either
defer them to `8b` (a silent chain) or assert them against a bridge it does not own. Two more —
`TRANSPORT-12` and `TRANSPORT-22` — say "**on both the sync and async paths**" in their own text.

**4. "Which is also the `SEAM-11`-versus-`SEAM-16`/`SEAM-17` line" — fails on the §17 side, which is the
side the cut turns on.** The chapter line and the seam line are not one line, and the failure is
one-directional:

- **§17 is not `SEAM-11`.** Five of its IDs are `SEAM-16`'s, as just shown. §17's own preamble says the
  chapter is about "send one request, get one response" delegated to a transport "(see §7 / **SEAM-11,
  SEAM-16**)" — both seams, named together, in the chapter's first sentence.
- **§18 is centrally about the bridge, and the roadmap's pairing is still too tidy — but it is not
  wrong.** §18's preamble names **both**: it "defines the portable contract an async-runtime adapter must
  honor when bridging the SDK's async HTTP transport SPI to a host runtime's concurrency primitives", and
  then, in its very next sentence, "the interchange point is a single canonical completion future (§7 /
  **SEAM-17**) that carries exactly one success value or one failure"
  (`docs/product-spec/18-asynchronous-runtime-adapter-contract.md:3`). So `SEAM-17` **is** §18's
  interchange point and no correction claims otherwise. What is still true, and is what makes `8b` a
  segment rather than a chapter, is that the obligations §18 actually imposes are mostly `SEAM-18`'s and
  `SEAM-25`'s: `ASYNC-2`'s worker-pool rejection, `ASYNC-3`/`ASYNC-4`'s blocking task on a worker thread,
  `ASYNC-5`'s producing worker, `ASYNC-8`–`ASYNC-12`'s thread handoff, `ASYNC-14`'s blocking bridge,
  `ASYNC-15`–`ASYNC-17`'s executor lifecycle and `ASYNC-19`'s "every bridge and facade overload" —
  **fifteen of twenty-two**. The remaining seven (`ASYNC-1`, `ASYNC-6`, `ASYNC-13`, `ASYNC-18`,
  `ASYNC-20`, `ASYNC-21`, `ASYNC-22`) restate the pivot/SPI contract and bind a native async transport as
  much as a bridge, which is why §9.3 (`:106-107`) groups ten of them as "exercised **against the
  pivot**".

**And `dexpace-transport-async_http` sits on neither side of the chapter line.** It is a **transport** by
chapter — §2.1 calls it "The reference *asynchronous* transport", it implements `SEAM-16` natively and it
is bound by §17's thirty requirements like any other adapter — and it is **not an async-runtime adapter**
by §18's own definition, because it bridges nothing:
it does not wrap the SPI over `async`, it *is* an implementation of the SPI that happens to run on a
reactor. Putting it in the roadmap's `8a` merges a default-gem synchronous adapter with a native-extension
reactor adapter whose body lifetime, cancellation semantics and error ancestry are all different
(verified facts 2, 3, 8, 9, 10). Putting it in the roadmap's `8b` merges a transport with a thread pool
that shares none of its code and none of its dependencies. **It gets its own segment, and that is the
whole of the three-way argument.**

**The correction the roadmap cell needs is given verbatim under *Roadmap follow-through owed*.**

### Why `8a` is one segment, and why the conformance gem is inside it

`8a` is 23 `TRANSPORT` IDs, one adapter gem and one non-adapter gem. Three questions a reader will ask.

**Why not split the adapter from the conformance gem?** Because a conformance assertion object with
nothing to assert against is `OI-8`'s exact shape — `NFR-4`-locked public API with no caller — and
`DEF-22`'s own argument is that one "would fix an interface before the contract it serves exists". By
`8a` the contract exists (spec ch.17, read in full) *and* an adapter exists to drive it, which is the
first moment both are true. Splitting them puts the assertion objects one review boundary away from their
only driver, which is the arrangement most likely to produce a suite that encodes what was built rather
than what the specification requires.

**Why `8a` rather than a fourth segment landing last?** A conformance suite written after three adapters
have shipped is a suite written *from* three adapters. §9.3 says the opposite is the point: the suite
carries "exactly the clauses an adapter author is most likely to satisfy by accident on the first call and
not on the second", which is a statement about writing the assertion before the second call exists. A
`8d` also strands the `TCPServer` fixture: `8a` and `8c` both need it, and neither can be tested without
it, so a segment that owns it and lands last is a segment both others must stub around.

**Why is 23 IDs one segment and not two?** The §17.3/§17.5 mapping halves (header and body mapping;
failure and response mapping) look separable and are not. `TRANSPORT-10`'s Content-Type authority is
decided by the same code that `TRANSPORT-26` makes emit a zero-length body and `TRANSPORT-11` makes drop
`Content-Length` — one outbound adaptation routine, three requirements. `TRANSPORT-24`, `TRANSPORT-25`
and `TRANSPORT-27` are one inbound adaptation routine. `TRANSPORT-15`, `TRANSPORT-16` and `TRANSPORT-29`
are the one `@owned` construction-time decision §3.7 fixes. And `TRANSPORT-2`, `TRANSPORT-17` and
`TRANSPORT-18` are settled by **one line of code** — `http.max_retries = 0`, which satisfies
`TRANSPORT-2` and removes `TRANSPORT-17`'s and `TRANSPORT-18`'s antecedent outright (`TRANSPORT-17`'s
"MUST NOT itself trigger a second write" half still needs asserting) —
(verified fact 1), which a cut between §17.1 and §17.4 would put in two documents.

### Why `8b` is one segment

`8b` is 19 `ASYNC` IDs and one gem with **zero third-party dependencies**. Its content is a bounded
`Thread`/`Thread::SizedQueue` pool satisfying `SEAM-18`'s caller-supplied-executor contract, the
`ASYNC-15`–`ASYNC-17` lifecycle over phase 2's `Dexpace::Closeable`, the `ASYNC-8`–`ASYNC-12` diagnostic
hop over `Fiber[]`, and `ASYNC-18`'s scheduled delay. Four reasons it is one segment:

1. **The pool is one object and every lifecycle requirement is about it.** `ASYNC-15`'s three clauses
   (idempotent, ownership-aware, interrupt-safe), `ASYNC-16`'s graceful shutdown, `ASYNC-17`'s no-op
   default and `DEF-31`'s lifecycle event are four requirements and one `#close`.
2. **The diagnostic-hop five (`ASYNC-8`–`ASYNC-12`) are one save/install/restore**, and splitting them
   from the pool would put the restore in a different document from the thing it restores on.
3. **It is the phase's only sub-phase with no socket.** `8b` needs no `TCPServer` fixture, no wire
   grammar and no header mapping; its whole test surface is threads, queues, futures and fiber storage.
   That is a genuinely different testing story and it is what makes `8b` independent of both others.
4. **It is where §10.5's three MUSTs get their antecedent.** Phase 4's segmentation design states it
   exactly: "In phase 4 the executor is a duck type with no implementation, so no worker exists to fail
   to interrupt. `dexpace-async-thread` is what makes the antecedent real"
   (`docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md:685-687`). One document, three ⏳/N/A
   rows, one argument.

### Why `8c` is one segment, and why its ten IDs are not a reason to fold it

`8c` is 10 own IDs and one gem. Ten is small — phase 7 rejected a nine-ID segment on exactly that ground
— so the argument has to be made rather than assumed. It rests on four measured differences between
`async-http` and `Net::HTTP`, every one of which is a different *implementation*, not a different value:

- **Body lifetime is solved natively and is unsolved for `Net::HTTP`.** `async-http` returns the response
  object in 1 ms and yields the second body chunk 400 ms later, with no pump, no fiber and no thread
  (verified fact 3). `Net::HTTP` buffers the whole body before `#request` returns unless the response is
  read inside a block that cannot outlive `#call` (verified fact 2). `SEAM-11`'s no-pre-buffering clause
  and `TRANSPORT-25` are free on one adapter and the single hardest problem on the other.
- **Cancellation is real on one and cooperative-only on the other.** `Async::Task#stop` runs `ensure`
  blocks and settles the task `:cancelled` (verified fact 8); the only way to abort a blocked `Net::HTTP`
  read is to close its socket from another thread, which surfaces as `IOError` (verified fact 11).
  `TRANSPORT-7` and `ASYNC-6` are satisfiable on `8c` and are `8b`'s ⏳ on the thread path.
- **The error ancestries do not overlap and one of them is outside `StandardError`.** `Async::Cancel <
  Exception` — and `Async::Stop` is a deprecated **alias** of `Async::Cancel`, not a subclass of it
  (verified fact 9) — so `rescue => e` does not see a cancelled task and `Dexpace.close_quietly`, which
  rescues `StandardError`, cannot be `8c`'s orphan-close path. Nothing in `8a` meets that shape.
- **The header grammars differ at exactly the point `TRANSPORT-12` is about.** `protocol-http1` raises
  `Protocol::HTTP1::BadHeader` on a header name the SDK model accepts; `Net::HTTP` writes it to the wire
  (verified fact 5). `TRANSPORT-12` and `TRANSPORT-13` have a live antecedent on one adapter and none on
  the other.

Ten own IDs plus twenty-three second-adapter conformance rows plus a fourteen-gem transitive closure plus
an HTTP/2 path is not a small segment. The ID count is the one measure that understates it, which is what
the roadmap's own "effectively more" says.

### Why none of the three leads another

Stated as the six directed edges a reader will look for. Each is answered from a shipped contract or a
measured fact, never from "probably not".

- **`8a` → `8b`?** No. `dexpace-async-thread`'s declared dependencies are `dexpace-core` and **nothing
  else** (§2.1). Its pool posts a block; what the block does is the caller's business, and phase 2's
  `FakeTransport` under `gems/dexpace-core/test/support/` is a sufficient driver for every `ASYNC` clause
  `8b` owns. Nothing in `8b` needs a socket, a wire fixture or a real adapter.
- **`8b` → `8a`?** No. `dexpace-transport-net_http` is a synchronous transport; it posts nothing, owns no
  executor, and takes phase 2's no-op close. The one place the two meet is
  `Transport.async_over(net_http, executor: pool)` — a convergence point (below), not a build-order edge,
  and it is written by whichever lands second.
- **`8a` → `8c`?** No, but it is the closest to one. `8c` consumes two artifacts `8a` is assigned:
  §9.3's `TCPServer` wire fixture and `DEF-22`'s assertion-object protocol. **Both are assigned to `8a`.**
  Neither is a *design* dependency — `8c`'s design can be written in full before `8a` lands — and if the
  sub-phases run out of order the one that lands first writes them and `8a`'s design records that it
  consumed rather than wrote them. **Both designs must say which side they are on** (`R16`) so the fixture
  is neither written twice nor left to each assuming the other wrote it.
- **`8c` → `8a`?** No. `async-http` brings its own reactor, its own connection pool (`async-pool`) and
  its own HTTP/1.1 and HTTP/2 stacks. It needs no `Net::HTTP` and no `Dexpace::Transport::NetHTTP`
  constant.
- **`8b` → `8c`?** No, and this is the edge a reader is most likely to invent. `async-http` does **not**
  use a thread pool: it drives `Async::Task` under a `Fiber.scheduler`, and `Async::Task#stop` is its
  cancellation primitive (verified fact 8). `dexpace-transport-async_http` declares `dexpace-core` and
  `async-http` — not `dexpace-async-thread` — and `NFR-2`'s budget would not permit a third declaration
  anyway.
- **`8c` → `8b`?** No. `dexpace-async-thread` is a `SEAM-18` executor for wrapping a *blocking* transport.
  A reactor-native transport is already async and has nothing to wrap.

**The one thing that is genuinely shared, and why it is not an edge.** `Dexpace::TransportError <
::IOError` is consumed by `8a` and `8c` and lives in **`dexpace-core`**, which is none of the three
sub-phases' gems. It is therefore a **phase-level task**, not an inter-sub-phase dependency — the same
structural answer phase 6 gave to `RETRY-13`'s shared calculator, arriving at a different shape because
the shared object is in a different gem from every sub-phase that uses it. **`8a` lands it** (phase-level
task 1 below fixes that and fixes the shape); `8c` requires it and writes it only if `8c` runs first.

### The order that is recommended, and why it is only a recommendation

`8a → 8b → 8c`. Four reasons, none of them a dependency:

1. **`8a` retires the most risk, and the risk is new to the repository.** It opens the first real socket
   (roadmap cross-cutting constraint 4), spends the first transport `NFR-2` budget — on `net-http`, a
   *default* gem, which is the cheapest possible first spend — adds the first `rbs_collection.yaml` row,
   and releases the first gem other than `dexpace-core`'s dependents. Every one of those is a phase-0 gate
   meeting a case it has never seen. Landing them first surfaces a scaffold defect while two sub-phases
   still have room to absorb it. This is the risk-retirement argument phases 4, 5, 6 and 7 each gave their
   first segment.
2. **`8b` is the only sub-phase that can be worked on with no network at all**, so it is the safest to run
   in parallel with either other, and it closes the register's oldest phase-8 obligations (`DEF-31`,
   `DEF-18`'s three rows) without waiting for a wire.
3. **`8c` carries the largest dependency risk and benefits most from a proven fixture.** Fourteen
   transitive gems, a native extension, and the first `bundler-audit` surface the repository has had.
4. **`8a` before `8c` puts the conformance protocol in place before the adapter that must satisfy it
   twice over.** Convenience, not order: `8c` can write its own if it runs first.

**Because the order is a convenience, each sub-phase's design must state its own independence in its own
Prerequisite section rather than inheriting a chain by habit.** A `8b` plan whose first task waits on
`8a`'s transport has re-imposed a chain nothing requires; so has a `8c` plan that waits on `8b`'s pool.

### Six other cuts were considered, and rejected

**Rejected cut A — the roadmap's two ways: `8a` transports (both), `8b` async runtime.** Rejected under
*The roadmap's forecast* on four grounds, of which two are decisive: it puts `TRANSPORT-7`/`8`/`9`/`21`/
`23` in a sub-phase with no future to cancel, and it merges a default-gem synchronous adapter with a
native-extension reactor adapter that shares none of its mechanics. It also produces a 3-gem/1-gem split
whose larger half is the biggest single document in the delivery.

**Rejected cut B — two ways on the gem-dependency line: `8a` the two zero-third-party gems
(`dexpace-async-thread`, `dexpace-conformance`), `8b` the two transports.** Superficially attractive
because it aligns with the `NFR-2` budget. Rejected because it merges the two adapters whose mechanics
differ most (cut A's second objection, unchanged) and because it pairs a thread pool with a conformance
suite that has nothing to do with it — `dexpace-conformance`'s first content is a **transport** suite, per
the roadmap's phase-8 row.

**Rejected cut C — four ways, with `dexpace-conformance` as `8d` landing last.** Rejected under *Why the
conformance gem is inside `8a`*: a suite written from three finished adapters encodes what was built, and
the `TCPServer` fixture two sub-phases need cannot land after them.

**Rejected cut D — four ways, with `dexpace-conformance` as `8a` landing first, before any adapter.**
The mirror of C, and it fails on `DEF-22`'s own recorded argument: "an assertion object with no transport
contract to assert against would fix an interface before the contract it serves exists". It also produces
a segment with no gem of its own to test against, which `OI-8` is the register's standing example of.

**Rejected cut E — splitting `8a` along §17's own section headings (pipeline authority and cancellation
against header/body/lifecycle/response mapping).** Rejected under *Why `8a` is one segment*, on
`TRANSPORT-2`/`17`/`18` being one line of code, on `TRANSPORT-10`/`11`/`26` being one outbound routine,
and on `TRANSPORT-24`/`25`/`27` being one inbound routine.

**Rejected cut F — splitting `8b` along the §18.3 logging-context line, giving `ASYNC-8`–`ASYNC-12` their
own segment.** Five IDs, one mechanism, and the mechanism is a save/install/restore *on the pool's
worker*. A segment that owns the restore and not the thing it restores on has no object to test against,
and `OI-13`'s `Fiber#storage=` decision would then be taken in a document that ships no pool. It is phase
7's rejected cut C in a different subsystem and it fails for the same reason.

---

## Spec-forced boundaries — not open to `8a`, `8b` or `8c`

Each is a MUST, a design deviation already argued, a shipped phase-0-through-7 contract, or a roadmap
obligation already fixed, that settles something a sub-phase design might otherwise believe it is free to
decide.

1. **The pipeline is the single authority on redirect and retry, and every adapter disables its native
   equivalent.** `TRANSPORT-1` ("the follow-redirects knob's default MUST be off"), `TRANSPORT-2`, and
   phase 4c's stage order as the premise they presuppose
   (`docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md:1437`). **This is not
   vacuous for either MVP adapter on the retry half** — verified fact 1 — and no sub-phase may record it
   as vacuous on design §3.2's stated reason.
2. **The streaming contracts impose no timeout; the transport owns every deadline.** `IO-40`, in full:
   "These streaming contracts MUST NOT impose their own read/write timeout or deadline; the adapter wraps
   foreign streams with a no-op timeout, **delegating all deadline enforcement to the transport** … The
   prompt-cancellation-of-blocked-I/O guarantee itself belongs to the wrapped transport, not to these
   contracts." Phase 3a's `resource-management/d1f16cad` note names phase 8's transports as where the
   styleguide's per-call timeout rules are paid. A sub-phase may not push a deadline down into
   `Dexpace::IO::BufferedSource`.
3. **Deadlines are explicit values, never ambient interrupts.** `Timeout.timeout`, `Thread#raise` and
   `Thread#kill` are forbidden in every gem here (§8.3, enforced by phase 0's `Dexpace/NoThreadInterrupt`
   cop). On the sync path a deadline goes to `open_timeout`/`read_timeout`/`write_timeout`
   (`cancellation-and-timeouts/92dd3710`); on the async path to the task's own timeout, interrupting only
   at a scheduler checkpoint.
4. **§10.5's three MUSTs are settled and are split exactly this way.** `ASYNC-3` **not satisfied**;
   `PIPE-33`'s interrupt clause **not satisfied** (phase 4's ID, four of five clauses met, re-asserted
   here); `ASYNC-4` **vacuous**, and vacuous is a real argument — "a port that never delivers an interrupt
   cannot produce the hazard, so the guarantee holds — and holds more strongly than an implementation of
   the handshake would provide, since a handshake narrows a window it does not close" (§10.5). `DEF-18`
   carries all three. **The mitigation is load-bearing and a sub-phase may not weaken it**:
   check-after-resume (`concurrency-and-async/611b9392`) plus `Completer#on_cancel`.
5. **The pivot is core-owned and phase 8's adapters bridge to it and never replace it.** Roadmap
   cross-phase obligation 5 (`:140-142`), §10.3, phase 2's `Dexpace::Async::Future` and `Completer`. No
   adapter may put `Async::Task`, `Protocol::HTTP::Response` or `Net::HTTPResponse` in a public signature.
6. **`NFR-11` is mechanised as an RBS scan over `sig/`** asserting that no constant outside `Dexpace::`
   and a fixed stdlib allowlist appears in any public signature. That is why boundary 5 exists, and it
   binds `8c` hardest: `Protocol::HTTP::Response` and `Async::Task` are the two constants most likely to
   leak into an RBS file by convenience.
7. **`NFR-2`'s budget is core plus at most one third-party library per adapter**, enforced by phase 0's
   `gates:gemspec_audit` with its `two_third_party` negative fixture. `dexpace-async-thread` and
   `dexpace-conformance` declare `dexpace-core` and nothing else, **by design and not by accident** —
   §2.1 says so for both. `8b` may not reach for `concurrent-ruby`; `concurrency-and-async/f414b864` is
   the note that already settled it.
8. **Every adapter's registration asserts `Dexpace::VERSION`.** Phase 2's
   `Dexpace::Registry#register(key, factory, core:)` takes the adapter's `~> MAJOR.MINOR` requirement as a
   **required** keyword and raises `Dexpace::SeamError` on skew (`DEF-21`, deviation `P2-7`). Every one of
   phase 8's gems registers, and none may pass the keyword optionally.
9. **Ownership is a construction-time fact, not a close-time judgement.** `cross-cutting-invariants/093b7681`,
   §3.7, `XCUT-22`, `SEAM-14`, `SEAM-25`, `ASYNC-15`: two differently named entry points, one that builds
   the resource and one that borrows it, with a frozen `@owned` boolean set at construction. `TRANSPORT-15`
   and `ASYNC-15` are the same rule under two IDs and get one implementation.
10. **Idempotent close is a latch under a `Thread::Mutex` held only across the flip.** §3.7, `XCUT-13`,
    phase 2's `Dexpace::Closeable`. The mutex is never held across a release, because Ruby's `Mutex` is
    per-fiber-owned and non-reentrant. Close never blocks on an unbounded await.
11. **Wire-boundary re-validation raises; `TRANSPORT-12`'s drop is a different rule over a different set.**
    `DEF-25` requires every adapter to call phase 1's `Dexpace::HeaderSyntax` again immediately before
    dispatch, and `HTTP-17`/`HTTP-18`/`XCUT-18`'s response to a violation is an **error**.
    `TRANSPORT-12`'s subject is a header "valid at the SDK model layer but rejected by the native client's
    stricter wire grammar", whose response is a **silent per-header drop**. The two sets are disjoint by
    construction and no sub-phase may merge them. Verified fact 5 gives the concrete example.
12. **A pipeline is a transport and closing it is a no-op on the transport.** `PIPE-26`, `PIPE-27`, phase
    4c. An adapter may not assume its caller is a pipeline, and a pipeline wrapping an adapter never
    closes it.
13. **Conformance runs against a local `TCPServer`, never a stubbing library** (§9.3), for two stated
    reasons: the requirements are about socket-level behaviour a stub cannot express, and a stub needs a
    per-client shim so the same assertions could not run unchanged against a second adapter.
14. **`dexpace-conformance`'s assertions are framework-agnostic callables** — "each one a callable that
    either returns cleanly or raises a `Dexpace::Conformance::Failure` carrying the expected and actual
    values — with thin Minitest and RSpec drivers over them" (§9.3, `DEF-22`). Minitest is a development
    dependency of the first-party build and never a runtime constraint on a consumer.
15. **Appendix B's phase-8 restatements are fixed by §9.3 and are not re-decided here.** B.6 is exercised
    per adapter; B.7's `ASYNC-4` is vacuous by construction and **`ASYNC-3`'s item is recorded as
    *failing*, not vacuous**, "since `dexpace-async-thread` supplies the blocking-task-on-a-worker
    antecedent the requirement conditions on". A failing item the port has decided not to satisfy "is
    reported as a failure by the suite and suppressed in the port's own build through a named waiver
    listing the requirement ID, so the gap stays visible rather than disappearing into a restated item."
16. **The seams are phase 2's and phase 8 registers into them.** `Dexpace::Transport` and
    `Dexpace::AsyncTransport` (both `#call(request, options, cancellation)`), `Dexpace::Async::Future` /
    `Completer`, `Dexpace::Cancellation`, `Dexpace::Closeable`, `Dexpace.close_quietly`,
    `Dexpace::Bridge::AsyncOver` / `SyncOver`, `Dexpace::Registry`. Phase 8 adds no seam, no second
    registry and no competing root.
17. **`SEAM-15` is taken explicitly: a send after close raises `Dexpace::ClosedError`** (§3.7 `:497-499`,
    unqualified), and `dexpace-conformance` asserts it among §9.3's lifecycle assertions. Phase 2 shipped
    the class and the rule with **no raise site**; phase 8's adapters are the first owners and are where
    the raise lands. **What is open, and is `8a`'s to decide rather than a boundary:** whether a transport
    that only *borrows* a caller-supplied client also raises, since it closed nothing — §3.7 does not
    distinguish, and §3.2's per-call `Net::HTTP` construction makes the borrowed case the only one with a
    live client to keep using.
18. **Bytes on the wire are `Encoding::BINARY` in both directions.** §3.1, phase 3a. Verified on both
    adapters (facts 2 and 3): `Net::HTTP`'s `read_body` chunks and `async-http`'s `body.read` chunks are
    both `ASCII-8BIT` and unfrozen.
19. **`URI::RFC3986_PARSER` is pinned for every parse and every resolution**, enforced by
    `Dexpace/NoUriDefaultParser`. An adapter converting a `Dexpace::Request#url` into a native endpoint
    touches this rule on every call.
20. **`OBS-19` is not a free-standing decision for phase 8 to reopen; it rides on `TRANSPORT-13`.**
    `DEF-41` defers the policy object with the two halves it is built from already shipped in 5b
    (`Severity`'s two levels and the once-per-key latch). See the sweep: the row's stated pick-up
    condition **is met**, by `8c`.

---

## Scope: every ID, assigned to exactly one sub-phase

**The assignment rule, stated once because three IDs turn on it.** An ID lands in the sub-phase whose
**antecedent** it is about. A requirement whose subject is "a transport" generically, and which both MVP
adapters must satisfy, lands in the sub-phase that first satisfies it and writes the conformance
assertion; **a second adapter satisfying the same ID adds a driver to that same assertion and gets no
second row.** That is the inverse of the "two rows, one obligation" treatment phase 2 gave `SEAM-29` and
phase 3b gave `HTTP-46`, and it is what keeps the one-row-per-ID convention intact across the phase's
gems. **`ASYNC-6` is the one ID the rule has to be quantified over adapters for**: its text is "across
**each** adapter" with a per-adapter conformance clause, so its row is `8c`'s (the only sub-phase that can
satisfy both directions) and `8b` carries a stated cross-reference rather than a silent absence.

### Reconciliation against the roadmap's arithmetic

| | `TRANSPORT` | `ASYNC` | Total |
|---|---|---|---|
| Roadmap's phase-8 row (`:93`) | 30 | 22 | **52** |
| `8a` | 23 | 0 | 23 |
| `8b` | 0 | 19 | 19 |
| `8c` | 7 | 3 | 10 |
| **Sum** | **30** | **22** | **52** |

**No ID moves in and none moves out.** Phase 8 is unlike phase 6, where `DEF-35` moved fifteen `RECOV`
IDs in; nothing analogous exists here. `PIPE-33` is re-asserted by `8b` and **keeps its phase-4 row** —
phase 4's design states the treatment: "Phase 8's disposition is therefore a re-assertion at the point
the requirement starts applying, not a second decision"
(`docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md:687-689`). It is a cross-reference row in
`8b`'s checklist, not a budget line. `ASYNC-6` is the mirror case **inside** the phase: its row is `8c`'s
and `8b` carries a second cross-reference row, because the requirement is quantified over "each adapter"
and a silent absence in the sub-phase that ships one would be indistinguishable from an oversight.

Dispositions other than ✅, across the whole phase: **three ⏳** (`TRANSPORT-28` and `TRANSPORT-30` against
`DEF-10`; `ASYNC-3` against `DEF-18`) — **corrected in place 2026-09-12**: `TRANSPORT-28` is
**partially satisfied**, not ⏳ whole. `8a`'s `R5` measured its embedded MUST (a file body is
replayable) and its byte-range clause as satisfied with no adapter code, through phase 3b's
`FileBody#write_to`, and carries only the "zero-copy path where supported" clause ⏳ against `DEF-10`.
Marking the whole ID ⏳ would defer a met MUST, which the checklist legend exists to prevent; this
document's own `R5` invited the split ("decide whether to implement the reachable half and mark
`TRANSPORT-28` partially satisfied") and `8a` took it. `TRANSPORT-30` stays ⏳ whole. Also **two N/A by §10.5 and §11.21** (`ASYNC-4`, `ASYNC-21`); **two
vacuous on `8a`'s adapter and re-asserted against `8c`'s by a different route** (`TRANSPORT-1`, the
absence of a follow-redirects knob; `TRANSPORT-18`, once `max_retries = 0`), each carrying its reason in
its row rather than a tick; and **one open** (`TRANSPORT-8`, settled by `8c` under `R14` — **settled
2026-09-12 as ✅ satisfied on `dexpace-transport-async_http`**: a cancellation arriving from the host
runtime's own structured-concurrency scope reaches the in-flight exchange as `Async::Cancel` while the
pivot is live, which is the requirement's "originates inside it" antecedent, and the terminal-versus-
retryable discrimination is free because `Async::Cancel < Exception` and `Async::TimeoutError <
StandardError`. §12 records the ID vacuous; `8c` files `OI-41` against that frozen cell rather than
correcting it).

### `8a` — Synchronous transport and the conformance harness (23 IDs, all `TRANSPORT`)

Gems: `dexpace-transport-net_http` (declares `dexpace-core` + `net-http`, spending its `NFR-2` budget on a
default gem) and `dexpace-conformance` (declares `dexpace-core` and nothing else).

| ID | Level | What `8a` owns |
|---|---|---|
| `TRANSPORT-1` | MUST | `Net::HTTP` exposes no follow-redirects knob (verified), so the clause is satisfied by the absence of one; the row states that and names `8c`'s obligation not to install `Async::HTTP::Middleware::LocationRedirector` |
| `TRANSPORT-2` | MUST | **`http.max_retries = 0`, explicitly and asserted.** Not vacuous — verified fact 1. The conformance clause is written as the specification words it: a single-use body, a first-attempt connection failure, assert no silent re-send |
| `TRANSPORT-3` | MUST | Sync-path cancellation as a terminal, non-retryable interrupt-shaped I/O exception, discriminated **out-of-band** through `Dexpace::Cancellation#reason`'s typed object (§3.3, `XCUT-2`) and never by matching a message |
| `TRANSPORT-4` | MUST | A read timeout is the **retryable** transport failure and does not set a cancellation flag. `Net::ReadTimeout < Timeout::Error < RuntimeError` and is not an `::IOError` (verified fact 10), so the wrap is what makes the clause true |
| `TRANSPORT-5` | MUST | Per-call `open_timeout`/`read_timeout`/`write_timeout` on a per-call `Net::HTTP`, never on a shared client (§3.2). `8a` decides what one `RequestOptions#timeout` means across three knobs (`R3`) |
| `TRANSPORT-6` | SHOULD | The clamp. `Net::HTTP`'s timeouts are floating-point seconds and accept `0.0005` (verified), so truncation-to-zero is unreachable here; §3.2 requires the clamp be implemented anyway for adapters over coarser APIs |
| `TRANSPORT-10` | MUST | Caller Content-Type authoritative, matched case-insensitively. Live: `Net::HTTP` stamps `Content-Type: application/x-www-form-urlencoded` on any body with no explicit type (verified fact 4) |
| `TRANSPORT-11` | MUST | The drop set. Live and larger than the requirement's minimum: `Net::HTTP` recomputes `Content-Length` but **honours a caller-set `Host`** verbatim, and auto-stamps `Accept-Encoding`, `Accept` and `User-Agent` (verified fact 4) |
| `TRANSPORT-14` | MUST | Inbound leniency. Entirely `8a`'s work: `Net::HTTP` **preserves** a control byte in a value and a non-ASCII byte in a name rather than dropping them (verified fact 6), and `XCUT-18` makes `Dexpace::Headers` reject both |
| `TRANSPORT-15` | MUST | Ownership-aware close over §3.7's `@owned` boolean and two entry points |
| `TRANSPORT-16` | MUST | Idempotent, non-blocking close over phase 2's `Dexpace::Closeable` latch |
| `TRANSPORT-17` | MUST | A single-use body written exactly once. `max_retries = 0` is what makes it true on this adapter (verified fact 1: the native retry re-runs `req.exec`, re-writing the body, for GET/HEAD/**PUT**/**DELETE**/OPTIONS/TRACE) |
| `TRANSPORT-18` | MUST | Vacuous **once `max_retries = 0`** — and the row must state that reason and not §11.18's, which is wrong (verified fact 1) |
| `TRANSPORT-19` | SHOULD | An abandoned streaming-body subscription unblocks its producer, idempotently. Interacts with `R1`'s pump decision |
| `TRANSPORT-20` | MUST | The canonical retryable transport failure, raised from the adapter. The **type** is the phase-level task; the raise sites are `8a`'s |
| `TRANSPORT-22` | MUST | Close the native response if adaptation throws, on both paths, through `Dexpace.close_quietly` (§3.7 names this call site explicitly) |
| `TRANSPORT-24` | MUST | Total status mapping. Verified: 499 and 520 both surface faithfully with a readable body |
| `TRANSPORT-25` | MUST | The lazily-read body whose close cascades. **`R1`** — the hardest single decision in the phase |
| `TRANSPORT-26` | MUST | A body-less request valid for any permitted method. Verified: a body-less POST already dispatches with `Content-Length: 0` |
| `TRANSPORT-27` | SHOULD | Unknown media type and the `-1` length sentinel. **Satisfied whole** — **corrected in place 2026-09-12**; this cell previously read "**Half unreachable**: a non-numeric `Content-Length` raises `Net::HTTPHeaderSyntaxError` out of `#request` (verified fact 12)", which is what fact 12 measured **without a block**. `8a` uses the block form for `R1`'s reasons anyway, and under it the response head is delivered in full before `Net::HTTPResponse#content_length` raises, so the length is parsed from the raw header text and the unparseable header deleted from the native response before the body read (`8a` design's verified fact 12, `R4` resolved). No deviation and no pre-parse |
| `TRANSPORT-28` | SHOULD | **Partially satisfied** (corrected in place 2026-09-12; this cell read "⏳ `DEF-10`" whole). The embedded MUST and the byte-range clause are met with no adapter code through 3b's `FileBody#write_to`; only the zero-copy clause is ⏳ `DEF-10`. `BODY-12` clause 2's transport half is UNSCHEDULED with phase 8a named — see the sweep and `R5` |
| `TRANSPORT-29` | MUST | Concurrent-call safety and effective immutability. Falls out of the per-call `Net::HTTP` (§3.2) and is asserted, not assumed |
| `TRANSPORT-30` | SHOULD | ⏳ `DEF-10`. Undiscoverable proxy features, and the MUSTs embedded in it (proxy credentials never logged, never answered to a 401) |

`8a` additionally owns, without owning a new ID: `dexpace-conformance`'s gemspec and `DEF-22`'s assertion
objects; §9.3's `TCPServer` fixture; `DEF-25`'s call site in this adapter; `DEF-29`'s UNSCHEDULED mark;
`DEF-42`'s transport-milestone emitter, subject to `R6`; **`7c`'s `PAGE-36` per-call-options conformance
test** (`docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md:1436`), which is not
`TRANSPORT-5`'s concurrent pair; **`5c`'s two conformance obligations on `dexpace-conformance`** —
`OBS-25`'s allocation assertion written under `5b`'s `R8` rule (arguments that *cannot allocate*, not the
file's `frozen_string_literal` comment and not a two-loop delta) and the **recording span** `OBS-21`'s
idempotence assertion needs, which that gem must supply
(`docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md:1455`); and **the stated
cross-reference for `TRANSPORT-12`'s sync half**, which is vacuous on this adapter (verified fact 5) and
whose row is `8c`'s.

### `8b` — The async-runtime adapter (19 owned IDs, all `ASYNC`, plus two cross-reference rows)

Gem: `dexpace-async-thread` (declares `dexpace-core` and **nothing else**).

| ID | Level | What `8b` owns |
|---|---|---|
| `ASYNC-1` | MUST | The single-value contract, exercised through a real producer for the first time: `Transport.async_over(transport, executor: pool)` settling phase 2's `Completer` |
| `ASYNC-2` | MUST | Every construction-time failure through the failure channel, **including worker-pool rejection** — the requirement names "a saturated/shut-down executor", which is this gem |
| `ASYNC-3` | MUST | ⏳ `DEF-18`, §10.5. **Not satisfied and not claimed to be.** `8b` may not re-open the trade; what it decides is the *mitigation's* observable shape (`R10`) |
| `ASYNC-4` | MUST | N/A — vacuous, §10.5, and appendix B records it as vacuous rather than passing (§9.3 B.7) |
| `ASYNC-5` | MUST | The orphaned closeable result closed exactly once, by whoever loses the produce/terminate race, under check-after-resume (`concurrency-and-async/611b9392`) |
| `ASYNC-6` | MUST | **Cross-reference row, no budget line.** The ID is `8c`'s, but `ASYNC-6` is quantified over "**each** adapter" with a per-adapter conformance clause. `8b` states the thread-pool half explicitly: cancelling the pivot reaches the worker only at its next check-after-resume point, which is `ASYNC-3`'s unsatisfied mode and not a second decision (§10.5, `DEF-18`) |
| `ASYNC-7` | SHOULD | The per-adapter README contrast §3.3 fixes: "the thread adapter lets an in-flight blocking read finish, the reactor-backed ones abort at the next scheduler checkpoint" (`concurrency-and-async/74aee9a8`). `8a` and `8c` each write their own section; `8b` owns the ID |
| `ASYNC-8` | SHOULD | Diagnostic-context propagation across the thread hop, over `Fiber[]` and never `Thread.current[]` |
| `ASYNC-9` | MUST | Save the worker's prior context, install for the duration, restore in an `ensure` including on a throw. **`R8`** — `OI-13`'s `Fiber#storage=` warning |
| `ASYNC-10` | MUST | Capture **per task submission**, not at pool construction. This is the clause a pooled worker makes non-trivial |
| `ASYNC-11` | MUST | Absent context captures empty; reinstating empty clears rather than raises. `Fiber.current.storage = nil` reads back differently on 3.2 than on 3.4/4.0 (`OI-13`), so the spelling is not free |
| `ASYNC-12` | MUST | The thread-creation-boundary transfer. **Antecedent check required**: a new `Thread` **does** inherit `Fiber[]` (verified fact 13), so the live case is the pooled worker, not the fresh one. **`R9`** |
| `ASYNC-13` | MUST | Unwrap wrapper exceptions to the original cause, terminating on a non-wrapper, a nil cause or a cycle. `Dexpace.each_cause` (phase 4b) is the walk; `raise error, cause: nil` (`pipeline/f02559b9`) is the re-raise |
| `ASYNC-14` | MUST | The async→sync blocking bridge. Phase 2 shipped `Bridge::SyncOver`; `8b` is the first sub-phase that can exercise it end to end, and §10.4 already settled that this port has no interrupt flag to restore |
| `ASYNC-15` | MUST | The three-clause close, and **`DEF-31`'s lifecycle event gets its first real subject here** |
| `ASYNC-16` | SHOULD | Graceful shutdown through §8.3's cancellable queue wait with a bounded deadline, never an unbounded `Thread#join` (§3.7 names this constraint for this gem by name) |
| `ASYNC-17` | SHOULD | The no-op default close on the SPI, and the rule that an owning implementation overrides it |
| `ASYNC-18` | MUST | The non-blocking scheduled delay: immediate at zero, rejected at negative, cancellable. **`R11`** — phase 5a's `Dexpace::Async.delay` raises with no `Fiber.scheduler` |
| `ASYNC-19` | MUST | Per-call options threaded through **every** bridge and facade overload, never dropped by an options-ignoring default |
| `ASYNC-20` | MUST | Cancelling a future whose response was already delivered must not close it. The negative twin of `ASYNC-5`, and the pair is one test |

`8b` additionally carries **two cross-reference rows with no budget line** — `PIPE-33` (phase 4's ID,
whose interrupt clause's antecedent becomes real here) and `ASYNC-6` (`8c`'s ID, quantified over "each
adapter") — implements **`Dexpace::Page::_Executor`**, the one-method `#post { }` duck type `PAGE-29`'s
executor mode takes and whose first real implementation `7c` assigns to this gem
(`docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md:1320`), and must answer the six
bounded-pool and deterministic-teardown corpus rules phase 2 routed to this gem by name (`R12`).

### `8c` — Asynchronous transport (10 IDs: 7 `TRANSPORT`, 3 `ASYNC`)

Gem: `dexpace-transport-async_http` (declares `dexpace-core` + `async-http`).

| ID | Level | What `8c` owns |
|---|---|---|
| `TRANSPORT-7` | MUST | Cancelling the SDK future propagates into the in-flight exchange. `Async::Task#stop` is the primitive and it runs `ensure` blocks (verified fact 8) |
| `TRANSPORT-8` | MUST | Native-internal cancellation discriminated from a genuine timeout. **Disposition open** — §12 calls it vacuous for `Net::HTTP` and says nothing about `async-http`. **`R14`** |
| `TRANSPORT-9` | MUST | The adaptation race: a native response delivered after the future settled is closed. Interacts with `R13` — the close must sit in an `ensure`, because `Async::Cancel` (alias `Async::Stop`) is not a `StandardError` |
| `TRANSPORT-12` | MUST | Drop **that header only**, on both paths, without letting the native exception escape. **Live antecedent**: `protocol-http1` raises `Protocol::HTTP1::BadHeader` on a name `HTTP-17` accepts (verified fact 5). The requirement says "on both sync and async paths"; its **sync half is vacuous on `dexpace-transport-net_http`** — it rejects no model-valid name and writes `Bad name: v` to the wire — and `8a`'s checklist carries that as a stated cross-reference rather than a silent absence |
| `TRANSPORT-13` | SHOULD | The three-mode drop-logging policy, case-insensitive and bounded. **This is where `DEF-41`/`OBS-19` is picked up**, because `8c` is the first adapter in the repository that drops rather than raises |
| `TRANSPORT-21` | MUST | A pre-dispatch failure delivered through the future, never thrown synchronously. Phase 2's normalisation (`ASYNC-2`, `PIPE-30`) is the shape |
| `TRANSPORT-23` | MUST | Never a null success. Falls out of `Settlement`'s "exactly one of response or error" (phase 2), and the row states that rather than re-implementing it |
| `ASYNC-6` | MUST | **Bidirectional** cancellation: stopping the `Async::Task` cancels the pivot, and cancelling the pivot reaches the task. This is the property `dexpace-transport-async_http` exists to prove (§2.1) |
| `ASYNC-21` | MUST | N/A — vacuous, §11.21, adapter-scoped with no reactive adapter shipping; the backpressure property is implemented anyway on 7b's pull path (`SSE-39`). **`7b` explicitly declined this row and named it phase 8's** |
| `ASYNC-22` | MUST | Concurrent async calls with all per-call state in the future's completion graph. The async twin of `TRANSPORT-29` |

`8c` additionally owns, without owning a new ID: `DEF-42`'s transport-milestone emitter call sites on this
adapter, once `R6` settles the route; `DEF-25`'s call site in this adapter; the
`rbs_collection.yaml` row for `async-http`; the second driver for every one of `8a`'s 23 conformance
assertions; and the `ASYNC-7` README section for a reactor-backed adapter.

---

## Exclusions — IDs a reader would expect here, and the phase that owns each

| Excluded | Owning phase |
|---|---|
| `SEAM-11`, `SEAM-12`, `SEAM-13` — the sync transport seam, concurrency safety, cooperative cancellation | 2, built as a duck-typed `#call(request, options, cancellation)`. `SEAM-12` is ⏳ `DEF-22` there precisely because "concurrency safety is a property of an implementation and this phase ships none"; phase 8 supplies the implementations and `dexpace-conformance` supplies the assertion |
| `SEAM-14`, `SEAM-15` — the close contract and the post-close send | 2, built. Phase 8's adapters are the **first owners** and therefore the first raise site for `Dexpace::ClosedError` (spec-forced boundary 17) |
| `SEAM-16`, `SEAM-17`, `SEAM-30` — the async seam, the pivot, the orphaned-response close | 2, built as `Dexpace::Async::Future`, `Completer` and `Dexpace::AsyncTransport`. §10.3 and roadmap obligation 5 forbid replacing any of them |
| `SEAM-18` — the two bridges and the required executor | 2, built as `Dexpace::Bridge::AsyncOver` and `SyncOver`. `8b` supplies the first executor the `async_over` direction has ever had |
| `SEAM-24` — cross-thread diagnostic propagation beyond fiber storage | `DEF-1`, riding on `DEF-11` (`dexpace-async-async`), post-v1. **`8b` satisfies its first sentence through `ASYNC-8` and `8c` its second through `ASYNC-6`** — see the sweep, which proposes saying so on the row |
| `SEAM-25` — the async adapter's idempotent, ownership-aware close | 2 for the release half; `DEF-31`'s event half closes in `8b` |
| `SEAM-29` — the construction contract | 1 and 2 |
| `PIPE-33`, `PIPE-34` — the two pipeline bridges | 4c. `8b` carries a `PIPE-33` **cross-reference** row and no budget line |
| `PIPE-26`, `PIPE-27` — a pipeline is a transport; closing it does not close the transport | 4c, built, and written into 4c's forward table for this phase |
| `PIPE-2`, `PIPE-37` — the stage order and `PRE_REDIRECT` | 4c. Phase 8 installs no step and adds no stage |
| `HTTP-17`, `HTTP-18`, `XCUT-18` — the header validators | 1, built as `Dexpace::HeaderSyntax`, public API "precisely so an adapter in another gem can call it". `DEF-25` is the call site and is picked up here |
| `HTTP-13` — case-insensitive header folding | 1. Relevant because `Net::HTTP` normalises name case on the wire (verified fact 14) and `async-http` does not; neither breaks `HTTP-13`, and the row stays phase 1's |
| `HTTP-36`–`HTTP-45`, `BODY-1`–`BODY-37` — the body model, `#source`, the close-in-`ensure` readers, `FileBody`'s `#path`/`#offset`/`#count` | 3a and 3b, built. Phase 8 consumes them and adds no second body type |
| `IO-1`–`IO-42` — the byte-stream contracts, `BufferedSource`, `MAX_MATERIALIZED_BYTES` | 3a, built. `IO-40` is the boundary that keeps timeouts out of them |
| `CTX-1`–`CTX-20`, `RECOV-1`–`RECOV-34` | 4a and 4b |
| `XCUT-4`'s branch (a), `XCUT-5`–`XCUT-9` | 4b built `Dexpace::ProtocolError` and `Dexpace.each_cause`; 5a built `Dexpace::Retryability.retryable_status?`; 6a discharged `DEF-40`. **Branch (b)'s type is phase 8's and is the phase-level task** |
| `CFG-1`–`CFG-38` | 5a. `CFG-15`'s clock and cancellable wait, `CFG-20`'s pivot reshaping (`OI-22`, still open) and `CFG-35`'s status classifier are all consumed, none re-decided |
| `OBS-1`–`OBS-40` | 5b and 5c. **`OBS-19` is the exception**: `DEF-41` targets phase 8 and is picked up in `8c` |
| `OBS-28`, `OBS-29` — the eleven-method `HTTPTracer` vocabulary and its ordering contract | 5c, built with no emitter. `DEF-42`'s **transport-milestone group** is phase 8's, subject to `R6`; the operation-lifecycle triple is `OI-32`'s and is nobody's in phase 8 |
| `RETRY-1`–`RETRY-45`, `REDIR-1`–`REDIR-28`, `AUTH-1`–`AUTH-38` | 6. Phase 8 disables the native equivalents and installs no step |
| `PAGE`, `SSE`, `SERDE` | 7. `SERDE-27`'s no-materialization clause names "any adapter phase 8 or later ships whose library has a pull parser" (`P7-1`), which none of phase 8's three is |
| `BODY-12` clause 2, `BODY-36` | `DEF-3`. Clause 2 targets phase 8 and is dispositioned in the sweep; `BODY-36` needs core's dependency budget to change and no v1 phase can meet it |
| `XCUT-11`, `XCUT-12`, `XCUT-13`, `XCUT-15`, `XCUT-19`–`XCUT-23` | 9 dispositions them. Phase 8 satisfies `XCUT-13` and `XCUT-22` by construction through §3.7 and adds no second rule |
| `NFR-1`–`NFR-17` | 0 built the machinery, 9 dispositions it. Phase 8 spends two third-party `NFR-2` budgets and asserts nothing about the gate |
| `docs/sdk-documentation/architecture.md` — "which gem to install, worked cross-gem examples" | A human, or a skill on request (`docs/README.md`). Phase 8 is the phase after which that question has five answers rather than two, and it is **not** a phase deliverable. Recorded so the absence is a decision |

---

## Gap IDs: zero, and what that does and does not license

`ruby scripts/knowledge.rb --gaps TRANSPORT,ASYNC`, run 2026-09-11, reports (the trailing summary line
elided, the rest verbatim, so re-running it and diffing this block is not mistaken for drift):

```
TRANSPORT — Transport adapter conformance contract
  30 canonical IDs: 30 substantive, 0 roll-up only, 0 uncited

ASYNC — Asynchronous runtime adapter contract
  22 canonical IDs: 22 substantive, 0 roll-up only, 0 uncited
```

The roadmap's design-document obligation — "budget the reading time in the phase's design document and
say so there" (`:154-155`) — is discharged by stating that the budget is **zero**, which this section is.
Phase 8 is the second build phase after phase 7 with a zero gap set, and the roadmap said so in advance:
"Every other prefix has full corpus coverage" (`:161`).

**What that does not license.** Three things, and the third is specific to this phase:

1. **`--gaps` measures corpus coverage, not specification coverage** (`OI-12` states the same asymmetry
   from the other side). Both chapters were read in full anyway, which is cheap at 51 and 46 lines.
2. **The `*Conformance:*` clauses appendix C drops are load-bearing here more than anywhere.** Nine of
   them prescribe a *test shape* no appendix-C row implies — `TRANSPORT-5`'s "two concurrent calls with
   different per-call timeouts", `TRANSPORT-13`'s "the same name warns once then goes quiet, a different
   name warns once", `TRANSPORT-25`'s "stream a multi-megabyte response and assert byte-exact
   round-trip", `ASYNC-4`'s "concurrency stress racing cancel-with-interrupt against completion on a
   small pool with a sentinel unrelated task", `ASYNC-5`'s "cancel the future in the window after the
   worker produces a Response but before delivery", `ASYNC-10`'s "assemble under context A,
   subscribe/execute under B → log lines carry B; re-subscribe under C → C". A sub-phase reading only
   appendix C writes none of them.
3. **Corpus coverage says nothing about whether a *design* sentence is true.** Verified fact 1 is a rule
   the corpus carries faithfully from a design chapter that is wrong about the library. `--gaps` cannot
   see that and neither can `--req`; only running Ruby can.

---

## Convergence points — what needs two sub-phases, and what does not

A convergence point is a **test or a mechanism that cannot be written until two segments exist**, or that
one segment writes and another extends. It is not a build-order dependency, and a plan that treats one as
one has re-imposed the chain the split existed to avoid. There are **four**, which is more than phase 7's
one and fewer than it looks, because three of the four are one-line extensions.

1. **The conformance suite driven by a second adapter.** `8a` writes `DEF-22`'s assertion objects and the
   `TCPServer` fixture; `8c` adds its adapter as a second driver of the same 21 assertable rows. This is
   the single reason `dexpace-conformance` is a published gem (§9.3) and it is the phase's headline
   convergence point. **The artifacts are assigned to `8a`**; if the sub-phases run out of order the one
   that lands first writes them and `8a` records that it consumed rather than wrote them. **Both designs
   must say which side they are on** (`R16`). Neither blocks on the other.
2. **The async transport built from `8a`'s and `8b`'s gems and neither's alone.**
   `Transport.async_over(net_http_transport, executor: thread_pool)` is where `ASYNC-1`, `ASYNC-2`,
   `ASYNC-5`, `ASYNC-14`, `ASYNC-19` and `ASYNC-20` first meet a **real socket** rather than
   `FakeTransport`, and where `PIPE-33`'s four met clauses are exercised end to end. Each of the six IDs
   is provable against `FakeTransport` inside `8b` alone; the composed test proves the composition and
   belongs to whichever of `8a` and `8b` lands second.
3. **The `ASYNC-7` cross-adapter contrast.** §3.3 fixes the answer — "the thread adapter lets an in-flight
   blocking read finish, the reactor-backed ones abort at the next scheduler checkpoint" — and it is a
   *contrast*, which only exists once two adapters have documented themselves. `8b` owns the ID; `8a` and
   `8c` each write their own README section; the assertion that the two differ as documented is a
   conformance row `8c` adds.
4. **`Dexpace::TransportError`'s consumers.** The type is the phase-level task below, **landed by `8a`'s
   Task 2** and *cited* rather than redefined by `8c`'s Task 4 (fixed 2026-09-12; this read "whoever
   lands first" and both plans then wrote it). `8a` and `8c` each raise it, and `8b` neither raises nor
   needs it. The convergence is that **one type serves two adapters in two gems**, which is `XCUT-4`'s
   "exactly two top-level branches" holding across a gem boundary.

**What is *not* a convergence point, stated because a plan will reach for each.**

- **`8b`'s pool is not a dependency of `8c`.** `async-http` runs on `Async::Task` (verified fact 3). A
  `8c` test that installs a `dexpace-async-thread` pool is testing `8b`'s gem.
- **The `TCPServer` fixture is not a dependency of `8b`.** Nothing in `dexpace-async-thread` opens a
  socket.
- **Phase 2's `FakeTransport` is not shared across the three sub-phases.** `DEF-29`'s move is `8a`'s
  disposition; until it lands, each sub-phase's suite uses what it needs, as phases 3a, 5b and 7a each
  did.
- **The two `rbs_collection.yaml` rows are not one edit.** `net-http`'s is `8a`'s and `async-http`'s is
  `8c`'s, and phase 0's file comment already anticipates both arriving separately.

---

## Phase-level tasks owned by no sub-phase

**Five, which is more than any earlier phase**, because phase 8 is the first phase whose sub-phases ship
gems that are none of them `dexpace-core`.

1. **`Dexpace::TransportError < ::IOError` in `dexpace-core`, with `XCUT-4` branch (b)'s
   default-retryable flag.** It is in a different gem from all three sub-phases' gems; it is consumed by
   `8a` and `8c`; and it closes `docs/first-release.md`'s standing phase-8 blocker and `6a`'s deviation
   `P6-4`. Verified fact 10 is why it cannot be skipped: `Net::ReadTimeout`, `Net::OpenTimeout`,
   `Net::WriteTimeout`, `SocketError`, `Errno::ECONNREFUSED` and `Async::TimeoutError` are **none of them
   `::IOError` descendants**, so a bare stdlib error escaping an adapter classifies as not-retryable
   through `RETRY-2`'s capability query.

   **Who lands it, fixed in place 2026-09-12.** This item read "whoever lands first writes it", and both
   `8a`'s plan (Task 2) and `8c`'s plan (Task 4) then wrote it, with two different shapes. **`8a`'s
   Task 2 lands it**, for two reasons that are not preference: `8a` is first in the recommended order,
   and `dexpace-conformance` — `8a`'s gem — asserts against the class in the assumption `R16` clause 12
   makes of every adapter ("every failure carrying no HTTP response answers `#retryable?`"), so the
   suite cannot be written against a class that does not exist. **`8c`'s Task 4 becomes a citation, not
   a second definition**: it requires the class `8a` landed, and lands it itself *only* if `8c` executes
   before `8a`, in which case it writes the identical shape below and `8a`'s Task 2 becomes the
   no-op confirmation its own preamble already describes.

   **The shape is `8a`'s, and it is a superset of `8c`'s.** `class TransportError < ::IOError; include
   Dexpace::Error; end`, with `#retryable?` returning `true` unconditionally (`XCUT-4` branch (b)'s
   "always", with no keyword that can override it), `initialize(message = <default>, phase: nil)`, and a
   `#phase` reader (`Symbol?`, one of `:connect`, `:write`, `:read`, `:close`) **for diagnostics only,
   never branched on by `RETRY-2`'s capability query**. `8c`'s definition was the same class without
   `#phase` and without a default message, and it needs nothing `8a`'s lacks: `8c` constructs it as
   `Dexpace::TransportError.new("…")` at every site in `Errors.wrap`, which the optional keyword leaves
   untouched. `8c`'s own three assertions — `< ::IOError`, `include Dexpace::Error`, `#retryable?`
   always true, plus `P3-3`'s sibling check against `Dexpace::StreamError` — all hold against `8a`'s
   shape, so `8c`'s Task 4 keeps them as the verification it performs rather than as a second test of a
   second class. The phase-level PR is where the one definition is reviewed as one thing.
2. **`dexpace-conformance`'s version bump and first release.** The roadmap's phase-8 row says phase 8 owns
   "its gemspec, its version and its first release"; phase 9 "adds the remaining suites, owning neither
   its gemspec nor its release". The gemspec and the suite are `8a`'s; the release is the phase's, and it
   lands with `docs/first-release.md`'s table.
3. **The phase-level pull request.** The roadmap's execution step 5: "a phase returns to `mvp` as **one
   phase-level pull request**, not one per sub-phase."
4. **The roadmap's phase-8 row link and the segmentation bullet's correction**, plus a dated entry in
   `## Phase Status Notes`. Written out verbatim under *Roadmap follow-through owed*.
5. **`CLAUDE.md`'s claims sentences.** Two are affected and they are affected at different moments, which
   matters:
   - **"There are eight phase directories under `docs/work/*/`" becomes nine the moment this file
     exists**, because filing it creates `docs/work/mvp/phase8/`. The probe's `claims` check reads that
     numeral, so it is mechanically caught; it is corrected by hand in the change that files this
     document, together with the `phase8/` entry in the enumeration and its sub-phase description.
   - **"Zero gems exist under `gems/` — the directory itself does not exist yet" remains true** until
     phase 0's scaffold actually lands, which is code and not documentation. Phase 8 changes nothing about
     it. Stated because a reader of the phase-8 row will assume otherwise.

**Two items are owed outside this document's own scope** and are recorded so they are not discovered
later:

- **The `knowledge-lookup` skill's audit-group table is owed two rows**, phase 7's *Serialization, SSE and
  pagination* (still not added) and phase 8's *Transport and async-runtime adapters*, whose exact content
  is given under *Corpus reading*. That is an edit to `.claude/skills/knowledge-lookup/SKILL.md` and not
  to a frozen tree, and the roadmap's first retrospective rule wants both in place before the first
  sub-phase runs the group.
- **`observability/65191069`'s single-interpreter caveat is phase 8's to clear.** The note says in its own
  words that it "must be re-run on 3.2.11 and 4.0.6 before anything rests on it", and `8b`'s
  `ASYNC-9`/`ASYNC-11` rest on it entirely.

### Shared transport contracts — stated once here, cited by `8a` and `8c`

**Added 2026-09-12.** Four things `dexpace-transport-net_http` and `dexpace-transport-async_http`
implement *the same way*, because a conformance assertion runs unchanged against both adapters (§9.3) and
two adapters that answered one requirement with two shapes would force the assertion to branch on which
adapter it is looking at — the one thing `R16` says the suite must never contain. Each sub-phase design
cites this subsection rather than restating it, and neither may re-decide it alone.

**1. The `TRANSPORT-11` managed-header drop set is ten folded names, identical on both adapters.**

```
host  content-length  transfer-encoding  connection  keep-alive  proxy-connection  te  trailer
upgrade  expect
```

The first three are the requirement's own named minimum. The other seven are taken under the
requirement's own invitation ("plus any the native client rejects outright … The exact drop set is
transport-specific"), and the extension is *more* load-bearing on `8c` than on `8a`: `Net::HTTP`
**recomputes** a caller-set framing header while `async-http` **appends** it, so on the async adapter a
caller-set `Content-Length`, `Host` or `Transfer-Encoding` produces the canonical Host-duplication and
CL.CL / TE.CL request-smuggling shapes on the wire (`8c`'s verified fact 5). `expect` carries its own
reason on `8a` (`Net::HTTP#continue_timeout` is `nil`, so `wait_for_continue` never runs and a caller-set
`Expect: 100-continue` hangs until the read deadline) and the generic one on `8c` (the
`100-continue` handshake is the body layer's to negotiate). **`trailer` is in the set on both** — an
earlier revision of `8c` listed nine names and omitted it: neither adapter supports caller-supplied
trailers, so a caller-set `Trailer` announces fields that will never be sent, which is a false statement
about a framing the transport chose. **`proxy-authorization` is in neither set** — `8a` configures no
proxy and holds no credential, so a caller-set value belongs to a proxying layer the SDK cannot see and
is passed through like any other header; `TRANSPORT-30`'s embedded MUST is about credentials *the SDK
holds*, of which there are none. The constant is named per gem (`NetHTTP::MANAGED_HEADERS`,
`AsyncHTTP::RequestMapper::FRAMING_HEADERS`) because `NFR-2` forbids either gem from depending on the
other; **the membership, not the name, is what is shared**, and each gem's suite asserts the list
verbatim so a divergence is a red test rather than a drift.

**2. A drop is logged through one event name and one field pair, on both adapters.**
`Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED = "http.transport.header_dropped"` — one new
frozen `String` in `dexpace-core`, added by whichever sub-phase lands first and a no-op confirmation for
the other, in the shape `Events`' existing `INSTRUMENTATION_CLOSE`/`_HOOK`/`_CONFIG`/`_LOG` rows already
use. The emission is `Dexpace::Instrumentation.contain(logger, event:
Events::TRANSPORT_HEADER_DROPPED) { logger.event(Severity::VERBOSE).event(
Events::TRANSPORT_HEADER_DROPPED).field("header", name).field("reason", why).emit }` — **`String` field
keys, matching 5b's own call sites**, and a `"reason"` field on both, so one assertion can read a drop
record from either adapter. An earlier revision of `8a` emitted a bare literal event name
(`"transport.header.dropped"`), contained under `INSTRUMENTATION_LOG`, with a `Symbol` `:header` key and
no reason; it is corrected to the above. `TRANSPORT-11`'s "SHOULD additionally log each drop at verbose"
is discharged at `Severity::VERBOSE` on both.

**3. The `TRANSPORT-13` three-mode drop policy and its bound of 64 are `8c`-only, and that is the
correct asymmetry.** `TRANSPORT-13`'s antecedent is a native wire grammar stricter than the SDK model's;
`Net::HTTP` has none — it writes `Bad name: v` to the wire rather than rejecting it — so the ID is
vacuous on `8a` and `8a` ships no policy object (`8a`'s row is a stated cross-reference). The bound is
the requirement's own clause ("MUST be bounded so an attacker synthesising unbounded distinct names
cannot grow it without limit") answered with a number, **64 distinct folded names per adapter instance**,
after which the policy degrades to its quiet mode. A `TRANSPORT-11` **framing** drop is *always* verbose
on both adapters and never goes through the policy: three modes over a set the caller controls would let
an attacker suppress a `WARNING` by exhausting the per-name bound. The two rules stay disjoint, which is
spec-forced boundary 11 applied one level down.

**4. One configuration key names the per-call timeout, on both adapters.**
`Dexpace::Configuration::Keys::REQUEST_TIMEOUT` (`8a`'s `R3`), read with
`Dexpace.configuration.duration(…)` — 5a ships no `#float`, and `#duration`'s grammar treats a bare
number as **milliseconds** (`CFG-7`), which both adapters document at the adapter. An earlier revision of
`8c`'s plan declared a second spelling, `TRANSPORT_REQUEST_TIMEOUT_SECONDS`; it is corrected to the
shared key, because one caller setting must govern both transports and `8c`'s own design already said so
("`8c` reads the same key rather than declaring a second spelling"). `8c`'s
`Keys::TRANSPORT_CONNECTION_LIMIT` is genuinely `8c`-only — `Net::HTTP` is constructed per call and has
no pool to bound — and is named so `8a` knows the name is taken and the concept it names.

### The CI matrix after `8c`'s per-gem Ruby floor

**Added 2026-09-12,** because three plans touch the same six files if each does this independently.
`dexpace-transport-async_http` declares `required_ruby_version >= 3.3` (`P8-36`, `OI-38`) and every other
gem keeps the repository floor of 3.2. **`8c`'s plan Task 3 makes the edit, in `8c`'s own PR**, against
this document's earlier recommendation that it be phase-level: without it `bundle install` on the 3.2 row
fails for the **whole workspace** the moment `8c`'s gemspec exists, because phase 0's root `Gemfile` adds
every `gems/*` directory unconditionally and Bundler checks `required_ruby_version` for a path gem at
install time. That makes the edit a prerequisite of `8c` building at all, which is not something a
phase-level PR can be waited on for.

The end state, which `8a` and `8b` align to rather than re-derive:

| File | After `8c` Task 3 |
|---|---|
| `VERSIONS` | one added line, `ruby floor:dexpace-transport-async_http  3.3`, beside the global `ruby floor  3.2`. `ruby matrix` still reads `3.2 3.3 3.4 4.0` |
| `tools/versions.rb` | `ruby_floor` gains two optional positionals, `ruby_floor(gem_name = nil, path = PATH)`; every existing zero-argument call site is unaffected |
| `tools/versions_gate.rb` | `gem_violations` reads the per-gem floor when one exists, else the global one |
| `Gemfile` | the `gems/*` glob skips a gem whose per-gem floor this interpreter does not meet |
| `tasks/quality.rake` | `test:gems` rejects an excluded gem's test files |
| `tasks/gates.rake` | `gates:clean_bundle` rejects an excluded gem from `targets` |
| `.github/workflows/ci.yml` | **unchanged.** Four rows, every job on every row, every gate in some job; `ci_workflow_test.rb`'s "every listed gate appears in some job" is unaffected, because the exclusion is per-**gem** and lives inside the Ruby-side tasks |
| Effect on the 3.2 row | exactly one gem is absent from `bundle install`, `test:gems` and `gates:clean_bundle`. `gates:gemspec_audit` and `gates:require_allowlist` need no exclusion — both only load a gemspec and read text — and are left alone |

**`8a` and `8b` do not touch any of those files**, and both run their gates on **three interpreters**
(3.2.11, 3.4.10, 4.0.6) exactly as their plans' Task 1 and Task 12 already describe: every gem `8a` and
`8b` ship keeps the 3.2 floor, so the matrix `8c` leaves behind changes nothing for either. **If `8a` or
`8b` executes after `8c`, their gate runs must tolerate the edited `VERSIONS`**, which they do without
any change: `ruby_floor`'s new positionals are optional, the `floor:<gem>` row is colon-joined into
`VERSIONS`' existing three-token `name` column so `.records` and every existing `.value` call site parse
it unchanged, and `gates:versions` continues to assert `>= 3.2` for each of their gems against the global
row. **If `8a` or `8b` executes before `8c` and the edit is not yet in place, nothing of theirs fails**,
because the collision exists only once `8c`'s gemspec declares `>= 3.3`. The one thing `8a` and `8b`
must not do is land a *second* version of the edit: whichever sub-phase runs first after `8c` finds the
table above already true and verifies rather than diffs.

---

## Prerequisites, and the decisions phase 8 inherits

**Phases 0 through 7, in full.** Phase 8 is the last build phase and inherits more than any other. What
it must read before writing a line, grouped by what it consumes:

**Phase 0 — the workspace phase 8 builds inside, on paper.** All four of phase 8's gems already have a
skeleton: a gemspec declaring `dexpace-core` **and nothing else** (deviation `P0-9` — "the third-party
half of each budget arrives with the code that needs it … `net-http` and `async-http` in phase 8"), an
entry file defining the namespace and `VERSION`, a `sig/` mirror, a `test/` tree and a named Steep target.
`rbs_collection.yaml` has an **empty `gems:` list** and phase 0's own comment says "net-http and
async-http with the transports in phase 8, and each adds its own row here then". `gates:gemspec_audit`,
the require-allowlist audit with its **denylist** (`json`, `net/http`, `socket`, `timeout` — `P0-5`), and
the clean-bundle isolation run are all standing. `DEF-22` and `DEF-23` were filed by phase 0 against this
phase.

**Phase 1 — `Dexpace::HeaderSyntax` as public API, built for this phase.** "A module of pure functions, and
**the public entry point every transport adapter calls again immediately before dispatch** (phase 8,
`DEF-25`) … It is public API in the full sense — YARD, RBS, surface manifest — precisely because a
phase-8 adapter is a different gem and must be able to reach it." Also `Dexpace::Request`
(`:method, :url, :headers, :body`), `Response`, `Headers`, `Query`, `RequestOptions`
(`:timeout, :max_retries, :tags`), `MediaType`, `Status`, and the module-not-class error root that makes
`Dexpace::TransportError < ::IOError` reachable at all.

**Phase 2 — every seam phase 8 registers into.** `Dexpace::Transport` / `AsyncTransport` and their
`.conforms?` predicates; `Dexpace::Async::Future` / `Completer` with `#on_settle`, `#cancel` and
`Completer#on_cancel`; `Dexpace::Cancellation` with its typed `#reason`, `.any` and `#on_cancel`;
`Dexpace::Closeable`; `Dexpace.close_quietly`; `Dexpace::Hooks.notify`; `Dexpace::Registry#register` with
its required skew keyword; `Dexpace::ClosedError`; the executor duck type `#post { … }`
(`concurrency-and-async/08a0e08d`), for which **`8b` supplies the first implementation**; and both
`SEAM-18` bridges. Phase 2 also states phase 8's obligation in its own words: "Phase 2's obligation is to
make the cooperative contract *stateable and testable* … not to close the gap, and it does not claim to."

**Phase 3a/3b — the byte layer every adapter's body crosses.** `BufferedSource.over(body)` and
`.wrapping(io)`; `MAX_MATERIALIZED_BYTES`; `Dexpace::StreamError < ::IOError` as a **sibling** of
`Dexpace::TransportError` and never a subclass (`P3-3`); `Dexpace::EndOfStreamError < ::EOFError`, without
which "every streaming upload phase 8 performs would fail"; `Dexpace::Body` with `#source` and a default
no-op `#close` (`OI-10`'s resolution); `Dexpace::FileBody` exposing `#path`, `#offset` and `#count` and
deliberately **not** `#to_path` (`P3-17`); `Body.buffer_bounded`. Two open items phase 8 inherits
unresolved: **`OI-9`** — `BufferedSource.wrapping` delivers one byte per read, "and it will reach every
transport phase 8 writes, since `BufferedSource.wrapping` is how a response body is built" — and
**`OI-7`**, the decode recipe.

**Phase 4b/4c — the error taxonomy and the runtime a transport sits under.** `Dexpace::ProtocolError` flat
beside where `Dexpace::TransportError` lands ("Putting either inside `Recovery` would make phase 8's
branch and phase 4's branch of one taxonomy live in two different namespaces"); `Dexpace.each_cause`;
`Dexpace::Suppressible` and `attach_suppressed`; `Stages`, `Cursor`, `Pipeline` / `AsyncPipeline`,
`PIPE-26`/`PIPE-27`. **`OI-18` is open and its repair is named as phase 8's or a phase-2 amendment's**:
`Transport.async_over` accepts an *async* transport silently and yields a future of a future.

**Phase 5a/5b/5c — configuration and observability, consumed and not re-decided.** `Dexpace::Clock` and
the cancellable queue wait; `Dexpace::Async.delay`, which **raises `Dexpace::SeamError` with no
`Fiber.scheduler`** (`P5-9`); the `deadline:` keyword on `Future#value`/`#wait` (`DEF-28`, closed);
`Dexpace::Retryability.retryable_status?`; `Configuration::Keys`; `Instrumentation::Severity`,
`Event`/`Event::INERT`, the duck-typed sink, `Instrumentation.contain`, the once-per-key latch,
`Events::INSTRUMENTATION_SHUTDOWN`; `Diagnostics.capture` / `.with`; `HTTPTracer`'s eleven methods with the
five transport ones' argument lists **fixed by 5c** — host and port on `#connection_acquired`, byte counts
on `#request_sent` and `#response_received`, status and headers on `#response_headers_received`.

**Phase 6a — the classifier phase 8 must feed.** `P6-4`'s stated blind spot and the obligation it puts on
this phase, quoted because it is the sharpest hand-off in the register: "**every transport adapter MUST
wrap a bare stdlib I/O or timeout error it lets escape in something answering `#retryable?`** … the
obligation phase 8 inherits is 'wrap, and default to retryable,' not 'wrap, and get the classification
right by hand'."

**Phase 7 — two obligations phase 8 inherits, and one thing it must not pre-empt.** `7b`'s design states
the whole integration from the other side: "A transport hands back a `Dexpace::Response`;
`Dexpace::SSE::Stream.open(response)` is the whole integration. `7b` requires nothing of a transport
beyond `Response#body` answering `#source`, which is 3b's contract." `7a` leaves `DEF-22`'s
callable-plus-`Failure` shape alone for this phase deliberately.

**Two things `7c` hands forward, and each is a row rather than a note.** First, **`PAGE-36`'s
per-call-options conformance test**: "phase 8's transport conformance suite must include a
per-call-options test that drives the same transport twice with different `RequestOptions` and asserts
both are honoured, before release"
(`docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md:1436`, citing `PAGE-36`, `HTTP-34`,
`HTTP-35`, `TRANSPORT-1`). That is **`8a`'s**, it lands in `dexpace-conformance`, and it is **not**
`TRANSPORT-5`'s clause — `TRANSPORT-5` asks for two *concurrent* calls with different timeouts, and this
asks for the same transport driven *twice in sequence* with different options, which is the failure
`PAGE-36` exists for ("otherwise a caller's timeout/retry policy silently fails to govern pages 2..N").
Second, **`Dexpace::Page::_Executor`** — "the one-method `#post { }` duck type `PAGE-29`'s executor mode
takes. The first real implementation is phase 8's; `7c` ships only a test double, and core spawns no
thread" (`…phase7c…-pagination-design.md:1320`). That is **`8b`'s**: its pool must satisfy a core-declared
RBS interface it did not write, which is an `NFR-3`/`NFR-11` surface it inherits rather than designs.
`7c` also fixes one division `8a` and `8c` must honour rather than re-decide: "a response the transport
never delivered because a cancel won the race is **the transport's** to release" (`PAGE-33`).

---

## Cross-cutting constraints that bite phase 8 specifically

Cited from `CLAUDE.md` and design §3, §4, §7 and §8.3, never copied — this section names only which of
them phase 8 meets and where.

- **The forbidden three.** `Timeout.timeout`, `Thread#raise` and `Thread#kill`. Phase 8 is the phase where
  a reader is most tempted: a blocked `Net::HTTP` read on a pooled worker is exactly the case
  `Thread#raise` looks designed for. §10.5 records the trade and `DEF-18` carries the cost; verified fact
  11 gives the sanctioned alternative.
- **`Fiber#kill` is not one of the forbidden three, and the distinction is the rationale rather than the
  list.** Phase 0's `Dexpace/NoThreadInterrupt` cop bans `Timeout.timeout`, `Thread#raise`, `Thread#kill`,
  `Thread#terminate` and `Thread#exit`
  (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:526`); **`Fiber#kill` is
  absent from it**. §8.3's reason for the ban is that an *asynchronous* interrupt "can land on **any**
  bytecode instruction, including inside an `ensure` block that is releasing a pooled connection", whereas
  `Fiber#kill` raises at the fiber's own suspension point and runs its `ensure` — verified on 3.4.10
  (fact 2), a deterministic location the rationale does not obviously reach. **`R1` may therefore consider
  it, and `8a` must make that argument in its own design rather than treat the cop's silence as
  permission** — and must settle the 3.2 availability this document leaves unverified.
- **`Thread::Mutex` is per-fiber and non-reentrant.** It binds `8b`'s pool hardest — a lock held across a
  queue pop deadlocks two fibers of one thread — and `8a`'s and `8c`'s close latches, which hold it across
  the flag flip only.
- **An abandoned `Enumerator` never runs its `ensure`.** Phase 8 meets the general form of this rule with
  a whole socket behind it: verified fact 2 shows an abandoned `Fiber` holding a `Net::HTTP` block open
  leaks the connection with no finaliser. §7.1's rule — the engine owns the resource in its own scope and
  exposes `#close` — is `R1`'s constraint, not its solution.
- **`Fiber[:key]`, never `Thread.current[:key]`.** Verified fact 13 measures both: a new `Thread` sees
  `Fiber[:k]` and does not see `Thread.current[:tk]`. `8b`'s `ASYNC-8`–`ASYNC-12` rest on it entirely.
- **Bytes on the wire are BINARY.** Verified on both adapters (facts 2 and 3).
- **`URI::RFC3986_PARSER` pinned.** Every adapter converts a `Dexpace::URL` into a native endpoint.
- **The bundled-gem rule.** It does not reach the adapters — they may declare — but it reaches the
  **phase-level task**, which lands `Dexpace::TransportError` in `dexpace-core` and therefore may not
  `require` `socket`, `timeout` or `net/http` to name a class. Phase 0's denylist names all three, and
  `DEF-40` already argued the consequence in full.
- **`Ractor` is never load-bearing**; **regexp timeouts are per-pattern**, which reaches `8a`'s and `8c`'s
  header and status-line parsing if either writes a regexp over attacker-supplied bytes.
- **SPDX header and `# frozen_string_literal: true` on every file** (`NFR-13`). Worth naming here because
  `8a` writes files into a gem — `dexpace-conformance` — whose content is assertions rather than domain
  code, and the cop does not care.

---

## Verified Ruby facts that shaped this cut

All verified on **3.4.10** (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`), the
only interpreter available to this document, against **`net-http` 0.6.0** (a default gem) and, for the
async facts, against **`async-http` 0.104.0**, **`async` 2.45.1**, **`protocol-http` 0.71.0**,
**`protocol-http1` 0.41.0**, **`protocol-http2` 0.28.0**, **`io-event` 1.22.0** and **`async-pool` 0.12.0**,
installed into a scratchpad directory with `gem install async-http --install-dir <scratchpad>` and run
under `GEM_HOME`/`GEM_PATH` pointing at it. Nothing was installed into the project or left in the user's
gem directory. **Where a fact needs the 3.2 floor or the 4.0 column to be load-bearing, that is said
rather than assumed**; the sub-phase designs run the three-interpreter check this document could not.

1. **`Net::HTTP` has a built-in automatic retry, it is ON by default, and design §3.2, §11.18 and §12 all
   say it does not.** `Net::HTTP.new("example.com").max_retries` is **`1`**. `Net::HTTP#transport_request`
   rescues `Net::ReadTimeout`, `IOError`, `EOFError`, `Errno::ECONNRESET`, `Errno::ECONNABORTED`,
   `Errno::EPIPE`, `Errno::ETIMEDOUT`, `OpenSSL::SSL::SSLError` and `Timeout::Error`, and retries when
   `count < max_retries && IDEMPOTENT_METHODS_.include?(req.method)`, where
   `IDEMPOTENT_METHODS_` is `["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]` — **including PUT and
   DELETE, both of which carry bodies**. The retry re-runs `req.exec`, so it re-writes the body.
   Design §3.2 says "The reference transport disables nothing for **TRANSPORT-1**/**TRANSPORT-2** because
   `Net::HTTP` follows no redirects and retries nothing on its own — those two requirements are vacuous
   for this adapter"; §11.18 says "`Net::HTTP` has no resend hook"; §12's `TRANSPORT` row and the
   MUST-level summary both list `TRANSPORT-2` and `TRANSPORT-18` among the eight vacuous MUSTs.
   **The redirect half is right** — `Net::HTTP` exposes no follow-redirects method at all
   (`(Net::HTTP.instance_methods + Net::HTTP.methods).grep(/redirect/i)` is `[]`). **The retry half is
   wrong**, and with it `TRANSPORT-2`, `TRANSPORT-17` and `TRANSPORT-18`'s dispositions. `8a` sets
   `max_retries = 0` and the three become true; it is one line and three requirements. Filed as `OI-34`.
   *Commands:* `ruby -e 'require "net/http"; p Net::HTTP.new("x").max_retries'`;
   `sed -n '2401,2446p' /usr/lib/ruby/3.4.0/net/http.rb`;
   `ruby -e 'require "net/http"; p Net::HTTP.const_get(:IDEMPOTENT_METHODS_)'`.

2. **`Net::HTTP` cannot deliver a lazily-read response body across the return of `#call`, and the only
   mechanisms that can leak a socket or need a method the floor may not have.** Against a local
   `TCPServer` that writes five body bytes, sleeps 400 ms, then writes five more:
   `Net::HTTP.start { |c| c.request(get) }` **returned after 401 ms with `res.body == "aaaaabbbbb"`** —
   the whole body buffered before `#request` returned, which is `SEAM-11`'s "MUST NOT pre-buffer the body"
   and `TRANSPORT-25` both violated. The block form is no better if the block does not read: `reading_body`
   ends with `self.body`, so after the block `res2.body` was already `"aaaaabbbbb"` and a later
   `res2.read_body` raised `IOError: Net::HTTPOK#read_body called twice`. A **`Fiber` holding the block
   open works**: `Fiber.yield(chunk)` inside `read_body` delivered chunk 1 at 1 ms and chunk 2 at 401 ms
   to a consumer outside the request entirely. But **abandoning that fiber never runs its `ensure`** —
   with the fiber dropped and `GC.start` called, the `ensure` had not run, so the connection leaks; and
   while **`Fiber#kill` exists on 3.4.10 and does run the `ensure`**, terminating at the fiber's own
   `Fiber.yield` point rather than at an arbitrary instruction, **its availability on the 3.2 floor is
   unverified here** — only 3.4.10 is installed, and this document asserts nothing about 3.2 either way.
   Chunks from `read_body` are `ASCII-8BIT` and unfrozen. **Design §3.2 states this construction satisfies
   `SEAM-11` and `TRANSPORT-25` "literally"**
   (`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:167-171`); measured, it does not, which is
   why `R1` is a deviation-or-erratum decision and not only an implementation choice, and why `OI-35` is
   filed. This is `R1`, and it is the single hardest decision in the phase.
   *Command:* `ruby scratchpad/wire4.rb` (a `TCPServer` dribble fixture; the five probes above).

3. **`async-http` solves the same problem natively, with no pump.** Against the same dribble fixture,
   `Async::HTTP::Client.new(endpoint, retries: 0).get("/")` **returned the response object after 1 ms**
   with `status == 200`, and `response.body.read` yielded `"aaaaa"` at 1 ms and `"bbbbb"` at 401 ms — both
   `ASCII-8BIT` and unfrozen. `Protocol::HTTP::Body::Readable`'s surface is `#read`, `#each`, `#close`,
   `#discard`, `#length`, `#stream?`, `#rewindable?`, `#buffered`, `#join` — a pull contract that maps
   onto `BufferedSource.over` directly. `Content-Length` does **not** appear in
   `response.headers.fields`; the length is `response.body.length`. That asymmetry with fact 2 is the
   strongest single argument for `8c` being its own segment.
   *Command:* `ruby scratchpad/async1.rb` under the scratchpad `GEM_HOME`.

4. **`Net::HTTP` recomputes `Content-Length`, honours a caller-set `Host`, and auto-stamps four headers.**
   A POST with `Content-Length: 9999`, `Host: bogus.example`, `X-Pass: kept` and a 3-byte body reached the
   wire as `Content-Length: 3` (recomputed), **`Host: bogus.example` (honoured verbatim)**, `X-Pass: kept`
   (preserved), plus three headers the caller never set — `Accept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3`,
   `Accept: */*`, `User-Agent: Ruby` — and a fourth, `Content-Type: application/x-www-form-urlencoded`,
   stamped by `supply_default_content_type` because a body was present and no type was set. So
   `TRANSPORT-11`'s drop set must include `Host`, which the requirement names, and `TRANSPORT-10`'s
   authority clause has to survive a default the native client supplies rather than derives. The gzip
   stamp has a second consequence: `Net::HTTP`'s `decode_content` defaults to `true`, and a gzip response
   came back with the body **already decompressed**, `Content-Encoding` **removed** and `Content-Length`
   **rewritten to the decoded length** (11 for `"hello world"`). `R2` and `R3`.
   *Commands:* `ruby scratchpad/wire.rb`, `ruby scratchpad/wire2.rb`.

5. **A header name the SDK model accepts is rejected by `protocol-http1` and written to the wire by
   `Net::HTTP` — so `TRANSPORT-12`'s antecedent is live on one adapter and absent on the other.**
   `HTTP-17` rejects only a blank name, a C0/DEL control byte and a byte ≥ 0x80; **`"Bad Name"` passes**
   (0x20 is none of those). `Protocol::HTTP1::VALID_FIELD_NAME` is the RFC 7230 token set
   (`/[!#$%&'*+\-\.\^_`|~0-9a-zA-Z]+/`) and **`"Bad Name"` fails it**, so `Protocol::HTTP1::Connection#write_headers`
   raises `Protocol::HTTP1::BadHeader < Protocol::HTTP1::BadRequest < Protocol::HTTP::BadRequest <
   Protocol::HTTP1::Error < Protocol::HTTP::Error < StandardError`. `Net::HTTP` accepts it and wrote
   `Bad name: v` onto the wire — an invalid HTTP/1.1 field name, with the case mangled. Separately,
   `Protocol::HTTP::Headers#add` performs **no validation at all**: `"Bad Name"` and a value containing
   `"\r\nEvil: 1"` both landed in `#fields` verbatim, so `DEF-25`'s wire-boundary re-validation is the only
   thing standing between a forged model and an injected header on the async path. `Net::HTTP`'s own
   `#[]=` does reject a CRLF value (`ArgumentError: header field value cannot include CR/LF`). Outbound
   *values* are the other way round: `HTTP-18` permits only HTAB plus 0x20–0x7E, while
   `VALID_FIELD_VALUE` is `/[^\0\r\n]+/` — strictly wider — so no value needs dropping.
   *Commands:* `ruby scratchpad/wire.rb`;
   `ruby -e 'require "protocol/http1"; p Protocol::HTTP1::VALID_FIELD_NAME.match?("Bad Name")'`.

6. **`Net::HTTP` is lenient about inbound headers in exactly the places `TRANSPORT-14` requires a drop.**
   An obs-text byte in a value (`X-Obs: caf\xE9`) came back as `"caf\xE9"` tagged `ASCII-8BIT` —
   `TRANSPORT-14`'s SHOULD satisfied by the library. A **control byte** in a value (`a\x01b`) came back
   intact, and a **non-ASCII byte in a name** (`X-B\xE9d`) came back as the key `"x-b\xE9d"` with the body
   still readable. Both must be dropped by the adapter, and dropped *before* the values reach
   `Dexpace::Headers::Builder`, which `XCUT-18` makes reject them — otherwise a single malformed inbound
   header fails the whole response, which is the failure `TRANSPORT-14` exists to prevent.
   *Command:* `ruby scratchpad/wire2.rb`.

7. **`dexpace-transport-async_http` declares one third-party dependency, which installs fifteen gems,
   one of them a native extension.**
   `gem install async-http` resolved to `async-http 0.104.0` plus `async 2.45.1`, `async-pool 0.12.0`,
   `console 1.37.0`, `fiber-annotation 0.2.0`, `fiber-local 1.1.0`, `fiber-storage 1.0.1`,
   `io-endpoint 0.18.0`, **`io-event 1.22.0` (native extension)**, `io-stream 0.14.0`,
   `protocol-hpack 1.5.1`, `protocol-http 0.71.0`, `protocol-http1 0.41.0`, `protocol-http2 0.28.0`,
   `protocol-url 0.19.0` — **15 gems**. (Installed into an isolated directory with no default gems visible
   it also pulled `openssl 4.0.2` and `json 3.0.2`, both of which are default gems in a normal bundle.)
   `NFR-2`'s budget and phase 0's `gates:gemspec_audit` count **declared** dependencies, of which
   `dexpace-transport-async_http` has exactly one. `R15`.
   *Command:* `gem install async-http --install-dir <scratchpad> --no-document --no-user-install`.

8. **`async-http` has a built-in retry too, `Async::Task#stop` is real cancellation, and
   `task.with_timeout` raises a `StandardError`.** `Async::HTTP::DEFAULT_RETRIES` is **`3`** and
   `Async::HTTP::Client#call` is documented "with automatic retries for idempotent requests", looping on
   `attempt` and rescuing `Protocol::HTTP::RefusedError` — so `TRANSPORT-2` is load-bearing on this
   adapter as well and the client is constructed `retries: 0`. `Async::HTTP::Middleware::LocationRedirector`
   exists but is an opt-in wrapper that `Async::HTTP::Internet` does not install, so `TRANSPORT-1`'s
   "default MUST be off" is satisfied by not wrapping. `Async::Task#stop` from outside **ran the task's
   `ensure` block** and left `task.status == :cancelled`. `task.with_timeout(0.1)` raised
   `Async::TimeoutError: execution expired`, whose ancestry is `[Async::TimeoutError, StandardError,
   Exception]`.
   *Commands:* `ruby -e 'require "async/http"; p Async::HTTP::DEFAULT_RETRIES'`; `ruby scratchpad/async1.rb`.

9. **A cancelled `Async` task raises an `Exception` that is not a `StandardError`, and `Async::Stop` is a
   deprecated alias rather than a subclass.** `Async::Stop` **is** `Async::Cancel` — `async` 2.45.1's
   `lib/async/stop.rb` is `module Async; Stop = Cancel; end`, and `lib/async/cancel.rb:8` declares
   `class Cancel < Exception`. So `Async::Stop.equal?(Async::Cancel)` is `true`,
   `Async::Cancel.ancestors.take(3)` is `[Async::Cancel, Exception, Object]`, and
   `Async::Cancel.superclass` is `Exception` — **not a `StandardError`**. Two consequences for `8c`.
   §3.7 makes `Dexpace.close_quietly` rescue `StandardError` from `#close`, and §3.3's
   check-after-resume rule says the producer "MUST close any response it holds and settle through the
   failure channel" — a `rescue` clause written the obvious way will not run when a task is cancelled,
   so the close has to sit in an `ensure`. And because the two names are one class, `rescue Async::Cancel`
   and `rescue Async::Stop` catch **the same thing**; an adapter that writes both has written one.
   `R13`, and filed as `OI-37`.
   *Command:* `ruby -e 'require "async"; p Async::Stop.equal?(Async::Cancel); p Async::Cancel.ancestors.take(3)'`
   → `true`, `[Async::Cancel, Exception, Object]`.

10. **None of the errors a transport must classify is an `::IOError`.** Ancestries measured:
    `Net::OpenTimeout`, `Net::ReadTimeout` and `Net::WriteTimeout` are each
    `[…, Timeout::Error, RuntimeError, StandardError, Exception]`; `SocketError` is
    `[SocketError, StandardError, Exception]`; `Errno::ECONNREFUSED` is
    `[Errno::ECONNREFUSED, SystemCallError, StandardError, Exception]`; `Async::TimeoutError` is
    `[Async::TimeoutError, StandardError, Exception]`; `Protocol::HTTP1::Error` is
    `[Protocol::HTTP1::Error, Protocol::HTTP::Error, StandardError, Exception]`. `XCUT-4` branch (b)
    requires the transport error to "belong to the runtime's I/O-error family", and phase 3a's
    `Dexpace::StreamError` **is** an `::IOError` while none of these is. Live confirmations: a 0.2 s read
    timeout against a slow server raised `Net::ReadTimeout`, and a connect to a dead port raised
    `Errno::ECONNREFUSED`. This is why the phase-level task exists and why
    `docs/first-release.md`'s phase-8 blocker is worded as it is.
    *Command:* `ruby scratchpad/wire3.rb`.

11. **Closing a socket from another thread wakes a blocked read with `IOError` — the only sanctioned
    abort, and it collides with fact 1.** A thread blocked in `sock.readpartial(10)` woke with
    **`IOError`** when a second thread called `sock.close`. That is the mechanism §10.5 names —
    "`Completer#on_cancel` lets an adapter shorten that by closing the socket under the read" — now
    measured. **But `IOError` is on `Net::HTTP`'s own retry rescue list** (fact 1), so with `max_retries`
    left at its default a cancel-by-socket-close on an idempotent request would be swallowed and retried
    by the library. `max_retries = 0` is therefore required by `TRANSPORT-2`, `TRANSPORT-17` and
    `TRANSPORT-3` independently.
    *Command:* `ruby scratchpad/thr.rb`.

12. **A malformed `Content-Length` fails the whole response; an absent one does not.** A response with
    `Content-Length: abc` raised `Net::HTTPHeaderSyntaxError: wrong Content-Length format` out of
    `#request` itself, so the response never materialises and the adapter has nothing to downgrade. An
    **absent** `Content-Length` with connection-close framing gave `res.content_length == nil` and a
    readable body. A malformed `Content-Type` (`not a/;;media type`) passes through untouched and the body
    reads, so that half of `TRANSPORT-27` is free. Half of a SHOULD is unreachable on this adapter and
    `8a` must say which half and why. `R4`.
    *Commands:* `ruby scratchpad/wire2.rb`, `ruby scratchpad/wire3.rb`.

13. **`Fiber[]` is inherited by a new `Thread` and `Thread.current[]` is not; `Fiber#storage=` warns twice
    for two calls; the queue primitives behave as `8b` needs.** With `Fiber[:k] = "outer"` set,
    `Thread.new { Fiber[:k] }.value` was `"outer"`; with `Thread.current[:tk] = "tl"` set,
    `Thread.new { Thread.current[:tk] }.value` was **`nil`**. A child thread rebinding `Fiber[:cow]` left
    the parent's slot unchanged. Two `Fiber.current.storage =` calls produced **two** warnings, category
    `:experimental`, at the default warning level (re-verifying `OI-13` on 3.4.10), and
    `Fiber.current.storage = nil` read back as `nil` here. `Thread::SizedQueue.new(2)` blocked a third push
    (`status == "sleep"`) and released it on a pop; `Thread::Queue#close` woke a blocked `#pop` with
    `nil`; `Thread::SizedQueue#close` raised `ClosedQueueError` in a blocked push; `Thread#join(0.1)`
    returned `nil` rather than blocking. Every one of those is a clause of `ASYNC-12`, `ASYNC-9`,
    `ASYNC-11`, `ASYNC-2`, `ASYNC-16` or `XCUT-13`.
    *Command:* `ruby scratchpad/thr.rb`.

14. **The two adapters disagree about header-name case on the wire, and neither breaks `HTTP-13`.**
    `Net::HTTP` normalises: `x-lower-name` → `X-Lower-Name`, `ETag` → `Etag`, `X-MiXeD-CaSe` →
    `X-Mixed-Case`. `Protocol::HTTP::Headers` preserves `X-MiXeD` exactly. `HTTP-13` is about the *model's*
    storage, lookup and equality, not about the wire spelling, and HTTP/1.1 field names are
    case-insensitive — so neither behaviour is a defect. Recorded because a conformance assertion that
    checks the wire bytes for a caller's exact spelling would pass on one adapter and fail on the other,
    which is precisely the kind of assertion `dexpace-conformance` must not contain.
    *Command:* `ruby scratchpad/wire2.rb`.

15. **`Net::HTTP` writes a streaming request body through `IO.copy_stream(f, sock)`, which is the opening
    `TRANSPORT-28` needs and not the whole of it.** `Net::HTTPGenericRequest#send_request_with_body_stream`
    is `IO.copy_stream(f, sock)` on the non-chunked path and `IO.copy_stream(f, Chunker.new(sock))` on the
    chunked one, and it raises `ArgumentError` unless a `Content-Length` or `chunked?` is set. The
    destination is a `Net::BufferedIO`, not a raw `::IO`, so the kernel `sendfile` path is **not** taken —
    but the "honouring any start position and byte count" half of `TRANSPORT-28` and the
    "MUST treat a file body as replayable (re-openable)" half are both reachable from phase 3b's
    `Dexpace::FileBody`. `protocol-http` ships `Protocol::HTTP::Body::File` with `(file, range = nil,
    size:, block_size:)`, `#offset`, `#rewind` and `#rewindable?`, which is `8c`'s equivalent. `R5`.
    *Commands:* `sed -n '269,284p' /usr/lib/ruby/3.4.0/net/http/generic_request.rb`;
    `ruby -e 'require "protocol/http/body/file"; p Protocol::HTTP::Body::File.instance_method(:initialize).parameters'`.

**Three things this document could not verify and does not assert.** (i) **`Fiber#kill`'s availability on
Ruby 3.2**, which `R1` may turn on — only 3.4.10 is installed. (ii) **Every fact above on 3.2.11 and
4.0.6**; the sub-phase designs run the three-interpreter check, and
`observability/65191069`'s own single-interpreter caveat is the standing example of why that matters.
(iii) **`async-http`'s HTTP/2 path**, which was not exercised: every async probe above ran HTTP/1.1
against a local `TCPServer`, so `TRANSPORT-18`'s GOAWAY-replay antecedent and `TRANSPORT-8`'s
native-internal-cancel antecedent are both **unverified** and are `R14`'s subject.

---

## Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every
row, not to scan for its own name. **All forty-two were read** — forty-two numbered rows, `DEF-1`
through `DEF-42`; `grep -c '^### DEF-'` returns 43 only because the file carries its own
`### DEF-<n> — <title>` template at `:18`. As with phases 3 through 7, this document
**states** each disposition and the sub-phase **performs** the register edit.

**Phase 8 picks up four rows, partly picks up one, marks two UNSCHEDULED, and files none.** That is more
register motion than any earlier phase, which is what the last build phase should look like.

- **`DEF-22` — picked up by `8a`.** Its condition names this phase in as many words: "phase 8, which owns
  this gem's gemspec, its version and its first release; phase 9 adds the remaining suites." `8a` writes
  `Dexpace::Conformance::Failure`, the callable assertion protocol and the thin Minitest and RSpec
  drivers, and the §9.3 `TCPServer` fixture beside them. `Status` moves to `picked-up (<date>, phase 8a)`.
- **`DEF-25` — picked up, by `8a` and `8c` together.** Its condition: "phase 8 (Transports and Async
  Runtime), **in each adapter's dispatch path**; phase 9's conformance suite is where the assertion that
  it happened belongs." Each adapter calls `Dexpace::HeaderSyntax` immediately before dispatch; verified
  fact 5 shows why it is load-bearing on the async path specifically, where
  `Protocol::HTTP::Headers#add` validates nothing. Each sub-phase carries its own checklist row; the
  row's `Status` moves at the phase-level PR, once both call sites exist.
- **`DEF-29` — condition met, action declined; `8a` marks it UNSCHEDULED with phase 8a named.** Its
  condition — "the first consumer outside `dexpace-core`. Phase 8 at the earliest, alongside `DEF-22`" —
  **is met**: `8b` drives phase 2's `FakeTransport` from a suite outside `dexpace-core`, and so do `8a`
  and `8c`. The row's *action*, and its whole content, is the literal move named in its title — and this
  document recommends against it: moving `gems/dexpace-core/test/support/`'s three fakes into
  `dexpace-conformance` would make `dexpace-core`'s own suite depend on a gem that depends on
  `dexpace-core`, a development-dependency cycle between the workspace's two most load-bearing gems, for
  no gain core's suite can see. Per the roadmap's retirement rule
  (`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:267-269`, `:299-303`) a met-but-declined
  condition is **UNSCHEDULED with the phase named**, not `picked-up`. `8a` performs the mark unless it
  reverses, in which case it says what it did about the cycle. Separately, `8a` **does** publish
  `dexpace-conformance`'s own doubles, which is the row's *purpose* met by a different route — stated in
  the UNSCHEDULED note rather than used to close the row. The row also says the moment they move "is also
  the moment `DEF-23`'s condition is worth re-reading" — done below.
- **`DEF-31` — picked up and closed by `8b`.** Its condition: "phase 5 … with §8.1's facade — that is
  where the event can be emitted. **The first thing in this repository that actually owns an executor is
  phase 8's `dexpace-async-thread`**, so phase 8 is where the emission gets a real subject and where
  `dexpace-conformance` asserts 'close twice → executor shut once, one event'." 5b ships
  `Events::INSTRUMENTATION_SHUTDOWN` and the field shape and **specifies** a dated `Status` line without
  closing the row (`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction.md:4111`); that
  edit lands when 5b executes, and the row reads `deferred` today. `8b` supplies the subject and `8a`'s
  harness supplies the assertion. `Status` moves to `picked-up`.
- **`DEF-41` — picked up by `8c`, and the row needs a citation corrected.** Its condition: "**phase 8**,
  at the first adapter that drops a caller-set header rather than raising on it — which is `TRANSPORT-8`'s
  subject and is not `dexpace-transport-net_http`." Verified fact 5 shows the condition **is met**:
  `protocol-http1` rejects a name `HTTP-17` accepts, so `TRANSPORT-12` obliges `8c` to drop that header
  only, and `TRANSPORT-13` obliges it to log the drop under a three-mode policy whose two ingredients —
  `Severity`'s two levels and the once-per-key latch — 5b already shipped. **`TRANSPORT-8` is the wrong
  requirement**: its subject is a cancellation originating inside the native client. The antecedent of
  the row's "which" is *the adapter that drops*, and dropping is **`TRANSPORT-12`**'s subject, with
  **`TRANSPORT-13`** the transport-side twin of `OBS-19`'s three-mode policy over that drop. 5b's own
  forward table repeats the same wrong ID — "**Phase 8**, on `TRANSPORT-8`"
  (`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md:2110`) — and is
  corrected with it. Filed as a register amendment below.
- **`DEF-42` — partly picked up by `8a`; the row stays open, and `8c` adds its own emitter call sites
  once `R6` settles the route.** Its own text: "The
  transport-milestone group follows in phase 8 with the first adapter." Phase 8 supplies the emitter for
  5c's five transport methods — **subject to `R6`**, because no route currently exists by which a
  transport reaches an `HTTPTracer` (filed as `OI-36`). The row does **not** close: `OI-32` records that
  the operation-lifecycle triple still waits on a `PRE_REDIRECT`-adjacent step, which phase 8 neither
  ships nor can justify.
- **`DEF-3` — `BODY-12` clause 2's half is dispositioned, and this document recommends UNSCHEDULED.** The
  row targets phase 8 explicitly: "clause 2 — the transport recognising a file-backed body by type and
  dispatching a true zero-copy kernel transfer — **targets phase 8**, alongside `DEF-10`". Verified fact
  15: `Net::HTTP` streams a body through `IO.copy_stream` to a `Net::BufferedIO`, which is not a raw
  `::IO`, so the kernel path is not reachable without bypassing the library's own write path. The roadmap
  is explicit about the status this earns: a row "whose pick-up condition a phase met and declined to act
  on" is marked **UNSCHEDULED with the phase named**, not silently carried. `8a` performs the mark unless
  it finds a route this document did not. **`BODY-36`'s half is untouched** — its condition is core's
  dependency budget changing, which phase 8 does not do.
- **`DEF-10` — untouched, and the distinction from `DEF-3` matters.** Its condition is "revisit when a
  transport adapter **beyond the two MVP transports** ships", and phase 8 ships exactly those two. Not
  met, so **not UNSCHEDULED**. `TRANSPORT-28` and `TRANSPORT-30` are carried as ⏳ rows inside `8a`'s 23,
  exactly as phase 7b counted `DEF-8`'s row inside its 41.
- **`DEF-18` — untouched, and carried as two ⏳ rows plus one N/A that is not on the row.** Its condition
  is "if an interruptible transport path is ever adopted", which §8.3 forbids and phase 8 does not adopt
  — so **not UNSCHEDULED**. The row's title is "ASYNC-3, PIPE-33's interrupt clause" and its `Cites:`
  line is "ASYNC-3, PIPE-33" (`docs/deferred-items.md:258-270`): **`ASYNC-4` is not on it**, and should
  not be, because §10.5 holds it *vacuous* rather than deferred. So `8b` carries `ASYNC-3` ⏳ **citing
  `DEF-18`** and `ASYNC-4` N/A **citing §10.5 and no register row at all**; `PIPE-33`'s cross-reference
  row is `8b`'s too. The roadmap's cross-cutting constraint 8 says "phase 8 marks all three ⏳ citing
  it"; §10.5, §12 and the checklist legend each distinguish an unsatisfied MUST from a vacuous one, so
  **`ASYNC-4` is N/A and not ⏳** — the roadmap's sentence is a summary of the three, and correcting it is
  owed (see *Roadmap follow-through owed*, change 3).
- **`DEF-1` — untouched, and the row is owed a sentence phase 8 can now write.** `SEAM-24`'s **first**
  sentence ("propagate the ambient logging/diagnostic context across the thread handoff") is `ASYNC-8`'s
  and `8b` implements it through `Fiber[]`, within fiber storage. Its **second** sentence is narrower
  than it looks: "**Each adapter's cancellation bridge** SHOULD map cancellation in both directions per
  that ecosystem's idiom (e.g. cancelling a downstream subscription/future cancels the pivot future, and
  vice versa)" — a **caller-facing** bridge over the host's own primitive, which design §3.3 (`:252-254`)
  assigns to `dexpace-async-async` ("maps `Async::Task#stop`/`#with_timeout` onto the pivot's
  cancellation in both directions for callers whose own code is already reactor-based (**ASYNC-6**)") and
  which is `DEF-11`, post-v1. `8c` satisfies `ASYNC-6` for the `Async::Task` **it creates itself**; it
  bridges no caller-held task, so it does not meet `SEAM-24`'s second sentence. What stays deferred is
  therefore both §12's "`SEAM-24` … **beyond fiber storage**, ships with `dexpace-async-async`" and that
  second sentence proper. The row's
  `Status` is right; what it lacks is the statement that most of the SHOULD is met, which a reader will
  otherwise re-derive. Filed as a register amendment below.
- **`DEF-23` — untouched, and the condition was checked rather than assumed.** "When a gem's test support
  becomes production-quality code worth checking — phase 8's conformance helpers at the earliest."
  `dexpace-conformance`'s assertion objects and `TCPServer` fixture are **`lib/` code**, not test support:
  §9.3's whole argument is that a third-party adapter author runs them, which means they ship in the gem,
  and phase 0 already gave that `lib/` its own Steep target. So the condition — a Steep target over a
  **`test/`** tree — is still not met. `8a` confirms; if it instead places the fixture under `test/`, it
  picks the row up and says so.
- **`DEF-21`, `DEF-24`, `DEF-26`, `DEF-27`, `DEF-28`, `DEF-34`, `DEF-39`, `DEF-40`, `DEF-42`'s phase-6
  half — dispositioned by the phase their conditions named** (2, 4b, 3b, 5b, 5a, 5b, 6a, 6a and 6a
  respectively). Their register edits are **execution-time and mostly not yet performed**: only `DEF-3`
  (`:120`), `DEF-21` (`:320`) and `DEF-26` (`:410`) carry a status other than plain `deferred` today.
  Phase 8 consumes the decisions, re-opens none, and does **not** read an unedited `Status` line as a
  missed pick-up.
- **`DEF-30` — untouched, and phase 8 must not meet it by accident.** Presence-gated auto-activation is
  permitted "for **instrumentation only**", and the row's restriction travels with it: "No transport or
  codec adapter may ever use it." Phase 8 ships two transports and one executor adapter, every one of
  which registers **explicitly** through phase 2's `Registry#register`. Named because "activate because
  `async-http` happens to be loaded" is a convenience a `8c` author might reach for, and it is forbidden.
- **`DEF-32` — untouched.** `Hooks.notify`'s dropped handler failures were resolved by phase 4b. Phase 8
  notifies no hook list of its own.
- **`DEF-33` — untouched, and its value has grown again.** A non-CRuby matrix row; phase 8 is the fifth
  phase whose concurrency guarantee rests on a `Thread::Mutex` the GVL would hide the absence of, and
  `8b`'s pool is the most acute case yet. No phase in v1 plans a JRuby or TruffleRuby row.
- **`DEF-35` — untouched.** Picked up by phase 6a; all fifteen `RECOV` IDs are behind phase 8.
- **`DEF-36`, `DEF-37`, `DEF-38` — untouched.** Phase 5's and phase 6's; all three were dispositioned by
  the phases their conditions named.
- **`DEF-2`, `DEF-4`–`DEF-9` — untouched.** `HTTP`, `PIPE`, `RECOV`, `RETRY`, `REDIR`, `SSE` and `OBS`
  deferrals in other prefixes. **`DEF-2` is worth one sentence**: phase 7 declined its floated phase-7
  target and proposed re-targeting it at an *event* rather than a phase — "the first consumer that
  constructs a conditional request … a **`dexpace-conformance` fixture**" is one of the three candidates
  named, and `8a` builds that gem. `8a` should check whether its fixture constructs one; this document
  expects not, because a wire fixture answers requests rather than making them.
- **`DEF-11`–`DEF-17` — untouched.** The seven post-v1 gems. Phase 8 is where the line §2.2 draws becomes
  observable: the pivot ships with `dexpace-async-thread` proving it and `dexpace-transport-async_http`
  proving the properties a thread pool cannot, and `DEF-11`'s `dexpace-async-async` is the second adapter
  over an already-proven property that waits.
- **`DEF-19`, `DEF-20` — untouched, and phase 8 moves them closer than any phase has.** Both are
  release-gated, and phase 8 performs the workspace's **first gem release** (`dexpace-conformance`).
  `DEF-20`'s condition is `docs/first-release.md`'s RubyGems-ownership and trusted-publishing blockers,
  which no phase owns; `DEF-19`'s is "published gems to point at", which phase 8 begins to supply. Neither
  is met by phase 8 alone and neither is marked UNSCHEDULED.

---

## The findings proposed for the registers

**Seven, described here for a human to file. None is acted on by this document, the four proposed
open-item numbers run contiguously from the register's own `next id`, and no register file is edited by
it.**

**Target register: `docs/open-items.md`. Proposed id `OI-34`** (the register's `next id` is `OI-34`).

> ### OI-34 — `Net::HTTP` has a built-in automatic retry that is on by default, and design §3.2, §11.18 and §12 all record that it has none
>
> - **Opened:** 2026-09-11, phase 8 segmentation design
> - **Status:** open
> - **Cites:** TRANSPORT-2, TRANSPORT-17, TRANSPORT-18, TRANSPORT-3, RETRY-13, PIPE-2, XCUT-4
>
> Design §3.2 says "The reference transport disables nothing for **TRANSPORT-1**/**TRANSPORT-2** because
> `Net::HTTP` follows no redirects and retries nothing on its own — those two requirements are vacuous for
> this adapter". §11.18 says "`Net::HTTP` has no resend hook". §12's `TRANSPORT` row lists `TRANSPORT-1`,
> `TRANSPORT-2`, `TRANSPORT-8` and `TRANSPORT-18` as "adapter-scoped and vacuous for `Net::HTTP`", and the
> MUST-level summary counts `TRANSPORT-2` and `TRANSPORT-18` among the eight MUSTs that hold vacuously.
> The redirect half is right; the retry half is false. Verified on `net-http` 0.6.0 under Ruby 3.4.10:
> `Net::HTTP#max_retries` **defaults to 1**, and `#transport_request` retries when
> `count < max_retries && IDEMPOTENT_METHODS_.include?(req.method)` on `Net::ReadTimeout`, `IOError`,
> `EOFError`, `Errno::ECONNRESET`, `Errno::ECONNABORTED`, `Errno::EPIPE`, `Errno::ETIMEDOUT`,
> `OpenSSL::SSL::SSLError` and `Timeout::Error`, where `IDEMPOTENT_METHODS_` is
> `["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]`. The retry re-runs `req.exec`, so it re-writes
> the request body; PUT and DELETE are both in the set. Three consequences, none of them cosmetic: a
> pipeline that believes it is the single retry authority (`TRANSPORT-2`, `PIPE-2`) is not; a single-use
> body could be written twice (`TRANSPORT-17`); and a cancellation delivered by closing the socket under
> a blocked read surfaces as `IOError`, which is **on the rescue list**, so the library would swallow and
> retry a caller's cancellation (`TRANSPORT-3`). All three are fixed by one line, `http.max_retries = 0`,
> which phase 8a will write — but the three requirements' dispositions in §12 are wrong until it does, and
> §12 is frozen. Nothing is broken today because nothing is implemented. What would resolve it: phase 8a
> implements the disable and its checklist states the corrected reason; §12's `TRANSPORT` row and the
> MUST-level count are corrected the next time §12 is deliberately amended by a human, and
> `docs/deviations.md` carries the interim note.
>
> **Resolution:** *(open)*

**Target register: `docs/open-items.md`. Proposed id `OI-35`.**

> ### OI-35 — design §3.2 prescribes a block-scoped `read_body` construction for `dexpace-transport-net_http` that cannot satisfy the two requirements it says it satisfies "literally"
>
> - **Opened:** 2026-09-11, phase 8 segmentation design
> - **Status:** open
> - **Cites:** SEAM-11, TRANSPORT-25, TRANSPORT-19, IO-41, BODY-15, HTTP-43
>
> `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:167-171` reads: "Streaming is preserved end
> to end: `dexpace-transport-net_http` issues the request inside `Net::HTTP#request(req) { |res| ... }`
> and exposes the response body as a `BufferedSource` over the block-scoped
> `Net::HTTPResponse#read_body` stream, so **SEAM-11**'s no-pre-buffering clause and **TRANSPORT-25**'s
> 'lazily-read stream, not pre-buffered ... closing the SDK response cascades to close the native body and
> release the connection' are satisfied **literally**." Measured against a `TCPServer` that writes five
> body bytes, sleeps 400 ms and writes five more, on `net-http` 0.6.0 under Ruby 3.4.10: `#request`
> without a block returned after **401 ms** with `res.body == "aaaaabbbbb"`; the block form with a block
> that does not read returned with the body already buffered, because `Net::HTTPResponse#reading_body`
> ends with `self.body` and nils `@socket` in its `ensure`; and `res.read_body` after the block raised
> `IOError: Net::HTTPOK#read_body called twice`. So the prescribed construction yields a **fully buffered
> body and a dead socket** — `SEAM-11`'s "MUST NOT pre-buffer the body (caller owns read/close)" and
> `TRANSPORT-25`'s lazily-read stream both violated by the design's own recipe. The construction that does
> work keeps the block open across the return of `#call` (a `Fiber` or a producer thread), which §3.2
> does not describe and which brings its own abandonment problem — an abandoned `Fiber` never runs its
> `ensure`, so the connection leaks. This is `OI-34`'s species in the same paragraph of the same frozen
> section: a design sentence that is false about `Net::HTTP`. Phase 8a's `R1` decides the construction and
> records whichever it takes as an implementation choice or a `P8-<n>` deviation; this row records that
> the chapter it is departing from is wrong rather than merely silent. Nothing is broken today because
> nothing is implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/open-items.md`. Proposed id `OI-36`.**

> ### OI-36 — no route exists by which a transport adapter reaches an `HTTPTracer`, so `DEF-42`'s transport-milestone group has a vocabulary and no reachable emitter
>
> - **Opened:** 2026-09-11, phase 8 segmentation design
> - **Status:** open
> - **Cites:** OBS-28, OBS-29, DEF-42, OI-31, OI-32, SEAM-11, SEAM-16, PIPE-11, NFR-4
>
> Phase 5c shipped `Dexpace::Instrumentation::HTTPTracer` with five transport methods whose argument lists
> it fixed — `#request_url_resolved(context, url)`, `#connection_acquired(context, host, port)`,
> `#request_sent(context, byte_count)`, `#response_headers_received(context, status, headers)`,
> `#response_received(context, byte_count)` — and `DEF-42` records that "the transport-milestone group
> follows in phase 8 with the first adapter". `OBS-29` additionally requires "One tracer instance
> corresponds 1:1 to a single logical **operation** lifecycle (created by the factory per operation)". The
> transport seam is `#call(request, options, cancellation)`; `Request`'s members are
> `(:method, :url, :headers, :body)` and `RequestOptions`'s are `(:timeout, :max_retries, :tags)`
> (phase 5b's `P5-33` states both), the adapter is in a different gem, `PIPE-11` forbids ambient carriage,
> and `NFR-4` locks the seam's three-argument shape. So an adapter can reach a tracer only through its own
> constructor — which gives one tracer for the adapter's whole lifetime, not one per operation — or
> through a widening of `RequestOptions`, which is a core type and a phase-1 surface. This is `OI-31`'s
> shape one layer further out: `OI-31` records that a pipeline **step** cannot reach a context bundle;
> this records that a **transport in another gem** cannot reach a per-operation tracer at all. Phase 8a
> decides and the decision may be "not wired, and `DEF-42` stays open on this half too", which is what
> `OI-32` already records for the operation-lifecycle triple.
>
> **Resolution:** *(open)*

**Target register: `docs/open-items.md`. Proposed id `OI-37`.**

> ### OI-37 — a cancelled `Async` task raises an `Exception` that is not a `StandardError`, so `Dexpace.close_quietly` and every `rescue` written the obvious way are blind to it
>
> - **Opened:** 2026-09-11, phase 8 segmentation design
> - **Status:** open
> - **Cites:** SEAM-30, ASYNC-5, ASYNC-6, TRANSPORT-7, TRANSPORT-9, TRANSPORT-22, CFG-21, XCUT-13
>
> Design §3.3's check-after-resume rule says a producer that discovers cancellation while holding a
> response "MUST close any response it holds and settle through the failure channel", and §3.7 makes
> `Dexpace.close_quietly` the single sanctioned exit for such a close — it "rescues `StandardError` from
> `#close`". Verified on `async` 2.45.1 under Ruby 3.4.10: `Async::Stop` **is** `Async::Cancel` —
> `lib/async/stop.rb` is `module Async; Stop = Cancel; end` — and `lib/async/cancel.rb:8` declares
> `class Cancel < Exception`, so `Async::Stop.equal?(Async::Cancel)` is `true` and
> `Async::Cancel.ancestors.take(3)` is `[Async::Cancel, Exception, Object]` — **not a `StandardError`**.
> `Async::Task#cancel` raises it inside the task and `#stop` is the backward-compatible alias, so a
> `rescue => e` or a `rescue StandardError` in an adapter's send path does not
> run, while `task.with_timeout`'s `Async::TimeoutError` **is** a `StandardError` and does. An orphan-close
> written as a `rescue` therefore runs on a timeout and not on a cancellation, which is the exact inverse
> of what `SEAM-30` and `ASYNC-5` are for, and it is silent. The mechanism is phase 2's and phase 8
> neither introduces nor widens the gap; the repair is local — the close belongs in an `ensure`, not a
> `rescue` — and `close_quietly`'s own rescue of `StandardError` from `#close` is unaffected and correct.
> Because the two names are one class, `rescue Async::Cancel` and `rescue Async::Stop` catch the same
> thing; an adapter that writes both has written one. Recorded rather than fixed here because
> `close_quietly`'s contract is phase 2's and a second exit would
> give the SDK two answers to one question. It is `OI-18`'s species: a core mechanism that is correct about
> what it was designed for and silent about a case a later gem made reachable.
>
> **Resolution:** *(open)*

**Target register: `docs/deferred-items.md`, as an amendment to `DEF-41`'s pick-up condition and `Cites:`
line.** `DEF-41`'s condition reads "**phase 8**, at the first adapter that drops a caller-set header
rather than raising on it — **which is `TRANSPORT-8`'s subject** and is not `dexpace-transport-net_http`."
`TRANSPORT-8`'s subject is a cancellation originating inside the native client. The antecedent of the
row's "which" is *the adapter that drops*, and dropping is **`TRANSPORT-12`**'s subject; **`TRANSPORT-13`**
is the logging policy over that drop — "A transport SHOULD expose a configurable policy for how such
header drops are logged (every drop loudly; first per name loudly then quiet, default; all quiet)" — which
is `OBS-19` from the transport side, three modes for three modes. So the condition should read: "… at the
first adapter that drops a caller-set header rather than raising on it — which is **`TRANSPORT-12`**'s
subject, with **`TRANSPORT-13`** the transport-side twin of `OBS-19`'s three-mode policy — and is not
`dexpace-transport-net_http`." The route the row describes is right and the requirement it names is wrong,
which is the same species of error phase 7 found in `OI-5`'s resolution text. **The same wrong ID is
repeated in phase 5b's forward table** — "**Phase 8**, on `TRANSPORT-8`"
(`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md:2110`) — and is
corrected in the same change, because a corrected register row pointing at an uncorrected phase document is
how a correction gets lost. The amendment also records that the condition **is now met**: `protocol-http1`
rejects a header name `HTTP-17` accepts, so `dexpace-transport-async_http` must drop rather than raise.
`Cites:` should become `OBS-19`, `TRANSPORT-12`, `TRANSPORT-13`, `HTTP-17`, `HTTP-18`, `XCUT-19`, `NFR-4`,
`DEF-25`, `OI-8`, `OI-27`.

**Target register: `docs/deferred-items.md`, as an amendment to `DEF-1`'s `Status` line.** The row is
correct and incomplete. Phase 8 satisfies `SEAM-24`'s **first** sentence within fiber storage —
`ASYNC-8`'s thread-handoff propagation in `dexpace-async-thread` — and `dexpace-transport-async_http`
satisfies `ASYNC-6` for the `Async::Task` **it creates itself**. What stays deferred is both the "beyond
fiber storage" scope §12 names and `SEAM-24`'s **second** sentence proper — "**Each adapter's cancellation
bridge** SHOULD map cancellation in both directions per that ecosystem's idiom" — a *caller-facing* bridge
over the host's own primitive, which design §3.3 (`:252-254`) assigns to `dexpace-async-async` and which
no phase-8 gem supplies. Without that distinction the row reads as though nothing of the SHOULD is built
after phase 8, and a phase-9 audit would have to re-derive it from three sub-phase designs. No status
change: the row stays **deferred** and is **not** UNSCHEDULED, because the condition it names —
`dexpace-async-async` — is post-v1 and unmeetable here.

**Target register: `docs/first-release.md`.** Two changes, both owed by the phase-level PR rather than by a
sub-phase. **First**, the standing phase-8 blocker — "Phase 8's first transport adapter must wrap every
stdlib I/O and timeout error it lets escape … in something answering `#retryable?`
(`Dexpace::TransportError` or equivalent), defaulting to `true` per `XCUT-4` branch (b)" — is **closed by
the phase-level task**, and verified fact 10 supplies the exact list the wrap must cover:
`Net::OpenTimeout`, `Net::ReadTimeout`, `Net::WriteTimeout` (all `< Timeout::Error < RuntimeError`),
`SocketError` (`< StandardError`), `Errno::*` (`< SystemCallError`), `Async::TimeoutError`
(`< StandardError`) and `Protocol::HTTP1::Error` (`< StandardError`) — **none of which is an `::IOError`**,
which is the whole reason the blocker exists. **Second**, the Gems table's `dexpace-conformance` row moves
off `no — 0.0.0` when phase 8 performs the workspace's first release, and the blocker "The
`dexpace-conformance` suite passing across the full supported Ruby range, 3.2 through 4.0" becomes
checkable for the first time.

**Two rows explicitly do not close.** `OI-9`'s one-byte-per-read defect in `BufferedSource.wrapping`
reaches every transport phase 8 writes and is phase 3a's code to fix, not phase 8's; `OI-22`'s missing
`CFG-20` citation is phase 5a's and phase 8 adds no fourth unsatisfied MUST for it to point at.

---

## Roadmap follow-through owed

`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` changes in **four** ways and this document is
constrained to write one file, so all four are owed. Each is given verbatim-ready. Two are
corrections-in-place, which the roadmap's own rule permits ("a wrong cell is corrected in place, with the
correction stated").

**1. The phase-8 row (`:93`) gains links, appended to the design citation and never replacing it.** The
`sdk-design refs` cell currently ends `§3.2, §3.3, §3.7, §9.3, §10.5`. It should end with the text below —
given in a fenced block rather than as live markdown, because the relative paths are correct **from the
roadmap's own directory** (`docs/work/mvp/`) and would dangle if they resolved from this file's:

```
§3.2, §3.3, §3.7, §9.3, §10.5; segmentation design: [`phase8/2026-09-11-phase8-segmentation-design.md`](./phase8/2026-09-11-phase8-segmentation-design.md); 8a design: [`phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md`](./phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md); 8b design: [`phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-design.md`](./phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-design.md); 8c design: [`phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md`](./phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md)
```

The three sub-phase links are added as each design is filed, matching how phases 3 through 7 accumulated
theirs.

**2. The segmentation rule's phase-8 bullet (`:248-251`) is corrected in place, with the correction
stated**, per the roadmap's own rule. The replacement:

> - **Phase 8 (52 nominal IDs, effectively more), expected 8a transports, 8b async runtime.** Raw count
>   alone would not force a split; shipping four gems does, and so does the per-gem conformance work the
>   count does not see. The cut is the §17/§18 line, which is also the
>   `SEAM-11`-versus-`SEAM-16`/`SEAM-17` line — a synchronous transport and an async-runtime bridge over
>   the core pivot are genuinely different concerns. (**Corrected in place 2026-09-11** by the phase-8
>   segmentation design, which took a **three-way** cut — `8a` synchronous transport and the conformance
>   gem, `8b` async-runtime adapter, `8c` asynchronous transport — and found the stated reason false on
>   the §17 side. **The count is unchanged and the phase-8 row above is unchanged**: `TRANSPORT-1`–`30`
>   and `ASYNC-1`–`22` still sum to 52 and no ID moves. What is wrong is the claim that the chapter line
>   *is* the seam line. Five of §17's thirty requirements — `TRANSPORT-7`, `TRANSPORT-8`,
>   `TRANSPORT-9`, `TRANSPORT-21` and `TRANSPORT-23` — have an **async-only antecedent** and are
>   `SEAM-16`'s, so a synchronous-transport segment cannot exercise them, and §17's own preamble names
>   "§7 / **SEAM-11, SEAM-16**" together in its first sentence. In the other direction the pairing is too
>   tidy rather than wrong: fifteen of §18's twenty-two impose an **executor, worker, pooled-thread or
>   bridge** obligation — `SEAM-18` and `SEAM-25` — while §18's own preamble names **`SEAM-17`** as its
>   interchange point, so the chapter line is not the seam line in either direction.
>   `dexpace-transport-async_http` sits on neither side of the chapter line:
>   it is a transport by chapter — §2.1 calls it "The reference *asynchronous* transport" — and is
>   **not** an async-runtime adapter by §18's own definition, because
>   it bridges nothing: it implements the SPI natively over a reactor. So it gets its own segment. The
>   three sub-phases are **independent** and every boundary is a **convenience**; `dexpace-async-thread`
>   declares `dexpace-core` and nothing else, `dexpace-transport-async_http` declares `async-http` and
>   needs no thread pool, and the two shared artifacts — §9.3's `TCPServer` fixture and `DEF-22`'s
>   assertion protocol — are **assigned to `8a`**, with each design stating whether it wrote or consumed
>   them if the sub-phases run out of order. One task is
>   phase-level because it lands in a gem none of the three ships: `Dexpace::TransportError < ::IOError`
>   in `dexpace-core`, which closes `docs/first-release.md`'s standing phase-8 blocker. Cross-cutting
>   constraint 4's "phase 8 brings the first real socket" is confirmed and is worth narrowing: `8a` and
>   `8c` bring it and `8b` brings none.)

**3. Cross-cutting constraint 8 (`:72-74`) is corrected in place.** It currently ends "phase 8 marks all
three ⏳ citing it". Phase 8 marks two ⏳ and one N/A, because §10.5, §12 and the checklist legend each
distinguish an unsatisfied MUST from a vacuous one, and because `DEF-18`'s `Cites:` line is
`ASYNC-3, PIPE-33` — `ASYNC-4` is on no register row. The replacement for the clause:

```
(design §10.5, carried as `DEF-18`): phase 8 marks `ASYNC-3` and `PIPE-33`'s interrupt clause ⏳ citing it and `ASYNC-4` **N/A**, per §10.5's own distinction between an unsatisfied MUST and a vacuous one (**corrected in place 2026-09-11** by the phase-8 segmentation design; the earlier sentence summarised all three as ⏳, and `DEF-18` carries only the first two); phase 10 audits the ledger.
```

**4. A dated entry appended to `## Phase Status Notes`.** Suggested content, to be adjusted by whoever
files it:

> **2026-09-11** — Phase 8's segmentation design filed at
> `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`. **Three sub-phases, not two**: `8a`
> synchronous transport and the conformance gem, `8b` async-runtime adapter, `8c` asynchronous transport;
> every boundary a convenience; the segmentation bullet and cross-cutting constraint 8 both corrected in
> place above with their reasons. 52 IDs, none moving in or out, split 23 / 19 / 10. **Four** register
> rows picked up (`DEF-22`, `DEF-25`, `DEF-31`, `DEF-41`), one partly (`DEF-42`), **two** marked
> UNSCHEDULED (`DEF-3`'s `BODY-12` clause 2, and `DEF-29` — condition met, the literal move declined on a
> development-dependency-cycle argument), none filed. Four open items proposed (`OI-34`–`OI-37`), of which
> `OI-34` and `OI-35` both record that design §3.2 is wrong about `Net::HTTP` — the built-in retry it says
> does not exist, and the block-scoped streaming construction it says satisfies `SEAM-11` and
> `TRANSPORT-25` "literally". No new unsatisfied MUST: `ASYNC-3` and `PIPE-33`'s interrupt clause are
> §10.5's and `DEF-18` carries both unchanged, while `ASYNC-4` is on no register row because §10.5 holds
> it vacuous. `CLAUDE.md`'s phase-directory count goes from eight to nine with this filing; the "Zero gems
> exist under `gems/`" sentence is unaffected and stays true.

**`CLAUDE.md` follow-through owed, in the same change that files this document.** Three edits, and the
third is the one a naive author gets wrong.

**(a)** The claims sentence "There are eight phase directories under `docs/work/*/`" becomes **nine**.

**(b)** The inline list on the same sentence — "plus `phase0/`, `phase1/`, `phase2/`, `phase3/`,
`phase4/`, `phase5/`, `phase6/` and `phase7/`" — becomes "… `phase6/`, `phase7/` and `phase8/`". The
document's "the enumeration gains `phase8/` after `phase7/`" is about the paragraph below it; the inline
list is a separate edit on the same line and is easy to miss.

**(c)** The enumeration gains a `phase8/` entry, in the style of the phase-6 and phase-7 ones:

> `phase8/` carries its segmentation design,
> `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`, and three sub-phase
> directories — `phase8/phase8a/` (synchronous transport and the conformance gem),
> `phase8/phase8b/` (async-runtime adapter) and `phase8/phase8c/` (asynchronous transport);
> each holds a design and a plan. Phase 8 is 52 IDs (`TRANSPORT-1`–`30`, `ASYNC-1`–`22`) and is
> the phase that ships the most gems in the roadmap — `dexpace-transport-net_http`,
> `dexpace-async-thread`, `dexpace-transport-async_http` and `dexpace-conformance`, whose
> gemspec, version and first release phase 8 owns. Its three sub-phases are independent, so
> their order is convenience; one task is phase-level because it lands in `dexpace-core`, which
> none of the three ships.

**The wording of (c) is not a style choice.** `.claude/skills/housekeeping/probe.rb:288` registers a
`CLAUDE.md` claim `numbered(/(?:\*\*)?gems\b/)` → `gem_count(repo)`, and `Claims#check` (`:303-313`)
loops over **every** match in the file's asserted prose rather than the first. `gem_count` is 0 today —
`gems/` does not exist — so a phrase of the form "**four gems**" anywhere in `CLAUDE.md` produces a
finding reading `states "four gems" but the repository has 0 gems under gems/`. That is why the existing
phase-7 entry says "the workspace's **second real gem**" (singular) and why `CLAUDE.md`'s own table
heading is "MVP gems (…§2.1):" with no numeral in front: the convention is deliberate. Any rewording of
(c) must keep every numeral away from the word *gems*.

**Nothing else in `CLAUDE.md` changes.** "Zero gems exist under `gems/` — the directory itself does not
exist yet" stays true until phase 0's scaffold lands as code; "There are 40 harvested topics under
`docs/knowledge/harvested/`" is untouched; the MVP gem table's dependency column already states
`net-http`, `async-http` and the zero-dependency adapters correctly.

**What `ruby .claude/skills/housekeeping/probe.rb` reports until follow-through lands, so the next runner
does not read it as drift.** Re-run on 2026-09-12 after all seven phase-8 documents were written and
reconciled, the probe reports **18 findings across two checks**, all of them consequences of those
documents existing and none fixable from inside them. (**Corrected in place**: this paragraph said
"exactly five findings", counting only this document's own four proposed ids, before the three sub-phase
designs proposed eleven more.)

- **`claims` (1)** — `CLAUDE.md:381`: states "eight phase directories" but the repository has 9 phase
  directories under `docs/work/`. Edit (a) above closes it.
- **`citations` (17)** — **fifteen `OI-<n>` numbers are cited across phase 8 with no entry in
  `docs/open-items.md` yet**, two of them (`OI-38` and `OI-41`) cited twice, which is where 15 becomes 17
  lines. The register's `next id` is `OI-34` and the fifteen run contiguously from it: `OI-34`–`OI-37`
  here, `OI-38`–`OI-41` in `8c`'s design, `OI-42`–`OI-45` in `8a`'s and `OI-46`–`OI-48` in `8b`'s, in
  sub-phase order. Every one of the fifteen is written out in the register's own item format in the
  document that proposes it, for pasting. Phase 7's findings deliberately carried no numbers and produced
  no such finding; this phase files numbered rows so the follow-through is a paste rather than a
  re-derivation, which is why the trade is different and why it is stated here rather than left to be
  rediscovered. **A filer runs `--only citations` first** and, if any of the fifteen lands on a different
  number, shifts the rest mechanically — nothing in phase 8 cites an `OI-3x`/`OI-4x` from source code.

`links`, `inbox`, `root`, `readmes`, `registers` and `guard` are clean.

**Once the follow-through above is applied**, edits (a) and (c)/(b) clear the `claims` finding and the
fifteen pasted register rows clear the `citations` findings, leaving the probe clean. The four-digit trap
is edit (c)'s wording: paste it as given.

---

## Risks and open questions the sub-phase designs must resolve

Each is named with the sub-phase that owns it. **None is decided here.** Risk numbering restarts per phase
in this repository — phase 3's ran R1–R10, phase 4's R1–R14, phase 5's R1–R15, phase 6's R1–R15 and phase
7's R1–R12 — so phase 8's are `R1`–`R16` and collide with none.

**R1 — `8a`: how a `Net::HTTP` response body outlives `#call` without leaking a socket.** The phase's
hardest decision, and verified fact 2 is the whole of the problem: `#request` without a block buffers the
entire body (`SEAM-11`'s "MUST NOT pre-buffer" and `TRANSPORT-25` both violated); the block form buffers
too unless the block reads; a `Fiber` holding the block open delivers chunks lazily and correctly but
**never runs its `ensure` when abandoned**, and `Fiber#kill`'s availability on the 3.2 floor is unverified.
The candidates are a per-response `Fiber` with `#close` driving `Fiber#kill` (needs the 3.2 check), a
per-response `Thread` plus a `Thread::SizedQueue` with deterministic teardown (costs a thread per in-flight
response and reaches `8b`'s territory without depending on `8b`'s gem), or a deviation admitting that this
adapter buffers. `8a` picks one, states the observable behaviour of `Response#close` on an unread body,
and if it is a deviation numbers it `P8-<n>` and says what `TRANSPORT-19`'s abandoned-subscription clause
then means. §7.1's rule — the resource lives on the object with `#close`, never inside the block — is the
constraint, not the answer.

**R2 — `8a`: the outbound header policy, against a library that stamps four headers and honours one it
should not.** Verified fact 4. `8a` decides the `TRANSPORT-11` drop set (`Host` is the surprise — the
requirement names it and `Net::HTTP` honours it verbatim), whether the three auto-stamps
(`Accept-Encoding`, `Accept`, `User-Agent`) are suppressed or documented, and how `TRANSPORT-10`'s
"body-derived Content-Type MUST be emitted only when the caller set none" survives
`supply_default_content_type`'s unconditional `application/x-www-form-urlencoded`. It also decides
`decode_content`: leaving it `true` means the SDK hands callers a decompressed body with
`Content-Encoding` removed and `Content-Length` rewritten, which is defensible and is not what
`TRANSPORT-24`/`TRANSPORT-27` describe; setting it `false` means the SDK owns decompression, which no
requirement asks for.

**R3 — `8a`: what one `RequestOptions#timeout` means across three `Net::HTTP` knobs.** `TRANSPORT-5`
requires a per-call override to apply "to that single call, overriding the transport's configured default
for that call only". Phase 1 shipped `RequestOptions` with a single `:timeout` member; `Net::HTTP` has
`open_timeout`, `read_timeout` and `write_timeout`. `8a` decides whether one value sets all three, whether
it is a total budget split across them (which needs a monotonic deadline and phase 5a's clock), or whether
the adapter takes three constructor defaults and the per-call value overrides one. Whichever it picks,
`resource-management/d1f16cad` requires the configured defaults to come from phase 5a's layered chain as
named settings rather than literals.

**R4 — `8a`: `TRANSPORT-27`'s unknown-length sentinel. RESOLVED 2026-09-12, and this risk's premise was
wrong.** It read: "half of which is unreachable … verified fact 12: a non-numeric `Content-Length` raises
`Net::HTTPHeaderSyntaxError` out of `#request` itself, so there is no response to downgrade", and offered
`8a` a choice between a deviation row, an expensive pre-parse, and a partial decline. **Fact 12 measured
`#request` *without a block*.** `8a` uses the block form for `R1`'s reasons anyway, and under it
(`8a` design's own verified fact 12) the head is delivered in full — `res.code`, `res.message` and
`res.to_hash` all available inside the block — and the raise comes later, from
`Net::HTTPResponse#content_length`, which `read_body_0` calls to choose its framing. So `8a` parses the
length from the raw header text (`/\A[0-9]+\z/`, else `-1`, because `Integer("-4", 10, exception: false)`
returns `-4` and would collide with the sentinel), deletes the unparseable header from the native
response before the body read so `read_body_0` falls through to connection-close framing, and downgrades
a malformed `Content-Type` in `ResponseMapper` through a `rescue Dexpace::InvalidArgumentError` — because
phase 1's `MediaType.parse` **raises** rather than returning `nil`. **`TRANSPORT-27` is satisfied whole,
with no deviation and no pre-parse**, and the scope table's cell is corrected to match. The unknown-length
sentinel is **`-1`** throughout, never `nil` (appendix C's own text; `BODY-35`); `8c` maps its native
`nil` length to `-1` at the point it reads it. **The adapters differ on the invalid-`Content-Length`
half and the conformance run must say so per adapter**: on `Net::HTTP` it is reachable and satisfied
(above); on `async-http` `Protocol::HTTP1::BadRequest` is raised out of the read and no response object
exists to downgrade (`8c`'s verified fact 11), so `8c` carries a **named waiver listing `TRANSPORT-27`
for its own driver only** — not, as an earlier revision of `8c` said, one waiver "covering both
drivers", because `8a` measured its own adapter directly and found the clause reachable there.

**R5 — `8a`: whether `TRANSPORT-28`'s reachable half is worth taking, and what that does to `DEF-3`.**
Verified fact 15: `Net::HTTP` writes a streaming body through `IO.copy_stream(f, sock)` where `sock` is a
`Net::BufferedIO`, so the kernel path is out of reach — but "honouring any start position and byte count"
and "MUST treat a file body as replayable (re-openable)" are both reachable from phase 3b's
`Dexpace::FileBody` (`#path`, `#offset`, `#count`, and deliberately no `#to_path`). `8a` decides whether
to implement the reachable half and mark `TRANSPORT-28` partially satisfied, or to carry the whole ID ⏳
against `DEF-10` — and, either way, performs `DEF-3`'s `BODY-12` clause-2 disposition, which this document
recommends be **UNSCHEDULED with phase 8 named**.

**R6 — `8a`: whether `DEF-42`'s transport-milestone group is wired at all.** `OI-36`: no route exists by
which an adapter in another gem reaches a per-operation `HTTPTracer` through an `NFR-4`-locked
three-argument seam. `8a` decides between a constructor keyword (one tracer per adapter lifetime, which
`OBS-29`'s 1:1 clause does not describe), a widening of `RequestOptions` (a core type, a phase-1 surface,
and a real `NFR-4` widening), and leaving the half unwired and saying so in the row — which is what
`OI-32` already records for the operation-lifecycle triple and is the answer this document expects. It
must not mark `OBS-29`'s transport group emitted on the strength of a method that is never called.

**R7 — `8a`: the shape of the `TCPServer` fixture and the assertion protocol, so `8c` and phase 9 extend
rather than fork them.** §9.3 fixes the protocol ("a callable that either returns cleanly or raises a
`Dexpace::Conformance::Failure` carrying the expected and actual values") and the fixture's reason (socket
behaviour a stub cannot express; the same assertions unchanged against a second adapter). What is open:
whether the per-adapter parameterisation is a module included per adapter or a driver taking an adapter
factory; whether the fixture ships in `lib/` (this document's recommendation, and the reading that leaves
`DEF-23` unmet) or `test/`; how a **vacuous** item is recorded as vacuous rather than passing, per §12;
and how §9.3's named-waiver mechanism for `ASYNC-3` is spelled. `8c` and phase 9 both inherit whatever
this decides.

**R8 — `8b`: `ASYNC-9`'s save/install/restore against `OI-13`'s warned setter.** `Fiber#storage=` is the
only whole-map write API, it warns on every call at the default warning level (re-verified, two calls →
two warnings, category `:experimental`), and the gate set fails the build on warnings. Three routes, all
with a cost: a **per-key** save/install/restore in the shape 5c's `P5-49` already took (which collapses
"was absent" and "was present and null" into removal — harmless at 5c's only reader because `OBS-10` skips
null values, and `8b` must check that the same argument holds for an arbitrary key set); a scoped
`Warning.warn` filter around the call, which is a mutation of a process-global object the port already
refuses for `Regexp.timeout`; or an `NFR-7` waiver carrying its reason. `8b` picks one and states the
supported-range risk "experimental and may be removed in the future" leaves on the table.

**R9 — `8b`: which clause of `ASYNC-12` is live, given that a new `Thread` inherits `Fiber[]`.** Verified
fact 13. `ASYNC-12`'s antecedent is "runtimes where a newly created worker does not inherit the spawning
thread's logging context" — **false for a freshly spawned Ruby thread**, and true for a **pooled** worker,
which was created long before the task arrived and carries the pool creator's context. That makes the live
obligation `ASYNC-10`'s per-task-submission capture rather than `ASYNC-12`'s thread-creation transfer.
`8b` states which it satisfies and how, and does not record `ASYNC-12` ✅ on the strength of a property
`Fiber[]` provides for a case the requirement is not about. It must also re-run
`observability/65191069`'s measurements on 3.2.11 and 4.0.6 and clear the note's own caveat.

**R10 — `8b`: what `Completer#on_cancel` actually does for a pooled worker blocked in a transport read.**
§10.5's mitigation is "the check-after-resume rule aborts the worker at its next resume point, and
`Completer#on_cancel` lets an adapter shorten that by closing the socket under the read". Verified fact 11
measures the mechanism (a cross-thread `#close` wakes a blocked `readpartial` with `IOError`) and
verified fact 1 measures the collision (`IOError` is on `Net::HTTP`'s retry rescue list). `8b` decides
whether the pool exposes such a hook at all — the pool posts an opaque block and does not know what is
inside it — or whether the hook belongs to the *transport* that owns the socket, which would make it
`8a`'s. Whichever it is, `TRANSPORT-3`'s out-of-band discrimination must survive: the woken `IOError` must
not be classified as a retryable transport failure when a cancellation caused it.

**R11 — `8b`: `ASYNC-18`'s non-blocking delay with no `Fiber.scheduler`.** Phase 5a's
`Dexpace::Async.delay` raises `Dexpace::SeamError` when `Fiber.scheduler` is `nil` (`P5-9`), and phase 5's
`R6` left `CFG-18`'s scheduler-conditional shape open. `ASYNC-18` requires the primitive to "complete after
the requested delay **without blocking a thread**", complete immediately at zero, reject a negative, and
cancel the underlying scheduled task when the future is cancelled. `8b` decides whether
`dexpace-async-thread` supplies a timer that satisfies the clause (a single timer thread parked on a
bounded queue wait is a defensible reading of "without blocking a thread" — it blocks *one* thread, not the
caller's and not a pool worker), or whether it is a deviation, and states the answer for the
no-scheduler case rather than inheriting 5a's raise by default.

**R12 — `8b`: the pool's bound, rejection policy and teardown, against six corpus rules routed here by
name, and against a core-declared interface it did not write.** `7c` assigns
`Dexpace::Page::_Executor` — the one-method `#post { }` duck type — its first real implementation here, so
`8b`'s pool must satisfy an RBS interface written in another gem in an earlier phase, which is an
`NFR-3`/`NFR-11` surface it inherits rather than designs; it states whether the pool's `#post` signature
is that interface's or a superset of it. `concurrency-and-async/f414b864` routes `/6764e0b5`, `/dc345cae`, `/df658d73`, `/3692970f`,
`/047644ea` and `/dd8e6d2d` — the bounded-pool and deterministic-teardown family — to this gem with no
phase-2 obligation. `8b` reads all six and says what it does with each. The requirement-side constraints it
must satisfy simultaneously: `SEAM-18`'s no-default-executor rule (the `executor:` keyword is required and
a shared global pool is "explicitly not acceptable because a blocking call would starve it"), `ASYNC-2`'s
rejection-through-the-future, `ASYNC-16`'s graceful shutdown, and `XCUT-13`'s prohibition on an unbounded
await — which §3.7 already states for this gem: "close signals its queue and returns, it does not join
workers under a `Kernel#sleep` or an unbounded `Thread#join`."

**R13 — `8c`: where the orphan close lives, given that a cancelled task raises outside `StandardError`.**
Verified fact 9 and `OI-37`. `SEAM-30`/`ASYNC-5`/`TRANSPORT-9`/`TRANSPORT-22` all require a response to be
closed on a path where nobody will receive it, and `Async::Cancel < Exception` — with `Async::Stop` a
deprecated **alias** of that same class, not a subclass — means a `rescue` written the obvious way never
runs on a cancellation while it does run on `Async::TimeoutError`. `8c` states that every such close sits
in an `ensure`; states how `TRANSPORT-3`'s and `TRANSPORT-8`'s discrimination tells a cancellation from a
timeout out-of-band (both are available: `Async::Task#status` and the token's typed `#reason`); notes that
`rescue Async::Cancel` and `rescue Async::Stop` name one class, so an adapter that writes both has written
one; and writes a test asserting the close ran on a **cancellation** specifically — not only on a timeout,
which is the test a correct-looking wrong implementation passes.

**R14 — `8c`: `TRANSPORT-8`'s and `TRANSPORT-18`'s dispositions, both of which this document could not
verify.** §12 records both as adapter-scoped and vacuous "for `Net::HTTP`" and says nothing about
`async-http`. `TRANSPORT-8` needs a cancellation "originating inside" the client while the SDK future is
live — candidates are `async-pool` reaping a connection, an HTTP/2 GOAWAY, and `Protocol::HTTP::RefusedError`.
`TRANSPORT-18` needs a re-subscribable producer driving a native internal resend — `Async::HTTP::Client#call`
has exactly that loop, bounded by `retries:`, which `8c` sets to 0. **`TRANSPORT-18`'s row stays `8a`'s**
under the one-row-per-ID convention: `8c` *reports* whether the antecedent is live on `async-http`, and
`8a` amends the row's stated reason if it is. **Every async probe in this document
ran HTTP/1.1 against a local `TCPServer`; the HTTP/2 path was not exercised.** `8c` decides whether either
antecedent is live for this adapter and, if `TRANSPORT-8` is, whether the port gains a requirement §12
records as vacuous — which would be a correction to §12 of the same species as `OI-34` and must be filed
as one.

**R15 — `8c`: `NFR-2`'s budget against a fourteen-gem transitive closure with a native extension.**
Verified fact 7. `dexpace-transport-async_http` declares one third-party dependency and installs fifteen
gems, one of which (`io-event`) compiles C. `gates:gemspec_audit` counts declared dependencies and passes.
`8c` states whether that satisfies `NFR-2` as written — this document's reading is that it does, because
the requirement's words are "depending on core plus at most one third-party library" and a library's own
dependencies are that library's business — and decides whether the closure is worth a line in
`docs/first-release.md`, whether `bundler-audit`'s surface changes materially, and what the
`rbs_collection.yaml` row needs. It also states what happens on a platform where `io-event` cannot build.

**R16 — `8a` and `8c` jointly: who writes the conformance harness, and the one-line extension.** This
document **assigns** the `TCPServer` fixture and `DEF-22`'s protocol to `8a`; under the recommended order
that is the sub-phase that lands first, and if the sub-phases run out of order the one that lands first
writes them while `8a` records that it consumed rather than wrote them. **Both designs must say which side
they are on** — the one that writes it and the one that adds a driver — so the harness is neither written twice nor left to each assuming the
other wrote it. A design that silently re-implements it, or one that assumes the other wrote it, is the
failure this risk exists to name; it is phase 7's `R11` in a subsystem where the shared artifact is a few
hundred lines rather than a few.

---

## Deviation Ledger

**Empty.** This document decides no deviation from the reference contract. Every mechanism substitution
phase 8 relies on is already catalogued in
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` — items 3 (`:18-22`, the
core-owned pivot), 4 (`:23-29`, cooperative cancellation and the producer-side orphan close), 5 (`:30-57`,
the three unsatisfied MUSTs, which are phase 8's to mark and not to re-argue), 7 (`:63-67`, the narrowed
stdlib, which binds only the phase-level task), 10 (`:77-81`, the wire-boundary re-validation that is
`DEF-25`) and 12 (`:87-91`, the stream-ownership rule) — and in §11 items 2, 5, 8, 12, 18 and 21, and is
cited above rather than re-argued. The sub-phase designs will have ledgers of their own; a deviation
decided by any of them is numbered `P8-<n>` and consolidated into design §10. Two are already foreseeable
and are named in `R1` and `R4`.

**The `P8-<n>` band allocation, fixed here 2026-09-12 because three documents stated it three different
ways.** The sub-phase designs were written concurrently and could not coordinate, so each reserved a
block; `8a`'s ledger preamble said `8b` had `P8-20`–`P8-39` and `8c` "`P8-40` onward", `8c`'s said `8a`
had `P8-1`–`P8-20` and `8b` `P8-21`–`P8-35`, and `8b`'s — narrowed by its own verification pass on
2026-09-12 — said `P8-1`–`P8-19` / `P8-20`–`P8-35` / `P8-36`–`P8-40`. **`8b`'s is the allocation, widened
at the top so `8c` has headroom**, and it is the one every phase-8 document now carries:

| Sub-phase | Reserved | Used | Free inside the band |
|---|---|---|---|
| `8a` | `P8-1`–`P8-19` | `P8-1`–`P8-14` | `P8-15`–`P8-19` |
| `8b` | `P8-20`–`P8-35` | `P8-20`–`P8-25` | `P8-26`–`P8-35` |
| `8c` | `P8-36`–`P8-50` | `P8-36`–`P8-40` | `P8-41`–`P8-50` |

A gap in a phase-local numbering is harmless; a three-way collision at filing time is not, and a ledger
id is cited from source comments and tests and can never be renumbered. **`P8-41` is not a used id**:
`8c`'s plan proposed one for its require-set correction and `8c`'s verifier retired it on 2026-09-12
before any `docs/deviations.md` row existed, on the ground that declining to write two `require` lines a
phase-0 gate rejects is neither deliberate nor a difference from the reference contract. Nothing cites
it, no id is reused, and `P8-41`–`P8-50` stay unallocated.

**What this document found is not a deviation and is filed as such.** Verified fact 1 — `Net::HTTP`'s
built-in retry — does not make the port differ from the reference contract; it makes the port **conform**
where three design sentences say conformance is free. Disabling `max_retries` is what `TRANSPORT-2`
requires, and the design's error is an erratum about a library, not a decision about a requirement. That
is why it is `OI-34` and not `P8-1`. The same reasoning covers verified facts 5, 9 and 12: each changes
what a sub-phase must *do* and none changes what the port *claims*.

**One refinement to the roadmap, stated here because the roadmap requires a corrected cell to be corrected
in place with the correction stated.** It is a **correction**, not a refinement — phases 3, 4 and 6 each
found a stated reason false and this one does too, at the level of the cut itself rather than of its
rationale. The exact replacement text is under *Roadmap follow-through owed*; the argument is under *The
roadmap's forecast, tested rather than deferred to*. **Filed as a roadmap correction and not as an open
item, and the judgement is deliberate**, on the reasoning phases 6 and 7 both gave: `OI-1`, `OI-2`,
`OI-12`, `OI-15`, `OI-21`, `OI-29` and `OI-31` each record a sentence that reads correctly and resolves to
something that is not there. The phase-8 bullet resolves to something that *is* there and is wrong about
it, which is what correction-in-place is for. `OI-34` is filed separately because its subject is a **frozen
design chapter**, which no phase may correct in place.

**Three consequences outside this document's own scope to fix, recorded so they are not discovered later.**

- **The roadmap edit itself is owed**, all three parts. This document is constrained to write one file.
- **`CLAUDE.md`'s phase-directory claims sentence is owed**, and goes stale the moment this file is filed.
- **The `knowledge-lookup` audit-group table is owed two rows**, phase 7's and phase 8's, both given
  above.
