# Phase 4c — Stage-Based Pipeline

**Status:** Draft, for review. Written 2026-09-08, after the phase-4 segmentation design and the 4a and 4b
sub-phase designs, and before any phase-4 plan or checklist exists.

## Purpose

The third and last sub-phase of phase 4, and the largest: **40 requirement IDs, all `PIPE`**, the whole of
`docs/product-spec/08-execution-pipelines.md` §8.1. It ships the user-facing dispatch runtime — the frozen stage
ordering, the pillar exclusivity rules, the surgical composition edits, the per-call cursor with its fork, the
async mirror, and the two `PIPE-39` seeding shapes — and it ships the one generic adapter that installs a phase-4b
`Dexpace::Recovery::Transform` into a non-pillar stage.

**What this document is.** The brainstormed design for 4c: what it builds, what it does not, the five risks the
charter assigned it resolved with evidence, and every public constant it locks under `NFR-4`. It is not a plan and
not a checklist; it names no numbered task and writes no code.

**Three things a reader should take from it before anything else.**

1. **`4c` ships no bridge.** `PIPE-33` and `PIPE-34` are satisfied by *composition*: a built pipeline is a
   transport (`PIPE-26`), so phase 2's `Dexpace::Transport.async_over(pipeline, executor:)` and
   `Dexpace::AsyncTransport.sync_over(async_pipeline)` are the bridges, unchanged. The charter's spec-forced
   boundary 15 is honoured by adding nothing rather than by being careful (P4-35).
2. **Cursor-scoped state is keyed by `(stage, key)`, not by key alone**, and its only write is an argument to
   `#fork`. That is the resolution of R11, it is a departure from §5.1's "a small keyed map", and it is what makes
   §6.2's own sentence — "no step downstream of AUTH can [set the marker] either" — literally true rather than
   true only of non-pillar steps (P4-28, P4-29).
3. **The standard-resilience preset ships as a mechanism with no step set.** `PIPE-24`'s all-or-nothing
   installation is a general `Builder` operation, real and tested today against probe steps; the redirect / retry /
   instrumentation *set* it would install does not exist until phases 5 and 6 and is deferred as **`DEF-39`**.
   Nothing in this phase claims to install defaults while installing nothing (R14, P4-34).

## Governing documents

- `docs/product-spec/08-execution-pipelines.md` — §8.1 in full, its introduction, and §8.3's two-layer
  prohibition; read in full for this document. `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`
  rows 189–228, the canonical text of all 40 `PIPE` IDs.
- `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1 and §5.3 in full, §5.2 for the boundary,
  §5.4 for the `equal?`-versus-`==` trap the pillar-idempotence rule repeats;
  `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.2's cross-origin-marker paragraph, which is
  what R11 is built for; `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.3 (deadlines, the
  prohibition); `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.2, §3.3 and §3.7;
  `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items 5 and 15;
  `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` items 11, 12
  and 16; §12's `PIPE` row.
- `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md` — the charter. Its scope table, its sixteen
  spec-forced boundaries, its `PIPE-33` clause accounting, and R8 and R10–R14.
- `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` — **R8 is a contract this
  document consumes**, and R9's namespace decision is what the adapter's argument type is named by.
- `docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-design.md` — cited where 4c uses it, which
  is in one optional place (`Dexpace::BoundedMap`, not used; see *Prerequisites*).
- `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` — the transport duck types, the async
  pivot, `Cancellation`, `Closeable`, and the two `SEAM-18` bridges phase 2 recorded as phase 4's to reuse.
- `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md`,
  `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`,
  `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`, `CLAUDE.md`, `docs/README.md`.

---

## Scope

### The 40 IDs, with dispositions

Taken from the charter's scope table and not re-derived.

| Disposition | IDs | Count |
|---|---|---|
| ✅ Implemented | `PIPE-1`–`PIPE-32`, `PIPE-34`, `PIPE-35`, `PIPE-37`, `PIPE-38`, `PIPE-40` | 37 |
| ⏳ partially unsatisfied — `DEF-18`, §10.5 | `PIPE-33` (the interrupt clause only) | 1 |
| ⏳ deferred — `DEF-4` (pre-existing), post-MVP | `PIPE-36` (SHOULD, pillar-step stage locking) | 1 |
| ⏳ deferred — **`DEF-39`** (new), phase 6 | `PIPE-39` (SHOULD, the standard-resilience constructor half) | 1 |

**The charter's table and this one differ by one row, and the difference is stated rather than absorbed.** The
charter puts `PIPE-39` under ✅. This document moves it to ⏳ against `DEF-39`, because R14's resolution ships one
of `PIPE-39`'s two named constructors and defers the other. The charter reserved that call for 4c in as many
words — "`4c` decides whether the preset ships empty and validating …, ships as a deferral, or ships with a
phase-6 pick-up condition" — and names the expected register row: "`4c`'s disposition of `PIPE-24`'s
standard-resilience preset before any pillar family exists (R14)". So this is the row the charter predicted, not a
scope change. `PIPE-24` stays ✅ because its subject is the *installation semantics*, which ship in full; see R14.

`PIPE-32` is ✅ **and its content is split**: its documentation clause is discharged here, and the clause about the
async standard pipeline's behaviour holds vacuously until `DEF-39`'s constructor exists to create one. That is
recorded in R14 rather than as a fourth ⏳ row, because the requirement's own antecedent — an async standard
pipeline — is not something this phase declines to build so much as something no phase-4 object is.

### The canonical text the design turns on

Quoted from appendix C, because a paraphrase is what a design gets wrong.

- **`PIPE-2`** — "The runtime MUST preserve the pillar precedence chain REDIRECT then RETRY then AUTH then LOGGING
  then SERDE (outer to inner), plus an outermost pre-redirect slot that runs OUTSIDE both the redirect and retry
  loops and a terminal SEND transport hop that runs innermost. … (SERDE is a reserved slot in the ordering with no
  shipped behavior yet.)"
- **`PIPE-3`** (SHOULD) — "The stage list SHOULD interleave user-extensible (non-pillar) slots around each pillar
  (a 'pre' slot before and a 'post' slot after) so callers can position steps at a precise point relative to a
  pillar without editing pillar internals. Numeric order keys SHOULD be sparse to allow inserting new stages later
  without renumbering existing ones."
- **`PIPE-6`** — "Re-installing the SAME step onto its pillar MUST be idempotent (no error, no duplication).
  Reference identity, not value equality, distinguishes 'same' from 'distinct'."
- **`PIPE-9`** — "An empty pipeline (no steps) MUST dispatch the request directly to the terminal transport,
  threading the caller's per-call options, and return/complete with the transport's result. It SHOULD do so
  without allocating per-call cursor state."
- **`PIPE-10`** — "The built runtime MUST be immutable after construction (fixed ordered step collection + fixed
  transport reference), and each send/sendAsync MUST allocate its own per-call cursor so concurrent calls share no
  mutable pipeline state."
- **`PIPE-11`** — "Steps MUST be safe to invoke from multiple threads concurrently, because a single step is
  shared across all calls. Per-request mutable state MUST live in the per-call cursor (carried and forked by
  next), never on the step."
- **`PIPE-15`** — "A step that drives the downstream chain MORE THAN ONCE … MUST fork a fresh cursor for each
  re-drive (the copy() operation) rather than reusing the same next handle. Reusing the same handle resumes past
  the already-visited steps and MUST be treated as a defect. A port MUST provide an equivalent fork primitive and
  its wrapping pillar steps MUST use it."
- **`PIPE-16`** — "A forked cursor MUST resume from the SAME position as its parent (re-running the entire
  downstream tail from that point), carry the current in-flight request, and share the immutable per-call options;
  forks MUST advance independently of one another."
- **`PIPE-18`** — "The surgical insert-after / insert-before edit MUST place a step immediately after/before the
  FIRST existing step that is an instance of a given anchor type. The inserted step MUST declare the same stage as
  the matched anchor; a cross-stage insert MUST be rejected with an error rather than silently relocating the step
  to wherever its own stage falls."
- **`PIPE-24`** — "The standard-resilience preset MUST install its pillar steps into EMPTY slots only, validating
  up front that none of the target pillars is already occupied and rejecting the whole call (installing nothing)
  if any is. It MUST NOT overlay onto or overwrite already-configured pillars."
- **`PIPE-25`** — "build() MUST produce the ordered step sequence by flattening stages in declaration order
  (skipping SEND) into an immutable runtime, and the runtime MUST expose a read-only, ordered view of its steps
  for inspection."
- **`PIPE-28`** — "The async runtime MUST reuse the identical stage identities and staging policy as the sync
  runtime (same ordered stage list, same pillar exclusivity, same surgical-edit semantics), so a given concern
  occupies the same ordered slot in both runtimes. The two runtimes MUST NOT each re-derive ordering
  independently."
- **`PIPE-30`** — "The async runtime MUST defensively normalize ANY synchronous exception thrown by a step's async
  entry point (or by the empty-pipeline transport dispatch) into an exceptionally-completed future, so one step's
  mistake cannot break the pipeline's async contract. Fatal/unrecoverable errors (e.g. out-of-memory / stack
  overflow) MUST propagate synchronously and MUST NOT be swallowed."
- **`PIPE-31`** — "The async terminal response-mapping operator MUST, on success, apply the handler and then close
  the response (idempotent double-close tolerated); on failure it MUST unwrap async wrapper exceptions to the
  original cause before failing the returned future, and MUST close any response that accompanies a failure to
  avoid leaking the body."
- **`PIPE-37`** — "A step whose correctness depends on observing only the SINGLE terminal response (e.g. mapping a
  non-successful status to a typed error) MUST be placed at the outermost pre-redirect slot so it runs outside
  both the redirect and retry loops, and on a non-error status it MUST return the response untouched (body not
  read, consumed, or closed)."
- **`PIPE-38`** — "When adding a batch of steps, append-all MUST preserve the batch's iteration order within each
  stage, while prepend-all (each element prepended individually) MUST result in the REVERSED batch order within
  each stage. A port MUST document this asymmetry so callers get predictable ordering."
- **`PIPE-40`** — "A wrapping step that re-drives the downstream chain … MUST release each superseded intermediate
  response — closing its body before issuing the next drive — and MUST NOT close the response it ultimately hands
  back to the caller (close-responsibility passes outward to the caller or the next outer step). On paths that
  abandon a re-drive (redirect cycle detected, non-replayable body, hop/attempt budget exhausted) the in-flight
  response MUST be returned unclosed."

### `PIPE-33`'s five clauses, enumerated

The charter did this accounting; it is reproduced because a checklist row citing `DEF-18` must not be read as a
wholly unbuilt requirement, and **the trade §10.5 settled is not re-opened here or anywhere in this phase**.

| # | Clause | Status in phase 4c |
|---|---|---|
| 1 | "MUST require a caller-supplied executor (no default)" | **Met.** Core defines the executor as a `#post`-shaped duck type and ships no implementation (`SEAM-1`, `SEAM-18`); 4c ships no executor either, so there is no default to fall into. The `executor:` keyword on `Transport.async_over` is required and phase 2 asserts it |
| 2 | "MUST run the wrapped synchronous pipeline as a single opaque unit on that executor (… its own steps stay synchronous on the worker/dispatch thread and do NOT gain per-step concurrency)" | **Met structurally.** A built pipeline *is* a transport (`PIPE-26`), so `Transport.async_over(pipeline, executor:)` posts one `#call` and the steps never see the executor. Asserted here with a counting fake executor: exactly one `#post` for a multi-step pipeline |
| 3 | "MUST thread the caller's per-call options into the wrapped synchronous send" | **Met.** Phase 2 asserts the exact object arrives at the wrapped transport; 4c re-asserts it through a pipeline with steps in between |
| 4 | "cancelling without interruption MUST complete as cancelled without interrupting the worker" | **Met** exactly by `Future#cancel` |
| 5 | "Cancelling the returned future with interruption MUST interrupt the worker running the in-flight send" | **Not met.** Interrupt-mode cancellation is the mechanism design §8.3 forbids repository-wide, so every cancellation on this bridge behaves as the non-interrupting mode. §10.5 states the residual gap and the mitigation and is not re-argued here. `DEF-18` |

**Two constraints follow and bind this design.** They are the charter's and are restated because both are load-bearing:

1. **No default executor.** 4c ships no executor implementation and no factory that would supply one.
2. **No deadline-less unconditional block.** `PIPE-34`'s wait is `future.value(cancellation:)`, never a bare wait
   with neither a token nor a deadline, and never `Timeout.timeout`. 4c ships no wait at all (R13), which is the
   strongest available form of the constraint.

### Out of scope, explicitly

| Excluded | Owner |
|---|---|
| The redirect, retry, auth and instrumentation **pillar step families** | 5 and 6. 4c ships the slots they occupy, the fork they use, and the cursor state they write |
| `REDIR-11`'s cross-origin marker, `AUTH-29`'s reading of it | 6. 4c ships the two cursor-state rules the marker rests on and nothing of the marker itself (R11) |
| `RETRY-1`–`RETRY-45` — both retry stacks, the shared backoff calculator, the pacing parser | 6, and `DEF-35`'s fifteen `RECOV` rows with them |
| `Dexpace::Outcome`, the two chains, the orchestrator, the three shipped transforms | **4b.** 4c consumes `Dexpace::Recovery::Transform` and ships one adapter over it; it ships **no** second implementation of an idempotency key, a client-identity line or a status mapping, and does not subclass the three |
| `Dexpace::Transport.async_over`, `AsyncTransport.sync_over`, the executor duck type, `SEAM-30`'s orphan close, the pivot's normalisation | **2, built.** Charter boundary 15; P4-35 |
| `CTX`'s promotion chain, `ContextStore`, `Instrumentation::Bundle` | **4a.** Nothing in `PIPE` consumes any of it — the charter's central finding, re-confirmed below |
| `deadline:` on any blocking wait, the clock behind it | 5 (`DEF-28`) |
| `ASYNC-3`, `ASYNC-4` | 8 marks them (`DEF-18`, §10.5) |
| `TRANSPORT-1`, `TRANSPORT-2` — disabling a native client's own redirect and retry | 8. They presuppose `PIPE` as the single authority, which is what this sub-phase makes true |
| `SERDE`'s behaviour | Nobody in v1. `PIPE-2` says outright that SERDE "is a reserved slot in the ordering with no shipped behavior yet"; 4c ships the slot and nothing in it |

---

## Prerequisites, and the independence this sub-phase must state

**The charter's finding, restated because it is a rule and not a courtesy: every phase-4 boundary is a
convenience, not a dependency.** A 4c plan whose first task waits on a 4a or 4b artefact has re-imposed a chain
that does not exist. Concretely:

- **4c does not consume 4a at all.** No `PIPE` requirement mentions an execution context; the token `CTX-<n>`
  appears in no specification chapter outside ch.07 and in no design section outside §5.4, §8.1, §11.11 and §12
  bar one `CTX-9` comparison in §5.2 that reads nothing from it. 4a offered `Dexpace::BoundedMap` to 4c
  "if `PIPE`'s per-call cursor ever needs a bounded keyed map"; **it does not** — cursor-scoped state is a small
  frozen `Hash` per fork with no cap, because a cursor lives for one call and the number of forks in one call is
  bounded by `REDIR-17`'s hop cap and `RETRY-27`'s attempt cap, both of which are phase 6's and neither of which
  is a *store* the way `CTX-11`'s is. 4c therefore declares no bounded map and takes no dependency on 4a.
- **4c consumes exactly one thing from 4b**, `Dexpace::Recovery::Transform`, and that consumption is a data
  dependency on a value type, not an ordering dependency: every stage, cursor, fork and edit rule in this design
  is built and tested against probe steps, which is what `PIPE-1`'s own conformance clause prescribes ("one probe
  step per stage records entry/exit"). If 4b landed after 4c, the only casualty would be the three adapter tests.

**From phase 0** — seventeen blocking gates, unchanged and unlowered. Four bite here.
`gates:require_allowlist` — **4c adds nothing to the allowlist**: the stage table is `Data` and frozen `Array`s,
the cursor is a frozen `Hash` and two ivars, and the async runtime reaches only phase 2's pivot.
`gates:surface_snapshot` and `gates:sig_diff` regenerate for a large new public surface — larger than 4a's or
4b's. `Dexpace/NoThreadInterrupt` is what keeps `PIPE-33`'s residual gap a stated deviation rather than a
temptation, and it is the cop a `PIPE-34` implementation would trip first. `Dexpace/QualifiedCoreConstant`
(P2-8, extended by P3-7) matters because `Dexpace::Pipeline::Entry#step` and `Dexpace::Pipeline::Cursor#request`
sit one line from phase 1's `Dexpace::Request`.

