# Phase 4 — Segmentation Design

**Status:** Draft, for review. Written 2026-09-08, before any phase-4 sub-phase design exists.

**What this document is.** The segmentation design the roadmap's **Segmentation rule** requires of a build
phase that spans more than one ID-bearing spec chapter. It decides how many ways phase 4 is cut and in what
order, says for each boundary whether that order is a **dependency** or a **convenience**, assigns every
requirement ID to exactly one sub-phase, and names the boundaries that are spec-forced and therefore not open
to `4a`'s, `4b`'s or `4c`'s own designs to revisit.

**What this document is not.** It is not a phase design, a plan or a checklist, and it does not pre-empt what
the three sub-phase designs are for. Where it names a decision as belonging to a sub-phase it stops there
deliberately; a segmentation design that settles the sub-phases' content is the same failure as a sub-phase
plan that re-imposes a chain the split existed to avoid, arriving from the other direction.

**The headline, stated once at the top because everything else depends on it.** Phase 4's stated scope is
`CTX-1`–`CTX-20`, `RECOV-1`–`RECOV-34` and `PIPE-1`–`PIPE-40`, 94 IDs, and the arithmetic is exactly right.
But **sixteen of the `RECOV` IDs — `RECOV-17`–`RECOV-31` and `RECOV-34` — are the recovery-stack retry
engine**, not recovery-chain machinery: `docs/sdk-design-ruby/` writes a Ruby mapping for none of
`RECOV-17`–`RECOV-30` anywhere and places `RECOV-34`'s in §6.1, a phase-6 chapter; the corpus has no entry
at all for fifteen of them and files the sixteenth (`RECOV-34`) under the `retry-and-resilience` topic;
`RECOV-27`'s cancellable inter-attempt wait is the object `CFG-15` defines, which is phase 5's; and
`RETRY-13` forbids phase 4 from building a backoff calculator phase 6 would then have to share. They are
carried as ⏳ checklist rows in `4b`: **fifteen** against a new deferral, `DEF-35`, targeting **phase 6**,
and the sixteenth — `RECOV-31` — against `DEF-5`, which already deferred it **post-MVP and not to phase 6**.
Phase 4 still owns all 94 rows: it builds 76 outright and carries 18 as ⏳, one of which — `PIPE-33` — is
met in part rather than not at all.

## Governing documents

- `docs/product-spec/07-execution-context-model.md` and `docs/product-spec/08-execution-pipelines.md` —
  normative, read in full for this document, together with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for every ID's canonical text.
  Appendix C is not a convenience here: it is the **only** source for eighteen of phase 4's IDs (below).
- `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1–§5.4 in full;
  `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1 (the correlation bundle, fiber storage)
  and §8.3 (the clock, the wait, the prohibition);
  `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.1 (where the deferred `RECOV` cluster's
  Ruby mapping actually lives) and §6.2 (the cursor marker phase 4's cursor rules must support);
  `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.3 and §3.7;
  `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` §7.1;
  `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items 5, 6, 15, 17 and 18;
  `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` items 11,
  12, 16 and 20; and §12's `CTX`, `RECOV`, `PIPE` and `ASYNC` rows.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-4 row, the segmentation rule, the
  gap-ID paragraph, the five cross-phase obligations and the nine cross-cutting constraints.
- `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md`,
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md`,
  `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md` and the two phase-3 sub-phase designs —
  what phase 4 stands on.
