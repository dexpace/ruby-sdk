# Phase 7c — Pagination

**Status:** Draft, for review. Written 2026-09-10, against
`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`, which is this sub-phase's charter.

**Path:** `docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md`. That is the path this
document carries for the rest of its life and the one every citation of it should use. Its plan is
`docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination.md`. The checklist is written at execution time
and is not written here.

## Purpose

Sub-phase 7c builds the pagination subsystem in full: the page value and its response ownership, the strategy
contract and the three built-in strategies, the byte-for-byte query splice, the two consumption views over one
lazy drive routine, and the async engine driven through phase 2's `Dexpace::Async::Future#on_settle`.
**Thirty-six requirement IDs, `PAGE-1`–`PAGE-36`, 32 MUST and 4 SHOULD**, all of them stated wholly inside
`docs/product-spec/12-pagination.md` and satisfied wholly inside this sub-phase. No ID moves in from another
phase and none moves out. `dexpace-core` only; `7c` writes nothing into `dexpace-serde-json` and nothing into
`dexpace-conformance`.

**It is the sub-phase the charter recommends last, and last is a convenience.** The charter's own reason —
"`7c` has the smallest inherited-surface footprint and the most self-contained object graph … It is the safest
to run last, and equally the safest to run in parallel with either other"
(`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`, *The order that is recommended*) — is a
statement about risk retirement, not about dependency. The Prerequisites section below states the
independence in `7c`'s own words rather than inheriting a chain by habit, which is what the roadmap's phase-7
bullet requires in as many words.

**Four decisions the charter named and declined to make are made here** — `R7`, `R8`, `R9` and `R10` — plus
`R11`'s phase-level question of which sub-phase owns spec-forced boundary 5's audit, answered from `7c`'s side
so that the answer is correct whichever of `7b` and `7c` lands first. Two of the four turn on a fact this
document **measured on 3.4.10 rather than reasoned about**, because the charter could describe the shape of
each problem but not the interpreter's answer to it:

- **`R8`** — `PAGE-15`'s wrapping clause presupposes "a stream whose terminal cannot declare the underlying
  I/O error type". Measured: a close error raised from an `ensure` while `Enumerable#first`,
  `Enumerator::Lazy#first(2)`, an explicit `break` or a plain block is unwinding reaches the caller
  **unwrapped and unchanged**, on all four. There is no such terminal in Ruby, because Ruby declares nothing.
  The clause is vacuous by a false antecedent, and it gets a ledger row (`P7-1`) rather than a fabricated
  wrapper type. **What is not vacuous** is the trap the same measurement exposed, and it is the sharper half
  of `R8`: a bare `ensure` that lets a close error escape makes the close error **primary even when the
  consumer already failed**, which is the exact inversion of `PAGE-13` and `PAGE-32`.
- **`R9`** — `PAGE-29`'s executor mode. The charter frames it against phase 5a's `Dexpace::Async.delay`,
  which raises `Dexpace::SeamError` with no `Fiber.scheduler` (`P5-9`). **`7c` never calls it**: not one of
  `PAGE-25`–`PAGE-33` computes, requests or waits out a delay, so the whole `Async.delay` question is
  unreachable from this sub-phase. What remains is a genuine question, answered in `R9`.

## Governing documents

- `docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md` — the charter. It fixes `7c`'s 36 IDs, the
  twenty-four spec-forced boundaries, the five rejected cuts, the single convergence point, and risks `R7`–`R11`
  (`R1`–`R3` and `R12` belong to `7a`; `R4`–`R6` to `7b`; `R11` is phase-level and answered here from `7c`'s
  side).
- `docs/product-spec/12-pagination.md`, **read in full (86 lines), chapter intro included**, together with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` rows 374–409 for the canonical
  text and modal level of all 36 IDs. The chapter intro carries two properties no `PAGE` ID restates and the
  chapter's own "A port MUST preserve …" sentence does not enumerate; both are treated below.
- `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` §7.1 in full — the two `Enumerator`s over one
  drive routine, the verified close-on-abandon asymmetry, the hard rule it forces, the one-slot look-ahead's
  home, the verbatim query splice, and the async engine's four named properties.
- `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` item **6** (`:58-62`, the
  core-owned suppressed trail, naming `PAGE-13` and `PAGE-15`) and item **18** (`:119-124`, the
  platform-constant substitutions — cited for its *shape*, since no `PAGE` constant joins its list).
- `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` item **15**
  (`:51-53`, "clauses with no Ruby manifestation"), which is the family `R8`'s answer joins, and
  `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:36`, whose `PAGE` row is the authority for
  `PAGE-35`'s disposition.
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.5 (the `URI::RFC3986_PARSER` pin, the
  component encoder) and §3.1's encoding boundary; §4 (the per-pattern regexp timeout, `Data`-based value
  types); §8.3 (the interrupt prohibition, deadlines as explicit values).
- The predecessor designs whose forward tables this document cites rather than re-derives:
  `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md`,
  `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md`,
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md`,
  `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md`,
  `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`,
  `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`,
  `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`,
  `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md`,
  `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-design.md` and
  `docs/work/mvp/phase6/phase6c/2026-09-09-phase6c-authentication-design.md` as the two closest worked
  examples of this document's form.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-7 row (`:92`), the ordering rationale
  (`:115-118`), and cross-cutting constraint 4 (`:52-53`), which is the only one of the nine that binds `7c`
  directly.
- `docs/deferred-items.md`, `docs/open-items.md`, `docs/deviations.md`, `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

---

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written, and re-run for this
document rather than trusted from the charter's report.

- `ruby scripts/knowledge.rb --origin note --brief` returns **38 entries across 19 note files**.
- `ruby scripts/knowledge.rb --section conflicts --brief` returns **24 entries across 17 topic files**, of
  which the six harvested styleguide-versus-design conflicts every one print `[overridden by notes/…]`.
  **None is open**, so `7c` inherits no unresolved conflict and owns no conflict decision of its own.
- Narrowed to this sub-phase's prefix, `--origin note --prefix PAGE` returns **exactly one** entry
  (`pagination/318ae05d`) and `--section conflicts --prefix PAGE` returns **none**.

**Coverage and the roll-up hazard.** `--prefix-info PAGE` reports **36 of 36 substantive, 0 roll-up only, 0
uncited**, and names the owning chapter and the three topics carrying `PAGE` knowledge (`pagination`,
`sdk-positioning`, `concurrency-and-async`). `--gaps PAGE` closes with "0 of 36 IDs in 1 prefix have no
substantive entry". **`7c`'s spec-reading budget is zero**, which the roadmap forecast (`:161`) and which this
document discharges by saying so — while reading the chapter in full anyway, because the `*Conformance:*`
clauses appendix C does not carry are load-bearing here more than usual (`PAGE-12`'s two-shape clause and
`PAGE-27`'s four-path clause are each two tests for one row). The charter's warning stands and was obeyed: a
third of `PAGE`'s 92 entries are `[appendix-B roll-up]`-tagged, so **`--req <ids> --section
rules,constraints,conclusions` is the query on this prefix and a bare `--req` is not**, even though no ID is
roll-up-only and the CLI's all-roll-up WARNING never fires.

**The audit group was run.** `ruby scripts/knowledge.rb --prefix PAGE --section rules` returns **36 entries
across 3 topic files** (`pagination`, `retry-and-resilience`, `sse-streaming`), **zero roll-up-tagged** — the
roll-ups live entirely in `Reference`, exactly as the charter reports. Every substantive bullet is a faithful
restatement of chapter 12's prose or design §7.1's own words, and none contradicts a decision this document
makes, so **no note is filed against `pagination`'s rules.** The charter records that the
`knowledge-lookup` audit-group table is owed a thirteenth row, *Serialization, SSE and pagination*; that is
the charter's obligation and its exact content is in the charter, not restated here.

`docs/knowledge/notes/pagination.md` was read in full — both entries, not the query summary.

### The two known navigation defects, and the two more this audit found

The charter names two corpus-attribution artefacts that cost a `7c` author a rule. Both were confirmed. **Two
more were found while running the audit, and one of them is sharper than either**; all four are proposed as a
register finding below rather than acted on here.

1. **`sse-streaming/5f4803a0` is an SSE rule filed under `PAGE-14` and under no `SSE` ID** — confirmed.
   `--prefix PAGE --section rules` returns it, so a pagination author reading their own audit group is handed
   the SSE facade's `@viewed` latch.
2. **`sse-streaming/b94ce49e` is the same defect, in the same topic, on the companion entry, and the charter
   does not name it.** It is the `Conclusions` half — "The single-use guard on the SSE `Enumerable` view is a
   SHOULD requirement that the port implements outright rather than deferring" — and it too carries **only
   `PAGE-14`**. So the defect is a pair, not a singleton, and a correction that names only `5f4803a0` leaves
   half of it standing.
3. **`pagination/b2a85752` does not carry "no requirement ID at all"; it carries `BODY-11`.** The charter's
   characterisation is inaccurate, though its *consequence* is exactly right: `--prefix PAGE` misses the
   entry, while `--prefix BODY` and `--req BODY-11` return it. Verified both ways. The correction matters
   because a reader chasing "an entry with no IDs" will not find it and may conclude the defect was fixed.
4. **The property spec-forced boundary 5 exists to protect is harvested nowhere at all.** `pagination/cb5f1b9e`
   harvests `docs/product-spec/12-pagination.md:3` as "A port MUST preserve the pagination engine's two-view
   model, page-lazy fetch discipline, deterministic response-lifecycle management, and strategy contract" —
   the second half of that line. **The first half — "It is transport-agnostic and serde-agnostic" — appears in
   no entry in the corpus.** `ruby scripts/knowledge.rb --grep 'serde-agnostic|transport-agnostic'` returns
   exactly one hit, `http-domain-model/f4bd2330`, which is `XCUT-18`'s validation layer and unrelated. So the
   property is invisible to every corpus query, carries no requirement ID, and — until boundary 5's audit
   exists — is enforced by nothing. That is not an argument against the boundary; it is the strongest argument
   for it, and it is stated here because a `7c` author who queried the corpus for "serde-agnostic" and found
   nothing would reasonably conclude the property does not exist.

**One note binds this sub-phase and is quoted rather than paraphrased**, because a design document that cites
it by key without the load-bearing sentence in view is the failure the note exists to prevent.

- **`pagination/318ae05d`** — the rule the whole of `7c`'s lifecycle is built on:

  > **The rule reaches phase 3 first.** … `Dexpace::IO::BufferedSource.over(body)` pulls chunks from a body's
  > `#each` on demand … and `IO-41`/`IO-42`/`BODY-15`/`BODY-27` all put a real transport resource behind a
  > close that must actually run. So the owning object with its own `ensure` and its own `#close` is a
  > **phase-3 obligation**, discharged through phase 2's `Dexpace::Closeable` latch, and **phase 7 inherits a
  > rule already paid for rather than discovering it.**

  <sub>review · `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md` · high · sha:manual-phase3-enumerator-range</sub>

- **`pagination/b2a85752`** — the half that closes the escape hatch. An `ensure` inside a plain `def each`
  behaves exactly like an `Enumerator.new` block under external iteration, and `block_given?` is **true**
  inside `#each` when reached through `to_enum(:each)` and `#next` — so a `raise unless block_given?` guard
  forbids nothing. **There is no in-method defence; the only defence is where the resource lives.**
  <sub>review · `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` · high · sha:manual-phase3b-each-method-abandonment</sub>

- **`pagination/71aed9c1`** and **`pagination/9bdf90fc`** — the two views over one internal drive routine, and
  the one-slot look-ahead living on the engine rather than in the enumerator's closure. Both are consumed
  directly by the object model below.

- **`pagination/86b5a3a3`** — the whole `URI.decode_www_form`/`CGI.parse`/`URI::Generic#query=`-re-render
  family is rejected for `PAGE-21`/`PAGE-22`. Measured again for this document (verified fact 4), because a
  design that cites a recollection here has cited nothing.

**No knowledge note is filed by this document.** The Ruby facts it measures are recorded below; the notes that
would carry them belong with the implementation that acts on them, which is phases 3, 5 and 6's stated
treatment of the same situation. Recorded here so their absence is a decision rather than an omission.

---

## Scope: the 36 IDs

### Disposition

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `PAGE-1`–`PAGE-34`, `PAGE-36` | 35 |
| Implemented as **vacuous by construction** — the conditional antecedent is declined, not the requirement | `PAGE-35` (SHOULD) | 1 |
| ⏳ deferred | **none** — design §12's `PAGE` row reads "*Deferred:* none" | 0 |
| **Total in budget** | | **36** |

**Level split, derived mechanically from appendix C rows 374–409 on 2026-09-10: 32 MUST, 4 SHOULD
(`PAGE-10`, `PAGE-20`, `PAGE-31`, `PAGE-35`), 0 MAY, 0 MUST NOT.** 32 + 4 = 36, which is the charter's figure
and the roadmap's phase-7 cell's `PAGE` component (`:92`). **`7c` adds no unsatisfied MUST**; the port's three
live under `ASYNC-3`, `ASYNC-4` and `PIPE-33` (§10.5) and `7c` adds no fourth.

### Six rows the checklist must state rather than tick

Each is a row where "implemented" is true but a bare tick would hide the argument that makes it true.

- **`PAGE-35` is vacuous rather than declined, and the distinction is design §12's.** Its own text is
  conditional — "**If** a mutable paging-options object is offered to fetchers, the *same* instance SHOULD be
  threaded through every fetcher call" — and design §12's `PAGE` row settles it: "the port offers an immutable
  value instead, so the clause is vacuous rather than declined"
  (`docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:36`). A row marked ⏳ or 🚫 would be wrong
  in both directions. See *`PAGE-35`* below for the full justification and for what the port does supply in
  the SHOULD's place.
- **`PAGE-15`'s wrapping clause is vacuous by a false antecedent, and it is `P7-1`.** The ID is implemented;
  its middle sentence is not, because the condition it is conditional on does not exist in Ruby. Measured, not
  argued — see `R8`. The row cites `P7-1` and ticks the ID's other two clauses.