**From phase 1** — `Dexpace::Model` (with the `#with` override routing through the validating `.build`, because
`Data#with` skips an `initialize` override on 3.2.11); `Dexpace::Builder`; `Dexpace::Error` as a **module**;
`Dexpace::InvalidArgumentError < ::ArgumentError`; `Dexpace::Request`, `Dexpace::Response`, and — decisively —
`Dexpace::RequestOptions` with its frozen `RequestOptions::EMPTY`, which is `PIPE-17`'s "immutable/shared, not
copied-and-diverged per fork" satisfied for free. Four phase-1 rules bind every file 4c writes: public wire-model
constants are flat unless the design namespaced the subsystem (§5.1 and §5.3 name `Dexpace::Pipeline::Stages`, so
`Pipeline` is a namespace this design keeps; `Dexpace::PipelineError` is named flat by §5.1); no `.build` is a
bare `new` wrapper; `Dexpace::ArgumentError` is never defined; `downcase` takes no argument.

**From phase 2** — the largest inheritance, and the reason 4c is smaller than 40 IDs suggests:

- `Dexpace::Transport` as a duck type over `#call(request, options, cancellation) -> Response`, with
  `.conforms?`'s parameter-shape predicate. **This is what `PIPE-26` satisfies "for free"** and what `PIPE-13`'s
  terminal dispatch calls.
- `Dexpace::AsyncTransport` — the same shape returning a `Dexpace::Async::Future`; a separate top-level constant
  and a separate registry (P2-1), which is the precedent `Dexpace::AsyncPipeline` follows (P4-36).
- `Dexpace::Async::Future` / `Async::Completer` / `Async::Settlement`, with `#value(cancellation:)`,
  `#on_settle`, `#cancel`, the check-after-resume rule, and `SEAM-30`'s orphan close. **`PIPE-29`/`PIPE-30`'s
  normalisation at the *bridge* is phase 2's `Completer#fail` routing, already built and already tested**; what
  4c adds is the same rule at a different call site — a step's async entry point — which no phase-2 object
  invokes. That distinction is drawn precisely under *The spec-forced boundaries, honoured*.
- **`Dexpace::Transport.async_over(transport, executor:)` and `Dexpace::AsyncTransport.sync_over(transport)`** —
  phase 2's `SEAM-18` bridges, with phase 2's own design recording the obligation: "phase 4 wraps a
  `Dexpace::Pipeline` with `Transport.async_over` and does not reimplement the executor contract, the orphan
  close or the normalisation." **This is the single largest reduction in 4c's cost and it is not optional**
  (R13, P4-35).
- `Dexpace::Cancellation`, `Cancellation.none`, `Cancellation::Source`, `#on_cancel`/`#off_cancel`. `.none` is
  the third argument's default at every 4c entry point.
- `Dexpace::Closeable` with its latch, `Dexpace.close_quietly`, `Dexpace::ClosedError`. **`PIPE-27` is
  `Closeable` with `owned: false`** — the exact shape phase 2 gave both bridges, so closing a pipeline latches
  and releases nothing and never cascades to the transport.
- `Dexpace::Registry` and three seam registries — **4c adds no fourth.** A pipeline is not a discovered provider;
  it is something a caller builds.

**From phase 3** — `Dexpace::Body` with its default no-op `#close` (P3-23); `Response#close`, `#body_string`,
`#body_bytes`; `Closeable#closed?` read under the close mutex (P3-6). `PIPE-31`'s "idempotent double-close
tolerated" and `PIPE-40`'s "close each superseded intermediate exactly once" are both properties of phase 3's
latch, not of anything 4c writes, which is why both are asserted here rather than implemented.

**From phase 4b** — `Dexpace::Recovery::Transform`, its `#phase` and `#apply(value)`, and the three transforms.
The contract is R8's and is consumed rather than restated; see *The generic adapter*.

**Two open items land in 4c's window and neither is 4c's to fix.** `OI-8` (`TeeSink#clear_tap`) and `OI-9`
(`BufferedSource.wrapping`) both name a window that closes when phase 3's plans execute; 4c neither widens nor
closes them. `OI-6` (RuboCop's own report is not clean under `.rubocop.yml` as phase 0 wrote it) is the one a 4c
implementer will meet first, and it is phase 0's.

---

## Corpus reading, and what it settled

**The phase-start pair was run first, and neither is a formality here.**

`ruby scripts/knowledge.rb --origin note --brief` returns **35 entries across 18 note files** at the time of the
query, 36 after the note this document files —
`docs/knowledge/notes/pipeline.md` is the newest, filed by 4b at `e2a1299`. `--section conflicts --brief` returns
**24 entries across 17 topic files, 18 of them notes**, so six are the harvested styleguide-versus-design
conflicts themselves; **all six print `[overridden by notes/…]`** —
`data-modeling/35fde90f`, `module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and
`/8c0687bf`, `tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`. **None is open**, so 4c inherits no
unresolved conflict and owns no conflict decision of its own.

**`OI-16`'s caution applies, was applied, and this document makes it worse before it makes it better.** The CLI
prints `[overridden by notes/…]` for every key a note backticks, including rules the note explicitly adopts.
**Before** this document's own note landed, three markers inside this phase's material were adoptions rather
than supersessions, and were read rather than assumed: `pipeline/c76ca402` and `pipeline/77de2b12` are named by
`notes/pipeline.md` as **"unaffected and adopted verbatim"**, and `execution-context/7459f067` is 4a's
drain-loop note, which does not reach `PIPE` at all. **After** it there are six, because the note below
backticks three more rules it adopts rather than weakens — `pipeline/591329b5` and `pipeline/debd2eb6` (the
`PIPE-15` fork rule in its design and spec voices, both implemented as written) and
`concurrency-and-async/c0fab747` (the smallest-critical-section rule, which the no-lock decision *follows*).
So seven keys in this phase's material now print the marker and **exactly one is genuinely superseded** —
`pipeline/b3f74458`, whose content is `RECOV-10`'s re-raise, 4b's and not 4c's. A reader who treats the marker as
evidence will conclude that phase 4 overturned **six** rules it in fact obeys. `concurrency-and-async/c0fab747`
is the sharpest case and worth naming for the plan: it now carries **three** override markers, from
`notes/concurrency-and-async.md`, `notes/execution-context.md` and `notes/pipeline.md`, and all three adopt it.
`OI-16` is the row that records why the tool cannot say otherwise, and this phase is its fourth instance rather
than its first.

**Four note entries bind this sub-phase directly and are cited rather than restated.**

- `concurrency-and-async/f414b864` — core's shared mutable state is one frozen `Data` snapshot swapped under a
  `Thread::Mutex`, read without a lock; `Mutex` is per-fiber-owned and non-reentrant. **`PIPE-10`'s runtime needs
  no lock at all**, which is the point of building it immutable, and the cursor's one mutable flag is examined
  against this rule under R10/P4-33 rather than waved past it.
- `pagination/b2a85752` — the `Enumerator`/`ensure` asymmetry reaches an ordinary `#each` method. **`PIPE-25`'s
  "read-only, ordered view of its steps" is a frozen `Array`, never a lazy enumerator**, and no resource is
  acquired inside any block 4c yields from.
- `resource-management/d1f16cad` — the styleguide's per-call I/O timeout rules do not reach the streaming layer.
  They do not reach 4c either, for a second reason: §8.3 forbids `Timeout.timeout` outright and the deadline is
  phase 5's (`DEF-28`).
- `pipeline/f02559b9` — 4b's `RECOV-10` re-raise finding. It reaches 4c in one place: the async runtime's
  `PIPE-30` normalisation re-raises the fatal family with a **bare** `raise`, and verified fact 7 below confirms
  a bare re-raise assigns no cause and returns the identical object, so the finding's hazard (`raise error`
  acquiring the caller's `$!` as a cause) is not reachable at 4c's call site.

### The audit groups this phase ran

Recorded so the run is repeatable, per the roadmap's first retrospective rule.

| Group | Query | What it produced |
|---|---|---|
| **Pipeline composition and execution context** | `--topic pipeline,execution-context,cancellation-and-timeouts --section rules --brief` (109 entries across 3 files) and `--prefix PIPE --section rules` (50 entries across 2 files) | The whole `PIPE` rule set, spec-role and design-role side by side. Two entries decided text in this document: `pipeline/da4007e4` ("an empty pipeline dispatches straight to the transport **without allocating a cursor**", design role) is what makes R12 a reconciliation rather than a choice, and `pipeline/2728824f` places `PIPE-40` on the re-driving step rather than the runtime, which is what makes 4c's `PIPE-40` obligation a rule-plus-probe rather than an implementation |
| **Fiber scheduler, thread safety** | `--prefix ASYNC --section rules --brief`, `--topic concurrency-and-async --section rules --brief`, `--chapter 9 --section rules --brief` | Four rules with no note recommend `concurrent-ruby` primitives over hand-rolled `Mutex` work; they are resolved by `notes/concurrency-and-async.md` and do not re-open — core cannot depend on `concurrent-ruby` (`SEAM-1`). Adopted and load-bearing here: `concurrency-and-async/c0fab747` (smallest critical section — which is why 4c has *no* critical section), `/54d8bb89` and `/2c743901` (immutable `Data` at every concurrency boundary — `PIPE-10`), `/b9d20c94` (never `Timeout.timeout`), `/611b9392` (check-after-resume). `concurrency-and-async/08a0e08d`, the executor's `#post` duck type, is phase 2's and 4c adds nothing to it |
| **Error handling** | `--chapter 8 --section rules --brief` and `--topic error-handling --section rules --brief` | `error-handling/3bfdf6f0`'s "never demote a programmer error to a handled operational error" is what settles `PIPE-30`'s boundary: a step's `NoMethodError` is a caller bug and becomes a failed future (the requirement says "ANY synchronous exception"), while a `ScriptError` propagates. `error-handling/d2eadac4` — `Dexpace::Error` is a module and `Dexpace::ArgumentError` is never defined — is why `Dexpace::PipelineError` includes the module and subclasses `::StandardError` |

The remaining seven rows of the skill's table are audits of built code and belong to 4c's plan, not to this
design; the *Testing strategy* section names which of them the plan must run.

### The notes filed against the corpus by this phase

**One**, under `docs/knowledge/notes/pipeline.md`'s existing `## Superseded` section. `harvested/` is untouched.

- **What `PIPE-15`'s fork rule cannot say about its own Ruby spelling**, superseding nothing and *adding* to
  `pipeline/591329b5` and `pipeline/debd2eb6` (the design and spec voices of "reusing the same cursor handle for a
  second downstream invocation must be treated as a defect"). The harvested rule is right and is implemented in
  full. Two things it cannot say, because it names no code. **First, the latch.** The obvious spelling — a plain
  ivar check-and-set, which is what a per-invocation unpublished object earns — detects the defect only when the
  two calls are sequential; verified fact 9 is the measurement, and the rate rather than the platform is what
  makes a test of the race unshippable in either of its two forms. **Second, the fork.** Both entries say "per
  re-drive", which describes the reference's mixed shape (drive 1 on the handle, drives 2..*n* on copies); this
  port forks for *every* drive and rejects `#fork` after `#call` (P4-39), because the fork is where cursor-scoped
  state is written and a first drive on the un-forked handle would have no stage slot to write into. The note also
  backticks `concurrency-and-async/c0fab747`, the smallest-critical-section rule, which the no-lock decision
  **follows** rather than overrides. Filed because a phase-6 pillar-step author reading either entry alone would
  reasonably conclude that the runtime catches every reuse and that the first drive uses the handle; neither is
  true here, and both mistakes compile and pass every ordering test.

---

## The verified Ruby facts this phase is built on

Every claim was run on **3.2.11, 3.4.10 and 4.0.6** via `mise exec ruby@<v>` on 2026-09-08. **The floor was run
explicitly and separately, and one fact diverges on it.** For each, what it licenses is written out, because a
fact that is true and licenses nothing is how the last three reviews found a wrong conclusion.

1. **A two-argument step predicate can be written from `#parameters` and is uniform across the range.**
   `->(request, cursor){}` reports `[:req, :req]`; `proc { |request, cursor| }` reports `[:opt, :opt]`;
   `obj.method(:call)` on a two-argument method reports `[:req, :req]`; `->(*a){}` reports `[:rest]`;
   `->(x){}` reports `[:req]`. The predicate "required ≤ 2 and (a rest parameter is present or required + optional
   ≥ 2)" returns `true`, `true`, `true`, `true`, `false` respectively, on all three.
   **Licenses:** `Dexpace::Pipeline::Step.conforms?` written exactly as phase 2 wrote `Transport.conforms?`, one
   arity lower — including the `:opt` handling, without which a non-lambda `proc` step would be rejected, which
   §5.1's "a lambda qualifies as a step" would then be false of half of Ruby's callables. It does **not** license
   any claim about the step's *return* type; a sync step and an async step have identical shapes, which is
   phase 2's admitted gap arriving at a second seam and is why `#build` and `#build_async` are two methods (R10).
2. **A runtime whose `#call` is `(request, options = EMPTY, cancellation = NONE)` reports
   `[[:req, :request], [:opt, :options], [:opt, :cancellation]]`, and phase 2's transport predicate accepts it on
   all three.** Both the one-argument and the three-argument call forms work.
   **Licenses:** `PIPE-26`'s "with and without per-call options" is Ruby's default arguments and needs no second
   entry point, and `Transport.conforms?(pipeline)` is `true` without `Pipeline` declaring anything. It does
   **not** license the converse — `conforms?` cannot tell a `Pipeline` from an `AsyncPipeline`, for the reason in
   fact 1. That converse is **`OI-18`**, filed by this document's review, and it is asymmetric:
   `AsyncTransport.sync_over(sync_pipeline)` raises `Dexpace::SeamError` at the first send because
   `Bridge::SyncOver#call` type-checks the returned future, while `Transport.async_over(async_pipeline,
   executor:)` is silent for ever — `Completer#fulfil` and `Settlement.success` validate nothing about the
   delivered object, so `Future#value` hands back the inner `Future` and the response inside it is never closed.
   Both bridges, the predicate and the settlement are phase 2's, committed; 4c neither introduces nor widens the
   gap, and shipping no third bridge is what keeps it at one occurrence rather than two.
3. **Two `Data` instances with equal members are `==`, `eql?` and hash-equal but not `equal?`; two distinct
   lambdas are never `==`.** On all three.
   **Licenses:** the `PIPE-6` fixture. A probe step must be a `Data` type for the idempotence test to discriminate
   at all — `Probe[:a]` and a second `Probe[:a]` are the "distinct but structurally identical" pair `PIPE-6` and
   §5.1 are about, and a lambda-based fixture would pass against an `==`-based implementation because two lambdas
   are never `==` in the first place. This is `CTX-9`'s trap (§5.4) arriving in the pillar-collision check, and it
   is the second place in phase 4 where a test written the obvious way proves nothing.
4. **A frozen `Hash` raises `FrozenError` on `[]=`; `#merge` on a frozen receiver returns a new *unfrozen* hash
   and leaves the receiver untouched; `#dup` of a frozen `Hash` is unfrozen but its frozen values stay frozen;
   `#fetch(missing, EMPTY)` returns the frozen default.** On all three.
   **Licenses:** the whole of R11's mechanism. The parent cursor's state cannot be written through a handle a
   child holds (`FrozenError`), a fork's state is `parent_state.merge(…).freeze` with the inner per-stage hashes
   shared by reference and separately frozen, and a read of an unwritten stage returns one shared frozen empty
   hash rather than allocating. It does **not** license a deep-freeze claim: `merge` is shallow, so **every inner
   per-stage hash is frozen independently at the moment it is created**, which is `CLAUDE.md`'s shallow-`freeze`
   rule applied one level down.
5. **`Data#with` preserves the identity of every unchanged member and returns a frozen instance.** On all three.
   **Licenses:** `PIPE-17`'s "immutable/shared, not copied-and-diverged per fork" asserted with `assert_same` on
   the options object across a fork, and `PIPE-14`'s substituted request carried on the cursor by identity.
6. **`respond_to?(:stage)` is `false` for a lambda and `true` for a `Data` with a `stage` member or an object with
   a singleton `#stage`; `Method#owner` reports the singleton class for the singleton case and the defining
   ancestor for an inherited one.** On all three.
   **Licenses:** the *shape* of R10's hybrid — a step may declare `#stage` and a lambda cannot, so a
   `#stage`-only mechanism cannot satisfy §5.1's lambda clause and an install-time argument is the only mechanism
   that covers both. It does **not** license using `Method#owner` to detect a `PIPE-36` stage relocation: an
   inherited `#stage` reports the *base* class as its owner, so a subclass that does not override it is
   indistinguishable from one that does at the owner level — which is one reason `PIPE-36` stays deferred under
   `DEF-4` rather than being quietly implemented here.
7. **A bare `raise` inside a `rescue` re-raises the identical object and assigns no `#cause`, even when an
   unrelated exception was in flight in an enclosing `rescue`.** Verified with an error constructed and raised
   with `cause: nil`: the object that emerges is `equal?` to the original and its `#cause` is `nil`. By contrast
   `raise stored_object` with `$!` non-`nil` and `stored_object.cause` `nil` assigns that `$!` as the cause — the
   fact `docs/knowledge/notes/pipeline.md` records. On all three.
   **Licenses:** the async runtime's `PIPE-30` normalisation is written `rescue ::Exception => e; raise unless
   e.is_a?(::StandardError); completer.fail(e)` — a **bare** `raise`, not `raise e` — and the note's hazard does
   not reach it. It does **not** license a bare `raise` anywhere core re-raises an error it is *carrying* rather
   than one it just rescued; that is `raise error, cause: nil` and is 4b's rule.
8. **A frozen `Array` returned from an accessor is the same object on every call, raises `FrozenError` on `<<`,
   and `#each` with a block returns the `Array` itself rather than an `Enumerator`.** On all three.
   **Licenses:** `PIPE-25`'s read-only ordered view needs no per-access `dup` and no wrapper (design §10.11's
   computed-once rule), and the charter's cross-cutting constraint 5 is satisfied by construction rather than by
   discipline.
