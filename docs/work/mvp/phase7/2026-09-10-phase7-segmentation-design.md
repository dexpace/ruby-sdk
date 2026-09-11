# Phase 7 — Segmentation Design

**Status:** Draft, for review. Written 2026-09-10, before any phase-7 sub-phase design exists.

**Path:** `docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`. That is the path this document
carries for the rest of its life and the one every citation of it should use — including the link the
roadmap's phase-7 row is owed, matching the segmentation-design links phases 3 through 6 already carry.

**What this document is.** The segmentation design the roadmap's **Segmentation rule**
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:173-181`) requires of a build phase that spans more
than one ID-bearing spec chapter or ships more than one gem. Phase 7 does both. It decides how many ways the
cut goes and in what order, says for each boundary whether that order is a **dependency** or a
**convenience**, assigns every requirement ID to exactly one sub-phase, and names the boundaries that are
spec-forced and therefore not open to the sub-phase designs to revisit.

**What this document is not.** It is not a phase design, a plan or a checklist, and it names no numbered task
and writes no code. Where it names a decision as belonging to a sub-phase it stops there deliberately; a
segmentation design that settles the sub-phases' content is the same failure as a sub-phase plan that
re-imposes a chain the split existed to avoid, arriving from the other direction.

**The headline, stated once at the top because everything else depends on it.** Phase 7's scope is
`SERDE-1`–`SERDE-30`, `SSE-1`–`SSE-41` and `PAGE-1`–`PAGE-36` — **107 requirement IDs, and no ID moves in
from another phase and none moves out.** **The cut is three ways — `7a` serde, `7b` SSE, `7c` pagination —
and every boundary is a CONVENIENCE.** The roadmap's forecast
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:242-247`) is **confirmed in full**: the letters, the
three-way shape, the independence claim and the "order is convenience only" instruction all survive testing
at ID level. Two things the roadmap says are refined rather than corrected, and both are stated in the
*Deviation Ledger*: the independence of `7b` from `7a` is a **mechanised** MUST (`SSE-37`) while the
independence of `7c` from `7a` rests on chapter-intro prose that carries **no requirement ID**, and this
document extends the mechanism to close that asymmetry; and the second gem's boundary falls *inside* `7a`
rather than *at* a sub-phase boundary, which is why shipping it does not change the cut the way the roadmap
says four gems will change phase 8's.

Phase 7 adds **no new unsatisfied MUST**, files **no deferral**, picks up **one** register row (`DEF-8`,
which stays deferred as a ⏳ line) and **resolves `OI-5`** — with a correction to the requirement ID `OI-5`'s
own resolution text names. It **declines `DEF-2`'s floated phase-7 target**, with the argument below.
Its spec-reading budget is **zero**: `ruby scripts/knowledge.rb --gaps SERDE,SSE,PAGE` reports 0 of 107 with
no substantive corpus entry.

---

## Governing documents

- `docs/product-spec/14-serialization-serde.md`, `docs/product-spec/13-server-sent-events-and-streaming.md`
  and `docs/product-spec/12-pagination.md` — normative, all three read in full for this document (57, 72 and
  86 lines), together with `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the
  canonical text and modal level of all 107 IDs. Appendix C is a **convenience** here and not a necessity:
  every one of the 107 appears in its own prose chapter, which is the opposite of phase 6's position.
- `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` in full — §7.1 (the two `Enumerator` views,
  the close-on-abandon rule, the verbatim query splice, the async engine), §7.2 (the WHATWG line machine, the
  event value, the pull-based facade, the `SSE-37` boundary) and §7.3 (the witness protocol, where the
  witness is cashed in, `Tristate`, the three closing notes).
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.4 in full
  (`03-seam-by-seam-idiomatic-mapping.md:295-350`) — the six-method codec duck type, the four allocation
  profiles, why the codec is a separate gem, the two naming hazards, the two adapter defaults; and §3.1's
  encoding boundary, which `7b`'s data lines and `7a`'s decode both cross.
- `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items **6** (`:58-62`, the
  core-owned suppressed trail, naming `PAGE-13`, `PAGE-15`, `SSE-29`, `SSE-30`, `SSE-36`), **12** (`:87-91`,
  the stream-ownership rule, whose third clause is the codec's), **13** (`:92-96`, four encode profiles, two
  of which are one Ruby type) , **14** (`:97-102`, the serde witness as a class-object-and-combinator
  protocol) and **18** (`:119-124`, platform-constant substitutions, which names `SSE-11`).
- `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` items 15
  (`:51-53`), 17 (`:56-58`), 18 (`:59-62`) and 21 (`:73-81`); and §12's `PAGE`, `SSE` and `SERDE` rows
  (`docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:36-38`).
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-7 row (`:92`), the ordering rationale
  (`:115-118`), the segmentation rule's phase-7 bullet (`:242-247`), the gap-ID paragraph (`:153-161`), the
  five cross-phase obligations (none of which binds phase 7) and the nine cross-cutting constraints, of which
  4 (`:52-53`, the in-memory fake transport) binds `7c` directly.
- `docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md` as the closest worked example of this
  document's form (three independent segments, every boundary a convenience), and
  `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md`,
  `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md` and
  `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md` as the other three.
- The predecessor sub-phase designs whose forward tables this document cites rather than re-derives:
  `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md`,
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md`,
  `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md`,
  `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`,
  `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`,
  `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`.
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
`tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`). **None is open**, so phase 7 inherits no
unresolved conflict and owns no conflict decision of its own. Narrowed to this phase's prefixes,
`--origin note --prefix SERDE,SSE,PAGE --brief` returns **two** entries and
`--section conflicts --prefix SERDE,SSE,PAGE --brief` returns **one**, which is one of the same two.

**Corpus coverage: complete, and this is the phase where that is most nearly free.** `--prefix-info` reports
`SERDE` **30 of 30 substantive**, `SSE` **41 of 41**, `PAGE` **36 of 36** — zero roll-up-only and zero
uncited in all three. `ruby scripts/knowledge.rb --gaps SERDE,SSE,PAGE` closes with "0 of 107 IDs in 3
prefixes have no substantive entry". **Phase 7 budgets no read-the-specification-directly time**, which is
the exact inverse of phase 4's fifteen-ID `RECOV` cluster and of phase 6's fourteen. The chapters were read
in full anyway, for the `*Conformance:*` clauses appendix C does not carry — several of which are
load-bearing and named in the scope tables below.

**The appendix-B roll-up hazard fires on this phase, and the shape of it matters.** Unlike phases 4 and 6,
where the tag appeared nowhere, roughly a third of every phase-7 prefix's entries carry it:
`--prefix SERDE --brief` returns 79 entries of which **30** are `[appendix-B roll-up]`, `SSE` **39 of 104**,
`PAGE` **33 of 92**. That is phase 5's position. Two things follow, and they point in opposite directions,
so both are stated:

- **No ID is roll-up-*only*** (`--gaps` says so for all three prefixes), so a `--req` on any phase-7 ID
  returns at least one substantive entry and the CLI's all-roll-up WARNING never fires. The skill's
  three-step roll-up path is the exception here, not the reading mode.
- **The roll-ups are dense enough to bury the substantive hit.** `--req SERDE-17` returns eight roll-up
  entries beside one Constraints entry and one Reference entry that actually answer it. A sub-phase author
  should reach for `--req <ids> --section rules,constraints,conclusions` rather than a bare `--req`, and this
  is the first phase where that is worth saying.

**Two navigation hazards in the corpus itself, observed while auditing and recorded so a sub-phase author
does not lose a rule to them.** Both are proposed as a register finding below rather than acted on here.

- **`sse-streaming/5f4803a0` is an SSE rule filed under `PAGE-14` and under no `SSE` ID.** Its text —
  "An SSE `Enumerable` view must not be taken twice over the same source … the facade enforces this by
  latching a `@viewed` flag on first call and raising on a second" — is the Ruby realisation of `SSE-26` and
  `SSE-40`, and it is harvested from design §7.2's sentence that *mentions* `PAGE-14` by way of comparison.
  So `--req SSE-26` and `--req SSE-40` do not return it and `--req PAGE-14` does.
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:84-87` · high · sha:4bf713047534</sub>
- **`pagination/b2a85752`, the sharper half of the `Enumerator`/`ensure` rule, carries no requirement ID at
  all**, so `--prefix PAGE` misses it while `--topic pagination` finds it. Its companion
  `pagination/318ae05d` does carry `PAGE-11`/`PAGE-12`, which makes the omission easy to miss rather than
  obvious.

**Two note entries bind this phase through its own prefixes, and three more bind it through the surfaces it
consumes. They are cited by key rather than restated, except the one the rule turns on.**

- **`pagination/318ae05d`** — the rule the whole of `7c`'s lifecycle and the whole of `7b`'s facade are built
  on, and the one a sub-phase author would otherwise re-derive. Quoted, not paraphrased:

  > **The rule reaches phase 3 first.** … `Dexpace::IO::BufferedSource.over(body)` pulls chunks from a body's
  > `#each` on demand … and `IO-41`/`IO-42`/`BODY-15`/`BODY-27` all put a real transport resource behind a
  > close that must actually run. So the owning object with its own `ensure` and its own `#close` is a
  > **phase-3 obligation**, discharged through phase 2's `Dexpace::Closeable` latch, and **phase 7 inherits a
  > rule already paid for rather than discovering it.**

  <sub>review · `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md` · high · sha:manual-phase3-enumerator-range</sub>

- **`pagination/b2a85752`** — the half that closes the escape hatch, and the reason `7c` may not put a page's
  response inside an ordinary `#each` either. An `ensure` inside a plain `def each` behaves exactly like an
  `Enumerator.new` block under external iteration, and `block_given?` is **true** inside `#each` when reached
  through `to_enum(:each)` and `#next` — so a `raise unless block_given?` guard, which looks like it forbids
  external iteration, does nothing at all. There is no in-method defence; the only defence is where the
  resource lives.
  <sub>review · `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` · high · sha:manual-phase3b-each-method-abandonment</sub>

- **`data-modeling/83610619`** — `7b`'s note, and it is why `SSE-20` is cheaper than §7.2 makes it look.
  `Data#with` does **not** call an `initialize` override on Ruby 3.2 and does on 3.4 and 4.0, so
  `Dexpace::Model` — the module every core `Data` type includes — overrides `#with` to route through the
  type's own validating `.build`. An `SSE::Event` that includes `Dexpace::Model` therefore re-owns its data
  list on every `#with` **through the same path that owns it at construction**, which is exactly what
  `SSE-20`'s second clause demands, rather than through a bespoke override `7b` would otherwise write.
  <sub>review · `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` · high · sha:manual-phase1-data-with</sub>

- **`io-and-byte-streams/6eb5155f`** — binds `7b` and `7a` both. The single decode boundary is **two steps**,
  retag then transcode, and the transcode must name its target encoding explicitly, because bytes arriving
  from the wire are `Encoding::BINARY` and `String#encode` with `undef: :replace` and no target destroys
  every byte at or above `0x80` and follows `Encoding.default_internal`, a process global the host sets.
  `7b`'s SSE data lines and `7a`'s JSON payload are both text derived from BINARY bytes and both cross this
  boundary. Recorded as `OI-7`.
  <sub>review · `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` · high · sha:manual-phase3b-decode-retag-then-transcode</sub>

- **`io-and-byte-streams/a44b4de6`** — binds `7b`'s line machine directly. `force_encoding` raises
  `FrozenError` on a frozen `String` **even when the target encoding is already the string's own**, and the
  chunks reaching `BufferedSource.over(body)` are routinely frozen; `String#b` is the retag idiom. The
  companion trap is the one that makes a green suite lie: appending a non-ASCII UTF-8 `String` to a BINARY
  one silently retags the result to UTF-8 while appending an ASCII-only one leaves it BINARY — so an
  ASCII-only SSE fixture passes under exactly the bug. **Every `7b` encoding test uses non-ASCII content**,
  for the same reason every phase-3a one does.
  <sub>review · `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` · high · sha:manual-phase3a-frozen-ingress-retag</sub>

- **`message-bodies/a7afc6ee`** — the only note that reaches this phase through a `SERDE` ID, and it reaches
  it by naming what phase 3 declined to touch: "A third ownership rule exists and belongs to neither layer —
  `SEAM-20`/`SEAM-21`/`SERDE-3` (`serde/cfbe4e9a`), where **a codec closes nothing** — and phase 3 neither
  implements nor weakens it." That rule is `7a`'s, and `serde/cfbe4e9a` prints
  `[overridden by notes/message-bodies.md:8]` for the citation half only; its content stands.
  <sub>review · `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` · high · sha:manual-phase3a-io6-ownership-home</sub>

**One audit group was run, and the skill's table is owed a thirteenth row this document cannot add.** The
`knowledge-lookup` audit-group table carries twelve rows — the eleventh was added by phase 6 — and none
covers serialization, SSE or pagination. (`Encoding and binary strings` names the `serde` topic, but its
group is the `IO` prefix and it is narrowed to an encoding regex; it is not this group.) The group that was
run is `ruby scripts/knowledge.rb --prefix SERDE,SSE,PAGE --section rules --brief` — **104 entries across 6
topic files** (`serde`, `sse-streaming`, `pagination`, `message-bodies`, `retry-and-resilience`,
`cross-cutting-invariants`), and **zero of them roll-up-tagged**, which is worth stating beside the density
figure above: the roll-ups live entirely in the `Reference` section, so the audit group is clean even where
`--req` is noisy. The roadmap's first retrospective rule and phases 3a, 4, 5 and 6's precedent require the
row to be **added before the group is run**; this document is constrained to write exactly one file and
therefore could not add it. **The thirteenth row is owed**, and its exact content is:

| Audit group | Query (once harvested) | Today | Status |
|---|---|---|---|
| Serialization, SSE and pagination | `--topic serde,sse-streaming,pagination --section rules --brief` and `--prefix SERDE,SSE,PAGE --section rules --brief` | `--prefix-info SERDE`, `--gaps SERDE,SSE,PAGE` | live |

Whoever files this document adds that row to `.claude/skills/knowledge-lookup/SKILL.md` in the same change.
It is not a frozen tree.

`--phase 3`, `--phase 4` and `--phase 6` were run to see what the predecessors already cite. **Phase 6 cites
no phase-7 ID at all**, which is the first mechanical corroboration of the roadmap's "6 before 7 is a
convenience order, not a dependency" (`:117-118`). Phase 3 cites `SERDE-3`, `SSE-11` and `SSE-12` without
owning any of them; phase 4 cites `PAGE-13`, `PAGE-15`, `SSE-29`, `SSE-33` and `SSE-36`, all pointing here.
Phases 2 and 5 cite none.

