# Phase 5b — The Logging Facade and Redaction

**Status:** Draft, for review. Written 2026-09-09, against
`docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`, which is this sub-phase's charter.

**Written concurrently with `5c`, and reconciled with it on 2026-09-09.** The `5c` design did not exist while
this document was drafted, so every place the two segments meet was stated as an assumption marked *pending
reconciliation with `5c`*. Those markers are now resolved in place: this document names `5c`'s shipped
constants and methods, and where `5c`'s answer won, the section says so and cites `5c` rather than restating
its argument. What the reconciliation changed here, in one list, so a reader of the committed draft can find
each: the step's two slots became **defaulted** keywords (`R11`, `P5-33` — `5c` won); the empty
`interface _Meter` declaration was **deleted** (`5c` declares it filled); the diagnostic-context key constants
**stayed 5b's, as `Symbol`s** (`R11`, `P5-24` — 5b won, on a narrower argument than the draft's); the span,
meter and instrument method names were filled in from `5c`; the two OTel instrument **names** became 5b's to
declare, which the draft had assigned to `5c`; the recording tracer and meter fakes became `5c`'s files, which
5b's suite reuses; and `Events::INSTRUMENTATION_SHUTDOWN` was settled here rather than deferred to `5c`. One thing the
reconciliation found that neither document had noticed: **`OBS-24` had a scope-table row in neither**, which
*Scope* now corrects — it is 5b's, making this segment 28 IDs and `5c` 12, against a charter whose arithmetic
and whose prose disagree. The register rows this document proposed are filed: `DEF-41`, `OI-25`, `OI-26` and
`OI-27`.

## Purpose

Sub-phase 5b builds the structured-logging facade the whole SDK writes through, the redaction policy that
scrubs a credential out of a URL before any sink sees it, the diagnostic-context fold and its cross-thread
snapshot, the failure containment that makes a broken logger unable to fail a request, and the HTTP
instrumentation step at `Stages::LOGGING` that ties all of it to a real exchange. Twenty-eight `OBS` IDs —
`OBS-1`–`OBS-20`, `OBS-24` and `OBS-34`–`OBS-40` — one specification chapter, one gem. (The charter's
arithmetic says 27 and its own prose says `OBS-24` is 5b's; the correction is in *Scope* below.)

**It is the segment where the port's security surface lives.** `XCUT-19` is default-deny in five clauses and
four of them are implemented here; `OBS-15` and `XCUT-20` make the whole of it total; and the failure mode is
not a crash but a bearer token in a log aggregator, which no happy-path test finds. That is why redaction is
welded to the event object rather than offered as a sink hook, and it is the one structural claim in the
sub-phase that a later refactor must not be able to undo quietly.

**5b depends on `5a` and `5c` for nothing, and neither depends on 5b.** The charter's finding is that the
`CFG`↔`OBS` edges run in both directions and that every phase-5 boundary is a convenience. 5b discharges its
half of both without `5a`: `OBS-35`'s resolution takes a `Configuration` **as an argument** and a
configuration-free caller passes a level directly, and `DEF-34`'s two remaining wirings are the only place 5b
touches the chain at all. **A 5b plan whose first task waits on `Dexpace::Configuration` has re-imposed a
chain that does not exist**, and so has one that waits on a `5c` tracer.

Seven decisions reshape what a plan can write, and each was forced by a fact run on a real interpreter rather
than by taste.

- **`OBS-1`'s allocation assertion is made immune to its file's magic comment by the *arguments it passes*,
  not by the technique it measures with.** Verified: the inert chain driven 1000 times with a `Symbol` key and
  an `Integer` value allocates the same **2** objects whether or not the measuring file carries
  `# frozen_string_literal: true`; the same chain with a bare `"x"` literal allocates **8** with the comment
  and **1008** without it, and its delta between a 1000-iteration and a 2000-iteration loop is **0** with the
  comment and exactly **1000** without. **The charter's R8 hypothesis is corrected here**: a
  delta-of-two-loops measurement is not insensitive to the caller's allocations, it isolates them precisely.
  What buys the insensitivity is passing arguments that cannot allocate. `R8`.
- **A redactor that rescues only `URI::Error` breaks `OBS-15`.** Verified: `URI::RFC3986_PARSER` **accepts**
  `%FF` in a query, `URI.decode_www_form_component("%FF")` returns an invalid-UTF-8 `String`, and `OBS-12`'s
  "decoded, compared case-insensitively" then raises `ArgumentError: input string invalid` out of
  `String#downcase` — an `ArgumentError`, which is not under `URI::Error`. The rescue is `StandardError`.
  `R9`.
- **`OBS-15`'s `[malformed url]` sentinel and `OBS-16`'s `?***` marker are two different answers to the same
  parse failure, so the redactor has two entry points and not one.** `OBS-15` governs URL redaction;
  `OBS-16` governs a URL arriving as a header value and requires the *opposite* of a sentinel for exactly the
  input `OBS-15` sentinels. Conflating them loses one requirement whichever way it is conflated. `R9`.
- **`OBS-24`'s whole-map snapshot is implementable with no `Fiber#storage=` call at all, and the residual gap
  is self-eliminating.** Verified: capture-then-reinstall-then-restore **per key over the union of the
  captured and prior key sets** restores a context byte-for-byte (`restored == prior` is `true`) using
  `Fiber[]=` alone, which emits no warning; the one context it cannot restore exactly is one holding a key
  whose value is literally `nil`, and such a context is only constructible through the very setter this route
  refuses. `OI-13`'s gate problem therefore never arises. `R12`.
- **Fiber-storage keys are `Symbol`s and event field keys are dotted `String`s, and the conversion must be
  `Symbol#name`.** Verified: `Fiber#storage=` raises `TypeError: wrong argument type String (expected Symbol)`
  on a `String` key while `Fiber[]=` coerces one; and `Symbol#name` returns the **same frozen `String`** on
  every call while `Symbol#to_s` allocates a fresh unfrozen one each time. A fold written with `#to_s`
  allocates one `String` per folded key per event on the hot path `OBS-1` exists to protect.
- **§3.1's decode recipe is wrong for `OBS-38` in the way `OI-7` records, and phase 3b's correction is what
  5b copies.** Re-verified: `"café".b.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace)` returns
  `"caf"` plus two replacement characters. The preview renderer retags first and names both encodings, exactly
  as `Response#body_string` does.
- **`OBS-7`'s 8 KiB cap is a byte figure and a byte-sliced multibyte string is not a valid `String`.**
  Verified: `("é" * 5000).byteslice(0, 8191)` has `valid_encoding? == false`; `#scrub("")` trims the partial
  character and yields a valid 4095-character result. A cap measured in characters is not 8 KiB — the same
  string is 8192 characters and 16384 bytes.

5b ships no span, no scope, no tracer protocol, no meter and no trace-id generator. It ships one event object,
one facade, one sink default, one redactor, one diagnostic-context bridge, one preview renderer, one log-level
value type and two pipeline steps.

## Governing documents

- `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md` — the charter. It fixes 5b's ID set (27 by
  its own arithmetic, 28 by its own prose — see *Scope*), the
  fifteen spec-forced boundaries and risks `R8`–`R12`. `R1`–`R7` are `5a`'s and `R13`–`R15` are `5c`'s;
  neither set is touched here.
- `docs/product-spec/15-instrumentation-and-observability.md`, read in full — 73 lines, including the per-ID
  `*Conformance: …*` clauses appendix C does not carry — with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text of all 27
  `OBS` IDs in scope and of `OBS-21`–`OBS-33` (`5c`'s neighbours, read so this document does not step on
  them), `XCUT-11`, `XCUT-14`, `XCUT-19`, `XCUT-20`, `XCUT-21`, `SEAM-25`, `CFG-1`–`CFG-4`, `CFG-21`,
  `CFG-24`, `CFG-25`, `NFR-4`, `NFR-7` and `NFR-11`.
- `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` in full — §8.1 is 5b's and is quoted rather
  than paraphrased wherever it fixes a shape; §8.2 is read because `OBS-35`'s four tiers are its chain and
  because `CFG-24`/`CFG-25`'s warning is the call site `5a` left for 5b to stand beside; §8.3 is read for the
  prohibition. `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items 4, 5, 7
  and 17; `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md`
  item 11; and §12's `OBS` row.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-5 row, the five cross-phase obligations,
  the nine cross-cutting constraints and the ✅ / 🚫 / ⏳ / N/A legend this sub-phase's checklist uses verbatim.
- `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md` for the require allowlist and
  its denylist — `logger` is on the denylist **by name** and that is the single most consequential gate in
  this sub-phase; `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` for
  `Dexpace::Model`, `Headers`, `MediaType` and `Dexpace::InvalidArgumentError`;
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` for `close_quietly`, `Hooks.notify`,
  `Closeable`/`SEAM-25` and `Async::Future#on_settle`; the phase-3a and phase-3b designs for
  `MAX_MATERIALIZED_BYTES`, the two logging bodies and `Response#body_string`'s corrected decode; all three
  phase-4 sub-phase designs for their *interface surface later phases may cite* tables, in particular 4a's
  `Instrumentation::Bundle` handshake and 4c's `Stages::LOGGING` and cursor protocol; and
  `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md` for `Configuration`, `Keys` and
  the `OBS-35` reconciliation it performed on 5b's behalf.
- `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md` — **added at
  reconciliation**, and not read while this document was drafted. It is the source for every span, tracer,
  scope, meter and instrument method name this document calls, for the two slot defaults, and for
  `interface _Meter`.
- `docs/deferred-items.md`, `docs/open-items.md`, `docs/deviations.md`, `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

## The `5b`/`5c` line, and how each crossing was settled

`5b` and `5c` were designed concurrently. Four things below are contracts across the line. Each was stated as
an assumption in the draft and each is now settled; the settlement is recorded here once and cited from the
sections that depend on it, so no section re-argues it.

1. **The instrumentation step is 5b's and `5c` fills two slots in it** — charter boundary 15, which was never
   in question. The *shape* of the slots was: the draft made them required and undefaulted, `5c` made them
   keywords with constant defaults, and **`5c`'s answer stands** (`R11`, `P5-33`). `5c` also fixes a
   precedence 5b's step implements and must not contradict: the request context's bundle when it is not
   `Bundle::NONE`, else the step's keyword, else the constant.
2. **5b declares the two diagnostic-context key names** — `Diagnostics::TRACE_ID` and `::SPAN_ID`, as
   `Symbol`s. `5c` declared `Instrumentation::TRACE_ID_KEY`/`::SPAN_ID_KEY` as frozen `String`s on a
   writer-owns-the-key rule. **5b's constants stand**, on the argument in `R11` below, and `5c` cites them.
3. **5b calls methods whose names `5c` fixes** — the tracer factory's `#tracer` (phase 4a's, never in
   question), span start and end, the counter and histogram accessors and their record methods. **`5c`'s
   names are now written out** in `R11` and in the step's entry in the object model; there is no
   `# PENDING 5c` marker left in this document.
4. **`OBS-24`'s decision about `Fiber#storage=` is stated once, here, and `5c` cites it for `OBS-23`** — the
   charter's `R12` puts the statement on whichever segment owns `OBS-24`, which is 5b. `5c` reached the same
   answer independently and recorded it as a recommendation; `R12` below is the statement and `5c`'s
   *R12* defers to it.

One crossing the draft did not anticipate is settled too: **the two OTel instrument names are 5b's to
declare**, not `5c`'s. Both drafts assigned them to the other; `R11` resolves it. Neither segment ships a
second step, a second diagnostic-context key-name constant, or a second no-op meter.

## Scope

### The 28 IDs, with dispositions

Twenty-eight IDs: **23 MUST, 5 SHOULD (`OBS-7`, `OBS-19`, `OBS-35`, `OBS-37`, `OBS-38`), 0 MAY**, derived
mechanically from appendix C on 2026-09-09.

**A second correction to the charter, found at reconciliation, stated here and filed as `OI-30` rather than
made by editing the charter.**
The charter says 5b's "ID set is exactly `OBS-1`–`OBS-20` together with `OBS-34`–`OBS-40`: 20 + 7 = **27**",
and its `5c` table's Implemented row reads `OBS-21`–`OBS-31`, which **includes `OBS-24`**. Its prose says the
opposite twice: "`OBS-24` goes to `5b`: it is the context snapshot itself, with no span in it", and `R12`
says "`5b` owns `OBS-24` and `5c` owns `OBS-23`". The two cannot both be true, and the prose is the one the
substance follows — 5b builds `Diagnostics.capture` and `.with` for it (`R12`, `P5-22`, `P5-23`) and `5c`
disclaims it in as many words. So **`OBS-24` is 5b's and this table carries it**, 5b is **28** IDs and `5c` is
**12**, and the phase still sums to 78 because the ID moved between two of the three segments and not out of
the phase. The cut is untouched: no §15 section changes hands and no requirement leaves phase 5. The draft of
this document inherited the charter's arithmetic and gave `OBS-24` **no row in either sub-phase's scope
table** while implementing it — which is precisely the one-row-per-ID failure the roadmap's convention exists
to prevent, and is why the correction is made rather than carried.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `OBS-1`–`OBS-18`, `OBS-20`, `OBS-24`, `OBS-34`, `OBS-35`, `OBS-36`, `OBS-38`, `OBS-39`, `OBS-40` | 26 |
| ⏳ deferred, **`DEF-41`**, target phase 8 — the requirement's subject is "a transport that drops a caller-set request header it cannot encode"; core has no transport, `Net::HTTP` raises rather than drops (§12's `OBS` row), and a three-mode policy object with no core caller and no core test is `OI-8`'s exact shape. `R10` | `OBS-19` (SHOULD) | 1 |
| ⏳ deferred, `DEF-9` (pre-existing), post-v1 with the async adapters | `OBS-37` (SHOULD) | 1 |

**This changes one cell of the charter's own scope table**, which expects `OBS-19` as "Partially satisfied —
the verbosity policy and its once-per-name throttle ship". The charter's `R10` explicitly leaves the choice
open and forbids only one of the two answers ("It must not ship a policy with no caller and no test that
exercises it"). `R10` below argues the deferral and `P5-32` records it, because §12's word for `OBS-19` is
"vacuous" and a checklist row cannot cite "vacuous" as a target. **The charter is not edited**; the correction
is made here, where it is made, and the discrepancy between the scope table and `R10` is filed as `OI-27`.
The precedent is phase 4c correcting the charter's `PIPE-39` row.

**`XCUT-19` and `XCUT-20` are phase 9's IDs and get no row here.** 5b satisfies both by construction —
`OBS-11`/`XCUT-19`(a), `OBS-12`/`OBS-13`/`XCUT-19`(b), `OBS-18`/`XCUT-19`(c), `OBS-34`/`XCUT-19`(e), and
`OBS-15`/`OBS-20`/`XCUT-20` — and phase 9 audits the claim. `XCUT-19`(d), credential objects not revealing
their secret, is `AUTH`'s and phase 6's; `5a`'s `Proxy#to_s`/`#inspect` already discharge it for the one
credential-bearing type that exists today, and **5b may not rely on that for any other type** (`5a`'s own
interface row).

**Also shipped by 5b without owning a new ID**, per the charter:

- `Dexpace.close_quietly`'s **second** disposal route — an `http.instrumentation.*` diagnostic for the
  `onto:`-absent case — which **closes `DEF-27`**, a row open since phase 2. The phase-2 test asserting the
  rescued error is dropped is what changes, and phase 4b's interface table already says so.
- `SEAM-25`'s lifecycle **event shape** — `DEF-31` is **half** supplied and the row stays open, because the
  first thing in the repository that owns an executor is phase 8's `dexpace-async-thread`.
- the optional per-dropped-failure diagnostic in `Dexpace::Hooks.notify` (`DEF-32`); 5b takes the option, and
  the suppressed trail phase 4b built stays.
- `DEF-34`'s two remaining wirings — the shared preview size read from the chain into
  `Dexpace::RequestLoggingBody` and `Dexpace::ResponseLoggingBody`, and the gating of their construction on
  `OBS-34`'s enablement level. `5a` supplied the third (`MAX_MATERIALIZED_BYTES`'s source) and did not edit the
  row; **5b lands second and edits it**, per the charter.
- the HTTP instrumentation step at `Stages::LOGGING`, with two slots `5c` fills.

### The canonical text the design turns on

Quoted from appendix C and from chapter 15's conformance clauses rather than paraphrased, because each fixes a
decision below.

> **OBS-1** (MUST) — When the requested log level is disabled on the underlying logger, obtaining a log event
> and calling its builder methods and terminal emit MUST allocate nothing and produce no output. The facade
> MUST decide enabled/disabled once, at event-creation time, and return a shared inert event for the disabled
> case. *Conformance: with the backend level below the event level, assert the returned event is the shared
> singleton (reference-identical across calls) and that a field/event/cause/log chain emits nothing.*

> **OBS-3** (MUST) — A field key MUST be rejected (error to the caller) when empty. A null field value MUST NOT
> be dropped; it MUST be emitted as the literal string 'null'.

> **OBS-4** (MUST) — event(name) MUST set an authoritative categorisation tag under the reserved key 'event'.
> An empty name MUST clear the tag rather than emit 'event='. When a non-empty tag is set, any 'event' key
> arriving from the global context, folded diagnostic context, or a per-event field MUST be suppressed so the
> emitted event carries the 'event' key exactly once.

> **OBS-5** (MUST) — … precedence MUST be: per-event field wins over global context, and both win over folded
> diagnostic context. A given key MUST appear at most once in the emitted event.

> **OBS-8** (MUST) — A single log event MUST be emitted at most once. A second terminal emit on the same event
> instance MUST be a no-op, and this guard MUST be correct under concurrent invocation. Field/tag/cause
> accumulation is not required to be thread-safe (single-thread build), but the terminal emit MUST be safe to
> call from any thread.

> **OBS-10** (MUST) — When folding thread-local diagnostic context into an event, only keys in the configured
> allow-list MUST be folded. The default allow-list MUST be exactly {trace.id, span.id}. A null (absent)
> allow-list MUST fold every present diagnostic-context key (opt-in unfiltered mode). Keys with null values
> MUST be skipped.

> **OBS-11** (MUST) — URL userinfo (the 'user:password@' component) MUST always be redacted to a fixed
> placeholder ('***:***@'), unconditionally and independent of any allow-list.

> **OBS-14** (MUST) — URL redaction MUST NOT alter scheme, host, port, or path, and MUST preserve a
> present-but-empty query (a trailing '?'). A '?' that appears only inside the fragment MUST NOT be treated as
> a query delimiter (no spurious separator inserted). A trailing '&' (empty final pair) in query or fragment
> MAY be dropped.

> **OBS-15** (MUST) — URL redaction MUST be total: on any parse/rebuild failure it MUST return a fixed sentinel
> ('[malformed url]') rather than throwing. Logging must never break the caller.

> **OBS-16** (MUST) — A URL that arrives as a header value MUST be redacted. A parseable absolute value is
> redacted exactly like a request URL; when the value is relative or otherwise unparseable, the redactor MUST
> keep the path and drop everything after it (both query and fragment), appending a fixed '?***' marker
> whenever the value carried a query OR a fragment … A value with neither MUST be returned verbatim.

> **OBS-20** (MUST) — … every log-emission site (request event, response event, failure event, and the
> body-drain that feeds them) MUST catch any exception and re-surface it as a best-effort
> 'http.instrumentation.*' diagnostic, and a secondary failure while emitting that diagnostic MUST be
> swallowed. The runtime does NOT defensively wrap tracer (span start, scope activation, end) or metrics
> (counter/histogram) calls …

> **OBS-34** (MUST) — HTTP logging granularity MUST be selectable across at least three levels — none,
> headers-only, and headers-plus-body — defaulting to none (logging off unless explicitly opted in). At none,
> request/response log events MUST NOT be emitted; body capture MUST occur only at the body level. Span
> lifecycle AND metric recording (request counter + latency histogram) run on every request independent of the
> log level, so 'none' silences log events without disabling tracing or metrics. *Conformance: at none assert
> no request/response events but the span still starts/ends and the counter/histogram still record; at body
> level assert body preview fields present.*

> **OBS-35** (SHOULD) — A log-level value SHOULD be resolvable from layered configuration … The SDK MUST NOT
> bake in a default config key name.

> **OBS-39** (MUST) — The set of emitted structured event names and field keys MUST be stable and predictable
> … The logged 'url.full' MUST always be the redacted URL.

And the one sentence in design §8.1 that the whole security argument rests on:

> "Redaction (**OBS-11**–**OBS-19**) runs on the way into `#field`, **not at the sink**, so no sink
> implementation can bypass it."

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `OBS-21`–`OBS-23`, `OBS-25`–`OBS-27` — the span recording flag, the scope handle, `OBS-23`'s per-key push, the no-op tracing defaults, the W3C identifiers, trace-id generation | `5c`. 5b declares the two key names `OBS-23` writes (`R11`) and nothing else about a span. **`OBS-24` is not in this range and is 5b's** — the draft wrote `OBS-21`–`OBS-27` here while owning `OBS-24` in `R12`, which is the same charter arithmetic error corrected above |
| `OBS-28`–`OBS-30` — the HTTP-tracer vocabulary and its ordering contract, and the must-not-throw SPI clause | `5c`. 5b honours `OBS-20`'s half of the asymmetry by **not** wrapping tracer or meter calls; it does not define the callbacks |
| `OBS-31`–`OBS-33` — the metrics SPI, the no-op meter, the counter and histogram contracts | `5c`. 5b's step takes a meter through a slot and calls it; it ships none |
| `OBS-32`'s instrument **units**, descriptions and attribute sets | `5c`, ⏳ `DEF-9`; its conformance clause needs a recording meter, which core does not ship. **The two instrument *names* are 5b's**, reversed at reconciliation: the step is the only caller of `create_counter`/`create_histogram` in core, so the object *is* 5b's, and `OBS-34` cannot record without a name (`R11`) |
| `CFG-1`–`CFG-38` — the layered chain, the clock, the proxy model, the five utilities | `5a`. 5b consumes `Configuration#string` and `Configuration::Keys` and adds **one** key name, `LOG_PREVIEW_BYTES`. **Corrected at the plan reconciliation: this said two.** `DEF-34`'s pick-up condition names three wirings — the shared preview size, the body-logging enablement gate, and a configured source for `MAX_MATERIALIZED_BYTES` — and only the first needs a name that does not exist. The enablement gate reads `5a`'s shipped `Keys::LOG_LEVEL` (`"LOG_LEVEL"`, `OBS-35`'s published name), which 5b must not restate, rename or revalue; `Keys::MAX_MATERIALIZED_BYTES` is `5a`'s too and `5a` supplied that third wiring |
| `ASYNC-8`–`ASYNC-12` — capture, install and restore of the diagnostic context across a **thread hop** in an adapter | 8. 5b owns the carrier and `OBS-24`'s bridge; `dexpace-async-thread` owns the pooled-worker save/install/restore and is what `OI-13` will meet |
| `BODY-17`–`BODY-29`, `BODY-34`, `IO-9`, `BODY-32` — the two logging body wrappers and the materialisation ceiling | 3a and 3b, built. 5b supplies the configured preview size and the enablement gate (`DEF-34`) and adds no keyword to either wrapper |
| `HTTP-42`'s decode boundary and `Response#body_string` | 3b, built. `OBS-38`'s preview renderer follows its corrected recipe (`OI-7`) and does not replace it |
| `XCUT-11`'s shared-instance audit, `XCUT-14`'s bounded-map audit, `XCUT-19`/`XCUT-20`'s totality audits | 9 dispositions. 5b builds the redactor and the two policies that are the audit's subject |
| `XCUT-21`'s CSPRNG path | 6. 5b draws no random value at all |
| `TRANSPORT-8` — header-drop reporting on a real adapter | 8, and it is what `DEF-41`, the `OBS-19` deferral, targets |
| `SEAM-5`'s presence-gated auto-activation for instrumentation | Post-v1 (`DEF-30`, `DEF-17`). **5b adds no fourth registry**: the sink, the redactor and the level are configured values, not discovered seams, and instrumentation is not one of `SEAM-2`'s five. The row's disposition is `5c`'s to record (`R15`), and this document's reading agrees with the charter's |
| `Pipeline.standard` and any preset that installs the instrumentation step | 6 (`DEF-39`). **5b builds the step and installs nothing**; `Builder#install_preset` is phase 4c's mechanism and phase 6's caller |

**No segmentation design of its own.** 5b is half of one spec chapter, one gem, 28 IDs, under a segmentation
design that already exists at the `phase5/` level.

## Prerequisites, and the independence this sub-phase must state

**Stated first, because the charter requires it of every phase-5 sub-phase and because 5b is the one most
tempting to chain.** 5b needs `5a` for exactly two things and neither is a blocker: `OBS-35`'s layered
resolution, which takes a `Configuration` as an argument and is therefore testable against a hand-built one
and skippable by a caller who passes a level directly; and `DEF-34`'s two wirings, which are one method call
each. 5b needs `5c` for two duck-typed slot arguments its own suite fills with fakes. **A 5b plan whose first
task waits on either has re-imposed a chain that does not exist.**

### From phase 0 — seventeen blocking gates, unchanged and unlowered

`gates:require_allowlist` — core's `lib/**/*.rb` may `require` only `monitor`, `uri`, `stringio`, `strscan`,
`time`, `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`. **5b adds nothing to
it** and requires exactly two entries already on it: `uri`, for the redactor's pinned parse, and `set`, for the
two allow-lists. It does not require `time`, `date`, `stringio` or `strscan`.

**`logger` is on the phase-0 denylist by name, and this is the sub-phase that gate exists for.** Re-verified
2026-09-09: `Gem::BUNDLED_GEMS::SINCE["logger"]` is `"4.0.0"` (28 entries in the table). The failure it
prevents is silent on the development interpreter and loud only on the 4.0 matrix row under Bundler, which is
what makes the clean-bundle isolation run load-bearing rather than ceremonial. **5b must not write
`require "logger"` even in a test-support file under `gems/dexpace-core`**, because the require scan resolves
relative targets and reads text. The one legitimate use — proving that a stdlib `Logger` satisfies the sink
duck type — is therefore *not* written as a test in `dexpace-core`; it is `dexpace-conformance`'s (phase 8,
`DEF-22`), where a declared dependency is permitted, and 5b records that rather than smuggling the require in.