9. **The unsynchronised single-use latch races, and it races only on the floor.** Eight threads released from one
   `Thread::Queue` barrier onto `unless spent; spent = true; passed += 1; end`, 2000 runs: **29 of 2000 runs let
   more than one caller through on 3.2.11**, and **0 of 2000 on 3.4.10 and on 4.0.6**. At 32 threads: 9 of 2000
   on 3.2.11, 0 of 2000 on the other two. A `Thread::Mutex` around the same body: 0 of 50 everywhere.
   **Licenses:** the honest statement of what `Cursor#call`'s reuse guard detects (P4-33) — a sequential second
   call always, a concurrent second call sometimes — and, decisively, **the decision that 4c ships no test
   asserting the race**. The rate is what makes that decision, and it has to be quoted as a rate rather than as
   "it reproduces on the floor": **29 in 2000 is 1.5 %**, so a test written the natural way — release eight
   threads once, assert two got through — fails about 98 times in 100 **on the floor as well**, and 100 times in
   100 above it. Only the aggregate form, the 2000-run loop itself, passes on 3.2.11, and it is red on every
   other column. Both forms are unshippable and neither is a weaker case than the other: one is a flake
   everywhere, the other is a green-on-one-column assertion of an interleaving no version guarantees.
   It does **not** license "3.4 and 4.0 are safe": zero in 2000 is an absence of observation, not an absence of
   the interleaving, and the design's statement is written over the whole range. Nor does it license the *absence of the lock* — a demonstrated race
   is evidence for a mutex, not against one. What licenses the absence is the argument in P4-33, that a cursor is
   created per step invocation, handed to exactly one step and never published; this fact only prices that
   argument, and the price is the sometimes-undetected concurrent double-call. **This is the fact the floor had
   to be run separately to find**; generalising from 3.4.10 would have produced a design that claimed a guarantee
   it does not have.
10. **A `Data` type responds to `<=>` (through `Kernel#<=>`), which returns `0` for an identical receiver and
    `nil` for any other — so `[stage_b, stage_a].sort` raises `ArgumentError: comparison of Stage with Stage
    failed`, while `sort_by(&:order)` orders correctly.** On all three.
    **Licenses:** the flatten function is written `Stages::ALL.flat_map { … }` over a pre-ordered frozen table,
    and nothing in 4c sorts stages at run time. It also names the trap directly: a reader who assumes `Data`
    gives ordering because `respond_to?(:<=>)` is `true` writes `entries.sort_by(&:stage)` and gets an
    `ArgumentError` at the first two-stage pipeline.
11. **`ObjectSpace.each_object(SomeClass).count` counts user-defined class instances accurately with `GC.disable`
    in force**, delta exactly 5 for five allocations, on all three.
    **Licenses:** R12's empty-pipeline branch is testable as a *non-allocation* rather than only as a behaviour —
    the assertion `PIPE-9`'s SHOULD actually makes. It does **not** license the technique outside CRuby;
    `DEF-33` already records that no v1 matrix row is non-CRuby, and the test's comment says so.
12. **A module supplying `def call(value) = apply(value)` as a default, included into a class defining `#phase`
    and `#apply`, forwards correctly; a class that overrides `#call` to raise still has a working `#apply`.**
    On all three.
    **Licenses:** the generic adapter calling `#apply` and never `#call` is *testable* — a `Transform` double
    whose `#call` raises is the assertion — which is what 4b's R8 clause 5 asks 4c to guarantee ("so a future
    default on `#call` cannot change what the pipeline does").
13. **A lambda's class is `Proc` and `instance_of?(Proc)` is `true` for every lambda.** On all three.
    **Licenses:** the honest statement of `PIPE-18`–`PIPE-21`'s reach: the surgical edits are keyed by *type*, and
    every lambda step in a pipeline shares one type, so a pipeline holding two lambdas cannot address one of them
    surgically. Filed as **`OI-17`** and documented in the YARD; it is a tension between two requirements, not an
    implementation choice.

---

## R10 — where a step's stage assignment lives

**Resolved: the stage is recorded by the builder at install time and is the authority; a step MAY declare
`#stage`, and when it does, disagreement is rejected rather than silently resolved.**

### Why the three candidates are not equivalent

The charter names three mechanisms. Two fail outright on §5.1's own requirement that "a `lambda` is a step".

- **A frozen table keyed by step class fails hardest.** Every lambda's class is `Proc` (verified fact 13), so two
  lambdas installed at two different stages would collide on one table key. There is no repair: the table cannot
  distinguish them and neither can anything else keyed by class.
- **A `#stage` method the pillar families define cannot stand alone.** A lambda does not respond to `#stage`
  (verified fact 6), so a `#stage`-only mechanism either rejects lambdas — contradicting §5.1 — or leaves them
  stage-less, which leaves `#fork` ungated for exactly the steps a caller writes by hand.
- **A stage passed at install time covers both and is the only one that does.**
  `append(step, stage: Stages::RETRY)` records the pair; the builder holds `Entry(stage:, step:)`; `build`
  freezes the flattened entry table into the runtime. Every step's stage is then known at composition time **by
  construction**, for a lambda exactly as for a class. Every install and every surgical edit takes the same
  optional `stage:` keyword, so there is one spelling and not one per operation.

### The hybrid, and why `#stage` survives at all

`PIPE-18` and `PIPE-19` say "the inserted step MUST **declare** the same stage as the matched anchor", and
`PIPE-36` (deferred, `DEF-4`) speaks of pillar families "**locking** their stage assignment". Both presuppose a
step that can carry a stage. So `#stage` is admitted as an **optional declaration** with a fixed precedence rule:

| The step | The `stage:` argument | Effective stage |
|---|---|---|
| declares `#stage` | omitted | the declared stage |
| declares `#stage` | given and equal | the declared stage |
| declares `#stage` | given and **different** | **rejected**, `Dexpace::PipelineError` naming both |
| declares nothing | omitted | **rejected**, `Dexpace::PipelineError` — a step with no stage cannot be installed |
| declares nothing | given | the argument |

`#stage` is read **once, at install**, and never again. The runtime's entry table is the only thing consulted
afterwards, so a step that changes its mind about `#stage` between installation and dispatch changes nothing —
which is what "checked at composition time … not trusted at call time" means, and it is the same discipline 4b's
R8 clause 2 reached independently for `#phase`.

For the surgical edits, "the same stage as the anchor" is then a comparison between two known values and the
cross-stage rejection is real for both step shapes: a declaring step whose declared stage differs from the
anchor's is rejected, and a lambda whose `stage:` argument differs from the anchor's is rejected. `stage:` is
therefore **required** on `insert_after`/`insert_before`/`replace` for a non-declaring step, rather than being
inferred from the anchor — inferring it would make the requirement's own rejection unreachable.

### The same fact gates two things, and that is deliberate

§5.1 gates **two** capabilities on the stage assignment: `#fork`, and the cursor-scoped-state write. Both read the
same frozen entry table, through one predicate:

```
entry = @entries[owner_index]        # the frozen table, built once at build()
entry.stage.pillar? && !entry.stage.terminal?
```

The cursor knows which entry handed it out because the runtime binds it: a cursor handed to the step at index *i*
carries `owner_index = i` and `position = i + 1`. **The cursor never asks the step anything.** A forged step
object — one that responds to `#stage` with `Stages::REDIRECT` while sitting in `PRE_REDIRECT` — cannot obtain a
fork, because nothing calls its `#stage` after installation. That is the property R10 exists to produce and it is
what R11 rests on.

---

## R11 — cursor-scoped state, and the write restriction phase 6 is built on

**Resolved, and strengthened: state is keyed by `(stage, key)`; the only write is an argument to `#fork`; and the
write lands in the forking step's own stage slot, chosen by the runtime from the frozen entry table and never by
the caller.**

### The two rules, quoted

§5.1: "state set on a cursor is inherited by every cursor forked from it and thereafter advanced from that fork,
and it is writable only by the pillar step that created the fork."

§10.15 (deviation 15) argues that these two together make `REDIR-11`'s forgery-impossibility claim **structural**
rather than defended, and §6.2 spells out what that requires: "inheritance is why a marker set on the per-hop fork
is visible to the AUTH step downstream of it, and the write restriction — only the pillar step that created a fork
may write its state — is why AUTH, which did not create it, can read the marker but cannot set one, **and why no
step downstream of AUTH can either**."

### Why a flat keyed map does not carry that sentence, and a `(stage, key)` map does

Consider the stage order `REDIRECT → RETRY → AUTH`, which is `PIPE-2`'s and which §6.2 says the argument depends
on. Under a flat namespace with a checked write:

- A non-pillar step between REDIRECT and AUTH cannot fork and cannot write. The claim holds.
- **A `RETRY` pillar step can.** It sits between REDIRECT and AUTH, it occupies a pillar, so it may fork, and
  under a flat map its fork could carry `cross_origin: false` for a hop that *was* cross-origin. AUTH, reading the
  cursor it was handed, cannot tell that value from REDIRECT's. Forgery is defended against by the honesty of the
  retry step, which is precisely the posture §10.15 says this port improves on.

Namespacing by the writing step's stage closes it without a check. `#fork(state:)` merges the supplied pairs into
`state[owner_stage]` and **only** there; the owner's stage comes from the frozen entry table, so a step cannot
name a slot it does not own. AUTH reads `cursor.state(Stages::REDIRECT)`. A retry step writes
`state[Stages::RETRY]` and nothing it writes is visible under `Stages::REDIRECT` to anyone.

Two further properties fall out and are worth naming because they are what a reviewer will ask about:

- **The writer namespace is exactly the five configurable pillars, and each has at most one possible writer.**
  Only a pillar step may fork, and a pillar admits at most one step (`PIPE-4`), so `state[Stages::REDIRECT]` has
  exactly one author in any built pipeline. There is no second writer to disambiguate against.
- **Non-pillar slots are permanently empty.** A slot step cannot fork, so `state[Stages::PRE_AUTH]` is the shared
  frozen empty hash in every cursor of every call. That is not waste; it is the invariant stated in the type.

### Expiry, which §6.2 requires and which falls out

§6.2: "the marker also expires correctly for free, since the next hop is a new fork from REDIRECT and starts from
REDIRECT's own state rather than the previous hop's." Under this model REDIRECT's step holds cursor *C* for the
whole call and forks *from C* for each hop; hop 2's fork is `C.fork(state: …)`, not `hop1_fork.fork(…)`, so it
inherits *C*'s state and never hop 1's. The requirement is met by the shape of the API rather than by REDIRECT
remembering to clear anything.

**One consequence has to be stated as a rule, because `PIPE-15`'s own wording points the other way and a
phase-6 author would follow it.** `PIPE-15` says a step that drives the chain more than once "MUST fork a fresh
cursor **for each re-drive** … rather than reusing the same next handle", which describes the reference's shape:
drive 1 uses the handle, drives 2..*n* use copies. **This port's rule is: a pillar step that may drive more than
once forks for *every* drive, the first included, and never calls its own `#call` at all.** Two reasons, and the
second is the load-bearing one.

- It is what makes hop 1 and hop *n* the same object. Under the mixed shape, hop 1 runs on *C* itself, and *C*'s
  `state[Stages::REDIRECT]` slot is the one nothing wrote — so hop 1 carries no marker. That is *accidentally*
  correct for `REDIR-11`, because hop 1 is the original request and is same-origin by definition, and it is
  wrong the moment a pillar wants to publish anything on its first drive. Making every drive a fork removes the
  special case rather than relying on nobody meeting it.
- It leaves `#call` and `#fork` disjoint. A step either drives once through `#call` and never forks, or drives
  *n* ≥ 1 times through `#fork` and never calls `#call`. **`#fork` after `#call` on the same cursor is therefore
  not a supported shape and is rejected** with `Dexpace::PipelineError`, on the same reasoning that makes `#call`
  single-use: a fork taken after the handle was spent resumes the tail a second time from a cursor whose own
  drive already completed, which is `PIPE-15`'s defect wearing the fork's name. `#spent?` is what a step asks.

Forking more often than `PIPE-15`'s minimum is not a violation of it — the requirement forbids *reusing a spent
handle*, not forking early — so the port's rule is strictly inside the requirement, and the deviation is one of
shape rather than of guarantee, recorded as **P4-39**. It is stated here, in `#fork`'s YARD, in the phase-6 row
of *The interface surface later phases may cite*, in the corpus note, and as one test — because it is the kind of
rule that is obvious once and invisible afterwards, and because every one of those four is a place a phase-6
author might arrive from.

### The negative assertions, which are the point

R11's instruction is explicit: "4c's tests must therefore assert the negative — that a step downstream of a fork
cannot write the fork's state — not only the positive." Nothing in phase 4's own suite would otherwise catch a
wrong write restriction, and getting it wrong makes a §10 entry false two phases out. Five assertions, and the
last two are the ones a positive-only suite would miss:

1. **There is no state-setting method.** `Dexpace::Pipeline::Cursor.public_instance_methods(false)` contains no
   writer; the runtime surface manifest pins it. A step cannot write state except by forking.
2. **The state a step can reach is frozen.** `cursor.state(Stages::REDIRECT)[:cross_origin] = false` raises
   `FrozenError`, and so does a write to the outer map if one is ever reachable (verified fact 4).
3. **A non-pillar step cannot fork.** A probe installed at `PRE_AUTH` calling `cursor.fork` raises
   `Dexpace::PipelineError`; the message names the step's stage.
4. **A pillar step downstream of a fork cannot alter an upstream pillar's slot.** A probe `RETRY` step forks with
   `{cross_origin: false}`; a probe `AUTH` step downstream reads `cursor.state(Stages::REDIRECT)` and still sees
   the value REDIRECT's fork wrote, while `cursor.state(Stages::RETRY)` shows RETRY's own. **This is the
   assertion the stage namespacing exists for**, and under a flat map it would fail.
5. **A write does not reach back.** After a fork, the parent cursor's `state(stage)` is `equal?` to what it was
   before — the same frozen object, not merely an equal one — and a second fork from the same parent does not see
   the first fork's write.

Assertion 4 is written against `Stages::REDIRECT` and `Stages::RETRY` **by name**, with a comment naming
`REDIR-11`, `AUTH-29` and §10.15, so a phase-6 author who changes the mechanism meets the test that says why.

---

## R12 — reconciling `PIPE-9` with `PIPE-10`

**Resolved: they are consistent, `PIPE-10`'s purpose clause is what reconciles them, and both branches are one
`if` in one method and two tests.**

`PIPE-9` (MUST, with a trailing SHOULD): an empty pipeline "MUST dispatch the request directly to the terminal
transport, threading the caller's per-call options … It SHOULD do so **without allocating per-call cursor
state**."
`PIPE-10` (MUST): "each send/sendAsync MUST allocate its own per-call cursor **so concurrent calls share no
mutable pipeline state**."

