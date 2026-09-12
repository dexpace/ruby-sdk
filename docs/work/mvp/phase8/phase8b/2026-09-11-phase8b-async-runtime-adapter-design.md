# Phase 8b — The async-runtime adapter

**Status:** Draft, for review. Written 2026-09-11, against
`docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`, which is this sub-phase's charter.

**Path:** `docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-design.md`. That is the
path this document carries for the rest of its life and the one every citation of it should use. Its plan
is `docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter.md`; the checklist is written at
execution time and is not this document's to draft.

## Purpose

Sub-phase 8b builds **`dexpace-async-thread`**: a fixed-size `::Thread` pool over a bounded
`::Thread::SizedQueue` that supplies the first real implementation of `SEAM-18`'s caller-supplied executor
duck type, settles phase 2's core-owned pivot from a real producer for the first time, carries the
`ASYNC-15`–`ASYNC-17` lifecycle over `Dexpace::Closeable`, performs the `ASYNC-8`–`ASYNC-12` diagnostic
hop over `Fiber[]`, and ships `ASYNC-18`'s scheduled delay. **Nineteen requirement IDs, all `ASYNC` —
`ASYNC-1`–`ASYNC-5` and `ASYNC-7`–`ASYNC-20`: 15 MUST, 4 SHOULD (`ASYNC-7`, `ASYNC-8`, `ASYNC-16`,
`ASYNC-17`), no MAY** — plus **two cross-reference rows with no budget line**, `PIPE-33` (phase 4's ID,
whose interrupt clause's antecedent becomes real here) and `ASYNC-6` (`8c`'s ID, quantified over "each
adapter").

It is also the sub-phase where **§10.5's three MUSTs get their antecedent**. Phase 4's segmentation design
states it exactly: "In phase 4 the executor is a duck type with no implementation, so no worker exists to
fail to interrupt. `dexpace-async-thread` is what makes the antecedent real"
(`docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md:685-687`). `ASYNC-3` is carried ⏳ citing
`DEF-18`; `ASYNC-4` is N/A citing §10.5 and **no register row**; `PIPE-33`'s interrupt clause is
re-asserted and keeps its phase-4 row. **8b does not re-open that trade and this document does not
re-argue it.**

**Three things this document measured rather than inherited, and the sharpest of them inverts a premise a
naive implementation would never test.**

- **A pooled worker leaks the *pool's own build-time* diagnostic context into every caller's task, if the
  install is a merge.** Verified fact 8: a pool built while `Fiber[:tenant] = "assembly"` was set, driven
  by a caller whose own context has no `:tenant` at all, runs the task with `tenant: "assembly"` visible —
  through phase 5b's `Diagnostics.with` exactly as that document writes it. That is `ASYNC-10`'s "a stale
  snapshot from when it was assembled", arriving through the one mechanism nothing else in the repository
  exercises, and it is invisible in every test that builds the pool in the same context it submits from.
  `R8` and `R9` both turn on it, and the repair is one line at worker start.
- **A pooled worker does not see a context set after the worker started** (verified fact 7), which is the
  fact that makes `ASYNC-10`'s per-submission capture the live obligation and `ASYNC-12`'s
  thread-creation transfer the dead one — the inverse of what `Fiber[]`'s inheritance suggests.
- **`::Thread::Queue#pop` returns `nil` for a timeout, for a closed queue and for a pushed `nil` alike**
  (verified fact 4), so the pool's own shutdown drain cannot tell "the budget elapsed" from "the queue
  closed" by the return value. Phase 2 recorded the same fact for the pivot's wake-up queue; 8b is the
  second place in the repository where it decides a control-flow branch, and a naive drain loop written
  against it reports a timeout as a clean shutdown.

Five decisions the charter named and declined to make are made here — **`R8`, `R9`, `R10`, `R11` and
`R12`** — each under its own heading below.

## Governing documents

- `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md` — the charter. It fixes `8b`'s 19 IDs and
  two cross-reference rows, the twenty spec-forced boundaries, the six rejected cuts, the four convergence
  points (of which `8b` owns one side of one), the five phase-level tasks (of which `8b` owns none), and
  risks `R8`–`R12`.
- `docs/product-spec/18-asynchronous-runtime-adapter-contract.md`, **read in full (46 lines)**, together
  with `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md:589-608` for the canonical
  text and modal level of all 19 IDs. Every one of the 19 appears in its own prose chapter, so appendix C
  is a convenience here rather than a necessity — and the chapter's `*Conformance:*` clauses, which
  appendix C drops, are load-bearing in six places named below.
- `docs/product-spec/03-pluggable-seams-and-extension-model.md` — `SEAM-16` (`:17`), `SEAM-17` (`:18`),
  `SEAM-18` (`:19`), `SEAM-30` (`:20`), `SEAM-24` (`:45`) and `SEAM-25` (`:44`). The seams `8b` implements
  against and phase 2 built.
- `docs/product-spec/08-execution-pipelines.md:40` — `PIPE-33` and `PIPE-34`, read for the
  cross-reference row's exact clause.
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.3 in full (`:189-294`) — the core-owned
  pivot, the two objects, `#value`'s queue pop, the check-after-resume rule, `Completer#on_cancel`, the
  two MVP gems that settle the pivot from two directions, `ASYNC-7`'s README obligation, and cancellation
  and deadlines end to end. **The `dexpace-async-async` mapping at `:252-254` is post-v1 (`DEF-11`) and is
  not `8b`'s.** And §3.7 in full (`:452-518`) — the `#close` duck type, the latch held across the flip
  only, the construction-time `@owned` boolean, the non-blocking-shutdown constraint stated **for this gem
  by name**, and `close_quietly`'s two disposal routes.
- `docs/sdk-design-ruby/05-pipeline-architecture.md` `:192-199` — the executor duck type as `#post { … }`
  with core shipping no implementation, and the async-to-sync bridge as `future.value(deadline:)`.
- `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1 (`:136-142`, fiber storage as the
  carrier, `Fiber[]`'s inheritance across a new `Thread`, and the sentence that fixes this gem's shape:
  "`dexpace-async-thread` saves the worker's prior storage, installs the captured snapshot for the work's
  duration and restores it in an `ensure`") and §8.3 in full (`:195-231`, the clock, the cancellable queue
  wait, and the prohibition that causes §10.5's three MUSTs).
- `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md` §9.2 (the gate table and the warnings-fatal
  rule) and §9.3 (`:65-113`) — Minitest as the framework, `dexpace-conformance`'s framework-agnostic
  assertion objects, and **appendix B.7's restatement**, which is `8b`'s: "`ASYNC-4` is vacuous by
  construction and **`ASYNC-3`'s item is recorded as *failing* rather than vacuous**, since
  `dexpace-async-thread` supplies the blocking-task-on-a-worker antecedent the requirement conditions on";
  "`ASYNC-1`/**2**/**5**/**6**/**13**/**14**/**18**/**19**/**20**/**22** are exercised against the pivot,
  `ASYNC-8`–`ASYNC-12` against fiber storage, and `ASYNC-15`–`ASYNC-17` against §3.7".
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.1 (`:24`, this gem's one-line charter: "The
  zero-third-party async driver: a bounded worker pool over `Thread`/`Thread::SizedQueue` that satisfies
  **SEAM-18**'s caller-supplied-executor contract and settles the core pivot"), §2.3 (`:39-70`, the layout
  and the registration-time skew assertion) and §2.4 (`:71-107`, the zero-dependency rule, what "standard
  library" means in Ruby, and the single-instance guarantee).
- `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items **3** (`:18-22`, the
  core-owned pivot — `8b` bridges to it and never replaces it), **4** (`:23-29`, cooperative cancellation
  and the producer-side orphan close) and **5** (`:30-57`, §10.5 in full — `ASYNC-3`, `ASYNC-4` and
  `PIPE-33`, whose split is fixed and which `8b` marks rather than re-argues).
- `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` item 2
  (`:10-12`, `NFR-11` versus `SEAM-17`) and item 21 (`:73-78`, `ASYNC-21`'s adapter-scoped MUST — `8c`'s,
  not `8b`'s).
- `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:42`, the `ASYNC` row, read verbatim:
  "**Not satisfied:** ASYNC-3 (§10.5). *Vacuous:* ASYNC-4 (§10.5); ASYNC-21 … *Deferred:* none. *Notes:*
  ASYNC-15–ASYNC-17's lifecycle in §3.7"; and the MUST-level summary (`:49-55`).
- The predecessor documents whose forward tables this document cites rather than re-derives:
  `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md`,
  `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md`,
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md`,
  `docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-design.md`,
  `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`,
  `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`,
  `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md`,
  `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`,
  `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md`,
  `docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md`.
- `docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-design.md` as the closest worked example
  of this document's form, and the most recent sub-phase design to ship a second real gem.
- `docs/deferred-items.md` (`DEF-1`, `DEF-11`, `DEF-12`, `DEF-18`, `DEF-21`, `DEF-27`, `DEF-28`, `DEF-29`,
  `DEF-31`, `DEF-32`, `DEF-33`), `docs/open-items.md` (`OI-8`, `OI-13`, `OI-18`, `OI-22`, `OI-26`),
  `docs/deviations.md`, `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

---

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written, and re-run for
this document rather than trusted from the charter's report.

`ruby scripts/knowledge.rb --origin note --brief` returns **38 entries across 19 note files**.
`ruby scripts/knowledge.rb --section conflicts --brief` returns **24 entries across 17 topic files, 18 of
them notes and six harvested**, and **all six harvested ones print `[overridden by notes/…]`**
(`data-modeling/35fde90f`, `module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and
`/8c0687bf`, `tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`). **None is open**, so `8b`
inherits no unresolved conflict and owns no conflict decision of its own. Narrowed to this sub-phase's one
prefix, `--section conflicts --prefix ASYNC --brief` returns the CLI's no-matching-entries message: **no
recorded styleguide-versus-design conflict touches an `ASYNC` ID.**

**Corpus coverage: complete.** `ruby scripts/knowledge.rb --prefix-info ASYNC` reports **22 of 22 IDs
substantive, 0 roll-up only, 0 uncited**, owning chapter
`docs/product-spec/18-asynchronous-runtime-adapter-contract.md`. `ruby scripts/knowledge.rb --gaps ASYNC`
closes with 0 of 22. **`8b`'s spec-reading budget is zero**, which the next section states in the form the
roadmap requires.

**The audit groups run, and what each found.** The charter's owed row —
*Transport and async-runtime adapters* — is still owed to `.claude/skills/knowledge-lookup/SKILL.md` and is
not this document's to add. What was run, narrowed to `8b`:

| Audit group | Query as run | Result |
|---|---|---|
| *Fiber scheduler, thread safety* | `--prefix ASYNC --section rules` (25 entries, 3 topic files, **zero roll-up-tagged**); `--topic concurrency-and-async --section rules --brief` (**75** entries, 1 file); `--topic concurrency-and-async --section constraints,conclusions --brief` (30 entries); `--chapter 9 --brief` (51 entries) | The `--topic` form is the one that matters and the `--prefix` form alone would have missed it: **50 of the 75 rules carry no `ASYNC` ID at all** — they are the styleguide's concurrency chapter, including all six the charter routes to this gem by name. A `--prefix`-only audit of this sub-phase reports clean over a third of its rules |
| *Gem layout, zero-dependency core* | `--topic package-and-dependency-layout --section rules,constraints --brief` (14); `--prefix SEAM --section rules --brief` (38 across 11 files) | Clean. `package-and-dependency-layout/fa303aa7` (zero `add_dependency` in core) and the single-instance entry are what `8b`'s skew assertion answers; `SEAM-18`'s no-default-executor rule is `R12`'s binding constraint |
| *Public API surface* | `--topic api-design,http-domain-model,documentation,module-organization,error-handling --section rules --brief` (150 across 5 files) | Two rules bite and are answered in the object model: `api-design/b0e18938`'s minimal-surface rule (why there is no `#pending`, no `#active` and no saturation-policy knob) and **`module-organization/d1bdfecf`** ("module nesting should stay shallow — three path segments is a smell"), which `Dexpace::Async::Thread::Pool` is four of |
| *RBS / Steep typing* | `--chapter 3 --section rules --brief`; `--topic type-system,data-modeling --section rules --brief` (86 across 2 files) | Clean. `type-system/545949a5` and `/169c8f38` are the Sorbet-versus-RBS notes, already settled; nothing narrows `8b`'s `sig/` beyond `NFR-11` |
| *Minitest conventions* | `--topic testing,assertions --section rules --brief` (29 across 2 files); `--chapter 11 --section rules --brief` | Two rules shape the suite. **`testing/4ef070df`** — "every test must run alone, in any order, and pass; build every mutable fixture fresh per test … never override Minitest's randomized test-order seed" — is what forces every test touching `Fiber[]` to restore the slot in a `teardown`, and what forbids a module-level shared pool. **`testing/7b383289`** pins a property test's seed, which `8b` needs for its contention test |
| *Resource lifecycle and stream ownership* | `--topic resource-management --section rules --brief`; `--chapter 13` | `resource-management/d1f16cad` is `8a`'s, not `8b`'s — `8b` owns no socket and sets no I/O timeout. The block-form acquisition rule reaches only `Diagnostics.with`, which already has that shape |

**The charter's roll-up warning holds and matters here.** `--prefix ASYNC --brief` returns 64 entries of
which **22** are `[appendix-B roll-up]` — 34%. Every query above therefore carried `--section`; a bare
`--req` was used nowhere in writing this document, and the `--req` calls that were made carried
`--section rules,constraints,conclusions`.

**The entries `8b` is built on, cited by key rather than restated**, except where the rule turns on the
sentence:

- **`concurrency-and-async/f414b864`** — the `concurrent-ruby` substitution note, and the one that routes
  work *to* this gem by name. Its closing paragraph is `R12`'s whole subject and is quoted there.
  <sub>review · `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` · high · sha:manual-phase2-no-concurrent-ruby</sub>
- **`concurrency-and-async/611b9392`** — check-after-resume, stated as a MUST on every async adapter:
  "after returning from any operation that may have suspended (an I/O wait, a scheduler yield, **a queue
  pop**, a task await), and before acting on the value it produced, the producer MUST re-check its
  cancellation state". The worker's `::Thread::Queue#pop` **is** a queue pop, and `R10` is where that is
  cashed in.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:239-244` · high · sha:bf7f85fc5f18</sub>
- **`concurrency-and-async/65882a70`** — `SEAM-25` in one sentence: "only the first close shuts the owned
  executor and emits the lifecycle event; closing MUST NOT be required to cancel in-flight requests (a
  graceful drain is acceptable), and an adapter over a caller-supplied executor MUST NOT shut it down".
  Every clause of `ASYNC-15`/`ASYNC-16` and all of `DEF-31` is in it.
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:44-44` · high · sha:0adae2d6a47f</sub>
- **`concurrency-and-async/74aee9a8`** — `ASYNC-7`'s answer, already fixed by the design: "the thread
  adapter lets an in-flight blocking read finish while reactor-backed adapters abort at the next scheduler
  checkpoint". `8b` writes that sentence into its README and does not re-decide it.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:254-257` · high · sha:bf7f85fc5f18</sub>
- **`concurrency-and-async/08a0e08d`** — the executor duck type: "`#post { ... }` and ships no
  implementation; the `dexpace-async-thread` gem supplies a bounded `Thread::SizedQueue` pool". The
  signature is fixed here and `8b` may not widen it.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:192-194` · high · sha:6b7ebc1dfd1d</sub>
- **`concurrency-and-async/a1ec6ce4`** — "The sync-to-async bridge requires a caller-supplied executor with
  no default, because a shared global pool would be starved by blocking work." The reason `Pool.build`
  has no module-level singleton and no `.default`.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:191-193` · high · sha:6b7ebc1dfd1d</sub>
- **`concurrency-and-async/e94924e3`** — the mutex guarding a latch "is held only across the consumed-flag
  flip and never across the drain, because Ruby's `Mutex` is per-fiber-owned and non-reentrant, so a lock
  held across a suspension point inside a drain would deadlock two fibers of one thread". `8b`'s close latch
  and its timer are the two objects the rule binds, and verified fact 9 is why it is load-bearing here
  rather than stylistic.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:108-112` · high · sha:bf7f85fc5f18</sub>
- **`concurrency-and-async/c0fab747`** — protect only the smallest critical section, "since a coarse lock
  spanning an I/O call couples concurrency and latency and risks deadlock". The table under *Thread-safety
  proof obligations* is this rule discharged object by object rather than asserted.
  <sub>styleguide · `styleguide/ruby/09-concurrency.md:101` · high · sha:bb7cce1169e7</sub>
- **`concurrency-and-async/2c743901`** and **`/16ceb098`** — model cross-thread payloads as immutable
  `Data` value objects rather than a `Hash` or a `Struct`, and document the invariant at the boundary.
  `Pool::Job` is a frozen `Data` for exactly this, and the boundary comment names the invariant.
  <sub>styleguide · `styleguide/ruby/09-concurrency.md:251-255` · high · sha:bb7cce1169e7</sub>
- **`concurrency-and-async/257d79cb`** — "A transport blocked inside an uninterruptible C-extension read …
  cannot be aborted early by any mechanism this port permits, so the worker occupies its pool slot until
  the read returns on its own." This is `R10`'s residual, already recorded, and `8b` neither widens nor
  narrows it.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:210-213` · high · sha:6b7ebc1dfd1d</sub>
- **`observability/698552b4`** and **`observability/65191069`** — the two notes that bind `8b` through its
  own prefix. The first is `OI-13`'s warned setter; the second carries two findings `8b` would otherwise
  get wrong (copy-on-write protects the slot, not the object in it; `Fiber#storage=` refuses a `String`
  key while `Fiber[]=` coerces one) and names `ASYNC-8`–`ASYNC-12` as its consumers. **Its own caveat is
  `8b`'s to clear**: it was verified on 3.4.10 only and says so.
  <sub>review · `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md` · high · sha:manual-phase5-fiber-slot-and-key-type</sub>
- **`pipeline/f02559b9`** — `raise error, cause: nil` is the spelling for re-raising an error a component is
  *carrying*. `8b` has exactly one re-raise site and it is not that shape; the paragraph under the object
  model says which and why.
  <sub>review · `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` · high · sha:manual-phase4b-reraise-cause</sub>
- **`module-organization/64e84d64`** — "Define nested constants using the full `module`/`class` nesting
  form rather than compact path syntax, because the compact form causes Ruby to resolve un-prefixed names
  against only the file's top-level lexical scope." Verified fact 14 shows this rule is what *creates*
  `8b`'s shadowing hazard, and `Dexpace/QualifiedCoreConstant` (`P2-8`, extended by `P3-7`) is what
  catches it.
  <sub>styleguide · `styleguide/ruby/12-module-organization.md:109-137` · high · sha:a7709c006923</sub>

**One knowledge note is filed by this document's plan.** Its subject is verified facts 7 and 8 — that a
pooled worker inherits the *pool creator's* fiber storage and sees nothing set afterwards, so a
merge-shaped install leaks assembly-time context into a caller's task. It is drafted under *The knowledge
note `8b` files* below, as a `## Reference` entry under `docs/knowledge/notes/observability.md` beside
`observability/65191069`, because it does not contradict that rule — it adds the consequence the rule's
"copy-on-write protects the slot" sentence does not reach.

## The spec-reading budget

**Zero, and stating that is the obligation.** The roadmap requires a phase whose IDs come back as gaps to
budget reading time in its design document and say so there
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:154-155`); `--gaps ASYNC` reports 0 of 22, so the
budget is zero and this sentence discharges the obligation.

**What that does not license.** `--gaps` measures *corpus* coverage, not *specification* coverage
(`OI-12` states the same asymmetry from the other side). Chapter 18 was read in full anyway, at 46 lines,
and the `*Conformance:*` clauses appendix C does not carry are load-bearing in six places, each quoted
where a decision turns on it:

1. `ASYNC-2` — "submit through a **shut-down** executor; assert the returned future completes exceptionally
   with the rejection." The clause names the shut-down case and not the saturated one, which is what makes
   `R12`'s saturation policy a decision rather than a reading.
2. `ASYNC-4` — "concurrency stress racing cancel-with-interrupt against completion on a small pool with a
   sentinel unrelated task; assert the sentinel is never interrupted and every reused thread hands back
   with a clear flag." A test that cannot be written on a port with no interrupt, which is what "vacuous"
   means concretely here.
3. `ASYNC-5` — "cancel the future in the window **after the worker produces a Response but before
   delivery**; assert `close()` invoked exactly once." A window `8b` must be able to open deterministically,
   which fixes the fake transport's shape.
4. `ASYNC-9` — "install context on a worker **that already has one**, run a task that **throws**, assert
   the worker's pre-existing context is intact after the task returns **and after it throws**."
5. `ASYNC-10` — "assemble under context A, subscribe/execute under B → log lines carry B; re-subscribe
   under C → C." The three-context sequence verified facts 7, 8 and 9 are measured against.
6. `ASYNC-15` — "close twice → shut once, one side-effect; **a BYO executor passed to a bridge is never
   shut down**; interrupt the closing thread during a blocking shutdown and assert it returns promptly."
   The middle clause is the assertion that makes `8b`'s pool and phase 2's bridge two objects rather than
   one.

---

## Scope: the 19 IDs

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `ASYNC-1`, `ASYNC-2`, `ASYNC-5`, `ASYNC-7`–`ASYNC-20` | 17 |
| ⏳ not satisfied — `DEF-18`, §10.5 | `ASYNC-3` | 1 |
| N/A — vacuous, §10.5, **no register row** | `ASYNC-4` | 1 |
| **Total in budget** | | **19** |
| Cross-reference rows, no budget line | `PIPE-33` (phase 4's), `ASYNC-6` (`8c`'s) | 2 |

Level split, derived mechanically from appendix C on 2026-09-11 and matching the charter's: **15 MUST, 4
SHOULD (`ASYNC-7`, `ASYNC-8`, `ASYNC-16`, `ASYNC-17`), 0 MAY.** No `MUST NOT` row appears. **No `DEF-<n>`
moves an ID into `8b` and none moves one out.**

### Twelve rows carry a clause the checklist must state rather than tick

Each is on the authority of a design chapter, a measured fact, or a requirement's own conditional
antecedent — never on `8b`'s convenience.

- **`ASYNC-3` is ⏳ and the row says so in full.** The text the checklist carries:

  > Not satisfied and not claimed to be. `dexpace-async-thread` supplies the blocking-task-on-a-worker
  > antecedent, so the requirement applies and is not vacuous. **Cancel-without-interrupt is met exactly**
  > by `Dexpace::Async::Future#cancel`; **cancel-with-interrupt is `Thread#raise`**, forbidden
  > repository-wide by design §8.3 and by phase 0's `Dexpace/NoThreadInterrupt` cop. The third clause — "a
  > task still queued (not yet started) or already finished MUST NOT be interrupted" — holds because
  > nothing is ever interrupted. §10.5's split is settled and is not re-opened here. `DEF-18` carries the
  > mechanism and its pick-up condition ("if an interruptible transport path is ever adopted"). Appendix B
  > records this item as **failing, not vacuous** (§9.3, B.7), and the port's own build suppresses it
  > through a named waiver listing `ASYNC-3`.

- **`ASYNC-4` is N/A and cites no register row.** `DEF-18`'s `Cites:` line is `ASYNC-3, PIPE-33`
  (`docs/deferred-items.md`), and §10.5 holds `ASYNC-4` *vacuous* rather than deferred: "a port that never
  delivers an interrupt cannot produce the hazard, so the guarantee holds — and holds more strongly than an
  implementation of the handshake would provide, since a handshake narrows a window it does not close." The
  row cites §10.5 and §9.3's B.7 restatement and **must not** cite `DEF-18`. The roadmap's cross-cutting
  constraint 8 says "phase 8 marks all three ⏳ citing it"; the charter corrects that sentence in place and
  `8b` follows the correction.
- **`ASYNC-7`'s answer is already fixed and `8b` writes it rather than deciding it.**
  `concurrency-and-async/74aee9a8`: the thread adapter lets an in-flight blocking read finish. The row is
  satisfied by a required README section (`gems/dexpace-async-thread/README.md`) plus a test that
  demonstrates the documented outcome against a transport double that ignores cancellation. The
  *cross-adapter contrast* the requirement is ultimately about is the charter's convergence point 3 and
  belongs to `8c`; `8b` owns the ID and writes only the thread half.
- **`ASYNC-12`'s antecedent is false for a freshly spawned thread and true for a pooled worker, and the
  row states which.** `R9` in full. Verified fact 6: a new `::Thread` **does** inherit `Fiber[]`, so the
  requirement's stated antecedent — "runtimes where a newly created worker does not inherit the spawning
  thread's logging context" — is false at the thread-creation boundary. Verified fact 7: a worker created
  *before* the context was set sees nothing, so the live obligation is `ASYNC-10`'s per-submission capture.
  **The row must not record ✅ on the strength of a property `Fiber[]` provides for a case the requirement
  is not about.**
- **`ASYNC-13`'s unwrap is the identity function, because no wrapper type exists.** Phase 2's
  `Completer#fail(error)` stores the object and `Future#value` re-raises *that object*; `8b` introduces no
  wrapper of its own and does not use `Thread#value` (which would also be identity-preserving — verified
  fact 13). The row states that the "terminate on the first non-wrapper cause" clause is satisfied by there
  being no wrapper, that the null-cause and cycle clauses are unreachable, and that the assertion is
  `assert_same` on the object the transport raised. `Dexpace.each_cause` (phase 4b) is the repository's
  cycle-safe walk and `8b` calls it nowhere.
- **`ASYNC-14`'s interrupt-flag clause is vacuous and the rest is exercised, not built.**
  `Dexpace::Bridge::SyncOver` is phase 2's (`P2-4`): "restore the interrupt flag" is vacuous for the same
  reason `ASYNC-4` is, and "surface an interrupted-I/O failure" is read as a typed
  `Dexpace::CancelledError` rather than an `::IOError`. `8b` is the first sub-phase that can drive the
  bridge end to end over a real worker and does exactly that; it ships **no second bridge**.
- **`ASYNC-15`'s clause (c) is vacuous and its substance is met by a different mechanism.** "Interrupt-safe
  — honors thread interruption on any blocking shutdown step": there is no interrupt to honour. What
  remains real is `XCUT-13`'s "MUST NOT block on interrupt-sensitive waits", and §3.7 states the
  consequence **for this gem by name**: "close signals its queue and returns, it does not join workers under
  a `Kernel#sleep` or an unbounded `Thread#join`." The row states that the bounded drain is what discharges
  it and names `DEFAULT_SHUTDOWN_TIMEOUT`.
- **`ASYNC-15`'s clause (b) is satisfied at the bridge, not at the pool, and the row says where.**
  `cross-cutting-invariants/093b7681` requires "two differently named entry points, one that builds the
  resource and one that borrows it". **The pool has one**, `.build`, and is always `owned: true`, because a
  pool that borrowed its threads is not a thing that exists — the threads are created by the pool or they
  are not the pool's. The ownership clause's real subject is `Transport.async_over(t, executor: pool)`,
  which phase 2 ships with `owned: false` and which `8b` asserts: closing the bridge does **not** close the
  pool, and the pool is still usable afterwards.
- **`ASYNC-16`'s escalation clause has no mechanism and holds vacuously.** "escalating to a forceful
  shutdown only if the closing thread is itself interrupted" — forceful shutdown of a Ruby worker is
  `Thread#kill`, which is forbidden, and there is no interrupt to trigger the escalation. The antecedent
  never fires, so the clause holds on `ASYNC-4`'s argument. The graceful half — stop accepting new work,
  let in-flight tasks finish — is met exactly and is what the conformance clause tests ("start an in-flight
  request, call close, and assert it completes rather than being interrupted").
- **`ASYNC-17` is the SPI's default and is phase 2's; `8b` supplies the overriding implementation.** The
  row states both halves: a lambda-shaped async transport constructs and its `#close` is a safe no-op
  (phase 2, asserted again here through the bridge), and an implementation that owns resources overrides it
  to follow `ASYNC-15` — which is `Pool#close`. "Behavior of executeAsync after close is undefined" is
  taken explicitly as `SEAM-15`'s rule instead: `#post` after close raises `Dexpace::ClosedError`.
- **`ASYNC-18` is satisfied under a stated reading and carries a deviation row.** `R11` in full, `P8-25`.
  "Without blocking a thread" is satisfied for the *caller's* thread and for every *worker* thread and is
  **not** satisfied absolutely: one timer thread is parked per pool that has ever scheduled a positive
  delay. The row states the reading, names the thread, and names `Dexpace::Async.delay` (`CFG-18`, phase
  5a) as the zero-thread alternative available to a caller running under a `Fiber.scheduler`.
- **`ASYNC-19` is satisfied by adding nothing.** The requirement's failure mode is "being dropped by the
  SPI's options-ignoring default overload". `8b` ships **no overload that accepts per-call options**: its
  only entry points are `Pool.build`, `#post`, `#delay` and `#close`, none of which takes a
  `Dexpace::RequestOptions`. The row states that, and the assertion is end to end — the exact
  `RequestOptions` object the caller passed to `Transport.async_over(...)#call` arrives at the wrapped
  transport, asserted with `assert_same`, across the thread hop.

### The two cross-reference rows, with no budget line

- **`PIPE-33`** — phase 4's ID. Its five clauses are enumerated in
  `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md:151-165`; four are met and
  clause 5 ("cancelling the returned future with interruption MUST interrupt the worker running the
  in-flight send") is not. `8b` is what makes clause 5's antecedent real. Phase 4's own treatment governs:
  "Phase 8's disposition is therefore a **re-assertion at the point the requirement starts applying, not a
  second decision**" (`docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md:687-689`). The row
  keeps its phase-4 ⏳, cites `DEF-18`, and adds what `8b` contributes: clauses 2 and 3 are re-asserted end
  to end through a real pool (exactly one `#post` for a multi-step pipeline; the identical options object
  arrives), and clause 4 is demonstrated against a running worker rather than a synchronous fake.
- **`ASYNC-6`** — `8c`'s ID, quantified over "**each** adapter" with a per-adapter conformance clause. `8b`
  states the thread-pool half explicitly so its absence is a decision rather than an oversight: **cancelling
  the pivot reaches the worker only at its next check-after-resume point**, which is `ASYNC-3`'s
  unsatisfied mode under a second ID and not a second decision (§10.5, `DEF-18`). The other direction —
  "cancelling the runtime-native primitive MUST cancel the canonical future" — has no subject here: this
  adapter exposes no runtime-native primitive to the caller. A `::Thread` is not handed out, `#post`
  returns `nil`, and the only handle a caller holds is the pivot itself. `SEAM-24`'s second sentence
  (a *caller-facing* cancellation bridge) is `DEF-11`/`DEF-1` and post-v1; design §3.3 (`:252-254`) assigns
  it to `dexpace-async-async`.

### What `8b` additionally ships, without owning a new ID

- **The first real implementation of `Dexpace::Page::_Executor`.** Phase 7c assigns it here by name: "the
  one-method `#post { }` duck type `PAGE-29`'s executor mode takes. The first real implementation is phase
  8's; `7c` ships only a test double, and core spawns no thread"
  (`docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md:1320`). The interface is
  core-declared and `8b` did not write it — `interface _Executor; def post: () { () -> void } -> void; end`
  (`…phase7c…-design.md:871`) — which is an `NFR-3`/`NFR-11` surface `8b` inherits. `R12` states how the
  pool's `#post` signature relates to it: **it is that interface exactly, not a superset.**
- **`DEF-1`'s `SEAM-24` first-sentence amendment.** `SEAM-24`'s first sentence — "propagate the ambient
  logging/diagnostic context across the thread handoff" — is `ASYNC-8`'s and `8b` implements it through
  `Fiber[]`, within fiber storage. The charter proposes the register amendment; `8b` supplies the fact it
  rests on and **performs no register edit**. What stays deferred is §12's "beyond fiber storage" scope and
  `SEAM-24`'s second sentence proper.
- **`DEF-31`'s lifecycle event, closed.** Phase 5b shipped `Events::INSTRUMENTATION_SHUTDOWN` and stated
  that "the first thing in this repository that actually **owns** an executor is phase 8's
  `dexpace-async-thread`". `8b` supplies the subject: the first — and only the first — `#close` emits it.
- **The gem's `README.md`**, which `ASYNC-7` makes a deliverable rather than a courtesy, and which the
  housekeeping probe's `readmes` check requires of every directory under `gems/`.
- **A second scratch bundle for `gates:clean_bundle`.** Phase 0's isolation run covers `dexpace-core` only.
  `8b` extends it to `dexpace-async-thread`, because this is the first gem in the repository whose `NFR-2`
  third-party budget is **zero by design** and therefore the first gem for which the run proves something
  the core run cannot: that an adapter activates with nothing but core in the bundle, on every Ruby in the
  matrix. Stated as an extension of an existing gate, not a sixteenth gate.
- **Its own test doubles**, in `gems/dexpace-async-thread/test/support/`. `8b` does **not** reach into
  `gems/dexpace-core/test/support/`; see the `DEF-29` disposition in the register sweep, which corrects a
  premise of the charter's.

### Canonical text quoted because a decision below turns on it

> **ASYNC-2** (MUST) — Every failure an adapter can detect while constructing the async operation MUST be
> delivered through the future's failure channel, never thrown synchronously from the method that promised a
> future. This includes request-adaptation errors and **worker-pool rejection (a saturated/shut-down
> executor)**.

> **ASYNC-9** (MUST) — When an adapter reinstates a captured logging context on an executing or callback
> thread, it MUST **first save that thread's prior context**, install the captured context **only for the
> duration of the work**, and **restore the prior context afterward — including when the work throws** — so
> a reused/pooled thread's own logging context is never clobbered.

> **ASYNC-10** (MUST) — When an adapter propagates logging context, capture MUST occur at the point that
> identifies the logical caller of the execution — per-subscription for cold/reusable stream or promise
> objects, and **per-task-submission for executor decorators** — not at object-construction/assembly time.
> **A reused async object MUST pick up the live context of each use rather than a stale snapshot from when
> it was assembled.**

> **ASYNC-15** (MUST) — An adapter that owns an executor or background threads MUST expose a close/dispose
> operation that is (a) **idempotent** — repeated calls are safe and only the first performs
> shutdown/side-effects; (b) **ownership-aware** — it releases only SDK-owned resources and never shuts down
> a caller-supplied executor/client; and (c) **interrupt-safe** — it honors thread interruption on any
> blocking shutdown step.

> **ASYNC-18** (MUST) — The non-blocking scheduled-delay primitive used to insert async delays into a
> future chain MUST complete after the requested delay **without blocking a thread**, MUST complete
> immediately for a zero delay, MUST reject a negative delay, and cancelling the returned future MUST
> cancel the underlying scheduled task **so no scheduler thread is held**.

> **SEAM-18** (MUST) — … wrapping a blocking transport as async **REQUIRES a caller-supplied executor**
> (there is intentionally no default, and a shared global fork/join-style pool is explicitly unacceptable
> because a blocking call would starve it) …

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `ASYNC-6` — bidirectional cancellation across each adapter | **`8c`**, which is the only sub-phase that can satisfy both directions. `8b` carries a stated cross-reference row |
| `ASYNC-21` — the reactive streaming source | **`8c`**, N/A by §11.21. `7b` explicitly declined the row and named phase 8's |
| `ASYNC-22` — concurrent async calls with per-call state in the completion graph | **`8c`**. `8b` ships no async *transport*; its pool's concurrency safety is asserted under `XCUT-11` and `PIPE-33` clause 2, not under `ASYNC-22` |
| `TRANSPORT-1`–`TRANSPORT-30` | `8a` and `8c`. **`8b` opens no socket, sets no I/O timeout, maps no header and adapts no native response** |
| `SEAM-16`, `SEAM-17`, `SEAM-30` — the async seam, the pivot, the orphaned-response close | **2, built** as `Dexpace::Async::Future`, `Completer`, `Settlement` and `Dexpace::AsyncTransport`. §10.3 and roadmap obligation 5 forbid replacing any of them. `8b` bridges to the pivot and ships no second future |
| `SEAM-18`'s two bridges | **2, built** as `Dexpace::Bridge::AsyncOver` and `SyncOver`. `8b` supplies the first executor the `async_over` direction has ever had and **ships no third bridge** |
| `SEAM-13`, `Dexpace::Cancellation`, `Cancellation::Source`, `.any`, `Subscription#detach` | 2. `8b` consumes the token and defines no reason type |
| `SEAM-14`, `SEAM-15`, `Dexpace::Closeable`, `Dexpace.close_quietly`, `Dexpace::ClosedError` | 2. `8b` includes `Closeable` and is the first raise site for `ClosedError` alongside `8a`'s transport |
| `SEAM-24`'s second sentence, `SEAM-28` | `DEF-1`, riding on `DEF-11` (`dexpace-async-async`), post-v1 |
| `SEAM-25`'s release half | 2. Only `DEF-31`'s **event** half closes here |
| `PIPE-1`–`PIPE-40` | 4c. `8b` installs no step, adds no stage and ships no pipeline. `PIPE-33` is a cross-reference row |
| `CTX-1`–`CTX-20`, `Instrumentation::Bundle`, `ContextStore` | 4a. **Nothing in `ASYNC` consumes any of it**: `ASYNC-8`–`ASYNC-12`'s subject is fiber storage, which is `OBS-23`/`OBS-24`'s carrier and not `CTX`'s store — phase 4a's own finding, re-confirmed from this side |
| `RECOV-1`–`RECOV-34`, `Dexpace::Outcome`, `each_cause`, `attach_suppressed` | 4b. `8b` folds no outcome and walks no cause chain |
| `CFG-15`–`CFG-21` — the clock, `Clock#sleep`, `Dexpace::Async.delay`, the `deadline:` keyword | 5a. `8b` consumes `Clock::SYSTEM#monotonic` for its own deadline arithmetic and re-decides nothing. **`CFG-20`'s unmet clause is `ASYNC-3`'s under a second ID (`OI-22`) and `8b` adds no fourth unsatisfied MUST for it** |
| `OBS-1`–`OBS-40`, `Diagnostics.capture`/`.with`, `Severity`, `Events`, `Logger`, `Instrumentation.contain` | 5b and 5c, built. `8b` calls four of them and builds none. **`OBS-23`/`OBS-24` are 5b's and 5c's; `ASYNC-9` is `8b`'s, and they are the same mechanism under two subsystems** |
| `OBS-28`, `OBS-29` — the `HTTPTracer` vocabulary | 5c. `DEF-42`'s transport-milestone group is `8a`'s subject to `R6`, and `Events::INSTRUMENTATION_SHUTDOWN` is deliberately **not** a twelfth tracer method (5b settled it) |
| `SERDE`, `SSE`, `PAGE` | 7. `8b` consumes **one** phase-7 artifact — `Dexpace::Page::_Executor` — and implements it; it ships no strategy, no codec and no event parser |
| `dexpace-conformance`'s gem, gemspec, assertion protocol and `TCPServer` fixture | `8a` (charter `R7`, `R16`). **`8b` writes no part of the harness**, needs no socket fixture, and hands `8a` the three assertion shapes named under *The interface surface later phases may cite* |
| `Dexpace::TransportError < ::IOError` | The **phase-level task**. It lands in `dexpace-core`, is consumed by `8a` and `8c`, and `8b` neither raises nor needs it |
| `XCUT-11`–`XCUT-23` | 9 dispositions them. `8b` satisfies `XCUT-11`, `XCUT-13` and `XCUT-22` by construction and adds no second rule |
| `NFR-1`–`NFR-17` | 0 built the machinery, 9 dispositions it. `8b` **spends no third-party `NFR-2` budget at all** and asserts nothing about the gates beyond extending one |

---

## Prerequisites, and the independence this sub-phase must state

**`8b` depends on `8a` and `8c` for nothing, and neither depends on `8b`.** The charter's finding — every
phase-8 boundary is a convenience — is stated here in `8b`'s own words rather than inherited, because the
charter requires exactly that of each sub-phase design ("a `8b` plan whose first task waits on `8a`'s
transport has re-imposed a chain nothing requires").

- **`8a` → `8b` is absent, and it is absent by dependency declaration rather than by luck.**
  `dexpace-async-thread`'s gemspec declares `dexpace-core` and **nothing else** (§2.1, phase 0's skeleton
  table). Its pool posts an opaque block; what the block does is the caller's business. Every `ASYNC`
  clause `8b` owns is provable against a ten-line transport double in `8b`'s own `test/support/`, and
  **nothing in `8b` opens a socket, needs a wire fixture, or names `Dexpace::Transport::NetHTTP`.**
- **`8b` → `8a` is absent.** `dexpace-transport-net_http` is a synchronous transport: it posts nothing,
  owns no executor, and takes phase 2's no-op close. The one place the two meet is
  `Transport.async_over(net_http, executor: pool)`, which is the charter's **convergence point 2** — a
  composed test that belongs to whichever of `8a` and `8b` lands second, and which is not a build-order
  edge. Each of `ASYNC-1`, `ASYNC-2`, `ASYNC-5`, `ASYNC-14`, `ASYNC-19` and `ASYNC-20` is provable inside
  `8b` alone against a double; the composed test proves the *composition*, and `8b`'s plan must not make
  any of its own tasks wait on it.
- **`8b` → `8c` is absent, and this is the edge a reader is most likely to invent.** `async-http` does not
  use a thread pool: it drives `Async::Task` under a `Fiber.scheduler`, and
  `dexpace-transport-async_http` declares `dexpace-core` and `async-http` — not `dexpace-async-thread` —
  and `NFR-2`'s budget would not permit a third declaration anyway. Verified fact 16 adds the mechanical
  half: **`Fiber.scheduler` is per-thread**, and a pool worker sees `nil` however the caller's thread is
  configured, so a reactor-native transport gains nothing from a pool and a pool gains nothing from a
  reactor.
- **`8c` → `8b` is absent.** `dexpace-async-thread` is a `SEAM-18` executor for wrapping a *blocking*
  transport. A reactor-native transport is already async and has nothing to wrap.
- **`8b` owns no side of the charter's convergence points 1, 3 or 4.** The conformance harness and the
  `TCPServer` fixture are `8a`'s (`R16`) and **`8b` writes no part of either and adds no path to them**,
  stated here so neither sibling design assumes `8b` did. `ASYNC-7`'s cross-adapter *contrast* (point 3) is
  `8c`'s conformance row; `8b` writes only its own README section. `Dexpace::TransportError` (point 4) is
  the phase-level task and `8b` neither raises nor needs it.

**A `8b` plan whose first task waits on anything from `8a` or `8c` has re-imposed a chain that does not
exist.** The recommended order `8a → 8b → 8c` is the charter's convenience and this document does not
re-argue it; if the order changes, nothing in `8b`'s plan needs to.

Every surface below was verified against the named phase's design on 2026-09-11. **Nothing is implemented
yet in this repository** — these are design commitments, and `8b` inherits them as such.

### From phase 0 — the workspace, on paper

- **The gem skeleton already exists**: `gems/dexpace-async-thread/` with `dexpace-async-thread.gemspec`
  declaring `dexpace-core` **and nothing else** (deviation `P0-9` — "nothing — core only, by design"), an
  entry file `lib/dexpace/async/thread.rb` defining `Dexpace::Async::Thread` and its `VERSION`, a `sig/`
  mirror, a `test/` tree with a `test_helper.rb` that puts **this gem's** `lib` on `$LOAD_PATH`, and a
  named Steep target. **`8b` adds no `add_dependency` line to that gemspec and the gate proves it.**
- **`gates:gemspec_audit`** — core plus at most one third-party gem per adapter, with a `two_third_party`
  negative fixture and a check that an adapter's `~> M.N` core constraint agrees with `VERSIONS`.
- **`gates:require_allowlist`, extended to the adapters** (`…phase0…-design.md:471-475`): every `require`
  in an adapter must be allowlisted, or under `dexpace/`, or the single third-party gem that adapter's
  gemspec declares. **`dexpace-async-thread` declares none, so its `lib/` may require only `dexpace` and
  its own `require_relative`s** — and verified fact 1 says that is enough, because every primitive the gem
  needs is built into the interpreter. **The bare name `"dexpace"` is not exempt under phase 0's guard as
  written** (verified fact 1's correction): the exemption is the `"dexpace/"` *prefix*, and the plan's
  Task 1 widens it by one alternative before the entry file gains its `require "dexpace"` line.
  `timeout` is on the **denylist** by name, which is §8.3's prohibition mechanised.
- **`gates:clean_bundle`** — the scratch-`Gemfile` isolation run, which `8b` extends to its own gem.
- **`gates:rbs_surface`** (`NFR-11`), **`gates:sig_diff`** and **`gates:surface_snapshot`** (`NFR-4`), and
  **`gates:single_instance`**.
- **`ruby -w` plus `RUBYOPT=-W:deprecated` with warnings failing the build**, and a shared test case that
  **overrides `Warning.warn` to raise**. This is the gate `OI-13`'s `Fiber#storage=` would fail, and `R8`
  is where `8b` avoids it. Verified fact 11 adds the complement a naive reading would miss:
  `Thread#report_on_exception` writes to `$stderr` **directly and not through `Warning.warn`**, so a dying
  worker is stderr noise the gate cannot see — which is one of two reasons `8b`'s worker never dies.
- **Five custom cops from phase 0, plus phase 2's `Dexpace/QualifiedCoreConstant` (`P2-8`, extended
  by `P3-7`) — six in the repository by phase 8.** Three reach `8b`: **`Dexpace/SpdxHeader`** (`NFR-13`: line 1
  `# frozen_string_literal: true`, line 2 `# SPDX-License-Identifier: MIT`, line 3 blank, in that order),
  **`Dexpace/NoThreadInterrupt`** (`Timeout.timeout`, `Thread#raise`, `Thread#kill`, `Thread#terminate`,
  `Thread#exit` — the cop that makes `ASYNC-3` a checklist row rather than a temptation), and
  **`Dexpace/QualifiedCoreConstant`** (`P2-8`, extended by `P3-7` to be repository-wide over every gem's
  `lib/` with a definition-site guard). `8b`'s gem is the **second definition site** in the repository
  after `lib/dexpace/io.rb`, and the first in an adapter gem; verified fact 14 is why the guard matters.
- **`Style/ClassAndModuleChildren: nested`** (`…phase0…-design.md:766`), which is what makes verified fact
  14's hazard live rather than hypothetical.

### From phase 1

`Dexpace::Model` (`.required!`, `#with`, `.own`), `Dexpace::InvalidArgumentError < ::ArgumentError` with
`SEAM-29`'s one message form `"<name> is required"`, `Dexpace::RequestOptions` (`:timeout, :max_retries,
:tags`), `Dexpace::Request` and `Dexpace::Response`, and `Dexpace::Error` as a **module** — which is what
lets `Dexpace::Async::Thread::RejectedError` be a `::StandardError` that `rescue Dexpace::Error` catches.

### From phase 2 — every seam `8b` implements against

- **`Dexpace::Async::Completer` and `Dexpace::Async::Future`**, with state on the completer and the future
  a facade over it. `Completer#fulfil(response)`/`#fail(error)` return `false` on a lost race, and
  **`#fulfil` on an already-settled future closes the response it was handed** through
  `Dexpace.close_quietly` — which is `SEAM-30`/`ASYNC-5` implemented once, for every adapter that routes
  through `Completer`. `#value` re-raises the stored object, so there is no wrapper (`ASYNC-13`).
  `Dexpace::Async::Settlement` is the frozen `Data` `#on_settle` yields.
- **`Dexpace::Transport.async_over(transport, executor:)`** — the bridge. `executor:` is **required with no
  default**; the executor is the `#post { … }` duck type; the bridge returns the future before doing
  anything fallible and routes a synchronous raise from `#post` **itself** — "a shut-down pool, a rejected
  task" — to `Completer#fail`. That sentence is what makes `R12`'s rejection policy satisfy `ASYNC-2`
  rather than violate it. Both bridges include `Dexpace::Closeable` with **`owned: false`**.
- **`Dexpace::AsyncTransport.sync_over(transport)`** — `ASYNC-14`'s subject, with `P2-4`'s three clauses.
- **`Dexpace::Cancellation`** with its typed `#reason`, `.none`, `.source`, `.any`, `#on_cancel` returning
  a `Subscription`, and `#check!`. `Completer#on_cancel` is the producer-side hook `R10` is about.
- **`Dexpace::Closeable`** — `#close`, `#closed?`, `#owned?`, a private `#release`, and a `@closed` boolean
  flipped under a `::Thread::Mutex` **held only across the flip**. `Dexpace.close_quietly` is null-safe and
  rescues `::StandardError`. `Dexpace::ClosedError` is `SEAM-15`'s class with the rule and **no raise
  site** — phase 8's adapters are the first owners.
- **The version-skew guard** (`DEF-21`, `P2-7`): `Registry#register(key, factory, core:)` takes the
  adapter's `~> MAJOR.MINOR` requirement as a **required** keyword and raises `Dexpace::SeamError` on skew.
  **There is no executor registry** (`P2-1`): `SEAM-18` requires the executor to be caller-supplied with no
  default, and an auto-resolved executor is exactly that default. The object model below says what `8b`
  does about the assertion when it has no registry to make it through.
- Phase 2's own statement of `8b`'s obligation, quoted because it is the hand-off: "Phase 2's obligation is
  to make the cooperative contract *stateable and testable* … not to close the gap, and it does not claim
  to."

### From phase 4

- **4a**: nothing. `ASYNC-8`–`ASYNC-12`'s carrier is fiber storage, not `ContextStore`; phase 4a's own
  design routes `ASYNC-9`'s save/install/restore to this gem by name (`…phase5c…-design.md:255`, quoting
  4a's exclusion row) and states that `CTX`'s store "touches fiber storage nowhere".
- **4b**: `RECOV-2`'s conversion rule — rescue `Exception`, immediately re-raise anything outside
  `StandardError`, convert the rest — which is the rule `8b`'s worker net deliberately **departs from**,
  argued in the object model. `pipeline/f02559b9`'s `raise error, cause: nil` spelling.
- **4c**: `PIPE-33`'s five-clause accounting, `PIPE-26`/`PIPE-27` (a pipeline is a transport and closing one
  does not close the transport), and `FakeExecutor` — 4c's own `#post`-shaped double, which is the proof
  that a test-side executor is a five-line object and a shared one buys nothing.

### From phase 5

- **5a**: `Dexpace::Clock` with exactly `#now`, `#monotonic` and `#sleep(duration, cancellation:)`, and
  `Clock::SYSTEM`. **`#monotonic` is `Process.clock_gettime(Process::CLOCK_MONOTONIC)` in Float seconds,
  used only for differences** — the arithmetic `8b`'s shutdown drain and timer both use.
  `Dexpace::Async.delay(duration)`, which **raises `Dexpace::SeamError` when `Fiber.scheduler` is `nil`**
  (`P5-9`) — `R11`'s starting point. `Future#value`/`#wait` gained `deadline:` and `clock:` (`DEF-28`,
  closed), with **`deadline:` a monotonic instant and not a duration**. And 5a's own precedent for
  declining a keyword: `Async.delay` has no `clock:` because "a `clock:` here would be an `NFR-4`-locked
  keyword with no consumer and no test that could drive it, which is `OI-8`'s shape".
- **5b**: `Instrumentation::Diagnostics.capture` (`(Fiber.current.storage || {}).freeze`) and
  `.with(snapshot) { }` (per key over the union of the captured and prior key sets, **never through
  `Fiber#storage=`**), which `P5-23` decided and which 5b's forward table hands to this gem in as many
  words: "`dexpace-async-thread`'s pooled-worker save/install/restore is the case `Diagnostics.with` was
  shaped for, and `OI-13`'s warned setter is the call it does not have to make". Also
  `Instrumentation::Logger` and `Logger::NULL`, `Severity` (`ERROR`, `WARNING`, `INFO`, `VERBOSE`),
  `Instrumentation.contain(logger, event:)`, and `Events::INSTRUMENTATION_SHUTDOWN =
  "http.instrumentation.shutdown"` with `Events::INSTRUMENTATION_LOG` as the containment's own diagnostic
  name. **`P5-38`/`OI-26` is inherited unchanged**: `Dexpace::Instrumentation::Logger` shadows the stdlib
  `Logger` and `8b` writes every reference fully qualified.
- **5c**: `OBS-23`'s per-key push and restore through `Fiber[]=`, and the two facts its `R12` measured —
  `Fiber[:k] = nil` **deletes** the key, and `Fiber[]=` emits **no** warning. `P5-49`'s residual (a prior
  key holding a literal `nil` restores as absent) is inherited and is harmless for the same reason, plus a
  second reason `8b` supplies: after the worker's one-time clear, the prior map is empty and there is no
  such key to lose.

### From phase 7c

`Dexpace::Page::_Executor` — the RBS interface `8b` implements, written in another gem in an earlier
phase. `7c` also fixes one division `8b` must honour rather than re-decide: "a response the transport never
delivered because a cancel won the race is **the transport's** to release" (`PAGE-33`). For `8b` that reads:
the pool releases nothing, ever — it holds no response and the orphan close is `Completer#fulfil`'s.

---

## Verified Ruby facts

**One interpreter, and this document says so before it says anything else.** Only **Ruby 3.4.10**
(`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`, `/usr/bin/ruby`) is installed on the
authoring machine. **The 3.2, 3.3 and 4.0 columns have not been run for anything below**, and neither has
anything on JRuby or TruffleRuby (`DEF-33`). `8b`'s plan installs 3.2.11 and 4.0.6 and **re-runs every fact
before any implementation task begins**; the facts on which a decision below is conditional are named at
the end of this section.

No gem was installed and nothing was written outside the session scratchpad. `dexpace-async-thread`
depends on nothing, so there was nothing to install.

1. **Every primitive this gem needs is built into the interpreter and needs no `require`.**
   `Thread`, `Thread::Queue`, `Thread::SizedQueue`, `Thread::Mutex`, `Thread::ConditionVariable` and
   `Fiber` are all `"constant"` with no `require`, and `Thread#name=` is defined. So the gem's `lib/`
   contains **no allowlisted `require` at all**: the only `require` in it is `require "dexpace"`.
   **Corrected 2026-09-12 (verification pass):** that last line is not yet *permitted* by phase 0's
   audit as written. `RequireAllowlist.reason_for` exempts only
   `permitted.include?(name) || name.start_with?("dexpace/")`, `permitted` for this gem is empty
   (`third_party_for` rejects `"dexpace-core"` by name), and `"dexpace"` is on neither `ALLOWED` nor
   `DENIED` — so `reason_for("dexpace", [])` returns the "not in the require allowlist" string.
   `dexpace-core`'s entry file is the one irregular case in the gem-to-file mapping
   (`lib/dexpace.rb`, not `lib/dexpace/core.rb`), which is why the prefix-only form misses it and why
   `8b` is the first sub-phase to reach it. The plan lands the one-line widening
   (`name == "dexpace" || name.start_with?("dexpace/")`) in its Task 1, before the entry file gains
   the line. The gem's zero-third-party claim is unaffected — it is about `add_dependency`, not about
   this exemption.
   *Command:* `ruby -e 'p defined?(Thread::SizedQueue), defined?(Thread::Queue), defined?(Thread::Mutex),
   defined?(Thread::ConditionVariable), defined?(Fiber), Thread.method_defined?(:name)'` →
   `"constant"` ×5, `true`.

2. **`Thread::SizedQueue` gives three distinct full-queue behaviours, and the choice between them is a
   requirement decision.** With a full queue: a plain `q << x` **blocks** (the pushing thread's `status` is
   `"sleep"` and it is released by a `pop`); `q.push(x, true)` raises **`ThreadError: queue full`**; and
   `q.push(x, timeout: 0.02)` returns **`nil`** after the interval. A successful `push` returns the queue
   itself. `Thread::SizedQueue.new(0)` raises `ArgumentError: queue size must be positive`, and
   `.new(-1)` raises too — so the bound validates itself.
   *Command:* `ruby -w q.rb` (the queue-semantics probe).

3. **`Thread::Queue#close` is the shutdown signal, and already-queued items still drain.** `#close` wakes a
   blocked `#pop` with `nil`; a `#push` on a closed queue raises `ClosedQueueError`; a `SizedQueue#close`
   raises `ClosedQueueError` **inside a blocked push**; and a queue closed with an item still in it pops
   that item and *then* `nil`. That last clause is what makes `ASYNC-16`'s graceful drain one method call:
   closing the submission queue stops accepting new work **and** lets queued work finish.
   *Command:* `ruby -w q.rb`.

4. **`Thread::Queue#pop` returns `nil` for a timeout, for a closed queue and for a pushed `nil` alike, and
   `closed?` disambiguates only two of the three.** Measured for all three cases.
   `Queue#pop(timeout: -1)` returns `nil` immediately and raises nothing. **Consequence, and it is
   load-bearing:** the shutdown drain must carry a **non-`nil` sentinel** and must re-read the monotonic
   clock to tell "the budget elapsed" from "the queue closed". A drain loop written against the return
   value alone reports a timed-out shutdown as a clean one — measured directly: the naive loop returned
   `[:closed, 0]` where the corrected loop returns `[:timed_out, 0]`, for the same slow worker.
   Phase 2 recorded the same fact for the pivot's wake-up queue and phase 5a for `Clock#sleep`; this is its
   third load-bearing appearance.
   *Commands:* `ruby -w q.rb`, `ruby -w amb.rb`, `ruby -w drain.rb`.

5. **`Fiber[]` is inherited by a new `Thread`; `Thread.current[]` is not; and a child's rebind does not
   reach the parent.** With `Fiber[:k] = "outer"` and `Thread.current[:tk] = "tl"` set,
   `Thread.new { [Fiber[:k], Thread.current[:tk], Fiber.current.storage] }.value` is
   `["outer", nil, {k: "outer"}]`; after `Thread.new { Fiber[:k] = "inner" }.join`, the parent's slot is
   still `"outer"`. Design §8.1's claim is confirmed, and `Fiber.current.storage` returns a **fresh,
   unfrozen `Hash` on every read**, so `.capture`'s freeze needs no defensive copy. `Fiber[:k] = nil`
   **deletes** the key.
   *Command:* `ruby -w t.rb`.

6. **A pooled worker does not see a context set after the worker started.** A worker thread spawned, then
   `Fiber[:late] = "set-after-worker-started"` set in the parent, then a job posted: the worker read
   **`nil`**. This is the fact that makes `ASYNC-12`'s thread-creation-boundary transfer the *dead* clause
   and `ASYNC-10`'s per-task-submission capture the *live* one, and it is `R9`'s whole subject.
   *Command:* `ruby -w t.rb`, probe 8.

7. **A merge-shaped install leaks the pool's *build-time* context into a caller's task.** Two identical
   pools, both built while `Fiber[:"trace.id"] = "POOL-BUILD-TIME"` and `Fiber[:tenant] = "assembly"` were
   set; both driven by a caller whose own captured context is exactly `{"trace.id": "CALLER-A"}`. The
   worker running phase 5b's `Diagnostics.with` **verbatim as that document writes it** observed
   `{"trace.id": "CALLER-A", tenant: "assembly"}`; the worker that had cleared its inherited storage once
   at thread start observed `{"trace.id": "CALLER-A"}` — the caller's context exactly. **`tenant:
   "assembly"` is `ASYNC-10`'s "stale snapshot from when it was assembled", visible on a log line the
   caller believes describes their own call**, and it is invisible in any test that builds the pool in the
   same context it submits from. `R8` and `R9` both turn on this.
   *Command:* `ruby -w leak.rb`.

8. **With the worker's storage cleared once at thread start, the union restore is exact — across reuse,
   across a throw, and with an empty snapshot — and emits no warning.** A single reused worker with a
   private key of its own, driven four times: context A installed and seen; the worker's own context intact
   afterwards; context B (two keys) installed on the **same** worker and seen live, not staled; a task
   that **throws** with the worker's own context intact after the throw; and an **empty** snapshot
   installed, observed as `{}`, restoring cleanly rather than raising. **Zero `Warning.warn` calls across
   all of it.** `Diagnostics.capture` in a thread with no context returns a frozen `{}`. That is
   `ASYNC-9`, `ASYNC-10` and `ASYNC-11` measured, not argued.
   *Command:* `ruby -w ctx.rb`.

9. **`Thread::Mutex` is non-reentrant and its ownership is per-fiber.** `m.synchronize { m.synchronize { } }`
   raises `ThreadError: deadlock; recursive locking`; a second **fiber of the same thread** locking a held
   mutex raises `ThreadError: deadlock; lock already owned by another fiber belonging to the same thread`.
   `#owned?`/`#locked?` report correctly and `#try_lock` from another thread returns `false`.
   `ConditionVariable#wait(m, 0.05)` returns after 50.1 ms. Re-verification of the repository's standing
   rule, on the object where a lock held across a queue pop would be fatal.
   *Command:* `ruby -w mx.rb`.

10. **`Thread#report_on_exception` is `true` by default, writes to `$stderr` **directly**, and does not go
    through `Warning.warn`.** A `Warning.warn` override captured **nothing** while the stderr block still
    printed. `Thread.abort_on_exception` is `false`. `Thread.current.report_on_exception = false` **inside**
    the thread body suppresses it reliably; setting it from outside after the thread has already raised is
    a race. **Two consequences:** phase 0's warnings-fatal gate cannot see a dying worker, and a dying
    worker is therefore silent to every gate and noisy to a human — which is one of the two reasons `8b`'s
    worker never dies.
    *Commands:* `ruby t2.rb`, `ruby -w t3.rb`.

11. **A worker that rescues `Exception` survives the whole fatal family, and `exit` on a worker does not
    exit the process.** One worker, four tasks: `exit(3)`, `raise NoMemoryError`, `raise Interrupt`,
    `raise NotImplementedError`. It swallowed `[SystemExit, NoMemoryError, Interrupt, NotImplementedError]`
    and was still alive; the process finished normally with status 0. Separately, a thread that calls
    `exit(3)` terminates only itself — the process continues — and `Thread#join` **re-raises the
    `SystemExit` in the joiner**. `NotImplementedError.ancestors` is
    `[NotImplementedError, ScriptError, Exception, Object]`, so `rescue => e` does not see it.
    *Commands:* `ruby -w fatal.rb`, `ruby -w fatal2.rb`.

12. **`Thread#value` re-raises the same exception object, every time.** Two `#value` calls on a thread that
    raised returned the `equal?` object, and the same object the block raised. Recorded because it is the
    property `ASYNC-13` would need if `8b` used `Thread#value` — and `8b` does not, which makes the
    requirement's unwrap the identity function through a second route as well as the first.
    *Command:* `ruby -w t3.rb`.

13. **Inside `module Dexpace; module Async; module Thread`, a bare `Thread` is the module — and the compact
    module form resolves differently.** In the **full nesting form** the repository mandates
    (`Style/ClassAndModuleChildren: nested`), `Module.nesting` is
    `[…::Pool, Dexpace::Async::Thread, Dexpace::Async, Dexpace]`, and a bare `Thread` resolves to
    **`Dexpace::Async::Thread`** because `Dexpace::Async` owns a constant of that name. `Thread.new` is a
    loud `NoMethodError: undefined method 'new' for module Dexpace::Async::Thread` and `Thread::Queue` a
    loud `NameError` — but **`real_thread.is_a?(Thread)` is silently `false` and `case … when Thread` falls
    silently through**, which is `P3-7`'s `IO` finding in a second namespace. In the **compact form**
    (`module Dexpace::Async::Thread`), `Module.nesting` omits `Dexpace::Async` and a bare `Thread` resolves
    to `::Thread`. **The repository's own nesting rule is what makes the hazard live**, and
    `Dexpace/QualifiedCoreConstant` is what catches it: every reference in `8b`'s `lib/` is `::Thread`,
    `::Thread::Queue`, `::Thread::SizedQueue`, `::Thread::Mutex`.
    *Command:* `ruby -w shadow.rb`, `ruby -w nest.rb`, `ruby -w final.rb`.

14. **At process exit on 3.4.10, a blocked worker's `ensure` did run — and that is not a substitute for
    deterministic teardown.** A worker blocked on `Queue#pop` with the main thread returning: the `ensure`
    printed. The same program with an `at_exit` that closes the queue and joins: the `ensure` printed in a
    defined order. The first is the interpreter delivering a termination at a point the program did not
    choose — which is exactly the hazard `concurrency-and-async/3692970f` names — so `Pool#close` is the
    deterministic path and process exit is not one. **A timer thread parked forever does not hold the
    process open**: `ruby exit3.rb` returned 0 immediately.
    *Commands:* `ruby -w exitp.rb`, `ruby -w exitp2.rb`, `ruby -w exit3.rb`.

15. **A blocking `Thread::Queue#pop` under a registered `Fiber::Scheduler` routes through `#block`/
    `#unblock` and never `#kernel_sleep`; and `Fiber.scheduler` is per-thread.** A minimal probe scheduler
    recorded `{block: 1, unblock: 1, close: 1}` and zero `kernel_sleep` for a fiber blocked on a queue pop
    — phase 5a's verified fact 8, re-measured. `Fiber.schedule` with no scheduler raises
    `RuntimeError: No scheduler is available!`. And **a worker thread sees `Fiber.scheduler` as `nil`
    regardless of the caller's**, which is decisive for `R11`: a pool worker can never use core's
    `Async.delay`, and the caller's scheduler is invisible from inside the pool.
    *Commands:* `ruby sched.rb`, `ruby -w final.rb`.

16. **One timer thread serves many deadlines, and a cancelled entry never fires.** A prototype timer with a
    deadline-ordered list, a wake queue and a single thread: entries at 50 ms and 100 ms fired at 50 ms and
    100 ms; a third, cancelled before its deadline, never fired and left the list empty. Cancellation woke
    the timer immediately rather than at the next deadline. That is every clause of `ASYNC-18` except the
    absolute reading of "without blocking a thread", and it is `R11`'s implementation.
    *Command:* `ruby -w drain.rb`.

17. **The bounded, sentinel-carrying drain behaves correctly in all three terminations.** Two workers
    exiting inside the budget → `[:drained, 2]` in 50 ms; one worker outliving an 80 ms budget →
    `[:timed_out, 0]` in 80 ms; a cancellation sentinel pushed at 30 ms into a 10 s budget →
    `[:cancelled, 0]` in 30 ms. The third is §8.3's cancellable-queue-wait shape, measured.
    *Commands:* `ruby -w drain.rb`, `ruby -w amb.rb`.

18. **A prototype of the whole pool behaves as `ASYNC-2`, `ASYNC-15` and `ASYNC-16` require.** Eight jobs
    on two workers all ran; `close` returned `true` then `false` (idempotent) and every worker's `ensure`
    ran; `post` after close raised `ClosedQueueError`; a submitter on a full queue blocked (`"sleep"`)
    while the non-blocking push raised `ThreadError: queue full`; `close` with a 150 ms task in flight
    waited 130 ms and **the task finished**; and three tasks queued behind a held worker **all ran** after
    `close`. **Twenty build-and-close cycles of a three-worker pool left `Thread.list.size` at its starting
    value of 1** — no thread leak.
    *Commands:* `ruby -w pool.rb`, `ruby -w final.rb`.

19. **Thread naming works and is visible in `Thread.list`.** `t.name = "dexpace-async-thread worker 1"`
    reads back and appears in `Thread.list.map(&:name)`. `Thread#join(0.05)` returns `nil` after 50.1 ms
    rather than blocking.
    *Command:* `ruby -w t.rb`.

20. **`Process.clock_gettime(Process::CLOCK_MONOTONIC)` is `Float` seconds with nanosecond resolution.**
    Two successive reads differed by 455 ns. Phase 5a's `Clock#monotonic` is this call, and `8b`'s deadline
    arithmetic is differences of it and nothing else.
    *Command:* `ruby -w mx.rb`.

**What is conditional on the three-interpreter re-run, named rather than left to be discovered.** Facts 5,
6, 7, 8 and 10 are the ones a decision below rests on. Specifically: `R8`'s route is conditional on
`Fiber[:k] = nil` deleting the key on 3.2.11 and 4.0.6 (5b's `P5-23` records the same condition and the
same repair — the restore loop deletes explicitly rather than assigning, and the mechanism is unchanged);
`R9`'s clearing step is conditional on fact 6 holding on all three; and the worker's error policy is
conditional on fact 10's `report_on_exception` default, which has been `true` since Ruby 2.5 but has not
been re-measured here on the floor. **Clearing `observability/65191069`'s own single-interpreter caveat is
`8b`'s obligation** — the note says in its own words that it "must be re-run on 3.2.11 and 4.0.6 before
anything rests on it", and `ASYNC-9` and `ASYNC-11` rest on it entirely.

**Nothing here is verified on a non-CRuby implementation** (`DEF-33`). `8b`'s pool is the fifth and most
acute case of a concurrency guarantee resting on a `::Thread::Mutex` the GVL would hide the absence of, and
this document states that without proposing a matrix row no v1 phase plans.

---

## `R8` — `ASYNC-9`'s save/install/restore against `OI-13`'s warned setter

**Decision: `8b` calls `Fiber#storage=` nowhere. Capture is phase 5b's `Diagnostics.capture`; install and
restore are phase 5b's `Diagnostics.with`, unchanged; and `8b` adds exactly one thing 5b's route does not
have — a one-time clear of the worker's *inherited* storage at thread start, which is what turns 5b's merge
into `ASYNC-9`'s replace and closes `ASYNC-10`. `P8-20`.**

The charter framed `R8` as a three-way choice — a per-key save/install/restore, a scoped `Warning.warn`
filter, or an `NFR-7` waiver — and required `8b` to pick one and state the supported-range risk. The
answer is the first, and it is **already decided in `dexpace-core`**: 5b's `R12`/`P5-23` chose per-key over
the union of the captured and prior key sets and shipped `Diagnostics.capture`/`.with` as public API, and
5b's own forward table names this gem as the consumer the pair was shaped for. `8b` does not re-derive that
argument and does not write a second mechanism. What `8b` owes is (a) the check that 5b's decision holds
for **an arbitrary key set on a pooled worker**, which 5b could not run because it ships no pool, and (b)
the one thing it does not hold for.

**What holds.** Verified fact 8, on a single reused worker: install-and-restore is exact across reuse,
exact across a task that throws, exact for an empty snapshot, and emits **zero warnings**. Every clause of
`ASYNC-9` is measured there — "first save that thread's prior context" (the `prior` read), "install the
captured context only for the duration of the work" (the yield), "restore the prior context afterward —
including when the work throws" (the `ensure`), and "a reused/pooled thread's own logging context is never
clobbered" (the worker's private key intact after four tasks, one of which threw). `ASYNC-11` is measured
in the same run: `Diagnostics.capture` with no context returns a frozen `{}`, and installing `{}` clears
the target rather than raising.

**What does not hold, and is the reason this is a decision rather than a delegation.** 5b's `.with`
**merges** on install: `snapshot.each { |k, v| Fiber[k] = v }`. For 5b's own consumer — a snapshot taken
and reinstated on the *same* logical flow — merge and replace agree, because the prior map is the
snapshot's own ancestor. For a **pooled** worker they diverge, and verified fact 7 measures the divergence:
a pool built under `Fiber[:tenant] = "assembly"` runs a caller's task with `tenant: "assembly"` visible,
because `::Thread.new` inherited it at pool construction and the caller's snapshot has no key to overwrite
it with. **That is `ASYNC-10`'s named failure** — "a stale snapshot from when it was assembled" — arriving
not through a stale *capture* but through a stale *floor under* the capture, which is a shape the
requirement's own conformance clause ("assemble under context A, subscribe/execute under B → log lines
carry B") does catch and which no test written in one context can see.

**The repair, and why it is at the worker rather than at the install.** Each worker, as the first statement
of its thread body and exactly once in its life, deletes every key it inherited:

```ruby
::Fiber.current.storage&.each_key { |key| ::Fiber[key] = nil }
```

Three properties make this the right place. **It is safe**: `Fiber.current.storage` returns a fresh `Hash`
(fact 5), so the iteration is over a copy and the writes go to the live storage — measured, not assumed.
**It is once per worker, not once per task**: `size` deletions at construction, and nothing on the hot
path. And **it makes `Diagnostics.with` correct without changing it**: with an empty prior map, merge *is*
replace, and the union restore returns the worker to empty. `8b` therefore writes no install code at all —
it writes one clearing line and calls core's pair.

**Why not the other two routes, restated for this sub-phase.** A scoped `Warning.warn` filter is a
`prepend` on a process-global object, which this port refuses for `Regexp.timeout` and
`Warning[:experimental]` alike and which a *library* may not do to its host unasked. An `NFR-7` waiver's
re-enable condition would be a condition on MRI's roadmap. Both keep `OI-13`'s second problem —
`Fiber.current.storage = nil` reading back as `{}` on 3.2.11 and `nil` on 3.4.10 and 4.0.6 — and only
silence the first. **The per-key route removes both problems rather than silencing one, and nothing in
`8b` depends on `Fiber#storage=`'s behaviour on any version, which is the point.**

**The supported-range risk, stated because the charter requires it.** `Fiber#storage=` carries "experimental
and may be removed in the future" and `8b` never calls it, so the risk `OI-13` records does not reach this
gem. `Fiber[]` and `Fiber[]=` carry no such warning and are 3.2+. What `8b` does inherit is
`P5-49`'s residual — a prior key holding a literal `nil` restores as *absent* — and `8b` adds a second
reason it is harmless here beside `OBS-10`'s null-skip clause: **after the one-time clear the worker's
prior map is empty**, so there is no prior key of any value to lose, and the only maps in play are the
caller's snapshot and the empty floor beneath it.

**What the checklist rows say.** `ASYNC-9` ✅, with the clause that the mechanism is 5b's `Diagnostics.with`
and the clearing line is `8b`'s; `ASYNC-11` ✅, with the clause that "absent captures as empty" is
`.capture`'s `|| {}` branch (which fact 5 shows is real and not defensive padding) and "reinstating empty
clears rather than raises" is measured; `ASYNC-8` ✅ as the SHOULD the two discharge together.

## `R9` — which clause of `ASYNC-12` is live, given that a new `Thread` inherits `Fiber[]`

**Decision: `ASYNC-12`'s *antecedent is false* at the thread-creation boundary and *true* at the
task-submission boundary, and the row states both halves. `8b` satisfies the requirement's purpose through
`ASYNC-10`'s per-submission capture and the `R8` clearing line, and records ✅ **with that clause**, not on
the strength of `Fiber[]`'s inheritance.**

`ASYNC-12`'s text is conditional: "**On runtimes where a newly created worker does not inherit the spawning
thread's logging context** (e.g. lightweight threads or plain thread-local contexts), an adapter that
propagates logging context MUST explicitly transfer it at the thread-creation boundary." Design §8.1 read
the antecedent the same way and said so first: `Fiber[]`'s inheritance "makes **ASYNC-12**'s explicit
transfer largely unnecessary at *creation* boundaries. It stays necessary at *reuse* boundaries."

**Three measurements settle it.** Verified fact 5: a newly created `::Thread` **does** inherit `Fiber[]`,
so the antecedent is false for a fresh thread and the requirement does not apply there. Verified fact 6: a
worker created *before* the caller's context existed sees **`nil`**, so a pool's workers carry the *pool
creator's* context and not the caller's — and the requirement's purpose, "the transport call executing on
the spawned worker sees the caller's context", is unmet by inheritance alone. Verified fact 7: without the
clearing line, what the worker *does* carry is actively wrong rather than merely absent.

**So the obligation is discharged at a different boundary than the requirement names, and the row says so
in these words:**

> The requirement's antecedent — "a newly created worker does not inherit the spawning thread's logging
> context" — is **false** on CRuby: `Fiber[]` is inherited by a new `::Thread` (verified). A pooled worker
> is nevertheless created long before the task arrives and sees nothing set afterwards (verified), so
> inheritance transfers the **pool creator's** context, not the caller's. `8b` therefore transfers
> explicitly at the boundary that identifies the logical caller — **per task submission**, which is
> `ASYNC-10` — and clears the worker's inherited storage once at thread start so the inherited context
> cannot survive underneath an installed snapshot. `ASYNC-12`'s "distinct from, and additional to, any
> carrier-hop guarantee the runtime provides" is honoured: the transfer is explicit and does not rely on
> the inheritance at all.

**The conformance clause is written for the case that exists rather than the case named.** `ASYNC-12`'s own
clause is "on the lightweight-thread adapter, set a context entry on the caller thread and assert the
transport call executing on the spawned worker sees it". `8b`'s assertion sets the entry **after the pool
was built** — which is the only version of that test that can fail — and additionally asserts the negative:
a key present at pool-build time and absent from the caller's snapshot is **not** visible to the task.
Without the second assertion the first passes under the bug.

**And the note's caveat is cleared here.** `observability/65191069` says it "must be re-run on 3.2.11 and
4.0.6 before anything rests on it", and `ASYNC-9`, `ASYNC-11` and this decision all rest on it. `8b`'s plan
re-runs facts 5 through 8 on both and records the result in the note rather than in a new one.

## `R10` — what `Completer#on_cancel` does for a pooled worker blocked in a transport read

**Decision: the pool exposes no cancellation hook and registers no `on_cancel` callback. The hook belongs
to whoever owns the blocking resource, which is the transport — `8a`'s, not `8b`'s. What the pool owns is
narrower and is stated positively: the worker's `Queue#pop` is a suspension point, so the block runs
directly after a resume, and check-after-resume's *first* opportunity is therefore before the block does
anything. `8b` does not take that opportunity itself, because the block is opaque to the pool; it asserts
the observable outcome and files the one-line improvement as a register finding.**

The charter posed the question exactly: "`8b` decides whether the pool exposes such a hook at all — the
pool posts an opaque block and does not know what is inside it — or whether the hook belongs to the
*transport* that owns the socket, which would make it `8a`'s."

**Three facts decide it, and none of them is a preference.**

1. **The pool cannot reach into a running block.** `Thread#raise` and `Thread#kill` are forbidden
   repository-wide (§8.3, `Dexpace/NoThreadInterrupt`), and there is no other mechanism. A hook the pool
   exposed could do nothing but set a flag the block may never read.
2. **The pool does not know what the block holds.** `#post { … }` takes a block and nothing else — that is
   `concurrency-and-async/08a0e08d`'s fixed shape, and it is what lets the same object serve
   `Transport.async_over` and `Dexpace::Page::_Executor`. A pool that needed to know how to abort its
   tasks would need a second, task-shaped parameter, which would make it a transport-specific object and
   break the second consumer.
3. **The only mechanism that shortens a blocked read is closing the socket under it**, which only the
   object that owns the socket can do. The charter's verified fact 11 measures it (a cross-thread `#close`
   wakes a blocked `readpartial` with `IOError`) and its verified fact 1 measures the collision
   (`IOError` is on `Net::HTTP`'s own retry rescue list, so `max_retries = 0` is required for the abort to
   surface at all). **Both facts are about `Net::HTTP`. Both belong to `8a`.** `8b` records the routing and
   does not pre-empt `8a`'s decision.