`Dexpace/NoUriDefaultParser` binds every URL touch in the redactor: `URI::RFC3986_PARSER` is pinned for every
parse, and — following `5a`'s finding — `URI.decode_uri_component` / `URI.decode_www_form_component` are the
decoders, never `URI::RFC3986_PARSER.unescape`, which emits `URI::RFC3986_PARSER.unescape is obsolete` on
3.4.10 against a gate set that fails the build on warnings.

`Dexpace/NoLocaleCaseFold` binds `OBS-12`'s "decoded, compared case-insensitively" and `OBS-18`'s header-name
gate: `downcase` takes no argument at every one of the four call sites.

`Dexpace/NoThreadInterrupt` is background here — 5b starts no thread and waits on nothing — but it is why
`OBS-20`'s containment can be a plain `rescue`: no asynchronous interrupt can land inside it.

`gates:surface_snapshot` and `gates:sig_diff` regenerate once, deliberately, in the phase's last task. 5b ships
the second-largest crop of new public constants in the repository after phase 1, and §8.1 requires `OBS-39`'s
event names and field keys to be "frozen constants **covered by §9.1's surface snapshot**, because a 'stable'
vocabulary that nothing asserts drifts on the first refactor" — so for this sub-phase the snapshot is not only
a gate, it is a requirement's mechanism.

`NFR-7`'s warnings-fail-the-build rule is what `R12` is about, and 5b's resolution is to never make the call
that warns.

### From phase 1

- **`Dexpace::Model`** — `Model.required!(name, value)` raising `Dexpace::InvalidArgumentError` with the one
  message form `"<name> is required"` (`SEAM-29`), where `OBS-3`'s empty-key rejection routes;
  `Model.own(collection)` = `Ractor.make_shareable(collection, copy: true)` for `OBS-9`'s frozen global
  context; and the `#with` override that routes through the validating `.build`.
- **`Dexpace::InvalidArgumentError < ::ArgumentError`.** `OBS-3`'s empty key raises it. **`Dexpace::ArgumentError`
  is never defined** (P1-3).
- **`Dexpace::Headers`** — `#names`, `#entries`, `#each_entry`, `#[](name)`, with equality and lookup under
  `HTTP-13`'s fold. `OBS-18`'s allow-list is checked against the **folded** name, which the collection already
  supplies, so 5b writes no second fold.
- **`Dexpace::MediaType`** — `Data.define(:type, :subtype, :parameters)` with `#charset` returning `nil` for an
  absent **or unrecognised** charset and never raising (`HTTP-24`). That `nil` is what makes `OBS-38`'s
  fallback need no second validation and what makes `Encoding.find` unreachable from 5b — verified that
  `Encoding.find("no-such-charset")` raises `ArgumentError`, which is exactly the raise phase 1 already
  removed.
- **`Dexpace::Response`** — `#body_string` (retag then transcode with both encodings named, `OI-7`'s
  correction) and `#body_bytes` (BINARY, decodes nothing). `OBS-38`'s renderer is the same recipe applied to a
  **preview** rather than to a whole body, and it does not reimplement it.
- **Public wire-model constants are flat (P1-1) unless the design namespaced the subsystem.** §8.1 names
  `Dexpace::Instrumentation::Event`, `Event::INERT` and `Dexpace::Instrumentation::Bundle`, and phase 4a
  already shipped `Dexpace::Instrumentation::NO_SPAN`, `NO_TRACER_FACTORY` and `TraceIdFlavour`. **Every 5b
  constant is therefore under `Dexpace::Instrumentation::`**, which is the one subsystem the design namespaces
  by name, and each still carries a ledger row because §8.1 names only three of them.
- **`Regexp.new(source, timeout:)` per pattern, never `Regexp.timeout`.** 5b compiles two families —
  `OBS-12`'s query tokenizer and `OBS-38`'s text-media-type discriminator — and both carry their own timeout.

### From phase 2

