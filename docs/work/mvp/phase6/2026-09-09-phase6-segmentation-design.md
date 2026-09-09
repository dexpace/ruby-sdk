# Phase 6 — Segmentation Design

**Status:** Draft, for review. Written 2026-09-09, before any phase-6 sub-phase design exists.

**What this document is.** The segmentation design the roadmap's **Segmentation rule** requires of a build
phase that spans more than one ID-bearing spec chapter. It decides how many ways phase 6 is cut and in what
order, says for each boundary whether that order is a **dependency** or a **convenience**, assigns every
requirement ID to exactly one sub-phase, and names the boundaries that are spec-forced and therefore not open
to the sub-phase designs to revisit.

**What this document is not.** It is not a phase design, a plan or a checklist, and it names no numbered task
and writes no code. Where it names a decision as belonging to a sub-phase it stops there deliberately; a
segmentation design that settles the sub-phases' content is the same failure as a sub-phase plan that
re-imposes a chain the split existed to avoid, arriving from the other direction.

**The headline, stated once at the top because everything else depends on it.** Phase 6's scope is
`RETRY-1`–`RETRY-45`, `REDIR-1`–`REDIR-28` and `AUTH-1`–`AUTH-38` — **111 prefix IDs of its own** — plus the
fifteen `RECOV` IDs `DEF-35` moves here, for a budget of **126**. **The cut is three ways — `6a` retry, `6b`
redirect, `6c` authentication — and every boundary is a CONVENIENCE.** The roadmap's phase-6 bullet leaves one
question open: whether the `REDIR-24`/`REDIR-11`/`AUTH-29` coupling makes redirect and auth "one segment or two
with a shared contract landed first". **That question was answered by phase 4c on 2026-09-08 and this document
does not re-open it**: the contract is `Cursor#fork(state:)` plus `Cursor#state(stage)`, it is built, it is
tested by five negative assertions, and its phase-6 consumption is written into 4c's own forward table. There
is no shared-contract sub-phase to land, because the shared contract already landed one phase early. The
roadmap sentence is a correctly-worded pointer at a premise that went stale three days after it was written,
and the correction is stated in this document's *Deviation Ledger* rather than filed as an open item — the
reasoning for that choice is given there.

Phase 6 adds **no new unsatisfied MUST**. It closes four register rows, half-closes two, files none, and
inherits a spec-reading budget of **fourteen** requirement IDs that exist only as appendix-C rows (`OI-12`).

---

## Governing documents

- `docs/product-spec/09-retry-and-resilience.md`, `docs/product-spec/10-redirect-handling.md` and
  `docs/product-spec/11-authentication.md` — normative, all three read in full for this document (36, 28 and 28
  lines), together with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text of all 111
  prefix IDs and of `RECOV-17`–`RECOV-34`. Appendix C is a **necessity** here and not a convenience: fourteen
  of the fifteen `RECOV` IDs in scope appear in no prose chapter at all (`OI-12`).
- `docs/product-spec/08-execution-pipelines.md` §8.2 — the recovery-chain primitives `DEF-35`'s engine installs
  into, and the chapter that stops at `RECOV-16`.
- `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` in full — §6.1 (single-sourcing, the open
  capability, construction-time validation, backoff, the three hand-written `Retry-After` pieces, the two
  stacks, the inter-attempt wait), §6.2 (the cross-origin marker on the per-hop cursor) and §6.3 (the
  descriptor/resolver model, credentials, challenge parsing, Digest, Basic, the AUTH pillar step, the provider).
- `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1 (cursor-scoped state and who may write it) and §5.2
  (the recovery chain, the cause enumerator, the suppressed-trail helper);
  `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.3 (the clock, the wait, the prohibition);
  `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items 4, 5, 15, 17 and 18;
  `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` items 1, 10,
  12, 19 and 20; and §12's `RETRY`, `REDIR`, `AUTH` and `RECOV` rows.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-6 row, the segmentation rule's phase-6
  bullet, the gap-ID paragraph, the five cross-phase obligations (2, 3 and 4 all bind here) and the
  nine cross-cutting constraints.
- `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md` and the three phase-4 sub-phase designs — in
  particular `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`, whose R11 and whose
  *interface surface later phases may cite* table are the contract this document declines to re-derive.
  `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md` and the three phase-5 sub-phase designs, in
  particular `phase5a`'s `R1` and its forward table.
  `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md` and
  `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md` as the two worked examples of this document's
  form.
- `docs/deferred-items.md`, `docs/open-items.md`, `docs/deviations.md`, `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

