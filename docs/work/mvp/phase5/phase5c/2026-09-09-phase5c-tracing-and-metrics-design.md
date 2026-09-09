# Phase 5c — Tracing and Metrics

**Status:** Draft, for review. Written 2026-09-09, against
`docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`, which is this sub-phase's charter.

**Written concurrently with the 5b design, and reconciled with it on 2026-09-09.** Every statement about
`5b`'s objects was drafted marked *pending reconciliation with 5b*; those markers are resolved in place below,
and where 5b's answer won, the section says so and cites 5b rather than restating its argument. What the
reconciliation changed here, in one list: the two diagnostic-context key names **moved to 5b** and are
`Symbol`s rather than 5c's proposed frozen `String`s, so `TRACE_ID_KEY`, `SPAN_ID_KEY` and the `keys.rb` that
held them are gone; the two OTel instrument **names** are 5b's, which is what this document assumed and 5b's
draft did not; the two slot defaults **stand as 5c wrote them** and 5b adopted them; `interface _Meter`
**stands as 5c wrote it** and 5b deleted its empty declaration; the refusal of a third slot is confirmed from
5b's side; and the recording tracer, span and meter fakes are 5c's, which 5b's step tests now reuse. The
deviation ledger starts at **`P5-40`** and is deliberately not contiguous with `5a`'s: `5a` consumed
`P5-1`–`P5-15` and the block `P5-16`–`P5-39` was reserved for `5b`, which used twenty-three of its
twenty-four. `P5-39` is a **deliberate** unused number, not a lost row. One thing the reconciliation found
that neither document had noticed: **`OBS-24` had a scope-table row in neither**, which *Scope* now corrects
— it is `5b`'s, making this segment 12 IDs and `5b` 28, against a charter whose arithmetic and whose prose
disagree. The register rows this document proposed are filed: `DEF-42`, `OI-28` and `OI-29`.

## Purpose

Sub-phase 5c builds the tracing and metrics half of chapter 15: the span and scope protocols behind phase 4a's
three published singletons, the current-span carrier and the log-correlation scope that pushes and restores two
diagnostic-context keys, `OBS-27`'s trace-id generation on `TraceIdFlavour`, the HTTP-shaped tracer vocabulary
and its ordering contract, and the metrics SPI with its no-op meter. Twelve `OBS` IDs, four specification
sections (§15.5–§15.8), one gem. (The charter's table says thirteen and counts `OBS-24`, which its own prose
gives to `5b`; the correction is in *Scope* below.)

**It is the smallest segment and every one of its inputs is already shipped.** The charter puts it last for
that reason and for no other: "A `5c` built first would be correct and would leave `OBS-34`'s step with two
empty slots for `5b` to fill instead of the other way round." Nothing here waits on `5a`'s `Configuration` or
on `5b`'s `Logger`, and this document states that independence rather than inheriting a chain by habit.

Seven decisions reshape what a plan can write. Each was forced by a fact measured on a real interpreter, by a
requirement read against another requirement, or by a contract phase 4 already signed.

- **A `**attributes` keyword splat allocates one `Hash` per call even when the caller passes nothing, and a
  named optional keyword allocates nothing at all.** Measured on 3.4.10: `def m(x, **attributes)` driven 1000
  times with no keyword argument allocates 1002 objects; `def m(x, attributes: nil)` driven the same way
  allocates 4, and driven *with* `attributes: FROZEN_HASH` allocates 4. A forwarding wrapper that re-splats
  doubles it (2003 / 1000). `OBS-25` makes it a MUST that "Selecting a no-op path MUST NOT allocate per call",
  so **no method in this segment's SPI takes a keyword splat**, and every attributes parameter is one named
  optional keyword carrying a frozen `Hash`. This is the single most consequential fact in the sub-phase: the
  splat is the spelling every Ruby tracing and metrics API uses, `api-design/1d9e6e0b`'s keywords-everywhere
  rule reads as licensing it, and nothing mechanised catches it (`P5-42`, and `OI-28`).
- **Fiber storage's copy-on-write protects the *slot*, not the object in it.** Measured:
  `Fiber[:stack] = []` followed by a `<<` inside `Thread.new` and inside `Fiber.new` mutates the parent's
  Array — the same object, verified by `object_id` — while `Fiber[:span] = :a` rebound in a child leaves the
  parent's slot untouched. So `OBS-22`'s previously-active span is held **in the scope handle's own ivar**,
  with `Fiber[]` carrying one immutable current-span reference, and **never** in a stack stored in fiber
  storage. A span stack there would be a cross-thread shared mutable Array, which is `XCUT-11`'s exact
  prohibition (`R13`).
- **`Fiber[]` accepts a `String` key and interns it, and `Fiber.current.storage` returns `Symbol` keys.**
  Measured: `Fiber["trace.id"] = v` and `Fiber["trace.id"]` each allocate nothing for a frozen literal, and
  `Fiber.current.storage.keys` comes back as `[:"trace.id"]`. `Symbol#name` returns the *same frozen* `String`
  on every call; `Symbol#to_s` allocates a new unfrozen one per call (1001 / 1000 measured). The fold at
  `OBS-10` therefore reads Symbols and must convert with `#name`, never `#to_s` — a fact that belongs to `5b`'s
  hot path and is stated here because 5c owns the writer. **The inference this document drew from it did not
  survive reconciliation**: the draft read "`Fiber[]` accepts either" as licensing frozen-`String` key
  constants declared by 5c, and the key constants are `5b`'s and are `Symbol`s, because `Fiber.current.storage`
  — `OBS-10`'s unfiltered reader — hands back `Symbol`s unconditionally and `Fiber#storage=` refuses a
  `String` key outright. The measurement stands; only what it licenses narrowed (`R11`).
- **`Fiber[:k] = nil` deletes the key; `Fiber#storage = {k: nil}` retains it.** So `OBS-23`'s "restore each key
  to its prior value (**or remove it if previously unset**)" is one assignment for both branches — and a key
  that was present *with* a `nil` value is turned into an absent key by that same assignment. The only way such
  a key exists is the warned whole-map setter, and `OBS-10`'s "Keys with null values MUST be skipped" makes the
  difference unobservable at the only reader. Stated because it looks like a bug and is not (`R12`).
- **`OBS-25`'s cached-singleton scope and `OBS-22`'s restoring scope are reconciled by an identity test, not by
  a recording flag.** A handle is returned that restores nothing exactly when there is nothing to restore — the
  span being activated is `equal?` to the current one and no diagnostic key changed. In an application with no
  tracer installed that is every activation, which is what `OBS-25`'s clause is about; a per-activation handle
  costs one allocation (measured: a plain three-ivar object is 1003 / 1000, a `Data` is 2003 / 1000) and is
  taken only when a restore is owed (`R13`, `P5-47`).
- **Core ships no recording span, no recording tracer and no recording meter, and that is a decision rather
  than an omission.** `OBS-21`'s recording branch, `OBS-30`'s must-not-throw and `OBS-29`'s ordering are
  obligations on an *implementer*; core's only implementations are the no-ops phase 4a published by identity.
  The suite asserts every recording clause against fakes under `test/support/`, following `5a`'s `FakeClock`
  precedent. The cost is that three MUSTs are verified against a fake rather than against shipped code, and
  the row for each says so (`P5-48`).
- **`OBS-29`'s vocabulary ships and nothing emits it in phase 5, and the checklist row says that in the row.**
  `OBS-29`'s own last sentence is "pipeline/transport wiring to emit it is a follow-up, so it is not yet
  runtime-enforced". The per-attempt half has no emitter until phase 6's retry step and the transport
  milestones none until phase 8, so wiring three of eleven callbacks would make the ordering contract half-true
  at runtime while reading as satisfied. 5c ships the vocabulary, `NULL`, the `CallableAdapter` and the
  ordering test §8.1 names, adds **no third slot** to `5b`'s step, and proposes a deferral for the wiring
  (`R14`).

5c ships no logger, no event, no redactor, no configuration accessor and no pipeline step. Its whole test
surface is protocols, frozen singletons, one `Fiber[]` slot, one generator and one ordering assertion.

## Governing documents

- `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md` — the charter, read in full. It fixes 5c's 13
  IDs, the fifteen spec-forced boundaries, the ten verified Ruby facts, the deferral-register sweep and risks
  `R11`–`R15`. `R1`–`R10` belong to `5a` and `5b` and are not touched here. **The cut is not re-opened.**
- `docs/product-spec/15-instrumentation-and-observability.md`, §15.5–§15.8 read in full together with the
  chapter's introduction and §15.9 — 73 lines, carrying a per-ID `*Conformance: …*` clause appendix C does not
  have — and
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text of
  `OBS-21`–`OBS-33` and of `OBS-10`, `OBS-20`, `OBS-24`, `OBS-34`, `SEAM-2`, `SEAM-5`, `SEAM-28`, `CTX-14`,
  `CTX-15`, `CTX-20`, `XCUT-11`, `XCUT-20`, `NFR-4`, `NFR-7` and `NFR-11`.
- `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1 in full — the listener paragraph that
  names `Dexpace::Instrumentation::NULL` and `CallableAdapter`, the tracing paragraph that fixes the
  `opentelemetry-api` structural subset, the correlation-bundle paragraph and the diagnostic-context paragraph.
  §8.2 and §8.3 are read for their edges only and are `5a`'s.
  `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items 4, 5 and 7;
  `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` item **11**,
  which governs the `OBS-28`/`OBS-29` parent-SHOULD/child-MUST pair; and §12's `OBS` row.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-5 row, **cross-phase obligation 1**, the
  gap-ID paragraph (which is where `SEAM-28` appears) and the ✅ / 🚫 / ⏳ / N/A legend the checklist uses
  verbatim.
- `docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-design.md` — its `R3` (the `Bundle`'s
  members, `TraceIdFlavour`, the two no-op singletons and the five-clause handshake), its object-model entry
  for `Dexpace::Instrumentation::*`, its RBS section and its *interface surface 4b and 4c may cite* table,
  whose two phase-5 rows are read as the contract rather than guessed at.
  `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-*` for `Stages::LOGGING` and its two slots.
  `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md` for the format and for its
  *interface surface later phases may cite* row that says 5c gets **nothing** from 5a.
  `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md` — **added at
  reconciliation**, and not read while this document was drafted. It is the source for the two
  diagnostic-context key constants, for the two instrument names, and for the step this segment fills two
  slots in.
  `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md` for the require allowlist and
  the denylist.
- `docs/deferred-items.md`, `docs/open-items.md`, `docs/deviations.md`, `docs/first-release.md` — all read in
  full. `docs/first-release.md` carries no line touching any 5c ID; `docs/deviations.md` rows 7 and 16 touch
  `OBS-2` and `OBS-35`, both `5b`'s.
- `CLAUDE.md` and `docs/README.md`.

## Scope

### The 12 IDs, with dispositions

Twelve IDs: **10 MUST, 2 SHOULD (`OBS-28`, `OBS-32`), 0 MAY**, derived mechanically from appendix C.

**A correction to the charter's arithmetic, found at reconciliation, stated here and filed as `OI-30` rather
than made by editing the charter.** The charter's 5c table says 13 and its Implemented row reads `OBS-21`–`OBS-31`, which **includes
`OBS-24`**; its prose says twice that `OBS-24` is `5b`'s ("it is the context snapshot itself, with no span in
it", and `R12`'s "`5b` owns `OBS-24` and `5c` owns `OBS-23`"). The prose is the reading both sub-phase designs
act on — `5b` builds `Diagnostics.capture` and `.with` for it and this document disclaims it — so 5c is **12**
IDs and `5b` is **28**, and the phase still sums to 78 because the ID moved between two segments rather than
out of the phase. The cut is untouched: no §15 section changes hands. This document's draft carried the
charter's 13 while listing 12 dispositions and marking `OBS-24` "not an ID"; `5b`'s draft did the same from
the other side, so **`OBS-24` had a row in neither scope table** — the one-row-per-ID failure the roadmap's
convention exists to prevent, which is why the correction is made rather than carried.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `OBS-22`, `OBS-23`, `OBS-25`, `OBS-27`, `OBS-28`, `OBS-31`, `OBS-33` | 7 |
| Implemented — core's only span is non-recording, so every clause holds on shipped code; the **recording** branch is an SPI obligation stated in the protocol's YARD and asserted against `RecordingSpan`, a test fake (`P5-48`) | `OBS-21` | 1 |
| Implemented — the **emission contract and its ordering test** ship; **nothing in phase 5 emits it**, which the requirement itself calls a follow-up. ✅-with-clause, citing `DEF-42` and naming the two unwired halves (`R14`) | `OBS-29` | 1 |
| Implemented **by construction** — core does not wrap a tracer or meter call anywhere, which is the whole of the runtime's obligation; the must-not-throw half is a contract on implementers, documented and asserted against a throwing fake that is required to propagate (`OBS-20`'s conformance clause says so in as many words) | `OBS-30` | 1 |
| Satisfied by **phase 4a**, which 5c populates and may not redefine — the reserved sentinels, the 16-lowercase-hex span-id rule and the derived validity flag are `Bundle`, `Bundle::INVALID_SPAN_ID` and `TraceIdFlavour`, all shipped. 5c adds the generator `OBS-27` needs and touches no sentinel (roadmap obligation 1, `DEF-37`, boundaries 10 and 11) | `OBS-26` | 1 |
| ⏳ deferred, `DEF-9` (pre-existing), post-v1 with `dexpace-instrumentation-otel` (`DEF-17`) | `OBS-32` (SHOULD) | 1 |
| Not 5c's, listed for the reader the charter's arithmetic will send here: `OBS-24` is **`5b`'s** and now carries a row in `5b`'s scope table. 5c owns `OBS-23`'s per-key push and cites `5b`'s `P5-23` for the whole-map half (`R12`) | `OBS-24` | — |

**Also shipped by 5c without owning a new ID**, per the charter:

- the span, scope and tracer protocols behind phase 4a's three published singletons, closing `DEF-37`;
- `SEAM-28`'s stable operation identifier as a **consumer** of phase 4a's `RequestContext#operation_name`,
  closing `DEF-1`'s second half;
- the widened RBS interfaces `_Span`, `_Tracer` and `_TracerFactory`, which phase 4a declared empty on purpose.

`OBS-28` (SHOULD) and `OBS-29` (MUST) are the parent-SHOULD/child-MUST pair §11.11 resolves as "the feature is
optional, its behaviour is not". 5c ships `OBS-28`'s vocabulary and therefore owes `OBS-29`'s ordering contract
in full — which it discharges as a contract plus a test, not as a wiring (`R14`).

### The canonical text the design turns on

Quoted from appendix C and from the chapter's conformance clauses rather than paraphrased, because each fixes a
decision below.

> **OBS-21** (MUST) — A Span MUST expose a recording flag; when non-recording, all mutators (attribute/error)
> MUST be inert and drop their data, and end() MUST be a no-op. end() (both success and error variants) MUST be
> idempotent — a second call, or a call on a non-recording span, MUST be a documented no-op.
> *Conformance: on a non-recording span assert mutators inert; call `end()` twice and assert no duplicate export.*

> **OBS-22** (MUST) — Activating a span as the current span MUST return a scope handle that, when closed,
> restores the previously-active span. The scope MUST be closeable from a try/using construct and MUST restore
> even when the guarded code throws.
> *Conformance: nest two scopes; assert the inner restores the outer; throw inside and assert restoration.*

> **OBS-23** (MUST) — Activating a span for log correlation MUST push the trace id and span id onto the
> thread-local diagnostic context (under keys 'trace.id' and 'span.id') for the scope's lifetime, and MUST
> restore each key to its prior value (or remove it if previously unset) on close. For a non-recording span the
> push MUST be skipped and activation MUST delegate to plain current-span activation.

> **OBS-25** (MUST) — The tracing abstractions MUST provide allocation-free no-op defaults used whenever
> tracing is disabled: a no-op Tracer returning a shared no-op Span, a no-op Span whose current-scope is a
> **cached singleton**, a no-op instrumentation context whose identifiers are all invalid sentinels, and a
> no-op HTTP-tracer / tracer-factory. **Selecting a no-op path MUST NOT allocate per call.**
> *Conformance: with no tracer installed, start/end spans in a loop and assert the same singletons and no
> per-iteration allocation.*

> **OBS-27** (MUST) — Trace-id generation MUST support at least the W3C flavour (128-bit value rendered as 32
> lowercase hex chars) and a Datadog flavour (64-bit unsigned integer rendered as a decimal string), plus a
> no-op flavour that always yields the invalid sentinel. Generation MUST NOT produce the reserved all-zero id —
> a zero draw MUST be coerced to a non-zero value.

> **OBS-28** (SHOULD) — … operation started/succeeded/failed; per-attempt started/failed(with next-delay)/
> retries-exhausted; and transport milestones (request URL resolved, connection acquired with host+port,
> request sent with byte count, response headers received with status+headers, response received with byte
> count). **Every event method SHOULD default to a no-op so adding a new event is a non-breaking change and
> implementers override only what they need.**