- **`Dexpace.close_quietly(resource, onto: nil)`** — null-safe (`CFG-21`'s last clause), `rescue StandardError`,
  with phase 4b's `onto:` keyword routing the rescued error onto a primary exception's suppressed trail. The
  `onto:`-**absent** branch currently drops the error and a phase-2 test asserts that it does. **5b changes
  that test**, which 4b's interface table already anticipates: "Phase 5 adds the `http.instrumentation.*`
  diagnostic for the `onto:`-absent case and **closes the row**; it does not replace the trail and does not
  remove the keyword."
- **`Dexpace::Hooks.notify(hooks, argument)`**, `private_constant` (P2-15) — runs the whole list and re-raises
  the **first** failure. `DEF-32` reserves the failures after the first for a diagnostic once §8.1's facade
  exists. 5b takes the option.
- **`Dexpace::Closeable`** with its latch and ownership rule — `SEAM-25`'s whole sentence except "and emits the
  lifecycle event", which is `DEF-31`.
- **`Dexpace::Async::Future`** — `#value(cancellation:)`, `#wait(cancellation:)`, `#cancel(reason)`,
  `#settled?`, `#outcome`, and **`#on_settle { |settlement| … }`, "invoked exactly once, on the settling
  thread-or-fiber"**. There is no `#then` and no `#map`. That single fact fixes the async step's shape and its
  one uncomfortable consequence (`R11`, and the cross-cutting section below).
- **`Dexpace::Registry` and three seam registries, with no auto-activation hook and a test asserting its
  absence** (`DEF-30`). 5b adds no fourth registry.
- **`Dexpace/QualifiedCoreConstant`** (P2-8, extended by 3a as P3-7). 5b defines `Dexpace::Instrumentation::Logger`,
  which is deliberately *named after* a core-adjacent constant it must never become — `P5-38` and a proposed
  open item.
- **P2-6's precedent, which 5a re-applied as `P5-8` and which 5b now discharges**: a warning emitted through
  `Kernel#warn` before the facade existed gets an `http.instrumentation.*` event **beside** it and keeps the
  warning. 5b adds the event at `Dexpace::ProxyResolution`'s two `Kernel#warn` sites (`CFG-24`, `CFG-25`) and
  removes neither.

### From phase 3

- **`Dexpace::RequestLoggingBody.new(delegate, tap_limit: ::Float::INFINITY)`** with `#snapshot -> String`
  returning the bytes mirrored so far (`BODY-20`), and
  **`Dexpace::ResponseLoggingBody.new(delegate, preview_bytes:)`** — required, no default — with `#source`,
  `#snapshot` and `#error`, each triggering the lazy drain on first access. These are `DEF-34`'s two remaining
  wirings and `OBS-36`'s whole mechanism: the over-cap regime already replays the captured prefix and
  continues from the live tail, so **5b writes no streaming code for `OBS-36` at all** — it supplies the cap
  and the gate.
- **`Dexpace::IO::MAX_MATERIALIZED_BYTES`**, whose configured source `5a` already supplied. 5b adds no
  `ceiling:` keyword and does not re-read it.
- **`Dexpace::ResponseBody#preview(cap:)`** — a fresh peek view, a capped read, the view closed in an `ensure`.
  `OBS-38`'s renderer takes bytes; it does not acquire a body.
- **The retag-then-transcode recipe and `OI-7`.** 5b copies phase 3b's corrected form and cites `OI-7`;
  §3.1's own sentence is the one that must not be copied.

### From phase 4

- **4a, obligatorily** — `Dexpace::Instrumentation::Bundle` with its eight stored members and derived
  `#valid?`, `Bundle::NONE`, `Bundle::INVALID_SPAN_ID`, `TraceIdFlavour`, `NO_SPAN`, `NO_TRACER_FACTORY` with
  its one method `#tracer(name = nil, version = nil)`, and the empty RBS interfaces `_Span`, `_Tracer`,
  `_TracerFactory`. **The shape is fixed and 5b does not populate it** — that is `5c`'s, under `DEF-37`. What
  5b uses is exactly two members: `bundle.trace_id` and `bundle.span_id` are what `OBS-23`'s keys will carry
  (`5c`'s write), and `bundle.tracer_factory` is what the step's tracer slot may be fed from by a caller. 5b
  adds no member, replaces no singleton, and defines no second `NONE`.
- **4a** — `RequestContext#operation_name` / `ExchangeContext#operation_name`, "already carried and already
  advisory". 5b's step reads it for the `tracer_factory.tracer(...)` call's name argument and for nothing else;
  `SEAM-28`'s consumer half is `5c`'s (`DEF-1`).
- **4a** — `ContextStore.new(cap:)` and `MAX_TRACKED_CONTEXTS`; `DEF-36` is `5a`'s and 5b does not touch it.
- **4b** — `Dexpace::Error#suppressed`, `Dexpace.attach_suppressed`, `Dexpace.each_cause`, and
  `Dexpace::ProtocolError` **whose message names the status and deliberately carries no body preview**, with
  the instruction attached: "a message is what lands in a log by default, and an error body is the one payload
  most likely to carry a token or a customer identifier. **Confirm with phase 5's planner rather than
  reversing it here.**" **5b confirms it, and strengthens it**: `OBS-39`'s failure event carries `error.type`
  and the throwable as the cause, and neither the response body nor a body preview is attached to a failure
  event at any level below `BODY`. At `BODY` the preview is a *field*, produced by the redaction-aware
  renderer, and is not the exception's message.
- **4c** — `Stages::LOGGING` as the pillar, `Stages::PRE_LOGGING` and `POST_LOGGING` as its slots, and the step
  and cursor protocols: a step responds to **`#call(request, cursor)`** returning a `Response` (a `Future` on
  the async path); `#stage` is optional, read once at install, and a step declaring it is installed with **no
  `stage:` argument**; `Cursor#call(request)` is **single-use**; `#fork` lives on the cursor, not the step. 4c
  is explicit that the instrumentation step "is a pillar, so it **may** fork. **It should not**: a step that
  drives the chain exactly once drives it through `#call`". **5b's step calls once and never forks**, and
  builds against that sentence rather than rediscovering it.
- **4c** — `Builder#install_preset(entries)` is `DEF-39`'s mechanism and phase 6's caller. 5b installs nothing
  and writes no preset.

### From phase 5a

- **`Dexpace::Configuration#string(name, default: nil)`** and **`Configuration::Keys`** — seven frozen `String`
  constants including `Keys::LOG_LEVEL`. `5a` performed the `OBS-35` reconciliation on 5b's behalf and its
  wording is binding here: "**`LOG_LEVEL` is a published name a caller may pass, not a default any resolver
  falls back to** — `OBS-35`'s embedded MUST is 'The SDK MUST NOT bake in a default config key name', so
  `5b`'s log-level resolution takes its key as a **required** argument." 5b honours it exactly (`P5-36`).
- **`5a` deliberately declared no key constant for the body preview size or the enablement setting**, and said
  why: "a key constant with no reader is `NFR-4`-locked surface nothing exercises, which is `OI-8`'s shape."
  **5b adds the two names in the change that reads them**, which is `DEF-34`'s pick-up.
- **`Dexpace::Clock` and `Clock::SYSTEM`** — `#now`, `#monotonic`, `#sleep`. `OBS-39`'s
  `http.response.duration_ms` is measured with `#monotonic` and **never** with `#now`, which is `CFG-16`'s own
  rule arriving at its first consumer. The step takes `clock:` defaulting to `Clock::SYSTEM`.
- **`Dexpace::ProxyResolution`'s two `Kernel#warn` sites** (`P5-8`), where 5b adds an event beside each.

**Three open items land in 5b's window and none is 5b's to close.** `OI-13` is `R12`'s subject and 5b's
resolution is to never make the call it records. `OI-7` is `OBS-38`'s recipe and 5b copies phase 3b's
correction rather than §3.1's sentence. `OI-8` is the shape `R10` refuses to repeat.

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written.
`ruby scripts/knowledge.rb --origin note --brief` returned **36 entries across 18 note files** when this
document was drafted and returns **37** after the reconciliation pass filed the note described below;
`--section conflicts --brief` returns **24 entries across 17 topic files, 18 of them notes and six
harvested**, and all six harvested conflicts print `[overridden by notes/…]` — `data-modeling/35fde90f`,
`module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and `/8c0687bf`,
`tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`. **None is open**, so 5b inherits no unresolved
conflict and owns no conflict decision of its own. The counts are unchanged from the charter's and `5a`'s.

`--prefix-info OBS` reports 40 IDs, 32 MUST / 8 SHOULD, owning chapter
`docs/product-spec/15-instrumentation-and-observability.md`, **40 of 40 substantive, 0 roll-up only, 0
uncited**, and names three topics carrying `OBS` knowledge: `observability`, `redaction-and-security`,
`testing`. `--gaps OBS` returns nothing, so **5b budgets no specification reading beyond chapter 15** — read in
full anyway, because it is 73 lines and because its per-ID `*Conformance: …*` clauses are not in appendix C
and four of them are load-bearing: `OBS-1`'s "assert the returned event is the shared singleton
(reference-identical across calls)" is what makes the singleton's *identity* rather than its cheapness the
tested property (`R8`); `OBS-14`'s "redact `http://h/p#a?b=c` and assert no `?` before `#`" is the only
statement of what the fragment-`?` clause produces; `OBS-16`'s "`/cb?code=SECRET` → `/cb?***`" is the only
worked example of the relative branch; and `OBS-34`'s "at none assert no request/response events but the span
still starts/ends and the counter/histogram still record" is the test `R11` has to make writable.

**`OI-24`'s shape does not recur for `OBS`, and that was checked rather than assumed.** `5a` found that
`--prefix CFG --section rules` returns 36 of 38 IDs because `CFG-14` and `CFG-29` are filed under `Reference`.
Verified mechanically on 2026-09-09: `ruby scripts/knowledge.rb --prefix OBS --section rules --brief` returns
**51 entries covering all 40 distinct `OBS` IDs**, `OBS-1` through `OBS-40` with none missing. So the audit
group's ID-bearing half is complete for this half of the phase, and a 5b designer who counts what comes back
gets the same number `--prefix-info` reports. Recorded positively because `OI-24` is open and a reader meeting
it would otherwise have to re-check.

**The appendix-B roll-up hazard fires on every `OBS` ID**, exactly as the charter said. Confirmed on the ten
IDs whose roll-up is most misleading: `observability/9345dbb4`, `/1b6ebe7e`, `/45e60e1e`, `/9394cf3e`,
`/1b707a6e`, `/a3ef0b69`, `/68e9b211`, `/1d4a57c9`, `/5c1a13f5` and `/6f8a26eb` are each tagged
`[appendix-B roll-up]` and each cites the **same ten IDs** — `OBS-1`–`OBS-9` plus `OBS-40` — while stating one
of them. A `--req OBS-7` that stopped at the first hit would read "A disabled log level allocates nothing" as
the answer to a truncation requirement. The skill's three-step roll-up path was the normal reading mode for
this document, and the substantive entry was located beside the roll-up in every case.

### The audit groups this phase ran

| Group | Query | Result |
|---|---|---|
| **Observability, configuration and redaction** (the tenth row, added by the charter for this material) | `--topic observability,configuration,redaction-and-security --section rules --brief` (92 entries across three topic files) and `--prefix OBS --section rules --brief` (51 entries, 40 distinct IDs) | The `redaction-and-security` half is the one that shaped this document: it carries `OBS-11`–`OBS-19` **and** `XCUT-19`'s five clauses **and** `XCUT-16`'s non-secure-transport rule **and** `XCUT-21` in one file, which is the charter's point that "the redaction surface is one audit target spanning two prefixes and must not be split from the event object". Nothing in either half contradicts a decision below, so **no note is filed** |
| **Observability, non-rule sections** | `--topic observability --section constraints,conclusions,reference --brief` | The four `Constraints` and eight `Conclusions` entries are §8.1's own arguments harvested, and three are cited rather than restated: `observability/956f1603` ("Ruby cannot make an enabled structured log event allocation-free; only the disabled path is required to allocate nothing"), `observability/53a73482` (why a `sink.info { }` shape was rejected) and `observability/c2ebb968` ("URL redaction runs on the way into `#field` rather than at the sink"). `observability/80c9594d` is the fragment split `OBS-13` needs and is the reason the fragment tokenizer is hand-rolled |
| **Fiber storage and the diagnostic context** | `--topic observability --origin note` | One entry, `observability/698552b4`, superseding `observability/e0f1e864`. It is the boundary 5b works inside: fiber storage is the carrier across the whole supported range, its inheritance is **copy-on-write**, `Fiber.new(storage: nil)` opts out, and it is **not** where `CTX`'s execution context lives. It also names `OI-13` for the write side, which is `R12` |
| **Concurrency and shared state** | `--topic concurrency-and-async --section rules --brief`, narrowed by grep on `mutex\|thread\|fiber\|frozen` | `concurrency-and-async/f414b864` (the note) governs `OBS-8`'s emit-once latch exactly as §8.1 describes it: a flag flipped under a `Thread::Mutex` held across the flip only, released before the sink call, and not the GVL. Verified here that `Thread::Mutex` is non-reentrant (`ThreadError: deadlock; recursive locking`) and per-**fiber**-owned (`m.owned?` is `false` inside a child fiber of the owning thread), so a sink call inside the lock would be a live deadlock risk and not a theoretical one |
| **Resource lifecycle** | `--topic resource-management --section rules --brief` | 27 entries. 5b acquires no resource: the step never closes a body (phase 3b's wrappers own that), `Instrumentation.contain` holds nothing across its `rescue`, and `Diagnostics.with` is a `begin/ensure` around a caller's block with no acquisition inside it. `resource-management/bf5560dc`'s block-form rule reaches only `Diagnostics.with`, which already has that shape |
| **Public API surface** | `--topic api-design,error-handling,module-organization,documentation --section rules --brief` | `api-design/1d9e6e0b` (keywords everywhere) shapes every constructor; `api-design/6ea28c9c` (never `nil` for absent) is **overruled by requirement** at `Redactor#header_value`, which returns a `String` always, and is honoured everywhere else; `api-design/c15b29ce` (every returned collection frozen) is adopted through `Model.own` for `OBS-9`'s context and through `#freeze` for `OBS-24`'s snapshot; `module-organization/64e84d64`'s full-nesting rule is what the four `private_constant`s depend on; and `api-design/1d9e6e0b`, `/a9943041` and `/634ccc4b` together make **adding an optional keyword non-breaking and changing an existing default MAJOR**, which is the rule the two required step slots are chosen under (`R11`, `P5-33`) |
| **RBS / Steep typing** | `--topic type-system,data-modeling --section rules --brief` | `type-system/545949a5` fixes `Severity` and `HTTPLogging` as frozen `Data` value types over a frozen table with an `.of` factory, never a `T::Enum`; `data-modeling/3e37c086` puts `Logger`, `Event` and `Redactor` in classes because they are implementations rather than values; `data-modeling/b74a2869` and `/ec0f41cb` put `Diagnostics`, `Preview`, `Keys` and `Events` in modules because they own no state; `data-modeling/6accaff9` (a mutable constant must be frozen at assignment) covers every one of the twenty-odd frozen `String` constants in `Keys`/`Events`; `data-modeling/5bc538ba` already narrows the Ractor claim and `P5-22` narrows it once more |
| **Minitest conventions** | `--topic testing,assertions --section rules --brief` | 29 entries. `testing/4ef070df` (every test runs alone, in any order, fresh fixtures) is what forces every `Diagnostics` test to restore fiber storage in an `ensure` — a leaked `Fiber[:"trace.id"]` is visible to every later test in the same thread; `testing/7ecef8e8` and `/630ba094` name the four doubles 5b builds **fakes**; `testing/26b866e1` forbids `assert_nothing_raised`, which bites hardest here because `OBS-15`, `OBS-20` and `XCUT-20` are all "never throws" requirements — each is asserted on the *substituted value* and on the *diagnostic emitted*, never on the absence of a raise; `assertions/e8c05720` routes `OBS-3`'s empty-key rejection through `Model.required!` |
| **RuboCop and formatting** | `--topic tooling-and-quality-gates --section rules --brief` | Clean. **5b adds no cop.** The one it would have wanted — a `Dexpace/QualifiedCoreConstant` entry for `Logger` — cannot be written, and that is `OI-26` rather than a silent omission |
| **Styleguide-vs-design conflicts** | `--section conflicts --brief` | All six resolved; none open |

### The notes filed against the corpus by this phase

**One, filed at reconciliation rather than by this document, and one declined.**

- **`Fiber#storage=`'s `Symbol`-only key type, and `Fiber[]=`'s coercion of a `String` key — filed.**
  Verified: `Fiber.current.storage = {"s" => 1}` raises `TypeError: wrong argument type String (expected
  Symbol)`, while `Fiber["k.dot"] = 1` succeeds and stores under `:"k.dot"`. That is a real fact about the
  write side and `docs/knowledge/notes/observability.md` did not record it. This document did not file it
  **because the note file already existed and the `5c` agent was writing concurrently** — a second author
  appending to one note file loses an edit — and recommended instead that it be added as a third write-side
  property beside `OI-13`'s two. The pass that reconciled the two designs did exactly that, in one entry that
  also carries `5c`'s finding that fiber storage's copy-on-write protects the **slot** and not a mutable
  object held in it. The entry narrows `observability/e0f1e864` a second time, is flagged single-interpreter
  (3.4.10 only), and is what `R11`'s type argument and `5c`'s `R13` both now cite instead of restating.
- **`Symbol#name` versus `Symbol#to_s` — declined, unchanged.** Verified: `#name` returns the same frozen
  `String` on every call, `#to_s` a fresh unfrozen one. No harvested rule says otherwise — the corpus was
  queried (`--topic performance,data-modeling --grep 'symbol'`) and holds nothing on it — so a note would be
  adding a rule rather than overriding one, which is a styleguide amendment plus a harvest and not a
  `notes/` file. It is verified fact 10 below and a YARD comment at the fold. (The filed entry mentions the
  measurement in passing, as the reason the fold must not use `#to_s`; it does not turn it into a rule.)

## The verified Ruby facts this phase is built on

**Interpreter availability, stated before the facts because it limits every one of them.** Phases 3 and 4 ran
their facts on 3.2.11, 3.4.10 and 4.0.6 via `mise exec ruby@<v>`. **On this machine only 3.4.10 is
installed** — re-checked for this document: `ruby -v` is `ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM
[x86_64-linux]`; `mise ls` lists `bun`, `go`, `node` and `opencode` and no Ruby;
`~/.local/share/mise/installs` holds `bun`, `go`, `node` and `opencode` and no `ruby`; and `~/.rbenv`,
`~/.rvm` and `/opt/rubies` do not exist. Every fact below was run on 3.4.10 and on nothing else. Facts **1**,
**2**, **3**, **6** and **9** are of the floor-straddling kind this repository has been bitten by three times
— `URI::DEFAULT_PARSER` at 3.4.0, `StringIO#read(n, buf)`'s encoding at 3.4, `Data#with`'s `initialize` on
3.2 — and **5b's plan re-runs each on 3.2.11 and 4.0.6 before the code that rests on it is written**; each is
flagged inline and the inline flags and this list are the same five. `OI-13` already establishes that one
member of this family, `Fiber.current.storage = nil`, **does** differ on the floor, which is independent
evidence that the flag is not ceremonial.

**1. `Fiber[]=` writes and reads without a warning; `Fiber#storage=` warns on every call and rejects a
`String` key. FLOOR-STRADDLING.** Two `Fiber[]=` writes and a read produce zero warnings. One
`Fiber.current.storage = {p: 1}` produces one warning, category `:experimental`, text
`Fiber#storage= is experimental and may be removed in the future!`. `Fiber.current.storage = {"s" => 1}`
raises `TypeError: wrong argument type String (expected Symbol)`, while `Fiber["k.dot"] = 1` succeeds and the
map reads back `{"k.dot": 1}` — the `String` was coerced to a `Symbol`. `Fiber[:a] = nil` **deletes** the key:
`Fiber.current.storage.key?(:a)` is `false` afterwards and the map is `{}`. `Fiber.current.storage = {a: nil,
b: 1}` **retains** the `nil`: `key?(:a)` is `true` and `Fiber[:a]` reads `nil`.
*What it licenses:* `OBS-23`'s per-key push and restore, and `OBS-24`'s whole bridge, expressed with `Fiber[]=`
alone, with no warning and therefore no `NFR-7` problem (`R12`); and the statement that the diagnostic-context
key space is `Symbol`-shaped, which fixes the type of `Diagnostics::TRACE_ID` (`R11`).
*What it does not license:* a claim that `OBS-10`'s "Keys with null values MUST be skipped" is vacuous. It is
live, and `R12` says exactly when: a `nil`-valued key is invisible through `Fiber[]` and **visible** through
`Fiber.current.storage`, which is the reader `OBS-10`'s unfiltered mode must use.

**2. `Fiber.current.storage` returns a fresh, unfrozen `Hash` on every call, and mutating it does not escape.
FLOOR-STRADDLING.** `s1.equal?(s2)` is `false` for two consecutive reads; `s1.frozen?` is `false`;
`s1[:injected] = 9` leaves `Fiber[:injected]` `nil`. In a fiber created with `Fiber.new(storage: nil)`,
`Fiber.current.storage` is **`nil`**, not `{}`.
*What it licenses:* `OBS-24`'s "immutable snapshot" as `Fiber.current.storage` **already being the copy**, so
capture is one read plus one `#freeze` and no defensive duplication — and the normalisation `nil → {}` that
`OBS-24`'s "capture on the originating thread" needs when the originating fiber opted out.
*What it does not license:* treating the returned map as a live view. Anything that reads it twice and expects
the same object is wrong, and any code that writes into it is writing into a discarded copy.

**3. The per-key union restore is exact, and its one gap is unreachable without the setter it avoids.
FLOOR-STRADDLING.** With `prior = Fiber.current.storage` and a snapshot installed per key, restoring with
`(prior.keys | snapshot.keys).each { |k| Fiber[k] = prior[k] }` yields `Fiber.current.storage == prior`
**exactly** — the installed `:"span.id"` is gone, the overwritten `:"trace.id"` is back, and the untouched
`:other` is untouched. The one context it cannot restore is one containing a key whose value is literally
`nil`: `prior2 = {a: nil, b: 1}` restores as `{b: 1}`. Such a `prior2` is only constructible through
`Fiber#storage=`.
*What it licenses:* `R12`'s whole answer, and `P5-23`.
*What it does not license:* omitting the gap from the YARD block. It is stated at the method, because a host
that calls `Fiber#storage=` itself can produce the input, and a caller has to be able to read that.

**4. A scoped `Warning.warn` filter around `Fiber#storage=` works, and 5b still does not need one.**
Prepending a module on `Warning`'s singleton that swallows `category == :experimental` messages containing
`Fiber#storage=` suppresses the warning while the module is installed; `Warning[:experimental]` is `true` by
default and setting it is process-global.
*What it licenses:* nothing 5b ships. It is recorded so `R12`'s rejected alternatives are rejected on evidence
rather than on assertion, and so phase 8 — which meets `ASYNC-9`/`ASYNC-11` and may have no choice — has a
measured starting point.
*What it does not license:* installing the filter. Even a scoped `prepend` on `Warning` is a mutation of a
process-global object, which is the imposition this port already refuses for `Regexp.timeout`.

**5. The inert chain's allocation count depends on the arguments, and only a `String` literal makes it depend
on the file's magic comment.** With `GC` disabled and `# frozen_string_literal: true` present, a frozen
singleton whose builder methods return `self` and whose `#emit` is a no-op, driven 1000 times: with a `Symbol`
key and an `Integer` value, **2** total allocations; with a frozen `"x"` literal and `.cause(nil)`, **8**;
with an interpolated `"x#{i}"`, **1992**. With the magic comment removed from the same file: the `Symbol`
and `Integer` case is **2**, unchanged; the `"x"` literal case is **1008**. The delta between a 1000-iteration
loop and a 2000-iteration loop is **0** with the comment and **1000** without it, for the `String`-literal
form.
*What it licenses:* `R8`'s answer — write the assertion with arguments that cannot allocate, and assert the
two-loop delta is exactly `0`. The delta removes the 8-versus-1 constant warm-up so the assertion needs no
fudge factor, and the argument choice removes the file dependence.
*What it does not license:* **the charter's R8 framing that a delta measurement is "insensitive to the
caller's allocations".** It is the opposite: the delta isolates the per-iteration cost, and the caller's own
per-iteration `String` allocation is exactly what a per-iteration cost is. Corrected here and in the report,
which is where a finding against a committed phase document goes; **re-measured independently on 2026-09-09 by
the reconciliation pass**, which reproduced the direction and the magnitude — a `String`-literal chain in a
file without the magic comment gave 1001 at 1000 iterations and 2000 at 2000, a delta of 999, while the
`Symbol`/`Integer` chain gave a delta of 0 in both files. (999 rather than a clean 1000 is first-call warm-up
in the smaller loop, which is itself an argument for the delta form over an absolute count.) The charter's
*other* candidate — "pass only frozen constants" — is not corrected and is half of what ships: it is the same
answer as "arguments that cannot allocate", stated less precisely, because a frozen `String` constant is
allocation-free while a frozen `String` **literal** is only allocation-free where the magic comment is.

**6. `URI::RFC3986_PARSER` raises on some inputs, silently escapes on others, and raises on any component
assignment to an opaque URI. FLOOR-STRADDLING.** Parsing: `"not a url at all"`, `"https://h/a b"` and
`"https://h/x?a=%zz"` raise `URI::InvalidURIError`; `"https://h/x?a=%FF"`, `"https://h/x?a=%e0%a4"`,
`"https://h/x?a=[1]"` and `"https://h/x?a=|"` all parse. `"/cb?code=SECRET"` parses with `scheme == nil`.
`"https://h/x?"` gives `query == ""` and `#to_s` `"https://h/x?"`. `"http://h/p#a?b=c"` gives `query == nil`
and `fragment == "a?b=c"`. `"#frag"` gives `path == ""`, `query == nil`, `fragment == "frag"`. `""` parses,
with `path == ""`. Rebuilding: `u.userinfo = "***:***"` renders `"https://***:***@h/x"`; `u.query = "a=<>"`
renders `"...?a=%3C%3E"` — **escaped, not rejected**; `u.query = "a=\n"` renders `"...?a="` — the newline is
**dropped**; `u.fragment = "k=<>"` renders `"#k=<>"` — **not** escaped, asymmetrically with `query=`;
`u.query = ""` renders the trailing `?` and `u.query = nil` removes it. On an **opaque** URI —
`mailto:a@b.c`, `urn:isbn:123`, `data:text/plain,hello`, all of which parse with a non-`nil` scheme —
`userinfo=` raises `URI::InvalidURIError: cannot set user with opaque` and `query=` raises
`query conflicts with opaque`. `scheme=` and `host=` raise `URI::InvalidComponentError` on bad input, and
every one of these is under `URI::Error < StandardError`.
*What it licenses:* `OBS-14`'s three clauses with one discipline — an emptied query is assigned `""` and never
`nil`; `OBS-16`'s parseable/relative branch as `scheme.nil?` and **not** a rescue; and the statement that
`OBS-15`'s "rebuild failure" is a real, reachable branch rather than defensive padding, reachable through a
`Location: mailto:...` header.
*What it does not license:* making the opaque branch the mechanism. `P5-27`'s rule — **never assign a component
that was absent** — makes it unreachable for every input the redactor can construct a rewrite for, because an
opaque URI has `userinfo == nil` and `query == nil` by construction. The `rescue` stays as the totality
backstop.

**7. `String#downcase` raises `ArgumentError` on a decoded query-parameter name carrying invalid UTF-8, and
`ArgumentError` is not a `URI::Error`.** `URI.decode_www_form_component("%FF")` returns a one-byte `String`
tagged UTF-8 with `valid_encoding? == false`; `#downcase` and `#casecmp?` on it raise
`ArgumentError: input string invalid`, while `==` returns `false` without raising and `#scrub("?")` returns
`"?"`. `URI.decode_uri_component("%zz")` and `URI.decode_www_form_component("%zz")` also raise
`ArgumentError`, though the parser rejects `%zz` first.
*What it licenses:* `R9`'s rescue clause — `StandardError`, not `URI::Error` — on evidence rather than on
caution, and the secondary discipline of folding through `#scrub` so the common case never reaches the rescue.
*What it does not license:* dropping the rescue because `#scrub` covers it. `OBS-6`'s rendering path calls
`#to_s` on caller-supplied objects inside the same containment, and fact 8 is why that cannot be reasoned away.

**8. Rendering is reachably total-hostile in three independent ways.** `Class.new(StandardError).name` is
`nil`. `BasicObject.new.to_s` raises `NoMethodError`, which `rescue StandardError` catches. An object whose
`#to_s` raises propagates a `RuntimeError` through `String()` and through `"#{}"` interpolation alike. And an
exception class whose `#message` itself raises propagates a `RuntimeError` from the *message* read, not from
the class-name read.
*What it licenses:* §8.1's "the rendering path rescues `StandardError` per value and substitutes
`[unrenderable <ClassName>]`", with the rescue placed around **both** halves of `OBS-6`'s
`SimpleClassName: message` form and with a `nil` guard on `#name`.
*What it does not license:* `e.class.name.split("::").last` without a `nil` guard. `Class.new(StandardError)`
appears in test suites and in metaprogrammed adapters, and it makes `OBS-6`'s own totality clause fail on the
totality path.

**9. `OBS-7`'s cap is a byte figure, and a byte-sliced multibyte string is not a valid `String`.
FLOOR-STRADDLING.** `("é" * 5000)` is 5000 characters and 10000 bytes; `#byteslice(0, 8191)` yields 8191 bytes
with `valid_encoding? == false`; `#scrub("")` on that yields a valid 4095-character `String`;
`s[0, 8192]` yields 16384 bytes.
*What it licenses:* truncating on **bytes** with `#byteslice` followed by `#scrub("")` and then the marker
suffix (`P5-29`), which is the only reading under which "bounded maximum length (reference: 8 KiB)" is a
memory bound.
*What it does not license:* asserting `output.length == cap + suffix.length`, which is `OBS-7`'s conformance
sentence written in characters. The 5b assertion is on **bytesize**, and the divergence is stated in the test
rather than resolved silently.

**10. `Symbol#name` returns the same frozen `String` on every call; `Symbol#to_s` does not.**
`:"trace.id".name.frozen?` is `true` and two calls return the same object; `#to_s` returns a fresh unfrozen
`String` each time.
*What it licenses:* the diagnostic-context fold converting a `Symbol` storage key to an `OBS-39` field key with
zero allocation per key per event.
*What it does not license:* using `#name` on anything but a `Symbol`. It is not a general accessor.

**11. `Encoding.find` raises on an unknown name, and the BINARY-source transcode destroys every non-ASCII
byte.** `Encoding.find("no-such-charset")` raises `ArgumentError`.
`"café".b.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace)` returns `"caf"` plus two U+FFFD
characters. Retagging first and naming both encodings —
`bytes.dup.force_encoding(enc).encode(::Encoding::UTF_8, enc, invalid: :replace, undef: :replace)` — returns
`"café"` for UTF-8 bytes and for ISO-8859-1 bytes alike, and returns a single U+FFFD for a truncated
`"\xE4\xBD"` without raising. Empty input yields `""`.
*What it licenses:* `OBS-38`'s renderer as phase 3b's corrected recipe applied to a preview, with
`MediaType#charset`'s documented `nil`-for-unknown making `Encoding.find` unreachable.
*What it does not license:* copying design §3.1's sentence, which is `OI-7`'s finding and is still open.

**12. `Thread::Mutex` is non-reentrant and per-fiber-owned; `Kernel#warn` routes through `Warning.warn`.**
`m.synchronize { m.synchronize { } }` raises `ThreadError: deadlock; recursive locking`; `m.owned?` inside
`Fiber.new { }.resume` while the enclosing thread holds the lock is `false`. `warn "hello"` reaches a
prepended `Warning.warn` with `category: nil`.
*What it licenses:* `OBS-8`'s latch as a flag flipped under a mutex **released before the sink call** — not as
prudence but because a sink whose `#debug` yields to another fiber of the same thread would otherwise
deadlock; and 5b's tests capturing `Kernel#warn` at the two `ProxyResolution` sites rather than letting a
required warning escape and fail `DexpaceTestCase`.
*What it does not license:* a lock-free flag. A bare boolean flip is atomic on CRuby and not on JRuby or
TruffleRuby, which §1 fixes as the port's rule.

**13. `Async::Future` offers `#on_settle` and no combinator.** Phase 2's shipped surface is `#settled?`,
`#cancelled?`, `#outcome`, `#value(cancellation:)`, `#wait(cancellation:)`,
`#on_settle { |settlement| … }` — "invoked exactly once, on the settling thread-or-fiber" — and
`#cancel(reason)`. There is no `#then` and no `#map`.
*What it licenses:* the async step's shape: register `#on_settle` and return **the same future**, so no second
future is created and `PIPE`'s chain is untouched.
*What it does not license:* assuming the callback runs on the caller's thread. It runs on the settling one,
which is why `OBS-24` exists and why `OBS-30`'s must-not-throw contract has a sharper consequence on the async
path — stated in the cross-cutting section.

## R8 — what `OBS-1`'s allocation test measures, and where its file-level precondition lives

**The question.** The charter's verified fact 6 found that a chain driven with a bare `"x"` literal allocates
one object per call unless the measuring file carries `# frozen_string_literal: true`. Every file in this
repository carries it by rule, so the in-gem test is safe — but `OBS-1`'s conformance clause is one
`dexpace-conformance` will restate (phase 8, `DEF-22`), **in a different gem**, and a conformance file that
loses the magic comment fails a correct implementation. The charter offers two candidate answers: make the
assertion insensitive to the caller's allocations (by measuring the delta of two loops, or by passing only
frozen constants), or state the precondition in a comment the later gem copies.

**The answer, and it is a third one the charter's framing rules out.** *Neither* candidate is what makes the
assertion safe, because **the delta of two loops is not insensitive to the caller's allocations at all** —
verified fact 5. With a `String` literal and no magic comment, a 1000-iteration loop allocates 1002 and a
2000-iteration loop allocates 2002; the delta is exactly **1000**, one per iteration. The delta does not hide
the caller's cost, it isolates it, which is the whole reason a delta is a better measurement than an absolute
count. **What buys the insensitivity is the second half of the charter's first candidate, and only that half:
pass arguments that cannot allocate.** With a `Symbol` key and an `Integer` value, the same measurement is
**2** with the comment and **2** without it, and the two-loop delta is **0** in both files.

So the assertion 5b writes, and the assertion `dexpace-conformance` restates, is:

```
# frozen_string_literal: true          # present by repository rule, and NOT what makes this correct
def inert_allocations(iterations, event)
  GC.disable
  before = GC.stat(:total_allocated_objects)
  iterations.times { event.field(:k, 1).event(:x).cause(nil).emit }
  GC.stat(:total_allocated_objects) - before
ensure
  GC.enable
end

assert_equal 0, inert_allocations(2_000, e) - inert_allocations(1_000, e)
```

Three properties, each stated because each is a thing a reader would otherwise get wrong.

1. **Every argument is a `Symbol`, an `Integer`, or `nil`.** None of the three allocates on any Ruby, with or
   without the magic comment. `#event(:x)` takes a `Symbol` rather than a `String` for the same reason — and
   `OBS-4`'s "An empty name MUST clear the tag" is then tested separately with `#event("")` and `#event(nil)`,
   in a test that does not measure allocation.
2. **The measurement is a delta of two loop sizes, asserted `== 0`, not an absolute count under a bound.**
   Verified fact 5 shows an absolute count of 8 for a chain that allocates nothing per call — interpreter
   warm-up, method-cache population, the block object itself. An absolute assertion would need a fudge factor,
   and a fudge factor is what hides a one-per-thousand regression.
3. **The precondition still appears, as a comment, and it is explicitly labelled as not load-bearing.** The
   line above is written out in 5b's own suite and is what phase 8 copies. A comment that says "this file must
   carry the magic comment" invites a later author to believe the assertion is correct *because* of it; a
   comment that says "the argument types are what make this file-independent; the magic comment is a
   repository rule and not this test's precondition" survives the copy.

**And what that forces about `Event::INERT`'s visibility.** The identity half of `OBS-1`'s conformance clause
is "assert the returned event is the shared singleton (**reference-identical across calls**)", which is
`assert_same(Dexpace::Instrumentation::Event::INERT, logger.event(Severity::VERBOSE))` — a **qualified**
reference to the constant, from a different gem. `execution-context/c2eb344c`'s superseding note records that
a `private_constant` on `Dexpace` is reachable by a bare reference from inside `module Dexpace; …` and **not**
through a qualified reference or from the compact `module Dexpace::X` form. So `Event::INERT` **must be
public**, and it is public for exactly the reason phase 4a made `NO_SPAN` and `NO_TRACER_FACTORY` public where
its other new internals are `private_constant`: a requirement that asserts identity needs a name the assertion
can write. The class behind it, `Event::Inert`, stays `private_constant`.

**What is not claimed.** That the enabled path allocates nothing. It cannot, `OBS-1` does not ask it to, and
`observability/956f1603` records the limit. The assertion above is run against `Event::INERT` and against a
logger whose sink predicate is `false`; a separate test drives a *live* event and asserts only that it emits,
never an allocation bound.

## R9 — `OBS-15`'s totality against a parser that raises on some inputs and succeeds on others

Three questions, and the first is a question about the shape of the redactor rather than about a rescue.

### The redactor has two entry points, because `OBS-15` and `OBS-16` give opposite answers to one input

`OBS-15`: "on any parse/rebuild failure it MUST return a fixed sentinel (`[malformed url]`)". `OBS-16`: "when
the value is relative **or otherwise unparseable**, the redactor MUST keep the path and drop everything after
it … appending a fixed `?***` marker whenever the value carried a query OR a fragment". Both are MUSTs and
they prescribe different outputs for the same unparseable string. They are not in conflict: `OBS-15` governs
**URL redaction** and `OBS-16` governs **a URL arriving as a header value**, and the header case is required
to degrade *usefully* rather than to a sentinel because a `Location` a reader cannot see the path of is a
useless log line. Any implementation with one entry point loses one of the two requirements whichever way it
resolves the collision. So:

```
Redactor#url(value)                 -> String   # OBS-11..OBS-15. Sentinel on failure.
Redactor#header_value(name, value)  -> String   # OBS-16..OBS-18. ?*** marker on failure.
```

`P5-25`. `OBS-39`'s `url.full` field is always `#url`, and the header fields are always `#header_value`.

### What counts as a rebuild failure, and why it is nearly unreachable by construction

Verified fact 6: **`query=` and `fragment=` never raise on content.** `a=<>` is escaped to `a=%3C%3E`;
`a=\n` silently drops the newline; `a=\0` becomes `a=%00`; and `fragment=` does not escape `<>` at all, which
is an asymmetry with `query=` worth knowing and irrelevant to a redactor that writes only `***` and
`api-version`. What **does** raise is assigning any component to an **opaque** URI — `mailto:`, `urn:`,
`data:` — with `URI::InvalidURIError: cannot set user with opaque` and `query conflicts with opaque`. Those
parse cleanly with a non-`nil` scheme, so they reach `OBS-16`'s "parseable absolute" branch, and a
`Location: mailto:support@example.com` header is not hypothetical.

**The rule that makes it unreachable is `P5-27`: the redactor never assigns a component that was absent.**
`userinfo=` runs only when `#userinfo` is non-`nil`; `query=` runs only when `#query` is non-`nil`;
`fragment=` runs only when `#fragment` is non-`nil`. An opaque URI has all three `nil` by construction, so it
round-trips through `#to_s` untouched and correctly — a `mailto:` carries no credential in a userinfo
component because it has no userinfo component. The rule is not a special case for opaque URIs; it is the
minimal-mutation rule that `OBS-14`'s "MUST NOT alter scheme, host, port, or path" already implies, applied to
the three components `OBS-14` does not mention.

**The rebuild `rescue` still ships.** It is the totality backstop, not the mechanism, and it is asserted by a
test that constructs the failure directly — an opaque URI handed to the *internal* rewrite with the guard
bypassed — so the branch has coverage rather than a comment claiming it is unreachable.

### The rescue is `StandardError`, and the fact that decides it is not about `URI` at all

Verified fact 7. The parser **accepts** `%FF` in a query. `OBS-12` requires the parameter name to be
"decoded, compared case-insensitively" against the allow-list. `URI.decode_www_form_component("%FF")` returns
a `String` tagged UTF-8 with `valid_encoding? == false`, and `String#downcase` on it raises
`ArgumentError: input string invalid`. **`ArgumentError` is not under `URI::Error`.** A redactor whose rescue
clause is `URI::Error` therefore propagates an exception out of `https://h/x?%FF=secret` and breaks `OBS-15`,
`OBS-20` and `XCUT-20` at once, on an input a hostile or merely broken server can produce. `P5-26`.

Two disciplines go with it, and both matter:

- **Fold through `#scrub` before comparing.** `name.scrub("").downcase` cannot raise and produces a stable
  comparison for the invalid-byte case (an unmatchable name, which default-denies to `***` — the safe
  direction). The rescue then covers what `#scrub` does not: `OBS-6`'s rendering path lives inside the same
  containment and calls `#to_s` on caller-supplied objects (verified fact 8).
- **`rescue StandardError`, never a bare `rescue` and never `Exception`.** A bare `rescue` is `StandardError`
  in Ruby, but writing it invites the reading that `Exception` was meant; and swallowing a `SignalException`
  or a `NoMemoryError` inside a log line is the failure `XCUT-20` does not ask for.

### `OBS-16`'s three-way branch is two branches over two different objects

"Relative" and "unparseable" reach the rule by two routes and the design says so rather than pretending one
branch covers both:

| Route | Reached when | How the branch reads its inputs |
|---|---|---|
| **absolute** | `P.parse` returned and `#scheme` is non-`nil` | delegate to `#url` |
| **relative** | `P.parse` returned and `#scheme` is `nil` | `#path`, and "carried a query or a fragment" is `!query.nil? \|\| !fragment.nil?` on the parsed object |
| **unparseable** | `P.parse` raised | **string surgery on the raw value**: the path is the value up to the first `?` or `#`, whichever comes first; "carried a query or a fragment" is `value.include?("?") \|\| value.include?("#")` |

Three things about that table are stated because each is a test a reader would otherwise write wrong.

- **The presence test is `!nil?`, not truthiness.** Verified: `P.parse("/cb?")` gives `query == ""`. A
  present-but-empty query is a query — `OBS-14` requires the trailing `?` preserved on the absolute path for
  the same reason — so `"/cb?"` redacts to `"/cb?***"` and `if query` would return it verbatim.
- **The unparseable route has no parsed object, so it cannot reuse the relative route's code.** There is no
  `#path` to read. Writing one branch and calling `P.parse` twice does not help: the second parse raises too.
  `P5-28`.
- **A fragment-only value has an empty path.** Verified: `P.parse("#frag")` gives `path == ""`. So `"#frag"`
  redacts to `"?***"`, which looks wrong and is right — the requirement's rule is "keep the path" and the path
  is empty, and the marker is what says a fragment was dropped.

And one that decides the fragment work: **`URI` does not tokenise a fragment.** `P.parse("https://h/p#a=1&b=2").fragment`
is the whole string `"a=1&b=2"`. `OBS-13` requires `key=value` tokens inside it to be redacted like query
values while "a plain fragment with no `=` MUST be preserved verbatim", so the fragment tokenizer is
hand-rolled — which is design §8.1's own split (`observability/80c9594d`) reached independently here.

## R10 — `OBS-19`'s disposition, given §12 calls it vacuous for `Net::HTTP`

**`OBS-19` is carried ⏳ against a proposed new deferral targeting phase 8. 5b ships no verbosity policy.**

The requirement's subject is stated in its first six words: "**A transport that drops** a caller-set request
header it cannot encode SHOULD surface the drop with a configurable verbosity policy". Three facts decide the
disposition together.

1. **Core has no transport and drops no header.** `HTTP-17`/`HTTP-18`'s wire-boundary re-validation is
   `DEF-25`, phase 8's, and it **raises** rather than drops — which is the general shape of this port, not an
   accident: a header a caller set and the wire cannot carry is a caller bug, and phase 1 made it an error.
2. **§12's `OBS` row already records the emission site as vacuous for the one MVP transport**: "`OBS-19`
   (SHOULD) is vacuous for `Net::HTTP`, which raises on an unencodable header rather than dropping it, and
   binds any adapter that drops."
3. **A three-mode policy object with no caller and no test is `OI-8`'s exact shape**, and the charter forbids
   it in as many words: "It must not ship a policy with no caller and no test that exercises it." `OI-8` is
   open right now precisely because phase 3a shipped `TeeSink#clear_tap` for a caller phase 3b then did not
   need, and the item's own body states the asymmetry that makes this cheap to avoid now and expensive later:
   before the first release tag, not shipping a method costs one edit; after it, removing one is a public
   signature disappearing, which `NFR-4` treats as a breaking change.

**What was weighed against deferring, and why it lost.** The charter's `R10` notes that the policy's throttle
"shares its latched-flag mechanism with `OBS-40`'s once-per-logger diagnostic, so it is nearly free". That is
true of the *throttle* and false of the *policy*. The throttle is one `private_constant` latch and 5b builds it
anyway for `OBS-40`. The policy is a public closed set of three modes, a public constructor keyword on
something, a default, an RBS signature, a YARD block, a surface-manifest row and a `sig/` mirror — and no
core code path that reaches it. Shipping the cheap half and deferring the expensive half is exactly what this
disposition does.

**What makes the deferral cheap to pick up**, stated in the proposed row so phase 8 does not re-derive it: both
halves the policy needs already exist after 5b. Its three modes are "WARN every occurrence / WARN the first per
name then VERBOSE / VERBOSE only", which is two `Severity` constants and a per-name latch; `Severity` ships
here and the latch ships here with `OBS-40` as its exercising caller. Phase 8's adapter writes a small
`Data` over both, at the one call site that actually drops a header, with a test that drops the same name
twice.

**And the checklist consequence, which is the reason this is a deferral and not a note.** §12's word is
"vacuous". A checklist row is one row per ID with a target, and "vacuous" names no target, no gem and no event
— it is a statement about `Net::HTTP` and not a disposition of the requirement. `⏳` requires a `DEF-<n>`, and
none of the existing thirty-nine covers `OBS-19`: `DEF-9` covers `OBS-32` and `OBS-37` and its condition is the
OTel and async adapters, which is not this. So a row was written and is filed as **`DEF-41`**. `P5-32`
records that this reads §12 differently from the way §12 words it, and `OI-27` records that it reads the
charter's 5b scope table differently too.

## R11 — the instrumentation step's two slots, and who declares `trace.id` and `span.id`

Charter boundary 15 fixes what is not in question: **the step is 5b's object, installed at `Stages::LOGGING`,
and `5c` fills a tracer slot and a meter slot in it. Neither segment ships a second step, a second key-name
constant, or a second no-op meter.** Four things were open; all four are decided, and the decisions are
**reconciled with `5c`** rather than pending it. Two went 5b's way, two went `5c`'s.

### The slots are two constructor keywords with constant defaults, not a configuration read

```
Dexpace::Instrumentation::Step.build(
  logger:, redactor:, level:,
  tracer_factory: Dexpace::Instrumentation::NO_TRACER_FACTORY,
  meter:          Dexpace::Instrumentation::NO_METER,
  preview_bytes: nil, clock: Dexpace::Clock::SYSTEM
)
```

**`5c`'s answer, adopted.** The draft made both slots required and undefaulted; `5c` defaulted them to phase
4a's `NO_TRACER_FACTORY` and to its own `NO_METER`, and that is what ships.

**Why keywords and not a configuration read.** A configuration read would put two duck-typed objects into the
layered chain, whose whole surface is `String`-valued keys resolved from `ENV` and a `configure` block
(`CFG-1`, `CFG-5`–`CFG-7`). There is no tier of that chain that can carry a tracer factory, and inventing one
would be `5a`'s P11 failure — fabricating a source — arriving one sub-phase later. A caller who wants the
level from configuration resolves it with `HTTPLogging.resolve` and passes the result; the same caller passes
the two collaborators directly, which is what `CFG-11`'s injectable-seam shape already does for the env and
property sources.

**Why defaulted rather than required, and why the draft's argument does not survive.** The draft's reason for
requiring both was that "`meter:` cannot be defaulted in 5b without naming `5c`'s no-op meter, which does not
exist and which this document may not invent", plus a symmetry argument that two slots with two different
defaulting rules is drift. The first reason is an artefact of the two designs being written in parallel and
nothing else: `NO_METER` is shipped by `5c` in the same phase, so there is nothing to invent. The second
survives and now argues the other way — both slots are defaulted, so there is no asymmetry to memorise.

Three things decide it on the merits, and the third is the one the draft could not see.

1. **`CTX-14` already puts a `tracer_factory` on every context**, and `CTX-15`/`OBS-25` make
   `Bundle::NONE.tracer_factory` the published no-op. A **required** keyword makes every caller supply a
   second source of truth for an object the request's own context already carries, and makes phase 6's
   `Pipeline.standard` (`DEF-39`) name the no-op explicitly in a preset. `5c`'s precedence is what the step
   implements: **the request context's bundle when it is not `Bundle::NONE`, else the step's keyword, else the
   constant.** 5b's step honours that ordering and this document does not restate `5c`'s argument for it.
2. **`OBS-34` defaults logging to `none` and `XCUT-19`(e) makes body logging off by default**, so the
   untraced, unmetered, unlogged step is the *default* configuration of this SDK rather than an edge case.
   A signature in which the default configuration cannot be written without naming two constants is a
   signature at odds with the requirement's own default.
3. **`OBS-25`'s allocation clause is asserted by reference identity from a qualified constant**
   (`execution-context/b58728da`), and a constant default *is* that constant. A required keyword defended
   nothing here: it neither made the identity assertion easier nor kept a configuration read out — the
   paragraph above already does that, and `5c`'s own reason 1 for rejecting the read is the same one.

`NFR-4` is not the deciding argument in either direction and the draft over-weighted it: adding a default
later widens and is safe, but so is shipping the right default now, and the lock only bites on *changing* an
existing default. `P5-33`, rewritten.

### `OBS-34`'s independence clause is a structural property of the step body, and the test asserts the property

> "Span lifecycle AND metric recording (request counter + latency histogram) run on every request independent
> of the log level, so 'none' silences log events without disabling tracing or metrics."
> *Conformance: at none assert no request/response events but the span still starts/ends and the
> counter/histogram still record.*

The expression is one sentence: **the step body contains exactly two `logger.event(…)` sites, both inside
`Instrumentation.contain`, both under the level guard; and every tracer and meter call is outside both.**

Every name below is `5c`'s and is written out rather than deferred: `_TracerFactory#tracer` is phase 4a's,
`_Tracer#start_span` and `_Span#finish` are `5c`'s span protocol, `Tracing.correlate` and `Scope#close` are
`5c`'s scope handle, and `_Meter#create_counter` / `#create_histogram` with `_Counter#add` and
`_Histogram#record` are `5c`'s metrics SPI. The two instruments are manufactured **once, in `.build`**, not
per request — `OBS-31` returns shared instrument singletons and `OBS-25` forbids per-call allocation on the
no-op path, so a per-request `create_counter` would pay a lookup for nothing.

**`attributes:` is optional on both instruments and 5b passes none, which is stated because a reader will
expect dimensions.** `OBS-31`'s MUST is that the Meter manufacture instruments "each accepting per-measurement
key/value attributes" — an obligation on the *instrument*, and 5c's `_Counter#add` / `_Histogram#record`
declare it as `?attributes: Hash[String, untyped]?`. No `OBS` requirement fixes an attribute set for these two
instruments: `OBS-32`'s semantic conventions, which would, are `5c`'s ⏳ `DEF-9`. And 5c's verified fact 1
prices the alternative — an inline hash literal at a call site allocates ~1 per call whether or not the callee
splats — so an invented dimension set would cost one allocation per request to carry a vocabulary nothing has
chosen. When `DEF-9` lands, the set is hoisted to a frozen constant and passed; neither signature changes.

```
def call(request, cursor)
  started  = @clock.monotonic
  factory  = tracer_factory_for(request)                             # bundle if not NONE, else @tracer_factory
  tracer   = factory.tracer(operation_name_for(request))             # 4a's #tracer — once per operation, OBS-29
  span     = tracer.start_span(operation_name_for(request))          # 5c's _Tracer#start_span
  scope    = Tracing.correlate(span, bundle_for(request))            # 5c's _Scope — OBS-22, OBS-23
  logged   = @level.at_least?(HTTPLogging::HEADERS)
  request  = wrap_bodies(request) if @level.at_least?(HTTPLogging::BODY)     # OBS-34, OBS-36
  Instrumentation.contain(@logger, event: Events::INSTRUMENTATION_LOG) { emit_request(request) } if logged
  response = cursor.call(request)
  Instrumentation.contain(@logger, event: Events::INSTRUMENTATION_LOG) { emit_response(...) } if logged
  response
rescue ::StandardError => e
  ...
ensure
  scope.close                                                        # 5c's Scope#close — OBS-22, OBS-23
  span.finish                                                        # 5c's _Span#finish — OBS-21
  @request_counter.add(1)                                            # 5c's _Counter#add
  @latency_histogram.record((@clock.monotonic - started) * 1000.0)   # 5c's _Histogram#record
end
```

**`Tracing.correlate` and not `Tracing.activate`, because `OBS-23` is what makes `OBS-10` non-vacuous.**
`correlate` pushes `Diagnostics::TRACE_ID` and `::SPAN_ID` from the bundle for a recording span and, for a
non-recording one, "skips the push and delegates to plain current-span activation" — the requirement's own
words, so one call covers both branches and the step needs no test on the recording flag. Without it the
default allow-list `OBS-10` mandates would have nothing to fold on any request.

**`5c` prefers the block form, and 5b's async step is where that preference cannot reach.** `5c`'s `P5-45`
makes `Tracing.with_correlated_span(span, bundle) { … }` the primary form and the bare handle secondary, on
`resource-management/bf5560dc`'s block rule, and its design said the block form "is what `5b`'s **sync** step
calls". **That sentence was corrected at the plan reconciliation and now reads the other way**: both steps take
the handle. For `Step` the block form would work, but `#call` already owns a `begin`/`rescue`/`ensure` for
`span.finish` and the two unwrapped meter calls, so a block would add a frame and a nesting level around a body
that needs the `ensure` regardless — and `AsyncStep < Step` shares one `correlate_span` helper, which a split of
forms would break. For `AsyncStep` a block is impossible outright, because
the span outlives `#call` — the future settles later and the `ensure` above moves into the `#on_settle`
callback, so activation and close are two statements on two stacks and the handle is the only form that
expresses it. **Both steps therefore use `correlate`/`#close`**, so one shape covers both runtimes, which is
`P5-34`'s own argument for one `Emitter` applied to the scope handle. That is a use `5c`'s `P5-45` explicitly
provides for ("a consumer spanning a non-lexical region needs one") and it does not reopen `P5-45`.

Two consequences are stated rather than left to be discovered.

- **The level is read into a local once, at the top, and consulted at exactly three sites** — the two emissions
  and the body wrapping. A step that re-read `@level` inside a helper would be one refactor away from a fourth
  site, and the fourth site is always the one that guards a span.
- **`OBS-20`'s asymmetry is the same structural property seen from the other side.** The two emissions are
  inside `contain`; the four tracer/meter calls are outside it, in the `ensure`, unwrapped. A comment at the
  `ensure` names `OBS-20` and `OBS-30` and says that a throwing tracer or meter **will** propagate, because
  that is a requirement and not an oversight.

**The test that discharges `OBS-34`'s conformance clause is this one, and it is 5b's.** It drives the step at
`HTTPLogging::NONE` with a recording sink and with `5c`'s `RecordingTracer` and `RecordingMeter`, and asserts
four things in one test: the sink saw **zero** writes; the tracer saw exactly one `start_span` and one
`finish`; the counter recorded once; the histogram recorded once. That is `OBS-34`'s conformance sentence
transcribed, and a second test at `HTTPLogging::BODY` asserts the preview fields, which is the clause's other
half.

**`5c` proves a different thing and neither is a substitute for the other.** `5c`'s suite asserts that its own
objects load and run with `Dexpace::Instrumentation::Event` undefined — a structural guard that nothing in the
tracing half can acquire a dependency on the logging half. That is `5c`'s regression on `5c`'s objects; it says
nothing about whether the step calls them at level `none`, which is what `OBS-34` requires asserted. The two
mechanisms are named here as two, and the requirement's conformance clause is discharged by the step test
above.

**The names are `5c`'s and are now fixed**, not assumed: the recording tracer, span and meter fakes are `5c`'s
files under `test/support/` (`P5-48`), and 5b's step tests **reuse them rather than adding a second set** —
which is this document's own open question 6 answered from the other side, and avoids the double-fake drift
`DEF-29` will otherwise have to consolidate.

### 5b declares `trace.id` and `span.id`, as `Symbol`s — and `5c`'s counter-proposal, weighed

**`5c` proposed the opposite on both counts** — `Dexpace::Instrumentation::TRACE_ID_KEY` and `::SPAN_ID_KEY`,
frozen `String`s, declared by `5c` — on the rule that "a constant owned by the writer cannot drift from what
is written; a constant owned by the reader can", `OBS-23` being the writer. **5b's constants stand.** The
argument is below and `5c` cites it rather than restating it; the draft's own reasoning is narrowed, because
one half of it turned out to license less than it looked like it did.

**Ownership: the anti-drift rule selects no owner here, and a different property does.** `5c`'s rule is sound
in general and inapplicable in this instance, because *both* requirements state the literal key names.
`OBS-23` (MUST): "push the trace id and span id onto the thread-local diagnostic context (**under keys
'trace.id' and 'span.id'**)". `OBS-10` (MUST): "The default allow-list MUST be **exactly {trace.id,
span.id}**." Neither constant derives from the other; each is pinned by its own MUST, so a divergence is a
conformance failure on both sides at once and there is no reader that can drift from a writer. What does
select an owner is that one of the two requirements needs the pair **as a collection** — `OBS-10`'s default
allow-list is a value 5b has to construct and hand to `Diagnostics.folded` — while `OBS-23` needs two
scalars it writes one at a time. The collection and its members belong in one place, and that place is where
the collection is used.

**Type: `Symbol`, on the reader rather than on the setter the draft cited.** The draft's reason was that
`Fiber#storage=` raises `TypeError` on a `String` key while `Fiber[]=` coerces one, "so the diagnostic-context
key space **is** `Symbol`-shaped whatever a constant declares". Both halves are verified (fact 1, re-verified
at reconciliation) but the first licenses less than the draft claimed, because `R12` decides that
`Fiber#storage=` is **never called in `lib/`** — a fact about a call this segment does not make cannot by
itself force a type. What does force it is the reader `OBS-10`'s unfiltered mode is obliged to use:
`Fiber.current.storage` returns **`Symbol` keys, always, whichever setter wrote them** (verified), and
"A null (absent) allow-list MUST fold every present diagnostic-context key" cannot be implemented any other
way. So every key that reaches the fold is a `Symbol` at the point it reaches it, and a `String` constant
would make the allow-listed path and the unfiltered path disagree about the type of the same key. Design §8.1
spells the carrier `Fiber[:key]` and `CLAUDE.md` restates it, which is the same shape from the design side.
The one place the setter fact still does work is forward-looking and is stated as such: phase 8's `ASYNC-9`
pooled-worker restore is a whole-map operation that may have no way to avoid `Fiber#storage=`, and a snapshot
keyed by `String` constants is not installable through it.