- `CLAUDE.md` and `docs/README.md`.

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run first. `--origin note --brief` returned **27 entries
across 15 note files** at the time of the query — 30 across 16 after the three notes this document filed;
`--section conflicts --brief` returns 24 entries across 17 topic files, **18 of them notes and six
harvested** — the six harvested ones being the styleguide-versus-design conflicts themselves — and each of
the six prints `[overridden by notes/…]` when resolved by key
(`data-modeling/35fde90f`, `module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and
`/8c0687bf`, `tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`). **None is open**, so phase 4
inherits no unresolved conflict and owns no conflict decision of its own.

Four note entries bind this phase directly and are cited rather than restated:

- `concurrency-and-async/f414b864` — core's shared mutable state is one frozen `Data` snapshot swapped under
  a `Thread::Mutex`, read without a lock; `Mutex` is per-fiber-owned and non-reentrant. This is the shape
  `CTX-7`'s store, `PIPE-10`'s immutable runtime and every latch in phase 4 take.
- `error-handling/d2eadac4` — `Dexpace::Error` is a **module**, `Dexpace::ArgumentError` is never defined,
  and the entry names phase 4 explicitly as where `#suppressed` and the `#full_message` override arrive
  (`DEF-24`). **The method name in that sentence is wrong** — verified fact 1 below. It is corrected by the
  new `## Superseded` entry in the same note file rather than in place, because a note's key is digested
  from its text and editing `d2eadac4` would retire the key this document cites; a reader meeting
  `d2eadac4` first must take the `## Superseded` entry as the later word on the mechanism.
- `resource-management/d1f16cad` — the styleguide's per-call I/O timeout rules do not reach the streaming
  layer. They do not reach phase 4 either, and for a second reason: §8.3 forbids `Timeout.timeout` outright
  and the deadline is phase 5's (`DEF-28`).
- `pagination/b2a85752` — the `Enumerator`/`ensure` asymmetry reaches an ordinary `#each` method and no
  in-method guard catches it. `PIPE-25`'s "read-only, ordered view of its steps" and `RECOV-3`'s fold are
  both places a lazy enumerator would be the idiomatic Ruby answer and the wrong one.

**Corpus coverage, and the roll-up hazard.** `--prefix-info` reports **20 of 20 `CTX` IDs and 40 of 40 `PIPE`
IDs substantive, with zero roll-up-only entries in any of the three prefixes**, and 19 of 34 for `RECOV`. The
appendix-B roll-up hazard therefore does not fire for phase 4 at all — not one `--req` hit across the three
prefixes is tagged `[appendix-B roll-up]`. The fifteen uncited `RECOV` IDs are treated under **Gap IDs** below.

**One audit group was run in full here, and one was added to the skill's table before running it.** The
`knowledge-lookup` table carries no group for this phase's subject matter, and the skill's own rule is that a
group not written down cannot be repeated — so a new row is added, **Pipeline composition and execution
context**: `--topic pipeline,execution-context,cancellation-and-timeouts --section rules --brief`, with
`--prefix CTX,RECOV,PIPE --section rules --brief` as the ID-bearing half. Running it produced the two findings
that reshaped this document (the `RECOV` split, and the `CTX`-independence result) and one edge this document
did not expect: `error-handling/1f635244` and `error-handling/5a7d53ab`, the two entries describing
`Dexpace.each_cause`, are **filed under `CTX-9`** — because design §5.2 compares the `equal?`-versus-`==`
trap to "the same trap **CTX-9** sets in §5.4" and the harvest read the comparison as a citation. A `4a`
designer running `--req CTX-9` gets two entries about the cause walk, which is `4b`'s material. Recorded here
so it is a known artefact rather than a surprise; it is a cross-filing, not a wrong rule, so it earns no note.

The table's other nine rows are not run in full here. **Styleguide-vs-design conflicts** is the phase-start
query above and was. The remaining eight — **Public API surface**, **Gem layout, zero-dependency core**,
**RBS / Steep typing**, **RuboCop and formatting**, **Minitest conventions**, **Encoding and binary
strings**, **Fiber scheduler, thread safety**, and **Resource lifecycle and stream ownership** — are audits
of built code and belong to the sub-phases, which name and record the ones they run per the roadmap's first
retrospective rule.

`--phase 1`, `--phase 2` and `--phase 3 --brief` were run to see what the predecessors already cite. Phase 1
cites `RECOV-12` and `RETRY-34` without owning them, pointing here. Phase 2 cites `PIPE-26`, `PIPE-30` and
`PIPE-33`, and records a **binding obligation on phase 4** over the two bridges those citations sit in
(below). Phase 3 cites `RECOV-15`, `RECOV-16` and `RETRY-36`, and phase 3b fixed the shape of one phase-4
function outright.

**Three notes were filed against the corpus before this document was finished**, per the roadmap's second
retrospective rule. They are listed under *Verified Ruby facts* and summarised here: two under
`docs/knowledge/notes/error-handling.md` (`## Superseded`) — the suppressed trail must be rendered through
`#detailed_message`, not `#full_message`, and the cause-chain cycle is not reachable the way design §5.2 says
it is — and one under `docs/knowledge/notes/observability.md` (`## Superseded`), widening the fiber-storage
entry across the supported range and drawing the line between fiber storage and `CTX`. `harvested/` is
untouched.

---

## The cut

**Three ways, on the specification's own §7 / §8.2 / §8.1 line — and every boundary is a CONVENIENCE.**

| Sub-phase | Name | Spec section | IDs | Order |
|---|---|---|---|---|
| **4a** | Execution context | `docs/product-spec/07-execution-context-model.md` | 20 | first, **convenience** |
| **4b** | Recovery-chain primitives | `docs/product-spec/08-execution-pipelines.md` §8.2 | 34 (18 built, 16 ⏳) | second, **convenience** |
| **4c** | Stage-based pipeline | `docs/product-spec/08-execution-pipelines.md` §8.1 | 40 | third, **convenience** |

The letters are the roadmap's, and they are adopted. **The roadmap's stated reason for the order is not**, and
that is this document's central structural finding: the roadmap's segmentation bullet says "`PIPE`'s steps
thread state through `CTX`'s promotion chain and `RECOV-10`/`RECOV-11` re-assert cancellation on the current
context, so 4a leads both." Both halves are wrong, in the same way and for the same reason — two mechanisms
with confusable names.

### Why `4a` does not lead as a dependency

**`CTX` is consumed by nothing in `RECOV` or `PIPE`.** Verified 2026-09-08 with a repository-wide grep:
outside `docs/product-spec/07-execution-context-model.md` and appendix C, the token `CTX-<n>` appears in **no
specification chapter at all** — and ch.07 returns the compliment, mentioning neither "pipeline", "recovery"
nor "retry" once. Inside `docs/sdk-design-ruby/` it appears in §5.4 (its own section), §8.1 (the correlation
bundle, phase 5's populate-not-replace handshake), §11.11 (embedded MUSTs inside SHOULDs) and §12 — **plus
exactly one occurrence outside those**, `CTX-9` in §5.2, and it is a **comparison and not a consumption**:
§5.2 says the cause walk tracks by `equal?` rather than `==` because value equality would truncate a chain,
"the same trap **CTX-9** sets in §5.4". Nothing is read from `CTX` there; a second subsystem is likened to it.
(That single cross-reference is also what mis-files two `error-handling` entries under `CTX-9` in the corpus,
recorded below.) The `PIPE` rules the corpus holds mention no `CTX` artefact; nor do the `RECOV` rules —
verified by running the whole `--prefix PIPE,RECOV --section rules` group and grepping it for `CTX-`, which
returns nothing.

- **"`PIPE`'s steps thread state through `CTX`'s promotion chain" is false.** What a step threads state
  through is the **per-call cursor**, and `PIPE-11` says so in as many words: "Per-request mutable state MUST
  live in the per-call cursor (carried and forked by next), never on the step." `PIPE-13`'s monotonic advance,
  `PIPE-16`'s fork, `PIPE-17`'s immutable options and design §5.1's keyed map of cursor-scoped state are the
  rest of it. That is `PIPE`'s own artefact, allocated per
  send by `PIPE-10` and shared by nothing. `CTX`'s promotion chain is a correlation model registered in a
  bounded store; `PIPE-9` through `PIPE-17` do not mention it and design §5.1 never reaches for it.
- **"`RECOV-10`/`RECOV-11` re-assert cancellation on the current context" is half a sentence about one ID.**
  `RECOV-10`'s canonical text has no cancellation clause and no context clause: it is "on Success it returns
  the contained response; on Failure it rethrows the contained throwable UNCHANGED (no wrapping, no
  substitution)."
  `RECOV-11` does say "re-assert the interrupt/cancellation signal on the current execution context" — and
  design §5.2 renders that, correctly, as "the wrapper re-asserts the cancellation state on **the ambient
  token**", which is `Dexpace::Cancellation`, **phase 2's**. The corpus records both readings side by side:
  `pipeline/8b1c7710` (spec role, "current context") and `pipeline/bc4b5e47` (design role, "ambient token").
  The design's rendering governs the Ruby mapping. So the edge `RECOV-11` creates runs `4b` → **phase 2**,
  and it is already satisfied.

The roadmap sentence is corrected in place in the change that files this document, exactly as phase 3's
`IO-28`/`IO-17` correction was.

### Why `4b` and `4c` do not lead one another

**Spec** §8.3 — chapter 08's own §8.3, not design §8.3, which is the clock and the prohibition; every other
bare `§N.M` in this document is the design's — is explicit that neither layer is built on the other: "A port
MUST NOT collapse the two layers into one: the stage pipeline owns ordering and re-drive-with-fork; the
recovery chain owns the sum-type fold and the uniform-failure guarantee." Chapter 08's introduction says the
same from the other side — "the two layers are parallel and cooperate".
`PIPE-26` makes a pipeline a transport and `RECOV-2` has the orchestrator invoke a transport — both depend on
phase 2's `SEAM-11`/`SEAM-16` seams, not on each other.

That same introduction names exactly two things the layers share: "they share one backoff calculator and one
pacing-header parser so their retry behavior cannot drift." **Both are the retry material this document
defers to phase 6.** After that disposition, `4b` and `4c` share no object at all in phase 4 — which is not a
convenience discovered but a consequence of the deferral, and is stated here so a sub-phase does not
re-introduce one.

What does cross the `4b`/`4c` line is a set of **three shipped non-pillar steps** — the idempotency-key step
(`RECOV-32`), the client-identity step (`RECOV-33`) and the error-mapping step (`RECOV-15`) — which design
§5.1 requires to be "written once against the step protocol both layers share, so the same object installs
into a non-pillar stage of this pipeline and into the recovery chain's request or response list (§5.2)
without a second implementation." That is a **shared contract, not a boundary**, and it does not make either
segment wait: `4c` can build and test every stage, cursor and fork rule against probe steps (which is exactly
what `PIPE-1`'s own conformance clause prescribes — "one probe step per stage records entry/exit"), and `4b`
can build and test every fold against lambdas. It is named as risk **R8** with both owners.

### The order that is recommended, and why it is only a recommendation

`4a → 4b → 4c`. Three reasons, none of them a dependency:

1. **`4a` is the smallest segment (20 IDs) and carries the phase's one irreversible external handshake.** The
   roadmap's cross-phase obligation 1 — "Phase 4 fixes the shape and ships the bundle in core; phase 5
   implements the sentinels and populates rather than replaces it. Phase 4 cannot defer the decision to phase
   5, and phase 5 cannot redefine it" — lands entirely in `CTX-14`/`CTX-15`. Landing it first makes the
   phase-5 contract visible earliest and gives phase 5's own planning the longest lead.
2. **`4b` lands the error primitives three register rows are waiting on.** `Dexpace::Error#suppressed`,
   `Dexpace.attach_suppressed` and `Dexpace.each_cause` are `DEF-24`'s content, `DEF-27`'s first disposal
   route and `DEF-32`'s one-line fix. `DEF-32` is a **behaviour change to code phase 2 shipped**
   (`Hooks.notify` currently drops every failure after the first), so landing it early means the rest of
   phase 4 is written over the corrected helper rather than around it.
3. **`4c` is the largest segment (40 IDs) and the only one that ships a public composition surface**, so it
   benefits from having the three shipped steps to install into rather than only probes.

**Because the order is a convenience, each sub-phase's design must say so in its own Prerequisite section
rather than inheriting a chain by habit** — the treatment the roadmap prescribes for phase 7, applied here
for the same reason. A `4c` plan whose first task waits on a `4b` artefact has re-imposed a chain that does
not exist, and a `4b` plan that assumes `4a`'s store is available has done the same.

### Two other cuts were considered, and rejected

**Rejected cut A — two ways: `4a` context, then `4b` "both pipeline layers".** Rejected on the prohibition
itself. Spec §8.3: "A port MUST NOT collapse the two layers into one." One sub-phase design, one plan and one
checklist covering both layers is not literally a collapse of the *implementation* — but it is a document
whose whole job is to keep two things apart while describing them as one deliverable, and 74 IDs in one
segment is larger than any sub-phase the roadmap's expectations contain (phase 3b's 49 was the previous
maximum and was explicitly flagged as the price of not splitting a lifecycle). There is no lifecycle here to
avoid splitting; the specification splits it for us.

**Rejected cut B — four ways: splitting `4c` into a sync runtime and an async mirror plus bridges
(`PIPE-28`–`PIPE-35`).** This is the only four-way candidate with a real line to cut on, and `PIPE-28`
forbids it: "The async runtime MUST reuse the identical stage identities and staging policy as the sync
runtime; the two MUST NOT each re-derive ordering independently." Design §5.3 satisfies that **structurally**
— "there is one `Dexpace::Pipeline::Stages` module holding the frozen ordering and the pillar set, and both
runtimes flatten through the same code" — which is precisely the property a segment boundary would put at
risk. A split there would also be strictly linear (the async runtime needs `Stages`), so it buys no
independence, and a phase returns to `mvp` as **one phase-level pull request** (roadmap execution step 5), so
a fourth sub-phase is a fourth document set and not a fourth merge. Rejected, and `PIPE-28` is recorded below
as a spec-forced boundary so `4c`'s own design cannot re-open it.

A third possibility — a segment for the three shipped steps and the bounded error copy — is rejected without
a paragraph: four IDs, and it would convert two independent segments into two segments both blocked on a
third.

---

## Spec-forced boundaries — not open to `4a`, `4b` or `4c`

Each is a MUST (or a design deviation already argued, or a roadmap obligation already fixed) that settles
something a sub-phase design might otherwise believe it is free to decide.

1. **Spec §8.3's two-layer prohibition, quoted in full because the roadmap requires this document to quote it.**
   > "A port MUST NOT collapse the two layers into one: the stage pipeline owns ordering and
   > re-drive-with-fork; the recovery chain owns the sum-type fold and the uniform-failure guarantee."

   `4b` and `4c` stay separate segments *and* separate object graphs. Neither may express itself in terms of
   the other, and the fact that `RECOV-32`/`RECOV-33` are header-stamping steps that live in the recovery
   chain rather than in a pillar does not make them a bridge between the layers — it makes them steps that
   two layers can both hold.
2. **`PIPE-2`'s pillar precedence chain, and `PIPE-8`'s reserved terminal.** `PRE_REDIRECT → REDIRECT →
   RETRY → AUTH → LOGGING → SERDE → SEND`, outer to inner, with `SEND` reserved for the transport, holding no
   user step and skipped by flattening. `4c` may not reorder it and may not add a pillar. The order is
   load-bearing two phases out: §6.2's cross-origin marker works *because* AUTH is downstream of the fork
   REDIRECT made.
3. **`PIPE-28`.** One `Stages` module, both runtimes flattening through the same code. This is why `4c` is
   not split, and it is not open to `4c` to re-derive ordering in the async runtime for any reason.
4. **`PIPE-15`/`PIPE-16`'s fork.** Reusing the next handle "MUST be treated as a defect". Design §5.1 fixes
   the mechanism: `#call` is single-use and raises `Dexpace::PipelineError` on a second invocation; `#fork` is
   available only to a step occupying a pillar stage, **checked at composition time from the step's stage
   assignment, not trusted at call time**. `4c` decides where the stage assignment lives (R10); it does not
   decide whether the check is at composition time.
5. **`PIPE-37`'s placement rule.** "A step whose correctness depends on observing only the SINGLE terminal
   response (e.g. mapping a non-successful status to a typed error) MUST be placed at the outermost
   pre-redirect slot so it runs outside both the redirect and retry loops, and on a non-error status it MUST
   return the response untouched (**body not read, consumed, or closed**)." That is `RECOV-15`'s step, `4b`'s
   object, in `4c`'s outermost slot. Neither may put it anywhere else — and the parenthesised clause is not
   decoration: it is what stops the outermost step from draining a 2xx body on the way past, which a test of
   the placement alone would not catch.
6. **`RECOV-1`'s closed two-variant outcome and `RECOV-6`'s fold order.** Success-carrying-a-response and
   Failure-carrying-a-throwable, mutually exclusive and jointly exhaustive; all response steps first on the
   success path, then all recovery steps, in declared order within each group; response steps on `Success`
   only (`RECOV-4`); recovery steps on **every** outcome, always (`RECOV-5`). `4b` may not add a third
   variant here — design §5.2 reserves that for §7's SSE typed adapter in a different namespace.
7. **`RECOV-8`'s totality.** "the response recovery chain's apply operation MUST NOT throw under any input."
   This is stronger than it looks and constrains `4b`'s own internal error handling, not only its treatment
   of a step's error.
8. **`RECOV-12`/`RECOV-13`'s ownership asymmetry, and the single helper.** A step that *throws* while holding
   a `Success` has its response closed by the pipeline before the throwable is wrapped, with the close error
   attached as suppressed; a step that *deliberately returns* a different outcome owns releasing the response
   it dropped. Design §5.2: "Both are implemented as one shared helper so the asymmetry lives in one place."
   `4b` may not implement them separately.
9. **`RECOV-14`'s uniform defensive copy.** Both chains copy and freeze both step lists at construction. This
   is one of the four reference sync/async drifts §11.12 resolves toward the stricter behaviour "each through
   a single shared implementation so the paths cannot drift again"; the decision is made and `4b` records it.
10. **`RECOV-16`'s one bound, and where the constant lives.** Phase 3b's addendum B2 already moved it:
    `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` is a phase-3b constant and
    `Dexpace::Body.buffer_bounded(body, cap:)` is the operation. §5.1's guarantee — one constant, one shared
    bound across every error-body-buffering path — holds exactly. **`4b` reads that constant and declares no
    second**, and `Recovery.buffer_error_body(response)` stays the one call site.
11. **`CTX-9`'s identity eviction.** The slot is cleared only when its current occupant `equal?` the closing
    context, never by value equality. Design §5.4 calls this "the one place a Ruby port is actively likely to
    go wrong". Verified on 3.2.11, 3.4.10 and 4.0.6 that a value-equality delete over two structurally
    identical `Data` contexts evicts the wrong one; `4a` asserts the distinction in a test.
12. **`CTX-17`'s registration-at-promotion.** Constructing the initial dispatch context registers nothing;
    the first store entry is installed by the first promotion. `4a` may not make construction register.
13. **`CTX-19`'s prohibition on weak references.** "Reimplementations MUST NOT hold contexts by weak/soft
    references … and MUST treat the bounded cap, not garbage collection, as the leak backstop." Design §5.4
    makes this a lint rule. `4a` decides the lint's shape (R1); it does not decide whether the prohibition
    holds.
14. **`CTX-14`/`CTX-15`'s bundle shape is fixed in phase 4 and only in phase 4.** Roadmap cross-phase
    obligation 1, and design §8.1's argument for it ("deferring the *shape* means every context type, the
    promotion chain of §5.4, and `CTX-4`'s call key all change when the adapter lands"). Nine members, a
    frozen `NONE` singleton, `OBS-26`'s reserved sentinels as its values, `CTX-20`'s no-op tracer factory.
    `4a` fixes it; phase 5 populates and may not redefine.
15. **`PIPE-33`/`PIPE-34` reuse phase 2's two bridges rather than building a second pair.** Recorded by phase
    2's own design as an obligation on this phase: "phase 4 wraps a `Dexpace::Pipeline` with
    `Transport.async_over` and does not reimplement the executor contract, the orphan close or the
    normalisation." `4c` may not ship a second executor duck type, a second orphan-close path or a second
    synchronous-raise normalisation.
16. **§10.5's split is settled and is not re-opened.** `PIPE-33`'s interrupt clause is unsatisfied; the
    non-interrupting half is met exactly; `ASYNC-4` holds vacuously; `ASYNC-3` is phase 8's. `DEF-18` carries
    all of it. See *The three unsatisfied MUSTs* below.

---

## Scope: every ID, assigned to exactly one sub-phase

**94 requirement IDs.** Level split, derived mechanically from appendix C on 2026-09-08: **82 MUST, 10 SHOULD,
2 MAY.**

### Reconciliation against the roadmap's arithmetic

**The roadmap's phase-4 arithmetic is correct and nothing is missing or double-counted.** Verified
mechanically against appendix C: `CTX` is 20 contiguous rows with no duplicate, `RECOV` is 34, `PIPE` is 40,
and the file holds exactly 645 requirement rows. 20 + 34 + 40 = 94, which is the roadmap's phase-4 cell.
`4a`'s 20 plus `4b`'s 34 plus `4c`'s 40 is 94, each ID in exactly one sub-phase.

Per-prefix levels: `CTX` 16 MUST / 3 SHOULD (`CTX-12`, `CTX-16`, `CTX-20`) / 1 MAY (`CTX-13`); `RECOV` 30
MUST / 3 SHOULD (`RECOV-9`, `RECOV-25`, `RECOV-30`) / 1 MAY (`RECOV-31`); `PIPE` 36 MUST / 4 SHOULD
(`PIPE-3`, `PIPE-35`, `PIPE-36`, `PIPE-39`) / 0 MAY.

### `4a` — Execution context (20 IDs, all `CTX`)

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `CTX-1`–`CTX-20` | 20 |

Nothing in `CTX` is deferred, retired or vacuous — design §12's `CTX` row reads "*Deferred:* none" and takes
`CTX-13`'s arbitrary-victim latitude as-is. `4a` additionally fixes, without owning a new ID: the shape of
`Dexpace::Instrumentation::Bundle` (§8.1, roadmap obligation 1), the bounded-map implementation `CTX-11`
shares with `XCUT-14` and `AUTH-19`, and the process-wide monotonic counter `CTX-4`'s key appends.

`CTX-16` and `CTX-20` are the two SHOULDs §11.11 flags as carrying embedded MUSTs ("the feature is optional,
its behaviour is not"); `4a` ships both features and therefore implements every embedded MUST in them.

### `4b` — Recovery-chain primitives (34 IDs, all `RECOV`)

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `RECOV-1`–`RECOV-16`, `RECOV-32`, `RECOV-33` | 18 |
| ⏳ deferred, `DEF-35`, target phase 6 | `RECOV-17`–`RECOV-30`, `RECOV-34` | 15 |
| ⏳ deferred, `DEF-5` (pre-existing), post-MVP | `RECOV-31` | 1 |

`4b` additionally ships, without owning a new ID: `Dexpace::Error#suppressed`, `Dexpace.attach_suppressed`
and the trail's rendering override (`DEF-24`); `Dexpace.each_cause` (`XCUT-9`, phase 9's ID); and
`Dexpace::Recovery.buffer_error_body(response)`, whose contract phase 3b already fixed.

**Why the sixteen move.** Design §12's `RECOV` row maps the prefix to "§5.1, §5.2" and notes that
"`RECOV-34`'s construction-time validation and defensive copies" are in **§6.1** — a phase-6 chapter. That is
not an isolated pointer: `docs/sdk-design-ruby/` cites `RECOV-17` through `RECOV-30` **nowhere at all**
(verified by repository-wide grep), cites `RECOV-31` only in §11.20 and §12, and cites `RECOV-34` only in
§6.1, §10.18 and §12 — every one of those a phase-6 or appendix location, and none of them §5.1 or §5.2.
So the §12 row's "§5.1, §5.2" is a **prefix-level** pointer that no §5.x sentence honours for these IDs:
read it as the chapter the *prefix* belongs to, not as a mapping any of the sixteen actually has. Every one
of the sixteen has a `RETRY` twin whose Ruby mapping §6.1 does write:

| `RECOV` | What it requires | Its `RETRY` twin |
|---|---|---|
| `RECOV-17` | retry eligibility off a capability, configured status set authoritative | `RETRY-37`, `RETRY-1`, `XCUT-6`/`XCUT-7` |
| `RECOV-18` | the re-sendability gate | `RETRY-5`, `RETRY-6`, `RETRY-7`, `RETRY-8` |
| `RECOV-19` | re-classify each re-sent attempt's response | `RETRY-36` |
| `RECOV-20` | max-attempts cap **and** total-timeout budget | `RETRY-27`, `RETRY-14` |
| `RECOV-21` | the exponential/jitter/clamp formula | `RETRY-9`, `RETRY-10`, `RETRY-11` |
| `RECOV-22` | pacing hint replaces, is still clamped, gains no jitter | `RETRY-20`, `RETRY-21` |
| `RECOV-23` | the parser is total; malformed → no hint, past → zero | `RETRY-16`, `RETRY-17` |
| `RECOV-24` | the four recognised forms and their precedence | `RETRY-15`, `RETRY-19`, `RETRY-21` |
| `RECOV-25` | X-RateLimit-Reset positive jitter to [100%, 120%] | `RETRY-15`'s own last clause |
| `RECOV-26` | overflow-safe duration arithmetic, 365-day clamp | `RETRY-11`, `RETRY-18` |
| `RECOV-27` | cancellable, non-pinning inter-attempt wait | `RETRY-23`, `RETRY-26`, `XCUT-3` |
| `RECOV-28` | the engine is stateless across calls | `RETRY-42` |
| `RECOV-29` | a pacing-parse failure never masks the upstream failure | `RETRY-22` |
| `RECOV-30` | one calculator and one parser across both stacks | `RETRY-13`, `RETRY-14`, `RETRY-28` |
| `RECOV-31` | the per-attempt ordinal header (MAY) | `RETRY-38` — §11.20: "the same feature under two IDs" |
| `RECOV-34` | construction-time validation and defensive copies | §6.1; §10.18's substituted ~292-year bound |

Two of those rows make the deferral **forced rather than preferred**, and they are the argument:

- **`RECOV-27`'s wait is `CFG-15`'s object, and phase 4 may not shape it.** The requirement is an
  inter-attempt wait that is cancellable and does not pin an execution carrier, and its own portability note
  rules out the easy answer in as many words: "the reference implementation uses a scheduler + interruptible
  wait, **not a plain sleep**; a port uses its runtime's cancellable timer/sleep with the same abort
  semantics." Its twin `RETRY-26` puts the same thing at the level of a verdict — "a naive uninterruptible
  sleep that cannot be cancelled is non-conforming" — and §10.17 already catalogues the port's answer as a
  deviation: "the interruptible sleep is a cancellable queue wait, not `Kernel#sleep`". Design §8.3 names
  that answer exactly: `Clock#sleep(duration, cancellation:)`, a bounded wait on a per-call `Thread::Queue`
  the token pushes to on cancel, **behind `CFG-15`'s injectable time seam**. The forcing fact is *not* that
  phase 4 could only reach for `Kernel#sleep` — `Thread::Queue#pop(timeout:)` exists on the 3.2 floor
  (verified) and phase 2's `Cancellation#on_cancel` supplies the push, so a hand-rolled wait is technically
  within reach. It is that building one here would **fix `CFG-15`'s shape a phase ahead of the requirement
  that defines it**, which is precisely the objection phase 2 raised in declining to build `deadline:`
  (`DEF-28`, deviation P2-5) and phase 0 raised against defining `Dexpace.register` early. `CFG-15`–`CFG-21`
  are phase 5's; so is the seam this wait is the first caller of.
- **`RETRY-13` forbids phase 4 from building the calculator.** "Both retry stacks MUST compute their backoff
  via the one shared calculator using the one shared set of constants … the stacks MUST NOT carry independent
  backoff formulas or duplicated constants." `RECOV-30` says the same at SHOULD level from this side. The
  roadmap's own phase-6 segmentation bullet already states the consequence: "the shared calculator lands
  before either stack and `RETRY` cannot be split along its two stacks." Building the recovery stack's half
  in phase 4 and the stage stack's half in phase 6 is exactly the drift both requirements exist to prevent —
  and `RETRY-12`'s default tuning constants come from phase 5's configuration chain in any case.

**This changes no roadmap cell and creates no new mechanism.** Phase 4's row still reads `RECOV-1`–`RECOV-34`;
phase 4 still writes 94 checklist rows; sixteen of the thirty-four `RECOV` rows carry the ⏳ the roadmap's own
legend defines — fifteen naming `DEF-35` with target phase 6, and `RECOV-31` naming `DEF-5`. It is the same
disposition phase 3 gave `BODY-12`'s second clause and `BODY-36`. The roadmap's cross-phase obligation 3 —
"`RETRY` needs `RECOV` and `PIPE`, and then Configuration.
Its **two stacks** depend on two different **substrates** from phase 4" — reads as confirmation rather than
contradiction once the words are taken at face value: the substrates are phase 4's, the stacks are phase 6's,
and fifteen of these sixteen IDs describe a stack.

**What it costs phase 6, stated here because that is the phase that pays it — and it is fifteen, not sixteen.**
The roadmap already calls phase 6 the largest at **111** prefix IDs (`RETRY` 45, `REDIR` 28, `AUTH` 38).
`DEF-35` adds the *work* of **fifteen** more **on top of that 111**, so **phase 6's segmentation design budgets
for 111 + 15 and not for 111** — and it must not have to discover that by counting, which is why the same
sentence appears in three places: the `DEF-35` row, the roadmap's phase-6 segmentation bullet (corrected in
place) and the roadmap's dated status note. **The sixteenth ID of the cluster, `RECOV-31`, is not phase 6's
work**: `DEF-5` defers it post-MVP, "picked up together with `RETRY-38` if the per-attempt ordinal header
feature is ever built", and `DEF-6` defers `RETRY-38` itself with "no named trigger" — so counting it into
phase 6's budget would book work no register schedules there. Phase 6 may still carry a ⏳ row for it beside
`RETRY-38`'s; a row is not a budget. No requirement ID moves. The fifteen keep their phase-4 checklist rows as
⏳ citing `DEF-35`, and phase 6 carries its own rows or cross-references to the `RETRY` twins — the
two-rows-one-obligation treatment phase 2 gave `SEAM-29` and phase 3b gave `HTTP-46`. `DEF-35` reproduces the
twin table above so phase 6 re-derives nothing, and the phase-6 **row** in the roadmap is left alone because
its three prefix ranges still sum to 111.

### `4c` — Stage-based pipeline (40 IDs, all `PIPE`)

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `PIPE-1`–`PIPE-32`, `PIPE-34`, `PIPE-35`, `PIPE-37`–`PIPE-40` | 38 |
| ⏳ partially unsatisfied, `DEF-18`, §10.5 | `PIPE-33` (the interrupt clause only) | 1 |
| ⏳ deferred, `DEF-4` (pre-existing), post-MVP | `PIPE-36` (SHOULD, pillar-step stage locking) | 1 |

`PIPE-33`'s row is counted under ⏳ because one of its five normative clauses is not met; the other four are.
See *The three unsatisfied MUSTs*.

---

## Exclusions — IDs a reader would expect here, and the phase that owns each

| Excluded | Owning phase |
|---|---|
| `RETRY-1`–`RETRY-45` — **both** retry stacks, including the recovery-chain half `RECOV-17`–`RECOV-30`/`RECOV-34` describe | 6. Phase 4 ships the recovery chain the recovery-aware stack installs into, and the stage list the stage-based step occupies |
| `REDIR-11`, `REDIR-24`, `AUTH-29` — the cross-origin marker and the auth stamping step | 6. Phase 4 ships §5.1's **cursor-scoped state rules** (inheritance across forks; write restricted to the fork's creator) on which §10.15's forgery-impossibility claim rests, and nothing else of the marker |
| `OBS-25`, `OBS-26`, `OBS-27` — the no-op tracer, the W3C sentinels, trace-id generation | 5. Phase 4 fixes the `Bundle`'s nine members and ships `NONE`; phase 5 populates and may not redefine (roadmap obligation 1) |
| `OBS-10`, `OBS-23`, `OBS-24`, `ASYNC-8`–`ASYNC-12` — the **diagnostic context** carried in `Fiber[:key]` | 5 and 8. This is not `CTX`, and the two are easy to conflate: design §8.1's fiber-storage paragraph is about `OBS`/`ASYNC`, and `CTX`'s store is a `Hash` behind a `Thread::Mutex` keyed by call key (§5.4). Recorded as a corpus note |
| `SEAM-28` — a stable operation identifier attached to the context chain | 5. `DEF-1` names phase 5 **rather than phase 4** and says why: phase 4 supplies the chain half, phase 5 is "the first phase that has both" |
| `SEAM-18`'s two bridges, `SEAM-30`'s orphan close, `SEAM-11`/`SEAM-16`'s seams | 2, built. `PIPE-26`, `PIPE-30`, `PIPE-33` and `PIPE-34` consume them |
| `XCUT-9` (cycle-safe cause walk), `XCUT-14` (bounded-map rule), `XCUT-2` (cancellation-vs-timeout) | 9 dispositions. Phase 4 builds `Dexpace.each_cause` and `CTX-11`'s bounded map, which is what phase 9 audits |
| `RETRY-34`'s self-suppression guard | 6. Phase 4 ships the `attach_suppressed` helper that carries it (`DEF-24` cites it), and `4b`'s checklist carries a cross-reference row — the treatment phase 2 gave `SEAM-29` |
| `PAGE-13`, `PAGE-15`, `SSE-29`, `SSE-36` — the other consumers of the suppressed trail | 7 |
| `SSE-33`–`SSE-36` — the typed adapter's reuse of `Outcome` with a third variant | 7 |
| `BODY-30`/`HTTP-52`'s bounded replayable copy, `BODY-31`'s 4xx/5xx predicate, `Status#error?` | 3b and 1, built. Phase 4 ships only `Recovery.buffer_error_body(response)`, the step that calls them |
| `CFG-15`–`CFG-21` — the clock, the monotonic counter, the interruptible sleep, `future.value(deadline:)` | 5 (`DEF-28`) |
| `ASYNC-3`, `ASYNC-4` | 8 marks them (`DEF-18`, §10.5) |
| `TRANSPORT-1`, `TRANSPORT-2` — disabling a native client's own redirect and retry | 8. They presuppose `PIPE` as the single authority, which is what phase 4 makes true |

