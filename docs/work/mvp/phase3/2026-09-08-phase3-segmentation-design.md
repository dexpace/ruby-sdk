# Phase 3 — Segmentation Design

**Status:** Draft, for review. Written 2026-09-08, before any phase-3 sub-phase design exists.

**What this document is.** The segmentation design the roadmap's **Segmentation rule** requires of a build
phase that spans more than one ID-bearing spec chapter. It decides how many ways phase 3 is cut and in what
order, says for each boundary whether that order is a **dependency** or a **convenience**, assigns every
requirement ID to exactly one sub-phase, and names the boundaries that are spec-forced and therefore not open
to `3a`'s or `3b`'s own designs to revisit.

**What this document is not.** It is not a phase design, a plan or a checklist, and it does not pre-empt what
`3a` and `3b`'s designs are for. Where it names a decision as belonging to a sub-phase it stops there
deliberately; a segmentation design that settles the sub-phases' content is the same failure as a sub-phase
plan that re-imposes a chain the split existed to avoid, arriving from the other direction.

## Governing documents

- `docs/product-spec/05-i-o-contracts.md` and `docs/product-spec/06-request-and-response-body-lifecycle.md` —
  normative, read in full for this document, together with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for every ID's canonical text.
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1 and §3.7,
  `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` §7.1 and §7.3,
  `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items 1, 2, 10, 11, 12 and 18,
  and `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md`'s `IO`, `BODY` and `HTTP` rows.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-3 row, the segmentation rule, the gap-ID
  paragraph and the eight cross-cutting constraints.
- `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` and
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` — what phase 3 stands on.
- `CLAUDE.md` and `docs/README.md`.

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run first. `--origin note --brief` returns twenty entries
across eleven note files; `--section conflicts --brief` returns twenty-two, and **every one of the six
styleguide-versus-design conflicts prints `[overridden by notes/…]`** — none is open, so phase 3 inherits no
unresolved conflict and owns no conflict decision of its own.

Two note entries bind this phase directly and are cited rather than restated:
`concurrency-and-async/f414b864` (core's shared mutable state is one frozen `Data` snapshot swapped under a
`Thread::Mutex`; `Mutex` is per-fiber-owned and non-reentrant, both re-verified) and `data-modeling/5bc538ba`
(the wire model is Ractor-shareable except where a member holds a `URI::Generic`).

One audit group from the skill's table was run in full here, **Encoding and binary strings** — `--prefix IO
--section rules --brief`, then `--topic io-and-byte-streams,serde --section rules --brief` narrowed by
`--grep 'encoding|binary|ASCII-8BIT|force_encoding'` as that row's note requires — because it is the group
whose rules decide a boundary rather than an implementation. It confirms §3.1's encoding rule and adds one
edge this document did not expect: `SERDE-3` (`serde/cfbe4e9a`) is a **third** ownership rule — a codec never
closes or takes ownership of a caller's stream — consistent with §10.12's two, and carried into spec-forced
boundary 5 below so a sub-phase does not later discover it as a fourth.
The remaining groups (**Public API surface**, **RBS / Steep typing**, **Fiber scheduler, thread safety**) are
audits of built code and belong to the sub-phases, which name and record them per the roadmap's first
retrospective rule. Corpus
coverage is unusually good here — `--prefix-info` reports **37 of 42 `IO` IDs and 37 of 37 `BODY` IDs
substantive, with zero roll-up-only entries in either prefix**, so the appendix-B roll-up hazard does not fire
for phase 3 at all. `--req` over the twelve jointly numbered `HTTP` IDs returns twenty-eight entries, none
tagged `[appendix-B roll-up]`.

**One note was filed against the corpus before this document was finished**, per the roadmap's second
retrospective rule — a resolution recorded only in a phase document is re-litigated by whoever reads the
corpus next. `docs/knowledge/notes/pagination.md`, a new file, supersedes `pagination/d626cf17` (whose
`Enumerator`-`ensure` claim was verified on 3.4.10 alone) and widens `pagination/731d9f17` (which carries no
version qualifier), recording the re-verification across 3.2.11, 3.4.10 and 4.0.6 **and** the fact that the
hard rule those two entries force reaches phase 3 before it reaches phase 7. Both harvested entries now print
`[overridden by notes/pagination.md]`. Nothing else earned a note: the three other Ruby facts below override no
harvested rule, because the corpus makes no claim about Ruby's read-into semantics or about constant shadowing,
and a note without a rule to override does not earn its place.

`--phase 1 --brief` and `--phase 2 --brief` were run to see what the predecessors already cite. Phase 1 cites
`BODY-35`, `HTTP-36`, `HTTP-38`, `HTTP-41` and `HTTP-43` without owning them — all in its own out-of-scope
table, pointing here. Phase 2 cites `IO-1`, `IO-29`, `IO-37`, `IO-39`, `IO-42` and `BODY-27` for the same
reason, plus `SEAM-3`/`SEAM-4`'s retirement.

---

## The cut

**Two ways, on the specification's own ch.05/ch.06 line, and `3a` leads `3b` as a dependency.**

| Sub-phase | Name | Spec chapter | IDs | Order |
|---|---|---|---|---|
| **3a** | I/O contracts | `docs/product-spec/05-i-o-contracts.md` | 42 | leads |
| **3b** | Body lifecycle | `docs/product-spec/06-request-and-response-body-lifecycle.md` | 49 | follows `3a`, **dependency** |

This is the roadmap's expectation, and it is adopted because the evidence supports it, not because it was
expected. What follows is the evidence.

### `3a` leads `3b`: the dependency edges, named

The roadmap gives one edge — "`BODY-17`'s tee-on-write builds on `IO-28`'s pump". That citation is wrong on the
ID and right on the substance, and the correction is stated below. The edge set is much larger than one, and it
is one-directional:

| `3b` requirement | needs from `3a` | Why it is a dependency and not a convenience |
|---|---|---|
| `BODY-17`–`BODY-21`, `BODY-37` (request-logging tee) | `IO-25`–`IO-29` (the `TeeSink`) | `BODY-37`'s own canonical text reads "restating IO-28 at the body layer". One mechanism, two checklist rows; building it twice is how the two drift |
| `BODY-3`/`HTTP-37` (materialize-once) | `IO-7`–`IO-10` (the FIFO buffer), `IO-8` (snapshot) | "drain the body's write output exactly once **into an in-memory buffer** and return a replayable buffer-backed body" — the buffer is the artefact `3a` ships |
| `HTTP-39`/`BODY-10` (exact-length copy) | `IO-12` (exact-count read), `IO-17` (write-all's zero-read rule) | `BODY-10`'s "a zero-length read for a positive request MUST be a stream-contract violation" *is* `IO-17`'s foreign-source clause applied one layer up |
| `BODY-22`–`BODY-29` (response-logging drain) | `IO-19`/`IO-20` (peek and slice), `IO-41`/`IO-42` (close) | `BODY-23`'s "serve every read as a **fresh non-consuming view**" is `IO-19` by name; `BODY-27`'s close-once guard is `IO-41`'s latch |
| `BODY-32`, `BODY-33` (capped preview) | `IO-9`'s `MAX_MATERIALIZED_BYTES`, `IO-19`'s peek | design §10.18 fixes one substituted constant for `IO-9` and `BODY-32` together; two constants would be two ceilings |
| `HTTP-41`/`BODY-14`, `BODY-15` (response body) | `BufferedSource`, `IO-41`, `IO-42` | the response body *is* a buffered source with a close that releases a transport resource |
| `HTTP-42` (charset decode) | `IO-13` (explicit-charset reads) | `IO-13` is the primitive; `HTTP-42` is the policy over it, and §3.1 permits exactly one decode boundary |
| `BODY-8` (body-layer ownership) | `IO-6` (ownership-on-wrap) | design §10.12 is **one** decision with two halves; `3a` fixes the wrap half, `3b` inverts it deliberately at the body layer |

Nothing in `3a` needs anything from `3b`. That is what makes the order a dependency rather than a convenience,
and it is why **`3b`'s design must state the edges above in its own Prerequisite section rather than inherit
them by habit** — the roadmap's warning applies to a real chain as much as to a false one.

### The one edge that would have run backwards, and how it is removed

`Dexpace::IO::BufferedSource.over(body)` — design §3.1's single inverse adapter, §10.2's counterpart to the
canonical body representation — is a `3a` artefact whose argument is called a *body*. Read naively that is a
`3a`→`3b` back-edge, and it would turn a clean dependency into a cycle that a sub-phase plan would then
"resolve" by collapsing the two.

It is removed by a decision this document makes rather than leaves open: **the canonical body
*representation* — any object responding to `#each` and yielding `String` chunks tagged `Encoding::BINARY`,
design §10.2 — is fixed in `3a`, together with `.over` and its no-ownership exception. The body *production
contract* — `HTTP-36`/`BODY-1`'s single write-to-sink operation, media type, content length and
`#replayable?` — is `3b`'s.** `.over` consumes a duck type, not a `3b` class; no `3b` constant appears in
`3a`, and no `3a` ID moves.