**What `5c`'s `String` reading gets right, and why it does not decide.** `OBS-39`'s field keys are dotted
`String`s and `OBS-10`'s folded key becomes one, so a `String` constant needs no conversion at that point.
Verified: the conversion is free anyway — `Symbol#name` returns the same frozen `String` on every call and
allocates nothing (1 per 1000 calls), against `Symbol#to_s`'s one per call. Note also that
`:"trace.id".name` is **not** `equal?` to a `"trace.id"` frozen literal, which is precisely why there must be
one constant and not two spellings of it.

So the constants live where the default lives:

```
Dexpace::Instrumentation::Diagnostics::TRACE_ID     = :"trace.id"
Dexpace::Instrumentation::Diagnostics::SPAN_ID      = :"span.id"
Dexpace::Instrumentation::Diagnostics::DEFAULT_KEYS = [TRACE_ID, SPAN_ID].freeze
```

**They are `Symbol`s and not `String`s, and that is forced rather than chosen.** Verified fact 1:
`Fiber#storage=` raises `TypeError` on a `String` key and `Fiber[]=` coerces one to a `Symbol`, so the
diagnostic-context key space **is** `Symbol`-shaped whatever a constant declares. Verified fact 10: the fold
converts to `OBS-39`'s dotted-`String` field key with `Symbol#name`, which returns the same frozen `String` on
every call, and never with `#to_s`, which allocates one per key per event on the hot path `OBS-1` protects.
`P5-24`.

**Settled, not assumed:** `5c` cites `Diagnostics::TRACE_ID` and `::SPAN_ID` for `OBS-23`'s push and declares
no second pair, and `5c`'s `lib/dexpace/instrumentation/keys.rb` — which would have collided with 5b's file of
that name for `Keys`/`Events` — is not created. `5c`'s reason for wanting its own file, that "a file that can
be required alone is what keeps the crossing contract from dragging the whole segment behind it", is honoured
in mirror image: `diagnostics.rb` requires nothing else in 5b and defines no `Event`, so `5c`'s suite can
require it without acquiring the logging half or breaking its own load-time assertion.

### The two OTel instrument names are 5b's, and both drafts assigned them to the other

`OBS-32`'s `http.client.request.count` and `http.client.request.duration` are named by neither draft: 5b's
exclusion table gave them to `5c` "because a name in `Instrumentation::Keys` would be an `NFR-4`-locked
constant for an object 5b does not build", and `5c` gave them to 5b "because `5b` owns the step that creates
them". **`5c`'s reading is right and 5b's reason was wrong**: the step *does* build the instruments — it is
the only caller of `meter.create_counter` and `meter.create_histogram` in core — so the object is 5b's, not
someone else's. And `OBS-34` is a 5b MUST that requires a request counter and a latency histogram to record on
every request, which is unsatisfiable without a name.

So `Instrumentation::Keys` gains two frozen `String` constants, `Keys::INSTRUMENT_REQUEST_COUNT` =
`"http.client.request.count"` and `Keys::INSTRUMENT_REQUEST_DURATION` = `"http.client.request.duration"`,
adopting `OBS-32`'s recommended spellings so a later OTel adapter needs no rename. `P5-16` covers them.

**This does not implement `OBS-32` and does not disturb `5c`'s ⏳ row.** What `OBS-32` asks for beyond the two
names is the units (`{request}`, `ms`), the descriptions, semantic-convention conformance and the
method/status/error attribute sets, and its conformance clause is "run a success and a failure with a
**recording meter**; assert the two instrument names/units and the attribute sets" — a recording meter is
exactly what `DEF-9`'s OTel adapter supplies and core does not (`P5-48`). `OBS-32` stays ⏳ `DEF-9` in `5c`'s
scope table with the deferred half being units, descriptions and attribute sets rather than the bare names.

### No third slot for the HTTP-tracer, confirmed from 5b's side

`5c` considered wiring `OBS-29`'s operation-lifecycle triple from this step and rejected it, partly because it
would need **a third slot** the charter's boundary 15 does not grant. **5b confirms the refusal and adds no
third slot.** Two reasons of 5b's own, neither of which is a restatement of `5c`'s: the step's `#call` sees one
operation and no attempts, so `OBS-29`'s "retries-exhausted … immediately followed by operationFailed with the
same throwable" is a pairing this object structurally cannot honour; and an eleven-method emitter reached
through a slot would sit *outside* `Instrumentation.contain` under `OBS-20`'s asymmetry, so a partially-wired
vocabulary would put three throwing callbacks on the request path for three of eleven events. The wiring is
`DEF-42`, phase 6's.

## R12 — `OBS-24`'s whole-map snapshot against `OI-13`'s warned setter

**The decision: capture is `Fiber.current.storage` normalised and frozen; reinstall and restore are per key
over the union of the captured and prior key sets, through `Fiber[]=` alone. `Fiber#storage=` is never
called anywhere in `dexpace-core`'s `lib/`, and exactly once in its `test/` — the one place the input
`OBS-10`'s null-value clause is about can be constructed at all.** `P5-23`.

**Stated conditionally, because the floor could not be run.** The charter requires the floor and ceiling
behaviour to be re-run before this is decided and could run only 3.4.10; so could this document — `mise ls`
lists no Ruby and no interpreter exists under `~/.local/share/mise/installs`, `~/.rbenv`, `~/.rvm` or
`/opt/rubies`, re-checked. **Re-running verified facts 1, 2 and 3 on 3.2.11 and 4.0.6 is the plan's first
task**, and the decision is conditional on `Fiber[:k] = nil` deleting the key on all three. If it does not —
if on some Ruby it stores a `nil` — the restore loop must delete explicitly rather than assign, and the
mechanism is unchanged; only the loop body moves. **Nothing in this decision depends on `Fiber#storage=`'s
behaviour on any version, which is the point:** `OI-13`'s two findings are both about a call 5b does not make.

### Why per-key wins on the merits and not only on the warning

`OI-13` gives two independent problems with `Fiber#storage=`: it warns on every call at the default warning
level, against a gate set that fails the build on warnings (`NFR-7`); and `Fiber.current.storage = nil` leaves
`{}` on 3.2.11 and `nil` on 3.4.10 and 4.0.6, so the obvious spelling of "reinstate an empty context" reads
back differently on the floor. The charter lists three routes: per key over the union; a scoped `Warning.warn`
filter; or an `NFR-7` waiver.

Routes two and three both keep the version-dependence and only silence the warning. Verified fact 4 confirms a
scoped filter *works* — and it is a `prepend` on `Warning`'s singleton class, a process-global object, which
is the imposition this port already refuses for `Regexp.timeout` and for `Warning[:experimental] = false`. A
waiver under `NFR-7` would be "a narrowly-scoped, documented exception carrying explicit re-enable
conditions", and the re-enable condition would be "`Fiber#storage=` stops being experimental", which is a
condition on MRI's roadmap rather than on this repository. **Route one removes both problems instead of
silencing one**, and verified fact 3 shows it is exact: `restored == prior` for every context reachable
through `Fiber[]=`.

### The residual gap, stated precisely and then shown to be self-eliminating

A prior context holding a key whose value is literally `nil` restores as *absent* rather than as
*present-with-`nil`* — verified fact 3, `prior2 = {a: nil, b: 1}` restores as `{b: 1}`. Two things make that
acceptable and both are stated in the YARD block rather than hidden:

- **Such a context cannot be produced by anything in this SDK.** `Fiber[:a] = nil` deletes; the only
  constructor of a `nil`-valued key is `Fiber#storage=`, which nothing here calls. A host that calls it can
  produce one, and a host that does gets a key removed instead of nulled — observationally identical through
  `Fiber[]`, which is the reader every consumer of a diagnostic context uses.
- **It is invisible to `OBS-24`'s own conformance clause**, which asserts "the captured keys visible inside and
  B's original context restored after (including on throw)". Both hold.

### And what it decides about `OBS-10`'s null-value clause

> "Keys with null values MUST be skipped."

The clause is **live, not vacuous**, and precisely where it is live is worth writing down because the two
readers disagree. Through `Fiber[key]`, a `nil`-valued key and an absent key are indistinguishable, so a fold
that reads per key skips it either way and the clause is satisfied trivially. Through
`Fiber.current.storage` — which is the reader `OBS-10`'s **unfiltered mode** requires, because "A null
(absent) allow-list MUST fold every present diagnostic-context key" cannot be implemented by asking about keys
you already know — a `nil`-valued key is `key?`-true with a `nil` value, and skipping it is a real branch with
a real test. So:

- **allow-listed mode** reads per key through `Fiber[]` and skips `nil`;
- **unfiltered mode** reads the whole map through `Fiber.current.storage` and skips `nil`;

and the second is where `OBS-10`'s clause earns its MUST. The test constructs the input the only way it can be
constructed — `Fiber.current.storage = {a: nil, b: 1}` **in the test**, which is permitted because the ban is
on `lib/`, not on a test that is deliberately exercising a host-produced state — and asserts the folded event
carries `b` and not `a`. That single `Fiber#storage=` call is the only one anywhere in the repository after
5b, it lives in one test, and it carries a comment saying why it is there.

## Module layout

Every file 5b creates, under `gems/dexpace-core/`. `sig/` mirrors `lib/` one file per file and ships inside
the gem; `test/` mirrors `lib/` one file per file and does not ship.

```
lib/dexpace.rb                                    MODIFIED: explicit requires for the tree below
lib/dexpace/instrumentation/severity.rb           Dexpace::Instrumentation::Severity
lib/dexpace/instrumentation/keys.rb               Dexpace::Instrumentation::Keys, ::Events
lib/dexpace/instrumentation/null_sink.rb          Dexpace::Instrumentation::NULL_SINK
lib/dexpace/instrumentation/render.rb             Dexpace::Instrumentation::Render        (private_constant)
lib/dexpace/instrumentation/event.rb              Dexpace::Instrumentation::Event, Event::INERT
lib/dexpace/instrumentation/logger.rb             Dexpace::Instrumentation::Logger, Logger::NULL
lib/dexpace/instrumentation/contain.rb            Dexpace::Instrumentation.contain
lib/dexpace/instrumentation/diagnostics.rb        Dexpace::Instrumentation::Diagnostics
lib/dexpace/instrumentation/redaction_policy.rb   Dexpace::Instrumentation::RedactionPolicy
lib/dexpace/instrumentation/redactor.rb           Dexpace::Instrumentation::Redactor
lib/dexpace/instrumentation/preview.rb            Dexpace::Instrumentation::Preview
lib/dexpace/instrumentation/http_logging.rb       Dexpace::Instrumentation::HTTPLogging
lib/dexpace/instrumentation/emitter.rb            Dexpace::Instrumentation::Emitter       (private_constant)
lib/dexpace/instrumentation/step.rb               Dexpace::Instrumentation::Step
lib/dexpace/instrumentation/async_step.rb         Dexpace::Instrumentation::AsyncStep

lib/dexpace/closeable.rb                          MODIFIED: close_quietly's diagnostic route (DEF-27, closes it)
lib/dexpace/hooks.rb                              MODIFIED: the per-dropped-failure diagnostic (DEF-32)
lib/dexpace/proxy/resolution.rb                   MODIFIED: an event beside each Kernel#warn (P5-8, discharged)
lib/dexpace/configuration/keys.rb                 MODIFIED: ONE key name 5b adds, LOG_PREVIEW_BYTES (DEF-34);
                                                  LOG_LEVEL is 5a's and is read, not redeclared

test/support/recording_sink.rb                    Dexpace::RecordingSink — the fake sink every emission test
                                                  asserts on. Flat under Dexpace, on 5a's FakeClock precedent
test/support/diagnostic_context.rb                Dexpace::DiagnosticContext — the ensure-restore helper every
                                                  Diagnostics test uses

                                                  NOT 5b's, and reused rather than duplicated (P5-48):
test/support/recording_tracer.rb                  5c's Dexpace::RecordingTracerFactory + ::RecordingTracer
test/support/recording_span.rb                    5c's Dexpace::RecordingSpan
test/support/recording_meter.rb                   5c's Dexpace::RecordingMeter, ::RecordingCounter,
                                                  ::RecordingHistogram — 5b declares none of the three
```

