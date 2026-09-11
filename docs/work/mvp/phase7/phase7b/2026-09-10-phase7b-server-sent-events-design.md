# Phase 7b — Server-Sent Events

**Status:** Draft, for review. Written 2026-09-10, against
`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`, which is this sub-phase's charter.

**Path:** `docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events-design.md`. That is the
path this document carries for the rest of its life and the one every citation of it should use. Its
plan is `docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events.md`; the checklist is
written at execution time and is not a deliverable of either.

## Purpose

Sub-phase 7b builds the Server-Sent Events subsystem in full: the WHATWG line and field state machine,
the immutable five-field event value, the resource-owning single-pass streaming facade with its four
termination paths, and the typed adapter with its three caller-supplied mapper outcomes. Forty-one
requirement IDs, `SSE-1`–`SSE-41`, of which forty are implemented and one (`SSE-41`) is carried as a
⏳ row under the pre-existing `DEF-8`. It is the second-largest sub-phase in the roadmap after `6a`'s
sixty and phase 3b's forty-nine.

It also owns the resolution of **`OI-5`**, the register row phase 3a opened against `#read_line_utf8`,
and the charter assigns it the mechanism for **spec-forced boundary 5** — the `SSE-37` require audit,
extended over core's pagination layer — if it lands before `7c`.

**Five decisions the charter named and declined to make are made here.** `R4` (the line cap), `R5`
(the third mapper outcome), `R6` (`SSE-31`'s two test shapes) and `R11` (the audit's ownership) are
the charter's own; the fifth is not in the charter's list at all and is the finding that reshaped this
document:

> **`7b` cannot build its line machine on phase 3a's `#read_line_utf8`, and design §7.2's sentence
> saying it does is wrong on the one clause that matters.** `IO-14` is normative that "a lone `'\r'`
> not followed by `'\n'` MUST be kept as part of the line's content"
> (`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md:103`); `SSE-2` is
> normative that "a CR not followed by LF terminates the line by itself" (`…appendix-c…:411`). Those
> are contradictory grammars over the same three bytes. Phase 3a implemented `IO-14` faithfully — "a
> lone `\r` is content" (`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md:659`)
> — so the method design §7.2 says the SSE machine sits on cannot recognise the terminator `SSE-2`
> requires. This is not a naming quibble: it changes what `OI-5` is resolving, which is why `R4` below
> is three corrections rather than one.

## Governing documents

- `docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md` — the charter. It fixes `7b`'s 41
  IDs (`:700`), the twenty-four spec-forced boundaries (`:484`), the five rejected cuts, the single
  convergence point (`:850`), the `OI-5` correction (`:900`) and risks `R4`, `R5`, `R6` and `R11`.
  `R1`–`R3` and `R12` are `7a`'s; `R7`–`R10` are `7c`'s.
- `docs/product-spec/13-server-sent-events-and-streaming.md`, read in full (72 lines), together with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` rows 410–450 for the
  canonical text of all 41 IDs. Both were read: the chapter carries `*Conformance:*` clauses appendix
  C does not, and **appendix C carries a clause the chapter's `SSE-19` row has and appendix C's drops**
  — see the findings.
- `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` §7.2 in full (`:48-98`), and §7.1's
  close-on-abandon rule (`:11-28`) which §7.2 reuses by name.
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1's encoding boundary and §3.7's
  close contract; `docs/sdk-design-ruby/04-domain-model-construction.md` for `Data` plus
  `Dexpace::Model`.
- `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items **6**
  (`:58-62`, the core-owned suppressed trail, naming `SSE-29`, `SSE-30`, `SSE-36`) and **18**
  (`:119-124`, the platform-constant substitutions, naming `SSE-11`); §11 item 17 (`:56-58`, no
  strict-WHATWG mode) and item 21 (`:73-81`, `ASYNC-21` adapter-scoped-and-vacuous); §12's `SSE` row
  (`docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:37`).
- The predecessor designs whose forward tables this document cites rather than re-derives:
  `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md`,
  `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md`,
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md`,
  `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md`,
  `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`,
  `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`,
  `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`.
- `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-design.md` and
  `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` as the two worked
  examples of this document's form; 3b is the closer analogue, being the other streaming,
  lifetime-sensitive sub-phase.
- `docs/open-items.md` (`OI-5` at `:224-268`, `OI-7`, `OI-10`, `OI-12`), `docs/deferred-items.md`
  (`DEF-8` at `:157-164`, `DEF-33`), `docs/deviations.md`, `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

---

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run first, exactly as `CLAUDE.md`'s workflow step 1
requires.

- `ruby scripts/knowledge.rb --origin note --brief` — **38 entries across 19 note files**. Narrowed to
  this sub-phase's prefix, `--origin note --prefix SSE` returns **nothing**: there is no note anywhere
  in the corpus filed against an `SSE` ID. The notes that reach `7b` reach it through the surfaces it
  consumes, and they are named individually below.
- `ruby scripts/knowledge.rb --section conflicts --brief` — **18 Conflicts entries, every one of them
  in `notes/`**, which means every recorded styleguide-versus-design contradiction is resolved.
  **None is open, and none carries an `SSE` ID.** `7b` inherits no unresolved conflict and owns no
  conflict decision of its own.

**Corpus coverage: complete.** `--prefix-info SSE` reports "41 of 41 IDs have a substantive entry, 0
are roll-up only, 0 are uncited"; `--gaps SSE` closes with "0 of 41 IDs in 1 prefix have no substantive
entry". **`7b`'s spec-reading budget is zero**, which discharges the roadmap's obligation
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:154-155`) to budget the reading and say so.
Both the chapter and the 41 appendix-C rows were read in full anyway, at 72 and 41 lines, which is
cheap at that size and is where three of this document's five findings came from.

### The audit group this sub-phase ran

`ruby scripts/knowledge.rb --prefix SSE --section rules` — **42 entries across 3 topic files**
(`sse-streaming`, `cross-cutting-invariants`, `message-bodies`), and **zero of them roll-up-tagged**.
The charter measured the same thing across all three phase-7 prefixes and recorded why: on this phase
the roll-ups live entirely in the `Reference` section, so the audit group is clean even where a bare
`--req` is noisy (`--req SSE-1` returns 17 entries of which most are appendix-B roll-ups). **A `7b`
task queries `--req <ids> --section rules,constraints,conclusions`, never a bare `--req`.**

The group was **incomplete as run**, and that is the point of the next section: `--prefix SSE`
does not return `sse-streaming/5f4803a0` or `/b94ce49e`, two SSE rules the corpus files under
`PAGE-14`. Both were recovered by querying `--topic sse-streaming` directly, and both are in scope.
`--section constraints` and `--section conclusions` on the same topic were also read, because `SSE-18`
and `SSE-37` live in Constraints and seven design conclusions live in Conclusions, and a `--section
rules` group returns none of them.

**The charter's thirteenth audit-group row is still owed.** Its exact content is given at
`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md:212`. It is an edit to
`.claude/skills/knowledge-lookup/SKILL.md`, which is not a frozen tree; this document is constrained
to write two files and cannot make it either. It is named again in the findings so two documents
asking for it is not mistaken for it having happened.

### The corpus-navigation defects this sub-phase found

The charter named one and asked `7b` to check for others. There are **four**, and three of them point
the same way — at the `SSE-11`/`SSE-19` conflation `OI-5` fell into.

1. **`sse-streaming/5f4803a0` files an SSE rule under `PAGE-14` only** (the charter's find). Its
   text — "An SSE `Enumerable` view must not be taken twice over the same source … the facade
   enforces this by latching a `@viewed` flag on first call and raising on a second" — is the Ruby
   realisation of `SSE-26` and `SSE-40`. `--req SSE-26` and `--req SSE-40` miss it.
   <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:84-87` · high · sha:4bf713047534</sub>
2. **`sse-streaming/b94ce49e` does the same thing in the `Conclusions` section**, and the charter did
   not have it: "The single-use guard on the SSE `Enumerable` view is a SHOULD requirement that the
   port implements outright rather than deferring. (`PAGE-14`)". So the SHOULD-is-implemented
   disposition for `SSE-40` is also unreachable from `SSE-40`.
   <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:86-87` · high · sha:4bf713047534</sub>
3. **`sse-streaming/dff112ad` files the `retry` magnitude cap under `(SSE-11, SSE-19)`** — both IDs on
   one entry — so `--req SSE-19` returns an entry that is entirely about 2^31−1 **milliseconds** and
   says nothing about line length. This is the corpus-level origin of `OI-5`'s mis-citation, and it is
   the one navigation defect that has already cost the repository something.
   <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:55-60` · high · sha:4bf713047534</sub>
4. **`sse-streaming/7adc2212` files the BOM lookahead under `(SSE-12, SSE-11)`**, the same artefact in
   the other direction: `--req SSE-11` returns a BOM rule.
   <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:54-55` · high · sha:4bf713047534</sub>

All four are attribution artefacts of harvesting a design sentence that *mentions* a neighbouring ID,
not defects in the rules themselves. They are filed as one register finding below.

### The five entries that bind `7b`, cited by key

- **`sse-streaming/ebb489ba`** — `SSE-37`'s mechanism: "Core's SSE layer must have zero serde
  dependency, and this boundary is checked mechanically by a require audit rather than by code review."
  This is what makes `7b`'s independence from `7a` a gate rather than a claim.
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:96-97` · high · sha:4bf713047534</sub>
- **`data-modeling/83610619`** — the note that makes `SSE-20` cheaper than §7.2 makes it look.
  `Data#with` does not call an `initialize` override on Ruby 3.2 and does on 3.4 and 4.0, so
  `Dexpace::Model` overrides `#with` to route through the type's own validating `.build`. An
  `SSE::Event` including `Dexpace::Model` therefore re-owns its data list on every `#with` through the
  same path that owns it at construction, which is exactly `SSE-20`'s second clause.
  <sub>review · `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` · high · sha:manual-phase1-data-with</sub>
- **`io-and-byte-streams/a44b4de6`** — binds the line machine directly. `force_encoding` raises
  `FrozenError` on a frozen `String` **even when the target encoding is already the string's own**, and
  the chunks reaching a `BufferedSource` are routinely frozen; `String#b` is the retag idiom. The
  companion trap makes a green suite lie: appending a non-ASCII UTF-8 `String` to a BINARY one silently
  retags the result to UTF-8 while appending an ASCII-only one leaves it BINARY — so **an ASCII-only
  SSE fixture passes under exactly the bug**. Every `7b` encoding test uses non-ASCII content.
  <sub>review · `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` · high · sha:manual-phase3a-frozen-ingress-retag</sub>
- **`io-and-byte-streams/6eb5155f`** — the single decode boundary is **two steps**, retag then
  transcode, and the transcode must name its target encoding explicitly, because `String#encode` with
  `undef: :replace` and no target destroys every byte at or above `0x80` and follows
  `Encoding.default_internal`, a process global the host sets. `7b`'s data lines cross this boundary
  and `P7-26` below is where.
  <sub>review · `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` · high · sha:manual-phase3b-decode-retag-then-transcode</sub>
- **`pagination/318ae05d`** and **`pagination/b2a85752`** — the `Enumerator`/`ensure` rule and the half
  that closes the `block_given?` escape hatch. The first records that the owning object with its own
  `ensure` and its own `#close` is a **phase-3 obligation** discharged through phase 2's
  `Dexpace::Closeable`, so "phase 7 inherits a rule already paid for rather than discovering it". The
  second records that an `ensure` inside a plain `def each` behaves exactly like an `Enumerator.new`
  block under external iteration, and that `block_given?` is **true** inside `#each` reached through
  `to_enum(:each)` and `#next` — so a `raise unless block_given?` guard forbids nothing. Both were
  re-measured for this document (verified fact 6).
  <sub>review · `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md` · high · sha:manual-phase3-enumerator-range</sub>
  <sub>review · `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` · high · sha:manual-phase3b-each-method-abandonment</sub>

**One corpus entry is contradicted by two MUSTs, and `7b` does not follow it.**
`sse-streaming/2dba42b0` says the convenience view "reuses one reader instance so per-stream state
(consumed BOM, **current retry value, last event id**) is preserved across pulls", harvested verbatim
from design §7.2's `:79-84`. `SSE-16` is a MUST that "**only** the 'BOM already consumed' flag persists
across calls; the last-event-id is NOT carried forward", and `SSE-38` is a MUST that the subsystem
"MUST NOT persist a last-event-id across events (see `SSE-16`)". `SSE-40`'s own canonical text says
"per-stream state (**e.g. BOM consumption**)" and names nothing else. `7b` persists the BOM flag and
nothing else, and the note a human should file for this is drafted in the findings.

---

## Scope: the 41 IDs

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `SSE-1`–`SSE-40` | 40 |
| ⏳ deferred, `DEF-8` (pre-existing, no phase trigger) | `SSE-41` (MAY, reactive-adapter error and lifecycle latitude) | 1 |
| **Total in budget** | | **41** |

Level split, from appendix C: **36 MUST, 3 SHOULD (`SSE-21`, `SSE-22`, `SSE-40`), 2 MAY (`SSE-19`,
`SSE-41`)** — 36 + 3 + 2 = 41, matching `--prefix-info SSE` and the charter's reconciliation table.
No `MUST NOT` row appears in the prefix.