### Three ways was considered twice, and rejected twice

**Rejected cut A — request side / response side, both after `3a`, order a convenience.** This is the only
candidate that would have bought genuine independence rather than a longer chain, and four requirements cross
it, each a MUST:

- `HTTP-52`/`BODY-30` re-serves a buffered **error response** body "as a replayable body" — `#replayable?` and
  the buffer-backed body are request-side artefacts.
- `BODY-34` is explicit that body logging on **both** sides is "bounded by **one shared** preview-size
  configuration". One shared thing across the boundary.
- `BODY-32`'s byte-capped snapshot/preview rules govern both sides' capture.
- `BODY-10`/`HTTP-39`'s short-write error and `BODY-25`'s zero-read violation share one helper "so the message
  form cannot diverge" (design §3.1, `message-bodies/a4c90d28`).

A cut with four shared MUSTs across it needs a shared contract landed before either side — which is exactly
the shape phase 6's segmentation bullet describes for `RETRY`'s backoff calculator, and it costs a third
document to recover independence the chapter did not have.

**Rejected cut B — body model (`3b`) then capture layer (`3c`), a strictly linear chain.** This one is
coherent: `3c` would be `BODY-17`–`BODY-34`, `BODY-37`, `HTTP-44`, `HTTP-45` and `HTTP-52`, and it would
isolate the one cluster with an external dependency on phase 5 (`BODY-19`/`BODY-34`'s cap and enablement).
It is rejected because it buys nothing the split exists to buy: `3c` depends on both `3a` and `3b`, so the
result is three segments in a strict line over what the specification writes as one lifecycle, and a phase
returns to `mvp` as **one phase-level pull request** (roadmap execution step 5) — so a third sub-phase is a
third document set, not a third merge. The sequencing `3c` would have enforced is `3b`'s plan's job, and this
document requires it of that plan below rather than of a segment boundary.

`3b` at **49 IDs is the largest sub-phase the roadmap's expectations contain** (phase 7b's SSE is 41, phase 4c's
pipeline 40). That is stated plainly rather than hidden: it is the price of not splitting a single lifecycle,
and the mitigation is a constraint on `3b`'s plan, not a fourth document —

> **`3b`'s plan orders the body model before the two logging wrappers, and says so.** `BODY-1`–`BODY-16`,
> `BODY-35`, `HTTP-36`–`HTTP-43` and `HTTP-51` land before `BODY-17`–`BODY-34`, `BODY-37`, `HTTP-44`, `HTTP-45`
> and `HTTP-52`, because every wrapper wraps a body. This is a task ordering inside one sub-phase, not a
> boundary, and `3b`'s design may not promote it to one without re-opening this document.

---

## Spec-forced boundaries — not open to `3a` or `3b`