**No knowledge note is filed by this document.** The candidates — stdlib `json` having no incremental parser
(verified fact 1), and `Data#with` sharing a member array (verified fact 3, whose general form is already
`data-modeling/83610619`) — are recorded under *Verified Ruby facts* below and the notes that carry them are
**`7a`'s and `7b`'s to file with the designs that act on them**, which is phases 5's and 6's stated treatment
of the same situation. Recorded here so their absence is a decision rather than an omission.

---

## The cut

**Three ways. Every boundary is a CONVENIENCE.**

| Sub-phase | Name | Spec chapter | Gems | IDs | Order |
|---|---|---|---|---|---|
| **7a** | Serialization — the witness protocol, `Tristate`, the response handlers, and the JSON codec | `docs/product-spec/14-serialization-serde.md`, all of it | `dexpace-core` **and** `dexpace-serde-json` | 30 | first, **convenience** |
| **7b** | Server-Sent Events — the line machine, the event value, the facade and the typed adapter | `docs/product-spec/13-server-sent-events-and-streaming.md`, all of it | `dexpace-core` | 41 | second, **convenience** |
| **7c** | Pagination — the two views, the strategies, the query splice and the async engine | `docs/product-spec/12-pagination.md`, all of it | `dexpace-core` | 36 | third, **convenience** |

### The roadmap's forecast, tested rather than deferred to

The segmentation rule's phase-7 bullet reads
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:242-247`):

> **Phase 7 (107 IDs), expected 7a serde, 7b SSE, 7c pagination.** The cut is spec-forced and so is the
> independence: `SSE-37` is a MUST that core parsing and streaming hold no serialization dependency, and
> §12's chapter intro requires the pagination engine to be transport-agnostic and serde-agnostic, with
> `PAGE-8` keeping the engine stateless and shareable. No sub-phase may depend on another, order is
> convenience only, and each sub-phase's plan must say so in its own Prerequisite section rather than
> inheriting a chain by habit. This is also the phase that ships the workspace's second real gem,
> `dexpace-serde-json`.

Phases 3, 4, 5 and 6 each either confirmed or corrected their bullet in place, and three of the four found
the stated *reason* false even where the shape was right. This bullet's shape and its reasons both hold.
Six checks, each run for this document:

1. **`SSE-37` says what the bullet says it says, at MUST level, with a conformance clause.**
   "Core parsing/streaming MUST remain format- and API-agnostic: no built-in done-sentinel, no error-envelope
   recognition, **no serialization dependency** … *Conformance: confirm no sentinel string or serde call
   exists in the reader or stream facade.*" (`docs/product-spec/13-server-sent-events-and-streaming.md:65`.)
   Design §7.2 adds the mechanism: it "is checked mechanically by §9.2's require audit, not by review"
   (`sse-streaming/ebb489ba`). So `7b`'s independence from `7a` is not an assertion — it is a gate.
2. **§12's chapter intro says what the bullet says it says, and the bullet attributes each half correctly.**
   "It is transport-agnostic and serde-agnostic: a single stateless *strategy* parses each response into the
   page's items plus the fully-formed request for the next page" (`docs/product-spec/12-pagination.md:3`);
   `PAGE-8` supplies the statelessness and shareability separately (`:381` of appendix C). The bullet does not
   claim `PAGE-8` carries the serde-agnosticism, and it is right not to.
3. **The transitive edges are absent too, not merely the direct ones.** `7b` → `7c`? `SSE`'s facade and
   `PAGE`'s page view share a *shape*, not an object: the shared piece is phase 2's `Dexpace::Closeable`
   latch and phase 3's `Enumerator` rule, both built two phases early. Neither chapter's requirements mention
   the other subsystem. `7c` → `7b`? Nothing in §12 reads an event stream.
4. **No ID straddles.** Every one of the 107 is stated wholly inside one chapter and satisfied wholly inside
   one sub-phase; the scope tables below assign all 107 with no shared row and no "see the other sub-phase"
   disposition. The two IDs a reader would suspect are `SERDE-27`/`SERDE-28` (which need a response, a body
   and a typed wrapper) and `PAGE-16` (which needs a strategy to read items out of a body) — the first pair
   consume phase 3b and phase 4b and not `7b` or `7c`; the second is settled under *Spec-forced boundaries*
   item 4.
5. **The letters are internally consistent with the roadmap's own row.** The phase-7 row (`:92`) lists the
   chapters in the order "§14 SERDE; §13 SSE; §12 PAGE" — reverse chapter order, matching the letters. No
   convention in this repository forces letters to follow chapter order (phase 4's and phase 5's do not), so
   there is nothing to correct and re-lettering would break a row that is already right.
6. **Phase 6 cites no phase-7 ID**, verified by grep over `docs/work/mvp/phase6/` on 2026-09-10, which is
   the corroboration for `:117-118`'s "6 before 7 is a convenience order, not a dependency" from the
   direction the ordering rationale could not check when it was written.

**One asymmetry the bullet does not state, and this document closes it.** `7b`'s independence is a MUST with
a mechanised check. `7c`'s is chapter-intro prose: §12's "A port MUST preserve the two-view model, the
page-lazy fetch discipline, deterministic response-lifecycle management, and the strategy contract described
here" (`docs/product-spec/12-pagination.md:3`) enumerates four things and **serde-agnosticism is not among
the four**, and no `PAGE` ID carries it. So the property `7c` and `7a` are independent *because of* is
enforced, today, by nothing. The zero-dependency gates do not reach it: core's require allowlist already
forbids `json` by name (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:459`),
but the boundary at issue is **internal** — core's pagination layer reaching for core's own
`Dexpace::Serde` seam — and no gate sees that. This document therefore extends `SSE-37`'s mechanism to the
pagination layer as a **spec-forced boundary of its own making** (item 5 below), states that it is an
extension rather than a requirement, and leaves the audit's exact shape to `7b`'s and `7c`'s plans.

### Why `7a` is one segment even though the gem boundary falls inside it

`7a` is the only sub-phase in the MVP so far that writes into two gems: `dexpace-core` (the witness protocol,
the combinators, `Tristate`, the `SERDE-2` body factory, the two response handlers) and
`dexpace-serde-json` (the codec adapter, the ISO-8601 encoder default, the `.default` factory, and the one
`add_dependency "json", ">= 2.19.9"` line). Saying that plainly is the precondition for arguing it is still
one segment.

**The gem line is where the `SERDE` IDs least want to be cut, because a large majority of them are satisfied
on both sides of it.** Four worked cases, each read out of the chapter and the design rather than asserted:

- **`SERDE-21`/`SERDE-22` are satisfied by the codec doing nothing and by the witness doing everything.**
  Design §7.3: "`JSON.parse` performs no coercion, so `"5"` never silently becomes `5`; the strictness burden
  moves into the witness, where each field asserts its expected class and raises a `DeserializationError`
  naming the target type on mismatch — which is also how `SERDE-13` is enforced" (`serde/b5e5efc8`). The
  adapter's half is an absence; the witness's half is core's. One ID, two gems, and the adapter's half is
  only *observable* through the witness's.
- **`SERDE-9`/`SERDE-10`/`SERDE-12`'s failure model is phase 2's hierarchy, whose observance is testable only
  in the adapter.** `Dexpace::Serde::Error`/`SerializationError`/`DeserializationError` shipped in phase 2
  (`docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md:980-1000`); what `7a` adds is an
  adapter that catches `JSON::JSONError` and re-raises inside the `rescue`, and a genuine stream `IOError`
  that is *not* caught. That is one decision with its statement in core and its proof in the gem.
- **`SERDE-19`'s tri-state wiring is "structural rather than registered"** (design §7.3), meaning the
  `Tristate` combinator in core is what makes Absent omit a key — there is nothing to register in the
  adapter, and the requirement is discharged in core and asserted through the adapter's round trip.
- **`SERDE-3`'s "never closes the caller's stream"** is stated at the seam in core (phase 2), restated as
  §3.4's decode mirror, and asserted against a close-counting tracker in the adapter's suite.

**The arithmetic makes the same point.** Of the 30 `SERDE` IDs, the ones whose satisfaction is *wholly*
inside `dexpace-serde-json` are `SERDE-24` (ISO-8601 encoder default), `SERDE-25` (the `.default` factory
returning a fresh instance) and `SERDE-26` (the private codec engine, near-vacuous per §11.18) — **three**.
A gem-shaped cut would produce a 27-ID segment and a 3-ID segment that cannot be tested without the 27. That
is strictly linear and buys no independence at all, which is the ground phase 6 rejected its cut B on
(`docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md:329-335`).

**And the gem is not new work in the sense that would force a split.** Phase 0 created
`gems/dexpace-serde-json` with a real gemspec at `0.0.0`, its entry file
`lib/dexpace/serde/json.rb`, its `sig/`, its `test/`, its Steep target
(`check "gems/dexpace-serde-json/lib"` with `signature "gems/dexpace-serde-json/sig",
"gems/dexpace-core/sig"`) and its row in the six-gem inventory
(`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:254-260`). What phase 7 adds is
one gemspec line and the contents of `lib/`. The roadmap's own phase-8 sentence is what settles the general
rule and it does not fire here: "Raw count alone would not force a split; **shipping four gems does**, and so
does the per-gem conformance work the count does not see" (`:249-250`). Phase 7 ships one, and its per-gem
conformance work is deliberately not phase 7's — see spec-forced boundary 8.

**What `7a` owes in exchange for spanning two gems** is stated so a reviewer can hold it to it: an explicit
internal task ordering in its plan, with the `add_dependency "json", ">= 2.19.9"` line landing **before** the
first `require "json"` in that gem's `lib/`. Phase 0's require-allowlist audit is extended to the adapters —
"for each adapter, every `require` must be allowlisted, or under `dexpace/`, or **the single third-party gem
that adapter's gemspec declares**"
(`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:471-475`) — so the reverse order
is a red build, not a style preference. That is task ordering inside one plan, not a segmentation boundary.

### Why `7b` is one segment at forty-one IDs

`7b` is **41 IDs**, the third largest sub-phase in the roadmap after `6a`'s 60 and phase 3b's 49, and the
phase-3 segmentation design already anticipated the figure ("phase 7b's SSE is 41",
`docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md:149`). The obvious internal cut — the parser
(`SSE-1`–`SSE-22`) from the facade and the typed adapter (`SSE-23`–`SSE-41`) — is rejected on three
requirement-level grounds, not on taste:

1. **`SSE-14`/`SSE-15`'s end-of-stream behaviour is the parser's and is only observable through the
   facade.** `SSE-14` requires a pending block to dispatch at EOF and `SSE-15` requires the sentinel to be
   sticky; `SSE-24` requires that "on reader end-of-stream during iteration, the facade MUST both terminate
   the iterator cleanly AND release the resource". A cut between them puts the behaviour in one document and
   the only assertion of it in another.
2. **`SSE-16` and `SSE-40` are one statement from two sides.** `SSE-16`: the reader is single-pass and
   stateful, and "only the 'BOM already consumed' flag persists across calls". `SSE-40`: the convenience view
   "SHOULD … **reuse one reader instance** so per-stream state (BOM consumption) is preserved". The test that
   proves the reuse spans both; a cut gives it no home.
3. **`SSE-17` and `SSE-23` are one ownership decision expressed as two requirements** — the reader owns
   nothing, the facade owns exactly one thing, "resource ownership is introduced only by the stream facade
   (§13.5)" says so inside `SSE-17` itself. Splitting a single ownership decision across a review boundary
   is the shape `OI-10` caught in phase 3, where a three-method surface was written against members two of
   the three implementing types did not have and every test passed.

**What `7b` owes in exchange for being large**: an explicit internal ordering in its plan — line machine →
event value → reader → facade → typed adapter — and, because that ordering is the same shape as `6a`'s, the
same statement that it is *task ordering inside one plan* and not a segmentation boundary.

### Why `7c` is one segment, and why the sync/async line is not the cut here

`7c` is 36 IDs, of which `PAGE-25`–`PAGE-33` (nine) are the async engine. The sync/async line is the right
line in phase 8 and is wrong here, for the reason phase 6 gave for `6a`
(`docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md:265-270`) and for one more of its own:

- **Design §7.1 puts both consumption views over one internal drive routine** — "two `Enumerator`s sharing
  one internal drive routine" (`pagination/71aed9c1`) — and the async engine drives the same fetch/parse
  sequence through `#on_settle`. The close-exactly-once obligation is stated once for the sync views
  (`PAGE-11`, `PAGE-12`, `PAGE-15`) and again for the async one (`PAGE-27`: "after drain, when dropping a
  fetched-but-undrained page, or inline on parse failure, with no double-close and no leak"), and the two
  statements are about the same lifecycle.
- **Nine IDs is not a segment**, and a segment that can only run after the other is a linear chain — the
  ground phase 6 rejected its cut D on.
- **`PAGE-31`'s trampoline is a cross-*phase* reuse, not a cross-sub-phase one.** Design §7.1: it "is the
  same iterative pump as **RETRY-30**", which is `6a`'s. So the pump's shared authorship question, if there
  is one, is a phase-6/phase-7 question and is answered by the specification's own latitude and a `while`
  loop (`pagination/579cc80b`), not by a cut inside `7c`.

### Why none of the three leads another

Stated as the six directed edges a reader will look for. Each is answered from a requirement or a shipped
contract, never from "probably not".

- **`7a` → `7b`?** No, and it is forbidden. `SSE-37` is a MUST and design §7.2 mechanises it. `7b`'s typed
  adapter (`SSE-33`–`SSE-36`) takes a **caller-supplied mapper**, receives `(event-name, joined-data)` and
  yields the mapper's decoded value; the three mapper outcomes are `Dexpace::Outcome`'s two reused with a
  third variant **in the SSE namespace**, which is phase 4b's contract
  (`docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md:1528`). No serde appears.
- **`7b` → `7a`?** No. Nothing in `docs/product-spec/14-serialization-serde.md` mentions an event stream, and
  `SERDE-27`'s streaming handler reads a `Response` body, not an SSE source.
- **`7a` → `7c`?** No. §12's engine is serde-agnostic and the built-in strategies read what they need out of
  the response through the caller's own extraction (spec-forced boundary 4). `7c` may accept an object
  conforming to phase 2's `Dexpace::Serde` duck type without depending on `7a` at all — **the seam is phase
  2's, shipped, and the codec is `7a`'s** (`docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md:942-960`).
  That distinction is the whole of why the edge is absent.
- **`7c` → `7a`?** No. `SERDE-27`/`SERDE-28`'s handlers take a `Response`; nothing about them is
  page-shaped, and `PAGE-2`'s "materialized item list" is produced by the strategy, not by a handler.
- **`7b` → `7c`?** No. The one thing they share is the close-once discipline, and its implementation is
  `Dexpace::Closeable` — phase 2's latch, consumed by phase 3a and 3b already. `SSE-26`'s single-pass guard
  and `PAGE-14`'s single-use guard are two `@viewed`-style flags on two unrelated objects; design §7.2 calls
  them "the same single-use treatment", which is a statement about shape, not about a shared object.
- **`7c` → `7b`?** No. §12 reads a body once per page through a strategy; it has no line machine and no event.

**The one thing that is genuinely shared, and why it is not an edge.** Design §7.2 says the streaming facade
"reuses §7.1's lifetime mechanism verbatim, deliberately, so one cleanup story covers both subsystems"
(`sse-streaming/971c5f77`), which reads like a dependency. It is not, because **the mechanism it names
already shipped**: the rule ("resource acquisition and release never live inside an `Enumerator` block; the
engine owns the resource in its own scope with its own `ensure` and exposes `#close`") is design §7.1's and
is a phase-3 obligation per `pagination/318ae05d`, and the latch it is discharged through is phase 2's
`Dexpace::Closeable`. Whichever of `7b` and `7c` lands first writes no shared object the other consumes; each
writes its own owner over the same already-built latch. This is the phase-7 analogue of phase 6's
`RETRY-13`, and the answer is the opposite one for a stated reason: **`RETRY-13` is a MUST naming ONE
calculator inside phase 6, while §7.2's sentence names a mechanism built two phases earlier.**

### The order that is recommended, and why it is only a recommendation

`7a → 7b → 7c`, the roadmap's own letters. Four reasons, none of them a dependency:

1. **`7a` is the only sub-phase that touches a second gem, and it exercises three phase-0 gates against a
   second gem for the first time.** The gemspec audit's `NFR-2` budget (core plus at most one), the
   adapter-extended require-allowlist audit, and the Steep target with two signature roots have all been
   *built* and none has ever seen a gem with a third-party dependency in it. Landing `7a` first surfaces a
   scaffold defect while two sub-phases still have room to absorb it. This is the risk-retirement argument
   phase 4 gave `4a`, phase 5 gave `5a` and phase 6 gave `6a`, applied to the one thing about phase 7 that is
   genuinely new.
2. **`7b` is the largest and it resolves an open register row against shipped phase-3 code.** `OI-5` records
   that `#read_line_utf8` is the one drain-style read the 64 MiB ceiling does not guard, and names phase 7's
   SSE machine as its only MVP consumer. The longer that stays open the longer phase 3a ships a documented
   unbounded read with no bound above it.
3. **`7c` has the smallest inherited-surface footprint and the most self-contained object graph** — a query
   tokeniser, an RFC 8288 link parser, a page engine and an async pump, over `Dexpace::Request` (phase 1),
   `Response` (phase 1/3b) and a transport duck type (phase 2). It is the safest to run last, and equally the
   safest to run in parallel with either other.
4. **`7a` before `7b` puts the one cross-gem `sig/` arrangement in place before the phase's largest RBS
   surface arrives.** `NFR-11`'s scan and `NFR-4`'s lock both act per gem; getting the two-root Steep target
   proven on 30 IDs before 41 arrive is convenience, not order.

**Because the order is a convenience, each sub-phase's design must say so in its own Prerequisite section
rather than inheriting a chain by habit** — which the roadmap's phase-7 bullet requires in as many words. A
`7b` plan whose first task waits on `7a`'s witness protocol has re-imposed a chain `SSE-37` positively
forbids; so has a `7c` plan that waits on a codec to write `PAGE-16`.

### Five other cuts were considered, and rejected

**Rejected cut A — four ways, splitting `7a` at the gem line into a core-serde segment and a
`dexpace-serde-json` segment.** Rejected under *Why `7a` is one segment*: 27 IDs against 3, strictly linear,
with the 3 untestable without the 27 and a majority of the 30 satisfied on both sides of the line. Phase 0
already created the gem, so "shipping a gem" here is one `add_dependency` line plus `lib/`.

**Rejected cut B — two ways, merging `7a` and `7b` as "the codec-adjacent half" against `7c`.** Superficially
attractive because both are byte-level text processing over §3.1's primitives. Rejected on `SSE-37`: merging
the codec and the layer that is *forbidden to know about the codec* into one document puts the prohibition
and the thing it prohibits inside one review boundary, which is the arrangement most likely to produce a
`require` the audit then has to catch. It is the same objection phase 6 made to merging a security-critical
stripping policy with a security-critical stamping policy
(`docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md:321-327`), arriving from the other direction.

**Rejected cut C — splitting `7b` along the parser/facade line.** Rejected under *Why `7b` is one segment*,
on `SSE-14`/`SSE-15` versus `SSE-24`, `SSE-16` versus `SSE-40`, and `SSE-17` versus `SSE-23`.

**Rejected cut D — splitting `7c` along sync/async.** Rejected under *Why `7c` is one segment*, on design
§7.1's one drive routine, on nine IDs not being a segment, and on `PAGE-31`'s trampoline being a cross-phase
reuse rather than a cross-sub-phase one.

**Rejected cut E — a fourth segment for the shared lifecycle mechanism, landing before `7b` and `7c`.**
This is the cut the roadmap's own reading of §7.2 ("one cleanup story covers both subsystems") would suggest.
Rejected because the mechanism is not phase 7's to build: it is design §7.1's rule, `pagination/318ae05d`
records it as a phase-3 obligation, and it is discharged through phase 2's `Dexpace::Closeable`. A segment
whose whole content is "consume two things two earlier phases already shipped" is a document, not a segment.

---

## Spec-forced boundaries — not open to `7a`, `7b` or `7c`

Each is a MUST, a design deviation already argued, a shipped phase-0-through-4 contract, or a roadmap
obligation already fixed, that settles something a sub-phase design might otherwise believe it is free to
decide. Item 5 is the one exception and is labelled as such.

1. **Core's SSE layer holds no serialization dependency, and the check is mechanical.** `SSE-37`, design
   §7.2, `sse-streaming/ebb489ba`. `7b` writes no `require` of `dexpace/serde`, names no `Dexpace::Serde`
   constant, and ships no done-sentinel string and no error-envelope recognition — `SSE-37`'s three
   prohibitions are one prohibition with three faces. `SSE-38`'s three (no auto-reconnect, no persisted
   last-event-id, no `Last-Event-ID` header) are satisfied by omission **and asserted by test**, because
   design §7.2 states the temptation to add them is real.
2. **The witness is a class-object-and-combinator protocol, never a reflective type token.** Design §10.14
   (`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md:97-102`) and §7.3.
   `SEAM-22`'s mechanism is already 🚫 in phase 2 with the reason attached
   (`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:5598`), and the surviving clause — `#load`
   takes an explicit witness and there is **no witness-less overload** — shipped there. `7a` builds the
   protocol §10.14 substituted and may not re-open the substitution; `SEAM-8`'s "unresolved type variable"
   rejection is unreachable by construction and `7a` records that rather than emulating a state that cannot
   exist.
3. **All four encode profiles ship and the seam's six methods are phase 2's, not `7a`'s to redesign.**
   Design §10.13 and §3.4. `#media_type`, `#dump_string`, `#dump_bytes`, `#dump_to`, `#dump_into` and
   `#load(source, witness)`, with `.conforms?` over them
   (`docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md:951-956`). `#dump` is a documented
   shorthand and is deliberately **not** in the conformance contract. `7a` implements the six; it adds no
   seventh to the seam and removes none.
4. **The pagination strategy reads the response itself; core supplies no codec-flavoured strategy.**
   `PAGE-5` fixes the contract — "a strategy MUST read everything it needs from the response synchronously
   inside parse (the body is single-use), MUST NOT retain the response or its body beyond the call, and MUST
   NOT close or mutate the response" — and §12's intro fixes the engine as serde-agnostic. `PAGE-16`'s
   "single read of the response body" is therefore *the strategy's* single read, performed through whatever
   extraction the caller supplied, which may be an object conforming to phase 2's `Dexpace::Serde` duck type
   and is never `Dexpace::Serde::JSON`. `7c` ships no JSON-flavoured strategy and no default codec, and
   `dexpace-serde-json` receives no pagination code.
5. **The `SSE-37` audit is extended over core's pagination layer, and this document is where that is
   decided.** This is the one boundary here with no requirement behind it, and it is stated as an extension
   rather than smuggled in as a MUST: §12's serde-agnosticism carries no ID, so without the extension it is
   enforced by nothing at all — core's require allowlist already denies `json` by name and the *internal*
   `Dexpace::Serde` reference is invisible to it. The mechanism is `SSE-37`'s own, one path wider. **Owned by
   whichever of `7b` and `7c` lands first**, with the other adding one path — see *Convergence points*.
6. **A codec closes nothing, and that rule belongs to neither the I/O layer nor the body layer.**
   `SEAM-20`, `SEAM-21`, `SERDE-3`; `serde/cfbe4e9a`; design §10.12 and §3.4's "The decode side is the
   mirror: `#load(source, witness)` **reads to EOF and does not close the caller's source**". Phase 3
   explicitly declined to implement or weaken it (`message-bodies/a7afc6ee`), so `7a` owns it whole:
   `#dump_to` does not close the sink, `#dump_into` does not own the buffer, `#load` does not close the
   source, and the JSON adapter's suite asserts each against a close-counting tracker — which is `SERDE-3`'s
   own conformance clause, including its "even when the codec's own auto-close feature is enabled" tail.
7. **`Dexpace::TypedResponse` is supplied into, never replaced.** Phase 3b built it over
   `Dexpace::_ResponseHandler`, "any object responding to `#call(response)`", validated by `respond_to?` and
   never by a nominal test, and stated why the narrower shapes were rejected:
   "`#call(body)` or `#call(bytes)` would be narrower and would force phase 7 to **replace**
   `TypedResponse` rather than supply a handler into it"
   (`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md:535`). `SERDE-27`'s streaming
   handler and `SERDE-28`'s status-aware handler are two such handlers. `7a` writes no second memo, no second
   `@state` machine and no second lock: `HTTP-44`'s memo and `HTTP-45`'s mutex-across-the-flip-only are 3b's
   and are already tested (`serde/e9047c51`, `serde/97665a9a`).
8. **`dexpace-conformance` is not written into by phase 7.** The roadmap gives phase 8 that gem — "phase 8
   owns that gem: its gemspec, its version and its first release, shipping the transport conformance suite"
   (`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:93`) — and phase 9 "adds the remaining suites to
   phase 8's gem, owning neither its gemspec nor its release" (`:94`). So §3.4's "asserted per adapter in
   `dexpace-conformance` rather than left to adapter discipline" and phase 2's "asserted per adapter in phase
   7 and phase 8" are satisfied *in phase 9*, and `7a` writes its assertions in
   `gems/dexpace-serde-json/test/`. `DEF-29`'s condition — the first consumer outside `dexpace-core` — is not
   met by phase 7 either, since `7a`'s assertions have exactly one adapter to run against and
   `dexpace-serde-oj` is `DEF-16`, post-v1. `7a` records the obligation in its checklist so phase 9 inherits
   a named target rather than reconstructing one.
9. **A pipeline is a transport, and a paginator wrapping one owns nothing.** Phase 4c's forward table, in the
   row written for this phase: "`PIPE-26`: a built pipeline is a transport, so a paginator takes one with no
   declaration. `Pipeline#close` is a no-op on the transport (`PIPE-27`), so a paginator wrapping one owns
   nothing" (`docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md:1436`). `7c`'s engine
   therefore takes a `#call`-shaped transport and states no pipeline dependency; `PAGE-3`'s ownership
   transfer is about the **response**, never about the transport it came from.
10. **`Dexpace::Outcome` gains its third variant in the SSE namespace and nowhere else.** Phase 4b's forward
    table: "`Dexpace::Outcome`, reused with a third variant **in the SSE namespace** and never by adding one
    here (`RECOV-1`, spec-forced boundary 6)"
    (`docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md:1528`). `SSE-34`'s three
    mapper outcomes — value, Skip, Done — are `7b`'s to name inside `Dexpace::SSE`, and `7b` adds no member
    to `Dexpace::Outcome`, `Success` or `Failure`.
11. **The suppressed trail is `Dexpace.attach_suppressed`/`Dexpace.suppressed`, and phase 7 writes no
    second one.** Phase 4b's forward table, again written for this phase: "`Dexpace.attach_suppressed` and
    `Dexpace.suppressed`. A primary that is not a `Dexpace::Error` is handled; a **frozen** primary is
    silently not, which is stated" (`…phase4b…:1529`). That covers `PAGE-13`, `PAGE-15`, `SSE-29` and
    `SSE-36`, which are design §10.6's named consumers. The frozen-primary caveat travels with it and each
    sub-phase states it rather than rediscovering it.
12. **`SSE-30`'s swallow-versus-propagate split is two call sites into one close-once helper, not two
    closes.** Design §7.2, and `cross-cutting-invariants/68aad33a`: "An explicit `#close` by the caller
    propagates its failure (`SSE-30`) and a `#release` raising during the latched close propagates once
    (`BODY-27`); these are the two required-to-be-loud exceptions to `close_quietly`'s otherwise quiet closing
    behaviour." The quiet route is `Dexpace.close_quietly(resource, onto:)` — phase 2's file, given `onto:`
    by 4b, given its `http.instrumentation.*` diagnostic by 5b, closing `DEF-27` there. `7b` and `7c` call it;
    neither writes a second quiet-close path, and `PAGE-26`'s and `PAGE-32`'s swallow clauses are the same
    call.
13. **Every cause walk goes through `Dexpace.each_cause`.** Phase 4b's forward table names phases 6 and 7
    together for `XCUT-9` (`…phase4b…:1527`): it yields the error first and tracks by reference identity
    through `#compare_by_identity`. Phase 7 walks no `#cause` chain by hand, and uses the **block** form —
    the block-less form returns an `Enumerator`, and boundary 14 is why that matters here.
14. **Resource acquisition and release never live inside an `Enumerator` block, or inside an ordinary
    `#each` that owns a resource.** `pagination/318ae05d` and `pagination/b2a85752`; design §7.1;
    `CLAUDE.md`'s constraints list. `PAGE-11`, `PAGE-12`, `SSE-24` and `SSE-25` are all cash-outs of it, and
    none of the three sub-phases may write a `block_given?` guard as a defence — it is measurably true inside
    `#each` when reached through `to_enum(:each)` and `#next`, so it forbids nothing.
15. **The line-reading primitive is phase 3a's, and `7b` builds a different machine over it, not a second
    primitive.** `IO-14`'s `#read_line_utf8` and `#peek` shipped in 3a, and 3a stated the boundary in its own
    plan: "Phase 7's SSE line machine is a **different** machine over the same primitive and is not built here
    (boundary to phase 7)" (`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts.md:2176-2177`).
    `SSE-2`'s LF/CR/CRLF recognition and `SSE-14`'s unterminated-final-line-as-content are why the primitive
    was hand-written rather than delegated to `IO#gets` (`sse-streaming/e98a0668`); `SSE-12`'s single leading
    BOM is consumed through 3a's non-consuming `#peek`.
16. **`MAX_MATERIALIZED_BYTES` is one ceiling, cited and never re-derived.** `IO-9`, `BODY-32`, design
    §10.18, phase 3a's `P3-4`. `7a`'s `#load` draining a source to EOF is guarded by it; `7b`'s line cap is a
    *different* bound at a *different* layer and is `OI-5`'s resolution (below). Neither sub-phase introduces
    a second materialisation constant and neither lowers 3a's.
17. **Bytes on the wire are `Encoding::BINARY`; the decode boundary is retag-then-transcode with both
    encodings named.** `io-and-byte-streams/6eb5155f`, `io-and-byte-streams/a44b4de6`, `OI-7`. `7b`'s data
    lines and `7a`'s payload both cross it, `String#b` is the retag idiom rather than `force_encoding`, and
    every encoding assertion in either sub-phase uses non-ASCII content.
18. **`URI::RFC3986_PARSER` is pinned for every parse and every resolution.** Design §3.5, phase 0's
    `Dexpace/NoUriDefaultParser` cop, which bans `URI::DEFAULT_PARSER` and the `URI.parse`/`URI.join`/
    `URI.split` family that routes through it
    (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:523`). `PAGE-19`'s
    reference resolution is `7c`'s and is written against the pinned parser.
19. **`downcase` is called with no arguments.** `HTTP-13` and phase 0's `Dexpace/NoLocaleCaseFold` cop, which
    rejects **any** argument to `downcase`/`upcase`/`capitalize`/`swapcase` and their `!` forms plus
    `casecmp?`. It bites in three places here: `PAGE-18`'s case-insensitive `rel` token match, `SSE-7`'s
    field-name comparison, and `SERDE-2`'s media-type comparison against phase 1's `MediaType`.
20. **`Time.parse`, `Date.parse` and `DateTime.parse` are banned repository-wide.** Phase 0's
    `Dexpace/NoTimeParse` cop. `SERDE-24`'s ISO-8601 round trip therefore uses `Time.iso8601`/`Time#iso8601`
    from `time`, which is on the allowlist and is not what the cop bans (verified fact 5). `7a` does **not**
    reach for phase 5a's `Dexpace::HTTPDate`, which is RFC 1123 and a different grammar.
21. **`JSON.load` and `JSON.unsafe_load` have no place in a decode path, and inside
    `module Dexpace::Serde` a bare `JSON` is the adapter.** Design §3.4: the adapter implements the seam
    "via `JSON.generate` and `JSON.parse`, **never** `JSON.dump` or `JSON.load` … This is enforced by a lint
    rule, not by convention." And phase 2's addendum `A1` ships `Dexpace/QualifiedCoreConstant`, "a blocking
    custom cop rejecting a bare `Thread`, `Queue`, `Mutex`, `SizedQueue`, `ConditionVariable` or `JSON`
    inside `lib/dexpace/async/**` and `lib/dexpace/serde/**` and requiring the `::`-qualified form"
    (`docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md:1295`). `Dexpace::Serde::JSON` is the
    exact constant that cop exists for, and `7a` is the first code it bites.
22. **Regexp timeouts are per-pattern and the process-global `Regexp.timeout` is never set.** Design §4 and
    §6.3; `CLAUDE.md`. `PAGE-18`'s RFC 8288 link-value grammar is not regular — quoted commas, quoted-pair
    escapes and a multi-token `rel` — so `7c` writes a character-level state machine for the same reason
    design §6.3 gives for the `WWW-Authenticate` parser, and the constraint is discharged by not writing the
    regexp. `SSE-11`'s all-ASCII-digits screen and `PAGE-22`'s percent-decode are the places a pattern does
    appear, and both are anchored.
23. **`Ractor` is never load-bearing, and `Data`-based value types are frozen at construction.**
    `SSE-20`/`SSE-21` and `PAGE-2` want immutable values with structural equality; they get them from `Data`
    plus `Dexpace::Model`, with Ractor-shareability a free side effect and no part of the claim
    (`data-modeling/5bc538ba` narrows exactly which models are shareable and why).
24. **Phases 1 through 7 test against an in-memory fake transport.** Roadmap cross-cutting constraint 4
    (`:52-53`). `7c` is the first phase-7 sub-phase with a transport-shaped dependency at all, and it uses
    phase 2's `SEAM-11`/`SEAM-16` fakes. No `TCPServer` fixture, no socket.

---

## Scope: every ID, assigned to exactly one sub-phase

**107 requirement IDs.** Level split, derived mechanically from
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` on 2026-09-10: **90 MUST, 14
SHOULD and 3 MAY** — 90 + 14 + 3 = 107. No `MUST NOT` row appears in any phase-7 prefix.

### Reconciliation against the roadmap's arithmetic

Verified mechanically with `grep -c '^| SERDE-'`-style counts:

| Prefix | Rows in appendix C | Level split |
|---|---|---|
| `SERDE` | 30 (`SERDE-1`..`SERDE-30`, contiguous, no duplicate) | 22 MUST, 7 SHOULD (`SERDE-11`, `SERDE-18`, `SERDE-20`, `SERDE-23`, `SERDE-24`, `SERDE-25`, `SERDE-29`), 1 MAY (`SERDE-30`) |
| `SSE` | 41 (`SSE-1`..`SSE-41`) | 36 MUST, 3 SHOULD (`SSE-21`, `SSE-22`, `SSE-40`), 2 MAY (`SSE-19`, `SSE-41`) |
| `PAGE` | 36 (`PAGE-1`..`PAGE-36`) | 32 MUST, 4 SHOULD (`PAGE-10`, `PAGE-20`, `PAGE-31`, `PAGE-35`), 0 MAY |

30 + 41 + 36 = **107**, which is the roadmap's phase-7 cell (`:92`) and its own segmentation bullet's figure
(`:242`). `7a`'s 30 plus `7b`'s 41 plus `7c`'s 36 is 107, each ID in exactly one sub-phase. **No `DEF-<n>`
moves an ID into this phase and none moves one out**, so unlike phase 6 there are two numbers here only if
someone invents one.

### `7a` — Serialization (30 IDs, all `SERDE`)

Scope in one sentence: the witness protocol and its combinators, the `Tristate` three-state PATCH type, the
`SERDE-2` body factory, the two response handlers over phase 3b's `TypedResponse`, and the JSON codec that
fills `dexpace-serde-json` and declares the `json >= 2.19.9` floor.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `SERDE-1`–`SERDE-30` | 30 |
| ⏳ deferred | none — design §12's `SERDE` row reads "*Deferred:* none" | 0 |
| **Total in budget** | | **30** |

Three rows carry a clause the checklist must **state** rather than tick, each on the authority of a design
appendix rather than on `7a`'s judgement:

- **`SERDE-11` and `SERDE-14`'s covariance clause are satisfied by the language.** Design §11.15: "**SERDE-11**'s
  unchecked exceptions and **SERDE-14**'s covariance are satisfied by the language and need no code"
  (`docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md:51-53`).
  `SERDE-14`'s *substantive* half — Present bounded to non-null so the illegal fourth state is
  unrepresentable — is real code and is implemented; only the covariance clause is vacuous, and the row says
  which half is which rather than marking the whole ID vacuous.
- **`SERDE-26` is near-vacuous and its own fallback clause is what covers it.** Design §11.18 and §7.3:
  `JSON` is stateless, so "operate on a private copy of the codec engine" is satisfied by holding
  configuration in a frozen options hash owned by the `Serde` instance, and **the behaviour is documented
  rather than silent**, which is the requirement's own condition for the fallback.
- **`SERDE-8`'s unresolved-type-variable rejection is unreachable, and that is a strength argued in §10.14,
  not a gap.** A combinator cannot be constructed without a concrete element witness, so there is no
  partially-resolved carrier to reject. The row cites §10.14 and states that `Dexpace::Serde.witness!(w)`
  fails at witness construction — earlier than the reference's binder-resolution failure — rather than
  claiming a rejection path that has no input.

`7a` additionally ships, without owning a new ID: the `add_dependency "json", ">= 2.19.9"` line in
`gems/dexpace-serde-json/dexpace-serde-json.gemspec`, which is `NFR-2`'s third-party half for that gem and
the *only* place in the repository that floor may be stated (`CLAUDE.md`'s hard rule; design §3.4;
`serde/d15ade64`); and a new `Dexpace::Body` factory taking a value and a serde, which `SERDE-2` requires
("that media type MUST be used as the default Content-Type when a request body is created from a value plus a
Serde") and which phase 3b deliberately did not build — 3b's eight factories are `.bytes`, `.string`,
`.file`, `.stream`, `.chunked`, `.form`, `.multipart` and `.buffer`, and it "builds no witness, no codec and
no status-aware handler"
(`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md:557`). Adding a factory **widens**,
which `NFR-4`'s "disappears or narrows" lock permits.

### `7b` — Server-Sent Events (41 IDs, all `SSE`)

Scope in one sentence: the WHATWG line and field state machine over phase 3a's line primitive, the immutable
five-field event value, the resource-owning single-pass streaming facade with its four termination paths, and
the typed adapter with its three caller-supplied mapper outcomes.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `SSE-1`–`SSE-40` | 40 |
| ⏳ deferred, `DEF-8` (pre-existing, no phase trigger) | `SSE-41` (MAY, reactive-adapter error and lifecycle latitude) | 1 |
| **Total in budget** | | **41** |

Four rows carry a clause the checklist must state rather than tick:

- **`SSE-19` is a MAY the port takes, and it is `OI-5`'s resolution.** The chapter's own sanction is
  "a port MAY add a configurable cap and reject/truncate oversized lines, **documenting the divergence**"
  (`docs/product-spec/13-server-sent-events-and-streaming.md:33`); design §7.2 commits to it — "**SSE-19**'s
  optional line-length cap is implemented with a documented default, because an unbounded line from a hostile
  server is an unbounded allocation" (`sse-streaming/d935a6cd`). **No document anywhere fixes the value**,
  unlike the other three constants §10.18 catalogues. `7b` fixes it, documents the divergence, and closes
  `OI-5` — see the `OI-5` section.
- **`SSE-11` is a different cap and a MUST.** Ruby integers are arbitrary-precision and cannot overflow, so
  the port "documents a cap of 2^31−1 milliseconds and ignores any larger value, which preserves the
  requirement's observable behaviour … on a host where the stated failure mode is unreachable" (design §7.2,
  `sse-streaming/dff112ad`), catalogued in §10.18 beside `IO-9` and `BODY-32`. The row says explicitly that
  this is **not** the line cap, because `OI-5` currently conflates the two.
- **`SSE-30`'s asymmetry is two call sites, not two closes**, and `SSE-31`'s cross-thread close is a
  `Thread::Mutex`-protected flag held across the flip only. `cross-cutting-invariants/68aad33a` and design
  §7.2. The row names `Dexpace.close_quietly(resource, onto:)` as the quiet route so a second one is not
  written.
- **`SSE-40` is a SHOULD the port implements outright**, and its second clause is the one needing a guard —
  a view MUST NOT be taken twice over the same source, latched by `@viewed`. Design §7.2 calls it "a
  **SHOULD** the port implements, not a deferral" (`sse-streaming/b94ce49e`). The row must cite the corpus key
  by hand, because that key is filed under `PAGE-14` and `--req SSE-40` does not return it.

`7b` additionally ships, without owning a new ID: `Dexpace::Outcome`'s third variant in the `Dexpace::SSE`
namespace for `SSE-34`'s Skip and Done, per phase 4b's forward contract; and the `SSE-37` require-and-constant
audit, which becomes spec-forced boundary 5's mechanism if `7b` lands before `7c`.

### `7c` — Pagination (36 IDs, all `PAGE`)

Scope in one sentence: the two `Enumerator` views over one lazy drive routine with the engine owning the
in-flight page, the three built-in strategies, the byte-for-byte query splice, and the async engine driven
through the pivot's `#on_settle`.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `PAGE-1`–`PAGE-34`, `PAGE-36` | 35 |
| Implemented as vacuous by construction — the conditional antecedent is declined, not the requirement | `PAGE-35` (SHOULD) | 1 |
| **Total in budget** | | **36** |

Four rows carry a clause the checklist must state rather than tick:

- **`PAGE-35` is vacuous rather than declined, and the distinction is design §12's.** Its own text is
  conditional — "**If** a mutable paging-options object is offered to fetchers, the *same* instance SHOULD be
  threaded through every fetcher call" — and design §12's `PAGE` row settles it: "`PAGE-35` (SHOULD) is
  conditional on offering a mutable paging-options object; the port offers an immutable value instead, so the
  clause is vacuous rather than declined"
  (`docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:36`). A row marked ⏳ or 🚫 here would be
  wrong in both directions; the row states the antecedent and why it is false.
- **`PAGE-21`–`PAGE-24` are this subsystem's obvious-tool-is-wrong case and the tool is banned by
  measurement, not by taste.** `URI.decode_www_form("q=a+b")` returns `[["q", "a b"]]` and
  `URI.encode_www_form_component("a b")` returns `"a+b"` (verified fact 4) — both the exact inverse of
  `PAGE-22`'s "space → `%20`, literal `+` preserved as data". Design §7.1 and `pagination/86b5a3a3` reject
  the whole family; the rewriter tokenises the raw query substring by hand.
- **`PAGE-33` is discharged by documentation, and the row must say where.** "A port MUST **document** the
  inherent async cancellation race" — the requirement's satisfaction is a YARD block plus a stated behaviour
  (an already-dispatched request that completes after the abort is closed and discarded), not a test that can
  observe the race. The row names the YARD site.
- **`PAGE-12`'s one-slot look-ahead lives on the engine, not in the enumerator's closure.** Design §7.1 says
  so in as many words, and `pagination/9bdf90fc` records it; it is the direct consequence of boundary 14, and
  a row that ticks `PAGE-12` without naming where the buffered page lives has not checked the thing that
  makes it true.

`7c` additionally ships, without owning a new ID: the pagination half of spec-forced boundary 5's audit, if
`7c` lands before `7b`.

---

## Exclusions — IDs a reader would expect here, and the phase that owns each

| Excluded | Owning phase |
|---|---|
| `SEAM-19`–`SEAM-21`, `SEAM-23` — the codec seam's six methods, `.conforms?`, and the `Error`/`SerializationError`/`DeserializationError` hierarchy | 2, built. `7a` implements against them and adds no second seam and no second root |
| `SEAM-22` — the reflective generic type capture | 2, marked 🚫 with the reason attached; the surviving clause (`#load` takes an explicit witness, no witness-less overload) is phase 2's Task 12. The **witness protocol** §10.14 substitutes is `7a`'s work, but the ID's row is phase 2's and does not move |
| `SEAM-26`, `SEAM-27` — the operation-input projection seam | 2. `SERDE-2`'s Content-Type default is `7a`'s and is a body-factory concern, not an operation-projection one |
| `HTTP-44`, `HTTP-45` — the lazy typed-response wrapper, its `@state` memo and its mutex | 3b, built as `Dexpace::TypedResponse` over `Dexpace::_ResponseHandler`. `7a` supplies handlers into it |
| `HTTP-41`, `HTTP-42`, `BODY-14`, `BODY-16` — the response body, `#source`, the charset decode, the close-in-`ensure` readers | 3b, built. `OI-10`'s resolution put `#source` and a default no-op `#close` on `Dexpace::Body` |
| `BODY-30`, `HTTP-52` — the bounded buffered error-body copy | 3b (`Body.buffer_bounded`, `MAX_BUFFERED_ERROR_BODY_BYTES`) and 4b (`Recovery.buffer_error_body`, the one buffering call site). `SERDE-28`'s "bounded, buffered in-memory copy" consumes them and adds no second |
| `IO-14` — the line-reading primitive `#read_line_utf8`, and `#peek` | 3a, built. `7b`'s line machine is a different machine over the same primitive, which 3a's plan states as a boundary |
| `IO-9`, `BODY-32` — `MAX_MATERIALIZED_BYTES` | 3a, one ceiling, cited and never re-derived |
| `IO-6`, `BODY-8` — the two ownership rules | 3a and 3b. The **third** rule — a codec closes nothing — is `7a`'s and phase 3 declined to touch it |
| `RECOV-1`–`RECOV-16` — `Outcome`, `Success`, `Failure`, the two chains, the orchestrator | 4b, built. `7b` adds a third variant in its own namespace |
| `XCUT-9` — the cycle-safe cause walk | 4b, built as `Dexpace.each_cause`. Phase 9 audits the general rule |
| `SEAM-30`, `RECOV-12`, `DEF-27` — `Dexpace.close_quietly(resource, onto:)` | 2, 4b and 5b between them; the row closes in 5b. `SSE-30`, `PAGE-26` and `PAGE-32` are call sites |
| `PIPE-1`–`PIPE-40` — the stage runtime, the cursor, the fork primitive | 4c, built. Phase 7 installs no step and writes no second installation path |
| `PIPE-26`, `PIPE-27` — a pipeline is a transport; `#close` is a no-op on it | 4c, built, and written into 4c's forward table *for this phase* |
| `SEAM-11`, `SEAM-16`, `SEAM-17` — the transport and async seams and the pivot | 2 and 8. `7c`'s async engine consumes `Dexpace::Async::Future#on_settle`, phase 2's, and replaces nothing |
| `CFG-1`–`CFG-38`, `OBS-1`–`OBS-40` | 5. `PAGE-10`'s "documentation SHOULD direct production callers to set a finite cap" is a YARD obligation, **not** a configuration key, and `7c` adds none |
| `CFG-29`–`CFG-31` — RFC 1123 date formatting and parsing (`Dexpace::HTTPDate`) | 5a. `SERDE-24` is ISO-8601 and a different grammar; `7a` does not consume `HTTPDate` |
| `RETRY-30` — the iterative retry pump | 6a. `PAGE-31`'s trampoline is the same *pattern* over a different object and the specification's own latitude covers both |
| `RETRY-1`–`RETRY-45`, `REDIR-1`–`REDIR-28`, `AUTH-1`–`AUTH-38` | 6. Phase 6 cites no phase-7 ID and phase 7 cites no phase-6 one; the two are independent in both directions |
| `ASYNC-13` — the original-cause-unwrapped rule `PAGE-28` restates | 8. `PAGE-28` is `7c`'s and its Ruby realisation is `raise error, cause: nil` per `pipeline/f02559b9` |
| `ASYNC-21` — reactive-stream backpressure over an SSE source | 8, and **adapter-scoped and vacuous** (§11.21): no reactive adapter ships, and the property it protects is implemented anyway on the pull-based path (`SSE-39`). Not a phase-7 row |
| `TRANSPORT-18` — the re-subscribable body producer | 8, and near-vacuous for `Net::HTTP` (§11.18) |
| `HTTP-22`, `HTTP-48`, `HTTP-49`, `HTTP-50` — interning, ETag, Range, the conditional-request aggregator | Still deferred (`DEF-2`). Phase 6's correction floated phase 7 as the next target; **phase 7 declines it** — see the `DEF-2` section |
| `XCUT-12`, `XCUT-15`, `XCUT-19` | 9 dispositions. Phase 7 satisfies each by construction: `XCUT-12` through `SERDE-29`'s publication-safe caches, `XCUT-15` through `Data`-frozen collections, `XCUT-19` through 5b's redactor, which no phase-7 requirement calls |
| `NFR-1`, `NFR-2`, `NFR-3`, `NFR-4`, `NFR-11` | 0 built the machinery, 9 dispositions it. `7a` spends `dexpace-serde-json`'s `NFR-2` budget and asserts nothing about the gate |
| `docs/sdk-documentation/architecture.md` — "which gem to install, worked cross-gem examples" | A human, or a skill on request (`docs/README.md`). Phase 7 is the first phase after which the question has a second answer, and it is **not** a phase deliverable. Recorded here so the absence is a decision |

---

## Gap IDs: zero, and what that does and does not license

`ruby scripts/knowledge.rb --gaps SERDE,SSE,PAGE`, run 2026-09-10, reports (the trailing summary line
elided, the rest verbatim, so re-running it and diffing this block is not mistaken for drift):

```
SERDE — Serialization (Serde)
  30 canonical IDs: 30 substantive, 0 roll-up only, 0 uncited

SSE — Server-Sent Events and streaming
  41 canonical IDs: 41 substantive, 0 roll-up only, 0 uncited

PAGE — Pagination
  36 canonical IDs: 36 substantive, 0 roll-up only, 0 uncited
```

**Phase 7 is the first build phase in the roadmap with a zero gap set, and the roadmap said so in advance:**
the gap paragraph names phases 2, 3 and 4 and closes "Every other prefix has full corpus coverage"
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:161`). So the design-document obligation the roadmap
imposes — "budget the reading time in the phase's design document and say so there" (`:154-155`) — is
discharged by stating that the budget is zero, which this section is.

**What that does not license.** Three things, stated because "the corpus can answer every ID" is easy to
over-read into "the corpus is the reading":

1. **`--gaps` measures corpus coverage, not specification coverage** — `OI-12` states the same asymmetry from
   the other side, and phase 6's design restates it. All three chapters were read in full for this document
   anyway (57, 72 and 86 lines), which is cheap at that size.
2. **The `*Conformance:*` clauses appendix C does not carry are load-bearing here more than usual**, because
   this phase's requirements are mostly about *observable sequences* rather than values. `SSE-31`'s is the
   sharpest: "park a reader thread inside a blocking read, close from another thread, and assert an I/O-style
   error plus one release; separately close between pulls and assert a clean end" — two different test shapes
   for one requirement, and a sub-phase that reads only appendix C writes one of them.
3. **The roll-up density means a bare `--req` is the wrong query on this phase** (see *Corpus reading*). Zero
   gaps and a noisy `--req` are compatible facts about different measures.

---

## Convergence points — what needs two sub-phases, and what does not

A convergence point is a **test or a mechanism that cannot be written until two segments exist**, or that one
segment writes and another extends. It is not a build-order dependency, and a plan that treats it as one has
re-imposed the chain the split existed to avoid. There is exactly **one**, which is fewer than phase 6's
three and is the strongest single piece of evidence for the three-way cut.

1. **The `SSE-37` require-and-constant audit, extended over the pagination layer.** `SSE-37` forces the
   mechanism for `lib/dexpace/sse/**`; spec-forced boundary 5 extends it to `lib/dexpace/page/**` because
   §12's serde-agnosticism carries no ID. **Owned by whichever of `7b` and `7c` lands first**, which writes
   the audit; the other adds one path in a one-line diff. Both designs must say which side they are on, so
   the audit is neither written twice nor left to each assuming the other wrote it; under the recommended
   order the writer is `7b`. Neither blocks on the other: a sub-phase that runs first with no audit yet in
   place ships its own path, and the extension arrives with the second.

**What is *not* a convergence point, stated because a plan will reach for it.**

- **The "one cleanup story" of design §7.2 needs no coordination.** Its mechanism is design §7.1's rule and
  phase 2's `Dexpace::Closeable` latch, both built before phase 7 begins (`pagination/318ae05d`). A `7b` test
  that installs a page engine to observe the shared shape is testing phase 2's code, not phase 7's.
- **`SERDE-27`'s "stream the body through the deserializer" needs no page or event.** Its object is a
  `Dexpace::Response`, and phase 3b built every member it reads.
- **`PAGE-14` and `SSE-26`'s single-use guards are two flags on two objects.** The corpus entry that files an
  SSE rule under `PAGE-14` is a harvest attribution, not a shared implementation.

---

## Phase-level tasks owned by no sub-phase

**None, and that is worth stating rather than leaving to inference.** Phase 6 had three, each because it
installed steps into a shared runtime (`DEF-39`'s presets), emitted into a shared vocabulary (`DEF-42`) or
widened a shared type (`OI-31`). Phase 7 installs nothing into the pipeline, ships no preset, emits no
instrumentation event required by any of its 107 IDs, and widens no phase-4 type. Every task it has belongs to
exactly one of its three segments.

Two items are **owed outside this document's own scope** and are recorded here so they are not discovered
later:

- **The `knowledge-lookup` skill's audit-group table is owed a thirteenth row**, *Serialization, SSE and
  pagination*, whose exact content is given under *Corpus reading*. That is an edit to
  `.claude/skills/knowledge-lookup/SKILL.md` and not to a frozen tree, and the roadmap's first retrospective
  rule wants it in place before the first sub-phase runs the group.
- **`CLAUDE.md`'s phase-directory claims sentence goes stale the moment this document is filed.** It reads
  "There are seven phase directories under `docs/work/*/`" and enumerates `phase0/` through `phase6/`; filing
  this document creates `docs/work/mvp/phase7/` and makes it eight. The probe's `claims` check reads that
  numeral, so it is mechanically caught — it is corrected by hand in the change that files this document,
  together with the phase-7 entry in the enumeration and its sub-phase description.

---

## `OI-5`: resolved by `7b`, and the requirement ID its resolution names is wrong

**Decision: `OI-5` is resolved in `7b`, by the stated route — the cap lives at the line-machine level — and
the requirement that obliges it is `SSE-19`, not `SSE-11`.**

`OI-5` (opened 2026-09-08, `docs/open-items.md:224-268`) records that phase 3a's `P3-4` widens `IO-9`'s SHOULD
so that `MAX_MATERIALIZED_BYTES` guards every operation producing one contiguous `String`, and that
`#read_line_utf8` is the one drain-style read left outside that guard and cannot be inside it: "`IO-14` fixes
no maximum line length, so there is neither a count to check up front nor an end to stop at but a terminator
that may never arrive." Its stated resolution is exactly the right one:

> Phase 7 supplying `SSE-11`'s cap **at the line-machine level**, so the bound is one documented number in the
> layer that knows what a line means, resolves it for the only consumer in the MVP. Adding a
> `max_line_bytes:` keyword to `#read_line_utf8` would not …

**The route is right and the ID is wrong, and the substitution matters rather than being a citation nit.**

- **`SSE-11` is the `retry` field's magnitude cap.** Canonical text: "The `retry` field value MUST be
  accepted only if it consists solely of ASCII digits `0`-`9`; a leading sign, an embedded non-digit, an
  empty value, or a value exceeding the maximum representable millisecond magnitude MUST cause the field to
  be ignored" (`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md:420`). Design §7.2
  cashes it out as "a cap of 2^31−1 milliseconds", and §10.18 catalogues that number beside `IO-9`'s 64 MiB
  and `RECOV-34`'s ~292 years. It has nothing to do with line length.
- **`SSE-19` is the line-length cap.** Chapter 13: "The parser MAY accept arbitrarily long lines/values with
  no built-in size cap; the reference imposes none. **This is a potential unbounded-memory surface for
  untrusted servers**; a port MAY add a configurable cap and reject/truncate oversized lines, documenting the
  divergence" (`docs/product-spec/13-server-sent-events-and-streaming.md:33`). Design §7.2 takes the option:
  "**SSE-19**'s optional line-length cap is implemented with a documented default, because an unbounded line
  from a hostile server is an unbounded allocation."
- **The failure mode of the mis-citation is concrete and silent.** A `7b` author reading `OI-5`, looking up
  `SSE-11`, and implementing the 2^31−1 ms retry cap has satisfied a MUST, ticked a checklist row, and left
  `#read_line_utf8` exactly as unbounded as `OI-5` found it — while `OI-5` looks discharged. `SSE-11` is a
  MUST and `SSE-19` a MAY, so the two rows do not even sit at the same level of obligation.
- **The same mis-citation is carried by phase 3a's `P3-4` deviation row**, verbatim: "the caller that reads
  lines from a hostile stream is phase 7's SSE machine, which `SSE-11` obliges to carry its own documented
  cap (`OI-5`)"
  (`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md:1109`), and by `OI-5`'s own
  `Cites:` line, which lists `IO-9, IO-14, SSE-11, SSE-12, BODY-32` and omits `SSE-19`. The likely origin is
  benign: §10.18 does list `SSE-11` "in the same breath as `IO-9`'s", because both are platform-constant
  substitutions, and §7.2 discusses both caps in adjacent sentences.

**What `7b` therefore owes, stated so the resolution is checkable rather than declarative.** Three things,
none of them settled here:

1. **A value for the line cap**, which no document in the repository currently fixes — unlike the other three
   §10.18 constants, all of which have numbers. `R4` is where `7b` picks it.
2. **The documented divergence `SSE-19` requires as the price of taking the option**, and a decision on
   whether that divergence joins §10.18's list or takes a §10 row of its own. `7b`'s ledger decides; this
   document does not.
3. **A statement, in the same YARD block, that this is the bound `OI-5` names** — so the relationship between
   3a's ceiling and 7b's cap is visible from the code and not only from a register. `OI-5`'s own warning
   applies: the cap must not be "a second, lower, silent cap underneath" 3a's, and at the line-machine level
   it is not underneath — it is in the layer that knows what a line is, which is the whole of the argument.

**`SSE-11`'s row in `7b`'s checklist stays a separate row and says so explicitly**, because two caps and one
citation is how this got confused once already.

The ID correction is proposed as an **amendment to `OI-5`'s resolution text and its `Cites:` line**, and a
matching one to `P3-4`'s row, in the findings below. Neither is acted on by this document.

---

## `DEF-2`: the phase-7 target is declined, and what the row actually needs

**Decision: phase 7 declines `DEF-2`'s floated target, and what the row needs is not a fourth phase but the
event shape.**

Phase 6's register sweep left the row here (`docs/deferred-items.md:79-88`):

> **Correction, 2026-09-09 (phase 6 segmentation design): the phase-6 target does not fire.** … The row stays
> **deferred and is still not UNSCHEDULED** … **What is owed is a new target or the event shape** — phase 7's
> pagination and conditional-request interplay is the next candidate, and the alternative is the event shape
> `DEF-33` and `DEF-3`'s `BODY-36` half were given.

`DEF-2` covers `HTTP-22` (MAY, header-name interning), `HTTP-48` (SHOULD, an ETag helper modelling the three
RFC 7232 forms with `etagc` validation and raw-form round-tripping), `HTTP-49` (SHOULD, a Range helper) and
`HTTP-50` (SHOULD, a conditional-requests aggregator emitting `If-Match`/`If-None-Match` and
`If-Modified-Since`/`If-Unmodified-Since`). Four checks, each against the canonical text:

1. **`HTTP-22` is untouched by phase 7**, as it was by phase 6. Nothing here interns a header name.
2. **`HTTP-50` has no caller.** `PAGE-23` requires that "following an absolute/whole next URL MUST instead
   swap only the request's URL, **preserving the template's method, headers, and body**"; `PAGE-21`–`PAGE-24`
   change only the query, and `PAGE-24` requires every non-query component to survive exactly. `SSE-38`
   positively **forbids** the SSE layer from setting a request header. So phase 7, like phase 6, *carries*
   whatever conditional headers the caller supplied and constructs none.
3. **`HTTP-49` has no caller.** The three built-in strategies are cursor, page-number and Link; no `PAGE`
   requirement mentions `Range`, `Content-Range` or `206`.
4. **`HTTP-48` gets its nearest miss in the whole roadmap, and it is still a miss.** `SERDE-28` is the first
   requirement anywhere in the specification that names an entity-tag in an executable clause: on a non-2xx,
   non-4xx/5xx status the handler "MUST close the response and raise a serde exception whose message leads
   with the status code and **preserves conditional/redirect context (e.g. ETag / Location)**"
   (`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md:478`). But what it requires is
   that the **raw header values reach the message**, not that they be parsed: `HTTP-48`'s helper validates
   `etagc` characters, rejects an empty strong opaque and rejects unterminated forms, and running a
   *malformed* server `ETag` through a validating parser inside an error path would turn a diagnostic into a
   second failure. `7a` reads the header string and copies it. `HTTP-48` remains a helper for the SDK's
   consumers, unbuilt.

**The pattern behind all of this, stated once so the row stops being re-targeted phase by phase.** The SDK
never *originates* a request. Every request in the system either comes from the caller or is a derivation of
one — the redirect re-issue (`REDIR-3`/`REDIR-4`/`REDIR-5`), the retry resend, the auth replay
(`AUTH-30`), and now the pagination next page (`PAGE-23`) — and **every one of those four derivations is
spec-required to preserve headers rather than add them.** A conditional-request helper is fired by a caller
constructing a conditional request, and the only such caller is an SDK author outside this repository. So
no remaining build phase will fire the condition either: phase 8's transports dispatch what they are given,
phase 9 audits, phase 10 reconciles.

**Therefore the alternative phase 6 already named is the right one: give `DEF-2` the event shape.** The
proposed pick-up event, stated so a human can file it verbatim: *the first consumer that constructs a
conditional request — a worked example in `docs/sdk-documentation/`, a `dexpace-conformance` fixture, or a
downstream SDK's `SEAM-26` operation projection asking for one.* That is the shape `DEF-33` has ("a non-CRuby
row is added to the CI matrix. No phase in v1 plans one") and `DEF-3`'s `BODY-36` half has, and it is honest
in a way a fifth phase target would not be.

**The row's status does not change and `UNSCHEDULED` still does not apply**, by the register's own definition
and by phase 6's reading of it: that status is for a row whose pick-up condition a phase *met and declined to
act on*, and phase 7 does not meet the condition — it merely, like phase 6, fails to fire it. Filed as a
finding below.

**One consequence outside `docs/deferred-items.md`.** `docs/first-release.md:32-33` carries `HTTP-48`,
`HTTP-49`, `HTTP-50` and `HTTP-22` in its readiness list on the same reasoning phase 6 found stale. That line
needs the same amendment, and it is named in the findings so the two registers do not diverge.

---

## Prerequisites, and the decisions phase 7 inherits

Every surface below was verified to exist and to be stated as shipping by the named phase's design, on
2026-09-10. **A sub-phase design must not cite one this document did not verify.** Nothing is implemented
yet in this repository — these are design commitments, and phase 7's sub-phases inherit them as such.

**From phase 0** — the seventeen blocking gates. Five bite here:

- `gates:require_allowlist`, with **`json` on the *denylist* by name** and the reason attached: "`SEAM-2`: the
  wire codec is a seam. The codec lives in `dexpace-serde-json` and the `>= 2.19.9` floor lives in that
  gemspec and nowhere else" (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:459`).
  Core may `require` only `monitor`, `uri`, `stringio`, `strscan`, `time`, `date`, `securerandom`, `digest`,
  `openssl`, `forwardable`, `set`, `singleton` — **`uri`, `strscan`, `stringio` and `time` are already on it,
  so no phase-7 sub-phase needs an allowlist diff in core.**
- The **adapter extension** to the same audit: every `require` in an adapter must be allowlisted, or under
  `dexpace/`, or the single third-party gem that adapter's gemspec declares (`:471-475`). This is what makes
  `7a`'s gemspec-line-before-first-require ordering a build constraint.
- `gates:gemspec_audit`, enforcing `NFR-2`'s core-plus-at-most-one budget, with a `two_third_party` negative
  fixture. `7a` is the first sub-phase to spend an adapter's third-party half.
- The clean-bundle isolation run, on every Ruby in the matrix.
- The five custom cops — `Dexpace/SpdxHeader`, `Dexpace/NoTimeParse`, `Dexpace/NoUriDefaultParser`,
  `Dexpace/NoLocaleCaseFold`, `Dexpace/NoThreadInterrupt` (`:523`) — plus phase 2's sixth,
  `Dexpace/QualifiedCoreConstant`, which names `JSON` and `lib/dexpace/serde/**` explicitly.
- The gem skeleton itself: `gems/dexpace-serde-json` at `0.0.0` with a real gemspec declaring `dexpace-core`
  and nothing else, `lib/dexpace/serde/json.rb`, `sig/`, `test/`, and a Steep target with two signature roots
  (`:254-260`; `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md:2629-2630`).

**From phase 1** — `Dexpace::Request`, `Response`, `Headers`, `Query`, `MediaType`, `Status`, `Method`,
`Protocol`, `HeaderName` and their builders; `Dexpace::Model` with its `.build`-routing `#with` override
(`data-modeling/83610619`) and `Model.required!`; `Dexpace::URL.parse!` and `.external_form`;
`Dexpace::Error` as a **module**. `MediaType#charset` returns `nil` for an absent **or**
unknown-to-this-Ruby charset, which is why `HTTP-42`'s fallback needs no second validation.

**From phase 2** — `Dexpace::Serde`, the six-method codec duck type with `.conforms?`, and the
`Error`/`SerializationError`/`DeserializationError` hierarchy with a **class** root that includes
`Dexpace::Error` (`P2-2`, and the rule it fixes: "the SDK root is a module, a seam-local root with no
competing family is a class") (`docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md:942-1005`);
`Dexpace::Closeable`, the idempotent ownership-aware release latch; `Dexpace::Cancellation` and its
`Source`/`Subscription`; the async pivot as **`Dexpace::Async::Future`, `Dexpace::Async::Completer` and
`Dexpace::Async::Settlement`** — *not* `Dexpace::Future`/`Dexpace::Completer` — with `Future#on_settle`,
`#value(cancellation:)`, `#wait` and `#cancel`; the `SEAM-11`/`SEAM-16` in-memory fakes; and
`Dexpace/QualifiedCoreConstant`. **`Dexpace::Hooks` is a `private_constant` with no `sig/` mirror and no
manifest row — phase 7 cannot cite it as an interface surface.**

**From phase 3a** — `Dexpace::IO::BufferedSource` with `#read_into`, `#read`, `#readpartial`, `#getbyte`,
`#each`, `#peek`, `#slice`, `#read_exactly`, `#read_string(encoding, count: nil)`, `#read_utf8` and
**`#read_line_utf8`**, whose bound is documented as the caller's (`OI-5`); `.over(body)` taking **no**
ownership (`message-bodies/f060d944`) and `.wrapping(io)` taking it (`IO-6`); `BufferedSink`;
`Dexpace::IO::Buffer`; `Dexpace::IO::MAX_MATERIALIZED_BYTES`; `Dexpace::StreamError < ::IOError` and
`Dexpace::EndOfStreamError < ::EOFError`; `Dexpace::IO::_Chunked`. `IO-40` forbids this layer from owning any
timeout (`resource-management/d1f16cad`), so neither `7b`'s reader nor `7c`'s engine imposes one.

**From phase 3b** — `Dexpace::Body` with `#write_to`, `#media_type`, `#content_length`, `#replayable?`,
`#to_replayable`, `#each`, `#source` (default **raises** `Dexpace::StreamError` naming the class) and
`#close` (default **no-op**), the include order fixed as `include Dexpace::Body` then
`include Dexpace::Closeable` so `Closeable#close` wins where a body owns something (`OI-10`, resolved,
`P3-23`); the eight factories `.bytes`, `.string`, `.file`, `.stream`, `.chunked`, `.form`, `.multipart`,
`.buffer`; `Body.buffer_bounded(body, cap:)` and `MAX_BUFFERED_ERROR_BODY_BYTES` (1 MiB, **3b's constant**);
`Response#close`, `#body_string` and `#body_bytes`, with the decode written as retag-then-transcode and both
encodings named; **`Dexpace::TypedResponse.new(response:, handler:)`** over
**`Dexpace::_ResponseHandler` — `def call: (Dexpace::Response) -> untyped`** — validated by
`respond_to?(:call)`, with `HTTP-44`'s four-state `@state` memo, a memoized failure re-raised as the same
object, and `HTTP-45`'s mutex held only across the flip. **3b builds no witness, no codec and no
status-aware handler** and says so.

**From phase 4b** — `Dexpace::Outcome` with `Success` and `Failure` (`.build`, `#success?`, `#failure?`,
`#response_or_nil`, `#error_or_nil`, `#fold`); `Dexpace::Suppressible`, `Dexpace.attach_suppressed` with the
self-suppression skip, and `Dexpace.suppressed`, with the **frozen-primary** caveat stated;
`Dexpace.each_cause`, cycle-safe by reference identity; `Dexpace.close_quietly(resource, onto:)`;
`Dexpace::ProtocolError` with `.for` and `.for_or_nil`; `Recovery.buffer_error_body(response)` as the **one**
buffering call site; and the `RECOV-2` fatal-family split — `rescue ::StandardError` converts,
`rescue ::Exception` re-raises unchanged. The re-raise spelling is `raise error, cause: nil` wherever core
re-raises an error it is *carrying* (`pipeline/f02559b9`), which `PAGE-28`'s "surfacing the *original*
underlying cause (unwrapping any future-composition wrapper)" is a call site for.

**From phase 4c** — `Dexpace::Pipeline` (`.builder`, `.direct`, `#call`, `#steps`, `#entries`, `#transport`,
`#close`) and `Dexpace::AsyncPipeline` (`.direct`, `.map_response`, `#call` returning a
`Dexpace::Async::Future`), with `PIPE-26`/`PIPE-27` written into 4c's forward table **for this phase**: a
built pipeline is a transport by phase 2's duck type, and `Pipeline#close` is a no-op on it. Phase 7 installs
no step, so nothing else of 4c's is in phase 7's reach.

**From phase 5** — nothing is required by any of the 107 IDs, and that is worth stating rather than leaving
implicit: no phase-7 requirement names a configuration key, an instrumentation event, a log level or a clock.
Two adjacencies exist and neither is a dependency: `PAGE-10`'s "documentation SHOULD direct production callers
to set a finite cap" is a YARD obligation and not a `CFG` key, and `SSE-30`'s out-of-band report route is
`Dexpace.close_quietly(resource, onto:)`, whose `onto:`-absent diagnostic 5b supplies and whose contract is
phase 2's and 4b's.

**From phase 6** — nothing, in either direction. Phase 6 cites no phase-7 ID and phase 7 cites none of
phase 6's.

**The independence statement each sub-phase design must make in its own Prerequisite section.** For every one
of the three, the *real* dependencies are on phases 0–4 in the list above; **the dependency on the other two
sub-phases of phase 7 is empty, with no exception at all** — not even the qualified one phase 6 had to make
for `OI-31`'s cursor widening. Anything a plan schedules behind another sub-phase is convenience.

---

## Cross-cutting constraints that bite phase 7 specifically

- **An `Enumerator` abandoned mid-`#next` never runs its `ensure`, and neither does an ordinary `#each`.**
  This is the constraint phase 7 exists downstream of. It reaches every one of `PAGE-11`, `PAGE-12`,
  `PAGE-14`, `PAGE-15`, `SSE-24`, `SSE-25`, `SSE-26` and `SSE-40`, and it is already paid for: design §7.1's
  rule, `pagination/318ae05d` and `/b2a85752`, phase 2's `Dexpace::Closeable`, phase 3's owning objects. No
  phase-7 sub-phase re-derives it and none writes a `block_given?` guard as a defence.
- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** `SSE-31` requires `close()` to be safe from a
  different thread than the one iterating, with the closed state guarded atomically; `HTTP-45`/`SERDE-27`'s
  memo is 3b's already. Design §7.2 holds the flag under a mutex; the rule is that it is held across the flag
  flip **only** and never across a read, a parse or any suspension point (`serde/97665a9a`,
  `concurrency-and-async` notes). `SERDE-29`'s "non-blocking, publication-safe updates rather than coarse
  locks" is the same rule from the other side and is `XCUT-12`'s shape.
- **Bytes on the wire are `Encoding::BINARY`, and the decode is retag-then-transcode with both encodings
  named.** `io-and-byte-streams/6eb5155f` and `/a44b4de6`, `OI-7`. `String#b` is the retag idiom;
  `force_encoding` raises on a frozen chunk. Every encoding assertion in `7a` and `7b` uses non-ASCII content,
  because an ASCII-only fixture passes under exactly the bug.
- **`downcase` takes no arguments and `URI::RFC3986_PARSER` is pinned.** `PAGE-18`'s `rel` token match,
  `SSE-7`'s field-name comparison and `PAGE-19`'s reference resolution are the three sites.
- **Regexp timeouts are per-pattern.** `PAGE-18`'s link-value grammar is not regular; `7c` writes a state
  machine rather than a pattern, and the anchored patterns that do appear (`SSE-11`'s digit screen,
  `PAGE-22`'s percent-decode) carry their own `Regexp.new(source, timeout:)` if they need one.
- **Deadlines are explicit values, not ambient interrupts, and `Timeout.timeout`/`Thread#raise`/`Thread#kill`
  are forbidden.** `PAGE-25`'s "cancelling/completing the walk's result future MUST halt the walk … and
  best-effort abort the in-flight exchange" is cooperative: it settles a `Dexpace::Async::Future` and cancels
  a transport future. `SSE-31`'s cross-thread close tears the resource down and lets the blocked read fail;
  it does not interrupt the reading thread. `PAGE-36`'s per-call overrides are values threaded to every page
  exchange.
- **`Ractor` is never load-bearing.** `SSE-20`/`SSE-21` and `PAGE-2` get immutability from `Data` and
  `Dexpace::Model`; shareability is a side effect and no part of any claim.
- **`SEAM-2`: core names no concrete implementation.** It bites hardest here because this is the phase with a
  concrete implementation in it. `Dexpace::Serde::JSON` appears in no core file, in no core `sig/` file
  (`NFR-11`) and in no core test.

---

## Verified Ruby facts that shaped this cut

All verified on **3.4.10** (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`), the only
interpreter available to this document, against `json` **2.9.1** — the version design §3.4 records Ruby 3.4.10
as shipping. **Where a fact needs the 3.2 floor or the 4.0 column to be load-bearing, that is said rather than
assumed**; the sub-phase designs run the three-interpreter check this document could not.

1. **Ruby's stdlib `json` has no incremental parser, and `JSON.parse` cannot be handed a stream.**
   `JSON.parse(StringIO.new(%q({"a":1})))` raises `TypeError: no implicit conversion of StringIO into String`;
   `JSON.load` *does* accept an IO and returns `{"a" => 1}`, and `JSON.load` is the method design §3.4 bans by
   lint rule. `JSON.singleton_methods` on 2.9.1 offers `parse`, `parse!`, `load`, `unsafe_load`, `load_file`
   and the generators, and **nothing pull-shaped**. That matters because `SERDE-27` requires a handler to
   "stream the response body directly through the deserializer into the target value (**without first
   materializing the whole body**)". The seam's own shape is what makes the requirement satisfiable at all:
   `#load(source, witness)` takes the source, so the *handler* performs no materialization and hands the
   `BufferedSource` straight down; the *adapter* then drains to EOF into one `String` under `IO-9`'s 64 MiB
   ceiling. **The reference's bounded-memory property is not available on stdlib `json`, and `7a` must argue
   that clause explicitly rather than tick it.** `R1`.
2. **`JSON::ParserError` is `JSON::JSONError` is `StandardError` — and is nowhere near `IOError`.**
   Ancestors on 2.9.1: `[JSON::ParserError, JSON::JSONError, StandardError, Exception]`. So `SERDE-12`'s
   "a genuine stream I/O error MUST propagate unwrapped and MUST NOT be re-wrapped as a serde exception" is
   satisfied **structurally** by `rescue ::JSON::JSONError`: a `Dexpace::StreamError`, which is an `::IOError`
   (3a's), cannot be caught by it. `7a` writes no `rescue StandardError` in the codec path, and the row states
   the ancestry as the reason rather than the discipline.
3. **`Data#with` copies the struct and shares its members.** With `E = Data.define(:id, :data)` and
   `a = ["x"]`, `E.new(id: "1", data: a).with(id: "2").data.equal?(a)` is **true**. That is the fact behind
   `SSE-20`'s second clause — "any copy-with-changes operation MUST likewise copy the data list" — and it is
   already discharged for this port by `data-modeling/83610619`: `Dexpace::Model#with` routes through the
   type's own validating `.build`, so an `SSE::Event` that includes `Dexpace::Model` re-owns its list through
   the same path that owns it at construction. `7b` gets `SSE-20` from the module rather than from a bespoke
   `#with`, and its test asserts the mutate-the-original case on both construction and derivation.
4. **Ruby's query helpers are the exact inverse of `PAGE-22` in both directions.**
   `URI.decode_www_form("q=a+b")` returns `[["q", "a b"]]` — a literal `+` read back as a space — and
   `URI.encode_www_form_component("a b")` returns `"a+b"` — a space encoded as `+`. `PAGE-22` requires
   "space → `%20`, literal `+` preserved as data … a literal `+` reads back as `+`". Design §7.1 and
   `pagination/86b5a3a3` reject the whole family on exactly this ground; measured here so `7c`'s design cites
   a number rather than a recollection.
5. **`Time#iso8601` round-trips exactly and is not what `Dexpace/NoTimeParse` bans.**
   `Time.utc(2026,9,10,12,0,0).iso8601` is `"2026-09-10T12:00:00Z"` and `Time.iso8601` of that is `==` the
   original. The cop bans `Time.parse`, `Date.parse` and `DateTime.parse` (phase 0's table), not
   `Time.iso8601`, so `SERDE-24`'s "whichever form is chosen, the encoding MUST round-trip to the same
   instant" is satisfiable under the ban with `time` — already on core's allowlist and legitimately
   `require`d by the adapter.
6. **`JSON.parse` performs no coercion, and a `Hash` distinguishes an absent key from a present null
   directly.** `JSON.parse(%q({"n":"5"}))["n"]` is `"5"`, never `5` — which is `SERDE-21` satisfied by the
   codec doing nothing. `JSON.parse(%q({"x":null})).key?("x")` is `true` with value `nil`, and
   `JSON.parse("{}").key?("x")` is `false` — which is `SERDE-16` and `SERDE-17` satisfied without the
   field-default machinery `SERDE-17` describes, because `SERDE-17`'s asymmetry is a key-oriented codec's
   problem and Ruby does not have it (`serde/5fe8e3ed`). `7a`'s `SERDE-17` row states the vacuity with the
   measurement rather than emulating the reference's hook.
7. **The UTF-8 BOM is the three bytes `[239, 187, 191]`.** `SSE-12` requires a single leading BOM consumed
   through **non-consuming lookahead** so a non-BOM prefix is left intact and a mid-stream BOM survives as
   data; 3a's `#peek` is the lookahead. Trivial, and recorded because a `7b` implementation that consumed
   three bytes unconditionally would pass every BOM-prefixed fixture and corrupt every stream without one.

---

## Deferrals filed by phase 7

**None, and that is deliberate.** A segmentation design decides a cut; it does not decide the interfaces whose
absence a deferral records. Phase 4 filed `DEF-35` only because it was a **scope disposition** — an entire ID
cluster moving to another phase. Phase 7 has no such candidate: every one of its 107 IDs is implemented here
or already carries a pre-existing row (`DEF-8`).

**Two rows are expected of the sub-phases** and are named in the risks so their absence later is visible:
`7a`'s disposition of `SERDE-27`'s no-materialization clause against verified fact 1 (`R1`), and `7b`'s
disposition of the `SSE-19` line cap's value and its documented divergence (`R4`).

### Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every row.
All forty-two were read. As with phases 3, 4, 5 and 6, this document **states** each disposition and the
sub-phase **performs** the register edit.

**Phase 7 touches four rows: it carries one as a ⏳ line, declines one target, and leaves two whose
conditions its own work bears on. It closes none outright and files none.**

- **`DEF-8` — carried as a ⏳ row in `7b`, not picked up, and its condition is not met.** `SSE-41` (MAY) is
  "scoped to a reactive (e.g. RxJS-analogue) adapter; the MVP ships only the pull-based SSE view and no
  reactive adapter", with pick-up "revisit if a reactive SSE adapter is ever built"
  (`docs/deferred-items.md:158-165`). Phase 7 builds none. The row is a ⏳ **inside** `7b`'s 41, exactly as
  phase 6 counted its three `DEF-6` rows inside `6a`'s 60. Design §11.21 and §12's `SSE` row both record the
  same disposition, and §11.21 adds the part a checklist would otherwise miss: `ASYNC-21`, the MUST that
  presupposes the same adapter, "is listed as adapter-scoped-and-vacuous rather than as either satisfied or
  deferred", and "the backpressure property it protects is implemented anyway on the pull-based path
  (**SSE-39**)". `7b` does **not** carry an `ASYNC-21` row; it is phase 8's.
- **`DEF-2` — stays deferred, the phase-7 target is declined, and the row needs the event shape.** Argued in
  full above. Filed as a finding.
- **`DEF-24` — untouched by phase 7, and phase 4 is where it closes.** The row defers "the suppressed-exception
  trail on the error root" and its `Cites:` line names `PAGE-13`, `PAGE-15`, `SSE-29` and `SSE-36` — four
  phase-7 IDs — but its pick-up condition is "phase 4 … with the recovery chain that is its first caller"
  (`docs/deferred-items.md:377-378`), and phase 4b's design ships `Dexpace::Suppressible`,
  `Dexpace.attach_suppressed` and `Dexpace.suppressed`. **Phase 7 is a consumer of the row's subject, not its
  owner**, and it writes no second trail and no second skip. The row's status moves when phase 4 executes,
  not when phase 7 does.
- **`DEF-16` — untouched, and phase 7 is what makes its condition checkable rather than what meets it.**
  `dexpace-serde-oj` waits for "when JSON throughput is identified as a bottleneck the stdlib `json` gem
  cannot clear". `7a` ships the first codec against which such a measurement could be taken, and design §3.4's
  "it keeps the door open for `dexpace-serde-oj` without a second code path in core" (`serde/66ebd950`) is a
  constraint on how `7a` writes the adapter — one code path, all policy at the seam — rather than a task.
- **`DEF-29` — untouched, and its condition is still not met.** "The first consumer outside `dexpace-core`.
  Phase 8 at the earliest." `7a`'s codec assertions have exactly one adapter to run against and live in that
  gem's own suite (spec-forced boundary 8), so they strengthen the row without meeting it — the same
  disposition phase 3a gave its three fakes.
- **`DEF-3`, `DEF-23`, `DEF-26`, `DEF-33`, `DEF-34` — untouched**, all phase-3-or-earlier subjects or
  matrix-gated. `DEF-26` is worth naming: it was picked up in phase 3b and narrowed `Request#body` and
  `Response#body` in `sig/`, which is the type `7a`'s `SERDE-2` factory returns into.
- **`DEF-1`, `DEF-4`–`DEF-7`, `DEF-9`–`DEF-15`, `DEF-17`–`DEF-22`, `DEF-25`, `DEF-27`, `DEF-28`, `DEF-30`,
  `DEF-31`, `DEF-32`, `DEF-35`–`DEF-42` — untouched**, all either closed by an earlier phase, targeted at
  phase 6 or 8, or riding on a post-v1 gem. Two are worth naming because a reader will wonder: `DEF-25`
  (wire-boundary re-validation of header names and outbound values) is phase 8's, and `SERDE-2`'s stamped
  `Content-Type` is among the values it will re-validate; `DEF-18`'s three unsatisfied MUSTs are phase 8's and
  **phase 7 adds no fourth**.

### The findings proposed for the registers

Four, described here for a human to file. **None is acted on by this document, none carries a number, and no
register file is edited by it.**

**Target register: `docs/open-items.md`, as an amendment to the existing `OI-5` row (not a new row).**
**`OI-5`'s resolution names `SSE-11`, and the requirement that obliges the line cap is `SSE-19`.** `SSE-11`
is the `retry` field's magnitude cap — a MUST, cashed out by design §7.2 as 2^31−1 milliseconds and
catalogued in §10.18 beside `IO-9`'s 64 MiB. The line-length cap is `SSE-19`, a MAY, whose chapter text
supplies the sanction ("a port MAY add a configurable cap and reject/truncate oversized lines, documenting
the divergence") and which design §7.2 commits the port to taking. The failure mode is silent and specific: a
`7b` author who implements `SSE-11`'s cap has satisfied a MUST, ticked a row, and left `#read_line_utf8`
exactly as unbounded as `OI-5` found it. The amendment is to the resolution text and to the `Cites:` line,
which currently reads `IO-9, IO-14, SSE-11, SSE-12, BODY-32` and should carry `SSE-19`. Cites: `IO-9`,
`IO-14`, `SSE-11`, `SSE-12`, `SSE-19`, `BODY-32`.

**Target register: `docs/deviations.md`, or wherever `P3-4`'s as-built text is audited.**
**Phase 3a's `P3-4` deviation row carries the same mis-citation and needs the same one-word correction.** Its
text reads "the caller that reads lines from a hostile stream is phase 7's SSE machine, which `SSE-11`
obliges to carry its own documented cap (`OI-5`)"
(`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md:1109`), and the same sentence appears
in 3a's plan at `:1831` and `:2157`. Nothing about `P3-4` itself changes — the widening it records is right
and unaffected — only the ID it hands forward. Recorded separately from the `OI-5` amendment because it is an
edit to a phase document rather than to a register, and because a corrected register row pointing at an
uncorrected deviation row is how a correction gets lost.

**Target register: `docs/deferred-items.md`, as a second amendment to `DEF-2`'s pick-up condition; and
`docs/first-release.md`, on the same reasoning.**
**`DEF-2`'s phase-7 target does not fire either, and what the row needs is the event shape rather than a
fifth phase target.** Phase 7 carries conditional headers and constructs none: `PAGE-23` preserves the
template's method, headers and body and changes only the URL; `SSE-38` forbids the SSE layer from setting a
request header at all; no `PAGE` requirement mentions `Range`. `SERDE-28` is the nearest miss anywhere in the
specification — it requires a 304's exception message to preserve "conditional/redirect context (e.g. ETag /
Location)" — and it is satisfied by copying the raw header value, not by `HTTP-48`'s validating helper, which
would turn a malformed server `ETag` into a second failure inside an error path. The pattern is structural
rather than accidental: the SDK never originates a request, and all four derivations it performs (redirect
re-issue, retry resend, auth replay, pagination next page) are spec-required to preserve headers rather than
add them — so no remaining build phase fires the condition. The proposed event: *the first consumer that
constructs a conditional request — a worked example in `docs/sdk-documentation/`, a `dexpace-conformance`
fixture, or a downstream SDK's `SEAM-26` operation projection asking for one*, which is the shape `DEF-33`
and `DEF-3`'s `BODY-36` half already have. The row stays **deferred and still not UNSCHEDULED**, by the
register's own definition. `docs/first-release.md:32-33` carries the same four IDs on the same stale
reasoning and needs the matching amendment. Cites: `HTTP-22`, `HTTP-48`, `HTTP-49`, `HTTP-50`, `PAGE-23`,
`SSE-38`, `SERDE-28`.

**Target register: `docs/open-items.md`.**
**Two corpus entries file a phase-7 rule where a phase-7 prefix query cannot reach it.**
`sse-streaming/5f4803a0` states the Ruby realisation of `SSE-26`/`SSE-40` — the `@viewed` latch on the SSE
`Enumerable` view — and carries **only `PAGE-14`**, because it is harvested from design §7.2's sentence that
mentions `PAGE-14` by way of comparison; so `--req SSE-26` and `--req SSE-40` miss it and `--req PAGE-14`
returns an SSE rule to a pagination author. And `pagination/b2a85752`, the note that widens the
`Enumerator`/`ensure` rule to an ordinary `#each` and closes the `block_given?` escape hatch, carries **no
requirement ID at all**, so `--prefix PAGE` misses it while its narrower companion `pagination/318ae05d` is
returned. Neither is a defect in the rules; both are attribution artefacts of the same species as `OI-16` and
`OI-24`, and both are the kind that costs a phase a rule rather than a query. Nothing is broken today because
nothing has been implemented. Cites: `SSE-26`, `SSE-40`, `PAGE-11`, `PAGE-12`, `PAGE-14`.

**One row explicitly does not close.** `OI-7`'s subject is a sentence in the frozen §3.1, and phase 7 consumes
the corrected recipe without touching the mechanism; the item resolves when §3 is next deliberately amended
by a human, as the row itself says.

---

## Risks and open questions the sub-phase designs must resolve

Each is named with the sub-phase that owns it. **None is decided here.** Risk numbering restarts per phase in
this repository — phase 3's ran R1–R10, phase 4's R1–R14, phase 5's R1–R15 and phase 6's R1–R15 — so phase
7's are `R1`–`R12` and collide with none.

**R1 — `7a`: `SERDE-27`'s "without first materializing the whole body", against a codec with no incremental
parser.** Verified fact 1: `JSON.parse` cannot be handed a stream, `JSON.load` can and is banned, and `json`
2.9.1 offers nothing pull-shaped. The seam's shape means the *handler* materializes nothing — it hands
`#load` the `BufferedSource` — while the *adapter* drains to EOF into one `String` under `IO-9`'s ceiling.
`7a` decides whether that is `SERDE-27` satisfied (the requirement's object being the handler's behaviour) or
a deviation to argue (the requirement's *purpose* being bounded memory), states which, and if it is a
deviation numbers it `P7-<n>` and names the obligation it puts on `dexpace-serde-oj` and on any future
adapter whose library does have a pull parser. It also states what `MAX_MATERIALIZED_BYTES` does on a
response larger than the ceiling, which is the observable behaviour a caller will meet.

**R2 — `7a`: the witness protocol's public surface, and how much of it `NFR-4` locks.** Design §7.3 names
`.dexpace_load(parsed, ctx)`, `#dexpace_dump`, `Dexpace::Serde.witness!(w)` and four combinators
(`List.of`, `Map.of`, `Nullable.of`, `Tristate.of`). Every one of those is public API the moment it ships,
and `api-design/b0e18938`'s minimal-surface rule and `execution-context/b58728da`'s `private_constant`
finding are the two inputs. `7a` also decides what `ctx` **is** — §7.3 names it and nothing in the repository
defines it — and whether the combinator set is closed or extensible.

**R3 — `7a`: where the two response handlers live and what they are called.** `SERDE-27`'s streaming handler
and `SERDE-28`'s status-aware one are both `Dexpace::_ResponseHandler`s over 3b's `TypedResponse`, and 3b
deliberately left the naming open. `7a` decides, and states how `SERDE-28`'s 4xx/5xx branch reaches
`Recovery.buffer_error_body` (4b's **one** buffering call site) without core's serde layer acquiring a
`Recovery` dependency it does not want — or states that it legitimately may, since both are core.

**R4 — `7b`: the value of `SSE-19`'s line cap, its configurability, and its documented divergence.** No
document fixes it, unlike §10.18's other three constants. `7b` picks a number, decides whether `SSE-19`'s
"configurable" is taken (which raises `DEF-34`'s shape — a cap with no configuration source behind it is
`DEF-28` without `DEF-28`'s pick-up condition, and `OI-5` says so explicitly about a keyword on
`#read_line_utf8`), decides whether an oversized line rejects or truncates, and decides whether the divergence
joins §10.18's list or takes a `P7-<n>` row. It also writes the YARD sentence that makes the relationship to
3a's ceiling visible from the code.

**R5 — `7b`: what `Dexpace::Outcome`'s third variant is called and where it lives.** Phase 4b fixed that it
is "in the SSE namespace and never by adding one here". `SSE-34` names three outcomes — value, Skip, Done —
and only two need constructors. `7b` decides whether Skip and Done are frozen singletons (the `Tristate`
sentinel shape, with `#to_s`/`#inspect` overridden for the reason `SERDE-30` gives) or `Data` types, and
whether `Dexpace::Outcome#fold` extends to three arms or the SSE adapter folds separately.

**R6 — `7b`: `SSE-31`'s two test shapes, and whether the blocked-read half is reproducible.** The
requirement's own conformance clause asks for both: "park a reader thread inside a blocking read, close from
another thread, and assert an I/O-style error plus one release; separately close between pulls and assert a
clean end." Phase 3a proved the second shape is writable with `IO.pipe` (`IO-38`'s cross-thread close), and
`DEF-33` records that the guarantee's *interesting* half is not reproducible on CRuby. `7b` states which of
its assertions distinguish a correct implementation from an incorrect one on the matrix as it stands, and
writes no test that passes on the floor and fails to reproduce elsewhere — phase 4c's `P4-33` is the
precedent for why that matters.

**R7 — `7c`: what a pagination strategy is handed, and what the built-in three take.** `PAGE-5` fixes the
contract and spec-forced boundary 4 fixes the serde-agnosticism, but the *shape* is open: does
`Dexpace::Page::CursorStrategy` take a `Dexpace::Serde` duck type plus a witness, a plain
`#call(response) -> [items, cursor]` extractor, or both? `PAGE-16`'s "single read of the response body" and
`PAGE-5`'s "MUST NOT close or mutate the response" are the constraints; `NFR-4` locks whatever ships. `7c`
decides, and states why the alternative it did not take would not have re-introduced the `7a` edge.

**R8 — `7c`: `PAGE-15`'s wrapping clause, which has no Ruby antecedent.** "When exposed through a stream
whose terminal cannot declare the underlying I/O error type, it MUST be re-thrown wrapped so the caller can
still catch it at the close site." Ruby has no checked exceptions and no terminal that cannot declare a type
(§11.15's family), so the clause's antecedent may be false here — which would make it vacuous, like
`PAGE-35`. `7c` decides whether it is vacuous or whether the second half ("when both held pages fail to
close, the first failure MUST propagate with the second attached as suppressed") is the whole of the ID in
this port, and states which, because a row that ticks both halves without checking has not read the
antecedent.

**R9 — `7c`: the async engine's executor mode against a library that owns no thread pool.** `PAGE-29`
requires "a mode running the driver — and therefore every consumer invocation — on a caller-supplied
executor", and `PAGE-30` requires a rejected re-dispatch to fail the walk and close any staged page. Phase
5a's `Dexpace::Async.delay` **raises `Dexpace::SeamError` when `Fiber.scheduler` is `nil`** (`P5-9`), and
`6a` faces the same question under its own `R2`. `7c` decides what a caller-supplied executor is in this port
(a duck type with `#post`? the `SEAM-16` async seam? a `Dexpace::Async::Thread` pool, which is phase 8's),
and states what happens with no scheduler and no executor.

**R10 — `7c`: whether `PAGE-6`'s zero-exchange guarantee survives the async engine's own exception.**
`PAGE-6` says the non-blocking engine "has no separate lazy 'obtain' step — invoking a walk method is itself
the consumption trigger and begins fetching immediately". That is an explicit carve-out, and a checklist row
that asserts "zero exchanges on construction" uniformly across both engines asserts something the requirement
does not say. `7c` states the two assertions separately.

**R11 — phase-level: who writes spec-forced boundary 5's audit if the sub-phases run out of order.** This
document assigns it to whichever of `7b` and `7c` runs first; under the recommended order that is `7b`. Both
designs must say which side they are on and that the other adds one path rather than a second audit. A design
that silently re-implements it, or one that assumes the other wrote it, is the failure this risk exists to
name.

**R12 — `7a`: the `dexpace-serde-json` suite's shape, given that phase 9 owns the reusable form.** Spec-forced
boundary 8 keeps phase 7 out of `dexpace-conformance`. `7a` decides how much of `SERDE-3`'s close-counting
tracker, `SERDE-4`'s offset/overflow matrix and `SERDE-9`'s type-escape assertions are written as
adapter-local tests versus as objects shaped so phase 9 can lift them, and it names the target in its
checklist so phase 9 inherits one rather than reconstructing it. `DEF-22`'s framework-agnostic assertion
objects are the shape phase 8 will build; `7a` should not pre-empt them and should not ignore them either.

---

## Deviation Ledger

**Empty.** This document decides no deviation from the reference contract. Every mechanism substitution phase
7 relies on is already catalogued in
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` — items 6 (`:58-62`, the
core-owned suppressed trail, which `PAGE-13`, `PAGE-15`, `SSE-29`, `SSE-30` and `SSE-36` consume), 12
(`:87-91`, the stream-ownership rule whose third clause is the codec's), 13 (`:92-96`, four encode profiles,
two of which are one Ruby type), 14 (`:97-102`, the witness protocol) and 18 (`:119-124`, the
platform-constant substitutions, which names `SSE-11`) — and in §11 items 15, 17, 18 and 21, and is cited
above rather than re-argued. The sub-phase designs will have ledgers of their own; a deviation decided by any
of them is numbered `P7-<n>` and consolidated into design §10. Two are already foreseeable and are named in
`R1` and `R4`.

**Two refinements to the roadmap, stated here because the roadmap requires a corrected cell to be corrected in
place with the correction stated.** Neither changes the cut, the letters or the count, which is why they are
refinements rather than corrections — phases 3, 4 and 6 each found a stated *reason* false and this one does
not.

**First: the two independence claims are not equally enforced, and the bullet reads as though they are.** The
segmentation rule's phase-7 bullet says "The cut is spec-forced and so is the independence: `SSE-37` is a MUST
that core parsing and streaming hold no serialization dependency, and §12's chapter intro requires the
pagination engine to be transport-agnostic and serde-agnostic, with `PAGE-8` keeping the engine stateless and
shareable." Every clause is true, and the two halves have different force: `SSE-37` is a MUST with a
conformance clause and a **mechanised require audit** (design §7.2), while §12's serde-agnosticism is chapter
prose that the chapter's own "A port MUST preserve …" sentence does not enumerate and that no `PAGE` ID
carries. So the property `7c` and `7a` are independent *because of* is, today, enforced by nothing. **The
bullet's second half should read: §12's chapter intro requires the pagination engine to be transport-agnostic
and serde-agnostic — a property that carries no requirement ID, so phase 7's segmentation design extends
`SSE-37`'s require audit over core's pagination layer to make it a gate rather than a convention** (spec-forced
boundary 5). Everything else in the bullet is confirmed unchanged and correct.

**Second: the second gem's boundary falls inside `7a`, not at a sub-phase boundary, so it does not change the
cut the way the phase-8 bullet says four gems will change phase 8's.** The bullet closes "This is also the
phase that ships the workspace's second real gem, `dexpace-serde-json`", which is right and leaves open what
follows from it. What follows is: nothing. Phase 0 built the gem's skeleton, its gemspec, its entry file, its
`sig/`, its `test/` and its Steep target; `7a` adds one `add_dependency` line and fills `lib/`; and 27 of the
30 `SERDE` IDs are satisfied in core rather than in the gem, so a gem-shaped cut would be strictly linear.
The segmentation rule's "ships more than one gem" trigger **is** met by phase 7 and **is** discharged by the
three-way cut, which is a different thing from the gem forcing the cut.

**Neither is filed as an open item, and the judgement is deliberate**, on the same reasoning phase 6 gave for
its own roadmap correction (`docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md:1272-1278`).
`OI-1`, `OI-2`, `OI-12`, `OI-15`, `OI-21`, `OI-29` and `OI-31` each record a sentence that reads correctly and
resolves to something that is not there. These two sentences resolve to things that *are* there and are
correct as far as they go; what they need is a clause each, which is a correction-in-place — the roadmap has
taken three already (the phase-3 bullet on 2026-09-08, the phase-4 and phase-6 bullets on 2026-09-08 and
2026-09-09). Filing an open item for a sentence that is true would dilute a register whose value is that
every row is a real find.

**Two consequences outside this document's own scope to fix, recorded so they are not discovered later.**

- **The roadmap edit itself is owed.** This document is constrained to write one file and cannot make it.
- **`CLAUDE.md`'s phase-directory claims sentence and the `knowledge-lookup` audit-group table are both
  owed**, as set out under *Phase-level tasks owned by no sub-phase*.