---

## Gap IDs: what `--gaps CTX,RECOV,PIPE` actually reports, and how the roadmap's claim held

The roadmap says: "Phase 4: `RECOV-17`–`RECOV-31`, read out of
`docs/product-spec/08-execution-pipelines.md` §8.2 — 15 IDs, the largest cluster in the corpus and the one
place a phase must plan for reading the specification directly rather than querying it."

`ruby scripts/knowledge.rb --gaps CTX,RECOV,PIPE`, run 2026-09-08, reports the following — the subsystem
lines and the closing summary elided, the rest verbatim, so re-running it and diffing this block is not
mistaken for drift:

```
CTX — Execution context model (context promotion chain + ContextStore backstop)
  20 canonical IDs: 20 substantive, 0 roll-up only, 0 uncited

RECOV — Recovery-chain pipeline primitives
  34 canonical IDs: 19 substantive, 0 roll-up only, 15 uncited
  uncited (no entry in either tree names them):
    RECOV-17 RECOV-18 RECOV-19 RECOV-20 RECOV-21 RECOV-22 RECOV-23 RECOV-24 RECOV-25 RECOV-26 RECOV-27 RECOV-28 RECOV-29 RECOV-30 RECOV-31
  read these out of docs/product-spec/08-execution-pipelines.md

PIPE — Stage-based execution pipeline runtime (http.pipeline)
  40 canonical IDs: 40 substantive, 0 roll-up only, 0 uncited
```