Each is a MUST (or a design deviation already argued) that fixes something a sub-phase design might otherwise
believe it is free to decide. Quoted from appendix C or from the owning design section.

1. **`IO-40`** — "These streaming contracts MUST NOT impose their own read/write timeout or deadline; the
   adapter wraps foreign streams with a no-op timeout, delegating all deadline enforcement to the transport."
   `3a` owns no clock and no deadline; `3b` may not push one down; neither may reach for the `deadline:`
   keyword `DEF-28` deliberately kept off the async pivot until phase 5.
2. **`IO-37` with `IO-38`** — every streaming instance is a single-threaded contract, and the **close state is
   the one cross-thread-visible exception**. `3a` may not make instances thread-safe (that would over-satisfy a
   MUST that says the opposite and would hide a caller's own error), and may not make the close flag
   fiber-local. Design §3.1 fixes the mechanism: written and read through a `Thread::Mutex` rather than
   relying on the GVL, "so the guarantee survives JRuby and TruffleRuby".
3. **`IO-42`'s asymmetry** — a stream-backed source/sink rejects read/write/flush/emit after close; a purely
   in-memory buffer is **exempt on its own surface** so snapshot-after-close logging still works, but its close
   **still invalidates every derived slice**. The requirement's own rationale names both wrong directions.
   Neither sub-phase may simplify it in either.
4. **`IO-28` ↔ `BODY-37`** — one mechanism, two rows, and design §10.10 already records the honest position:
   the prohibition cannot be language-enforced (`instance_variable_get` reaches anything), so core exposes no
   reader and raises from any method that would hand one out. `3b` may not re-derive it and may not claim more.
5. **`IO-6` with `BODY-8`, per design §10.12** — "A body closes exactly the sources it opened; **ownership-on-wrap
   remains the I/O layer's rule** and is deliberately not the body layer's." Two rules, deliberately different,
   one decision. `3a` fixes the first and `.over`'s stated exception to it; `3b` fixes the second. Neither may
   re-decide the other's half, and `BODY-8`'s "A port MUST decide its stream-ownership/close rule deliberately"
   is already discharged by §10.12 — `3b` records it, it does not re-open it. **There is a third rule and it is
   phase 7's, not phase 3's**: `SEAM-20`/`SEAM-21` and `SERDE-3` require a codec to read or write a
   caller-supplied stream fully and close nothing, and §10.12's own sentence carries it ("the serde seam's
   streaming variants close nothing"). Phase 3 neither implements nor weakens it, and `3b` must not generalise
   its two rules over a third subsystem that has deliberately opted out of both.
6. **`BODY-4`'s three declines are deliberately not unified.** The specification says a port need not unify
   them and design §3.1 preserves the difference. `3b` ships one `#replayable?` property and three documented
   decline behaviours; it may not collapse them into one code path for tidiness.
7. **`HTTP-42`'s single decode boundary.** Design §3.1: "there is exactly one decode boundary,
   `Response#body_string`". `3a` ships `IO-13`'s charset reads as a primitive; `3b` adds no second decode site.
8. **`IO-9`/`BODY-32`'s `MAX_MATERIALIZED_BYTES`** — design §10.18 fixes the substitution (Ruby has no maximum
   single-array allocation), and §3.1 fixes the default at 64 MiB, "chosen, not derived", configurable through
   phase 5's layered chain. `3a` owns the constant because `IO-9` is `3a`'s; `3b` cites it. Two ceilings is the
   failure this pins.
9. **The retirement of the byte-stream provider seam is settled and is not `3a`'s to revisit.** Design §10.1
   retires `SEAM-3`–`SEAM-10`'s apparatus together with `IO-30`–`IO-36` and `IO-39`; phase 2 already shipped
   `SEAM-3`/`SEAM-4` as 🚫 with the reason attached. `3a` creates **no fourth registry**, no factory and no
   installation call, and its eight 🚫 rows cite §10.1 rather than re-arguing it.
10. **The `Dexpace::IO::` namespace is fixed.** Design §3.1 and §10.2 name `Dexpace::IO::Buffer` and
    `Dexpace::IO::BufferedSource`, and phase 1's P1-1 rule is explicit that "a subsystem the design already
    names with a namespace keeps it — `Dexpace::IO::Buffer`". `3a` does not get to flatten it to avoid the
    shadowing hazard below; it gets to gate the hazard.

---

## Scope: every ID, assigned to exactly one sub-phase

**91 requirement IDs**: 79 prefix IDs (`IO-1`–`IO-42`, `BODY-1`–`BODY-37`) plus the 12 jointly numbered into
spec ch.06 (`HTTP-36`–`HTTP-45`, `HTTP-51`, `HTTP-52`). Level split, derived from appendix C: **77 MUST,
12 SHOULD, 2 MAY**.

### 3a — I/O contracts (42 IDs, all `IO`)

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `IO-1`–`IO-29`, `IO-37`, `IO-38`, `IO-40`, `IO-41`, `IO-42` | 34 |
| 🚫 permanent simplification, §10.1 | `IO-30`, `IO-31`, `IO-32`, `IO-33`, `IO-34`, `IO-35`, `IO-36`, `IO-39` | 8 |

`3a` also fixes, without owning a new ID: the canonical body representation (§10.2), `BufferedSource.over` and
its no-ownership exception, and `MAX_MATERIALIZED_BYTES`.

The three SHOULDs inside the implemented set are `IO-9` (materialisation ceiling — satisfied by §10.18's
substituted constant), `IO-16` (the native-stream bridge) and `IO-18` (emit versus flush). Design §3.1 records
`IO-16` as "satisfied by construction, since a `BufferedSource` already responds to `#read`, `#readpartial`
and `#each`" — `3a` verifies that claim rather than restating it, because `IO-6`'s second sentence makes the
bridge's close ownership-bearing.