**The reconciliation.** `PIPE-10`'s requirement is the clause after "so": concurrent calls must share no mutable
pipeline state. The per-call cursor is the *named mechanism* for it, not the goal. An empty pipeline has no step
to hand a cursor to and therefore no per-call mutable state to share — the runtime is a frozen entry table of
length zero and a transport reference — so `PIPE-10`'s guarantee holds with no cursor at all, and `PIPE-9`'s
SHOULD is the specification's own licence to skip the allocation in exactly that case. The two are consistent
**only** through the empty-pipeline special case; there is no reading under which a non-empty pipeline may skip
the cursor, and none under which an empty one must allocate one. The corpus records both halves as one rule —
`pipeline/5ee282fe` (spec role, both clauses in one sentence) and `pipeline/da4007e4` (design role, "an empty
pipeline dispatches straight to the transport without allocating a cursor").

**The code is one branch:**

```
def call(request, options = RequestOptions::EMPTY, cancellation = Cancellation.none)
  return @transport.call(request, options, cancellation) if @entries.empty?    # PIPE-9
  Cursor.build(drive: SyncDriver.new(self), request:, options:, cancellation:)  # PIPE-10
        .call(request)
end
```

**Both branches are tested, and the empty branch's SHOULD is tested as a non-allocation rather than only as a
behaviour** (verified fact 11):

- *Empty, behaviour.* `Pipeline.direct(fake_transport).call(request, options)` — the fake records its arguments;
  assert `assert_same(options, recorded.options)`, `assert_same(request, recorded.request)`, and that the returned
  response is the fake's own object by identity.
- *Empty, allocation.* Under `GC.disable`, `ObjectSpace.each_object(Dexpace::Pipeline::Cursor).count` before and
  after one send: **delta zero**. Its comment names `PIPE-9`'s SHOULD, names CRuby as the assumption, and cites
  `DEF-33`.
- *Non-empty, allocation.* The same measurement over a one-step pipeline: **delta at least one**. This is the
  assertion that would fail if someone "optimised" the empty branch into the general one and then removed the
  cursor everywhere.
- *Non-empty, concurrency.* `PIPE-10`'s own clause: 16 threads sending concurrently through a probe step that
  records the cursor it was handed into a thread-local; afterwards, the 16 cursors collected into a
  `{}.compare_by_identity` and asserted to number 16. Reference identity, not `==`, because a `Cursor` defines no
  `==` and would fall through to identity anyway — the assertion says what it means rather than relying on that.
- *Immutability.* `pipeline.frozen?`, `pipeline.steps.frozen?`, and `pipeline.steps` returning the same object on
  two calls (`assert_same`), which is `PIPE-10`'s first clause and `PIPE-25`'s view in one.

---

## R13 — `PIPE-34`'s blocking wait

**Resolved: there is no 4c signature to widen, because 4c ships no wait, no bridge and no new deferral.
`DEF-28` is cited and phase 2's P2-5 is the deviation that already carries it.**

The charter offered two answers — "a deferral row or a signature phase 5 widens" — and named the `DEF-28`
precedent for the second. The right answer turns out to be neither, and the reason is spec-forced boundary 15:

> "`PIPE-33`/`PIPE-34` reuse phase 2's two bridges rather than building a second pair … `4c` may not ship a second
> executor duck type, a second orphan-close path or a second synchronous-raise normalisation."

`PIPE-34` is "the async-to-sync bridge MUST block the calling thread on the async result for each call while
preserving per-call options". Phase 2's `Dexpace::AsyncTransport.sync_over(transport)` is that bridge, over
anything responding to `#call(request, options, cancellation) -> Future`. An `AsyncPipeline` responds to exactly
that (`PIPE-26`, verified fact 2). So `AsyncTransport.sync_over(async_pipeline)` **is** `PIPE-34` at the pipeline
layer, with no new object, no new method and no new signature.

**What that buys, stated as consequences rather than as tidiness:**

- **The "no deadline-less unconditional block" constraint is met in its strongest form.** 4c writes no wait, so
  there is no place a bare `Thread::Queue#pop`, a `Kernel#sleep` or a `Timeout.timeout` could appear. The wait is
  phase 2's `Future#value(cancellation:)`, whose narrowing to `cancellation:` is P2-5 and `DEF-28`.
- **No new register row.** `DEF-28`'s scope is "the pivot's `deadline:` keyword and the clock behind it", its
  pick-up is phase 5 with `CFG-15`–`CFG-21`, and its `NFR-4` argument — "adding a keyword later **widens** a
  signature, and the lock fails when a public signature disappears or narrows" — is unchanged by 4c using the
  method. Filing a second row for the same missing keyword on the same method would be a duplicate, and the
  register's own rule is that an ID is never reused and never restated.
- **`PIPE-34`'s remaining clauses are already discharged and are re-asserted rather than re-implemented.**
  "Unwrap execution-wrapper exceptions" holds structurally because the pivot never wraps (`Completer#fail` stores
  the error and `#value` re-raises *that object*); "restore the interrupt flag" is vacuous for the reason
  `ASYNC-4` is vacuous (§10.5) — a port that never delivers an interrupt cannot leave a stale one set;
  "surface an interrupted-I/O error" is read as `Dexpace::CancelledError`, phase 2's P2-4, because `XCUT-4`'s
  I/O family is for transport failures and a cancellation is not one.
- **`PIPE-33` is the same story from the other side**, and its clause-1 constraint ("no default executor") is met
  by 4c shipping no executor and no factory for one.

4c's obligation is therefore a **test and a YARD cross-reference**, not code: an end-to-end assertion that
`Transport.async_over(pipeline, executor: fake)` and `AsyncTransport.sync_over(async_pipeline)` work over a real
built pipeline with steps in it, and a documented pointer on both runtime classes saying which phase-2 function is
the bridge. Recorded as **P4-35**, on 4b's P4-17 precedent — a requirement satisfied by shipping nothing is a
ledger row precisely because a reader looking for the object will otherwise conclude it was forgotten.

---

## R14 — the preset and the convenience constructors

**Resolved: `PIPE-24`'s all-or-nothing installation ships in full as a general `Builder` mechanism; the standard
step *set* — and with it `PIPE-39`'s second constructor and `PIPE-32`'s `redirect: :unsupported` argument — is
deferred as `DEF-39` to phase 6.**

### The split, and why it is the requirement's own

`PIPE-24` is entirely about **installation semantics**: install into empty slots only, validate up front, reject
the whole call installing nothing, never overlay. It names no step. `PIPE-39` is entirely about **which steps**:
"a standard pipeline that installs the default resilience pillars over a transport (sync: redirect+retry+
instrumentation; async: retry+instrumentation with a caller-supplied scheduler for non-blocking backoff)". Those
are separable, and separating them is what lets `PIPE-24` be a real, tested MUST today.

So the builder gains `#install_preset(entries)`, which:

- validates that **every** target pillar named by the entries is currently empty, **before** installing anything;
- raises `Dexpace::PipelineError` naming every occupied pillar and its occupant's type on any collision;
- on rejection leaves the builder byte-for-byte unchanged — asserted by comparing the flattened entry list before
  and after the rejected call, not by inspecting internals;
- shares its validate-then-commit implementation with `PIPE-23`'s `#reload(entries)`, so "all-or-nothing" is one
  code path and the two requirements cannot drift.

That is testable **today** against probe pillar steps: install a probe at `RETRY`, call `install_preset` with
probes for `REDIRECT`, `RETRY` and `AUTH`, assert the raise names `RETRY`, and assert `REDIRECT` and `AUTH` are
still empty. `PIPE-24` is ✅.

### What defers, and why an empty-but-named constructor is not acceptable

`Pipeline.standard(transport)` would, in phase 4, install nothing — because the redirect and retry steps are
phase 6's and the instrumentation step is phase 5's. The charter forbids exactly that: 4c "must not ship a preset
that silently installs nothing while claiming to install the defaults". A constructor named for what it installs
and installing nothing is worse than its absence, because a caller reaches for it *instead of* composing the
pillars by hand and gets a bare transport with the word "standard" on it.

**A middle option was considered and rejected.** `Pipeline.standard(transport, redirect:, retry:, instrumentation:)`
with three required keywords would install exactly what the caller names, be testable today against probe steps,
and gain defaults in phases 5 and 6. It is rejected on two counts. First, it is not what `PIPE-39` asks for — a
constructor whose three steps the caller must supply is `#install_preset` with three fixed parameter names, a
second name for a mechanism that already has one. Second, and decisively, it locks three public keyword names
under `NFR-4` at the first release tag *before the objects they name exist*, which is the same objection phase 2
raised in declining to build `deadline:` (`DEF-28`, P2-5) and phase 0 raised against defining `Dexpace.register`
early.

### What ships now, so the row is not empty

- **`Dexpace::Pipeline.direct(transport)`** and **`Dexpace::AsyncPipeline.direct(transport)`** — `PIPE-39`'s first
  named shape, "a step-less pipeline that forwards directly to a transport". Fully implemented, and it is
  `PIPE-9`'s empty pipeline behind a name a caller can find.