Fifteen new `lib/` files, **thirteen** `sig/` mirrors and thirteen `test/` mirrors — `render.rb` and
`emitter.rb` are `private_constant`s and get neither, per P2-15 and P4-3, and their behaviour is asserted at
their call sites — four already-existing `lib/` files that gain content, with `sig/` mirrors updated for the
two of those that are public surface (`hooks.rb` and `proxy/resolution.rb` are `private_constant`s and
`configuration/keys.rb`'s mirror gains **one** constant), **two** test-support files, and the repository-root
`test/fixtures/surface/dexpace-core.txt`.

**The draft listed four test-support files and now lists two.** The recording tracer and the recording meter
moved to `5c` at reconciliation, because `5c` defines the protocols they impersonate and asserts every
recording clause of `OBS-21`, `OBS-29`, `OBS-30` and `OBS-31` against them (`P5-48`). 5b's step tests **reuse**
them rather than adding a second set — which is this document's own open question 6 answered from the other
side, and which keeps one fake per idea rather than the drift `DEF-29` would otherwise have to consolidate.

**Every 5b constant in `lib/` is under `Dexpace::Instrumentation::`** — the two doubles under `test/support/`
are flat under `Dexpace`, which is `5a`'s convention and is the point of keeping a test-only name out of the
shipping namespace. That placement is phase 1's rule applied
rather than re-decided (P1-1, `module-organization/6e69ad04`): a public constant the design names *with* a
namespace keeps it, and §8.1 names `Dexpace::Instrumentation::Event`, `Event::INERT` and
`Dexpace::Instrumentation::Bundle` while phase 4a already shipped three more under the same namespace. The
five-file grouping inside it — the event family, the redaction family, the diagnostic-context family, the
level-and-preview family, the step family — organises rather than namespaces, which is the same reading phase
1 gave `Headers::Builder`.

**`Dexpace::Instrumentation::Emitter` is `private_constant` and it is what makes `OBS-17`'s anti-drift clause
structural.** `OBS-17` requires that "the redaction policy MUST be shared by the sync and async logging paths
so it cannot drift". Two steps sharing one policy *object* would satisfy the letter and drift the moment one
step grows a field the other does not; two steps sharing one `Emitter` — which owns every `logger.event(…)`
call and every field key in the sub-phase — cannot. `P5-34`.

## The object model 5b ships

Every public constant, its surface, and the IDs forcing that shape.

### `Dexpace::Instrumentation::Severity` — `OBS-2`

A frozen `Data` closed set over a frozen table with an `.of` factory, never a `T::Enum`
(`type-system/545949a5`). `private_class_method :new`.

```
Data.define(:name, :sink_method, :sink_predicate)
```

| Constant | `name` | `sink_method` | `sink_predicate` |
|---|---|---|---|
| `Severity::ERROR` | `:error` | `:error` | `:error?` |
| `Severity::WARNING` | `:warning` | `:warn` | `:warn?` |
| `Severity::INFO` | `:info` | `:info` | `:info?` |
| `Severity::VERBOSE` | `:verbose` | `:debug` | `:debug?` |

`Severity::ALL` is the frozen four-element `Array`; `Severity.of(name)` resolves a `Symbol` and raises
`Dexpace::InvalidArgumentError` on anything else.

**`OBS-2`'s mapping is data, not a `case`.** "exactly four severity levels — ERROR, WARNING, INFO, VERBOSE —
and map them onto the backend's ERROR, WARN, INFO, and most-verbose/DEBUG levels respectively" is two columns
of a table, and putting them in the value type means the sink call is `sink.public_send(severity.sink_method)`
and the enabled check is `sink.public_send(severity.sink_predicate)` — one code path for four levels, so a
fifth cannot be added by accident and the fourth cannot be mapped twice.

### `Dexpace::Instrumentation::Keys` and `::Events` — `OBS-39`, `OBS-4`, `OBS-20`

Two modules of frozen `String` constants, no instance side. **They are the one part of this sub-phase the
design makes a requirement of the surface snapshot rather than only of the code:** §8.1 says the names "are
frozen constants and covered by §9.1's surface snapshot, because a 'stable' vocabulary that nothing asserts
drifts on the first refactor". `OBS-39`'s "MUST be stable and predictable" is therefore mechanised, not
promised.

`Keys` — fifteen: thirteen for `OBS-39`'s named minimum, plus the two instrument names `R11` moved here:

| Constant | Value | Requirement |
|---|---|---|
| `Keys::EVENT` | `"event"` | `OBS-4`'s reserved key |
| `Keys::HTTP_REQUEST_METHOD` | `"http.request.method"` | `OBS-39` |
| `Keys::URL_FULL` | `"url.full"` | `OBS-39`; **always the redacted URL**, structurally (the reserved-key table on `Event`) |
| `Keys::HTTP_RESPONSE_STATUS_CODE` | `"http.response.status_code"` | `OBS-39` |
| `Keys::HTTP_RESPONSE_DURATION_MS` | `"http.response.duration_ms"` | `OBS-39`; from `clock.monotonic`, never `Time.now` (`CFG-16`) |
| `Keys::HTTP_REQUEST_BODY_SIZE`, `::HTTP_RESPONSE_BODY_SIZE` | `"http.request.body.size"`, `"http.response.body.size"` | `OBS-39`'s content-length fields; `OBS-36`'s "describe the captured preview, not necessarily the full body" |
| `Keys::HTTP_REQUEST_BODY_PREVIEW`, `::HTTP_RESPONSE_BODY_PREVIEW` | `"http.request.body.preview"`, `"http.response.body.preview"` | `OBS-36`, `OBS-38`; emitted only at `HTTPLogging::BODY` |
| `Keys::HTTP_REQUEST_HEADER_PREFIX`, `::HTTP_RESPONSE_HEADER_PREFIX` | `"http.request.header."`, `"http.response.header."` | `OBS-39`'s header fields, and the prefixes the reserved-key table matches for `OBS-16`/`OBS-17` redaction |
| `Keys::ERROR_TYPE` | `"error.type"` | `OBS-39`'s failure event |
| `Keys::CAUSE` | `"cause"` | `OBS-39`'s failure event, second half: "and the throwable cause attached". **Added at the plan reconciliation, 2026-09-09**, and it is the thirteenth rather than a thirteenth invented: `Event#emit` already wrote this key, as a bare `"cause"` literal in `event.rb`, which put an emitted field key outside the vocabulary `OBS-39` requires to be "stable and predictable" and outside the surface-snapshot coverage §8.1 asks for. `Event#cause(error)` is the only writer and `Render.render` is what shapes the value |
| `Keys::INSTRUMENT_REQUEST_COUNT`, `::INSTRUMENT_REQUEST_DURATION` | `"http.client.request.count"`, `"http.client.request.duration"` | `OBS-34`'s two instruments, named with `OBS-32`'s recommended spellings. Added at reconciliation (`R11`); `OBS-32`'s units, descriptions and attribute sets stay `5c`'s ⏳ `DEF-9` |

`Events` — eight, of which six carry `OBS-20`'s `http.instrumentation.` prefix (five diagnostics and the
prefix constant itself):

| Constant | Value | Requirement |
|---|---|---|
| `Events::HTTP_REQUEST` | `"http.request"` | `OBS-39` |
| `Events::HTTP_RESPONSE` | `"http.response"` | `OBS-39`, success **and** failure — the requirement is explicit that "a failure emits an `http.response` event with `error.type`", not a third event name |
| `Events::INSTRUMENTATION_PREFIX` | `"http.instrumentation."` | `OBS-20`'s family name, so the four below are derived from one string and a test can assert every diagnostic starts with it |
| `Events::INSTRUMENTATION_LOG` | `"http.instrumentation.log"` | `OBS-20`'s own case: a log-emission site that raised |
| `Events::INSTRUMENTATION_CLOSE` | `"http.instrumentation.close"` | `DEF-27`'s second disposal route |
| `Events::INSTRUMENTATION_HOOK` | `"http.instrumentation.hook"` | `DEF-32`'s per-dropped-failure diagnostic |
| `Events::INSTRUMENTATION_SHUTDOWN` | `"http.instrumentation.shutdown"` | `SEAM-25`'s lifecycle event; `DEF-31`, half supplied. A **log-event** name, not an `OBS-28` tracer callback — see the `DEF-31` wiring below |
| `Events::INSTRUMENTATION_CONFIG` | `"http.instrumentation.config"` | `CFG-24`/`CFG-25`'s warning, beside `5a`'s `Kernel#warn` (`P5-8`) |

**The two instrument names were absent in the draft and are here now.** The draft left
`http.client.request.count` and `http.client.request.duration` to `5c` on the ground that they would be
"`NFR-4`-locked constant[s] for an object 5b does not build". `5c` left them to 5b, and `5c` is right: the step
is the only caller of `create_counter` and `create_histogram` in core, so it *does* build them, and `OBS-34`
requires them recorded on every request. `R11` states the reversal and why `OBS-32` stays ⏳ `DEF-9` anyway.
What remains deliberately absent is everything else of `OBS-32`'s — no unit, no description and no attribute
set is a constant here, because those are what `DEF-9`'s recording meter is needed to assert.

### `Dexpace::Instrumentation::NULL_SINK` — `OBS-1`'s default output

One frozen instance of a `private_constant` class. `#debug`, `#info`, `#warn`, `#error` each accept a message
argument **or** a block and return `nil` without calling the block; `#debug?`, `#info?`, `#warn?`, `#error?`
return `false`.

**It is a public constant naming a frozen instance of a private class**, which is phase 4a's exact shape for
`NO_SPAN` and `NO_TRACER_FACTORY` and for the same reason: `OBS-1`'s conformance asserts identity, and an
identity needs a name. `P5-19` records that §8.1 calls it `NullLogger`.

**The sink duck type it implements is the whole contract**, and it is written down here because nothing else
does: **anything responding to `#debug`/`#info`/`#warn`/`#error` and `#debug?`/`#info?`/`#warn?`/`#error?`**.
That is a structural subset of the stdlib `Logger` surface (verified: all eight are public instance methods of
`Logger`, along with `#fatal`/`#fatal?`/`#add`/`#level`), so a stdlib `Logger`, a Rails logger or
`SemanticLogger` drops in with no adapter code — which is the payoff §8.1 names and the reason core can define
the sink without requiring `logger`. **Core never requires `logger`** and no file in `gems/dexpace-core`
mentions it; the proof that a real `Logger` satisfies the type is `dexpace-conformance`'s, phase 8's, where a
declared dependency is permitted.

**Emission uses the block form**, `sink.public_send(severity.sink_method) { rendered }`, so no rendering runs
if the sink's own level check disagrees. Verified: a `Logger` at `INFO` does not evaluate a `#debug` block.
That is a redundant guard for a sink whose level moved after event creation, **not** the enabled decision,
which `OBS-1` fixes at `#event`.

### `Dexpace::Instrumentation::Event` and `Event::INERT` — `OBS-1`, `OBS-3`–`OBS-9`, `OBS-39`, `OBS-40`, `OBS-7`

A plain class, `private_class_method :new`, obtained only from `Logger#event`. **Not a `Data`**, and that is a
deliberate departure from phase 1's construction pattern with a requirement behind it: `OBS-8` says
"Field/tag/cause accumulation is not required to be thread-safe (single-thread build)", which describes a
mutable accumulator, and a frozen value type cannot accumulate. `P5-21`.

| Method | Requirement |
|---|---|
| `#field(key, value) -> self` | `OBS-3`, `OBS-5`, `OBS-6`, `OBS-7`, and — through the reserved-key table below — `OBS-11`–`OBS-18` and `OBS-39` |
| `#event(name) -> self` | `OBS-4`. A `nil` or empty name **clears** the tag rather than emitting `event=` |
| `#cause(error) -> self` | `OBS-39`'s "the throwable cause attached"; renders through `OBS-6`'s exception form |
| `#emit -> nil` | `OBS-8`, `OBS-5`, `OBS-9`, `OBS-10` |
| `Event::INERT` | `OBS-1`'s shared inert event. Public; `R8` |

**`#tag(key, value)` from §8.1's code block is not shipped.** §8.1 lists it once and never mentions it again;
no `OBS` requirement names a tag other than `OBS-4`'s reserved `event` tag, which `#event(name)` sets; and
`OBS-5`'s precedence enumerates exactly three sources, so a fourth channel would have no precedence rule and no
test. A public, `NFR-4`-locked method with no requirement and no caller is `OI-8`'s shape. `P5-18`, and a
finding filed as `OI-25` against §8.1, because the method is named in a frozen document.

**`Event::INERT` is an instance of `Event::Inert < Event`**, a `private_constant` subclass overriding all five
methods to return `self` (or `nil` for `#emit`) and writing no instance variable, then frozen. Two
alternatives were rejected: a frozen `Event`, which raises `FrozenError` the first time `#field` writes its
hash — the disabled path is required to be a no-op, not a failure; and an unrelated class, which would make
`Logger#event`'s return type a union and force an RBS interface for a case where a subclass is exactly right.
`P5-20`.

**The eight clauses the object carries.**

- **Keys and null values** (`OBS-3`). A `key` that is `nil`, not a `String` or `Symbol`, or empty after
  `#to_s`, raises `Dexpace::InvalidArgumentError` through `Model.required!`, so the message form is
  `SEAM-29`'s. A `nil` **value** is not dropped: it renders as the four-character `String` `"null"`, because
  a dropped key and a null key mean different things to whoever reads the output. The consequence is stated
  rather than hidden: a JSON sink receives `"k" => "null"`, a quoted string, not a JSON `null` — core does no
  serialisation and the sink is a duck type, so the requirement's literal words are the only thing that can be
  honoured.
- **The reserved `event` tag** (`OBS-4`). `Keys::EVENT` is `"event"`. `#event(name)` stores the tag; a `nil` or
  empty name clears it. At `#emit`, when a non-empty tag is set, an `event` key arriving from a per-event
  field, the global context or the folded diagnostic context is **suppressed**, so the record carries `event`
  exactly once. A JSON appender handed two `event` keys produces invalid output, which is the requirement's own
  rationale.
- **Precedence and at-most-once** (`OBS-5`). One merge, in one place, in one order — folded diagnostic
  context, then global context, then per-event fields — into a single `Hash` at `#emit`. Not three sources
  consulted by the renderer, because a renderer that consults three sources is a renderer that can emit a key
  twice.
- **Rendering is total** (`OBS-6`), and it lives in `Instrumentation::Render`, `private_constant`. An exception
  renders as `SimpleClassName: message`, where `SimpleClassName` is `e.class.name&.split("::")&.last` **with
  the `nil` guard** (verified fact 8: `Class.new(StandardError).name` is `nil`, and an anonymous error class
  is what a test suite and a metaprogrammed adapter both produce) falling back to `"Class"`; arrays, hashes and
  other collections render in a bracketed textual form; numerics, booleans and single-character strings pass
  through type-preserving. **Every value is rendered inside a `rescue StandardError` that substitutes
  `[unrenderable <ClassName>]`** — placed around *both* the class-name derivation and the message read, because
  verified fact 8 shows `#message` itself can raise.
- **Truncation** (`OBS-7`, SHOULD, implemented). `Render::MAX_VALUE_BYTES = 8 * 1024` and
  `Render::TRUNCATION_MARKER = "…[truncated]"`. Applied to the rendered `String` on **bytes**, via
  `#byteslice(0, MAX_VALUE_BYTES)` then `#scrub("")` then the marker — verified fact 9 shows a byte slice of a
  multibyte string is not a valid `String` and that a character-measured cap is not 8 KiB. Primitives are
  exempt, as the requirement says. `P5-29`.
- **Emit at most once, correctly under concurrency** (`OBS-8`). A `@emitted` boolean flipped under a
  `Thread::Mutex`, **with the mutex released before the sink call**. Verified fact 12 makes that a live
  requirement rather than prudence: `Thread::Mutex` is per-fiber-owned and non-reentrant, so a sink whose
  `#debug` block yields to another fiber of the same thread would deadlock inside the lock. Not the GVL: a
  lone flag read and write is atomic on CRuby and not on JRuby or TruffleRuby, and §1 fixes safe publication as
  the port's rule.
- **Global context on every event** (`OBS-9`). Attached at `#emit`, subject to `OBS-5`. The logger freezes what
  it is given at configuration time through `Model.own`, so "referenced, not deep-copied per event" is true and
  the "effectively immutable" expectation the requirement states is enforced rather than hoped for.
- **The collision diagnostic** (`OBS-40`, SHOULD, implemented). A caller setting a per-event field named
  `event` while a tag is set has that field dropped in favour of the tag; the logger warns **once**, at
  `Severity::VERBOSE`, gated on `#enabled?(Severity::VERBOSE)` so it costs nothing when disabled, and
  throttled by a latched flag on the logger. Ambient `event` keys from the global or diagnostic context defer
  **silently** and are not warned about, since the caller did not write them — which is a branch, and a test.

**Redaction runs on the way into `#field`, and here is what that sentence can and cannot mean.** §8.1's claim
is that "no sink implementation can bypass it", and the mechanism is a frozen table on the `Event` mapping a
**reserved key** to a redaction function:

| Key | Function |
|---|---|
| `Keys::URL_FULL` | `redactor.url(value)` |
| any key beginning `Keys::HTTP_REQUEST_HEADER_PREFIX` or `Keys::HTTP_RESPONSE_HEADER_PREFIX` | `redactor.header_value(name_after_the_prefix, value)` |
| everything else | identity |

This is what makes `OBS-39`'s "The logged `url.full` MUST always be the redacted URL" structural: **whoever**
calls `#field(Keys::URL_FULL, raw)` — the step, an SDK author, a future phase — gets the redacted form, because
the redaction is keyed by the field name and not by the call site. It is stated explicitly that redaction is
**not** applied to arbitrary values: URL-redacting a status code would corrupt it, and §8.1's sentence has to
be read as "the URL-valued fields are redacted on the way in" or it says something false.

### `Dexpace::Instrumentation::Logger` and `Logger::NULL` — `OBS-1`, `OBS-2`, `OBS-9`, `OBS-10`, `OBS-40`

A plain class — it holds `OBS-40`'s latch and `OBS-8`'s mutex factory — with `private_class_method :new`.

```
Logger.build(sink: NULL_SINK,
             context: {},
             redactor: Redactor::DEFAULT,
             diagnostic_keys: Diagnostics::DEFAULT_KEYS)
```

| Method | Requirement |
|---|---|
| `#event(severity) -> Event` | `OBS-1`. The enabled decision, made **once**, here: `sink.public_send(severity.sink_predicate)` — a live `Event` or `Event::INERT` |
| `#enabled?(severity) -> bool` | `OBS-40`'s verbose gate, and the one query the step and a caller share |
| `#context -> Hash` | `OBS-9`. The frozen map, the same object every time |
| `#sink` | the installed sink, for a caller composing a second logger over it |
| `Logger::NULL` | a frozen `Logger` over `NULL_SINK` — the value a component with no logger installed holds |

**`diagnostic_keys:` is `nil`-meaningful**, which is `OBS-10` and not an accident: "A null (absent) allow-list
MUST fold every present diagnostic-context key (opt-in unfiltered mode)". So `nil` is a *mode*, not "use the
default", and `Diagnostics::DEFAULT_KEYS` is the default because a keyword's default and a keyword's `nil` are
different things. This is the one place `api-design/6ea28c9c`'s "never `nil` for absent" is **overruled by
requirement**, and it is documented at the keyword.

**`Logger::NULL` exists so no caller ever holds a `nil` logger.** `Instrumentation.contain` takes a logger and
a `nil` would make the containment path itself branch; `Bundle::NONE` is the same decision made by phase 4a for
the same reason. It is a new public name §8.1 does not have, and `P5-17` says so.

### `Dexpace::Instrumentation.contain(logger, event:) { … } -> nil` — `OBS-20`, `XCUT-20`

The failure-containment primitive, and there is exactly one.

```
def self.contain(logger, event:)
  yield
  nil
rescue ::StandardError => e
  begin
    logger.event(Severity::WARNING).event(event).cause(e).emit
  rescue ::StandardError
    nil                       # OBS-20: "a secondary failure ... MUST be swallowed"
  end
  nil
end
```

Three properties, all required rather than chosen:

- **It returns `nil` and swallows the block's value.** A caller that branched on the result would be branching
  on whether logging worked, which is what `OBS-20` forbids. Every call site is a statement, not an expression.
- **The secondary rescue is `StandardError` and does nothing at all** — no `Kernel#warn`, no re-raise, no
  counter. `OBS-20`'s words are "MUST be swallowed", and a secondary path that itself has a failure mode is a
  third failure mode.
- **It is a module function and not a method on `Logger`.** A `logger.contain { }` would read as "the logger
  contains", which invites a sink-level containment — and a containment at the sink is exactly the placement
  §8.1 rejects for redaction, for the same reason: it can be bypassed by installing a different sink. `P5-37`.

**It wraps log-emission sites and nothing else.** The step's tracer and meter calls are outside it, deliberately
and with a comment naming `OBS-20` and `OBS-30`. **`5c` may not wrap them and 5b may not stop wrapping** —
charter boundary 3.

### `Dexpace::Instrumentation::Diagnostics` — `OBS-10`, `OBS-24`

A module with no instance side.

| Member | Requirement |
|---|---|
| `Diagnostics::TRACE_ID = :"trace.id"`, `::SPAN_ID = :"span.id"` | `OBS-10`'s default allow-list, `OBS-23`'s keys. **`Symbol`s**, and 5b's against `5c`'s `String` counter-proposal; `R11`, `P5-24`. `5c` cites these and declares no second pair |
| `Diagnostics::DEFAULT_KEYS = [TRACE_ID, SPAN_ID].freeze` | `OBS-10`'s "MUST be exactly {trace.id, span.id}" |
| `Diagnostics.capture -> Hash` | `OBS-24`'s "immutable snapshot": `(Fiber.current.storage \|\| {}).freeze` |
| `Diagnostics.with(snapshot) { … } -> Object` | `OBS-24`'s reinstall-and-restore bridge, `begin/ensure`, per key over the union |
| `Diagnostics.folded(allow_list) -> Hash` | `OBS-10`'s fold, keyed by `String`, `nil` values skipped |

**`.capture` is one read and one freeze.** Verified fact 2: `Fiber.current.storage` already returns a fresh
unfrozen `Hash` on every call, so there is nothing to duplicate; and it returns **`nil`** in a fiber created
with `Fiber.new(storage: nil)`, so the `|| {}` is a real branch and not defensive padding. No
`Ractor.make_shareable` is called: `OBS-24` says the snapshot "MUST be immutable/shareable" and a caller may
have put an unshareable object in fiber storage, so a `make_shareable` would turn a host's choice into a
`Ractor::IsolationError` raised from a logging path. Frozen is what is claimed; shareable is not. `P5-22`, and
it narrows `data-modeling/5bc538ba` and `5a`'s `P5-6` once more.

**`.with` restores per key over the union**, never through `Fiber#storage=`:

```
def self.with(snapshot)
  prior = Fiber.current.storage || {}
  snapshot.each { |k, v| Fiber[k] = v }
  yield
ensure
  (prior.keys | snapshot.keys).each { |k| Fiber[k] = prior[k] }
end
```

Verified fact 3: this restores `Fiber.current.storage == prior` exactly. The `ensure` runs on an exception,
which is `OBS-24`'s "restore that thread's prior context afterward (**including on exception**)". `R12` states
the one residual and the YARD block carries it.

**`.folded` is where `Symbol#name` earns its place.** Each surviving key becomes an event field key with
`key.name` — the same frozen `String` on every call (verified fact 10) — and never `key.to_s`, which allocates
one `String` per key per event. Two modes:

- `allow_list` non-`nil`: read **per key** through `Fiber[k]`, skip `nil`.
- `allow_list` `nil`: read the **whole map** through `Fiber.current.storage`, skip `nil`-valued keys.

`R12` explains why those are two readers and why `OBS-10`'s null clause is live in the second.

### `Dexpace::Instrumentation::RedactionPolicy` — `OBS-12`, `OBS-17`, `OBS-18`, `XCUT-19`

A frozen `Data` including `Dexpace::Model`, `private_class_method :new`.

```
Data.define(:query_allow_list, :header_allow_list, :url_header_names, :omit_disallowed_headers)
```

| Member | Default | Requirement |
|---|---|---|
| `query_allow_list` | `Set["api-version"]` | `OBS-12` "MUST be exactly {api-version}". A **`Set`** of already-folded names; an empty set redacts every value, which the requirement requires and which a `nil`-means-default keyword would make unreachable |
| `header_allow_list` | the frozen set below | `OBS-18` "MUST contain only diagnostic, non-credential headers", `XCUT-19`(c) |
| `url_header_names` | `Set["location", "content-location"]` | `OBS-17` "at minimum Location and Content-Location" |
| `omit_disallowed_headers` | `false` | `OBS-18`'s boolean policy: `false` emits the fixed `REDACTED` marker, `true` omits the header entirely |

**The default header allow-list, in full, because `NFR-4` locks it and `XCUT-19` audits it:** `accept`,
`accept-encoding`, `cache-control`, `connection`, `content-encoding`, `content-length`, `content-location`,
`content-type`, `date`, `etag`, `expires`, `if-match`, `if-modified-since`, `if-none-match`,
`if-unmodified-since`, `last-modified`, `location`, `retry-after`, `server`, `traceparent`, `tracestate`,
`user-agent`, `vary`, `via`, `x-correlation-id`, `x-request-id`. **Every name is folded** and the check is
against `Headers`' own fold, so 5b writes no second `downcase`.

**What is deliberately absent, and each has a reason a reader will ask for:** `authorization` and
`proxy-authorization` carry the credential; `cookie` and `set-cookie` carry a session; `x-api-key` and every
vendor variant of it carry a key, and a default-deny list cannot enumerate them anyway; and
**`www-authenticate` and `proxy-authenticate` are excluded even though they are challenges rather than
credentials**, because a Digest challenge carries a server nonce and `AUTH`'s phase-6 material is what decides
whether that is loggable. `P5-30` records that the membership is chosen rather than derived — `OBS-18` names a
property, not a list.

**`omit_disallowed_headers` defaults to `false`, emitting the marker rather than omitting.** `OBS-18` gives a
boolean and names no default. Emitting `REDACTED` is chosen because *a header that was present and redacted*
and *a header that was absent* are different facts to whoever is reading the log, and collapsing them loses
the one that matters when a request fails on an auth header nobody realises was sent. That is `OBS-3`'s own
null-versus-absent argument arriving at a second place in the same sub-phase. `P5-35`.

### `Dexpace::Instrumentation::Redactor` — `OBS-11`–`OBS-18`, `XCUT-19`, `XCUT-20`