### 3b — Body lifecycle (49 IDs: 37 `BODY` + 12 `HTTP`)

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `BODY-1`–`BODY-11`, `BODY-13`–`BODY-35`, `BODY-37`; `HTTP-36`–`HTTP-45`, `HTTP-51`, `HTTP-52` | 47 |
| ⏳ deferred, `DEF-3` | `BODY-12` (SHOULD, platform zero-copy file transfer), `BODY-36` (MAY, memory-mapped view) | 2 |

`3b` additionally carries **`DEF-26` as a picked-up row** (below) and one **cross-reference row for `HTTP-46`**,
whose by-value body comparison `3b` completes without owning the ID — the same treatment phase 2 gave
`SEAM-29`, and for the same reason: dropping the row would leave a requirement whose obligation this phase
discharges with no row in the phase that discharges it.

### Reconciliation against the roadmap's arithmetic

**The roadmap's phase-3 arithmetic is correct and nothing is missing or double-counted.** Verified mechanically
against appendix C on 2026-09-08: the `IO` family is 42 contiguous rows with no duplicate, `BODY` is 37, `HTTP`
is 53, and the file holds exactly 645 requirement rows. The `HTTP` family partitions with no residue —
phase 1's 39 (`HTTP-3`–`HTTP-35`, `HTTP-46`–`HTTP-50`, `HTTP-53`) plus phase 3's 12 plus `HTTP-1`/`HTTP-2` is
53 — and 42 + 37 = 79 is the roadmap's "79 prefix IDs plus 12 jointly numbered", total 91. `3a`'s 42 plus
`3b`'s 49 is 91, each ID in exactly one sub-phase.

**Two things a reader of the spec chapters would get wrong, and neither is an arithmetic error:**

- **`HTTP-16-body` is not a requirement ID.** `docs/product-spec/06-request-and-response-body-lifecycle.md`
  §6.3 labels the convenience-reader rule "**HTTP-16-body / BODY-16**". Canonical `HTTP-16` is
  "The header model SHOULD preserve the insertion order of distinct names" — a phase-1 SHOULD, unrelated. The
  obligation is carried by `BODY-16` and by `HTTP-41`'s own appendix-C text, which folds the finally-close
  clause in. `HTTP-16` is **not** in phase 3's scope and must not be pulled in by a sub-phase reading §6.3.