**`SSE-41` is confirmed correctly deferred and is carried, not implemented.** `DEF-8`
(`docs/deferred-items.md:157-164`) was read in full: deferred by the MVP scope design on 2026-09-05,
because `SSE-41` is "MAY-level, and scoped to a reactive (e.g. RxJS-analogue) adapter; the MVP ships
only the pull-based SSE view and no reactive adapter", with the pick-up condition "revisit if a
reactive SSE adapter is ever built". Phase 7 builds none, so the condition is not met and the row's
status does not change. Design §12's `SSE` row and §11.21 record the same disposition. **`7b` carries
`SSE-41` as a ⏳ checklist row inside its 41**, exactly as phase 6a counted its three `DEF-6` rows
inside `6a`'s 60. **`7b` carries no `ASYNC-21` row**: §11.21 lists that MUST as
adapter-scoped-and-vacuous, it is phase 8's, and the backpressure property it protects is implemented
here anyway on the pull-based path (`SSE-39`).

### Five rows the checklist must state rather than tick

Each is a row that will be marked ✅ and whose ✅ means something other than "a test asserts the
behaviour". Recording them here is what stops a ✅ from being reconstructed later as a guess.

- **`SSE-19` is a MAY the port takes, and it is `OI-5`'s resolution.** The row cites `R4` below, names
  both constants and their values, states that an over-long line is **rejected and never truncated**,
  and states in the same row that this is **not** `SSE-11`'s cap. `SSE-11`'s row stays a separate row
  and says the same thing from the other side, because two caps and one citation is how this got
  confused once already.
- **`SSE-18` is satisfied by omission and by documentation.** "A single reader instance MUST be driven
  from one thread at a time; the parser offers no thread-safety for concurrent `next()` calls. A port
  MAY leave the parser non-thread-safe." `7b` leaves it non-thread-safe, takes the MAY, and the row's
  evidence is a YARD block on `Dexpace::SSE::Reader` plus the absence of any lock in that class — **not**
  a test, because there is no assertion that distinguishes "documented single-threaded" from
  "accidentally single-threaded". The one lock in the subsystem is the facade's (`SSE-31`), and it is
  on a different object for a different reason.
- **`SSE-21` and `SSE-22` are SHOULDs the port implements outright.** `SSE-21`'s equality, hash and
  string form over five fields are `Data`'s, free (`sse-streaming/e5e6eea7`); `SSE-22`'s predicate is
  four lines. Neither is deferred and neither row is ⏳.
- **`SSE-40` is a SHOULD the port implements outright**, and its second clause — MUST NOT be taken
  twice over the same source — is the one needing a guard. The row must cite `sse-streaming/5f4803a0`
  and `/b94ce49e` **by hand**, because both are filed under `PAGE-14` and `--req SSE-40` returns
  neither.
- **`SSE-37`'s evidence is a gate, not a test.** Its three prohibitions are one prohibition with three
  faces: no serialization dependency (mechanised, `R11`), no built-in done-sentinel and no
  error-envelope recognition (asserted by test, because no scanner recognises a sentinel string
  generically). The row names the gate task and the two tests separately.

### Canonical text quoted because a decision below turns on it

- **`SSE-2`** — "Line termination MUST recognize all three SSE-legal terminators — LF (`'\n'`), CR
  (`'\r'`), and CRLF (`'\r\n'`) — treating CRLF as a single terminator, with terminators stripped from
  line content; **a CR not followed by LF terminates the line by itself.**"
  (`…appendix-c…:411`.)
- **`IO-14`**, phase 3a's, quoted beside it — "readUtf8Line() MUST read up to and consume the next line
  terminator … treating both `'\n'` and `'\r\n'` as terminators; … and **a lone `'\r'` not followed by
  `'\n'` MUST be kept as part of the line's content.**" (`…appendix-c…:103`.)
- **`SSE-19`**, chapter form, which carries the sanction — "The parser MAY accept arbitrarily long
  lines/values with no built-in size cap; the reference imposes none. This is a potential
  unbounded-memory surface for untrusted servers; **a port MAY add a configurable cap and
  reject/truncate oversized lines, documenting the divergence.**"
  (`docs/product-spec/13-server-sent-events-and-streaming.md:33`.)
- **`SSE-19`**, appendix-C form, which does not — "The parser MAY accept arbitrarily long lines / data
  values with no built-in size cap; the reference implementation imposes no maximum line **or event
  size** (a growable byte accumulator expands by doubling)." (`…appendix-c…:428`.) The second sentence
  of the chapter row is absent, and the phrase "or event size" is present here and absent there. Both
  halves of that asymmetry are load-bearing below.
- **`SSE-11`** — "The `retry` field value MUST be accepted only if it consists **solely of ASCII digits
  `'0'`-`'9'`**; a leading sign, an embedded non-digit, an empty value, or a value exceeding the maximum
  representable millisecond magnitude MUST cause the field to be ignored …" (`…appendix-c…:420`.)
- **`SSE-16`** — "The reader MUST be single-pass and stateful: **only** the 'BOM already consumed' flag
  persists across calls; the last-event-id is NOT carried forward …"
  (`docs/product-spec/13-server-sent-events-and-streaming.md:30`.)
- **`SSE-31`**'s conformance clause, which asks for two different test shapes for one requirement —
  "park a reader thread inside a blocking read, close from another thread, and assert an I/O-style
  error plus one release; separately close between pulls and assert a clean end."
  (`docs/product-spec/13-server-sent-events-and-streaming.md:53`.)
- **`SSE-34`** — "a value is yielded to the consumer; a **Skip** result silently drops the event and
  advances to the next (never surfacing to the consumer); a **Done** result ends iteration cleanly and
  closes the underlying stream/resource without yielding a model for the sentinel event itself."
  (`…appendix-c…:443`.)

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `IO-14` — `#read_line_utf8` itself, and `#peek` | 3a, built. `7b` consumes `#peek`, `#getbyte` and `#skip` and **does not consume `#read_line_utf8`** — `P7-20` is why, and it is a change to what the charter's boundary 15 assumed |
| `IO-9`, `BODY-32` — `MAX_MATERIALIZED_BYTES` | 3a, one ceiling, cited and never re-derived. `7b`'s two caps are different bounds at a different layer and neither lowers 3a's |
| `IO-40` — the no-timeout rule on the streaming layer | 3a, and it binds: neither `7b`'s reader nor its facade imposes a read timeout (`resource-management/d1f16cad`) |
| `HTTP-41`, `HTTP-42`, `BODY-14`, `BODY-15` — `Dexpace::ResponseBody`, `#source`, the charset decode, `#close` | 3b, built. `SSE-32`'s convenience consumes them |
| `HTTP-44`, `HTTP-45` — the lazy typed-response wrapper and its mutex | 3b. `7b` writes no second memo and no second lock; the facade's lock is `SSE-31`'s and guards a different thing |
| `RECOV-1`–`RECOV-16` — `Outcome`, `Success`, `Failure`, the chains, the orchestrator | 4b, built. `7b` adds a variant in **its own** namespace and adds no member to any of them (`P7-23` states what that costs) |
| `RECOV-12`, `SEAM-30`, `DEF-27` — `Dexpace.close_quietly(resource, onto:)` | 2, 4b and 5b between them. `SSE-30`'s swallow route is a call site; `7b` writes no second quiet-close path |
| `XCUT-9` — the cycle-safe cause walk | 4b, built as `Dexpace.each_cause`. `7b` walks no `#cause` chain by hand |
| `SERDE-1`–`SERDE-30` | `7a`. `SSE-37` positively forbids `7b` from naming any of it |
| `PAGE-1`–`PAGE-36` | `7c`. The one thing shared is the close-once discipline, whose mechanism is phase 2's `Dexpace::Closeable` |
| `ASYNC-21` — reactive-stream backpressure over an SSE source | 8, and adapter-scoped-and-vacuous (§11.21). **Not a `7b` row**, and `SSE-39` is where the property it protects is actually implemented |
| `CFG-1`–`CFG-38` | 5. No `SSE` requirement names a configuration key and `7b` adds none — `R4`'s configurability is two constructor keywords, not a `CFG` entry |
| `OBS-1`–`OBS-40` | 5. No `SSE` requirement requires an instrumentation event. `SSE-30`'s out-of-band report is `close_quietly`'s `onto:`-absent diagnostic, which 5b already supplies |
| A strict-WHATWG mode | Nobody. §11.17 resolves the chapter's preamble: "the deviations are replicated … and no strict mode ships in the MVP" |

---

## Prerequisites, and the independence `7b` states in its own words

### `7b` depends on no other phase-7 sub-phase, with no exception at all

The charter requires each sub-phase design to state this rather than inherit a chain by habit
(`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md:461-466`), and the roadmap's phase-7
bullet requires it in as many words. `7b` states it:

- **`7b` does not depend on `7a`.** It is forbidden to. `SSE-37` is a MUST with a conformance clause,
  and design §7.2 mechanises it as a require audit. `7b` writes no `require` of `dexpace/serde`, names
  no `Dexpace::Serde` constant, ships no done-sentinel string and no error-envelope recognition. The
  typed adapter (`SSE-33`–`SSE-36`) takes a **caller-supplied** mapper and yields whatever the mapper
  returns; no codec appears anywhere in the subsystem. A `7b` task scheduled behind `7a`'s witness
  protocol has re-imposed a chain `SSE-37` forbids.
- **`7b` does not depend on `7c`.** Nothing in chapter 13 reads a page and nothing in chapter 12 reads
  an event. The one shared thing is the close-once discipline, and its mechanism — "resource
  acquisition and release never live inside an `Enumerator` block; the engine owns the resource in its
  own scope with its own `ensure` and exposes `#close`" — is design §7.1's rule, recorded by
  `pagination/318ae05d` as a **phase-3 obligation**, discharged through phase 2's
  `Dexpace::Closeable`. Both sub-phases write their own owner over the same already-built latch.
  `SSE-26`'s single-pass guard and `PAGE-14`'s single-use guard are two `@viewed`-style flags on two
  unrelated objects.
- **The one thing `7b` and `7c` share is a *tool*, not a dependency**: spec-forced boundary 5's audit.
  `R11` below resolves it in both directions and neither ordering blocks the other.
- **`7b` does not depend on phase 6.** Phase 6 cites no phase-7 ID and phase 7 cites no phase-6 one.

**`7b`'s real dependencies are on phases 0, 1, 2, 3a, 3b and 4b**, listed below. Every surface named
was verified to exist and to be stated as shipping by that phase's design, on 2026-09-10. Nothing is
implemented yet in this repository; these are design commitments and `7b` inherits them as such.

### From phase 0 — the seventeen blocking gates, unchanged and unlowered

Four bite here.