- **`Dexpace::Pipeline::Builder#install_preset`** — `PIPE-24`'s mechanism, above.
- **`PIPE-35`'s two seeding constructors**, `Builder.flattening(pipeline)` and `Builder.nesting(pipeline)`, which
  §5.3 also counts under `PIPE-39`'s heading in design §12's note ("`PIPE-39`'s convenience constructors are
  §5.1's preset and §5.3's two named seeding constructors"). Both ship in full.

**Which reading of `PIPE-39` this ⏳ is against, stated because §12 offers a second one.** Design §12's `PIPE`
row glosses the requirement as "`PIPE-39`'s convenience constructors are §5.1's preset and §5.3's two named
seeding constructors" — and every one of those three ships here, so under §12's gloss the row would be ✅ with
nothing outstanding. **This document dispositions against appendix C's own two shapes instead**, "a step-less
pipeline that forwards directly to a transport, and a standard pipeline that installs the default resilience
pillars over a transport", because that is the normative text and the gloss is a design-chapter summary of where
the port put the constructors. One of the requirement's two shapes is absent, so the row is ⏳. The choice is
recorded rather than silent because a later reader diffing this ⏳ against §12's note will otherwise read a
contradiction where there is a narrower reading.

`DEF-39` therefore defers the *standard-resilience constructor pair* — sync and async — and nothing else. Its
pick-up condition names **phase 6**, because that is the first phase in which all three of the step families
`PIPE-39` enumerates exist (redirect and retry are phase 6's; the instrumentation step is phase 5's), and it names
`#install_preset` as the mechanism already built and waiting so phase 6 writes a constructor and not a mechanism.

### `PIPE-32`, from the other side

`PIPE-32`'s substantive clause — "the async standard pipeline MUST NOT follow HTTP redirects at the pipeline
layer" — is about an object `DEF-39` defers, so it **holds vacuously in phase 4**: there is no async standard
pipeline to follow a redirect. What does not defer is the requirement's last clause, "a port MUST document this
asymmetry with the sync standard pipeline", which is discharged here and in the YARD on `Dexpace::AsyncPipeline`.

**One thing 4c deliberately does not do**, and it is worth stating because it is the tempting reading: it does
**not** make `Stages::REDIRECT` un-installable on the async path. `PIPE-28` requires "the identical stage
identities and staging policy" in both runtimes and forbids the two re-deriving anything independently; a builder
that rejected a REDIRECT step for the async build and accepted it for the sync one would be two staging policies.
`PIPE-32` constrains the *preset*, not the runtime, and 4c keeps that line. The `redirect: :unsupported` argument
§5.3 specifies is an argument on the deferred async standard-pipeline factory, and it travels with `DEF-39`.

---

## The generic adapter — how 4c consumes 4b's `Transform` contract

**One class, `Dexpace::Pipeline::TransformStep`. It reads `#phase` once at construction, calls `#apply` and never
`#call`, and it is the only object 4c ships that mentions a `Dexpace::Recovery::` constant.**

4b's R8 is the contract and is cited rather than restated. Its five clauses fix: `#apply(value)` is the entire
behaviour and returns the type it was handed; `#phase` is `:request` or `:response`, constant per class, read at
composition time; a chain step is a one-argument `#call`-able; a transform installs into a chain as itself through
the module's one forwarding `#call` default; **and the stage pipeline wraps `#apply`, through a wrapper that is
4c's, generic, and written once.** 4b's own correction to the charter is adopted with it: the error-mapping step's
shape is `response -> response` and it *raises* on an error status — the charter's `response -> outcome` is wrong,
`RECOV-4` is parenthetically explicit, and **no `Outcome` ever crosses into the `PIPE` layer**.

### The surface

```
Dexpace::Pipeline::TransformStep.build(transform) -> TransformStep
  #call(request, cursor) -> Dexpace::Response
  #transform -> Dexpace::Recovery::Transform
```

`.build` validates and memoises:

- the argument responds to `#phase` and `#apply` — the two obligations `api-design/88e6bf12`'s narrowest-duck-type
  rule leaves a caller, and the pair 4b's contract declares;
- `#phase` returns `:request` or `:response` and **nothing else**. A third value raises
  `Dexpace::InvalidArgumentError` with `SEAM-29`'s message form, which is R8 clause 2's "neither may add a third
  phase" made mechanical on this side. A phase naming the recovery-step list is the specific mistake the check
  catches: a recovery step is `Outcome -> Outcome` and is not a transform at all;
- the branch is chosen **at build**, from the value read then, and stored. `#call` never asks again — the same
  composition-time discipline `#fork` follows (R10), reached from the other direction.

`#call` is two lines and the whole of it:

```
:request  ->  cursor.call(@transform.apply(request))
:response ->  @transform.apply(cursor.call(request))
```

### What this deliberately does not do

- **It calls `#apply`, not `#call`.** 4b's clause 5 asks for exactly this, "so a future default on `#call` cannot
  change what the pipeline does". The assertion is a `Transform` double whose `#call` raises and whose `#apply`
  returns; the test passes only if the adapter never touches `#call` (verified fact 12).
- **It ships no second implementation of anything.** No idempotency key, no client-identity line, no status
  mapping, and no subclass of `IdempotencyKeyStep`, `ClientIdentityStep` or `ErrorMappingStep`. Those three are
  4b's objects and 4c installs them.
- **It declares no `#stage`.** One class wraps three transforms whose correct placements differ — `PIPE-37`
  requires the error-mapping transform at `PRE_REDIRECT`, while an idempotency-key transform belongs at or before
  `PRE_RETRY` so a re-attempt reuses the key. A `#stage` on the adapter would be a stage for the wrapper rather
  than for what it wraps. The stage is named at install (R10).
- **It does not make the `PIPE` layer depend on the recovery *chain*.** The dependency is on one value type,
  `Dexpace::Recovery::Transform`, and it runs one way: nothing in `Dexpace::Recovery::` names a cursor, a stage or
  a pipeline, which is what boundary 1 forbids. 4b's R8 assigns this adapter to 4c explicitly, so the direction is
  the contract's and not this document's invention.

### `PIPE-37`, which is where the two layers actually meet

`PIPE-37` is spec-forced boundary 5 and it is 4b's object in 4c's slot. What 4c owes:

- **The slot.** `Stages::PRE_REDIRECT` is order 100, outside every pillar's fork, so a step there is invoked once
  per call with the terminal response. That is a property of the stage table, asserted directly.
- **The test the placement alone would not catch.** A probe REDIRECT pillar step that forks twice, with
  `TransformStep.build(ErrorMappingStep…)` at `PRE_REDIRECT` and a 2xx terminal response: assert the pre-redirect
  step ran **once**, that the response it returned is `assert_same` to the transport's, and that the body's
  `#source` was never called. The last clause is `PIPE-37`'s parenthesis — "body not read, consumed, or closed" —
  and 4b's `ErrorMappingStep#apply` already guarantees it; 4c asserts it *through the pipeline*, because that is
  where a wrapper could break it.
- **Documentation, not enforcement.** 4c cannot know which caller-supplied transforms are terminal-response
  dependent, so it does not attempt to reject a misplacement. The YARD on `TransformStep` and on
  `Stages::PRE_REDIRECT` states the rule and cites `PIPE-37`.

---

## Module layout

Every file 4c creates or modifies, under `gems/dexpace-core/`. `sig/` mirrors `lib/` one file per file and ships
inside the gem; `test/` mirrors `lib/` one file per file and does not ship.

```
lib/dexpace.rb                                    MODIFIED: explicit requires for the tree below
lib/dexpace/error/pipeline_error.rb               Dexpace::PipelineError
lib/dexpace/pipeline.rb                           Dexpace::Pipeline, .builder, .direct
lib/dexpace/pipeline/stage.rb                     Dexpace::Pipeline::Stage
lib/dexpace/pipeline/stages.rb                    Dexpace::Pipeline::Stages  (16 constants, ALL, PILLARS, .of)
lib/dexpace/pipeline/step.rb                      Dexpace::Pipeline::Step    (module, .conforms?)
lib/dexpace/pipeline/entry.rb                     Dexpace::Pipeline::Entry
lib/dexpace/pipeline/cursor.rb                    Dexpace::Pipeline::Cursor
lib/dexpace/pipeline/builder.rb                   Dexpace::Pipeline::Builder
lib/dexpace/pipeline/transform_step.rb            Dexpace::Pipeline::TransformStep
lib/dexpace/pipeline/sync_driver.rb               Dexpace::Pipeline::SyncDriver   (private_constant)
lib/dexpace/pipeline/async_driver.rb              Dexpace::Pipeline::AsyncDriver  (private_constant)
lib/dexpace/async_pipeline.rb                     Dexpace::AsyncPipeline, .direct, .map_response

test/support/probe_steps.rb                       the probe families, required explicitly
test/support/fake_executor.rb                     a counting #post executor
test/support/fake_async_transport.rb              a settled-Future transport
```

**Twelve** new `lib/` files, **ten** `sig/` mirrors and **ten** `test/` mirrors — the two drivers are
`private_constant`s and get neither, per P2-15, and their behaviour is asserted at their call sites, which is the
treatment phase 2 gave `Dexpace::Hooks`, 4a gave `BoundedMap` and 4b gave `Recovery::Ownership`. Three
test-support files. Two already-existing files gain content: `lib/dexpace.rb` and `sig/dexpace.rbs`, plus the
repository-root `test/fixtures/surface/dexpace-core.txt`.

**`lib/dexpace.rb`'s require order is load-bearing here for the second time in phase 4.** There is no autoloader
(`CLAUDE.md`'s bundled-gem rule), and every file under `lib/dexpace/pipeline/` opens `class Pipeline` to nest a
constant inside it — so `pipeline.rb` must be required **first** among them, or the nested files create
`Dexpace::Pipeline` themselves and `pipeline.rb`'s own definition reopens something a reader did not expect to
already exist. Within the nested set the order is `stage` → `stages` → `step` → `entry` → `cursor` → the two
drivers → `builder`, because `Stages` names `Stage` at load and `Builder` names `Entry` at load; every other
reference is inside a method body and resolves at call time. `async_pipeline.rb` is last. This is the same
ordering constraint phase 2 recorded for `hooks` preceding `cancellation/source`, and 4b recorded for
`suppressible` preceding `error`.

**The placement rule is phase 1's and is applied, not re-decided** (P1-1, `module-organization/6e69ad04`): a
public constant the design names without a namespace is flat and its file sits under a directory that organises
rather than namespaces, so `Dexpace::PipelineError` joins `lib/dexpace/error/` beside 4b's `OutcomeError` and
`ProtocolError`. A subsystem the design already names with a namespace keeps it, so `pipeline/` is a directory
that genuinely namespaces — §5.1 and §5.3 write `Dexpace::Pipeline::Stages`. `Dexpace::AsyncPipeline` is flat
because it is a second top-level subsystem constant, on P2-1's precedent (P4-36).

---

## The object model 4c ships

Every public constant, its surface, and the IDs forcing that shape.

### `Dexpace::Pipeline::Stage` — `PIPE-1`, `PIPE-2`, `PIPE-3`, `PIPE-4`, `PIPE-8`

`Data.define(:name, :order, :pillar, :terminal)`, including `Dexpace::Model`, with `private_class_method :new`
and **no public factory at all**: every instance is a constant on `Stages`, and `Stages.of(name)` is the only
lookup. That is `PIPE-2`'s "the runtime MUST preserve the pillar precedence chain" made structural — a caller
cannot mint a sixteenth-and-a-half stage and therefore cannot add a pillar (P4-32).

| Member / method | Requirement |
|---|---|
| `name -> Symbol` | what an error message names (`PIPE-5`, `PIPE-18`, `PIPE-21`) |
| `order -> Integer` | `PIPE-1`'s total order; sparse by 100 (`PIPE-3`) |
| `#pillar? -> bool` | `PIPE-4`'s at-most-one rule, and R10's fork gate |
| `#terminal? -> bool` | `PIPE-8`'s reserved SEND |
| `#installable? -> bool` | `!terminal?`; what rejects an install at SEND |

Validated in `initialize`: `terminal` implies `pillar`, because `PIPE-4` says SEND "is also flagged as a singleton
but is the transport hop itself". **Nothing sorts a `Stage` at run time**, and verified fact 10 is why: `Data`
responds to `<=>` through `Kernel#<=>`, which returns `nil` for two distinct stages, so `entries.sort_by(&:stage)`
raises `ArgumentError` at the first two-stage pipeline. Ordering is `Stages::ALL`'s position, always.

### `Dexpace::Pipeline::Stages` — `PIPE-1`, `PIPE-2`, `PIPE-3`, `PIPE-25`, `PIPE-28`

A module with no instance side. **Sixteen stage constants**, `ALL` (a frozen `Array` in ascending order), `PILLARS`
(a frozen `Array` of the five configurable pillars, SEND excluded) and `.of(name) -> Stage`, which raises
`Dexpace::InvalidArgumentError` on an unknown name.

| Constant | Order | Kind |
|---|---|---|
| `PRE_REDIRECT` | 100 | slot — `PIPE-2`'s outermost pre-redirect slot, and `PIPE-37`'s required placement |
| `REDIRECT` | 200 | **pillar** |
| `POST_REDIRECT` | 300 | slot |
| `PRE_RETRY` | 400 | slot |
| `RETRY` | 500 | **pillar** |
| `POST_RETRY` | 600 | slot |
| `PRE_AUTH` | 700 | slot |
| `AUTH` | 800 | **pillar** |
| `POST_AUTH` | 900 | slot |
| `PRE_LOGGING` | 1000 | slot |
| `LOGGING` | 1100 | **pillar** |
| `POST_LOGGING` | 1200 | slot |
| `PRE_SERDE` | 1300 | slot |
| `SERDE` | 1400 | **pillar**, reserved with no shipped behaviour (`PIPE-2`) |
| `POST_SERDE` | 1500 | slot |
| `SEND` | 1600 | **pillar + terminal** — the transport hop, holds no user step, skipped by flattening (`PIPE-8`) |

**Sixteen, because `PIPE-3` is taken literally** (P4-31). It asks for "a 'pre' slot before and a 'post' slot
after" each pillar; five pillars give ten such slots, `PRE_REDIRECT` is REDIRECT's own pre-slot and is also
`PIPE-2`'s named outermost one, and SEND completes the list. `POST_REDIRECT` and `PRE_RETRY` are adjacent and
order-equivalent; they are kept as two constants because they express two different intents — "after the redirect
loop" and "before the retry loop" — and collapsing them would make `PIPE-3` half-honoured for four of the five
pillars. Sparse numbering is `PIPE-3`'s other clause and is what lets a future specification revision insert a
stage without renumbering.

**There is exactly one `Stages` module and both runtimes use it.** That is §5.3's structural satisfaction of
`PIPE-28` and it is asserted rather than assumed: a test flattens one step set through `#build` and through
`#build_async` and asserts the two entry tables are equal stage-for-stage and step-for-step by identity.

### `Dexpace::Pipeline::Step` — the step protocol

A module with no instance side and no implementation, mirroring `Dexpace::Transport`'s shape. It exists so
`NFR-11`'s RBS scan has a named home for the protocol and so the predicate lives once.

- **`.conforms?(object)`** — `object` responds to `#call` and its callable accepts two positional arguments:
  "required ≤ 2 and (a rest parameter is present or required + optional ≥ 2)", which is phase 2's predicate one
  arity lower and is what verified fact 1 licenses. An object whose `#parameters` cannot be read falls back to
  `respond_to?(:call)` alone rather than refusing — phase 2's rule, unchanged.
- **No registry.** `Dexpace::Registry` has three seam instances and 4c adds no fourth; a step is something a
  caller builds and installs, not something the SDK discovers.

**A step is a duck type and `include Dexpace::Pipeline::Step` is neither required nor meaningful.** §5.1's "a
`lambda` is a step" is the requirement, and a module a lambda cannot include cannot be the gate. The same
admitted gap phase 2 recorded applies: `.conforms?` cannot distinguish a sync step from an async one, because
they differ only in return type. That is why `#build` and `#build_async` are two methods and not one with a flag.

### `Dexpace::Pipeline::Entry` — `PIPE-22`, `PIPE-23`, `PIPE-25`, `PIPE-35`

`Data.define(:stage, :step)`, including `Dexpace::Model`, `private_class_method :new`, `.build(stage:, step:)`
validating that `stage` is a `Stage`, that `stage.installable?` and that `Step.conforms?(step)`.

It is the unit the builder holds, the unit `#reload` and `#install_preset` take, and the unit
`Builder.flattening` reads back off a built runtime. It is public because `PIPE-23`'s bulk reload and `PIPE-35`'s
FLATTEN both need a caller-visible representation of "this step, at this stage"; without it, reload would take
two parallel arrays and flatten would need the runtime to expose its internals.

### `Dexpace::Pipeline::Cursor` — `PIPE-10`–`PIPE-17`, `PIPE-40`

A class, because it owns per-call state (`data-modeling/3e37c086`).

**`.build` is public and validating, and its signature is
`(drive:, request:, options:, cancellation:)` — there is no `owner_index:` or `position:` keyword and a caller
cannot name one.** The `(owner_index, position)` pair is the runtime's: `.build` produces the cursor bound to
entry 0, each advance produces the next one internally, and `#fork` copies the parent's pair unchanged — which is
R10's "a cursor handed to the step at index *i* carries `owner_index = i`", reached from the constructor side.
That is why the surface is safe to leave public,
and it is a narrower claim than the one phase 1's P8 makes about `Request`. The residual holes are the two P8
already names and neither is closed here: `Cursor.send(:new, …)` reaches the generated constructor, and
`drive:` is typed against a `private_constant` driver that `const_get` will hand out. Both put a forged cursor in
the forger's own hands and **neither reaches a step**, because a step never constructs the cursor it is given —
it is handed one by the driver, whose owner index is the position it is invoking, and the gate R10 describes
reads the *runtime's* frozen entry table and nothing the caller supplied. Do not write a proof that the holes are
closed; the reason they cost nothing is the direction of the handoff, not their absence.

| Method | Requirement |
|---|---|
| `#call(request) -> Response` (a `Future` on the async path) | `PIPE-12`, `PIPE-13`. Advances to the next entry and invokes it; when the position is past the last entry, dispatches `@transport.call(request, @options, @cancellation)` — `PIPE-13`'s terminal clause, threading the options (`PIPE-17`). **Single-use**: a second invocation raises `Dexpace::PipelineError` (§5.1, `PIPE-15`) |
| `#fork(state: nil) -> Cursor` | `PIPE-15`, `PIPE-16`. A fresh cursor at the **same** position as the parent, carrying the current in-flight request and the same frozen options object. Raises `Dexpace::PipelineError` unless the owning entry's stage is a non-terminal pillar (R10), **and raises it again on a cursor whose own `#call` is already spent** — `#call` and `#fork` are disjoint on one cursor (R11), so a driving step forks for every drive including the first. `state:` writes into the owner's own stage slot (R11) |
| `#may_fork? -> bool` | so a step can ask rather than rescue; reads the same frozen entry table `#fork` gates on |
| `#request -> Request` | `PIPE-16`'s "carry the current in-flight request" |
| `#options -> RequestOptions` | `PIPE-17`'s "readable by any step". The same frozen object at every position and across every fork, asserted with `assert_same` |
| `#cancellation -> Cancellation` | what a step checks at every resume point; threaded into the terminal dispatch |
| `#state(stage) -> Hash` | R11. Frozen; a shared frozen empty hash for an unwritten stage |
| `#spent? -> bool` | whether `#call` has been used; what makes `PIPE-15`'s defect observable in a test without rescuing, and what a step asks before choosing between `#call` and `#fork` |

**`PIPE-14`'s substitution "sticks" by construction**: `#call(request)` takes the request as its argument and the
child cursor carries *that* object, so a substituted request reaches every downstream step and the terminal
dispatch with nothing to remember. The original is not retained anywhere on the drive.

**The cursor holds no lock, and that is a decision with a measured cost** (P4-33). It is created per step
invocation, handed to exactly one step, and never published; the only mutable state is the single-use flag. A
`Thread::Mutex` per invocation would cost an allocation on every step of every call and would introduce a
per-fiber-owned, non-reentrant lock into the hot path (`concurrency-and-async/f414b864`). Verified fact 9 measures
what is given up: two threads calling one cursor concurrently both got through on **29 of 2000 runs on 3.2.11**
and **0 of 2000 on 3.4.10 and 4.0.6**. So `PIPE-15`'s "MUST be treated as a defect" is honoured — the runtime
raises — and the detection is **sequential-only**. Handing one cursor to two threads is already the defect
`PIPE-15` names; this design does not promise to catch every
instance of it, and it ships no test asserting the race, because at 1.5 % the single-shot form of that test is a
flake on the floor too and the 2000-run form is green on one column and red on three.

**Where "sequential-only" is written, in three places, because one of them is not enough.** In `Cursor#call`'s
YARD, which is what a step author reads. In the `#fork` YARD paragraph the phase-6 pillar families are pointed
at, because they are the steps that hold a cursor longest. And in *The interface surface later phases may cite*
below, because a phase-6 author scoping work from that table alone would otherwise inherit "the runtime raises
on reuse" with no qualifier. `docs/knowledge/notes/pipeline.md` carries it for anyone who arrives from the
corpus instead.

### `Dexpace::Pipeline::Builder` — `PIPE-4`–`PIPE-8`, `PIPE-18`–`PIPE-25`, `PIPE-35`, `PIPE-38`

A mutable class, phase 1's builder shape (`HTTP-3`'s split: cross-field validation, so a real builder rather than
`#with`). **One builder serves both runtimes** (P4-30) — the staging, the pillar exclusivity, the surgical edits
and the flattening are one implementation, which is `PIPE-28`'s "MUST NOT each re-derive ordering independently"
satisfied by there being one deriver rather than by two derivers agreeing.

| Method | Requirement |
|---|---|
| `.new(transport:)`, `Pipeline.builder(transport:)` | the entry point |
| `.flattening(pipeline)` | `PIPE-35` FLATTEN — copies the runtime's entries **and** its transport, so the seeded steps run inside the new builder's loops |
| `.nesting(pipeline)` | `PIPE-35` NEST — a new builder whose **transport is that pipeline**, legal because `PIPE-26` makes a pipeline a transport, so the new steps run once outside the nested loops |
| `#append(step, stage: nil)` / `#prepend(step, stage: nil)` | `PIPE-7` tail and head; pillar exclusivity checked here (`PIPE-4`, `PIPE-5`, `PIPE-6`) |
| `#append_all(steps, stage: nil)` / `#prepend_all(steps, stage: nil)` | `PIPE-38`. `prepend_all` is written as "each element prepended individually", so the reversal is a consequence rather than a special case, and the YARD documents the asymmetry as the requirement demands |
| `#insert_after(anchor_type, step, stage: nil)` / `#insert_before(…)` | `PIPE-18`. First instance of the anchor type in flattened order; same-stage required; cross-stage rejected |
| `#replace(anchor_type, step, stage: nil)` | `PIPE-19`. First instance, 1:1, same stage |
| `#remove(anchor_type)` | `PIPE-20`. Every instance, relative order preserved, no-op when absent |
| `#reload(entries)` | `PIPE-23`. All-or-nothing: validate the whole set, then swap |
| `#install_preset(entries)` | `PIPE-24`. Empty target pillars only, validated up front, whole call rejected on any collision (R14) |
| `#entries -> Array[Entry]` | the flattened order as it currently stands; what `PIPE-22`'s determinism is asserted on |
| `#build -> Pipeline` / `#build_async -> AsyncPipeline` | `PIPE-25`. Flatten once into an immutable runtime |

**Pillar collisions, stated exactly because `PIPE-5` and `PIPE-6` are two halves of one rule.** Installing a step
onto an occupied pillar compares by **`#equal?`**, never `==`: the same object is idempotent (`PIPE-6`, no error,
no duplication), a distinct object raises `Dexpace::PipelineError` naming both types and pointing at `#replace`
(`PIPE-5`). Reference identity is load-bearing and is the same trap `CTX-9` sets in §5.4 — core's models define
value equality, so `==` on two structurally identical steps would report them the same and silently swallow a
genuine collision. Verified fact 3 is why the test fixture must be a `Data` step and not a lambda.

**Flattening is one function and it re-derives from the stage table, never from an accumulated order:**
`Stages::ALL.flat_map { |stage| bucket_for(stage) }`, skipping SEND. `PIPE-22`'s "the observable ordering after an
edit is identical to building the same set of steps from scratch" is then true because there is nothing else it
could be, and it is asserted directly by comparing an edited builder's `#entries` against a freshly built one's.

**Missing anchors and cross-stage moves each raise with the offending type named** (`PIPE-21`, `PIPE-18`,
`PIPE-19`), and `#remove` on an absent type is a silent no-op — the one place the four surgical edits differ from
one another, and each gets its own test.

### `Dexpace::Pipeline` — `PIPE-9`, `PIPE-10`, `PIPE-25`, `PIPE-26`, `PIPE-27`, `PIPE-39`

A class. Frozen after construction; `private_class_method :new`, built through `Builder#build`.

| Method | Requirement |
|---|---|
| `.builder(transport:) -> Builder` | the composition entry point |
| `.direct(transport) -> Pipeline` | `PIPE-39`'s step-less constructor |
| `#call(request, options = RequestOptions::EMPTY, cancellation = Cancellation.none) -> Response` | `PIPE-26`. A pipeline **is** a transport, with and without options, verified fact 2. `PIPE-9`'s empty branch and `PIPE-10`'s cursor branch are the two arms of one `if` (R12) |
| `#steps -> Array` | `PIPE-25`'s read-only ordered view. A frozen `Array` of the step objects, the **same object** on every call, never a lazy enumerator (`pagination/b2a85752`, verified fact 8) |
| `#entries -> Array[Entry]` | the stage-annotated view `Builder.flattening` reads and an inspector wants. Frozen, same object each call |
| `#transport` | what `Builder.flattening` copies |
| `#close` | `PIPE-27`. `Dexpace::Closeable` with `owned: false` — latches, releases nothing, never cascades to the transport. Phase 2's shape for both bridges, unchanged |

`#steps` and `#entries` are two frozen arrays built once at construction and returned by the same reference every
time, which is design §10.11's computed-once rule rather than a per-access `dup` or a wrapper.

### `Dexpace::AsyncPipeline` — `PIPE-28`–`PIPE-32`

A class, flat, not `Pipeline::Async` — P2-1's precedent for `Dexpace::AsyncTransport`, and for the same reason: a
seam beside its own implementations is the confusion `SEAM-2` exists to prevent (P4-36).

| Method | Requirement |
|---|---|
| `.direct(transport) -> AsyncPipeline` | `PIPE-39`'s step-less constructor, async form |
| `#call(request, options = …, cancellation = …) -> Dexpace::Async::Future` | the async mirror. Same cursor, same entry table, same stage order |
| `#steps`, `#entries`, `#transport`, `#close` | as `Pipeline` |
| `.map_response(future, &handler) -> Future` | `PIPE-31`'s terminal response-mapping operator |

**It has no `Stages` of its own and no `Cursor` of its own.** It references `Dexpace::Pipeline::Stages` by that
name and uses `Dexpace::Pipeline::Cursor` unchanged; what differs between the runtimes is one `private_constant`
driver that knows how to invoke a step and reach the terminal transport. `PIPE-28` is satisfied by there being
nothing to keep in sync (P4-30).

**`PIPE-29` and `PIPE-30`, at the call site no phase-2 object reaches.** The async driver wraps every step
invocation and the empty-pipeline dispatch:

```
rescue ::Exception => e
  raise unless e.is_a?(::StandardError)   # PIPE-30's fatal family; bare raise, verified fact 7
  completer.fail(e)
```

Two consequences are stated rather than left to be met. **A `ScriptError` propagates synchronously**, so an async
step that lazily `require`s something absent raises a `LoadError` out of `#call` rather than failing the future —
the same line 4b drew for `RECOV-2` (its verified fact 4), reached here independently and named in the YARD.
And **an argument-validation raise from a step is normalised too**: `PIPE-29` permits a step to "throw
synchronously only for caller-bug argument-validation errors", but `PIPE-30` requires the runtime to normalise
"ANY synchronous exception", so the runtime's obligation is unconditional and `PIPE-29`'s permission is a
statement about what a *step author* may do, not a hole in the runtime. Both requirements are then satisfiable at
once, which a reading that treats `PIPE-29` as an exception to `PIPE-30` is not.

**`PIPE-31`'s operator is a class method over the pivot, not an overload of `#call`** (P4-38):
`AsyncPipeline.map_response(source) { |response| … }` returns a new `Future` and

- on success, applies the handler and **then** closes the response, in an `ensure`, tolerating the idempotent
  double close phase 3's latch provides;
- if the handler raises, closes the response and fails the returned future with the handler's error — which is
  the requirement's "close any response that accompanies a failure";
- needs no unwrapping, because the pivot never wraps: `Completer#fail(error)` stores the error and `#value`
  re-raises *that object*, phase 2's structural satisfaction of the same clause in `sync_over`. The test asserts
  the identical object comes back, not merely an equal message;
- wires `completer.on_cancel { |reason| source.cancel(reason) }`, so cancelling the mapped future reaches the
  send. The block parameter is not decoration: phase 2's `Completer#request_cancel` runs its hook list through
  `Hooks.notify(hooks, reason)`, so the reason arrives **as the block's argument**. Written without the parameter,
  `{ source.cancel(reason) }` parses, and `reason` is then an undefined local that raises `NameError` inside the
  hook on the first cancellation — where `Hooks.notify` swallows it into the "first failure re-raised after the
  whole list" path and the cancellation reaches the source having lost its reason. One line, phase 2's shape, and
  it is what stops `map_response` from being a place a cancellation goes to die.
- needs no separate close on a *source* failure, and the reason is phase 2's `Settlement` rather than this
  operator: `Settlement.failure(error)` carries an error and no response, so "close any response that accompanies
  a failure" has exactly one reachable case here — the handler raising over a response the source delivered — and
  that is the bullet above. Stated because the requirement's wording invites a second, unreachable branch.

It is a class method taking a future rather than a `#call`-with-handler overload because that makes it testable
against a bare `Completer` with no pipeline, transport or fake in sight, and because a second `#call` arity would
collide with `PIPE-26`'s transport shape, which must stay exactly three positional parameters.

### `Dexpace::Pipeline::TransformStep`

R8's adapter, above. `.build(transform)`, `#call(request, cursor)`, `#transform`.

### `Dexpace::PipelineError` — `PIPE-5`, `PIPE-8`, `PIPE-15`, `PIPE-18`, `PIPE-19`, `PIPE-21`, `PIPE-23`, `PIPE-24`

`< ::StandardError`, `include Dexpace::Error`, matching phase 2's three and 4a's `ContextConflictError`. Named
flat by §5.1, so the constant is not this design's invention; its message forms are.

**One class for nine conditions, carrying no fields** (P4-37). Every condition it reports is a composition-time
or defect condition that a caller fixes by editing code — a pillar collision, an install at SEND, a cursor reused,
a fork from a slot, a fork from a spent cursor (P4-39), a cross-stage move, a missing anchor, a rejected reload, a
rejected preset. None is a runtime
race a caller could retry, which is the distinction that made 4a's `ContextConflictError` carry `#call_key`: a
caller that lost a race may retry and needs the key. Here no caller branches on the reason, so a field would be
surface with no reader — the failure `NFR-4` makes permanent. The messages are fixed in this design so the plan
writes tests against exact forms, and each names the requirement's own words: `PIPE-5`'s "naming both step types
and pointing at the replace path", `PIPE-21`'s "identifying the missing type".

### The RBS interfaces

`interface _Step` declares `#call: (Dexpace::Request, Dexpace::Pipeline::Cursor) -> Dexpace::Response` and
`interface _AsyncStep` the same returning `Dexpace::Async::Future`. A type alias unions each with the
corresponding proc type, so a lambda step type-checks. Declaring them as interfaces rather than typing the step
lists `untyped` keeps `NFR-11` mechanical: no constant outside `Dexpace::` and the stdlib allowlist appears in any
public signature. They are 4c's constants for `NFR-4` purposes and carry a ledger row.

**The one signature the two interfaces do not settle is `Cursor`'s own, and P4-30 is what creates the problem.**
One `Cursor` class serves both runtimes, so `Cursor#call` returns a `Dexpace::Response` under `SyncDriver` and a
`Dexpace::Async::Future` under `AsyncDriver`, and `#fork` returns whichever cursor the caller then calls. RBS has
no way to say "the same class, two return types, chosen by a `private_constant` collaborator". Three answers are
available and this design does not pick one, because the right choice depends on how much of core's internals
Steep's target for `lib/dexpace/pipeline/` is set strict over — which is phase 0's `Steepfile` shape, not this
phase's: a union `Dexpace::Response | Dexpace::Async::Future`, which type-checks and pushes a narrowing onto
every step author; a generic `class Cursor[R]` with `_Step` and `_AsyncStep` naming `Cursor[Response]` and
`Cursor[Future]`, which is precise and is the first generic in this repository; or `untyped` on `#call` alone
with the two interfaces carrying the real types, which is what phase 2 did for `Future#value`'s response for the
same reason. It is listed under *Open questions* so the plan makes it deliberately.

---

## The spec-forced boundaries, honoured

Each of the charter's sixteen that reaches 4c, with what honouring it costs.

1. **Spec §8.3's two-layer prohibition** — "A port MUST NOT collapse the two layers into one: the stage pipeline
   owns ordering and re-drive-with-fork; the recovery chain owns the sum-type fold and the uniform-failure
   guarantee." Honoured in both directions and checkably: **no `Dexpace::Pipeline::` object mentions
   `Dexpace::Outcome`, either chain, or the orchestrator**, and no `PIPE` step returns an `Outcome`. The single
   crossing is `TransformStep`, which 4b's R8 assigns to 4c, and it names one value type. The `PIPE-30`
   normalisation is 4c's own three lines at 4c's own call site and does **not** call into `Dexpace::Recovery`,
   even though the fatal-family rule is the same rule — sharing the code would make the `PIPE` layer's error
   handling a function of the recovery layer's, which is what the prohibition forbids. The rule is stated once
   here and once in the YARD instead.
2. **`PIPE-2`'s pillar precedence chain and `PIPE-8`'s reserved terminal.** The order is a frozen table; `SEND` is
   `terminal?` and rejects every install; flattening skips it. **4c adds no pillar and reorders nothing**, and the
   stage table's closedness is structural (P4-32) rather than a promise.
3. **`PIPE-28`.** One `Stages`, one `Builder`, one `Cursor`; the runtimes differ by one private driver.
4. **`PIPE-15`/`PIPE-16`'s fork.** `#call` single-use, raising on a second invocation; `#fork` gated at
   composition time from the frozen entry table. R10 decides where the assignment lives; it does not re-decide
   that the check is at composition time.
5. **`PIPE-37`'s placement rule.** `PRE_REDIRECT` at order 100, outside every fork; 4b's `ErrorMappingStep`
   installed there through `TransformStep`; the test asserts one invocation, identity return and an unread body.
6. **`RECOV-1`'s closed outcome and `RECOV-6`'s fold order** — 4b's, and 4c neither extends nor observes them.
7. **`RECOV-8`'s totality** — 4b's.
8. **`RECOV-12`/`RECOV-13`'s ownership asymmetry** — 4b's. `PIPE-40`'s superficially similar rule is a different
   rule at a different layer and 4c does not unify them: `RECOV-12` is about a step that throws while holding a
   `Success`; `PIPE-40` is about a step that re-drives and supersedes a response. The first is the recovery
   chain's and the second is the re-driving step's.
9. **`RECOV-14`'s uniform defensive copy** — 4b's, and it is the model `Builder#build` follows for its own step
   collection: the entry table is copied and frozen once at build, so later mutation of the builder cannot alter a
   built runtime. Asserted directly.
10. **`RECOV-16`'s one bound** — 4b's; 4c declares no constant of its own and reads none.
11.–14. **`CTX-9`, `CTX-17`, `CTX-19`, `CTX-14`/`CTX-15`** — 4a's. 4c consumes none of them.
15. **`PIPE-33`/`PIPE-34` reuse phase 2's two bridges.** Honoured by shipping nothing: no second executor duck
    type, no second orphan close, no second bridge-level normalisation (R13, P4-35).
16. **§10.5's split is settled and is not re-opened.** `PIPE-33`'s interrupt clause is unsatisfied; the
    non-interrupting half is met exactly; the four met clauses are enumerated above so the ⏳ row is not read as a
    wholly unbuilt requirement. **Nothing in this document argues the trade.**

---

## Cross-cutting constraints that bite 4c specifically

1. **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden in every gem**, enforced by
   `Dexpace/NoThreadInterrupt`. In 4c the constraint is met by an absence: **4c writes no wait, no sleep and no
   interrupt of any kind.** The only blocking call in reach is phase 2's `Future#value(cancellation:)`, and 4c
   does not call it either — a caller composing `AsyncTransport.sync_over` does.
2. **Deadlines are explicit values, not ambient interrupts.** `DEF-28` keeps `deadline:` off the pivot until
   phase 5; 4c ships the narrower composition and fabricates no deadline (R13).
3. **`Fiber[:key]` is the diagnostic-context carrier and `PIPE` is not it.** Per-call state lives on the cursor
   and is passed as an argument, never read from ambient storage. That is `PIPE-11` in as many words — "per-request
   mutable state MUST live in the per-call cursor … never on the step" — and it also means a step that spawns a
   fiber or a thread must hand it the cursor explicitly; nothing is inherited. Stated in the YARD, because
   `Fiber[]`'s inheritance (4a's verified fact 7) makes the wrong intuition available.