- **`PAGE-16`'s "single read of the response body" is the *strategy's* read, and core performs none.** Per
  spec-forced boundary 4 and `R7`, the built-in cursor strategy's own contribution is the next-request
  derivation and the null-or-empty end-of-stream rule; the items and the cursor come out of a caller-supplied
  extractor. The row names the read-counting body double that asserts "once", because that is the only place
  the clause is observable.
- **`PAGE-21`–`PAGE-24` are this subsystem's obvious-tool-is-wrong case, and the tool is rejected by
  measurement.** `URI.decode_www_form("q=a+b")` returns `[["q", "a b"]]` and
  `URI.encode_www_form_component("a b")` returns `"a+b"` — both the exact inverse of `PAGE-22`. The row cites
  verified fact 4 rather than design §7.1's prose alone. **What the row must also state is the half that is
  already built**: phase 1's `Dexpace::PercentEncoding.encode_component`/`.decode_component` are `PAGE-22`
  exactly, shipped and tested, and `7c` writes no percent codec.
- **`PAGE-28`'s "null success completion" clause is satisfied upstream by phase 2's `SEAM-16` and given a
  code site anyway.** `Dexpace::Async::Settlement` validates that exactly one of `response`/`error` is
  non-nil, so a settled-with-nothing state cannot be constructed. The driver's `Settlement` dispatch still
  carries an explicit `else` that fails the walk, so the clause has a line of code rather than only an
  argument, and the row says which line.
- **`PAGE-33` is discharged by documentation, and the row must say where.** "A port MUST **document** the
  inherent async cancellation race" — the satisfaction is a YARD block plus a stated behaviour, not a test
  that can observe the race. The row names the YARD site (`Dexpace::Page::AsyncPaginator#walk`).

### Canonical text quoted because a decision below turns on it

> **PAGE-5** (MUST) — A strategy MUST read everything it needs from the response synchronously inside parse
> (the body is single-use), MUST NOT retain the response or its body beyond the call, and MUST NOT close or
> mutate the response — lifecycle ownership belongs to the engine. Strategies MUST be immutable and safe to
> share concurrently.

> **PAGE-8** (MUST) — Each independent iteration MUST restart from the initial request with its own fresh
> state; the engine itself MUST hold only immutable configuration and be safe to share. A single returned
> iterator/stream/walk MAY be single-consumer, but two separate iterations from the same engine MUST each
> drive a full fetch sequence and yield identical results.

> **PAGE-11** (MUST) — The item-level view MUST eager-close each page *before* yielding any of that page's
> items (after copying the materialized items), so abandoning item iteration mid-page never strands the
> response.

> **PAGE-12** (MUST) — The page-level view MUST be auto-closing with a close-on-abandon guarantee: close the
> previous page as the consumer advances, close the last page at exhaustion, and — because probing for the
> next page eagerly runs that page's exchange — buffer the fetched-but-undelivered page in storage it owns so
> an emptiness probe or early break followed by an explicit close still releases it. Explicit close MUST
> release both the currently-held page and any buffered page.

> **PAGE-15** (MUST) — A close error while releasing held page(s) MUST be surfaced, not swallowed. When
> exposed through a stream whose terminal cannot declare the underlying I/O error type, it MUST be re-thrown
> wrapped so the caller can still catch it at the close site. When both held pages fail to close, the first
> failure MUST propagate with the second attached as suppressed.

> **PAGE-29** (MUST) — For a single async walk the consumer MUST NOT be invoked concurrently, and items MUST
> be delivered one at a time in server order; the consumer MUST NOT assume a particular thread. By default the
> consumer runs inline on the page-completion thread. The engine MUST also offer a mode running the driver —
> and therefore every consumer invocation — on a caller-supplied executor, so a blocking consumer does not tie
> up transport callback threads.

> **PAGE-32** (MUST) — In the async drain path, releasing a page's response MUST happen whether the consumer
> succeeds or throws, and a throwing close MUST NOT escape the driver: on the success path a throwing close
> MUST be reported through the result future (so the walk terminates instead of hanging); if the consumer
> already failed, that cause stays primary and the close error is swallowed.

**And the chapter intro, which carries two properties no `PAGE` ID restates:**

> It is transport-agnostic and serde-agnostic: a single stateless *strategy* parses each response into the
> page's items plus the fully-formed request for the next page (or an end-of-stream signal), and the engine
> drives iteration, owns each page's live HTTP response, and bounds a misbehaving server with a page cap. A
> port MUST preserve the two-view model, the page-lazy fetch discipline, deterministic response-lifecycle
> management, and the strategy contract described here.
> (`docs/product-spec/12-pagination.md:3`)

The four things the "A port MUST preserve" sentence enumerates are all carried by `PAGE` IDs. The two things
the first sentence states — transport-agnostic and **serde-agnostic** — are not, and this is the sub-phase
that makes the second of them a gate rather than a convention (`R11`).

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `SERDE-1`–`SERDE-30` — the witness protocol, `Tristate`, the two response handlers, the JSON codec | `7a`. `7c` names no `Dexpace::Serde` constant at all (`R11`) |
| `SSE-1`–`SSE-41` — the line machine, the event value, the facade, the typed adapter | `7b`. `PAGE-14`'s single-use latch and `SSE-26`'s are two flags on two unrelated objects |
| `SEAM-11`, `SEAM-16`, `SEAM-17` — the transport and async seams and the pivot | 2 and 8. `7c` consumes `Dexpace::Async::Future#on_settle` and replaces nothing |
| `HTTP-28`–`HTTP-32` — `Query`, `Query::Builder`, `PercentEncoding` | 1, built. `7c` **consumes** `PercentEncoding` and deliberately does **not** consume `Query` — see `PAGE-21` below |
| `HTTP-46`, `HTTP-47` — `Dexpace::URL.parse!` and `.external_form`, the `URI::RFC3986_PARSER` pin | 1, built. `7c` adds `URL.resolve` as a widening (`P7-3`) and writes no second pin |
| `HTTP-34`, `HTTP-35` — `RequestOptions` and its validation | 1, built. `PAGE-36`'s three named overrides are `RequestOptions`'s three members exactly |
| `HTTP-41`–`HTTP-45`, `BODY-14`–`BODY-16`, `BODY-30`, `HTTP-52` — the response body, `#source`, the decode, the bounded error copy | 3b, built. `7c` reads no response body itself |
| `IO-9`, `BODY-32` — `MAX_MATERIALIZED_BYTES` | 3a, one ceiling. `7c` introduces no second materialisation constant and reads no stream |
| `RECOV-1`–`RECOV-16` — `Outcome`, the two chains, the orchestrator | 4b, built. No `Outcome` crosses into `7c`; a page is not an outcome |
| `RECOV-12`, `SEAM-30`, `DEF-27` — `Dexpace.close_quietly(resource, onto:)` | 2, 4b and 5b between them. `PAGE-26` and `PAGE-32`'s swallow clauses are call sites and `7c` writes no second quiet-close path |
| `XCUT-9` — the cycle-safe cause walk | 4b, built as `Dexpace.each_cause`. `7c` walks no `#cause` chain at all, which is what boundary 13 requires of it |
| `PIPE-1`–`PIPE-40` — the stage runtime, the cursor, the fork primitive | 4c, built. `7c` installs no step and forks no cursor |
| `PIPE-26`, `PIPE-27` — a pipeline is a transport; `#close` is a no-op on it | 4c, built, and written into 4c's forward table **for this phase** |
| `CFG-15`–`CFG-21` — the clock, the cancellable wait, `Async.delay` | 5a, built. **`7c` calls none of them**, because no `PAGE` requirement waits (`R9`) |
| `CFG-1`–`CFG-38`, `OBS-1`–`OBS-40` | 5. `PAGE-10`'s documentation clause is a YARD obligation, **not** a configuration key, and `7c` adds none |
| `RETRY-30` — the iterative retry pump | 6a. `PAGE-31`'s trampoline is the same *pattern* over a different object; the specification's own latitude covers both and `7c` shares no code with `6a` |
| `RETRY-1`–`RETRY-45`, `REDIR-1`–`REDIR-28`, `AUTH-1`–`AUTH-38` | 6. Phase 6 cites no phase-7 ID and `7c` cites none of phase 6's |
| `ASYNC-13` — the original-cause-unwrapped rule `PAGE-28` restates | 8. `PAGE-28` is `7c`'s and its realisation is "do not wrap", plus `raise error, cause: nil` where an error is re-raised (`pipeline/f02559b9`) |
| `HTTP-22`, `HTTP-48`, `HTTP-49`, `HTTP-50` — interning, ETag, Range, the conditional-request aggregator | Still deferred (`DEF-2`). **The charter declined the phase-7 target and `7c` does not re-open it** — `PAGE-23` preserves the template's headers and the SDK never originates a request |
| `XCUT-11`, `XCUT-12`, `XCUT-15` | 9 dispositions. `7c` satisfies each by construction: `XCUT-11` through a frozen `Paginator` with all per-walk state on the `Walk`, `XCUT-12`/`XCUT-15` through `Data`-frozen collections |
| `NFR-1`–`NFR-4`, `NFR-11` | 0 built the machinery, 9 dispositions it. `7c` adds no `require` to core's allowlist |

---

## Prerequisites, and the independence this sub-phase must state

**`7c` depends on `7a` for nothing and on `7b` for nothing, and neither depends on `7c`. There is no
exception at all — not even a qualified one.** The charter's finding is stated here in `7c`'s own words rather
than inherited, because the roadmap's phase-7 bullet requires each sub-phase's design to say so rather than
let a chain be inherited by habit:

- **`7c` → `7a` is absent because the strategy is handed an extractor, not a codec.** `PAGE-16`'s items and
  cursor come out of a caller-supplied `#call(response)` object (`R7`). Core's pagination layer names no
  `Dexpace::Serde` constant, requires no `dexpace/serde` file, and ships no JSON-flavoured strategy and no
  default codec. The seam a caller may route through is **phase 2's**, shipped; the codec is `7a`'s and never
  appears here.
- **`7a` → `7c` is absent because `SERDE-27`/`SERDE-28`'s handlers take a `Response`.** Nothing about them is
  page-shaped, and `PAGE-2`'s materialized item list is produced by the strategy, not by a handler.
- **`7c` → `7b` is absent because §12 reads a body once per page through a strategy.** There is no line
  machine and no event anywhere in this sub-phase.
- **`7b` → `7c` is absent because the one thing they share already shipped.** The close-once discipline is
  phase 2's `Dexpace::Closeable` latch and phase 3's owning-object rule. Whichever of `7b` and `7c` lands
  first writes no shared object the other consumes; each writes its own owner over the same already-built
  latch.
- **The single convergence point is not a dependency either.** Spec-forced boundary 5's audit is owned by
  whichever of `7b` and `7c` lands first, and `R11` states both sides so it is neither written twice nor left
  to each assuming the other wrote it. **A `7c` plan whose first task waits on `7a`'s witness protocol or on
  `7b`'s audit has re-imposed a chain that does not exist.**

Every surface below was verified to exist and to be stated as shipping by the named phase's design, on
2026-09-10. Nothing is implemented yet in this repository — these are design commitments, and `7c` inherits
them as such.

### From phase 0 — the seventeen blocking gates