- **`BODY-6` and `BODY-7` appear nowhere in ch.06's prose as their own bullets** — §6.1's `BODY-3`/`HTTP-37`
  entry states their content ("A single-use body MUST fail loudly on a second write … the consume-once guard
  MUST be race-safe") without the two IDs. Both have substantive corpus coverage and appendix-C rows, so
  neither is a gap; but they are two separate checklist rows in `3b`, not one, and design §3.1 already names
  them separately.

---

## Exclusions — IDs a reader would expect here, and the phase that owns each

| Excluded | Owning phase |
|---|---|
| `HTTP-16` — the header insertion-order SHOULD that ch.06 §6.3's `HTTP-16-body` label resembles | 1 |
| `HTTP-46` — request equality by value; the ID stays phase 1's, and phase 3 completes its body half through `DEF-26` | 1, completed here |
| `SEAM-3`, `SEAM-4` — the byte-stream provider seam, retired; design §3.1 states `IO-6`'s content citing `SEAM-3`, which is why the note below matters | 2 (🚫, §10.1) |
| `SEAM-14`, `SEAM-25`, `XCUT-13`, `XCUT-22` — the close and ownership contracts `Dexpace::Closeable` implements | 2 built, 9 dispositions |
| `BODY-30`/`HTTP-52`'s **pipeline step** and `BODY-31`'s error-to-exception mapping **step** — design §12 places both in §5.1, alongside `RECOV-16` | 4. Phase 3 ships the bounded replayable copy and the 4xx/5xx predicate; phase 4 ships the recovery-chain step that calls them |
| `BODY-19`/`BODY-34`'s **configuration source** — the tap cap, the shared preview size and the "body-level logging enabled" predicate | 5 (`CFG-1`–`CFG-4`, `OBS-35`). Phase 3 parameterises; phase 5 wires the layered chain |
| `IO-9`/`BODY-32`'s ceiling as a **configurable** limit rather than a constant with a default | 5, same reason |
| `BODY-4`/`BODY-5`'s three **call sites** — retry, redirect and the 401 challenge | 6 |
| `HTTP-44`/`HTTP-45`'s **witness-based handler** — design §7.3 is where the typed value is cashed in | 7. Phase 3 ships `Dexpace::TypedResponse` over a handler duck type; `SEAM-22`'s witness is phase 7's |
| `SSE-12`'s BOM rule and the SSE line machine over `IO-14`; `PAGE`'s and `SERDE`'s use of `BufferedSource.over` | 7 |
| `TRANSPORT-25`'s streaming response body over `Net::HTTPResponse#read_body`; `TRANSPORT-28`'s zero-copy dispatch (`DEF-10`) | 8 |
| `XCUT-15`, `XCUT-18` — restated cross-cutting invariants phase 3 leaves satisfiable without claiming | 9 |

---

## Gap IDs: `IO-6` and `IO-32`–`IO-35`

The roadmap says four of the five "are the byte-stream provider apparatus §10.1 retires, which is a decided
non-implementation and not unmapped spec", and directs the phase to read all five out of
`docs/product-spec/05-i-o-contracts.md`. **Both halves were checked. The first is correct; the second is not
followable, and one of the five is a live MUST.**

**`IO-32`–`IO-35` — the roadmap is right.** All four fall inside `IO-30`–`IO-36`, which design §10.1 retires by
name and §12's `IO` row confirms ("IO-30–IO-36 and IO-39 retired with the provider seam and its registry").
They are install idempotence, install-wins-after-discovery, discovery caching and the late-replacement warning
— the exact mirrors of `SEAM-6`–`SEAM-9`, which survive intact for the three seams phase 2 shipped. `3a`
carries them as four 🚫 rows citing §10.1 and reads nothing further for them. **Budget: none.**

**`IO-6` is not one of them, and it is a MUST `3a` must implement.** Its canonical text:

> When a provider wraps a caller-supplied underlying stream (readable stream -> buffered source, writable
> stream -> buffered sink), the returned wrapper MUST take ownership of that stream: closing the wrapper closes
> the underlying stream. The same holds for the stream bridges obtained from a buffered source/sink (closing
> the bridge closes the owning source/sink). Wrapping a plain byte array owns no external resource.

That is the I/O half of design §10.12's two-ownership-rules decision — the half §3.1 states as "At the I/O
layer, wrapping takes ownership: closing a `BufferedSource` built over a caller's `IO` closes that `IO`". Three
things follow, and they are why this ID gets its own paragraph rather than a line:

1. **`IO-6` appears in no specification chapter and in no design chapter.** Verified 2026-09-08 with a
   repository-wide grep: outside appendix C, the string `IO-6` occurs exactly once in the whole tree — in the
   roadmap's own gap paragraph. The chapter the roadmap sends a reader to does not carry it. §5.1 runs
   `IO-1`–`IO-5` and `IO-18`; the *bridge* half of `IO-6` survives in the chapter under **`IO-16`, a SHOULD**
   ("closing the bridge MUST close (or invalidate) the owning source"), and the *wrap* half — the MUST — is in
   appendix C alone.
2. **Both places that state its content cite `SEAM-3`, a retired ID.** §3.1's "Two ownership rules" paragraph
   attributes ownership-on-wrap to `SEAM-3`; so does the corpus (`message-bodies/8a1e7a7b`). A `3a` design
   auditing §10.1's retirement of `SEAM-3` and finding no surviving citation could reasonably conclude the rule
   retires with the seam. It does not: `IO-6` is its surviving normative home, and it is a MUST.
3. **Read it out of appendix C, not out of ch.05.** This is the same shape as `OI-1`'s five `SEAM` IDs, and it
   is filed as **`OI-2`** so the next reader of the roadmap's gap paragraph is not sent to the same empty
   chapter. **Budget: `3a` reads `IO-6` from appendix C and reconciles it against §3.1's `SEAM-3` wording and
   §10.12; one paragraph of design, not a chapter of reading.**

The corpus itself is otherwise complete for this phase — `--gaps IO,BODY` returns nothing beyond these five —
so phase 3 budgets no further specification reading than the two chapters, which were read in full for this
document.

---

## Prerequisites, and the decisions phase 3 inherits

**From phase 0** — seventeen blocking gates, unchanged and unlowered. The two that bite hardest here:
`gates:require_allowlist` (core's `lib/**/*.rb` may `require` only `monitor`, `uri`, `stringio`, `strscan`,
`time`, `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`; growing it is "a
reviewed one-line diff with the requirement that motivated it"), and `gates:surface_snapshot` plus
`gates:sig_diff`, which every new public constant regenerates. `stringio` is already allowlisted. **`tempfile`
is not, and does not need to be**: a file-backed body opens `::File`, which is core Ruby and requires nothing,
and the allowlist scans `lib/` only, so a `3b` test may use `tempfile` freely. Verified on 3.2.11, 3.4.10 and
4.0.6 that `stringio` and `tempfile` are default gems on all three and appear in **no**
`Gem::BUNDLED_GEMS::SINCE` table, so if `lib/` ever did need `tempfile` the one-line diff is admissible.

**From phase 1** — `Dexpace::Model` (the shared construction helper, with the `#with` override that routes
through the validating `.build` because `Data#with` skips an `initialize` override on 3.2.11),
`Dexpace::Builder` (`SEAM-29`'s generic contract), `Dexpace::Error` as a **module**,
`Dexpace::InvalidArgumentError < ::ArgumentError`, `Dexpace::HeaderSyntax`, `MediaType` (which `HTTP-42`'s
charset default reads), `Status` (which `BODY-31`'s 4xx/5xx test reads), and `Request`/`Response` carrying an
opaque `body` member. Four rules bind every file phase 3 writes:

- **Public wire-model constants are flat** and their files sit under `lib/dexpace/http/` (deviation P1-1) —
  **but a subsystem the design names with a namespace keeps it**, which is why `Dexpace::IO::Buffer` is
  namespaced and `Dexpace::TypedResponse` is flat.
- **No `.build` is a bare `new` wrapper.** Validation lives in each `Data` type's `initialize`, because
  `.build` is public, `#with` routes every derivation through it, and `send(:new, …)` reaches the constructor
  regardless.
- **`Dexpace::ArgumentError` is never defined**, in this or any later phase.
- **`downcase` takes no argument**, everywhere in core (`Dexpace/NoLocaleCaseFold`).

**From phase 2** — `Dexpace::Closeable` with its latch (a `@closed` boolean flipped under a `Thread::Mutex`
held **only across the flip**), `Dexpace.close_quietly`, `Dexpace::ClosedError`, `Dexpace::Cancellation`,
`Dexpace::Async::Future`/`Completer`, `Dexpace::Registry` with three seam registries that all start empty, and
`Dexpace::Hooks`. Three consequences for phase 3:

- **`Closeable`'s latch is the mechanism for `IO-41`, `BODY-15`, `BODY-27` and `HTTP-43`.** Design §3.7 already
  says all four "use the same mechanism", and phase 2 built it. `3a` and `3b` include the module; neither
  writes a second latch.
- **`close_quietly` still drops its rescued error** (`DEF-27`; phase 4 supplies the suppressed trail, phase 5
  the diagnostic). `BODY-28`'s best-effort close on the fits-cap path is a **new call site** for it, which
  strengthens that row without meeting its condition.
- **There is no fourth registry**, and `3a` adds none (§10.1, boundary 9 above).

**What phase 3 changes about a phase-1 public type.** `HTTP-43` puts `#close` on `Dexpace::Response`, `HTTP-42`
puts `#body_string` on it, and `DEF-26` **narrows** `Request#body` and `Response#body` in `sig/` from
`untyped`. `NFR-4`'s API lock is a diff against the previous release tag and **there is no release tag** —
every gem is at `0.0.0` and nothing is published (`docs/first-release.md`). The narrowing is therefore free
now and would not be later, which is precisely why `DEF-26` targets phase 3 rather than a phase after the
first release.

---

## Cross-cutting constraints that bite phase 3 specifically

1. **Bytes on the wire are always `Encoding::BINARY`** (§3.1). Verified on all three interpreters that
   `Encoding::BINARY.equal?(Encoding::ASCII_8BIT)`, and that appending a non-ASCII UTF-8 `String` to a BINARY
   one silently retags the result to UTF-8 — so a buffer that concatenates chunks must force the tag, not
   inherit it.
2. **An `Enumerator` abandoned mid-`#next` never runs its `ensure`, so resource acquisition and release never
   live inside an `Enumerator` block** (§7.1). Design §7.1 verified this on 3.4.10 only, and frames it as
   pagination's rule; **it binds phase 3 first**, because `BufferedSource.over` pulls from a body's `#each` and
   several body variants are `Enumerator`-shaped. Re-verified on 3.2.11, 3.4.10 and 4.0.6 (below). The engine
   owns the resource in its own scope and exposes `#close`.
3. **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden** (§8.3, `Dexpace/NoThreadInterrupt`),
   and **`IO-40` independently forbids the streaming contracts from owning any timeout or deadline**. The two
   agree, and together they mean a blocked read in `3a` is interrupted by nothing phase 3 owns.
4. **`Thread::Mutex` is per-fiber-owned and non-reentrant.** `BODY-22`'s once-latch and `HTTP-45`'s parse latch
   hold the mutex across the state flip and never across the drain or the parse; a caller arriving mid-work
   waits on a `Thread::ConditionVariable` over the same mutex, which the fiber scheduler hooks (§7.3, §3.1).
   `IO-38`'s cross-thread close flag uses the same shape and does not rely on the GVL.
5. **The bundled-gem rule.** Settled for this phase: `stringio` allowlisted, `tempfile` unnecessary in `lib/`
   and admissible if it ever became necessary, `File` core. No new allowlist entry is expected.
6. **`Ractor` is never load-bearing.** `data-modeling/5bc538ba` narrows the shareability claim already; a body
   holds an `IO` or a `File` and is not a value type, so no shareability claim is made for it at all.

---

## Verified Ruby facts that shaped this cut

Every claim below was run on real interpreters via `mise exec ruby@<v>` on 2026-09-08. Three changed something
in this document; the rest are recorded because a sub-phase design would otherwise assume them.

1. **`IO#read(n, buf)` and `StringIO#read(n, buf)` OVERWRITE the destination buffer; they do not append to its
   tail.** With `buf = (+"seed").b`, `StringIO.new("XY".b).read(2, buf)` leaves `buf == "XY"` on 3.2.11, 3.4.10
   and 4.0.6 alike, and `IO#read`/`IO#readpartial` behave identically. **`IO-1` requires the opposite** —
   "MUST append bytes to the TAIL of a caller-provided destination buffer (never overwriting existing
   content)". So `3a`'s `Source#read(dest, count)` **cannot delegate to Ruby's read-into form**; it reads into
   a fresh BINARY `String` and appends. This is the obvious-idiom-is-wrong case (P13) for `3a`, and it is the
   single most likely way `IO-1` gets silently violated.
2. **`StringIO#read(n, buf)`'s encoding behaviour changed at exactly Ruby 3.4, inside the supported range.**
   With a UTF-8 destination buffer, the result is tagged `ASCII-8BIT` on 3.2.11 and `UTF-8` on 3.4.10 and
   4.0.6; `IO#read`/`#readpartial` preserve the destination's own tag on all three. That is the same
   floor-straddling shape as `URI::DEFAULT_PARSER`, which design §3.5 pins against: it passes where you look
   and fails where you do not. `3a` forces `Encoding::BINARY` explicitly after every read and never infers a
   tag from a destination or a source.
3. **`Dexpace::IO` shadows `::IO` for every file inside `module Dexpace`, and the dangerous case is silent.**
   Verified on all three: inside `module Dexpace`, a bare `IO.pipe` raises `NoMethodError` (loud, harmless),
   but **`x.is_a?(IO)` and `IO === x` return `false` for a real `::IO`, with no error at all**. Design §3.1
   has core adapting "`#read`-shaped `IO`-likes at the edge because `Net::HTTP#body_stream=` wants one", which
   is exactly an `is_a?`-shaped test, and `Response#body_string` lives in `lib/dexpace/http/response.rb`, also
   inside `module Dexpace`. Phase 2 shipped `Dexpace/QualifiedCoreConstant` for the analogous
   `Dexpace::Async::Thread` hazard, but it covers the constants `Thread`, `Queue`, `Mutex`, `SizedQueue`,
   `ConditionVariable` and `JSON` under `lib/dexpace/async/**` and `lib/dexpace/serde/**` only — **neither the
   constant `IO` nor any path phase 3 writes**. Worse than the phase-2 case in one respect: that one needed the
   adapter gem to be required before it bit, whereas this one bites the moment `Dexpace::IO` is defined.
   Extending the cop is `3a`'s, and it is named as a risk below rather than designed here.
4. **The `Enumerator` `ensure` asymmetry holds on 3.2.11 and 4.0.6, not only on the 3.4.10 the design tested.**
   `Enumerator.new { |y| begin … ensure … end }` runs its `ensure` when a consumer calls `#each` with a block
   and `break`s; a consumer driving it with `#next` and abandoning it leaves the `ensure` unrun after two
   `GC.start` calls, and `#rewind` does not run it either. §7.1's hard rule is therefore floor-to-ceiling, not
   a 3.4 observation.
5. **`read(0)` returns `""`, never EOF, on both `IO` and `StringIO`, exhausted or not**, on all three. The
   hazard `IO-2` exists to warn about — "underlying libraries often collapse a zero-byte read against an
   exhausted stream to −1" — does **not** fire for Ruby's own readers. `IO-2` is still a `3a` row and still
   needs its test, because the requirement is about `3a`'s own surface, not about `IO`'s.
6. **`readpartial` raises `EOFError` at end of stream on all three**, where `read(n)` returns `nil` — two
   different sentinels for one condition, which is `3a`'s to normalise to `IO-1`'s −1.
7. **`stringio` and `tempfile` are default gems on 3.2.11, 3.4.10 and 4.0.6 and appear in no
   `Gem::BUNDLED_GEMS::SINCE` table** (undefined on 3.2.11; 28 entries on 3.4.10; 23 on 4.0.6). Neither is at
   risk of the bundled-gem trap within the supported range.

---

## Deferrals Filed by Phase 3

**None, and that is deliberate.** A segmentation design decides a cut; it does not decide the interfaces whose
absence a deferral records. Filing a row here for `BODY-19`/`BODY-34`'s cap parameter would fix that
parameter's shape ahead of `3b`'s design, which is the objection phase 0 raised against defining
`Dexpace.register` early and phase 2 raised again against `close_quietly`'s disposal routes. Two rows are
**expected of `3b`** and are named in the risks below so their absence later is visible: the configuration
source for the two caps and the enablement predicate, and `BODY-12`'s body-side clause if `3b` declines it.

### Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every row.
All thirty-two were read.

**Phase 3 picks up one row and sharpens a second.**

- **`DEF-26` — picked up, by `3b`.** Its pick-up condition names phase 3 explicitly: narrow `Request#body` and
  `Response#body` in `sig/`, and add the by-value equality test against a real body type. Both need a body type
  to exist, so the row belongs to **`3b`**, not `3a` — `3a` fixes only the `#each`/BINARY duck type, which is
  not a type `sig/` can narrow to. `HTTP-46` stays phase 1's ID and gets a cross-reference row in `3b`'s
  checklist. The narrowing is safe against `NFR-4` for the reason phase 1 could not yet state: the lock diffs
  against the previous release tag and there is none.
- **`DEF-3` — stays deferred; its `BODY-12` half gets a target it never had.** Phase 3 owns both IDs and ships
  the gem, so this is the row the sweep exists for. `BODY-12` is a SHOULD with two clauses: stream via the
  platform's most efficient file-to-sink transfer, **and** be recognizable by type so transports can dispatch
  a zero-copy kernel path. The second clause has no subject until a transport exists and is the same feature
  as `TRANSPORT-28` (`DEF-10`, post-MVP), so it is given the target **phase 8**, alongside `DEF-10`. The first
  clause is meetable in `3b` — `IO.copy_stream` is stdlib and available on all three interpreters — and
  **`3b`'s design decides it**; this document does not, because whether the file body's write uses it is an
  implementation question inside the sub-phase. **Not UNSCHEDULED either way**: that status is for a condition
  a phase met and declined, and `DEF-3`'s stated condition for `BODY-12` is "post-MVP", which phase 3 cannot
  meet. `BODY-36` (MAY, memory-mapped view) gets an **explicit pick-up condition in place of the "no named
  trigger" it has now**: Ruby's standard library has no `mmap`, and the only routes are a C extension or the
  `mmap` gem, both barred from core by `SEAM-1`/`NFR-1` — so the condition is *core's dependency budget
  changes*, which no phase in v1 can meet. Recorded so a later reader does not mistake an unmeetable condition
  for a forgotten one.
- **`DEF-27` — untouched, condition unmet, and phase 3 adds a caller.** `BODY-28`'s best-effort close after a
  successful full capture is a new `close_quietly` site. Neither disposal route exists yet (phase 4 supplies
  the suppressed trail, phase 5 the diagnostic), so the row stands as written and this note is recorded rather
  than the behaviour being re-litigated in `3b`.
- **`DEF-28` — untouched, and named as a constraint rather than a deferral here.** The pivot has no
  `deadline:` until phase 5, and `IO-40` independently forbids phase 3 from owning one, so the two agree.
- **`DEF-29` — untouched.** `3a` and `3b` will add test doubles (a fake sink, a fake body, a fake source) under
  `gems/dexpace-core/test/support/`, following phase 2's precedent and its four reasons. The condition — a
  consumer outside `dexpace-core` — is not met.
- **`DEF-24`, `DEF-25`, `DEF-30`, `DEF-31`, `DEF-32` — untouched.** Targets phase 4, 8, 5, 5 and 4; none is
  reachable from a phase that ships bodies and byte streams.
- **`DEF-1`, `DEF-2` — untouched.** `SEAM-24`/`SEAM-28` target phase 5; `HTTP-22`/`HTTP-48`–`HTTP-50` target
  phase 6.
- **`DEF-4`–`DEF-9` — untouched.** `PIPE`, `RECOV`, `RETRY`, `REDIR`, `SSE` and `OBS`; other prefixes, later
  phases. `DEF-10` is touched only as `BODY-12`'s transport half, above.
- **`DEF-11`–`DEF-17` — untouched.** Post-v1 gems, out of the MVP by construction.
- **`DEF-18` — untouched.** `ASYNC-3`/`PIPE-33`, the two known-unsatisfied MUSTs; do not re-open.
- **`DEF-19`, `DEF-20` — untouched.** Release-gated; nothing is published.
- **`DEF-21` — already picked up** by phase 2.
- **`DEF-22`, `DEF-23` — untouched.** Phase 8's conformance assertion objects, and a Steep target over a test
  tree whose condition ("production-quality test support") phase 3's fakes do not meet.

### The finding filed against `docs/open-items.md`

**`OI-2` — `IO-6`, a MUST, exists only as an appendix-C row, and every statement of its content cites the
retired `SEAM-3`.** Filed for the reasons under Gap IDs above. It is the same shape as `OI-1` and shares its
resolution path, which is why the two are worth reading together.

---

## Risks and open questions the sub-phase designs must resolve

Each is named with the sub-phase that owns it. None is decided here.

**R1 — `3a`: the `Dexpace::IO` shadowing gate.** Verified fact 3 above makes `x.is_a?(IO)` silently false
throughout `module Dexpace`. `Dexpace/QualifiedCoreConstant` covers neither the constant nor the paths. `3a`
decides the extension — which constants (`IO` certainly; `File`, `StringIO` and `Tempfile` only if a
`Dexpace::` constant of that name is ever created), which paths (repository-wide for `IO`, not just
`lib/dexpace/io/**`, because `Response#body_string` is the counter-example), and whether the accompanying
behavioural test from phase 2's precedent is reproducible here without an adapter gem to require.

**R2 — `3a`: the `Source#read(dest, count)` primitive.** Verified fact 1 forbids delegation to Ruby's
read-into form. `3a` decides the shape (`IO-1`'s tail-append with its four return values, `IO-2`'s zero-count
rule, `IO-3`'s eager negative-count rejection) and how `readpartial`'s `EOFError` and `read`'s `nil` are both
normalised to −1 without a rescue on the hot path.

**R3 — `3a`: `IO-6`'s reconciliation with §3.1's `SEAM-3` wording.** The ID is a MUST with no chapter prose,
and the bridge half of it lives in the chapter under a SHOULD. `3a` states the rule once, cites `IO-6` and
§10.12 rather than `SEAM-3`, and names `.over`'s exception in the same place.

**R4 — `3a`: whether `IO-16`'s "satisfied by construction" claim survives `IO-6`.** §3.1 says a
`BufferedSource` already responds to `#read`, `#readpartial` and `#each`, so the native-stream bridge needs no
separate object. `IO-6`'s second sentence makes closing the bridge close the owning source — which is trivially
true when the bridge *is* the source, and is worth an assertion rather than an inference.

**R5 — `3b`: where `BODY-19`, `BODY-34` and `IO-9`/`BODY-32`'s ceiling get their values before phase 5.** The
caps are "configurable" in three requirements and there is no configuration chain until phase 5. `3b` decides
the parameter shape and whether that is a deferral row; the precedent is `DEF-28`, where phase 2 shipped the
narrower signature and deferred the wider one, and the same `NFR-4` argument applies (adding a keyword widens).

**R6 — `3b`: the body constants' names and namespace.** Design §3 names `Dexpace::IO::Buffer`,
`Dexpace::IO::BufferedSource` and `Dexpace::TypedResponse`, and names **no** body-variant constant. Phase 1's
P1-1 rule decides the shape (flat unless the design namespaced it) but not the names, and every one of them is
`NFR-4`-locked at the first release tag, so each needs a Deviation Ledger row in `3b` the way phase 2's six
unnamed constants did.

**R7 — `3b`: `HTTP-44`/`HTTP-45` without a witness.** `Dexpace::TypedResponse` is design §7.3's, where its
handler is `SEAM-22`'s witness — phase 7's. `3b` decides the handler duck type (`#call(response)`, or
something narrower) so that phase 7 supplies a witness *into* it rather than replacing it, and so `NFR-11`'s
scan sees no phase-7 constant in a phase-3 signature.

**R8 — `3b`: the boundary against phase 4 at `BODY-30`/`HTTP-52` and `BODY-31`.** The bounded replayable copy
and the 4xx/5xx predicate are `3b`'s; the recovery-chain step that invokes them is phase 4's (§5.1,
`RECOV-16`). `3b`'s plan states which side of that line each task is on, because a task that builds the step
collides with phase 4 and a task that builds neither leaves a MUST unowned.

**R9 — `3b`: `BODY-9`'s mark/reset clause has no Ruby subject.** The requirement conditions replayability on
"the stream supports mark/reset"; Ruby's `IO` has no mark/reset, `IO#rewind` raises on a pipe or socket, and
`StringIO#rewind` always succeeds. `3b` decides what the Ruby antecedent is — most likely rewindability probed
at construction — and whether the SHOULD is implemented, vacuous or deferred. It is the one `BODY` requirement
whose Ruby mapping the design does not already fix.

**R10 — `3b`: `BODY-24`'s over-cap tail and `IO-42`'s in-memory exemption interact.** The over-cap regime
serves a single-use stream that replays a captured prefix then continues from a still-live delegate, while
`IO-42` exempts a purely in-memory buffer from use-after-close but requires its close to invalidate derived
slices. The composite object is both. `3b` states which surface each rule governs; getting it wrong is exactly
one of the two directions `IO-42`'s rationale names.

---

## Deviation Ledger

**Empty.** This document decides no deviation from the reference contract. Every mechanism substitution phase 3
relies on is already catalogued in `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`
— items 1 (the retired provider seam), 2 (the duck-typed canonical body), 10 (`IO-28`/`BODY-37`'s
unenforceable prohibition), 11 (read-only collection exposure), 12 (the one stream-ownership rule) and 18
(the substituted platform constants) — and is cited above rather than re-argued. The sub-phase designs will
have ledgers of their own; a deviation decided by either is numbered `P3-<n>` and consolidated into design §10.

One correction to the roadmap, stated here because the roadmap requires a corrected cell to be corrected in
place with the correction stated: the segmentation rule's phase-3 bullet reads "`BODY-17`'s tee-on-write builds
on **`IO-28`**'s pump". `IO-28` is the tee's no-direct-backing-buffer prohibition, which `BODY-37` restates;
the **pump** is `IO-17` (write-all), and the apparatus `BODY-17` builds on is the tee sink, `IO-25`–`IO-29`.
The dependency the sentence asserts is real and is confirmed above — only the ID is wrong. The roadmap sentence
is corrected in place in the same change that files this document.