---

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run first. `ruby scripts/knowledge.rb --origin note --brief`
returns **37 entries across 18 note files**; `--section conflicts --brief` returns **24 entries across 17 topic
files, 18 of them notes and six harvested** — the six harvested ones being the styleguide-versus-design
conflicts themselves, and **every one of them prints `[overridden by notes/…]`**
(`data-modeling/35fde90f`, `module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and
`/8c0687bf`, `tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`). **None is open**, so phase 6
inherits no unresolved conflict and owns no conflict decision of its own.

**Corpus coverage, and the roll-up hazard, both checked rather than assumed.** `--prefix-info` reports
`RETRY` **45 of 45 substantive**, `REDIR` **28 of 28**, `AUTH` **38 of 38** — zero roll-up-only, zero uncited in
all three. `RECOV` reports **19 of 34 substantive, 15 uncited**. And the appendix-B roll-up hazard **does not
fire on this phase at all**: `ruby scripts/knowledge.rb --prefix RETRY --brief`, and the same for `REDIR` and
`AUTH`, return **zero** entries tagged `[appendix-B roll-up]` across every section (105, 47 and 70 entries
respectively). That is phase 4's position and the exact inverse of phase 5's, where all 78 IDs returned at
least one roll-up hit. A phase-6 sub-phase designer running `--req` gets substantive answers, and the skill's
three-step roll-up path is the exception here rather than the reading mode.

**Five note entries bind this phase directly. They are cited by key rather than restated, except the two the
roadmap's own instructions require quoting.**

- **`pipeline/86343352`** — the rule every one of phase 6's three pillar steps is built on, and the one a
  sub-phase author would otherwise get wrong from `PIPE-15`'s own wording. Quoted, not paraphrased:

  > **This port's rule is: a pillar step that may drive more than once forks for *every* drive, the first
  > included, and never calls its own `#call` at all** … because the fork is also where cursor-scoped state is
  > written (`docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1, and §6.2's cross-origin marker), so a
  > first drive that ran on the un-forked handle would have no stage slot to write and hop 1 could publish
  > nothing. … **The consequence for a phase-6 redirect or retry step is concrete** … writing the mixed shape
  > the harvested sentence describes compiles, passes every ordering test, and silently drops whatever the
  > pillar meant to publish on its first drive.

  The same entry carries `P4-33`: `Cursor#call`'s reuse guard is **sequential-only** — 29 of 2000 concurrent
  runs let a second caller through on 3.2.11 and 0 of 2000 on 3.4.10 and 4.0.6 — so a phase-6 pillar step must
  not treat the raise as a concurrency guard, **and a test asserting the race passes on the matrix floor and
  fails to reproduce on every other column.** No sub-phase writes such a test.
  <sub>review · `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md` · high · sha:manual-phase4c-cursor-latch</sub>

- **`execution-context/b58728da`** — the condition under which `6c`'s `AUTH-19` nonce store may reuse phase
  4a's shared bounded map. Quoted:

  > a `private_constant` defined on `Dexpace` **is** reachable by a bare, unqualified reference from
  > `module Dexpace; module Store` and from `module Dexpace; module Auth; module Digest` at any depth; it is
  > **not** reachable from the compact `module Dexpace::Compact` form, which raises `NameError: uninitialized
  > constant`; and it is **not** reachable through a qualified `Dexpace::BoundedMap` even from a file lexically
  > inside `Dexpace`, which raises `NameError: private constant … referenced`. So "one implementation" holds
  > exactly as far as `module-organization/64e84d64` … is followed — a rule this repository already requires
  > for an unrelated reason, and which is load-bearing for this one.

  <sub>review · `docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-design.md` · high · sha:manual-phase4a-bounded-map-private-constant</sub>

- **`url-and-query-encoding/08c54234`** — `6b`'s note, and it names phase 6 in its own text. Two facts travel:
  the sanctioned spelling for `REDIR-13`/`REDIR-14`'s reference resolution is `URI::RFC3986_PARSER.join`,
  because phase 0's `Dexpace/NoUriDefaultParser` cop fails the build on `URI.join`; and
  `URI::InvalidURIError`'s message differs by a space between 3.2.11 (`bad URI(is not URI?)`) and 4.0.6
  (`bad URI (is not URI?)`), **so no `6b` assertion may match it** — phase 1's `Dexpace::URL.parse!`
  converts it to a `Dexpace::InvalidArgumentError` carrying the offending input, and that is what to assert on.
  <sub>review · `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` · high · sha:manual-phase2-seam27-composition</sub>

- **`error-handling/a0c4abfe`** — `6a`'s note. The suppressed trail is `Dexpace::Suppressible`, a module
  `Dexpace::Error` includes and `Dexpace.attach_suppressed` `extend`s onto anything else, with the
  self-suppression skip `RETRY-34` names already implemented; `Dexpace.suppressed(error)` reads the trail off
  any object. `6a` writes no second trail and no second skip.
  <sub>review · `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` · high · sha:manual-phase4b-suppressible-module</sub>

- **`pipeline/f02559b9`** — `6a`'s second note. Every place core re-raises an error it is *carrying* rather
  than one it just rescued is written `raise error, cause: nil`, because a bare `raise stored` silently assigns
  the caller's in-flight exception as that error's `#cause`. `RETRY-34`'s terminal surfacing and `RECOV-20`'s
  "the terminal failure's throwable MUST be surfaced" are both such places.
  <sub>review · `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` · high · sha:manual-phase4b-reraise-cause</sub>

**One audit group was run, and the skill's table is owed a row this document cannot add.** The
`knowledge-lookup` audit-group table carries ten rows and none covers retry, redirect or authentication. The
group that was run is `ruby scripts/knowledge.rb --prefix RETRY,REDIR,AUTH --section rules --brief` — **119
entries across 6 topic files** (`retry-and-resilience`, `redirect-handling`, `authentication`, `pipeline`,
`execution-context`, `cancellation-and-timeouts`), zero of them roll-up-tagged. The roadmap's first
retrospective rule and phases 3a, 4 and 5's precedent require the row to be **added before the group is run**;
this document is constrained to write exactly one file and therefore could not add it. **The eleventh row is
owed**, and its exact content is:

| Audit group | Query (once harvested) | Today | Status |
|---|---|---|---|
| Resilience: retry, redirect and authentication | `--topic retry-and-resilience,redirect-handling,authentication,cancellation-and-timeouts --section rules --brief` and `--prefix RETRY,REDIR,AUTH --section rules --brief` | `--prefix-info RETRY`, `--gaps RETRY,REDIR,AUTH,RECOV` | live |

Whoever files this document adds that row to `.claude/skills/knowledge-lookup/SKILL.md` in the same change. It
is not a frozen tree.

`--phase 4` and `--phase 5` were run to see what the predecessors already cite. Phase 4 cites `RETRY-13`,
`RETRY-25`, `RETRY-27`, `RETRY-28`, `RETRY-34`, `RETRY-37`, `RETRY-42`, `REDIR-11`, `REDIR-24`, `AUTH-19` and
`AUTH-29` without owning any of them, all pointing here. Phase 5a cites `RETRY-1` and `RETRY-12` and fixed one
object phase 6 consumes and must not duplicate (`Dexpace::Retryability`, `DEF-40`).

**No knowledge note is filed by this document.** The one candidate — `URI::Generic#userinfo = nil` being a
silent no-op — is recorded under *Verified Ruby facts* below and the note that carries it is **`6b`'s to file
with the design that acts on it**, which is phase 5's stated treatment of the same situation. Recorded here so
its absence is a decision rather than an omission.

---

## The cut

**Three ways. Every boundary is a CONVENIENCE.**

| Sub-phase | Name | Spec sections | IDs | Order |
|---|---|---|---|---|
| **6a** | Retry — both stacks and the shared policy | `docs/product-spec/09-retry-and-resilience.md`, all of it, plus `RECOV-17`–`RECOV-30` and `RECOV-34` from appendix C | 60 | first, **convenience** |
| **6b** | Redirect | `docs/product-spec/10-redirect-handling.md`, all of it | 28 | second, **convenience** |
| **6c** | Authentication | `docs/product-spec/11-authentication.md`, all of it | 38 | third, **convenience** |

### The roadmap's open question is already answered, and not by this document

The segmentation rule's phase-6 bullet ends:

> `REDIR-24` fixes the redirect loop outer and auth stamping inner, per hop, and `REDIR-11`'s cross-origin
> suppression signal is consumed by `AUTH`'s stamping step, so neither pillar half finishes without the other's
> contract fixed; phase 6's segmentation design settles whether that is one segment or two with a shared
> contract landed first.

Every clause of that is true. Its premise — that the contract is unfixed when phase 6 starts — is not, and the
document that changed it is `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`, written
three days after the roadmap. Five pieces of evidence, verified for this document:

1. **The stage order is fixed and shipped.** 4c's stage table gives `PRE_REDIRECT` 100, `REDIRECT` 200
   (pillar), `POST_REDIRECT` 300, `PRE_RETRY` 400, `RETRY` 500 (pillar), `POST_RETRY` 600, `PRE_AUTH` 700,
   `AUTH` 800 (pillar), `POST_AUTH` 900, then `LOGGING` 1100, `SERDE` 1400 and `SEND` 1600. That is `PIPE-2`'s
   precedence chain — REDIRECT outer, RETRY, then AUTH — and `AUTH-27`'s "redirect wraps retry wraps auth" in
   the same order. `PIPE-4` admits at most one step per pillar, so each of `6a`, `6b` and `6c` occupies exactly
   one slot and no two of them can collide.
2. **The marker mechanism is built.** `Cursor#fork(state:)` merges the supplied pairs into `state[owner_stage]`
   and **only** there, the owner's stage coming from the frozen entry table so a step cannot name a slot it
   does not own; `Cursor#state(stage)` returns a frozen hash, a shared frozen empty one for an unwritten stage;
   `Cursor#may_fork?` lets a step ask rather than rescue.
3. **The write restriction is tested by five negative assertions**, and 4c states why: "4c's tests must
   therefore assert the negative — that a step downstream of a fork cannot write the fork's state — not only
   the positive." Assertion 4 is written against `Stages::REDIRECT` and `Stages::RETRY` **by name, with a
   comment naming `REDIR-11`, `AUTH-29` and §10.15, so a phase-6 author who changes the mechanism meets the
   test that says why**.
4. **4c's own forward table already writes phase 6's consumption of it**, in the row headed *Phase 6, on
   `REDIR-11`/`AUTH-29`*: "The redirect step forks per hop from its own cursor with `state: { cross_origin: … }`,
   landing in `Stages::REDIRECT`'s slot; the auth step reads
   `cursor.state(Dexpace::Pipeline::Stages::REDIRECT)`. **Phase 6 adds no marker to the request and strips
   nothing**, which is §10.15's whole claim."
5. **The deviation is argued and consolidated.** Design §10.15 — "The cross-origin redirect marker lives on the
   per-hop cursor, not on the request. *Touches* `REDIR-11`, `AUTH-29`, `PIPE-16`. *Judged, and stronger.*" —
   and design §6.2 states the mechanism and closes with "The auth step reads it through the cursor
   (**AUTH-29**)." Design §5.1 supplies the two rules the argument rests on.

**So the answer is three independent segments and no shared-contract sub-phase.** What is left at the `6b`/`6c`
boundary is not a contract to design but two halves of an already-designed one to implement, and each half is
testable alone against the doubles 4c shipped: `6b` forks with `state: { cross_origin: true }` and asserts a
probe `AUTH` step downstream reads it; `6c` reads `cursor.state(Stages::REDIRECT)` and asserts against a probe
`REDIRECT` step that forks with the marker set and unset. `test/support/ForkingProbe` and `StateProbe` are
phase 4c's and are the worked examples.

Two clauses at that boundary must not be lost in the split, and each is named in its owner's scope table below:

- **`REDIR-7` is `6b`'s and is what makes `6c`'s re-stamp correct.** "The Authorization header MUST be stripped
  before EVERY redirect re-issue — including same-origin and the 303 GET rebuild — because re-attaching a
  credential for a known origin is the auth layer's job." `6c` may assume no inherited `Authorization` on any
  re-issue; `6b` may assume nothing about who re-attaches it.
- **`AUTH-29`'s stripping clause is vacuous here, and `6c` records it as satisfied by construction rather than
  ticking it silently.** "MUST strip the internal cross-origin marker so it never reaches the wire" has no code
  under §10.15, because nothing was ever added to the request. `REDIR-11`'s clause (c) — "be removed by the
  credential-attaching layer before dispatch" — is satisfied *a fortiori* for the same reason, and clause (a)
  — unforgeable by a server-supplied `Location` — is satisfied **structurally**, because a `Location` value
  cannot reach cursor state at all. Clause (b), "only SUPPRESS stamping, never CAUSE a credential to be sent",
  is the only one of the three with executable content, and it is `6c`'s.

### Why `6a` is one segment and not two, at sixty IDs

`6a` is **60 IDs**, the largest sub-phase in the roadmap — larger than phase 3b's 49, which was explicitly
flagged as "the price of not splitting a lifecycle". Saying that plainly is the precondition for arguing it is
still right.

The specification's own chapter introduction is the argument:

> The SDK ships two cooperating stacks — the recovery-chain retry (with a total-timeout budget) and the
> stage-based retry step — **deliberately built on ONE status classifier, ONE backoff calculator, ONE
> pacing-header parser, and ONE set of tuning constants so behavior cannot drift.**

`RETRY-13` makes it normative: "Both retry stacks MUST compute their backoff via the one shared calculator
using the one shared set of constants (multiplier, jitter, base, cap); the stacks MUST NOT carry independent
backoff formulas or duplicated constants." `RETRY-14` requires their budgets to denote the same number of wire
sends. `RECOV-30` restates both at SHOULD level from the recovery side. Design §6.1 puts the consequence in one
sentence: the idempotent set, the classifier, `XCUT-7`'s configurable set and the calculator "all live in one
`Dexpace::Resilience::Policy` module as frozen constants and pure functions".

**`DEF-35` is that argument already applied once, at phase scale.** It refused to build the recovery half in
phase 4 because "building the recovery half two phases before the stage half is exactly the drift both
requirements exist to prevent". A cut inside `6a` — along the two stacks, or along sync-versus-async — re-runs
the same mistake at document scale: one document would author the calculator and another would consume it,
with a review boundary between the constants and one of their two callers. That is precisely the seam the word
ONE is in four requirements to close.

The sync/async line is separately wrong here even though it is the right line in phase 8. `PIPE-28` requires
the async runtime to reuse "the identical stage identities and staging policy" and forbids the two runtimes
from re-deriving ordering independently; 4c satisfied it structurally by shipping one `Stages` module both
runtimes use and asserting the two entry tables equal step-for-step. The retry step is the same shape: one
policy module, two thin drivers, `RETRY-14`'s budget equivalence asserted by a test that spans both. Splitting
the drivers into two documents gives the equivalence test no home.

**What `6a` owes in exchange for being large** is stated so a reviewer can hold it to it: its plan carries an
explicit internal ordering — the shared policy core (classifier, calculator, pacing parser, constants,
re-sendability gate) lands before **either** stack — and that ordering is *task ordering inside one plan*, not
a segmentation boundary. Its checklist is 60 rows plus four ⏳ rows, the largest single table in the
repository.

### Why `6b` and `6c` do not lead one another

Neither reads a line of the other's code. Stated as the two directed edges a reader will look for:

- **`6b` → `6c`?** No. `6b` writes `state: { cross_origin: bool }` into its own stage slot and returns. It does
  not know whether an AUTH step is installed, and `PIPE-4` guarantees it cannot install one. `REDIR-11`'s
  porter caveat — "only the auth step strips the marker, so a pipeline with no auth step … forwards the
  internal marker to the transport" — **cannot occur under §10.15**, which is exactly why the deviation was
  taken; so `6b` has no contingency to write against `6c`'s presence or absence.
- **`6c` → `6b`?** No. `6c` reads `cursor.state(Stages::REDIRECT)`, which 4c guarantees is a shared frozen
  empty hash when nothing wrote it. A pipeline with no REDIRECT step therefore hands `6c` the "not
  cross-origin" answer with no branch of its own, which is `AUTH-29`'s same-origin case and the one it must
  re-stamp normally. `AUTH-27`'s "running nested inside both the redirect loop and the retry loop" is a
  statement about *stage order*, which 4c fixed, not about a call `6c` makes.

`6a` is independent of both in the same way: `Stages::RETRY` sits between REDIRECT and AUTH, and 4c's stage
namespacing means a RETRY fork's state is invisible under `Stages::REDIRECT` to anyone — that is negative
assertion 4, and it is the assertion that makes `6a` unable to interfere with the `6b`/`6c` contract even by
accident.

### The order that is recommended, and why it is only a recommendation

`6a → 6b → 6c`. Four reasons, none of them a dependency:

1. **`6a` is the largest and its policy core is the phase's longest pole.** Landing it first gives the other
   two the longest lead, which is the reasoning phase 4 gave `4a` and phase 5 gave `5a`.
2. **`6a` is where four register rows close or half-close** — `DEF-35`, `DEF-38`, `DEF-40` and `DEF-42`'s
   per-attempt half. Two of those (`DEF-38`, `DEF-40`) name objects phase 5a deliberately shipped half of, and
   the longer they stay half-shipped the more likely a second one gets built.
3. **`6a` is the sub-phase this document assigns `OI-31`'s resolution to**, and the widening it lands is
   consumed by `6b` and `6c` if it exists and by nothing if it does not — see *Phase-level tasks* below.
4. **`6b` before `6c` puts the marker's writer in place before its reader.** This is the reason most likely to
   be mistaken for a dependency and it is not one: each side is fully testable against 4c's probes, and the
   only thing `6b`-first buys is that the end-to-end convergence test can be written by `6c` rather than
   deferred to a phase-level task.

**Because the order is a convenience, each sub-phase's design must say so in its own Prerequisite section
rather than inheriting a chain by habit.** A `6b` plan whose first task waits on `6a`'s `Resilience::Policy`
has re-imposed a chain that does not exist; so has a `6c` plan that waits on `6b`'s redirect step to exist
before it can assert `AUTH-29`.

### Four other cuts were considered, and rejected

**Rejected cut A — two ways: `6a` retry, and one segment holding redirect and auth "with a shared contract
landed first".** This is the roadmap's open option. Rejected on the five pieces of evidence above: the shared
contract landed in phase 4c and there is nothing left to land. Rejected additionally on shape — the merged
segment would be **66 IDs** over two disjoint object graphs (a URL-resolution and response-lifecycle loop; an
RFC 7235/7616 credential stack), and it would put a security-critical *stripping* policy and a security-critical
*stamping* policy in one document, which is the arrangement most likely to produce a sentence true of one and
assumed of the other.

**Rejected cut B — four ways, with a shared "resilience policy core" segment landing before `6a`.**
Superficially attractive because `RETRY-13` demands one calculator and one set of constants. Rejected: the
policy core has exactly two consumers and both are inside `6a`, so the segment is strictly linear and buys no
independence at all; and separating the constants' authorship from both of their callers is the drift
`RETRY-13` forbids, arriving from the direction nobody watches. The ordering constraint is real and is
discharged as **task ordering inside `6a`'s plan**, where a reviewer of the calculator is also a reviewer of
both stacks.

**Rejected cut C — splitting `6a` along its two stacks, or along sync/async.** Rejected under *Why `6a` is one
segment*, on `RETRY-13`, `RETRY-14`, `RECOV-30`, the chapter's own introduction and `PIPE-28`'s precedent.

**Rejected cut D — four ways, with a closing segment for `DEF-39`, `DEF-42` and `OI-31`.** The three
phase-level items genuinely belong to no sub-phase. Rejected anyway: together they are a handful of tasks, a
fourth segment is a fourth document set and not a fourth merge (a phase returns to `mvp` as one phase-level
pull request, roadmap execution step 5), and a segment that can only run last is the definition of a linear
chain. They are assigned instead as **phase-level tasks with named owners**, below.

---

## Spec-forced boundaries — not open to `6a`, `6b` or `6c`

Each is a MUST, a design deviation already argued, a shipped phase-4/5 contract, or a roadmap obligation
already fixed, that settles something a sub-phase design might otherwise believe it is free to decide.

1. **All three phase-6 pillars fork for every drive, the first included, and never call `Cursor#call`.** Each
   of the three may drive the downstream chain more than once: REDIRECT per hop (`REDIR-24`), RETRY per attempt
   (`RETRY-44`), AUTH twice on the 401 re-challenge path (`AUTH-30`: "drive the replacement through a fresh
   copy of the downstream chain exactly once"). `pipeline/86343352` and 4c's R11 make the rule absolute:
   `#call` and `#fork` are disjoint on one cursor, and `#fork` on a spent cursor raises
   `Dexpace::PipelineError`. **`AUTH-30`'s replay is the case a `6c` author is most likely to write as
   `cursor.call` then `cursor.fork`**, which is exactly the rejected shape.
2. **The cross-origin marker is cursor state, never a header.** Design §10.15, §6.2, §5.1. `6b` writes
   `state: { cross_origin: … }` into `Stages::REDIRECT`; `6c` reads `cursor.state(Stages::REDIRECT)`. Neither
   adds a request header, neither strips one, and neither may propose a header-based fallback "for pipelines
   built by hand" — 4c's negative assertion 4 fails if the mechanism changes.
3. **Two retry stacks, one policy, and neither unification sanction is invoked.** Design §6.1 and §11.19. The
   port keeps both stacks because §5 keeps both layers, and `08-execution-pipelines.md` forbids collapsing
   them. `6a` may not unify the stacks and may not unify the two entry points onto them; a port that unified
   only the entry points would escape `RETRY-28`'s sanction and be caught by the pipelines chapter's.
4. **`RETRY-28` forbids a total-timeout on the stage stack; `RECOV-20` requires one on the recovery stack.**
   One calculator, two budget policies. `6a` implements the asymmetry rather than reconciling it, and design
   §6.1's "the recovery-aware stack MAY additionally enforce a total-timeout deadline that the stage-based step
   omits" is the sanctioned reading.
5. **The inter-attempt wait is `CFG-15`'s cancellable queue wait, and `Timeout.timeout`, `Thread#raise` and
   `Thread#kill` are forbidden.** Design §8.3, §10.17, §11.1, and `CLAUDE.md`'s ban list. `6a` calls
   `Dexpace::Clock#sleep(duration, cancellation:)` (phase 5a's) on the sync path. `RETRY-26`'s
   no-carrier-pinning and `XCUT-3`'s "the normative requirement is prompt cancellation, not the specific
   mechanism" are what license it.
6. **The status classifier is phase 5's object and `6a` builds no second one.** `Dexpace::Retryability.retryable_status?`
   ships in 5a as `XCUT-5`'s SINGLE shared classifier with the exact set 408, 429 and all 5xx except 501 and
   505. `6a` computes `DEF-38`'s baked `ProtocolError#retryable?` **from it**. `XCUT-7`'s configurable set —
   default `{408, 429, 500, 502, 503, 504}` — is a different object and `XCUT-5`'s own closing NOTE is what
   keeps them apart: the baked flag is queryable and is **not** what the retry step consults.
7. **The non-protocol retryability branch is `XCUT-6`'s capability query, not a concrete-type match.** Design
   §6.1: `error.respond_to?(:retryable?) && error.retryable?`, walked over `Dexpace.each_cause` (phase 4b's,
   cycle-safe by reference identity, `XCUT-9`). `6a` writes no `is_a?(::IOError)` branch — `DEF-40` records
   that such a branch is wrong in both directions.
8. **`Dexpace::BoundedMap` is reachable only from a full-nesting `module` form.** `execution-context/b58728da`.
   `6c`'s `AUTH-19` store is written in `module Dexpace; module Auth; module Digest`, never
   `module Dexpace::Auth::Digest` and never through a qualified `Dexpace::BoundedMap`.
9. **Basic is `["u:p"].pack("m0")` and Digest is `Digest::MD5`/`Digest::SHA256`, never `Base64` and never
   `OpenSSL::Digest`.** `CLAUDE.md`'s hard rule and design §6.3. `base64` is on phase 0's require **denylist**;
   `digest`, `securerandom` and `openssl` are on its allowlist, so `6c` needs no allowlist diff.
10. **`SecureRandom` for the cnonce, never `Random`.** `AUTH-20`, `XCUT-21`, design §6.3. 5a's `Dexpace::UUID`
    is explicitly the *non-cryptographic* path and its YARD says so; `6c` must not reach for it.
11. **`URI::RFC3986_PARSER` is pinned for every parse and every resolution.** Design §3.5, phase 0's
    `Dexpace/NoUriDefaultParser` cop, and `url-and-query-encoding/08c54234`. `6b` writes
    `URI::RFC3986_PARSER.join`, never `URI.join`.
12. **The async pipeline follows no redirects.** `REDIR-25` and `PIPE-32`. `6b` ships **no** async redirect
    step. 4c deliberately did not make `Stages::REDIRECT` un-installable on the async path (`PIPE-28`), and
    `6b` must not add that restriction either.
13. **`AUTH-31`'s replayability gate applies on both the sync and async paths.** Design §11.12 resolves all
    four reference sync/async drifts — `BODY-8`, `RECOV-14`, `RETRY-34`, `AUTH-31` — "toward the stricter,
    uniform behaviour, each through a single shared implementation so the paths cannot drift again". `RETRY-34`
    is `6a`'s and its shared implementation is `Dexpace.attach_suppressed`, already built. `AUTH-31` is `6c`'s.
14. **Roadmap cross-phase obligation 2 is discharged by implementation, not by re-design.** "Both sides land in
    phase 6, under one contract" — the contract is 4c's, and phase 6 lands the two sides.

---

## Scope: every ID, assigned to exactly one sub-phase

**126 requirement IDs.** Level split, derived mechanically from appendix C on 2026-09-09: **111 MUST, 11
SHOULD, 3 MAY and 1 MUST NOT** — 111 + 11 + 3 + 1 = 126. The single MUST NOT is `RETRY-45`, the only
requirement in the whole specification tagged that way, which design §11.10 indexes as a MUST "since RFC 2119
MUST and MUST NOT are the same strength"; it is counted in its own column here so the four columns sum, and a
checklist may treat it as a MUST.

### Reconciliation against the roadmap's arithmetic

Verified mechanically against `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` on
2026-09-09 with `grep -c '^| RETRY-'`-style counts:

| Prefix | Rows in appendix C | Level split |
|---|---|---|
| `RETRY` | 45 (`RETRY-1`..`RETRY-45`, contiguous, no duplicate) | 39 MUST, 3 SHOULD (`RETRY-12`, `RETRY-38`, `RETRY-40`), 2 MAY (`RETRY-29`, `RETRY-43`), 1 MUST NOT (`RETRY-45`) |
| `REDIR` | 28 (`REDIR-1`..`REDIR-28`) | 23 MUST, 4 SHOULD (`REDIR-10`, `REDIR-21`, `REDIR-23`, `REDIR-28`), 1 MAY (`REDIR-27`) |
| `AUTH` | 38 (`AUTH-1`..`AUTH-38`) | 36 MUST, 2 SHOULD (`AUTH-19`, `AUTH-38`) |
| `DEF-35`'s `RECOV` | 15 (`RECOV-17`–`RECOV-30`, `RECOV-34`) | 13 MUST, 2 SHOULD (`RECOV-25`, `RECOV-30`) |

45 + 28 + 38 = **111**, which is the roadmap's phase-6 cell and its own segmentation bullet's figure.
111 + 15 = **126**, which is what the bullet instructs this document to budget for: "**Phase 6's segmentation
design must budget for 111 + 15 and not for 111**". `6a`'s 60 plus `6b`'s 28 plus `6c`'s 38 is 126, each ID in
exactly one sub-phase.

**`RECOV-31` is the cluster's sixteenth ID and is deliberately excluded from the budget.** `DEF-5` defers it
post-MVP and `DEF-6` defers its `RETRY-38` twin with no named trigger, so no register schedules its
implementation here. `6a` carries a ⏳ row for it beside `RETRY-38`'s; **a row is not a budget line.** `DEF-35`
states the arithmetic hazard exactly and this document adopts its wording: "Fifteen and sixteen are both correct
numbers about different sets … and conflating them is the one arithmetic mistake this row exists to prevent."

### `6a` — Retry: both stacks and the shared policy (60 IDs)

**45 `RETRY` + `DEF-35`'s 15 `RECOV`.** Scope in one sentence: one `Dexpace::Resilience::Policy` (status
classification consulting phase 5a's `Retryability`, the configurable retryable-status set, the idempotent
method set, the backoff calculator, the pacing-header parser, the tuning constants), one re-sendability gate,
and the two stacks that drive it — the recovery-stack engine that installs into phase 4b's
`Recovery::ResponseChain`, and the stage-based pillar step at `Stages::RETRY` with a sync and an async driver.

| Disposition | IDs | Count |
|---|---|---|
| Implemented — `RETRY` | `RETRY-1`–`RETRY-28`, `RETRY-30`–`RETRY-37`, `RETRY-39`–`RETRY-42`, `RETRY-44`, `RETRY-45` | 42 |
| ⏳ deferred, `DEF-6` (pre-existing), no named trigger | `RETRY-29` (MAY), `RETRY-38` (SHOULD), `RETRY-43` (MAY) | 3 |
| Implemented — `DEF-35`'s `RECOV` | `RECOV-17`–`RECOV-30`, `RECOV-34` | 15 |
| **Total in budget** | | **60** |
| ⏳ row only, no budget line — `DEF-5`, the twin of `RETRY-38` | `RECOV-31` (MAY) | — |
| Inherited row, no budget line — `DEF-40`'s throwable half of a phase-5 ID | `CFG-35` (SHOULD) | — |

`6a` additionally ships, without owning a new ID: `Dexpace::ProtocolError#retryable?`, computed once at
construction from 5a's `Dexpace::Retryability` (`DEF-38`, `XCUT-5`); `CFG-35`'s throwable half as `XCUT-6`'s
capability query over `Dexpace.each_cause` (`DEF-40`); `RETRY-12`'s five default values behind 5a's
`Keys::MAX_RETRY_ATTEMPTS` name, which 5a shipped without a value; and `OBS-29`'s per-attempt event group on
the retry step (`DEF-42`, half of it).

Two clauses inside `6a` a plan will otherwise leave implicit:

- **`RETRY-35` orders the close before the wait.** "A retryable response's body/connection MUST be released
  before the backoff wait so a socket is not pinned across the delay; the pacing delay is computed from the
  still-open response first, and if the retry decision or delay computation throws, the response MUST still be
  closed before propagating." That is three orderings in one requirement and it interacts with `PIPE-40`'s
  "close every superseded intermediate before the next drive".
- **`RETRY-37`'s semantics are authoritative-contains, not intersection.** The configured set both widens and
  narrows relative to the built-in classifier and is **not** AND-ed with the baked flag. Design §6.1 requires a
  dedicated test for it and `6a` writes one.

### `6b` — Redirect (28 IDs, all `REDIR`)

Scope in one sentence: one iterative redirect follower occupying `Stages::REDIRECT`, forking per hop with the
cross-origin marker, resolving `Location` against the current hop through `URI::RFC3986_PARSER`, enforcing the
credential-hygiene rules against the **seed** origin, and managing response-body lifecycle deterministically.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `REDIR-1`–`REDIR-26`, `REDIR-28` | 27 |
| ⏳ deferred, `DEF-7` (pre-existing), no named trigger | `REDIR-27` (MAY, configurable target header) | 1 |
| **Total** | | **28** |

Three rows carry a clause the checklist must state rather than tick:

- **`REDIR-11`** — clause (a) satisfied **structurally** (a `Location` cannot reach cursor state), clause (b)
  implemented in `6c`, clause (c) satisfied *a fortiori* (nothing is added, so nothing is removed). Cites
  §10.15 and 4c's five negative assertions.
- **`REDIR-25`** — satisfied by shipping no async redirect step. Its substantive clause holds vacuously until
  `DEF-39`'s async standard pipeline exists, which is a phase-level task; the row says so, exactly as phase
  4c's `PIPE-32` row does.
- **`REDIR-8`** — the comparison is against the **seed** origin, not the previous hop, and design §6.2 requires
  an explicitly constructed `[scheme.downcase, host.downcase, effective_port]` triple rather than `URI#==`.
  Verified fact 3 below is why `downcase` is not optional.

`6b` additionally ships, without owning a new ID: the `REDIR-28` ↔ `Dexpace::Instrumentation::Redactor#url`
linkage, which **no phase-5 document states** — verified 2026-09-09, `REDIR-28` appears nowhere under
`docs/work/mvp/phase5/`. 5b's `Redactor#url` is total, returns `MALFORMED_URL` on failure and wraps its whole
body in one `rescue StandardError`, which is exactly `REDIR-28`'s "redaction failures degrading to a
placeholder rather than crashing logging"; and `REDIR-28`'s stated exception — the malformed-`Location` event
logs the raw string as received, because it failed to parse and cannot be redacted — is the one place `6b` must
**not** call the redactor.

### `6c` — Authentication (38 IDs, all `AUTH`)

Scope in one sentence: the descriptor/resolver model, the four credential types with their variant-specific
equality and redaction, the RFC 7235 challenge parser, the Basic and Digest handlers with the bounded per-nonce
counter store, the composing handler, and the AUTH pillar step at `Stages::AUTH` with its HTTPS guard,
cross-origin suppression, 401 re-challenge replay and bearer token cache in both runtimes.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `AUTH-1`–`AUTH-28`, `AUTH-30`–`AUTH-38` | 37 |
| Implemented, with one clause satisfied by construction and no code — the marker-stripping clause is vacuous under §10.15; the suppression and HTTPS-guard-skip clauses are executable and are implemented | `AUTH-29` | 1 |
| **Total** | | **38** |

Design §12's `AUTH` row confirms the shape: "*Deferred:* none." `6c` is the only sub-phase of phase 6 with no
⏳ row of its own.

`6c` additionally ships, without owning a new ID: `AUTH-19`'s bounded per-nonce counter store as the second
consumer of phase 4a's `private_constant Dexpace::BoundedMap`, which is `XCUT-14`'s general rule getting its
third call site and phase 4a's stated anticipation of this phase.

### `DEF-35`'s fifteen: own checklist rows, not cross-references

**Decision: each of the fifteen gets its own row in `6a`'s checklist, naming the numbered `6a` plan task that
satisfies it, with its `RETRY` twin or twins carried as an annotation on the row rather than as its
disposition.** `DEF-35` left the choice open — "decides whether each is a separate checklist row or a
cross-reference to its twin" — and the answer is rows, on five grounds.

1. **A cross-reference cannot discharge what a checklist row is for.** `CLAUDE.md`: a checklist "names, for
   each requirement ID in scope, the numbered plan task that satisfies it — or records it as a deferral … or a
   deviation." A row reading "see `RETRY-9`" names a *requirement*, not a task. The question a checklist exists
   to answer — which task satisfies `RECOV-21`? — would then need one more hop and a re-derivation at the end
   of it, which is the failure mode the one-row-per-ID convention prevents.
2. **The fifteen are the work, not a pointer to it.** `DEF-35`: "This row adds the work of fifteen more on top
   of that 111 — the implementation of `RECOV-17`–`RECOV-30` and `RECOV-34`, which is this row's whole scope."
   An ID whose implementation this phase performs gets a row like any other.
3. **The mapping is not one-to-one and in three places it is a contrast rather than an identity.** `DEF-35`'s
   own table gives `RECOV-18 ↔ RETRY-5, RETRY-6, RETRY-7, RETRY-8` (one to four), `RECOV-24 ↔ RETRY-15,
   RETRY-19, RETRY-21` and `RECOV-30 ↔ RETRY-13, RETRY-14, RETRY-28`. And `RECOV-20`'s total-timeout budget
   pairs with `RETRY-27` while `RETRY-28` **forbids** the same budget on the other stack, so a bare
   cross-reference from `RECOV-20` would point at an ID pair that disagrees; `RECOV-25` pairs with a *clause
   inside* `RETRY-15` rather than with an ID at all. A cross-reference asserts an identity the mapping does not
   have.
4. **`DEF-35` forbids the reading a cross-reference row invites.** "none may be dropped on the grounds that the
   twin is satisfied, because the roadmap's phase-4 row states the range `RECOV-1`–`RECOV-34`." A row whose
   disposition is "satisfied via its twin" is that reading in table form.
5. **The precedent is two rows, one obligation, and both rows real.** Phase 2 gave `SEAM-29` that treatment and
   phase 3b gave `HTTP-46` the same. Here the two rows are already distributed across two phases: phase 4's
   fifteen stay ⏳ citing `DEF-35`, and `6a`'s fifteen are live rows naming `6a` tasks. Neither is a pointer at
   the other.

**No requirement ID moves and no phase-4 row changes.** `DEF-35`'s twin table is used verbatim and re-derived
nowhere; `6a`'s checklist copies the annotation column from it.

---

## Exclusions — IDs a reader would expect here, and the phase that owns each

| Excluded | Owning phase |
|---|---|
| `RECOV-1`–`RECOV-16` — the recovery **chain** the retry engine installs into | 4b, built. `Outcome`/`Success`/`Failure`, `Recovery::RequestChain`, `Recovery::ResponseChain`, `Recovery::Orchestrator`, `Recovery.buffer_error_body` |
| `RECOV-32`, `RECOV-33` — the idempotency-key and client-identity steps | 4b, built as `IdempotencyKeyStep` and `ClientIdentityStep`. `RECOV-31`'s attempt-ordinal header is a *third* header-stamping step and is **not** built (`DEF-5`) |
| `RECOV-31`, `RETRY-38` — the per-attempt ordinal header | Post-MVP. One feature under two IDs at two modal levels (§11.20); `DEF-5` and `DEF-6`. ⏳ rows in `6a`, never a budget line |
| `PIPE-2`–`PIPE-40` — the stage runtime, the cursor, the fork primitive, `Builder#install_preset` | 4c, built. Phase 6 installs steps into it and writes no second installation path |
| `PIPE-39`'s `standard` constructors, `PIPE-32`'s `redirect: :unsupported` | **6, phase-level** (`DEF-39`). Below |
| `CTX-11`, `XCUT-14` — the bounded-map implementation | 4a built it; phase 9 audits the general rule. `6c` is its second consumer |
| `CFG-15`–`CFG-21` — the clock, the cancellable wait, `Async.delay` | 5a, built. `6a` calls `Clock#sleep(duration, cancellation:)`; `DEF-35` moved `RECOV-27` here *because* this object is 5a's |
| `CFG-29`–`CFG-31` — RFC 1123 date formatting and parsing | 5a, built as `Dexpace::HTTPDate`. `RETRY-15`'s HTTP-date form consumes it and 5a never claims `RETRY-15` — `R1` below |
| `CFG-35`'s status half, `XCUT-5` | 5a, built as `Dexpace::Retryability.retryable_status?`. `6a` computes from it and builds no second classifier |
| `CFG-12`, `CFG-14` — the well-known configuration key names | 5a, built. `Keys::MAX_RETRY_ATTEMPTS` is the name; `RETRY-12`'s **values** are `6a`'s |
| `OBS-1`–`OBS-40` — the event object, the logger facade, the redactor, `Severity`, the span/tracer/meter SPIs, the `HTTPTracer` vocabulary | 5b and 5c, built. Phase 6 supplies emitters for two groups (`DEF-42`) and consumes `Redactor#url` for `REDIR-28` |
| `OBS-19` — the header-drop verbosity policy | 8 (`DEF-41`). Core raises rather than drops |
| `XCUT-5`, `XCUT-6`, `XCUT-7` — the baked flag, the open capability, the configurable set | 9 dispositions. `6a` builds the three objects the audit is about, and `XCUT-5`'s closing NOTE is what keeps them three |
| `XCUT-3`, `XCUT-9`, `XCUT-12`, `XCUT-16`, `XCUT-19`, `XCUT-21` | 9 dispositions. Phase 6 satisfies each by construction: `XCUT-3` through 5a's wait, `XCUT-9` through `Dexpace.each_cause`, `XCUT-12` through `AUTH-34`'s lock-free hot path, `XCUT-16` through `AUTH-28`'s guard, `XCUT-19` through 5b's redactor, `XCUT-21` through `SecureRandom` |
| `HTTP-48`, `HTTP-49`, `HTTP-50` — ETag, Range and the conditional-request aggregator | Still deferred (`DEF-2`). Its phase-1 sweep named phase 6 as the target; the condition does not fire — see the sweep below |
| `ASYNC-3`, `ASYNC-4`, `PIPE-33`'s interrupt clause | 8 marks all three (`DEF-18`, §10.5). Phase 6 meets the same prohibition at `RETRY-23`/`RETRY-26` and adds **no fourth** |
| `TRANSPORT-1`, `TRANSPORT-2` — an adapter disabling its native redirect and retry | 8. Phase 6 is the authority those two defer to; it opens no socket |
| `SEAM-11`, `SEAM-16`, `SEAM-17` — the transport and async seams | 2 and 8. `6a`'s async driver consumes `Dexpace::Async::Future#on_settle`, phase 2's, and replaces nothing |
| `BODY-1`–`BODY-5` — `#replayable?` and the three documented declines | 3b, built. `RETRY-5`, `REDIR-6` and `AUTH-31` are the three call sites and `Dexpace::Resilience::Resend.eligible?(request)` — the predicate 3b's own forward table names as phase 6's — is `6a`'s to write |

---

## Gap IDs: the two different fifteens, and the spec-reading budget

`ruby scripts/knowledge.rb --gaps RETRY,REDIR,AUTH,RECOV`, run 2026-09-09, reports (the trailing summary line
elided, the rest verbatim, so re-running it and diffing this block is not mistaken for drift):

```
RETRY — Retry and resilience
  45 canonical IDs: 45 substantive, 0 roll-up only, 0 uncited

REDIR — Redirect handling (HTTP 3xx following in the synchronous stage-based pipeline)
  28 canonical IDs: 28 substantive, 0 roll-up only, 0 uncited

AUTH — Authentication
  38 canonical IDs: 38 substantive, 0 roll-up only, 0 uncited

RECOV — Recovery-chain pipeline primitives
  34 canonical IDs: 19 substantive, 0 roll-up only, 15 uncited
  uncited (no entry in either tree names them):
    RECOV-17 RECOV-18 RECOV-19 RECOV-20 RECOV-21 RECOV-22 RECOV-23 RECOV-24 RECOV-25 RECOV-26 RECOV-27 RECOV-28 RECOV-29 RECOV-30 RECOV-31
  read these out of docs/product-spec/08-execution-pipelines.md
```

**Two fifteens, and they are different sets. Conflating them is the reading error this section exists to
prevent, and it is a second instance of the arithmetic hazard `DEF-35` warns about.**

- The **gap** fifteen is `RECOV-17`–`RECOV-31`: the IDs the corpus cannot answer.
- The **`DEF-35`** fifteen is `RECOV-17`–`RECOV-30` **and `RECOV-34`**: the IDs whose implementation lands here.
- The intersection is **fourteen** — `RECOV-17`–`RECOV-30`.
- `RECOV-31` is a gap and is **out of budget** (`DEF-5`). `RECOV-34` is in budget and is **not** a gap: it has
  substantive design-role entries drawn from `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md`
  §6.1 and §10.18, and design §12's `RECOV` row places it there. `OI-12` states the same asymmetry from the
  other side: "'the corpus cannot answer' and 'the specification cannot answer' are independent facts here, and
  `--gaps` measures only the first."

**The spec-reading budget, stated explicitly the way phase 4's design did.**

1. **Fourteen IDs are read out of appendix C directly** — `RECOV-17`–`RECOV-30`, rows 245–258 of
   `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`. Verified for this document:
   `docs/product-spec/08-execution-pipelines.md` §8.2 states `RECOV-1` through `RECOV-16` and stops, so the
   `--gaps` trailer's "read these out of docs/product-spec/08-execution-pipelines.md" is **unfollowable as an
   instruction**. That is `OI-12`, already filed, and phase 6 discharges the *reading* without closing the
   *item* — the item is about the derivation, and any fix belongs to `--gaps`, not to a phase.
2. **The reading is cheap because chapter 09 states the same rules in prose under IDs it can read.** `DEF-35`'s
   twin-by-twin table is what makes that true, and it was derived and verified by the phase-4 segmentation
   design against appendix C. `6a` reads `docs/product-spec/09-retry-and-resilience.md` in full (36 lines) and
   the appendix-C canonical text of all 45 `RETRY` IDs and the fifteen `RECOV` ones. **Budget: one focused
   pass, not a research task** — which is the sense in which `OI-12`'s "the reading budget the roadmap asks a
   phase to plan for therefore largely transfers with the work" holds.
3. **`6b` and `6c` budget no appendix-C-only reading at all.** Verified 2026-09-09: every one of
   `REDIR-1`–`REDIR-28` and `AUTH-1`–`AUTH-38` appears in its own prose chapter, and `--gaps` prints no "read
   these out of …" line for either prefix. `REDIR-25` appears in chapter 10's introduction rather than as a
   §10.1–§10.4 bullet, which is a formatting fact and not a gap.
4. **All three chapters are short and all three were read in full for this document** (36, 28 and 28 lines),
   together with the `*Conformance:*` clauses appendix C does not carry. Several of those clauses are
   load-bearing and a sub-phase must not skip them — `RETRY-36`'s "a 503,503,200 sequence must terminate on the
   200" is the only statement anywhere of what the re-classification loop is *for*.

---

## Convergence points — what needs two sub-phases, and what does not

A convergence point is a **test or a constructor that cannot be written until two segments exist**. It is not a
build-order dependency, and a plan that treats it as one has re-imposed the chain the split existed to avoid.
There are exactly three.

1. **The end-to-end cross-origin credential-leak test needs `6b`'s real REDIRECT step and `6c`'s real AUTH
   step.** Until both exist, each side asserts against phase 4c's probes: `6b` installs a probe AUTH step that
   records what `cursor.state(Stages::REDIRECT)` gave it; `6c` installs a probe REDIRECT step that forks with
   the marker set and unset. Those are complete tests of each half. **The end-to-end test — a seed origin, a
   `Location` to a foreign host, a real credential configured, and an assertion that no `Authorization` reaches
   the second transport — is owned by whichever of `6b` and `6c` lands second**, and both designs must name it
   so it cannot be dropped by each assuming the other wrote it. Under the recommended order that is `6c`.
2. **`RETRY-14`'s budget-equivalence test spans `6a`'s two stacks and nothing else.** It is a convergence point
   *inside* `6a` and therefore an ordering constraint in one plan, named here only so it is not mistaken for a
   cross-segment one.
3. **`DEF-39`'s `Pipeline.standard` needs `6a` + `6b` + phase 5b's instrumentation step, and never `6c`.**
   `PIPE-39` names the sync preset "redirect+retry+instrumentation" and the async one "retry+instrumentation
   with a caller-supplied scheduler for non-blocking backoff". **Auth is in neither.** That is what makes it a
   phase-level task rather than a sub-phase's, and it is treated as one below.

**What is *not* a convergence point, stated because a plan will reach for it.** `AUTH-27`'s "redirect wraps
retry wraps auth" needs no coordination: it is `PIPE-2`'s stage order, fixed in 4c's frozen `Stages::ALL` table
and asserted there. A `6c` test that installs a real redirect and a real retry step to observe the nesting is
testing phase 4c's code, not phase 6's.

---

## Phase-level tasks owned by no sub-phase

Three items belong to phase 6 and to no single segment. Each is named with the sub-phase that **executes** it,
because "owned by no sub-phase" is how a task gets built twice or not at all.

### `DEF-39` — `Pipeline.standard` and `AsyncPipeline.standard`

**Executed by whichever of `6a` and `6b` lands second; under the recommended order, `6b`.** `DEF-39`'s pick-up
condition names "phase 6, the first phase in which all three families exist", and requires the two constructors
to be written **over** `Builder#install_preset` with no second installation path. `PIPE-24`'s
validate-then-commit semantics ship already and are tested; what phase 6 adds is a step set and two names, plus
the explicit `redirect: :unsupported` argument design §5.3 specifies on the async one so `PIPE-32`'s asymmetry
is visible at the call site.

Two consequences the executing sub-phase must carry:

- **`REDIR-25`'s substantive clause stops being vacuous the moment this lands.** Until now there is no async
  standard pipeline for it to be true of. The `6b` row says so.
- **`PIPE-39`'s ⏳ row in phase 4c's checklist closes here**, and `DEF-39`'s status becomes picked-up.

### `DEF-42` — `OBS-29`'s per-attempt emitter, and where the operation triple cannot go

**The per-attempt half is executed by `6a`.** `OBS-29`'s three per-attempt events — attempt started, attempt
failed with next delay, retries exhausted — are `Dexpace::Instrumentation::HTTPTracer#attempt_started`,
`#attempt_failed` and `#retries_exhausted`, shipped by 5c as no-ops on a frozen `NULL` instance with a
`CallableAdapter` bus and an ordering test. `6a`'s retry step is the emitter, and `OBS-29`'s ordering clause —
"retries-exhausted (when it fires) is immediately followed by operationFailed with the same throwable" — is the
regression 5c's test already guards.

**A finding that constrains how the rest of `DEF-42` can ever be picked up, and it is new here.** `DEF-42`
says the operation-lifecycle triple was not wired in phase 5 because "it needs a third slot on `5b`'s
instrumentation step, which the phase-5 charter's boundary 15 does not grant". Verified for this document:
5b's `Dexpace::Instrumentation::Step` **declares `#stage` returning `Stages::LOGGING`** and is installed with
no `stage:` argument, and 4c rejects with `Dexpace::PipelineError` any install that supplies a different
`stage:` for a step that declares one. `Stages::LOGGING` is order **1100**, which is *inside* `REDIRECT` (200),
`RETRY` (500) and `AUTH` (800). **So once phase 6's three pillars are installed, a step at `LOGGING` runs once
per redirect hop, per retry attempt and per auth replay — and an operation-scoped triple emitted from there
fires many times per operation, which is the opposite of `OBS-29`'s "One tracer instance corresponds 1:1 to a
single logical operation lifecycle."** The route `DEF-42` names is therefore unavailable in exactly the phase
its pick-up condition targets. The site that works is `Stages::PRE_REDIRECT`, order 100 — `PIPE-2`'s outermost
slot, which 4c states is "outside every pillar's fork, so a step there is invoked once", and which `PIPE-37`
already reserves for steps whose correctness depends on observing only the single terminal response. That is a
**new step**, not a third slot on an existing one. This document does not decide whether phase 6 ships it; it
records that `DEF-42`'s stated mechanism does not work and files the finding (below). `6a` decides, and `R15`
is where.

### `OI-31` — the instrumentation step's first slot-precedence clause

**Decision: widen `Dexpace::Pipeline::Cursor`. Executed by `6a`.** The full argument is the next section.

---

## `OI-31`: widening the cursor, and what depends on it

`OI-31` (opened 2026-09-09, `docs/open-items.md:1341`) records that the reconciled `5b`/`5c` contract resolves
the instrumentation step's tracer factory and meter in three clauses — "the request context's instrumentation
bundle when it is not `Bundle::NONE`, else the step's constructor keyword, else the constant" — and that **the
first clause has no implementation path**, because nothing in the shipped surface lets a pipeline step reach a
`RequestContext` or an `Instrumentation::Bundle`. It names two candidate resolutions and assigns the choice to
phase 6, adding: "Whichever it picks, `bundle_for` in `5b`'s step is the one method that changes."

**Candidate (b) — have `Pipeline.standard` (`DEF-39`) thread a bundle in at construction — is rejected on the
merits, not merely on reach.** `CTX-14` requires the bundle to be carried by a **context**, and `CTX-20` calls
its factory "per-operation … because operation starts are not serialized"; `OBS-23` has span activation push a
trace id and a span id onto the diagnostic context. Every one of those is per-operation. A bundle supplied to
`Pipeline.standard` is fixed at pipeline construction and is therefore **per-pipeline**: shared by every call
that pipeline ever serves. It cannot carry a per-request span or trace id, so it is not the object clause 1
names. What it actually is, is clause 2 under a second name — a default the step could equally have taken as
its own keyword — and choosing it would leave clause 1 permanently dead **including for the preset**, which is
the opposite of what `OI-31` asks phase 6 to fix. The main session's stated objection (it leaves the clause
dead for anything not built from the preset) is right and understates the case.

**Candidate (a) — widen `Cursor` — is right, and this document states it completely, because as `OI-31` words
it the producer side is missing.** The resolution is two additive changes:

- a read-only `Cursor` accessor for the per-call instrumentation bundle, carried across `#fork` exactly as
  `#request` and `#options` are (`PIPE-16`, `PIPE-17`);
- one optional keyword on the pipeline's own call path that seeds it, defaulting to
  `Dexpace::Instrumentation::Bundle::NONE`.

Four supports:

1. **`PIPE-11` names the cursor as the home and rules out every alternative.** "Per-request mutable state MUST
   live in the per-call cursor (carried and forked by next), never on the step." `OI-31` itself uses that
   sentence to close off the ambient-storage route; the same sentence is a positive argument for the cursor.
   `CTX-13` closes the `ContextStore` back door.
2. **The bundle is a frozen `Data` and rides like the options.** Nothing about it needs mutation, so `PIPE-17`'s
   "share the immutable per-call options" shape applies unchanged and the fork semantics are already tested.
3. **Both halves are widenings.** `api-design/1d9e6e0b` makes adding an optional keyword a non-breaking change
   and `NFR-4` locks only signatures that "disappear or narrow"; adding a reader widens. 4c's own precedent is
   explicit: `Cursor#spent?` and `#may_fork?` have no caller in `lib/` and were shipped anyway (`P4-27`).
4. **It makes the clause live for every pipeline shape**, hand-built and preset alike, which is the property
   (b) structurally cannot have. `OBS-34`'s and `XCUT-19`(e)'s default — no tracer, no meter, level `none` —
   remains what a caller who passes nothing gets, so no phase-5 assertion moves.

**Against it, honestly.** 4c states outright that "4c does not consume 4a at all", and this widening makes
`Dexpace::Pipeline` name a `Dexpace::Instrumentation::` constant for the first time. That is a real change to a
committed position and it is why the change is a **named task with one owner** rather than something a
sub-phase does in passing. It is not a breach: 4c's position is about what 4c built, not a prohibition on later
phases, and roadmap obligation 1 binds phase 5 — not phase 6 — from redefining the bundle. **Phase 6 adds no
`Bundle` member, renames nothing, and replaces no published singleton**, which is the substance of the
obligation either way.

**Owner: `6a`**, as a self-contained task. `6b`'s `REDIR-28` emitter and `6c` consume the reader **if it
exists** and each ships its own constructor keyword regardless, so neither blocks on `6a` and neither
re-implements it. If the sub-phases run out of the recommended order, the task travels with whichever runs
first, and both other designs state that they consume it and do not build it — `R13`.

**What `6a`'s `DEF-42` emission task depends on, stated because it is easy to get backwards.** It depends on
5c's `Dexpace::Instrumentation::HTTPTracer`, its frozen `NULL` instance and the `CallableAdapter` bus, and on
the retry step's own `http_tracer:` constructor keyword. **It does not depend on this widening, on
`Pipeline.standard`, or on `6b` or `6c`.** `OI-29` is why: `CTX-14`'s `Bundle#tracer_factory` produces **span**
tracers and is legitimately shared or cached, while `OBS-29`'s factory produces **HTTP-tracers** — `OBS-28`'s
eleven-method event vocabulary — and is legitimately per-operation. They are two different kinds of object, so
a widened cursor carrying a `Bundle` does not supply `6a`'s emitter and `6a` must not read the emitter off
`Bundle#tracer_factory`. Phase 6 is the first phase that needs them distinguished, exactly as `OI-29` predicted,
and `R3` is where `6a` decides what the separate HTTP-tracer slot is.

---

## `DEF-40`: picked up and closed in `6a`

**Decision: agreed with the prior reading. `DEF-40` is picked up in `6a` and the row closes there.** The
argument, from `DEF-40`'s and `CFG-35`'s own text rather than from convenience:

- **What is deferred is a method, and `6a` writes it.** `DEF-40`'s scope is "the second clause of `CFG-35`
  (SHOULD) — 'and SHOULD treat a throwable as retryable iff it or any throwable in its cause chain is an
  IO/timeout error. Cause-chain traversal MUST be cycle-safe.'" Its pick-up condition is "phase 6, with
  `XCUT-6`'s retryability capability and `RETRY-1`". `RETRY-2` is the same clause at MUST level and is a
  phase-6 ID: "The set of retryable throwables MUST be defined in exactly one place: any throwable that IS, or
  has anywhere in its cause chain, an I/O error or a timeout error." `6a` cannot satisfy `RETRY-2` without
  writing the very method `DEF-40` defers, so the row is discharged by `6a` whether or not anyone says so.
- **The mechanism is already fixed and needs nothing from phase 8.** `XCUT-6` requires the classifier to query
  "the **capability** (is-Retryable and the flag), not a concrete-type match", and design §6.1 gives the Ruby
  spelling: `error.respond_to?(:retryable?) && error.retryable?`, walked over `Dexpace.each_cause`, which is
  phase 4b's and is already cycle-safe by reference identity (`XCUT-9`). `CFG-35`'s cycle-safety clause needs
  no second implementation — `DEF-40` says so itself.
- **Phase 8's `Dexpace::TransportError` supplies an instance of the capability, not the other half of the
  obligation.** `DEF-40` calls it "the other half" and the sentence is easy to over-read. Read in place, it is
  the other half of the *demonstration* — "which is exactly the mechanism that lets
  `dexpace-transport-net_http` declare `Errno::ETIMEDOUT` retryable without core naming it". A classifier that
  queries a capability is complete when the query exists; an error class that answers it is an ordinary use of
  an extension point, and by that standard the row could never close, because a new adapter could always define
  one more. `XCUT-6`'s whole point is that adding such a class requires "**without editing the retry
  classifier**".
- **Nothing else in the row is outstanding.** Its `NFR-4` clause — "Adding a method **widens**, which `NFR-4`'s
  'disappears or narrows' lock permits, so shipping the status half alone now prejudices nothing" — is about
  phase 5a's position, not about a phase-6 obligation.

**One residual, recorded rather than hidden.** A capability-only classifier has a stated blind spot: a bare
`Errno::ETIMEDOUT` or `SocketError` that escapes an adapter *without* being wrapped in something answering
`#retryable?` is classified not-retryable. `DEF-40` verified that the alternative is worse — an
`is_a?(::IOError)` classifier would mark phase 3a's `Dexpace::StreamError` retryable and a connection timeout
not retryable, "wrong in both directions" — and `RETRY-4` is satisfied from the other side, because design §6.1
gives `XCUT-4`'s transport-error branch the flag by default. The residual is therefore an **obligation on phase
8's adapters to wrap**, and it is a candidate deviation for `6a`'s ledger rather than a defect. `R4` is where
`6a` argues it.

**Consequence for the checklists.** Phase 5a's `CFG-35` row stays ⏳ citing `DEF-40` with its met half named,
and `6a` carries a `CFG-35` row of its own outside its 60-ID budget, the same inherited-row treatment as the
⏳ rows. `DEF-40`'s status moves to picked-up and the row closes when that row lands. **`OI-21` closes with
it**: 5a's `R1` supplied the cross-reference from the phase-5 end — "the status classifier is phase 5's and
lives in `Dexpace::Retryability`, phase 6 computes `DEF-38`'s baked `#retryable?` from it rather than building
a second one" — and `6a` supplies the phase-6 end when it does exactly that. Nothing about `OI-21` is re-opened
here.

---

## Prerequisites, and the decisions phase 6 inherits

Every surface below was verified to exist and to be stated as shipping by the named phase's design, on
2026-09-09. **A sub-phase design must not cite one this document did not verify**, and three items the prior
research assumed do **not** exist — they are flagged inline.

**From phase 0** — the seventeen blocking gates, unchanged. Three bite here: `gates:require_allowlist` (core
may `require` only `monitor`, `uri`, `stringio`, `strscan`, `time`, `date`, `securerandom`, `digest`,
`openssl`, `forwardable`, `set`, `singleton` — **`digest`, `securerandom` and `openssl` are already on it, so
phase 6 needs no allowlist diff**), the denylist (`base64` by name, with the reason attached), and the
`Dexpace/NoUriDefaultParser` and `Dexpace/NoTimeParse` cops.

**From phase 1** — `Dexpace::URL.parse!(input)` (parses with `URI::RFC3986_PARSER`, **rejects a
non-absolute URI**, converts `URI::InvalidURIError` into a `Dexpace::InvalidArgumentError` carrying the input)
and `.external_form(uri)`. `Dexpace::Request`, `Response`, `Headers`, `RequestOptions`, `Status`, `Method`,
`HeaderName` and their builders.

**From phase 2** — `Dexpace::Cancellation` (`.none`, `.source`, `.over`, `.any`, `#cancelled?`, `#reason`,
`#check!`, `#on_cancel` returning a `Cancellation::Subscription` with `#detach`) and
`Cancellation::Source#off_cancel`; the async pivot as **`Dexpace::Async::Future`, `Dexpace::Async::Completer`
and `Dexpace::Async::Settlement`** — *not* `Dexpace::Future`/`Dexpace::Completer`, which is a correction to the
prior research — with `Future#on_settle`, `#value(cancellation:)`, `#wait`, `#cancel` and
`Completer#fulfil`/`#fail`/`#await`/`#request_cancel`.
**`Dexpace::Hooks` is a `private_constant` with no `sig/` mirror and no manifest row — phase 6 cannot cite it
as an interface surface**, which is a second correction.
**And phase 2 ships no `URI::RFC3986_PARSER`-pinned join or merge helper, which is the third and the largest.**
Deviation `P2-3` and addendum `A1` record that `SEAM-27`'s base-URL composition is hand-built inside
`Operation#build_request` precisely *because* `URI::RFC3986_PARSER.join` and `URI::Generic#merge` drop the base
path segment and the base query. **`REDIR-13`/`REDIR-14`'s reference resolution is `6b`'s own work and there is
no module to call** — what phases 0 and 2 supply is the *spelling* (`URI::RFC3986_PARSER.join`) and the cop
that enforces it. `url-and-query-encoding/08c54234` says this in as many words, naming phase 6, and adds that
the semantics *are* right for a redirect target because "a redirect target genuinely is a reference resolved
against the previous URL" — which is the distinction between `SEAM-27`'s concatenation and `REDIR-14`'s
resolution.

**From phase 3** — `#replayable?` on the `Dexpace::Body` module, defaulting to `false`, with `#to_replayable`
beside it (3b's, not 3a's); `Dexpace::StreamError < ::IOError`; `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES`
(1 MiB, **3b's constant**, not `Recovery`'s); `Response#close`. 3b's forward table already names the predicate
phase 6 writes over `#replayable?`: **`Dexpace::Resilience::Resend.eligible?(request)`** — "3b ships the
`#replayable?` property the three consult and the documented decline behaviours; it builds no gate and no
predicate." That name is `6a`'s to confirm or change, and `6b`'s `REDIR-6` and `6c`'s `AUTH-31` are its other
two callers.

**From phase 4a** — `private_constant Dexpace::BoundedMap` with `.new(cap:)`, `#set`, `#put`, `#[]`,
`#delete_if_identical`, `#size`; `Dexpace::Instrumentation::Bundle` (nine-member frozen `Data`, `.build`,
`#with`), `Bundle::NONE`, the public `NO_SPAN` and `NO_TRACER_FACTORY`; `Dexpace::ContextStore` and
`MAX_TRACKED_CONTEXTS`.

**From phase 4b** — `Dexpace::Outcome` with `Success` and `Failure` (`.build`, `#success?`, `#failure?`,
`#response_or_nil`, `#error_or_nil`, `#fold`); `Recovery::RequestChain` and `Recovery::ResponseChain`
(`.build`, `#apply`); `Recovery::Orchestrator.build(transport:, request_chain:, response_chain:)` with
`#call(request, options, cancellation)`, which **is** a `Dexpace::Transport` by phase 2's duck type and is
**not** a `PIPE` runtime; `Recovery.buffer_error_body(response)`; `Dexpace::ProtocolError` with `.for` and
`.for_or_nil` and **no `#retryable?`** (`DEF-38`); `Dexpace::Suppressible`, `Dexpace.attach_suppressed`,
`Dexpace.suppressed`; `Dexpace.each_cause`; the `RECOV-2` fatal-family passthrough — `rescue ::StandardError`
converts, `rescue ::Exception` re-raises unchanged with no trail, which is `RETRY-25` already implemented.
`Recovery::Transform` takes **one** argument (`#apply(value)`), never `#call(request, cursor)`.

**From phase 4c** — `Dexpace::Pipeline` (`.builder`, `.direct`, `#call`, `#steps`, `#entries`, `#transport`,
`#close`); `Dexpace::AsyncPipeline` (`.direct`, `.map_response`, `#call` returning a `Dexpace::Async::Future`);
`Pipeline::Builder` with the ten surgical edits, `#reload` and `#install_preset`; `Pipeline::Cursor`
(`.build`, `#call`, `#fork(state:)`, `#may_fork?`, `#request`, `#options`, `#cancellation`, `#state(stage)`,
`#spent?`); `Pipeline::Stages` with sixteen constants, `ALL`, `PILLARS` and `.of`; `Pipeline::TransformStep`,
which declares **no** `#stage`. The step duck type is `#call(request, cursor) -> Response` (or `-> Future`),
`Step.conforms?` is arity-based, `include Dexpace::Pipeline::Step` is neither required nor meaningful, and
**`#stage` is read once at install with a four-row precedence table — a step that declares nothing and is
installed with no `stage:` is rejected.** Phase 6's three pillar steps declare `#stage`.

**From phase 5a** — `Dexpace::Clock` (`#now`, `#monotonic`, **`#sleep(duration, cancellation: nil)`**) and
`Clock::SYSTEM`, plus `Clock.deadline_in`; `Dexpace::Async.delay(duration) -> Async::Future` **which raises
`Dexpace::SeamError` when `Fiber.scheduler` is `nil`** (deviation `P5-9`) — so `6a`'s sync backoff cites
`Clock#sleep` and only the async driver reaches for `Async.delay`; `Dexpace::HTTPDate.format`/`.parse` (an
owned anchored grammar, `P5-12`) — **5a never claims `RETRY-15`**, verified by grep over `docs/work/mvp/phase5/`,
so `6a` consumes `HTTPDate` and asserts `RETRY-15`'s tolerances against it (`R1`);
`Dexpace::Retryability.retryable_status?`; the configuration chain (`Dexpace::Configuration` with `#string`,
`#integer`, `#boolean`, `#duration`, `#derive`, `Configuration::Keys`, `Configuration::Sources`,
`Dexpace.configuration`) and `Keys::MAX_RETRY_ATTEMPTS` — **the name only; `RETRY-12`'s 200 ms / ×2 / 8 s / 0.2 /
3-sends values are phase 6's**.

**From phase 5b and 5c** — `Dexpace::Instrumentation::Step` and `::AsyncStep` at `Stages::LOGGING`, built with
`logger:`, `redactor:`, `level:`, `tracer_factory:`, `meter:`, `preview_bytes:` and `clock:`, whose private
`bundle_for` is `OI-31`'s seam; `Dexpace::Instrumentation::Redactor` (`#url`, `#header_value`, `#header_name?`,
`MALFORMED_URL`, `REDACTED_VALUE`, `REDACTED_USERINFO`, `REDACTED_HEADER`, `RELATIVE_MARKER`) and
`Redactor::DEFAULT`; `Dexpace::Instrumentation::Severity` with `ERROR`/`WARNING`/`INFO`/`VERBOSE`, `ALL` and
`.of`; `Instrumentation.contain`, the `Logger` facade and the `Keys`/`Events` vocabularies;
`Dexpace::Instrumentation::HTTPTracer` (eleven no-op methods across `OBS-28`'s three groups), its frozen `NULL`
instance, and `CallableAdapter`. **`interface _HTTPTracer` is deliberately not declared** in 5c's RBS, which
phase 6 inherits as a shape decision.

**The independence statement each sub-phase design must make in its own Prerequisite section.** For every one
of the three, the *real* dependencies are on phases 0–5 in the list above; the dependency on the other two
sub-phases of phase 6 is **empty**, with the single exception of `OI-31`'s cursor widening, which `6b` and `6c`
consume if present and neither requires. Anything else a plan schedules behind another sub-phase is
convenience.

---

## Cross-cutting constraints that bite phase 6 specifically

- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** `AUTH-24` requires the Digest nonce counter to
  yield "correct, non-duplicated counts" under concurrent reuse of one server nonce, and `AUTH-34`/`XCUT-12`
  require a wait-free hot-path read of a valid cached token with single-flight refresh. Design §6.3 fixes both:
  the counter increments under a `Thread::Mutex`; the bearer hot path reads one frozen token object from an
  instance variable **without** taking a lock, safe by publication rather than by the GVL, so it holds on JRuby
  and TruffleRuby. `XCUT-12` explicitly sanctions holding the scoped lock across a blocking token fetch —
  which is the one place in this repository where holding a lock across a suspension point is intended, and it
  is scoped per-credential so it can never serialise unrelated requests.
- **Bytes on the wire are `Encoding::BINARY`; `downcase` is called with no arguments.** `HTTP-13`'s rule and
  the `Dexpace/NoLocaleCaseFold` cop bite in three places here: `REDIR-8`'s host comparison, `AUTH-12`'s
  scheme/param-name normalisation, and `AUTH-14`/`AUTH-16`'s case-insensitive scheme acceptance.
- **Regexp timeouts are per-pattern, never the process-global `Regexp.timeout`.** Design §6.3 keeps the
  challenge parser a character-level state machine rather than a regexp, "both because the grammar is not
  regular and because a hostile `WWW-Authenticate` should not be able to drive a backtracking engine" — so the
  constraint is discharged by not writing the regexp. `6b`'s `Retry-After` decimal screen and `6a`'s pacing
  grammar are the places a pattern does appear, and both are anchored.
- **An `Enumerator` abandoned mid-`#next` never runs its `ensure`.** Nothing in phase 6 puts a resource inside
  an `Enumerator` block; `Dexpace.each_cause`'s block-less form returns one, and `6a` uses the block form.
- **Deadlines are explicit values, not ambient interrupts.** `RECOV-20`'s total-timeout is threaded as a value
  and clamped per attempt; `RETRY-27`'s "per-attempt deadline shrinking" is arithmetic, not an interrupt.
- **`Ractor` is never load-bearing.** `RETRY-42` and `AUTH-7`/`AUTH-24` require immutable, stateless,
  concurrently-safe policy objects — which phase 6 gets from `Data` and frozen constants, exactly as phase 4
  did, with Ractor-shareability a free side effect and no part of the claim.

---

## Verified Ruby facts that shaped this cut

All verified on **3.4.10** (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`), the only
interpreter available to this document. **Where a fact needs the 3.2 floor or the 4.0 column to be load-bearing,
that is said rather than assumed** — the sub-phase designs run the three-interpreter check this document could
not.

1. **`URI::Generic#userinfo = nil` is a silent no-op, and it is the obvious spelling of `REDIR-12`.** Measured:
   parsing `https://user:pass@ex.com/p`, assigning `userinfo = nil` and rendering gives back
   `"https://user:pass@ex.com/p"` — the credential survives. Confirmed at source in `uri/generic.rb`: the
   writer opens `if userinfo.nil? then return nil`, before `check_userinfo` and `set_userinfo` are ever
   reached. What *does* clear both fields: `#user = nil`, `#userinfo = ""`, or building a fresh URI. And
   `set_userinfo` is **protected**, so the third obvious route needs a `send`. `REDIR-12` says "server-supplied
   embedded credentials MUST never be used"; the spelling that reads as satisfying it forwards them. **This is
   `6b`'s knowledge note to file with the design that acts on it**, and `6b`'s `REDIR-12` test must assert on
   the rendered URL rather than on `#userinfo` being `nil`.
2. **`URI::RFC3986_PARSER.join` preserves already-percent-encoded octets, bracketed IPv6 literals and explicit
   ports byte-for-byte.** `join("https://ex.com/a%2Fb/c?x=%26y#f", "/d%2Fe?q=%2Bz")` yields
   `"https://ex.com/d%2Fe?q=%2Bz"` with `%2F` and `%2B` intact; `join("https://[2001:db8::1]:8443/p", "/q")`
   yields `"https://[2001:db8::1]:8443/q"`. That is `REDIR-13`'s "re-encoding that would decode `%2F`→`/` or
   `%26`→`&` is forbidden" satisfied by not round-tripping through a re-rendered string, which is design §6.2's
   claim.
3. **`URI` does not normalise host case, and does supply the effective port.**
   `URI::RFC3986_PARSER.parse("https://EX.com/").host` is `"EX.com"`; `.port` is `443` for `https://ex.com/`
   with no port written, `80` for `http://`, and `443` for an explicit `:443`. So `REDIR-8`'s "host
   (case-insensitive)" needs an explicit `downcase` and its "effective port (scheme default when omitted)" is
   free — which is exactly why design §6.2 specifies a constructed triple rather than `URI#==`.
4. **`Dexpace::URL.parse!` cannot parse a `Location` value.** It "rejects a non-absolute URI" by design
   (phase 1, `HTTP-47`), and `REDIR-14` requires a **relative** `Location` to be resolved against the current
   hop. `URI::RFC3986_PARSER.parse("/d%2Fe?q=%2Bz")` succeeds. So `6b` parses the reference with the pinned
   parser directly and converts `URI::InvalidURIError` itself — and per
   `url-and-query-encoding/08c54234` no test may match that error's message, because it differs by a space
   between 3.2.11 and 4.0.6. `R7`.
5. **`["u:p"].pack("m0")` returns a US-ASCII string and encodes the UTF-8 bytes of a non-ASCII credential.**
   `["alice:s3cr3t"].pack("m0")` → `"YWxpY2U6czNjcjN0"`; `["ü:pä"].pack("m0")` → `"w7w6cMOk"`, encoding
   `US-ASCII`. `AUTH-14` asks for "base64(UTF-8 of `username:password`)" and this is it, with no `base64`
   require and a header-safe result encoding.
6. **`String#encode("ISO-8859-1")` raises on an unmappable character.** `"pä".encode("ISO-8859-1")` gives
   bytes `[112, 228]`; `"日".encode("ISO-8859-1")` raises `Encoding::UndefinedConversionError`. `AUTH-21`
   requires ISO-8859-1 hash-input encoding whenever a challenge does *not* advertise `charset=UTF-8`, so the
   default Digest branch is a **raising** path on a credential the caller legitimately supplied. `6c` decides
   the disposition — `:replace`, a typed failure, or a documented raise — and `R10` is where.
7. **`Digest::MD5.hexdigest` and `Digest::SHA256.hexdigest` return lower-case hex**, which is `AUTH-17`'s
   requirement satisfied by the default; and `format("%08x", n & 0xFFFFFFFF)` renders `AUTH-18`'s "exactly 8
   lower-case hex digits using the low 32 bits on overflow", wrapping `0x100000001` to `"00000001"`.
8. **`digest`, `securerandom`, `openssl`, `uri` and `time` are all absent from `Gem::BUNDLED_GEMS::SINCE` on
   3.4.10**, consistent with phase 0's allowlist. **Phase 0 verified the 4.0.6 column and this document did
   not**; the allowlist's category assertion is the gate that keeps it true, and phase 6 relies on that gate
   rather than on this measurement.
9. **`NoMemoryError` and `SystemStackError` are outside `StandardError`** (both `< Exception` directly), which
   is 4b's verified fact 9 re-confirmed here because `RETRY-25` is `6a`'s row: "non-recoverable runtime errors
   … MUST NOT be retried, classified retryable, or logged; they MUST be surfaced unchanged with no
   suppressed-trail attachment." 4b's `rescue ::StandardError` / `rescue ::Exception` split already implements
   it, so `6a`'s row cites 4b's code rather than adding a second guard.

---

## Deferrals filed by phase 6

**None, and that is deliberate.** A segmentation design decides a cut; it does not decide the interfaces whose
absence a deferral records. Phase 4 filed `DEF-35` only because it was a **scope disposition** — an entire ID
cluster moving to another phase. Phase 6 has no such candidate: every ID in its scope is implemented here or
already carries a pre-existing row (`DEF-5`, `DEF-6`, `DEF-7`).

**Two rows are expected of the sub-phases** and are named in the risks so their absence later is visible:
`6a`'s disposition of the async trampoline under an absent `Fiber.scheduler` (`R2`), and `6a`'s disposition of
the operation-lifecycle group of `OBS-29` if it declines the `PRE_REDIRECT` step (`R15`).

### Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every row. All
forty-two were read. As with phases 3, 4 and 5, this document **states** each disposition and the sub-phase
**performs** the register edit.

**Phase 6 picks up six rows, closes three of them outright, leaves three deferred with a correction owed to
one, and files none.**

- **`DEF-35` — picked up and CLOSED, by `6a`.** Its pick-up condition names "phase 6 … with `RETRY`'s two
  stacks and the one shared calculator". `6a` implements `RECOV-17`–`RECOV-30` and `RECOV-34` and carries a row
  for each; phase 4's fifteen ⏳ rows stay as they are, which is what "no requirement ID moves" means. Status
  moves to picked-up and the row closes when `6a`'s checklist lands.
- **`DEF-38` — picked up and CLOSED, by `6a`.** "The attachment point already exists and the work is one
  method: add `#retryable?` to `Dexpace::ProtocolError`, computed once at construction from the classifier
  phase 6 builds for `RETRY-1`, and add **no** second protocol-error type." Amended by 5a's `R1`: the
  classifier is 5a's `Dexpace::Retryability` and `6a` computes from it rather than building one. Phase 4b's
  `XCUT-5` row closes with it.
- **`DEF-40` — picked up and CLOSED, by `6a`.** Argued in full above.
- **`DEF-42` — picked up, NOT closed, by `6a`.** The per-attempt group gets its emitter here; the five
  transport milestones wait for phase 8's first adapter, which the row already says. **The row also needs a
  correction**: its stated route for the operation-lifecycle triple — a third slot on 5b's step — is
  unavailable, because that step is pinned to `Stages::LOGGING`, which sits inside all three phase-6 loops.
  Filed as a finding below.
- **`DEF-39` — picked up, by the phase-level task above.** Its condition — "phase 6, the first phase in which
  all three families exist" — is met the moment `6a` and `6b` have both landed. `PIPE-39`'s ⏳ row in phase
  4c's checklist closes with it.
- **`DEF-2` — stays deferred, and its target phase needs restating.** Phase 1's register sweep gave it "target:
  phase 6 … that is where the helpers first get a caller, because a re-issued request carries
  `If-Match`/`If-None-Match` (`HTTP-50`'s aggregator) and an entity-tag (`HTTP-48`)." **Phase 6 carries such a
  request; it does not construct one.** `REDIR-3`/`REDIR-4` preserve the original headers verbatim, `REDIR-5`
  removes `Content-*` and drops the body, and `AUTH-30`'s replay copies the request — none of the three builds
  a conditional header, parses an ETag or validates a Range. So `HTTP-48`–`HTTP-50` still have no caller when
  phase 6 ends. The row is **not UNSCHEDULED**, by the register's own definition — that status is for a row
  whose pick-up condition a phase met and declined to act on, and phase 6 does not meet the condition
  ("convenience helpers prioritized over minimal public surface"), it merely fails to fire it. The correction
  owed is to the *target*, not the status. Filed as a finding below.
- **`DEF-5`, `DEF-6`, `DEF-7` — untouched, and each gets a ⏳ row and no budget line.** `DEF-5` (`RECOV-31`) and
  `DEF-6` (`RETRY-29`, `RETRY-38`, `RETRY-43`) in `6a`; `DEF-7` (`REDIR-27`) in `6b`.
- **`DEF-18` — untouched.** `ASYNC-3` and `PIPE-33`'s interrupt clause are phase 8's; phase 6 meets the same
  §8.3 prohibition at `RETRY-23`/`RETRY-26` and adds no fourth unsatisfied MUST.
- **`DEF-25` — untouched.** Wire-boundary re-validation of header names and outbound values is phase 8's.
  `6c`'s stamped `Authorization` and `6b`'s re-issued headers are among the values it will re-validate.
- **`DEF-28`, `DEF-34`, `DEF-36`, `DEF-37`, `DEF-27`, `DEF-31`, `DEF-32`, `DEF-41` — untouched**, all either
  closed by phase 5 or targeted at phase 8.
- **`DEF-1`, `DEF-3`, `DEF-4`, `DEF-8`–`DEF-24`, `DEF-26`, `DEF-29`, `DEF-30`, `DEF-33` — untouched.** `DEF-4`
  (`PIPE-36`, pillar-step stage locking) is the one worth naming: phase 6 installs three pillar steps and does
  **not** lock a stage, which is the row's whole content, and nothing here changes its condition.

### The findings proposed for the registers

Three, described here for a human to file. **None is acted on by this document, none carries a number, and no
register file is edited by it.**

**Target register: `docs/open-items.md`.**
**`OBS-29`'s operation-lifecycle triple cannot be emitted from `Stages::LOGGING`, and `DEF-42`'s stated wiring
route is therefore unavailable in the phase its pick-up condition names.** `DEF-42` explains phase 5's decision
not to wire the triple as "it needs a third slot on `5b`'s instrumentation step, which the phase-5 charter's
boundary 15 does not grant" — a statement about a *slot*, which leaves the *stage* implicit. Verified
2026-09-09: 5b's `Dexpace::Instrumentation::Step` declares `#stage` returning `Dexpace::Pipeline::Stages::LOGGING`
and is installed with no `stage:` argument, and phase 4c rejects with `Dexpace::PipelineError` any install
supplying a different `stage:` for a step that declares one — so the step cannot be moved. `Stages::LOGGING` is
order 1100 and `REDIRECT`, `RETRY` and `AUTH` are 200, 500 and 800, so once phase 6's pillars exist a step at
`LOGGING` runs once per hop, per attempt and per auth replay. An operation-scoped triple emitted from there
fires many times per operation, contradicting `OBS-29`'s "One tracer instance corresponds 1:1 to a single
logical operation lifecycle". The site that satisfies the clause is `Stages::PRE_REDIRECT`, order 100, which 4c
states is "outside every pillar's fork, so a step there is invoked once" and which `PIPE-37` already reserves
for terminal-response-only steps — and that is a **new step**, not a slot on an existing one. Nothing is broken
today, because nothing emits the triple. It is the `OI-14`/`OI-27`/`OI-30`/`OI-31` family: a sentence that reads
correctly and resolves to something that is not there. Cites: `OBS-28`, `OBS-29`, `PIPE-2`, `PIPE-37`,
`DEF-42`, `OI-29`.

**Target register: `docs/deferred-items.md`, as an amendment to `DEF-2`'s pick-up condition.**
**`DEF-2`'s phase-6 target does not fire, and the row needs a new target or the event shape.** The
target was supplied by phase 1's register sweep on the reasoning that a re-issued request carries `If-Match`
and an entity-tag. Phase 6 carries such headers and constructs none: `REDIR-3` and `REDIR-4` preserve the
original headers, `REDIR-5` removes `Content-*` and drops the body, `AUTH-30` replays a caller-supplied
replacement. `HTTP-48`, `HTTP-49` and `HTTP-50` therefore still have no caller when phase 6 ends. The row stays
deferred — phase 6 does not *meet* the condition, so `UNSCHEDULED` does not apply by the register's own
definition — and what it needs is either a later target (phase 7's pagination and conditional-request
interplay is the next candidate) or the event shape `DEF-33` and `DEF-3`'s `BODY-36` half were given. Cites:
`HTTP-22`, `HTTP-48`, `HTTP-49`, `HTTP-50`, `REDIR-3`, `REDIR-5`, `AUTH-30`.

**Target register: `docs/open-items.md`, as a resolution on the existing `OI-31` row (not a new row).**
**`OI-31` is resolved by widening `Dexpace::Pipeline::Cursor`, owned by `6a`.** The full argument is the
`OI-31` section above; the resolution text a human writes into the row is: candidate (b) is rejected because a
bundle threaded at pipeline construction is per-pipeline and `CTX-14`'s bundle is per-operation, so (b) cannot
carry a per-request span and merely re-spells clause 2; candidate (a) is adopted as a read-only per-call
accessor on `Cursor` plus one optional seeding keyword on the pipeline's call path, both widenings under
`NFR-4` per `api-design/1d9e6e0b`, with `PIPE-11` naming the cursor as the home and `PIPE-17` giving the fork
semantics; `bundle_for` in 5b's step gains its first clause in the same task; and `6a`'s `DEF-42` emission task
does **not** depend on it, because `OI-29` establishes that `OBS-29`'s HTTP-tracer is not `Bundle#tracer_factory`.

**Two existing rows close as a consequence and are named so the closure is not lost.** `OI-21` closes when
`6a` computes `ProtocolError#retryable?` from 5a's `Dexpace::Retryability`, which supplies the phase-6 end of
the cross-reference 5a's `R1` supplied from the phase-5 end. `OI-29`'s resolution is decided by `6a` under
`R3`. Neither is re-opened or re-argued here.

**One row explicitly does not close.** `OI-12` is about the derivation — "`--gaps` could say 'appendix C only'
when the chapter does not carry the ID" — and phase 6 discharges the reading without touching the mechanism.

---

## Risks and open questions the sub-phase designs must resolve

Each is named with the sub-phase that owns it. **None is decided here.** Risk numbering restarts per phase in
this repository — phase 3's ran R1–R10, phase 4's R1–R14 and phase 5's R1–R15 — so phase 6's are `R1`–`R15` and
collide with neither.

**R1 — `6a`: whether 5a's `Dexpace::HTTPDate.parse` already accepts `RETRY-15`'s tolerances, and what happens
if it does not.** `RETRY-15` requires the HTTP-date form to be parsed "tolerant of an informational weekday and
single-digit day"; `CFG-30` asks for the same tolerances and 5a implemented them in an owned anchored grammar
(`P5-12`), but **5a never mentions `RETRY-15`** — verified by grep over `docs/work/mvp/phase5/`. Design §6.1
requires "one bounded-lenient RFC 1123 parser (shared with **CFG-29**–**CFG-31**)", so a second parser is
forbidden. `6a` asserts `RETRY-15`'s tolerance list against `HTTPDate.parse` and, if any is missing, **widens
5a's parser** (a widening, `NFR-4`-safe) rather than writing a second one, and records the widening.

**R2 — `6a`: the async trampoline with no `Fiber.scheduler`.** `RETRY-31` requires async backoff delays to be
"scheduled non-blockingly", and 5a's `Dexpace::Async.delay` **raises `Dexpace::SeamError`** when
`Fiber.scheduler` is `nil` (`P5-9`): "An application with no scheduler cannot call `Async.delay` at all."
Falling back to `Clock#sleep` would block, which `RETRY-31` forbids and `RETRY-26` forbids more strongly. Three
routes: require a scheduler at async-retry-step construction and fail loudly there; accept a caller-supplied
scheduler as `PIPE-39`'s async preset already anticipates ("a caller-supplied scheduler for non-blocking
backoff"), remembering that `RETRY-45` forbids the engine from ever shutting it down; or let the `SeamError`
surface at the first backoff. `6a` picks one and states what a zero-length delay does (`RETRY-31`: "a
zero-length delay completing inline and re-arming the active pump").

**R3 — `6a`: where the retry step's `HTTPTracer` comes from, and `OI-29`'s separate slot.** `OI-29` establishes
that `CTX-14`'s `Bundle#tracer_factory` and `OBS-29`'s per-operation HTTP-tracer factory are two different kinds
of object and says "a separate HTTP-tracer factory slot … is phase 6's to shape when it has an emitter". `6a`
decides whether the retry step takes an `HTTPTracer` instance, a factory, or a `CallableAdapter`-wrapped
callable, and whether `interface _HTTPTracer` — which 5c deliberately did not declare — is declared now.

**R4 — `6a`: `RETRY-2`'s throwable set as a capability-only query, and the blind spot that comes with it.**
Design §6.1 and `XCUT-6` fix the mechanism; `DEF-40` establishes that the concrete-type alternative is wrong in
both directions. The residual is that an unwrapped stdlib `Errno::ETIMEDOUT` or `SocketError` is classified
not-retryable. `6a` states this as a deviation candidate (`P6-<n>`), names the obligation it puts on phase 8's
adapters, and decides whether a `docs/first-release.md` line is owed.

**R5 — `6a`: `Dexpace::Resilience::Policy`'s visibility, and how it coexists with 5a's `Dexpace::Retryability`.**
Design §6.1 names the module and puts four things in it. `NFR-4` locks whatever is public; `api-design/b0e18938`'s
minimal-surface rule and `execution-context/b58728da`'s `private_constant` finding are the two inputs. `6a`
also confirms or changes 3b's forward-named `Dexpace::Resilience::Resend.eligible?(request)`.

**R6 — `6a`: one calculator, two budget policies.** `RETRY-28` forbids a total-timeout on the stage stack and
`RECOV-20`/`RETRY-27` require one on the recovery stack, with `RECOV-20` adding "a total-timeout of zero MUST
mean 'unbounded'". `6a` decides whether the budget is a parameter of the shared calculator that the stage
driver never sets, or a wrapper the recovery driver alone applies — and states which, because §11.19's
unification sanction is watching the answer.

**R7 — `6b`: the `Location` parsing route.** Phase 1's `Dexpace::URL.parse!` rejects a non-absolute URI
and `REDIR-14` requires relative resolution, so `6b` parses the reference itself with
`URI::RFC3986_PARSER`. It decides how `URI::InvalidURIError` becomes `REDIR-18`'s "logs it and returns the
current redirect response unfollowed" without ever matching the error's message
(`url-and-query-encoding/08c54234`), and how `REDIR-12`'s userinfo strip is spelled given verified fact 1.

**R8 — `6b`: `REDIR-28`'s emission site.** The redirect step sits at `Stages::REDIRECT` (200), outside 5b's
instrumentation step at `LOGGING` (1100), so it cannot borrow that step's logger. `6b` decides whether the
redirect step takes its own `logger:`/`redactor:` keywords defaulting to the no-op pair, and it makes the
`Redactor#url` ↔ `REDIR-28` linkage no phase-5 document states — including `REDIR-28`'s stated exception, the
malformed-`Location` event that logs the raw string because it cannot be redacted.

**R9 — `6b`: `REDIR-20`'s condition snapshot.** The predicate receives "a READ-ONLY, defensively-copied
condition snapshot (the current response, the count of redirects already followed, and an insertion-ordered set
of visited URIs including the current request's)". `6b` decides whether that is public `NFR-4`-locked API — it
is handed to caller code, so it probably must be — and how `REDIR-21`'s short-circuit ("SHOULD short-circuit
before allocating a condition snapshot") coexists with "a recognized 3xx always allocates the snapshot and
consults the predicate, even with no usable Location".

**R10 — `6c`: `AUTH-21`'s ISO-8859-1 branch is a raising path.** Verified fact 6. `6c` decides between
`:replace`, a typed `Dexpace::` failure naming the credential field, and a documented raise, and states what
the Digest test matrix asserts for each of the four algorithms.

**R11 — `6c`: the shape and lifetime of `AUTH-19`'s per-nonce counter store.** `execution-context/b58728da`
fixes the *reachability* condition (full nesting, bare reference). What it does not fix is whether the store is
per-handler or process-wide, and `AUTH-24` requires "concurrent reuse of one nonce still yields correct,
non-duplicated counts" while `AUTH-18` requires the count to restart at `00000001` per server nonce and
`AUTH-19` permits evicting a live nonce as harmless. `6c` states which, and whether `DEF-36`'s
configuration-source treatment applies to this cap too.

**R12 — `6c`: `AUTH-37`'s three-zone async policy against the pivot.** Fresh / expiring-but-valid / expired,
with a background refresh that must not block the dispatching thread and must be non-fatal when it fails. The
mechanism is `Dexpace::Async::Future#on_settle` (phase 2's), and the question `6c` must answer is what "kick
off an off-thread background refresh" means in a library that owns no thread pool and where `Async.delay` needs
a scheduler — including whether `AUTH-38`'s "SHOULD be delivered through the asynchronous channel" makes the
no-scheduler case a failed future rather than a synchronous raise.

**R13 — phase-level: who executes `OI-31`'s cursor widening if the sub-phases run out of order.** This document
assigns it to `6a`. If `6b` or `6c` runs first, the task travels with it and the other two designs state that
they consume the reader and do not build it. A design that silently re-implements it is the failure this risk
exists to name.

**R14 — phase-level: `DEF-39`'s two constructors, and the `PIPE-32` argument.** Written **over**
`Builder#install_preset`, never as a second installation path, with `redirect: :unsupported` on the async one.
The sub-phase that executes it decides the keyword names — which `NFR-4` locks the moment they ship — and
carries phase 4c's `R14` prohibition: "must not ship a preset that silently installs nothing while claiming to
install the defaults."

**R15 — `6a`: whether phase 6 ships a `PRE_REDIRECT` step for `OBS-29`'s operation-lifecycle triple.** The
finding above establishes that `DEF-42`'s stated route does not work. `6a` decides whether to ship the step
(and take the `NFR-4` surface and the `PIPE-37` neighbourhood that comes with it), or to record the finding and
leave the triple unwired with the row corrected — noting `OBS-29`'s own "pipeline/transport wiring to emit it
is a follow-up, so it is not yet runtime-enforced", and `OBS-28`'s "Every event method SHOULD default to a
no-op so adding a new event is a non-breaking change", which is what makes wiring a subset safe.

---

## Deviation Ledger

**Empty.** This document decides no deviation from the reference contract. Every mechanism substitution phase 6
relies on is already catalogued in
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` — items 4 (cooperative
cancellation, where `RETRY-23`'s flag restoration sits), 5 (the three unsatisfied MUSTs, which phase 6 does not
join), 15 (the cross-origin marker on the per-hop cursor), 17 (the interruptible sleep as a cancellable queue
wait, which is `RETRY-26`'s mechanism) and 18 (`RECOV-34`'s substituted ~292-year bound) — and in §11 items 1,
10, 12, 19 and 20, and is cited above rather than re-argued. The sub-phase designs will have ledgers of their
own; a deviation decided by any of them is numbered `P6-<n>` and consolidated into design §10. Two are already
foreseeable and are named in `R4` and `R15`.

**One correction to the roadmap, stated here because the roadmap requires a corrected cell to be corrected in
place with the correction stated.** The segmentation rule's phase-6 bullet closes:

> `REDIR-24` fixes the redirect loop outer and auth stamping inner, per hop, and `REDIR-11`'s cross-origin
> suppression signal is consumed by `AUTH`'s stamping step, so neither pillar half finishes without the other's
> contract fixed; phase 6's segmentation design settles whether that is one segment or two with a shared
> contract landed first.

**The question is answered, and by a document written three days after the bullet.** `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`
fixed the stage order, shipped `Cursor#fork(state:)`, `#state(stage)` and `#may_fork?` with stage-namespaced
write restriction, tested it with five negative assertions written against `Stages::REDIRECT` and
`Stages::RETRY` by name, and wrote phase 6's consumption of it into its own forward table. Design §10.15 is the
consolidated deviation. So the bullet's final clause should read: **the cut is three ways — `6a` retry, `6b`
redirect, `6c` authentication — and the shared contract landed in phase 4c, so phase 6 implements two halves of
a designed contract rather than designing one.** Everything else in the bullet — the 111 + 15 budget, the
`RECOV-31` exclusion, `RETRY`'s two stacks and the shared-calculator-before-either-stack rule — is confirmed
unchanged and correct.

**This is not filed as an open item, and the judgement is deliberate.** `OI-1`, `OI-2`, `OI-12`, `OI-15`,
`OI-21`, `OI-29` and `OI-31` all record a sentence that reads correctly and resolves to something that is not
there. This bullet's sentence resolves to something that *is* there and asks the right document to say so; it
is a correction-in-place, which the roadmap has taken twice already (the phase-4 bullet on 2026-09-08, the
phase-5 bullet on 2026-09-09), not a discovered inconsistency. Filing an open item for a sentence that
correctly delegated a decision would dilute a register whose value is that every row is a real find.

**Three consequences outside this document's own scope to fix, recorded so they are not discovered later.**

- **The roadmap edit itself is owed.** This document is constrained to write one file and cannot make it.
- **`CLAUDE.md`'s phase-directory claims sentence goes stale the moment this document is filed.** It currently
  reads "There are six phase directories under `docs/work/*/`" and enumerates `phase0/` through `phase5/`.
  Filing this document creates `docs/work/mvp/phase6/` and makes it seven; the probe's `claims` check reads
  that numeral and will report it, so this one is mechanically caught. It is corrected by hand in the change
  that files this document, together with the phase-6 entry in the enumeration and its sub-phase description.
- **The `knowledge-lookup` skill's audit-group table is owed an eleventh row**, *Resilience: retry, redirect and
  authentication*, whose exact content is given under *Corpus reading* above. That is an edit to
  `.claude/skills/knowledge-lookup/SKILL.md` and not to a frozen tree, and the roadmap's first retrospective
  rule wants it in place before the next sub-phase runs the group.