**The ID list is exactly right. The count is right. The instruction built on it is unfollowable, and the
characterisation is wrong in two directions.**

**The pointer does not resolve.** `docs/product-spec/08-execution-pipelines.md` §8.2 runs `RECOV-1` through
`RECOV-16` and stops. Verified by repository-wide grep on 2026-09-08: **`RECOV-17` through `RECOV-34` appear
nowhere in `docs/product-spec/` outside appendix C** — eighteen IDs, not fifteen. Both `--gaps`'s trailing
line and the roadmap's own gap paragraph send a reader to a chapter that does not carry them. This is the
third instance of the shape `OI-1` (five `SEAM` IDs) and `OI-2` (`IO-6`) already record, it is now clearly a
pattern rather than three accidents, and it is filed as **`OI-12`**.

**Three of the eighteen are not gaps only because the *design* rescued them.** `RECOV-32`, `RECOV-33` and
`RECOV-34` have substantive corpus entries — `pipeline/785eab36`, `pipeline/2e998896`, `pipeline/7f286969`,
`retry-and-resilience/58d2faad`, `retry-and-resilience/c9228a67` — every one of them role `design`, drawn
from `docs/sdk-design-ruby/05-pipeline-architecture.md` and `/06-retry-redirect-and-authentication.md`. The
specification says nothing about them either. So "the corpus cannot answer" and "the **specification**
cannot answer" are independent facts here, and only the first is what `--gaps` measures — which is exactly
why its fifteen understate the eighteen a reader cannot find in a chapter.