> **OBS-29** (MUST) — … operationStarted fires once at the start; operationSucceeded and operationFailed are
> mutually exclusive and each fires exactly once at the end; attempt events may fire multiple times;
> retries-exhausted (when it fires) is immediately followed by operationFailed with the same throwable. One
> tracer instance corresponds 1:1 to a single logical operation lifecycle (created by the factory per
> operation). **This is a documented emission contract; pipeline/transport wiring to emit it is a follow-up, so
> it is not yet runtime-enforced.**

> **OBS-30** (MUST) — Tracer and HTTP-tracer callbacks MUST be safe to invoke concurrently and from transport
> threads other than the caller's, and implementations MUST NOT throw from any callback. … **The
> instrumentation runtime does not defensively catch these callbacks (see OBS-20)**, so violating
> must-not-throw breaks the caller's request.

> **OBS-31** (MUST) — The metrics SPI MUST expose a Meter that manufactures at least a monotonic integer
> counter and a floating-point histogram, each accepting per-measurement key/value attributes. The default
> Meter MUST be a no-op that discards every measurement and **returns shared instrument singletons**, and the
> core MUST NOT pull a metrics runtime into its dependencies.

> **OBS-33** (MUST) — A monotonic counter MUST document that only non-negative increments are valid (negative
> deltas are undefined behaviour, the caller's responsibility), and **the core instrument MUST NOT validate
> this on the hot path**. A histogram MUST tolerate any input without throwing (the no-op discards it);
> handling of non-finite values (NaN/±Infinity) is delegated to concrete adapters.

The four neighbours that bound the segment:

> **OBS-10** (MUST, `5b`'s) — … The default allow-list MUST be exactly {trace.id, span.id}. … **Keys with null
> values MUST be skipped.**

> **OBS-34** (MUST, `5b`'s) — … **Span lifecycle AND metric recording (request counter + latency histogram) run
> on every request independent of the log level**, so 'none' silences log events without disabling tracing or
> metrics. *Conformance: at none assert no request/response events but the span still starts/ends and the
> counter/histogram still record.*

> **CTX-20** (SHOULD, phase 4's) — The **per-operation** tracer factory carried on the instrumentation bundle
> SHOULD default to a no-op that emits nothing … Its factory method MUST be safe to invoke concurrently from
> multiple threads, **because operation starts are not serialized**.

> **SEAM-28** (MAY) — The operation projection MAY carry a stable operation identifier for
> instrumentation/tracing; when present it is attached to the request's context chain but **MUST NOT affect the
> assembled request's URL, headers, or body.**

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `OBS-1`–`OBS-20`, `OBS-34`–`OBS-40` — the event object and `Event::INERT`, the duck-typed sink, redaction, the diagnostic-context **fold** and its two key-name constants, `OBS-24`'s snapshot bridge, and the HTTP instrumentation step itself | `5b`. 5c ships **no step, no diagnostic-context key-name constant and no second no-op meter** (boundary 15; the key names moved to `5b` at reconciliation, `R11`) |
| `CFG-1`–`CFG-38` — the configuration chain, the clock, the proxy model | `5a`, shipped. 5c reads nothing from the chain (`R11`) |
| `CTX-14`, `CTX-15`, `CTX-20` — the bundle's shape, `Bundle::NONE`, the no-op tracer factory's existence | 4a, built. Roadmap obligation 1: phase 4 fixed the shape, phase 5 populates and may not redefine. 5c owns `OBS-25`/`OBS-26`/`OBS-27`, the requirements those members are *values of* |
| `ASYNC-8`–`ASYNC-12` — capture, install and restore of the diagnostic context across a thread hop | 8. 5c owns the *writer* (`OBS-23`); `dexpace-async-thread` owns the adapter-side save/install/restore, and `OI-13`'s warned setter is what it will meet |
| `XCUT-11`'s shared-instance audit, `XCUT-20`'s observability-totality audit | 9. 5c builds three of the audited objects — `NO_SPAN`, `NO_TRACER`, `NO_METER` — and `XCUT-20` is the audit `OBS-30`'s deliberate non-wrapping has to survive |
| `SEAM-5`'s auto-activation for instrumentation | Post-v1 (`DEF-30`, `DEF-17`). 5c adds no registry, which is `R15` |
| `PIPE-24`/`PIPE-39`'s `Pipeline.standard` and any preset installing an instrumentation step | 6 (`DEF-39`). 5c installs nothing |
| `RETRY`'s attempt loop and `TRANSPORT`'s connection and byte-count milestones — the emitters `OBS-28`'s vocabulary is *for* | 6 and 8. This is `R14`, and it is why nothing emits in phase 5 |
| `OBS-32`'s OpenTelemetry metric names, units and attribute sets | Post-v1 with `dexpace-instrumentation-otel` (`DEF-9`, `DEF-17`) |
| A span-id **generator** | Nobody, deliberately. `OBS-27`'s scope is trace ids and `OBS-26` states the span-id rule as a *validity* rule; core creates no spans, so a generator would be `NFR-4`-locked surface with no caller (`P5-44`, `OI-8`'s shape) |

**No segmentation design of its own.** 5c is four sections of one spec chapter, one gem, 12 IDs, under a
segmentation design that already exists at the `phase5/` level.

## Prerequisites, and the independence this sub-phase must state

**5c depends on `5a` and `5b` for nothing, and neither depends on 5c.** The charter is explicit that every
phase-5 boundary is a convenience: "A `5b` plan whose first task waits on `5a`'s `Configuration` object has
re-imposed a chain that does not exist; so has a `5c` plan that waits on `5b`'s `Logger`." 5c reads no
configuration value, emits no log event and constructs no `Event`. Its edges to `5b` are a **contract**, not an
ordering — the step's two slots, and the two diagnostic-context key names, which reconciliation put in `5b`
and 5c now reads through one `require` of `5b`'s `diagnostics.rb` (`R11`) — and each was written so that
either sub-phase could land first. 5a's own interface table already records the answer from the other side: the row
for `5c` reads "Nothing. 5a touches `Dexpace::Instrumentation` not at all."

### From phase 0 — seventeen blocking gates, unchanged and unlowered

`gates:require_allowlist` — core's `lib/**/*.rb` may `require` only `monitor`, `uri`, `stringio`, `strscan`,
`time`, `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`. **5c adds nothing to
it** and requires exactly one entry already on it: `securerandom`, for `OBS-27`'s trace-id draw (verified fact
6 below shows why that is safe and what it costs). It writes no `require "logger"`, which is on the
**denylist by name** — the constraint the charter calls the one that "bites harder here than in any phase
before it" is `5b`'s in substance, and 5c meets it only by never defining a sink.

`Dexpace/NoThreadInterrupt` binds nothing 5c writes: 5c starts no thread, takes no lock and performs no wait.
That is worth stating positively, because it is unusual — every other phase-5 segment has a concurrency
mechanism and 5c's concurrency safety is **structural**, resting on frozen stateless singletons and on
`Fiber[]` being per-fiber by construction (`OBS-30`, `CTX-20`, `XCUT-11`).

`Dexpace/NoLocaleCaseFold` binds `OBS-27`'s "32 **lowercase** hex chars": the generator produces lowercase by
construction (`String#unpack1("H*")` and `SecureRandom.hex` both emit lowercase — verified) and never
`downcase`s anything, so the cop has nothing to police and the requirement is met without a fold.

`gates:surface_snapshot` and `gates:sig_diff` regenerate once, deliberately, in the phase's last task. Every
public constant below is `NFR-4`-locked at the first release tag, which is why each carries a Deviation Ledger
row where §8.1 did not already name it — and **§8.1 names exactly two things in Ruby for this segment**,
`Dexpace::Instrumentation::NULL` (§8.1 line 10) and `CallableAdapter` (line 13), verified by grepping the whole
`docs/` tree and re-verified at reconciliation.

**One correction to the charter, stated here because this is where it is made and the charter is not edited.**
The charter's *From phase 1* prerequisite enumerates the constants §8.1 names as
"`Dexpace::Instrumentation::Event`, `Event::INERT` and `Dexpace::Instrumentation::Bundle`", and adds that
phase 4a already shipped `NO_SPAN`, `NO_TRACER_FACTORY` and `TraceIdFlavour`. That enumeration is
**incomplete**: §8.1 also names `Dexpace::Instrumentation::NULL` and `CallableAdapter`, both of them 5c's, and
a sub-phase reading the charter's list as exhaustive would file a Deviation Ledger row for each — an
`NFR-4`-relevant name recorded as arriving by accident when the design in fact chose it. Neither needs a row,
and `P5-40` says so explicitly. The charter is not edited; the correction lives here, which is the treatment
the charter itself prescribes for a sub-phase correcting it and the same one `5b` uses for the charter's `R8`
framing and its 5b scope-table cell.

`OI-19` is a live constraint on the last task and not background: the runtime surface snapshot "does not hold
a `Data`-generated reader for any type using this repository's `class X < Data.define(...)` convention". 5c
adds methods to `TraceIdFlavour`, which is such a type; the methods are ordinary and *are* held, but a reader
regenerating the manifest must not read a stable diff as proof the `Data` readers are covered.

### From phase 1

- **`Dexpace::Model`** with `Model.required!` raising `Dexpace::InvalidArgumentError` and the one message form
  `"<name> is required"` (`SEAM-29`). 5c has exactly one validating entry point — `TraceIdFlavour#generate`
  takes no argument — so this binds only the `Meter` protocol's documented refusal to validate (`OBS-33`
  forbids hot-path validation, so the helper is *not* called there, and that is the point).
- **`Dexpace::ArgumentError` is never defined**, in this or any later phase.
- **Public wire-model constants are flat (P1-1) — but a subsystem the design already names with a namespace
  keeps it.** Everything 5c ships is under `Dexpace::Instrumentation::`, which §8.1 and phase 4a both already
  use, so P1-1 is satisfied by the exception it already carries rather than deviated from.
- **`downcase` takes no argument, everywhere in core.** 5c calls it nowhere; see the cop note above.

### From phase 2

- `Dexpace::Registry` and three seam registries, with **no auto-activation hook of any kind** and a test
  asserting its absence (`DEF-30`). **Phase 4 added no fourth registry and 5c adds no fourth registry** —
  that is `R15`, and it is an argument rather than a lookup.
- `Dexpace::Hooks.notify` and `Dexpace.close_quietly` are `5b`'s edges, not 5c's. 5c defines nothing closeable
  in the `XCUT-13` sense: `OBS-22`'s scope handle responds to `#close` and is deliberately **not** a
  `Dexpace::Closeable` (see `P5-45`).
- Six custom cops, including `Dexpace/QualifiedCoreConstant` (P2-8, extended by P3-7). 5c defines no constant
  that shadows a core class. `Scope`, `Tracing`, `NULL` and `Meter` were each checked against Ruby's own
  constant table; none collides.

### From phase 3

Nothing. 5c touches no body, no stream and no `IO`. The one phase-3 rule that reaches it is the discipline
behind `CLAUDE.md`'s abandoned-`Enumerator` line, applied to the scope handle in `R13`.

### From phase 4 — the largest and most constrained inheritance, and the one this document exists to honour

**From 4a, obligatorily.** Read from 4a's *interface surface* table rather than guessed:

| What 5c receives | Shape, fixed by 4a |
|---|---|
| `Dexpace::Instrumentation::Bundle` | frozen `Data`, **eight stored members** (`trace_id`, `span_id`, `trace_flags`, `trace_state`, `flavour`, `remote`, `span`, `tracer_factory`) plus the **derived** `#valid?` and the predicate `#remote?` (`P4-6`) |
| `Bundle::NONE` | the one frozen untraced singleton, carrying `CTX-15`'s exact sentinel pair |
| `Bundle::INVALID_SPAN_ID` | 16 hex zeros |
| `TraceIdFlavour` | `Data.define(:name, :trace_id_pattern, :invalid_trace_id)`, `.of`, `#valid_trace_id?`, `#renders?`, and the three constants `NONE` / `W3C` / `DATADOG` with `NONE`'s `invalid_trace_id` being `OBS-26`'s 32 hex zeros and `DATADOG`'s being `"0"` (`P4-7`) |
| `Dexpace::Instrumentation::NO_SPAN` | one frozen instance of a `private_constant` class responding to **nothing beyond `Object`'s surface** |
| `Dexpace::Instrumentation::NO_TRACER_FACTORY` | one frozen instance with exactly one method, `#tracer(name = nil, version = nil)` — **positional**, for call-compatibility with `OpenTelemetry.tracer_provider` (`P4-8`) — returning one shared frozen `NO_TRACER` (`private_constant`) |
| RBS `_Span`, `_Tracer` | declared **empty**, on purpose |
| RBS `_TracerFactory` | declares `#tracer` alone |
| `RequestContext#operation_name`, `ExchangeContext#operation_name` | already carried, already advisory — `DEF-1`'s first half for `SEAM-28` |

**The five prohibitions travel with it** (roadmap obligation 1, `DEF-37`, boundary 10). 5c may not introduce a
second no-op span or tracer, replace either published singleton, rename or remove a `Bundle` member, **add** a
`Bundle` member, change `#valid?` from derived to stored, replace `TraceIdFlavour` with a bare `Symbol`, or
give `Bundle` a second `NONE`. 4a answered the question a 5c planner asks first and it is answered here so it
is not re-asked: **adding a `Data` member is redefinition and is not permitted**, because a new member changes
`Data`'s generated `==`, `hash` and `to_h` and with them every `Bundle::NONE` comparison already written. 4a
also checked, rather than assumed, that none of `OBS-21`–`OBS-27` needs a field the eight members do not carry.
This document re-checked the same seven and reaches the same answer, and adds the two 4a did not read for this
purpose: `OBS-31` and `OBS-33` are the metrics SPI and touch no bundle field either.

**From 4c.** `Stages::LOGGING` is the pillar for the instrumentation step, with `Stages::PRE_LOGGING` and
`POST_LOGGING` as its slots, and 4c's own sentence about the step's shape — "It is a pillar, so it **may**
fork. **It should not**" — binds the step. **The step is `5b`'s object and 5c builds no step**, so 4c's row
reaches 5c only through `R11`.

**From 4b.** Nothing directly. `Dexpace.each_cause` exists and 5c writes no cause walk; `OBS-29`'s
"immediately followed by operationFailed with **the same throwable**" is an identity assertion
(`assert_same`), not a walk.

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written.
`ruby scripts/knowledge.rb --origin note --brief` returned **36 entries across 18 note files** when this
document was drafted and returns **37** after the reconciliation pass filed the note described below;
`--section conflicts --brief` returns **24 entries across 17 topic files, 18 of them notes and six harvested**,
and all six harvested conflicts print `[overridden by notes/…]` — `data-modeling/35fde90f`,
`module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and `/8c0687bf`,
`tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`. **None is open**, so 5c inherits no unresolved
conflict and owns no conflict decision of its own. The conflicts count is unchanged from the charter's and
from 5a's; the notes count moved by one at reconciliation (below).

`--prefix-info OBS` reports 40 IDs, 32 MUST / 8 SHOULD, owning chapter
`docs/product-spec/15-instrumentation-and-observability.md`, **40 of 40 substantive, 0 roll-up only, 0
uncited**, and names three topics carrying `OBS` knowledge: `observability`, `redaction-and-security`,
`testing`. `--gaps OBS` returns nothing, so 5c budgets no specification reading beyond chapter 15 — which was
read anyway for §15.5–§15.9, because the per-ID `*Conformance: …*` clauses are not in appendix C and four of
them are load-bearing: `OBS-25`'s "assert the same singletons and no per-iteration allocation" is what makes
identity rather than cheapness the tested property; `OBS-21`'s "call `end()` twice and assert no duplicate
export" needs an exporting span, which core does not have; `OBS-29`'s "drive a succeeding and a failing
(retry-exhausted) operation **through a conformant emitter**" is what licenses `R14`'s fake; and `OBS-34`'s
"at none assert no request/response events but the span still starts/ends and the counter/histogram still
record" is the test `R11` has to make writable.

**The appendix-B roll-up hazard fires on every `OBS` ID**, exactly as the charter said. `--req` on any of
`OBS-21`–`OBS-25` returns five entries tagged `[appendix-B roll-up]` that name all five IDs and state none of
them ("A span exposes a recording flag and its end operation is idempotent" is filed against
`OBS-21, OBS-22, OBS-23, OBS-24, OBS-25` together), and `OBS-26`–`OBS-30` and `OBS-31`–`OBS-33` roll up the
same way in blocks of five and three. The skill's three-step roll-up path was the normal reading mode for this
document; the substantive entry was located beside the roll-up in every case, which is what `--prefix-info`'s
"0 roll-up only" promises and what was checked rather than assumed.

### The audit groups this phase ran

| Group | Query | Result |
|---|---|---|
| **Observability, configuration and redaction** (the tenth row, added by the charter for this material) | `--topic observability,configuration,redaction-and-security --section rules --brief` and `--prefix OBS --section rules --brief` | 92 entries across 3 topic files, and **51 entries covering all 40 `OBS` IDs**. **`OI-24` does not recur on the `OBS` half, and that was checked rather than trusted**: the IDs returned by `--prefix OBS --section rules` were extracted and diffed against the canonical range `OBS-1`..`OBS-40`, and none is missing. `OI-24`'s own mitigation line is what was run |
| **Tracing and metrics rules proper** | `--req OBS-21,…,OBS-33` (three calls, one per roll-up block) | `observability/3655d800` (`OBS-21`), `/97ee8aa4` (`OBS-22`), `/87b26572` (`OBS-23`), `/14b7a965` (`OBS-25`), `/ab7e3bc3` (`OBS-26`), `/ed4172fe` (`OBS-27`), `/1f2f8c85` (`OBS-28`), `/2da9e2f3` (`OBS-29`), `/23abba6b` (`OBS-30`), `/6ba95c3c` (`OBS-31`), `/31cefdb2` (`OBS-32`), `/65043fdd` (`OBS-33`) are faithful restatements of the chapter and add nothing it does not say. **Three design-role entries do add something**: `/94f90bac` (the `opentelemetry-api` structural subset, and *why one shape rather than two*), `/68a9625c` (`dexpace-instrumentation-otel` is "the one adapter permitted presence-gated activation" — which is `R15`'s subject seen from the corpus), and `/4044a5c7`, which is the only place outside §8.1 that names `Dexpace::Instrumentation::NULL` |
| **Failure containment, read for the boundary rather than for 5c's own IDs** | `--topic observability --section constraints --brief` | 3 entries. `observability/0ea8a5ee` is `OBS-20`/`OBS-30`'s asymmetry stated as a constraint — "a throwing tracer or meter will propagate and can fail the request" — and is the entry `P5-48`'s honesty rests on. `/c2ebb968` and `/956f1603` are `5b`'s |
| **Public API surface** | `--topic api-design,module-organization,documentation --section rules --brief` | `api-design/1d9e6e0b` (keywords everywhere) is the rule verified fact 1 **narrows rather than deviates from**: a *named* keyword is free and a *splat* is not, and 1d9e6e0b's stated reason ("a new keyword with a default is always backward-compatible") is a property of named keywords only. `/a9943041` and `/634ccc4b` make adding an optional keyword non-breaking and changing an existing default MAJOR, which is the rule the two slots in `R11` are defaulted under. `/88e6bf12` (narrowest duck-typed parameter) is what makes every protocol here an RBS `interface` rather than a class. `api-design/b0e18938`'s minimal-surface rule is why `NO_METER`'s instruments are `private_constant` |
| **RBS / Steep typing and value objects** | `--topic type-system,data-modeling --section rules --brief` | `type-system/545949a5` (closed sets are frozen `Data` over a frozen table, never `T::Enum`) already governs `TraceIdFlavour`, which 5c extends rather than reshapes. `data-modeling/3e37c086` (state-owning behaviour in a class) puts `Scope` in a class and `Tracing` in a module. `data-modeling/6accaff9` (a mutable constant must be frozen at assignment) is why every singleton here is `.freeze`d at its definition |
| **Minitest conventions** | `--topic testing,assertions --section rules --brief` | `testing/4ef070df` (every test runs alone, in any order, fresh fixtures) is what forces every suite touching `Fiber[]` to restore the slot in a `teardown` — a test that leaves a current span set poisons every later test in the same fiber. `testing/7ecef8e8` and `/630ba094` name the four doubles 5c builds **fakes**. `testing/26b866e1` forbids `assert_nothing_raised`, which bites `OBS-33`'s "MUST tolerate any input without throwing" and `OBS-30`'s concurrency clause directly |
| **Resource lifecycle** | `--topic resource-management --section rules --brief` | 27 entries. `resource-management/bf5560dc`'s block-form rule is what makes `Tracing.with_span` the primary form and the bare handle the secondary one (`P5-45`); `/d1f16cad`'s note reaches nothing here |
| **Styleguide-vs-design conflicts** | `--section conflicts --brief` | All six resolved; none open |
| **Execution-context notes, read because 5c populates 4a's objects** | `--origin note --brief`, narrowed to `execution-context` and `observability` | `execution-context/b58728da` is the entry that decides which of 5c's constants are public: a **qualified** reference to a `private_constant` raises even from inside `Dexpace`, so any object a conformance assertion names by `assert_same` must be public. `observability/698552b4` is the fiber-storage note, and it is the boundary `R12` and `R13` work inside |

### The notes filed against the corpus by this phase

**None, and that is a decision rather than an omission.** Two candidates were considered.

- **The keyword-splat allocation fact.** It corrects nothing in the corpus: `api-design/1d9e6e0b` says to use
  keyword arguments and says nothing about `**splat`, and `observability/956f1603` records only that an
  *enabled* event cannot be allocation-free. A note would be adding a rule, not overriding one, and the
  mechanism for that is a styleguide amendment plus a harvest — not a `notes/` file. It is recorded here as
  verified fact 1, as `P5-42`, and as `OI-28`.
- **`Fiber[]`'s copy-on-write being per-slot and not per-object — filed at reconciliation, not by this
  document.** It *narrows* the "inheritance is copy-on-write" property this repository's existing note added
  to `observability/e0f1e864`, and a narrowing of a note is exactly what a second note is for — **but the `5b`
  agent was writing concurrently and might have been filing against the same topic file.** Per the
  working-in-parallel rule this document was written under, no note was written here; the finding was stated
  as verified fact 2 and reported. The pass that reconciled the two designs filed **one** entry against
  `docs/knowledge/notes/observability.md`, carrying this finding together with `5b`'s that `Fiber#storage=`
  rejects a `String` key while `Fiber[]=` coerces one — the two halves of the same write-side story — with
  both re-verified on 3.4.10 and the entry flagged single-interpreter. `--origin note --brief` accordingly
  returns **37** entries after the reconciliation and returned 36 when this document was drafted.

## The verified Ruby facts this phase is built on

**Interpreter availability, stated before the facts because it limits every one of them.** Phases 3 and 4 ran
their facts on 3.2.11, 3.4.10 and 4.0.6 via `mise exec ruby@<v>`. **On this machine only 3.4.10 is
installed** — re-checked for this document: `ruby -v` is `ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM
[x86_64-linux]`; `mise ls` lists `bun`, `go`, `node` and `opencode` and **no Ruby**; `~/.rbenv`, `~/.rvm` and
`/opt/rubies` do not exist. Every fact below was run on 3.4.10 and on nothing else, and **no result is claimed
across a range that was not run.** Facts **2, 3, 4 and 6** are of the floor-straddling kind this repository has
been bitten by three times (`URI::DEFAULT_PARSER` at 3.4.0, `StringIO#read(n, buf)`'s encoding at 3.4,
`Data#with`'s `initialize` on 3.2), and **5c's plan re-runs each on 3.2.11 and 4.0.6 before relying on it**;
the inline flags and this list are the same four. Fact 1 is not among them — allocation counts are a VM
property and the plan re-measures them anyway as part of `OBS-25`'s own test.

1. **A `**attributes` keyword splat allocates one `Hash` per call; a named optional keyword allocates
   nothing.** Driven 1000 times each, `GC` disabled, `GC.stat(:total_allocated_objects)` deltas, in a file
   carrying `# frozen_string_literal: true`:

   | Call shape | Allocations / 1000 |
   |---|---|
   | `def m(x, **attributes)` called as `m(e)` | **1002** |
   | `def m(x, **attributes)` called as `m(e, method: "GET")` | **1002** |
   | `def m(x, **attributes)` called as `m(e, **FROZEN)` | **1003** |
   | a wrapper forwarding `**kw` to another `**kw` | **2003** |
   | `def m(x, attributes: nil)` called as `m(e)` | 4 |
   | `def m(x, attributes: nil)` called as `m(e, attributes: FROZEN)` | 4 |
   | `def m(name, with_parent: nil, attributes: nil, kind: nil)` called as `m("op")` | 1 |
   | `def add(v, attributes = nil)` called as `add(1)` / `add(1, FROZEN)` | 3 / 3 |
   | `def add(v, attributes = nil)` called as `add(1, { "m" => "GET" })` | 1001 |
   | `obj.recording?`, `obj.finish`, `obj.set_attribute("k", "v")` on a frozen singleton | 1 / 1 / 1 |
   | `in_span("op")` yielding to a **literal block**, not a `Proc` | 1 |

   (1 per 1000 is the measurement floor; the loop itself allocates.) *What it licenses:* `OBS-25`'s "Selecting
   a no-op path MUST NOT allocate per call" is satisfiable in Ruby for every method core calls on a span, a
   tracer or an instrument, **provided no signature uses a splat** — and the block form `OBS-22` wants is free
   too. *What it does not license:* the claim that the no-op path is free end-to-end. An **inline hash
   literal** at the call site allocates whether or not the callee splats (1001 / 1000 measured), so the caller
   — `5b`'s step — must hoist its attribute hashes to frozen constants or accept one allocation per request.
   That is `5b`'s call site and 5c states it in the crossing contract rather than assuming it (`R11`). It also
   does not license reading this as a *deviation* from `api-design/1d9e6e0b`: that rule asks for keywords and
   the splat is not a keyword.

2. **Fiber storage's copy-on-write protects the slot, not the object in it.** *Floor-straddling.*
   `Fiber[:stack] = []`, then `<<` inside `Thread.new` and inside `Fiber.new`: both mutations are visible in
   the parent and `object_id` is identical across the thread boundary. Rebinding an immutable value —
   `Fiber[:span] = :child` in a thread — leaves the parent's slot at `:parent`. Re-verified in the same run
   that `Fiber[:k]` set in the main fiber is visible inside `Fiber.new { }`, inside `Thread.new { }` and
   inside an `Enumerator`'s internal fiber, which is `observability/698552b4` holding. *What it licenses:*
   one `Fiber[]` slot holding an immutable current-span reference, with the previously-active span held in the
   scope handle's own ivar and restored through the Ruby call stack. *What it does not license:* a span
   **stack** in fiber storage, which would be one shared mutable `Array` across every thread and child fiber
   descended from the one that created it — `XCUT-11`'s "any shared mutable state MUST be synchronized" with
   no synchronisation in sight. `observability/698552b4`'s phrase "inheritance is copy-on-write" is true and
   is about the slot; read as being about the contents it produces exactly this bug.

3. **`Fiber[]` accepts a `String` key and interns it; `Fiber.current.storage` returns `Symbol` keys and a
   fresh `Hash` per read.** *Floor-straddling.* `Fiber["trace.id"] = "abc"` then
   `Fiber.current.storage.keys` gives `[:"trace.id"]`; `Fiber[1] = x` raises
   `TypeError: 1 is not a symbol nor a string`. Reading and writing with a frozen `String` literal allocates
   nothing (1 / 1000 each). Two successive `Fiber.current.storage` calls return objects that are **not**
   `equal?`, the returned `Hash` is unfrozen, and mutating it does not affect storage; with four keys present
   the read allocates one `Hash` per call (1003 / 1000), with none present it allocates nothing.
   `Symbol#name` returns the **same frozen `String`** on every call (`equal?` true, `frozen?` true);
   `Symbol#to_s` returns a new unfrozen one (1001 / 1000; over a two-key storage the difference is
   1007 / 1000 for `name` against 5001 / 1000 for `to_s`). *What it licenses:* the key constants are frozen
   `String`s — the form `OBS-23` and `OBS-10` both write — and `OBS-23`'s push and restore cost nothing.
   *What it does not license:* any claim about `5b`'s fold being free. The whole-map read allocates a `Hash`
   per event once anything is in storage, and a fold spelled with `Symbol#to_s` allocates one `String` per
   key per event. Both are `5b`'s to pay or avoid; 5c owes the fact, not the fix.

4. **`Fiber[:k] = nil` deletes the key; `Fiber#storage = {k: nil}` retains it.** *Floor-straddling — and
   `OI-13` already records that `Fiber.current.storage = nil` reads back as `{}` on 3.2.11 and as `nil` on
   3.4.10 and 4.0.6, so the whole-map setter's floor behaviour is known-divergent.* Verified here: after
   `Fiber[:k] = "v"; Fiber[:k] = nil`, `Fiber.current.storage.key?(:k)` is `false`. After
   `Fiber.current.storage = { a: nil, b: 1 }`, `key?(:a)` is `true` and `Fiber[:a]` is `nil`. Consequently a
   key that was present with a `nil` value and is restored per key becomes **absent** — measured directly,
   `key?` going `true` → `false` across a push-and-restore cycle. Two `Fiber#storage=` calls produced two
   `Fiber#storage= is experimental and may be removed in the future!` warnings, category `:experimental`, at
   the default warning level; two `Fiber[]=` writes produced none. *What it licenses:* `OBS-23`'s entire
   contract — push two keys, restore each "to its prior value (or remove it if previously unset)" — as **two
   plain assignments in one `ensure`**, with no branch on presence, no warned setter and no `NFR-7` problem.
   *What it does not license:* treating "previously unset" and "previously present with a `nil` value" as
   distinguishable through the per-key API. They are not, the second is reachable only through the warned map
   setter, and `OBS-10`'s "Keys with null values MUST be skipped" makes the difference invisible at the only
   reader — which is the argument, not an excuse (`R12`).

5. **A three-ivar object per activation costs one allocation; a `Data` costs two; `begin/ensure` costs
   nothing.** Measured: a plain class with three ivars is 1003 / 1000; `Data.define(:a,:b,:c).new(...)` is
   2003 / 1000 positional and 2003 / 1000 by keyword; `Struct` is 1003 / 1000; a method wrapping a `yield` in
   `begin/ensure` is 1 / 1000. Nesting through the Ruby call stack was driven directly: two nested
   activations restore in the right order, and a `raise` inside the inner one leaves the outer slot at its
   original value. *What it licenses:* `Scope` as a plain class with three ivars rather than a `Data` — the
   one place in this repository where the domain-model construction pattern is **not** the answer, because
   `Scope` is a per-call resource handle and not a value (`data-modeling/3e37c086`), and because `OBS-25`
   counts allocations. *What it does not license:* claiming the recording path is allocation-free. It is not
   and does not have to be; `OBS-25`'s clause is about the **no-op** path.

6. **`securerandom` is a permanently-default gem, its require pulls in two files and does not load
   `openssl`, and `SecureRandom.hex(16)` yields 32 lowercase hex characters.** *Floor-straddling for the
   bundled-gem half.* `Gem::BUNDLED_GEMS::SINCE["securerandom"]` is `nil` while `["logger"]` is `"4.0.0"` and
   `["base64"]` is `"3.4.0"`; `require "securerandom"` adds 2 entries to `$LOADED_FEATURES` and
   `$LOADED_FEATURES.any? { |f| f.include?("openssl") }` is `false` afterwards. `Random#bytes(16).unpack1("H*")`
   also yields 32 lowercase hex. `(1 << 64) - 1` is `18446744073709551615`, twenty decimal digits. *What it
   licenses:* `OBS-27`'s W3C and Datadog generation from `SecureRandom`, with **no growth of the require
   allowlist** — `securerandom` is already on it — and with the bundled-gem rule satisfied on the highest Ruby
   in the matrix. *What it does not license:* reading this as reversing boundary 8. That boundary forbids
   implementing **`CFG-32`** as `SecureRandom.uuid`, because `CFG-32`'s own text demands a non-cryptographic
   per-thread PRNG; `OBS-27` states no such constraint, and using the CSPRNG path here is what *keeps* the two
   paths separate rather than merging them. It also does not license omitting the zero-draw check: the
   coercion `OBS-27` requires is unconditional, not probabilistic.

7. **A frozen stateless singleton is seen as the same object from sixteen threads, and `Module#constants`
   excludes a `private_constant`.** `16.times.map { Thread.new { S.equal?(S) } }.map(&:value).all?` is `true`;
   `module M; X = 1; Y = 2; private_constant :Y; end` then `M.constants` is `[:X]`. A frozen object's `#dup`
   is unfrozen and its `#clone` is frozen. *What it licenses:* `OBS-30`'s "safe to invoke concurrently" and
   `CTX-20`'s embedded MUST are satisfied **structurally** for every no-op in this segment — no lock, no
   flag, and a test that asserts identity across threads rather than absence of corruption (4a's precedent).
   And `NO_METER`'s instruments can be `private_constant` without appearing in the surface snapshot. *What it
   does not license:* the same claim for a *recording* implementation, which is the adapter's obligation and
   which `#dup` quietly defeats — an adapter that `dup`s a frozen instrument gets an unfrozen copy, which is
   why the protocol's YARD says implementations are shared and must not be copied.

8. **A no-op histogram accepts `Float::NAN`, `±Float::INFINITY`, `0` and `-1` without raising.** Driven
   directly against `def record(v, attributes: nil) = nil`. *What it licenses:* `OBS-33`'s "A histogram MUST
   tolerate any input without throwing (the no-op discards it)" is met by construction, and its counterpart —
   "the core instrument MUST NOT validate this on the hot path" — is met by there being no validation to
   write. *What it does not license:* an `assert_nothing_raised`-shaped test. `testing/26b866e1` forbids it,
   so the assertion is `assert_nil` on the return value for each of the five inputs, which is a stronger
   claim than "did not raise" and is what a discarding instrument actually promises.

## `R11` — the instrumentation step's two slots, and who declares `trace.id` and `span.id`

**Reconciled with 5b on 2026-09-09; nothing in this section is pending.** The charter's boundary 15 fixes that
the step is `5b`'s, installed at `Stages::LOGGING`, and that 5c fills two slots and ships **no second step, no
second key-name constant and no second no-op meter**. 5c honours all three. Of the four things this section
decided, **two stand as written** (the slot defaults and their precedence; no third slot) and **one is
reversed** (the two key names, which are 5b's); the fourth — the OTel instrument names — is settled the way
this document assumed. Each subsection says which, and where 5b won, 5c cites 5b rather than re-arguing.

### The two slots are constructor keywords with constant defaults, not a configuration read

**Decision: the step takes `tracer_factory:` defaulting to `Dexpace::Instrumentation::NO_TRACER_FACTORY` and
`meter:` defaulting to `Dexpace::Instrumentation::NO_METER`. Stands after reconciliation; 5b adopted it.**
Three reasons, in increasing order of force.

1. **A configuration read makes the step depend on `5a`'s chain**, which the charter forbids in as many words
   for `5b` and `5c` alike. It would also make the no-op path a `Configuration#derive` lookup rather than a
   constant reference, and `OBS-25`'s allocation clause is asserted by *reference identity from a qualified
   constant* (`execution-context/b58728da`) — a lookup returning the same object still passes, but the test
   would be asserting the chain's memoisation rather than the singleton's identity.
2. **`api-design/1d9e6e0b`, `/a9943041` and `/634ccc4b` make adding an optional keyword non-breaking and
   changing an existing default MAJOR**, which is exactly the property two slots that later gain a
   configuration source need. A phase-6 `Pipeline.standard` (`DEF-39`) can read the chain and pass the
   result; the step's signature does not change when it does.
3. **`CTX-14` already carries a `tracer_factory` on every context**, so a step-level keyword is a *default*
   for the case where the context's bundle is `Bundle::NONE`, not a second source of truth. The precedence a
   plan must implement, stated once: **the context's bundle wins when it is not `Bundle::NONE`; otherwise the
   step's keyword; otherwise `NO_TRACER_FACTORY`.** That is the ordering `CTX-14` implies and `OBS-25`
   requires the tail of.

**What 5c assumed about 5b, and what actually happened.** 5c assumed the step's constructor takes keywords at
all and that `5b` does not instead read both from a `Configuration`. `5b` did take keywords and rejected the
configuration read for the same reason (there is no tier of `5a`'s `String`-valued chain that can carry a
tracer factory) — but made both slots **required and undefaulted**, on the ground that `meter:` could not be
defaulted without naming an object `5c` had not yet shipped. That ground is an artefact of parallel
authorship: `NO_METER` ships in this segment, in the same phase. **5c's defaults stand**, and `5b`'s `P5-33`
is rewritten around reason 3 above — `CTX-14` already puts a `tracer_factory` on every context, so a required
keyword makes every caller restate an object the request's own context carries. The precedence stated above is
the one `5b`'s step implements; nothing in `5b` contradicts it.

### `OBS-34`'s independence of the log level, and the half 5c owes

`OBS-34` is `5b`'s ID and **its conformance clause is discharged by a `5b` test**: the one that drives the
step at `HTTPLogging::NONE` with a recording sink, `RecordingTracer` and `RecordingMeter` and asserts zero sink
writes, one `start_span`, one `finish`, one counter record and one histogram record, with a second test at
`HTTPLogging::BODY` for the preview fields. **Nothing 5c ships discharges it**, and the assertion below is not
a second mechanism for the same clause — it is 5c's own regression against acquiring a dependency on the
logging half. Both are named here as two, because two documents each describing a different mechanism as *the*
mechanism is how a requirement ends up with no test at all. What 5c owes is the half that makes `5b`'s test
writable, and it is a structural property rather than a behaviour:

> **Nothing 5c ships reads a log level, holds a sink, or references `Dexpace::Instrumentation::Event`.**
> `Tracing`, `Scope`, `HTTPTracer`, `NULL`, `TraceIdFlavour#generate`, `NO_METER` and its instruments have no
> constructor parameter, no ivar and no method argument through which a level could reach them.

That is asserted directly, in 5c's own suite, by a test that would otherwise not be written: **a grep-shaped
assertion is not enough, so the suite constructs every 5c object with the `Dexpace::Instrumentation` tree
loaded and `Dexpace::Instrumentation::Event` *not* defined** — 5c's suite requires only the files in its own
module layout, so a reference to `5b`'s event object would raise `NameError` at load. A dependency on the
logging half becomes a red suite in 5c rather than a subtly-passing test in 5b.

**The consequence for 5b's own test**, stated so it is not rediscovered: at level `none` the step must call
`tracer_factory.tracer(...)`, activate, record and end **outside** whatever branch suppresses the log events.
The cheapest correct shape is one method that does the tracing and metrics unconditionally and calls a
private `emit_events` only when the level permits — not two branches each doing part of the work, which is
the shape that passes the conformance test and drifts on the first refactor.

**What 5c assumed about 5b:** nothing about the step's internal structure. The recommendation above is a
recommendation, and `5b` independently adopted the same shape — two `logger.event` sites under the level guard
inside `Instrumentation.contain`, every tracer and meter call outside both, in the `ensure`. The assertion 5c
makes is only about its own objects, and it stays a load-time assertion rather than becoming an `OBS-34`
claim.

### The two key names are declared by 5b, as `Symbol`s — this section's decision, reversed

**This document proposed `Dexpace::Instrumentation::TRACE_ID_KEY = "trace.id"` and `::SPAN_ID_KEY =
"span.id"`, frozen `String`s declared here. `5b` proposed `Diagnostics::TRACE_ID` and `::SPAN_ID`, `Symbol`s
declared there. `5b`'s stand.** 5c declares neither constant, ships no `lib/dexpace/instrumentation/keys.rb`
— which would have collided with `5b`'s file of that name for `Keys`/`Events` — and references `5b`'s pair
from `Tracing.correlate`. The argument is `5b`'s `R11`; it is not restated here, but the two halves of this
document's own reasoning that did not survive are recorded, because a reader who finds the draft is entitled
to know which part was wrong.

**On ownership, the writer-owns-the-key rule does not reach this case.** The rule was that "a constant owned
by the writer cannot drift from what is written; a constant owned by the reader can". That is sound where the
reader's value is *derived* from the writer's. Here it is not: `OBS-23` (MUST) fixes the literal keys — "under
keys 'trace.id' and 'span.id'" — and `OBS-10` (MUST) independently fixes the default allow-list as "exactly
{trace.id, span.id}". Both sides are pinned by their own MUST, so there is no direction for drift to run in,
and the rule selects no owner. What does select one is that `OBS-10` needs the pair **as a collection** —
`DEFAULT_KEYS`, a value `5b` constructs and passes to its fold — while `OBS-23` needs two scalars written one
at a time.

**On type, verified fact 3 is right and its inference was not.** `Fiber[]` does accept a `String` and intern
it at no per-call cost, and `OBS-23`/`OBS-10` do write the keys as strings in prose. But
`Fiber.current.storage` returns `Symbol` keys unconditionally, and that is the reader `OBS-10`'s **unfiltered
mode** is obliged to use — "A null (absent) allow-list MUST fold every present diagnostic-context key" cannot
be implemented by asking about keys you already know. So every key reaching the fold is a `Symbol` at that
point, and a `String` constant would make the allow-listed and unfiltered paths disagree about the type of the
same key. Design §8.1 spells the carrier `Fiber[:key]`, which is the same answer from the design side. And the
one place this document's own `Fiber#storage=` finding still does work is forward-looking: phase 8's `ASYNC-9`
pooled-worker restore is a whole-map operation that may have no way to avoid the setter, which **rejects a
`String` key** — so a snapshot keyed by `String` constants is not installable through it.

**The crossing fact `5b` would otherwise have got wrong stands, and `5b` uses it:** the fold reads
`Fiber.current.storage`, whose keys are `Symbol`s, and converts with **`Symbol#name`** — the same frozen
`String` on every call — and **never `Symbol#to_s`**, which allocates a new unfrozen `String` per key per
event (verified fact 3: 1007 / 1000 against 5001 / 1000 over two keys). `Symbol#name` exists from Ruby 3.0 and
so is available on the 3.2 floor; its identity guarantee is flagged for re-verification with the other
floor-straddling facts. The reconciliation pass added one measurement this document did not make and `5b`
depends on: **`:"trace.id".name` is not `equal?` to a `"trace.id"` frozen literal**, so the two spellings are
two objects and a single declaring constant is not a stylistic preference.

**What this costs 5c: one require.** `Tracing` now requires `5b`'s `lib/dexpace/instrumentation/diagnostics.rb`
for `Diagnostics::TRACE_ID` and `::SPAN_ID`. The reason this document wanted its own file — "a file that can be
required alone is what keeps the crossing contract from dragging the whole segment behind it" — is honoured in
mirror image: `diagnostics.rb` requires nothing else in `5b` and defines no `Event`, so requiring it does not
pull the logging half in and does not break the load-time assertion below.

### The two OTel instrument names are 5b's, as this document assumed

`5b`'s draft assigned `http.client.request.count` and `http.client.request.duration` to 5c, "because a name in
`Instrumentation::Keys` would be an `NFR-4`-locked constant for an object 5b does not build". They are 5b's,
and 5b now declares them: the step is the only caller of `create_counter` and `create_histogram` in core, so
it *does* build the instruments, and `OBS-34` — a 5b MUST — cannot record a counter and a histogram without
naming them. **5c declares no instrument name, unit or attribute set**, which is unchanged from the draft, and
`OBS-32` stays ⏳ `DEF-9`: what remains deferred is the units, the descriptions, semantic-convention
conformance and the method/status/error attribute sets, whose conformance clause needs a **recording meter**
that core does not ship (`P5-48`).

## `R12` — `OBS-23`'s half of the fiber-storage decision

**5c owns `OBS-23`. `5b` owns `OBS-24`. The decision about `Fiber#storage=` is stated once and cited by the
other, and the charter's verified fact 1 splits it cleanly.**

### 5c's half, stated fully and not pending anything

`OBS-23`'s contract is discharged with **`Fiber[]=` alone, per key, in one `ensure`, with no branch on
presence and no warned setter anywhere in core.** The shape:

```
prev_trace = Fiber[Diagnostics::TRACE_ID]           # 5b's constants, Symbols — R11
prev_span  = Fiber[Diagnostics::SPAN_ID]
Fiber[Diagnostics::TRACE_ID] = bundle.trace_id
Fiber[Diagnostics::SPAN_ID]  = bundle.span_id
...
ensure
  Fiber[Diagnostics::TRACE_ID] = prev_trace     # nil deletes — verified fact 4
  Fiber[Diagnostics::SPAN_ID]  = prev_span
```

Four properties, each verified rather than assumed:

- **"restore each key to its prior value (or remove it if previously unset)" is one assignment for both
  branches**, because `Fiber[:k] = nil` deletes the key (verified fact 4). No `key?` check, no sentinel, no
  branch — which matters because a branch here would be dead on every path a test can drive.
- **The two restores are one `ensure`**, together with the current-span restore that `OBS-22` owes, in the
  same handle and the same block. Three restores, one `ensure`, no ordering hazard between them because none
  reads another's slot.
- **`Fiber[]=` emits no warning** (verified fact 4: two writes, zero warnings), so `NFR-7`'s
  warnings-fail-the-build gate is never engaged and `OI-13` never bites 5c.
- **Nothing is stored that a child fiber or thread can mutate.** The slots hold frozen `String`s and one
  immutable span reference (verified fact 2).

**The one honest gap.** A key present with a `nil` **value** — reachable only through `Fiber#storage=`, which
is `5b`'s `OBS-24` bridge and phase 8's `ASYNC-9` — is turned into an **absent** key by the per-key restore
(verified fact 4, measured `key?` going `true` → `false`). `OBS-23`'s words are "its prior value (or remove
it if previously unset)", and this restores *removal* where the prior state was *present-and-null*. It is
unobservable at the only reader, because `OBS-10` requires that "Keys with null values MUST be skipped", so
a null-valued key and an absent key fold identically. Recorded as a deviation (`P5-49`) rather than buried,
because the argument that makes it harmless is `OBS-10`'s clause and a later phase that relaxes that clause
re-opens this.

### The shared half — settled, and `5b` reached the same answer

`OBS-24`'s whole-map snapshot is the warned operation. **5c recommended, and `5b` decided (its `R12`,
`P5-23`), and 5c does not implement:** restore per key over the **union of the captured and prior key sets**,
which
stays inside `Fiber[]=`, never touches `Fiber#storage=`, and therefore never meets `OI-13`'s warning or its
3.2-versus-3.4 `= nil` divergence. The costs, stated so the recommendation is not free: the union restore is
O(captured + prior) rather than one assignment; a key present-with-`nil` in the *prior* map is dropped by the
same mechanism this section already records; and the capture side still needs `Fiber.current.storage`, which
is not warned and which verified fact 3 shows already returns a fresh unfrozen `Hash` per call — so
`OBS-24`'s "The snapshot itself MUST be immutable/shareable" is one `freeze` on an object nobody else holds,
with no defensive copy needed. That last point is a genuine simplification of `OBS-24` that 5c measured and
`5b` should not re-derive.

**Settled:** `5b` reached the same answer independently and states it as `P5-23` — `Fiber#storage=` is never
called in `dexpace-core`'s `lib/`, and exactly once in its `test/`, to construct the null-valued key
`OBS-10`'s skip clause is about. `5b`'s statement is the one that binds and this section cites it; 5c does not
restate the argument. The one thing 5c adds that `5b`'s route also inherits is `P5-49`'s gap, recorded on both
sides. Neither route touches `OI-13`, which is the point of both.

**Both halves need re-running on 3.2.11 and 4.0.6 before either is implemented.** This document ran 3.4.10
only, and `OI-13` already documents a floor divergence in the neighbourhood.

## `R13` — the scope handle, against `OBS-25`'s cached-singleton clause

`OBS-22` requires activation to "return a scope handle that, when closed, restores the previously-active
span", and to restore even when the guarded code throws. `OBS-25` requires "a no-op Span whose current-scope
is a **cached singleton**" and that "Selecting a no-op path MUST NOT allocate per call". A handle that
restores a previous span carries per-activation state and cannot be a singleton; a handle with nothing to
restore can be.

### The split is an identity test, not a recording flag

**Decision: `Tracing.activate(span)` returns `Dexpace::Instrumentation::NO_SCOPE` — one frozen cached
singleton — exactly when nothing is owed on close, and a fresh `Scope` otherwise.** "Nothing is owed" is
`span.equal?(Fiber[CURRENT_SPAN_KEY])` for a plain activation, and additionally "no diagnostic key changed"
for a correlating activation.

Stating it against the recording flag instead — return `NO_SCOPE` iff `!span.recording?` — is the tempting
reading of `OBS-25` and it is **wrong**, for a reason worth writing down: a non-recording span activated on
top of a *recording* one still has to restore the recording one on close, and `OBS-23`'s own sentence
requires that case to exist ("For a non-recording span the push MUST be skipped and activation MUST delegate
to **plain current-span activation**" — delegate to it, not skip it). A singleton returned there would leave
the recording span un-restored, which is `OBS-22`'s exact failure. The identity test is strictly stronger:
it returns the singleton in every case the recording test would, plus the case of a recording span
re-activated on itself, and never in the case that breaks.

**In an application with no tracer installed the identity test is true on every activation**, because
`Bundle::NONE.span` is `NO_SPAN` and the slot already holds it — so the untraced path allocates nothing per
call, which is what `OBS-25`'s clause is about and what its conformance note asserts ("start/end spans in a
loop and assert the same singletons and no per-iteration allocation").

### Where the previously-active span is stored

**Decision: one `Fiber[]` slot holds the current span; the previously-active span is an ivar on the `Scope`
handle; there is no stack anywhere.**

- **Not a stack in fiber storage.** Verified fact 2 is decisive: a mutable `Array` in a `Fiber[]` slot is the
  *same object* in every child fiber and every thread descended from the fiber that created it, so two
  concurrent requests sharing an ancestor would push and pop into one another's stack. That is `XCUT-11`'s
  "any shared mutable state MUST be synchronized" with no synchronisation, and it would be invisible in a
  single-threaded test.
- **Not a closure.** A closure over the previous span is a `Proc` allocation per activation and gives
  `OBS-22`'s "closeable from a try/using construct" nothing to close.
- **A three-ivar handle**: `prev_span`, `prev_trace_id`, `prev_span_id`. One allocation (verified fact 5),
  taken only on the path that owes a restore. Nesting is the Ruby call stack; correctness under a raise is
  the language's, and was driven directly (verified fact 5: two nested activations restore in order, and a
  `raise` inside the inner leaves the outer slot at its original value).

**`Scope` is a plain class and not a `Data`**, which is the one place in this repository where the domain-model
construction pattern is deliberately not applied. It is a per-call resource handle rather than a value: it has
no meaningful `==`, its `#hash` would be nonsense, `Data`'s frozen-on-construction property is worth nothing
to it, and it costs two allocations against a plain object's one (verified fact 5). `data-modeling/3e37c086`
puts state-owning behaviour in a class and that is the rule followed here (`P5-46`).

### How the handle is exposed, and the `Enumerator` rule

`CLAUDE.md`: "**resource acquisition and release never live inside an `Enumerator` block**"; an `Enumerator`
abandoned mid-`#next` never runs its `ensure`. `OBS-22` requires a handle "closeable from a try/using
construct", so the handle must exist as an object — but the *primary* form is the block:

- **`Tracing.with_span(span) { |span| … }`**, and its correlating sibling `with_correlated_span` —
  `begin`/`ensure` in one method scope, free (verified fact 5: 1 / 1000), and the form
  `resource-management/bf5560dc` asks for. This is what `5b`'s **sync** step calls.
- **`Tracing.activate(span) -> _Scope`** and `.correlate(span, bundle) -> _Scope`, with `#close` —
  `OBS-22`'s literal requirement, public because the requirement is. **`activate` is called by nothing in
  core**; `correlate` is, by `5b`'s `AsyncStep`, whose span outlives `#call`. `activate`'s bare-handle form is
  the `OI-8` shape and it is accepted deliberately (`P5-45`): the requirement's words are "return a scope handle", the conformance test nests two of them by
  hand, and an SDK consumer who spans a non-lexical region needs exactly this. What makes it not `OI-8` is
  that the block form is implemented **in terms of** it, so the handle has a caller and one code path.
- **`Scope` is not a `Dexpace::Closeable`.** `XCUT-13`'s idempotent non-blocking close is about resources
  with an owner and a lifecycle; a scope is neither, its `#close` restores rather than releases, and
  inheriting the latch would give it an ownership contract nothing asks for. Its `#close` is idempotent
  anyway — a second call restores the same three values to the same three slots — which is what `OBS-21`'s
  neighbouring idempotence clause makes a reader expect and is stated so it is not mistaken for the latch.

**No `Enumerator` appears anywhere in 5c**, and no resource is acquired inside any block 5c yields from: the
only thing `with_span` acquires is three slot values, and it releases them in the `ensure` of the same method.

## `R14` — whether `OBS-29`'s lifecycle wiring ships here

**Decision: the vocabulary, its no-op defaults, `NULL`, the `CallableAdapter` and the ordering test ship in
5c. Nothing in phase 5 emits any of it. The checklist row for `OBS-29` is ✅ with the missing half named in
the row, and a deferral is proposed for the wiring.**

### What the requirement itself says, and what §8.1 says

`OBS-29` ends: "This is a documented emission contract; **pipeline/transport wiring to emit it is a follow-up,
so it is not yet runtime-enforced.**" §8.1 says the ordering "is asserted by an ordering test". The
requirement and the design agree that the deliverable is a contract plus a test, and both say so before any
port existed to argue about it.

### Why not wire the operation-lifecycle triple, which 5c *could* wire

The tempting middle answer is to wire the three callbacks that have an emitter today — `operation_started`,
`operation_succeeded`, `operation_failed` — from `5b`'s step, which drives exactly one operation, and leave
the per-attempt and transport halves for phases 6 and 8. **Rejected**, for three reasons.

1. **It requires a third slot on `5b`'s step**, and boundary 15 gives 5c two. Asking for a third is a change
   to another sub-phase's object, negotiated across a boundary neither design could see across while both
   were being written. **Confirmed at reconciliation from `5b`'s side**, with two reasons of `5b`'s own that
   are not restatements of these: the step's `#call` sees one operation and no attempts, so `OBS-29`'s
   exhausted→failed pairing is one this object structurally cannot honour; and an eleven-method emitter
   reached through a slot would sit outside `Instrumentation.contain` under `OBS-20`'s asymmetry, putting
   three throwing callbacks on the request path for three of eleven events. **No third slot, from both
   sides.**
2. **`OBS-29`'s ordering contract is not separable into a wired half and an unwired half.** Its own clauses
   couple them: "retries-exhausted (when it fires) is immediately followed by operationFailed with the same
   throwable". A step that cannot see attempts cannot honour that pairing, so wiring `operation_failed`
   without the attempt half ships a runtime that satisfies three clauses and structurally cannot satisfy the
   fourth — while a checklist row reads it as wired.
3. **Phase 6 is where all of it can be wired at once.** `DEF-39` targets `Pipeline.standard` at phase 6 as
   "the first phase in which all three families exist", and the retry step that supplies the per-attempt
   vocabulary is the same phase's. Wiring once, completely, is cheaper than wiring twice and auditing the
   seam.

### What ships, and what the row says

Ships: `Dexpace::Instrumentation::HTTPTracer` (a module of eleven no-op instance methods covering `OBS-28`'s
three groups), `NULL` (a frozen instance of a `private_constant` class that includes it and adds nothing),
`CallableAdapter` (§8.1's bus-shape adapter, offered so the `#call(name, payload)` shape is available without
being the default), and **the ordering test §8.1 names**, driven through a conformant emitter fake as
`OBS-29`'s own conformance clause prescribes ("drive a succeeding and a failing (retry-exhausted) operation
**through a conformant emitter** and assert the ordering and the exhausted→failed pairing").

The checklist row, written out here so the plan copies it rather than inventing it:

> `OBS-29` — ✅ **contract and ordering test only.** The eleven-method vocabulary, its no-op defaults and an
> ordering assertion over a conformant emitter fake ship in 5c. **Nothing in phase 5 emits any of it**: the
> per-attempt group has no emitter until phase 6's retry step and the transport-milestone group none until
> phase 8's adapters, which the requirement's own last sentence anticipates. Wiring is `DEF-42`, picked up
> with `DEF-39`'s `Pipeline.standard`. *Cites:* `OBS-28`, `OBS-29`, `DEF-39`, `DEF-42`, §8.1.

**The cost, stated rather than hidden.** An eleven-method public module with no core caller is `OI-8`'s shape
— `NFR-4`-locked surface that nothing exercises in production. Two things make it a different case, and
neither is "the requirement says so": the ordering test drives every one of the eleven through the fake, so
the module has a caller in the suite and its no-op defaults are asserted rather than assumed; and deferring
the vocabulary itself would hand phase 6 the job of inventing an event surface `OBS-28` already fixes, which
is `P11`'s failure — fixing an interface a later phase must be free to shape — arriving from the opposite
direction. What is genuinely at risk is that the eleven method *names* are locked by `NFR-4` before any
emitter exists to prove they are the right eleven, and that risk is real and is accepted.

## `R15` — whether `DEF-30`'s condition is met

**Decision: it is not met. `DEF-30` stays `deferred` and does not become UNSCHEDULED, and 5c records the
reading explicitly because the charter's sweep requires a phase that could have met a condition to say
whether it did.**

`DEF-30`'s condition: "an instrumentation seam exists to activate — phase 5 (Configuration and Observability)
at the earliest — and its first and only sanctioned user is `dexpace-instrumentation-otel` (see `DEF-17`),
which is post-v1."

**The argument, which is `SEAM-2`'s own enumeration.** `SEAM-2` (MUST) fixes what a core interface seam is and
lists them: "The enumerated core interface seams are: byte-stream provider, synchronous transport,
asynchronous transport, wire codec (serde), and operation-input->request projection." **Instrumentation is not
among them.** `DEF-30`'s subject is `SEAM-5`'s provider *resolution* — an explicitly installed provider wins,
otherwise the runtime auto-discovers from a registry, with loud failures at zero and at more than one — and
that whole mechanism presupposes a `Dexpace::Registry` instance.

**What 5c actually ships is not a seam in that sense.** The tracer factory is a member of a frozen `Data`
(`CTX-14`), populated by the caller through `Bundle.build`. The meter is a constructor keyword on `5b`'s step
with a constant default. Neither is registered, neither is discovered, neither has a resolution precedence
beyond "the value you passed, else the no-op constant", and there is no zero-provider or ambiguous-provider
case for `SEAM-5`'s error messages to describe. **Phase 2 added three registries, phase 4 added none, and 5c
adds none** — and phase 2's test asserting the auto-activation hook is absent stays green, untouched.

**What would reverse this, stated so the reversal is visible if it ever happens.** If any later phase ships a
`Dexpace::Registry` for a tracer, a meter or a sink, `DEF-30`'s condition is met at that moment and the row
becomes UNSCHEDULED with that phase named. 5c ships none, so the row's `Status` gains a dated line recording
that phase 5 read the condition and found it unmet — which is a register edit, and per the working-in-parallel
rule this document proposes it rather than making it.

**The one entry that reads the other way, and why it does not change the answer.**
`observability/68a9625c` records that `dexpace-instrumentation-otel` "is the one adapter permitted
presence-gated activation" (§3.6). That is a statement about a *post-v1 adapter gem*, not about core, and
`DEF-30`'s own text already carries it — "its first and only sanctioned user is `dexpace-instrumentation-otel`
… which is post-v1". The permission exists; the object it would attach to does not, and phase 5 does not build
it.

## Module layout

Every file 5c creates or modifies, under `gems/dexpace-core/`. `sig/` mirrors `lib/` one file per file and
ships inside the gem; `test/` mirrors `lib/` one file per file and does not ship.

```
lib/dexpace/instrumentation/tracing.rb           Dexpace::Instrumentation::Tracing
lib/dexpace/instrumentation/scope.rb             Dexpace::Instrumentation::Scope, ::NO_SCOPE
lib/dexpace/instrumentation/http_tracer.rb       Dexpace::Instrumentation::HTTPTracer, ::NULL
lib/dexpace/instrumentation/callable_adapter.rb  Dexpace::Instrumentation::CallableAdapter
lib/dexpace/instrumentation/meter.rb             Dexpace::Instrumentation::NO_METER

lib/dexpace/instrumentation/no_span.rb           MODIFIED: NO_SPAN's private class gains OBS-21's methods
lib/dexpace/instrumentation/no_tracer.rb         MODIFIED: NO_TRACER's private class gains OBS-25's methods
lib/dexpace/instrumentation/trace_id_flavour.rb  MODIFIED: OBS-27's #generate, and #sampled? on Bundle's side
lib/dexpace/instrumentation/bundle.rb            MODIFIED: #sampled? only — no member changes (boundary 10)
lib/dexpace.rb                                   MODIFIED: explicit requires for the six new files

test/support/recording_span.rb                   the fake recording span
test/support/recording_tracer.rb                 the fake tracer + factory, one tracer per operation
test/support/recording_meter.rb                  the fake meter, counter and histogram
test/support/recording_http_tracer.rb            the conformant emitter OBS-29's ordering test drives
```

**Five** new `lib/` files — the draft listed six, and `keys.rb` is gone with the two key constants it held —
five `sig/` mirrors and five `test/` mirrors; four already-existing `lib/` files that gain content, with
`sig/` mirrors updated for all four; four test-support files, three of which `5b`'s step tests also consume;
and the repository-root `test/fixtures/surface/dexpace-core.txt`.

**Every new constant sits under `Dexpace::Instrumentation::`**, which §8.1 and phase 4a both already
established, so phase 1's flat-constant rule (P1-1) is satisfied by the exception it already carries rather
than deviated from. **Every file uses the full `module Dexpace; module Instrumentation; …` nesting form**, never
the compact `module Dexpace::Instrumentation`, because `module-organization/64e84d64` and
`execution-context/b58728da` together make the compact form unable to resolve a bare reference to a
`private_constant` on `Dexpace` — and `NO_TRACER` and the three no-op instrument classes are exactly that.

**`tracing.rb` requires `5b`'s `lib/dexpace/instrumentation/diagnostics.rb`**, and that is the only file 5c
requires from the other segment. The draft carried its own `keys.rb` for the two diagnostic-context key names,
on the reasoning that "a file that can be required alone is what keeps the crossing contract from dragging the
whole segment behind it"; the constants moved to `5b` (`R11`) and the reasoning is honoured in mirror image —
`diagnostics.rb` requires nothing else in `5b` and defines no `Event`, so requiring it drags nothing and does
not break the load-time assertion in `R11`. It would also have **collided by path** with `5b`'s own
`instrumentation/keys.rb`, which holds `Keys` and `Events`.

## The object model 5c ships

Every public constant, its surface, and the IDs forcing that shape.

### `Dexpace::Instrumentation::Tracing` — `OBS-22`, `OBS-23`

A module of module functions; it owns no state beyond one `Fiber[]` slot and is therefore a module, not a
class (`data-modeling/b74a2869`).

- **`.current_span` → `_Span`** — reads the slot, returning `NO_SPAN` when unset so no caller ever sees `nil`
  (`api-design/6ea28c9c`). Allocation-free (verified fact 3).
- **`.activate(span) → _Scope`** — `OBS-22`'s literal requirement. Sets the slot, returns `NO_SCOPE` when
  `span.equal?` the current one and a fresh `Scope` otherwise (`R13`).
- **`.with_span(span) { |span| … }`** — the block form; `begin`/`ensure` around `.activate`.
- **`.correlate(span, bundle) → _Scope`** — `OBS-23`. For a **recording** span, pushes
  `Diagnostics::TRACE_ID` and `::SPAN_ID` — `5b`'s constants — from the bundle and returns a `Scope` carrying
  all three restores. For a **non-recording** span, skips the push and delegates to `.activate` — the
  requirement's own words.
- **`.with_correlated_span(span, bundle) { |span| … }`** — the block form of the above, and what `5b`'s **sync**
  step calls. `5b`'s `AsyncStep` cannot use a block form — the span outlives `#call` and the restore happens
  in the future's `#on_settle` callback — so it takes `.correlate` and closes the handle itself, which is the
  non-lexical case `P5-45` keeps the bare handle for. Both of `5b`'s steps call `.correlate` rather than
  `.activate`, because `OBS-23`'s non-recording branch already delegates to plain activation and a caller
  branching on the recording flag would be re-deriving that.

The current-span slot key is a `private_constant`; it is never part of the diagnostic context and must not be
folded, so it is deliberately *not* one of the two published key names and is named so it cannot collide with
an application's own (`:"dexpace.current_span"`).

**Why the bundle is a parameter rather than read from a context.** `OBS-23` says to push "the trace id and
span id"; `CTX-14` puts both on the bundle. Taking the bundle as an argument keeps `Tracing` free of any
`CTX` dependency, which is what lets 5c's suite load without the context tree and is what makes the
`OBS-34`-independence assertion above possible.

### `Dexpace::Instrumentation::Scope` and `::NO_SCOPE` — `OBS-22`, `OBS-25`

`Scope` is a plain class with three ivars (`prev_span`, `prev_trace_id`, `prev_span_id`) and one public
method, `#close`, restoring all three in one `ensure`-free body — the `ensure` belongs to the block form that
calls it. `#close` is idempotent by construction, `private_class_method :new` keeps construction inside
`Tracing`, and it is **not** a `Dexpace::Closeable` (`R13`).

`NO_SCOPE` is one frozen instance of a `private_constant` class whose `#close` is `nil`. It is **public**,
because `OBS-25`'s conformance clause asserts "the same singletons" and
`execution-context/b58728da` verified that a qualified reference to a `private_constant` raises even from
inside `Dexpace` — the same argument that made `NO_SPAN` public in 4a.

### The two diagnostic-context key names — `5b`'s, and not shipped here

`Dexpace::Instrumentation::Diagnostics::TRACE_ID` and `::SPAN_ID`, `Symbol`s, declared by `5b` beside
`OBS-10`'s `DEFAULT_KEYS`. **5c ships no key-name constant** and reads these two from `Tracing.correlate`
(`R11`, reversing this document's draft).

### `NO_SPAN`'s class, widened — `OBS-21`, `OBS-25`

4a's `private_constant` class gains `OBS-21`'s surface. The object keeps the identity 4a published; the class
is not `NFR-4`-locked, which is precisely what `DEF-37`'s pick-up condition reserved.

| Method | Behaviour | ID |
|---|---|---|
| `#recording?` | `false` | `OBS-21` |
| `#set_attribute(key, value)` | returns `self`, drops the data | `OBS-21` |
| `#add_event(name, attributes: nil)` | returns `self` | `OBS-21`, `OBS-28` |
| `#record_error(error, attributes: nil)` | returns `self` | `OBS-21` |
| `#status=(status)` | returns the argument, drops it | `OBS-21` |
| `#finish(end_timestamp: nil)` | `nil`, idempotent | `OBS-21` |
| `#context` | `Bundle::NONE` | `OBS-25`, `CTX-15` |

Every attributes parameter is a **named optional keyword**, never `**attributes` (verified fact 1, `P5-42`).
`#finish` rather than `#end`, on the ecosystem-compatibility argument alone: `opentelemetry-api` spells it
`finish`. **`def end` is *not* a syntax error** — checked, because the assumption that it is would be the
obvious reason to pick `finish` and it is wrong; `end` is a legal method name and `span.end` parses. So the
choice rests entirely on `P4-8`'s structural-subset argument and would be reversible on it, which question 3
of the plan's open questions confirms against the gem.

### `NO_TRACER`'s class, widened — `OBS-25`, `OBS-29`

4a's `private_constant` class gains `#start_span(name, attributes: nil, kind: nil, with_parent: nil)`
returning `NO_SPAN`, and `#in_span(name, attributes: nil, kind: nil) { |span| }` yielding it. Both return the
published singleton, so `OBS-25`'s "a no-op Tracer returning a shared no-op Span" is a reference-identity
claim, and both allocate nothing (verified fact 1: a four-keyword signature called with one positional
argument is 1 / 1000).

**`OBS-29`'s 1:1 clause against 4a's shared `NO_TRACER`, reconciled rather than ignored.** `OBS-29` requires
"One tracer instance corresponds 1:1 to a single logical operation lifecycle (created by the factory per
operation)", and `NO_TRACER_FACTORY#tracer` returns **the same object every time** — a shape 4a fixed and
boundary 10 forbids changing. The two are consistent because the 1:1 correspondence is a constraint on
*state*: a tracer that accumulates anything per operation must not be shared, and a stateless no-op has
nothing to correspond. The obligation is therefore restated where it can bind — in `_Tracer`'s YARD, as an
implementer contract — and asserted in the suite against `RecordingTracer`, whose factory returns a fresh
instance per call and whose test would fail if it did not (`P5-43`).

### `TraceIdFlavour`, widened — `OBS-27`

Two methods added to 4a's frozen `Data`; no member is added, renamed or removed (boundary 10).

- **`#generate_trace_id → String`** — `W3C`: `SecureRandom.hex(16)`, 32 lowercase hex. `DATADOG`: a 64-bit
  unsigned integer rendered decimal. `NONE`: `invalid_trace_id`, always. Each result is frozen.
- **The zero-draw coercion is unconditional and per-flavour**, because the sentinel is (`P4-7`): a `W3C`
  draw equal to 32 hex zeros is redrawn, and a `DATADOG` draw of `0` is coerced to a non-zero value. It is
  written as a check, not as a range that cannot produce zero, because `OBS-27`'s words are "a zero draw MUST
  be coerced to a non-zero value" and a test can only drive it through an injected generator.
- **`NONE#generate_trace_id` returns the sentinel and is not an error**, which `OBS-27` states directly ("a
  no-op flavour that always yields the invalid sentinel").

**No span-id generator ships** (`P5-44`): `OBS-27`'s scope is trace ids, `OBS-26` states the span-id rule as a
*validity* rule that 4a's pattern already enforces at `Bundle.build`, and core creates no spans.

**Randomness source.** `SecureRandom`, which is on phase 0's require allowlist, is not in
`Gem::BUNDLED_GEMS::SINCE` and does not load `openssl` (verified fact 6). This is not a reversal of boundary
8: that boundary forbids implementing **`CFG-32`** as `SecureRandom.uuid`, and `OBS-27` carries no
non-cryptographic constraint. 5c does **not** reach for `5a`'s `Dexpace::UUID` generator, which would make 5c
depend on 5a for no gain and would put a `Thread.current[]`-memoised PRNG on a path that has no per-thread
requirement.

### `Bundle#sampled?` — `OBS-26`

One predicate over the existing `trace_flags` member: the sampled bit is the low bit of the two-hex-char
byte. 4a explicitly reserved it — "A `#sampled?` predicate is *not* shipped … **Phase 5 may add it**" — and
adding a method widens, which `NFR-4` permits. No member changes.

### `Dexpace::Instrumentation::HTTPTracer` and `::NULL` — `OBS-28`, `OBS-29`

A **module** of eleven no-op instance methods, included by an implementer who overrides only what it needs —
which is `OBS-28`'s "Every event method SHOULD default to a no-op so adding a new event is a non-breaking
change" implemented as a mechanism rather than as a docstring. A module rather than a base class because Ruby
has single inheritance and an implementer may already have a superclass; a module rather than a bare duck type
because a duck type gives no defaults and `OBS-30`'s no-wrapping rule means a missing method is a
`NoMethodError` in the caller's request path.

| Group | Methods | Emitter |
|---|---|---|
| operation | `#operation_started(context)`, `#operation_succeeded(context, response)`, `#operation_failed(context, error)` | none in phase 5 |
| per-attempt | `#attempt_started(context, attempt)`, `#attempt_failed(context, error, next_delay)`, `#retries_exhausted(context, error)` | phase 6 |
| transport | `#request_url_resolved(context, url)`, `#connection_acquired(context, host, port)`, `#request_sent(context, byte_count)`, `#response_headers_received(context, status, headers)`, `#response_received(context, byte_count)` | phase 8 |

`NULL` is one frozen instance of a `private_constant` class that includes the module and adds nothing. It is
public because §8.1 names it, and it is the value an unconfigured slot holds.

`CallableAdapter` wraps a `#call(name, payload)` object and forwards each of the eleven, so §8.1's "the bus
shape is available without being the default" is a shipped object rather than a promise. It **allocates a
payload `Hash` per event by construction** — that is what the bus shape costs, it is why it is not the default,
and its YARD says so rather than leaving a reader to discover it.

**Nothing in core instantiates or installs any of this in phase 5** (`R14`).

### `Dexpace::Instrumentation::NO_METER` — `OBS-31`, `OBS-33`

One frozen instance of a `private_constant` class with two methods:

- **`#create_counter(name, unit: nil, description: nil)`** → one shared frozen no-op counter, whose
  `#add(amount, attributes: nil)` returns `nil`.
- **`#create_histogram(name, unit: nil, description: nil)`** → one shared frozen no-op histogram, whose
  `#record(amount, attributes: nil)` returns `nil` for every input including `Float::NAN` and `±Infinity`
  (verified fact 8).

**The instrument singletons are `private_constant`s and `NO_METER` is public.** `OBS-31`'s "returns shared
instrument singletons" is a reference-identity claim, and it is assertable **meter-to-meter** —
`assert_same NO_METER.create_counter("a"), NO_METER.create_counter("b")` — without naming the instruments,
so `execution-context/b58728da`'s qualified-reference argument does not force them public and
`api-design/b0e18938`'s minimal-surface rule keeps them private. That is the asymmetry with `NO_SPAN`, which
*is* public because `Bundle::NONE.span` must be asserted against a qualified name; the difference has a
reason and is not an inconsistency.

**No validation on the hot path** (`OBS-33`): `#add` does not check the sign of its argument and `#record`
does not check finiteness. The "MUST document" half is discharged in the YARD block on `_Counter#add`, which
is the only place a documentation requirement can bind in a duck-typed SPI.

**`OBS-32` is not implemented** (`DEF-9`): no instrument name, unit or attribute set is fixed by 5c, and
`http.client.request.count` and `http.client.request.duration` appear nowhere in `lib/`. That matters
concretely — `OBS-34` says metric recording runs on every request, so `5b`'s step must name its two
instruments, and it does so from its own constants until `dexpace-instrumentation-otel` lands. **Pending
reconciliation with 5b**: 5c's assumption is that the two instrument names are `5b`'s to declare because
`5b` owns the step that creates them, and 5c declares neither.

### The RBS interfaces

Three widened, four new, all under `Dexpace::`. Declaring them as `interface` rather than typing parameters
`untyped` is what keeps `NFR-11` mechanical: no constant outside `Dexpace::` and the fixed stdlib allowlist
appears in any public signature.

```
interface _Span                                   # widened from 4a's empty declaration
  def recording?: () -> bool
  def set_attribute: (String key, untyped value) -> self
  def add_event: (String name, ?attributes: Hash[String, untyped]?) -> self
  def record_error: (Exception error, ?attributes: Hash[String, untyped]?) -> self
  def finish: (?end_timestamp: Time?) -> void
end

interface _Tracer                                 # widened from 4a's empty declaration
  def start_span: (String name, ?attributes: Hash[String, untyped]?, ?kind: Symbol?) -> _Span
  def in_span: [T] (String name, ?attributes: Hash[String, untyped]?) { (_Span) -> T } -> T
end

interface _TracerFactory                          # unchanged from 4a
  def tracer: (?String? name, ?String? version) -> _Tracer
end

interface _Scope
  def close: () -> void
end

interface _Meter                                  # 5c's; 5b's empty declaration was deleted at reconciliation
  def create_counter: (String name, ?unit: String?, ?description: String?) -> _Counter
  def create_histogram: (String name, ?unit: String?, ?description: String?) -> _Histogram
end

interface _Counter
  def add: (Integer amount, ?attributes: Hash[String, untyped]?) -> void
end

interface _Histogram
  def record: (Numeric amount, ?attributes: Hash[String, untyped]?) -> void
end
```

`_HTTPTracer` is deliberately **not** declared: eleven methods with no core caller would be eleven
`NFR-4`-locked signatures asserting a shape nothing checks, and `HTTPTracer` is a **module** an implementer
includes, so the module's own definition is the contract and `rbs validate` reads it from `sig/`'s class
declaration. If phase 6 wires the vocabulary, the interface arrives with the wiring.

**`interface _Meter` is declared once, here.** `5b`'s draft declared it **empty**, borrowing phase 4a's device
of stating a deferral in the type system rather than in a comment, and its step types `meter:` against it.
That device was right for 4a, whose populating phase was a *different* phase held open by `DEF-37`; here the
populating segment is in the same phase, so an empty declaration would be widened before it was ever released
— and two declarations of one interface name is an **`rbs validate` failure**, not a merge conflict. 5c's
filled declaration is the one that ships and `5b`'s was deleted; `_Counter` and `_Histogram` are 5c's for the
same reason, and `5b`'s step types its instruments against all three.

`untyped` appears once, as an attribute *value*: `OBS-31` says "key/value attributes" and fixes nothing about
the value type, and narrowing it here would be this document inventing a constraint the requirement does not
carry.

## The spec-forced boundaries, honoured

Six of the charter's fifteen bind 5c; each is honoured by a named mechanism rather than by intent.

1. **The bundled-gem rule (boundary 1).** 5c requires `securerandom`, which is allowlisted and which
   `Gem::BUNDLED_GEMS::SINCE` does not name (verified fact 6), and nothing else. It writes no
   `require "logger"` anywhere in `lib/` or `test/`, which matters because the require scan reads text and
   resolves relative targets.
2. **`OBS-20`'s asymmetry (boundary 3).** **5c wraps nothing.** No `rescue` appears on any tracer or meter
   call path in `lib/`, and the suite asserts the negative directly: a throwing fake tracer passed through
   `Tracing.with_span` **propagates**, which is `OBS-20`'s own conformance clause ("separately assert a
   throwing tracer/meter is NOT caught by the step"). `5b` may not stop wrapping and 5c may not start.
3. **Phase 4a's five-clause handshake (boundary 10).** 5c adds methods to the two `private_constant` classes
   and to `TraceIdFlavour` and `Bundle`; it introduces no second no-op span or tracer, replaces neither
   published singleton, renames and removes no member, **adds** no member, leaves `#valid?` derived, leaves
   `TraceIdFlavour` a `Data`, and gives `Bundle` no second `NONE`. `DEF-37` closes.
4. **`OBS-26`'s reserved sentinels are already values in core and are not re-chosen (boundary 11).** 5c
   implements `OBS-27`'s generation over `TraceIdFlavour::W3C` and `::DATADOG` and alters `::NONE`'s sentinel
   not at all.
5. **`OBS-25`'s no-allocation clause is asserted by reference identity from a qualified constant (boundary
   12).** `NO_SPAN` and `NO_TRACER_FACTORY` stay public, and `NO_SCOPE` joins them for the same reason and
   with the same argument. The `dexpace-conformance` suite that will restate it is phase 8's.
6. **`Fiber[:key]` is the diagnostic-context carrier and `CTX`'s store is not it (boundary 14).** 5c writes
   `Fiber[]` for two diagnostic keys and one private current-span slot, writes `Thread.current[]` nowhere, and
   writes `Dexpace::ContextStore` nowhere.

Boundary 15 — the charter's own charter decision about the step — is `R11`, resolved above.

## Cross-cutting constraints that bite 5c specifically

1. **`OBS-30`'s no-wrapping rule makes every defect in this segment a caller-visible failure.** There is no
   safety net anywhere in 5c: a `NoMethodError` from an incomplete tracer, a `TypeError` from a bad key, a
   `FrozenError` from a mutation attempt all reach the caller's request. That is the specification's choice
   and the port preserves it (§10 item 4's neighbours; `observability/0ea8a5ee`), and the consequence is that
   5c's own totality — `.current_span` never returning `nil`, `NULL` defining all eleven methods, `#finish`
   accepting a second call — is load-bearing rather than defensive.
2. **`XCUT-20`'s "observability code paths MUST NEVER throw into the caller's request path" sits directly
   against constraint 1, and the resolution is `OBS-20`'s own wording.** `XCUT-20` is phase 9's audit and it
   generalises `OBS-15`'s totality; `OBS-20` carves tracer and meter calls out of it explicitly. 5c satisfies
   `XCUT-20` for everything it *owns* — no method 5c writes can raise on any input — and does not extend the
   guarantee to a foreign callback, which `OBS-20` forbids it from doing. Phase 9 audits the claim, and this
   sentence is what it should read.
3. **`XCUT-11`'s shared-instance safety is the audit every object here is subject to.** `NO_SPAN`,
   `NO_TRACER`, `NO_TRACER_FACTORY`, `NO_SCOPE`, `NULL`, `NO_METER` and the two instruments are frozen and
   hold no state, so per-call state lives where `XCUT-11` requires it — on the call's own stack, in `Scope`'s
   ivars. Verified fact 7 is what makes the assertion an identity test across threads rather than a stress
   test.
4. **`Fiber[]`'s inheritance is the property wanted here and the hazard in the neighbouring subsystem.** A
   span activated before `Thread.new` is current inside the thread, which is what `OBS-23`'s correlation is
   for; `5a`'s `P5-13` reached the opposite conclusion for a PRNG, where inheritance means a shared generator.
   Both are right and the difference is whether the slot holds an immutable value (verified fact 2). 5c's
   slots hold frozen `String`s and one immutable span reference.
5. **An `Enumerator` abandoned mid-`#next` never runs its `ensure`.** No `Enumerator` appears in 5c and no
   resource is acquired inside any block it yields from (`R13`).
6. **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden.** 5c reaches for none: it starts no
   thread, takes no lock and performs no wait. Stated because it is unusual for a phase-5 segment, not
   because it was in doubt.
7. **`Metrics/ParameterLists` counts keyword arguments (`OI-20`).** `_Tracer#start_span`'s four-parameter
   signature is at the `Max: 4` boundary and `NO_TRACER`'s implementation of it is exactly four; if the plan
   confirms `opentelemetry-api` carries `links:` and `start_timestamp:` as well, the method trips the cop and
   is paid with a named inline disable, which is phase 0's convention for a directive and `OI-20`'s recorded
   treatment. Not a `.rubocop.yml` change (`OI-6`).
8. **`Ractor` is never load-bearing.** Every singleton here is deep-frozen and therefore shareable as a free
   side effect, and no claim is made for it. `Scope` holds a foreign span reference and is not shareable; that
   is a non-claim, not a gap.

## Testing strategy

`test/` mirrors `lib/` one file per file; each file's header comment names the requirement IDs it exercises,
and a non-obvious branch names the ID that forced it. Every suite subclasses `DexpaceTestCase`, so a warning
raised by code under test fails the test that triggered it — which is what would catch a stray
`Fiber#storage=` in 5c's own code before `OI-13` ever became relevant.

**No transport, no socket, no stream, no configuration, no logger.** 5c's suite requires only the
`Dexpace::Instrumentation` tree, and **that is itself an assertion** (`R11`): a reference to `5b`'s event
object or `5a`'s chain from any 5c file raises `NameError` at load rather than passing quietly.

**Every suite that touches `Fiber[]` restores its slots in `teardown`**, unconditionally, including on
failure. `testing/4ef070df` requires every test to run alone in any order, and a test that leaves a current
span or a `trace.id` set poisons every later test in the same fiber — a failure mode that is order-dependent
and therefore does not reproduce.

**Four doubles, and all four are fakes** (`testing/7ecef8e8`, `/630ba094`), under
`gems/dexpace-core/test/support/`, each required explicitly by the suites that use it (phase 2's precedent).

- **`RecordingSpan`** — a real in-memory `_Span` with `#recording? == true`, recording attributes, events and
  errors into arrays and latching `#finish`. This is what every `OBS-21` recording-branch assertion and every
  `OBS-22` nesting assertion runs against, because core ships no recording span (`P5-48`).
- **`RecordingTracer`** and its factory — the factory returns a **fresh** tracer per `#tracer` call, which is
  `OBS-29`'s 1:1 clause made testable (`P5-43`).
- **`RecordingMeter`** — records `(name, unit, amount, attributes)` tuples, and returns a fresh instrument per
  `#create_counter`/`#create_histogram` call, so the *no-op*'s shared-singleton property is asserted against a
  fake that deliberately does not have it.
- **`RecordingHTTPTracer`** — `OBS-29`'s "conformant emitter": includes `HTTPTracer`, overrides all eleven,
  appends a symbol per callback to one array. The ordering test drives a succeeding operation and a
  retry-exhausted failing operation through it by hand and asserts the sequence.

### The tests a reader would otherwise write wrong

- **`OBS-25`'s allocation test measures the caller unless its arguments cannot allocate, and the file's magic
  comment is not what saves it.** The charter's verified fact 6 established the hazard for `5b`'s inert event
  and it is identical here: a bare `"op"` `String` literal in the loop body allocates one object per iteration
  and fails a correct implementation. Every file in this repository carries `# frozen_string_literal: true` by
  rule, so the in-gem test is safe — but `OBS-25`'s conformance clause is one `dexpace-conformance` will
  restate in a **different gem** (phase 8, `DEF-22`), where the comment may not survive the copy.
  **`5b`'s `R8` corrects the charter's proposed remedy and 5c adopts the correction**: a *delta of two loops*
  does **not** make the assertion insensitive to the caller — it isolates the caller's per-iteration cost,
  which is exactly what a per-iteration `String` allocation is (measured: 999 per 1000 iterations without the
  comment, 0 with it). What buys the insensitivity is **passing arguments that cannot allocate** — a frozen
  constant `String`, a `Symbol`, an `Integer`, `nil` — which is the half of the charter's first candidate that
  works. So the loop passes only frozen constants **and** the measurement is the two-loop delta, the second
  for the different reason that it cancels interpreter warm-up so the assertion needs no fudge factor. The
  precondition is stated in a comment the later gem is meant to copy, and that comment says the argument types
  are what make the test portable and the magic comment is a repository rule rather than this test's
  precondition.
- **`OBS-25`'s identity half is the assertion, and it must be `assert_same` on a qualified constant.**
  `assert_equal` passes against a freshly allocated no-op span with a generated `==`, which is exactly the
  implementation the requirement forbids. `assert_same Dexpace::Instrumentation::NO_SPAN, tracer.start_span("x")`.
- **`OBS-22`'s nesting test must use two *distinct* spans and assert by identity.** Two `RecordingSpan`
  instances, `assert_same` on `Tracing.current_span` at each level. A test written with one span passes under
  an implementation that never restores anything, because the value it reads back is the value it expects for
  the wrong reason.
- **`OBS-22`'s throw case must assert the slot, not the exception.** `assert_raises` around the block proves
  nothing about restoration; the assertion after the `assert_raises` is `assert_same outer, Tracing.current_span`.
- **`OBS-23`'s restore test must distinguish "absent" from "present and nil", and the way to do that is
  `Fiber.current.storage.key?`, not `Fiber[]`.** `Fiber[Diagnostics::TRACE_ID]` returns `nil` in both cases (verified
  fact 4). The test sets no prior key, activates, asserts the two keys present *inside*, closes, and asserts
  `Fiber.current.storage.key?(:"trace.id")` is **false** — which is the "or remove it if previously unset"
  half and is invisible to a test written on `assert_nil`.
- **`OBS-23`'s non-recording branch is a negative and needs the positive beside it.** Activate a
  `RecordingSpan` and assert both keys appear; activate `NO_SPAN` and assert neither does **and** that
  `Tracing.current_span` still changed — the "delegates to plain current-span activation" half, which a test
  asserting only the absence of the keys would pass with an implementation that does nothing at all.
- **`OBS-21`'s "no duplicate export" cannot be asserted against `NO_SPAN`**, which exports nothing whether
  called once or twice. The assertion is against `RecordingSpan`: `#finish` twice, one entry in its
  `finished_at` array. Writing it against the no-op is the test that passes for every implementation.
- **`OBS-27`'s generation test must assert the *format* over many draws and the *coercion* over an injected
  zero.** `1000` draws asserted `=~ /\A[0-9a-f]{32}\z/` and never equal to the sentinel is the format half;
  the coercion half is unreachable by sampling and is driven by injecting a generator that returns zero, which
  is why `#generate_trace_id` takes its randomness source as an optional argument with a real default rather
  than calling `SecureRandom` inline.
- **`OBS-30`'s concurrency assertion is an identity test across threads, not a stress test.**
  `16.times.map { Thread.new { NO_TRACER_FACTORY.tracer } }.map(&:value)` and `assert_equal 1, results.uniq.size`
  — 4a's precedent, and it asserts the property (`CTX-20`'s "safe to invoke concurrently") rather than the
  absence of a race, which no test can show.
- **`OBS-30`'s must-not-throw assertion is the *opposite* of what the sentence sounds like.** The runtime does
  not catch, so the test asserts that a throwing fake tracer **propagates** out of `Tracing.with_span` — and
  that the current-span slot is nonetheless restored, because the restore is in an `ensure` and the exception
  is not the scope's fault.
- **`OBS-33`'s "tolerate any input" is not `assert_nothing_raised`**, which `testing/26b866e1` forbids. Each of
  `Float::NAN`, `Float::INFINITY`, `-Float::INFINITY`, `0` and `-1` asserts `assert_nil` on the return value,
  which is the stronger claim a discarding instrument actually makes.
- **`OBS-31`'s shared-instrument assertion must compare instruments obtained under *different names***, or it
  proves memoisation rather than sharing: `assert_same NO_METER.create_counter("a"), NO_METER.create_counter("b")`.
- **`OBS-29`'s ordering test must drive both operations**, succeeding and retry-exhausted, and must assert the
  exhausted→failed **adjacency** and the **same throwable** (`assert_same` on the error object), not merely
  that both fired. The pairing is the clause a naive test omits.

## The interface surface later phases may cite

**The load-bearing statement is a negative one, and it is the charter's.** `5a` and `5b` are not obliged to
consume any of this, and a `5b` plan whose first task waits on 5c has re-imposed a chain that does not exist.
What 5c ships as a stable contract:

| Consumer | What it gets, and when |
|---|---|
| **`5b`**, on `OBS-10` | Nothing 5c declares: the key constants are `5b`'s `Diagnostics::TRACE_ID` and `::SPAN_ID`, `Symbol`s, and 5c reads them (`R11`). What 5c supplies is the **fact**: `Fiber.current.storage` returns `Symbol` keys and a fresh unfrozen `Hash` per read, so convert with `Symbol#name`, never `Symbol#to_s` (verified fact 3), and `:"trace.id".name` is not `equal?` to a `"trace.id"` frozen literal |
| **`5b`**, on `OBS-34`'s step | `NO_TRACER_FACTORY` (4a's) as the `tracer_factory:` default and `NO_METER` as the `meter:` default, both constants, neither a configuration read. Precedence: the context's bundle when it is not `Bundle::NONE`, else the keyword, else the constant (`R11`) |
| **`5b`**, on `OBS-34`'s independence clause | `Tracing.with_correlated_span`, `Tracing.correlate` and `NO_METER`'s instruments read no log level and hold no sink, by construction and by a load-time assertion in 5c's own suite. **That assertion does not discharge `OBS-34`'s conformance clause** — the `5b` step test at level `none` does; the two are named as two (`R11`) |
| **`5b`**, on `OBS-24` | Nothing binding: `5b` owns the decision and reached the same answer, `P5-23`. 5c's contribution is the measurement `5b` need not re-derive — `Fiber.current.storage` already returns a fresh unfrozen `Hash`, so the snapshot's immutability is one `freeze` — and `P5-49`'s gap, which `5b`'s union restore inherits (`R12`) |
| **`5b`**, on `OBS-32` | Nothing. 5c fixes no instrument name, unit or attribute set; `5b` declares `Keys::INSTRUMENT_REQUEST_COUNT` and `::INSTRUMENT_REQUEST_DURATION` for the step's two instruments, and `OBS-32`'s units, descriptions and attribute sets stay ⏳ `DEF-9` until `dexpace-instrumentation-otel` lands (`R11`) |
| **`5b`**, on `OBS-31` | `interface _Meter`, `_Counter` and `_Histogram`, declared **filled**, here and only here — `5b`'s empty `_Meter` was deleted at reconciliation because two declarations of one interface name is an `rbs validate` failure. `5b`'s `meter:` types as `Dexpace::_Meter` |
| **`5b`**, on test doubles | `RecordingTracer`, `RecordingSpan` and `RecordingMeter` under `test/support/`, 5c's files (`P5-48`). `5b`'s step tests consume them and add no second set; the method names in them are 5c's |
| **Phase 6**, on `OBS-28`/`OBS-29` | `HTTPTracer` with its eleven no-op methods, `NULL`, `CallableAdapter`, and the ordering contract. Phase 6 wires the operation and per-attempt groups with `DEF-39`'s `Pipeline.standard`; it does not redefine the vocabulary (`R14`) |
| **Phase 6**, on `RETRY`'s events | `#attempt_started`, `#attempt_failed(context, error, next_delay)` and `#retries_exhausted` are the three names the retry step emits, and `OBS-29`'s adjacency clause — retries-exhausted immediately followed by `operation_failed` **with the same throwable** — is a constraint on the retry step, not on the vocabulary |
| **Phase 8**, on `TRANSPORT`'s milestones | The five transport methods, with their argument lists fixed here: host and port on `#connection_acquired`, byte counts on `#request_sent` and `#response_received`, status and headers on `#response_headers_received` |
| **Phase 8**, on `ASYNC-8`–`ASYNC-12` | The finding that a key present with a `nil` value is turned absent by a per-key restore (`P5-49`), and that `Fiber#storage=` — which a whole-map restore may have no way to avoid — **rejects a `String` key**, which is why the two key names are `Symbol`s. The names themselves are `5b`'s. `dexpace-async-thread`'s save/install/restore is the other place that matters |
| **Phase 8**, on `dexpace-conformance` (`DEF-22`) | `OBS-25`'s allocation assertion, and `5b`'s `R8` finding it must be written under: **what makes such an assertion caller-insensitive is passing arguments that cannot allocate**, not the file's `frozen_string_literal` comment and not a two-loop delta, which isolates the caller's per-iteration cost rather than hiding it. `OBS-21`'s idempotence assertion needs a recording span the conformance gem must supply |
| **Post-v1**, `dexpace-instrumentation-otel` (`DEF-17`) | `_Span`, `_Tracer`, `_TracerFactory`, `_Meter`, `_Counter`, `_Histogram` as the six protocols to satisfy, and `OBS-32`'s names and units as its own work |
| **Phase 9**, on `XCUT-11` | Seven frozen stateless singletons as the audited shared instances, and `Scope` as the object that deliberately holds per-call state on the call's own stack |
| **Phase 9**, on `XCUT-20` | The scoped claim: 5c satisfies it for everything it owns and does not extend it to a foreign callback, which `OBS-20` forbids |

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`. **Numbering starts at `P5-40`
and is deliberately not contiguous with `5a`'s.** `5a` consumed `P5-1`–`P5-15`; the block `P5-16`–`P5-39` is
reserved for `5b`, which was being written concurrently in the same working tree and could not be read from
here. Reserving a block is what keeps two designs from claiming one number; the gap is the visible cost and it
is preferred to a collision.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P5-40 | Public constants design §8.1 does not name: `Dexpace::Instrumentation::Tracing`, `::Scope`, `::NO_SCOPE`, `::HTTPTracer`, `::NO_METER`; and the RBS interfaces `_Scope`, `_Meter`, `_Counter`, `_Histogram`. **`NULL` and `CallableAdapter` are §8.1's own names and are not deviations** | `NFR-4`; `api-design/b0e18938`; phase 2's P2-11, phase 4a's P4-2 and phase 5a's P5-1 precedent | §8.1 names exactly two Ruby identifiers for this segment — `Dexpace::Instrumentation::NULL` at §8.1 line 10 and `CallableAdapter` at line 13 — verified by grepping the tracked `docs/` tree and re-verified at reconciliation. `NFR-4` locks every public name at the first release tag, so a name arriving by accident is locked by accident. Each is chosen for a stated reason in the object-model section. **`::TRACE_ID_KEY` and `::SPAN_ID_KEY` were in the draft's list and are not shipped**: the two key constants are `5b`'s (`R11`) |
| P5-41 | Public **methods** design §8.1 does not name: `Tracing.current_span`, `.activate`, `.with_span`, `.correlate`, `.with_correlated_span`; `Scope#close`; `TraceIdFlavour#generate_trace_id`; `Bundle#sampled?`; the seven methods on `NO_SPAN`'s class and the two on `NO_TRACER`'s; `HTTPTracer`'s eleven; `NO_METER#create_counter`/`#create_histogram` and the instruments' `#add`/`#record` | `NFR-4`; phase 2's P2-11, phase 4a's P4-11, phase 5a's P5-2 | `NFR-4` locks a public *signature*, not only a name. Two deserve naming here. **`Tracing.activate` has no core caller** — `5b`'s sync step takes the block form and its async step takes `correlate`'s handle — and is public because `OBS-22`'s words are "return a scope handle" and its conformance test nests two by hand; the block forms are implemented in terms of it, so there is one code path rather than two. **`Bundle#sampled?` has no core caller either** and is added because 4a explicitly reserved it for phase 5 and because a two-hex-char byte whose low bit nobody can read is a member with no reader |
| P5-42 | **No method in this segment takes a `**` keyword splat.** Every attributes parameter is one named optional keyword carrying a frozen `Hash`, against the shape every Ruby tracing and metrics library uses | `OBS-25` ("Selecting a no-op path MUST NOT allocate per call"); `api-design/1d9e6e0b`; verified fact 1 | Measured on 3.4.10: `def m(x, **attributes)` allocates one `Hash` per call **even with no keyword argument passed** (1002 / 1000), and a forwarding wrapper doubles it; the named form allocates nothing. `OBS-25` is a MUST and the splat makes it unsatisfiable. Recorded as a deviation rather than as a style note because the splat is what an implementer copying `opentelemetry-api` will write, `api-design/1d9e6e0b` reads as licensing it, and **nothing mechanised catches it** — an open item is proposed for that |
| P5-43 | `OBS-29`'s "One tracer instance corresponds 1:1 to a single logical operation lifecycle" is read as binding **stateful** tracers only; `NO_TRACER_FACTORY#tracer` returns one shared object on every call | `OBS-29`, `OBS-25`, `CTX-20`; phase 4a's fixed shape and boundary 10 | The two MUSTs are in literal conflict: `OBS-25` requires the no-op factory to return a shared no-op tracer and to allocate nothing per call, and `OBS-29` requires one tracer per operation. They are consistent only if the 1:1 clause is about per-operation *state*, which a stateless no-op has none of. 4a fixed the shared return and boundary 10 forbids changing it, so the obligation is restated where it can bind — `_Tracer`'s YARD as an implementer contract — and asserted against `RecordingTracer`, whose factory returns a fresh instance per call |
| P5-44 | **No span-id generator ships.** `OBS-27`'s generation is implemented for trace ids only | `OBS-26`, `OBS-27`; `OI-8`'s shape; phase 4a's P4-7 | `OBS-27`'s scope is "Trace-id generation" and `OBS-26` states the span-id rule as a *validity* rule, which 4a's span-id pattern already enforces at `Bundle.build`. Core creates no spans, so a generator would be `NFR-4`-locked public surface with no caller — `OI-8`'s exact shape. An adapter that creates spans generates its own span ids, which is what every tracing runtime already does |
| P5-45 | `OBS-22`'s scope handle is exposed **block-form-first**, and the bare handle is the secondary form | `OBS-22` ("closeable from a try/using construct"); `resource-management/bf5560dc`; `CLAUDE.md`'s abandoned-`Enumerator` rule | Ruby's `ensure` is the try/using construct and a block is how a library hands it to a caller. The bare handle exists because the requirement's words are "return a scope handle" and because a consumer spanning a non-lexical region needs one — and reconciliation found that core has such a consumer: `5b`'s `AsyncStep` activates before `cursor.call` and closes in the future's `#on_settle` callback, two stacks apart, which no block form can express. The block form is implemented in terms of `activate`, so there is one restore path rather than two whichever form a caller takes; the draft said core never calls `#close` directly, and that is now true only of the **sync** path. `Scope` is **not** a `Dexpace::Closeable`: `XCUT-13`'s latch is about owned resources and a scope owns nothing |
| P5-46 | `Scope` is a plain class with three ivars, not a `Data` — the one place in this repository where the domain-model construction pattern is deliberately not applied | `docs/sdk-design-ruby/04-domain-model-construction.md`; `data-modeling/3e37c086`; `OBS-25`; verified fact 5 | `Scope` is a per-call resource handle, not a value: it has no meaningful `==`, its generated `#hash` would be nonsense, frozen-on-construction buys it nothing, and it costs two allocations as a `Data` against one as a plain object (measured). `data-modeling/3e37c086` puts state-owning behaviour in a class. Recorded because §4's opening sentence is "Every core model follows one shape" and a reader is entitled to know why this one does not |
| P5-47 | `NO_SCOPE` is returned on an **identity** test — the span being activated is `equal?` to the current one — and not on the span's recording flag | `OBS-22`, `OBS-25` | The recording-flag reading is the obvious one and it is wrong: a non-recording span activated on top of a recording one still owes a restore, and `OBS-23` requires that case to exist ("activation MUST delegate to plain current-span activation"). Returning the cached singleton there would leave the recording span un-restored, which is `OBS-22`'s exact failure. The identity test returns the singleton in every case the flag test would, plus one it misses, and never in the case that breaks — and in an untraced application it is true on every activation, which is what `OBS-25`'s clause is about |
| P5-48 | Core ships **no recording span, no recording tracer and no recording meter**; every recording-branch clause of `OBS-21`, `OBS-29`, `OBS-30` and `OBS-31` is asserted against a fake under `test/support/` | `OBS-21`, `OBS-29`, `OBS-30`, `OBS-31`; `SEAM-2`; phase 5a's `FakeClock` precedent | Core owns no exporter and no metrics runtime — `OBS-31` forbids the second in as many words — so a recording implementation would be a second, unused runtime beside the no-ops, with an export path nothing consumes. The clauses are obligations on an implementer and are stated in each protocol's YARD, which is where a duck-typed SPI's contract can bind. The cost is real and is accepted: four MUSTs are verified against a fake rather than against shipped code, and phase 8's `dexpace-conformance` is where the same assertions meet a real adapter |
| P5-49 | A diagnostic key that was present with a `nil` **value** is turned **absent** by `OBS-23`'s per-key restore | `OBS-23` ("restore each key to its prior value (or remove it if previously unset)"); `OBS-10`; verified fact 4; `OI-13` | `Fiber[:k] = nil` deletes the key (measured), so one assignment serves both of `OBS-23`'s branches and no presence check is needed — at the price of collapsing "was absent" and "was present and null" into removal. A null-valued key is reachable only through `Fiber#storage=`, the warned setter `OI-13` records, and `OBS-10`'s "Keys with null values MUST be skipped" makes the two states fold identically at the only reader. Recorded rather than buried because the argument that makes it harmless is `OBS-10`'s clause, and a later phase that relaxes that clause re-opens this |

## Deferrals filed by phase 5c

**One, filed as `DEF-42`** by the pass that reconciled this design with `5b`'s, on 2026-09-09. The draft
stated the row in the register's own item format rather than appending it, because `5b` and 5c were being
written concurrently and both would have taken the same next id. The row is now in `docs/deferred-items.md`
and is cited rather than duplicated here.

**`DEF-42` — `OBS-29`'s HTTP-tracer lifecycle wiring: the vocabulary ships with no emitter.** 5c ships
`HTTPTracer`'s eleven no-op methods, the frozen `NULL` §8.1 names, the `CallableAdapter` bus shape and the
ordering test §8.1 requires, driven through a conformant emitter fake as `OBS-29`'s conformance clause
prescribes. **Nothing in phase 5 emits any of it**: the per-attempt group has no emitter until phase 6's retry
step and the transport milestones none until phase 8. Wiring only the operation-lifecycle triple was
considered and rejected — it needs a third slot boundary 15 does not grant, and `OBS-29`'s exhausted→failed
pairing is not honourable by a step that cannot see attempts; `5b` confirms the refusal from its own side
(`R14`). Pick-up is phase 6, with the retry step and `DEF-39`'s `Pipeline.standard`. `OI-29` carries the
separate finding that `CTX-14`'s bundle member and `OBS-29`'s per-operation factory are two different objects.

**`OBS-32` files no new row.** It is `DEF-9`'s, pre-existing, and its condition — the OTel adapter (`DEF-17`)
— is post-v1 and phase 5 cannot meet it. What `5b` now declares is the two instrument **names** and nothing
else (`R11`); the units, descriptions and attribute sets `OBS-32` asks for stay deferred, because its
conformance clause needs a recording meter core does not ship.

## Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every row.
**All forty were read** — the register had grown by one since the charter's sweep of thirty-nine, `DEF-40`
having been filed by `5a` and being the highest id present when this document was drafted. (`grep -c '^### DEF-'`
reported 41 and is off by one: the file's own *Item format* block matches the pattern. The numbered rows were
`DEF-1`..`DEF-40`, with no duplicate — verified. After reconciliation the rows are `DEF-1`..`DEF-42` and the
grep reports 43, the same off-by-one.) The charter performed the phase-wide pass and it is not repeated; what follows is the
**5c-specific delta**. As with phases 3, 4 and 5a, this
document **states** each disposition and 5c's **plan performs** the register edit — except that, per the
working-in-parallel rule, the *new* row was stated rather than appended; the pass that reconciled this design
with `5b`'s appended it as `DEF-42`, together with `5b`'s `DEF-41`, so the register now holds forty-two.

- **`DEF-37` — picked up and CLOSED, by 5c.** Its condition names "phase 5, with `OBS-25`". 5c gives the three
  `private_constant` classes their methods, widens `_Span` and `_Tracer`, and leaves all three published
  objects with the identity phase 4 gave them — which is what makes `OBS-25`'s allocation clause assertable by
  reference identity. The five prohibitions in the row's "What phase 5 may not do" are honoured item by item
  in *The spec-forced boundaries, honoured* above. `Status` moves to `picked-up (<date>, phase 5c)`.
- **`DEF-1`'s `SEAM-28` half — picked up, by 5c; the `SEAM-24` half is untouched and stays with `DEF-11`.**
  The condition names phase 5 explicitly and gives the reason: "phase 5 is the first phase that has both" —
  the context chain (phase 4a's `RequestContext#operation_name`) and a consumer for the identifier
  (instrumentation). 5c supplies the consumer: `_TracerFactory#tracer(name, version)` takes the operation
  name, and `OBS-29` requires "One tracer instance corresponds 1:1 to a single logical operation lifecycle
  (created by the factory per operation)" — the operation identifier is what names it. **`SEAM-28`'s own
  constraint travels with the pick-up and is honoured structurally:** "when present it is attached to the
  request's context chain but **MUST NOT affect the assembled request's URL, headers, or body**" — 5c reads
  `operation_name` and writes nothing to any request, and nothing in `Dexpace::Instrumentation` can reach a
  `Request` at all. **Note for whoever files this:** `SEAM-28` is one of the five IDs `OI-1` records as
  existing **only** as an appendix-C row — re-verified for this document, `grep -rn 'SEAM-28'
  docs/product-spec/` matches appendix C and nothing else — so 5c read it out of appendix C and the row's
  pick-up note should say so. `DEF-1`'s own row points nowhere; it is the roadmap's gap paragraph and
  `ruby scripts/knowledge.rb --gaps SEAM` that both send a reader to
  `docs/product-spec/03-pluggable-seams-and-extension-model.md`, which does not carry the ID — which is
  precisely what `OI-1` records, unresolved. Nothing new is filed for it.
- **`DEF-30` — untouched, `deferred`, condition read and found NOT met.** `R15` above is the argument:
  `SEAM-2` enumerates five core interface seams and instrumentation is not among them; 5c ships a tracer, a
  meter and a vocabulary as duck types with constant no-op defaults, registers nothing, discovers nothing, and
  adds no fourth registry. The row gains a **dated line in its `Status`** recording that phase 5 read the
  condition and found it unmet, so a later reader does not have to re-derive the argument — and it does **not**
  become UNSCHEDULED, because UNSCHEDULED is for a row whose condition a phase met and declined.
- **`DEF-9` — untouched, and cited by 5c's one ⏳ row.** `OBS-32` is 5c's; `OBS-37` is `5b`'s. The condition is
  the OTel adapter (`DEF-17`) plus the async adapters (`DEF-11`, `DEF-12`), all post-v1. Not UNSCHEDULED.
- **`DEF-17` — untouched.** `dexpace-instrumentation-otel` is post-v1 and is the gem `DEF-9` and `DEF-30` both
  ride on. 5c's six RBS interfaces are what it will satisfy, which is worth a line in the row when someone
  next edits it and is not worth a phase-5 edit on its own.
- **`DEF-39` — untouched, and it is where `DEF-42` lands.** `PIPE-24`/`PIPE-39`'s
  standard-resilience constructors target phase 6; 5c writes neither and installs no preset.
- **`DEF-22` — untouched, and worth reading beside the testing strategy.** `dexpace-conformance` is phase 8's
  and will restate `OBS-25`'s allocation assertion and `OBS-21`'s idempotence assertion; the first has a
  argument-type precondition — not the file-level `# frozen_string_literal: true`, which `5b`'s `R8` shows is
  not what makes it portable — and the second needs a recording span that gem must supply, both of which are
  stated in *The tests a reader would otherwise write wrong*.
- **`DEF-29` — untouched, and 5c's doubles gained a second consumer inside the same gem.** 5c adds four test
  doubles under `gems/dexpace-core/test/support/`, following phases 2, 3, 4 and 5a. `5b`'s draft added its own
  `RecordingTracer` and `RecordingMeter` — two files at the same paths — and at reconciliation they became
  5c's alone, with `5b`'s step tests reusing them; that is `DEF-29`'s own concern met inside the gem rather
  than deferred. The row's condition — a consumer **outside** `dexpace-core` — is still not met.
- **`DEF-27`, `DEF-31`, `DEF-32`, `DEF-34` — untouched by 5c**, all `5b`'s or joint with `5a`. 5c emits no
  event and so cannot supply a disposal route, a lifecycle event or a per-failure diagnostic.
- **`DEF-28`, `DEF-35`, `DEF-36`, `DEF-38`, `DEF-40` — untouched by 5c.** All `5a`'s or phase 6's; 5c builds
  no clock, no configuration source and no classifier.
- **`DEF-18` — untouched.** `ASYNC-3`, `ASYNC-4` and `PIPE-33`'s interrupt clause; 5c starts no thread and
  meets the prohibition nowhere.
- **`DEF-41` — `5b`'s, filed at the same time as `DEF-42` and untouched by 5c.** `OBS-19`'s header-drop
  verbosity policy; 5c ships no policy, no transport and no header.
- **`DEF-2`–`DEF-8`, `DEF-10`–`DEF-16`, `DEF-19`–`DEF-21`, `DEF-23`–`DEF-26`, `DEF-33` —
  untouched.** Other prefixes, later phases, post-v1 gems, release-gated rows, or already picked up.

## Open items filed by phase 5c

**Two, filed as `OI-28` and `OI-29`** by the reconciliation pass on 2026-09-09, for the reason the deferral
above was: the `5b` agent would have taken the same next id. Both are in `docs/open-items.md`; neither is
acted on by this document.

- **`OI-28` — a `**` keyword splat allocates a `Hash` per call even when nothing is passed, and nothing
  mechanised distinguishes it from the named keyword the styleguide's rule is about.** `api-design/1d9e6e0b`
  asks for keyword arguments and gives backward compatibility as its reason, which is a property of *named*
  keywords; the splat is the spelling `opentelemetry-api` and every Ruby metrics library uses, and it makes
  `OBS-25`'s and `OBS-1`'s allocation MUSTs unsatisfiable for any method written with one. **Independently
  reproduced by the reconciliation pass on 2026-09-09** — `def m(x, **attributes)` called with no keyword
  argument measured 1005 per 1000 calls against the named form's 2, and a forwarding wrapper 2004 — so the
  numbers in the filed row are given as a range rather than a single figure and the per-call cost is 1 in
  every run. `P5-42` pays it for this segment; the resolution is a `Dexpace/` cop, which belongs with `OI-6`.
- **`OI-29` — "per-operation tracer factory" names two different objects, and phase 4a bound the bundle's
  member to the one that is per-library.** `CTX-14`/`CTX-20`'s bundle member and `OBS-29`'s HTTP-tracer factory
  read as one object across appendix C, §8.1, `DEF-37` and phase 4a's `R3`, and phase 6 is the first phase
  that needs them to be two. **Amended when filed:** the draft's supporting claim that an `opentelemetry-api`
  `TracerProvider` caches per name and version is a statement about a gem **neither phase 4a nor 5c could
  install**, re-checked at reconciliation and still absent from this machine, so the filed row marks it as the
  motivation for `P4-8` rather than as a measured fact and rests the argument instead on the internal
  contradiction between `OBS-25`'s shared no-op tracer and `OBS-29`'s one-per-operation clause — which needs
  nothing outside this repository's normative text. `P5-43` records the reconciliation 5c adopted.

## Open questions for 5c's own plan

Six, each bounded, none reopening a decision above.

1. **Re-run the four floor-straddling facts on 3.2.11 and 4.0.6 before the code that rests on them is
   written.** Facts 2 (`Fiber[]`'s copy-on-write being per slot and not per object), 3 (`Fiber[]`'s String-key
   interning, `Fiber.current.storage`'s Symbol keys and fresh-copy return, and `Symbol#name`'s identity
   guarantee), 4 (`Fiber[:k] = nil` deleting, and the map setter retaining a nil) and 6
   (`Gem::BUNDLED_GEMS::SINCE` and `securerandom`'s require footprint). **Only 3.4.10 is installed on this
   machine**, verified. Recommendation: the plan's first task installs the two interpreters and re-runs all
   four as one script whose output is pasted into the plan, exactly as phases 3, 4 and 5a did. `OI-13`
   already documents a 3.2-versus-3.4 divergence in fact 4's immediate neighbourhood, so this is not a
   formality. If fact 3's `Symbol#name` identity does not hold on 3.2.11, the crossing contract's advice to
   `5b` narrows to the versions where it was observed and the fold takes a memoised lookup instead.
2. **`opentelemetry-api`'s exact method names and arities for `Tracer`, `Span` and the metrics SPI.** This
   document could not install the gem, which is the same limit phase 4a hit for `#tracer`'s arity (`P4-8`, and
   4a's own open question 1 — check whether its plan resolved it before re-deriving); re-checked at
   reconciliation and the gem is still absent from this machine, which is why `OI-29` marks the
   `TracerProvider`-caches claim as unverified rather than measured. **Whatever this check returns, `5b` has
   already written these names into its step and its `OBS-34` conformance test**, so a name that moves here
   moves there in the same change — the plan states the divergence rather than letting the two documents drift. The signatures 5c designs
   to are `#start_span(name, attributes:, kind:, with_parent:)`, `#in_span(name, attributes:) { |span| }`,
   `#set_attribute(key, value)`, `#add_event(name, attributes:)`, `#record_error(error, attributes:)`,
   `#finish(end_timestamp:)`, `#recording?`, and on the meter `#create_counter(name, unit:, description:)`,
   `#create_histogram(...)`, `#add(amount, attributes:)`, `#record(amount, attributes:)`. Recommendation:
   confirm each against the gem's source on the first task and record any divergence as a ledger row rather
   than silently adopting it — the whole value of the structural subset is call-compatibility, and a name that
   is nearly right is worse than one that is deliberately different. **`P5-42` is not negotiable by this
   check**: if the gem spells a parameter `**attributes`, core's own signature stays named and the adapter
   pays the one-line bridge, because `OBS-25` is a MUST and call-compatibility is a design preference.
3. **Whether `record_error` or `record_exception` is the right name.** `OBS-21` says "all mutators
   (attribute/error)"; `opentelemetry-api` spells it `record_exception`; this repository's own vocabulary is
   `Dexpace::Error` and `#each_cause`, and `error.type` is `OBS-39`'s field key. Recommendation: take the
   gem's spelling if question 2 confirms it, on the same call-compatibility argument that produced `P4-8`, and
   record the choice as a ledger row either way — this is a public method name under an `NFR-4` lock and it is
   cheap now and expensive later.
4. **Whether `Tracing`'s current-span slot should also be readable by `5b`'s fold.** 5c makes the slot key a
   `private_constant` and exposes `.current_span`. `OBS-10` folds only allow-listed diagnostic keys and the
   current span is not one, so nothing needs it today, and `5b`'s design confirms it: `Diagnostics::DEFAULT_KEYS`
   is the pair and nothing else. Recommendation: keep it private and expose only the reader; if `5b` finds it
   needs the span itself for an event field, that is a `.current_span` call and not a third key name, and it
   must not become one (boundary 15).
5. **How `#generate_trace_id` takes its randomness source.** The zero-draw coercion is unreachable by
   sampling, so the test must inject a generator that returns zero. Recommendation: one optional positional
   parameter defaulting to `SecureRandom` — not a keyword, because it is a test seam and not part of the
   requirement's surface, and not a module-level swap, because `testing/4ef070df` forbids a test that mutates
   process-wide state. Confirm on the first task that a positional test seam does not trip
   `api-design/1d9e6e0b`'s cop, and if it does, take the named keyword and pay one allocation on a per-operation
   path where `OBS-25` does not bind.
6. **Whether the `OBS-34`-independence load-time assertion is expressible as written.** The design asserts
   that 5c's suite loads with `Dexpace::Instrumentation::Event` undefined, which depends on
   `lib/dexpace.rb`'s explicit-require tree not pulling `5b`'s files in transitively. Recommendation: confirm
   on the first task by requiring only the five 5c files — plus `5b`'s `diagnostics.rb`, which `tracing.rb`
   now requires for the two key constants and which defines no `Event` — in a fresh interpreter and asserting
   `defined?(Dexpace::Instrumentation::Event)` is `nil`; if `lib/dexpace.rb` is the only entry point and
   requires the whole tree, replace the assertion with a require-scan over 5c's own `lib/` files — weaker, and
   the weakening must be recorded rather than quietly substituted.