A plain class holding one frozen `RedactionPolicy`, itself frozen. `Redactor::DEFAULT` is the one over
`RedactionPolicy::DEFAULT`. `.build(policy: RedactionPolicy::DEFAULT)`.

| Member | Requirement |
|---|---|
| `#url(value) -> String` | `OBS-11`–`OBS-15`. Total; `MALFORMED_URL` on parse or rebuild failure |
| `#header_value(name, value) -> String` | `OBS-16`, `OBS-17`. Total; `?***` on the relative/unparseable route |
| `#header_name?(name) -> bool` | `OBS-18`'s gate, against the folded name |
| `#policy -> RedactionPolicy` | so a caller can derive one with `#with` rather than rebuilding |
| `Redactor::MALFORMED_URL = "[malformed url]"` | `OBS-15`'s fixed sentinel |
| `Redactor::REDACTED_VALUE = "***"` | `OBS-12`, `OBS-13` |
| `Redactor::REDACTED_USERINFO = "***:***"` | `OBS-11`'s `***:***@` placeholder, rendered by `URI` |
| `Redactor::REDACTED_HEADER = "REDACTED"` | `OBS-18`'s fixed marker |
| `Redactor::RELATIVE_MARKER = "?***"` | `OBS-16`'s fixed marker |

**`#url`'s algorithm, in the order the clauses demand.**

1. `URI::RFC3986_PARSER.parse(value)` — pinned, never `DEFAULT_PARSER` (`Dexpace/NoUriDefaultParser`). A raise
   goes straight to `MALFORMED_URL`.
2. **`userinfo=` only if `#userinfo` is non-`nil`**, set to `REDACTED_USERINFO`. `OBS-11` is unconditional and
   can never be allow-listed; `XCUT-19`(a) says the same word, "always". Verified: `u.userinfo = "***:***"` on
   an `https` URI renders `"https://***:***@h/x"`, and a userinfo with a user and no password
   (`https://user@h/x`, `#password` `nil`) still redacts to the full two-part placeholder, because the
   placeholder is fixed and revealing that there was no password is itself a fact about the credential.
3. **`query=` only if `#query` is non-`nil`**, set to the rewritten query. The rewrite splits on `"&"` with a
   limit of `-1` so a trailing empty pair survives to be dropped deliberately rather than by `String#split`'s
   default (`OBS-14`'s "MAY be dropped" — 5b drops it, and says so); splits each pair on the **first** `"="`
   only; decodes the name with `URI.decode_www_form_component`, folds it with `#scrub("").downcase`, and keeps
   the value iff the folded name is in `policy.query_allow_list`. **Multi-value keys are atomic** because the
   decision is a function of the name alone — every occurrence of a name takes the same branch, which is
   `OBS-12`'s "all values for a name kept or all redacted" satisfied by construction rather than by a grouping
   pass. Names and the `=` are preserved; a token with no `=` is preserved verbatim.
4. **`fragment=` only if `#fragment` is non-`nil`**, set to the rewritten fragment. `URI` does not tokenise a
   fragment, so this is the hand-rolled half (`OBS-13`, `observability/80c9594d`): split on `"&"`, and for each
   token containing `"="` apply the query rule; **a fragment with no `=` anywhere is preserved verbatim**.
5. `#to_s`.

**And the two clauses that are satisfied by *not* doing something.** `OBS-14`'s "MUST NOT alter scheme, host,
port, or path" is satisfied because no branch assigns any of them — verified that `scheme=` and `host=` are the
two setters that raise `URI::InvalidComponentError`, so a redactor that touched them would also be the one
that could fail. And "A `?` that appears only inside the fragment MUST NOT be treated as a query delimiter" is
satisfied by the pinned parser: verified, `P.parse("http://h/p#a?b=c")` gives `query == nil` and
`fragment == "a?b=c"`, so step 3 does not run and no separator is inserted. The chapter's conformance case —
"redact `http://h/p#a?b=c` and assert no `?` before `#`" — is a direct assertion on that.

**The whole of `#url` is inside one `rescue StandardError` returning `MALFORMED_URL`** (`OBS-15`, `XCUT-20`,
`R9`, `P5-26`). Not `URI::Error`: verified fact 7.

**`#header_value`'s algorithm** is `R9`'s table. `OBS-17`'s clause decides whether it runs at all: a header
whose folded name is in `policy.url_header_names` is redacted through it; every other header value passes
through unchanged. `OBS-18`'s gate runs first and independently — a header whose name is not allow-listed never
reaches a value redactor at all, because its value is not logged.

**`XCUT-11`, discharged rather than deferred.** A `Redactor` is frozen, holds a frozen policy, and keeps no
per-call state: every intermediate lives in a method local. That is "safe for concurrent invocation" by
construction, and phase 9's audit has an object to point at rather than a promise.

### `Dexpace::Instrumentation::Preview` — `OBS-38`

A module with no instance side.

| Member | Requirement |
|---|---|
| `Preview.render(bytes, media_type:) -> String` | `OBS-38` |
| `Preview::BINARY_MARKER_FORMAT` | `OBS-38`'s "`[binary N bytes captured]`" |
| `Preview::TEXT_SUBTYPES` | the frozen discriminator set below |

**Text or binary, and the discrimination is chosen.** A payload is text when `media_type.type == "text"`, or
its subtype is in `TEXT_SUBTYPES` — `json`, `xml`, `yaml`, `csv`, `javascript`, `graphql`,
`x-www-form-urlencoded`, `x-ndjson` — or its subtype ends `+json` or `+xml` (the RFC 6839 structured-syntax
suffixes, matched by a `Regexp.new(source, timeout:)` per the per-pattern rule). Everything else, **including
an absent media type**, is binary. `OBS-38` says "charset-aware for text … and binary-safe for non-text" and
names no test; defaulting an unknown type to **binary** is the safe direction, because rendering unknown bytes
as text is how a log line acquires a control character or a partial credential.

**The text path is phase 3b's corrected recipe**, not §3.1's:
`bytes.dup.force_encoding(enc).encode(::Encoding::UTF_8, enc, invalid: :replace, undef: :replace)` where `enc`
is `media_type.charset` resolved through `Encoding.find`, falling back to `::Encoding::UTF_8`. Verified fact
11: the §3.1 form destroys every non-ASCII byte, and `MediaType#charset` returning `nil` for an unrecognised
charset is what makes `Encoding.find` unreachable from here. `OI-7` is the open item and `P5-31` records that
5b follows the correction rather than the frozen sentence.

**"Decoding MUST NOT throw" and "Empty input yields an empty preview" are both asserted, and neither is
asserted with `assert_nothing_raised`** (`testing/26b866e1`): the truncated-multibyte case asserts the
substituted U+FFFD, the empty case asserts `""`.

### `Dexpace::Instrumentation::HTTPLogging` — `OBS-34`, `OBS-35`

A frozen `Data` closed set over a frozen table, `private_class_method :new`.

```
Data.define(:name, :order)
```

| Constant | `name` | `order` |
|---|---|---|
| `HTTPLogging::NONE` | `:none` | 0 |
| `HTTPLogging::HEADERS` | `:headers` | 1 |
| `HTTPLogging::BODY` | `:body` | 2 |

| Method | Requirement |
|---|---|
| `#at_least?(other) -> bool` | the one comparison the step makes; `order`'s only purpose |
| `HTTPLogging.of(name) -> HTTPLogging` | strict; raises `Dexpace::InvalidArgumentError` |
| `HTTPLogging.parse(text, default: NONE) -> HTTPLogging` | `OBS-35`'s tolerant parse: `text.to_s.strip.downcase`, matched against the three names, falling back to `default` when absent, empty or unrecognised. Never raises |
| `HTTPLogging.resolve(configuration, key:, default: NONE) -> HTTPLogging` | `OBS-35`'s layered resolution: `HTTPLogging.parse(configuration.string(key), default:)` |
| `HTTPLogging::DEFAULT = NONE` | `OBS-34`'s "defaulting to none (logging off unless explicitly opted in)", `XCUT-19`(e) |

**`key:` is required and has no default**, which is `OBS-35`'s embedded MUST — "The SDK MUST NOT bake in a
default config key name" — and which `5a` already reconciled against `CFG-14` on 5b's behalf:
`Configuration::Keys::LOG_LEVEL` is a published name a caller may pass, never a name a resolver falls back to.
`P5-36` restates it because the method is 5b's and a later reader will find a required keyword with an obvious
default and want to supply one.

**`.parse` and `.resolve` are two methods because the tolerant parse has a caller with no `Configuration`.**
A caller who already holds a level `String` — from a YAML file, a Rails initializer, a command-line flag —
gets `OBS-35`'s tolerance without touching the chain, which is also what makes 5b's independence from `5a`
concrete rather than asserted. The chapter's own conformance cases (`"  Headers  "` and `"HEADERS"` both
resolving to the headers level; unset, empty and garbage all falling back) are asserted against `.parse`.

### `Dexpace::Instrumentation::Step` and `::AsyncStep` — `OBS-34`, `OBS-36`, `OBS-39`, `OBS-20`

Both are plain classes with `private_class_method :new` and the same `.build` keywords (`R11`), both declare
`#stage` returning `Dexpace::Pipeline::Stages::LOGGING`, and both delegate every emission to the
`private_constant` `Emitter`.

| Member | Requirement |
|---|---|
| `#stage -> Stage` | 4c's optional declaration, read once at install; installed with **no `stage:` argument** |
| `Step#call(request, cursor) -> Response` | 4c's `_Step`. Calls `cursor.call` exactly once and **never forks** |
| `AsyncStep#call(request, cursor) -> Async::Future` | 4c's `_AsyncStep`. Registers `#on_settle` and returns the **same** future |
| `.build(logger:, redactor:, level:, tracer_factory: NO_TRACER_FACTORY, meter: NO_METER, preview_bytes: nil, clock: Clock::SYSTEM)` | `R11`; the two slots take `5c`'s constant defaults, and the per-request precedence is the context's bundle when it is not `Bundle::NONE`, else the keyword. `preview_bytes:` is `DEF-34`'s cap and is required when `level` is `BODY` |
| `#call`'s tracing and metrics calls | `5c`'s protocols: `factory.tracer(name)` (4a), `tracer.start_span(name)`, `Tracing.correlate(span, bundle)` / `Scope#close`, `span.finish`, `counter.add(1, attributes:)`, `histogram.record(ms, attributes:)`. The two instruments are manufactured once in `.build` |

**The events and fields the `Emitter` writes** are `OBS-39`'s, and every name is a frozen constant in
`Keys`/`Events` covered by the surface snapshot, because §8.1 requires it:

| Event | Fields |
|---|---|
| `Events::HTTP_REQUEST` | `Keys::HTTP_REQUEST_METHOD`, `Keys::URL_FULL` (redacted, structurally), the allow-listed request headers under `Keys::HTTP_REQUEST_HEADER_PREFIX`, `Keys::HTTP_REQUEST_BODY_SIZE` and — at `BODY` — `Keys::HTTP_REQUEST_BODY_PREVIEW` |
| `Events::HTTP_RESPONSE` | `Keys::HTTP_RESPONSE_STATUS_CODE`, `Keys::HTTP_RESPONSE_DURATION_MS`, the allow-listed response headers under `Keys::HTTP_RESPONSE_HEADER_PREFIX`, `Keys::HTTP_RESPONSE_BODY_SIZE` and — at `BODY` — `Keys::HTTP_RESPONSE_BODY_PREVIEW` |
| `Events::HTTP_RESPONSE` (failure) | `Keys::ERROR_TYPE` and the throwable attached with `#cause` — **and no body and no body preview**, at any level below `BODY`, which is phase 4b's `ProtocolError` decision confirmed and extended |

`Keys::HTTP_RESPONSE_DURATION_MS` is computed from `clock.monotonic` differences and never from `Time.now` —
`CFG-16`'s rule, arriving at its first consumer.

**`OBS-36` is discharged by construction and 5b writes no streaming code.** At `HTTPLogging::BODY` the step
wraps the outbound body in `Dexpace::RequestLoggingBody.new(body, tap_limit: preview_bytes)` and the inbound
body in `Dexpace::ResponseLoggingBody.new(body, preview_bytes: preview_bytes)`. Phase 3b's over-cap regime
already replays the captured prefix and continues from the live tail, which is `OBS-36`'s whole sentence, and
`BODY-34`'s "engaged only when body-level logging is enabled" becomes true because **this is the only place in
core that constructs either wrapper** — the structural satisfaction phase 3b described now has its subject.
`DEF-34` is picked up here and 5b, landing second, edits the row.

**The async step's one uncomfortable consequence, stated because nothing else states it.** Verified fact 13:
`Future#on_settle` runs "on the settling thread-or-fiber", and phase 2's `Hooks.notify` runs the whole hook
list and re-raises the **first** failure to whoever settled. So on the async path an `OBS-30`-violating meter
— one that throws, which `OBS-20` says is not defensively wrapped — propagates into the **producer**, not into
the caller. `OBS-20`'s own words are "a throwing tracer or meter WILL propagate and can fail the request",
which is honoured; *which* thread it fails on is a Ruby consequence and it is written in the `AsyncStep`'s YARD
block so an adapter author is not surprised by it. The log emissions are inside `contain` on both paths and
have no such consequence.

**Neither step forks.** 4c: "a step that drives the chain exactly once drives it through `#call`, and `#call`
and `#fork` are disjoint on one cursor". Both steps call once.

### The two picked-up register wirings

**`Dexpace.close_quietly(resource, onto: nil)` — `DEF-27`, closed.** The `onto:`-absent branch, which today
rescues `StandardError` and drops it, now routes through `Instrumentation.contain(logger, event:
Events::INSTRUMENTATION_CLOSE)`. There is no process-wide logger to reach for — a logger slot beside
`Dexpace.configuration` would be `5a`'s object and 5b may not add one — so **the logger is a keyword,
`logger:`, defaulting to `Logger::NULL`**, and a caller who wants the diagnostic passes one. That is one more widening of a phase-2
signature and it is what makes the route testable without a process-wide slot. **The phase-2 test asserting the
error is dropped is what changes**, which 4b's interface table already anticipates; the `onto:` route and the
suppressed trail are untouched. `DEF-27` moves to `picked-up`.

**`Dexpace::Hooks.notify(hooks, argument)` — `DEF-32`, option taken.** Each failure **after** the first is
emitted as `Events::INSTRUMENTATION_HOOK` through the same containment; the first is still attached to the
trail and re-raised. `DEF-32`'s own words are honoured exactly: "it does not replace the trail". `Hooks` is a
`private_constant` with no `sig/` mirror, so the change adds no public surface; it gains a `logger:` keyword
with the same `Logger::NULL` default.

**`SEAM-25`'s lifecycle event — `DEF-31`, half supplied, row stays open.** 5b ships
`Events::INSTRUMENTATION_SHUTDOWN` and the field shape an owned-executor close emits. It does **not** move the
row to `picked-up`: the first thing in this repository that owns an executor is phase 8's
`dexpace-async-thread`, so phase 8 is where the emission gets a real subject and where `dexpace-conformance`
asserts "close twice → executor shut once, one event". 5b adds a dated line to the row's `Status` and nothing
more.

**And it has no place in `OBS-28`'s vocabulary, which the draft left to `5c` to find.** `OBS-28` enumerates
eleven event methods in three groups — operation started/succeeded/failed, per-attempt
started/failed/retries-exhausted, and five transport milestones — and none of them is a shutdown, a close or
any other lifecycle milestone of a *resource*. `Events::INSTRUMENTATION_SHUTDOWN` is a **log-event name** on
`SEAM-25`'s close path, in the same family as `INSTRUMENTATION_CLOSE` and `INSTRUMENTATION_HOOK`, and putting
it in the HTTP-tracer vocabulary would be inventing a twelfth method `OBS-28` does not name — which `OBS-28`'s
own no-op-default clause makes cheap to add later and which neither segment has a requirement for now.
Settled here rather than passed across the line; `5c` adds no method for it.

**`Dexpace::ProxyResolution`'s two `Kernel#warn` sites — `P5-8`, discharged.** An
`Events::INSTRUMENTATION_CONFIG` event is emitted **beside** each warning, through a `logger:` keyword on
`Proxy.resolve`. The warning stays, which is P2-6's shape and `5a`'s explicit expectation.

### The RBS interfaces

Two, both new, both under `Dexpace::`:

```
interface _Sink                                    # OBS-1, OBS-2, §8.1's duck type
  def debug: (?untyped) ?{ () -> untyped } -> void
  def info:  (?untyped) ?{ () -> untyped } -> void
  def warn:  (?untyped) ?{ () -> untyped } -> void
  def error: (?untyped) ?{ () -> untyped } -> void
  def debug?: () -> bool
  def info?:  () -> bool
  def warn?:  () -> bool
  def error?: () -> bool
end

interface _DiagnosticSnapshot                      # OBS-24's "immutable snapshot"
  def each: () { ([Symbol, untyped]) -> void } -> void
  def keys: () -> Array[Symbol]
  def []:   (Symbol) -> untyped
end
```

**`interface _Meter` is `5c`'s and 5b declares nothing for it.** The draft declared it empty, borrowing phase
4a's device of stating a deferral in the type system rather than in a comment. That device was right for 4a
because the populating phase was a *different* phase held open by `DEF-37`; here `5c` populates it in the same
phase, so an empty declaration would be widened before it was ever released — and two declarations of one
interface name is an **`rbs validate` failure**, not a merge conflict. `5c`'s filled `_Meter`, `_Counter` and
`_Histogram` are the ones that ship, and the step's `meter:` types as `Dexpace::Instrumentation::_Meter`, `5c`'s — a bare `_Meter` in `step.rbs`, which is written inside `module Instrumentation`. This is the
same rule 5b already follows for `_Span`, `_Tracer` and `_TracerFactory`, which are phase 4a's and which 5b
does not redeclare.

**5b declares no `_Tracer`, no `_TracerFactory` and no `_Span`** — phase 4a already declares all three and
charter boundary 10 forbids a second. The step's `tracer_factory:` types as `Dexpace::_TracerFactory`,
phase 4a's, which is what makes `NO_TRACER_FACTORY` passable without an adapter.

`_Sink` is what makes `NFR-11` mechanical here: no constant outside `Dexpace::` and the fixed stdlib allowlist
appears in any public signature under `sig/`. A signature typed `Logger` would have put a bundled-gem constant
in the public surface — the failure the whole duck type exists to avoid — and typing it `untyped` would have
hidden it from the `NFR-11` scan rather than satisfying it.

## The spec-forced boundaries, honoured

Eight of the charter's fifteen bind 5b; each is honoured by a named mechanism rather than by intent.

1. **The bundled-gem rule, and `logger` in particular (boundary 1).** 5b requires `uri` and `set`, both
   allowlisted, and nothing else. **No file in `gems/dexpace-core` written by 5b contains the string
   `require "logger"`, including under `test/`** — the require scan resolves relative targets and reads text,
   and phase 0's denylist names `logger` so the failure message says *when* it left the default set. The sink
   is a duck type declared as `_Sink`; `NULL_SINK` is the default; the proof that a stdlib `Logger` satisfies
   it is `dexpace-conformance`'s. Re-verified 2026-09-09: `Gem::BUNDLED_GEMS::SINCE["logger"] == "4.0.0"`.
2. **`OBS-1`'s shared inert event is an object with an asserted identity (boundary 2).** `Event::INERT` is
   public, is a frozen instance of `Event::Inert < Event`, and is asserted with `assert_same` on a qualified
   constant (`R8`). 5b ships no `sink.info { }` substitute for the event object and no block-form facade.
3. **`OBS-20`'s asymmetry (boundary 3).** Every `logger.event(…)` site in the sub-phase is inside
   `Instrumentation.contain`; every tracer and meter call in both steps is outside it, in an `ensure`, with a
   comment naming `OBS-20` and `OBS-30`. **5b does not stop wrapping and does not start wrapping `5c`'s
   calls.**
4. **`XCUT-19` is default-deny in five clauses and `OBS-11`'s userinfo redaction can never be allow-listed
   (boundary 4).** `RedactionPolicy` has **no member that can reach userinfo** — the redaction is
   unconditional and there is no keyword, no policy field and no configuration key that turns it off, which is
   stronger than a default and is the only reading of "unconditionally and independent of any allow-list" that
   a policy object can honour. The query allow-list defaults to exactly `{api-version}`; the header allow-list
   contains only diagnostic, non-credential names; `HTTPLogging::DEFAULT` is `NONE`. 5b defaults no level above
   `none` and adds no allow-list entry that reaches a credential.
5. **Redaction runs at `#field`, not at the sink (boundary 5).** The reserved-key table on `Event`, above.
   **5b offers no sink-level redaction hook**, because a sink that could bypass redaction is the whole failure
   this placement prevents — and the mechanism is checkable: `Redactor` is reachable from `Event` and from the
   `Emitter`, and from nowhere on the sink path.
6. **The three unsatisfied MUSTs are settled and phase 5 does not re-open them (boundary 13).** 5b meets none
   of them; it starts no thread, waits on nothing, and delivers no interrupt.
7. **`Fiber[:key]` is the diagnostic-context carrier and `CTX`'s store is not it (boundary 14).** `Diagnostics`
   uses `Fiber[]`/`Fiber.current.storage` and nothing else. It does not use `Thread.current[]`, which is
   fiber-local and invisible to a child fiber, a new `Thread` and an `Enumerator`'s internal fiber; and it does
   not use `Dexpace::ContextStore`, whose cap and reachability requirements it would defeat. `5a`'s `P5-13`
   uses `Thread.current[]` for a PRNG and is not a counter-example — that decision turns on
   *non*-inheritance being wanted, which is the opposite property.
8. **Phase 4a's five-clause handshake over the instrumentation bundle (boundary 10).** 5b **reads** two
   `Bundle` members and adds nothing: no member, no method, no second `NONE`, no replacement singleton, no
   second no-op span or tracer, and no change to `#valid?`. `DEF-37` is `5c`'s row and 5b does not touch it.
   Named here because it is on the charter's closed list and a reader must be able to see that 5b met it by
   staying out.

## Cross-cutting constraints that bite 5b specifically

1. **The bundled-gem rule, and it bites harder here than in any sub-phase of the project.** This is the one
   place where the idiomatic Ruby answer to the chapter's headline requirement — "use `Logger`" — is the
   forbidden one, and where the failure is silent on the development interpreter and loud only on the 4.0
   matrix row under Bundler. Three mitigations already exist and 5b relies on all three: the denylist names
   `logger`, the clean-bundle isolation run is what makes the 4.0 column load-bearing, and §8.1's duck type is
   the stdlib `Logger` surface as a *structural subset*, so the ecosystem drops in with no adapter gem.
2. **`Thread::Mutex` is per-fiber-owned and non-reentrant.** One mutex exists in 5b — `OBS-8`'s emit-once
   latch — and it is held across the flag flip and nothing else. Verified fact 12 makes that a correctness
   rule: a sink whose `#debug` block suspends to another fiber of the same thread while the lock is held is a
   deadlock, not a slow path. No 5b code path holds two locks, so no lock order exists to get wrong.
3. **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden.** 5b starts no thread and waits on
   nothing, so the prohibition costs it nothing — and it is what makes `Instrumentation.contain`'s `rescue`
   sound: no asynchronous interrupt can land between the `rescue` and the diagnostic emit.
4. **An `Enumerator` abandoned mid-`#next` never runs its `ensure`.** 5b returns no enumerator.
   `Diagnostics.with` is a `begin/ensure` around a caller's block and acquires nothing inside it, which is the
   engine-owns-the-resource shape §7.1 fixes; and the two steps acquire nothing — phase 3b's wrappers own the
   body lifecycle and 5b constructs them without closing them.
5. **Bytes on the wire are `Encoding::BINARY`.** Every captured preview arrives BINARY from phase 3a's sinks,
   and `Preview.render` **retags before transcoding** rather than transcoding from BINARY — verified fact 11,
   and `OI-7`'s finding. The binary branch never decodes at all and reports `#bytesize`.
6. **Pin `URI::RFC3986_PARSER` explicitly.** Every parse in the redactor does. `Dexpace/NoUriDefaultParser` is
   the mechanised half, and `5a`'s finding travels: `URI.decode_uri_component` and
   `URI.decode_www_form_component`, never `URI::RFC3986_PARSER.unescape`, which warns on 3.4.10.
7. **Regexp timeouts are per-pattern.** Two families — `OBS-12`'s query tokenizer's escape-aware split and
   `OBS-38`'s `+json`/`+xml` suffix matcher — each `Regexp.new(source, timeout:)`, each compiled once into a
   frozen constant, and never `Regexp.timeout`. Verified that the process-global stays `nil`.
8. **`downcase` takes no argument.** Four call sites: `OBS-12`'s decoded parameter name, `OBS-18`'s header-name
   gate, `OBS-35`'s tolerant level parse, and `OBS-38`'s media-type subtype fold.
   `Dexpace/NoLocaleCaseFold` is what makes that a rule rather than a habit, and `OBS-12`'s allow-list is
   exactly the kind of security decision a Turkish-locale fold would silently invert.
9. **`Ractor` is never load-bearing, and 5b narrows the claim twice.** `OBS-24`'s snapshot is shallow-frozen
   and no shareability claim is made (`P5-22`); a `Logger` holds a mutable latch and a mutex, so no claim is
   made for it either. `data-modeling/5bc538ba`, phase 1's `P1-9` and `5a`'s `P5-6` already narrow it.
10. **`NFR-7`'s warnings-fail-the-build rule is the gate `R12` routes around.** 5b's `lib/` makes no call that
    warns on any supported Ruby; the one `Fiber#storage=` in the whole repository after 5b is a single test
    line with a comment saying why, and `DexpaceTestCase` failing on an unexpected warning is what would catch
    a second one appearing.