4. **`Thread::Mutex` is per-fiber-owned and non-reentrant.** 4c holds no mutex anywhere. The built runtime is
   immutable, so concurrent sends read frozen data with no lock (`PIPE-10`); the cursor is per-invocation and
   unshared (P4-33); the builder is single-threaded by construction and says so in its YARD, exactly as phase 1's
   builders do.
5. **An `Enumerator` abandoned mid-`#next` never runs its `ensure`.** `#steps` and `#entries` are frozen `Array`s,
   the flatten is `flat_map`, and no resource is acquired inside any block 4c yields from. `PIPE-25`'s "read-only,
   ordered view" is the place a lazy enumerator would be the idiomatic Ruby answer and the wrong one
   (`pagination/b2a85752`).
6. **Bytes on the wire are `Encoding::BINARY`.** 4c touches no bytes: a step receives a `Request` and returns a
   `Response`, and the body is phase 3's.
7. **The bundled-gem rule.** 4c adds nothing to the require allowlist. In particular the LOGGING pillar is a
   *slot*: core never `require`s `logger`, and the sink is a duck type (§8.1).
8. **`Ractor` is never load-bearing.** The stage table and the entry table are deep-frozen and would be
   Ractor-shareable, but a `Response` holds a body holding an `IO`, so **no shareability claim is made for a
   cursor, a runtime or a step**, and none is written into any YARD.
9. **`Regexp` timeouts are per-pattern.** 4c compiles no regexp.

---

## Testing strategy

`test/` mirrors `lib/` one file per file; each file's header comment names the requirement IDs it exercises and a
non-obvious branch names the ID that forced it. Every suite subclasses `DexpaceTestCase`, so a warning raised by
code under test fails the test that triggered it.

**No transport, no socket, no stream.** Roadmap cross-cutting constraint 4 puts phases 1 through 7 on an in-memory
fake transport implementing only the `SEAM-11`/`SEAM-16` seams, and 4c is the phase that most needs it: every
`PIPE` rule is about ordering, cursors and composition, none is about bytes, and the terminal hop is a lambda
recording its three arguments. Phase 2's `test/support/fake_transport.rb` is reused unchanged.

**The doubles, and why each exists.** All are fakes rather than mocks (`testing/630ba094`, `testing/7ecef8e8`):
real in-memory implementations of an owned interface, not recorders of expectations.

- **`ProbeStep`** — `Data.define(:tag, :log)` with `#call(request, cursor)` appending `[:enter, tag]` and
  `[:exit, tag]` around `cursor.call(request)`. It is a `Data` **deliberately**: verified fact 3 makes two
  same-membered instances `==` and not `equal?`, which is the only pair that discriminates `PIPE-6`'s
  reference-identity rule from a value-equality implementation. A lambda-based probe would pass against the wrong
  implementation. **Two things about the shape are load-bearing and were got wrong once in drafting this
  document, so they are written down rather than left to the plan.** A two-member `Data` has no one-argument
  constructor: `ProbeStep[:a]` raises `ArgumentError: missing keyword: :log` on 3.2.11, 3.4.10 and 4.0.6, so
  every construction in the suite is `ProbeStep.new(tag: :a, log: log)`. And **the `log` member is what decides
  `==`**: two probes with *separate* log arrays are `==` only while both are empty, and stop being `==` the
  instant either runs — measured on all three, `a == b` flips `true` → `false` after one appended entry. The
  `PIPE-6` fixture therefore constructs both probes over **one shared `log` object**, so the `==`-and-not-`equal?`
  relation is a property of the pair rather than of when the assertion happens to run. A fixture built the
  other way is not merely fragile: once the two are `!=`, the collision raises for the wrong reason and the
  test passes against the `==`-based implementation it exists to fail.
- **`ForkingProbe`** — a pillar-stage probe that forks *n* times, closing each superseded response before the next
  drive and returning the last unclosed. It is `PIPE-15`, `PIPE-16` and `PIPE-40`'s conformance fixture, and it is
  what proves the rules are honourable before phases 5 and 6 have to honour them.
- **`StateProbe`** — a pillar probe that forks with a named state map, and a slot probe that reads one. R11's five
  assertions are written against these two.
- **`FakeExecutor`** — `#post { … }` running the block synchronously and counting calls. `PIPE-33` clause 2's
  "single opaque unit" is `assert_equal(1, executor.posts)` for a five-step pipeline.
- **`FakeAsyncTransport`** — returns an already-settled `Future`, or a `Completer` the test settles, so every
  async assertion is deterministic and no test sleeps.

**The tests a reader would otherwise write wrong.**

- **`PIPE-1`'s conformance clause, verbatim.** One probe per stage — fifteen, SEND excluded — installed in a
  **shuffled** order under a pinned seed (`testing/7ece0212`): the entry log equals `Stages::ALL` minus SEND, and
  the exit log is its exact reverse. Installing them in declaration order would pass against an implementation
  that preserved insertion order and derived nothing, which is the one thing `PIPE-1` forbids.
- **`PIPE-2`'s conformance clause, verbatim.** A `ForkingProbe` at `REDIRECT` driving twice: a probe at
  `PRE_REDIRECT` is invoked **once** and sees the final response, and a probe at `AUTH` is invoked **twice**. This
  is the assertion that would fail if `PRE_REDIRECT` were ordered inside the redirect loop, and it is the same
  fact `PIPE-37` and §6.2 both rest on.
- **`PIPE-6`'s idempotence, and the fixture that makes it real.** `log = []`, then
  `first = ProbeStep.new(tag: :a, log: log)` and `second = ProbeStep.new(tag: :a, log: log)` — one shared `log`,
  for the reason under *The doubles*. Install `first` at `RETRY`; re-install the **same object** — no error, no
  duplication, `entries.size` unchanged. Then install `second`, asserting `first == second` and
  `!first.equal?(second)` in the same test so the discriminating property is stated rather than assumed —
  `Dexpace::PipelineError`, message naming both types. The second half is the test; the first half alone passes
  against an `==`-based implementation.
