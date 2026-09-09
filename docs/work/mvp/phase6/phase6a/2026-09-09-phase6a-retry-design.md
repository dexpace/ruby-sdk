# Phase 6a — Retry

**Status:** Draft, for review. Written 2026-09-09, against
`docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`, which is this sub-phase's charter.

## Purpose

Sub-phase 6a builds the retry subsystem in full: **one** shared policy core (status-and-throwable
classification consult, re-sendability gate, backoff calculator, pacing-header parser, tuning
constants) and the **two** stacks the charter names as `6a`'s whole scope — the recovery-chain retry
that installs beneath phase 4b's `Recovery::Orchestrator` with a total-timeout budget, and the
stage-based pillar step at `Dexpace::Pipeline::Stages::RETRY` with a sync and an async driver.
Sixty requirement IDs: forty-five `RETRY` and, under `DEF-35`, fifteen `RECOV` (`RECOV-17`–`RECOV-30`,
`RECOV-34`), each carrying its own checklist row per the charter's decision — a cross-reference to
the `RETRY` twin is an annotation on the row, never the row's disposition.

**It is the sub-phase the charter recommends first**, for four reasons the charter itself gives and
this document does not re-argue: it is the largest and the longest pole; it closes or half-closes
four register rows (`DEF-35`, `DEF-38`, `DEF-40`, half of `DEF-42`); it is where `OI-31`'s cursor
widening is assigned; and it is where the redirect-then-auth marker's writer-before-reader ordering
becomes moot because `6a` touches neither side of it. **None of that makes `6a` a dependency of `6b`
or `6c`.** The charter is explicit that every phase-6 boundary is a convenience, and the Prerequisites
section below states that independence in `6a`'s own words rather than inheriting a chain by habit.

Seven decisions the charter named and declined to make are made here — `R1`–`R6` and `R15` — plus
`OI-31`'s cursor-widening task, which the charter assigns to `6a` outright. Two of the seven turn on
a fact this document verifies against 5a's shipped code rather than against the segmentation
charter's prose, because the charter could describe the shape of the problem but not the exact
regular expression 5a wrote:

- **`R1`** — 5a's `Dexpace::HTTPDate::GRAMMAR` requires a **two-digit** day (`(\d{2})`), verified
  by reading `gems/dexpace-core/lib/dexpace/http_date.rb`'s task in
  `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md` (Task 5). `RETRY-15` asks for
  tolerance of a single-digit day. The weekday tolerance `RETRY-15` also asks for is **already**
  there — the grammar captures `[A-Za-z]{3}` with no comparison against the computed weekday, and
  5a's own `CFG-31` test proves it by asserting `"Mon, 06 Nov 1994 …"` (wrong weekday) parses. `6a`
  widens the day group to `(\d{1,2})` and nothing else, and states exactly what that costs 5a's own
  test suite.
- **`R2`** — 5a's `Dexpace::Async.delay` **already** completes a zero-length delay before checking
  for a scheduler (verified by reading Task 7's code: the `dur.zero?` branch returns before the
  `Fiber.scheduler.nil?` check), so `RETRY-31`'s "a zero-length delay completing inline and re-arming
  the active pump" is free. Only a **positive** computed delay with no registered scheduler raises
  `Dexpace::SeamError`. `6a` picks the route that fact makes the only implementable one.

## Governing documents

- `docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md` — the charter. It fixes `6a`'s 60
  IDs, the fifteen spec-forced boundaries, the four rejected cuts, and risks `R1`–`R6` and `R15`
  (`R7`–`R12` belong to `6b`/`6c`; `R13`/`R14` are phase-level and touched only where they name `6a`).
- `docs/product-spec/09-retry-and-resilience.md`, read in full (36 lines), together with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text
  of all 45 `RETRY` IDs and of `RECOV-17`–`RECOV-30`, `RECOV-34` (rows 245–258, 262). `RECOV-17`
  through `RECOV-30` appear in no prose chapter (`OI-12`); the spec-reading budget section below
  states exactly what was read in place of a chapter that does not exist for them.
- `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.1 in full — single-sourcing, the
  open capability, construction-time validation, backoff, the three hand-written `Retry-After`
  pieces, the two-stacks-one-policy argument, the inter-attempt wait, and every named deviation
  candidate.
- `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1 (cursor-scoped state, the write
  restriction) and §5.2 (the recovery chain, the cause enumerator, the suppressed-trail helper);
  `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.3 (the clock, the wait, the
  prohibition); `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items
  4, 5, 17 and 18 (item 15 is `6b`'s); `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md`
  items 1, 10, 12, 19 and 20; §12's `RETRY` and `RECOV` rows.
- `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` in full — the
  `Outcome`/`Success`/`Failure` shape, `Recovery::RequestChain`/`::ResponseChain`/`::Orchestrator`,
  `Recovery::Transform`'s three-method contract (R8), `ErrorMappingStep`, `Recovery.buffer_error_body`,
  `Dexpace::ProtocolError`, `Dexpace::Suppressible`/`.attach_suppressed`/`.suppressed`,
  `Dexpace.each_cause`, and the `RECOV-2` fatal-family passthrough already implemented as `RETRY-25`.
- `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md` in full — `Stages`,
  `Cursor#fork(state:)`/`#state(stage)`/`#may_fork?`/`#spent?`, the fork-for-every-drive rule (R11,
  P4-39), the sequential-only reuse latch (P4-33), `Builder#install_preset` (`PIPE-24`, `DEF-39`),
  `Dexpace::PipelineError`, `TransformStep`.
- `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md`, Tasks 4, 5, 6, 7, 8 and 9 read
  as **code**, not summary — `Dexpace::Retryability.retryable_status?`, `Dexpace::HTTPDate`'s exact
  grammar, `Dexpace::Clock#sleep(duration, cancellation:)`, `Dexpace::Async.delay`'s exact branch
  order, the `Future`/`Completer` `deadline:`/`clock:` additions, `Configuration::Keys` — because
  `R1` and `R2` both turn on the literal code, not the design prose describing it.
- `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md` — `HTTPTracer`'s
  eleven no-op methods across `OBS-28`'s three groups, `NULL`, `CallableAdapter`, and the deliberate
  absence of `interface _HTTPTracer`.
- `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` — `Dexpace::Body#replayable?`
  (default `false`), `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` (1 MiB, 3b's constant, **not**
  `Recovery`'s), and the forward-named `Dexpace::Resilience::Resend.eligible?(request)`.
- `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` — `Method::IDEMPOTENT`
  (`HTTP-9`'s single source, already `{GET, HEAD, OPTIONS, PUT, DELETE}`, exposed as `#idempotent?`),
  `Request` (`Data.define(:method, :url, :headers, :body)`, `body` optional), `Response`
  (`Data.define(:request, :protocol, :status, :reason, :headers, :body)` — **`Response` carries the
  request that produced it**), `Headers#[]` (case-folded, frozen `Array[String]` or `nil`), `Status#error?`.
- `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` — `Dexpace::Cancellation`,
  `Dexpace::Async::Future`/`::Completer`/`::Settlement` (never `Dexpace::Future`), `Dexpace::Closeable`,
  `Dexpace.close_quietly(resource, onto: nil)`.
- `docs/deferred-items.md` (`DEF-5`, `DEF-6`, `DEF-35`, `DEF-38`, `DEF-39`, `DEF-40`, `DEF-42`),
  `docs/open-items.md` (`OI-12`, `OI-21`, `OI-29`, `OI-31`), `docs/deviations.md`,
  `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written.
`ruby scripts/knowledge.rb --origin note --brief` returns **37 entries across 18 note files** (112
lines of output at `--brief`, matching the charter's count exactly); `--section conflicts --brief`
returns **24 entries across 17 topic files, 18 of them notes and six harvested**, with **6 of 6**
harvested conflicts printing `[overridden by notes/…]`. **None is open**, so `6a` inherits no
unresolved conflict and owns no conflict decision of its own — re-run for this document rather than
trusted from the charter's report.

`--prefix-info RETRY` reports **45 of 45 substantive, 0 roll-up only, 0 uncited**; `--prefix-info
RECOV` reports **19 of 34 substantive, 15 uncited**; `--gaps RETRY,RECOV` names the fifteen exactly
as `RECOV-17`–`RECOV-30`, distinct from `RECOV-31` (the gap set's sixteenth member and `DEF-5`'s, out
of `6a`'s budget). `ruby scripts/knowledge.rb --prefix RETRY --brief` returns zero
`[appendix-B roll-up]`-tagged entries across 105 hits — the charter's claim, re-verified rather than
inherited. `ruby scripts/knowledge.rb --prefix RETRY --section rules` was read in full (173 lines,
43 entries across `retry-and-resilience.md`, `pipeline.md` and `cancellation-and-timeouts.md`) and
every substantive bullet is a faithful restatement of chapter 9's prose or design §6.1's own words —
none contradicts a decision this document makes, so no note is filed against `RETRY`'s rules.

Two notes bind this sub-phase and are cited by key, quoted only where the charter's own text already
quotes them (both quotes are reproduced here rather than re-derived, because a design document that
cites a note by key without the load-bearing sentence in view is the failure the note exists to
prevent):

- **`pipeline/86343352`** — the fork-for-every-drive rule. "**This port's rule is: a pillar step that
  may drive more than once forks for *every* drive, the first included, and never calls its own
  `#call` at all** … The consequence for a phase-6 redirect or retry step is concrete … writing the
  mixed shape the harvested sentence describes compiles, passes every ordering test, and silently
  drops whatever the pillar meant to publish on its first drive." Binds `Stages::RETRY`'s driver
  directly: attempt 1 and attempt *n* fork identically.
- **`error-handling/a0c4abfe`** — the suppressed trail is `Dexpace::Suppressible`, included by
  `Dexpace::Error` and `extend`-able onto anything else via `Dexpace.attach_suppressed`, with
  `RETRY-34`'s self-suppression skip already implemented. `6a` writes no second trail.
- **`pipeline/f02559b9`** — every re-raise of a *carried* error is `raise error, cause: nil`, never a
  bare `raise stored`, because `$!` may be the caller's own in-flight exception. `RETRY-34`'s terminal
  surfacing and `RECOV-20`'s "the terminal failure's throwable MUST be surfaced" are both such places.

Re-run for this document and confirmed unchanged: `--phase 4` shows phase 4 cites `RETRY-13`,
`RETRY-25`, `RETRY-27`, `RETRY-28`, `RETRY-34`, `RETRY-37`, `RETRY-42`, all pointing here without
owning them; `--phase 5` shows 5a cites `RETRY-1` and `RETRY-12`, fixing `Dexpace::Retryability` as
the object `6a` computes from and never rebuilds.

**No knowledge note is filed by this document.** Nothing found here contradicts a harvested rule; the
findings this document produces are register findings (below), not corpus corrections. The
`knowledge-lookup` skill's audit-group table row the charter states is owed —
*Resilience: retry, redirect and authentication* — is the charter's own obligation, restated in the
findings section below rather than added twice.

## The spec-reading budget for the fifteen `RECOV` IDs

`RECOV-17`–`RECOV-30` appear in no prose chapter — `docs/product-spec/08-execution-pipelines.md` §8.2
states `RECOV-1` through `RECOV-16` and stops (`OI-12`). `RECOV-34` is **not** in this set; it has
substantive design-role entries (design §6.1, §10 item 18) and is read from there. The budget, stated
exactly as the charter states it: fourteen IDs read directly out of appendix C rows 245–258, and the
reading is cheap because `docs/product-spec/09-retry-and-resilience.md` states the same rules in
prose under `RETRY` IDs this document can read normally — `DEF-35`'s twin-by-twin table (reproduced
in the Scope section below) is what makes that transfer exact rather than approximate. One focused
pass over 36 lines of chapter 9 plus fifteen appendix-C rows, not a research task.

---

## Scope: the 60 IDs

### `RETRY` — 45 IDs, 42 implemented, 3 ⏳

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `RETRY-1`–`RETRY-28`, `RETRY-30`–`RETRY-37`, `RETRY-39`–`RETRY-42`, `RETRY-44`, `RETRY-45` | 42 |
| ⏳ deferred, `DEF-6` (pre-existing, no named trigger) | `RETRY-29` (MAY, server-driven override), `RETRY-38` (SHOULD, attempt-ordinal header), `RETRY-43` (MAY, fixed-delay mode) | 3 |

### `RECOV` — `DEF-35`'s fifteen, all implemented as their own rows

| ID | Level | `RETRY` twin(s), carried as an annotation only |
|---|---|---|
| `RECOV-17` | MUST | `RETRY-37`, `RETRY-1`, `XCUT-6`/`XCUT-7` |
| `RECOV-18` | MUST | `RETRY-5`, `RETRY-6`, `RETRY-7`, `RETRY-8` |
| `RECOV-19` | MUST | `RETRY-36` |
| `RECOV-20` | MUST | `RETRY-27`, `RETRY-14` (**contrast, not twin**: `RETRY-28` forbids the same budget on the other stack) |
| `RECOV-21` | MUST | `RETRY-9`, `RETRY-10`, `RETRY-11` |
| `RECOV-22` | MUST | `RETRY-20`, `RETRY-21` |
| `RECOV-23` | MUST | `RETRY-16`, `RETRY-17` |
| `RECOV-24` | MUST | `RETRY-15`, `RETRY-19`, `RETRY-21` |
| `RECOV-25` | SHOULD | a **clause inside** `RETRY-15` (the `X-RateLimit-Reset` jitter), not an ID |
| `RECOV-26` | MUST | `RETRY-11`, `RETRY-18` |
| `RECOV-27` | MUST | `RETRY-23`, `RETRY-26`, `XCUT-3` |
| `RECOV-28` | MUST | `RETRY-42` |
| `RECOV-29` | MUST | `RETRY-22` |
| `RECOV-30` | SHOULD | `RETRY-13`, `RETRY-14`, `RETRY-28` |
| `RECOV-34` | MUST | design §6.1's construction-time validation, §10 item 18's substituted ~292-year bound |

**Total in budget: 60.** `⏳` rows for `RETRY-29`/`RETRY-38`/`RETRY-43` and a `⏳`-row-only,
no-budget-line entry for `RECOV-31` beside `RETRY-38`'s, per the charter's exact instruction. This
document copies `DEF-35`'s table verbatim rather than re-deriving it; the twin annotations above are
`DEF-35`'s own words.

**Two clauses inside `RETRY` a plan will otherwise leave implicit**, restated because the charter
names them and this design must not silently drop them again:

- **`RETRY-35`'s three orderings**: release the response before the wait (so the delay is computed
  from the still-open response *first*, then the response closes, then the wait runs); and if the
  retry decision or delay computation throws, the response is still closed before propagating.
  `PIPE-40`'s "close every superseded intermediate before the next drive" is the same rule stated
  from the pipeline side for the stage stack's own attempt-to-attempt handoff.
- **`RETRY-37`'s authoritative-contains semantics**: the configured retryable-status set is
  consulted *alone*; it is never AND-ed with `XCUT-5`'s baked flag. `Policy.status_retryable?`
  below takes no baked-flag argument at all, which makes the AND-ing this clause forbids a method
  that does not exist rather than a bug that could be introduced.

**Also shipped by `6a`, without owning a new ID** (per the charter):

- `Dexpace::ProtocolError#retryable?`, computed once at construction from `Dexpace::Retryability`
  (`DEF-38`, `XCUT-5`).
- `CFG-35`'s throwable half, as `XCUT-6`'s capability query over `Dexpace.each_cause` (`DEF-40`).
- `RETRY-12`'s five default tuning-constant values, behind 5a's `Keys::MAX_RETRY_ATTEMPTS` name.
- `OBS-29`'s per-attempt event group on the retry step (`DEF-42`, half of it).
- `OI-31`'s cursor widening (a read-only per-call bundle reader plus one optional seeding keyword on
  the pipeline call path).