## Testing strategy

`test/` mirrors `lib/` one file per file; each file's header comment names the requirement IDs it exercises,
and a non-obvious branch names the ID that forced it. Every suite subclasses `DexpaceTestCase`, so a warning
raised by code under test fails the test that triggered it — which in this sub-phase is not a formality but
the mechanism that would catch a `Fiber#storage=` creeping into `lib/`.

**No transport, no socket, no real stream.** Roadmap cross-cutting constraint 4 puts phases 1 through 7 on an
in-memory fake transport; the two steps are driven through a `Dexpace::Pipeline` over one, and every body is a
`Dexpace::BufferBody`.

**Two doubles of 5b's own, both fakes** (`testing/7ecef8e8`, `/630ba094`), under
`gems/dexpace-core/test/support/`, each required explicitly by the suites that use it (phase 2's precedent) —
plus three of `5c`'s **files** that 5b's step tests **reuse rather than reimplement**.

**Both of 5b's are flat under `Dexpace`, not under `Dexpace::Instrumentation`.** `5a` set the convention with
`Dexpace::FakeClock`, `Dexpace::FakeSource` and `Dexpace::ProbeScheduler` — the most recent phase, and the one
whose shape this sub-phase follows — and `5c`'s six recording doubles follow it too, so `RecordingSink` sits
beside `Dexpace::DiagnosticContext` rather than one level deeper than it. The draft nested it as
`Dexpace::Instrumentation::RecordingSink`, which would have put a test-only constant inside the shipping
namespace the runtime surface manifest walks and made 5b inconsistent with its own second double.

- **`RecordingSink`** — a real in-memory `_Sink`: the eight methods, with per-severity enablement the test
  sets and an array of every rendered payload. It is what every `OBS-1`–`OBS-9`, `OBS-39` and `OBS-40`
  assertion reads.
- **`DiagnosticContext`** — a test helper that snapshots fiber storage before a block and restores it in an
  `ensure`. **Every `Diagnostics` test uses it**, because `testing/4ef070df` requires every test to run alone
  in any order and a leaked `Fiber[:"trace.id"]` is visible to every later test on the same thread. This is
  the double most likely to be skipped and the one whose absence produces the most confusing failure.
- **`5c`'s `recording_tracer.rb`, `recording_span.rb` and `recording_meter.rb`, consumed and not redefined.**
  Three files, **six** constants: `Dexpace::RecordingSpan`; `Dexpace::RecordingTracerFactory` and
  `Dexpace::RecordingTracer` (a *separate* factory constant, not a nested `RecordingTracer::Factory`); and
  `Dexpace::RecordingMeter` with `Dexpace::RecordingCounter` and `Dexpace::RecordingHistogram`. **5b declares
  none of the six**, including the counter and the histogram. They record
  call names and arguments against `5c`'s own protocols, and `5c` asserts every recording clause of `OBS-21`,
  `OBS-29`, `OBS-30` and `OBS-31` against them (`P5-48`). The draft wrote 5b versions of the tracer and the
  meter because the names were `5c`'s to confirm and `5c` did not exist; the names are now confirmed and two
  files at one path were the alternative. `OBS-34`'s conformance test — the one that discharges the clause —
  drives 5b's step with `5c`'s two and 5b's `RecordingSink`.

**The tests a reader would otherwise write wrong.**

- **`OBS-1`'s allocation assertion, written with `Symbol` and `Integer` arguments and asserted as a two-loop
  delta of exactly zero.** `R8`. A test written with a `"x"` literal passes in this repository and fails when
  `dexpace-conformance` restates it without the magic comment — the failure is in the *conformance gem*
  against a *correct implementation*, which is the worst place for it. The suite additionally asserts the
  identity half with `assert_same` on the qualified constant, which is what forces `Event::INERT` public.
- **`OBS-5`'s precedence, with all three sources supplying the same key.** The chapter's own conformance case.
  A test that supplies two of the three passes under an implementation that gets the third wrong, and the
  third — folded diagnostic context — is the one whose loss is silent, because a missing diagnostic key looks
  like a diagnostic key that was not set.
- **`OBS-4`'s suppression, tested from all three sources separately.** `OBS-4` names three places an `event`
  key can arrive from and requires each suppressed; `OBS-40` requires exactly one of the three — the per-event
  field — to be **warned about** and the other two to defer **silently**. So there are six assertions, not
  two, and the pair that is easiest to get wrong is "global context supplies `event`, a tag is set, no warning
  is emitted".
- **`OBS-12`'s multi-value atomicity, with a name appearing three times.** `?t=1&t=2&t=3` must redact all
  three or keep all three. An implementation that decides per pair passes a two-occurrence test by accident
  half the time.
- **`OBS-12` with a percent-encoded, invalid-UTF-8 parameter name.** `?%FF=secret`. Verified fact 7: this is
  the input that raises `ArgumentError` out of `#downcase` and that a `rescue URI::Error` propagates. The
  assertion is that the value is `***` and that nothing raised — asserted as `assert_equal` on the output,
  never `assert_nothing_raised` (`testing/26b866e1`).
- **`OBS-14`'s trailing `?`, asserted on the rendered string and not on `#query`.** Verified: an emptied query
  must be assigned `""` and never `nil`, because `nil` removes the `?`. The test redacts `https://h/x?` and
  asserts the output *ends with* `?`.
- **`OBS-14`'s fragment `?`, the chapter's own case.** `http://h/p#a?b=c` → assert **no `?` before the `#`**.
  A test that only asserts the fragment is redacted passes under an implementation that also inserts a
  spurious `?`.
- **`OBS-16`'s presence test, with `/cb?` — a relative value with a present-but-empty query.** Verified:
  `P.parse("/cb?")` gives `query == ""`, which is falsy in no language but is what `if query` gets wrong in
  none and what `if query && !query.empty?` gets wrong in this one. The assertion is `/cb?***`.
- **`OBS-16`'s unparseable route, with a value the parser rejects.** `"a b?c=1"` raises
  `URI::InvalidURIError`, so the branch has no parsed object and the path comes from string surgery. A test
  that only uses relative-but-parseable values never enters the branch, and the branch is the one that has to
  be written twice.
- **`OBS-16`'s fragment-only value.** `#frag` → `?***`, because the path is `""`. It looks wrong; it is the
  requirement.
- **`OBS-15`'s rebuild failure, constructed directly.** The `P5-27` rule makes the opaque-URI branch
  unreachable through the public entry point, so a test that only feeds URLs never covers the `rescue`. The
  suite drives the internal rewrite with the guard bypassed and asserts `[malformed url]`, so the branch has
  coverage rather than a comment claiming it cannot happen.
- **`OBS-34`'s independence, asserted as four things in one test at level `none`.** Zero sink writes, one span
  start, one span end, one counter record, one histogram record. `R11`. A test that asserts only "no events at
  none" passes under an implementation that guards the span with the same `if`.
- **`OBS-20`'s two halves in two tests that must not be merged.** A sink whose `#warn` raises: the request
  still completes and an `http.instrumentation.*` diagnostic is emitted. A meter whose record raises: the
  exception **propagates**. The second is an `assert_raises`, and writing it as "and nothing bad happens" is
  how the asymmetry gets quietly removed.
- **`OBS-20`'s secondary failure.** A sink that raises on *every* call, including the diagnostic. The
  assertion is that the request completes and nothing raised — and it is the test that fails if the inner
  `rescue` is written as a bare `rescue nil` in a place Ruby parses differently than intended.
- **`OBS-8`'s race, two threads on one event instance.** Exactly one output. Sequenced through a
  `Thread::Queue` so it is deterministic rather than flaky, which is phase 3a's precedent for the same shape.
- **`OBS-10`'s null-value skip, in unfiltered mode, with the input built by `Fiber#storage=` in the test.**
  `R12`. This is the only `Fiber#storage=` in the repository after 5b and it carries a comment saying so.
- **`OBS-24`'s restore on exception, and its restore of an *absent* key.** Two assertions: after a block that
  raises, the prior context is back; and a key that was **unset** before the snapshot is unset after, not
  present-with-`nil`. Verified fact 3 is what makes the second one pass, and an implementation that restores
  only the captured keys fails it.
- **`OBS-24` across a real thread boundary.** Capture on thread A, run the block on thread B through the
  bridge, assert the captured keys visible inside and B's original context restored after. Verified that a new
  `Thread` inherits a copy of the parent's storage, so B's "original context" is not empty and a test that
  assumes it is asserts the wrong thing.
- **`OBS-38`'s three cases, none of them ASCII.** An ISO-8859-1 body that decodes, a binary body that gets the
  size marker, and a truncated multibyte body that yields U+FFFD. `OI-7`'s own finding is that **an ASCII-only
  fixture passes under the bug**, which is why phase 3 made every encoding test non-ASCII and why 5b does too.
- **`OBS-7`'s cap, asserted on `bytesize`.** Verified fact 9: the requirement's conformance sentence says
  "output length equals cap+suffix", and `String#length` is characters. The assertion is on bytes and the
  divergence is named in the test.
- **`OBS-18`'s negative, which is the assertion that matters.** Log a request carrying `Authorization` and
  `Content-Type`; assert the `Content-Type` **value** is present and that the string `Bearer` appears nowhere
  in the emitted payload. Asserting only that an `Authorization` key is absent passes under an implementation
  that logs the value under a different key.
- **`OBS-11`'s negative, likewise.** Redact `https://user:secret@h/x` and assert neither `user` nor `secret`
  appears as a substring anywhere in the output — the chapter's own conformance wording, and the only form of
  the assertion that catches a redaction applied to the wrong component.

## The interface surface later phases may cite

**The load-bearing statement is a negative one, and it is the charter's.** `5a` and `5c` are not obliged to
consume any of this, and a plan that waits on it has re-imposed a chain that does not exist. What 5b ships as
a stable contract:

| Consumer | What it gets, and when |
|---|---|
| **`5c`**, on `OBS-23` | `Diagnostics::TRACE_ID` and `::SPAN_ID`, **`Symbol`s**, and `Diagnostics::DEFAULT_KEYS`, from `lib/dexpace/instrumentation/diagnostics.rb`, which requires nothing else in 5b and defines no `Event`. `5c` cites them and declares no second pair (`R11`, settled) |
| **`5c`**, on `OBS-24` | `Diagnostics.capture` / `.with`, and the decision that `Fiber#storage=` is never called in `lib/`. `OBS-23`'s per-key push and restore uses `Fiber[]=` and inherits the decision rather than re-deriving it (`R12`) |
| **`5c`**, on `OBS-34` | `Instrumentation::Step` and `::AsyncStep` with `tracer_factory:` and `meter:` as keywords defaulting to `NO_TRACER_FACTORY` and `NO_METER`, and the per-request precedence `5c` fixed. **`5c` ships no second step and no third slot** (boundary 15, `R11`, `DEF-42`) |
| **`5c`**, on `OBS-31` | Nothing. `interface _Meter` is `5c`'s, declared filled, together with `_Counter` and `_Histogram`; 5b's empty declaration was deleted at reconciliation because two declarations of one interface name is an `rbs validate` failure. 5b **consumes** them: `meter:` types as `Dexpace::Instrumentation::_Meter`, reached by bare name from inside `module Instrumentation` |
| **`5c`**, on `OBS-20` | `Instrumentation.contain`. **`5c` may not wrap a tracer or meter call in it**, and 5b may not stop wrapping its own emissions (boundary 3). 5b's step calls `5c`'s tracer, scope, span and instrument methods **outside** `contain`, in the `ensure`, which is the same rule seen from the caller's side |
| **`5c`**, on `OBS-32` | `Keys::INSTRUMENT_REQUEST_COUNT` and `::INSTRUMENT_REQUEST_DURATION`, the two names the step's instruments are created under. `5c` declares no instrument name, unit or attribute set, and `OBS-32` stays ⏳ `DEF-9` for the units, descriptions and attribute sets (`R11`) |
| **`5c`**, on test doubles | Nothing 5b ships. 5b's suite **consumes** `5c`'s `RecordingTracer`, `RecordingSpan` and `RecordingMeter` under `test/support/` and adds no second set (`P5-48`) |
| **`5c`**, on `DEF-31` | Nothing. `Events::INSTRUMENTATION_SHUTDOWN` is a **log-event name** in 5b's `Events` and has no place in `OBS-28`'s vocabulary to find: `OBS-28` enumerates eleven methods across three groups — operation, per-attempt, transport — and none is a shutdown or close milestone, so a twelfth would be vocabulary `OBS-28` does not name. Settled here; `5c` adds no method for it |
| **`5a`** | Nothing. 5b consumes `Configuration#string` and adds two `Configuration::Keys` constants; it changes no `5a` signature |
| **Phase 6**, on the retry and redirect steps | `Instrumentation::Logger#event`, `Severity`, `Instrumentation.contain` and `Keys`/`Events`. **Every log emission in phase 6 goes through `contain`**, because `OBS-20`'s "every log-emission site" is not scoped to phase 5's sites |
| **Phase 6**, on `DEF-39` | The two steps are two of the three families `Pipeline.standard` installs. Phase 6 writes the constructor **over** `Builder#install_preset` and 5b installs nothing |
| **Phase 6**, on `AUTH` | `RedactionPolicy#with`, for a phase that may need a header name allow-listed or a credential type kept out of a rendering. **The userinfo redaction has no member to change**, deliberately (boundary 4) |
| **Phase 8**, on `TRANSPORT-8` | `Severity` and the once-per-key throttle, which is what `DEF-41` targets. Phase 8 writes the three-mode policy at the call site that actually drops a header |
| **Phase 8**, on `ASYNC-8`–`ASYNC-12` | `Diagnostics.capture` and `.with`, and `R12`'s decision. `dexpace-async-thread`'s pooled-worker save/install/restore is the case `Diagnostics.with` was shaped for, and `OI-13`'s warned setter is the call it does not have to make |
| **Phase 8**, on `DEF-31` | `Events::INSTRUMENTATION_SHUTDOWN`, and the row still open with phase 8 named |
| **Phase 8**, on `DEF-22` | `OBS-1`'s allocation assertion in the form `dexpace-conformance` restates, and the reason its argument types rather than its file's magic comment are what make it portable (`R8`) |
| **Phase 9**, on `XCUT-19` | `RedactionPolicy::DEFAULT`'s three sets and `HTTPLogging::DEFAULT`, as the five clauses' audited subjects — (a) `OBS-11`, (b) `OBS-12`/`OBS-13`, (c) `OBS-18`, (e) `OBS-34` |
| **Phase 9**, on `XCUT-20` | `Instrumentation.contain`, `Redactor#url`'s sentinel and `Preview.render`'s never-throw decode as the three totality paths |
| **Phase 9**, on `XCUT-11` | `Redactor` and `RedactionPolicy` — frozen, no per-call state — as the audited shared instances |

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`.

**Numbering starts at `P5-16` because the block `P5-16`–`P5-39` is reserved for this sub-phase and `P5-40`
onward for `5c`.** `5a` consumed `P5-1`–`P5-15`. The sequence is not contiguous with `5c`'s because the two
sub-phases were designed **concurrently**: a shared "next free number" would have had both documents taking
the same one, and a ledger id is cited from source comments and tests and can never be renumbered.
Twenty-three of the twenty-four reserved numbers are used.

**`P5-39` is a deliberate gap and not a lost row.** It was reserved by this document and never needed; nothing
was written against it, nothing was deleted, and nothing is renumbered to close it. A reader meeting the jump
from `P5-38` to `5c`'s `P5-40` should read it as the cost of two designs landing without a lock between them,
which is what the reservation was for.

**The collision with `5a`'s plan is resolved, and the sentence that moved is `5a`'s.** `5a`'s **plan**
(`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md`) reserved `P5-16` for "a sixteenth
deviation found at execution time", which is the number this block starts at. 5a's design ledger is complete
at `P5-15` and its sixteenth row was hypothetical; this document's `P5-16` is actual and its rows are written,
so the actual row keeps the number. The reconciliation pass repointed 5a's plan to **`P5-50`** — the next
number no sub-phase has claimed, `5c`'s block ending at `P5-49` — and recorded there that `P5-39`'s gap is
deliberate.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P5-16 | Public **constants** design §8.1 does not name: `Dexpace::Instrumentation::Severity` (+ four constants and `ALL`); `::Keys` (twelve frozen `String` constants) and `::Events` (eight); `::NULL_SINK`; `::Logger` (+ `Logger::NULL`); `::Diagnostics` (+ `TRACE_ID`, `SPAN_ID`, `DEFAULT_KEYS`); `::RedactionPolicy` (+ `DEFAULT`); `::Redactor` (+ `DEFAULT`, `MALFORMED_URL`, `REDACTED_VALUE`, `REDACTED_USERINFO`, `REDACTED_HEADER`, `RELATIVE_MARKER`); `::Preview` (+ `BINARY_MARKER_FORMAT`, `TEXT_SUBTYPES`); `::HTTPLogging` (+ `NONE`, `HEADERS`, `BODY`, `DEFAULT`); `::Step`; `::AsyncStep`; `Keys::INSTRUMENT_REQUEST_COUNT` and `::INSTRUMENT_REQUEST_DURATION`; and the RBS interfaces `_Sink` and `_DiagnosticSnapshot` | `NFR-4`; `api-design/b0e18938`; phase 2's P2-11, phase 4a's P4-2 and `5a`'s P5-1 precedent | §8.1 names exactly three Ruby identifiers in this segment — `Dexpace::Instrumentation::Event`, `Event::INERT` and `NullLogger` — and describes everything else in prose. `NFR-4` locks every public name at the first release tag, so a name arriving by accident is locked by accident. Each is chosen for a stated reason in the object-model section, and the `Keys`/`Events` constants are additionally required to be snapshot-covered by §8.1 itself |
| P5-17 | Public **methods** design §8.1 does not name: `Logger.build`, `#event`, `#enabled?`, `#context`, `#sink`; `Event#field`, `#event`, `#cause`, `#emit`; `Severity.of`; `Diagnostics.capture`, `.with`, `.folded`; `RedactionPolicy.build`, `#with`; `Redactor.build`, `#url`, `#header_value`, `#header_name?`, `#policy`; `Preview.render`; `HTTPLogging.of`, `.parse`, `.resolve`, `#at_least?`; `Step.build`, `#call`, `#stage`; `AsyncStep.build`, `#call`, `#stage`; `Dexpace::Instrumentation.contain`; plus the `logger:` keyword added to `Dexpace.close_quietly` and to `Dexpace::Proxy.resolve` | `NFR-4`; phase 2's P2-11 and phase 4a's P4-11, both of which cover methods as well as constants | `NFR-4` locks a public *signature*, not only a name. Two deserve naming here. **`Logger::NULL` exists so no caller ever holds a `nil` logger** — `contain` takes one, `close_quietly` takes one, and a `nil` would make every containment site branch; `Bundle::NONE` is phase 4a's identical decision. **`Redactor#policy` is public so a later phase derives with `#with` rather than rebuilding**, which is what keeps `OBS-17`'s "shared … so it cannot drift" true when phase 6 needs one more allow-listed header |
| P5-18 | `Event#tag(key, value)`, listed in design §8.1's code block, is **not shipped** | §8.1; `OBS-4`, `OBS-5`; `NFR-4`; `OI-8`'s shape | §8.1 lists it once and never mentions it again. No `OBS` requirement names a tag other than `OBS-4`'s reserved `event` tag, which `#event(name)` sets, and `OBS-5`'s precedence enumerates exactly three sources — so a fourth channel would have no precedence rule, no default and no test. A public, `NFR-4`-locked method with no requirement and no caller is `OI-8`'s exact shape, and `OI-8` is open right now because a previous phase shipped one. Adding a method later **widens**, so nothing is prejudiced. `OI-25` records the finding against §8.1, because the method is named in a frozen document |
| P5-19 | The default sink is `Dexpace::Instrumentation::NULL_SINK`, one frozen instance of a `private_constant` class, and not §8.1's `NullLogger` class | §8.1; `OBS-1`; phase 4a's `NO_SPAN`/`NO_TRACER_FACTORY` precedent; `Dexpace/QualifiedCoreConstant` | Two reasons. What `OBS-1` needs is a **value** to install and compare, not a class to instantiate, and phase 4a already set the shape for exactly that: a public constant naming a frozen instance of a private class. And `Logger` is already taken in this namespace by the facade §8.1 itself calls `Logger#event`, so a second constant whose name also says "Logger" would put the facade and its default output under one word in one namespace — the confusion `P5-3` avoided for `Sources::ENV` |
| P5-20 | `Event::INERT` is a frozen instance of `Event::Inert < Event`, a `private_constant` subclass, rather than a frozen `Event` | `OBS-1`; `NFR-3` | A frozen `Event` raises `FrozenError` the first time `#field` writes its accumulator, and `OBS-1` requires the disabled path to be a no-op, not a failure. An unrelated class would make `Logger#event`'s return type a union and force an RBS interface for a case a subclass models exactly. The subclass writes no instance variable, so freezing it is safe, and `is_a?(Event)` stays true |
| P5-21 | `Dexpace::Instrumentation::Event` and `::Logger` are plain classes, not `Data` types, against phase 1's construction pattern | `OBS-8`; `OBS-40`; `docs/sdk-design-ruby/04-domain-model-construction.md`; `data-modeling/3e37c086` | `OBS-8` says field, tag and cause accumulation "is not required to be thread-safe (single-thread build)", which describes a mutable accumulator; a frozen value type cannot accumulate. `Logger` holds `OBS-40`'s once-per-logger latch. Phase 1's pattern governs the **wire model**, and `data-modeling/3e37c086` already puts an implementation of a duck type in a class. Both keep `private_class_method :new` and a validating `.build`, so the half of the pattern that is about construction discipline survives |
| P5-22 | `OBS-24`'s snapshot is a shallow-frozen `Hash` and **no `Ractor` shareability claim is made** | `OBS-24` ("The snapshot itself MUST be immutable/shareable"); `data-modeling/5bc538ba`; phase 1's P1-9; `5a`'s P5-6 | The snapshot's *values* are the host's, and `Ractor.make_shareable` on an unshareable value raises `Ractor::IsolationError` — from a logging path, which `XCUT-20` forbids failing. "Immutable/shareable" is read as one property, immutability, which is what makes the cross-thread bridge the requirement is about safe and which a frozen `Hash` supplies. A claim that holds only for hosts that store shareable values is not a claim |
| P5-23 | `OBS-24`'s reinstall and restore are **per key over the union of the captured and prior key sets**, through `Fiber[]=` alone; `Fiber#storage=` is never called in `lib/` | `OBS-24`; `OI-13`; `NFR-7`; design §8.1 | `OI-13` records two problems with the whole-map setter: it warns per call at the default warning level against a gate set that fails on warnings, and `= nil` reads back differently on the 3.2 floor. A scoped `Warning.warn` filter (verified to work) is a mutation of a process-global object, which this port refuses for `Regexp.timeout`; an `NFR-7` waiver's re-enable condition would be a condition on MRI's roadmap. The per-key route removes both problems instead of silencing one, and is verified exact. **Residual, stated in the YARD block:** a prior key holding a literal `nil` restores as absent — and such a key is only constructible through the setter this route refuses. `R12`, conditional on the floor re-run |
| P5-24 | The diagnostic-context key constants are **`Symbol`s**, and the fold to an `OBS-39` field key is `Symbol#name` and never `#to_s` | `OBS-10`, `OBS-23`, `OBS-39`, `OBS-1` | Verified: `Fiber#storage=` raises `TypeError` on a `String` key and `Fiber[]=` coerces one, so the storage key space **is** `Symbol`-shaped whatever a constant declares; and `Symbol#name` returns the same frozen `String` on every call while `#to_s` allocates a fresh unfrozen one. A fold written with `#to_s` allocates one `String` per folded key per event, on the hot path `OBS-1` exists to protect. The specification writes the keys as `trace.id` and `span.id`, which is the *field* spelling, and both spellings are needed — and verified at reconciliation that `:"trace.id".name` is **not** `equal?` to a `"trace.id"` frozen literal, so one constant must be the single source. **Narrowed at reconciliation, against `5c`'s frozen-`String` counter-proposal:** the deciding fact is not `Fiber#storage=`'s `TypeError` (a call `P5-23` never makes in `lib/`) but `Fiber.current.storage` returning `Symbol` keys unconditionally, which is the reader `OBS-10`'s unfiltered mode is obliged to use, plus design §8.1's own `Fiber[:key]` spelling. `R11` carries the ownership half |
| P5-25 | The redactor has **two** public entry points with two failure policies, `#url` and `#header_value` | `OBS-15`, `OBS-16`; `XCUT-20` | `OBS-15` requires the `[malformed url]` sentinel "on any parse/rebuild failure"; `OBS-16` requires the **opposite** for the same input arriving as a header value — keep the path, append `?***`. Both are MUSTs. One entry point loses one requirement whichever way the collision resolves, and neither §8.1 nor §11 records that they are two operations. `R9` |
| P5-26 | The redactor rescues `StandardError`, not `URI::Error` | `OBS-15`, `OBS-12`, `XCUT-20` | Verified: `URI::RFC3986_PARSER` **accepts** `%FF` in a query; `URI.decode_www_form_component("%FF")` returns an invalid-UTF-8 `String`; and `OBS-12`'s "decoded, compared case-insensitively" then raises `ArgumentError: input string invalid` out of `String#downcase`, which is not under `URI::Error`. `https://h/x?%FF=secret` is reachable from any server. `#scrub` before folding keeps the common case out of the rescue; the rescue still covers `OBS-6`'s rendering path, which calls `#to_s` on caller-supplied objects inside the same containment. `R9` |
| P5-27 | The redactor **never assigns a URI component that was absent** | `OBS-14`, `OBS-15`; verified fact 6 | Verified: `userinfo=` and `query=` raise `URI::InvalidURIError` on an **opaque** URI — `mailto:`, `urn:`, `data:` — all of which parse with a non-`nil` scheme and therefore reach `OBS-16`'s "parseable absolute" branch. A `Location: mailto:…` header is not hypothetical. Assigning only present components makes an opaque URI round-trip untouched and correct, because it has no userinfo and no query to redact. This generalises `OBS-14`'s "MUST NOT alter scheme, host, port, or path" to the three components `OBS-14` does not name. The `rescue` remains as the totality backstop and is covered by a test that bypasses the guard |
| P5-28 | `OBS-16`'s "relative or otherwise unparseable" is **two** code paths — one over a parsed `URI`, one over the raw `String` | `OBS-16` | Verified: `P.parse("/cb?code=S")` succeeds with `scheme == nil`, and `P.parse("a b?c=1")` raises. The unparseable route has no object to read `#path`, `#query` or `#fragment` from, so it derives the path and the query-or-fragment test by string surgery on the raw value. Calling `parse` again inside the branch does not help — it raises again. Written as one branch, the code is either wrong for one of the two inputs or silently re-parses |
| P5-29 | `OBS-7`'s bounded maximum is measured in **bytes**, truncated with `#byteslice` then `#scrub("")` then the marker | `OBS-7` ("bounded maximum length (reference: 8 KiB)") | Verified: `("é" * 5000)` is 5000 characters and 10000 bytes; `#byteslice(0, 8191)` yields an invalid `String`; `s[0, 8192]` yields 16384 bytes. "8 KiB" is a memory bound and only the byte reading makes it one. The cost is that `OBS-7`'s conformance sentence — "assert output length equals cap+suffix" — is asserted on `bytesize` and not on `length`, and the divergence is named in the test rather than resolved silently |
| P5-30 | The default header-name allow-list's exact membership is chosen, not derived, and excludes `www-authenticate` and `proxy-authenticate` | `OBS-18` ("MUST contain only diagnostic, non-credential headers"); `XCUT-19`(c) | `OBS-18` names a property and no list, and `NFR-4` locks whatever list ships. Twenty-six names are enumerated in the object model. The two challenge headers are excluded even though a challenge is not a credential, because a Digest challenge carries a server nonce and whether that is loggable is `AUTH`'s question, phase 6's. Default-deny means an omission is safe and an inclusion is not, so the list errs short |
| P5-31 | `OBS-38`'s text/binary discrimination set is chosen, and its decode is phase 3b's corrected recipe rather than design §3.1's | `OBS-38`; `HTTP-42`; `OI-7` | `OBS-38` says "charset-aware for text … binary-safe for non-text" and gives no test. `TEXT_SUBTYPES` plus `type == "text"` plus the RFC 6839 `+json`/`+xml` suffixes is the discriminator, and an **absent** media type is binary — rendering unknown bytes as text is how a log line acquires a control character. The decode retags before transcoding and names both encodings; verified that §3.1's form returns `"caf"` plus two replacement characters for `"café".b`. `OI-7` is the open item and §3.1 is frozen |
| P5-32 | `OBS-19` is carried **⏳ against a deferral** rather than as §12's "vacuous" | §12's `OBS` row; `OBS-19`; `OI-8`; the charter's 5b scope table | §12 records `OBS-19` as vacuous for `Net::HTTP` and does **not** list it as deferred, and the charter's 5b scope table expects the policy to ship. "Vacuous" names no target, no gem and no event, so a one-row-per-ID checklist has nothing to cite; and shipping a three-mode public policy with no core caller is the `OI-8` shape the charter's own `R10` forbids. The requirement's subject is a transport that drops a header, core has none, and the two halves the policy needs — `Severity` and a per-name latch — both ship here with `OBS-40` as the latch's exercising caller. `R10` |
| P5-33 | The step's `tracer_factory:` and `meter:` slots are keywords **defaulted** to `Dexpace::Instrumentation::NO_TRACER_FACTORY` and `NO_METER`, and the per-request precedence is the context's bundle when it is not `Bundle::NONE`, else the keyword | `OBS-34`; `CTX-14`, `CTX-15`; `OBS-25`; `NFR-4`; `api-design/1d9e6e0b`, `/a9943041`, `/634ccc4b`; `5c`'s `R11` | **Rewritten at reconciliation; the draft made both slots required and undefaulted and `5c`'s answer won.** The draft's reason — `meter:` cannot be defaulted without naming a `5c` object that did not exist — was an artefact of parallel authorship, and `NO_METER` ships in the same phase. On the merits: `CTX-14` already puts a `tracer_factory` on every context and `CTX-15`/`OBS-25` make `Bundle::NONE`'s the published no-op, so a required keyword would make every caller — phase 6's `Pipeline.standard` included — restate an object the request's context already carries; `OBS-34` defaults logging to `none` and `XCUT-19`(e) makes body logging off by default, so the untraced, unmetered step is this SDK's *default* configuration and ought to be writable without naming two constants; and `OBS-25`'s allocation clause is asserted by reference identity from a qualified constant, which a constant default is. A configuration read stays rejected for the reason the draft gave and `5c` gave independently: no tier of `5a`'s `String`-valued chain can carry a tracer factory. `NFR-4` decides nothing here — the lock bites on *changing* a default, not on having one. Recorded because the shipped signature differs from the one this document first argued for. **The first clause of the precedence is unimplementable in phase 5 and is `OI-31`:** no mechanism exists by which a pipeline step reaches a `RequestContext` or an `Instrumentation::Bundle` — 4c "does not consume 4a at all", `Cursor` has no context reader, `Request`'s members are `(:method, :url, :headers, :body)`, `RequestOptions`'s are `(:timeout, :max_retries, :tags)`, and `PIPE-11` forbids ambient carriage. The step therefore resolves to its keyword and to `Bundle::NONE`, which is `OBS-34`'s and `XCUT-19`(e)'s **default** configuration, so `OBS-34`'s conformance clause is unaffected; the missing clause is a widening phase 6 supplies, not a signature change |
| P5-34 | 5b ships **two** steps, `Step` and `AsyncStep`, over one `private_constant` `Emitter` | `OBS-17` ("The redaction policy MUST be shared by the sync and async logging paths so it cannot drift"); `PIPE-28`; 4c's `_Step`/`_AsyncStep` | Two steps sharing one policy *object* satisfy the letter and drift the moment one grows a field the other lacks. Two steps sharing one `Emitter` — which owns every `logger.event(…)` call and every field key in the sub-phase — cannot. `PIPE-28` requires identical stage identities in both runtimes, and `OBS-37`'s deferral presupposes an async logging path exists to skip capture on |
| P5-35 | `RedactionPolicy#omit_disallowed_headers` defaults to `false`, emitting the fixed `REDACTED` marker rather than omitting the header | `OBS-18` (a boolean policy with no stated default) | A header that was present and redacted and a header that was absent are different facts to a reader, and collapsing them loses the one that matters when a request fails on an auth header nobody realised was sent. That is `OBS-3`'s own null-versus-absent argument arriving at a second place in the same sub-phase, and the requirement's own ordering — "either emitted with a fixed redaction marker … or omitted entirely" — puts the marker first |
| P5-36 | `HTTPLogging.resolve(configuration, key:, default:)` takes its configuration key as a **required** keyword with no default, and `Configuration::Keys::LOG_LEVEL` is a name a caller may pass rather than a fallback | `OBS-35`'s embedded MUST ("The SDK MUST NOT bake in a default config key name"); `CFG-14`; `5a`'s own reconciliation | `CFG-14` asks for "stable well-known key constants … for … SDK log level" and `OBS-35` forbids baking one in, and the two are only consistent one way. `5a` fixed it and 5b implements it: the constant exists and nothing falls back to it. Restated as a ledger row rather than inherited silently, because `.resolve` is 5b's method and a required keyword with an obvious default is exactly what a later reader supplies a default for. `.parse` is the sibling for a caller who holds a level `String` and no `Configuration`, which is also what makes 5b's independence from `5a` concrete |
| P5-37 | `Instrumentation.contain(logger, event:)` is a **module function**, not a method on `Logger` or on `Event` | `OBS-20`, `XCUT-20`; §8.1 | A `logger.contain { }` reads as "the logger contains", which invites the containment to move to the sink — the placement §8.1 rejects for redaction, and for the identical reason: it can be bypassed by installing a different sink. A module function has no receiver to reimplement. It returns `nil` and swallows the block's value, so no call site can branch on whether logging worked, which is what `OBS-20` forbids; and its secondary rescue does nothing at all, because a swallow path with its own failure mode is a third failure mode |
| P5-38 | `Dexpace::Instrumentation::Logger` keeps §8.1's name despite shadowing the stdlib `Logger` for a bare reference inside `module Dexpace`, and the shadow is **not** covered by `Dexpace/QualifiedCoreConstant` | §8.1; `Dexpace/QualifiedCoreConstant` (P2-8, P3-7); `5a`'s P5-3; `SEAM-1` | `5a` met the same hazard for `ENV` and chose a different name. That escape is unavailable here: §8.1 names the facade `Logger`, and the sink duck type is deliberately the stdlib `Logger` surface as a structural subset, so the word is load-bearing. The cop cannot carry it either — adding `Logger` to `SHADOWED` would flag every legitimate bare reference in an adapter gem that declares the dependency, which is the budget `NFR-2` exists to permit. Mitigated in the two places it can be: the default sink is `NULL_SINK` and not §8.1's `NullLogger`, so exactly one `Logger`-shaped name exists in the namespace (`P5-19`), and every reference to either constant in 5b's own code is fully qualified. Recorded as a deviation because a reader checking §8.1 against the code will see a name the repository's own cop set would normally forbid, and `OI-26` carries the cop-coverage gap |

## Deferrals filed by phase 5b

**One, filed as `DEF-41`** by the pass that reconciled this design with `5c`'s, on 2026-09-09. The draft
stated the row in the register's own item format rather than appending it, because `5b` and `5c` were being
written concurrently and both would have taken the same next id. The row is now in
`docs/deferred-items.md` and is cited rather than duplicated here.

**`DEF-41` — `OBS-19`'s header-drop verbosity policy.** Phase 5b ships **no** policy object, no mode constants
and no reporting method; the requirement's subject is a transport that drops a caller-set header it cannot
encode, core has none, and `HTTP-17`/`HTTP-18`'s wire-boundary re-validation (`DEF-25`, phase 8) **raises**
rather than drops. What is *not* deferred is both halves the policy is built from: `Severity` supplies the two
levels the three modes are expressed in and the once-per-key latch supplies the throttle, with `OBS-40`'s
collision diagnostic as its exercising caller. Pick-up is phase 8, at the first adapter that drops rather than
raises (`TRANSPORT-8`), and the row carries the fallback of naming the **event** rather than a phase if no v1
adapter drops. `R10` is the argument, `P5-32` is the ledger row, and `OI-27` records that the charter's 5b
scope table words the same disposition as shipping.

## Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every row.
All forty were read — thirty-nine plus `5a`'s `DEF-40`; the register now holds forty-two, `DEF-41` being this
sub-phase's own row and `DEF-42` `5c`'s, both appended by the reconciliation pass. The charter's own sweep
covered the phase-5-wide dispositions and is not repeated, so what follows is the **5b-specific delta**. As
with phases 3, 4 and `5a`, this document **states** each disposition and 5b's **plan performs** the register
edit — the two *new* rows excepted, which are filed, because a proposed row nobody appends is a row nobody
can cite.

- **`DEF-27` — picked up and CLOSED.** The row's second disposal route is "an `http.instrumentation.*`
  diagnostic through §8.1's facade when there is not [a primary exception in flight]", and its pick-up
  condition names phase 5 explicitly: "**phase 5 supplies the second with §8.1's facade and closes this row**."
  5b adds a `logger:` keyword to `Dexpace.close_quietly` defaulting to `Logger::NULL` and routes the
  `onto:`-absent branch through `Instrumentation.contain`. **The phase-2 test asserting the rescued error is
  dropped is what changes**, which 4b's interface table already anticipates. The `onto:` keyword stays, the
  suppressed trail is not replaced, and `CFG-21`'s null-safety is untouched. `Status` moves to `picked-up`.
- **`DEF-32` — the optional half is taken; the row stays as phase 4b left it.** Its text reserves the trail for
  phase 4 and adds: "Phase 5 **may** additionally emit an `http.instrumentation.*` diagnostic per dropped
  failure once §8.1's facade exists; **it does not replace the trail**." 5b emits
  `Events::INSTRUMENTATION_HOOK` for each failure after the first and leaves the first attached and re-raised.
  `Hooks` is a `private_constant`, so no public surface changes.
- **`DEF-34` — picked up, and 5b lands second and edits the row.** Its condition names "phase 5, when
  `CFG-1`–`CFG-4`'s layered chain and `OBS-35`'s body-level-logging setting exist" and states the work as
  "three wirings and no new mechanism". `5a` supplied the third (`MAX_MATERIALIZED_BYTES`'s configured source)
  and deliberately did not edit the row. 5b supplies the other two — the shared preview size read into both
  wrappers, and the gating of their construction on `HTTPLogging::BODY` — and adds the two
  `Configuration::Keys` names **in the change that reads them**, which is `5a`'s stated reason for not
  pre-declaring them. All three are widenings, so `NFR-4` is not prejudiced. `Status` moves to `picked-up`.
- **`DEF-41` — filed by 5b.** `OBS-19`'s header-drop verbosity policy, target phase 8. See *Deferrals filed
  by phase 5b* above; the row's own text carries what is and is not deferred.
- **`DEF-42` — `5c`'s, filed at the same time and untouched by 5b.** `OBS-29`'s HTTP-tracer lifecycle wiring.
  It reaches 5b only as a negative: **no third slot on the step**, which `R11` confirms from this side.
- **`DEF-31` — half supplied, row stays open, and 5b must not close it.** Its condition names phase 5 "with
  §8.1's facade — that is where the event can be emitted", and then names phase 8: "The first thing in this
  repository that actually **owns** an executor is phase 8's `dexpace-async-thread`, so phase 8 is where the
  emission gets a real subject and where `dexpace-conformance` asserts 'close twice → executor shut once, one
  event'." 5b supplies `Events::INSTRUMENTATION_SHUTDOWN` and the field shape and adds a dated line to the
  row's `Status`. It does **not** move to `picked-up`.
- **`DEF-9` — untouched, and cited by one 5b ⏳ row.** `OBS-37` (async body-capture skip) is 5b's; `OBS-32`
  (OTel metric conventions) is `5c`'s. The condition — the OTel adapter (`DEF-17`) and the async adapters
  (`DEF-11`, `DEF-12`) — is post-v1 and 5b cannot meet it. **Worth stating precisely, because 5b ships an
  async step:** `OBS-37` is the *skip*, not the path. 5b's `AsyncStep` captures a body preview the same way the
  sync one does; what is deferred is the optimisation of not capturing for an unknown-length body, and it
  needs an async adapter to be an optimisation of anything. Not UNSCHEDULED.
- **`DEF-30` — untouched, and 5b strengthens the charter's reading without acting on it.** Its condition is "an
  instrumentation seam exists to activate". **5b adds no fourth registry**: the sink, the redactor, the level
  and the two step slots are configured or injected values, not discovered seams, and `SEAM-2` enumerates five
  core interface seams of which instrumentation is none. The row's disposition is `5c`'s to record, as the
  charter's `R15` says, and this document's reading agrees with the charter's recommendation.
- **`DEF-22` — untouched, and it is `R8`'s subject.** `OBS-1`'s allocation and identity assertions are two of
  the assertions `dexpace-conformance` will hold, in a different gem written in a later phase. `R8`'s whole
  point is that they are written here in the form that survives the copy — non-allocating argument types and a
  two-loop delta — and that the file-level `frozen_string_literal` precondition is documented as *not* what
  makes them correct. The row's condition (phase 8, which owns the gem) is not met by 5b.
- **`DEF-29` — untouched, and 5b adds two doubles under `gems/dexpace-core/test/support/`.** `RecordingSink`
  and `DiagnosticContext`, following phases 2, 3, 4 and `5a`. The condition — a consumer outside
  `dexpace-core` — is not met. **The draft added four**, and `RecordingTracer` and `RecordingMeter` moved to
  `5c` at reconciliation, because their method names belong to `5c`'s protocols and `5c` asserts every
  recording clause against them (`P5-48`); 5b's step tests reuse them. That is `DEF-29`'s own concern —
  one double per idea — met rather than deferred, and if `dexpace-conformance` ever restates `OBS-34` it
  will need `5c`'s two and 5b's `RecordingSink`.
- **`DEF-37` — untouched.** `5c`'s, with `OBS-25`. 5b reads two `Bundle` members and adds nothing.
- **`DEF-1`'s `SEAM-28` half — untouched.** `5c`'s. 5b's step reads `RequestContext#operation_name` for the
  `tracer_factory.tracer(...)` name argument, which is a *use* and not the consumer half `DEF-1` names.
- **`DEF-36` — untouched.** `5a`'s, and already picked up there.
- **`DEF-28` — untouched.** `5a`'s. Neither step calls a blocking wait, so `deadline:` reaches nothing here;
  4c's own note applies unchanged.
- **`DEF-38`, `DEF-40` — untouched.** Both are the `CFG-35`/`XCUT-5` classifier, phase 6's and `5a`'s. 5b
  classifies nothing.
- **`DEF-39` — untouched, and 5b supplies one of the three families it names.** `PIPE-24`/`PIPE-39`'s
  standard-resilience constructors target phase 6 as "the first phase in which all three families exist"; the
  instrumentation step is the family 5b builds. **5b writes neither constructor and installs no preset.**
- **`DEF-25` — untouched, and it is what makes `OBS-19`'s deferral coherent.** Wire-boundary re-validation is
  phase 8's and it **raises** on an unencodable header rather than dropping it, which is why `OBS-19`'s
  antecedent is unmet in core.
- **`DEF-33` — untouched, and its value has grown again.** 5b is the fourth phase whose concurrency guarantee
  rests on a `Thread::Mutex` the GVL would hide the absence of: `OBS-8`'s emit-once latch passes with the mutex
  and passes without it on every row of the CI matrix.
- **`DEF-3` — untouched.** `BODY-36`'s condition is core's dependency budget changing, which 5b explicitly does
  not do: it adds nothing to the require allowlist and requires only `uri` and `set`.
- **`DEF-23` — untouched.** A Steep target over a test tree; 5b's two fakes do not meet the
  "production-quality test support" condition, and `5c`'s `RecordingTracer` and `RecordingMeter` — the two
  most likely to be promoted when phase 8 restates `OBS-34` — are `5c`'s to promote.
- **`DEF-24`, `DEF-26`, `DEF-21` — already picked up** by phases 4b, 3b and 2.
- **`DEF-18` — untouched.** Phase 5b neither meets nor re-opens it; `CFG-20` is `5a`'s row.
- **`DEF-35` — untouched.** `RECOV-27`'s wait is `CFG-15`'s object, `5a`'s.
- **`DEF-2`, `DEF-4`–`DEF-8`, `DEF-10`–`DEF-17`, `DEF-19`, `DEF-20` — untouched.** Other prefixes, later
  phases, post-v1 gems, or release-gated.

## Open items filed by phase 5b

**Three, filed as `OI-25`, `OI-26` and `OI-27`** by the reconciliation pass on 2026-09-09, for the reason the
deferral above was: `5b` and `5c` were written concurrently and both would have taken the same next id. All
three are in `docs/open-items.md`; none is acted on by this document.

- **`OI-25` — design §8.1 names `Event#tag(key, value)` and no requirement in chapter 15 does.** Four of the
  five methods §8.1's code block fixes trace to a requirement and `#tag` does not; `OBS-5`'s precedence rule
  enumerates exactly three contributing sources, so a fourth channel would have no precedence and no collision
  rule. **Amended when filed:** the row now names `OBS-8`'s "Field/tag/cause accumulation" phrase, which is
  the closest chapter 15 comes to `#tag` and which a reader would otherwise cite against the item — the tag it
  names is `OBS-4`'s single reserved categorisation tag that `#event(name)` sets, and nothing in the chapter
  gives a tag a **key**, which is what the two-argument signature is for. 5b ships `#field`, `#event`,
  `#cause` and `#emit` and not `#tag` (`P5-18`).
- **`OI-26` — `Dexpace::Instrumentation::Logger` shadows the stdlib `Logger`, and `Dexpace/QualifiedCoreConstant`
  cannot carry the name.** §8.1 names the facade `Logger` and the sink duck type is deliberately the stdlib
  `Logger` surface as a structural subset, so the word is load-bearing and `5a`'s `ENV` escape is unavailable;
  adding `Logger` to the cop's `SHADOWED` list would flag every legitimate bare reference in an adapter gem
  that declares the dependency, which is the budget `NFR-2` exists to permit. 5b keeps the name (`P5-38`) and
  mitigates by shipping `NULL_SINK` rather than §8.1's `NullLogger` (`P5-19`) and by qualifying every
  reference.
- **`OI-27` — the phase-5 segmentation design's 5b scope table states an outcome its own `R10` leaves open.**
  The scope table dispositions `OBS-19` as "the verbosity policy and its once-per-name throttle ship"; `R10`
  says recording it vacuous with a phase-8 cross-reference is equally available and forbids only shipping a
  policy with no caller. Both sentences are defensible and they are not the same sentence. Filed rather than
  fixed because the charter is committed; the precedent for the sub-phase's reading winning is phase 4c's
  correction of the charter's `PIPE-39` row, and `P5-32` records the divergence.

## Open questions for 5b's own plan

Six, each bounded, none reopening a decision above.

1. **Re-run the five floor-straddling facts on 3.2.11 and 4.0.6 before the code that rests on them is
   written, and make it the plan's first task.** Facts 1 (`Fiber[]=`'s warning-free write, `= nil`'s deletion,
   `Fiber#storage=`'s `Symbol`-only key), 2 (`Fiber.current.storage`'s fresh unfrozen copy and its `nil` under
   `Fiber.new(storage: nil)`), 3 (the per-key union restore's exactness), 6 (`URI::RFC3986_PARSER`'s parse and
   rebuild behaviour, including the opaque-URI raises) and 9 (`#byteslice`'s invalid result and `#scrub`'s
   trim). **Only 3.4.10 is installed on this machine**, verified. `R12`'s decision is explicitly conditional
   on fact 1 holding across the range, and `OI-13` already records that a neighbouring fact does **not** hold
   on the floor, so this is not a formality. Recommendation: install the two interpreters and re-run all five
   as a single script whose output is pasted into the plan, exactly as phases 3 and 4 did. **If `Fiber[:k] =
   nil` stores rather than deletes on some Ruby**, the restore loop deletes explicitly instead of assigning and
   the mechanism is unchanged; `P5-23` survives and only its loop body moves.
2. **Reconciled with `5c`, 2026-09-09 — nothing left open here, and the plan adopts the names as written.**
   The five method names, the two key-name constants, `interface _Meter`, the two slot defaults, the two
   instrument names and the recording fakes are all settled above and in `5c`'s design; there is no
   `# PENDING 5c` marker anywhere in this document and the plan must not reintroduce one. What the plan
   *does* still owe is the mechanical half: read `5c`'s shipped `sig/` and `lib/` before writing the step, and
   if `5c`'s own open question 2 (`opentelemetry-api`'s exact arities) or question 3 (`record_error` versus
   `record_exception`) moved a name after this reconciliation, adopt the moved name and say so — 5b fixes
   where and when these are called and `5c` fixes what they are called, which is unchanged.