**The budget the roadmap asks a phase to plan for is not the budget phase 4 actually pays.** All fifteen
uncited IDs (`RECOV-17`–`RECOV-31`) are the recovery-stack retry engine, and fourteen of them travel to phase 6
under `DEF-35` while `RECOV-31` stays post-MVP under `DEF-5` — so the *reading for implementation* transfers
with the work either way, and phase 6 inherits it alongside the `RETRY` chapter that states the same rules in
prose it can actually read. (`--gaps`'s fifteen and `DEF-35`'s fifteen are **different sets**: the first is
`RECOV-17`–`RECOV-31`, the second drops `RECOV-31` and adds `RECOV-34`. The coincidence of size is worth
naming, because a reader who assumes they are the same set will reconcile two correct numbers into one wrong
conclusion.) What phase 4 owes is a **disposition** pass over all eighteen, out of appendix C, deciding for
each whether it is phase 4's or phase 6's. That pass is what produced the
twin table above, it was done for this document, and **`4b`'s budget is therefore one careful reading of
eighteen appendix-C rows, not a chapter**. Say so in `4b`'s design and do not re-derive it.

**`CTX` and `PIPE` need no specification reading beyond their chapters**, both of which were read in full for
this document, and neither carries a single roll-up-only entry.

---

## Prerequisites, and the decisions phase 4 inherits

**From phase 0** — seventeen blocking gates, unchanged and unlowered. Three bite here.
`gates:require_allowlist` (core's `lib/**/*.rb` may `require` only `monitor`, `uri`, `stringio`, `strscan`,
`time`, `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`) — **phase 4 is
expected to add nothing**: the context store is a `Hash` behind a `Thread::Mutex`, both core; `Data` is core;
`securerandom` is already allowlisted if `CTX-4`'s key ever wanted it, though the design's counter does not.
`gates:surface_snapshot` and `gates:sig_diff` regenerate for every new public constant, and phase 4 ships more
new public constants than any phase since 1. And the `Dexpace/NoThreadInterrupt` cop, which is what makes
`PIPE-33`'s residual gap a stated deviation rather than a temptation.

**From phase 1** — `Dexpace::Model` (with the `#with` override that routes through the validating `.build`,
because `Data#with` skips an `initialize` override on 3.2.11), `Dexpace::Builder`, `Dexpace::Error` as a
**module**, `Dexpace::InvalidArgumentError < ::ArgumentError`, `Status` (whose `#error?` is `RECOV-15`'s
400..599 test and `Recovery.buffer_error_body`'s guard), `Method`, `Headers`, and `Request`/`Response`. Four
rules bind every file phase 4 writes:

- **Public wire-model constants are flat** (deviation P1-1) — *but a subsystem the design already names with
  a namespace keeps it*. Design §5.1 and §5.3 name `Dexpace::Pipeline::Stages`; §5.2 names
  `Dexpace::Outcome::Success` and `::Failure`; §8.1 names `Dexpace::Instrumentation::Bundle`. Those keep
  their namespaces. `Dexpace::PipelineError` is named flat by §5.1. Everything else is a naming decision each
  sub-phase must record as a Deviation Ledger row (R3, R6, R9, R10).
- **No `.build` is a bare `new` wrapper.** Validation lives in each `Data` type's `initialize`.
- **`Dexpace::ArgumentError` is never defined**, in this or any later phase.
- **`downcase` takes no argument**, everywhere in core.

**From phase 2** — and this is the largest inheritance of the four:

- `Dexpace::Cancellation`, `Cancellation::Source` (with `#on_cancel` returning a `Subscription`, and
  `#off_cancel`) — **this is `RECOV-11`'s "current context"**, and the whole of that requirement's Ruby
  mapping.
- `Dexpace::Async::Future` and `Async::Completer`, with `#on_cancel`, the check-after-resume rule and
  `SEAM-30`'s orphan close. `PIPE-29`/`PIPE-30`'s normalisation is phase 2's `Completer#fail` routing,
  already built and already tested.
- **`Dexpace::Transport.async_over(transport, executor:)` and `AsyncTransport.sync_over(transport)`** —
  phase 2's `SEAM-18` bridges, with phase 2's design recording that **phase 4 reuses these rather than
  building a second pair**. Phase 2 names `PIPE-33` (with `PIPE-26`) and writes `PIPE-34` nowhere; its
  obligation is worded over both bridges, and `PIPE-34` is the one `AsyncTransport.sync_over` answers. This
  is the single largest reduction in `4c`'s cost and it is not optional.
- `Dexpace::Transport`/`AsyncTransport` as duck types over `#call(request, options, cancellation)` — which is
  what `PIPE-26` satisfies "for free", and what `PIPE-13`'s terminal dispatch calls.
- `Dexpace::Closeable` with its latch, `Dexpace.close_quietly`, `Dexpace::ClosedError` — `PIPE-27`'s "closing
  the pipeline MUST be a no-op with respect to the underlying transport" is `Closeable` with `owned: false`,
  the shape phase 2 already gave both bridges.
- `Dexpace::Hooks` (`private_constant`) — whose `notify` currently drops every handler failure after the
  first (`DEF-32`), and whose fix phase 4 supplies.
- `Dexpace::Registry` and three seam registries — **phase 4 adds no fourth**.
- One custom cop, the sixth: `Dexpace/QualifiedCoreConstant` (P2-8), extended by phase 3a with the constant
  `IO` and a repository-wide third namespace (P3-7). The other five, `Dexpace/NoThreadInterrupt` among them,
  are **phase 0's** and are listed there.

**From phase 3** — `Dexpace::Body` as the contract, carrying `#source` and a default no-op `#close` (P3-23,
resolving `OI-10`); `Dexpace::Body.buffer_bounded(body, cap:)`; `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES`
(1 MiB); `Dexpace::BufferBody`, `ResponseBody`, and the two logging wrappers; `Response#close`,
`#body_string`, `#body_bytes`; the whole `Dexpace::IO::` tree; `Dexpace::StreamError < ::IOError` and
`EndOfStreamError < ::EOFError`; and `Closeable#closed?` read under the close mutex (P3-6).

**Phase 3b fixed one phase-4 function outright, and `4b` implements it rather than designing it.** Its API
table reads: `Dexpace::Recovery.buffer_error_body(response)` "returns the response unchanged when
`status.error?` is false **or the body is nil**, otherwise calls `Body.buffer_bounded` with the constant and
returns a response carrying the buffered body." `Body.buffer_bounded` is deliberately status-blind so the
body layer cannot get `BODY-31` wrong, and the status test is phase 4's. `4b` may refine the *name*'s
namespace (R9); it may not re-decide the contract.

**Two open items from phase 3 land in phase 4's window and neither is phase 4's to fix.** `OI-8`
(`TeeSink#clear_tap` is `NFR-4`-locked public API with no core caller) and `OI-9`
(`BufferedSource.wrapping` returns one byte per read) both name a window that closes when phase 3's plans
execute and before the first release tag. Phase 4 neither widens nor closes them; it is recorded here so a
`4b` or `4c` designer meeting either does not open a third item for the same finding.

---

## Cross-cutting constraints that bite phase 4 specifically

1. **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden in every gem**, argued in §8.3 and
   enforced by `Dexpace/NoThreadInterrupt` (a phase-0 cop). In phase 4 this is not a background rule: it is
   the direct and only cause of `PIPE-33`'s unsatisfied clause. It is **not** what moves `RECOV-27` — that
   is `CFG-15` owning the wait's seam, argued under *Why the sixteen move*; the prohibition only rules out
   the one shortcut a phase in a hurry would reach for.
2. **Deadlines are explicit values, not ambient interrupts.** `PIPE-34`'s blocking wait is
   `future.value(cancellation:)` in phase 4; the `deadline:` keyword and the clock behind it are phase 5's
   (`DEF-28`, deliberately). `4c` ships the narrower signature and does not fabricate a deadline (R13).
3. **`Fiber[:key]` is the diagnostic-context carrier, and `CTX` is not it.** Design §8.1 verifies that
   `Fiber[:key]` is inherited by a child fiber, by a new `Thread` and by an `Enumerator`'s internal fiber
   while `Thread.current[:key]` is visible in none of them; re-verified here across the whole supported range
   (below), with one property the entry omits — **inheritance is copy-on-write**, so a write inside a child
   fiber does not escape to the parent. That carrier belongs to `OBS-10`/`OBS-23`/`OBS-24` and
   `ASYNC-8`–`ASYNC-12`, phases 5 and 8. `CTX`'s store is a keyed, bounded, process-wide `Hash`
   (`CTX-7`, `CTX-11`), and putting it in fiber storage would defeat `CTX-11`'s cap and `CTX-19`'s
   reachability requirement at once. The two are near neighbours with opposite designs; a corpus note now
   records the line.
4. **`Thread::Mutex` is per-fiber-owned and non-reentrant** (`concurrency-and-async/f414b864`, re-verified).
   `CTX-8`'s reject-on-duplicate insert, `CTX-11`'s drain loop and `CTX-4`'s counter all hold the mutex
   across a flag flip or a hash write and never across a callback, a drain or a close. `PIPE-10`'s runtime is
   immutable after construction and needs no lock at all — which is the point of building it that way.
5. **An `Enumerator` abandoned mid-`#next` never runs its `ensure`, and the rule reaches an ordinary `#each`
   method** (`pagination/b2a85752`). `PIPE-25`'s "read-only, ordered view of its steps" is a frozen `Array`,
   not a lazy enumerator; `RECOV-3`'s fold is `Array#reduce`, not `Enumerator#next`; and no resource is
   acquired inside any block phase 4 yields from.
6. **The bundled-gem rule.** Settled for this phase: nothing in `CTX`, `RECOV` or `PIPE` reaches outside the
   existing allowlist, and no new entry is expected. In particular `logger` is not required for `PIPE-2`'s
   LOGGING pillar — that stage is a slot, and the sink is a duck type (§8.1).
7. **`Ractor` is never load-bearing.** `data-modeling/5bc538ba` already narrows the shareability claim; a
   context holds a `Response` holding a body holding an `IO`, so no shareability claim is made for the
   promotion chain at all, despite every link being a frozen `Data`.

---

## The three unsatisfied MUSTs: `PIPE-33` is phase 4's

`ASYNC-3`, `ASYNC-4` and `PIPE-33`'s interrupt clause are the port's three, split by §10.5 because they are
not equivalent cases. **`PIPE-33` is the one inside phase 4's ID range**, and the roadmap's cross-cutting
constraint 8 says "phase 8 marks all three ⏳ citing it". Both are true, and the relationship is worth stating
precisely because a reader can otherwise conclude that phase 4 has nothing to do here.

**What phase 4 can do, and does.** `PIPE-33` has **five** normative clauses — three MUSTs on the bridge's
construction plus the two halves of its cancellation sentence. **Four are met**, and phase 2 has already built
most of the machinery:

- *"MUST require a caller-supplied executor (no default)"* — met. Core defines the executor as a duck type
  (`#post { … }`) and ships **no implementation**, so there is no default to fall into (`SEAM-1`, `SEAM-18`).
- *"MUST run the wrapped synchronous pipeline as a single opaque unit on that executor (… so its own steps
  stay synchronous on the worker/dispatch thread and do NOT gain per-step concurrency)"* — met structurally:
  a built pipeline *is* a transport (`PIPE-26`), so `Transport.async_over(pipeline, executor:)` posts one
  `#call` and the steps never see the executor.