- **`gates:require_allowlist`**, with core's allowlist being `monitor`, `uri`, `stringio`, `strscan`,
  `time`, `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`, and **`json`
  on the denylist by name** (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:459`).
  **`7b` requires nothing at all outside `dexpace/`** — no allowlist diff, no new stdlib name. That is
  worth stating as a positive fact rather than an absence: an SSE parser is a place a `strscan` or a
  `stringio` reaches for reflexively, and neither is needed once the line machine reads bytes from a
  `BufferedSource`.
- **`gates:gemspec_audit`** — untouched; `7b` writes only into `dexpace-core`, whose
  `runtime_dependencies` stay empty.
- **The five custom cops** — `Dexpace/SpdxHeader`, `Dexpace/NoTimeParse`, `Dexpace/NoUriDefaultParser`,
  `Dexpace/NoLocaleCaseFold`, `Dexpace/NoThreadInterrupt` (`…phase0…:523`) — plus phase 2's sixth,
  `Dexpace/QualifiedCoreConstant`. Only two have sites in `7b`: `SpdxHeader` on every file, and
  `NoThreadInterrupt`, which is honoured by the subsystem containing no interrupt at all
  (`SSE-31`'s cross-thread close tears the resource down and lets the blocked read fail; it does not
  raise into the reading thread). **`NoLocaleCaseFold` has no site in `7b`** — see `P7-24`.
- **The clean-bundle isolation run** on every Ruby in the matrix, which `7b` must keep green on 4.0.

### From phase 1

`Dexpace::Model` with `Model.required!`, `Model.own(collection)` —
`Ractor.make_shareable(collection, copy: true)`, a deep-frozen copy
(`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md:347`) — and the
`.build`-routing `#with` override (`data-modeling/83610619`); `Dexpace::Error` as a **module**;
`Dexpace::Response` and `Dexpace::MediaType`. `SSE-20`'s defensive copy is `Model.own` and nothing
else; `SSE-20`'s copy-on-`#with` clause is the `#with` override and nothing else.

### From phase 2

`Dexpace::Closeable` — a module supplying `#initialize_closeable(owned: true)`, `#close`, `#closed?`,
`#owned?` and a private `#release` the including class defines
(`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:379-380`). Three of its properties are
`7b`'s whole lifecycle story and none is rebuilt here:

- **Idempotence is a latch, not a flag check** — a `@closed` boolean flipped under a `Thread::Mutex`
  **held only across the flip** and released before `#release` runs. That is `SSE-28` and `SSE-31`
  satisfied by inclusion.
- **A release that raises still leaves the latch flipped**, so no second release is attempted and the
  failure propagates once. That is `SSE-30`'s explicit-close half.
- **Ownership is a construction-time fact**, a frozen `@owned` boolean, with `#close` running
  `#release` only when owned. That is what `Stream.owning` / `Stream.borrowing` below are named for.

Also `Dexpace::ClosedError`, `Dexpace::InvalidArgumentError < ::ArgumentError`, `Dexpace::SeamError`,
and `Dexpace.close_quietly(resource, onto: nil)`. **`Dexpace::Hooks` is a `private_constant` with no
`sig/` mirror and no manifest row — `7b` cannot cite it as an interface surface.**

### From phase 3a

`Dexpace::IO::BufferedSource`, and `7b` uses exactly four of its members:

| Member | What `7b` does with it |
|---|---|
| `#getbyte -> Integer?` | The line machine's whole read path. `nil` at EOF |
| `#peek -> BufferedSource` | `SSE-12`'s **non-consuming** lookahead, the requirement's own word |
| `#skip(count) -> void` | Consuming the three BOM bytes after `#peek` confirms them |
| `#closed?` / the `Dexpace::ClosedError` it raises | What a torn-down source surfaces as, which `SSE-31` needs |

`Dexpace::StreamError < ::IOError` and `Dexpace::EndOfStreamError < ::EOFError` are the two error
shapes a source failure arrives as. `BufferedSource.over(body)` takes **no** ownership
(`message-bodies/f060d944`) and `.wrapping(io)` takes it — a polarity `P7-25` deliberately does not
reuse.

**`#read_line_utf8` is *not* in that table**, and that is the finding this design turns on. `R4`.

### From phase 3b

`Dexpace::ResponseBody` — includes `Dexpace::Body` **then** `Dexpace::Closeable`, wraps a
`BufferedSource` the transport built with `.wrapping`, and answers `#source` with **the same
underlying handle every time** (`HTTP-41`/`BODY-14`), never a fresh replay
(`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md:828-846`). `Response#body`
returns `Dexpace::ResponseBody?` — narrowed by `DEF-26` — and `Response#close` releases it. `SSE-32`'s
convenience is built on exactly those three facts and adds nothing to `Response`.

### From phase 4b

- `Dexpace.attach_suppressed(primary, secondary)` with the self-suppression skip, and
  `Dexpace.suppressed(error)`. **The frozen-primary caveat travels with it and `7b` states it rather
  than rediscovering it**: `attach_suppressed` `extend`s its primary, both `extend` and the ivar write
  raise `FrozenError` on a frozen exception, and the helper rescues that and **silently no-ops**
  (`P4-13`). So `SSE-29` and `SSE-36`'s "attached as suppressed" is satisfied for every error the SDK
  or a caller normally raises and is **silently not** satisfied for a frozen one. `7b`'s YARD says so
  at both sites; there is no second mechanism to reach for.
- `Dexpace.close_quietly(resource, onto: nil)`, the **one** quiet-close route (`SSE-30`'s automatic
  path, `SSE-24`'s auto-release), with 5b's `http.instrumentation.*` diagnostic behind the
  `onto:`-absent case (`DEF-27`, closed in 5b).
- `Dexpace.each_cause`, cycle-safe by reference identity through `#compare_by_identity`. `7b` uses the
  **block** form; the block-less form returns an `Enumerator`, and boundary 14 is why that matters.
- `Dexpace::Outcome`, `Outcome::Success = Data.define(:response)` and `Outcome::Failure =
  Data.define(:error)`, with `Success.build: (response: Dexpace::Response) -> …`
  (`docs/work/mvp/phase4/phase4b/2026-09-09-phase4b-recovery-primitives.md:1527`). **That signature is
  why `R5` decides against reusing them** — see below.
- The re-raise spelling `raise error, cause: nil` wherever core re-raises an error it is **carrying**
  rather than one it has just rescued (`pipeline/f02559b9`).

### From phase 4c

`PIPE-26`/`PIPE-27` — a built pipeline is a transport and `Pipeline#close` is a no-op on it. Written
into 4c's forward table for phase 7 (`docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md:1436`),
and it binds `7c` rather than `7b`: **`7b` installs no step, dispatches no request and holds no
transport.** An SSE stream is opened over a `Response` a caller already has.

### From phase 5

**Nothing.** No `SSE` requirement names a configuration key, an instrumentation event, a log level or
a clock. Two adjacencies exist and neither is a dependency: `SSE-30`'s out-of-band report route is
`close_quietly`'s `onto:`-absent diagnostic, whose contract is phase 2's and 4b's and whose emission is
5b's; and `SSE-19`'s "configurable" cap is taken as two constructor keywords, not a `CFG` key
(`R4`).

---

## The verified Ruby facts this phase is built on

All verified on **3.4.10** (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`), the
only interpreter available to this document. **The 3.2 and 4.0 columns have not been run**, and the
plan's Task 1 installs both and re-runs every fact below on all three before any implementation task
begins — the precedent phases 3, 4, 5 and 6 all set.

1. **`Integer(s, exception: false)` is the wrong tool for `SSE-11`, and measurably so.** `SSE-11`
   requires the `retry` value be accepted "only if it consists **solely of ASCII digits** `0`-`9`".
   Measured: `Integer("+5")` → `5`, `Integer("-5")` → `-5`, `Integer("0x10")` → `16`,
   `Integer("1_0")` → `10`, `Integer(" 5")` → `5`, `Integer("5\n")` → `5`. Every one of those must be
   **ignored** and `Integer` accepts all six. `String#to_i` is worse: `"12abc".to_i` → `12`. **This is
   `7b`'s obvious-tool-is-wrong case**, the exact shape `7c` has with `URI.decode_www_form` and
   `PAGE-22`. The screen is an anchored pattern, `Regexp.new("\\A[0-9]+\\z", timeout: …)`, measured to
   reject all eight adversarial inputs and to reject the full-width digits `"０５"` that `Integer` also
   rejects but `[[:digit:]]` would not.
2. **`force_encoding` raises `FrozenError` on a frozen `String` even when the target encoding is
   already the string's own**, and `String#b` on a frozen string returns a fresh unfrozen BINARY copy.
   Re-measured for this document, confirming `io-and-byte-streams/a44b4de6`.
3. **Appending to a BINARY accumulator silently retags it.** `(+"".b) << "é"` produces a **UTF-8**
   string; `(+"".b) << "x"` stays BINARY; `(+"".b) << "é".b` stays BINARY. So an ASCII-only fixture
   passes under exactly the bug, and every `7b` encoding assertion uses non-ASCII content.
4. **`Data.define(:retry)` works and `event.retry` parses.** `retry` is a Ruby keyword, but as a method
   call on a receiver it is unambiguous: measured, `E = Data.define(:id, :event, :data, :comment,
   :retry)` builds, `E.members` is the five symbols, `e.retry` returns the value, `e.public_send(:retry)`
   works and `e.with(retry: 10)` works. **What is not verified is whether `rbs validate` accepts
   `def retry: () -> Integer?`**, because no gems are installed here; the plan's Task 1 checks it on all
   three interpreters and `P7-27`'s fallback (`retry_ms`, with the ledger row that would go with it) is
   named in advance.
5. **`Data#with` copies the struct and shares its members.** With `G = Data.define(:data)` and
   `a = ["x"]`, `G.new(data: a).with(data: …)` shares — which is `SSE-20`'s second clause's whole
   hazard, and `Dexpace::Model#with` routing through `.build` is what removes it
   (`data-modeling/83610619`). Also measured: a `Data` instance is frozen at construction, and the same
   frozen collection reference comes back from every accessor call, so `HTTP-5`'s per-access wrapper is
   unnecessary here too.
6. **Both halves of the `Enumerator`/`ensure` rule, re-measured in `7b`'s own shape.** An `Enumerator`
   abandoned mid-`#next` never runs its `ensure`, after two `GC.start` calls; an ordinary `def each`
   with an `ensure`, driven through `to_enum(:each)` and `#next` and abandoned, never runs it either;
   and `block_given?` **is `true`** inside `#each` when reached that way, so a `raise unless
   block_given?` guard forbids nothing. `7b` writes no such guard and puts no resource inside either
   shape.
7. **`SSE-31`'s hard half is reproducible on CRuby with `IO.pipe`.** A thread parked in
   `r.readpartial(16)` while another thread calls `r.close` raises **`IOError`** in the parked thread —
   an I/O-family error, which is what `SSE-31` requires ("surfaces to the iterating thread as a read
   failure (an I/O error), not a clean end"). The contrast case is measured too: closing the **writer**
   end instead raises `EOFError`, the clean end. `R6` turns on this pair.
8. **The UTF-8 BOM is the three bytes `[239, 187, 191]`**, and `String.new(capacity:, encoding:
   Encoding::BINARY)` produces a BINARY buffer, which is the line accumulator's construction.

---

## `R4` — `OI-5`, the line cap, and the requirement ID its resolution names

**Decision: `OI-5` is resolved here; the requirement that obliges the cap is `SSE-19` and not
`SSE-11`; the cap is two documented constants, `MAX_LINE_BYTES = 1 MiB` and `MAX_EVENT_BYTES = 8 MiB`,
both rejecting loudly and never truncating and both settable per reader; and `OI-5`'s stated route is
right while its stated *premise* is false, because `7b` cannot call `#read_line_utf8` at all.**

`OI-5` (opened 2026-09-08, `docs/open-items.md:224-268`) records that phase 3a's `P3-4` widens `IO-9`'s
SHOULD so `MAX_MATERIALIZED_BYTES` guards every operation producing one contiguous `String`, and that
`#read_line_utf8` is the one drain-style read left outside the guard and cannot be inside it: "`IO-14`
fixes no maximum line length, so there is neither a count to check up front nor an end to stop at but a
terminator that may never arrive."

### The first correction: `SSE-11` is not the requirement

`OI-5`'s resolution text reads "Phase 7 supplying **`SSE-11`**'s cap at the line-machine level …", and
its `Cites:` line reads `IO-9, IO-14, SSE-11, SSE-12, BODY-32`. This was verified independently for
this document against appendix C rather than taken from the charter:

- **`SSE-11` is the `retry` field's magnitude cap, and a MUST** (`…appendix-c…:420`). Design §7.2
  cashes it out as 2^31−1 **milliseconds** and §10.18 catalogues that number beside `IO-9`'s 64 MiB and
  `RECOV-34`'s ~292 years. It has nothing to do with line length.
- **`SSE-19` is the line-length cap, and a MAY** (`…appendix-c…:428`, chapter `:33`). Its chapter form
  carries the port sanction; design §7.2 commits the port to taking it — "**SSE-19**'s optional
  line-length cap is implemented with a documented default, because an unbounded line from a hostile
  server is an unbounded allocation" (`sse-streaming/d935a6cd`).
- **The failure mode is silent and specific.** A `7b` author reading `OI-5`, looking up `SSE-11` and
  implementing the 2^31−1 ms retry cap has satisfied a MUST, ticked a checklist row, and left the line
  read exactly as unbounded as `OI-5` found it — while `OI-5` looks discharged. The two rows are not
  even at the same level of obligation.
- **The same mis-citation is carried by phase 3a's `P3-4` row**, verbatim: "the caller that reads lines
  from a hostile stream is phase 7's SSE machine, which `SSE-11` obliges to carry its own documented
  cap (`OI-5`)"
  (`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md:1109`), with the same
  sentence at `:1052` and in 3a's plan at `:1831` and `:2157`.
- **The likely origin is now identifiable, and it is the corpus.** `sse-streaming/dff112ad` files the
  2^31−1 ms retry conclusion under **`(SSE-11, SSE-19)`**, both IDs on one entry — so `--req SSE-19`
  returns the retry cap. §10.18 also lists `SSE-11` "in the same breath as `IO-9`'s" because both are
  platform-constant substitutions, and §7.2 discusses both caps in adjacent sentences. Three documents
  and one corpus entry all push the reader the same way.

### The second correction: `#read_line_utf8` is not the method, because `SSE-2` and `IO-14` disagree

This is the finding neither `OI-5` nor the charter has, and it changes what the resolution is.

**`IO-14` and `SSE-2` specify contradictory grammars over the same three bytes.** `IO-14`: "a lone
`'\r'` not followed by `'\n'` MUST be kept as part of the line's content." `SSE-2`: "a CR not followed
by LF terminates the line by itself." Phase 3a implemented `IO-14` faithfully — the read-vocabulary
table's row reads "`\n` and `\r\n` terminate, **a lone `\r` is content**"
(`…phase3a…-design.md:659`), and 3a's plan asserts it directly:
`assert_equal("a\rb", source("a\rb\n").read_line_utf8)` (`…phase3a…-io-contracts.md:2201-2202`).

Design §7.2 says the opposite about the same method: the primitive "was hand-written rather than
delegated to `IO#gets`, since **SSE-2** requires LF, CR and CRLF all recognised with a lone CR
terminating alone" (`docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:50-53`,
`sse-streaming/8c25db7d`). **The reason is right and the conclusion is wrong**: hand-writing was
necessary, and what was hand-written follows `IO-14`'s grammar, which is not `SSE-2`'s.

**Post-processing does not rescue it, and the reason is not the grammar but `SSE-39` and `OI-5`
itself.** Splitting a `#read_line_utf8` result on `\r` does reproduce `SSE-2`'s lines for every input
tried. But a **conforming** SSE server that terminates with lone CRs — which `SSE-2` explicitly
permits — emits a stream containing no `\n` at all, and `#read_line_utf8` would then buffer the entire
stream into one `String` before returning anything. That breaks `SSE-39`'s "no eager read-ahead … no
unbounded internal buffer accumulates", a MUST, and it manufactures the exact unbounded allocation
`OI-5` exists to prevent, from a server that is not even hostile. So the route is closed twice over.

**Therefore `7b` builds `Dexpace::SSE::LineReader` over `BufferedSource#getbyte`**, recognising all
three terminators natively and applying the cap to the accumulator as it grows. That is boundary 15's
"a **different** machine over the same primitive" read strictly: the primitive is the *buffered source*,
not `#read_line_utf8`. Recorded as **`P7-20`**.

**What this does to `OI-5`, stated honestly rather than conveniently.** `OI-5`'s route is
right — the bound is one documented number in the layer that knows what a line means, and it is not "a
second, lower, silent cap underneath" 3a's, because it is at a different layer and is documented. But
`OI-5`'s premise — "the consumer that reads lines from a stream a server controls is **phase 7's SSE
machine**", and "resolves it for the only consumer in the MVP" — is **false**: `7b` is not
`#read_line_utf8`'s consumer, and after `7b` lands `#read_line_utf8` has **zero callers anywhere in
this repository**. So the honest closure is two sentences, not one:

> The bound `OI-5` asked for exists, in the layer `OI-5` named, as `Dexpace::SSE::MAX_LINE_BYTES`.
> `#read_line_utf8` itself remains unbounded and now has no in-repository caller at all, which is
> exactly where `IO-14` puts it and where phase 3a's own YARD says the bound is the caller's. The
> residual risk is therefore an SDK author outside this repository calling a public, `NFR-4`-locked
> method whose YARD documents it as unbounded — a documented sharp edge, not a live hazard.

A resolution that said only the first sentence would leave a reader believing `#read_line_utf8` is now
guarded. It is not.

### The constants, and why these numbers

**No document in the repository fixes a value**, unlike the other three constants §10.18 catalogues,
all of which have numbers. `7b` fixes two.

```
Dexpace::SSE::MAX_LINE_BYTES  = 1 * 1024 * 1024   # 1_048_576
Dexpace::SSE::MAX_EVENT_BYTES = 8 * 1024 * 1024   # 8_388_608
```

**Why two and not one.** `SSE-19`'s chapter form sanctions capping "oversized **lines**". Its
appendix-C form states the surface being left open as "no maximum line **or event** size (a growable
byte accumulator expands by doubling)". A line cap alone leaves the second half open: 2^20 one-byte
`data:` lines cost nothing per line and produce a million-element `Array` inside one event block, which
is the same unbounded-memory surface arriving by a different route. Capping the running byte total
accumulated into one event block closes it. Taking a MAY's inverse over the whole of the subject the
requirement itself names is within the MAY; extending it beyond that subject would not be, and `7b`
does not — there is no cap on the number of *events* in a stream, which is what makes SSE a stream.

**Why 1 MiB for a line.** Four reasons, in the order they were applied:

1. **It must be a different bound at a different layer, not a restatement of 3a's.** 3a's
   `MAX_MATERIALIZED_BYTES` is 64 MiB and guards operations that produce one contiguous `String`
   through `BufferedSource`'s own drain methods. `7b`'s machine calls none of those — it reads bytes —
   so 3a's ceiling is not merely higher, it is **not on this path at all**. Setting the line cap at or
   near 64 MiB would produce a number that guards nothing anybody meets.
2. **It must be far above the largest line a conforming server plausibly sends.** An SSE `data` line
   carries one line of an application payload. Streaming APIs in the wild emit data lines measured in
   hundreds of bytes to a few kilobytes; the largest defensible single-line payload is a whole JSON
   document or a base64 blob framed on one line. 1 MiB is roughly three orders of magnitude above the
   common case and one order above the largest plausible one.
3. **It must not be a magnitude the repository has not already committed to.** 3b's
   `MAX_BUFFERED_ERROR_BODY_BYTES` is 1 MiB
   (`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`), so a reader meeting
   two 1 MiB bounds in core is meeting one magnitude rather than two arbitrary ones. **`7b` does not
   reuse 3b's constant** — one constant shared across two subsystems is the failure boundary 16 names
   — it matches its order deliberately and says so.
4. **512 KiB was considered and rejected**, because it would refuse a 600 KiB attachment framed as one
   `data` line, which is unusual but not malformed. 1 MiB refuses nothing anyone has been shown to
   send. The ratio to 3a's ceiling is 1:64, which makes the layering legible: sixty-four lines at the
   cap would fill the materialisation ceiling.

**Why 8 MiB for an event.** Eight times the line cap, so a legitimate multi-line event may carry
several large lines without meeting the bound; one eighth of 3a's ceiling, so the event bound is still
visibly beneath it. Both numbers are **chosen, not derived**, which is phase 3a's own phrasing for
`MAX_MATERIALIZED_BYTES`, and both are stated as such in their YARD.

### Reject, never truncate; configurable, but not through `CFG`

**Reject.** `SSE-19` sanctions "reject/truncate". Truncating a `data` line silently corrupts the
payload — a truncated JSON document reaches the caller's mapper as a parse error at a place the caller
cannot relate to the cause — and §10.18's own sanction is "fails or **ignores loudly** above them".
`7b` raises `Dexpace::SSE::LimitExceededError`, carrying `#limit` (the constant that was exceeded) and
`#kind` (`:line` or `:event`), from the pull that crosses the bound. The error propagates through the
facade's mid-stream-failure path (`SSE-29`), so the resource is released before it surfaces and a
release failure is attached as suppressed — the cap does not get its own lifecycle.

**Configurable — as two constructor keywords, and this is not `DEF-28`'s shape.** `SSE-19`'s sanction
says "a **configurable** cap", and `OI-5` explicitly rules out one route: "Adding a `max_line_bytes:`
keyword to `#read_line_utf8` would not [resolve it]: phase 5 owns the configuration chain,
`IO-40`-adjacent limits reaching this layer is what `docs/knowledge/notes/resource-management.md`
already declines for timeouts, and a keyword with no configuration source behind it is `DEF-28`'s shape
without `DEF-28`'s pick-up condition."

Every clause of that objection is about the **I/O layer**. At the SSE layer the objection does not
hold, and the distinction is exactly the one `OI-5` itself draws:

- `IO-40` forbids **the streaming contracts** from imposing their own limits and `resource-management/d1f16cad`
  resolves that for timeouts. `Dexpace::SSE::Reader` is not a streaming contract; it is a consumer of
  one, at the layer that knows what a line means — which is `OI-5`'s own criterion for where the bound
  belongs.
- A keyword on `#read_line_utf8` has no configuration source because nothing constructs a
  `BufferedSource` for the caller's own reasons. A keyword on `Dexpace::SSE::Reader.new` /
  `Stream.owning` / `Stream.borrowing` / `Stream.open` **does**: the caller constructs the reader
  directly, so the caller is the source. No `CFG` key is added, phase 5's chain is untouched, and the
  charter's "no phase-7 requirement names a configuration key" stays true.
- `NFR-4` locks a public signature and fails when one "disappears or narrows". A keyword with a default
  **widens**, which is `DEF-28`'s own stated precedent for adding one later — so shipping the keyword
  now and shipping it never are both safe, and shipping it now is what `SSE-19` asks for.

Recorded as **`P7-21`**.

### Where the divergence is documented

`SSE-19` charges taking the option with "documenting the divergence", and it is documented in four
places, each with a different reader in mind:

1. **YARD on both constants**, stating the number, that it is chosen rather than derived, that it is a
   `SSE-19` divergence from the reference (which imposes no maximum), and — on `MAX_LINE_BYTES` — that
   **this is the bound `OI-5` names**, so the relationship between 3a's ceiling and `7b`'s cap is
   visible from the code and not only from a register. `OI-5`'s third obligation, discharged.
2. **`7b`'s Deviation Ledger**, `P7-21`, consolidated into design §10 by a human.
3. **The §10.18 amendment text drafted in the findings below**, because §10 is frozen to this document.
   The recommendation is that both constants join §10.18's existing list rather than take a §10 row of
   their own: §10.18 is precisely "platform-constant substitutions where Ruby has no constant", Ruby
   has no maximum single allocation, and `SSE-11` already sits in that item — putting the SSE line cap
   somewhere else is what let it be confused with the retry cap in the first place.
4. **`7b`'s checklist row for `SSE-19`**, which names the value and states that it is not `SSE-11`'s.

---

## `R5` — the third mapper outcome, and why `Dexpace::Outcome`'s two are not reused

**Decision: `SSE-34`'s three outcomes are the mapper's decoded value returned bare, plus two frozen
sentinels `Dexpace::SSE::SKIP` and `Dexpace::SSE::DONE`. `Dexpace::Outcome::Success` and `::Failure`
are not reused, and `7b` adds no member to `Dexpace::Outcome` or to either variant.**

The charter's spec-forced boundary 10 says two things, and `7b` honours both: whatever `7b` names
lives inside `Dexpace::SSE`, and `7b` adds no member to `Dexpace::Outcome`, `Success` or `Failure`.
What `7b` declines is the *framing* both the charter and phase 4b's forward table wrap around it —
that `Dexpace::Outcome`'s two are "reused with a third variant". They cannot be, and the reason is
mechanical rather than a matter of taste:

**`Outcome::Success`'s single member is a response.** `Dexpace::Outcome::Success = Data.define(:response)`,
with `def self.build: (response: Dexpace::Response) -> Dexpace::Outcome::Success` in phase 4b's RBS
(`docs/work/mvp/phase4/phase4b/2026-09-09-phase4b-recovery-primitives.md:1523-1527`). A mapper's
decoded value is a caller's model object — a `Struct`, a `Hash`, a generated SDK type. Putting one in
a member named `response` and typed `Dexpace::Response` fails `steep check`, misreads at every call
site, and would drag `7b` toward asking phase 4b to widen a type — which boundary 10 forbids in as many
words.

**And `Outcome`'s derived surface does not fit three arms.** `RECOV-1` gives both variants
`#success?`, `#failure?`, `#response_or_nil`, `#error_or_nil` and
`#fold(on_success:, on_failure:)`. `SSE-34`'s three outcomes are not success/failure at all — Skip and
Done are both *successful*, they differ in what the iterator does next — so every one of those five
methods answers a question the SSE adapter is not asking. `#fold`'s two arms would need a third, which
is a member change to a phase-4b type.

**What ships instead.**

```
Dexpace::SSE::Signal = Data.define(:name)   # private_class_method :new; two instances, both frozen
Dexpace::SSE::SKIP   # Signal, name: :skip
Dexpace::SSE::DONE   # Signal, name: :done
```

with `#to_s` and `#inspect` overridden to `"Dexpace::SSE::SKIP"` / `"…DONE"`, so a sentinel that
reaches a log or a failure message identifies itself instead of printing a `Data` dump. Everything a
mapper returns that is not one of those two objects is a value and is yielded — **including `nil`**,
which is what makes a mapper decoding an explicit JSON `null` work without a wrapper.

Three properties fall out and each is worth stating because a wrapper-based design would have lost
them:

- **No allocation per event.** `SSE-35` requires per-element laziness on what may be a very long-lived
  stream; a wrapper would allocate one object per delivered event for no information gain.
- **`SSE-33`'s "MUST yield the mapper's decoded value" is satisfied literally** — the consumer receives
  the mapper's return value, not something holding it.
- **The comparison is `equal?`, not `==`.** Two frozen singletons compared by identity cannot be
  spoofed by a decoded model that happens to `==` a sentinel, which a `Data`-with-a-name comparison by
  value could be.

**`7a`'s `Tristate` sentinels are the same shape and `7b` does not borrow them.** Design §7.3 gives the
serde layer sentinel objects with overridden string forms for the reason `SERDE-30` states, and `R5`
asks whether `7b` should follow that shape. It follows the *shape* and shares no *object*: reaching
into `Dexpace::Serde` for a sentinel would be a serialization dependency in core's SSE layer, which is
`SSE-37`, a MUST, mechanised. The two subsystems each own a two-instance sentinel type and neither
knows the other exists. Recorded as **`P7-23`**.

---

## `R6` — `SSE-31`'s two test shapes, and which of them distinguishes a correct implementation

**Decision: both shapes are written, both are deterministic, and the design states which one is real
evidence and which one is a green light the platform gives for free.**

`SSE-31`'s conformance clause asks for two: "park a reader thread inside a blocking read, close from
another thread, and assert an I/O-style error plus one release; separately close between pulls and
assert a clean end."

**Shape A — close between pulls, clean end.** Deterministic, sequenced through a `Thread::Queue` the
way phase 3a sequenced `IO-38`'s cross-thread test, and it asserts real behaviour: the drive routine
checks `closed?` at the top of every pull and returns end (`SSE-27`), and the resource has already been
released exactly once. **This test distinguishes a correct implementation from an incorrect one on
every matrix row**, because an implementation that did not check the flag would read from a torn-down
source and raise instead of ending cleanly.

**Shape B — close during a blocked read, I/O error.** Reproducible on CRuby, and measured for this
document rather than assumed (verified fact 7): a thread parked in `readpartial` on the read end of an
`IO.pipe` whose read end is closed from another thread raises **`IOError`**; closing the *writer* end
instead raises `EOFError`. So the test is writable, it is not flaky, and it asserts the distinction
`SSE-31` cares about — a torn-down resource surfaces as a read failure and **not** as a clean end.
`7b`'s facade turns that into a `Dexpace::StreamError` at the `BufferedSource` boundary, which is 3a's
`::IOError` subclass, so "an I/O-style error" is satisfied by ancestry rather than by discipline.

**What neither shape proves, stated so a ✅ is not read as more than it is.** `DEF-33`
(`docs/deferred-items.md`) records that the *mechanism* behind a cross-thread flag — reading and
writing it under a `Thread::Mutex` rather than relying on the GVL — cannot be exercised on any row of a
CRuby-only matrix: the test passes with the mutex and passes without it. `7b` inherits that latch from
phase 2's `Dexpace::Closeable` and adds no second one, so **`SSE-31` inherits `DEF-33`'s limitation
along with the latch**, and `7b`'s checklist row says so rather than claiming a guarantee the matrix
cannot show. This is `P4-33`'s precedent — do not write a test that passes on the floor and would fail
to reproduce elsewhere — applied from the other direction: the test is right, the *mechanism* claim is
what the matrix cannot reach.

---

## `R11` — the `SSE-37` require audit, and the `7b`/`7c` convergence resolved in both directions

**Decision: `7b` builds the audit, in a shape that makes `7c`'s contribution exactly one line whichever
of the two lands first, and that cannot pass silently on a typo.**

`SSE-37` forces the mechanism for `lib/dexpace/sse/**`. The charter's spec-forced boundary 5 extends it
to `lib/dexpace/page/**`, because §12's serde-agnosticism carries no requirement ID and is therefore
enforced by nothing: core's require allowlist denies `json` by name but the boundary at issue is
**internal** — core's pagination layer reaching for core's own `Dexpace::Serde` seam — and no existing
gate sees that.

**The mechanism.** A new gate body `tools/serde_boundary.rb` and a new blocking task
`gates:serde_boundary` in `tasks/gates.rake`, beside phase 0's three zero-dependency gates. It is a
**text scan**, not a runtime trace, for the same reason phase 0's require audit is one: `lib/dexpace.rb`
issues explicit requires for the whole tree and there is no autoloader to interrogate. For every guarded
path it fails on:

1. any `require` or `require_relative` whose target names `serde` or `json`;
2. any occurrence of the constant `Dexpace::Serde`, a bare `Serde`, or `JSON` in any form (`::JSON`
   included — phase 2's `Dexpace/QualifiedCoreConstant` cop makes the qualified spelling mandatory
   elsewhere in core, so the scan must catch the spelling the cop *encourages*).

**The shape that makes the convergence a one-line diff, and the part that matters.** The tool holds two
lists rather than one:

```ruby
GUARDED = [
  ["gems/dexpace-core/lib/dexpace/sse.rb",       "SSE-37"],
  ["gems/dexpace-core/lib/dexpace/sse/**/*.rb",  "SSE-37"],
].freeze

# Spec-forced boundary 5 (phase 7 segmentation design): §12's serde-agnosticism carries no
# requirement ID, so the SSE-37 mechanism is extended one path wider. 7c moves this row into
# GUARDED in the change that creates the files.
PENDING = [
  ["gems/dexpace-core/lib/dexpace/page/**/*.rb", "phase-7 segmentation design, spec-forced boundary 5"],
].freeze
```

and **asserts that every `GUARDED` glob matches at least one file**. That assertion is the whole design:
without it, a glob with a typo scans nothing and reports clean forever, which is the precise way a
boundary gate stops being a gate. `PENDING` is the escape hatch for a path whose files do not exist
yet, and it is deliberately *not* silent — the gate prints each `PENDING` row and the reason it is
pending on every run, so the row is a standing reminder rather than a hole.

**Both orderings, stated so the audit is neither written twice nor left to each assuming the other
wrote it.**

- **If `7b` lands first** (the charter's recommended order): `7b` writes `tools/serde_boundary.rb`,
  `gates:serde_boundary`, its negative fixtures and its wiring into the default rake task, with
  `sse/**` in `GUARDED` and `page/**` in `PENDING`. `7c`'s contribution is one line — moving the
  `page/**` row from `PENDING` to `GUARDED` — in the change that creates the first file under
  `lib/dexpace/page/`.
- **If `7c` lands first**: `tools/serde_boundary.rb` already exists with `page/**` in `GUARDED` and
  `sse/**` in whatever list `7c` chose. `7b`'s contribution is one line — adding or moving the two
  `sse/**` rows into `GUARDED`. `7b` writes **no second tool and no second rake task**, and if it finds
  one already there it uses it unchanged.
- **Neither blocks the other.** A sub-phase running first with no audit yet in place ships its own path;
  the extension arrives with the second.

**Negative fixtures, because a gate with no failing fixture is an assertion about itself.** Four, in the
plan: a fixture file under a guarded path with `require "json"`; one with `require_relative
"../serde/json"`; one naming `Dexpace::Serde`; and one naming `::JSON` — the spelling the
`QualifiedCoreConstant` cop pushes an author toward. Plus one positive control (a guarded file that
mentions neither) and one **glob-typo fixture** proving the at-least-one-match assertion fires.

**What the gate does not cover, and what does.** `SSE-37`'s other two prohibitions — no built-in
done-sentinel, no error-envelope recognition — are not scannable: a done-sentinel is a string literal
and no scanner can tell `"[DONE]"` from any other string. They are asserted by test instead: a stream
whose data line is `[DONE]` yields an ordinary `Event` and does not terminate iteration, and a stream
whose event name is `error` yields an ordinary `Event` and raises nothing. `SSE-38`'s three
prohibitions are asserted the same way — a stream that ends does not reopen, a second event's id is
absent when only the first carried one, and no request is constructed anywhere in the subsystem — which
is design §7.2's own instruction, "satisfied by omission **and asserted by test**, since the temptation
to add them is real".

---

## The object model `7b` ships

### `Dexpace::SSE::LineReader` — `SSE-2`, `SSE-14`, `SSE-19`

Public, because `SSE-2`'s grammar is a distinct contract with its own conformance clause and because
`MAX_LINE_BYTES` lives on it.

- `.new(source, max_line_bytes: Dexpace::SSE::MAX_LINE_BYTES)` over a `Dexpace::IO::BufferedSource`.
  **Owns nothing** (`SSE-17`).
- `#next_line -> String?` — the next line's content as **BINARY bytes** with the terminator stripped,
  or `nil` when the source is exhausted before any byte. A final unterminated line at EOF comes back as
  content (`SSE-14`).
- **All three terminators, natively.** LF terminates. CR terminates, and the machine reads one further
  byte to decide whether it was CRLF; if that byte is not LF it is held in a one-byte pushback and
  becomes the first byte of the next line. At EOF immediately after a CR, the CR terminates.
- **The pushback is the machine's own state, not a second buffer over the source.** One `Integer` or
  `nil`. There is no second accumulator anywhere in `7b`.
- **The cap is checked as the accumulator grows**, before each append, so an over-long line raises
  before it is materialised rather than after. The accumulator is a `String.new(capacity: …, encoding:
  ::Encoding::BINARY)` reused across lines by `#clear`, which keeps the machine allocation-flat on a
  long stream.

**One inherent property, stated because it looks like a bug and is not.** A line terminated by a lone
CR cannot be dispatched until one further byte arrives, because nothing distinguishes CR from the first
half of CRLF without it. This is the grammar's, not the implementation's — WHATWG has it too — and it
affects only a CR-terminating server. LF- and CRLF-terminated streams are unaffected, since the byte
the machine needs is the terminator that has already arrived. `SSE-39`'s no-read-ahead test therefore
uses LF fixtures, and a CR fixture gets its own test asserting the behaviour rather than pretending it
away.

### `Dexpace::SSE::Event` — `SSE-20`, `SSE-21`, `SSE-22`

`Data.define(:id, :event, :data, :comment, :retry)`, including `Dexpace::Model` and `Dexpace::SSE`'s
nothing else, with `private_class_method :new` and a validating
`.build(id: nil, event: nil, data: [], comment: nil, retry: nil)`.

- **`SSE-21` is free**: `Data` gives equality and hash over all five members and a stable `#inspect`
  (`sse-streaming/e5e6eea7`).
- **`SSE-20`'s defensive copy is `Model.own(data)`** — `Ractor.make_shareable(collection, copy: true)`,
  a deep-frozen copy — applied inside `.build`, so neither the list the parser accumulates into nor a
  caller's later mutation can reach inside a constructed event.
- **`SSE-20`'s copy-with-changes clause is `Dexpace::Model#with`**, which routes through `.build` and
  therefore through `Model.own` again (`data-modeling/83610619`). `7b` writes no bespoke `#with`, and
  its test asserts the mutate-the-original case on **both** construction and derivation, because
  verified fact 5 shows the raw `Data#with` shares.
- **`SSE-22`'s `#empty?` is true only when all five fields are *unset*** — `id`, `event`, `comment` and
  `retry` `nil` and `data` empty — which is design §7.2's reading (`sse-streaming/49e0a75a`) and makes a
  comment-only keep-alive report non-empty. Note the two cases a looser reading gets wrong: an event
  whose only field is `event: ""` is **not** empty, because `SSE-4` makes present-but-empty distinct
  from absent; and an event whose `data` is `[""]` — one `data:` line with an empty value — is not
  empty either.
- **The member is named `retry`**, matching the wire field and `SSE-13`'s "five tracked fields". Verified
  fact 4 shows `Data.define(:retry)` and `event.retry` both work; the plan's Task 1 verifies `rbs
  validate` accepts the signature, with `retry_ms` as the named fallback.

### `Dexpace::SSE::Reader` — `SSE-1`, `SSE-3`–`SSE-18`

- `.new(source, max_line_bytes:, max_event_bytes:)`, holding a `LineReader`. **Owns nothing**
  (`SSE-17`): the conformance test drives a reader to completion over an instrumented source and
  asserts its `#close` was never invoked.
- `#next_event -> Dexpace::SSE::Event?` — `nil` is the end-of-stream sentinel (`SSE-15`), stable and
  distinct because an `Event` is never `nil`, and sticky: once end has been reported every later call
  reports it. **`P7-22`** records the choice against `api-design/6ea28c9c`'s never-`nil`-for-absent
  rule, and the argument is that this is a *stream terminator* rather than an absent value — the exact
  case `#gets`, `#getbyte` and `IO-14`'s own `#read_line_utf8` all use `nil` for — and that almost no
  caller sees it, because the facade turns it into `Enumerator` termination.
- **The single item of persistent state is the BOM flag** (`SSE-16`). Nothing else survives a call: no
  last-event-id, no carried retry value. Two tests assert the two prohibitions directly, since
  `sse-streaming/2dba42b0` records the opposite and a future reader may find it.
- **`SSE-12`'s BOM** is consumed on the first `#next_event` and not at construction, so a facade that is
  built and never iterated touches the source zero times. The lookahead is phase 3a's `#peek` — a
  non-consuming view — read for up to three bytes and closed in an `ensure`; only on an exact
  `[0xEF, 0xBB, 0xBF]` match does the reader `#skip(3)` on the parent. A stream of fewer than three
  bytes, and a stream whose first three bytes are a prefix of the BOM but not the BOM, both leave the
  source untouched. **A reader that consumed three bytes unconditionally would pass every BOM-prefixed
  fixture and corrupt every stream without one**, which is why the non-BOM case gets its own test.
- **The field split (`SSE-3`) and the one-space strip (`SSE-5`) are byte operations** on the BINARY line,
  before decoding. `SSE-6`'s comment is a line whose first **byte** is `0x3A`.
- **`SSE-7`'s four field names are compared case-**sensitively**.** WHATWG compares them exactly, and
  `SSE-7` names four lowercase tokens and requires that "any other field name MUST be silently
  discarded" — so `DATA:` is an unknown field, discarded, setting no state and causing no dispatch.
  This is `P7-24`, and it means **`7b` calls `downcase` nowhere**, so the charter's spec-forced boundary
  19 is honoured vacuously rather than at a site.
- **`SSE-9`'s NUL check** is `value.include?("\x00".b)` on the BINARY value, before decoding, so a NUL
  cannot be lost to a replacement character first.
- **`SSE-10`'s `event` field is stored raw with latest-wins semantics and surfaced as absent when no
  `event` line was sent**, and is **never defaulted to `message`.** The default is the one thing a
  reader of the WHATWG specification would add without noticing, since WHATWG *does* default it;
  `SSE-10` is one of the chapter's deliberate deviations from strict WHATWG and §11.17 settles that
  the deviations are replicated rather than offered behind a strict mode. `SSE-4` is what makes an
  `event:` line with an empty value distinct from an absent one here.
- **`SSE-11`'s screen is an anchored `Regexp.new("\\A[0-9]+\\z", timeout: …)`**, per-pattern as
  `CLAUDE.md` and design §4 require, never the process-global `Regexp.timeout`. Verified fact 1 is the
  argument for the pattern over `Integer(…, exception: false)`, and the test battery is the eight
  measured inputs. The accepted value is compared against **2^31−1** (design §7.2, §10.18) and ignored
  above it — a separate constant, `Dexpace::SSE::MAX_RETRY_MS`, and a separate checklist row from
  `SSE-19`'s.
- **`SSE-13`'s permissive dispatch** is a five-way "was any field seen" flag; `SSE-14`'s EOF dispatch
  and `SSE-15`'s sticky end are the two states after it.
- **`MAX_EVENT_BYTES` is checked on the running total** of raw bytes accumulated into the current block,
  reset at each dispatch.

### `Dexpace::SSE::Stream` — the facade, `SSE-23`–`SSE-32`, `SSE-39`, `SSE-40`

`include Dexpace::Closeable`, holding one `Reader` and one closeable resource.

- **Three factories, and the names are chosen against a trap.** `Stream.open(response)` is `SSE-32`'s
  convenience: it takes a `Dexpace::Response`, raises `Dexpace::InvalidArgumentError` when
  `response.body` is `nil` ("MUST fail loudly if the response has no body"), builds a `Reader` over
  `response.body.source`, and **owns the response** — `initialize_closeable(owned: true)`, `#release`
  calls `response.close`, so closing the stream closes the response. `Stream.owning(source)` owns a
  caller-supplied source; `Stream.borrowing(source)` does not. **None of them is called `.over`**,
  because `Dexpace::IO::BufferedSource.over` means *borrowing* and `.wrapping` means *owning*
  (`message-bodies/f060d944`), and a method named `.over` in the neighbouring subsystem with the
  opposite polarity is the kind of thing that reads correctly and is wrong. **`P7-25`.**
- **`SSE-23`'s "exactly one closeable resource, closed exactly once" is `Closeable`'s latch**, and the
  test wraps a close-counting resource and drives each of the five termination paths the chapter names
  — clean end, explicit close, block-form exit, partial consume, mid-stream failure — asserting one
  close each.
- **`#each { |event| }` and `#events -> Enumerator`** are the two consumption shapes, both single-pass,
  both latching `@viewed` on first call and raising on a second (`SSE-26`, `SSE-40`'s second clause,
  `sse-streaming/5f4803a0`). Requesting either after close raises (`SSE-27`).
- **The resource lives on the `Stream`, never inside the enumerator's block or inside `#each`.**
  Verified fact 6 is why, in both of its halves. `#each`'s block form gets `SSE-25`'s partial-consume
  release from an `ensure` that is genuinely reached; external iteration gets it from `#close`, which
  the block form makes the default. **There is no `block_given?` guard anywhere in `7b`** — it is
  measurably true inside `#each` reached through `to_enum` and `#next`, so it forbids nothing.
- **`SSE-24`'s auto-release** happens in the drive routine when the reader returns `nil`, not in an
  `ensure`: `Dexpace.close_quietly(@resource, onto: nil)`, then the iteration ends.
- **`SSE-30`'s asymmetry is two call sites into one close-once helper, not two closes**
  (`cross-cutting-invariants/68aad33a`). The automatic terminal path calls
  `Dexpace.close_quietly(@resource, onto: nil)` — swallowed, reported out of band by 5b's diagnostic.
  An explicit `#close` goes through `Closeable#close`, whose `#release` failure propagates once. Both
  routes flip the same latch, so `SSE-28`'s idempotence holds across them and the "even after an
  automatic release" clause is satisfied by construction rather than by a second flag.
- **`SSE-29`'s mid-stream failure**: rescue, `Dexpace.close_quietly(@resource, onto: error)` — which
  releases **before** the error propagates and attaches a release failure as suppressed — then re-raise.
  The frozen-primary caveat is stated in the YARD at this site.
- **`SSE-31`'s closed-state guard is `Closeable`'s mutex**, held across the flip only. The drive routine
  reads `closed?` at the top of every pull, which is `SSE-27`'s "an in-flight iterator MUST observe the
  closed state and end cleanly on its next pull".
- **`SSE-39`'s no-read-ahead** falls out of the design: a synchronous machine over a source that pulls a
  chunk only when asked, with no queue between parser and consumer. It is asserted rather than assumed
  (`sse-streaming/317a3b6d`), by a body whose `#each` yields one event's bytes per chunk and counts its
  yields: after one `#next`, the count is 1.

### `Dexpace::SSE::TypedStream` — `SSE-33`–`SSE-36`

Returned by `Stream#typed(&mapper)`, or `.typed(mapper)`. It is **not** a second `Closeable`: it holds
the `Stream` and delegates `#close`/`#closed?` to it, so `SSE-23`'s exactly-one-resource claim survives
the typed layer.

- **`SSE-33`**: the mapper is called with `(event_name, joined_data)` — the raw `event` field, `nil`
  when absent, and the data lines joined with a single `"\n"`, the empty string when there was no
  `data` field. The join happens **here**, not in the parser, because `SSE-8` requires the parser keep
  the raw per-line list.
- **`SSE-34`**: `DONE` ends iteration cleanly and closes the stream **without yielding a model for the
  sentinel event**; `SKIP` drops the event and advances; anything else is yielded.
- **`SSE-35`**: the mapper runs inside the pull, so a partial consume decodes only the events taken. The
  test instruments the mapper and asserts one call per pull. The one nuance `SSE-39` states explicitly:
  the typed layer may pull several *raw* events per yielded element to drain Skips, "but only as many
  as needed to produce one element" — so the assertion is on mapper calls per element, not on raw pulls
  per element.
- **`SSE-36`**: a mapper that raises releases the resource first — `Dexpace.close_quietly(stream, onto:
  error)` — then propagates to the consumer's pull. Same shape as `SSE-29`, same frozen-primary caveat.

### `Dexpace::SSE::Signal`, `SKIP`, `DONE`, `LimitExceededError` and the three constants

Covered under `R5` and `R4`. **Two error classes**, both `< ::StandardError` and both `include
Dexpace::Error`: `Dexpace::SSE::LimitExceededError`, carrying `#kind` (`:line` or `:event`) and
`#limit` (the constant that was crossed, so a caller raising a cap knows which one to raise); and
`Dexpace::SSE::StreamStateError`, which is `SSE-26`'s "a second attempt MUST fail loudly (e.g. an
illegal-state error)" and `SSE-27`'s post-close refusal. It lives **inside the `Dexpace::SSE` namespace** rather
than flat in `lib/dexpace/error/`, because it is meaningless outside this subsystem — unlike
`Dexpace::ProtocolError`, which every layer raises — and because phase 4b's `P1-1` placement rule is
"namespaces the design itself wrote, everything else is flat", and design §7.2 writes
`Dexpace::SSE::Event`.

---

## Module layout

```
lib/dexpace/sse.rb                          Dexpace::SSE, MAX_LINE_BYTES, MAX_EVENT_BYTES,
                                            MAX_RETRY_MS, SKIP, DONE
lib/dexpace/sse/signal.rb                   Dexpace::SSE::Signal
lib/dexpace/sse/limit_exceeded_error.rb     Dexpace::SSE::LimitExceededError
lib/dexpace/sse/stream_state_error.rb       Dexpace::SSE::StreamStateError
lib/dexpace/sse/line_reader.rb              Dexpace::SSE::LineReader
lib/dexpace/sse/event.rb                    Dexpace::SSE::Event
lib/dexpace/sse/reader.rb                   Dexpace::SSE::Reader
lib/dexpace/sse/stream.rb                   Dexpace::SSE::Stream
lib/dexpace/sse/typed_stream.rb             Dexpace::SSE::TypedStream

sig/dexpace/sse.rbs                         and one .rbs per file above, mirroring lib/ exactly
test/dexpace/sse/*_test.rb                  one suite per file above
tools/serde_boundary.rb                     the SSE-37 gate body (R11) — if 7b lands first
tasks/gates.rake                            + gates:serde_boundary                — if 7b lands first
test/tools/serde_boundary_test.rb           the gate's own six fixtures            — if 7b lands first
```

The three constants that are *values* live in `lib/dexpace/sse.rb`, beside the module whose limits they
are — phase 3a's placement of `MAX_MATERIALIZED_BYTES` in `lib/dexpace/io.rb`, applied unchanged.
`SKIP` and `DONE` live there too rather than in `signal.rb`, because a constant should be findable at
the name a caller writes (`Dexpace::SSE::SKIP`) and `Signal` itself is the type, not the value.

`lib/dexpace.rb` gains nine `require_relative` lines, in dependency order, added in the plan's final
wiring task.

---

## Encoding, stated once for `7b`

**Bytes on the wire are `Encoding::BINARY` and stay BINARY until a field value is extracted.** The line
machine accumulates into a BINARY buffer; `SSE-3`'s colon split, `SSE-5`'s one-space strip, `SSE-6`'s
comment test, `SSE-9`'s NUL test and `SSE-11`'s digit screen are all byte operations on BINARY strings.
The caps count **bytes**, so a multi-byte character cannot slip a bound.

**The decode is one boundary and it is retag-then-transcode with both encodings named**
(`io-and-byte-streams/6eb5155f`). `text/event-stream` is UTF-8 by definition, so the declared source
encoding is not a guess and there is no `MediaType#charset` to consult — which is exactly the place a
declared charset is most tempting and the SSE grammar removes the temptation. The two steps:

```ruby
retagged = bytes.b.force_encoding(::Encoding::UTF_8)
retagged.encode(::Encoding::UTF_8, ::Encoding::UTF_8, invalid: :replace, undef: :replace)
```

`String#b` first because verified fact 2 shows `force_encoding` raises `FrozenError` on a frozen chunk
**even when the target is the string's own encoding**; both encodings named on `#encode` because
`undef: :replace` with no target follows `Encoding.default_internal`, a process global the host sets;
`invalid: :replace` because WHATWG decodes the stream with UTF-8 replacement and the alternative is
raising on a byte the reference tolerates. Recorded as **`P7-26`**.

**Every encoding assertion in `7b` uses non-ASCII content** (`io-and-byte-streams/a44b4de6`, verified
fact 3): an ASCII-only fixture passes under exactly the bug, because appending an ASCII-only UTF-8
string to a BINARY one leaves it BINARY while appending a non-ASCII one silently retags it.

---

## §7.1's `Enumerator` rule applied — where it bites in `7b`

Four requirements are cash-outs of one rule that was paid for two phases ago, and the rule is:
**resource acquisition and release never live inside an `Enumerator` block, or inside an ordinary
`#each` that owns a resource.**

| Requirement | Where the release actually lives |
|---|---|
| `SSE-24` — clean end releases | The drive routine, on the reader returning `nil`. Not an `ensure` |
| `SSE-25` — partial consume must not strand | `Stream#close`, which the block form of `#each` calls in its own `ensure` in the `Stream`'s scope |
| `SSE-26` — single-pass | A `@viewed` latch on the `Stream`, checked before the enumerator is built |
| `SSE-40` — the lazy view | The same latch and the same reader instance; the view holds no resource of its own |

`7b` writes no `block_given?` guard (verified fact 6), and it does not test abandonment by dropping an
enumerator and calling `GC.start`: garbage collection is not a cleanup hook, and a test that asserted a
release after `GC.start` would assert the opposite of what was measured. The abandonment test asserts
the **absence** of a release after abandonment and its **presence** after the explicit `#close` that is
the documented remedy.

---

## The spec-forced boundaries, honoured

The charter's twenty-four, filtered to the ones with an SSE site. Each is honoured, and where `7b`
found the boundary's *statement* imprecise that is said rather than quietly worked around.

1. **Boundary 1 — core's SSE layer holds no serialization dependency, mechanically checked.** `R11`.
   `SSE-38`'s three prohibitions satisfied by omission and asserted by test.
2. **Boundary 10 — `Dexpace::Outcome` gains no member and `7b`'s variant lives in the SSE namespace.**
   Honoured. The "reused" half of the framing does not survive `Success`'s signature; `R5` and `P7-23`.
3. **Boundary 11 — the suppressed trail is `Dexpace.attach_suppressed`/`Dexpace.suppressed`.** Two call
   sites (`SSE-29`, `SSE-36`), both through `close_quietly(…, onto:)`. The frozen-primary caveat travels
   with it and is stated at both.
4. **Boundary 12 — `SSE-30`'s split is two call sites into one close-once helper.** Honoured;
   `Dexpace.close_quietly` is the quiet route and `Closeable#close` the loud one, over one latch.
5. **Boundary 13 — every cause walk goes through `Dexpace.each_cause`, block form.** `7b` has no cause
   walk at all, which honours it vacuously; the row says so rather than claiming a site.
6. **Boundary 14 — no resource inside an `Enumerator` block or an owning `#each`; no `block_given?`
   guard.** Honoured; the table above is where.
7. **Boundary 15 — the line-reading primitive is 3a's and `7b` builds a different machine over it.**
   Honoured in substance and **corrected in detail**: the primitive is `BufferedSource`, not
   `#read_line_utf8`, because `IO-14` and `SSE-2` specify contradictory CR handling. `P7-20`, `R4`.
8. **Boundary 16 — `MAX_MATERIALIZED_BYTES` is one ceiling, cited and never re-derived.** Honoured:
   `7b` introduces no second materialisation constant, lowers 3a's not at all, and its two caps are a
   different bound at a different layer on a path 3a's ceiling does not touch.
9. **Boundary 17 — BINARY on the wire, retag-then-transcode with both encodings named, non-ASCII
   fixtures.** Honoured; *Encoding, stated once* is where.
10. **Boundary 19 — `downcase` takes no arguments**, which the charter says bites at `SSE-7`. **It does
    not bite here at all**: `SSE-7`'s comparison is case-sensitive, so `7b` calls `downcase` nowhere and
    `Dexpace/NoLocaleCaseFold` has no site in the subsystem. `P7-24`, and a finding.
11. **Boundary 22 — Regexp timeouts are per-pattern.** One pattern in `7b`, `SSE-11`'s anchored digit
    screen, carrying its own `timeout:`. The process-global `Regexp.timeout` is never set.
12. **Boundary 23 — `Ractor` is never load-bearing.** `SSE-20`/`SSE-21` get immutability from `Data`
    plus `Dexpace::Model`; `Model.own`'s use of `Ractor.make_shareable(…, copy: true)` is a
    deep-freezing *copy* helper and shareability is a free side effect, no part of any claim.
13. **Boundary 24 — phases 1 through 7 test against an in-memory fake.** `7b` needs no transport at all;
    its fixtures are `StringIO`-backed and `IO.pipe`-backed bodies, plus phase 2's fakes where a
    `Response` is needed for `SSE-32`.

Boundaries 2–9, 18, 20 and 21 are `7a`'s or `7c`'s and have no site in `7b`.

---

## Cross-cutting constraints that bite `7b` specifically

- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** The one lock in `7b` is `Closeable`'s, held
  across the flag flip only and never across a read, a parse or any suspension point. `7b` adds no
  second lock; `SSE-18` leaves the *parser* unsynchronised on purpose.
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden.** `SSE-31`'s cross-thread close
  tears the resource down and lets the blocked read fail; it never interrupts the reading thread. There
  is no interrupt anywhere in the subsystem.
- **`IO-40` forbids this layer from owning a timeout** (`resource-management/d1f16cad`). Neither the
  reader nor the facade imposes one; a stream that never sends a byte blocks until the transport's own
  deadline fires, which is the transport's to own.
- **Deadlines are explicit values, not ambient interrupts.** `7b` threads none, because no `SSE`
  requirement names one.
- **`Fiber[:key]` rather than `Thread.current[:key]`** — `7b` carries no diagnostic context, but the
  rule matters negatively: nothing in the subsystem may key state off `Thread.current`, since an
  `Enumerator`'s internal fiber is a different fiber and `#events` returns one.
- **`URI::RFC3986_PARSER` and `Time.parse`** have no site in `7b`. Neither cop fires here.

---

## Testing strategy

- **One suite per `lib/` file**, each opening with a header comment naming the requirement IDs it
  exercises (`CLAUDE.md`'s citation convention), under `ruby -w` with `RUBYOPT=-W:deprecated`.
- **The conformance clauses drive the tests, not appendix C.** Several `SSE` clauses specify a *test
  shape* rather than a value, and a suite written from appendix C alone would miss them: `SSE-31`'s two
  shapes (`R6`), `SSE-17`'s instrumented source asserting the reader never closes it, `SSE-23`'s
  close-counting resource across five termination paths, `SSE-35`'s instrumented deserializer counting
  decodes against pulls, and `SSE-39`'s read-count assertion.
- **A grammar battery for `SSE-1`–`SSE-12`**, table-driven from the chapter's own conformance examples
  verbatim — `data: 1\n\ndata: 2\n\n`, `id: 1\ndata: a\n\ndata: b\n\n`, `data\n\n` and `data:\n\n`,
  `data: hello` versus `data:   hello`, `:keep-alive\n\n`, `garbage: zzz\nevent: kept\ndata: p\n\n`,
  `id: a\0b\ndata:x\n\n` and `id: good\nid: a\0b\ndata:x\n\n`, `retry: 5000` / `retry: bad` /
  `retry: -100` / `retry:` — plus the same event parsed with each of the three terminators and with
  mixed terminators, asserting identical data lists (`SSE-2`'s own clause).
- **A property test over the terminator grammar**: for a generated sequence of lines and a generated
  assignment of terminators, the parsed line list equals the generated one. Seed pinned and logged
  (`testing/7ece0212`). This is the exhaustiveness claim for `SSE-2` in executable form, and it is where
  a lone-CR-at-a-chunk-boundary case will surface if the pushback is wrong.
- **A mutation battery on the caps**: a line of exactly `MAX_LINE_BYTES` passes, `+1` raises; an event
  block whose accumulated bytes are exactly `MAX_EVENT_BYTES` passes, `+1` raises; and the assertions
  name the constants rather than the literals, so a second constant would break the test rather than
  pass it. This is 3b's and 4b's precedent for the same shape, and it is two allocations of ~1 MiB and
  ~8 MiB per run per matrix row — the one place `7b` allocates at scale, stated so it is a decision.
- **Every encoding assertion uses non-ASCII content**, and at least one uses invalid UTF-8 bytes to
  assert the `:replace` policy rather than a raise.
- **SimpleCov `minimum_coverage 80`** per the gate table; `7b`'s branch-heavy line machine is where a
  coverage gap would hide, so the grammar battery is written before the machine rather than after.

---

## The interface surface later phases may cite

Stated as a contract, so a later phase cites rather than re-derives.

| Consumer | What it gets, and the obligation |
|---|---|
| **`7c`**, optionally | `tools/serde_boundary.rb` and `gates:serde_boundary`, if `7b` lands first. `7c` moves the `page/**` row from `PENDING` to `GUARDED` — **one line** — and writes no second tool and no second rake task. If `7c` lands first, `7b` does the mirror-image one-line change |
| **Phase 8**, on `SSE-41` / `DEF-8` | `Dexpace::SSE::Reader` and `Dexpace::SSE::Stream` are what a reactive adapter would wrap. `SSE-39`'s pull-based, no-read-ahead property is implemented on the pull path, so `ASYNC-21`'s backpressure obligation is inherited rather than rebuilt (§11.21) |
| **Phase 8**, on transports | A transport hands back a `Dexpace::Response`; `Dexpace::SSE::Stream.open(response)` is the whole integration. `7b` requires nothing of a transport beyond `Response#body` answering `#source`, which is 3b's contract |
| **Phase 9**, on `SSE-37` | The audit target: `gates:serde_boundary`'s `GUARDED` list, and the repository-wide check that its `PENDING` list is empty by the end of phase 7 |
| **Phase 9**, on `XCUT-12`/`XCUT-15` | `SSE-20`/`SSE-21`'s frozen `Data` values satisfy `XCUT-15` by construction; `7b` claims neither ID and carries no row for either |
| **A downstream SDK author** | `Stream#typed(&mapper)` is the only extension point, and it is deliberately the only one: `SSE-37` means core will never recognise a done-sentinel or an error envelope, so a generated SDK's conventions live in its mapper. `SKIP` and `DONE` are the vocabulary |

---

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`.

**Numbering.** Phase 7's rows are `P7-<n>`. `7a`, `7b` and `7c` are being written concurrently and
cannot coordinate, so this document takes a **reserved band** rather than starting at `P7-1`:
`P7-1`–`P7-19` for `7a` (which runs first under the charter's recommended order), **`P7-20`–`P7-39` for
`7b`**, `P7-40`–`P7-59` for `7c`. A gap in a phase-local numbering is harmless; a three-way collision at
filing time is not. If the human filing the three documents prefers contiguous numbers, renumbering is
safe today because no `P7-<n>` is cited outside phase-7 documents yet — but it must happen in the same
change that files all three.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P7-20 | `7b`'s line machine is built over `Dexpace::IO::BufferedSource#getbyte`, **not** over phase 3a's `#read_line_utf8`, and design §7.2's sentence naming that method as the SSE machine's primitive is wrong on the clause that matters | `SSE-2`; `IO-14`; design §7.2 (`:50-53`, `sse-streaming/8c25db7d`); `OI-5`; charter boundary 15 | `IO-14` requires a lone `\r` be **kept as content** and `SSE-2` requires it **terminate a line** — contradictory grammars over the same bytes, and phase 3a implemented `IO-14` (`…phase3a…-design.md:659`, plan `:2201`). Post-processing a `#read_line_utf8` result reproduces `SSE-2`'s lines but breaks `SSE-39`: a conforming CR-only stream contains no `\n`, so the method would buffer the whole stream before returning, which is both the read-ahead `SSE-39` forbids and the unbounded allocation `OI-5` exists to prevent. The correction is one clause in §7.2 and one premise in `OI-5`; nothing about `IO-14` or `P3-4` changes |
| P7-21 | `SSE-19`'s MAY is taken as **two** documented bounds — `MAX_LINE_BYTES` 1 MiB and `MAX_EVENT_BYTES` 8 MiB — with an over-long line or event **rejected loudly and never truncated**, and both settable per reader through a constructor keyword | `SSE-19` (chapter `:33` and `…appendix-c…:428`); design §7.2, §10.18; `OI-5` | The chapter sanctions capping "oversized lines"; appendix C states the open surface as "no maximum line **or event** size". A line cap alone leaves 2^20 one-byte `data:` lines unbounded, so the MAY's inverse is taken over the whole of the subject the requirement names and no further — there is no cap on events per stream. Truncation silently corrupts a payload; §10.18's own sanction is "fails or ignores loudly". The keyword is not `DEF-28`'s shape because the caller constructs the reader and is therefore the configuration source, which is exactly the distinction `OI-5` draws when it rules the same keyword out one layer down |
| P7-22 | `SSE-15`'s end-of-stream sentinel is Ruby's `nil`, not a distinguished object | `SSE-15`; `api-design/6ea28c9c` | A stream terminator is the documented exception to never-`nil`-for-absent: `#gets`, `#getbyte` and `IO-14`'s own `#read_line_utf8` all use it, an `Event` is never `nil` so the sentinel is stable and distinct, and the facade — which is what nearly every caller uses — turns it into `Enumerator` termination and never surfaces it. Recorded because `RECOV-1`'s `#response_or_nil` set the precedent that this needs a row rather than a shrug |
| P7-23 | `SSE-34`'s three outcomes are the mapper's decoded value returned **bare**, plus two frozen `Dexpace::SSE::Signal` singletons `SKIP` and `DONE`; `Dexpace::Outcome::Success`/`Failure` are **not** reused | `SSE-33`, `SSE-34`, `SSE-35`; `RECOV-1`; charter boundary 10; phase 4b's forward table (`…phase4b…-design.md:1528`) | `Outcome::Success = Data.define(:response)` with `build: (response: Dexpace::Response)` — a decoded model is not a response, and putting one there fails `steep check` and pulls toward widening a phase-4b type, which boundary 10 forbids. `Outcome`'s five derived methods answer success-versus-failure and Skip and Done are both successful. Returning the value bare also satisfies `SSE-33`'s "MUST yield the mapper's decoded value" literally, allocates nothing per event on a long-lived stream, and lets a mapper decode an explicit null. Boundary 10's two binding clauses are both honoured; only its "reused" framing is declined |
| P7-24 | `SSE-7`'s field-name comparison is **case-sensitive**, so `7b` calls `downcase` nowhere and the charter's spec-forced boundary 19 has no site in this sub-phase | `SSE-7`; `HTTP-13`; charter boundary 19 | WHATWG compares SSE field names exactly, and `SSE-7` names four lowercase tokens and requires that "any other field name MUST be silently discarded". A fold would make `DATA:` an interpreted data field, which WHATWG discards and `SSE-7` requires be discarded. The boundary is honoured vacuously rather than at a site, and the charter's sentence naming `SSE-7` as one of three fold sites is corrected |
| P7-25 | The facade's factories are `Stream.open(response)`, `Stream.owning(source)` and `Stream.borrowing(source)` — deliberately **not** `.over` | `SSE-23`, `SSE-32`; `SEAM-14`/`XCUT-22`; `message-bodies/f060d944` | `Dexpace::IO::BufferedSource.over` means **borrowing** and `.wrapping` means **owning**. A `Stream.over` in the neighbouring subsystem would read as the same polarity and mean the opposite, which is a name that is wrong in the one way review does not catch. `Closeable`'s ownership-at-construction rule is what the three names make legible at the call site |
| P7-26 | The SSE decode is retag-then-transcode `UTF-8 → UTF-8` with `invalid: :replace, undef: :replace`, both encodings named, applied per extracted field value rather than per chunk | `io-and-byte-streams/6eb5155f`, `/a44b4de6`; design §3.1; `OI-7` | `text/event-stream` is UTF-8 by definition, so the declared source encoding is not a guess and no `MediaType#charset` is consulted. `String#b` first because `force_encoding` raises on a frozen chunk even when the target is the string's own encoding; both encodings named because `undef: :replace` with no target follows `Encoding.default_internal`, a process global the host sets. Per field value rather than per chunk so the caps count bytes and a multi-byte character cannot straddle a bound |
| P7-27 | Public constants and methods design §7.2 does not name: `Dexpace::SSE` itself, `::LineReader`, `::Signal`, `::SKIP`, `::DONE`, `::LimitExceededError`, `::StreamStateError`, `::TypedStream`, `MAX_LINE_BYTES`, `MAX_EVENT_BYTES`, `MAX_RETRY_MS`; and the methods `LineReader#next_line`, `Reader#next_event`, `Stream.open`/`.owning`/`.borrowing`/`#each`/`#events`/`#typed`, `TypedStream#each`/`#close`, `Event#empty?` and `Event`'s five generated readers | `NFR-4`; `api-design/b0e18938`; P2-11, P3-14, P4-23 and P4-24 precedent | `NFR-4` locks a public *name* before it locks a signature, and §7.2 names exactly one Ruby constant in the whole subsystem (`Dexpace::SSE::Event`). Each addition is deliberate rather than incidental: `LineReader` is public because `SSE-2`'s grammar has its own conformance clause and the cap lives on it; `Signal` is public because a caller writes `Dexpace::SSE::SKIP` in their own mapper; the three constants are public because `SSE-19` and `SSE-11` require them documented. `Event`'s `Data`-generated readers are public API too and are invisible to `rbs validate` — the runtime surface snapshot is what holds them, and the plan's last task regenerates both artifacts |

---

## Deferrals filed by `7b`

**None.** Every one of `7b`'s 41 IDs is implemented here or carries the pre-existing `DEF-8` row. No
`7b` decision postpones an interface: `R4`'s cap ships with a value, `R5`'s sentinels ship, `R6`'s two
tests are both written, and `R11`'s audit is built rather than described.

### Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the whole register and disposition every row.
All forty-two were read. The charter stated each disposition and this document **performs** the one that
belongs to `7b`, which is a ⏳ row and not a register edit.

- **`DEF-8` — carried as a ⏳ row inside `7b`'s 41; not picked up; its condition is not met.** Verified
  against the row itself (`docs/deferred-items.md:157-164`) rather than the charter's summary: the
  reason ("scoped to a reactive adapter; the MVP ships only the pull-based SSE view"), the pick-up
  condition ("revisit if a reactive SSE adapter is ever built") and the `Cites:` line (`SSE-41`) are all
  still correctly stated and none needs an amendment. `7b` builds no reactive adapter. **`7b` carries no
  `ASYNC-21` row** — §11.21 makes it adapter-scoped-and-vacuous and phase 8's, and the property it
  protects is `SSE-39`'s, implemented here.
- **`DEF-24` — untouched, and phase 4 is where it closes.** Its `Cites:` line names `SSE-29` and
  `SSE-36` — two `7b` IDs — but its pick-up condition is phase 4, and phase 4b's design ships
  `Dexpace::Suppressible`, `Dexpace.attach_suppressed` and `Dexpace.suppressed`. **`7b` is a consumer of
  the row's subject, not its owner**; it writes no second trail and no second skip.
- **`DEF-27` — untouched; closed in 5b.** `Dexpace.close_quietly`'s `onto:`-absent diagnostic is what
  `SSE-30`'s "reported out-of-band" resolves to, and `7b` calls it rather than supplying it.
- **`DEF-33` — untouched, and `7b` inherits its limitation rather than meeting or closing it.** `R6`.
  `SSE-31` rides on phase 2's mutex-guarded latch, whose *mechanism* no CRuby matrix row can exercise;
  `7b`'s checklist row says so.
- **`DEF-2` — untouched by `7b`.** The charter argued phase 7's decline in full and named `SSE-38` as
  half the argument: `SSE-38` positively **forbids** the SSE layer from setting a request header, so `7b`
  constructs no conditional request and cannot fire `HTTP-50`'s condition. The register edit is the
  charter's finding, not `7b`'s.
- **`DEF-16`, `DEF-22`, `DEF-26`, `DEF-28`, `DEF-29`, `DEF-31`, `DEF-32`, `DEF-34`, `DEF-35`, `DEF-38`,
  `DEF-40`, `DEF-42` and the remainder — untouched**, all `7a`'s, `7c`'s, an earlier phase's or a later
  one's. Two are worth naming because a reader will wonder: **`DEF-28`** is cited by `P7-21` as a
  *precedent* about widening a signature with a defaulted keyword, not as a row `7b` acts on; and
  **`DEF-26`**, picked up in phase 3b, narrowed `Response#body` in `sig/` to `Dexpace::ResponseBody?`,
  which is the type `SSE-32`'s nil check is written against.

---

## The findings proposed for the registers

**Seven, described here for a human to file. None is acted on by this document, none carries a number,
and no register file, spec file, design file or corpus file is edited by it.** Findings 1 and 2 are the
charter's, restated because `7b` verified them independently and because `7b` adds a third correction to
each that the charter does not have.

**1. Target register: `docs/open-items.md`, as an amendment to the existing `OI-5` row (not a new row).**
**`OI-5` needs three corrections, and the third changes what its resolution says.**
(a) Its resolution text names **`SSE-11`**, the `retry` field's magnitude cap (a MUST, `…appendix-c…:420`,
cashed out as 2^31−1 ms and catalogued in §10.18). The requirement that obliges the line cap is
**`SSE-19`**, a MAY (`…appendix-c…:428`; the sanction is in the chapter at `:33`), which design §7.2
commits the port to taking. (b) Its `Cites:` line reads `IO-9, IO-14, SSE-11, SSE-12, BODY-32` and
should read `IO-9, IO-14, SSE-2, SSE-11, SSE-12, SSE-19, SSE-39, BODY-32`. (c) Its **premise** is false:
the row says "the consumer that reads lines from a stream a server controls is phase 7's SSE machine",
and phase 7's SSE machine cannot call `#read_line_utf8` at all, because `IO-14` requires a lone `\r` be
kept as content and `SSE-2` requires it terminate a line. So the closure text must say two things — that
the bound `OI-5` asked for exists at the layer `OI-5` named, as `Dexpace::SSE::MAX_LINE_BYTES = 1 MiB`;
and that `#read_line_utf8` itself remains unbounded and finishes the MVP with **no in-repository caller
at all**, which is where `IO-14` puts it and what phase 3a's own YARD says. A closure that said only the
first would leave a reader believing a public method is now guarded. Cites: `IO-9`, `IO-14`, `SSE-2`,
`SSE-11`, `SSE-12`, `SSE-19`, `SSE-39`, `BODY-32`.

**2. Target register: `docs/deviations.md`, or wherever `P3-4`'s as-built text is audited.**
**Phase 3a's `P3-4` row carries the same mis-citation and the same false premise.** Its text reads "the
caller that reads lines from a hostile stream is phase 7's SSE machine, which `SSE-11` obliges to carry
its own documented cap (`OI-5`)"
(`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md:1109`), with the same sentence
at `:1052` and in 3a's plan at `:1831` and `:2157`. Two edits: `SSE-11` → `SSE-19`, and the clause "the
caller … is phase 7's SSE machine" → a statement that phase 7's SSE machine builds its own line reader
because `SSE-2` and `IO-14` disagree about a lone CR, so `#read_line_utf8` ends v1 with no caller.
**Nothing about `P3-4` itself changes** — the widening it records is right and unaffected, and phase 3a
implemented `IO-14` correctly; only the forward-looking clause is wrong. Recorded separately from the
`OI-5` amendment because it is an edit to a phase document rather than a register, and because a
corrected register row pointing at an uncorrected deviation row is how a correction gets lost.

**3. Target register: `docs/open-items.md`, a new row.**
**Appendix C's `SSE-19` row drops the port sanction the chapter carries, and appendix C is what
`CLAUDE.md` calls the index.** The chapter reads "…This is a potential unbounded-memory surface for
untrusted servers; a port MAY add a configurable cap and reject/truncate oversized lines, **documenting
the divergence**" (`docs/product-spec/13-server-sent-events-and-streaming.md:33`). Appendix C's row
(`…appendix-c…:428`) ends at "a growable byte accumulator expands by doubling" and carries no sanction
at all. So a checklist author working from the index — which `CLAUDE.md` names as "the fastest way to
locate a requirement ID" and which the roll-up-hazard guidance points at for canonical text — sees a MAY
that licenses only *accepting* unbounded lines, and would read `7b`'s cap as unsanctioned. The reverse
asymmetry is in the same pair of rows: appendix C says "no maximum line **or event** size" and the
chapter says only "lines/values", and `P7-21` turns on the appendix-C half. Neither row is wrong; the
two together are the only complete statement of `SSE-19`, and nothing says so. `docs/product-spec/` is
frozen, so this is a finding for a human rather than an edit. Cites: `SSE-19`.

**4. Target register: `docs/open-items.md`, a new row (or an extension of the charter's own
corpus-navigation finding, if that one is filed first).**
**Four corpus entries file a phase-7 rule where a phase-7 prefix query cannot reach it, and two of them
are the origin of finding 1.** `sse-streaming/5f4803a0` (Rules) and `sse-streaming/b94ce49e`
(Conclusions) both state the `@viewed` latch on the SSE `Enumerable` view and both carry **only
`PAGE-14`**, so `--req SSE-26` and `--req SSE-40` return neither and `--req PAGE-14` returns two SSE
rules to a pagination author; the charter found the first and not the second.
`sse-streaming/dff112ad` files the 2^31−1 **millisecond** retry conclusion under `(SSE-11, SSE-19)`, so
`--req SSE-19` returns the retry cap — which is the corpus-level origin of the conflation `OI-5` fell
into. `sse-streaming/7adc2212` files the BOM lookahead under `(SSE-12, SSE-11)`, the same artefact in
the other direction. All four are attribution artefacts of harvesting a design sentence that mentions a
neighbouring ID, the same species as `OI-16` and `OI-24`; none is a defect in the rule. Nothing is
broken today because nothing has been implemented. Cites: `SSE-11`, `SSE-12`, `SSE-19`, `SSE-26`,
`SSE-40`, `PAGE-14`.

**5. Target: `docs/knowledge/notes/sse-streaming.md`, a new note under `## Superseded`.**
**`sse-streaming/2dba42b0` states as per-stream state two things two MUSTs forbid.** Its text says the
convenience view "reuses one reader instance so per-stream state (consumed BOM, **current retry value,
last event id**) is preserved across pulls", harvested verbatim from design §7.2 (`:79-84`). `SSE-16` is
a MUST that "**only** the 'BOM already consumed' flag persists across calls; the last-event-id is NOT
carried forward"; `SSE-38` is a MUST that the subsystem "MUST NOT persist a last-event-id across
events"; and `SSE-40`'s own canonical text says "per-stream state (**e.g. BOM consumption**)". Suggested
note body, in the corpus's own shape:

> - **Only the BOM-consumed flag persists across `Reader#next_event` calls; the last event id and the
>   current retry value do not**, superseding `sse-streaming/2dba42b0`. `SSE-16` and `SSE-38` are both
>   MUSTs and both name the last-event-id specifically; carrying a "current retry value" across events
>   is forbidden by the same "only" in `SSE-16`. Design §7.2's parenthesis at `:79-84` lists three
>   things where the requirement lists one, and the harvested entry copied it. The view does reuse one
>   reader instance, which is `SSE-40`'s actual clause; what that preserves is the BOM flag.
>   <sub>review · `docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events-design.md` · high · sha:manual-phase7b-sse16-only-bom</sub>

The correction belongs in `notes/`, never in `harvested/` (`CLAUDE.md`); `docs/knowledge/` is frozen to
this document, so the note is drafted rather than filed. The underlying §7.2 sentence is a
design-document error and is finding 6's neighbour, but §7 is frozen too.

**6. Target: the phase-7 segmentation design, as a correction in place; or `docs/open-items.md` if a
human prefers a row.**
**Two of the charter's own statements do not survive `7b`'s reading, and both are small.** Spec-forced
boundary 19 names "`SSE-7`'s field-name comparison" as one of three sites where the no-argument
`downcase` rule bites; `SSE-7`'s comparison is case-sensitive (WHATWG compares exactly; `SSE-7` names
four lowercase tokens and requires every other name be silently discarded), so `7b` calls `downcase`
nowhere and the boundary has no site here. And spec-forced boundary 15's "a different machine over the
same primitive" is true of the `BufferedSource` and false of `#read_line_utf8`, per finding 2. Neither
changes the cut, the letters, the count or any ID assignment, which is why this is a correction in place
rather than a register row — the same judgement the charter itself made about its two roadmap
refinements. Cites: `SSE-2`, `SSE-7`, `IO-14`, `HTTP-13`.

**7. Target: `.claude/skills/knowledge-lookup/SKILL.md`.**
**The audit-group table's thirteenth row is still owed**, *Serialization, SSE and pagination*, whose
exact content the charter gives at
`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md:212`. The roadmap's first retrospective
rule wants it in place before the first sub-phase runs the group; two phase-7 documents have now run it
without the row existing. It is not a frozen tree, and this document is constrained to two files.

**One row explicitly does not close.** `OI-7`'s subject is a sentence in the frozen §3.1, and `7b`
consumes the corrected recipe (`P7-26`) without touching the mechanism; the item resolves when §3 is
next deliberately amended by a human, as the row itself says.

---

## Open questions for `7b`'s own plan

Four, each with the task that must settle it. None blocks the design.

1. **Does `rbs validate` accept `def retry: () -> Integer?`** on 3.2, 3.3, 3.4 and 4.0? `retry` is a
   Ruby keyword and RBS has its own lexer. Verified fact 4 proves the Ruby side works; the RBS side is
   unverifiable here because no gems are installed. **Task 1** checks it on all three interpreters. If
   it fails, the member becomes `retry_ms`, the plan says so at the point it changes, and a ledger row
   records that `Event`'s member names then differ from the wire field names in exactly one place.
2. **Does `Dexpace::IO::BufferedSource#peek` return a view whose own `#close` is required, and does
   closing it disturb the parent?** 3a's view-retention rule says a view pins the parent's cursor and
   the parent holds nothing back for it, and that a view's later reads fail with `Dexpace::ClosedError`
   once the parent's cursor passes what the view still needs. `SSE-12`'s three-byte lookahead closes its
   view immediately, before the parent has advanced at all, so the rule should not bite — **Task 1**
   confirms it against 3a's shipped behaviour rather than against its prose.
3. **Where exactly does the `SSE-39` read-count assertion attach?** Design §7.2 says "the underlying
   source's read count", but a `BufferedSource` reads a chunk when its buffer empties, so a naive 1:1
   assertion measures the buffer and not the parser. The assertion this design intends is on the
   **body's `#each` yields**: a body yielding one event's bytes per chunk, with the count asserted at 1
   after one pull. **Task 2** builds the counting body and states the assertion; if 3a's buffering makes
   even that indirect, the fallback is a source double implementing `#getbyte` directly.
4. **Is `gates:serde_boundary` already present?** `R11` resolves the convergence in both directions, but
   the plan cannot know which. **Task 11** begins by checking for `tools/serde_boundary.rb`; if it
   exists, the task collapses to a one-line diff and its own fixtures are not written, and the plan says
   so at the step rather than in a preamble.