**What the pool does own, and it is worth stating positively rather than as an absence.** The worker's
`::Thread::Queue#pop` **is** one of the four suspension points
`concurrency-and-async/611b9392` enumerates ("an I/O wait, a scheduler yield, **a queue pop**, a task
await"). The block therefore begins executing in the instant after a resume, which is the earliest moment
check-after-resume can fire for a queued task — earlier than `ASYNC-3`'s third clause asks for. `ASYNC-3`
requires only that a queued task "MUST NOT be interrupted", which holds because nothing is ever
interrupted; the stronger property — a task cancelled while queued is never *run* — is available for one
`if` and would turn a wasted network round-trip into no round-trip.

**`8b` does not implement that `if`, and the reason is a gem boundary rather than a judgement.** The block
is built by `Dexpace::Bridge::AsyncOver` in `dexpace-core`, and phase 2's design describes it as
performing "the blocking send, re-check[ing] cancellation on return" — after, not before. Putting a
pre-dispatch check in `8b` is impossible (the pool cannot see the token); putting one in core is an edit to
a committed, reviewed phase-2 object that `8b`'s gem does not contain. **So `8b` records it as a register
finding** (below), states that `ASYNC-3`'s queued clause is satisfied without it, and writes the assertion
against the observable rather than the mechanism.

**The assertion `8b` writes for the cancel-while-queued case**, which is `ASYNC-3`'s third clause and
`ASYNC-5`'s window in one test: occupy every worker with a gate, post a second unit, cancel its future
before the gate opens, open the gate, and assert — the future is cancelled with the caller's reason; **no
response is delivered**; and if the block produced a closeable response, `#close` was invoked **exactly
once**, by `Completer#fulfil`'s losing-race branch and not by the pool. The gate is a `::Thread::Queue`,
so the test is deterministic and contains no sleep.

**`TRANSPORT-3`'s discrimination survives, and `8b` says how.** The charter requires that "the woken
`IOError` must not be classified as a retryable transport failure when a cancellation caused it". `8b`
neither wakes nor classifies anything — it holds no socket and raises no transport error — and the
discrimination is `XCUT-2`'s out-of-band one through `Dexpace::Cancellation#reason`'s typed object, which
is available on the worker because the token is an argument to the transport call. Recorded here so `8a`
inherits the statement rather than re-deriving it.

**Residual, stated rather than claimed away**, and it is `concurrency-and-async/257d79cb` verbatim: a
transport blocked inside an uninterruptible C-extension read occupies its pool slot until the read returns
on its own. The consequence is **bounded worker occupancy under aggressive cancellation**, not a
correctness failure: no response is delivered to a cancelled caller and any response produced is closed
exactly once. §10.5 already records it; `8b` neither widens nor narrows it, and its README says it in the
`ASYNC-7` section where a user will meet it.

## `R11` — `ASYNC-18`'s non-blocking scheduled delay, with no `Fiber.scheduler`

**Decision: `dexpace-async-thread` ships its own timer. `Pool#delay(duration) -> Dexpace::Async::Future`
is backed by **one** lazily created thread per pool, shared across every outstanding delay, parked on a
bounded `::Thread::Queue#pop(timeout:)` against the nearest deadline, and stopped by `#close`. Zero
completes immediately with no thread touched; negative raises before anything is scheduled; cancelling the
returned future removes the entry and wakes the timer so no slot is held. The absolute reading of "without
blocking a thread" is not met and carries a deviation row, `P8-25`.**

The charter posed it as: does the gem supply a timer that satisfies the clause, "a single timer thread
parked on a bounded queue wait is a defensible reading of 'without blocking a thread' — it blocks *one*
thread, not the caller's and not a pool worker", or is it a deviation? **The answer is both**: the timer is
shipped and the reading is stated, and because the reading is a reading it gets a ledger row rather than a
tick with a footnote.

**Why the gem must own a timer at all, which is the half the charter left open.** Phase 5a's
`Dexpace::Async.delay` **raises `Dexpace::SeamError` when `Fiber.scheduler` is `nil`** (`P5-9`), and
verified fact 15 shows that `Fiber.scheduler` is **per-thread**: a pool worker sees `nil` however the
caller's thread is configured. So core's delay is unavailable to a pool worker unconditionally, and
unavailable to the caller unless the caller installed a scheduler — which, for the gem whose entire reason
to exist is the no-reactor case, is the case that does not apply. Inheriting 5a's raise would make
`ASYNC-18` — a **MUST** — unimplemented in the only adapter that has it, where `CFG-18` is a **SHOULD** and
could afford it.

**Why one shared timer thread rather than one thread per delay, or a pool worker.** A thread per delay is
unbounded thread creation, which `concurrency-and-async/171f800d` and `/6764e0b5` both forbid. A pool worker
would be worse than either: it occupies a slot the pool sized for blocking sends, so `n` outstanding delays
starve the pool at `n = size`, which is the exact failure `SEAM-18`'s "a shared global pool would be starved
by blocking work" is about. One thread, lazily created on the first **positive** delay and never before, is
the smallest thing that works. Verified fact 16 measures it: one thread served two deadlines at 50 ms and
100 ms and a third, cancelled, never fired.

**The reading of "without blocking a thread", stated precisely so it can be judged.** The requirement's
conformance clause ends "cancelling the future cancels the scheduled task **so no scheduler thread is
held**", and its own subject is "the non-blocking scheduled-delay primitive used to insert async delays
into a future chain". What the clause protects is the *carrier*: a delay must not pin the thread that is
waiting on it, and a cancelled delay must not keep a scheduler resource alive. **Both are satisfied
exactly**: the caller's thread is never parked (the future is returned immediately), no pool worker is ever
parked, and a cancelled delay is removed from the list and the timer re-computes its next wake. What is not
satisfied is the absolute reading — the timer thread itself is parked in `Queue#pop(timeout:)` for the
interval. `P8-25` records that, names the thread (`"<name> timer"`, so it is identifiable in a thread dump
rather than anonymous), and names the zero-thread alternative for a caller who has a reactor:
`Dexpace::Async.delay`, which uses `Fiber.schedule` and holds nothing.

**Why not two code paths — delegate to core's delay when the caller has a scheduler, and use the timer
otherwise.** Rejected, and the reason is not simplicity. A delay that fires on the caller's reactor fires
only while that reactor is running; a caller that installs a scheduler, calls `#delay`, and then blocks
outside the reactor gets a delay that never completes. One primitive with one behaviour, documented, is
worth more than a primitive whose timing depends on where it was called from — and the second path would
need its own tests, its own `ASYNC-18` clause accounting and its own README paragraph, for a caller who
already has the better primitive one method call away.

**The four clauses, each with its mechanism.**

| Clause | Mechanism |
|---|---|
| "MUST reject a negative delay" | `Dexpace::InvalidArgumentError` raised **before** anything is scheduled and before the timer thread is created, with `SEAM-29`'s message form. 5a's `Clock#sleep` guard is the precedent and the reason is verified: `Queue#pop(timeout: -1)` returns `nil` immediately and raises nothing (fact 4), so the primitive will not reject for us |
| "MUST complete immediately for a zero delay" | A `Completer` settled with `nil` before the method returns. No queue, no entry, **no timer thread created** — a pool that only ever schedules zero delays never spawns one |
| "MUST complete after the requested delay without blocking a thread" | One entry on the deadline-ordered list; the timer parks on `pop(timeout: remaining)` against the **nearest** deadline and re-computes after every wake. Elapsed time is differences of `clock.monotonic` (`CFG-16`), never `Time.now` |
| "cancelling the returned future MUST cancel the underlying scheduled task so no scheduler thread is held" | `Completer#on_cancel` removes the entry under the timer's mutex and pushes a `:recompute` sentinel to the wake queue, so the timer wakes at once and re-parks against the *next* real deadline. Measured (fact 16): the cancelled entry never fired and the list emptied |

**What `#delay` returns and what it settles with.** `Dexpace::Async::Future`, settled with `nil`. Not the
duration, not a timestamp: the primitive's whole content is "later", and a value would be a surface
`NFR-4` locks for no consumer. 5a's `Async.delay` settles with `nil` for the same reason and `8b` matches
it deliberately, so the two primitives are interchangeable at the call site.

**Lifecycle.** The timer is part of the pool's owned resources: `#release` closes the wake queue and waits
for the timer thread within the same `DEFAULT_SHUTDOWN_TIMEOUT` budget as the workers, and every
outstanding entry is settled — **failed with `Dexpace::ClosedError`, not left hanging and not completed
early**. A delay whose pool is closed is a delay that will never fire, and a future nobody settles is a
caller blocked forever in `#value`; failing it is the only honest answer and it is `ASYNC-15`'s "only the
first close performs side-effects" applied to the one resource a reader would forget.

## `R12` — the pool's bound, rejection policy and teardown, against six corpus rules and a core-declared interface

**Decision, in one paragraph.** `Dexpace::Async::Thread::Pool.build(size:, …)` creates **exactly `size`**
threads at construction and **never grows**; its submission queue is a `::Thread::SizedQueue` bounded at
`size * QUEUE_DEPTH_PER_WORKER` by default; **`#post` never blocks the calling thread** — it uses the
non-blocking push and translates a full queue into `Dexpace::Async::Thread::RejectedError` and a closed
pool into `Dexpace::ClosedError`, both of which the bridge routes to `Completer#fail`, which is `ASYNC-2`;
and `#close` closes the queue (stop accepting, drain what is queued), waits for every worker and the timer
within a construction-time bounded budget, and emits `DEF-31`'s event exactly once. `#post`'s signature is
`Dexpace::Page::_Executor`'s **exactly**, not a superset.

### The six corpus rules the charter routed here by name, one at a time

`concurrency-and-async/f414b864` ends with the sentence that routes them, quoted because the routing is the
point:

> The bounded-pool and deterministic-teardown rules in the same chapter
> (`concurrency-and-async/6764e0b5`, `/dc345cae`, `/df658d73`, `/3692970f`, `/047644ea`, `/dd8e6d2d`) are
> **not** resolved here and are not weakened: they bind `dexpace-async-thread`, an adapter gem whose
> `NFR-2` budget permits one third-party library, and they are that gem's to answer in phase 8.

**They are answered here, and the budget the note offers is declined.** `dexpace-async-thread`'s `NFR-2`
budget permits one third-party library and **§2.1 says it spends none, by design** — "The zero-third-party
async driver". Spending it on `concurrent-ruby` would make the one gem in the MVP that proves the pivot is
reachable with nothing installed depend on the largest concurrency gem in the ecosystem, which is the
opposite of what the gem is for. Every rule below is therefore answered in substance with a stdlib
mechanism, and the two that name `concurrent-ruby` APIs are answered by what those APIs *do*.

| Key | The rule | `8b`'s answer |
|---|---|---|
| `6764e0b5` | Use `Concurrent::FixedThreadPool` (never `CachedThreadPool` or raw `Thread.new`) for thread-based fan-out, and `Async::Semaphore` for Fiber-based fan-out, **declaring the bound as a named, documented constant** | **Adopted in substance; both named mechanisms are unavailable.** `concurrent-ruby` is barred by §2.1 and `f414b864`; `Async::Semaphore` would be a second third-party dependency and the gem's fan-out is threads, not fibers. The pool is **fixed-size and never grows**, which is the whole of what `FixedThreadPool`-over-`CachedThreadPool` buys. The `Thread.new` the rule calls "raw" is not raw here: it is one call, in one private method, bounded by a validated `size`, and it is the only `Thread.new` in the gem. **The bound is a required keyword rather than a constant**, argued below; the *derived* bound, `QUEUE_DEPTH_PER_WORKER`, is a named documented constant as the rule asks |
| `dc345cae` | Use `SizedQueue` instead of `Queue` for producer-consumer channels, since an unbounded `Queue` lets producers race arbitrarily ahead of consumers while `SizedQueue` applies backpressure when the buffer is full | **Adopted for the mechanism, and its blocking behaviour deliberately not used.** The submission queue **is** a `::Thread::SizedQueue`, so the bound is real and enforced by the primitive. But `#post` uses the **non-blocking** push, so the backpressure signal is a *rejected future* rather than a *blocked producer* — argued in full below. The rule's purpose (a producer cannot race arbitrarily ahead) is met exactly; its mechanism's side effect (the producer parks) is what an async seam must not do |
| `df658d73` | A custom RuboCop cop bans `Thread.new` inside loops; review rejects `Queue.new` where `SizedQueue.new` belongs; **pool size and queue bound must be named constants** | **Adopted; no new cop proposed.** This repository ships five custom cops and none of them is a `Thread.new`-in-loop cop. `8b` proposes no sixth: the single site is `Array.new(size) { ::Thread.new { … } }`, bounded construction in a private method, which is the one place the pattern is correct — a cop whose only firing site in the repository is a false positive costs more than it catches. The rule's purpose is met structurally and asserted: a test greps the gem's `lib/` for `Thread.new` and asserts **exactly one** occurrence, in the named private method. `Queue.new` where `SizedQueue` belongs is answered by there being exactly one submission queue and it being sized |
| `3692970f` | Join threads, shut down pools, and close queues deterministically, since an unjoined thread or pool may be killed mid-operation by the OS at process exit, corrupting the operation | **Adopted, and verified fact 14 sharpens rather than weakens it.** On 3.4.10 a blocked worker's `ensure` *did* run at process exit — but that is the interpreter delivering a termination at a point the program did not choose, which is the hazard the rule names. `#close` is the deterministic path: it closes the submission queue, waits for every worker's exit sentinel and the timer within a bounded budget, and reports whether the drain completed. **8b installs no `at_exit` hook** (`concurrency-and-async/b667b6a4` offers one as an alternative to an `ensure`): a library that registers a process-global `at_exit` on its host is the same imposition this port refuses for `Regexp.timeout` and `Warning[:experimental]`, and it would make a pool the application forgot to close **also** the reason the process exits slowly. The `ensure` form belongs in the caller's code and the README shows it |
| `047644ea` | Call **both** `shutdown` (stop accepting new work) and `wait_for_termination` (block until in-flight work drains) on every pool | **Adopted as one method, and the merge is deliberate.** `#close` is both: closing the `SizedQueue` is `shutdown` (verified fact 3 — a push on a closed queue raises and queued items still drain) and the bounded sentinel drain is `wait_for_termination`. One method because `Dexpace::Closeable` is this repository's single close vocabulary — `Dexpace.close_quietly(pool)` calls `#close` with no arguments, and a pool that needed two calls to shut down would be the one closeable in the SDK that does not work through the helper §3.7 makes the single sanctioned exit |
| `dd8e6d2d` | Every pool must have a paired `shutdown` plus `wait_for_termination` **in an `ensure` block**, and every `SizedQueue` must be `close`d on exit | **Adopted at the call site and at the implementation.** The queue is closed by `#release`, so a closed pool has a closed queue by construction. The `ensure` is the *caller's* and the README's first example is `pool = Pool.build(size: 4); begin … ensure pool.close end` — because the object that must be in an `ensure` is the one the caller holds, and a gem cannot write its consumer's `ensure` |

**Two more rules from the same chapter that `f414b864` *adopts* and that bind `8b` just as hard**, named
because the charter names them: `/c0fab747` (protect only the smallest critical section) and `/ee54cb68`
with `/f261a143` (never hold a lock across I/O). Both are satisfied structurally rather than by discipline:
see *Thread-safety proof obligations* below, where every mutex in the gem is enumerated with what it
protects and what it is provably not held across.

**And two the chapter states that `8b` satisfies for free:** `/2c743901` (model cross-thread payloads as
immutable `Data` values) is why `Pool::Job` is a frozen `Data` and not a two-element `Array`, and
`/16ceb098` (document the invariant at every boundary) is why `Job`'s definition carries the one-line
comment naming it.

### The bound: `size:` is required and `queue_limit:` is derived

**`size:` has no default.** This is `SEAM-18`'s own argument applied one level down, and it is the single
most contestable decision in this document, so it is made explicitly. `SEAM-18` refuses a default executor
because "a shared global fork/join-style pool is explicitly unacceptable because a blocking call would
starve it" — the failure is a *guess about the caller's concurrency* meeting *blocking work*. A default
pool **size** is the same guess one layer in: the right number is a function of the caller's service, its
p99 latency and its connection budget, none of which the SDK can see, and the failure of a wrong guess is
the starvation `SEAM-18` names. A required keyword makes the caller state the number once, in their own
code, where `concurrency-and-async/6764e0b5`'s "named, documented constant" actually belongs.

**`queue_limit:` defaults, because it is a ratio to a number the caller chose.**
`queue_limit` defaults to `size * QUEUE_DEPTH_PER_WORKER`, with `QUEUE_DEPTH_PER_WORKER = 8` a named
documented public constant. Eight is a depth, not a capacity: it says "a worker may have eight units of
work waiting behind it before the pool rejects", which is a statement about burst tolerance that scales
with whatever `size` the caller picked. Both are validated as positive `Integer`s with
`Dexpace::InvalidArgumentError` and `SEAM-29`'s message form; `::Thread::SizedQueue.new(0)` would raise
anyway (fact 2), and `8b` raises first so the message names the keyword.

**The pool does not grow, and does not shrink.** `size` threads are created at construction and live until
`#close`. No idle timeout, no watermark, no replacement of a dead worker — because a worker cannot die
(below), so there is nothing to replace, and a pool whose thread count changes has a capacity a caller
cannot reason about.

### `#post` never blocks the calling thread, and that is what makes `ASYNC-2` live

**The rule, stated as an invariant with its own test:** `Pool#post` returns in bounded time regardless of
the queue's state, on any thread, including a pool worker.

Four reasons, in decreasing order of force.

1. **`ASYNC-2` names the saturated executor and the conformance clause names only the shut-down one.** The
   requirement: "worker-pool rejection (**a saturated/shut-down executor**)" MUST be delivered through the
   failure channel. If `#post` blocked on saturation, this adapter would have **no saturated case at all**
   and half of `ASYNC-2`'s named antecedent would be dead. Rejecting makes both halves live and both
   testable.
2. **A blocking `#post` parks the caller inside a method that promised a future.** `Transport.async_over`'s
   `#call` returns a `Dexpace::Async::Future`; phase 2 makes it "return the future before doing anything
   fallible" precisely so a caller of an async seam never has to wait. A `#post` that blocks moves the
   blocking from the transport (where the caller asked for it) to the submission (where they did not), and
   no amount of documentation makes an async call that blocks unsurprising.
3. **`PAGE-30` already expects a raising `#post`.** 7c: "`PAGE-30`'s rejection is `#post` raising. Every
   `#post` call site is wrapped; the raised error becomes the walk's failure through `Completer#fail`."
   The second consumer of this interface was designed against a rejecting executor.
4. **A blocking `#post` deadlocks on re-entry.** A task that posts back to the same pool — a paginator
   re-dispatch, a retry that re-enqueues — would, with a full queue, park a worker waiting for a worker.
   The non-blocking push turns that into a `RejectedError` the caller can see.

**The rejected alternatives, named.** A *caller-runs* policy (run the block inline when the queue is full)
would execute a blocking HTTP send on the caller's thread inside an async call, which is reason 2 with the
volume turned up. A *saturation-policy keyword* (`on_saturation: :block | :reject | :caller_runs`) is
`OI-8`'s shape — an `NFR-4`-locked knob whose two extra values have no requirement behind them and whose
tests would exist only to exercise the knob — and `api-design/b0e18938`'s minimal-surface rule argues
against it. A caller who wants to wait sizes `queue_limit` to their burst, or rescues and retries; both are
one line in their code and neither is a permanent surface in ours.

**Two errors, two conditions, one new name.** A **closed** pool raises `Dexpace::ClosedError` — phase 2's
class, `SEAM-15`'s rule, and this is one of its first two raise sites in the repository (the other is
`8a`'s transport). A **full** queue raises `Dexpace::Async::Thread::RejectedError`, a new
`::StandardError` including `Dexpace::Error`, whose message names the pool, the limit and the number of
workers. Two classes rather than one with a `#reason`, because a caller's two sensible responses differ:
a closed pool is a lifecycle bug and a full queue is backpressure to retry or shed.

**No bare stdlib error escapes the gem's `lib/`.** The `::ThreadError` a full non-blocking push raises and
the `::ClosedQueueError` a closed queue raises are both translated at the one call site. That is phase 6a's
`P6-4` obligation — "every transport adapter MUST wrap a bare stdlib I/O or timeout error it lets escape" —
met by a gem that is not a transport, and stated because a phase-9 audit will look for it.

### `Dexpace::Page::_Executor`: the interface is core's and `#post` is exactly it, not a superset

7c declares, in `gems/dexpace-core/sig/dexpace/page/strategy.rbs`:

```rbs
interface _Executor
  def post: () { () -> void } -> void
end
```

**`Pool#post`'s RBS is that signature verbatim, and the method returns `nil`.** The temptation is to return
something useful — a handle, a future, the job — and the temptation is refused for a stated reason:
`-> void` in RBS means the return value is not to be used, and a method that returns something a caller
*could* use, declared through an interface that says they may not, is a surface that exists in one artifact
`NFR-4` diffs and not the other. Returning `nil` makes the two agree and makes the runtime surface snapshot
and the RBS say the same thing. A caller who wants a result uses `Transport.async_over`, which is what the
pivot is for.

**What `8b` must not do**, stated because it is the failure mode the interface inheritance creates: it must
not add a keyword to `#post`, must not make the block's arity non-zero, and must not declare a second
`post`-shaped method with a different contract. Any of the three would make the pool satisfy `_Executor`
by luck rather than by declaration. The plan's task asserts the agreement directly — a test that builds a
`Dexpace::Page::AsyncPaginator` with the pool as its `executor:` and drives a two-page walk over `8b`'s own
fake transport, which is the only assertion that proves the interface is satisfied *as 7c's code uses it*
rather than as `respond_to?` reports it.

### Teardown, stated as the sequence it is

`#close` runs `Dexpace::Closeable`'s latch — a `@closed` boolean flipped under a `::Thread::Mutex` held
**across the flip only** — and the winner runs `#release`, in this order:

1. **Close the submission queue.** New `#post` calls now raise `Dexpace::ClosedError` (checked against the
   latch, so the message is the pool's and not `ClosedQueueError`'s), every idle worker's blocked `#pop`
   wakes with `nil` and exits, and **queued work still drains** (verified fact 3).
2. **Stop the timer, if one was ever created**, and fail every outstanding delay with
   `Dexpace::ClosedError`.
3. **Wait, bounded**, for `size` worker-exit sentinels on a private `::Thread::Queue`, against a deadline
   of `clock.monotonic + shutdown_timeout`. The sentinel is non-`nil` and the loop re-reads the clock, for
   verified fact 4's reason; a `nil` pop is disambiguated by `closed?` and by the remaining budget, never
   by itself.
4. **Emit `Events::INSTRUMENTATION_SHUTDOWN` exactly once**, inside `Instrumentation.contain`, with
   `Severity::INFO` and two adapter-private fields: the worker count and whether the drain completed within
   the budget. `DEF-31` closes here.

**`#close` returns `nil` whether or not the drain completed**, and the fact is carried on the event rather
than in the return value, because `Dexpace::Closeable#close` is a duck type shared with `Response`, `IO`
and `Tempfile` and a pool that returned a different kind of value from `#close` would break
`close_quietly`'s uniformity for one caller's benefit. A caller who needs to know queries the event.

**Why there is no `cancellation:` keyword on `#close`.** §3.7 asks for "the wait itself performed through
§8.3's cancellable queue wait and a bounded deadline, so a caller who closes inside a cancelled scope is
not parked". `8b` takes the **bounded deadline** and declines the **token**, and the trade is `P8-24`: a
keyword on `#close` cannot be passed by `Dexpace.close_quietly(resource)`, which is the single sanctioned
exit §3.7 itself defines and which calls `#close` with no arguments — so the keyword would be unreachable
from the one call site that matters, which is `OI-8`'s shape exactly. The bounded budget delivers the
clause's substance: a caller closing inside a cancelled scope waits at most `shutdown_timeout` and never
forever, and the wait *is* a queue wait as the sentence asks. The budget is a construction-time property,
which is also where `@owned` lives, so the pool's whole lifecycle policy is fixed in one place.

---

## Module layout

Every file `8b` creates or modifies. `sig/` mirrors `lib/` one file per file and **ships inside the gem**;
`test/` mirrors `lib/` and does not ship. `private_constant`s get neither, per phases 3, 4 and 7.

```
gems/dexpace-async-thread/
  dexpace-async-thread.gemspec          UNCHANGED: dexpace-core and nothing else (P0-9), and a test asserts it
  README.md                             MODIFIED: ASYNC-7's required section, the ensure-form example,
                                        the close-semantics table, and OI-13's caller-owned-object warning
  lib/dexpace/async/thread.rb           MODIFIED: require "dexpace", the require_relatives, CORE_REQUIREMENT,
                                        the skew assertion, and the module YARD block
  lib/dexpace/async/thread/pool.rb      Dexpace::Async::Thread::Pool  (+ private_constant Job)
  lib/dexpace/async/thread/timer.rb     Dexpace::Async::Thread::Timer  — private_constant, no sig/, no manifest row
  lib/dexpace/async/thread/rejected_error.rb
                                        Dexpace::Async::Thread::RejectedError
  sig/dexpace/async/thread.rbs          MODIFIED: VERSION, CORE_REQUIREMENT
  sig/dexpace/async/thread/pool.rbs     NEW
  sig/dexpace/async/thread/rejected_error.rbs
                                        NEW
  test/test_helper.rb                   phase 0's, unchanged
  test/support/fake_transport.rb        8b's own — a #call(request, options, cancellation) double with a
                                        gate, a produces-a-closeable mode and an ignores-cancellation mode
  test/support/counting_response.rb     a #close-counting Response double, for ASYNC-5 and ASYNC-20
  test/support/recording_sink.rb        a logging sink double, for DEF-31's one-event assertion
  test/support/probe_scheduler.rb       the minimal Fiber::Scheduler, for the one ASYNC-18 contrast test
  test/dexpace/async/thread_test.rb     the entry file, VERSION, CORE_REQUIREMENT and the skew assertion
  test/dexpace/async/thread/pool_test.rb
                                        construction, #post, rejection, close, contention, thread accounting
  test/dexpace/async/thread/pool_diagnostics_test.rb
                                        ASYNC-8..ASYNC-12
  test/dexpace/async/thread/pool_delay_test.rb
                                        ASYNC-18's four clauses and the timer's lifecycle
  test/dexpace/async/thread/bridge_test.rb
                                        ASYNC-1, 2, 5, 13, 14, 17, 19, 20 and PIPE-33 clauses 2-4, end to end
  test/dexpace/async/thread/page_executor_test.rb
                                        Dexpace::Page::_Executor, driven by AsyncPaginator
```

**Three new public constants, one new private one, and no core file touched.** `8b` writes nothing under
`gems/dexpace-core/`: not a `lib/` file, not a `sig/` file, not a test. That is worth stating because three
of `8b`'s nineteen IDs (`ASYNC-1`, `ASYNC-5`, `ASYNC-20`) are satisfied by mechanisms that live entirely in
core, and the temptation is to "finish" them there.

**Two placement notes.** `Timer` is a `private_constant` of `Dexpace::Async::Thread` rather than a nested
class of `Pool`, so its file is `lib/dexpace/async/thread/timer.rb` and the one-public-constant-per-file
rule is not broken by a file with no public constant at all (7c's `Page::LinkHeader` is the precedent).
`RejectedError` gets its own file beside phase 1's `lib/dexpace/error/invalid_argument_error.rb`
convention — one public constant, one file — rather than being defined inside `pool.rb`.

**`module-organization/d1bdfecf` — "module nesting should stay shallow; three path segments is a smell" —
is answered rather than ignored.** `Dexpace::Async::Thread::Pool` is four. The fourth segment is **imposed
by the gem-name-to-constant mapping** `CLAUDE.md` and §2.3 fix segment for segment
(`dexpace-async-thread` → `lib/dexpace/async/thread.rb` → `Dexpace::Async::Thread`), and the rule's own
remedy — flatten to `Dexpace::Async::ThreadPool` — would break that mapping, which `NFR-4`'s two artifacts
and phase 0's `gates:surface_snapshot` both key on. `Dexpace::Serde::JSON::Codec` (7a) is the same shape
under the same mapping and is the precedent. The rule is satisfied in the direction it can be: the gem
defines **four** constants total and nests nothing below the fourth segment.

---

## The object model `8b` ships

### `Dexpace::Async::Thread` — the entry file

```ruby
Dexpace::Async::Thread::VERSION          # String, phase 0's
Dexpace::Async::Thread::CORE_REQUIREMENT # "~> M.N", the same string the gemspec declares
```

**The version-skew assertion has no registry to travel through, and is made directly.** Spec-forced
boundary 8 says "every adapter's registration asserts `Dexpace::VERSION`", and `P2-1` says there **is no
executor registry** — `SEAM-18` requires the executor to be caller-supplied with no default, and an
auto-resolved executor is exactly that default. The *assertion* is the boundary's substance and the
`Registry#register` call is only its usual vehicle, so `8b` keeps the assertion and drops the vehicle it
has no seam for: the entry file compares `Dexpace::VERSION` against `CORE_REQUIREMENT` with
`Gem::Requirement` at require time and raises `Dexpace::SeamError` naming both versions on skew. Two
consequences the plan must carry: the check runs **before** any `require_relative`, so a skewed pair fails
at `require` rather than at the first `#post`; and a test asserts `CORE_REQUIREMENT` equals the string the
gemspec declares, which is the agreement `gates:gemspec_audit` checks from the gemspec side and nothing
checks from this side. 7a's `P7-7` is the precedent for a require-time assertion in an adapter's entry
file; `P8-21` records this one.

**`Dexpace::Async::Thread` is a module and not the pool.** A caller writes
`Dexpace::Async::Thread::Pool.build(size: 4)`. There is **no module-level default pool, no `.instance`,
no memoised singleton and no `.post`** — `concurrency-and-async/a1ec6ce4` and `SEAM-18` both forbid a
shared global pool, and a convenience constructor on the module would be one by another name.

### `Dexpace::Async::Thread::Pool`

```
Pool.build(size:,
           queue_limit:      nil,   # derived: size * QUEUE_DEPTH_PER_WORKER
           shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT,
           name:             DEFAULT_NAME,
           logger:           Dexpace::Instrumentation::Logger::NULL,
           clock:            Dexpace::Clock::SYSTEM) -> Pool

#post { … }            -> nil     # Dexpace::Page::_Executor; SEAM-18's duck type; ASYNC-2
#delay(duration)       -> Dexpace::Async::Future   # ASYNC-18
#close                 -> nil     # Dexpace::Closeable; ASYNC-15, ASYNC-16, SEAM-25, DEF-31
#closed?               -> bool    # Dexpace::Closeable
#owned?                -> bool    # Dexpace::Closeable — always true; see below
#size                  -> Integer
#queue_limit           -> Integer
#name                  -> String

Pool::QUEUE_DEPTH_PER_WORKER  = 8
Pool::DEFAULT_SHUTDOWN_TIMEOUT = 30.0
Pool::DEFAULT_NAME             = "dexpace-async-thread"
```

`private_class_method :new`, and `.build` validates: `size` and `queue_limit` positive `Integer`s,
`shutdown_timeout` a non-negative `Numeric`, `name` a non-empty `String`, `logger` responding to `#event`,
`clock` responding to `#monotonic`. Every failure is `Dexpace::InvalidArgumentError` with `SEAM-29`'s one
message form, through phase 1's shared helper. That is phase 1's construction pattern applied to a class
that is not a `Data` — the pool holds threads and is mutable by nature, so it is a plain class, which
`data-modeling/3e37c086` is the rule for and which `Dexpace::Clock` (5a) and
`Dexpace::Instrumentation::Logger` (5b) both already are.

**`#owned?` is always `true`, and the two-entry-point rule has nothing to bind.**
`cross-cutting-invariants/093b7681` requires "two differently named entry points, one that builds the
resource and one that borrows it". A pool that borrowed its threads is not a coherent object: the threads
*are* the pool, created by it, and there is no foreign executor for it to wrap — a caller who already has
one passes that one to `Transport.async_over` and never constructs a `Pool` at all. So the pool has one
entry point and one ownership value, and `ASYNC-15`'s clause (b) is discharged at the **bridge**, which is
phase 2's object with `owned: false` and which `8b` asserts rather than implements. The row says so and
does not claim a second entry point exists.

**`clock:` exists here where 5a declined it on `Async.delay`, and the difference is that there is a
consumer.** 5a's argument was that "a `clock:` here would be an `NFR-4`-locked keyword with no consumer and
no test that could drive it". `8b` has two consumers — the shutdown drain's deadline arithmetic and the
timer's — and a fake clock **can** drive one of them: the drain's "did the budget elapse" branch is a pure
comparison of two `#monotonic` readings and a fake that advances on demand exercises the timed-out path
with no real waiting at all. It cannot drive the other (no fake clock makes a real queue wake early — 5a's
own note), and the design says so rather than implying the keyword buys more than it does.

### `Pool::Job` — `private_constant`

```ruby
# Crosses a thread boundary: frozen Data, both members immutable by construction.
# concurrency-and-async/2c743901, /16ceb098.
Job = Data.define(:snapshot, :block)
```

The snapshot is `Diagnostics.capture`'s frozen `Hash`; the block is a `Proc`. **The comment is the rule's
own requirement** — `/16ceb098` asks that every value crossing a concurrency boundary carry a comment
naming the invariant — and the invariant it names is narrower than "frozen", which is the honest part:
the `Hash` is frozen and the `Proc` is immutable, but **the snapshot's *values* are the caller's objects**
and `8b` neither copies nor freezes them. `observability/65191069` records the general form ("copy-on-write
protects the slot, not the object in it"); the consequence here is that a caller who puts a mutable object
into fiber storage shares that object across the hop, which is `XCUT-11`'s "any shared mutable state MUST
be synchronized" and is the caller's obligation. It is stated in the README and in `#post`'s YARD block,
because it is invisible in a single-threaded test and `8b` is the first thing in the repository that makes
it reachable.

### The worker loop, stated as code because four requirements are in its shape

```ruby
def spawn_worker(index)                                   # the ONE Thread.new in this gem
  ::Thread.new do
    ::Thread.current.name = "#{@name} worker #{index}"
    ::Thread.current.report_on_exception = false          # verified fact 10
    ::Fiber.current.storage&.each_key { |k| ::Fiber[k] = nil }   # R8/R9; once per worker
    begin
      while (job = @queue.pop)                            # a suspension point (611b9392)
        run(job)
      end
    ensure
      @exits << WORKER_EXITED                             # non-nil sentinel; verified fact 4
    end
  end
end

def run(job)
  Dexpace::Instrumentation::Diagnostics.with(job.snapshot) { job.block.call }
rescue ::Exception => e                                   # the worker never dies
  Dexpace::Instrumentation.contain(@logger, event: Dexpace::Instrumentation::Events::INSTRUMENTATION_LOG) do
    @logger.event(Dexpace::Instrumentation::Severity::ERROR)
           .event(Dexpace::Instrumentation::Events::INSTRUMENTATION_HOOK)
           .cause(e).emit
  end
  nil
end
```

**Five decisions are in those fifteen lines and each is argued.**

1. **`while (job = @queue.pop)` is the loop, and `nil` is the only exit.** The queue is closed exactly once,
   by `#release`, and a `nil` pop therefore means "closed and drained" unambiguously — the one place in the
   gem where verified fact 4's ambiguity does *not* bite, because nothing ever pushes a `nil` and no
   timeout is used here. The YARD comment says that, because it is the assumption a later edit would break.
2. **The context clear is the first statement and runs once.** `R8`.
3. **`report_on_exception = false` is set *inside* the thread**, because setting it from outside is a race
   (verified fact 10) — and it is set even though the worker is designed never to die, because "designed
   never to die" is a claim about code a future edit can falsify and a stderr line nothing can see is the
   worst possible failure signal.
4. **The net rescues `::Exception` and the worker survives everything, which departs from `RECOV-2`'s rule
   and the departure is `P8-22`.** §5.2's rule is "rescue `Exception`, immediately re-raise anything outside
   `StandardError`, convert the rest", and it exists so a programmer error is never demoted to a handled
   operational error. **On a pool worker, "re-raise" means the thread dies**, and verified facts 10 and 11
   make the consequences concrete: the process does not notice (a worker's `SystemExit` does not exit the
   process, and `exit(3)` on a worker is swallowed entirely), the gate set does not notice (`report_on_exception`
   bypasses `Warning.warn`), and the pool is permanently one worker smaller with no signal — a capacity
   invariant the caller depends on, silently violated by one bad task. So `8b` converts the rule's *purpose*
   into a different mechanism: nothing is demoted, because the error is **not** routed into any caller's
   result — the caller's failure channel was already settled by the block itself (`AsyncOver` rescues and
   calls `Completer#fail`), and anything reaching this net is a defect in the block, which is emitted as a
   `http.instrumentation.*` diagnostic, §3.7's second disposal route, now that phase 5b's facade exists.
   **`Interrupt` is the one case worth naming**: swallowing it on a worker is harmless because `Ctrl-C` is
   delivered to the main thread, and re-raising it would kill the worker for a signal that was never aimed
   at it.
5. **There is no `raise` in `#run` at all**, so `pipeline/f02559b9`'s `raise error, cause: nil` spelling has
   no site here — `8b` never re-raises an error it is carrying. The gem's only `raise`s are the four
   validation raises in `.build` and the two rejection raises in `#post`, all of them raising a fresh error
   about the immediate call, which is the shape a bare `raise Klass, msg` is correct for.

### How a unit of work reaches the pivot, how a caller awaits it, and where the deadlines are

**`8b` writes none of this path and must state all of it**, because three of its IDs (`ASYNC-1`,
`ASYNC-5`, `ASYNC-20`) are satisfied by mechanisms in `dexpace-core` and the temptation is to reimplement
them in the gem that finally exercises them.

**Submission to settlement, in one sequence.** `Dexpace::Transport.async_over(transport, executor: pool)`
returns a `Dexpace::AsyncTransport`. Its `#call(request, options, cancellation)` mints a
`Dexpace::Async::Completer`, **returns `completer.future` before doing anything fallible**, and posts a
block to `pool.post`. The pool captures `Diagnostics.capture` at that moment (`ASYNC-10`), wraps it with
the block in a frozen `Pool::Job`, and pushes it onto the bounded queue — or raises `RejectedError` /
`ClosedError`, which `AsyncOver` routes to `Completer#fail` (`ASYNC-2`). A worker pops the job, installs
the snapshot, and runs the block; the block performs the blocking send, re-checks cancellation on return
(check-after-resume), and calls `Completer#fulfil(response)` or `#fail(error)`. **`#fulfil` on an
already-settled future returns `false` and closes the response it was handed** — which is `SEAM-30` and
`ASYNC-5` satisfied once, in core, for every adapter that routes through `Completer`, and is why `8b` has
no orphan-close code of its own. `#cancel` after settlement is a no-op on the value, which is `ASYNC-20`.

**How a caller awaits, without `Timeout.timeout`.** `future.value(cancellation:, deadline:, clock:)` —
phase 2's blocking read, widened by 5a's `DEF-28`. It blocks on a `::Thread::Queue` pop rather than a spin
or a `Kernel#sleep` poll, so under a registered `Fiber.scheduler` it routes through the scheduler's
`#block`/`#unblock` hooks and unmounts the fiber (verified fact 15), and with no scheduler it blocks the
**calling** thread and never a pool worker. `#wait` is the non-raising form and `#on_settle` the callback
form, invoked on the settling thread-or-fiber — which for this adapter is a **pool worker**, a fact a
caller's `#on_settle` handler must be told about and which the README says: a handler that blocks is
blocking a worker.

**Where every deadline in this design lives, and none of them is ambient.** Four, and they do not overlap:

| Deadline | Whose | Checked at |
|---|---|---|
| The transport's `open_timeout`/`read_timeout`/`write_timeout` | `8a`'s, from phase 5a's layered configuration (`resource-management/d1f16cad`) | A syscall boundary, with a typed exception |
| The caller's await budget, `future.value(deadline:)` | The caller's; a **monotonic instant** on `Clock#monotonic`'s scale (`DEF-28`) | The pivot's queue pop, on the caller's own thread |
| The pool's `shutdown_timeout` | The pool's, fixed at construction (`P8-24`) | Each iteration of the drain loop, as a `clock.monotonic` difference |
| A scheduled delay's interval | The caller's, per `#delay` call | The timer's `pop(timeout:)`, recomputed against the nearest deadline after every wake |

**None of the four is an interrupt and none is enforced by a signal.** That is §8.3's rule stated as an
inventory rather than as a prohibition, and it is the form a reviewer can check: a fifth deadline appearing
anywhere in this gem, or any of the four being implemented with `Timeout.timeout`, is a finding.

### `Dexpace::Async::Thread::Timer` — `private_constant`

`R11`'s implementation. One lazily created `::Thread` named `"#{@name} timer"`, a `::Thread::Mutex`
guarding a deadline-ordered `Array` of frozen entries, and a `::Thread::Queue` used **only as a wake
signal** — never as a value channel, for the reason phase 2 gives about the pivot's queue and verified fact
4 measures. `#schedule(delay) -> entry`, `#cancel(entry)`, `#stop`. The pool's `#delay` owns the
`Completer`; the timer knows nothing about futures, which keeps its whole surface three methods over
`clock.monotonic`.

### `Dexpace::Async::Thread::RejectedError`

```ruby
class RejectedError < ::StandardError
  include Dexpace::Error
end
```

Raised by `#post` when the bounded queue is full. `Dexpace::Error` is phase 1's **module** root, so
`rescue Dexpace::Error` catches it and it is not a `::IOError` — it is not a transport failure and
`XCUT-4`'s two-branch taxonomy is not widened. **It answers no `#retryable?` predicate**, deliberately: the
`#retryable?` protocol belongs to `Dexpace::TransportError` and is the phase-level task's to define, and a
pool rejection never crosses a retry boundary — the rejection happens at the bridge, *above* the pipeline,
so no `RETRY` step can see it. Stated because a phase-9 audit reading `P6-4` will look for the predicate
here.

### Thread-safety proof obligations

**Every mutex in the gem, what it protects, and what it is provably not held across.** There are two, and
neither is the submission queue's — a `::Thread::SizedQueue` is its own synchronisation and `8b` adds none
around it.

| Mutex | Protects | Held across | Never held across |
|---|---|---|---|
| `Dexpace::Closeable`'s (phase 2's, inherited) | the `@closed` boolean | **the flip only** | `#release` — the queue close, the timer stop, the drain wait, the event emission. Phase 2's `Closeable` already releases before `#release` runs; `8b` adds no second lock around close |
| `Timer`'s | the deadline-ordered entry list and the `@thread` slot | a list insert, a list delete, a `first` read, and the lazy creation of the timer thread | the `Queue#pop(timeout:)` wait, the entry's `on_fire` callback, and the `Completer` settle. The timer computes its next wait **inside** the lock and **waits outside** it |

**The rule this satisfies, and why it is not stylistic here.** `concurrency-and-async/c0fab747` asks for the
smallest critical section and `/e94924e3` states the Ruby-specific reason: `::Thread::Mutex` is
per-fiber-owned and non-reentrant (verified fact 9), so a lock held across a suspension point deadlocks two
fibers of one thread. **The concrete hazard in this gem is the timer**: a caller running the pool's
consumer code under `Async { }` has two fibers on one thread, and a timer that held its mutex across
`pop(timeout:)` — a suspension point that routes through the scheduler's `#block` hook (verified fact 15) —
would deadlock them. That is the test the plan writes: **two fibers of one thread, both calling `#delay`
and `#cancel`, under a probe scheduler, asserting no `ThreadError` and both futures settling.** A
single-threaded test passes under the bug; a two-*thread* test passes under it too, because thread-level
mutex ownership would be correct. Only two fibers of one thread can see it.

**The other concurrency assertions, each naming what it would catch.**

- **`#post` from many threads at once**: `size * queue_limit * 2` submissions from 16 threads; every
  accepted unit runs exactly once, every rejected one raises `RejectedError`, and accepted + rejected
  equals submitted. Catches a lost job and a double-run.
- **`#close` from many threads at once**: 16 threads call `#close`; **exactly one** event is recorded and
  every call returns. Catches a latch that is a flag check rather than a latch — `ASYNC-15`(a) and
  `SEAM-25`'s "close twice → executor shut once, one event".
- **`#post` racing `#close`**: a thread posting in a loop while another closes; every call either succeeds
  or raises `ClosedError`, and **none raises `::ClosedQueueError`** — which is the assertion that proves the
  stdlib error is translated on every path and not only on the one the happy test takes.
- **`#post` from inside a task**: a task that posts back to the same pool returns rather than deadlocking,
  and raises `RejectedError` rather than blocking when the queue is full.
- **No thread leaks**: 20 build-and-close cycles leave `::Thread.list.size` at its starting value
  (verified fact 18 as a prototype; asserted as a test).

---

## The `sig/` shape

**Public means a YARD block *and* an RBS signature**, so each of the three public constants gets a `sig/`
mirror at the mirrored path, inside the gem. `Timer` and `Job` are `private_constant` and get neither, and
carry no runtime-surface-manifest row.

```rbs
module Dexpace
  module Async
    module Thread
      VERSION: String
      CORE_REQUIREMENT: String

      class RejectedError < ::StandardError
        include Dexpace::Error
      end

      class Pool
        include Dexpace::Closeable

        QUEUE_DEPTH_PER_WORKER: Integer
        DEFAULT_SHUTDOWN_TIMEOUT: Float
        DEFAULT_NAME: String

        def self.build: (size: Integer,
                         ?queue_limit: Integer?,
                         ?shutdown_timeout: Numeric,
                         ?name: String,
                         ?logger: Dexpace::Instrumentation::Logger,
                         ?clock: Dexpace::Clock) -> Pool
        def post: () { () -> void } -> void
        def delay: (Numeric duration) -> Dexpace::Async::Future
        def size: () -> Integer
        def queue_limit: () -> Integer
        def name: () -> String
      end
    end
  end
end
```

Four things about the shape are decisions rather than mechanics.

- **`#post`'s signature is `Dexpace::Page::_Executor`'s verbatim**, `-> void` and a zero-arity block, so
  the pool satisfies a core-declared interface by declaration rather than by luck. `R12` argues it; the
  agreement is asserted by a test that drives `AsyncPaginator`, not by `respond_to?`.
- **`NFR-11` is satisfied with room to spare, and the reason is worth naming.** No constant outside
  `Dexpace::` appears anywhere above — not `::Thread`, not `::Thread::SizedQueue`, not `::Fiber`. That is
  not luck: the pool's threads and queues are private instance variables with **no readers**, and `#size`
  and `#queue_limit` return the `Integer`s the caller passed rather than `@queue.max` or
  `@workers.length`. `gates:rbs_surface`'s five fixtures test exactly the five positions a foreign type can
  occupy (a return type, a superclass, an `include`, a type alias, a generic bound) and this gem occupies
  none of them. **This is the gem where `NFR-11` is cheapest to satisfy and would be easiest to break** —
  a `#workers -> Array[::Thread]` accessor added for a diagnostic would fail the gate — and the plan's task
  says so at the file.
- **`include Dexpace::Closeable` is declared in the RBS**, so `#close`, `#closed?` and `#owned?` are
  visible to a consumer's `steep check` without being redeclared here. Phase 2's `sig/` carries the
  module's own signatures; restating them would put two declarations of one method into the tree
  `gates:sig_diff` compares.
- **`?queue_limit:` is `Integer?` and not `Integer`, because the derived default is a `nil` sentinel.**
  `queue_limit` cannot default to `size * QUEUE_DEPTH_PER_WORKER` in the parameter list without
  evaluating that expression against an *unvalidated* `size` — `Pool.build(size: nil)` would then raise
  `NoMethodError` from the default rather than `Dexpace::InvalidArgumentError` naming the keyword. So
  `.build` takes `nil`, derives after validating `size`, and the signature says `Integer?` rather than
  declaring a type the default value does not satisfy (which `steep check` reads as an error).
- **`?logger:` and `?clock:` name core types**, which is what keeps them inside `NFR-11`'s allowance —
  `Dexpace::Instrumentation::Logger` and `Dexpace::Clock` are `Dexpace::` constants, and phase 5 made both
  public for exactly this kind of injection.

The plan's final task regenerates **both** the RBS baseline and the runtime surface snapshot, because
`Data.define`'s generated readers on `Pool::Job` are invisible to `rbs validate` — `Job` is
`private_constant` and should therefore appear in **neither** artifact, which is itself an assertion worth
making once (`OI-19` is the standing record that the snapshot's treatment of `Data` readers is not
automatic).

---

## Spec-forced boundaries, honoured

Each of the charter's twenty boundaries is answered by name. The ones belonging wholly to `8a` or `8c` are
listed as not `8b`'s so a reader can see the whole set was read.

1. **The pipeline is the single authority on redirect and retry (boundary 1).** `8a`'s and `8c`'s. `8b`
   ships no transport, disables no native knob, and installs no step.
2. **The streaming contracts impose no timeout; the transport owns every deadline (boundary 2).** `8a`'s.
   **`8b` sets no I/O timeout of any kind** and pushes no deadline into `Dexpace::IO::BufferedSource` —
   its only two deadlines are the shutdown budget and a scheduled delay, neither of which is an I/O
   deadline.
3. **Deadlines are explicit values, never ambient interrupts (boundary 3).** The boundary that binds `8b`
   hardest. `Timeout.timeout`, `Thread#raise` and `Thread#kill` appear nowhere in the gem; the shutdown
   drain is a bounded queue wait against `clock.monotonic` differences and the delay is a deadline-ordered
   list. `Dexpace/NoThreadInterrupt` has nothing to bite, and the plan asserts it with a grep-shaped test
   over the gem's `lib/` rather than relying on the cop alone, because the cop's absence of findings and a
   test's positive assertion are different evidence.
4. **§10.5's three MUSTs are settled and split exactly that way (boundary 4).** `ASYNC-3` ⏳ `DEF-18`;
   `PIPE-33`'s interrupt clause ⏳, cross-reference; `ASYNC-4` **N/A, vacuous, no register row**. The
   mitigation is load-bearing and `8b` does not weaken it: check-after-resume
   (`concurrency-and-async/611b9392`) is honoured at the worker's `Queue#pop` — the earliest resume point
   a queued task has — and `Completer#on_cancel` is left to the object that owns the blocking resource
   (`R10`).
5. **The pivot is core-owned and phase 8's adapters bridge to it and never replace it (boundary 5).** `8b`
   ships **no future, no completer, no settlement and no second cancellation token**. `Pool#delay` returns
   core's `Dexpace::Async::Future`. No `::Thread` appears in any public signature.
6. **`NFR-11` is mechanised as an RBS scan over `sig/` (boundary 6).** See *The `sig/` shape*. This gem
   occupies none of the five positions the gate's fixtures test.
7. **`NFR-2`'s budget is core plus at most one third-party library (boundary 7).** `dexpace-async-thread`
   declares `dexpace-core` and nothing else, **by design and not by accident** (§2.1). `8b` may not reach
   for `concurrent-ruby`; `concurrency-and-async/f414b864` already settled it and `R12` answers the six
   rules the note routes here. The gate proves it from the gemspec; `8b` adds the clean-bundle run that
   proves it from the other side.
8. **Every adapter's registration asserts `Dexpace::VERSION` (boundary 8).** Honoured with the vehicle
   changed and the assertion kept: there is no executor registry (`P2-1`), so the entry file asserts
   directly. `P8-21`.
9. **Ownership is a construction-time fact, not a close-time judgement (boundary 9).** The pool is always
   `owned: true` and has one entry point, because there is no foreign executor to borrow; the
   ownership-aware clause of `ASYNC-15` is discharged at phase 2's bridge, which is `owned: false`, and is
   **asserted** here rather than implemented.
10. **Idempotent close is a latch under a `::Thread::Mutex` held only across the flip (boundary 10).**
    Phase 2's `Dexpace::Closeable`, included and not reimplemented. `8b` adds no second lock around close
    and never holds the latch across the drain — the table under *Thread-safety proof obligations* is the
    proof.
11. **Wire-boundary re-validation raises; `TRANSPORT-12`'s drop is a different rule (boundary 11).** `8a`'s
    and `8c`'s. `8b` validates no header and calls `Dexpace::HeaderSyntax` nowhere.
12. **A pipeline is a transport and closing it is a no-op on the transport (boundary 12).** 4c's. `8b`
    consumes it in one place: `PIPE-33` clause 2's assertion posts a whole `Dexpace::Pipeline` as one unit
    and counts **exactly one** `#post`.
13. **Conformance runs against a local `TCPServer` (boundary 13).** `8a`'s and `8c`'s. **`8b` needs no
    socket fixture** and writes none; its whole test surface is threads, queues, futures and fiber storage.
14. **`dexpace-conformance`'s assertions are framework-agnostic callables (boundary 14).** `8a`'s. `8b`
    writes ordinary Minitest assertions in its own gem and **does not pre-empt the callable-plus-`Failure`
    shape** — 7a's `R12` is the precedent for exactly this restraint. What `8b` owes is the *list* of
    assertions worth lifting, given under *The interface surface later phases may cite*.
15. **Appendix B's phase-8 restatements are fixed by §9.3 (boundary 15).** B.7 is `8b`'s and it is honoured
    literally: `ASYNC-4` vacuous by construction; **`ASYNC-3`'s item recorded as *failing*, not vacuous**,
    and suppressed in the port's own build through a named waiver listing `ASYNC-3`;
    `ASYNC-1`/`2`/`5`/`13`/`14`/`18`/`19`/`20` exercised against the pivot; `ASYNC-8`–`ASYNC-12` against
    fiber storage; `ASYNC-15`–`ASYNC-17` against §3.7. `8b` writes the waiver's text and `8a` owns the
    mechanism that carries it.
16. **The seams are phase 2's and phase 8 registers into them (boundary 16).** `8b` adds no seam, no second
    registry and no competing root — and registers into none, because there is no executor registry.
17. **`SEAM-15` is taken explicitly: a send after close raises `Dexpace::ClosedError` (boundary 17).**
    `8b` is one of the two first raise sites. The open question the boundary leaves to `8a` — whether a
    transport that only *borrows* a client also raises — does not arise here: the pool owns its threads
    unconditionally, so there is no borrowed case.
18. **Bytes on the wire are `Encoding::BINARY` in both directions (boundary 18).** `8a`'s and `8c`'s.
    **`8b` touches no bytes**; the only `String`s it holds are thread names and an error message.
19. **`URI::RFC3986_PARSER` is pinned (boundary 19).** `8b` parses no URL and names no URI constant.
20. **`OBS-19` rides on `TRANSPORT-13` (boundary 20).** `8c`'s. `8b` drops no header and emits no
    drop-logging policy.

---

## Cross-cutting constraints that bite `8b` specifically

- **The forbidden three.** `Timeout.timeout`, `Thread#raise`, `Thread#kill`. **This is the gem a reader is
  most tempted by** — a blocked read on a pooled worker is exactly what `Thread#raise` looks designed for,
  and `ASYNC-3` is a MUST that names it. §10.5 records the trade, `DEF-18` carries the cost, `R10` states
  the residual, and the cop plus a grep-shaped test are what make it a decision rather than a discipline.
- **`::Thread::Mutex` is per-fiber-owned and non-reentrant.** It binds `8b` hardest of any gem: verified
  fact 9 measures both failures, and the two-fibers-on-one-thread test is what proves the timer's lock is
  not held across its wait. Every mutex in the gem is enumerated above with what it is not held across.
- **`Fiber[:key]`, never `Thread.current[:key]`.** Verified fact 5 measures both directions.
  `Thread.current[]` appears nowhere in the gem, and a test asserts that by grep — because the name is the
  one a Ruby author reaches for first and the failure is silent.
- **An abandoned `Enumerator` never runs its `ensure`.** `8b` builds no `Enumerator` and yields no block a
  caller can abandon mid-iteration. The related rule §7.1 states — "resource acquisition and release never
  live inside an `Enumerator` block; the engine owns the resource in its own scope and exposes `#close`" —
  is satisfied in its general form: the pool owns its threads in its own scope and exposes `#close`, and
  verified fact 14 is the measurement that says process exit is not a substitute for calling it.
- **Bytes on the wire are BINARY; `URI::RFC3986_PARSER` is pinned; `downcase` takes no argument.** None of
  the three has a site in this gem, stated so the absence is visible.
- **The bundled-gem rule.** It does not bind an adapter — `dexpace-async-thread` *may* declare — and `8b`
  declares nothing, so the rule is satisfied more strongly than it asks. Verified fact 1 is why that costs
  nothing: every primitive the gem needs is built into the interpreter.
- **`Ractor` is never load-bearing.** `Pool::Job` is a frozen `Data` and is therefore incidentally
  shareable if its members are; **no claim rests on that and no test asserts it**, because the snapshot's
  values are the caller's objects and `Ractor.make_shareable` on one would turn a host's choice into an
  isolation error raised from a logging path (5b's `P5-22`, inherited).
- **Regexp timeouts are per-pattern.** `8b` compiles no regexp.
- **SPDX header and `# frozen_string_literal: true` on every file** (`NFR-13`), including the four test
  support files, which the cop does not treat differently.
- **`Dexpace::Instrumentation::Logger` shadows the stdlib `Logger`** (`OI-26`, `P5-38`). `8b` holds one and
  writes every reference fully qualified. It is also, by verified fact 13's argument, the *second* shadow
  this gem must be careful about — the first being its own namespace.

---

## Testing strategy

Seven groups. Three of them exist because a measured fact showed the obvious test would pass under the bug.

1. **Construction and validation** — `size` required; `size`/`queue_limit` rejecting `0`, a negative and a
   non-`Integer` with `SEAM-29`'s message form naming the keyword; `queue_limit` defaulting to
   `size * QUEUE_DEPTH_PER_WORKER`; `name`, `logger` and `clock` defaulting; `Pool.new` being private.
   Plus the entry file's `CORE_REQUIREMENT` agreeing with the gemspec, and the skew assertion raising
   `Dexpace::SeamError` naming both versions for a stubbed mismatched `Dexpace::VERSION`.
2. **`#post` and rejection (`ASYNC-2`)** — a unit runs on a worker and not on the caller's thread (asserted
   by `::Thread.current.object_id`, not by a sleep); `#post` **returns in bounded time with a full queue**,
   asserted from a thread whose `#join(1)` must not be `nil`; a full queue raises `RejectedError`; a closed
   pool raises `Dexpace::ClosedError` and **never `::ClosedQueueError`**; and — the assertion that makes
   `ASYNC-2` a requirement rather than a claim — `Transport.async_over(t, executor: closed_pool).call(…)`
   returns a **future that completes exceptionally**, with nothing raised synchronously from `#call`.
3. **Lifecycle (`ASYNC-15`–`ASYNC-17`, `SEAM-25`, `DEF-31`)** — close twice → one event, one shutdown,
   both calls return; 16 concurrent closes → **exactly one** event; an in-flight task **finishes** rather
   than being interrupted; queued work drains; a task still queued when `#close` runs still runs;
   `Transport.async_over(t, executor: pool).close` leaves the pool **open and usable**, which is
   `ASYNC-15`(b) and `XCUT-22`; and a lambda-shaped async transport's `#close` is a safe no-op
   (`ASYNC-17`).
4. **Diagnostics (`ASYNC-8`–`ASYNC-12`)** — the three-context sequence `ASYNC-10`'s conformance clause
   names (assemble under A, execute under B, re-execute under C), on **one reused worker**; a task that
   **throws** with the worker's context intact afterwards; an absent context capturing as `{}` and
   installing as a clear; and **the two negative assertions the measured facts demand**:
   - **a key set at pool-build time and absent from the caller's snapshot is not visible to the task**
     (verified fact 7 — the test that fails without `R8`'s clearing line and passes with it), and
   - **the pool is built in a *different* context from the one it is driven from**, in a `setup` that sets
     the build-time key and a test body that sets a different caller key. A suite that builds the pool in
     the test body, in the caller's own context, passes under the bug.
   Every test touching `Fiber[]` restores the slot in `teardown` (`testing/4ef070df`), and a
   `teardown`-order assertion proves the restoration itself.
5. **`#delay` (`ASYNC-18`)** — negative raises **before** a timer thread exists (asserted by
   `::Thread.list` being unchanged); zero returns an **already-settled** future and still spawns no timer;
   a positive delay settles after at least the interval, measured as a `clock.monotonic` difference with a
   lower bound and no upper bound; three concurrent delays fire in deadline order on **one** timer thread
   (asserted by `::Thread.list.count` over the pool's name); cancelling a future removes the entry and the
   block never fires; `#close` fails every outstanding delay with `Dexpace::ClosedError`; and a pool that
   never scheduled a positive delay has **no** timer thread to stop.
6. **The bridge, end to end (`ASYNC-1`, `ASYNC-5`, `ASYNC-13`, `ASYNC-14`, `ASYNC-19`, `ASYNC-20`,
   `PIPE-33`)** — `Transport.async_over(fake, executor: pool)` delivering the exact `Response` object;
   a failure arriving as the **same exception object** (`assert_same`, which is `ASYNC-13`'s whole
   assertion); the exact `RequestOptions` object arriving at the wrapped transport (`ASYNC-19`);
   `ASYNC-5`'s window — cancel after the worker produced a closeable response and before delivery, assert
   `#close` called **exactly once**; `ASYNC-20`'s negative twin — deliver, then cancel, assert the response
   is **not** closed; `AsyncTransport.sync_over(…)` round-tripping and surfacing `CancelledError` rather
   than an `::IOError` (`ASYNC-14`); and `PIPE-33` clauses 2 and 3 through a real multi-step
   `Dexpace::Pipeline` — **exactly one `#post`** and the identical options object.
7. **Concurrency and the two-fiber deadlock proof** — the five assertions listed under *Thread-safety proof
   obligations*, of which the load-bearing one is **two fibers of one thread** driving `#delay` and
   `#cancel` under the probe scheduler, asserting no `ThreadError` and both futures settling. A
   single-threaded test and a two-**thread** test both pass under the bug this one catches.

**How a slow or stuck task is simulated, without `Timeout.timeout` and without a sleep.** Every "slow"
task in the suite is a block that pops a `::Thread::Queue` the test controls: the task blocks until the
test pushes, so the test decides when the task finishes and the assertion is about ordering rather than
duration. Every "stuck" task is the same gate never pushed, released in `teardown`. The three places a real
duration is unavoidable — the delay's interval, the shutdown budget's expiry and the timeout-versus-close
disambiguation — use a **small interval with a lower-bound assertion and no upper bound**, because an upper
bound is what makes a timing test flaky on a loaded machine, and the shutdown-budget expiry additionally
gets a **fake clock** test that exercises the timed-out branch with no waiting at all.

**No test overrides Minitest's seed and no fixture is shared across tests** (`testing/4ef070df`): every
test builds its own pool in `setup` and closes it in `teardown`, and the teardown asserts the pool's
threads are gone. A module-level pool shared by the file would make every test order-dependent and would
hide the thread-accounting assertion.

**The clean-bundle isolation run, extended.** A scratch `Gemfile` holding `gem "dexpace-core", path: …`
and `gem "dexpace-async-thread", path: …` and nothing else, then `bundle exec ruby -e` requiring
`dexpace/async/thread`, building a pool, posting a unit, awaiting a future through the bridge and closing —
on **every Ruby in the matrix**. Bundler refuses to activate a gem outside the bundle, so this is the run
that proves the zero-third-party claim rather than asserting it, and the **4.0 row is load-bearing** for the
same reason it is for core: a `require` of a gem that became bundled would fail there and nowhere else.

**The CI matrix.** 3.2 / 3.3 / 3.4 / 4.0, running the **real suite** on each — not a syntax check, because
`TargetRubyVersion` catches syntax and not stdlib availability (§9.2). For this gem the matrix carries a
second load: **facts 5 through 8 and 10 are re-run as tests on every row**, so `Fiber[]`'s inheritance,
`Fiber[:k] = nil`'s deletion and the pooled-worker leak are properties the suite asserts on each
interpreter rather than properties a design document measured once. That is what clears
`observability/65191069`'s single-interpreter caveat permanently rather than for one day.

---

## The interface surface later phases may cite

Stated as a contract, so a later phase cites rather than re-derives.

| Consumer | What it gets, and the obligation |
|---|---|
| **`8a`**, on the conformance harness | **Nothing from `8b`'s code, and three assertion shapes worth lifting.** `8b` writes no part of `DEF-22`'s protocol or the `TCPServer` fixture (`R16`: `8b` is on neither side). What it hands `8a` is the list: **(i)** `SEAM-25`/`ASYNC-15`'s "close twice → executor shut once, one event", which needs a recording sink and no socket; **(ii)** `XCUT-22`'s "a BYO executor passed to a bridge is never shut down", which is one line and is the clause an adapter author satisfies by accident on the first call; **(iii)** `ASYNC-2`'s "submit through a shut-down executor → the future completes exceptionally", which is adapter-agnostic and belongs in the shared suite rather than in this gem |
| **`8a`**, on `ASYNC-3`'s waiver | The waiver's text — a named suppression listing `ASYNC-3` and citing `DEF-18` and §10.5 — which §9.3 requires and which `8a` owns the mechanism for. `8b` writes the words; `8a` builds the thing that carries them |
| **`8a`**, on `Completer#on_cancel` | **The hook is the transport's, not the pool's** (`R10`). `8a` decides whether `dexpace-transport-net_http` registers one to close its socket under a blocked read, and inherits two constraints from here: the woken `IOError` must not be classified as a retryable transport failure when a cancellation caused it (`XCUT-2`, `TRANSPORT-3`), and `max_retries = 0` is required for the abort to surface at all (the charter's verified facts 1 and 11) |
| **`8a`**, on `DEF-29` | **A corrected premise.** The charter's `DEF-29` disposition says "`8b` drives phase 2's `FakeTransport` from a suite outside `dexpace-core`". It does not: `8b` writes its own doubles, because phase 0's `test_helper.rb` puts only *this gem's* `lib` on the load path and a `require_relative` into another gem's `test/` tree is the cross-gem reach styleguide 12.6 forbids. **That strengthens `8a`'s UNSCHEDULED recommendation rather than weakening it** — the cheapest correct answer for the first consumer outside core was a ten-line double, which is evidence the three fakes are not in fact shared. `8a`'s mark should cite this sentence rather than the charter's |
| **`8c`**, on `ASYNC-6` | `8b`'s stated half: cancelling the pivot reaches a thread-pool worker only at its next check-after-resume point, which is `ASYNC-3`'s unsatisfied mode and not a second decision. `8c` owns the row and the bidirectional property; `8b` owns the sentence that makes its own absence a decision |
| **`8c`**, on `ASYNC-7` | The thread half of the contrast, written in `gems/dexpace-async-thread/README.md`: an in-flight blocking read **runs to completion**. `8c` writes the reactor half and owns the conformance row asserting the two differ as documented (convergence point 3) |
| **`8c`**, on the pool | **Nothing.** `async-http` runs on `Async::Task` under a `Fiber.scheduler`, and verified fact 15 adds that a pool worker sees `Fiber.scheduler` as `nil` regardless. A `8c` test that installs a `dexpace-async-thread` pool is testing `8b`'s gem |
| **`8c`**, on the deadline and cancel contract | **`8b`'s side, stated so `8c` can honour it without reading this document.** (i) `8b` **enforces no I/O deadline of any kind** and pushes none into a stream — its only two deadlines are the pool's construction-time `shutdown_timeout` and a `#delay` interval, and the deadline inventory above is exhaustive (a fifth deadline in this gem is a finding). Every transport deadline is the transport's, on both paths. (ii) `8b` **registers no `Completer#on_cancel`** (`R10`): the abort-shortening hook belongs to whoever owns the blocking resource, so `8c` owns its own on `Async::Task` exactly as `8a` owns its own on the socket, and neither inherits a hook from here. (iii) A cancelled pivot reaches a thread-pool worker only at its **next check-after-resume point** and never as an interrupt; `8c` is free to do better through `Async::Task#stop` and that difference is `ASYNC-7`'s documented contrast, not a divergence to reconcile. (iv) `#post` hands out no runtime-native handle, so nothing `8c` writes can cancel through the pool |
| **Phase 9**, on `XCUT-11` | The five concurrency assertions above as the audit's existing evidence — in particular the **two-fibers-on-one-thread** test, which is the only shape that proves a per-fiber mutex is not held across a suspension point |
| **Phase 9**, on `XCUT-13` and `XCUT-22` | `Pool#close` as the bounded, non-blocking, latched shutdown, and the bridge assertion that a caller-supplied executor survives its holder's close. Both satisfied by construction through §3.7 and asserted rather than argued |
| **Phase 9**, on `SEAM-12` | The `#post`-from-16-threads and `#post`-racing-`#close` assertions, which are "concurrency safety is a property of an implementation" for the one seam implementation that is not a transport |
| **`dexpace-async-async` (`DEF-11`)** | The pool is **not** its precedent. That gem bridges a *caller-held* `Async::Task` to the pivot in both directions, which is `SEAM-24`'s second sentence and a different shape entirely; what it inherits from `8b` is the `ASYNC-7` README obligation and the `ASYNC-9` context-hop shape, not the pool |
| **A downstream SDK author** | `Dexpace::Async::Thread::Pool.build(size:)` plus `Dexpace::Transport.async_over(transport, executor: pool)` as the whole of "make my blocking transport async with nothing installed", and `Pool` as the worked example of what a `SEAM-18` executor owes: a `#post` that does not block, a rejection through the failure channel, an idempotent ownership-aware close, and a per-submission context capture |

---

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`.

**Numbering, and the collision risk stated rather than discovered.** Phase 8's rows are `P8-<n>`, and
`8a`, `8b` and `8c` are being written concurrently and cannot coordinate. **No `P8-<n>` exists anywhere in
`docs/` as of this writing** (verified 2026-09-11; the charter's `P8-<n>` is a placeholder, not a claim).
This document takes 7b's **reserved band** rather than 7c's start-at-one — `P8-1`–`P8-19` for `8a` (which
runs first under the charter's recommended order), **`P8-20`–`P8-35` for `8b`**, and
**`P8-36`–`P8-50` for `8c`** (widened from `P8-36`–`P8-40` on 2026-09-12, with the correction stated:
the narrower form named only `8c`'s *used* rows and left `8c` no headroom, which is the thing a reserved
band exists to give). **The charter now fixes the allocation once**, under its own *Deviation Ledger*,
and every phase-8 document cites that rather than restating a fourth version; `8c` uses `P8-36`–`P8-40`
and `P8-41`–`P8-50` stay unallocated.
A gap in a phase-local numbering is harmless; a three-way collision at filing time is not. If the human
filing the three documents prefers contiguous numbers, renumbering is safe **today** because no `P8-<n>` is
cited outside phase-8 documents yet — but it must happen in the same change that files all three, and it is
resolved at consolidation into design §10 in any case. (**The band was narrowed from `P8-20`–`P8-39` on
2026-09-12**, in the verification pass, to leave `8c` the block it takes; `8b` uses six of
its sixteen and has no prospect of needing twenty.)

**One thing that is deliberately *not* a ledger row.** `8b`'s plan widens phase 0's
`RequireAllowlist.reason_for` by one alternative so the bare `require "dexpace"` is exempt alongside the
`"dexpace/"` prefix (verified fact 1's correction). That is a repair to a sibling phase's gate, not a
departure from the reference contract, and this ledger is the record of the latter; it is carried as a
step of the plan's Task 1, with a regression test, rather than as a `P8-<n>`.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P8-20 | **A pooled worker clears its inherited fiber storage once, at thread start**, so the caller's captured context is *installed* rather than *merged onto* whatever the pool creator's fiber happened to hold. Design §8.1 describes the adapter as saving, installing and restoring and does not mention the floor underneath | `ASYNC-9`, `ASYNC-10`, `ASYNC-12`; design §8.1 (`:136-142`); `OBS-24`; `P5-23`; `observability/65191069`; verified facts 5, 7, 8 | Measured: a pool built while `Fiber[:tenant] = "assembly"` was set runs a caller's task with `tenant: "assembly"` visible, through phase 5b's `Diagnostics.with` exactly as written, because `::Thread.new` inherited it at construction and the caller's snapshot has no key to overwrite it with. That is `ASYNC-10`'s "stale snapshot from when it was assembled" reaching a log line the caller believes describes their own call, and it is **invisible in any test that builds the pool in the same context it submits from**. The repair is one line, once per worker, on a `Hash` `Fiber.current.storage` already returns fresh — not a change to 5b's `.with`, which is correct for its own consumer, and not `Fiber#storage=`, which `OI-13` and `P5-23` both rule out. The residual `P5-49` records (a prior key holding a literal `nil` restores as absent) is doubly harmless here: after the clear there is no prior key at all |
| P8-21 | **The version-skew assertion is made directly in the gem's entry file**, with `Gem::Requirement` against `Dexpace::VERSION`, rather than through `Dexpace::Registry#register`'s required `core:` keyword | `SEAM-10`'s replacement (`DEF-21`, `P2-7`); §2.3's version-skew guard; `P2-1`; charter boundary 8 | `P2-1` established that **there is no executor registry**, because `SEAM-18` requires the executor to be caller-supplied with no default and an auto-resolved executor is exactly that default. The boundary's substance is the assertion, not the call that usually carries it, so the assertion is kept and the vehicle is dropped. Two properties are preserved and one is added: the failure is at `require` time and names both versions (§2.3's whole purpose), the keyword is not optional because there is no keyword, and a test asserts `CORE_REQUIREMENT` equals the gemspec's declared string — the agreement `gates:gemspec_audit` checks from one side and nothing checked from the other. 7a's `P7-7` is the precedent for a require-time assertion in an adapter entry file |
| P8-22 | **A pool worker rescues `::Exception` and never dies**, where `RECOV-2`'s rule (design §5.2) is "rescue `Exception`, immediately re-raise anything outside `StandardError`, convert the rest" | `RECOV-2`; design §5.2; `ASYNC-15`; `error-handling/3bfdf6f0`; verified facts 10, 11 | On a worker thread, "re-raise" means the thread dies, and three measurements say nothing would notice: a worker's `SystemExit` does not exit the process and `exit(3)` on a worker is swallowed entirely; `Thread#report_on_exception` writes to `$stderr` **directly and not through `Warning.warn`**, so phase 0's warnings-fatal gate cannot see it; and the pool is then permanently one worker smaller with no signal, which is a capacity invariant the caller depends on silently violated by one bad task. The rule's *purpose* — never demote a programmer error to a handled operational error — is served by a different mechanism rather than abandoned: the error is **not** routed into any caller's result (the block already settled the future through `Completer#fail` before the net could see anything), and what reaches the net is a defect in the block, emitted as an `http.instrumentation.*` diagnostic through §3.7's second disposal route, which phase 5b's facade made available and phase 2 and 4b did not have. `Interrupt` is the case worth naming: `Ctrl-C` is delivered to the main thread, so swallowing it on a worker discards nothing |
| P8-23 | **`#post` never blocks the calling thread**: the submission queue is a bounded `::Thread::SizedQueue` used with the **non-blocking** push, so a full queue is a `RejectedError` rather than a parked producer — where `concurrency-and-async/dc345cae` names `SizedQueue`'s blocking backpressure as the mechanism | `ASYNC-2`; `SEAM-18`; `PAGE-30`; `concurrency-and-async/dc345cae`, `/171f800d`; verified fact 2 | Four reasons, of which the first is normative. `ASYNC-2` names "worker-pool rejection (**a saturated**/shut-down executor)" as a failure that MUST arrive through the future; a blocking `#post` gives this adapter **no saturated case at all** and kills half the requirement's antecedent. Second, `Transport.async_over#call` promises a future and phase 2 makes it return that future before doing anything fallible — a `#post` that parks moves the blocking from the transport, where the caller asked for it, to the submission, where they did not. Third, `PAGE-30` was designed against a raising `#post` ("every `#post` call site is wrapped"). Fourth, a task that posts back to the same pool would park a worker waiting for a worker. The rule's *purpose* — a producer cannot race arbitrarily ahead of consumers — is met exactly by the bound; only its side effect is declined. Rejected alternatives: a caller-runs policy runs a blocking send on the caller's thread inside an async call; a `on_saturation:` keyword is `OI-8`'s shape |
| P8-24 | **`#close` takes no arguments**: the graceful-drain wait is bounded by a **construction-time** `shutdown_timeout:` and carries no `cancellation:` token, where design §3.7 writes the wait as "§8.3's cancellable queue wait **and** a bounded deadline" | `ASYNC-15`, `ASYNC-16`, `XCUT-13`; design §3.7 (`:493-497`); `OI-8` | The wait **is** a queue wait and it **is** bounded, so two of the sentence's three elements are taken literally. The token is declined for a mechanical reason: `Dexpace.close_quietly(resource)` is the single sanctioned exit §3.7 itself defines and it calls `#close` with **no arguments**, so a `cancellation:` keyword would be unreachable from the one call site that matters — an `NFR-4`-locked keyword with no caller, which is `OI-8`'s shape and what `P5-2` exists to keep deliberate. A second, differently named `#shutdown(cancellation:)` was considered and rejected: two names for one latch, and the `#close` duck type's whole value is that a `Response`, an `IO`, a `Tempfile` and a pool answer the same message. §3.7's stated harm — "a caller who closes inside a cancelled scope is not parked" — is prevented by the budget: such a caller waits at most `shutdown_timeout` and never forever |
| P8-25 | **`ASYNC-18`'s "without blocking a thread" is satisfied for the caller's thread and every worker thread, and not absolutely**: one timer thread per pool is parked for the interval, lazily created on the first positive delay | `ASYNC-18`; `CFG-18`; `P5-9`; design §8.3; verified facts 15, 16 | Phase 5a's `Dexpace::Async.delay` raises `Dexpace::SeamError` with no `Fiber.scheduler`, and `Fiber.scheduler` is **per-thread** (verified) — a pool worker sees `nil` however the caller's thread is configured, so core's delay is unavailable to this adapter unconditionally. Inheriting that raise would leave `ASYNC-18`, a **MUST**, unimplemented in the only adapter that has it, where `CFG-18` is a SHOULD and could afford it. What the clause protects is the *carrier*: "cancelling the future cancels the scheduled task **so no scheduler thread is held**". Both halves hold exactly — the caller is never parked, no pool worker is ever parked, and a cancelled delay is removed and the timer re-computes. What does not hold is the absolute reading, and one named thread (`"<name> timer"`, identifiable in a thread dump) is the cost. A thread per delay is unbounded creation; a pool worker starves the pool at `n = size`, which is `SEAM-18`'s own failure. A second code path delegating to core's delay under a scheduler was rejected: a delay that fires on the caller's reactor never completes for a caller who then blocks outside it |

---

## Deferrals filed by phase 8b

**None.** Seventeen of `8b`'s nineteen IDs are implemented here; `ASYNC-3` is `DEF-18`'s, which already
exists and whose pick-up condition ("if an interruptible transport path is ever adopted") `8b` does not
meet; and `ASYNC-4` is vacuous and on no register row. **`8b` adds no unsatisfied MUST, no unsatisfied
SHOULD clause with a register row, and no new `DEF-<n>`.** Design §12's `ASYNC` row — "*Deferred:* none" —
is unchanged by this document.

### Deferral-register sweep

`8b`'s delta against the charter's whole-register sweep, which covered all forty-two rows once and is not
repeated here. As with phases 3 through 7, this document **states** each disposition and `8b`'s **plan
performs** the register edit.

- **`DEF-31` — picked up and closed by `8b`.** Its condition names this gem: "The first thing in this
  repository that actually **owns** an executor is phase 8's `dexpace-async-thread`, so phase 8 is where
  the emission gets a real subject and where `dexpace-conformance` asserts 'close twice → executor shut
  once, one event'." `8b` supplies the subject: `#release` emits `Events::INSTRUMENTATION_SHUTDOWN` at
  `Severity::INFO`, inside `Instrumentation.contain`, **exactly once**, asserted under 16-way concurrent
  close. Phase 5b shipped the event name and the field shape and added a dated line to `Status` without
  moving the row; `8b` moves `Status` to `picked-up (<date>, phase 8b)`. The *harness* half of the
  condition — the assertion living in `dexpace-conformance` — is `8a`'s, and `8b` hands it the shape under
  *The interface surface later phases may cite* rather than writing it.
- **`DEF-1` — untouched, and `8b` supplies the fact the charter's proposed amendment rests on.**
  `SEAM-24`'s **first** sentence ("propagate the ambient logging/diagnostic context across the thread
  handoff") is `ASYNC-8`'s and `8b` implements it through `Fiber[]`, within fiber storage. Its **second**
  sentence — "Each adapter's cancellation bridge SHOULD map cancellation in both directions" — is a
  *caller-facing* bridge over the host's own primitive, which design §3.3 (`:252-254`) assigns to
  `dexpace-async-async` and which is `DEF-11`, post-v1. **`8b` bridges no caller-held primitive**: it hands
  out no `::Thread`, `#post` returns `nil`, and the only handle a caller holds is the pivot. So `8b` does
  not meet the second sentence and does not claim to. The row's `Status` stays **deferred** and is **not**
  UNSCHEDULED, because the condition it names is post-v1 and unmeetable here. The charter proposes the
  `Status` amendment; `8b` performs no register edit for it.
- **`DEF-18` — untouched, and carried as one ⏳ row plus one cross-reference plus one N/A that is not on
  the row.** Its condition is "if an interruptible transport path is ever adopted", which §8.3 forbids and
  `8b` does not adopt — so **not UNSCHEDULED**. The row's `Cites:` line is `ASYNC-3, PIPE-33`, so `8b`
  carries `ASYNC-3` ⏳ **citing `DEF-18`**, `PIPE-33`'s cross-reference row citing it too, and `ASYNC-4`
  N/A **citing §10.5 and no register row at all**. **`8b` does not edit `DEF-18`**: its `Cites:` line is a
  committed, adversarially reviewed row and the register's rules permit only a `Status` edit, which this
  phase does not earn.
- **`DEF-29` — `8b`'s premise correction, and the mark is `8a`'s.** The charter marks it UNSCHEDULED and
  cites, among its reasons, that "`8b` drives phase 2's `FakeTransport` from a suite outside
  `dexpace-core`". **`8b` does not.** Phase 0's `test_helper.rb` puts only *this gem's* `lib` on the load
  path, and a `require_relative` into `gems/dexpace-core/test/support/` is the cross-gem reach styleguide
  12.6 forbids — worse here than a style violation, because it would make this gem's suite depend on a
  path that exists only in the workspace. `8b` writes its own doubles, which is what phases 3a, 5b, 7a and
  4c each did. **That strengthens the UNSCHEDULED recommendation rather than weakening it**: the first
  consumer outside core found a ten-line double cheaper than a shared fake, which is evidence the three
  fakes are not in fact shared. `8b` performs no mark; `8a` does, and should cite this sentence.
- **`DEF-28` — closed in 5a, and named because `8b` is the first consumer of the half that was added.**
  `Future#value`/`#wait` gained `deadline:` and `clock:`. `8b` uses neither on the pivot — its own waits
  are on its own queues — but the **`deadline:` is a monotonic instant, not a duration** convention is the
  one `8b`'s shutdown budget follows, so the repository has one meaning for the word. No action.
- **`DEF-27` — closed in 4b and 5b, and `8b` is the first adapter to use the route it opened.**
  `close_quietly`'s two disposal routes now exist; `8b`'s worker net uses the second (the
  `http.instrumentation.*` diagnostic) for an error that has no primary exception to attach to. No action,
  and named because `P8-22`'s argument depends on that route existing.
- **`DEF-21` — closed in phase 2, and `8b` is the one adapter its mechanism does not fit.** `P8-21` states
  what `8b` does instead and why. No action on the row: the guard it describes is the registry's, and `8b`
  registers nothing.
- **`DEF-11`, `DEF-12` — untouched, and `8b` is what makes the line §2.2 draws observable.**
  `dexpace-async-thread` proves the pivot with a thread pool; `dexpace-async-async` and
  `dexpace-async-concurrent_ruby` are second adapters over an already-proven property and wait. Neither
  condition is met and neither is marked.
- **`DEF-32` — untouched.** `Hooks.notify`'s dropped handler failures were resolved by phase 4b. `8b`
  notifies no hook list of its own; the one it touches indirectly is `Cancellation::Source`'s, through
  `Completer#on_cancel`, which is phase 2's.
- **`DEF-33` — untouched, and its value is higher after this phase than before it.** A non-CRuby matrix
  row. `8b`'s pool is the fifth and most acute case of a concurrency guarantee resting on a
  `::Thread::Mutex` the GVL would hide the absence of — and it is the first case where the *object under
  test is the concurrency*, rather than a lock incidental to something else. No v1 phase plans a JRuby or
  TruffleRuby row and `8b` does not propose one; the row's `Why` is worth one added sentence and the
  charter's sweep already says so.
- **`DEF-22`, `DEF-23`, `DEF-25`, `DEF-42`, `DEF-3`, `DEF-10`, `DEF-41` — `8a`'s and `8c`'s.** `8b` writes
  no conformance assertion object, no `TCPServer` fixture, no dispatch-path header re-validation, no tracer
  emitter, no file-body transfer and no header-drop policy. Named so the sweep is visibly complete rather
  than visibly partial.
- **`DEF-2`, `DEF-4`–`DEF-9`, `DEF-13`–`DEF-17`, `DEF-19`, `DEF-20`, `DEF-24`, `DEF-26`, `DEF-30`,
  `DEF-34`–`DEF-40` — untouched.** Other prefixes, other phases, or post-v1 gems. **`DEF-30` is worth one
  sentence** because `8b` must not meet it by accident: presence-gated auto-activation is permitted "for
  instrumentation only" and "no transport or codec adapter may ever use it". `dexpace-async-thread` is
  neither, and it activates nothing at all — **it registers into no registry**, which is the strongest
  available form of the restriction and is `P2-1`'s consequence rather than `8b`'s choice.

---

## The findings proposed for the registers

**Four, described here for a human to file. None is acted on by this document and no register file is
edited by it.** Three target `docs/open-items.md` and **carry numbers as of 2026-09-12**; the fourth
targets `docs/deviations.md` and carries none, because it is an attribution note against design §10.5 and
`OI-<n>` is `docs/open-items.md`'s namespace, not that register's.

**The numbers, and why they are safe to write down now.** This section previously left them blank, on the
ground that the charter's `OI-34`–`OI-37` and two concurrent sibling sets made any choice a collision
waiting to be renumbered. That reasoning was right while the three designs were being written
independently and is now spent: all three sets are written and none has moved. **`8b`'s three are
`OI-46`–`OI-48`**, following `8a`'s `OI-42`–`OI-45` — 8a before 8b, in sub-phase order, so the ordering
rule is statable rather than incidental. A filer still checks before pasting, with
`ruby .claude/skills/housekeeping/probe.rb --only citations`: fifteen numbers (`OI-34`–`OI-37` from the
charter, `OI-38`–`OI-41` from `8c`, `OI-42`–`OI-45` from `8a` and these three) are cited across phase 8
with no row in the register yet, which is the expected state and not drift. If any of the fifteen is filed
under a different number, every one after it shifts and the shift is mechanical — nothing in phase 8 cites
an `OI-4x` from source code, only from these documents.

Each row below is written in `docs/open-items.md`'s own item format — `### OI-<n> — <title>`, then
`Opened` (the register's found-by field: a date and the phase that found it), `Status`, `Cites`, the body,
and a `**Resolution:**` line — so filing is a paste rather than a re-derivation.

**Target register: `docs/open-items.md`. Proposed id `OI-46`.**

> ### OI-46 — a pooled worker inherits the pool creator's fiber storage, so the repository's context-restore mechanism leaks assembly-time context into a caller's task
>
> - **Opened:** 2026-09-11, phase 8b design
> - **Status:** open
> - **Cites:** ASYNC-9, ASYNC-10, ASYNC-12, OBS-23, OBS-24, XCUT-11

**A pooled worker inherits the pool creator's fiber storage, so the repository's context-restore mechanism
leaks assembly-time context into a caller's task — and nothing in `docs/knowledge/` or design §8.1 says
so.** Design §8.1 fixes the adapter's shape as "saves the worker's prior storage, installs the captured
snapshot for the work's duration and restores it in an `ensure`", and phase 5b's `Diagnostics.with`
implements exactly that with a **merge** on install (`snapshot.each { |k, v| Fiber[k] = v }`), which is
correct for 5b's own consumer and for `OBS-24`. Measured on Ruby 3.4.10: a pool built while
`Fiber[:tenant] = "assembly"` was set, driven by a caller whose captured context is
`{"trace.id" => "CALLER-A"}`, runs the task with `{"trace.id" => "CALLER-A", :tenant => "assembly"}`
visible — because `::Thread.new` inherited `:tenant` at pool construction and the snapshot has no key to
overwrite it with. That is `ASYNC-10`'s "a stale snapshot from when it was assembled", and it is invisible
in every test that builds the pool in the same context it submits from. **Phase 8b fixes it for its own
gem** with a one-time clear of inherited storage at worker start (`P8-20`), and the *finding* is that the
hazard is a property of **any** long-lived carrier this repository creates with `::Thread.new` — a future
`dexpace-instrumentation-otel` background exporter, a `dexpace-async-concurrent_ruby` pool, or a caller's
own worker wrapped in `Diagnostics.with` — and neither the design sentence nor the harvested rule warns
about it. What would resolve it: either a sentence in §8.1 (a frozen chapter, so not now) or the knowledge
note `8b` files below, which is the route taken. Nothing is broken today because nothing is implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/open-items.md`. Proposed id `OI-47`.**

> ### OI-47 — `Dexpace::Bridge::AsyncOver`'s posted block re-checks cancellation on return and not before dispatch, so a task cancelled while queued still performs its network round-trip
>
> - **Opened:** 2026-09-11, phase 8b design
> - **Status:** open
> - **Cites:** SEAM-18, SEAM-30, ASYNC-3, ASYNC-5, PIPE-33, XCUT-3

**`Dexpace::Bridge::AsyncOver`'s posted block re-checks cancellation on return and not before dispatch, so
a task cancelled while queued still performs its network round-trip.** Phase 2's design describes the block
as "perform[ing] the blocking send, re-check[ing] cancellation on return". The worker's
`::Thread::Queue#pop` is one of the four suspension points `concurrency-and-async/611b9392` enumerates, so
the block begins executing immediately after a resume — the earliest check-after-resume point a queued task
has — and a single `cancellation.cancelled?` test there would turn a wasted round-trip into no round-trip.
**Nothing is broken**: `ASYNC-3`'s third clause requires only that a queued task not be *interrupted*,
which holds because nothing is ever interrupted; `SEAM-30`/`ASYNC-5` close the orphan through
`Completer#fulfil`'s losing-race branch; and no response reaches a cancelled caller. What is lost is one
network call, one connection from the pool, and — on a non-idempotent method — one **server-side side
effect a caller believed they had cancelled**, which is the half that makes this worth a row rather than a
micro-optimisation. **It is filed rather than fixed because it is `dexpace-core`'s code**: `AsyncOver` is
phase 2's, committed and reviewed, and `dexpace-async-thread` cannot see the token — the pool posts an
opaque block by design (`concurrency-and-async/08a0e08d`), which is also what lets the same object serve
`Dexpace::Page::_Executor`. The repair is one `if` at the top of the posted block and belongs to whoever
next amends phase 2. `OI-18` is the same species from the same object: a core mechanism correct about what
it was designed for and silent about a case a later gem made reachable. Nothing is broken today because
nothing is implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/open-items.md`. Proposed id `OI-48`.**

> ### OI-48 — `Thread#report_on_exception` writes to `$stderr` directly, so a dying thread is invisible to the warnings-fatal gate that exists for exactly this
>
> - **Opened:** 2026-09-11, phase 8b design
> - **Status:** open
> - **Cites:** NFR-7, NFR-17, XCUT-11, ASYNC-15

**`Thread#report_on_exception` writes to `$stderr` directly, so a dying thread is invisible to the one gate
that exists for exactly this.** Phase 0's gate set runs the real suite under `ruby -w` with warnings
failing the build, and its shared test case **overrides `Warning.warn` to raise** — which is what catches
`IO::Buffer`'s experimental warning (7a's `P7-5`) and `Fiber#storage=`'s (`OI-13`). Measured on 3.4.10: a
thread that dies with an exception prints `#<Thread:…> terminated with exception (report_on_exception is
true)` to `$stderr` and the `Warning.warn` override captures **nothing**. So a suite that leaks a dying
thread — a test double's worker, a helper's background thread, a future adapter's exporter — produces
stderr noise no gate reads and no assertion fails. **Phase 8b's own workers cannot die** (`P8-22`) and set
`report_on_exception = false` inside the thread body anyway, so this gem is not the subject; the finding is
that **the repository's warnings-fatal gate does not cover thread death**, and phase 8 is the first phase
to create threads at all. What would resolve it: a shared test-case addition asserting `::Thread.list.size`
is unchanged at `teardown`, which is a phase-0 artifact and a one-line change — cheaper than the class of
bug it catches, and `8b`'s own suite already asserts it per-test. Nothing is broken today because nothing
is implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/deviations.md`, as an entry to add when design §10 is next amended. No `OI-<n>`,
deliberately** — `docs/deviations.md` is the as-built audit of design §10's ledger and is a judgement
register rather than a mechanical append; an attribution note filed with an open item's number would
resolve to a row in the wrong file.
**§10.5's mitigation sentence names `Completer#on_cancel` as something "an adapter" does, and phase 8 has
three adapters of which only one can.** §10.5 reads: "the check-after-resume rule (§3.3) aborts the worker
at its next resume point, and `Completer#on_cancel` lets an adapter shorten that by **closing the socket
under the read**". `dexpace-async-thread` owns no socket and cannot register such a hook — the pool posts an
opaque block and does not know what is inside it — so on the thread path the mitigation reduces to
check-after-resume alone, and the "shorten" half belongs entirely to the transport
(`dexpace-transport-net_http`, `8a`). The sentence is not wrong; it is unattributed, and a phase-9 audit
reading `DEF-18` will look for the hook in the gem whose name appears two sentences earlier. The addition:
one clause naming the transport rather than "an adapter", recorded in `docs/deviations.md` as the as-built
audit of item 5 until §10 is deliberately amended by a human. Cites: `ASYNC-3`, `ASYNC-6`, `PIPE-33`,
`TRANSPORT-3`, `DEF-18`.

**Two rows explicitly do not close.** `OI-13`'s subject is `Fiber#storage=`, a call `8b` does not make —
`R8` removes the problem rather than resolving the row, and the row stays open for whoever does call it.
`OI-22`'s missing `CFG-20` citation is phase 5a's; `CFG-20`'s unmet clause is `ASYNC-3`'s under a second ID
and **`8b` adds no fourth unsatisfied MUST for it to point at**.

---

## The knowledge note `8b` files

Drafted here; the plan's final task writes it to `docs/knowledge/notes/observability.md`, beside the two
entries already there. It is a **`## Reference`** entry rather than a `## Superseded` one, because it does
not contradict `observability/65191069` — it adds the consequence that entry's "copy-on-write protects the
slot, not the object in it" sentence does not reach. The same task **clears that entry's own
single-interpreter caveat** by re-running its measurements on 3.2.11 and 4.0.6 and amending the note to say
so, which the charter names as a phase-8 obligation.

```markdown
## Reference
- **A pooled worker inherits the *pool creator's* fiber storage and sees nothing set afterwards, so a
  merge-shaped context install leaks assembly-time context into a caller's task.** Beside
  `observability/65191069`, which records that copy-on-write protects the slot and not the object in it;
  this is the other half of the same write-side story and it decides an implementation. Measured on Ruby
  3.4.10: `::Thread.new` inherits `Fiber[]` at the moment the thread is created, and a worker created
  before a key was set reads `nil` for it — so a pool's workers carry whatever the fiber that called
  `Pool.build` happened to hold, and nothing the caller does later reaches them. Phase 5b's
  `Diagnostics.with` merges on install (`snapshot.each { |k, v| Fiber[k] = v }`), which is exact for its
  own consumer and for `OBS-24`; on a pooled worker the merge leaves the inherited keys visible underneath
  the caller's snapshot, so a pool built under `Fiber[:tenant] = "assembly"` runs a caller's task with
  `tenant: "assembly"` on its log lines. That is `ASYNC-10`'s "a stale snapshot from when it was
  assembled", and it is invisible in any test that builds the carrier in the same context it submits from.
  `dexpace-async-thread` fixes it for itself with one line at worker start —
  `::Fiber.current.storage&.each_key { |k| ::Fiber[k] = nil }`, safe because `Fiber.current.storage`
  returns a fresh `Hash` — after which merge and replace agree and the union restore returns the worker to
  empty. **The rule generalises to any long-lived carrier this repository creates with `::Thread.new`**: a
  background exporter, a second executor adapter, or a caller's own worker wrapped in `Diagnostics.with`.
  Neither `Diagnostics.with` nor design §8.1 needs changing; what needed stating is that the carrier must
  start empty.
  <sub>review · `docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-design.md` · high · sha:manual-phase8b-pooled-worker-context-floor</sub>
```

---

## Reference

Every external claim this document makes, with where to re-resolve it.

| Claim | Source |
|---|---|
| The 19 IDs, their levels and their canonical text | `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md:589-608`; the prose and `*Conformance:*` clauses in `docs/product-spec/18-asynchronous-runtime-adapter-contract.md` |
| `SEAM-16`, `SEAM-17`, `SEAM-18`, `SEAM-24`, `SEAM-25`, `SEAM-30` | `docs/product-spec/03-pluggable-seams-and-extension-model.md:17-20`, `:44-45` |
| `PIPE-33`'s five clauses | `docs/product-spec/08-execution-pipelines.md:40`; the accounting at `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md:151-165` |
| The pivot, check-after-resume, `ASYNC-7`'s README rule | `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:189-294` |
| The close contract, the `@owned` boolean, the non-blocking-shutdown constraint stated for this gem | `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:452-518` |
| The executor duck type as `#post { }`, core shipping no implementation | `docs/sdk-design-ruby/05-pipeline-architecture.md:192-194`; `concurrency-and-async/08a0e08d` |
| Fiber storage as the carrier and this gem's save/install/restore | `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:136-142` |
| The prohibition on `Timeout.timeout`/`Thread#raise`/`Thread#kill` and its three consequences | `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:195-231`; `docs/sdk-design-ruby/10-…md:30-57` |
| Appendix B.7's restatement, the `ASYNC-3` waiver, Minitest as the framework | `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:65-113` |
| The `ASYNC` coverage row and the MUST-level summary | `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:42`, `:49-55` |
| The gem's charter sentence and its zero-third-party budget | `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:24`; phase 0's skeleton table |
| `Diagnostics.capture`/`.with`, `P5-23`'s per-key union restore, the forward table naming this gem | `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md:1571-1572`, `:2111`, `:2150` |
| `Fiber[:k] = nil` deletes; `Fiber[]=` emits no warning; `P5-49`'s residual | `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md:524-532`, `:730-800` |
| `Dexpace::Clock`, `Clock::SYSTEM`, `Async.delay`'s `SeamError`, `deadline:` as a monotonic instant | `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md:898-1000`, `:1190-1240` |
| `Dexpace::Page::_Executor`'s RBS and its assignment to this gem | `docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md:871`, `:1320` |
| The version-skew guard and the absence of an executor registry | `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md:579-604`, `:1286`, `:1304` |
| `Completer`, `Future`, `Settlement`, both bridges, `Closeable`, `close_quietly`, `ClosedError` | `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md:686-940`, `:1070-1122` |
| The six custom cops, the require allowlist and denylist, the seventeen gates | `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:250-270`, `:430-475`, `:515-535`, `:355-365` |
| The six bounded-pool corpus rules routed to this gem | `concurrency-and-async/6764e0b5`, `/dc345cae`, `/df658d73`, `/3692970f`, `/047644ea`, `/dd8e6d2d`, routed by `concurrency-and-async/f414b864` |
| Every Ruby fact | *Verified Ruby facts* above, each with its command; the probe scripts are session-scratchpad only and are not committed |

---

## Open questions for `8b`'s own plan

Six, each bounded, none reopening a decision above.

1. **`QUEUE_DEPTH_PER_WORKER`'s exact value.** 8 is this document's choice and the *shape* of the decision
   is settled — a depth per worker rather than an absolute capacity, so the bound scales with the `size`
   the caller chose. **Open:** whether 8 is the right depth. *Recommendation:* keep 8 and do not tune it
   against a benchmark, because the number that matters is the caller's `size` and a depth chosen against
   one machine's timing would read as a measured value when it is a burst-tolerance policy. The plan
   states the reasoning in the constant's YARD block, which is what
   `concurrency-and-async/6764e0b5`'s "named, **documented** constant" asks for.
2. **`DEFAULT_SHUTDOWN_TIMEOUT`'s exact value, and whether it should exist at all.** 30.0 seconds is this
   document's choice, reasoned as "long enough to outlive one in-flight HTTP send". **Open:** whether the
   keyword should instead be required, the way `size:` is. *Recommendation:* keep the default. The
   asymmetry with `size:` is defensible and worth stating: a wrong `size` is a *starvation* bug that
   persists for the life of the pool, while a wrong `shutdown_timeout` costs at most one slow shutdown —
   and a required keyword on a close-time budget would make the common construction three keywords long for
   a value most callers have no opinion about. The YARD block says it should exceed the transport's own
   read timeout and why.
3. **The two adapter-private field keys on `DEF-31`'s event.** The event name is core's
   (`Events::INSTRUMENTATION_SHUTDOWN`) and settled. **Open:** the spelling of the worker-count and
   drained-flag field keys, which 5b's `Keys` does not carry and which `8b` must not add to core.
   *Recommendation:* `"dexpace.executor.worker_count"` and `"dexpace.executor.drained"`, as
   `private_constant` frozen `String`s in the pool — private because `dexpace-conformance`'s assertion is
   "close twice → one event" and needs the event name only, and a public field key would be an `NFR-4` lock
   with one reader inside the gem that owns it.
4. **Whether the `ASYNC-7` README section belongs in `README.md` alone or also in `Pool`'s YARD block.**
   `ASYNC-7` says "document, per adapter"; `concurrency-and-async/74aee9a8` says "in its README".
   *Recommendation:* the README is the requirement's home and `Pool#close`'s and `#post`'s YARD blocks
   carry a one-line cross-reference to it — because a caller reading `#post`'s signature in their editor is
   exactly the reader who needs to know an in-flight blocking read runs to completion, and a YARD block
   that restates the whole section would be two sources for one rule.
5. **Whether the fake clock is a test double or a second `Dexpace::Clock`-shaped support file worth
   naming.** `8b` needs one to drive the shutdown budget's timed-out branch with no real waiting. 5a
   already wrote a clock double for `CFG-15`'s suite, in core's `test/`, which `8b` cannot reach
   (`DEF-29`'s disposition). *Recommendation:* `8b` writes a five-line `StubClock` in its own
   `test/support/`, implementing exactly `#monotonic` and raising `NotImplementedError` from `#now` and
   `#sleep` — so a later edit that reaches for either fails loudly rather than silently using a stub that
   was never designed for it. The plan should not attempt to share 5a's.
6. **The three-interpreter re-run, and specifically facts 5 through 8.** Task 1 of the plan installs 3.2.11
   and 4.0.6 and re-runs every fact. **`R8`'s route is conditional on `Fiber[:k] = nil` deleting the key on
   all three** — 5b's `P5-23` records the same condition and the same repair (the restore loop deletes
   explicitly rather than assigning; the mechanism is unchanged and only the loop body moves), and `8b`
   inherits both. **`R9`'s clearing line is conditional on fact 6** (a pooled worker seeing nothing set
   after it started) holding on all three; if some Ruby propagated later writes into existing threads, the
   clearing line would still be correct but `ASYNC-12`'s row would need re-argument. And the run is what
   clears `observability/65191069`'s own caveat, which is a phase-8 obligation the charter names and which
   no other sub-phase can discharge.