- **`PIPE-16`'s independent forks.** A `ForkingProbe` at `RETRY` forking twice, with counting probes at
  `POST_RETRY` and `AUTH`: each downstream probe is invoked exactly twice, and the two forks' `#spent?` states are
  independent. A test that only asserted the response came back would pass against a cursor that resumed past the
  downstream tail on the second drive — the exact defect `PIPE-15` describes.
- **`PIPE-13`'s forward-only cursor.** A probe calling `cursor.call` twice raises `Dexpace::PipelineError`, and
  `cursor.spent?` is `true` afterwards. Asserted on the raised object, never with `assert_nothing_raised`
  (`testing/26b866e1`, `testing/80c44c7f`). A second case in the same file: a **pillar** probe that calls
  `cursor.call` and then `cursor.fork` raises too, which is R11's disjointness rule and is the assertion that
  fails if someone re-admits `PIPE-15`'s mixed drive-then-fork shape.
- **`PIPE-12`'s short-circuit, which has no natural home anywhere else.** A probe at `PRE_AUTH` that returns a
  synthetic `Response` **without** calling `cursor.call`: every downstream probe is invoked zero times, the fake
  transport is never reached, and the synthetic response is what comes back by identity. It is one small test and
  it is listed here because `PIPE-12`'s "MAY short-circuit" is the one clause in the cursor's range that no other
  test in this section would exercise even incidentally — every other fixture drives the chain.