- **`gates:require_allowlist`.** Core may `require` only `monitor`, `uri`, `stringio`, `strscan`, `time`,
  `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`
  (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:459`). **`7c` needs `uri`
  only, and it is already on the list**, so no allowlist diff is required by this sub-phase. `json` is on the
  **denylist** by name — which is exactly why boundary 5 is needed, since the boundary at issue is core's
  pagination layer reaching for core's own `Dexpace::Serde`, which no allowlist sees.
- **The five phase-0 custom cops plus phase 2's sixth.** `Dexpace/SpdxHeader` (`NFR-13`);
  `Dexpace/NoUriDefaultParser`, which bans `URI::DEFAULT_PARSER` and the `URI.parse`/`URI.join`/`URI.split`
  family that routes through it (`:523`) — **this cop is what forces `PAGE-19`'s resolution through the
  pinned parser and is the direct reason for `P7-3`**; `Dexpace/NoLocaleCaseFold`, which rejects **any**
  argument to `downcase` and its family — `PAGE-18`'s `rel` token match is the one fold site in `7c`;
  `Dexpace/NoThreadInterrupt`, which bars `Timeout.timeout`/`Thread#raise`/`Thread#kill`; `Dexpace/NoTimeParse`,
  which binds nothing here because `7c` parses no date; `Dexpace/QualifiedCoreConstant`, which is scoped to
  `lib/dexpace/async/**` and `lib/dexpace/serde/**` and therefore does not reach `lib/dexpace/page/**` — `7c`
  nevertheless `::`-qualifies every core constant, per the repository-wide convention.
- **The gemspec audit and the clean-bundle isolation run.** `7c` spends no adapter budget and adds no
  dependency; both gates pass unchanged.

### From phase 1

`Dexpace::Request` — `Data.define(:method, :url, :headers, :body)`, `url` a **frozen `URI::Generic`** that
`URL.parse!` returned. `Dexpace::Response` — `Data.define(:request, :protocol, :status, :reason, :headers,
:body)`; **the response carries the request that produced it**, which is the object `PAGE-17`'s "originating
(executed) request" and `PAGE-19`'s "originating page's response URL" both resolve to in this port.
`Dexpace::Headers#[]` returns a case-folded frozen `Array[String]` or `nil` — which is what makes `PAGE-20`'s
multiple-Link-header case a `join`, not a special path. `Dexpace::RequestOptions` —
`Data.define(:timeout, :max_retries, :tags)` with a canonical frozen `EMPTY`; **its three members are
`PAGE-36`'s three named overrides exactly** (timeout, retry budget, tags), so `7c` invents no options type.
`Dexpace::PercentEncoding.encode_component`/`.decode_component` — RFC 3986 component encoding with the
unreserved set exactly `A-Za-z0-9-._~`, `+` encoded to `%2B` and decoded back to `+`, verified in phase 1
against the probe input `a b*~+/!()'` → `a%20b%2A~%2B%2F%21%28%29%27`. **That is `PAGE-22` in both directions,
already built and already tested.** `Dexpace::URL.parse!` and `.external_form`; `Dexpace::Model` with its
`.build`-routing `#with` override, `Model.required!` and `Model.own`; `Dexpace::Error` as a **module**;
`Dexpace::InvalidArgumentError`.

### From phase 2

`Dexpace::Closeable` — `#initialize_closeable(owned: true)`, `#owned?`, `#closed?`, `#close`, and a private
`#release` the including class defines. The latch is a `@dexpace_closed` boolean flipped under a
`Thread::Mutex` **held across the flip only**; a `#release` that raises leaves the latch flipped, so no second
release is attempted and the failure propagates exactly once. **This is `PAGE-27`'s "no double-close" and
`PAGE-3`'s idempotence, already built.** `Dexpace.close_quietly(resource, onto: nil)` — null-safe, rescues
`StandardError` from `#close`, never raises over a primary failure; the quiet route `PAGE-26` and `PAGE-32`'s
swallow clauses call. `Dexpace::Async::Future` (`#settled?`, `#cancelled?`, `#value(cancellation:)`, `#wait`,
`#on_settle { |settlement| }`, `#cancel(reason)`), `Dexpace::Async::Completer` (`#future`, `#fulfil`, `#fail`,
`#on_cancel { |reason| }`, `#settled?`, `#outcome`) and `Dexpace::Async::Settlement` =
`Data.define(:response, :error, :cancelled)` with **exactly one of `response`/`error` non-nil** validated in
`initialize` — the constraint that makes `PAGE-28`'s null-success clause structurally unreachable.
`#on_settle` on an already-settled future **invokes the block immediately, on the calling fiber**, which is
precisely the recursion hazard `PAGE-31` exists for. The transport duck type: **any object responding to
`#call(request, options, cancellation)`** and returning a `Response` (sync) or a `Dexpace::Async::Future`
(async). The `SEAM-11`/`SEAM-16` in-memory fakes, which roadmap cross-cutting constraint 4 requires `7c` to
test against — **no `TCPServer` fixture, no socket.** `Dexpace::SeamError` for "a seam in a state the caller
must fix but did not pass in".

### From phase 3a and 3b

Nothing is required by any of `7c`'s 36 IDs, and that is worth stating rather than leaving implicit: **`7c`
reads no response body**, opens no `BufferedSource`, and crosses no encoding boundary. The strategy's
extractor may call `Response#body_string` or `Body#source` — those are 3b's and the caller's, not `7c`'s.
What `7c` does inherit from phase 3 is the **rule**, not an object: `pagination/318ae05d` and
`pagination/b2a85752`, and the shape of an owning object with its own `ensure` and its own `#close`.
`Dexpace::Response#close` is 3b's and is `body&.close` and nothing else — **a pure forward with no latch of
its own**, which is a load-bearing fact for the object model below.

### From phase 4b

`Dexpace::Suppressible`, `Dexpace.attach_suppressed(primary, secondary)` with the self-suppression skip, and
`Dexpace.suppressed(error)`. **A primary that is not a `Dexpace::Error` is handled** (the helper `extend`s
it); **a frozen primary is silently not** (`P4-13`: the `FrozenError` rescue is a deliberate one-class
swallow). That caveat travels with the helper and `7c` states it in the YARD of both call sites rather than
rediscovering it. `PAGE-13` and `PAGE-15` are two of design §10 item 6's four named consumers.
`Dexpace.each_cause` exists and `7c` calls it nowhere — boundary 13 forbids hand-walking a `#cause` chain; it
does not require walking one. The re-raise spelling `raise error, cause: nil` (`pipeline/f02559b9`) wherever
core re-raises an error it is **carrying**.

### From phase 4c

`Dexpace::Pipeline` (`.builder`, `.direct`, `#call`, `#steps`, `#entries`, `#transport`, `#close`) and
`Dexpace::AsyncPipeline` (`.direct`, `.map_response`, `#call` returning a `Dexpace::Async::Future`), with
4c's forward table written **for this phase**: "`PIPE-26`: a built pipeline is a transport, so a paginator
takes one with no declaration. `Pipeline#close` is a no-op on the transport (`PIPE-27`), so a paginator
wrapping one owns nothing"
(`docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md:1436`). **`7c`'s consequence,
stated so it cannot be quietly re-decided**: `Dexpace::Page::Paginator` takes a `#call`-shaped transport, holds
it by reference, declares no `Pipeline` dependency, and **never closes it**. `PAGE-3`'s ownership transfer is
about the **response**, never about the transport it came from. `7c` installs no step, forks no cursor and
touches nothing else of 4c's.

### From phase 5

**Nothing.** No `PAGE` requirement names a configuration key, an instrumentation event, a log level or a
clock. Two adjacencies exist and neither is a dependency: `PAGE-10`'s "documentation SHOULD direct production
callers to set a finite cap" is a YARD obligation and not a `CFG` key, and `Dexpace.close_quietly`'s
`onto:`-absent diagnostic is 5b's and is reached through phase 2's helper, not through a phase-5 call.
**`Dexpace::Async.delay` is named here only to say `7c` never calls it** — see `R9`.

### From phase 6

**Nothing, in either direction.** Phase 6 cites no phase-7 ID and `7c` cites none of phase 6's. Two
resemblances are named so a reviewer does not mistake either for an edge: `PAGE-31`'s trampoline is the same
*pattern* as `RETRY-30`'s pump over a different object, and `PAGE-18`'s character-level link parser is the
same *shape* as `6c`'s `Dexpace::Auth::Challenges`. **Neither shares a line of code**, and the grammars are
genuinely different — `WWW-Authenticate` is a scheme plus an `auth-param` list with `token68`, `Link` is an
angle-bracketed URI-reference plus a `;`-separated parameter list. Reusing either parser for the other would
be the worst kind of false economy, and it is declined explicitly here rather than left unconsidered.

---

## `R7` — what a strategy is handed, and what the built-in three take

**Decision: a strategy is `#parse(response, template) -> Dexpace::Page::Info`, validated by
`respond_to?(:parse)`; and the built-in cursor and page-number strategies take a caller-supplied
`#call(response) -> [items, cursor_or_nil]` extractor, never a codec and never a witness.**

The charter fixes the constraints and leaves the shape open: `PAGE-5` fixes the parse contract, spec-forced
boundary 4 fixes the serde-agnosticism, and `NFR-4` locks whatever ships. Three shapes were considered.

**Rejected — a `Dexpace::Serde` duck type plus a witness on the strategy.** This is the shape the reference
contract's own vocabulary suggests, and it is wrong here for a reason that is mechanical rather than
aesthetic: a constructor keyword named `serde:` or `witness:` puts the words `Serde` and `witness` inside
`lib/dexpace/page/**`, and **spec-forced boundary 5's audit would fail on `7c`'s own code**. An audit a
sub-phase has to carve an exception into is an audit that has already stopped meaning anything. The
serde-agnosticism the chapter intro states would then be true only of the *default*, which is the position
§12 is written to prevent.

**Rejected — both, with the codec route as a convenience overload.** Two constructors, one `NFR-4` lock each,
and the same audit problem on the second. `api-design/b0e18938`'s minimal-surface rule settles it against the
larger surface where the smaller one loses nothing.

**Adopted — the plain extractor.** `Dexpace::Page::CursorStrategy.build(extract:, parameter: "cursor")`.
`extract` is any object responding to `#call`, given the `Dexpace::Response` and returning a two-element
`[items, cursor]`. The consequences are all stated, including the uncomfortable one:

- **A caller who wants JSON writes the codec into the closure**, outside core:
  `->(r) { doc = codec.load(r.body.source, witness); [doc.items, doc.cursor] }`. That is exactly where
  boundary 4 says the extraction belongs — "performed through whatever extraction the caller supplied, which
  may be an object conforming to phase 2's `Dexpace::Serde` duck type and is **never** `Dexpace::Serde::JSON`."
- **`PAGE-16`'s "single read of the response body" becomes a contract `7c` asserts rather than performs.**
  Core reads nothing. The assertion is a read-counting body double that fails if the built-in strategy touches
  the body at all, plus a documented obligation on the extractor. The row states this; a tick that implied
  core does the reading would be false.
- **`PAGE-5`'s three prohibitions become assertions about the built-ins.** The strategies are frozen `Data`
  types with no instance state, so "immutable and safe to share concurrently" is structural; "MUST NOT close
  or mutate the response" is asserted against a close-counting `Response` double across all three; "MUST NOT
  retain the response or its body beyond the call" is asserted by holding a weak expectation that no built-in
  strategy has an instance variable at all.
- **`PAGE-4`'s "never by throwing"** governs the strategy, and an extractor that throws is *not* the strategy
  signalling termination — it is a parse failure, and `PAGE-13` is the path it takes. The built-in strategies
  therefore do **not** rescue the extractor. Stated explicitly, because rescuing it and returning a null
  next-request would convert every server-side schema change into a silently truncated stream.
- **The `LinkStrategy` takes an extractor for items only**, because its next-request comes from the `Link`
  header and not from the body: `Dexpace::Page::LinkStrategy.build(extract_items:, header: "Link")`.

---

## `R8` — `PAGE-15`'s wrapping clause, measured

**Decision: the wrapping clause is vacuous by a false antecedent. `7c` implements `PAGE-15`'s other two
clauses in full, ships no wrapper type, and records the vacuity as `P7-1`. The measurement that settles it
also exposes a trap that is not vacuous, and that trap shapes every `ensure` in this sub-phase.**

### The antecedent, tested

The clause reads: "When exposed through a stream **whose terminal cannot declare the underlying I/O error
type**, it MUST be re-thrown wrapped so the caller can still catch it at the close site." The antecedent is a
language with checked exceptions, where a stream terminal's signature cannot name the exception a close might
raise and an unchecked wrapper is the only way through. Ruby has no checked exceptions and no terminal that
declares anything, so the antecedent looks false — but "looks false" is what §11.15's family is for, and the
charter asked for a decision, not an intuition.

**Measured on 3.4.10, one case per terminal shape** (verified fact 1 below). A scoped helper owning a resource
whose `#close` raises `Boom`, driven four ways:

| Terminal | Result |
|---|---|
| `Enumerable#first` (internally short-circuits with `break`) | `Boom` reaches the caller, **unwrapped** |
| `Enumerator::Lazy#map { }.first(2)` | `Boom` reaches the caller, **unwrapped** |
| explicit `view.each { \|x\| break x if … }` | `Boom` reaches the caller, **unwrapped** |
| the block simply returning a value | `Boom` reaches the caller, **unwrapped** |

**There is no Ruby terminal that cannot surface a close error at the close site**, because there is no
declaration to be unable to make. A `Dexpace::` wrapper type introduced to satisfy the clause would be a type
with no reachable construction site and one more `NFR-4` lock, and every caller would have to `rescue` two
things where the language already delivers one. `P7-1` records it, joining §11.15's family
(`CFG-34`'s boxed-versus-primitive array clause, `SERDE-11`'s unchecked exceptions, `SERDE-14`'s covariance)
rather than inventing a mechanism.

**What `PAGE-15` therefore is, in this port**: (a) a close error while releasing a held page is **surfaced**,
not swallowed — the `Pages` view's `#close` and its scoped block form both propagate; and (c) when **both**
held pages fail to close, the first failure propagates with the second attached through
`Dexpace.attach_suppressed`. Both are implemented and both are tested. `PAGE-15`'s conformance clause — "make
a held page's close throw and consume via a short-circuiting terminal inside a scoped close; assert the
wrapped close error surfaces" — is written as **assert the close error surfaces**, with the word "wrapped"
dropped and `P7-1` cited on the test's header comment.

### The half that is not vacuous, and is the sharper finding

The same measurement produced this, which is the reason `R8` was worth running rather than reasoning through:

> A bare `ensure` whose close raises **while a consumer exception is already in flight replaces the consumer's
> exception as the primary.** Ruby sets `#cause` to the in-flight error, so nothing is lost — but the primary
> is the close error, and `PAGE-13`'s conformance clause asserts the exact opposite: "make both parse and
> close throw; assert the **parse** error propagates with the close error suppressed."

Measured: `scoped { raise ArgumentError }` where the `ensure` raises `Boom` produces `Boom` with
`cause: ArgumentError`. So **`ensure` alone is not an implementation of `PAGE-13`, `PAGE-15` or `PAGE-32`** —
it is an implementation of their inverse, and it is the shape a competent Ruby author writes by default. The
rule this sub-phase adopts, stated once and cited at every site:

```ruby
def scoped
  yield
ensure
  primary = $!                    # read BEFORE anything in this block can raise
  begin
    release_held_pages!
  rescue ::StandardError => close_error
    raise if primary.nil?         # PAGE-15: surface it
    Dexpace.attach_suppressed(primary, close_error)   # PAGE-13/PAGE-32: primary stays primary
  end
end
```

Measured on all four paths: with a consumer failure in flight the primary stays `ArgumentError` and the close
error is attached; with none in flight — including under a `break`-driven short circuit, where `$!` is `nil` —
the close error propagates. `PAGE-26`'s and `PAGE-32`'s consumer-already-failed branch is the same shape with
`Dexpace.close_quietly` in place of the attach, because those two require the close error **swallowed** rather
than attached.

**This is `7c`'s single largest correctness risk and it is invisible to a passing test suite that does not
look for it**, because the happy path and the close-fails-alone path both behave identically under either
shape. Two dedicated tests exist for it, one per view, and they are named in the testing strategy.

---

## `R9` — the executor mode against a library that owns no thread pool

**Decision, in four parts: (1) `7c` never calls `Dexpace::Async.delay`, so `P5-9` is unreachable from this
sub-phase; (2) the default mode needs no scheduler, no executor and no thread, and is fully functional;
(3) `PAGE-29`'s executor is a caller-supplied `#post`-shaped duck type validated by `respond_to?`, and core
spawns nothing; (4) `PAGE-31`'s trampoline is required by the *default* mode, not by the executor mode, which
is the opposite of the intuition.**

### (1) There is no wait in this subsystem

The charter frames `R9` against 5a's `Async.delay`, which raises `Dexpace::SeamError` when `Fiber.scheduler`
is `nil`, and notes that `6a` faces the same question under its own `R2`. **It does not fire here.** All nine
async IDs were read for a delay clause and none has one: `PAGE-25` drives fetch/parse/delivery/re-arm;
`PAGE-26` is cancellation granularity; `PAGE-27` is close-exactly-once; `PAGE-28` is failure surfacing;
`PAGE-29` is delivery ordering and the executor; `PAGE-30` is executor rejection; `PAGE-31` is the
trampoline; `PAGE-32` is the drain-path close; `PAGE-33` is documentation. **Pagination has no backoff, no
pacing and no inter-page wait.** That is the substantive difference between `PAGE-31`'s pump and `RETRY-30`'s:
the retry pump exists to *wait* between attempts and the paginator's pump exists only to *not recurse*. `7c`
requires nothing of `Fiber.scheduler` and its whole async surface works with none registered.

### (2) The default mode is a callback pump, and it owns nothing

`Dexpace::Page::AsyncPaginator#walk(consumer)` returns a `Dexpace::Async::Future`. The driver dispatches
`transport.call(request, options, cancellation)`, receives a `Future`, and attaches `#on_settle`. Phase 2
fixes that the callback runs "on the settling thread-or-fiber" — so **whoever settles the transport future
drives the next page**, which is `PAGE-29`'s stated default in as many words ("By default the consumer runs
inline on the page-completion thread"). No thread is created, no pool is held, and `Fiber.scheduler` is never
consulted. The engine is a state machine plus a re-arm flag.

### (3) The executor is the caller's, and its duck type is one method

`PAGE-29`'s second sentence asks for "a mode running the driver — and therefore every consumer invocation —
on a **caller-supplied** executor". The adjective is the whole answer, and it is the same one `6c` reached
under its own `R12` for `AUTH-37`'s "off-thread background refresh": **the SDK owns no thread pool;
off-thread-ness is a property of the caller's own object** (`docs/work/mvp/phase6/phase6c/2026-09-09-phase6c-authentication-design.md`,
`P6-5`). `7c` states the same conclusion for the same reason, from the other subsystem.

The duck type is **one method**: `#post { … }`, fire-and-forget, returning anything. It is documented as an
RBS `interface _Executor` and validated at construction with `respond_to?(:post)` — 3b's `_ResponseHandler`
precedent exactly, "validated by `respond_to?` and never by a nominal test". Three alternatives were rejected:

- **The `SEAM-16` async seam.** It is a *transport* pivot — `#call(request, options, cancellation) -> Future`
  — and has no submit side at all. `PAGE-29` needs "run this block somewhere else", which a `Future` cannot
  express.
- **`Dexpace::Async::Completer` as a submit surface.** Same objection; a completer is written to, not
  submitted to.
- **A `Dexpace::Async::Thread` pool in core.** That is phase 8's gem and `SEAM-1` forbids core from owning
  one. `7c` ships a test double (`test/support/probe_executor.rb`) with an inline mode, a deferred mode and a
  rejecting mode, and phase 8's `dexpace-async-thread` is the first real implementation.

**With no executor supplied, the mode is the default mode.** There is no degraded third state, no
`SeamError`, and nothing that raises for want of a runtime facility — which is the concrete answer to the
charter's "states what happens with no scheduler and no executor": **the engine works, on the settling
thread, exactly as `PAGE-29` specifies as its default.**

`PAGE-30`'s rejection is `#post` raising. Every `#post` call site is wrapped; the raised error becomes the
walk's failure through `Completer#fail`, and any staged page is closed on the way out. In Ruby a rejecting
executor has no other vocabulary — there is no `RejectedExecutionException` to catch by type — so the driver
catches `StandardError` from `#post` and `rescue ::Exception` re-raises unchanged, per `RECOV-2`'s
fatal-family split.

### (4) The trampoline is the default mode's problem

Measured (verified fact 2): recursive future composition over synchronously-completed futures raises
`SystemStackError` at roughly 11,000 frames on 3.4.10; a `while` pump completes 200,000 synchronous pages with
no stack growth. **The recursion arises precisely because `#on_settle` on an already-settled future invokes
the block immediately, on the calling fiber** — phase 2's stated behaviour, and the right behaviour, since a
late registration must never be lost. An executor mode incidentally breaks the stack by hopping threads; the
inline default does not. So `PAGE-31`'s conformance clause — "drive thousands of synchronously-completed pages
through **both** inline and executor paths" — is testing the inline path for the property and the executor
path for the absence of a regression, and `7c`'s pump is a `while` loop with a re-arm flag, per the
specification's own latitude ("A port on a runtime without deep-recursion risk MAY satisfy the intent with its
native loop model but MUST NOT recurse per page").

**Concurrency of the pump.** With an executor, the pump body may run on a pool thread while a transport
callback lands on another. `PAGE-29`'s "the consumer MUST NOT be invoked concurrently" holds structurally:
there is **at most one in-flight exchange per walk** and each settlement re-arms exactly one continuation, so
two continuations never exist at once. The re-arm flag is nevertheless read and written from two threads, so
it is guarded by a `Thread::Mutex` **held across the flag flip only** — never across a dispatch, a parse, a
consumer call or a close. That is the repository rule (`Thread::Mutex` is per-fiber-owned and non-reentrant),
and it is stated here so the plan's task cannot widen the critical section by accident.

---

## `R10` — `PAGE-6`'s zero-exchange guarantee across two engines

**Decision: two assertions, written separately, because `PAGE-6` states two different guarantees and a
uniform assertion asserts something the requirement does not say.**

`PAGE-6`'s own text carves the async engine out: "For the blocking engine, constructing the paginator,
obtaining the iterable/stream, and obtaining the item iterator MUST trigger zero exchanges … **The
non-blocking engine has no separate lazy 'obtain' step — invoking a walk method is itself the consumption
trigger and begins fetching immediately** — but the one-exchange-per-page-consumed guarantee still holds."

- **Sync assertion.** With a counting transport: `Paginator.build(…)` → 0 exchanges; `paginator.items` → 0;
  `paginator.items.to_enum(:each)` → 0; `paginator.pages` → 0. Then one exchange per page consumed.
- **Async assertion.** `AsyncPaginator.build(…)` → 0 exchanges (construction is still inert; the requirement
  carves out the *walk method*, not the constructor). `async.walk(consumer)` → **1** exchange immediately, and
  one per page thereafter.

Both are in the checklist as `PAGE-6`'s row with the two sub-assertions named. The row that would be wrong is
a single "zero exchanges until first probe" assertion applied to both.

---

## `R11` — spec-forced boundary 5's audit, and which side `7c` is on

**Decision: `7c` states both branches and its plan carries both. If `7c` lands first it builds the audit,
generalised over a path list, with `lib/dexpace/page/**` as its first entry and the extension point
documented. If `7b` has already built it, `7c` adds one path entry and one negative fixture, and builds
nothing.**

The charter assigns the audit to whichever of `7b` and `7c` lands first, with the other adding one path in a
one-line diff, and requires both designs to say which side they are on so the audit is neither written twice
nor left to each assuming the other wrote it. **`7c` cannot know which order runs and does not coordinate**;
what it can do is make the two branches cost the same to execute and be visibly exclusive.

**The audit, as `7c` would build it** (`tasks/gates.rake`, `gates:serde_isolation`, blocking):

- Its input is a **list of `[glob, label, requirement]` triples**, not a single path, so the second sub-phase's
  contribution is one array element. `7c`'s entry is
  `["gems/dexpace-core/lib/dexpace/page/**/*.rb", "pagination", "docs/product-spec/12-pagination.md:3 (chapter intro; no requirement ID — phase 7 segmentation design, spec-forced boundary 5)"]`.
  `7b`'s is the same shape over `lib/dexpace/sse/**/*.rb` citing `SSE-37`.
- For each guarded file it scans for **(a)** any `require`/`require_relative` whose argument matches
  `dexpace/serde` or `json`, and **(b)** any occurrence of the constant tokens `Dexpace::Serde`, a bare
  `Serde`, or a bare `JSON`. A hit fails the build with the label and the citation attached, so the failure
  message says *why* rather than "not allowed".
- **It is labelled an extension in its own source comment**, verbatim: the `sse/` entry is `SSE-37`'s
  requirement and the `page/` entry is a segmentation-design boundary with **no requirement behind it**. The
  charter's instruction — "stated as an extension rather than smuggled in as a MUST" — is discharged in the
  code, not only in a document.
- **`SSE-37`'s two extra prohibitions are not in this gate.** No done-sentinel string and no error-envelope
  recognition are `7b`'s, are SSE-specific, and are asserted by `7b`'s tests. `7c` does not generalise them,
  because generalising a rule to a subsystem it was not written for is how an audit acquires an exception.
- **Negative fixtures.** Whichever sub-phase builds the gate ships one fixture per guarded path that the gate
  must reject (a scratch file naming `Dexpace::Serde`) plus one it must accept, following phase 0's
  `two_third_party` negative-fixture precedent.

**If `7b` landed first**, `7c`'s task is: add the one triple, add the `page/` negative fixture, run the gate
red then green, and delete nothing. The plan's Task 1 begins by looking for `gates:serde_isolation` and
branching on its presence; both branches produce the same end state, and neither blocks.

**Neither branch is a dependency.** A `7c` that runs with no audit in place still ships correct code — the
audit is a gate over a property the design already holds — and the extension arrives with the second
sub-phase.

---

## `PAGE-35`: vacuous by construction, not declined

**`PAGE-35` (SHOULD)**: "If a mutable paging-options object is offered to fetchers, the *same* instance SHOULD
be threaded through every fetcher call so a custom retriever can stash cursor/state between pages, and this
cross-call mutation visibility SHOULD be documented; such an options object is single-consumer and need not be
thread-safe."

**The antecedent is declined; the requirement is not.** The port offers `Dexpace::RequestOptions` — a frozen
`Data` with `Model.own`'d collections and a canonical frozen `EMPTY` — and offers no mutable options object
anywhere. Design §12's `PAGE` row is the authority and says exactly this: "`PAGE-35` (SHOULD) is conditional
on offering a mutable paging-options object; the port offers an immutable value instead, so the clause is
vacuous rather than declined" (`docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:36`). **A ⏳ or
🚫 row would be wrong in both directions**: ⏳ implies a pick-up condition that cannot arise without reversing
a domain-model decision that predates this phase, and 🚫 implies a capability withheld.

**Three things the row must nevertheless state**, so "vacuous" is a finding rather than a dismissal:

1. **The same `RequestOptions` instance *is* threaded through every fetcher call**, by identity — the
   `Fetchers` front-end holds one frozen instance and passes that object, never a copy. So `PAGE-35`'s first
   clause is satisfied literally; it is only the *mutation visibility* the immutability makes unobservable.
   A test asserts `assert_same` across both fetcher calls, which is the closest observable form of the
   requirement's own conformance clause ("assert both fetchers receive the identical options instance").
2. **The SHOULD's purpose is served, by the caller's own closure.** A fetcher that needs to stash cursor state
   between pages is a Ruby callable, and a callable carries its own binding. The requirement's motivation —
   "so a custom retriever can stash cursor/state between pages" — needs no library facility here.
3. **`PAGE-34`'s continuation token is the library's own answer to the same need**, and it is a MUST that
   `7c` implements: the next-page fetcher is keyed off the previous page's next link, falling back to its
   continuation token. So a retriever that wants per-page state has a first-class channel that does not
   require a mutable options bag.

---

## Module layout

Every file `7c` creates, under `gems/dexpace-core/`. `sig/` mirrors `lib/` one file per file and ships inside
the gem; `test/` mirrors `lib/` one file per file and does not ship. `private_constant`s get neither, per
phase 4's precedent.

```
lib/dexpace/page.rb                          Dexpace::Page                    (the page value; Closeable)
lib/dexpace/page/info.rb                     Dexpace::Page::Info              (PAGE-4's PageInfo)
lib/dexpace/page/query_rewriter.rb           Dexpace::Page::QueryRewriter     (PAGE-21..PAGE-24)
lib/dexpace/page/link_header.rb              Dexpace::Page::LinkHeader        (PAGE-18, PAGE-20)
lib/dexpace/page/cursor_strategy.rb          Dexpace::Page::CursorStrategy    (PAGE-16)
lib/dexpace/page/page_number_strategy.rb     Dexpace::Page::PageNumberStrategy (PAGE-17)
lib/dexpace/page/link_strategy.rb            Dexpace::Page::LinkStrategy      (PAGE-18, PAGE-19, PAGE-20)
lib/dexpace/page/walk.rb                     Dexpace::Page::Walk              (the lifetime owner; Closeable)
lib/dexpace/page/items.rb                    Dexpace::Page::Items             (PAGE-1, PAGE-8, PAGE-11)
lib/dexpace/page/pages.rb                    Dexpace::Page::Pages             (PAGE-1, PAGE-12, PAGE-14, PAGE-15)
lib/dexpace/page/paginator.rb                Dexpace::Page::Paginator         (PAGE-6..PAGE-10, PAGE-36)
lib/dexpace/page/async_paginator.rb          Dexpace::Page::AsyncPaginator    (PAGE-25..PAGE-33)
lib/dexpace/page/fetchers.rb                 Dexpace::Page::Fetchers          (PAGE-34, PAGE-35)

lib/dexpace/http/url.rb                      MODIFIED: URL.resolve added (P7-3, PAGE-19)
lib/dexpace.rb                               MODIFIED: the thirteen requires

sig/dexpace/page/strategy.rbs                NEW, sig/-only: interface _Strategy, _Extractor, _Executor
test/support/counting_transport.rb           a scriptable, exchange-counting sync + async transport double
test/support/probe_executor.rb               inline / deferred / rejecting executor double (PAGE-29, PAGE-30)
test/support/closing_probe.rb                a Response double counting #close and refusing a second read
tasks/gates.rake                             MODIFIED or NEW: gates:serde_isolation (R11)
```

Thirteen new `lib/` files, thirteen `sig/` mirrors, thirteen `test/` mirrors, one `sig/`-only interface file
with no `lib/` counterpart, two modified existing files, three new test-support doubles, and one gate.

**`Dexpace::Page` is a class *and* the namespace, and that is a decision rather than a default.** Design §7.1
names exactly one Ruby identifier for this subsystem — `Dexpace::Page`, in the shorthand
"`Dexpace::Page.each { }`" — and appendix A's glossary calls the value "a Page". Nesting the rest inside it
keeps `lib/dexpace/page/**` as the audited glob boundary 5 fixes, and keeps the directory-to-namespace
correspondence phases 6a (`Dexpace::Resilience::*`) and 6c (`Dexpace::Auth::*`) established. **Phase 3b's
`OI-3`/`P3-7` shadowing lesson is applied rather than ignored**: the nested names are `Info`,
`QueryRewriter`, `LinkHeader`, `CursorStrategy`, `PageNumberStrategy`, `LinkStrategy`, `Walk`, `Items`,
`Pages`, `Paginator`, `AsyncPaginator` and `Fetchers`, and **none shadows a Ruby core constant or a
`Dexpace::` one**; the plan's final task runs an explicit shadowing audit over the list rather than trusting
this sentence. The names 3b rejected — `File`, `Buffer`, `Response` — have no counterpart here. Recorded as
`P7-2`.

**What design §7.1's `Dexpace::Page.each { }` shorthand resolves to.** It is the design's illustration of the
block form, and it names no receiver precisely. This port supplies `Dexpace::Page::Items#each` and
`Dexpace::Page::Pages#each` as the block forms, plus `Paginator#each_item { }` and `#each_page { }` as the
scoped openers that close the walk in an `ensure`. Stated explicitly, so a reader comparing the design to the
code is not left to guess whether the shorthand was implemented or dropped.

---

## The object model `7c` ships

### `Dexpace::Page` — the page value, and why it is not a `Data`

```
Dexpace::Page.build(response:, items:, next_link: nil, continuation_token: nil)
  #items                  frozen Array, never nil, MAY be empty          (PAGE-2)
  #status  #headers  #request   delegated to the held Response           (PAGE-2)
  #next_link  #continuation_token                                        (PAGE-34)
  #response               the live response, invalid after close
  #close  #closed?  #owned?     from Dexpace::Closeable                  (PAGE-3, PAGE-27)
```

**A plain class including `Dexpace::Closeable`, not a `Data`.** Phase 3b established the reason in the
neighbouring case: "A `Data` instance is frozen and **cannot hold a latch**", which is why `Response#close` is
a pure forward with idempotence living in `ResponseBody`
(`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md:911`). `PAGE-3` requires a page to
be "a closeable resource owning exactly one underlying response" and `PAGE-27` requires "no double-close"
**on whichever path consumes it** — four paths, in the async engine alone. Relying on the response's body to
supply the latch is not available: `Response#body` may be `nil` (close is a no-op), may be a `BufferBody`
(default `#close` is a no-op by `BODY-30`'s requirement), and is only a latching `ResponseBody` in the
transport case. **So the page carries its own latch**, `initialize_closeable(owned: true)`, with
`#release` calling `@response.close`. That makes `PAGE-27`'s exactly-once a property of the page rather than a
property of what the transport happened to put in the body — which is the only version of it a test can
assert across all four paths.

**`PAGE-2` is then free**: `items` is a frozen `Array` duplicated at construction (`Model.own`'s shape,
applied by hand since this is not a `Data`), and `status`/`headers`/`request` are read off the frozen
`Response` `Data`, which close does not touch. A test closes a page and re-reads all four.

**`PAGE-3`'s "a component that hands a caller a live page MUST NOT itself close the response — ownership
transfers to the page"** is the fetcher front-end's rule and is asserted there.

### `Dexpace::Page::Info` — `PAGE-4`'s PageInfo

`Data.define(:items, :next_request, :next_link, :continuation_token)`, including `Dexpace::Model`,
`private_class_method :new`, `.build` validating that `items` is a non-nil `Array` (`Model.own`'d and frozen)
and that `next_request` is `nil` or a `Dexpace::Request`. **`next_request == nil` is the single, exclusive
end-of-stream signal**, and there is no second one: `Info` has no `terminal?` flag, no sentinel and no
exception path, which is `PAGE-4`'s prohibition made structural. `.terminal(items: [])` is a named factory
for the common case, so a strategy author never writes `next_request: nil` by hand and never mistakes an
empty items list for termination — `PAGE-4`'s "An empty items list paired with a non-null next-request is a
valid non-terminal page" is the case that trips people, and the factory names the other one.

### The three duck types, declared in RBS and validated by `respond_to?`

```rbs
interface _Strategy
  def parse: (Dexpace::Response response, Dexpace::Request template) -> Dexpace::Page::Info
end

interface _Extractor
  def call: (Dexpace::Response response) -> Array[untyped]
end

interface _Executor
  def post: () { () -> void } -> void
end
```

No `.conforms?` predicate and no `include`-able module: phase 3b's `_ResponseHandler` precedent is exactly
this shape — an RBS interface, `respond_to?` at construction, never a nominal test — and
`api-design/b0e18938`'s minimal-surface rule argues against a fourth public constant per duck type.

### `Dexpace::Page::QueryRewriter` — `PAGE-21`–`PAGE-24`

A module of pure functions over the **raw query substring**, never over a parsed model.

| Function | Requirement |
|---|---|
| `.get(query, name)` | `PAGE-22`'s reading half: first match wins, a value-less flag reads as `""`, decoding through `Dexpace::PercentEncoding.decode_component` so `+` reads back as `+` and `%20` as a space |
| `.set(query, name, value)` | `PAGE-23`: replace the first occurrence in place, drop further duplicates, append if absent, **remove entirely when `value` is `nil`**, order otherwise preserved. The new value encodes through `PercentEncoding.encode_component` (`PAGE-22`) |
| `.rewrite_url(uri, name, value)` | `PAGE-24`: `uri.dup`, splice `query`, assign. Every non-query component survives because none is touched |

**`PAGE-21`'s byte-for-byte preservation is the whole design of this module.** It tokenises on `&` and on the
**first** `=` per segment, copies every untargeted segment as the exact bytes it found, and re-encodes only
the targeted parameter's name and value. It never round-trips the whole query. `Dexpace::Query` and
`Query::Builder` — phase 1's, shipped, correct for what they are — are **deliberately not used**, because
`Query.parse(q).encode` re-encodes every parameter and would rewrite `filter=a:b` to `filter=a%3Ab`, which is
the canonicalisation `PAGE-21` forbids in as many words.

**Three measured facts hold this module up** (verified facts 3–5):

- `URI.decode_www_form("q=a+b")` → `[["q", "a b"]]` and `URI.encode_www_form_component("a b")` → `"a+b"`.
  Both are the exact inverse of `PAGE-22` in both directions, which is why the entire `www_form`/`CGI`
  family is rejected rather than merely not chosen.
- **`URI::Generic#query=` is byte-transparent for every query string `URI::RFC3986_PARSER.parse` can
  produce.** A differential probe over every printable ASCII byte found **zero** characters where
  `parse(s).query != (dup.query = that_same_string)`. The canonicalisation people fear here happens at
  **parse** time — a space, `"`, `'`, `<`, `>` and `` ` `` are percent-encoded on the way in — and a
  `Request#url` has already been through `URL.parse!`, so `PAGE-21`'s "byte-for-byte" is measured against
  `uri.query`, which round-trips exactly. Without this measurement the module would need a hand-rolled URL
  renderer; with it, `query=` is safe and `PAGE-24` is free.
- `uri.query = nil` removes the query entirely (`https://x/a`); `uri.query = ""` leaves a dangling `?`
  (`https://x/a?`). **`.set` therefore normalises an empty spliced query to `nil`**, so removing the only
  parameter yields a URL with no `?`. `PAGE-23`'s own example removes one of two and does not settle the
  degenerate case; recorded as `P7-4` because it is a choice the requirement does not make.

**One residue, stated honestly rather than papered over.** If the caller hands `URL.parse!` a URL containing
a bare `'`, phase 1's parse turns it into `%27` before `7c` ever sees it. That is `HTTP-46`/`HTTP-47`'s
normalisation, not the rewriter's: `PAGE-21` governs what the *rewriter* changes, and the rewriter changes
nothing. A test asserts the rewriter's own byte-identity against the executed request's query, which is the
object the requirement names.

### `Dexpace::Page::LinkHeader` — `PAGE-18`, `PAGE-20`

A `private_constant` module holding a **character-level state machine**, not a regexp. Spec-forced boundary 22
is the reason and it is not a style preference: RFC 8288's link-value grammar is not regular — commas inside
angle brackets and inside quoted parameter values must not split link-values, and quoted-pair escapes (`\"`)
must be honoured — so a pattern that appeared to work would fail on exactly the inputs `PAGE-18`'s conformance
clause names. The constraint "regexp timeouts are per-pattern, never `Regexp.timeout`" is discharged here by
**not writing the regexp**, which is the same route design §6.3 takes for `WWW-Authenticate`.

States: `expect_lt` → `in_uri` (until `>`) → `after_uri` → `in_params`, with `in_quoted` and `in_escape`
nested inside `in_params`. `.next_target(values)` joins the header instances with `", "` (`PAGE-20`'s
normalisation by concatenation), scans link-values in order, and returns the **first** whose `rel` parameter
contains the token `next` — split on space and tab, compared with `downcase` and no argument
(`Dexpace/NoLocaleCaseFold`), with the value accepted quoted or unquoted. An empty header set, an absent
header, and a value with no `rel=next` segment all return `nil`.

### The three built-in strategies

All three are frozen `Data` types including `Dexpace::Model`, with `private_class_method :new` and a
validating `.build`. **No instance state, so `PAGE-5`'s "immutable and safe to share concurrently" is
structural rather than promised**, and `PAGE-8`'s "safe to share" follows for the engine that holds one.

- **`CursorStrategy.build(extract:, parameter: "cursor")`** — `PAGE-16`. Calls `extract.call(response)` once,
  takes `[items, cursor]`, treats **`nil` or `""`** as end-of-stream, and otherwise derives the next request
  by `QueryRewriter.rewrite_url(template.url, parameter, cursor)` and `template.with(url: …)`. The parameter
  name is configurable and defaults to `cursor`.
- **`PageNumberStrategy.build(extract_items:, parameter: "page", start: 1)`** — `PAGE-17`. **Checks the empty
  items list first** and terminates on it, defensively, before computing anything. Otherwise it reads the
  current page from `QueryRewriter.get(response.request.url.query, parameter)` — the **originating (executed)
  request**, which in this port is `response.request`, not the template — falling back to `start` when the
  parameter is absent, empty, or non-numeric (screened with an anchored `\A\d+\z` pattern carrying its own
  `Regexp.new(source, timeout:)`), and sets the next page to current + 1. `start` defaults to 1 and 0 is
  permitted, for 0-based servers.
- **`LinkStrategy.build(extract_items:, header: "Link")`** — `PAGE-18`, `PAGE-19`, `PAGE-20`. Reads
  `response.headers[header]`, hands the array to `LinkHeader.next_target`, and resolves the result.

**`PAGE-19`'s reference resolution, and the two measured facts behind it.** The base is
`response.request.url` — the request the transport was handed, which after a redirect chain is the *final*
request, so it is the "originating page's response URL" the requirement names. Resolution goes through
`Dexpace::URL.resolve(base, reference)`, a new module function that wraps
`URI::RFC3986_PARSER.join(base, reference)` (`P7-3`). Measured: `join` on base
`https://api.example.com/repo/issues?page=1` with reference `?page=2` yields
`https://api.example.com/repo/issues?page=2` — the **full path preserved**, which is `PAGE-19`'s explicit
RFC 3986 requirement and not the RFC 2396 behaviour it forbids. And measured: `join` raises
`URI::InvalidURIError` on `"not a url"`, on `"http://[bad"` and on a whitespace-only reference, so
`PAGE-19`'s "A target that cannot resolve into a valid URL MUST be treated as end-of-stream, not an error" is
a `rescue` returning `nil`, and the rescued class is named.

**One trap `PAGE-19` does not name and this design closes.** Measured: `join(base, "")` and `join(base, "//")`
return the **base unchanged** — they resolve successfully. A server sending `<>; rel=next` would therefore
produce a next request identical to the current one and loop until the page cap. `PAGE-34` states the rule for
the fetcher front-end explicitly ("An empty/blank next link … MUST end the stream"), and `7c` applies the same
rule to the Link strategy: **a blank or whitespace-only target is end-of-stream before resolution is
attempted.** Recorded as `P7-5`, because `PAGE-18`'s "Absence of a Link header or a rel=next segment" does not
literally cover present-but-blank.

### `Dexpace::Page::Walk` — the lifetime owner, and the whole of the `Enumerator` answer

**This is the object the phase-3 rule exists to force, and it is the reason `7c` has a design at all.**

```
Dexpace::Page::Walk           # per-iteration; NOT shareable; includes Dexpace::Closeable
  @paginator                  frozen configuration, shared
  @next_request               the request for the page not yet fetched, or nil
  @current                    the page handed to the consumer, or nil
  @buffered                   PAGE-12's one-slot look-ahead, or nil
  @exchanges                  Integer, for PAGE-9's cap
  @exhausted                  Boolean latch, for PAGE-7's idempotent probes
  #fetch_next_page  -> Dexpace::Page | nil     the ONE drive routine
  #close                                       from Closeable; releases @current and @buffered
```

**Neither `@current` nor `@buffered` ever lives inside an `Enumerator` block or inside a `#each` method's
local scope.** They are instance variables on an object the caller can reach and `#close`. That is the rule
from `pagination/318ae05d` and `pagination/b2a85752` applied literally, and `Dexpace::Closeable` is the latch
phase 2 built for it. The rule's consequences are stated so no task can quietly reverse one:

- **No `block_given?` guard anywhere in `7c`.** It is measurably true inside `#each` when reached through
  `to_enum(:each)` and `#next`, so it forbids nothing. Boundary 14 says so and the plan's lint pass greps for
  it.
- **`Walk#release`** (private, called by the latch) closes `@current` and `@buffered` under `R8`'s
  first-primary/second-suppressed discipline: the first close error is held, the second is attached to it via
  `Dexpace.attach_suppressed`, and the first is re-raised with `raise error, cause: nil`. That is `PAGE-15`'s
  third clause, and `PAGE-12`'s "Explicit close MUST release **both** the currently-held page and any buffered
  page".
- **The block forms close in an `ensure` that reads `$!` first**, per `R8`. `Paginator#each_item { }` and
  `#each_page { }` are the scoped openers, and their YARD tells consumers to use them — `PAGE-12`'s
  "Consumers MUST be told to wrap the view in a scoped/auto-close construct" is a documentation clause and the
  YARD is where it is discharged.
- **External iteration's residue is stated in the YARD of both `#each`-without-a-block forms**, naming
  `#close` as the remedy and naming the note. It is not hidden and it is not pretended away — the same honesty
  phase 3b applied to `Dexpace::FileBody`.

**`Walk#fetch_next_page` is the one internal drive routine both views share** (`pagination/71aed9c1`):

1. return `nil` if `@exhausted` or `@next_request.nil?` — **`PAGE-7`'s idempotent end-of-stream probe, with no
   exchange**;
2. return `nil` and latch `@exhausted` if `@exchanges >= @paginator.cap` — **`PAGE-9`**, checked *before* the
   exchange, so a cap of `N` produces exactly `N` exchanges;
3. `response = transport.call(@next_request, options, cancellation)`; `@exchanges += 1` — **`PAGE-36`**'s
   overrides are the paginator's frozen `options`, passed on **every** call, which is what makes the
   requirement structural rather than remembered;
4. `info = strategy.parse(response, template)` inside a `rescue ::StandardError` that closes `response`
   inline and re-raises with the close error attached as suppressed — **`PAGE-13`**, and the page is never
   constructed so nothing else would close it;
5. build the `Page`, set `@next_request = info.next_request`, latch `@exhausted` when it is `nil`, return the
   page.

`rescue ::Exception` is **not** written: `RECOV-2`'s fatal-family split says a non-`StandardError` is
surfaced unchanged with no trail attached, and phase 4b already implements that rule.

### `Dexpace::Page::Items` — `PAGE-1`, `PAGE-8`, `PAGE-11`

`Items#each` drives a **fresh `Walk` per call**, which is `PAGE-8`'s "Each independent iteration MUST restart
from the initial request with its own fresh state" for the item view. Per page: fetch → the page's items are
already a frozen copy → **close the page** → yield each item. So **at every yield point the walk holds
nothing open.**

**That is not an implementation convenience; it is what makes the item view safe on a host where `ensure` does
not run.** `PAGE-11`'s eager-close means the only suspension points an external consumer can abandon the walk
at are points where no response is live. The residue of `pagination/b2a85752` on this view is therefore
**zero**, and that is worth stating because it is the one place in this subsystem where the hard rule costs
nothing. `Items#close` exists anyway, forwarding to the walk, so the two views share one lifetime vocabulary
and a consumer never has to remember which one needs it.

`PAGE-1`'s "items MUST be delivered in server-defined order across page boundaries" is the drive routine's
order, asserted against a three-page fixture.

### `Dexpace::Page::Pages` — `PAGE-1`, `PAGE-12`, `PAGE-14`, `PAGE-15`

`Pages` holds **one** `Walk`, created when the view is created. `#each` latches `@viewed` on first call and
raises `Dexpace::InvalidArgumentError` on a second — **`PAGE-14`**, "re-iteration MUST fail rather than
silently restart". Two separate `paginator.pages` calls give two independent single-use views over two walks,
which is `PAGE-8`'s two-iterations clause; design §7.1 fixes that the fresh-restart-per-iteration is
"deliberately not offered by the page view", and the two statements are compatible exactly this way.

The advance sequence is `PAGE-12`'s, verbatim: close the previous page as the consumer advances, close the
last page at exhaustion, and buffer the fetched-but-undelivered page in `Walk#@buffered` — **storage the walk
owns**, per `pagination/9bdf90fc` and design §7.1's "**PAGE-12**'s one-slot look-ahead lives on the engine,
not in the enumerator's closure". `#any?`/`#peek`-style emptiness probes fill `@buffered`; `#close` releases
both slots.

### `Dexpace::Page::Paginator` — `PAGE-6`–`PAGE-10`, `PAGE-36`

```
Data.define(:transport, :template, :strategy, :cap, :options)
  .build(transport:, template:, strategy:, cap: Float::INFINITY, options: Dexpace::RequestOptions::EMPTY)
  #items -> Items     #pages -> Pages
  #each_item { }      #each_page { }        the scoped block openers
```

**`PAGE-8`'s "the engine itself MUST hold only immutable configuration and be safe to share" is why this is a
frozen `Data` with no instance state at all.** Every per-walk quantity lives on a `Walk`. Ractor-shareability
is a free side effect of `Data` plus `Model.own` and is **no part of the claim** — `PAGE-8`'s "safe to share"
is about threads, and the runtime floor keeps Ractor out of the supported surface.

**`PAGE-9`'s cap** is validated strictly positive at construction, in the model's `initialize` so `.build`,
`#with` and a forged `send(:new, …)` all meet it. **`PAGE-10`'s "effectively unbounded" default is
`Float::INFINITY`**, which is strictly positive (measured), compares correctly against an `Integer` exchange
count, and is a value rather than a magic sentinel — so the cap check is one expression with no nil branch.
`PAGE-10`'s documentation clause is discharged in `.build`'s YARD, which directs production callers to set a
finite cap; it is **not** a `CFG` key and `7c` adds none.

**`PAGE-6`'s zero-exchange guarantee** is free: `#items` and `#pages` allocate a view, and the view allocates
a `Walk` that has fetched nothing. `R10` states the two assertions.

### `Dexpace::Page::AsyncPaginator` — `PAGE-25`–`PAGE-33`

```
Data.define(:transport, :template, :strategy, :cap, :options, :executor)
  .build(transport:, template:, strategy:, cap: Float::INFINITY,
         options: Dexpace::RequestOptions::EMPTY, executor: nil)
  #walk(consumer, cancellation: nil) -> Dexpace::Async::Future
```

The driver is a `while` pump over a re-arm flag, guarded by a `Thread::Mutex` **held across the flag flip
only** (`R9`). One iteration: dispatch → `#on_settle` → on a response, parse, build the page, deliver each
item to the consumer serially, close the page, re-arm. The eight behaviours, each with its site:

| Requirement | Site |
|---|---|
| `PAGE-25` — no thread blocks per page; cancelling the result future halts the walk and cancels the in-flight transport future | `Completer#on_cancel { in_flight&.cancel(reason) }` plus phase 2's check-after-resume rule before acting on any settlement |
| `PAGE-26` — page-granular: a settled result mid-drain lets the current page finish delivering; a fetched-but-undrained page is dropped **and closed**, close errors **swallowed** | the settled check runs at the page boundary, never inside the drain loop; the drop path is `Dexpace.close_quietly(page)` |
| `PAGE-27` — exactly once on all four paths | the `Page`'s own `Closeable` latch, which is why the page is not a `Data` |
| `PAGE-28` — consumer throw, transport failure, parse failure, null success, **and an eagerly-throwing transport**, each failing the walk with the **original** cause | `transport.call` is wrapped in a `rescue ::StandardError` for the eager-throw clause; `Settlement#error` is passed to `Completer#fail` **unwrapped**, because phase 2's pivot wraps nothing; the null-success branch is the `Settlement` dispatch's explicit `else` |
| `PAGE-29` — serial, ordered delivery; inline by default; executor mode runs the driver | the pump; `executor.nil? ? yield : executor.post { … }` at the one re-dispatch site |
| `PAGE-30` — a rejecting executor fails the walk and closes any staged page | every `#post` call site is wrapped; the raised error becomes the failure and the staged page is closed on the way out |
| `PAGE-31` — iterative, never recursive | the `while` pump, measured against 200,000 synchronous pages |
| `PAGE-32` — the drain-path close happens whether the consumer succeeds or throws; a throwing close is reported through the future on the success path and swallowed if the consumer already failed | `R8`'s `$!`-branching `ensure`, with `close_quietly` on the already-failed branch |

`PAGE-33` is a YARD block on `#walk`, quoting the race and stating the port's behaviour: an already-dispatched
request that completes after the abort **is closed and discarded**, and a response the transport never
delivered because the cancel won the race is the transport's to release. That behaviour has a code site — the
settled-check-then-close path — even though the race itself is not reproducible as a test.

### `Dexpace::Page::Fetchers` — `PAGE-34`, `PAGE-35`

`Fetchers.build(first:, next_page:, options: Dexpace::RequestOptions::EMPTY)` produces an object exposing the
same `#items`/`#pages`/`#each_item`/`#each_page` surface, over a `Walk` whose drive routine calls the two
fetchers instead of a transport and a strategy. `PAGE-34`'s rules, each a branch:

- the first-page fetcher is called **exactly once**, asserted with a call counter;
- subsequent pages key off `previous.next_link`, **falling back to `previous.continuation_token`** when the
  link is absent — next link wins;
- a blank next link with no fallback token, or a `nil` page from either fetcher, ends the stream; a `nil`
  first page yields an **empty** stream, not an error;
- **each fetcher builds a page that owns its response and MUST NOT close it** — ownership transfers to the
  page, and a fetcher that throws *before* building the page remains responsible for that response. The
  second half is a documented obligation on the caller, stated in the YARD, because core cannot reach a
  response a fetcher never handed it. That is `PAGE-3`'s own division of responsibility, restated where it
  bites.

`PAGE-35` is the vacuity argued above; the same frozen `options` instance is threaded through both fetcher
calls and a test asserts `assert_same`.

---

## The engine's lifetime and `#close` story, in one place

Stated as five sentences a reviewer can hold the implementation to.

1. **Every live response in this subsystem is held by a `Dexpace::Page`, and every `Page` holds it behind
   `Dexpace::Closeable`'s latch.** There is no other holder and no second latch.
2. **Every `Page` a walk is holding is held on the `Walk` object as `@current` or `@buffered`, never in an
   `Enumerator` block's closure and never in a `#each` method's locals.** That is `pagination/318ae05d` and
   `pagination/b2a85752` applied literally, and it is the only defence that works — `block_given?` does not,
   measurably.
3. **The item view holds nothing at a yield point**, because `PAGE-11` closes each page before yielding any of
   its items; the page view holds up to two, which `PAGE-12` names and `Walk#release` releases.
4. **Every `ensure` that closes reads `$!` first and branches**, because a bare `ensure` inverts
   `PAGE-13`/`PAGE-32`'s primary-error rule (measured). The two branches are `raise` when nothing is in
   flight and `Dexpace.attach_suppressed` (or `Dexpace.close_quietly`, where the requirement says *swallow*)
   when something is.
5. **The paginator owns no transport.** `PIPE-26`/`PIPE-27` make a built pipeline a transport whose `#close`
   is a no-op, and `PAGE-3`'s ownership transfer is about the response. A paginator that closed its transport
   would break a caller who built one pipeline for a whole client.

---

## The spec-forced boundaries, honoured

The twenty-four boundaries the charter names are not re-argued. The nine that reach `7c` are honoured by name:

4. **The strategy reads the response itself; core supplies no codec-flavoured strategy.** `R7`. No JSON
   strategy, no default codec, no `Serde` reference.
5. **The `SSE-37` audit is extended over `lib/dexpace/page/**`.** `R11`, both branches.
9. **A pipeline is a transport and a paginator wrapping one owns nothing.** `Paginator` takes a `#call`-shaped
   object, declares no `Pipeline` dependency, and never closes it.
11. **The suppressed trail is `Dexpace.attach_suppressed`/`Dexpace.suppressed`, and `7c` writes no second
    one.** The frozen-primary caveat travels with it and is stated in both call sites' YARD.
12. **`SSE-30`'s swallow-versus-propagate split is two call sites into one close-once helper.** `PAGE-26`'s
    and `PAGE-32`'s swallow clauses are `Dexpace.close_quietly` calls; `7c` writes no second quiet-close path.
13. **Every cause walk goes through `Dexpace.each_cause`.** `7c` walks no `#cause` chain, so it calls it
    nowhere; the boundary forbids hand-walking and does not require walking.
14. **Resource acquisition and release never live inside an `Enumerator` block or an ordinary `#each` that
    owns a resource, and no `block_given?` guard is written as a defence.** The `Walk` is the whole answer.
18. **`URI::RFC3986_PARSER` is pinned for every parse and every resolution.** `PAGE-19` goes through
    `Dexpace::URL.resolve`, which is where the pin lives (`P7-3`); `Dexpace/NoUriDefaultParser` is the gate.
19. **`downcase` is called with no arguments.** `PAGE-18`'s `rel` token match is `7c`'s one fold site.
22. **Regexp timeouts are per-pattern.** `PAGE-18`'s grammar is a state machine and the constraint is
    discharged by not writing the pattern; `PAGE-17`'s anchored digit screen carries its own
    `Regexp.new(source, timeout:)`.
23. **`Ractor` is never load-bearing.** `PAGE-2`'s and `PAGE-8`'s immutability come from `Data` plus
    `Dexpace::Model`; shareability is a side effect and no part of any claim.
24. **Phases 1 through 7 test against an in-memory fake transport.** `7c` is the first phase-7 sub-phase with
    a transport-shaped dependency at all, and it uses phase 2's `SEAM-11`/`SEAM-16` fakes plus its own
    counting double. **No `TCPServer` fixture, no socket.**

---

## Cross-cutting constraints that bite `7c` specifically

- **An `Enumerator` abandoned mid-`#next` never runs its `ensure`, and neither does an ordinary `#each`.**
  The constraint this whole sub-phase is downstream of. Answered by the `Walk`, not re-derived.
- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** Two mutexes exist in `7c`'s reach and both are
  held across a flag flip only: `Closeable`'s latch (phase 2's, not `7c`'s) and the async pump's re-arm flag.
  Neither is held across a dispatch, a parse, a consumer call or a close.
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden; deadlines are explicit values.**
  `PAGE-25`'s abort is cooperative — it settles a `Dexpace::Async::Future` and cancels a transport future;
  `PAGE-36`'s per-call overrides are a frozen `RequestOptions` threaded to every exchange. `7c` interrupts
  nothing.
- **`Fiber[:key]` is the diagnostic-context carrier, and it matters directly here.** Measured: `Fiber[]` is
  visible inside an `Enumerator`'s internal fiber and `Thread.current[]` is not. **The internal fiber is
  created at the first pull, not at `Enumerator.new`** — so a correlation value set between constructing a
  view and first driving it *is* seen, and one changed after the first pull is *not*. `7c` writes nothing for
  this; it asserts it, because a lazily-driven paginator is exactly where the snapshot semantics would
  surprise someone, and no `PAGE` ID would catch the regression.
- **Bytes on the wire are `Encoding::BINARY`.** `7c` crosses no decode boundary — it reads no body — but
  `PercentEncoding` reads bytes (`text.b`) and its decoder retags at the end, which is phase 1's contract and
  the reason the rewriter round-trips a value carrying invalid UTF-8 byte-exactly rather than raising.
- **`SEAM-2`: core names no concrete implementation.** `7c` names no transport, no codec and no executor
  implementation. The three duck types are the whole of its coupling.

---

## Verified Ruby facts this document measured

All on **3.4.10** (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`), the only interpreter
installed on the authoring machine — re-checked while writing this document: `mise ls` lists `bun`, `go`,
`node` and `opencode` and no Ruby; `~/.local/share/mise/installs` holds no ruby directory; `~/.rbenv`,
`~/.rvm` and `/opt/rubies` do not exist. **The 3.2.11 and 4.0.6 columns have not been run for any fact
below.** The plan's Task 1 installs both and re-runs all seven before any implementation task begins, which
is phases 3, 4, 5 and 6's precedent.

1. **A close error raised from an `ensure` reaches the caller unwrapped through every terminal shape** —
   `Enumerable#first`, `Enumerator::Lazy#map{}.first(2)`, an explicit `break`, and a plain block. `PAGE-15`'s
   wrapping clause has no antecedent here (`R8`, `P7-1`). **And**: with a consumer exception already in
   flight, a raising `ensure` **replaces** it as the primary (`#cause` is set to the consumer's error), which
   inverts `PAGE-13`'s and `PAGE-32`'s primary-error rule. Reading `$!` at the top of the `ensure` and
   branching restores the required order, measured on both branches including the `break`-driven one where
   `$!` is `nil`.
2. **Recursive future composition over synchronously-completed futures raises `SystemStackError` at roughly
   11,000 frames; a `while` pump completes 200,000 with no stack growth.** `PAGE-31`, and the reason the
   trampoline is the *default* mode's requirement rather than the executor mode's (`R9`).
3. **`URI::Generic#query=` is byte-transparent for every query string `URI::RFC3986_PARSER.parse` can
   produce.** A differential probe over every printable ASCII byte found zero characters where
   `parse(s).query != (dup.query = that_same_string)`; the canonicalisation happens at parse time (space,
   `"`, `'`, `<`, `>`, `` ` ``), and a `Request#url` has already been through it. This is what makes
   `PAGE-21`'s byte-for-byte splice implementable without a hand-rolled URL renderer, and what makes
   `PAGE-24` free: userinfo, an explicit port and a fragment all survive `query=` unchanged, measured.
4. **Ruby's query helpers are the exact inverse of `PAGE-22` in both directions.**
   `URI.decode_www_form("q=a+b")` → `[["q", "a b"]]`; `URI.encode_www_form_component("a b")` → `"a+b"`.
   Measured so `7c` cites a number rather than a recollection (`pagination/86b5a3a3`).
5. **`URI::RFC3986_PARSER.join` gives `PAGE-19`'s RFC 3986 behaviour and raises where `PAGE-19` wants
   end-of-stream.** Base `https://api.example.com/repo/issues?page=1` + `?page=2` →
   `https://api.example.com/repo/issues?page=2` (**path preserved**, not the RFC 2396 behaviour);
   `"not a url"`, `"http://[bad"` and `"   "` raise `URI::InvalidURIError`. **And the trap**: `""` and `"//"`
   resolve *successfully*, to the base itself — which is why a blank target is treated as end-of-stream
   before resolution (`P7-5`).
6. **`uri.query = nil` removes the query; `uri.query = ""` leaves a dangling `?`.** `PAGE-23`'s degenerate
   remove-the-only-parameter case (`P7-4`).
7. **`Fiber[]` is visible inside an `Enumerator`'s internal fiber and `Thread.current[]` is not, and the
   internal fiber is created at the first pull rather than at `Enumerator.new`.** A value set between
   construction and the first pull is seen; a change after the first pull is not.

---

## Testing strategy

Five groups, all against phase 2's in-memory fakes and `7c`'s three doubles. Roadmap cross-cutting constraint
4 is honoured: no socket, no `TCPServer`.

1. **`QueryRewriter` and `LinkHeader` unit tests.** `PAGE-21`'s byte-identity assertion is written as a
   **byte comparison of the untargeted segments**, not as a URL equality — `?flag&filter=a:b&page=1` →
   `?flag&filter=a:b&page=2` with `flag` and `filter` asserted byte-identical, which is the requirement's own
   conformance clause. `PAGE-22`'s three named cases (`q='a b'` → `q=a%20b`; `token='a+b/c='` →
   `token=a%2Bb%2Fc%3D`; `get` of `q=a+b` → `a+b`) are three assertions against phase 1's shipped
   `PercentEncoding`, not against a new codec. `PAGE-18` gets one fixture per named hazard: a quoted comma, a
   comma inside angle brackets, an unquoted `rel`, a multi-token `rel`, a quoted-pair escape, and a mixed
   `rel=prev`/`rel=last` set. `PAGE-24` gets one URL carrying userinfo, an explicit port and a fragment.
2. **Strategy unit tests, against a close-counting, read-counting `Response` double.** `PAGE-5`'s three
   prohibitions are three negative assertions per strategy: zero `#close` calls, zero body reads by the
   strategy itself, and no instance variable on the strategy object. `PAGE-16`/`PAGE-17`/`PAGE-19`'s
   conformance clauses each become their own test, including `PAGE-17`'s garbage-page-value case and
   `PAGE-19`'s unresolvable-target case.
3. **Sync engine integration tests, against the counting transport.** `PAGE-6`'s two assertions (`R10`);
   `PAGE-7`'s repeated-probe idempotence; `PAGE-8`'s two-iterations-two-fetch-sequences; `PAGE-9`'s
   exactly-`N`-then-stop against a server echoing one cursor forever, plus the construction-time rejection of
   a non-positive cap; `PAGE-36`'s override on **every** request, asserted by inspecting each recorded call's
   options rather than only the first.
4. **The lifetime suite, which is this sub-phase's real test surface.** Six tests, and the last two are the
   ones a suite written without `R8` would omit:
   - `PAGE-11`: take one item from a multi-item first page and stop; assert the first page closed and no
     second exchange.
   - `PAGE-12`, shape one: probe for a next page without advancing, then `#close`; assert the prefetched
     page's response closed.
   - `PAGE-12`, shape two: `break` out of a page loop inside `#each_page { }`; assert the held page closed.
   - `PAGE-14`: obtain the page iterator twice; assert the second raises.
   - **`PAGE-15`/`PAGE-13`, the inversion test**: make the consumer raise *and* the page's close raise;
     assert the **consumer's** error is the one that propagates and the close error is in
     `Dexpace.suppressed`. A bare `ensure` passes every other test in this list and fails this one.
   - **`PAGE-15`, both-pages-fail**: make both held pages' closes raise; assert the first propagates with the
     second attached. Written with the word "wrapped" absent and `P7-1` cited in the header comment.
5. **Async engine tests, against the counting transport's async mode and `ProbeExecutor`'s three modes.**
   `PAGE-25`'s cancel-mid-walk (assert the in-flight transport future cancelled and no further dispatch);
   `PAGE-26`'s staged-page drop (assert closed, walk ends cleanly, no masking error); `PAGE-27` across all
   four paths with an instrumented response asserting exactly one close each; `PAGE-28`'s five failure modes
   including the eagerly-throwing transport; `PAGE-29`'s serial ordered delivery plus an executor-mode test
   asserting consumer invocations run on the executor; `PAGE-30`'s reject-the-second-dispatch case;
   `PAGE-31`'s thousands-of-synchronous-pages test through **both** paths; `PAGE-32`'s throwing close on the
   success path (assert the future completes exceptionally rather than hanging — a test with a timeout, since
   "hangs" is the failure mode).

**One property test.** `PAGE-21`'s splice over generated queries: for 128 generated raw query strings mixing
value-less flags, reserved characters, repeated names and percent escapes, `set(q, name, v)` leaves every
segment whose name is not `name` byte-identical, and `get(set(q, name, v), name) == v`.

**One thing deliberately not tested.** `PAGE-33`'s race. It is documented, not observable; the row names the
YARD site and the test suite asserts only the half that *is* observable — that a response arriving after the
walk has settled is closed and discarded.

---

## The interface surface later phases may cite

| Consumer | What it gets, and the obligation |
|---|---|
| **`7a`** | Nothing. `7c` names no `Serde` constant and asks `7a` for none. If `7a` ships first, nothing in `7c` changes |
| **`7b`** | `gates:serde_isolation`, **if `7c` lands first** — a path-list gate `7b` extends with one triple plus its two SSE-specific prohibitions. If `7b` lands first, `7c` adds the one triple instead (`R11`) |
| **Phase 8**, on `TRANSPORT`/`ASYNC` | The transport duck type as `7c` consumes it: `#call(request, options, cancellation)` returning a `Response` or a `Dexpace::Async::Future`, with **`PAGE-36`'s `RequestOptions` passed on every call**. An adapter that ignores per-call options breaks pages 2..N and not page 1, which is the failure mode `PAGE-36` exists for |
| **Phase 8**, on `dexpace-async-thread` | `Dexpace::Page::_Executor` — the one-method `#post { }` duck type `PAGE-29`'s executor mode takes. The first real implementation is phase 8's; `7c` ships only a test double, and core spawns no thread (`R9`) |
| **Phase 8**, on `PAGE-33` | The stated division: a response the transport never delivered because a cancel won the race is **the transport's** to release. `7c` documents it; an adapter has to honour it |
| **Phase 9**, on `XCUT-11` | `Dexpace::Page::Paginator` and `AsyncPaginator` as audited shared-instance state: frozen `Data`, no lock, no per-call state on the instance. `Dexpace::Page::Walk` is the per-call state and the audit target is that nothing else is |
| **Phase 9**, on `XCUT-13`/`XCUT-22` | `Dexpace::Page` as a second consumer of `Dexpace::Closeable`'s ownership-aware latch beyond phase 3's bodies, confirming the contract holds where the resource is a whole `Response` |
| **Phase 9**, on the conformance pass | One vacuity to audit rather than tick — `PAGE-35`, design §12's — and one this sub-phase adds, `PAGE-15`'s wrapping clause (`P7-1`), which §12's `PAGE` row does **not** currently record |
| **`docs/sdk-documentation/`** | The first worked cross-gem example this repository can write: a paginated JSON endpoint needs `dexpace-core`'s paginator and `dexpace-serde-json`'s codec **in the caller's extractor closure**, which is the shape that demonstrates the serde-agnosticism rather than describing it. Not a phase-7 deliverable; recorded so the absence is a decision |

---

## Deviation Ledger

**Numbering, and the collision risk stated rather than discovered.** `7a`, `7b` and `7c` are being written
concurrently under the same phase, and each will start its ledger at `P7-1` unless one has already claimed a
number. No `P7-<n>` exists anywhere in `docs/` as of this writing (verified 2026-09-10), so this ledger starts
at `P7-1`. **A sibling sub-phase design may claim the same numbers**; the collision is resolved at
consolidation into design §10, which assigns final numbers across all three ledgers at once — `6b`'s
precedent, and the failure `6a` and `6c` both walked into by numbering in isolation.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P7-1 | **`PAGE-15`'s wrapping clause is not implemented; no wrapper type ships.** The ID's other two clauses are implemented in full | `PAGE-15`; design §11.15's "clauses with no Ruby manifestation" family | Measured, four terminal shapes: a close error raised from an `ensure` reaches the caller **unwrapped** through `Enumerable#first`, `Enumerator::Lazy#first(2)`, an explicit `break` and a plain block. The clause's antecedent — a terminal that cannot declare the underlying I/O error type — cannot arise in a language with no checked exceptions. A wrapper would be a type with no reachable construction site, one more `NFR-4` lock, and a second thing every caller must `rescue`. §12's `PAGE` row records `PAGE-35`'s vacuity and **not** this one, so the row is owed an addition (filed below) |
| P7-2 | Public constants and methods design §7.1 does not name: `Dexpace::Page` (as a **class and namespace**) with `::Info`, `::QueryRewriter`, `::CursorStrategy`, `::PageNumberStrategy`, `::LinkStrategy`, `::Walk`, `::Items`, `::Pages`, `::Paginator`, `::AsyncPaginator`, `::Fetchers`; every `.build` and `#each`/`#close`/`#each_item`/`#each_page`; the RBS interfaces `_Strategy`, `_Extractor`, `_Executor` | `NFR-4`; `api-design/b0e18938`; phases 3b (`P3-14`), 5a (`P5-1`) and 6a (`P6-1`) precedent | Design §7.1 names one Ruby identifier, `Dexpace::Page`, in a block-form shorthand and describes everything else in prose. `NFR-4` locks a signature, not only a name, so each is listed. **`Dexpace::Page` being a class that is also the namespace** is the one sub-decision needing its own argument: it keeps `lib/dexpace/page/**` as boundary 5's glob, keeps the glossary's noun for the value, and is checked against `OI-3`/`P3-7`'s shadowing hazard by an explicit audit over the twelve nested names rather than by assertion. `Dexpace::Page::LinkHeader` is `private_constant` and carries no `sig/` and no manifest row |
| P7-3 | `Dexpace::URL` gains a third function, `.resolve(base, reference)`, wrapping `URI::RFC3986_PARSER.join` — a widening of phase 1's module rather than a resolution call inside the Link strategy | `PAGE-19`; `HTTP-46`/`HTTP-47`; phase 0's `Dexpace/NoUriDefaultParser`; `api-design/1d9e6e0b` | `PAGE-19` needs *resolution*, and `URL.parse!` cannot do it — it rejects a non-absolute URI, which every relative `rel=next` target is. The cop bans `URI.join`, so the call must be `URI::RFC3986_PARSER.join`, and the design's rule is that the pin lives in one place. Putting it in `URL` beside `.parse!` keeps that true; putting it in the strategy would make `lib/dexpace/page/` the second file in core that knows which parser is pinned. Adding a module function widens and prejudices no existing signature |
| P7-4 | `QueryRewriter.set` normalises an empty spliced query to `nil`, so removing the only parameter yields a URL with **no** `?` rather than a dangling one | `PAGE-23`; `HTTP-29`'s "returns `""` when empty" | Measured: `uri.query = nil` gives `https://x/a` and `uri.query = ""` gives `https://x/a?`. `PAGE-23`'s own example removes one of two parameters and does not settle the degenerate case. A dangling `?` is a different URL on the wire, and a next-page request that differs from the caller's template by a stray `?` is a difference `PAGE-24`'s "only the query may change" did not license |
| P7-5 | A blank or whitespace-only `rel=next` target is treated as **end-of-stream before resolution is attempted**, rather than resolved | `PAGE-18`, `PAGE-19`; `PAGE-34`'s explicit rule for the fetcher front-end | Measured: `URI::RFC3986_PARSER.join(base, "")` and `join(base, "//")` **succeed**, returning the base unchanged — so `<>; rel=next` produces a next request identical to the current one and loops until the page cap. `PAGE-18`'s "Absence of a Link header or a rel=next segment" does not literally cover present-but-blank, and `PAGE-34` states exactly this rule for the other front-end, so applying it here makes the two consistent rather than inventing one |
| P7-6 | The built-in strategies take a caller-supplied `#call(response)` **extractor**, never a `Dexpace::Serde` duck type and never a witness; `PAGE-16`'s "single read of the response body" is a contract `7c` asserts rather than a read core performs | `PAGE-16`, `PAGE-5`; `docs/product-spec/12-pagination.md:3`'s serde-agnosticism; spec-forced boundaries 4 and 5 | A `serde:` or `witness:` keyword would put the word `Serde` inside `lib/dexpace/page/**`, and boundary 5's audit would fail on `7c`'s own code — an audit a sub-phase carves an exception into has stopped meaning anything. The extractor route puts the codec in the caller's closure, which is where boundary 4 says the extraction belongs, and halves the surface `NFR-4` locks. The cost, stated: core cannot *enforce* the single read, only assert it against a read-counting double and document the obligation |

**Nothing else in this sub-phase substitutes a mechanism the reference specifies.** The suppressed trail is
design §10 item 6's, already argued and consolidated, and `7c` consumes it; the `Enumerator` rule is design
§7.1's, already argued, and `7c` obeys it.

---

## Deferrals filed by phase 7c

**None.** Every one of `7c`'s 36 IDs is implemented — 35 outright and `PAGE-35` as vacuous-by-construction on
design §12's own authority — and design §12's `PAGE` row reads "*Deferred:* none", which this sub-phase
confirms rather than changes. **`7c` adds no ⏳ row anywhere and no `DEF-<n>`.**

### Deferral-register sweep

`7c`'s delta against the charter's whole-register sweep, which covered every row once and is not repeated
here. As with phases 3 through 6, this document **states** each disposition and `7c`'s **plan performs** the
register edit.

- **`DEF-2` — untouched, and the charter's decline is not re-opened.** The charter declined phase 7 as
  `DEF-2`'s target and proposed the event shape instead. `7c` confirms the pagination half of that argument
  from inside the subsystem: `PAGE-23` requires that following an absolute next URL "swap only the request's
  URL, **preserving the template's method, headers, and body**", `PAGE-21`–`PAGE-24` change only the query,
  and `PAGE-24` requires every non-query component to survive exactly. **`7c` constructs no header at all.**
  No `PAGE` requirement mentions `Range`, `Content-Range` or `206`. The row stays deferred and still not
  `UNSCHEDULED`.
- **`DEF-24` — untouched; `7c` is a consumer of the row's subject, not its owner.** The row's `Cites:` line
  names `PAGE-13` and `PAGE-15` among four phase-7 IDs, and its pick-up condition is phase 4's. Phase 4b
  ships `Dexpace::Suppressible`, `Dexpace.attach_suppressed` and `Dexpace.suppressed`; `7c` writes no second
  trail and no second skip, and carries the frozen-primary caveat forward in its YARD.
- **`DEF-27` — untouched; closed in 5b.** `Dexpace.close_quietly(resource, onto:)` is `PAGE-26`'s and
  `PAGE-32`'s swallow route and `7c` writes no second quiet close.
- **`DEF-8`, `DEF-16`, `DEF-29` — untouched, and all three are `7a`'s or `7b`'s to disposition.** `SSE-41`,
  `dexpace-serde-oj` and the first consumer outside `dexpace-core` respectively; none has a pagination side.
- **`DEF-18` — untouched.** `ASYNC-3`, `ASYNC-4` and `PIPE-33`'s interrupt clause are phase 8's. `7c` meets
  the same §8.3 prohibition — its async abort is cooperative — and **adds no fourth unsatisfied MUST**.
- **`DEF-4`, `DEF-39`, `DEF-42` — untouched.** `7c` installs no pipeline step, ships no preset and emits no
  instrumentation event required by any of its 36 IDs.
- **Every other row — untouched**, all either closed by an earlier phase, targeted at phase 8 or 9, or riding
  on a post-v1 gem.

---

## The findings proposed for the registers

Four, described here for a human to file. **None is acted on by this document, none carries a number, and no
register file is edited by it.**

**Target register: `docs/deviations.md`, and design §12's `PAGE` row when §10 is next amended.**
**`PAGE-15`'s wrapping clause has no Ruby antecedent and is recorded nowhere.** Design §12's `PAGE` row
currently records exactly one vacuity — `PAGE-35`'s — and reads "*Deferred:* none", which is true and
incomplete: `PAGE-15`'s middle sentence ("When exposed through a stream whose terminal cannot declare the
underlying I/O error type, it MUST be re-thrown wrapped") is conditional on a language feature Ruby does not
have, measured four ways on 3.4.10. §11.15 already catalogues this family for `CFG-34`, `SERDE-11` and
`SERDE-14`; `PAGE-15` belongs in it. The proposed addition to §12's `PAGE` row, verbatim: *`PAGE-15`'s
re-throw-wrapped clause is conditional on a terminal that cannot declare the underlying error type; Ruby has
no checked exceptions and no such terminal, so the clause is vacuous (§11.15) while the ID's other two
clauses are implemented.* Cites: `PAGE-15`, `PAGE-35`, `CFG-34`, `SERDE-11`, `SERDE-14`.

**Target register: `docs/open-items.md`, as an amendment to the corpus-attribution finding the charter
already proposes.** **The charter's corpus-attribution finding is right and is understated in two ways, both
measured.** First, the SSE-rule-filed-under-`PAGE-14` defect is a **pair**, not a singleton:
`sse-streaming/5f4803a0` (Rules) and `sse-streaming/b94ce49e` (Conclusions) both carry only `PAGE-14`, and a
correction naming one leaves the other. Second, `pagination/b2a85752` does **not** carry "no requirement ID at
all" — it carries `BODY-11`, so `--prefix BODY` and `--req BODY-11` return it while `--prefix PAGE` does not;
the consequence the charter names is right and the characterisation is not, which matters because a reader
chasing "an entry with no IDs" will not find it. Cites: `SSE-26`, `SSE-40`, `PAGE-11`, `PAGE-12`, `PAGE-14`,
`BODY-11`.

**Target register: `docs/open-items.md`, as a new row.**
**§12's serde-agnosticism is harvested nowhere, which makes it invisible to every corpus query.**
`pagination/cb5f1b9e` harvests `docs/product-spec/12-pagination.md:3` as the "A port MUST preserve …" half
only; the same line's first sentence — "It is transport-agnostic and serde-agnostic" — appears in no entry,
and `ruby scripts/knowledge.rb --grep 'serde-agnostic|transport-agnostic'` returns exactly one unrelated hit
(`http-domain-model/f4bd2330`, `XCUT-18`). So a phase author who queried the corpus for the property would
conclude it does not exist, and the charter's spec-forced boundary 5 — which exists precisely because the
property carries no requirement ID — would look unmotivated. This is a **harvest-coverage** gap rather than an
attribution one, which is a species neither `OI-16`, `OI-24` nor the charter's own finding covers, and it is
worth a row of its own so the next harvest can be checked against it. Nothing is broken today because nothing
is implemented. Cites: `PAGE-16`, `SSE-37`, `SEAM-2`.

**Target register: `docs/first-release.md`.**
**`PAGE-36`'s per-call overrides are a contract on phase 8's adapters and are invisible until one exists.**
`PAGE-36` requires that "per-call request overrides (timeout, retry budget, tags) … MUST be applied to *every*
page exchange, not just the first", and in this port those overrides are a frozen `Dexpace::RequestOptions`
that the paginator passes to `transport.call` on every page. `7c` can assert that the paginator *passes* them
— against a recording double — and cannot assert that an adapter *honours* them, because none exists. The
failure mode is precise and silent: an adapter that reads `options.timeout` on its first call and caches a
configured client would give page 1 the caller's timeout and pages 2..N the default, which is exactly the
regression `PAGE-36`'s rationale names ("otherwise a caller's timeout/retry policy silently fails to govern
pages 2..N"). The line to file: **phase 8's transport conformance suite must include a per-call-options test
that drives the same transport twice with different `RequestOptions` and asserts both are honoured**, before
release. Cites: `PAGE-36`, `HTTP-34`, `HTTP-35`, `TRANSPORT-1`.

**One row explicitly does not close.** `OI-7`'s subject is a sentence in the frozen §3.1 about the decode
boundary; `7c` reads no body and does not touch the mechanism, so the row is unaffected in either direction.

---

## Open questions for `7c`'s own plan

Five, each bounded, none re-opening a decision above.

1. **Whether `Dexpace::Page::Items` and `::Pages` include `Enumerable` or only define `#each`.**
   `Enumerable` gives `first`, `take`, `.lazy` and the rest for free, which is design §7.1's stated reason for
   the two-`Enumerator` shape ("giving callers `Enumerable` for free … without core inventing vocabulary").
   It also imports roughly sixty methods into a class `NFR-4` locks and a runtime surface snapshot records.
   *Recommendation:* include it, and record in the plan's final task that the surface manifest will carry the
   inherited names — `public_instance_methods(false)` excludes them, so the snapshot is unaffected and the
   RBS `include Enumerable[…]` line is the whole of the declaration.
2. **The exact spelling of the page view's emptiness probe.** `PAGE-12`'s conformance clause says "probe
   has-next without advancing, then close", and Ruby's `Enumerable` vocabulary for that is `#any?`, which
   consumes. *Recommendation:* `Pages#more?` as an explicit non-consuming probe that fills `@buffered`, with
   its YARD stating that it runs an exchange — because `PAGE-12`'s own rationale is that probing is not free,
   and a method named `any?` that costs an HTTP request is a trap. Confirm against `api-design`'s naming rules
   on the plan's first task.
3. **Whether `Walk` is `private_constant`.** It is per-iteration state a consumer never constructs, which
   argues for private; but `Items#close` and `Pages#close` delegate to it and a `sig/` mirror is cheaper if it
   is public. *Recommendation:* `private_constant`, no `sig/`, no manifest row — phase 4's precedent, and the
   views' `#close` is the public surface.
4. **The counting transport double's exact shape**, given it must serve both the sync path (returns a
   `Response`) and the async path (returns a `Dexpace::Async::Future`, settled synchronously or deferred).
   *Recommendation:* one class with a `mode:` of `:sync`, `:async_immediate` or `:async_deferred`, scripting
   an `Array` of responses/raises consumed in order and recording `[request, options, cancellation]` triples —
   6a's `FakeTransport` shape extended with the async modes `PAGE-31` needs. Confirm against 4b's and 6a's
   doubles on Task 1 rather than inventing fresh.
5. **Whether `gates:serde_isolation` scans `sig/` as well as `lib/`.** A `sig/dexpace/page/*.rbs` naming
   `Dexpace::Serde` would be a public-surface dependency `NFR-11`'s scan might or might not catch, depending
   on how `NFR-11` was implemented in phase 0. *Recommendation:* scan both, since the cost is one more glob
   and the gate is cheap; confirm against phase 0's `NFR-11` scan on the task that builds or extends the gate,
   so the two do not overlap confusingly.