**Inherited row, no budget line:** `CFG-35` (SHOULD) — 5a's row, closed here (`DEF-40`).

### Canonical text quoted because a decision below turns on it

> **RETRY-1** (MUST) — The retryable-status classifier MUST be single-sourced and treat exactly 408,
> 429, and all of 500–599 EXCEPT 501 and 505 as retryable. This classifier is the single definition
> the response-carrying exception flag and the stage stack's default predicate derive from; the
> recovery stack layers its own configurable status allow-list on top (**RETRY-37**).

> **RETRY-2** (MUST) — The retryable-throwable set MUST be defined in exactly one place: any
> throwable that is, or has anywhere in its cause chain, an I/O error or a timeout error, with an
> iterative, identity-tracking cause-chain walk that terminates on a cyclic chain.

> **RETRY-13** / **RETRY-14** (MUST) — Both stacks MUST compute backoff via the one shared
> calculator and constants, and their attempt budgets MUST denote the same number of total wire
> sends under equivalent defaults (the recovery stack's max-attempts, default 3, equals the stage
> stack's max-retries, default 2, plus one initial send).

> **RETRY-27** (MUST) — The recovery stack MUST enforce an optional total-timeout budget with
> per-attempt deadline shrinking … with a zero budget disabling the deadline. **RETRY-28** (MUST) —
> the stage-based stack MUST NOT impose a total-timeout budget; a port that unifies the stacks MUST
> make the total-timeout an explicitly opt-in feature rather than always-on.

> **RETRY-39** (MUST) — The stage stack's delay resolution MUST follow the precedence caller
> delay-override → server pacing headers (response path only) → fixed delay → exponential backoff,
> the exception path skipping the header step. **RETRY-40** (SHOULD) — a throwing user
> delay-override SHOULD be non-fatal (log and fall back), while a throwing should-retry predicate
> SHOULD abort the call as a well-typed error, with fatal errors rethrown unchanged in both.

> **RECOV-20** (MUST) — Retrying MUST be bounded by BOTH a maximum-attempts cap … AND a
> total-timeout budget … A total-timeout of zero MUST mean 'unbounded' (deadline disabled). … (The
> total-timeout deadline is the recovery layer's addition; the stage-based retry step intentionally
> omits it.)

> **RECOV-19** (MUST) — Because a transport returns an error-status response rather than throwing,
> each RE-SENT attempt's response MUST be re-classified: if its status is an error status present in
> the retryable-status set, it MUST be re-mapped into a Failure (with its body buffered per
> `RECOV-16`) so the loop keeps evaluating the budget and can reach an eventual success (e.g. a
> 503,503,200 sequence must terminate on the 200). All other re-sent responses — including a
> non-retryable error status — pass through as Success.

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `RECOV-1`–`RECOV-16`, `RECOV-32`, `RECOV-33` — the recovery **chain** the retry engine installs into | 4b, built |
| `RECOV-31`, `RETRY-38` — the per-attempt ordinal header | Post-MVP (`DEF-5`), no named trigger (`DEF-6`). ⏳ rows, no budget line |
| `PIPE-2`–`PIPE-40` — the stage runtime, `Cursor`, the fork primitive, `Builder#install_preset` | 4c, built |
| `PIPE-39`'s `standard` constructors | **6, phase-level** (`DEF-39`). `6a` builds the ingredient it needs; does not own the constructors |
| `CFG-15`–`CFG-21` — the clock, the cancellable wait, `Async.delay` | 5a, built. `6a` calls both and builds neither |
| `CFG-29`–`CFG-31` — RFC 1123 date parsing | 5a, built as `Dexpace::HTTPDate`. `6a` widens the day tolerance (`R1`), owns no second parser |
| `CFG-35`'s status half, `XCUT-5` | 5a, built as `Dexpace::Retryability.retryable_status?`. `6a` computes `DEF-38`'s flag from it |
| `CFG-12`, `CFG-14` — the well-known configuration key names | 5a, built. `Keys::MAX_RETRY_ATTEMPTS` is the name; `RETRY-12`'s values are `6a`'s |
| `OBS-1`–`OBS-40` — the event object, logger facade, redactor, `HTTPTracer` vocabulary | 5b/5c, built. `6a` supplies the per-attempt emitter (`DEF-42`, half) |
| `XCUT-5`, `XCUT-6`, `XCUT-7` | 9 dispositions. `6a` builds the three objects the audit is about |
| `HTTP-9` — the idempotent-method set | 1, built as `Method::IDEMPOTENT`/`#idempotent?`. `6a` consumes it, builds no second set |
| `BODY-1`–`BODY-5` — `#replayable?` and the three documented declines | 3b, built. `6a` writes `Resilience::Resend.eligible?(request)` over it |
| `ASYNC-3`, `ASYNC-4`, `PIPE-33`'s interrupt clause | 8. `6a` meets the same §8.3 prohibition and adds no fourth unsatisfied MUST |
| `SEAM-11`, `SEAM-16`, `SEAM-17` | 2 and 8. `6a`'s async driver consumes `Dexpace::Async::Future#on_settle`, replaces nothing |

---

## Prerequisites, and the independence this sub-phase must state

**`6a` depends on `6b` and `6c` for nothing, and neither depends on `6a`.** The charter's finding —
every phase-6 boundary is a convenience — is stated here in `6a`'s own words rather than inherited:
`Stages::RETRY` sits between `Stages::REDIRECT` (200) and `Stages::AUTH` (800), and 4c's
stage-namespaced cursor state means a RETRY fork's `state:` is invisible under any other stage's key
to anyone, including `REDIRECT` and `AUTH` — the same negative assertion (assertion 4 in 4c's suite)
that makes `6b`/`6c`'s marker exchange safe from `6a`'s interference. `6a`'s one export a later
sub-phase might consume, `OI-31`'s cursor widening, is stated as an *if-it-exists* consumption in
`6b`'s and `6c`'s own designs, never a wait. **A `6a` plan whose first task waits on anything from
`6b` or `6c` has re-imposed a chain that does not exist**, and none does here.

### From phase 0 — seventeen blocking gates, unchanged

`gates:require_allowlist` — `6a` requires nothing new: `set` (for `Policy::DEFAULT_RETRYABLE_STATUSES`)
and `monitor` (if a `Thread::Mutex`-guarded structure needs one; the retry objects here need none) are
already allowlisted, and `6a` writes no `require` outside `time`/`uri`/`securerandom`/`digest` already
in use elsewhere in core. `Dexpace/NoThreadInterrupt` bars `Timeout.timeout`/`Thread#raise`/
`Thread#kill`; every wait in `6a` routes through `Dexpace::Clock#sleep(duration, cancellation:)`
(sync) or `Dexpace::Async.delay` (async). `Dexpace/NoTimeParse` and `Dexpace/NoUriDefaultParser` bind
nothing new here — `6a` parses no URL and calls `Dexpace::HTTPDate.parse`, never `Time.parse`.
`Dexpace/NoLocaleCaseFold` binds the pacing-header name lookup (case-insensitive header matching is
already `Headers#[]`'s job, not `6a`'s to re-implement) and the decimal-grammar screen.

### From phase 1

`Dexpace::Method::IDEMPOTENT`/`#idempotent?` (`HTTP-9`'s single source — `Resilience::Resend` reads
it and defines no second set); `Dexpace::Request` (`body` optional, `nil` when absent);
`Dexpace::Response` (`Data.define(:request, :protocol, :status, :reason, :headers, :body)` — the
response carries the request that produced it, which `6a`'s object model notes but does not rely on,
per the architecture decision below); `Dexpace::Headers#[](name)` (case-folded lookup, frozen
`Array[String]` or `nil` — the pacing parser's read path); `Dexpace::Status#error?` (400–599);
`Dexpace::RequestOptions` (`:timeout, :max_retries, :tags` — `#max_retries` is `RETRY-41`'s
present-override); `Dexpace::InvalidArgumentError`; `Dexpace::Model.required!`, `.own`.

### From phase 2

`Dexpace::Cancellation` (`.none`, `.source`, `.any`, `#cancelled?`, `#reason`, `#check!`, `#on_cancel`
returning a `Cancellation::Subscription` with `#detach`) and `Cancellation::Source#off_cancel`;
`Dexpace::Async::Future`/`::Completer`/`::Settlement` — **not** `Dexpace::Future`/`Dexpace::Completer`
— with `Future#on_settle`, `#value(cancellation:)`, `#wait`, `#cancel`, `Completer#fulfil`/`#fail`/
`#on_cancel`/`#await`/`#request_cancel`; `Dexpace::Closeable`, `Dexpace.close_quietly(resource,
onto: nil)`, `Dexpace::ClosedError`. **`Dexpace::Hooks` is a `private_constant` with no `sig/` mirror
and no manifest row — `6a` cannot cite it as an interface surface.**

### From phase 3

`Dexpace::Body#replayable?` (default `false`) and `#to_replayable`; `Dexpace::StreamError < ::IOError`;
`Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` (1 MiB, **3b's constant**); `Response#close`. `3b`'s
own forward table names `Dexpace::Resilience::Resend.eligible?(request)` as `6a`'s to confirm or
change — confirmed in `R5` below, unchanged.

### From phase 4a

`Dexpace::Instrumentation::Bundle` (`Bundle::NONE`, `#tracer_factory` — `OI-29`'s point: this factory
produces **span** tracers, never the HTTP-tracer `6a` needs, and `6a` does not read it).

### From phase 4b

`Dexpace::Outcome` (`Success`/`Failure`, `.build`, `#success?`, `#failure?`, `#response_or_nil`,
`#error_or_nil`, `#fold`); `Recovery::RequestChain`/`::ResponseChain` (`.build`, `#apply`);
`Recovery::Orchestrator.build(transport:, request_chain:, response_chain:)` with
`#call(request, options, cancellation)` — **itself a `Dexpace::Transport` by phase 2's duck type**;
`Recovery::Transform` (`#phase`, `#apply(value)`, and the module's default `#call(value)` — **one**
argument, never the pipeline's `#call(request, cursor)`); `Recovery.buffer_error_body(response)`;
`Dexpace::ProtocolError` (`.for`, `.for_or_nil`, `#response`, `#status`, **no `#retryable?`**,
`DEF-38`); `Dexpace::Suppressible`, `Dexpace.attach_suppressed`, `Dexpace.suppressed`;
`Dexpace.each_cause` (cycle-safe by reference identity, `XCUT-9`); the `RECOV-2` fatal-family
passthrough (`rescue ::StandardError` converts, `rescue ::Exception` re-raises unchanged, already
`RETRY-25`); `Ownership.close_on_throw` (`private_constant`, the asymmetric close-on-raise helper
`ErrorMappingStep`'s response-step position uses — `6a`'s recovery step is a different position on
the chain and is argued not to need it, in the object model below).

### From phase 4c

`Dexpace::Pipeline` (`.builder`, `.direct`, `#call`, `#steps`, `#entries`, `#transport`, `#close`);
`Dexpace::AsyncPipeline` (`.direct`, `.map_response`, `#call` returning a `Future`);
`Pipeline::Builder` (`#install_preset`, `#reload`, the ten surgical edits); `Pipeline::Cursor`
(`.build`, `#call(request)`, `#fork(state:)`, `#may_fork?`, `#request`, `#options`, `#cancellation`,
`#state(stage)`, `#spent?`); `Pipeline::Stages` (`RETRY` at order 500, `REDIRECT` at 200, `AUTH` at
800, `PRE_RETRY`/`POST_RETRY` slots at 400/600); `Pipeline::TransformStep` (declares no `#stage`);
`Dexpace::PipelineError`. **The rule this sub-phase is built on**: `Cursor#call` and `Cursor#fork` are
disjoint on one cursor; a driving pillar step forks for every drive including the first and never
calls its own `#call` (P4-39, `pipeline/86343352`); `#call`'s reuse guard is **sequential-only**
(P4-33) and must not be treated as a concurrency guard.

### From phase 5a

`Dexpace::Clock#sleep(duration, cancellation: nil)` and `Clock::SYSTEM`, `Clock.deadline_in`;
`Dexpace::Async.delay(duration) -> Async::Future`, which **completes a zero-length delay before
checking for a scheduler** and **raises `Dexpace::SeamError` for any positive delay with no
registered `Fiber.scheduler`** (verified against the shipped code, Task 7); `Dexpace::HTTPDate.format`/
`.parse` — the exact `GRAMMAR` regexp, `R1` below; `Dexpace::Retryability.retryable_status?`;
`Dexpace::Configuration`, `Configuration::Keys::MAX_RETRY_ATTEMPTS` (the **name** only — 5a shipped no
value); `Dexpace.configuration`.

### From phase 5b and 5c

`Dexpace::Instrumentation::Step`/`::AsyncStep` at `Stages::LOGGING`, whose `bundle_for` gains its
first clause under `OI-31` (below); `Dexpace::Instrumentation::Redactor` (`6a` does not call it —
`REDIR-28`'s linkage is `6b`'s); `Dexpace::Instrumentation::HTTPTracer` (eleven no-op methods:
`#operation_started(context)`, `#operation_succeeded(context, response)`,
`#operation_failed(context, error)`; `#attempt_started(context, attempt)`,
`#attempt_failed(context, error, next_delay)`, `#retries_exhausted(context, error)`; five transport
milestones `6a` does not call), its frozen `NULL` instance, `CallableAdapter`. **`interface
_HTTPTracer` is deliberately not declared in 5c's RBS** — `R3` decides whether `6a` declares one now.

**The independence statement, restated as the charter requires**: every real dependency above is on
phases 0–5; the dependency on `6b` and `6c` is empty. `OI-31`'s widening is the one export either of
them might consume, and neither's design may wait on it existing.

---

## `R1` — `Dexpace::HTTPDate.parse` against `RETRY-15`'s tolerances

**Decision: widen 5a's grammar. The weekday tolerance is already there; the day-of-month tolerance
is not, and `6a` adds it in place rather than writing a second parser.**

`RETRY-15` requires the pacing-header HTTP-date form to be parsed "tolerant of an informational
weekday and single-digit day." 5a's `Dexpace::HTTPDate::GRAMMAR` (`gems/dexpace-core/lib/dexpace/http_date.rb`,
written by `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md` Task 5) is:

```
GRAMMAR = ::Regexp.new(
  '\A[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) (GMT|UTC|\+0000|\+00:00)\z',
  ::Regexp::IGNORECASE,
  timeout: 1.0,
).freeze
```

The weekday group `[A-Za-z]{3}` is captured and discarded, never compared against the computed
weekday — 5a's own `CFG-31` test proves the tolerance by asserting `"Mon, 06 Nov 1994 08:49:37 GMT"`
(a Sunday, mislabelled) parses. **That half of `RETRY-15` needs nothing.** The day group `(\d{2})`
requires exactly two digits, and 5a's own `CFG-31` test proves the *rejection*: `assert_raises
(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse("Sun, 6 Nov 1994 08:49:37 GMT") }`. That
assertion is the one line `RETRY-15` requires to change.

Design §6.1 forbids a second parser ("the port therefore ships **one** bounded-lenient RFC 1123
parser (shared with `CFG-29`–`CFG-31`)"), so `6a` widens `GRAMMAR`'s day group from `(\d{2})` to
`(\d{1,2})` and nothing else. Two things this costs, stated rather than discovered later:

1. **The task that widens the grammar edits a file 5a shipped, and it edits 5a's own test alongside
   it.** The `CFG-31` test's single-digit-day assertion flips from `assert_raises` to `assert_equal`
   (the same expected `Time` a two-digit `"06"` parse produces). `CFG-31`'s own text — "malformed
   header missing the comma after the weekday MUST fail" — says nothing about digit count, so
   widening the day group narrows nothing `CFG-31` requires; the widening is `NFR-4`-safe because it
   makes the parser accept **more**, never less, of what it already accepted.
2. **`Time.utc(year, month, day, …)` already accepts a single-digit day as an `Integer`** — the
   widening changes only what the *regexp* admits, not the `Time.utc` construction that follows the
   match, so no downstream code in `http_date.rb` needs to change.

`RETRY-15`'s remaining clauses — `retry-after-ms`/`x-ms-retry-after-ms` as integer milliseconds,
`X-RateLimit-Reset` as epoch seconds — are new parsing surface `6a` writes itself in
`Dexpace::Resilience::Policy` (below); `HTTPDate.parse` supplies only the HTTP-date branch of the
pacing parser's total dispatch.

## `R2` — the async trampoline with no `Fiber.scheduler`

**Decision: route 3 — let `Dexpace::SeamError` surface at the first *positive* backoff, and rely on
`Dexpace::Async.delay`'s own zero-length fast path for the case `RETRY-31` names by name.**

`RETRY-31` requires async backoff delays to be "scheduled non-blockingly, a zero-length delay
completing inline and re-arming the active pump." Verified against 5a's shipped `Async.delay`
(`gems/dexpace-core/lib/dexpace/async/delay.rb`, Task 7):

```ruby
def delay(duration)
  dur = duration.to_f
  raise Dexpace::InvalidArgumentError, "delay duration must be non-negative" if dur.negative?

  completer = Completer.new
  if dur.zero?
    completer.fulfil(ELAPSED)
    return completer.future
  end

  if ::Fiber.scheduler.nil?
    raise Dexpace::SeamError, "Async.delay requires a registered Fiber.scheduler …"
  end
  # … Fiber.schedule + Thread::Queue …
end
```

**The zero-duration branch returns before the scheduler check runs at all.** So `RETRY-31`'s named
case — a zero-length delay — never raises, with or without a scheduler, exactly as the requirement's
own words describe: "completing inline and re-arming the active pump" is what happens when the async
retry driver's `on_settle` callback on the zero-duration future fires synchronously-enough to loop
straight back into the next attempt with no suspension at all. **Only a positive computed delay with
no registered scheduler reaches the raise.**

The charter names three routes and the shipped code settles which is implementable:

1. *"Fail loudly at async-retry-step construction."* **Rejected as incoherent for this object.**
   `RETRY-42` requires every retry policy component to be "immutable and stateless after
   construction and safe for concurrent invocation." `Dexpace::Resilience::AsyncRetryStep` is
   constructed once and shared across every call a pipeline serves; whether a scheduler is
   registered is a property of the *fiber that is running when a given call happens to need a
   backoff wait*, which can differ from one call to the next and is unknowable at the step's own
   construction time. There is no fact to check at construction.
2. *"Accept a caller-supplied scheduler … remembering `RETRY-45` forbids the engine from ever
   shutting it down."* **Rejected as out of `6a`'s scope, not on the merits.** `Dexpace::Async.delay`
   has no `scheduler:` parameter — it reads the ambient `Fiber.scheduler` — so "accepting" one would
   mean the retry step calling `Fiber.set_scheduler` itself, which is a reactor-lifecycle decision
   `PIPE-39`'s async preset names as its own concern ("retry+instrumentation with a caller-supplied
   scheduler for non-blocking backoff"), and `PIPE-39`'s constructors are `DEF-39`'s phase-level task,
   owned by neither `6a` nor `6c` — see *Relationship to phase-level tasks* below. `6a`'s async retry
   step takes no `scheduler:` keyword of its own and installs no `Fiber.scheduler`; `RETRY-45`'s
   "never shuts down a caller-supplied scheduler" is then satisfied by there being nothing for `6a`'s
   own code to shut down.
3. *"Let the `SeamError` surface at the first backoff."* **Adopted.** The async retry step calls
   `Dexpace::Async.delay(delay)` for every computed delay including the first, and:
   - a delay of exactly `0.0` never touches the scheduler check, per the code quoted above;
   - a positive delay under a caller-supplied scheduler (however it was registered — `PIPE-39`'s
     preset, an `Async { }` block, or hand-written) unmounts the fiber exactly as §8.3 requires;
   - a positive delay with **no** scheduler fails the async retry `Future` through
     `completer.fail(seam_error)` — the async trampoline's own terminal-path rule (`RETRY-33`:
     "every terminal path of the async loop MUST complete the returned future … a throwing … delay
     computation … completing it exceptionally") already requires this exact behaviour for *any*
     throwing delay computation, so `Async.delay`'s `SeamError` needs no special case in the driver
     at all — it is caught by the same `rescue` the driver already writes for `RETRY-33`.

**What a zero-length delay does, stated because `RETRY-31` asks by name**: it completes inline (no
suspension reaches the caller) and the driver's `on_settle` callback re-arms the pump for the next
attempt from within that same callback, which is the "single active pump via a re-arm flag rather
than recursing" shape `RETRY-30` requires — see the object model's async driver below for the exact
loop.

## `R3` — where the retry step's `HTTPTracer` comes from

**Decision: a factory, called once per pipeline-level call. `interface _HTTPTracer` is declared now,
in a new `sig/` file widening 5c's instrumentation namespace.**

`OI-29` establishes that `CTX-14`'s `Bundle#tracer_factory` (span tracers, legitimately shared or
cached) and `OBS-29`'s per-operation HTTP-tracer factory (`OBS-28`'s eleven-method vocabulary,
legitimately per-operation) are different kinds of object, and assigns the separate slot to phase 6.
Two constraints fix the shape:

- `RETRY-42` requires the retry step itself to be shared and stateless across calls, so it cannot
  hold a per-operation `HTTPTracer` as a plain constructor-time instance — that would give every call
  the pipeline ever serves the same tracer, violating `OBS-29`'s "one tracer instance corresponds 1:1
  to a single logical operation lifecycle."
- The retry step has no reachable per-operation context object to read one off — `OI-31`'s own
  finding, restated for this ID: nothing shipped lets a pipeline step reach a `RequestContext` or an
  `Instrumentation::Bundle`, and `6a`'s widening of `Cursor` (below) adds a *bundle* reader, which
  `OI-29` says is the wrong object for this purpose anyway.

**The resolution needs no second cursor widening.** `Dexpace::Resilience::RetryStep#call(request,
cursor)` (sync) and `AsyncRetryStep#call(request, cursor)` (async) already receive `cursor` as an
argument — the pipeline hands every step its cursor on every invocation — and a driving pillar step
is visited exactly once per top-level `Pipeline#call`/`AsyncPipeline#call` (fork-for-every-drive
notwithstanding: the *step's own* `#call(request, cursor)` method runs once per operation; it is the
step's internal loop, not repeated visits from the pipeline, that drives the downstream chain more
than once). So the retry step's constructor takes `http_tracer_factory:`, a callable
`#call(cursor) -> HTTPTracer`-shaped object, defaulting to a lambda returning
`Dexpace::Instrumentation::HTTPTracer::NULL`, called **exactly once**, at the top of `#call`, before
the attempt loop begins. The resulting tracer is used for every `#attempt_started`/`#attempt_failed`/
`#retries_exhausted` call for that one operation, and `cursor` itself is the `context` argument
`HTTPTracer`'s eleven methods take — the same per-call correlation handle the pipeline design already
established, reused rather than duplicated.

This also settles why `6a`'s `DEF-42` emission task does not depend on `OI-31`'s widening, which the
charter states as a finding and this document confirms by construction: the factory's argument is
`cursor`, never a `Bundle`, so nothing about `OI-31` landing or not landing changes what the retry
step passes to `http_tracer_factory.call`.

**`interface _HTTPTracer` is declared now**, because a constructor keyword typed `untyped` for
something with eleven fixed methods is worse than the eleven-`NFR-4`-locked-signatures cost 5c
declined to pay when nothing called it — here, something does. It lands in a *new* file,
`sig/dexpace/instrumentation/http_tracer.rbs`, widening 5c's shipped `sig/` tree rather than editing
it (`api-design/1d9e6e0b`: adding a signature nothing narrows is a widening); 5c's own
`Dexpace::Instrumentation::HTTPTracer` module gains no method and no file changes on the `lib/` side.
`Dexpace::Resilience::RetryStep#http_tracer_factory` is then typed
`^(Dexpace::Pipeline::Cursor) -> _HTTPTracer` instead of `untyped`.

## `R4` — `RETRY-2`'s throwable set as a capability-only query, and its blind spot

**Decision: the capability query, per design §6.1 and `XCUT-6`; the blind spot is real, named as a
deviation candidate, and closes as an obligation on phase 8's adapters rather than as a phase-6 gap.**

`RETRY-2` fixes the mechanism completely: "the retryable-throwable set MUST be defined in exactly one
place: any throwable that is, or has anywhere in its cause chain, an I/O error or a timeout error,
with an iterative, identity-tracking cause-chain walk that terminates on a cyclic chain." `XCUT-6`
fixes the Ruby shape: "the classifier queries the capability (is-Retryable and the flag), not a
concrete-type match." `DEF-40` already establishes, from the phase-5 end, that the concrete-type
alternative (`is_a?(::IOError)`) is wrong in both directions — it would mark phase 3a's
`Dexpace::StreamError` retryable (it is an `IOError` and is not a transport timeout) and a real
connection timeout not retryable (`Errno::ETIMEDOUT`, `SocketError` and `Timeout::Error` are none of
them `IOError`). `6a` therefore ships:

```ruby
def self.throwable_retryable?(error)
  Dexpace.each_cause(error).any? { |e| e.respond_to?(:retryable?) && e.retryable? }
end
```

walked over `Dexpace.each_cause` — phase 4b's, already cycle-safe by reference identity (`XCUT-9`),
so `RETRY-2`'s cycle-safety clause needs no second implementation.

**The residual, named rather than hidden.** An `Errno::ETIMEDOUT` or `SocketError` that escapes an
adapter *unwrapped* — not answering `#retryable?` at all — classifies as **not retryable** under this
query, because `respond_to?(:retryable?)` is `false` on the bare stdlib class. This is the mirror
image of `DEF-40`'s own residual for `CFG-35`'s throwable half, restated here because `RETRY-2` is
the ID that actually ships the query. It is a **deviation candidate**, `P6-4` below: the requirement
reads as though every I/O-or-timeout error should be classified correctly, and this port classifies
correctly only the ones that were wrapped to say so.

**The obligation this puts on phase 8's adapters, stated plainly**: every transport adapter MUST wrap
a bare stdlib I/O or timeout error it lets escape in something answering `#retryable?` — which is
exactly `Dexpace::TransportError`'s job, per `XCUT-4` branch (b) and `DEF-40`'s own text ("this is
exactly the mechanism that lets `dexpace-transport-net_http` declare `Errno::ETIMEDOUT` retryable
without core naming it"). `RETRY-4`'s own text is the other half of why this is not a live gap today:
"a transport-level failure that produced no complete response … MUST be classified retryable
unconditionally at the condition level," and design §6.1 gives `XCUT-4`'s transport-error branch the
flag **by default** — so `Dexpace::TransportError.new(...).retryable?` is `true` unless an adapter
deliberately overrides it, which means the obligation phase 8 inherits is "wrap, and default to
retryable," not "wrap, and get the classification right by hand" — a much smaller thing to get wrong.

**Whether a `docs/first-release.md` line is owed: yes, one, filed below (unnumbered).** The residual
is invisible until an adapter ships (phase 8), at which point it becomes a real, testable property
of that adapter rather than of `6a`'s classifier — which is exactly the shape a release-readiness
register exists to track rather than a phase-6 checklist row (`6a` ships no adapter and therefore has
no code to test this against).

## `R5` — `Dexpace::Resilience::Policy`'s visibility, and `Resend.eligible?`

**Decision: `Dexpace::Resilience::Policy` and `Dexpace::Resilience::Resend` are both public, flat
under the `Dexpace::Resilience` namespace design §6.1 already names; `Resend.eligible?(request)` is
confirmed unchanged from 3b's forward naming.**

`NFR-4` locks whatever ships public; `api-design/b0e18938`'s minimal-surface rule argues for keeping
what is public small; `execution-context/b58728da`'s `private_constant` finding argues that a
`private_constant` is reachable only from a full-nesting `module` body and is invisible to
`rbs validate` and the runtime surface snapshot alike. None of the three argues for making `Policy`
itself private, and one argues against it directly: `Policy`'s pure functions (`backoff_delay`,
`pacing_delay`, `status_retryable?`, `throwable_retryable?`) are exactly the surface `RETRY-13`
requires "cannot drift" — a caller assembling a custom retry driver (a generated SDK's own retry
step, per design §6.1's stated audience) needs to call the **same** calculator, not a
`private_constant` it cannot reach even from `module Dexpace::Resilience`'s own full-nesting form.
`XCUT-6`'s capability query is likewise the extension point a third-party transport adapter is meant
to use by defining `#retryable?` on its own error class, which only works if the classifier consulting
it is public and stable. **`Policy` is public.**

**5a's `Dexpace::Retryability` and `Policy` coexist without collision, because they answer different
questions for different callers.** `Retryability.retryable_status?(status)` is `XCUT-5`'s SINGLE
shared status classifier — the fixed built-in set — and its only caller in `6a` is
`ProtocolError#retryable?`'s construction-time computation (`DEF-38`). `Policy.status_retryable?
(status, retryable_statuses:)` is the retry step's own eligibility gate over `XCUT-7`'s
**configurable** set, and it never reads `Retryability.retryable_status?` at all — `XCUT-5`'s own
closing NOTE is what keeps the two apart: "this baked flag is a queryable property of the error; the
retry step's actual eligibility gate for a protocol error is the configured retryable-status set."
Reversing that — computing `Policy.status_retryable?` from `Retryability.retryable_status?`, or
ANDing them — is exactly what `RETRY-37`'s authoritative-contains clause forbids, and `Policy`'s own
method signature (no baked-flag parameter) makes that reversal a method that does not exist rather
than a bug someone could introduce later.

**`Dexpace::Resilience::Resend.eligible?(request)` is confirmed, unchanged, exactly as 3b named it.**

```ruby
def self.eligible?(request)
  request.body.nil? ? request.method.idempotent? : request.body.replayable?
end
```

`RETRY-5`/`RETRY-6`/`RECOV-18` in one line: a body-less request is re-sendable iff its method is
idempotent (`Method::IDEMPOTENT`, `HTTP-9`'s single source, never re-listed here); a body-bearing
request is re-sendable iff its body says so. Both stacks call this same function; `6a` writes no
second re-sendability gate and confirms 3b's own table entry needed no change — the predicate 3b
anticipated is exactly the predicate `6a` needed.

## `R6` — one calculator, two budget policies

**Decision: a wrapper the recovery driver alone applies. The shared calculator takes no
total-timeout parameter at all, so the stage driver has no keyword through which it could
accidentally engage a budget `RETRY-28` forbids it.**

`RETRY-28` forbids a total-timeout on the stage stack; `RECOV-20`/`RETRY-27` require one on the
recovery stack, with `RECOV-20` adding "a total-timeout of zero MUST mean unbounded." Design §6.1's
sanctioned reading is "the recovery-aware stack MAY additionally enforce a total-timeout deadline
that the stage-based step omits" — the word *additionally* is the argument for a wrapper rather than
a shared parameter with a disabling default: a parameter that exists on the calculator, however
defaulted, is a parameter the stage driver's code *could* pass, and `RETRY-28`'s prohibition is
strongest when there is no such argument to pass at all — the same "structurally impossible rather
than defended against" shape design §10 item 15 already uses for the cross-origin marker.

`Dexpace::Resilience::Policy.backoff_delay(attempt, initial_delay:, multiplier:, max_delay:, jitter:,
random:)` computes `RETRY-9`/`RETRY-10`/`RETRY-11`/`RECOV-21` with no budget in scope at all, and
**both** drivers call it identically. A second function,
`Policy.budget_remaining(elapsed:, total_timeout:)`, exists **only** for the recovery driver to call:
it returns `Float::INFINITY` when `total_timeout` is `0` (`RECOV-20`'s "zero MUST mean unbounded"),
else `total_timeout - elapsed`, and the recovery driver clamps its own next attempt against it
(`RECOV-20`'s three abort conditions — attempt cap reached, elapsed ≥ budget, elapsed + next delay
would exceed budget — computed once per attempt from this one number). `Dexpace::Resilience::RetryStep`
(the stage driver) never requires this file's constant and never calls `budget_remaining`; nothing in
its own source names `total_timeout`, which is what makes `RETRY-28` a property of the file rather
than of a runtime check.

`Dexpace::Resilience::RetrySettings` (below) carries a `total_timeout` member (default `0`,
unbounded) so that a **single** settings type serves both stacks — `RECOV-30`'s "the SAME default
schedule … so the two stacks cannot drift apart" reaches every tunable this way, `total_timeout`
included, even though only one driver ever consults it. `RECOV-34`'s construction-time validation
(non-negative, representable within the ~292-year nanosecond ceiling design §10 item 18 already
substitutes) runs on this member unconditionally, whichever driver eventually reads it or does not.

## `R15` — `PRE_REDIRECT` for `OBS-29`'s operation-lifecycle triple

**Decision: record the finding; do not ship the step. `6a` corrects `DEF-42`'s row rather than
building a new pillar-adjacent slot to close it.**

The charter's own finding, verified again for this document rather than trusted: 5b's
`Dexpace::Instrumentation::Step` declares `#stage` returning `Stages::LOGGING` (order 1100) and is
installed with no `stage:` argument; 4c rejects with `Dexpace::PipelineError` any install supplying a
different `stage:` for a step that declares one. `Stages::LOGGING` sits *inside* `REDIRECT` (200),
`RETRY` (500) and `AUTH` (800), so once `6a`'s pillar is installed a step at `LOGGING` runs once per
retry attempt — an operation-scoped triple emitted from there would fire on every attempt, which
contradicts `OBS-29`'s "one tracer instance corresponds 1:1 to a single logical operation lifecycle."
`DEF-42`'s stated route (a third slot on 5b's step) is therefore unavailable in exactly the phase its
own pick-up condition targets.

**Why `6a` does not ship `Stages::PRE_REDIRECT` to fix it, weighed rather than assumed.** Three
considerations, each cited from the charter's own words:

1. **Nothing is broken today.** `OBS-28`'s "every event method SHOULD default to a no-op so adding a
   new event is a non-breaking change" is what makes leaving the triple unwired *safe*, not merely
   convenient — a later phase can wire it with no test anywhere needing to change, because every
   caller of `HTTPTracer#operation_started`/`#operation_succeeded`/`#operation_failed` that does not
   yet exist cannot regress.
2. **The site that would work belongs to no ID `6a` owns.** `PRE_REDIRECT` (order 100) is `PIPE-2`'s
   outermost slot and `PIPE-37`'s reserved home for a step whose correctness depends on observing
   only the single terminal response — but installing a step there, giving it a public constructor
   and a public name, is `NFR-4` surface with no requirement in `6a`'s 60-ID budget asking for it.
   `OBS-29` itself is 5c's ID (already ✅ there, vocabulary shipped) and phase 6 wires a *subset* of
   it per `DEF-42`'s own pick-up condition — the per-attempt group, which `6a`'s retry step already
   emits without any new pillar slot. Shipping a whole new step to wire the operation triple would be
   `6a` building surface for an obligation `DEF-42` assigns to "phase 6" generically, not to `6a`
   specifically, and doing so silently would be exactly the "build it once, and the wrong sub-phase
   owns the review" mistake the segmentation design's rejected-cut-B argument warns against for the
   policy core — the same shape of error, one level up.
3. **The neighbourhood is genuinely contended.** `PRE_REDIRECT` is `6b`'s stage (it sits immediately
   before `Stages::REDIRECT`, which `6b` owns), and a step installed there by `6a` would put a
   phase-6a-authored constant inside a stage-order neighbourhood the charter assigns to `6b`'s
   convenience, not `6a`'s. Nothing forbids it structurally (`PIPE-4` admits one step per pillar and
   `PRE_REDIRECT` is a slot, not a pillar, so multiple steps could occupy it in principle) but nothing
   in `6a`'s scope asks for it either, and building it here would pre-empt a decision `6b`'s own
   design has equal standing to make if it ever needed that slot for something of its own.