- *"MUST thread the caller's per-call options into the wrapped synchronous send"* — met, and phase 2 asserts
  the exact object arrives at the wrapped transport.
- *"cancelling without interruption MUST complete as cancelled without interrupting the worker"* — met
  exactly by `Future#cancel`.

**What phase 4 cannot do.** *"Cancelling the returned future with interruption MUST interrupt the worker
running the in-flight send."* Interrupt-mode cancellation is the mechanism §8.3 forbids repository-wide, so
every cancellation on this bridge behaves as the non-interrupting mode. §10.5 states the residual gap
precisely — a transport blocked inside an uninterruptible C-extension read cannot be aborted early by any
mechanism this port permits, so the worker occupies its pool slot until the read returns — and states the
mitigation just as precisely: the future completes as cancelled *promptly*, the worker aborts at its next
check-after-resume point, and `Completer#on_cancel` lets an adapter shorten that by closing the socket under
the read. **The consequence is bounded worker occupancy under aggressive cancellation, not a correctness
failure.**

**Phase 4 does not re-open the trade §10.5 settled**, and no sub-phase design may argue it. The `4c`
checklist row for `PIPE-33` is ⏳ citing `DEF-18` and §10.5, with the four met clauses named so the row is
not read as a wholly unbuilt requirement.

**Why phase 8 marks it again, and why that is not a duplicate.** §10.5's own distinction between `ASYNC-3`
and `ASYNC-4` is about antecedents: a requirement whose antecedent never occurs holds vacuously; one whose
antecedent is satisfied by a real adapter does not. In phase 4 the executor is a duck type with no
implementation, so no worker exists to fail to interrupt. `dexpace-async-thread` is what makes the antecedent
real. Phase 8's disposition is therefore a re-assertion at the point the requirement starts applying, not a
second decision — the same two-rows-one-obligation treatment phase 2 gave `SEAM-29` and phase 3b gave
`HTTP-46`.

**Two constraints follow, and they bind `4c` rather than being observations.** Because the gap is a
*mitigated* gap rather than an unmitigated one, every mitigation is load-bearing and `4c` may ship nothing that
widens it:

1. **No default executor.** This one is not an inference at all — it is `PIPE-33`'s own first clause, "MUST
   require a caller-supplied executor (no default)", restated here because the gap makes it load-bearing
   twice over. Core defines the executor as a `#post`-shaped duck type and ships no implementation; a default
   would let a caller reach the sync-to-async bridge without choosing a pool, which is the starvation
   `SEAM-18` names and which turns "the worker occupies its slot until the read returns" from a bounded cost
   into an unbounded one.
2. **No deadline-less unconditional block.** This one has a requirement of its own before it has anything to
   do with `PIPE-33`'s gap: `PIPE-34` itself requires the async-to-sync bridge to "honour thread
   interruption", cancelling the in-flight future and surfacing an interrupted-I/O error, and a bare wait
   with no token cannot do any of that. The gap only sharpens it — omitting the token would also make the
   "no caller waits on work it has abandoned" half of §10.5's mitigation false, because a caller stuck in an
   unconditional wait has no way to abandon anything. So `PIPE-34`'s blocking wait is
   `future.value(cancellation:)` — never a bare wait with neither a cancellation token nor a deadline, and
   never `Timeout.timeout` (§8.3). The
   `deadline:` keyword arrives in phase 5 (`DEF-28`); until then the cancellation token is the only way out of
   the wait, so omitting it would strand the caller as well as the worker.

---

## Verified Ruby facts that shaped this cut

Every claim below was run on 3.2.11, 3.4.10 and 4.0.6 via `mise exec ruby@<v>` on 2026-09-08. Two changed a
decision in this document; the rest are recorded because a sub-phase design would otherwise assume them.

1. **The suppressed trail must be rendered through `#detailed_message`, not `#full_message`.** Design §5.2
   specifies `Dexpace::Error` with "`#full_message` overridden to render the trail"
   (`error-handling/34f54b5e`). Verified: a module defining `full_message` and included into a
   `StandardError` subclass renders correctly **when `#full_message` is called explicitly**, and is
   **completely invisible to the default uncaught-exception printer** — the output on all three interpreters
   is the plain `file:line:in '<main>': boom (MyErr)` with no trail. Overriding `#detailed_message` instead
   reaches the default printer on all three, `#detailed_message` exists on the 3.2 floor, and Ruby's own
   `#full_message` calls it — so overriding `detailed_message` alone satisfies **both** paths, while
   overriding `full_message` alone satisfies only the explicit-call one and misses the path a reader of a
   crashed process actually sees. This is `DEF-24`'s content and `DEF-32`'s
   carrier, so it changes what `4b` builds rather than being noted after it. **Note filed**, superseding
   `error-handling/34f54b5e`.
2. **The `#cause` cycle is not reachable the way design §5.2 says it is, and a `4b` designer who tests the
   stated route will wrongly conclude the guard is unnecessary.** §5.2 says "Ruby does not prevent the cycle:
   `#cause` is settable through `Exception#exception` and re-raise chains built by application code can and
   do close on themselves" (`error-handling/11c6f36c`). Verified, all three: `raise y, cause: x` when `x`
   already causes `y` raises **`ArgumentError: circular causes`** — the VM rejects it; `raise s, cause: s`
   is accepted and leaves `s.cause` **`nil`**; re-raising the same object while it is `$!` also leaves its
   cause `nil`; and `Exception#exception("msg")` returns a **new** object whose cause is `nil`, so it is not
   a route to setting a cause at all. **The cycle is reachable, through the one route §5.2 does not name**: a
   caller-defined `#cause` override. `class Loopy < StandardError; def cause = self; end` self-cycles, and a
   pair of wrapper objects each returning the other cycles two ways — both verified on all three. Since
   `Dexpace.each_cause` walks *caller-supplied* errors (a third-party transport adapter's class, an
   application's own), that is exactly the shape core cannot control. `XCUT-9` stays a live MUST and the
   `equal?`-tracked visited set stays necessary; only the test that proves it changes. **Note filed**,
   superseding `error-handling/11c6f36c`.
3. **`NoMatchingPatternError` is a `StandardError` on all three**, which puts `RECOV-1`'s fold inside
   `RECOV-2`'s conversion boundary: an internal exhaustiveness defect becomes a `Failure` and is then
   rethrown unchanged by `RECOV-10`, indistinguishable at the call site from a step's own error. Design §5.2
   already routes it through an explicit `else` arm producing "a named internal error"; whether that named
   error is inside or outside `StandardError` is `4b`'s to decide (R6).
4. **`LoadError` and `NotImplementedError` are `ScriptError`s, not `StandardError`s**, on all three — so
   `RECOV-2`'s "rescue `Exception`, immediately re-raise anything outside `StandardError`" re-raises both. A
   step that lazily `require`s something absent escapes the recovery chain entirely. This is phase 2's
   registry finding (a `LoadError` from a factory wedged the registry) arriving at a second subsystem, and it
   is stated so `4b` decides it deliberately.
5. **`ObjectSpace::WeakKeyMap` is undefined on Ruby 3.2.11** and defined on 3.4.10 and 4.0.6;
   `ObjectSpace::WeakMap` exists on all three. Design §5.4 names both as `CTX-19`'s "live temptation". A
   source-text cop is unaffected; a *behavioural* test that names the constant cannot run on the floor (R1).
6. **A value-equality delete over the context store evicts a structurally identical live sibling.** With two
   `Data` instances carrying identical members, `h.delete_if { |_, v| v == other }` empties the hash while
   `h.delete(k) if h[k].equal?(other)` leaves it intact — on all three. `CTX-9`'s trap reproduced, and the
   test `4a` owes is one line.
7. **`Fiber[:key]` inheritance holds across the whole supported range, and it is copy-on-write.** Inherited
   by a child fiber, a newly created `Thread` and an `Enumerator`'s internal fiber; `Thread.current[:key]`
   visible in none of the three; a write inside a child fiber does **not** escape to the parent; and
   `Fiber.new(storage: nil)` opts out entirely. `Fiber#storage` reads the map on all three. The harvested
   entry (`observability/e0f1e864`) carries no version qualifier and omits the copy-on-write half. **Note
   filed**, widening it and recording the `CTX`-versus-diagnostic-context line above. The **write** side is
   a different story and is not phase 4's: `Fiber#storage=` warns on every call on all three and reads back
   differently on the floor, filed as `OI-13` for phases 5 and 8.
8. **A module included into an exception class sits ahead of `StandardError` in the ancestry** on all three,
   so `super` from `Dexpace::Error`'s `#detailed_message` reaches `Exception`'s. `Dexpace::Error` being a
   module (P1-2) costs nothing here.

---

## Deferrals Filed by Phase 4

**One, and it is the disposition of an entire ID cluster rather than an interface whose absence needed
recording.**

### `DEF-35` — `RECOV-17`–`RECOV-30` and `RECOV-34`: the recovery-stack retry engine

**Appended to `docs/deferred-items.md` in the change that files this document, and that row — not this
summary — is the authority.** It carries the twin-by-twin `RECOV`→`RETRY` mapping in full so phase 6 re-derives
nothing. What matters here is the shape of the disposition, which is:

- **Fifteen IDs, not sixteen.** `RECOV-17`–`RECOV-30` and `RECOV-34`. `RECOV-31` is the sixteenth ID of the
  same *cluster* and is **not** in `DEF-35`: `DEF-5` already defers it post-MVP, and `DEF-6` defers its twin
  `RETRY-38` with no named trigger. Every count derived from `DEF-35` — phase 6's budget above included — is
  fifteen; every count of the *cluster* is sixteen. Both numbers are correct about different sets and the
  distinction is load-bearing, because one is scheduled work and the other is not.
- **Why they are the retry stack and not the chain.** Eligibility classification, the re-sendability gate,
  re-classification of re-sent responses, the attempt cap and total-timeout budget, the backoff formula, the
  pacing-header parser and its precedence, the cancellable inter-attempt wait, per-call statelessness, and
  construction-time configuration validation. Each has a `RETRY` twin whose Ruby mapping §6.1 writes; design
  §12's `RECOV` row already places `RECOV-34` there; and `docs/sdk-design-ruby/` writes no Ruby mapping for
  `RECOV-17`–`RECOV-30` anywhere at all.
- **Two make it forced rather than preferred**, argued in full under *Why the sixteen move* above:
  `RECOV-27`'s conforming wait is the object `CFG-15` defines and phase 5 owns, and `RETRY-13` forbids a
  second backoff calculator.
- **Pick-up:** phase 6, with `RETRY`'s two stacks and the one shared calculator the roadmap's phase-6
  segmentation bullet already requires to land before either stack. Phase 6 decides whether each of the
  fifteen is a separate checklist row or a cross-reference to its twin; none may be dropped on the grounds
  that the twin is satisfied, because the roadmap's phase-4 row states the range `RECOV-1`–`RECOV-34`.
- **Phase 4 still ships the recovery chain the engine installs into** — `RECOV-1`–`RECOV-16` plus
  `RECOV-32`/`RECOV-33` — which is the substrate the roadmap's cross-phase obligation 3 names.

**Nothing else is filed, and that is deliberate.** A segmentation design decides a cut; it does not decide the
interfaces whose absence a deferral records. Two rows are **expected of the sub-phases** and are named in the
risks below so their absence later is visible: `4c`'s disposition of `PIPE-24`'s standard-resilience preset
before any pillar family exists (R14), and `4c`'s `PIPE-34` signature without a deadline (R13, on the
`DEF-28` precedent).

### Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every row.
All thirty-four were read.

**Phase 4 picks up three rows, supplies half of a fourth, and files one.** As with phase 3, this
document **states** each disposition and the sub-phase **performs** the register edit — the phase-3
segmentation design named `DEF-26` as `3b`'s pick-up and `DEF-3`'s two sharpenings, and `3b`'s own plan
made both edits — so `DEF-24`, `DEF-32`, `DEF-5` and `DEF-27` below are named here and edited by `4b`.
`DEF-35` is the one exception and is filed with this document, because it is a **scope disposition**
rather than an interface: leaving it unrecorded would oblige `4b`'s design to re-derive the same
sixteen-ID argument from scratch, and possibly reach a different answer.

- **`DEF-24` — picked up, by `4b`.** Its pick-up condition names phase 4 explicitly: "phase 4 (Execution
  Context and Pipelines), with the recovery chain that is its first caller." `4b` ships
  `Dexpace::Error#suppressed` (frozen once populated), `Dexpace.attach_suppressed(primary, secondary)` with
  `RETRY-34`'s skip-self guard, and the trail's rendering — **through `#detailed_message`, not
  `#full_message`**, per verified fact 1, which is a correction to the row's own stated content and to design
  §5.2. `RECOV-12` is the first caller, exactly as the row predicted. `NFR-4` is not a concern: the lock
  diffs against a release tag that does not exist.
- **`DEF-32` — picked up, by `4b`.** Its pick-up condition names phase 4 and its content: "with `DEF-24`'s
  `Dexpace::Error#suppressed`. That is the first carrier a second failure can be attached to, and the change
  is confined to `Hooks.notify`: attach each later failure to the first through `Dexpace.attach_suppressed`,
  then re-raise as now." It is a **behaviour change to code phase 2 shipped**, and phase 2's own edge-case
  table asserts the current behaviour ("the first failure is re-raised after the whole list"), so the test
  that pins it must change in the same commit. That is the reason `4b` precedes `4c` in the recommended order.
- **`DEF-5` — picked up as a disposition, not as work, by `4b`.** `RECOV-31` (MAY, the per-attempt ordinal
  header) is `4b`'s only pre-existing ⏳ row. Its condition — "picked up together with `RETRY-38` if the
  per-attempt ordinal header feature is ever built" — is post-MVP and phase 4 cannot meet it. The row is
  **not UNSCHEDULED**; `4b` carries the checklist row citing `DEF-5` and §11.20 and moves on.
- **`DEF-27` — half supplied, row stays open, and phase 4 must not close it.** The row names two disposal
  routes for `close_quietly`'s rescued error and says: "**phase 4 supplies the first route** with `DEF-24`'s
  `#suppressed` and `Dexpace.attach_suppressed`; **phase 5 supplies the second with §8.1's facade and closes
  this row**." `4b` supplies the first and adds a dated line to the row's `Status` recording it; the row does
  **not** move to `picked-up`, because its own text reserves closure for phase 5.
- **`DEF-4` — untouched, and carried as `4c`'s one pre-existing ⏳ row.** `PIPE-36` (SHOULD, pillar-step stage
  locking) is post-MVP per design §12's own `PIPE` row. Condition "post-MVP; no narrower trigger named yet" —
  not met, not UNSCHEDULED.
- **`DEF-18` — untouched, and cited by `4c`'s `PIPE-33` row.** Phase 4 neither meets nor re-opens it. See
  *The three unsatisfied MUSTs*.
- **`DEF-1` — untouched, and the one row whose condition names phase 4 as *not* the target.** "`SEAM-28`
  targets phase 5 … Both halves of the MAY need machinery phase 2 does not have — the request's context chain
  (`CTX`, phase 4) for 'attached to the request's context chain', and a consumer for the identifier
  (instrumentation, phase 5) for 'for instrumentation/tracing' — and **phase 5 is the first phase that has
  both**, which is why it is the target rather than phase 4." Phase 4 supplies the first half — `CTX-16`'s
  operation name is the chain's own carrier — and that is recorded rather than acted on. Not UNSCHEDULED: the
  condition names phase 5 and phase 4 cannot meet it.
- **`DEF-28` — untouched, and named as a constraint rather than a deferral.** The pivot has no `deadline:`
  until phase 5, and §8.3 independently forbids phase 4 from reaching for `Timeout.timeout`. `PIPE-34` and
  `RECOV-27` both feel it; `PIPE-34` ships narrower (R13) and `RECOV-27` moves under `DEF-35`.
- **`DEF-2` — untouched.** `HTTP-22`/`HTTP-48`–`HTTP-50` target phase 6.
- **`DEF-3` — untouched.** `BODY-12` clause 1 was discharged by phase 3b; clause 2 targets phase 8 with
  `DEF-10`; `BODY-36`'s condition is core's dependency budget changing, which phase 4 cannot meet.
- **`DEF-6`, `DEF-7`, `DEF-8`, `DEF-9` — untouched.** `RETRY`, `REDIR`, `SSE` and `OBS`; other prefixes,
  later phases. `DEF-6` becomes materially more relevant once `DEF-35` lands beside it in phase 6, and phase
  6 should read the two together.
- **`DEF-10` — untouched.** Per-adapter, phase 8 at the earliest.
- **`DEF-11`–`DEF-17` — untouched.** Post-v1 gems, out of the MVP by construction.
- **`DEF-19`, `DEF-20` — untouched.** Release-gated; nothing is published.
- **`DEF-21` — already picked up** by phase 2. **`DEF-26` — already picked up** by phase 3b.
- **`DEF-22`, `DEF-23` — untouched.** Phase 8's conformance assertion objects; a Steep target over a test
  tree whose condition ("production-quality test support") phase 4's fakes do not meet.
- **`DEF-25` — untouched.** Wire-boundary re-validation inside every transport, phase 8.
- **`DEF-29` — untouched.** `4a`, `4b` and `4c` will add test doubles (a fake step, a fake transport, a fake
  executor, a probe step per stage) under `gems/dexpace-core/test/support/`, following phase 2's and phase
  3's precedent. The condition — a consumer outside `dexpace-core` — is not met.
- **`DEF-30`, `DEF-31` — untouched.** Both target phase 5's instrumentation facade.
- **`DEF-33` — untouched.** A non-CRuby matrix row; no phase in v1 plans one.
- **`DEF-34` — untouched.** Phase 5's configuration source for the body-logging caps.

### The findings filed against `docs/open-items.md`

**`OI-12` — eighteen `RECOV` requirements exist only as appendix-C rows, and both the roadmap's gap paragraph
and `scripts/knowledge.rb --gaps` send a reader to a chapter that does not carry them.** Filed for the reasons
under *Gap IDs* above. It is the third instance of `OI-1`'s and `OI-2`'s shape and the largest; the three are
worth reading together, because at three occurrences the pattern is a property of appendix C's relationship to
the prose chapters rather than three separate omissions, and the pointer `--gaps` prints is derived
mechanically from appendix C's subsystem cell in every case.

**`OI-13` — `Fiber#storage=` warns on every call on every supported Ruby, and `= nil` reads back differently
on the floor.** Filed by this document's review, not by phase 4's own scope. Fiber storage's *read* side is
uniform across the range and is what verified fact 7 and the `observability` note record; its *write* side is
the mechanism design §8.1's `ASYNC-9`/`ASYNC-11` save/install/restore needs, and it emits
`Fiber#storage= is experimental and may be removed in the future!` per call on 3.2.11, 3.4.10 and 4.0.6 at
the default warning level, against a gate set that fails the build on warnings. `Fiber.current.storage = nil`
also leaves `{}` on 3.2.11 and `nil` on the other two. Nothing in `CTX`, `RECOV` or `PIPE` touches fiber
storage, so phase 4 neither acts on it nor is blocked by it; phases 5 and 8 are the ones that will meet it.

---

## Risks and open questions the sub-phase designs must resolve

Each is named with the sub-phase that owns it. None is decided here.

**R1 — `4a`: `CTX-19`'s weak-reference prohibition, on a range where one of the two constants does not
exist.** Design §5.4 makes the prohibition a lint rule and names `ObjectSpace::WeakMap` and
`ObjectSpace::WeakKeyMap`. Verified fact 5: the second is undefined on 3.2.11. `4a` decides whether this
extends an existing cop or adds a seventh, what it forbids (both constant names, `WeakRef`, and any
`require "weakref"`), and how the accompanying test is written given it cannot name the constant on the floor.