3. **Confirm `Dexpace::MediaType`'s accessor names before `Preview.render` is written.** This document assumes
   `#type`, `#subtype` and `#charset`, of which only `#charset` is quoted verbatim from phase 1's design
   ("`#charset` resolves the `charset` parameter case-insensitively and returns `nil` when absent or
   unrecognised"). `#type` and `#subtype` are the `Data.define(:type, :subtype, :parameters)` members and are
   therefore generated readers, which is safe — but `OBS-38`'s suffix rule needs the subtype string and the
   plan should confirm rather than infer. Recommendation: confirm on the first task, and if a `#suffix`
   accessor exists, use it instead of the `+json`/`+xml` regexp and drop one pattern from `P5-31`.
4. **Confirm `Dexpace::Async::Future`'s `#on_settle` yields a `Settlement` and what that carries.** The async
   step needs the status, the response or the error, and the elapsed time. Phase 2's design names
   `Async::Settlement` and says `#on_settle` is "what it yields"; it does not enumerate the members here.
   Recommendation: read phase 2's shipped `settlement.rb` on the first task rather than the design's
   description of it, and if the `Settlement` does not distinguish cancelled from failed, the `AsyncStep`'s
   failure event needs a third branch and `OBS-39`'s `error.type` needs a value for it.
5. **Decide where `preview_bytes:`'s default comes from when a caller builds a step at `HTTPLogging::BODY`
   without one.** `OBS-36` names a "reference default 8 KiB" and `DEF-34` says the cap is read "from the
   chain". This document makes `preview_bytes:` a keyword defaulting to `nil` and required in effect at
   `BODY`. Recommendation: `Step.build` raises `Dexpace::InvalidArgumentError` naming the field when `level`
   is `BODY` and `preview_bytes:` is `nil`, rather than silently defaulting to 8 KiB — a silent default is a
   memory bound nobody chose. The `Configuration::Keys` name 5b adds is what a caller resolves it from, and
   `HTTPLogging.resolve`'s shape is the precedent: the key is passed, not baked in.
6. **Confirm whether `dexpace-core`'s existing `test/support/` fakes already have a recording-sink shape.**
   Phases 2, 3 and 4 each added doubles and `5a` adds three more. Recommendation: read the directory on the
   first task; if a recording collaborator already exists with the right shape, extend it rather than adding a
   fifth pattern for the same idea, which is the drift `DEF-29` will eventually have to consolidate.