**What `6a` does instead: correct the row.** `DEF-42`'s finding — filed by the charter, restated
below under the findings section for a human to apply to `docs/deferred-items.md` — is that the
stated route does not work and the site that would is a new step nobody's scope currently asks for.
`6a`'s own checklist marks `OBS-29` **not** as its ID (it owns none of `OBS-29`; `5c` does) but names
the per-attempt group it *does* wire as satisfying `DEF-42`'s per-attempt half, and leaves the
operation-lifecycle triple explicitly unwired with the reason stated in the row rather than silently
absent.

---

## `OI-31`: widening the cursor

**Decision: widen `Dexpace::Pipeline::Cursor`. Executed by `6a`, as the charter assigns.**

The full argument for *why* is the charter's own — candidate (b) (thread a bundle through
`Pipeline.standard` at construction) is rejected because a bundle fixed at pipeline-construction time
is per-pipeline, not per-operation, and cannot carry a per-request span or trace id; candidate (a)
(widen `Cursor`) is right because `PIPE-11` names the cursor as the only legitimate home for per-call
mutable state and because both halves are additive widenings under `NFR-4`. `6a` states the two
concrete changes precisely, because "widen the cursor" is not yet a task until the exact surface is
named:

1. **A read-only `Cursor` accessor for the per-call instrumentation bundle**, carried across
   `#fork` exactly as `#request` and `#options` already are:

   ```ruby
   def bundle
     @bundle
   end
   ```

   `Cursor.build` gains one more keyword, `bundle: Dexpace::Instrumentation::Bundle::NONE`, stored
   alongside `@request`/`@options`/`@cancellation` and copied unchanged into every `#fork`'s child —
   the same treatment `#options` already gets, which is why `#fork`'s implementation needs no new
   branch, only one more field to copy.