**R2 — `4a`: whether the call key is a member of the context `Data`, and what `CTX-5`/`CTX-6`'s stated
inequality costs.** The key participates in value equality by requirement, so two default-constructed
contexts are never `==` — which is a documented consequence, not a bug, and which a caller escapes only by
pinning an explicit shared key. `4a` decides the key's type (a rendered `trace-id:span-id` prefix plus a
monotonic counter, per §5.4 — a `String`? a frozen `Data`?), where the counter lives, and how "an explicit
shared key" is passed. It also owes the `equal?`-versus-`==` eviction test verified fact 6 makes one line.

**R3 — `4a`: the `Bundle`'s nine members, their names, and the phase-5 handshake.** Roadmap obligation 1
forbids deferring the shape and forbids phase 5 redefining it. §8.1 enumerates the nine and their no-op
values; it does not name them in Ruby. Every name is `NFR-4`-locked at the first release tag, so `4a` owes a
Deviation Ledger row of the kind phase 2's P2-11 and phase 3b's P3-14 set the precedent for — including the
trace-id-flavour enumeration, which per `type-system/545949a5` is a frozen `Data` type over a frozen table
with a `parse`/`of` factory, and not a `T::Enum`.

**R4 — `4a`: what shape `CTX-11`'s bounded map takes, given two later consumers share it.** §5.4 says it
shares "one implementation with `XCUT-14`'s general bounded-map rule and with `AUTH-19`'s per-nonce counter
store". `4a` decides whether that implementation is a public constant, a `private_constant`, or a module
function, knowing phase 6 and phase 9 both point at it and that a `private_constant` is invisible to a
consumer's `steep check`.

**R5 — `4b`: the suppressed trail's exact rendering, and what `DEF-32` costs phase 2's suite.** Verified fact
1 moves the override from `#full_message` to `#detailed_message`. `4b` decides whether `#full_message` is
*also* overridden (Ruby's own calls `detailed_message`, so it need not be), what the trail renders for an
error whose Ruby superclass is `::IOError` rather than a core class, whether `#suppressed` is frozen at the
first read or at the first raise, and which of phase 2's three `Hooks.notify` tests changes when `DEF-32`
lands.

**R6 — `4b`: where `RECOV-2`'s conversion boundary sits relative to the fold's own defects.** Verified facts
3 and 4: `NoMatchingPatternError` is inside `StandardError` and would be converted to a `Failure`;
`LoadError` and `NotImplementedError` are outside it and would escape. `4b` decides whether the fold's `else`
arm raises something the orchestrator re-raises rather than converts, and states the rule for a lazily
`require`ing step in one place rather than leaving each site to discover it.

**R7 — `4b`: the test that proves `each_cause`'s cycle guard, given the stated route does not build a
cycle.** Verified fact 2. `4b` builds the cycle through a caller-defined `#cause` override, asserts
termination, and asserts the `equal?`-not-`==` distinction over two distinct errors carrying identical
fields. It must not conclude from `ArgumentError: circular causes` that the guard is unnecessary — which is
exactly what testing the route §5.2 names would suggest.

**R8 — `4b` and `4c` jointly: how the three shipped steps are single-sourced across two invocation shapes.**
§5.1 asserts "the step protocol both layers share", but a pipeline step is `#call(request, cursor)`, a
recovery request step is `request -> request`, and the error-mapping step is `response -> outcome`. No single
arity spans all three. `4b` decides the pure-transform core and its home; `4c` decides how a pure transform
is installed into a non-pillar stage. **Neither may ship a second implementation of a transform**, and
whichever design lands second cites the first rather than restating it. This is the one contract that crosses
the `4b`/`4c` line and it is a contract, not an ordering.

**R9 — `4b`: `Dexpace::Recovery`'s namespace, and the constant it must not declare.** §5.1 names
`Dexpace::Recovery.buffer_error_body(response)`; P1-1 says flat unless the design namespaced it, and §5.1
did. `4b` decides whether `Recovery` also holds `Outcome`, the two chains and the shared ownership helper, or
whether those are flat — and, either way, ships **no second copy** of
`Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` (spec-forced boundary 10, phase 3b addendum B2).

**R10 — `4c`: where a step's stage assignment lives, given `#fork` is gated on it at composition time.** §5.1
requires the fork capability to be "checked at composition time from the step's stage assignment, not trusted
at call time", and separately requires a bare `lambda` to be a valid step. A lambda has no stage. `4c`
decides the mechanism — a stage passed at install time, a `#stage` method the pillar families define, or a
frozen table keyed by step class — and it decides the same question for cursor-scoped state's write
restriction, which is gated on the identical fact.

**R11 — `4c`: cursor-scoped state's two rules, which phase 6's redirect marker is built on.** Inheritance by
every cursor forked from a cursor, and a write permitted only to the pillar step that created the fork.
§10.15 (deviation 15) argues that these two together make `REDIR-11`'s forgery-impossibility claim
*structural* rather than defended. `4c` fixes them; getting the write restriction wrong makes a §10 entry
false two phases later, and nothing in phase 4's own suite would catch it. `4c`'s tests must therefore assert
the negative — that a step downstream of a fork cannot write the fork's state — not only the positive.

**R12 — `4c`: reconciling `PIPE-9` with `PIPE-10`.** `PIPE-9` says an empty pipeline SHOULD dispatch "without
allocating per-call cursor state"; `PIPE-10` says "each send MUST allocate its own per-call cursor". The two
are consistent only through the empty-pipeline special case, and `4c` states the reconciliation and tests
both branches rather than implementing one and hoping.

**R13 — `4c`: `PIPE-34`'s blocking wait has no deadline until phase 5.** `DEF-28` keeps `deadline:` off the
pivot and §8.3 forbids `Timeout.timeout`, so the bridge blocks on `future.value(cancellation:)`. `4c` decides
whether that is a deferral row or a signature phase 5 widens — the `DEF-28` precedent is to ship the narrower
signature and defer the wider one, and adding a keyword widens rather than narrows, so `NFR-4` permits it.

**R14 — `4c`: what `PIPE-24`'s standard-resilience preset and `PIPE-39`'s convenience constructors install
when no pillar family exists yet.** Both name redirect, retry, auth and instrumentation steps that arrive in
phases 5 and 6. `PIPE-32`'s explicit `redirect: :unsupported` argument on the async factory has the same
problem from the other side. `4c` decides whether the preset ships empty and validating (so `PIPE-24`'s
all-or-nothing rejection is real and testable against probe steps), ships as a deferral, or ships with a
phase-6 pick-up condition — and must not ship a preset that silently installs nothing while claiming to
install the defaults.

---

## Deviation Ledger

**Empty.** This document decides no deviation from the reference contract. Every mechanism substitution phase
4 relies on is already catalogued in
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` — items 5 (the unsatisfied
MUSTs), 6 (the core-owned suppressed trail), 15 (the cursor-borne redirect marker), 17 (the interruptible
sleep as a cancellable queue wait, which is why `RECOV-27` is `CFG-15`'s and not phase 4's) and 18 (the
substituted platform constants) — and is cited above rather than re-argued. The sub-phase designs will have
ledgers of their own; a deviation decided by any of them is numbered `P4-<n>` and consolidated into design §10.

**One correction to the roadmap, stated here because the roadmap requires a corrected cell to be corrected in
place with the correction stated.** The segmentation rule's phase-4 bullet reads: "`PIPE`'s steps thread state
through `CTX`'s promotion chain and `RECOV-10`/`RECOV-11` re-assert cancellation on the current context, so
4a leads both." Neither clause supports the conclusion. `PIPE`'s steps thread state through the **per-call
cursor** (`PIPE-11` puts per-request mutable state there in as many words; `PIPE-13`, `PIPE-16`, `PIPE-17`,
design §5.1's cursor-scoped state), not through `CTX`'s promotion chain — `CTX-<n>` is cited in no
specification chapter outside its own, and in no design section outside §5.4, §8.1, §11.11 and §12 bar one
`CTX-9` comparison in §5.2 that reads nothing from it. `RECOV-10` has no cancellation or context clause at
all. `RECOV-11` does, and design
§5.2 renders its "current context" as **the ambient cancellation token** — `Dexpace::Cancellation`, which
phase 2 already built — so the edge runs to phase 2 and not to `4a`. **`4a` still leads, and the letters are
unchanged; the order is a convenience with three stated reasons rather than a dependency.** The roadmap
sentence is corrected in place in the same change that files this document.

**Two further corrections, one to a roadmap bullet and one to `CLAUDE.md`, both made in the change that
files this document.**

- **The roadmap's phase-6 segmentation bullet.** It opened "Phase 6 (111 IDs, the largest)". No requirement ID
  moved and the phase-6 **row** stays correct — `RETRY-1`–`RETRY-45`, `REDIR-1`–`REDIR-28` and
  `AUTH-1`–`AUTH-38` still sum to 111 — but the scope that number stood for is stale, because `DEF-35` moves
  the *work* of fifteen `RECOV` IDs into phase 6 — `DEF-35`'s fifteen, not the cluster's sixteen, because
  `RECOV-31` is `DEF-5`'s post-MVP row and no register schedules it there. The bullet now reads "111 prefix
  IDs of its own … plus `DEF-35`'s fifteen" and says outright that **phase 6's segmentation design budgets
  for 111 + 15**, with the sixteenth named and excluded so the two counts cannot be conflated. The same
  statement is repeated in `DEF-35`'s own register row and in the roadmap's dated status note, because
  phase 6's planner may meet any one of the three first and must not have to discover it by counting. All
  three name `RECOV-31` as the cluster's excluded sixteenth and say why, so the two counts cannot be
  conflated from any of the three entry points.
- **`CLAUDE.md`'s `Fiber[:key]` citation.** Its constraints list cited design "§8.2" for `Fiber[:key]` versus
  `Thread.current[:key]`; the passage is in `docs/sdk-design-ruby/08-instrumentation-and-configuration.md`
  **§8.1**, since §8.2 is Configuration. The section number is corrected and nothing else in that sentence is
  touched. This is fixed rather than merely recorded because `CLAUDE.md` is the working contract every later
  phase reads first, and a wrong section pointer there is the same class of unfollowable pointer `OI-2` and
  `OI-12` record — the difference being that this one is a one-character fix in a writable file.