- **`Stages::ALL`'s literal order against `Stage#order`.** `assert_equal(Stages::ALL, Stages::ALL.sort_by(&:order))`,
  plus `assert_equal(Stages::ALL.map(&:order), Stages::ALL.map(&:order).uniq.sort)`. `ALL` is a hand-written
  frozen `Array` and `#order` is a separate public member that **nothing at run time reads** (verified fact 10:
  flattening walks `ALL`'s positions, and sorting a `Stage` raises), so the two can disagree with no symptom
  while `#order` is `NFR-4`-locked surface a caller may reasonably order by. This is the assertion that catches a
  sixteenth stage inserted in the list at the wrong index, or given a duplicate or out-of-sequence key — the one
  edit `PIPE-3`'s sparse numbering exists to make safe and the one nothing else would notice.
- **`PIPE-14`'s sticking substitution.** A probe at `PRE_RETRY` substitutes a new `Request`; every downstream
  probe and the fake transport assert `assert_same` on that object, and the original is asserted absent.
- **`PIPE-17` across a fork.** `assert_same` on the options object at every probe, at both forks, and at the
  transport. `assert_equal` would pass against an implementation that rebuilt them per fork, which is the clause's
  "not copied-and-diverged" half.
- **R11's five assertions**, above — including the two negatives nothing else would catch.
- **R12's four assertions**, above — including the two `ObjectSpace` allocation deltas.
- **`PIPE-22`'s determinism.** Build a set of steps, apply an `insert_after`, a `remove` and a `replace`, and
  assert `edited.entries == from_scratch.entries` for a builder seeded with the resulting step set. Comparing the
  *flattened entries* rather than the response is what makes the assertion about ordering.
- **`PIPE-23` and `PIPE-24`'s all-or-nothing.** Capture `builder.entries` before the rejected call, assert the
  raise, assert `builder.entries` is unchanged. Asserting only the raise would pass against a partial rebuild.
- **`PIPE-35`'s two seedings, distinguished by behaviour.** The same inner pipeline with a `ForkingProbe` at
  `REDIRECT`, seeded both ways, with a new probe added at `PRE_RETRY`: under FLATTEN the new probe runs **twice**
  (it is inside the redirect loop); under NEST it runs **once** (the inner pipeline is an opaque transport). That
  is `PIPE-35`'s own wording turned into two numbers, and it is the only assertion that distinguishes the two
  constructors at all.
- **`PIPE-38`'s asymmetry.** `append_all([a, b, c])` yields `a, b, c` within the stage; `prepend_all([a, b, c])`
  yields `c, b, a`. Both asserted, because the requirement's own words are "a port MUST document this asymmetry"
  and a test is the documentation that cannot go stale.
- **`PIPE-28`'s single derivation.** One step set flattened through `#build` and `#build_async`; the two entry
  tables equal stage-for-stage and step-for-step **by identity**.
- **`PIPE-29`/`PIPE-30`.** An async step raising `RuntimeError` synchronously: the returned future is failed and
  `#call` did not raise. An async step raising `NotImplementedError` (a `ScriptError`): `#call` **does** raise,
  and the test asserts the class rather than merely that something escaped.
- **`PIPE-31`.** Success: the handler's value settles the future and `response.closed?` is `true`. Handler raises:
  the future fails with the identical object and the response is still closed. Double close: closing again is a
  no-op. Cancellation: cancelling the mapped future cancels the source.
- **`PIPE-33` and `PIPE-34` end to end**, through phase 2's bridges over a real five-step pipeline: one `#post`,
  options arriving by identity, the response coming back, and — for `sync_over` — a cancelled token raising
  `Dexpace::CancelledError` rather than blocking. There is no test of interrupt-mode cancellation, because there
  is no interrupt mode; the ⏳ row and §10.5 are where that is recorded.
- **`PIPE-27`.** `pipeline.close` twice; the fake transport's `closed?` is `false` after both. The negative is the
  assertion — a test that only called `close` once and checked nothing would pass against a cascading close.

**The audit groups 4c's plan must run and record**, per the roadmap's first retrospective rule: *Public API
surface* (this phase adds more public constants than any since phase 1), *RBS / Steep typing*, *Minitest
conventions*, *Fiber scheduler, thread safety*, and *Resource lifecycle and stream ownership* — the last because
`PIPE-40` and `PIPE-31` are both response-lifecycle rules and the styleguide's block-form resource rule needs the
same disposition 4b's P4-18 and phase 3a's P3-10 gave it.

**No property tests.** `testing/f36a19cd` makes round-trip property tests mandatory for "any value object with
parse-constructor invariants". 4c ships two `Data` types — `Stage` and `Entry` — and neither qualifies: `Stage`
has no public constructor at all and its instances are sixteen constants, so a generator would draw from a set of
sixteen and assert nothing a direct test does not; `Entry` is a pair whose validation is two type checks. Recorded
as a disposition rather than an omission.

---

## The interface surface later phases may cite

Stated as a contract, so a later phase cites rather than re-derives.

| Consumer | What it gets, and the obligation |
|---|---|
| **Phase 5**, on the instrumentation step | `Stages::LOGGING` as the pillar, and `Stages::PRE_LOGGING`/`POST_LOGGING` as its slots. The step declares `#stage` and is installed with no `stage:` argument (R10). It is a pillar, so it **may** fork. It should not: a step that drives the chain exactly once drives it through `#call`, and `#call` and `#fork` are disjoint on one cursor (R11) — a step either calls once and never forks, or forks for every drive and never calls |
| **Phase 5**, on `DEF-28` | Nothing new. 4c calls no blocking wait; when `deadline:` lands on `Future#value`, `AsyncTransport.sync_over` gains it and no pipeline signature changes |
| **Phase 6**, on `REDIR-11`/`AUTH-29` | **`Cursor#fork(state:)` and `Cursor#state(stage)`.** The redirect step forks per hop from its own cursor with `state: { cross_origin: … }`, landing in `Stages::REDIRECT`'s slot; the auth step reads `cursor.state(Dexpace::Pipeline::Stages::REDIRECT)`. **Phase 6 adds no marker to the request and strips nothing**, which is §10.15's whole claim. The five negative assertions in R11 are the tests that fail if the mechanism is changed |
| **Phase 6**, on `RETRY`/`REDIR` pillar steps | `Stages::REDIRECT` and `Stages::RETRY`, `Cursor#fork`, `Cursor#may_fork?`, and **`PIPE-40`'s rule as stated in `#fork`'s YARD**: close every superseded intermediate before the next drive, never close the one handed back, return the in-flight response unclosed on an abandoned re-drive. `ForkingProbe` in `test/support/` is the worked example and its test is the requirement's own conformance clause. **Two limits travel with the handle and are part of this contract, not footnotes to it.** A driving pillar step **forks for every drive including the first** and never calls its own `#call` — the rule stated under R11, which is what makes hop 1 and hop *n* the same shape and what `#fork`'s YARD says. And `#call`'s reuse guard is **sequential-only** (P4-33): a second sequential call always raises, a second *concurrent* call sometimes does not, so a pillar step must not treat the raise as a concurrency guard |
| **Phase 6**, on `PIPE-24`/`PIPE-39` (`DEF-39`) | `Builder#install_preset(entries)` — the all-or-nothing mechanism, built and tested. Phase 6 writes `Pipeline.standard` and `AsyncPipeline.standard` **over** it, with `PIPE-32`'s explicit `redirect: :unsupported` argument on the async one, and writes no second installation path |
| **Phase 6**, on `PIPE-36` (`DEF-4`) | If the deferral is ever picked up, `#stage`'s precedence table in R10 is where the lock goes: a family locks by defining `#stage` and rejecting a `stage:` argument. Verified fact 6 records why `Method#owner` is **not** a usable detector for a subclass that inherits `#stage` |
| **Phase 7**, on `PAGE`/`SSE` | `PIPE-26`: a built pipeline is a transport, so a paginator takes one with no declaration. `Pipeline#close` is a no-op on the transport (`PIPE-27`), so a paginator wrapping one owns nothing |
| **Phase 8**, on `TRANSPORT-1`/`TRANSPORT-2` | The premise those two requirements presuppose: `PIPE` is the single authority on redirect and retry, so an adapter disables its native client's own. `Stages::REDIRECT` and `Stages::RETRY` are where that authority lives |
| **Phase 8**, on `PIPE-33` (`DEF-18`) | `Dexpace::Pipeline` as the object `Transport.async_over` wraps. Phase 8's `dexpace-async-thread` is what makes `PIPE-33`'s interrupt clause's antecedent real; its disposition is a re-assertion at the point the requirement starts applying, not a second decision |
| **Phase 9**, on `XCUT-11` | `Dexpace::Pipeline` and `AsyncPipeline` as audited shared-instance state: immutable after construction, no lock, no per-call state on the instance. `Dexpace::Pipeline::Cursor` is the per-call state, and the audit target is that nothing else is |
| **Phase 9**, on the conformance pass | The ⏳ rows and their reasons: `PIPE-33` (`DEF-18`, four of five clauses met), `PIPE-36` (`DEF-4`), `PIPE-39` (`DEF-39`, one of two constructors shipped), and `PIPE-32`'s vacuity until `DEF-39` lands |

---

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`. Numbering continues from 4b's
`P4-25`.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P4-26 | Public **constants** neither design §5.1 nor §5.3 names as Ruby constants: `Dexpace::Pipeline::Stage`, `::Stages` with its sixteen stage constants plus `ALL` and `PILLARS`, `::Step`, `::Entry`, `::Cursor`, `::Builder`, `::TransformStep`, `Dexpace::AsyncPipeline`, and the RBS interfaces `_Step` and `_AsyncStep` | `NFR-4`; `NFR-11`; P1-1; P2-11, P3-14, P4-2 and P4-24 precedent | `NFR-4` locks a name before it locks a signature. §5.1 names `Dexpace::Pipeline::Stages` and `Dexpace::PipelineError` and no other Ruby constant; §5.3 names `Stages` again and nothing else. Every name above is chosen for a stated reason in the object-model section. Placement follows P1-1 unchanged: `Pipeline` is a namespace the design itself wrote, `PipelineError` is flat and joins `lib/dexpace/error/`, and `AsyncPipeline` is flat on P2-1's precedent |
| P4-27 | Public **methods** neither §5.1 nor §5.3 names: `Stage#pillar?`, `#terminal?`, `#installable?`; `Stages.of`; `Step.conforms?`; `Entry.build`; `Cursor.build`, `#call`, `#fork`, `#may_fork?`, `#request`, `#options`, `#cancellation`, `#state`, `#spent?`; `Builder.new`, `.flattening`, `.nesting`, `#append`, `#prepend`, `#append_all`, `#prepend_all`, `#insert_after`, `#insert_before`, `#replace`, `#remove`, `#reload`, `#install_preset`, `#entries`, `#build`, `#build_async`; `Pipeline.builder`, `.direct`, `#call`, `#steps`, `#entries`, `#transport`, `#close`; `AsyncPipeline.direct`, `.map_response`, and its five instance methods; `TransformStep.build`, `#call`, `#transform` | `NFR-4`; `api-design/b0e18938`; P2-11, P3-8, P4-11 and P4-23 precedent | `NFR-4` locks a public *signature*, not only a public name, and §5.1 describes the whole subsystem in prose while naming two Ruby constants and no method at all. Three deserve naming here. **`Cursor#spent?` and `#may_fork?` have no caller in `lib/`** — both exist so a step can ask rather than rescue and so the suite can assert without `assert_nothing_raised`, and deleting either later would be an `NFR-4` break for a method core never used. **`Pipeline#transport` is public only because `Builder.flattening` must read it**, and Ruby has no package-private visibility; the alternative is a cross-object `send`, which is the hole P2's `Completer`/`Future` pair exists to avoid. The `Data`-generated readers on `Stage` and `Entry` are public API too and are invisible to `rbs validate`; the runtime surface snapshot is what holds them, and the phase's last task regenerates both |
| P4-28 | **Cursor-scoped state is keyed by `(stage, key)`**, not by key alone as design §5.1's "a small keyed map of per-call state" writes it | §5.1; §6.2; §10.15; `REDIR-11`, `AUTH-29`, `PIPE-16` | Under a flat namespace a `RETRY` pillar step — which sits between REDIRECT and AUTH in `PIPE-2`'s own order, occupies a pillar, and may therefore fork — can write the key AUTH reads, and AUTH cannot tell that value from REDIRECT's. §6.2's sentence "**no step downstream of AUTH can [set the marker] either**" and §10.15's "forgery becomes structurally impossible rather than defended against" are then true of non-pillar steps only. Namespacing by the writing step's stage, chosen by the runtime from the frozen entry table rather than by the caller, makes both sentences literally true against every step, and it costs one level of `Hash`. The writer set is exactly the five configurable pillars and each has at most one possible writer, because a pillar admits at most one step (`PIPE-4`) |
| P4-29 | **A cursor has no state-setting method.** The only write is the `state:` argument to `#fork` | §5.1's "writable only by the pillar step that created the fork"; §10.15 | "Writable only by the pillar step that created the fork" can be implemented as a checked write or as an unwritable object plus a fork-time argument. The second needs no check, cannot be bypassed by any caller, and makes the negative assertion R11 demands a statement about the *surface* (`public_instance_methods(false)` contains no writer, pinned by the runtime manifest) rather than about a branch. The cost is that a pillar step which does not re-drive cannot set state for its downstream at all; that case has no requirement behind it, and if phase 6 ever needs it, it is a new `P4`-numbered deviation and a change to this row rather than a quiet second write path |
| P4-30 | **One `Cursor` class and one `Builder` class serve both runtimes**; the async runtime differs by one `private_constant` driver and is not a parallel object graph | `PIPE-28`; §5.3's "both runtimes flatten through the same code" | `PIPE-28` forbids the two runtimes re-deriving ordering independently, and §5.3 satisfies it by sharing `Stages`. Sharing only `Stages` would still leave two builders duplicating the surgical-edit semantics `PIPE-28` also names ("same pillar exclusivity, same surgical-edit semantics") and two cursors duplicating the fork gate and the state rules R11 rests on — the exact drift the requirement targets, one level below where §5.3 stops. One builder with `#build` and `#build_async` and one cursor with a per-runtime driver leave nothing to keep in sync. The cost, stated: the builder cannot tell a sync step from an async one, because they differ only in return type — phase 2's admitted `.conforms?` gap arriving at a second seam — so the discriminator is which build method the caller called, and that is documented rather than checked |
| P4-31 | **Sixteen stages**, taking `PIPE-3`'s "a 'pre' slot before and a 'post' slot after" each pillar literally, with `PRE_REDIRECT` doubling as REDIRECT's pre-slot and as `PIPE-2`'s named outermost slot | `PIPE-2`, `PIPE-3`; `NFR-4` | `PIPE-3` is a SHOULD with a concrete clause, and the port ships the feature, so §11.11's rule applies: "the feature is optional, its behaviour is not". Ten interleaved slots plus five pillars plus SEND is what the clause describes. `POST_REDIRECT` and `PRE_RETRY` are adjacent and order-equivalent and are kept as two constants because they name two different intents; collapsing them would honour `PIPE-3` for one pillar boundary and not the other four. Sparse numbering by 100 is the requirement's other clause. Recorded because sixteen public constants is the largest single block of `NFR-4` surface in phase 4 and it arrives from a SHOULD |
| P4-32 | **`Stage` is `private_class_method :new` with no public factory**; `Stages.of(name)` is the only lookup and the stage set is closed at sixteen | `PIPE-2`; `type-system/545949a5`; P1-1's closed-set shape | `PIPE-2` fixes the pillar chain and the charter's boundary 2 says 4c "may not reorder it and may not add a pillar". A `Stage` a caller could construct would make both statements policy rather than structure. It is also `type-system/545949a5`'s shape for a closed domain set — a frozen `Data` over a frozen table with a parse-constructor — applied where the table is the entire population. The departure from phase 1's pattern is that there is no public `.build` at all, because there is no raw input a caller could legitimately supply |
| P4-33 | **The cursor's single-use latch is an unsynchronised instance variable**; `PIPE-15`'s reuse detection is sequential-only | `PIPE-15`; `concurrency-and-async/f414b864`, `/c0fab747` | A cursor is created per step invocation, handed to one step, and never published, so a mutex would cost an allocation per step per call and would put a per-fiber-owned, non-reentrant lock in the hot path for a case that is already a caller defect. Measured on 2026-09-08: eight threads through one unsynchronised latch let more than one caller past on **29 of 2000 runs on 3.2.11** and **0 of 2000 on 3.4.10 and 4.0.6**; a mutex gave 0 of 50 everywhere. So the requirement's "MUST be treated as a defect" is honoured — the runtime raises — while detection under a concurrent double-call is not guaranteed, which `Cursor#call`'s YARD, `#fork`'s YARD and the interface-surface table all state. **No test asserts the race, and the rate is the reason rather than the platform**: 29 in 2000 is 1.5 %, so the single-shot form fails ~98 times in 100 on the floor as well as 100 in 100 above it, and the 2000-run aggregate form is green on one column and red on three. The measurement is not what licenses the missing lock — a demonstrated race is evidence *for* a mutex — it is what prices the argument in this cell |
| P4-34 | **`PIPE-24`'s all-or-nothing preset ships as a general `Builder` mechanism with no standard step set**; the set, and `PIPE-39`'s standard constructor, defer under `DEF-39` | `PIPE-24`, `PIPE-39`, `PIPE-32`; the charter's R14 | `PIPE-24` is about installation semantics and names no step; `PIPE-39` names the steps and is a SHOULD. Separating them lets `PIPE-24` ship as a real, tested MUST today against probe steps, and stops 4c shipping a constructor named for defaults it cannot install — which the charter forbids in as many words. A middle option, `Pipeline.standard(transport, redirect:, retry:, instrumentation:)` with three required keywords, was rejected: it is `#install_preset` under a second name, and it locks three public keyword names under `NFR-4` before the objects they name exist — phase 2's objection to building `deadline:` early (`DEF-28`, P2-5) |
| P4-35 | **4c ships no bridge.** `PIPE-33` and `PIPE-34` are satisfied by composing phase 2's `Transport.async_over` and `AsyncTransport.sync_over` with a pipeline; 4c adds no pipeline-layer wrapper, no wait and no new signature, and files no deferral for the missing `deadline:` | `PIPE-26`, `PIPE-33`, `PIPE-34`; the charter's boundary 15 and R13; `DEF-28`; 4b's P4-17 precedent | A built pipeline responds to `#call(request, options, cancellation)` (verified fact 2), so it is already what both bridges take. Shipping a `Pipeline.async_over`-shaped convenience would be a second name for one function and the first step toward a second executor contract, which boundary 15 forbids. `DEF-28` already covers the missing `deadline:` on `Future#value` with the same `NFR-4` argument, so a second row would be a duplicate. Recorded because a reader looking for phase 4's `PIPE-33` object will find none and must not conclude it was forgotten — the same reason 4b filed P4-17 for a requirement it satisfied by shipping nothing |
| P4-36 | `Dexpace::AsyncPipeline` is a **separate flat constant**, not `Dexpace::Pipeline::Async` | `PIPE-28`; P2-1's precedent for `Dexpace::AsyncTransport` | `Dexpace::Pipeline::Async` would sit inside the namespace that also holds `Stages`, `Cursor` and `Builder` — three things the async runtime *shares* rather than mirrors — and would read as a variant of the sync runtime when `PIPE-28` makes them two users of one staging policy. It is also the shape phase 2 already chose for the seam pair, for the reason `SEAM-2` gives: a seam beside its own implementations is a confusion |
| P4-37 | **One `Dexpace::PipelineError` for nine distinct conditions, carrying no fields** | §5.1 (which names the constant for cursor reuse); `PIPE-5`, `PIPE-8`, `PIPE-15`, `PIPE-18`, `PIPE-19`, `PIPE-21`, `PIPE-23`, `PIPE-24`; 4a's `ContextConflictError`; 4b's P4-20 | Every condition is a composition-time or defect condition a caller fixes by editing code, so no caller branches on the reason and a carried field would be `NFR-4`-locked surface with no reader. The contrast is deliberate: 4a's `ContextConflictError` carries `#call_key` because `CTX-8`'s caller *lost a race* and may retry, which is a runtime condition. `PIPE-5`'s "naming both step types" and `PIPE-21`'s "identifying the missing type" are message requirements and are met in the message, whose exact forms this design fixes so the plan tests them. **One phrase in `PIPE-5` deserves an answer rather than a silence**: its parenthesis says a cross-stage replace "fails with a **distinct** cross-stage error instead" of the collision error. Here that distinction is a distinct *message*, not a distinct class, and it is enough — the sentence exists so a caller can tell the two failures apart when reading one, which a message that names both stages does, and the alternative reading (a second exception class so a caller can `rescue` one and not the other) is the runtime-branching this row exists to refuse. If a phase ever finds a caller that must branch, that is a new `P4`-numbered deviation and a subclass, not a field |
| P4-38 | **`PIPE-31`'s terminal response-mapping operator is `AsyncPipeline.map_response(future, &handler)`**, a class method over the pivot, rather than a `#send_async(request, handler)` overload of the runtime | `PIPE-31`; `PIPE-26`; phase 2's `Async::Completer` | A handler overload would add a fourth parameter shape to `#call`, and `PIPE-26` requires `#call` to be exactly the transport SPI's three positional parameters so a pipeline stands in wherever a transport is expected. A class method over a `Future` is also testable against a bare `Completer` with no pipeline, transport or fake involved, which is what makes the four clauses — close on success, close on handler failure, no unwrap needed, cancellation propagated — four small deterministic tests instead of four integration tests |
| P4-39 | **`#call` and `#fork` are disjoint on one cursor**: a pillar step either drives once through `#call` and never forks, or forks for **every** drive including the first and never calls `#call`. `#fork` on a spent cursor raises `Dexpace::PipelineError` | `PIPE-15`; `PIPE-16`; §5.1; §6.2; §10.15 | `PIPE-15`'s own wording describes the reference's shape — "MUST fork a fresh cursor **for each re-drive** … rather than reusing the same next handle" — under which drive 1 runs on the handle and drives 2..*n* on copies. This port forks for drive 1 too. The requirement is not narrowed: it forbids reusing a *spent* handle, and forking earlier than it requires is strictly inside that. What the change buys is that hop 1 and hop *n* are the same object, so R11's `(stage, key)` state is writable on a pillar's **first** drive as well as its re-drives; under the mixed shape drive 1 runs on a cursor nothing forked and its own stage slot can never be written, which is accidentally harmless for `REDIR-11` (hop 1 is same-origin by definition) and wrong for any future pillar that publishes on first drive. Rejecting `#fork` after `#call` rather than allowing it is the other half: a fork taken from a cursor whose drive already completed re-runs the tail from a position that is done, which is `PIPE-15`'s defect under the fork's name. Recorded because a phase-6 author reading `PIPE-15` alone will write the mixed shape |

---

## Deferrals Filed by Phase 4c

Filed against `docs/deferred-items.md`; the row named there, not this summary, is the authority. (The heading
avoids the literal words the housekeeping probe's `registers` check reserves for the aggregate register.)

### `DEF-39` — `PIPE-39`'s standard-resilience constructors, and `PIPE-32`'s `redirect: :unsupported` argument

- **Deferred by:** phase 4c, 2026-09-08.
- **What defers:** `Dexpace::Pipeline.standard(transport, …)` and `Dexpace::AsyncPipeline.standard(transport, …)`
  — the second of the two convenience constructors `PIPE-39` names — together with the explicit
  `redirect: :unsupported` argument design §5.3 specifies on the async one for `PIPE-32`.
- **What does not:** `PIPE-24`'s all-or-nothing installation mechanism ships in full as
  `Dexpace::Pipeline::Builder#install_preset` and is tested against probe steps; `PIPE-39`'s first constructor
  ships as `Pipeline.direct` / `AsyncPipeline.direct`; `PIPE-35`'s two seeding constructors ship in full.
- **Why:** the three step families the constructor installs — redirect, retry and instrumentation — arrive in
  phases 5 and 6. A constructor named for the defaults it installs while installing nothing is worse than its
  absence, and the phase-4 segmentation design forbids it directly. The alternative of three required keyword
  arguments was considered and rejected in R14: it locks three public keyword names under `NFR-4` before the
  objects they name exist, which is phase 2's own objection to building `deadline:` early (`DEF-28`, P2-5).
- **Pick-up condition:** **phase 6**, the first phase in which all three families exist (redirect and retry are
  phase 6's; the instrumentation step is phase 5's). Phase 6 writes the two constructors **over**
  `Builder#install_preset` and writes no second installation path. `PIPE-32`'s asymmetry documentation is already
  discharged in phase 4; what phase 6 adds is the argument that makes it visible at the call site.
- **Cites:** `PIPE-24`, `PIPE-32`, `PIPE-39`, `NFR-4`.
- **Consequence for the checklist:** `PIPE-39` is ⏳ citing this row with its met half named; `PIPE-24` is ✅;
  `PIPE-32` is ✅ with its substantive clause holding vacuously until this row is picked up.

### Deferral-register sweep

The charter performed the full sweep of all rows for phase 4 and its dispositions stand. 4c adds the following and
re-derives nothing.

- **`DEF-4` — untouched, and carried as 4c's one pre-existing ⏳ row.** `PIPE-36` (SHOULD, pillar-step stage
  locking) is post-MVP per design §12's own `PIPE` row; the condition "post-MVP; no narrower trigger named yet" is
  not met. R10's precedence table is where a future lock would go, and verified fact 6 records why `Method#owner`
  is not a usable detector for it.
- **`DEF-18` — untouched, and cited by 4c's `PIPE-33` row.** Phase 4 neither meets nor re-opens it; the four met
  clauses are enumerated above so the row is not read as a wholly unbuilt requirement.
- **`DEF-28` — untouched, and named as a constraint rather than a deferral.** 4c ships no wait at all, so the
  narrowing costs this phase nothing and no second row is filed (R13, P4-35).
- **`DEF-29` — untouched.** 4c adds three test doubles under `gems/dexpace-core/test/support/`, following phase
  2's, phase 3's, 4a's and 4b's precedent. The condition — a consumer outside `dexpace-core` — stays unmet; this
  strengthens the row without meeting it.
- **`DEF-35` — untouched, and 4c is one of the two substrates it names.** The recovery-stack retry engine installs
  into 4b's chain; the stage-based retry step occupies `Stages::RETRY` and uses `Cursor#fork`. Phase 6 gets both.
- **`DEF-1` — untouched.** `SEAM-28` targets phase 5; 4c supplies nothing toward it.
- **`DEF-22`, `DEF-23` — untouched.** `dexpace-conformance`'s assertion objects and a Steep target over a test
  tree; 4c's fakes do not meet the "production-quality test support" condition. `PIPE-1`'s and `PIPE-2`'s
  conformance clauses are exercised here in `dexpace-core`'s own suite, which is where they will be lifted from
  when `DEF-22` is picked up.
- **`DEF-33` — untouched, and named once.** R12's `ObjectSpace` allocation assertions are CRuby-specific; no v1
  matrix row is non-CRuby, and the tests' comments cite this row rather than asserting portability.
- **`DEF-36`, `DEF-37`, `DEF-38` — untouched.** 4a's and 4b's, targeting phases 5 and 6.

### The findings filed against `docs/open-items.md`

**`OI-17` — the surgical edits are keyed by step *type*, and every lambda step shares one type, so a pipeline
holding two lambdas cannot address either of them surgically.** `PIPE-18`, `PIPE-19`, `PIPE-20` and `PIPE-21` are
four MUSTs whose subject is "an anchor type"; design §5.1 requires that "a `lambda` is a step" and Ruby gives
every lambda the class `Proc` (verified fact 13, all three interpreters). The two requirements are individually
satisfiable and jointly reach less far than either implies: `remove(Proc)` correctly deletes *every* lambda step,
which is `PIPE-20`'s own semantics and is almost certainly not what a caller meant, and `insert_after(Proc, …)`
anchors on whichever lambda happens to be flattened first. Nothing in the specification or the design notices it.

4c's mitigation is documentation — the YARD on each surgical edit states that a step intended as an anchor should
be a named class — and the finding is filed rather than only documented for two reasons: a caller who meets it has
no recourse in the API, and phase 9's conformance pass will test the four edits against class-typed steps and
would never see it. It is the same shape as `OI-1`, `OI-2` and `OI-12` — a requirement that cannot be followed as
written for a case another requirement makes legal — with the difference that here both requirements are
satisfiable in isolation and it is their conjunction that is thin.

**`OI-18` — `Transport.async_over` accepts an *async* transport silently and yields a future of a future, while
the mirror direction is loud.** Filed by this document's review rather than by its scope, on the model of the
charter's `OI-13`. `Transport.conforms?` and `AsyncTransport.conforms?` are one predicate over `#parameters`
(verified facts 1 and 2), and the two seams differ only in return type — phase 2's admitted gap, recorded there.
What phase 4c adds is not the gap but its reach: `Dexpace::Pipeline` and `Dexpace::AsyncPipeline` are two
core-owned classes with identical `#call` shapes one file apart, and R13's whole answer is "compose them with
phase 2's two bridges". `AsyncTransport.sync_over(sync_pipeline)` raises `Dexpace::SeamError` at the first send;
`Transport.async_over(async_pipeline, executor:)` raises nothing ever, because `Completer#fulfil` and
`Settlement.success` validate nothing about the object delivered, so the outer `Future#value` returns the inner
`Future` and the response inside it is never closed. **Every object involved is phase 2's, committed and
reviewed**, and 4c neither introduces nor widens the gap — which is why it is an item rather than a ledger row,
and why the repair it recommends (one `is_a?` in `Bridge::AsyncOver#deliver`, making the bridges symmetric)
belongs to whoever amends phase 2 rather than to this phase.

---

## Open questions for 4c's own plan

Named so their absence later is visible. None blocks the design; each is a decision the plan makes with code in
front of it.

1. **The exact message forms for `Dexpace::PipelineError`'s nine conditions.** This design fixes what each must
   name (`PIPE-5`'s two step types plus the replace path; `PIPE-21`'s missing type; `PIPE-18`/`PIPE-19`'s two
   stages) and not the wording. `SEAM-29` fixes the form for a *required-argument* error and does not reach these;
   the plan writes eight strings and eight assertions against them.
2. **Whether `Stages::ALL` and `Stages::PILLARS` are `Ractor.make_shareable`d or merely frozen.** Both are
   collections the module owns and has already `dup`ed, so deep-freezing is available at no cost; but the port
   makes no shareability claim for anything in the pipeline (constraint 8), so the deep freeze would be a property
   nothing states. The plan decides and does not document a shareability guarantee either way.
3. **The `ProbeStep` family's exact shape**, and in particular whether one `Data` type with a `role` member serves
   all four probes or whether `ForkingProbe` and `StateProbe` are separate types. Three constraints from this
   design, not one: the probe used for `PIPE-6` must be a `Data` type (verified fact 3); its `PIPE-6` pair must
   share whatever mutable member it carries, or the pair stops being `==` the moment either runs; and no probe
   acquires a resource inside a block it yields from.
4. **Whether `Builder` validates its transport with `Transport.conforms?` / `AsyncTransport.conforms?` at
   `#build`/`#build_async` time, or only at first dispatch.** Validating at build is the phase-1 instinct and
   fails fast; the predicate cannot distinguish the two seams (verified facts 1 and 2), so it catches a non-
   callable and nothing else. The plan decides whether a check that weak earns its line.
5. **How many of the fifteen `PIPE-1` probes one test file holds**, and whether the shuffled-insertion case is one
   test with a pinned seed or a small fixed set of permutations. `testing/7ece0212` requires the seed pinned and
   logged either way.
6. **Whether `#install_preset` and `#reload` share one public validation error or two.** They share an
   implementation by this design; whether `PIPE-23`'s "leaves the existing collection completely unchanged" and
   `PIPE-24`'s "rejecting the whole call (installing nothing)" want distinguishable messages is a plan decision,
   and the answer affects two tests.
7. **How `Dexpace::Pipeline::Cursor#call` and `#fork` are declared in RBS**, given P4-30 puts one class under two
   drivers with two return types. The three candidates — a union, a generic `Cursor[R]`, or `untyped` on `#call`
   with `_Step`/`_AsyncStep` carrying the real types — are set out under *The RBS interfaces*, with the reason
   this design does not choose: the answer depends on how strict phase 0's `Steepfile` target over
   `lib/dexpace/pipeline/` is, and `NFR-4` locks whichever is written. It is the one signature in this phase the
   design fixes least and the type checker will ask about first.