2. **One optional keyword on the pipeline's own call path that seeds it.** `Pipeline#call(request,
   options = RequestOptions::EMPTY, cancellation = Cancellation.none, bundle: Dexpace::Instrumentation::Bundle::NONE)`
   and the same keyword on `AsyncPipeline#call`. `Cursor.build` is called with this `bundle:` at the
   top of `#call`, exactly as `options` and `cancellation` already are. **This is the producer side
   `OI-31`'s own text omits and this document supplies it explicitly**, because a reader accessor with
   nothing that ever populates it non-`NONE` would be `OI-8`'s "an implementation with no caller and
   no test that exercises the non-default branch" shape all over again.

**`bundle_for` in 5b's `Dexpace::Instrumentation::Step` gains its first clause in the same task.**
5b's step currently resolves `tracer_factory:`/`meter:` from its own constructor keywords and the
published `Bundle::NONE`/`_HTTPTracer`... wait — 5b's step resolves *span* tracer factories and
meters, and `OI-31`'s three-clause rule names "the request context's instrumentation bundle when it
is not `Bundle::NONE`, else the step's constructor keyword, else the constant" for exactly that
resolution. With `Cursor#bundle` shipped, `bundle_for(cursor)` becomes:

```ruby
def bundle_for(cursor)
  bundle = cursor.bundle
  return bundle unless bundle.equal?(Dexpace::Instrumentation::Bundle::NONE)
  @bundle # the step's own constructor-time fallback, unchanged
end
```

which is the one method `OI-31`'s own text says changes, and no other 5b file changes.

**Why this is safe against `4c`'s stated position** ("4c does not consume 4a at all"): `4c` itself is
untouched — `Cursor` gains a member and a keyword, and `4c`'s own design and tests named no
prohibition on `Cursor` ever growing one; the sentence 4c states is a fact about what 4c *built*, not
a promise about what phase 6 may add. Phase 6 adds no `Bundle` member, renames nothing, and replaces
no published singleton — roadmap obligation 1's actual content, honoured either way.

**Owner: `6a`, as a self-contained task with no dependency on the rest of `6a`'s scope.** `6b`'s
`REDIR-28` emitter and `6c` consume `Cursor#bundle` **if it exists** and ship their own constructor
keyword regardless of whether it does, per the charter's `R13`. **`6a`'s own `DEF-42` emission task
does not depend on this widening** — `R3` above resolves the retry step's `HTTPTracer` slot through
`cursor` itself (the argument every step already receives), never through `Cursor#bundle`, because
`OI-29` establishes the two are different kinds of object. If `6b` or `6c` lands first, this task
travels with whichever does, and this document's own Prerequisites section already states that `6a`
does not wait for either.

---

## `DEF-40`: picked up and closed here

**Decision: agreed with the prior reading (5a's `R1`, and `DEF-40`'s own text). `DEF-40` closes when
`6a`'s row lands.**

`RETRY-2` is `CFG-35`'s throwable clause restated at MUST level, and `6a` cannot satisfy `RETRY-2`
without writing the exact method `DEF-40` defers — so the row is discharged by `R4`'s
`Policy.throwable_retryable?` whether or not this section says so, and this section says so anyway
because `CLAUDE.md` requires the checklist to name the task, not merely to happen to satisfy it. The
mechanism is `XCUT-6`'s capability query walked over `Dexpace.each_cause`, exactly as `DEF-40`
specifies; `6a` writes no second walk. The one residual `DEF-40` records — a bare, unwrapped
`Errno::ETIMEDOUT`/`SocketError` classifying not-retryable — is `R4`'s deviation candidate `P6-4`,
and it is the same residual under one name, not two. Phase 5a's `CFG-35` row stays ⏳ citing this
document with its met half named; `6a` carries the `CFG-35` row that closes it, outside its 60-ID
budget (an inherited row, per the Scope section above). `OI-21` closes with it, per 5a's own `R1`
supplying the phase-5 end of the cross-reference and `6a` supplying the phase-6 end.

---

## Module layout

Every file `6a` creates or modifies, under `gems/dexpace-core/`. `sig/` mirrors `lib/` one file per
file; `test/` mirrors `lib/` one file per file and does not ship. `private_constant`s get neither, per
phase 4's precedent.

```
lib/dexpace/resilience/policy.rb                 Dexpace::Resilience::Policy
lib/dexpace/resilience/resend.rb                 Dexpace::Resilience::Resend
lib/dexpace/resilience/retry_settings.rb         Dexpace::Resilience::RetrySettings
lib/dexpace/resilience/recovery_retry.rb         Dexpace::Resilience::RecoveryRetry
lib/dexpace/resilience/retry_step.rb             Dexpace::Resilience::RetryStep        (sync)
lib/dexpace/resilience/async_retry_step.rb       Dexpace::Resilience::AsyncRetryStep    (async)

lib/dexpace/http_date.rb                         MODIFIED: GRAMMAR's day group widened (R1)
lib/dexpace/error/protocol_error.rb              MODIFIED: #retryable? added (DEF-38)
lib/dexpace/pipeline/cursor.rb                   MODIFIED: #bundle reader, .build's bundle: (OI-31)
lib/dexpace/pipeline.rb                          MODIFIED: #call's bundle: keyword (OI-31)
lib/dexpace/async_pipeline.rb                    MODIFIED: #call's bundle: keyword (OI-31)
lib/dexpace/instrumentation/step.rb              MODIFIED: bundle_for's first clause (OI-31)

sig/dexpace/instrumentation/http_tracer.rbs      NEW FILE: interface _HTTPTracer (R3), widening 5c's tree

test/support/probe_http_tracer.rb                a RecordingHTTPTracer-shaped double for ordering assertions
test/support/fake_transport.rb                   a scriptable raw transport double for the recovery engine's suite
```

Six new `lib/` files (five public constants, `RetrySettings` public as a `Data` config type), six
`sig/` mirrors, six `test/` mirrors, plus one new `sig/`-only file with no `lib/` counterpart (widening
an existing module's declared interface), six modified existing files, and two new test-support
doubles. The placement rule is phase 1's, applied and not re-decided: design §6.1 names exactly one
Ruby identifier, `Dexpace::Resilience::Policy`, so every other constant here carries its own ledger
row (below).

---

## The object model `6a` ships

### `Dexpace::Resilience::Policy` — the shared calculator, classifier consult, pacing parser

A module with no instance side, frozen constants and pure functions — `RETRY-42`'s "immutable and
stateless" made structural rather than promised.

```
Policy::DEFAULT_INITIAL_DELAY       = 0.2       # seconds, RETRY-12
Policy::DEFAULT_MULTIPLIER          = 2.0       # RETRY-12
Policy::DEFAULT_MAX_DELAY           = 8.0       # seconds, RETRY-12
Policy::DEFAULT_JITTER              = 0.2       # RETRY-12
Policy::DEFAULT_MAX_RETRIES         = 2         # stage vocabulary; +1 = 3 total sends, RETRY-12/RETRY-14
Policy::DEFAULT_RETRYABLE_STATUSES  = ::Set[408, 429, 500, 502, 503, 504].freeze   # XCUT-7
Policy::MAX_PACING_DELAY_SECONDS    = 365 * 24 * 60 * 60   # RETRY-18/RECOV-26, design §10 item 18
Policy::MAX_DURATION_NANOSECONDS    = (2**63) - 1           # RECOV-34/RECOV-26, design §10 item 18
```

| Method | Requirement |
|---|---|
| `.status_retryable?(status, retryable_statuses:)` | `retryable_statuses.include?(status)`. `RETRY-37`'s authoritative-contains: no baked-flag parameter exists to AND against |
| `.throwable_retryable?(error)` | `RETRY-2`'s capability query, `R4` |
| `.retryable?(error, retryable_statuses:)` | `error.is_a?(Dexpace::ProtocolError) ? status_retryable?(error.status.code, retryable_statuses: retryable_statuses) : throwable_retryable?(error)`. The **one** dispatch point both stacks and the recovery engine's internal reclassification call |
| `.backoff_delay(attempt, initial_delay:, multiplier:, max_delay:, jitter:, random:)` | `RETRY-9`–`RETRY-11`, `RECOV-21`. No budget parameter (`R6`) |
| `.pacing_delay(headers, header_order:, now: ::Time.now, random:)` | `RETRY-15`–`RETRY-19`, `RECOV-22`–`RECOV-26`. Total; never raises |
| `.effective_max_retries(override:, configured:)` | `RETRY-41`: present-override-wins (validated non-negative), else configured, negative-configured clamped to `DEFAULT_MAX_RETRIES` |
| `.budget_remaining(elapsed:, total_timeout:)` | `RECOV-20`. Recovery driver only (`R6`) |

**`.backoff_delay`**, stated in full because it is the one function both stacks trust never to drift:

```ruby
def self.backoff_delay(attempt, initial_delay:, multiplier:, max_delay:, jitter:, random:)
  raise Dexpace::InvalidArgumentError, "attempt must be >= 1" if attempt < 1

  unjittered = [initial_delay * (multiplier**(attempt - 1)), max_delay].min
  return unjittered if jitter.zero?

  spread = unjittered * jitter
  return unjittered if spread < 1e-9 # RETRY-10's degenerate sub-nanosecond range

  low = unjittered - (spread / 2.0)
  high = unjittered + (spread / 2.0)
  [random.rand(low..high), 0.0].max # RETRY-10's negative-sample floor, defensive
end
```

`multiplier**(attempt - 1)` saturates to `::Float::INFINITY` for a large enough `attempt` rather than
raising, and `[Float::INFINITY, max_delay].min` is `max_delay` — `RETRY-11`'s overflow-safety is Ruby
float arithmetic's own behaviour, not a guard `6a` writes.

**`.pacing_delay`** dispatches, in the caller-supplied `header_order`, to one of three per-form
parsers, each individually total (wrapped so a raise inside one form falls through to the next
rather than aborting the whole dispatch — `RETRY-22`/`RECOV-29`'s "a failure while parsing a pacing
header MUST NOT mask the real upstream failure" is honoured one level up, by the *caller* falling back
to `backoff_delay` when `pacing_delay` returns `nil`, and one level down, by no single header's
malformed value poisoning the whole header set's scan):

```ruby
def self.pacing_delay(headers, header_order:, now: ::Time.now, random: ::Random.new)
  header_order.each do |name|
    value = headers[name]&.first
    next if value.nil?

    delay = case name.downcase
            when "retry-after" then parse_retry_after(value)
            when "retry-after-ms", "x-ms-retry-after-ms" then parse_millis(value)
            when "x-ratelimit-reset" then parse_epoch_reset(value, now: now, random: random)
            end
    return delay unless delay.nil?
  end
  nil
end
```

`parse_retry_after` screens with a strict decimal grammar (`RETRY-19`) before any float parse —
`\A\d+(\.\d+)?\z`, anchored, rejecting a type suffix, hex-float or `NaN`/`Infinity` spelling — and
falls back to `Dexpace::HTTPDate.parse` inside its own `rescue Dexpace::InvalidArgumentError` when the
decimal screen does not match, so a `Retry-After` header is tried as delta-seconds first and as an
HTTP-date second, per `RETRY-15`. `parse_millis` requires a non-negative integer literal and divides
by 1000. `parse_epoch_reset` requires a non-negative integer literal, computes `value - now.to_i`,
floors a past value to zero (`RETRY-17`), and jitters the result to `[100%, 120%]`
(`RECOV-25`/`RETRY-15`'s embedded clause) via `random.rand(delta..(delta * 1.2))`. Every branch clamps
its result to `[0, MAX_PACING_DELAY_SECONDS]` before returning (`RETRY-18`/`RECOV-26`) and every
branch is wrapped in `rescue StandardError; nil`, so a malformed value in any form maps to "no hint,"
never to a zero delay it did not earn (`RETRY-16`/`RECOV-23`).

### `Dexpace::Resilience::Resend` — the re-sendability gate

One module function, `.eligible?(request)`, stated in full under `R5` above. `6a` writes no second
one.

### `Dexpace::Resilience::RetrySettings` — one config `Data`, two consumers

```
Data.define(:initial_delay, :multiplier, :max_delay, :jitter, :max_retries, :total_timeout,
            :retryable_statuses, :pacing_header_order, :random, :clock)
```

Including `Dexpace::Model`, `private_class_method :new`, `.build` with every default from `Policy`'s
constants (`total_timeout: 0`, `random: ::Random.new`, `clock: Dexpace::Clock::SYSTEM`,
`pacing_header_order: nil` — each driver substitutes its own default order when `nil`, per `RETRY-21`'s
split precedence). `initialize` validates `RECOV-34`: `initial_delay`/`max_delay`/`total_timeout`
non-negative and `<= Policy::MAX_DURATION_NANOSECONDS` nanoseconds; `multiplier >= 1.0`; `max_retries
>= 0`; `jitter` in `[0.0, 1.0]`. `retryable_statuses` and `pacing_header_order` are `Model.own`'d —
defensively copied and frozen at construction, so a caller's later mutation of the array or set they
passed cannot change a running client's behaviour (`RECOV-34`'s collection-copy clause).

**One settings type for both stacks is the object-level statement of `RETRY-13`/`RECOV-30`**: there
is no second place a base delay or a jitter fraction could be typed in, because there is no second
type to type it in.

### `Dexpace::Resilience::RecoveryRetry` — the recovery-stack engine

**The integration decision, stated once because it resolves a question the segmentation charter's
prose does not settle by itself: `RecoveryRetry` is installed as `Recovery::Orchestrator`'s own
`transport:` argument, decorating the raw transport, rather than as a `Recovery::ResponseChain`
recovery step.** Two facts force this:

- `Recovery::Transform`'s recovery-step contract is `#apply(outcome) -> Outcome` — **one** argument.
  `Outcome::Failure` carries only `#error`; `Outcome::Success` carries only `#response`. Neither
  carries the request that produced it, and a generic recovery step therefore has no way to *resend*
  anything — it can only look at what already happened.
- `RECOV-19`'s "each RE-SENT attempt's response MUST be re-classified" describes an engine that
  dispatches its own resends directly against a raw transport and inline-replicates `ErrorMappingStep`'s
  classification (`Recovery.buffer_error_body` then `ProtocolError.for_or_nil`) purely to decide
  *whether to keep retrying* — which is exactly what a transport-decorator sees and a generic
  recovery step does not.

So `Dexpace::Resilience::RecoveryRetry.build(transport:, settings: Dexpace::Resilience::RetrySettings.build,
http_tracer_factory: ->(_) { Dexpace::Instrumentation::HTTPTracer::NULL })` is itself a
`Dexpace::Transport` by phase 2's duck type, and `Recovery::Orchestrator.build(transport: recovery_retry,
request_chain:, response_chain:)` is how the "recovery-chain retry" stack `RETRY-13` names is
assembled — `RequestChain` runs once (its idempotency-key and client-identity stamping happen exactly
once per exchange, never once per attempt, which is what keeps `Recovery::ClientIdentityStep`'s
`:append` mode from growing its header on a retry); `RecoveryRetry#call` receives the **stamped**
request once and resends that same object for every attempt; `Recovery::ResponseChain`'s
`ErrorMappingStep` runs exactly once, on whichever response `RecoveryRetry` finally hands back,
respecting whatever custom `factory:` the caller configured — `6a`'s own internal reclassification
never substitutes for it and never uses a caller's custom factory, because it is discarded the moment
a final response is chosen.

```ruby
def call(request, options, cancellation)
  attempt = 1
  elapsed = 0.0
  start = @settings.clock.monotonic
  suppressed_trail = []

  loop do
    response = @transport.call(request, options, cancellation)
    error = classify(response) # nil for Success, else an internally-built ProtocolError
    return response if error.nil? # terminal Success -- outer ErrorMappingStep, if any, sees this raw response

    unless retry?(error, request, attempt)
      return response # terminal, still an error status -- same reasoning: return, do not raise
    end

    @http_tracer.attempt_failed(request, error, nil) # next_delay filled in once computed, below
    Dexpace.attach_suppressed(error, suppressed_trail.last) unless suppressed_trail.empty?
    suppressed_trail << error

    delay = @settings.pacing_header_order && response &&
            Dexpace::Resilience::Policy.pacing_delay(response.headers, header_order: @settings.pacing_header_order)
    delay ||= Dexpace::Resilience::Policy.backoff_delay(attempt, **@settings.to_backoff_kwargs)

    elapsed = @settings.clock.monotonic - start
    budget = Dexpace::Resilience::Policy.budget_remaining(elapsed: elapsed, total_timeout: @settings.total_timeout)
    if attempt >= @settings.max_retries + 1 || elapsed >= budget || (elapsed + delay) > budget
      suppressed_trail[0...-1].each { |e| Dexpace.attach_suppressed(error, e) }
      raise error, cause: nil # pipeline/f02559b9: never a bare `raise`
    end

    @settings.clock.sleep([budget - elapsed, delay].min, cancellation: cancellation)
    attempt += 1
  end
end
```

(Sketch; the plan's task carries the exact, fully-buffered, connection-releasing version.
`RETRY-35`'s ordering — release before wait, close on any throw in between — is enforced by
`classify`'s own use of `Recovery.buffer_error_body`, which materialises and releases the underlying
connection as its side effect, and by wrapping the delay computation in an `ensure` that closes
`response` if it is still open when the method exits by any path.)

`RECOV-28`'s per-call statelessness is structural: `attempt`, `elapsed`, `start` and `suppressed_trail`
are all local to one `#call` invocation; nothing is written to `@settings` or any other shared
instance variable, so two concurrent calls through one `RecoveryRetry` instance cannot clobber each
other's budget.

**The one instrumentation call above is deliberately partial** — `#attempt_started` is called at the
top of the loop (omitted from the sketch), `#attempt_failed` on every non-terminal retry decision, and
`#retries_exhausted` immediately before the terminal `raise`, **immediately followed by
`operation_failed` with the same throwable** where the *pipeline* itself observes the whole chain
failing — that adjacency is `OBS-29`'s clause and is a constraint on 5c's `NULL`/conformant emitter
test, not on this engine, which emits only the per-attempt group (`DEF-42`, R15).

### `Dexpace::Resilience::RetryStep` — the sync stage-based pillar step

`.build(settings: Dexpace::Resilience::RetrySettings.build, http_tracer_factory: ->(_) {
Dexpace::Instrumentation::HTTPTracer::NULL }, delay_override: nil, should_retry: nil)`. Declares
`#stage => Dexpace::Pipeline::Stages::RETRY`.

```ruby
def call(request, cursor)
  tracer = @http_tracer_factory.call(cursor)
  max_retries = Dexpace::Resilience::Policy.effective_max_retries(
    override: cursor.options.max_retries, configured: @settings.max_retries
  )

  attempt = 1
  suppressed_trail = []
  loop do
    tracer.attempt_started(cursor, attempt)
    fork = cursor.fork # PIPE-15/PIPE-16: fresh cursor, every drive, including the first (pipeline/86343352)

    begin
      response = fork.call(cursor.request)
    rescue ::StandardError => e
      raise unless attempt <= max_retries && eligible?(e, request, nil, attempt)
      # exception path: RETRY-39 skips the pacing-header step entirely
      delay = resolve_delay(attempt, nil, e)
      tracer.attempt_failed(cursor, e, delay)
      Dexpace.attach_suppressed(e, suppressed_trail.last) unless suppressed_trail.empty?
      suppressed_trail << e
      @settings.clock.sleep(delay, cancellation: cursor.cancellation)
      attempt += 1
      next
    end

    unless response.status.error? && attempt <= max_retries && eligible?(nil, request, response, attempt)
      return response
    end

    delay = resolve_delay(attempt, response, nil)
    tracer.attempt_failed(cursor, response, delay) # RETRY-35: close before the wait
    response.close
    @settings.clock.sleep(delay, cancellation: cursor.cancellation)
    attempt += 1
  end
end
```

(Sketch; `eligible?` composes `Dexpace::Resilience::Resend.eligible?(request)` with
`Policy.retryable?`/`@should_retry`, and `resolve_delay` implements `RETRY-39`'s four-source
precedence with `RETRY-40`'s non-fatal-override / fatal-predicate split, both stated in full by the
plan's task.) **No total-timeout anywhere in this method** — `R6`'s structural argument, visible in
the source rather than merely asserted: there is no local variable named `elapsed`, no `budget`, and
no call to `Policy.budget_remaining`.

### `Dexpace::Resilience::AsyncRetryStep` — the async driver

Same settings, same `Policy` calls, different suspension mechanism and a genuinely different control
shape: an iterative pump via `Future#on_settle`, never a recursive method call nested inside its own
still-open stack frame.

```ruby
def call(request, cursor)
  tracer = @http_tracer_factory.call(cursor)
  completer = Dexpace::Async::Completer.new
  max_retries = Dexpace::Resilience::Policy.effective_max_retries(
    override: cursor.options.max_retries, configured: @settings.max_retries
  )
  suppressed_trail = []

  pump = lambda do |attempt|
    tracer.attempt_started(cursor, attempt)
    fork = cursor.fork
    fork.call(cursor.request).on_settle do |settlement|
      # RETRY-32: a settled/cancelled completer launches nothing further; an in-flight response
      # from an abandoned re-drive is closed rather than leaked.
      if completer.settled?
        Dexpace.close_quietly(settlement.response) if settlement.response
        next
      end

      response = settlement.response
      error = settlement.error
      retryable = attempt <= max_retries &&
                  (error ? eligible?(error, request, nil, attempt)
                         : response.status.error? && eligible?(nil, request, response, attempt))

      unless retryable
        response ? completer.fulfil(response) : completer.fail(error)
        next
      end

      begin
        delay = resolve_delay(attempt, response, error)
      rescue ::StandardError => e
        response&.close
        completer.fail(e) # RETRY-33: a throwing delay computation completes the future exceptionally
        next
      end

      tracer.attempt_failed(cursor, error || response, delay)
      response&.close # RETRY-35
      Dexpace.attach_suppressed(error || response.to_protocol_error, suppressed_trail.last) unless suppressed_trail.empty?

      Dexpace::Async.delay(delay).on_settle do |delay_settlement|
        if delay_settlement.error
          completer.fail(delay_settlement.error) # R2: SeamError from a scheduler-less positive wait
        elsif completer.settled?
          nil # cancelled while waiting: RETRY-32, launch nothing
        else
          pump.call(attempt + 1) # the re-arm: a plain call, not a recursive frame kept alive
        end
      end
    end
  end

  pump.call(1)
  completer.future
end
```

(Sketch; the plan's task states the full body including `#retries_exhausted`'s emission and the
final `raise`-vs-`return` symmetry with the sync driver.) **`pump.call(attempt + 1)` does not grow the
Ruby call stack across retries**: it runs from inside the delay future's `on_settle` callback, which
fires on whatever thread or fiber settles that future — not nested inside the frame that called
`pump.call(attempt)` — so `RETRY-30`'s "N retries MUST NOT build an N-deep chain of future
continuations or stack frames" holds by the same mechanism phase 2's `Completer#fulfil`/`#on_settle`
pair already relies on (§3.3's "callbacks run outside the settling mutex, on the calling fiber, and
a late registration is never lost").

### `Dexpace::ProtocolError#retryable?` — `DEF-38`, `XCUT-5`

```ruby
def retryable?
  @retryable
end
```

computed once in `initialize`, from `Dexpace::Retryability.retryable_status?(status.code)` — 5a's
classifier, never a second one. `Dexpace::ProtocolError#retryable?` and
`Dexpace::Resilience::Policy.status_retryable?` answer two different questions from two different
objects and neither reads the other, per `XCUT-5`'s own closing NOTE.

### `Dexpace::Configuration::Keys::MAX_RETRY_ATTEMPTS` — `RETRY-12`'s values, 5a's name

5a shipped the key name with no reader consulting it. `6a`'s `RetrySettings.build` reads it once,
if the caller did not override `max_retries` directly:
`configuration.integer(Configuration::Keys::MAX_RETRY_ATTEMPTS, default: Dexpace::Resilience::Policy::DEFAULT_MAX_RETRIES)`.
The key's semantics — this document's own decision — denote the **stage-vocabulary** `max_retries`
(default 2, excluding the initial send); the recovery driver's `max_attempts` is always `max_retries +
1` wherever it reads the same configured number, which is `RETRY-14`'s equivalence made an arithmetic
identity rather than two independently-typed numbers that could drift.

---

## The spec-forced boundaries, honoured

Each of the fourteen boundaries the charter names as not open to any sub-phase is honoured by name,
not re-argued:

1. **Fork for every drive, never call `#call` on a driving pillar.** Both `RetryStep` and
   `AsyncRetryStep` fork before every attempt including the first; neither ever calls `cursor.call`.
2. **The cross-origin marker is `6b`'s and `6c`'s alone.** `6a` writes no `state:` argument to
   `#fork` at all — its own fork calls pass no `state:`, because `RETRY` owns no cursor-scoped
   publication of its own under this design.
3. **Two retry stacks, one policy, no unification.** `Policy`, `RetrySettings`, `Resend` are the one
   shared core; `RecoveryRetry` and the two `Stages::RETRY` drivers are three thin consumers.
4. **`RETRY-28` forbids a budget on the stage stack; `RECOV-20` requires one on the recovery
   stack.** `R6`'s wrapper decision.
5. **The inter-attempt wait is `CFG-15`'s cancellable queue wait.** `Clock#sleep(duration,
   cancellation:)` on the sync path; `Async.delay` on the async path; no `Timeout.timeout`,
   `Thread#raise` or `Thread#kill` anywhere in this sub-phase.
6. **The status classifier is 5a's; `6a` builds no second one.** `Dexpace::Retryability` feeds
   `ProtocolError#retryable?` only; `Policy.status_retryable?` is a different object over a different
   (configurable) set, per `XCUT-5`'s NOTE.
7. **The non-protocol branch is `XCUT-6`'s capability query.** `Policy.throwable_retryable?`, no
   `is_a?` branch anywhere.
8. **`Dexpace::BoundedMap`** — not touched by `6a` at all; `6c`'s boundary.
9. **Basic/Digest never `Base64`/`OpenSSL::Digest`** — `6c`'s boundary; `6a` requires neither.
10. **`SecureRandom` for the cnonce** — `6c`'s boundary. `6a`'s `random:` keyword defaults to
    `::Random.new`, the **non**-cryptographic generator `RETRY-9`/`RETRY-10`'s jitter is explicitly
    permitted to use (nothing in `RETRY`'s chapter asks for a CSPRNG).
11. **`URI::RFC3986_PARSER`** — not touched by `6a`; it parses no URL.
12. **The async pipeline follows no redirects** — `6b`'s boundary; `6a` ships an async retry driver
    precisely because `RETRY` has no such restriction, unlike `REDIR-25`.
13. **`AUTH-31`'s replayability gate on both paths** — `6c`'s boundary; `6a`'s own `RETRY-34`
    (the parallel sync/async drift the same design-§11.19-item-12 resolution covers) is honoured by
    both drivers calling `Dexpace.attach_suppressed` identically.
14. **Roadmap cross-phase obligation 2** — `6b`/`6c`'s boundary; not `6a`'s.

---

## Cross-cutting constraints that bite `6a` specifically

- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** `6a` holds no mutex at all — every mutable
  quantity in `RecoveryRetry#call`, `RetryStep#call` and `AsyncRetryStep#call` is a local variable
  scoped to one invocation (`RECOV-28`, `RETRY-42`); the only shared, cross-call state anywhere in
  `6a`'s object model is the frozen `RetrySettings` instance and the frozen `Policy` constants, both
  read-only after construction.
- **Bytes on the wire are `Encoding::BINARY`; `downcase` takes no argument.** `Policy.pacing_delay`'s
  header-name dispatch (`name.downcase`) and its per-form value screens are the two places a fold
  matters in `6a`; neither reads a response body.
- **Regexp timeouts are per-pattern, never `Regexp.timeout`.** `Policy`'s decimal-grammar screen
  (`\A\d+(\.\d+)?\z`) is compiled once with an explicit `timeout:`, following the pattern 5a's own
  `HTTPDate::GRAMMAR` and `ConfigParsers` already establish; `6a` widens `HTTPDate::GRAMMAR`'s day
  group in place and does not recompile it without a timeout.
- **An `Enumerator` abandoned mid-`#next` never runs its `ensure`.** `Dexpace.each_cause`'s
  block-form is what `Policy.throwable_retryable?` uses (`.any? { … }`, block form, never the
  block-less `Enumerator` return); `6a` acquires no resource inside an `Enumerator` block anywhere.
- **Deadlines are explicit values.** `RecoveryRetry`'s `budget_remaining` computation and the
  per-attempt `[budget - elapsed, delay].min` clamp are arithmetic on `Float` values threaded as
  parameters, never an ambient interrupt.
- **`Ractor` is never load-bearing.** `Policy`'s frozen constants and `RetrySettings`'s deep-frozen
  collections are Ractor-shareable as a free side effect of `Model.own`; nothing in `6a`'s design
  claims or tests it.

---

## Testing strategy

`6a`'s suite has five natural groups, and the charter's own convergence-point warning (`RETRY-14`'s
budget-equivalence test) is honoured as an ordering constraint inside this one plan rather than a
cross-sub-phase dependency:

1. **`Policy` unit tests** — the calculator against `RETRY-9`–`RETRY-11`/`RECOV-21` (including the
   overflow-saturation and degenerate-jitter-range cases as explicit fixtures, not relied on
   incidentally); the pacing parser against every one of `RETRY-15`–`RETRY-19`'s named forms, with a
   dedicated fixture per malformed-input class (`RETRY-16`'s totality is a **negative** test suite:
   assert `nil`, never assert an exception is not raised, per `testing/26b866e1`'s ban on
   `assert_nothing_raised`); `RETRY-37`'s authoritative-contains semantics as its own test, per design
   §6.1's explicit instruction.
2. **`Resend` unit tests** — the four-cell truth table (body-less idempotent/non-idempotent,
   body-bearing replayable/non-replayable) against a `FakeBody` double, per `RETRY-5`–`RETRY-8`.
3. **`RecoveryRetry` integration tests, against a scriptable fake raw transport** — `RECOV-17`
   through `RECOV-30`, one test per row wherever the row names an independently-testable behaviour,
   plus the 503,503,200 sequence `RETRY-36` names by example and `RETRY-35`'s close-before-wait
   ordering asserted by a fake response whose `#close` call count and call order relative to the
   fake clock's `#sleep` call are both observed.
4. **`RetryStep`/`AsyncRetryStep` integration tests, against 4c's `ForkingProbe`/`StateProbe`
   doubles** — the fork-for-every-drive rule (a test that counts `#fork` calls and asserts zero
   `#call` calls on the owning cursor across N attempts), the sequential single-use latch's
   sequential-only guarantee stated in the YARD and *not* tested as a race (P4-33's own precedent —
   `6a` writes no test asserting the concurrent-reuse race, for the same reason 4c wrote none).
5. **The `RETRY-14` convergence test** — one test, in `6a`'s own suite, spanning both stacks: builds
   a `RecoveryRetry` and a `RetryStep` from the **same** `RetrySettings`, drives each against an
   identical failure sequence, and asserts both exhaust after the same number of total wire sends
   (3, under the shared defaults). This is the ordering constraint the charter names for `6a`'s own
   plan, not a cross-sub-phase dependency — see *Task order and dependency chain* in the plan.

`R2`'s three named routes get one test each: a zero-length async delay under no scheduler (asserts no
`SeamError`, `Fiber.scheduler.nil?` throughout); a positive async delay under `test/support/probe_scheduler.rb`
(4c's/5a's, reused rather than re-written); a positive async delay under no scheduler (asserts the
returned `Future` fails with `Dexpace::SeamError`, not a hang and not a silent thread-blocking
fallback).

---

## The interface surface later phases may cite

| Consumer | What it gets, and the obligation |
|---|---|
| **`6b`** (`OI-31`) | `Cursor#bundle`, if `6a` lands first. `6b` states in its own design that it consumes it if present and ships its own constructor keyword regardless |
| **`6c`** (`OI-31`) | The same, for the same reason |
| **`DEF-39`'s executor** (phase-level, `6a` or `6b`, whichever lands second) | `Dexpace::Resilience::RetryStep`/`AsyncRetryStep`, both declaring `#stage`. `DEF-39`'s constructors install them **over** `Builder#install_preset`; `6a` builds the ingredient and does not build the constructors |
| **Phase 8**, on `R4`'s deviation candidate | The obligation to wrap a bare `Errno::*`/`SocketError`/`Timeout::Error` an adapter lets escape in something answering `#retryable?`, defaulting to `true` per `XCUT-4` branch (b)'s default |
| **Phase 9**, on `XCUT-5`/`XCUT-6`/`XCUT-7` | `Dexpace::Retryability.retryable_status?` (the baked classifier), `Policy.throwable_retryable?` (the capability query), `RetrySettings#retryable_statuses` (the configurable set) — three distinct objects, audited as three |
| **Phase 9**, on `XCUT-11` | `Policy` (frozen, stateless module) and `RetrySettings` (frozen `Data`) as audited shared instances |

---

## Deviation Ledger

Numbering starts at `P6-1`; no `P6-<n>` exists anywhere in `docs/` (verified 2026-09-09).

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P6-1 | Public constants design §6.1 does not name: `Dexpace::Resilience::Resend`, `::RetrySettings`, `::RecoveryRetry`, `::RetryStep`, `::AsyncRetryStep`; `Policy`'s own constant table (`DEFAULT_INITIAL_DELAY` etc.); the RBS interface `_HTTPTracer` (widening 5c's tree) | `NFR-4`; `api-design/b0e18938`; phase 5a's P5-1 precedent | Design §6.1 names exactly one Ruby identifier, `Dexpace::Resilience::Policy`, and describes the two stacks and the shared config in prose. Each name above is chosen for a stated reason in the object model |
| P6-2 | Public **methods** design §6.1 does not name: `Policy`'s eight module functions; `Resend.eligible?`; `RetrySettings.build`; `RecoveryRetry.build`, `#call`; `RetryStep.build`, `#call`, `#stage`; `AsyncRetryStep.build`, `#call`, `#stage`; `ProtocolError#retryable?`; `Cursor#bundle`; `Pipeline#call`'s and `AsyncPipeline#call`'s `bundle:` keyword | `NFR-4`; phase 5a's P5-2 precedent | `NFR-4` locks a signature, not only a name. `Cursor#bundle` and the two `bundle:` keywords are widenings, per `api-design/1d9e6e0b`, and prejudice no existing signature |
| P6-3 | The recovery-stack engine is installed as `Recovery::Orchestrator`'s `transport:` argument, decorating the raw transport, rather than as a `Recovery::ResponseChain` recovery step | `RECOV-19`; `Recovery::Transform`'s one-argument contract (4b's design); `RETRY-13`/`RECOV-30` | `Recovery::Transform#apply(outcome)` carries no request, so a generic recovery step cannot resend anything; `RECOV-19`'s "each RE-SENT attempt's response MUST be re-classified" describes an engine dispatching its own resends directly, which only a transport-decorator position can do while keeping `RequestChain`'s stamping (idempotency key, client identity) applied exactly once per exchange rather than once per attempt |
| P6-4 | `RETRY-2`'s capability-only classification has a stated blind spot: a bare, unwrapped stdlib I/O or timeout error escaping an adapter classifies not-retryable | `RETRY-2`, `RETRY-4`, `XCUT-4`, `XCUT-6`; `DEF-40`'s mirror-image residual for `CFG-35` | The concrete-type alternative is wrong in both directions (`DEF-40`'s own argument, re-verified here); the residual becomes an obligation on phase 8's adapters to wrap, mitigated by `XCUT-4` branch (b)'s own default-retryable flag on the wrapper type they must supply |
| P6-5 | `Dexpace::Resilience::Policy.backoff_delay` takes no `total_timeout` parameter; the recovery-only budget check is a separate function, `Policy.budget_remaining`, that `RetryStep`/`AsyncRetryStep` never call | `RETRY-28`; `RECOV-20`; design §6.1's "MAY additionally enforce" reading (`R6`) | A parameter that exists, however defaulted, is a parameter the stage driver's code could pass by mistake. Splitting the function makes `RETRY-28`'s prohibition a fact about which files reference which method name, checkable by a text scan, rather than a runtime invariant that depends on every future edit remembering not to pass the keyword |
| P6-6 | `Configuration::Keys::MAX_RETRY_ATTEMPTS`'s configured integer is defined to denote the **stage-vocabulary** `max_retries` (excluding the initial send); the recovery stack's `max_attempts` is always `max_retries + 1` wherever it reads the same key | `RETRY-12`; `RETRY-14`; 5a's un-decided key semantics | 5a shipped the name with no semantics attached to its value. Fixing the semantics as an arithmetic derivation rather than as two independently-configured numbers makes `RETRY-14`'s equivalence an identity a test asserts structurally, never a coincidence two separate defaults happen to agree on today and could silently stop agreeing after an edit to one of them |
| P6-7 | `Dexpace::Resilience::RetryStep`'s and `AsyncRetryStep`'s `http_tracer_factory:` keyword is called with `cursor` as its sole argument and as the `context` HTTPTracer's eleven methods take, rather than with an `Instrumentation::Bundle` or a new correlation type | `OI-29`; `OBS-29`; `PIPE-11` (`R3`) | `OI-29` establishes the bundle is the wrong object for a per-operation HTTP-tracer; `cursor` is the one per-call handle every step already receives, so reusing it needs no second cursor widening beyond `OI-31`'s own and keeps `6a`'s `DEF-42` task independent of whether `OI-31` has landed |

---

## Deferrals filed by phase 6a

**None new.** `6a` is a scope disposition of a phase-4 row (`DEF-35`, picked up and closed) plus two
sub-clauses of other phases' rows (`DEF-38`, `DEF-40`, both picked up and closed) plus half of a
fourth (`DEF-42`, picked up, not closed — the operation-lifecycle triple stays unwired, `R15`). No new
ID cluster is moved out of `6a`'s scope to a later phase; `RETRY-29`/`RETRY-38`/`RETRY-43` keep the
pre-existing rows `DEF-6` and `DEF-5` already carry, untouched.

### Deferral-register sweep

`6a`'s delta against the charter's whole-register sweep, which covered every row once and is not
repeated here — as with phases 3, 4 and 5, this document **states** each disposition and `6a`'s
**plan performs** the register edit.

- **`DEF-35` — picked up and CLOSED, by `6a`.** `RECOV-17`–`RECOV-30` and `RECOV-34` each carry a
  row naming a `6a` plan task; phase 4's fifteen ⏳ rows stay exactly as they are.
- **`DEF-38` — picked up and CLOSED, by `6a`.** `ProtocolError#retryable?` computed once at
  construction from `Dexpace::Retryability`, per 5a's `R1` amendment. Phase 4b's `XCUT-5` row closes
  with it.
- **`DEF-40` — picked up and CLOSED, by `6a`.** Argued above.
- **`DEF-42` — picked up, NOT closed, by `6a`.** The per-attempt group ships (`RetryStep`'s and
  `RecoveryRetry`'s `http_tracer_factory:`-produced tracer, called at `#attempt_started`/
  `#attempt_failed`/`#retries_exhausted`). The row's finding about the operation-lifecycle triple's
  unavailable route is confirmed and a correction is filed below for a human to apply.
- **`DEF-39` — untouched by `6a`, and named because the charter assigns its execution elsewhere.**
  `6a` builds the two step families the constructor needs but does not build
  `Pipeline.standard`/`AsyncPipeline.standard` — see *Relationship to phase-level tasks* below.
- **`DEF-5`, `DEF-6` — untouched.** `RECOV-31`/`RETRY-29`/`RETRY-38`/`RETRY-43` keep their existing
  ⏳ rows and no budget line, per the charter's exact instruction.
- **`DEF-18` — untouched.** `ASYNC-3`/`PIPE-33`'s interrupt clause are phase 8's; `6a` meets the same
  §8.3 prohibition at `RETRY-23`/`RETRY-26` and adds no fourth unsatisfied MUST.

## Relationship to phase-level tasks, and to `6b`/`6c`

`6a` is **independent of `6b` and `6c`**, as the Prerequisites section states in its own words. Its
only two touchpoints with the rest of phase 6 are:

- **`OI-31`'s cursor widening**, which `6a` **builds**, per the charter's assignment and this
  document's `OI-31` section above. `6b` and `6c` consume `Cursor#bundle` if it exists and ship their
  own constructor keyword regardless.
- **`DEF-39`'s `Pipeline.standard`/`AsyncPipeline.standard`**, a phase-level task `6a` does **not**
  own. The charter assigns its execution to "whichever of `6a` and `6b` lands second"; `6a` builds the
  ingredient (`RetryStep`/`AsyncRetryStep`, both declaring `#stage`) the constructor will install and
  states here that it does not claim the constructor itself, so the task is not built twice and is
  not silently dropped between two designs that each assume the other wrote it.
- **`RETRY-14`'s budget-equivalence test** is a convergence point **inside** `6a` alone (both stacks
  are `6a`'s), not a cross-sub-phase one, and is named in the testing strategy above precisely so a
  reader does not mistake it for one.

`6a` claims neither `DEF-39`'s constructors nor `6b`'s/`6c`'s work. If `6a` runs before either, the
recommended order the charter states (`6a` → `6b` → `6c`) is a convenience this document does not
re-argue; if the order changes, nothing in `6a`'s own plan needs to.

---

## The findings proposed for the registers

Three, described here for a human to file. **None is acted on by this document, none carries a
number, and no register file is edited by it.**

**Target register: `docs/deferred-items.md`, as a correction to `DEF-42`'s row.** `DEF-42`'s stated
pick-up route for `OBS-29`'s operation-lifecycle triple — a third slot on 5b's instrumentation step —
is confirmed unavailable in the phase its own condition names: 5b's step is pinned to
`Stages::LOGGING` (order 1100), which sits inside `Stages::REDIRECT` (200), `Stages::RETRY` (500) and
`Stages::AUTH` (800), so once phase 6's three pillars exist, a step at `LOGGING` runs once per
redirect hop, per retry attempt and per auth replay, and an operation-scoped emission from there would
fire many times per operation — the charter's own finding, re-verified here against the shipped code
rather than trusted. `6a` discharges the per-attempt half of `DEF-42`'s row (the retry step emits it)
and leaves the operation-lifecycle triple unwired, per `R15`'s decision not to ship a new
`Stages::PRE_REDIRECT`-adjacent step to close it. The row's pick-up condition needs the correction the
charter already drafted: the site that would work is `Stages::PRE_REDIRECT`, a **new** step, not a
slot on an existing one, and no sub-phase of phase 6 currently owns the ID that would justify shipping
it. Cites: `OBS-28`, `OBS-29`, `PIPE-2`, `PIPE-37`, `DEF-42`, `OI-29`.

**Target register: `docs/open-items.md`, as a resolution on the existing `OI-31` row.** `OI-31` is
resolved by widening `Dexpace::Pipeline::Cursor`, built by `6a`: a read-only per-call `#bundle`
accessor plus one optional `bundle:` seeding keyword on `Pipeline#call`/`AsyncPipeline#call`, both
widenings under `NFR-4` per `api-design/1d9e6e0b`; `bundle_for` in 5b's `Dexpace::Instrumentation::Step`
gains its first clause in the same task, exactly as `OI-31`'s own text anticipates. `6a`'s `DEF-42`
emission task does **not** depend on this widening, because `OI-29` establishes that `OBS-29`'s
HTTP-tracer is a different kind of object from `CTX-14`'s `Bundle#tracer_factory`, and `6a`'s retry
step reads its per-operation tracer from a factory called with `cursor` itself, never from a `Bundle`.

**Target register: `docs/first-release.md`.** `RETRY-2`'s capability-only classification has a stated
blind spot (`P6-4`): a bare, unwrapped `Errno::ETIMEDOUT`/`SocketError`/`Timeout::Error` an adapter
lets escape unwrapped classifies as not-retryable, and this is invisible until an adapter exists to
test it against. The line to file: **phase 8's first transport adapter must wrap every stdlib I/O and
timeout error it lets escape in something answering `#retryable?`** (`Dexpace::TransportError` or
equivalent), defaulting to `true` per `XCUT-4` branch (b), before release — because the alternative
is a real, silent retry-eligibility regression for exactly the class of failure `RETRY-4` calls
"always retryable," reachable the first time a real socket times out against a real adapter. Cites:
`RETRY-2`, `RETRY-4`, `XCUT-4`, `XCUT-6`, `DEF-40`.

**One existing row closes as a consequence and is named so the closure is not lost.** `OI-21` closes
when `6a` computes `ProtocolError#retryable?` from 5a's `Dexpace::Retryability`, supplying the
phase-6 end of the cross-reference 5a's `R1` supplied from the phase-5 end.

---

## Open questions for `6a`'s own plan

Four, each bounded, none reopening a decision above.

1. **The exact `RetryStep`/`AsyncRetryStep` `should_retry:` and `delay_override:` customization
   hooks.** `RETRY-39`/`RETRY-40` name a caller-delay-override and a should-retry predicate as
   customization points, and this document's object model sketches how each is consulted, but the
   exact well-typed error `RETRY-40`'s "abort the call as a well-typed error" raises for a throwing
   predicate is not fixed here. Recommendation: `Dexpace::Resilience::RetryPredicateError <
   ::StandardError`, `include Dexpace::Error`, wrapping the predicate's own raise as `#cause` (a
   genuine wrap, not a re-raise of a carried error, so `pipeline/f02559b9`'s `cause: nil` rule does
   not apply — this is a *new* exception the step is raising, not a re-raise of one it is carrying).
2. **Whether `Policy.pacing_delay`'s per-form parsers live as `private_class_method`s on `Policy`
   itself or as a `private_constant` sibling module, `Dexpace::Resilience::PacingParsers`, mirroring
   5a's `Dexpace::ConfigParsers`.** Recommendation: the sibling module, following 5a's own precedent
   exactly, so `Policy`'s own public surface stays the eight methods the object model names and the
   parsing internals carry no `NFR-4` lock of their own.
3. **The exact fake transport double's shape for `RecoveryRetry`'s suite.** `test/support/fake_transport.rb`
   needs to script a sequence of responses/raises across successive calls and record call count,
   call order and the arguments each call received (to assert the resend uses the *same* request
   object every time). Recommendation: a small `Data`-backed scripted double following 4c's
   `ForkingProbe`/`StateProbe` naming convention, confirmed against 4b's own recovery-chain suite's
   test doubles on the plan's first task rather than invented fresh.
4. **Whether `RecoveryRetry`'s internal per-attempt reclassification (`Recovery.buffer_error_body`
   then `ProtocolError.for_or_nil`) needs its own `factory:` keyword mirroring `ErrorMappingStep`'s,
   or whether always using the default `ProtocolError.for_or_nil` internally is sufficient because
   the internal classification is discarded the moment a final response is chosen.** The object
   model above states the latter; the plan's task confirms it against a fake `factory:` double that
   asserts the custom factory is called **exactly once**, on the terminal response, and never on an
   intermediate retried one.
