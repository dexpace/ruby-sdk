# Phase 4b — Recovery-Chain Primitives

**Status:** Draft, for review. Written 2026-09-08, against
`docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`, which is this sub-phase's charter.

## Purpose

Sub-phase 4b builds §8.2's resilience layer: one closed two-variant outcome, two folds over frozen
step lists, one orchestrator that lets no throwable past it, and the error primitives four register
rows and five later phases have been waiting on. Eighteen `RECOV` IDs built, sixteen carried as ⏳,
one specification section, one gem.

**It is also the phase that gives the whole SDK its suppressed-exception trail**, which is why three
of its four register pick-ups are error primitives rather than chain machinery: `DEF-24` ships the
trail, `DEF-32` makes phase 2's `Hooks.notify` use it, and `DEF-27` gets the first of its two
disposal routes.

Six decisions reshape what a plan can write. **Five** were forced by a fact run on a real interpreter
rather than by taste; the sixth — `RECOV-12`'s "exactly once" — was forced by phase 3b's committed
design and is listed last so the distinction is visible rather than absorbed.

- **The trail cannot live on `Dexpace::Error`, because every primary it will ever be handed is a
  caller's exception.** `RECOV-12`'s primary is whatever a caller-supplied step raised; `DEF-32`'s
  is whatever a caller's hook raised — phase 2's own tests raise a bare `::IOError`. A `#suppressed`
  defined only on `Dexpace::Error` raises `NoMethodError` at the first such call, which is the
  ordinary case and not an edge one. So the trail is a **separate** module, `Dexpace::Suppressible`,
  that `Dexpace::Error` includes and `Dexpace.attach_suppressed` `extend`s onto anything else — and
  it has to be separate, because `rescue M` matches a module reached through a singleton class
  (verified), so extending a third-party `IOError` with the rescue root would make
  `rescue Dexpace::Error` catch errors the SDK never raised (P4-12, P4-13).
- **`RECOV-10`'s "rethrow UNCHANGED" is broken by the obvious Ruby spelling.** `raise error` assigns
  `$!` as that error's `#cause` when it has none, and `$!` is thread-scoped, so it is non-`nil`
  inside a method **called from a caller's `rescue`** — ordinary consumer code, with no `rescue`
  anywhere in core required to reach it. Verified: the surfaced error came back carrying the
  caller's unrelated in-flight exception as its cause, on all three interpreters, for the error
  `RECOV-10` itself names — "a recovery step **constructing** the error and returning a Failure",
  which reaches the unwrap with `cause` still `nil`. Every unwrap is written
  `raise error, cause: nil`, which suppresses the assignment and does not clear a legitimate
  pre-existing cause — so it stops core adding a cause and cannot undo one a caller's own `raise`
  already added, which is also why the `RECOV-10` test's fixture must construct its error rather than
  raise it. Corpus note filed (R5's neighbour, and the reason the `RECOV-10` test asserts a
  negative).
- **The `equal?`-tracked visited set `XCUT-9` demands is not what the corpus says it is, and the
  container matters more than the comparison.** `Exception#==` is structural in Ruby's own
  definition — class, message, backtrace — so an `Array`-based visited set truncates a two-node chain
  of distinct errors to one entry (measured; and the pair has to be two *never-raised* errors chained
  through a `#cause` override, because a `raise`-built pair is not `==` on 3.2.11 and the truncation
  vanishes there — verified fact 7, and the reason R7's third fixture is built the way it is). A
  `Set` or a plain `Hash` uses `#eql?`/`#hash`, which
  for a bare exception are identity and therefore accidentally correct, and which a caller-supplied
  error class overriding them defeats (measured: `Set[a].include?(b) == true`). Only
  `{}.compare_by_identity` is immune. Core's errors are not `Data`, so the reason the corpus gives
  for the rule is false about this codebase while the rule itself is load-bearing. Corpus note filed
  (R7).
- **`RECOV-11` has nothing to do in this port, and that is a property of phase 2's primitive rather
  than an omission.** The requirement's own portability note says "a port preserves whatever its
  cancellation primitive is". Phase 2's `Cancellation::Source#cancel` is idempotent and latched and
  there is no clearable flag anywhere in the model, so converting a `CancelledError` into a `Failure`
  cannot swallow a signal: the token still answers `cancelled?` afterwards. 4b ships **no
  token-mutating wrapper** and asserts the property instead (P4-17).
- **The exhaustiveness `else` arm joins `RECOV-2`'s fatal-family passthrough rather than becoming a
  `Failure`.** `NoMatchingPatternError` is inside `StandardError` on all three, so the naive routing
  turns a core defect into an outcome a recovery step may swallow — which is
  `error-handling/3bfdf6f0`'s prohibition exactly. `Dexpace::OutcomeError` is re-raised by the same
  arm that already re-raises `ScriptError` and `SignalException`, one arm with two members and one
  reason (R6, P4-19).
- **`RECOV-12`'s "exactly once" is discharged by phase 3b's latch, not by bookkeeping.** The
  error-mapping step buffers the error body — which closes the original — and then raises, so
  `RECOV-12`'s close runs against an already-closed body. **`Closeable`'s latch is the whole
  licence**: it flips under the close mutex and calls the private `#release` at most once, so the
  second close releases nothing and `RECOV-12`'s "exactly once" is a property of phase 2's primitive
  rather than of bookkeeping in the chain. (`PIPE-31`'s "idempotent double-close tolerated" is *not*
  the licence and is not cited as one: it governs the async terminal response-mapping operator, a
  `PIPE` construct in the other layer, and boundary 1 is exactly the reason 4b may not borrow it.)

4b ships no stage, no cursor, no pipeline, no transport and no socket. Its whole test surface is
value objects, folds over lambdas, and one fake transport that returns what it was told to.

## Governing documents

- `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md` — the charter. It fixes 4b's 34
  IDs, the sixteen spec-forced boundaries, and risks R5, R6, R7, R9 plus R8 jointly with 4c. R1–R4
  are 4a's and are resolved; R10–R14 are 4c's and are not touched here.
- `docs/product-spec/08-execution-pipelines.md`, read in full — §8.2 line by line and §8.3's
  prohibition — with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text
  of all 34 `RECOV` IDs and of `XCUT-4`, `XCUT-5`, `XCUT-7`, `XCUT-8`, `XCUT-9`, `RETRY-25`,
  `RETRY-34`, `RETRY-36`, `BODY-30`, `BODY-31` and `HTTP-52`. Appendix C is the **only** source for
  eighteen of the `RECOV` IDs (`OI-12`), and reading those eighteen rows is the whole of 4b's
  specification-reading budget — the charter did that pass and this document does not redo it.
- `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.2 in full and §5.1's "three shipped steps"
  and "bounded error-body copy" paragraphs;
  `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.7 (the close helper and its two
  disposal routes) and §3.1 (stream ownership);
  `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.1 for what the deferred cluster
  becomes; `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1 (the diagnostic that
  is `DEF-27`'s *second* route and not 4b's) and §8.3 (the prohibition);
  `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items 6, 12 and 18;
  `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md`
  items 12 and 20; and §12's `RECOV` row.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-4 row, cross-phase obligation
  3, and the ✅ / 🚫 / ⏳ / N/A legend 4b's checklist uses verbatim.
- `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md`,
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` with
  `docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md` (whose Task 4 is the code `DEF-32`
  changes), `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` (whose API
  table fixes two phase-4 mechanisms outright), and
  `docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-design.md`.
- `CLAUDE.md` and `docs/README.md`.

## Scope

### The 34 IDs, with dispositions

Taken from the charter's scope table rather than re-derived, and checked against it row by row.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `RECOV-1`–`RECOV-16`, `RECOV-32`, `RECOV-33` | 18 |
| ⏳ deferred, `DEF-35`, target phase 6 | `RECOV-17`–`RECOV-30`, `RECOV-34` | 15 |
| ⏳ deferred, `DEF-5` (pre-existing), post-MVP | `RECOV-31` | 1 |

**The sixteen ⏳ rows are rows and not work.** `DEF-35` — filed by the charter, not by this document
— carries `RECOV-17`–`RECOV-30` and `RECOV-34` to phase 6 with a twin-by-twin `RECOV`→`RETRY` table,
and its two forcing arguments are `RECOV-27`'s wait being the object `CFG-15` defines and `RETRY-13`
forbidding a second backoff calculator. **`RECOV-31` is not in `DEF-35`**: `DEF-5` defers it post-MVP
together with `RETRY-38`, and `DEF-6` defers that twin with no named trigger, so it is the cluster's
sixteenth ID and not phase 6's fifteenth. 4b writes both kinds of row, cites the right deferral in
each, and **builds no backoff calculator, no pacing-header parser and no retry engine.** The one
place a plan could drift into one is `RECOV-19`'s re-classification of a re-sent response, which
reads like the error-mapping step: it is not, it is the retry loop's re-entry into that step, and
`RETRY-36` is its twin.

Level split for the eighteen built: 17 MUST, 1 SHOULD (`RECOV-9`). `RECOV-9` governs **recovery
steps** — "Recovery steps SHOULD NOT throw; they SHOULD surface errors explicitly by returning a
Failure outcome" — and **4b ships no recovery step at all**: `IdempotencyKeyStep` and
`ClientIdentityStep` are request steps and `ErrorMappingStep` is a response step, so none of the
three is `RECOV-9`'s subject and citing `ErrorMappingStep`'s mandatory raise as an exception to it
would be a category error. The row is therefore satisfied in the only sense a SHOULD about *step
authors* can be: the chain tolerates a throwing recovery step (`RECOV-8`), and `ResponseChain`'s YARD
states the preference and names `Outcome::Failure.build` as the way to honour it. Phase 6's recovery
stack is the first phase with a recovery step of its own and is where the SHOULD acquires a subject.

**Also shipped by 4b without owning a new ID**, per the charter and per phase 3b's API table:

- `Dexpace::Suppressible`, `Dexpace::Error#suppressed`, `Dexpace.attach_suppressed`,
  `Dexpace.suppressed` and the trail's rendering (`DEF-24`, `RETRY-34`, `PAGE-13`, `PAGE-15`,
  `SSE-29`, `SSE-36`).
- `Dexpace.each_cause` (`XCUT-9`, phase 9's ID; design §5.2 puts the enumerator in core here).
- `Dexpace::Recovery.buffer_error_body(response)`, whose contract phase 3b fixed and 4b implements.
- **`XCUT-8`'s status-to-exception factory and `XCUT-4`'s protocol-error branch** — phase 3b's own
  API table assigns "the error-mapping step, `RECOV-15`/`XCUT-8`'s exception factory" to phase 4 in
  as many words, and `RECOV-15` cannot be built without something to map *to*. What 4b ships and
  what it does not is P4-20 and `DEF-38`.
- The `DEF-32` change to `Dexpace::Hooks.notify` and the `DEF-27` change to
  `Dexpace.close_quietly`, both phase-2 files.

### The canonical text the design turns on

Quoted from appendix C rather than paraphrased, because each fixes a decision below.

> **RECOV-1** (MUST) — The response-side outcome MUST be a closed sum type with exactly two variants
> … Standard accessors (is-success / is-failure, response-or-null, error-or-null) and a fold that
> applies exactly one of two branch functions MUST be derivable from this shape, and the fold MUST
> invoke the selected branch at most once per call.

> **RECOV-2** (MUST) — The unified orchestrator MUST catch EVERY throwable raised by (a) any
> request-chain step and (b) the transport invocation, convert it into a Failure outcome, and thread
> it through the response recovery chain. No throwable from the pre-request phase or the transport
> may bypass the recovery hooks. This is the defining invariant of the subsystem: a before-request
> throw MUST NOT skip after-error handling.

> **RECOV-3** (MUST) — The request recovery chain MUST apply its ordered steps as a sequential
> left-to-right fold … An empty chain MUST return the input request unchanged (identity/no-op). If a
> step throws, the chain MUST NOT invoke the remaining steps and MUST propagate the throwable to its
> caller (which the orchestrator then converts per RECOV-2).

> **RECOV-8** (MUST) — If a recovery step itself throws, its throwable MUST be wrapped into a Failure
> and fed to the NEXT recovery step. A throwing recovery step MUST NOT bypass or abort the remaining
> recovery steps, and the response recovery chain's apply operation MUST NOT throw under any input.

> **RECOV-10** (MUST) — The unified orchestrator's dispatch operation MUST unwrap the final outcome
> as follows: on Success it returns the contained response; on Failure it rethrows the contained
> throwable UNCHANGED (no wrapping, no substitution). Any typed-exception surfacing must be performed
> by a recovery step constructing the error and returning a Failure.

> **RECOV-11** (MUST) — When a throwable that represents thread interruption/cancellation is wrapped
> into a Failure, the wrapping helper MUST first re-assert the interrupt/cancellation signal on the
> current execution context before returning the Failure … In the reference implementation the shared
> wrapper restores the JVM interrupt flag specifically for InterruptedException; a port preserves
> whatever its cancellation primitive is.

> **RECOV-12** (MUST) — When a response step or recovery step THROWS while a Success response is in
> hand, the pipeline MUST close/release that in-hand response … before wrapping the throwable into a
> Failure, and MUST attach any error raised while closing as a suppressed/secondary error so it never
> masks the primary throwable. The response MUST be released exactly once on this throw path.

> **RECOV-13** (MUST) — When a step is handed a Success and deliberately RETURNS a different outcome
> … the pipeline MUST NOT auto-close the discarded original response. The step that performs that
> transform OWNS releasing the response it drops and MUST release it before returning the
> replacement. (The failure→failure 'Replace' path carries no response, so nothing needs releasing
> there.)

> **RECOV-14** (MUST) — A chain's step lists MUST behave as immutable after construction. The
> response recovery chain MUST defensively copy BOTH its response-step list and its recovery-step
> list at construction … (Reference-implementation asymmetry a porter must not assume away: the
> request recovery chain does NOT copy … a port SHOULD copy there too.) Steps MUST be safe to invoke
> concurrently from multiple execution contexts; per-request state MUST live in the passed context or
> the value being transformed, never on the step instance.

Three IDs outside `RECOV` fix values 4b must carry, and are quoted because 4b is where they first
become real:

> **XCUT-4** (MUST) — The error taxonomy MUST have exactly two top-level branches: (a) protocol
> errors that carry a fully-received response (status, headers, body) and are raised as an
> unchecked/runtime error …; and (b) transport errors that carry NO response and belong to the
> runtime's I/O-error family … A transport error MUST report itself as always-retryable at the error
> level.

> **XCUT-8** (MUST) — The status-to-exception mapping factory MUST reject being asked to map a
> non-error status (1xx/2xx/3xx) — it MUST raise an argument error rather than fabricate a
> 'successful exception'. A convenience form MAY instead return an absent/null value for non-error
> statuses.

> **XCUT-9** (MUST) — Any classification that walks an error's cause chain MUST be cycle-safe: it
> MUST track visited causes by reference identity and terminate on a self-referential or cyclic chain
> instead of looping forever.

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `CTX-1`–`CTX-20` — the context chain, the store, the instrumentation bundle | 4a, built. 4b consumes **none** of it; `RECOV-11`'s "current context" is phase 2's `Dexpace::Cancellation` |
| `PIPE-1`–`PIPE-40` — stages, the per-call cursor, `#fork`, both bridges | 4c. 4b names no stage and no cursor anywhere, which is spec-forced boundary 1 |
| `RECOV-17`–`RECOV-30`, `RECOV-34` — the recovery-stack retry engine | 6 (`DEF-35`). The recovery-aware retry stack installs **into** what 4b ships |
| `RECOV-31` — the per-attempt ordinal header (MAY) | post-MVP (`DEF-5`, with `RETRY-38` under `DEF-6`) |
| `XCUT-5`'s baked retryability flag and the single shared status classifier; `XCUT-6`'s capability; `XCUT-7`'s configurable retryable-status set | 6 (`DEF-38`). 4b ships the protocol-error class the flag would sit on, and no flag |
| `XCUT-4`'s branch (b), `Dexpace::TransportError < ::IOError` | 8. It is a transport's error and no transport exists |
| `RETRY-34`'s failed-attempt trail and `RETRY-25`'s fatal-family rule as *retry* behaviour | 6. 4b ships `attach_suppressed` with the skip-self guard `RETRY-34` names, and the fatal-family passthrough `RETRY-25` requires, as `RECOV-2`'s rule |
| `PAGE-13`, `PAGE-15`, `SSE-29`, `SSE-36` — the other consumers of the trail; `SSE-33`–`SSE-36`'s third `Outcome` variant | 7 |
| `DEF-27`'s **second** disposal route, the `http.instrumentation.*` diagnostic | 5, with §8.1's facade. It is what closes that row and 4b must not |
| A configuration source for the idempotency-key and client-identity steps' settings | 5. 4b ships keyword arguments with documented defaults and no configuration chain |
| `BODY-30`/`HTTP-52`'s bounded copy, `BODY-31`'s predicate, `Status#error?` | 3b and 1, built. 4b ships only the step that calls them |

**No segmentation design of its own.** 4b is one specification section, one gem, 34 rows, under a
segmentation design that already exists at the `phase4/` level.

## Prerequisites, and the independence this sub-phase must state

**4b depends on 4a for nothing and on 4c for nothing, and neither depends on 4b.** The charter's
finding is that every phase-4 boundary is a convenience: `CTX` is consumed by nothing in `RECOV`, and
`RECOV-11`'s "current context" resolves to phase 2's ambient cancellation token rather than to
anything 4a ships. 4b leads 4c for three convenience reasons and blocks it for none — 4c builds and
tests every stage, cursor and fork rule against probe steps, which is what `PIPE-1`'s own conformance
clause prescribes. **The one thing that crosses the line is a contract, not an ordering**, and it is
R8 below; 4b lands first and states it so 4c cites rather than restates it.

The one thing 4b takes from 4a is a **precedent**, not an artefact: `Dexpace::ContextConflictError`
is the fourth error in phase 2's shape, and `Dexpace::OutcomeError` and `Dexpace::ProtocolError` are
the fifth and sixth. 4b names no 4a constant in `lib/`.

### From phase 0 — seventeen blocking gates, unchanged and unlowered

`gates:require_allowlist` — core's `lib/**/*.rb` may `require` only `monitor`, `uri`, `stringio`,
`strscan`, `time`, `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`.
**4b adds nothing to it and requires nothing at all.** `Data`, `Hash`, `Array`, `Exception`,
`Module#===` and `Object#extend` are core Ruby, and the one place a `require` looked likely —
`XCUT-9`'s visited set — resolves to `{}.compare_by_identity` and not to `set` (verified fact 7),
which is on the allowlist and is nonetheless not reached.

`gates:surface_snapshot` and `gates:sig_diff` regenerate once, deliberately, in the phase's last
task. Every public constant and public method below is `NFR-4`-locked at the first release tag, which
is why each is named on purpose and carries a Deviation Ledger row where design §5.1 or §5.2 did not
already name it. `Dexpace/SpdxHeader` and `Dexpace/NoThreadInterrupt` bind every file; the latter has
nothing to bite on, because 4b starts no thread, interrupts none, and has no wait.

**4b adds no cop.** Seven exist after 4a; nothing in `RECOV` is a source-text rule.

### From phase 1

- **`Dexpace::Error` is a module** (P1-2), and 4b is the phase that first puts a method on it.
- **`Dexpace::Model`** — `Model.required!`, `Model.own`, `Model.frozen_string`, and the `#with`
  override routing through the validating `.build` because `Data#with` skips an `initialize` override
  on 3.2.11. Both `Outcome` variants include it.
- **`Dexpace::InvalidArgumentError < ::ArgumentError`**, and `Dexpace::ArgumentError` is never
  defined.
- **`Dexpace::Status`** with `#error?` (400–599, `HTTP-11`) — `RECOV-15`'s classification and
  `Recovery.buffer_error_body`'s guard. **4b writes no second predicate**, which is phase 3b's stated
  negative guarantee arriving at its one consumer.
- **`Dexpace::Method`**, `Method::POST`/`PUT`/`PATCH` — `RECOV-32`'s default method set.
- **`Dexpace::Headers`** with `#[]`, `#include?`, `#new_builder`, and `Headers::Builder#add`/`#set` —
  `RECOV-32`'s and `RECOV-33`'s whole mechanism. `#set(name, nil)` removes; `#add` appends
  (`HTTP-14`, `HTTP-15`).
- **`Dexpace::Request`** and **`Dexpace::Response`** with `#with` and `#new_builder`, `#status`,
  `#headers`, `#body`.
- **Public constants are flat unless the design namespaced the subsystem** (P1-1). §5.1 names
  `Dexpace::Recovery.buffer_error_body` and §5.2 names `Dexpace::Outcome::Success` and `::Failure`,
  so both namespaces are the design's own and are kept. Everything else 4b names is a decision with a
  ledger row (R9).
- **No `.build` is a bare `new` wrapper**; validation lives in each `Data` type's `initialize`.

### From phase 2

- **`Dexpace::Transport` as a duck type over `#call(request, options, cancellation)`** — what
  `RECOV-2`'s "the transport invocation" invokes, and what makes an orchestrator itself a transport
  without either layer knowing about the other.
- **`Dexpace::Cancellation`** with `#cancelled?`, `#reason`, `#check!` and `#on_cancel`, and
  `Cancellation::Source#cancel` **idempotent with the first reason winning**. That latch is the whole
  of `RECOV-11`'s Ruby answer (P4-17). `Dexpace::CancelledError` is the typed error a cancelled wait
  raises.
- **`Dexpace::Closeable`** with its latch and `#closed?` read under the close mutex (P3-6) — what
  makes `RECOV-12`'s "exactly once" structural rather than bookkept.
- **`Dexpace.close_quietly(resource)`** — `DEF-27`'s subject. 4b changes it; see below.
- **`Dexpace::Hooks`** (`private_constant`) with `notify(hooks, argument)` — `DEF-32`'s subject. 4b
  changes it; see below.
- **The error-class shape** — `class X < ::StandardError; include Dexpace::Error; end`, as
  `SeamError`, `ClosedError`, `CancelledError` and 4a's `ContextConflictError` all are.
- **The private-snapshot rule (P2-9)**: a `Data` that is public API follows phase 1's construction
  rule without exception. Both `Outcome` variants are public API, so both get `private_class_method
  :new` and a validating `.build`.
- **4b adds no registry**, no seam and no fourth bridge.

### From phase 3

- **`Dexpace::Body.buffer_bounded(body, cap:)`** and **`Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES`
  (1 MiB)** — phase 3b's addendum B2 moved the constant one layer down and **4b declares no second
  copy** (spec-forced boundary 10). `buffer_bounded` closes the original in an `ensure`, unguarded,
  which is what discharges `RECOV-13` for the error-mapping step without a second close.
- **`Dexpace::Body`'s contract** — `#source`, a default no-op `#close` (P3-23), and `#replayable?`.
- **`Dexpace::Response#close`**, `#body_string`, `#body_bytes`, and `Dexpace::BufferBody`.
- **`Dexpace::StreamError < ::IOError`** and `EndOfStreamError < ::EOFError` — the two errors whose
  Ruby superclass is not a core-family class, and therefore R5's second sub-question.
- **`OI-8` and `OI-9`** land in 4b's window and neither is 4b's to fix or widen.

### From phase 4a

Nothing in `lib/`. 4a's `Dexpace::BoundedMap` is offered to 4c and not to 4b; 4b has no keyed map.
What 4b takes is P4-11's discipline — a public method design §5 does not name gets a ledger row — and
`OI-16`'s standing caution, which this document obeys by reading each note rather than trusting the
`[overridden by notes/…]` marker.

## Corpus reading, and what it settled

The phase-start pair was run before anything here was written. `--origin note --brief` returned **32
entries across 17 note files** at the time of the query — 35 across 18 after the three notes this
document filed. `--section conflicts --brief` returns 24 entries across 17 topic files, **18 of them
notes and six harvested**, and each of the six prints `[overridden by notes/…]` when resolved by key
(`data-modeling/35fde90f`, `module-organization/bf6411ad`,
`package-and-dependency-layout/41b154a3` and `/8c0687bf`, `tooling-and-quality-gates/86d763f1`,
`type-system/93dc79aa`). **None is open**, so 4b inherits no unresolved conflict and owns no conflict
decision of its own.

`--prefix-info RECOV` reports 34 IDs, 30 MUST / 3 SHOULD / 1 MAY, owning chapter
`docs/product-spec/08-execution-pipelines.md`, **19 of 34 substantive, 0 roll-up only, 15 uncited**.
`--gaps RECOV` returns the fifteen the charter already dispositioned. **The appendix-B roll-up hazard
does not fire for this prefix at all** — not one `--req` hit across the eighteen built IDs is tagged
`[appendix-B roll-up]` — so 4b budgets no specification reading beyond §8.2, which is eight bullets
and was read in full anyway, plus the eighteen appendix-C rows the charter's disposition pass already
covered.

`--phase 2 --brief` and `--phase 3 --brief` were run. Phase 2 cites `RECOV-12` (through `DEF-27`) and
nothing else in the prefix; phase 3 cites `RECOV-15` and `RECOV-16` and fixes two 4b mechanisms
outright. Phase 1 cites `RECOV-12` and `RETRY-34` without owning them, pointing here — which
`DEF-24`'s row already said and which is now met.

**The `CTX-9` cross-filing was met, exactly as the charter predicted.** `--req CTX-9` returns
`error-handling/1f635244` and `error-handling/5a7d53ab`, both about `Dexpace.each_cause`, because
§5.2 likens the cause walk to "the same trap **CTX-9** sets in §5.4" and the harvest read the
comparison as a citation. They are 4b's material and are used here as such. It is a cross-filing
rather than a wrong rule and earns no note; the *content* of `error-handling/5a7d53ab` earns one, for
an unrelated reason (R7).

### The audit groups this phase ran

| Group | Query | Result |
|---|---|---|
| **Pipeline composition and execution context** | `--prefix RECOV --section rules` then `--topic pipeline --section rules,constraints,conclusions,reference --brief` | 24 + 58 entries, the whole `pipeline` topic. `pipeline/93ff85e7` is what R8 turns on; `pipeline/964aab48`, `/746d6478` and `/19516188` are what R6 turns on; `pipeline/d01039c4` and `/aacfac10` are what R9 turns on — with `/aacfac10`'s "one `Dexpace::Recovery.buffer_error_body(response)` function **holding** the single `MAX_BUFFERED_ERROR_BODY_BYTES` constant" no longer true of the file it lives in, since phase 3b's addendum B2 moved the constant to `Dexpace::Body` while keeping the guarantee the entry is actually about (one constant, one bound, one call site). No note: the rule holds and only its location moved, which is what B2 already recorded and why it filed no ledger row either. One entry earns a note (`pipeline/b3f74458`, above) |
| **Public API surface** | `--topic api-design,http-domain-model,documentation,module-organization,error-handling --section rules --brief` | 64 entries in `error-handling` alone. `error-handling/a86bc536` (a deliberate swallow catches one class, re-raises the rest, and carries a why-comment) is the shape of the two rescues 4b writes; `error-handling/5e2aa68b` (an `ensure` that can raise must rescue narrowly inside it) is `RECOV-12`'s mechanism stated as a styleguide rule; `error-handling/3bfdf6f0` (never demote a programmer error) is R6's decisive rule; `error-handling/5da8cb17` and `/61ab4fb6` are why there is no per-status exception tree (P4-20) |
| **Minitest conventions** | `--topic testing,assertions --section rules --brief` | 29 entries. `testing/80c44c7f` (assert on the raised object, never rescue and ignore) shapes every `RECOV-2` and `RECOV-10` case; `testing/26b866e1` (no `assert_nothing_raised`) is what turns `RECOV-8`'s totality into an assertion on the returned outcome; `testing/7ecef8e8` and `/630ba094` name the two doubles 4b builds **fakes**; `testing/4ef070df` is why no test mutates a shared chain |
| **RBS / Steep typing** | `--topic type-system,data-modeling --section rules --brief` | `type-system/545949a5` does **not** reach `Outcome` — it governs closed sets of *identifiers*, and `Outcome`'s two variants are a sum type over two payloads, which is the `Data` union §5.2 already names; `data-modeling/3e37c086` puts the two chains and the orchestrator in classes, because each owns state (its frozen step lists) |
| **Resource lifecycle and stream ownership** | `--topic resource-management --section rules --brief` and `--chapter 13` | `resource-management/d1f16cad` (the note) confirms the per-call I/O timeout rules do not reach here; `resource-management/bf5560dc`'s block form does not reach a fold whose resource is handed *outward* on success — recorded as P4-18 rather than as a note, on 4a's P4-5 precedent |
| **Fiber scheduler, thread safety** | `--topic concurrency-and-async --section rules --brief` | 75 entries. `concurrency-and-async/f414b864` (the note) governs: 4b owns no mutable shared state at all, so it needs no mutex, which is the strongest form of that rule rather than an exemption from it |
| **Styleguide-vs-design conflicts** | `--section conflicts --brief` | All six resolved; none open |

Three audit results earn **no note**, and the reasons are specific:

- **`error-handling/e43096c3`** ("every failure must be a typed `StandardError` subclass") is
  *adopted*, and it is what stops R6 from reaching for a `ScriptError` to get outside the conversion
  boundary. An adopted rule needs no note.
- **`error-handling/596831fc`** and **`error-handling/bdae8080`/`6d4dbc71`** ("chain through `cause`
  on rethrow"; "every wrap-and-rethrow must pass `cause:`") are adopted for *wrapping* and are
  precisely inverted for `RECOV-10`, which is a **rethrow without a wrap**: there is no new error to
  chain, and Ruby's implicit assignment is the defect rather than the discipline. That inversion is
  the pipeline note above, not a second one.
- **`error-handling/299be011`** ("carry identifying inputs on custom error classes as `attr_reader`
  fields") is adopted with one stated limit: `Dexpace::OutcomeError` carries the offending object's
  **class** and not the object, because an `OutcomeError` can end up on a suppressed trail and
  retaining an arbitrary value there would pin whatever it holds.

### The three notes filed against the corpus by this phase

Written before the plan, because a resolution recorded only in a design document is re-litigated by
whoever reads the corpus next. `docs/knowledge/notes/pipeline.md` is a new file;
`docs/knowledge/notes/error-handling.md` gains two entries; `harvested/` is untouched.

- **`## Superseded`, superseding `error-handling/5a7d53ab`** — the reason `each_cause` must track by
  reference identity is **`Exception#==`**, which is structural by Ruby's own definition, and not
  "core's `Data`-based errors", which do not exist: core's errors are ordinary `StandardError`
  subclasses including a module. The note carries the consequence the entry cannot reach — which
  *container* makes the tracking true — with the three measurements that separate them.
- **`## Superseded`, superseding `error-handling/5a8298f6`** — `attach_suppressed`'s self-guard
  stands verbatim; its silence about the primary's **type** is what needed answering, because every
  primary `RECOV-12`, `DEF-27` and `DEF-32` hand it is a caller's exception and a trail defined only
  on `Dexpace::Error` raises `NoMethodError` on the first one. The note records the `extend`
  mechanism, its cost, its `FrozenError` boundary, and the reason the trail module must not be the
  rescue root.
- **`## Superseded`, superseding `pipeline/b3f74458`** — `RECOV-10`'s rule is right and the obvious
  Ruby spelling breaks it, because `raise error` assigns `$!` as the error's cause and `$!` is
  non-`nil` inside a method called from a caller's `rescue`. The note records the spelling core uses
  and the negative assertion the test has to make.

## The verified Ruby facts this phase is built on

Every claim was run on 3.2.11, 3.4.10 and 4.0.6 through `mise exec ruby@<v>` on 2026-09-08. The first
seven changed a decision; the rest are recorded because a plan would otherwise assume them. Each says
what it licenses, because a true fact that does not support its conclusion is what the last two
reviews caught.

1. **A `#detailed_message` override reaches the default uncaught-exception printer and a
   `#full_message` override does not — through inclusion *and* through `extend`.** Raising an error
   whose class includes a module defining `detailed_message(**kw)` prints the trail under the plain
   header on all three; the same module defining `full_message(**kw)` prints nothing. Extending an
   ordinary `::IOError` instance with the `detailed_message` module prints the trail identically.
   Ruby's own `Exception#full_message` calls `#detailed_message`, so the override satisfies both
   paths. **What it licenses:** `#detailed_message` alone, no `#full_message` override, and the same
   module usable on a caller's error (R5). **What it does not license:** any claim about a logger
   that formats an exception itself rather than calling `#full_message`; such a logger sees neither
   override and the trail is invisible to it, which is why `Dexpace.suppressed(error)` is public.
2. **`rescue M` matches a module reached through a singleton class.** `e.extend(OnlyTrail)` then
   `raise e` is caught by `rescue OnlyTrail`, and `e.is_a?(OnlyTrail)` is true, on all three.
   **What it licenses:** the split into `Dexpace::Suppressible` and `Dexpace::Error`. Extending a
   third-party error with the rescue root would silently widen what `rescue Dexpace::Error` catches;
   extending it with a trail-only module does not, and the negative was measured
   (`e6.is_a?(Dexpace::Error) == false` after `attach_suppressed`). **What it does not license:** a
   claim that the extension is invisible — it is visible to `is_a?(Dexpace::Suppressible)`, which is
   the point.
3. **`extend` and an ivar write both raise `FrozenError` on a frozen exception**, on all three, with
   the message differing only in Ruby's own wording. **What it licenses:** `attach_suppressed`
   rescuing `FrozenError` into a documented no-op — the single-class deliberate swallow with a
   why-comment `error-handling/a86bc536` sanctions — because a helper that raises while attaching a
   *close* error would mask the primary, which is the one thing `RECOV-12` exists to prevent. **What
   it does not license:** silence about it; the no-op is stated in the YARD and asserted in a test.
4. **`did_you_mean`'s suggestion survives `super` from an extended `#detailed_message`.** Extending a
   real `NoMethodError` and calling `super` keeps "Did you mean? upcase" and appends the trail, on all
   three. **What it licenses:** `super` being mandatory rather than decorative in
   `Suppressible#detailed_message`, and the trail being safe to attach to any caller error including
   the ones Ruby decorates. Measured with a real near-miss (`"".uppcase`); an earlier run with a
   name having no near neighbour produced no suggestion and would have licensed the opposite
   conclusion.
5. **A bare `raise error` assigns `$!` as that error's `#cause` when it has none, and `$!` is visible
   inside a method called from the caller's `rescue`.** Measured: the surfaced error came back
   carrying "the CALLER's unrelated in-flight error". `raise error, cause: nil` suppresses the
   assignment; it does **not** clear a pre-existing cause (measured: same object before and after);
   and it does not trip `ArgumentError: circular causes` even against a caller-defined cyclic
   `#cause` override. `raise error, cause: error.cause` behaves identically in every case measured.
   **Which errors it actually bites, measured on all three:** an error the `Failure` was handed
   **already constructed and never raised** — `RECOV-10`'s own named case, "a recovery step
   constructing the error and returning a Failure" — surfaces with `cause` = the caller's unrelated
   error under a bare `raise` and `nil` under `cause: nil`. An error a **step raised** acquired the
   caller's `$!` as its cause at the step's own `raise`, before core ever saw it, and `cause: nil`
   leaves that untouched, because it suppresses the assignment and does not clear a pre-existing
   cause. **What it licenses:** `raise error, cause: nil` as the one spelling for every `RECOV-10`
   unwrap, chosen over `cause: error.cause` because it invokes no caller-overridable method to do its
   job; and the `RECOV-10` test carrying a **constructed** error, since a step-raised one makes
   `assert_nil error.cause` fail against a correct implementation. **What it does not license:** a
   claim that core is otherwise safe — the hazard is the *caller's* `$!`, so it is present even where
   core writes no `rescue` at all — nor a claim that core can undo a cause a caller's own `raise`
   already assigned. It cannot, and does not try.
6. **`Exception#==` is structural and `#eql?`/`#hash` are not.** Two distinct un-raised errors of one
   class with one message are `==` on all three; two raised at the same source line are `==`; two
   raised at different lines are not. `#eql?` is false and the hashes differ. **What it licenses:**
   the `XCUT-9` visited set being identity-tracked, and the `RECOV-10` and `RECOV-12` assertions
   using `assert_same` rather than `assert_equal` — `assert_equal` would pass against an
   implementation that substituted a structurally identical error, which is exactly what "no
   substitution" forbids.
7. **`Array#include?` truncates a cause chain; `Set` is accidentally right and defeatable;
   `{}.compare_by_identity` is right — and the pair that shows it must be built the right way, or
   the demonstration silently disappears on the floor.** A two-node chain of `==`-equal errors yields
   **1** through an `Array`-tracked walk and **2** through an identity-tracked one. A `Set` gives the
   right answer for a plain exception and the **wrong** one (`Set[a].include?(b) == true`) for a
   caller class overriding `hash`/`eql?`; `compare_by_identity` gives the right answer for both, on
   all three. **The construction is load-bearing and the obvious one does not survive 3.2.** Chaining
   the pair by *raising* — raise the parent, then raise the child from the `rescue` so Ruby links
   them — makes them `==` on 3.4.10 and 4.0.6 and **not** `==` on 3.2.11, because 3.2's backtrace
   carries a `rescue in <method>` frame that the parent's does not and `Exception#==` compares the
   backtrace (fact 6). Measured on that construction: `Array`-tracked walk yields **2, 1, 1** across
   3.2.11 / 3.4.10 / 4.0.6 — the truncation is simply absent on the floor. The construction that
   *is* uniform is two **never-raised** instances, whose backtraces are both `nil` and which are
   therefore `==` on all three, chained by a caller-defined `#cause` override: measured `Array` **1**
   / identity **2** on all three, and with `hash`/`eql?` also overridden, `Set` **1** / identity
   **2** on all three. **What it licenses:** the container, the fact that core reaches for no
   `require`, and R7's third fixture being a never-raised `#cause`-override pair. **What it does not
   license:** a `raise`-built fixture — a suite written that way is green on 3.2.11 against an
   `Array`-tracked implementation, so the matrix's floor column would report a pass on the one bug
   the test exists to catch. **And it does not license** treating the `Set` result as a near-miss:
   `each_cause` walks caller-supplied errors by construction, so the defeating case is the expected
   one, not the exotic one.
8. **The cause cycle is reachable only through a caller-defined `#cause` override.** `raise y, cause:
   x` on a linked pair raises `ArgumentError: circular causes`; `raise s, cause: s` is accepted and
   leaves `s.cause` `nil`; `Exception#exception("m")` returns a **new** object with a `nil` cause
   while `#exception` with no argument returns `self`. `class Loopy < StandardError; def cause = self;
   end` self-cycles and a pair of objects each returning the other cycles two ways. All three.
   **What it licenses:** the shape of R7's test and nothing else — in particular it does **not**
   license concluding the guard is unnecessary, which is what testing the route §5.2 names would
   suggest. Confirms `docs/knowledge/notes/error-handling.md`'s existing entry.
9. **`NoMatchingPatternError` and `NoMatchingPatternKeyError` are inside `StandardError`; `LoadError`
   and `NotImplementedError` are `ScriptError`s; `Interrupt`, `SystemExit`, `SignalException`,
   `NoMemoryError` and `SystemStackError` are outside.** All three. **What it licenses:** R6's split
   — an exhaustiveness defect would be converted where a missing `require` would escape, which is
   backwards, and the fix is a named exclusion rather than a hierarchy change.
10. **An exception raised inside an `ensure` replaces the in-flight one and becomes its cause.**
    Measured: the primary is lost and reachable only through `#cause`. Rescuing narrowly *inside* the
    `ensure` body keeps the primary and yields the cleanup error as a value. **What it licenses:**
    `RECOV-12`'s close being written as a rescue inside the ensure body rather than as a bare close,
    and `attach_suppressed` being the disposal for what that rescue captures.
11. **The frozen replace-on-append trail works and needs no lifecycle.** `@t = [*@t, e].freeze`
    leaves the array frozen at every moment; a handle a caller took earlier stays a stable snapshot
    of that moment; `<<` on a returned trail raises `FrozenError`. All three. **What it licenses:**
    R5's answer that `#suppressed` is frozen from construction rather than at a first read or a first
    raise — both of which are lifecycles nothing can enforce and neither of which any requirement
    names.
12. **`Object#extend` on an already-extended object is a no-op** — the module appears once in the
    singleton ancestry after two calls — **and costs roughly four times a bare exception
    allocation**: 5 ms versus 22–27 ms per 50 000, spread across the three interpreters. **What it
    licenses:** doing the `is_a?` check for readability rather than for correctness, and not treating
    the cost as a reason to avoid the mechanism, since it is paid only on an error path. The absolute
    numbers are machine-dependent and are not a number a plan should assert.
13. **A concurrent read-modify-write on the trail loses writes on 3.2.11 and not on 3.4.10 or 4.0.6,
    and neither result is evidence of anything.** 8 threads × 250 attaches against one error object,
    five runs per interpreter: **3.2.11 lost 1 500–4 500 of 10 000 across runs, reproducibly**;
    3.4.10 and 4.0.6 lost **0**. It is therefore **not** the same GVL artefact 4a's verified fact 9
    records — that one holds on all three and this one does not, and the difference is scheduling,
    not safety. **What it licenses:** nothing, in either direction. The zero on the two newer
    interpreters is a scheduling accident and the loss on the floor is a demonstration, not a bug
    report: core makes **no** thread-safety claim for concurrent `attach_suppressed` on one error
    object. What carries the "no mutex" decision is the single-writer argument alone — the trail has
    exactly one writer by construction at every call site (`RECOV-12` unwinds on one thread,
    `RETRY-34` attaches on one, `Hooks.notify` drains one list on one) — and a per-exception mutex on
    a caller's object is not available anyway. Stated in the YARD, with the loss named, rather than
    measured away.
14. **`Data`-generated `deconstruct_keys` makes `case/in` over the two variants work**, including
    with `private_class_method :new`, and an unmatched value with no `else` raises
    `NoMatchingPatternError`. All three. **What it licenses:** §5.2's `case/in` fold verbatim, and
    the `else` arm having something real to convert.

## R5 — the suppressed trail's exact rendering, and what `DEF-32` costs phase 2's suite

Four sub-questions, four answers.

**`#full_message` is not overridden.** Ruby's own calls `#detailed_message` (verified fact 1), so
overriding `detailed_message` alone reaches both the explicit-call path and the default
uncaught-exception printer, while a second override would be a second copy of the same rendering with
two ways to drift. `NFR-4` permits adding one later; nothing needs it.

**The trail lives on `Dexpace::Suppressible`, not on `Dexpace::Error`, and that is forced.** Verified
fact 2: `rescue M` matches a module reached through a singleton class. Every primary
`RECOV-12`, `DEF-27` and `DEF-32` hand the helper is a caller's exception, so the helper must be able
to give a trail to an object whose class it does not control — and the only Ruby mechanism for that
is `Object#extend`. If the extended module were `Dexpace::Error`, a third-party `IOError` that
happened to be closed over during a failed close would start matching `rescue Dexpace::Error`, which
is phase 1's rescue root and a promise about *what the SDK raised*. Two modules, one relationship:

```
module Dexpace::Suppressible   # #suppressed, #detailed_message
module Dexpace::Error          # include Dexpace::Suppressible
```

Every SDK error gets the trail by inclusion and nothing else does by accident.

**For an error whose Ruby superclass is `::IOError`, the trail renders identically** — verified fact
1 ran `Dexpace::StreamError`'s exact shape (`class SE < ::IOError; include Trail; end`) and the
default printer produced the same two lines as for a `StandardError` subclass, on all three. There is
no `IOError`-specific `detailed_message` to compose with. Where composition *does* happen —
`NoMethodError`'s `did_you_mean`, `NameError`'s error-highlight — `super` preserves it (verified fact
4), which is why `super` is mandatory rather than stylistic and why the module's method body is
`suppressed.empty? ? super : "#{super}\n…"` and never a rendering that ignores what came before.

**`#suppressed` is frozen from construction, and neither "at first read" nor "at first raise" is the
answer.** Both are lifecycles nothing enforces: nothing in Ruby hooks a first read, `raise` is not a
hook core controls, and `RETRY-34` attaches a trail on terminal failure — after the point where an
error may already have been inspected. The design's phrase is "frozen once populated", and verified
fact 11 makes it literally true at every moment instead: the internal array is `[].freeze` at first
read and each attach **replaces** it with `[*trail, secondary].freeze`. A caller who took a handle
earlier holds a stable frozen snapshot, `<<` on a returned trail raises `FrozenError`, and
`api-design/c15b29ce`'s "every collection returned from a public method must be frozen" holds with no
per-read `dup`. **P4-14** records the departure from §5.2's wording, which suggests one array
transitioning from mutable to frozen.

### What `DEF-32` costs phase 2's suite

`DEF-32`'s pick-up condition is exact: "the change is confined to `Hooks.notify`: attach each later
failure to the first through `Dexpace.attach_suppressed`, then re-raise as now." 4b implements it as
written, and **phase 2's plan is unexecuted**, so what changes is text in committed documents rather
than a passing test — which is why this section names the tests anyway: the phase-2 plan is what will
be executed, and a task list that still describes the old behaviour will produce it.

Phase 2 names **three** `Hooks.notify` tests, one per call site:

| Test | File | What changes |
|---|---|---|
| `"one raising handler does not drop the handlers registered after it"` | `gems/dexpace-core/test/dexpace/cancellation_test.rb` | **Assertions unchanged.** One raising handler, so the trail is empty and `assert_raises(::IOError)` still names the same object |
| `"one raising settle callback does not drop the callbacks registered after it"` | `gems/dexpace-core/test/dexpace/async/completer_test.rb` | **Assertions unchanged**, same reason — `Completer#settle`'s site |
| `"a raising cancel hook still leaves the future settled and every waiter unblocked"` | `gems/dexpace-core/test/dexpace/async/completer_test.rb` | **Assertions unchanged**, same reason — `Completer#request_cancel`'s site |

**The honest answer to R5's fourth sub-question is therefore "none of the three, and that is the
finding."** Every one of phase 2's three cases raises from exactly **one** handler, so
`#suppressed` is empty and the observable behaviour is identical before and after. A design that
reported "test X changes" without checking would have been wrong, and a plan that assumed the three
would fail and then found them passing would have no signal that `DEF-32` had landed at all. What
`DEF-32` actually costs is:

1. **A fourth test, at one site**, asserting the new behaviour: three handlers, **two** of which
   raise, and the raised object carries the second failure on `Dexpace.suppressed(error)` in
   registration order. It goes in `cancellation_test.rb` beside the existing case, because
   `Source#cancel` is the site whose list a caller most obviously extends. It is the only test that
   distinguishes the old code from the new, and it is written first.
2. **The `#suppressed`-carrier assertion the existing three cannot make**: the failure phase 2's
   tests raise is a bare `::IOError`, which is not a `Dexpace::Error`. The fourth test therefore also
   asserts that the surfaced `::IOError` **is** a `Dexpace::Suppressible` afterwards and is **not** a
   `Dexpace::Error` — which is the P4-13 split asserted where it is first used rather than only where
   it is defined.
3. **Five prose corrections in committed phase-2 documents**, which 4b does **not** edit. Three say
   the failures after the first are dropped and become false the moment 4b lands: the YARD block in
   the plan's Task 4 step 3 ("The failures after the first are dropped until `#suppressed` exists to
   carry them; `DEF-32` records that"), the design's `Every handler runs, whatever an earlier one
   did` paragraph, and the plan's edge-case bullet "`Hooks.notify` re-raises the **first** handler
   failure and drops the rest." Two more name the wrong **carrier**, which is P4-12's finding rather
   than `DEF-32`'s and is therefore not anticipated anywhere: the phase-2 design's own `DEF-32`
   deferral row ("Phase 4, with `DEF-24`'s `Dexpace::Error#suppressed` — the first carrier a second
   failure can attach to") and the same clause in the plan's edge-case bullet, both of which name the
   one carrier that cannot work here, because the primary at this site is a bare `::IOError`. The
   register's own `DEF-32` and `DEF-27` rows carry the same clause and are the manager's to correct
   with the `picked-up` move. They are phase 2's documents, committed and reviewed, so 4b's **plan**
   carries a task that updates the shipped `hooks.rb` and `closeable.rb` comments it rewrites, and
   this finding goes to the manager rather than into an edit.
4. **No change to `Hooks`'s privacy, signature or call sites, and one change the row does not
   mention.** It stays a `private_constant` with `notify(hooks, argument)` and three callers. The
   body gains one line — `failure ? attach_suppressed(failure, error) : (failure = error)` — and its
   trailing `raise failure if failure` becomes **`raise failure, cause: nil if failure`**. This edit
   is not `DEF-32`'s, and its effect is **narrow — stated narrowly rather than sold as a bug fix**.
   `Hooks.notify` re-raises an error it has been *carrying* since an earlier iteration rather than
   one it just rescued, which is the shape verified fact 5 is about, and `$!` at that line is
   measurably the *caller's* in-flight exception whenever a hook list is drained from inside a
   `rescue` (measured on all three). But in the ordinary case the handler's error acquired that same
   cause at the **hook's own `raise`**, and `cause: nil` cannot clear a pre-existing cause, so the
   surfaced object is identical either way; the spelling changes the outcome only when the carried
   failure reaches `notify` with a `nil` cause — a hook that re-raises an object it was already
   holding, or one that raised with an explicit `cause: nil` (measured: a bare `raise` attaches the
   caller's error there, `cause: nil` leaves it `nil`, all three). The reason to make the edit anyway
   is not the size of the case: it is that `notify` must not be *the thing that adds* a cause, and
   that this design's own `pipeline` note claims a scope — "every `RECOV-10` unwrap **and every place
   core re-raises an error it is carrying rather than one it just rescued**" — that phase 2's site
   falls inside. It is the only such site outside 4b's own, and leaving it would make the note false
   on the day it was filed. `DEF-32`'s pick-up condition says "re-raise as now", which this honours:
   the object surfaced is the same object, and the only thing suppressed is an assignment `notify`
   would itself have been making.

`DEF-32`'s register row moves to `picked-up` with the date and the naming of the fourth test.

## R6 — where `RECOV-2`'s conversion boundary sits relative to the fold's own defects

**The decision: `Dexpace::OutcomeError` is a `StandardError`, and the orchestrator re-raises it by
name in the same arm that already re-raises the fatal family.**

`RECOV-2`'s Ruby rule is §5.2's: rescue `Exception`, immediately re-raise anything outside
`StandardError`, convert the rest. Verified fact 9 puts `NoMatchingPatternError` **inside**
`StandardError`, so the naive routing converts a core exhaustiveness defect into a `Failure`, feeds
it to the recovery steps — any of which may legitimately turn a `Failure` into a `Success` — and
surfaces it, if at all, as something a caller cannot tell from a step's own error. That is
`error-handling/3bfdf6f0`'s "never demote a programmer error to a handled operational error", and it
is the one place in 4b where the conforming-looking route is the wrong one.

Three options were weighed:

- **Convert it, like any other `StandardError`.** `RECOV-8`'s literal totality holds. Rejected: a
  recovery step that rescues broadly turns a core bug into a 200, and the caller has no way to
  distinguish it.
- **Put it outside `StandardError`** — a `ScriptError` or a bare `Exception` subclass — so
  `RECOV-2`'s existing arm re-raises it with no new clause. Rejected on two grounds:
  `error-handling/e43096c3` requires every failure to be a typed `StandardError` subclass, and
  `ScriptError` means "this file could not be loaded or is not implemented", which this is not.
  Borrowing a family for its rescue behaviour is exactly the kind of thing that makes a later
  `rescue ScriptError` mean two things.
- **Keep it a `StandardError` and name it in the re-raise arm.** Chosen.

The arm reads, in one place, once:

```ruby
rescue Dexpace::OutcomeError               # a defect in this code, not an outcome (R6)
  raise
rescue ::StandardError => error
  Dexpace::Outcome::Failure.build(error: error)
rescue ::Exception                          # RETRY-25: surfaced unchanged, no trail
  raise
end
```

**This is a deviation from `RECOV-8`'s "MUST NOT throw under any input" and it is exactly the
deviation the port already made for `RECOV-2`** — `pipeline/19516188` records the fatal-family
passthrough as "this port's own choice rather than a sanctioned one", justified because
`StandardError` is the boundary every Ruby application already codes against. `Dexpace::OutcomeError`
joins that family for the same reason: a value that is not an `Outcome` reaching a fold is not an
*input* in the sense `RECOV-1`'s closed sum type gives the word, and `RETRY-25`'s "surfaced unchanged
with no suppressed-trail attachment" points the same way. **P4-19.**

**Where the two `else` arms actually sit, because "the fold" is two different things.** `RECOV-1`'s
derivable fold is a method on each variant — `Success#fold` calls `on_success`, `Failure#fold` calls
`on_failure`, one branch at most once per call, and no pattern match is involved. The `case/in` with
the raising `else` is used only where a value **arrived from a caller-supplied step** and its type is
unproven, which is the only place exhaustiveness can fail. There are exactly two such places, and a
plan must not add a third: the recovery-step loop, which folds whatever a recovery step returned, and
the orchestrator's `RECOV-10` unwrap, which folds whatever the chain returned. A caller calling
`ResponseChain#apply` with a non-`Outcome` never reaches either: `#apply` validates its argument at
the public boundary and raises `Dexpace::InvalidArgumentError` in `SEAM-29`'s message form, which is
a caller mistake and not a fold defect.

### The rule for a lazily-loaded constant

Verified fact 9: `LoadError` and `NotImplementedError` are `ScriptError`s, so `RECOV-2`'s arm
**re-raises both and they escape the recovery chain entirely**. A step that lazily `require`s
something absent is not observed by any recovery hook — the defining invariant's one blind spot, and
it is the same shape as phase 2's registry finding, where a `LoadError` from a factory wedged the
registry.

The rule, stated once here so no site rediscovers it:

- **Core `require`s nothing lazily.** `lib/dexpace.rb` issues explicit requires for the whole tree
  (`CLAUDE.md`'s bundled-gem rule), so no core step can raise a `LoadError` at call time. This is
  already true and 4b keeps it true.
- **A caller-supplied step that lazily loads is documented as escaping**, in `RecoveryChain`'s and
  `Orchestrator`'s YARD blocks, with the reason and the remedy: load at construction, not at `#call`.
  A step author who wants a lazy dependency observed by the chain rescues its own `LoadError` and
  raises a `StandardError`.
- **`NotImplementedError` is named beside it**, because an adapter author writing `raise
  NotImplementedError` for an unimplemented method is the likelier of the two to be surprised, and
  its family membership is counter-intuitive enough that verified fact 9 exists to prove it.
- **One test asserts it rather than the documentation asserting it**: a request step raising
  `LoadError` surfaces to the caller as a `LoadError` and no recovery step observes it. That is the
  fatal-family passthrough proven for the case that will actually happen, rather than for
  `NoMemoryError`, which no test can raise honestly.

## R7 — the test that proves `each_cause`'s cycle guard

**The route the design names does not build a cycle**, and a 4b implementer who tests it gets
`ArgumentError: circular causes` and could reasonably conclude Ruby prevents cycles and drop the
guard (verified fact 8, and `docs/knowledge/notes/error-handling.md`'s existing entry). The cycle is
reachable through a caller-defined `#cause` override, which is precisely the shape core cannot
control, because `each_cause` walks caller-supplied errors by construction.

**Three tests, and each proves something the other two do not.**

1. **Termination on a self-cycle.** `class SelfCause < StandardError; def cause = self; end`.
   `Dexpace.each_cause(error).to_a.size == 1`, and the assertion is on the **count**, not on
   `assert_nothing_raised`, which `testing/26b866e1` forbids and which would pass against an infinite
   loop only by hanging the suite. The test-support class lives in
   `gems/dexpace-core/test/support/cyclic_errors.rb` beside the two-way pair.
2. **Termination on a two-node cycle.** Two objects each returning the other from `#cause`.
   `each_cause(p1)` yields exactly `[p1, p2]` — asserted by identity with `assert_same` on each
   element, which is where verified fact 6 bites: `assert_equal` on the array would pass against an
   implementation that yielded `[p1, p1]` if the two carried the same message.
3. **The `equal?`-not-`==` distinction, over two distinct errors carrying identical fields — and the
   fixture's construction is the whole test.** Two **never-raised** `StructurallyEqualError`
   instances carrying the same message, chained by the fixture's own `#cause` override, walked to
   completion: **two** yielded values, both distinct by `equal?`, while `a == b` is `true`. Verified
   fact 7 makes this a real discriminator and not a tautology — the same walk with an `Array`-tracked
   visited set yields **one** — but only for *this* construction. **The fixture must not build the
   pair by raising**, which is the shape a reader reaches for first: a raised pair is `==` on 3.4.10
   and 4.0.6 and **not** `==` on 3.2.11, whose backtrace carries a `rescue in <method>` frame the
   parent's lacks, so the `Array`-tracked walk yields 2 there and the test goes green on the matrix's
   floor against exactly the bug it exists to catch (verified fact 7). Two never-raised instances
   have `nil` backtraces and are `==` on all three, which is why the chain is built through `#cause`
   and not through `raise` — the same mechanism R7's first two tests already use for the cycles. A
   comment on the fixture says so, because "why is this not just `raise`d?" is the first question a
   reader will have.

**A fourth assertion the three do not cover, and it is the one the corpus does not predict.** A
caller-supplied error class that overrides `hash` and `eql?` structurally defeats a `Set`-tracked
visited set (verified fact 7), and a `Set` is what a reader will reach for once they know `==` is
wrong. So the third test's fixture class **overrides `hash` and `eql?`** as well as being `==`-equal,
which makes it a discriminator against `Set` *and* against `Array` in one case, and the comment says
so. Measured on the never-raised `#cause`-override pair: `Array` **1**, `Set` **1**,
`{}.compare_by_identity` **2**, on all three. The shipped container is `{}.compare_by_identity`.

**What none of the four proves.** Nothing here reaches a *third-party* classification that walks
`#cause` by hand; `XCUT-9` says "any classification", and core can only guarantee its own. Design
§5.2's "every classification in the port goes through it; none walks `#cause` by hand" is a
discipline, and phase 9's `XCUT-9` audit is what checks it repository-wide. Stated in
`each_cause`'s own YARD rather than papered over.

**`Dexpace.each_cause` yields the error itself first**, then each cause. `XCUT-9`'s consumers are
classifications — "is this retryable", "is this a cancellation" — and every one of them has to
inspect the error before its causes, so a walk that skipped the head would make every call site write
the same two-line preamble. Stated because the name reads the other way. **P4-16.**

## R8 — how the three shipped steps are single-sourced, stated as the contract 4c cites

**The problem, restated — and the charter's third shape corrected.** §5.1 asserts the three shipped
steps are "written once against the step protocol both layers share". There is no such protocol: a
pipeline step is `#call(request, cursor)`, a recovery **request** step is `request -> request`, and
the error-mapping step is a recovery **response** step, `response -> response`, which *raises* on an
error status. **The charter writes that third shape as `response -> outcome`, and it is
`response -> response`** — `RECOV-4`'s canonical text is parenthetically explicit ("response steps
(response→response)") and `RECOV-15` calls the mapping step "the status→typed-exception mapping
**response step**", which maps an error status "to the matching typed exception (which the pipeline
then turns into a Failure per `RECOV-7`)". `RECOV-7` converts a *throw*, so the step raises and
returns nothing; the `Outcome` never appears in its signature. The correction matters twice over: it
is what lets a transform whose `#apply` "returns a value of the type it was handed" be the
error-mapping step at all, and it is what stops 4c inheriting a contract obliged to express an
`Outcome` the `PIPE` layer must never see. It is recorded here rather than in a ledger row because it
corrects a *restatement* in the charter and not a requirement or a design chapter: `RECOV-4` states
the shape outright, and design §5.1's "the same object installs into a non-pillar stage of this
pipeline and into the recovery chain's request or **response** list" and §5.2's "response steps run
only on a `Success`" are both written against it.

**A fourth shape exists on this side and the charter does not name it:** a recovery **step** is
`outcome -> outcome` (`RECOV-5`, and `RECOV-13`'s "handed a Success and deliberately RETURNS a
different outcome"). It is not a transform and 4b ships none; it is named here so the three lists
below are not read as two. No single arity spans the four, and `pipeline/93ff85e7` states the
conclusion without stating the mechanism.

**The resolution: the shared thing is a pure transform, `#apply(value)`, and each layer reaches it
through one generic mechanism written once rather than once per step — the recovery chain through the
module's own forwarding `#call`, so no adapter exists on this side at all, and the stage pipeline
through 4c's single `#phase`-reading wrapper.**

### The contract

```
module Dexpace::Recovery::Transform
  # @return [Symbol] :request or :response — which phase this transform belongs to.
  def phase
  # @param value [Dexpace::Request, Dexpace::Response] per #phase
  # @return [Dexpace::Request, Dexpace::Response] the same type it was handed
  def apply(value)
  # The module's one default implementation: `def call(value) = apply(value)`.
  # It is what makes a transform a chain step with no adapter (clause 4).
  def call(value)
end
```

Five clauses, and they are the whole of it:

1. **`#apply` is the entire behaviour.** A transform reads nothing but its argument and its own
   frozen configuration, holds no per-call state (`RECOV-14`), performs no I/O, and returns a value
   of the type it was handed. It may raise; `ErrorMappingStep` does, by `RECOV-15`.
2. **`#phase` returns `:request` or `:response`, is constant per class**, and is what decides which
   adapter shape applies. It is read at composition time and never at call time — which is the same
   discipline `PIPE-15`'s fork gate follows (R10, 4c's), reached independently. **`#phase` never
   returns a value naming the recovery-step list**: a recovery step is `outcome -> outcome` and is
   not a transform.
3. **A chain step is a `#call`-able of one argument, and that is fixed here rather than left to the
   plan.** §5.1's "a lambda qualifies as a step" is as true of a recovery step as of a pipeline step,
   and every fold fixture below is a bare lambda, so the two chains invoke `step.call(value)` and
   nothing else. There are three step positions and three argument types, and mixing them is the
   mistake this clause exists to prevent: `RequestChain`'s steps are `Request -> Request`
   (`RECOV-3`), `ResponseChain`'s **response** steps are `Response -> Response` (`RECOV-4`), and its
   **recovery** steps are `Outcome -> Outcome` (`RECOV-5`, `RECOV-13`).
4. **A transform is therefore installed into a chain as itself, with no adapter and no `Method`
   object.** `Transform#call(value)` forwards to `#apply(value)`, so a `:request` transform is a
   `RequestChain` step and a `:response` transform is a `ResponseChain` **response** step, each by
   the ordinary `#call` protocol of clause 3. 4b installs them exactly that way and writes no
   adapter of its own. `#apply` stays the name the contract is about, because it is the name 4c's
   wrapper calls and the name that says "pure transform" where `#call` says only "callable".
5. **The stage pipeline wraps `#apply`, and the wrapper is 4c's, generic, and written once.** For a
   `:request` transform the wrapper is `cursor.call(transform.apply(request))`; for a `:response`
   transform it is `transform.apply(cursor.call(request))`. Which wrapper applies is read off
   `#phase`, not decided per step. The wrapper calls `#apply` and not `#call`, so a future default
   on `#call` cannot change what the pipeline does.

### What each side may and may not do

- **4b ships the three transforms and `Transform`. 4b ships no wrapper, names no cursor, and mentions
  no stage** — spec-forced boundary 1 forbids either layer expressing itself in terms of the other,
  and a `#call(request, cursor)` method on a `Dexpace::Recovery::` object would be exactly that.
  `Transform#call(value)` is **one** argument and is the recovery chain's own step protocol (clause
  3); the boundary is about the second parameter, which names the other layer, and not about the
  method name — `#call` is what §5.1 uses for a pipeline step and what phase 2's `Dexpace::Transport`
  duck type uses for a transport, and neither of those made either a bridge.
- **4c ships one generic adapter** — one class, whatever 4c names it — that turns any `Transform`
  into a `PIPE` step by reading `#phase`. 4c ships **no** second implementation of an idempotency
  key, a client-identity line or a status mapping, and does not subclass the three.
- **`PIPE-37` is the one placement rule that crosses**, and it is already spec-forced (boundary 5):
  the error-mapping transform, installed as a pipeline step, occupies the outermost pre-redirect slot
  and returns a non-error response **untouched — body not read, consumed, or closed**. That clause is
  4c's to honour and 4b's to make honourable: `ErrorMappingStep#apply` returns its argument by
  identity on a non-error status, which the test asserts with `assert_same` and with an assertion
  that the body's `#source` was never called.
- **Neither may add a third phase.** If a later requirement needs a transform over something that is
  neither a request nor a response, it is a new `P4`-numbered deviation and a change to this
  contract, not a quiet third `#phase` value.

**Why a `Transform` is a module rather than a duck type with no name.** `NFR-11`'s RBS scan wants a
named type in the public signature 4c will write, and `#phase` needs somewhere to be documented once
rather than three times. `api-design/88e6bf12`'s narrowest-duck-type rule is satisfied by the two a
caller must write — `#phase` and `#apply` — and the third, `#call`, is the module's **one** default
implementation rather than a third obligation, which is what buys clause 4: without it a transform
would reach a chain only through an adapter or a `Method` object, and "4b writes no adapter" would be
false. That single default is the departure from 4a's `Dexpace::Context` and phase 1's
`Dexpace::Error`, both of which only declare, and it is stated rather than absorbed.

## R9 — `Dexpace::Recovery`'s namespace, and the constant it must not declare

**Two namespaces, both the design's own, and the error primitives flat.**

- **`Dexpace::Outcome` is flat and is not inside `Recovery`.** §5.2 writes
  `Dexpace::Outcome::Success = Data.define(:response)` and `Dexpace::Outcome::Failure =
  Data.define(:error)` — those are the design's own constant paths, and P1-1's rule is "flat unless
  the design namespaced it", which it did, at `Outcome` and not at `Recovery::Outcome`. It is also
  the right answer independently: `SSE-33`–`SSE-36` reuse the same type "with a third variant in that
  namespace" (`pipeline/97624a72`), and phase 7's SSE adapter has nothing to do with the recovery
  chain, so an `Outcome` reachable only through `Recovery` would make the reuse read as a
  layering violation it is not.
- **`Dexpace::Recovery` holds the chains, the orchestrator, the three transforms, the `Transform`
  contract and `buffer_error_body`.** §5.1 names `Dexpace::Recovery.buffer_error_body(response)`, so
  the namespace is the design's; everything §8.2 describes and `Outcome` does not is inside it. That
  keeps the layer's own boundary visible in the constant path, which spec-forced boundary 1 is about.
- **The error primitives are flat**, because they are not the recovery layer's: `Dexpace::Error` is
  phase 1's, `Dexpace::Suppressible` is its sibling, and `Dexpace.attach_suppressed`,
  `Dexpace.suppressed` and `Dexpace.each_cause` are named flat by §5.2 itself. `XCUT-9`'s consumers
  are `RETRY`, `REDIR`, `AUTH`, `PAGE` and `SSE`, none of which is a recovery chain.
- **`Dexpace::OutcomeError` is flat, beside the `Outcome` it names**, and `Dexpace::ProtocolError` is
  flat, because `XCUT-4`'s taxonomy is repository-wide and its sibling `Dexpace::TransportError`
  lands flat in phase 8. Putting either inside `Recovery` would make phase 8's branch and phase 4's
  branch of one taxonomy live in two different namespaces.

**The constant 4b must not declare, stated as a negative that is checked.**
`Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` is phase 3b's and there is **no second copy anywhere
in 4b** — no local constant, no default argument spelling out `1024 * 1024`, no `cap:` keyword on
`Recovery.buffer_error_body`. Spec-forced boundary 10 and phase 3b's addendum B2 both say so, and
`RECOV-16`'s "the same bound MUST be shared across all error-body-buffering paths" is what makes it a
requirement rather than tidiness. `Recovery.buffer_error_body` reads the constant and calls
`Body.buffer_bounded(body, cap: Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES)`. The test asserts the
truncation boundary through the constant rather than through a literal, so a second constant would
not merely be redundant — it would be the thing the assertion is written against.

## Module layout

Every file 4b creates or modifies, under `gems/dexpace-core/`. `sig/` mirrors `lib/` one file per
file and ships inside the gem; `test/` mirrors `lib/` one file per file and does not ship.

```
lib/dexpace.rb                                    MODIFIED: explicit requires for the tree below
lib/dexpace/suppressible.rb                       Dexpace::Suppressible, Dexpace.attach_suppressed,
                                                  Dexpace.suppressed
lib/dexpace/error.rb                              MODIFIED: include Dexpace::Suppressible
lib/dexpace/each_cause.rb                         Dexpace.each_cause
lib/dexpace/error/outcome_error.rb                Dexpace::OutcomeError
lib/dexpace/error/protocol_error.rb               Dexpace::ProtocolError
lib/dexpace/outcome.rb                            Dexpace::Outcome                        (module)
lib/dexpace/outcome/success.rb                    Dexpace::Outcome::Success
lib/dexpace/outcome/failure.rb                    Dexpace::Outcome::Failure
lib/dexpace/recovery.rb                           Dexpace::Recovery, .buffer_error_body
lib/dexpace/recovery/transform.rb                 Dexpace::Recovery::Transform            (module)
lib/dexpace/recovery/ownership.rb                 Dexpace::Recovery::Ownership   (private_constant)
lib/dexpace/recovery/request_chain.rb             Dexpace::Recovery::RequestChain
lib/dexpace/recovery/response_chain.rb            Dexpace::Recovery::ResponseChain
lib/dexpace/recovery/orchestrator.rb              Dexpace::Recovery::Orchestrator
lib/dexpace/recovery/idempotency_key_step.rb      Dexpace::Recovery::IdempotencyKeyStep
lib/dexpace/recovery/client_identity_step.rb      Dexpace::Recovery::ClientIdentityStep
lib/dexpace/recovery/error_mapping_step.rb        Dexpace::Recovery::ErrorMappingStep
lib/dexpace/hooks.rb                              MODIFIED: DEF-32, two lines plus their comment
lib/dexpace/closeable.rb                          MODIFIED: DEF-27, Dexpace.close_quietly(onto:)

test/support/fake_transport.rb                    the two fakes, required explicitly
test/support/cyclic_errors.rb                     R7's three fixture classes
```

**Sixteen** new `lib/` files, **fifteen** `sig/` mirrors and **fifteen** `test/` mirrors —
`recovery/ownership.rb` is a `private_constant` and gets neither, per P2-15, and its behaviour is
asserted at its call sites, which is the treatment phase 2 gave `Dexpace::Hooks` and 4a gave
`BoundedMap`. Two test-support files. **Nine** already-existing files gain content, counted rather
than described: `lib/dexpace.rb` and `sig/dexpace.rbs` (requires and declarations for the tree);
`lib/dexpace/error.rb` (one `include` line) and `sig/dexpace/error.rbs` (the same); the
repository-root `test/fixtures/surface/dexpace-core.txt`; and the two behaviour changes,
`lib/dexpace/hooks.rb` (`DEF-32`) and `lib/dexpace/closeable.rb` (`DEF-27`), each with its own
test-file delta — `test/dexpace/cancellation_test.rb` and `test/dexpace/closeable_test.rb`.

**`lib/dexpace.rb`'s require order is load-bearing here for the first time.** `Dexpace::Error`
includes `Dexpace::Suppressible`, and there is no autoloader (`CLAUDE.md`'s bundled-gem rule), so
`suppressible.rb` must be required **before** `error.rb` or the `include` raises `NameError` at load.
That is the same ordering constraint phase 2 recorded for `hooks` preceding `cancellation/source`
and `async/completer`, and it is the one line of `lib/dexpace.rb` a reordering would break silently
in every consumer at once.

**The placement rule is phase 1's and is applied, not re-decided** (P1-1,
`module-organization/6e69ad04`): a public constant the design names without a namespace is flat and
its file sits under a directory that organises rather than namespaces, so `Dexpace::OutcomeError` and
`Dexpace::ProtocolError` join `lib/dexpace/error/`. A subsystem the design already names with a
namespace keeps it, so `Outcome` and `Recovery` are directories that genuinely namespace.

**`suppressible.rb` defines one module and two module functions**, which is
`module-organization/1828a984`'s shape and phase 2's precedent for `closeable.rb` holding
`Dexpace::Closeable` and `Dexpace.close_quietly`: the helper and the contract it serves live
together, and splitting a four-line function into its own file to satisfy a one-constant-per-file
reading buys nothing. `each_cause.rb` is separate because it serves `XCUT-9` and not the trail, and
its only relationship to `Suppressible` is that the trail is walked with it.

## The object model 4b ships

Every public constant, its surface, and the IDs forcing that shape.

### `Dexpace::Suppressible` — the trail (`DEF-24`, `RECOV-12`, `RETRY-34`)

A module. Two public methods and no state of its own beyond one namespaced ivar,
`@dexpace_suppressed`, following `Closeable`'s `@dexpace_closed` precedent — the ivar lands on a
caller's exception object under `extend`, so the name has to be one no application would pick.

- **`#suppressed -> Array`** — the frozen trail, `[]` when empty. Never the internal array under a
  different name: there is no internal mutable array (verified fact 11).
- **`#detailed_message(**kwargs) -> String`** — `super` when the trail is empty, otherwise `super`
  plus one indented line per suppressed error naming its class and message. `**kwargs` is forwarded
  to `super` verbatim; verified fact 1 shows Ruby passes `highlight:` and `order:`, and a signature
  that named them would break the day Ruby adds a third.

**No `#full_message` override** (R5). **No `#suppress`, no `#add_suppressed`, no writer at all** —
the only way in is `Dexpace.attach_suppressed`, which is what keeps the self-guard `RETRY-34`
requires in one place and unavoidable.

### `Dexpace::Error` — modified (phase 1's module)

`include Dexpace::Suppressible`, and nothing else changes. `rescue Dexpace::Error` keeps meaning
"the SDK raised this", which is the promise P1-2 made and which R5's split protects.

### `Dexpace.attach_suppressed(primary, secondary) -> primary`

- Returns `primary` always, so it composes inside an `ensure` or a `rescue` without a temporary.
- **Skips self** when `primary.equal?(secondary)` — `RETRY-34`'s guard, by identity and never by
  `==`, because verified fact 6 makes two structurally identical errors `==` and suppressing a
  *different* error that happens to match would be a silent loss.
- **`extend`s `primary` with `Suppressible`** when it is not already one, then replaces the frozen
  trail. Verified facts 2 and 12.
- **Rescues `FrozenError` into a documented no-op** and returns `primary` unchanged (verified fact
  3). The single-class swallow with a why-comment `error-handling/a86bc536` sanctions; the reason is
  that raising here would mask the primary, which is the failure `RECOV-12` exists to prevent.
- **Raises `Dexpace::InvalidArgumentError` when either argument is not an `Exception`** — a caller
  mistake, `error-handling/ffdf6f4f`'s discipline, and unreachable from core's own three call sites,
  which all pass a rescued object.
- **No mutex**, and the reason is the single-writer-by-construction argument and **not** verified
  fact 13, which licenses nothing: a concurrent read-modify-write on one error's trail does lose
  writes on 3.2.11. Stated in the YARD, loss included, so a consumer that invents a second writer
  knows what it is buying.

### `Dexpace.suppressed(error) -> Array`

The frozen trail of anything, `[]` for an error that carries none. It exists because
`RECOV-10` rethrows a caller's error unchanged, so a consumer reading a trail off a surfaced error
cannot know whether it is `Suppressible` — and because verified fact 1's limit is real: a logger that
formats an exception itself sees neither override, and this is how it gets the trail. **P4-15.**

### `Dexpace.each_cause(error) { |e| … } -> nil`, or `-> Enumerator` with no block

`XCUT-9`. Yields the error itself first, then each `#cause` transitively (P4-16), tracking visited
objects in a `Hash` built with `#compare_by_identity` (R7, verified fact 7). Returning an
`Enumerator` when no block is given is safe here specifically — the walk acquires no resource, so
`pagination/b2a85752`'s abandoned-`ensure` hazard has nothing to leak — and it is what lets a
classification write `each_cause(e).any? { … }`, which is how §6.1's retryability walk will read.
`#cause` is called on caller-supplied objects and may raise or lie; the walk treats a raise from
`#cause` as the end of the chain rather than propagating it, because a classification must not be
the thing that fails.

### `Dexpace::Outcome` — the module the two variants share (`RECOV-1`)

Following 4a's P4-1 reading of "sharing a module": a module the two **include**, so
`outcome.is_a?(Dexpace::Outcome)` is the one type test the chains and the RBS union need.
`Dexpace::Outcome` declares no factory; there is exactly one way to build each variant.

### `Dexpace::Outcome::Success` and `::Failure` — `RECOV-1`

`Data.define(:response)` and `Data.define(:error)` — §5.2's own spelling — each including
`Dexpace::Model` and `Dexpace::Outcome`, each with `private_class_method :new` and a validating
`.build(response:)` / `.build(error:)` (phase 1's rule, P2-9's exemption not applying because both
are public API).

`RECOV-1` enumerates the derivable surface and 4b ships exactly it, on both:

| Method | `Success` | `Failure` | `RECOV-1`'s words |
|---|---|---|---|
| `#success?` | `true` | `false` | "is-success" |
| `#failure?` | `false` | `true` | "is-failure" |
| `#response_or_nil` | the response | `nil` | "response-or-null" |
| `#error_or_nil` | `nil` | the error | "error-or-null" |
| `#fold(on_success:, on_failure:)` | calls `on_success` with the response | calls `on_failure` with the error | "a fold that applies exactly one of two branch functions … at most once per call" |

`#response_or_nil` and `#error_or_nil` return `nil` against `api-design/6ea28c9c`'s
never-`nil`-for-absent rule, and that is the requirement's own words rather than a choice — the same
documented case `CTX-18` reserved for 4a. **P4-21.** `#fold`'s "at most once" is structural: each
variant's implementation calls one lambda once and returns its value; there is no loop and no retry,
so the property is asserted rather than defended.

`Failure.build(error:)` **validates that `error` is an `Exception`**. Nothing else in the model would
catch a `Failure` carrying a string, and `RECOV-10` would then `raise` it into a `TypeError` at the
one point the caller is furthest from the cause.

### `Dexpace::OutcomeError` — R6's named internal error

`< ::StandardError`, `include Dexpace::Error`, carrying `#offending_class` (a `Module`) and a message
naming it. Not the value (see the audit-group note above). It is what every `case/in` `else` arm
raises and what the orchestrator re-raises by name.

### `Dexpace::ProtocolError` — `XCUT-4` branch (a), `RECOV-15`

`< ::StandardError`, `include Dexpace::Error`, carrying `#response` and `#status`, with a message
naming the status code and its canonical name where `Status.canonical_name` has one. It is
`RECOV-15`'s "matching typed exception" and the object a `Failure` carries after the error-mapping
step.

**There is no per-status subclass tree, and that is P4-20.** `XCUT-4` requires exactly **two**
top-level branches and describes no third level; `XCUT-7` decides retry eligibility from a
*configured status set* and never from a class; `error-handling/5da8cb17` admits a new subclass only
when callers must distinguish it for different handling; and `error-handling/61ab4fb6` caps a
hierarchy at two levels. A caller distinguishes a 404 from a 429 by reading `#status`, which is the
same object phase 1 already made comparable. A generated SDK that wants `UserNotFoundError` supplies
its own factory (below) rather than subclassing ours.

**`ProtocolError.for(response) -> ProtocolError`** raises `Dexpace::InvalidArgumentError` for a
non-error status — `XCUT-8`'s first clause, and an argument error is what that clause names.
**`ProtocolError.for_or_nil(response) -> ProtocolError?`** returns `nil` instead — `XCUT-8`'s
sanctioned convenience form, shipped because `ErrorMappingStep` needs exactly that shape and would
otherwise write a status check its own `RECOV-15` predicate already performed.

**No `#retryable?`.** `XCUT-5` requires the baked flag to come from "a SINGLE shared status
classifier", and that classifier is `RETRY-1`'s and phase 6's; building one here would fix a phase-6
seam a phase early, which is the charter's own test and the reason `RECOV-27` moved. `DEF-38`. Adding
a predicate later widens a signature, which `NFR-4` permits.

### `Dexpace::Recovery.buffer_error_body(response) -> Response` — `RECOV-16`, `BODY-30`

Phase 3b fixed the contract and 4b implements it without re-deciding: returns the response unchanged
when `status.error?` is false **or the body is `nil`**; otherwise calls
`Body.buffer_bounded(body, cap: Body::MAX_BUFFERED_ERROR_BODY_BYTES)` and returns
`response.with(body: buffered)`. The original body's close happens inside `buffer_bounded`'s
`ensure`, unguarded, which is `BODY-30`'s close-guaranteeing scope and, here, `RECOV-13`'s ownership
discharge.

### `Dexpace::Recovery::Transform` — R8's contract

`#phase` and `#apply(value)` declared and not implemented, plus `#call(value)` as the module's one
default implementation, forwarding to `#apply`. The three shipped steps include it. `#call` is what
makes a transform a chain step under R8's clause 3 with no adapter and no `Method` object; it is one
argument and is the recovery chain's protocol, not the pipeline's two-argument `#call(request,
cursor)` (boundary 1). **P4-25.**

### `Dexpace::Recovery::IdempotencyKeyStep` — `RECOV-32`

`.build(header:, strategy:, methods: [Method::POST, Method::PUT, Method::PATCH], mode: :respect_existing)`.
`#phase` is `:request`.

- Adds the header **only** for a method in `methods`; every other method passes through **by
  identity**, asserted with `assert_same`.
- In `:respect_existing` (the default) a request already carrying the header is returned by identity
  **and `strategy` is not called at all** — §5.1's own emphasis, and the assertion is on a strategy
  double's call count being zero, because "burns a key per redirect hop" is invisible to a test that
  only checks the header.
- In `:overwrite` the strategy's result replaces every existing value (`Headers::Builder#set`).
- **The strategy is invoked at most once per applicable request** — `RECOV-32`'s last clause, and the
  test counts calls rather than inspecting the result.
- `strategy` is a duck type over `#call(request) -> String`; core ships no default, because a default
  would have to mint a UUID and `securerandom`'s allowlist entry is not a licence to pick a caller's
  key format.

### `Dexpace::Recovery::ClientIdentityStep` — `RECOV-33`

`.build(header:, tokens:, mode: :append)`. `#phase` is `:request`.

- Joins `tokens` into one space-separated line.
- `:append` (default) appends the line after the **first** existing value, preserving every other
  value; sets it as the sole value when the header is absent. `:replace` overwrites all values.
- **An empty token list, or one joining to a blank or whitespace-only line, makes the step a no-op**
  and it must not emit a blank header — the request is returned by identity.
- **In `:append` mode an empty first existing value is treated as absent**, so no leading space is
  emitted. That clause and the previous one are `RECOV-33`'s two easy-to-miss halves and each gets
  its own test.

### `Dexpace::Recovery::ErrorMappingStep` — `RECOV-15`, `RECOV-16`, `XCUT-8`

`.build(factory: Dexpace::ProtocolError.method(:for))`. `#phase` is `:response`.

- **Only 400..599 are errors** (`Status#error?`, phase 1's, no second predicate). A 1xx, 2xx or 3xx
  response is returned **by identity**, body not read, consumed or closed — `PIPE-37`'s parenthesised
  clause, asserted by `assert_same` plus an assertion that `#source` was never called on the body.
- On an error status it calls `Recovery.buffer_error_body` **first** (`RECOV-16`'s "before mapping"),
  then `factory` on the buffered response, then raises the result. `RECOV-7` converts the raise into
  a `Failure`.
- **`factory:` defaults to core's own and is a keyword**, so a generated SDK substitutes its typed
  errors without a second step. §5.1's word is "delegates to"; `XCUT-8`'s definite article is what
  makes the default core's rather than absent.
- **`RECOV-13` is discharged by the buffering, not by a separate close.** The step drops the original
  response and `buffer_bounded`'s `ensure` released it. Two cases need no release at all: a non-error
  status is not dropped, and a `nil` body has nothing to release.
- **`RECOV-12` then closes the response the chain was holding, and that is a second close of an
  already-closed body.** It is a no-op by `Closeable`'s latch, which is what makes `RECOV-12`'s
  "exactly once" structural — the latch calls `#release` once and the second `#close` releases
  nothing, which is the only rule 4b relies on here. The test asserts the
  body's release count is 1 across the whole path — the only assertion that would catch a chain that
  started bookkeeping instead.

### `Dexpace::Recovery::RequestChain` — `RECOV-3`, `RECOV-14`

A class (`data-modeling/3e37c086`: it owns state). `.build(steps: [])`, `#apply(request) -> Request`,
`#steps -> Array` (frozen).

- **Left-to-right fold**; the output of step N is the input of step N+1. `Array#reduce`, never
  `Enumerator#next` (the charter's cross-cutting constraint 5).
- **An empty chain returns the input unchanged**, by identity, asserted with `assert_same`.
- **A throwing step aborts the remainder and propagates** — this chain is *not* total, and that is
  `RECOV-3`'s own text; the orchestrator converts per `RECOV-2`. The test asserts both halves: the
  raise reaches the caller **and** the steps after the thrower were not invoked.
- **The list is copied and frozen at construction** — `RECOV-14`'s SHOULD, resolved toward the
  stricter behaviour, which §5.2 records as one of four reference inconsistencies this port resolves
  uniformly (`pipeline/28f79ca2`, `/dae7b50b`, `/46c4887f`). The test mutates the caller's array
  after construction and asserts the chain is unaffected.
- **`#steps` returns the frozen copy itself**, not a per-call snapshot — `HTTP-5`'s second tier,
  which applies because the collection is genuinely immutable.

### `Dexpace::Recovery::ResponseChain` — `RECOV-4`–`RECOV-8`, `RECOV-12`–`RECOV-14`

`.build(response_steps: [], recovery_steps: [])`, `#apply(outcome) -> Outcome`, `#response_steps`,
`#recovery_steps`.

- **Fold order is all response steps first, then all recovery steps, in declared order within each
  group** (`RECOV-6`). One method, two loops, no interleaving.
- **The two loops fold different types, and that is `RECOV-4`'s own parenthesis.** A response step is
  `Response -> Response`: the loop unwraps the `Success`, folds `step.call(response)` left to right,
  and rewraps the result with `Outcome::Success.build(response:)`. A recovery step is
  `Outcome -> Outcome` and is handed the outcome itself. A response step therefore **cannot** return
  a `Failure` or a substitute `Success` — only a recovery step can, which is where `RECOV-13`'s
  "handed a Success and deliberately RETURNS a different outcome" lands. Getting this backwards is
  the one modelling mistake that would make R8's transform contract unable to express the
  error-mapping step, so it is fixed here and typed in `sig/` (three proc types, below).
- **Response steps run only on a `Success`** (`RECOV-4`); on a `Failure` the entire response phase is
  skipped and the failure passes through untouched.
- **Recovery steps run on every outcome, always**, including a failure a response step just produced
  by throwing (`RECOV-5`) — the test builds exactly that sequence, because a suite that only feeds a
  transport failure never exercises the clause.
- **A throwing response step's error becomes a `Failure` fed to the recovery steps** (`RECOV-7`), and
  **a throwing recovery step's error is wrapped into a `Failure` fed to the *next* recovery step**
  (`RECOV-8`) — never aborting the remainder. Both rescues go through `Ownership`.
- **`#apply` does not raise** for any `Outcome` input and any step behaviour within `StandardError`
  (`RECOV-8`), with **three** stated exceptions and not two: the fatal family, `Dexpace::OutcomeError`
  (R6, P4-19), and a non-`Outcome` argument, which raises `Dexpace::InvalidArgumentError` at the
  boundary before any fold runs. The third is an *input* and `RECOV-8`'s words are "under any input",
  so it is counted rather than excused — P4-19 carries all three.
- **Both lists are copied and frozen at construction** (`RECOV-14`, explicit MUST for this chain).

### `Dexpace::Recovery::Ownership` — `RECOV-12`, `RECOV-13`, `private_constant`

One function, `Ownership.close_on_throw(outcome) { … } -> Outcome`, and the name states the
asymmetry: it closes on a throw and does not close on a return.

```
on a raise, with a Success in hand:  close the response, attaching any close error
                                     as suppressed to the raised one, then return
                                     Outcome::Failure.build(error: raised)
on a raise, with a Failure in hand:  return Outcome::Failure.build(error: raised)   (nothing to close)
on a normal return:                  return the block's value untouched             (RECOV-13)
```

**The block returns an `Outcome`, in both loops, and the caller is what makes that true.** The helper
takes the outcome in hand — it needs it to know whether there is a response to close — and the block
takes no argument, because the two loops feed their steps different types (above): the response-step
loop's block is `Outcome::Success.build(response: step.call(outcome.response))` and the
recovery-step loop's block is `step.call(outcome)`. Keeping the rewrap on the caller's side is what
lets one helper serve both without a mode flag and without the `-> Outcome` return type being a lie
on one of the two paths.

§5.2 requires "one shared helper so the asymmetry lives in one place", and this is that place: every
step invocation in `ResponseChain` goes through it and no other code in 4b closes a response.
`RECOV-13`'s half is the **absence** of a close on the normal path, which is why the helper is named
for the throw path and why the test that proves `RECOV-13` asserts a release count of **zero** after
a deliberate `Success`→`Failure` transform performed by a **recovery** step — the only step position
that can perform one.

The close is written as a rescue **inside** the ensure-shaped region, never as a bare close (verified
fact 10, `error-handling/5e2aa68b`): an exception escaping there replaces the primary and the primary
survives only as a `#cause`, which is the masking `RECOV-12` forbids in its own sentence.

### `Dexpace::Recovery::Orchestrator` — `RECOV-2`, `RECOV-10`, `RECOV-11`

`.build(transport:, request_chain:, response_chain:)`, `#call(request, options, cancellation)`.

- **It is itself a `Dexpace::Transport`** by phase 2's duck type, which costs nothing and is what
  lets a recovery-aware stack nest. It is *not* a `PIPE` runtime and knows nothing about one.
- **`RECOV-2`**: the request chain, the transport invocation and the response chain all run inside
  one `rescue Exception` region with R6's three arms. A **before-request throw does not skip
  after-error handling** — the converted `Failure` is threaded through the response chain, and the
  test drives exactly that, because a suite that only throws from the transport never proves the
  defining invariant.
- **`RECOV-10`**: unwrap by the `case/in` fold with R6's raising `else` — the chain is reached
  through an `#apply` duck type, so its return value is unproven and this is the second of R6's two
  unproven-value sites. On `Success` return the response; on `Failure`
  `raise error, cause: nil` (verified fact 5). The test asserts the surfaced object is `assert_same`
  the one the `Failure` carried **and** that its `#cause` is unchanged while an unrelated exception
  is in flight — the negative assertion the corpus note exists to make someone write.
- **`RECOV-11`**: nothing to do, asserted rather than implemented (P4-17). A `Dexpace::CancelledError`
  is converted to a `Failure` like any other `StandardError`; the token the caller passed still
  answers `cancelled?` afterwards, because phase 2's `Source#cancel` is idempotent and latched and no
  code path anywhere clears it. The test asserts the token is still cancelled after the fold and
  after `RECOV-10` rethrows, which is the property the requirement is actually about. A `::Interrupt`
  is outside `StandardError` and is re-raised unconverted, which preserves it maximally and is worth
  one line in the YARD.
- **Ruby's `throw`/`catch` is not used anywhere in core** (`pipeline/3dc6dae0`), so no step escapes
  through it. Stated, not tested: there is nothing to assert about an absence of a construct except
  through a lint, and no requirement asks for one.

### The RBS interfaces

`interface _Transform` mirrors `Dexpace::Recovery::Transform`'s three methods — `#phase`, `#apply`
and `#call` — so 4c's adapter has a type to name.

**Three step lists, three proc types, and the third is the one a reader will drop.** R8's clause 3
fixes three argument types and `sig/` carries all three:

| List | RBS type | Requirement |
|---|---|---|
| `RequestChain#steps` | `Array[^(Dexpace::Request) -> Dexpace::Request]` | `RECOV-3` |
| `ResponseChain#response_steps` | `Array[^(Dexpace::Response) -> Dexpace::Response]` | `RECOV-4` ("response steps (response→response)") |
| `ResponseChain#recovery_steps` | `Array[^(Dexpace::Outcome) -> Dexpace::Outcome]` | `RECOV-5`, `RECOV-13` |

They are proc types, because §5.1's "a lambda qualifies as a step" is as true of a recovery step as
of a pipeline step and a nominal interface would exclude one; a `Transform` type-checks against the
first two through `#call`, which is why the module carries that default (R8, clause 4). Typing the
response-step list as `Outcome -> Outcome` is the error this table exists to prevent: it would let
Steep accept a response step that returns a `Failure`, which is a **recovery** step's privilege and
is what `RECOV-4`'s parenthesis forbids. `Dexpace::Outcome` is the union's name and is what Steep
checks at every fold site (§9, and design §5.2's second half of the exhaustiveness argument).

## The spec-forced boundaries, honoured

Seven of the charter's sixteen bind 4b; each is honoured by a named mechanism.

- **Boundary 1 — §8.3's two-layer prohibition.** 4b names no stage, no cursor, no pillar and no
  `PIPE` constant anywhere in `lib/` or `sig/`. R8's contract is the one thing that crosses and it
  crosses as a *transform* — `#apply(value)`, a pure function of one value — which is neither layer's
  invocation shape. `Transform#call(value)` is the **recovery** chain's one-argument step protocol
  and not the pipeline's `#call(request, cursor)`; the prohibition is about a layer expressing itself
  in the other's terms, and no `Dexpace::Recovery::` object takes a cursor. `RECOV-32`/`RECOV-33`
  being steps two layers can both hold does not make them a bridge, exactly as the boundary says.
- **Boundary 6 — `RECOV-1`'s closed two-variant outcome and `RECOV-6`'s fold order.** Two variants, no third;
  response steps first on the success path, then recovery steps, in declared order within each
  group; response steps on `Success` only; recovery steps on every outcome, always. §7's SSE third
  variant is phase 7's and lives in that namespace (`pipeline/97624a72`).
- **Boundary 7 — `RECOV-8`'s totality.** Held over `StandardError`, with the fatal family and
  `Dexpace::OutcomeError` as stated exceptions (R6, P4-19). The boundary's warning that it
  "constrains 4b's own internal error handling, not only its treatment of a step's error" is why
  `Ownership` rescues its own close and why `attach_suppressed` rescues `FrozenError`: neither may
  be the thing that raises.
- **Boundary 8 — `RECOV-12`/`RECOV-13`'s ownership asymmetry, and the single helper.**
  `Recovery::Ownership.close_on_throw`, and 4b implements them nowhere else.
- **Boundary 9 — `RECOV-14`'s uniform defensive copy.** Both chains copy and freeze both lists at
  construction, which resolves the reference asymmetry toward the stricter behaviour through one
  shared construction step in each class.
- **Boundary 10 — `RECOV-16`'s one bound, and where the constant lives.**
  `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` is read and no second constant exists (R9).
- **Boundary 5 — `PIPE-37`'s placement rule.** 4b makes it honourable and 4c honours it:
  `ErrorMappingStep#apply` returns a non-error response by identity, body not read, consumed or
  closed, which is the half a placement test alone would not catch.

Boundaries 2, 3, 4, 11, 12, 13, 14, 15 and 16 are 4a's or 4c's and 4b touches none of them.

## Cross-cutting constraints that bite 4b specifically

1. **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden**, enforced by phase 0's
   `Dexpace/NoThreadInterrupt`. 4b has no wait, no timer and no thread, so the cop has nothing to
   bite on — and it is named because `RECOV-27`'s cancellable inter-attempt wait is the one place in
   the `RECOV` prefix where a phase in a hurry would reach for one. That ID is `DEF-35`'s and phase
   6's, and 4b builds no wait of any kind, cancellable or otherwise.
2. **Deadlines are explicit values, never ambient interrupts.** 4b has no deadline and no clock;
   `RECOV-20`'s total-timeout budget travels with `DEF-35`.
3. **`Thread::Mutex` is per-fiber-owned and non-reentrant.** 4b holds no mutex, because it owns no
   mutable shared state: a built chain is frozen lists, an orchestrator is three frozen references,
   and per-call state lives in the value being transformed, which is `RECOV-14`'s own instruction.
   That is the strongest form of `concurrency-and-async/f414b864` rather than an exemption from it.
   The one place a reader might expect a lock — the suppressed trail — is covered by the stated
   single-writer claim alone; verified fact 13 measures a real loss on 3.2.11 and licenses nothing,
   so it is not part of the argument, and a lock on a caller's exception object is not available in
   any case.
4. **An `Enumerator` abandoned mid-`#next` never runs its `ensure`, and the rule reaches an ordinary
   `#each`** (`pagination/b2a85752`). Both folds are `Array#reduce` and neither is lazy.
   `Dexpace.each_cause` **does** return an `Enumerator` with no block, and that is safe for a stated
   reason rather than by exemption: it acquires nothing, so an abandoned walk leaks nothing an
   `ensure` would have released. No other method in 4b returns one.
5. **Bytes on the wire are always `Encoding::BINARY`.** 4b reads no bytes; `buffer_error_body`
   delegates every byte decision to phase 3b's `buffer_bounded`, which is where the encoding rule
   already lives.
6. **The bundled-gem rule.** 4b requires nothing. The near miss is `XCUT-9`'s visited set, which
   resolves to `{}.compare_by_identity` rather than to `set` (verified fact 7) — and `set` is
   allowlisted anyway, so the fact buys correctness rather than dependency headroom.
7. **`Ractor` is never load-bearing.** Both `Outcome` variants are frozen `Data`, and a `Failure`
   holds an `Exception` while a `Success` holds a `Response` holding a body holding an `IO`, so **no
   shareability claim is made for either**. `data-modeling/5bc538ba` already narrows it and 4b
   narrows it no further.
8. **`XCUT-15`'s no-alias rule** reaches both chains' constructors, and `Model.own` is not the tool:
   a step list is an `Array` of caller-supplied *callables*, and `Ractor.make_shareable(…, copy:
   true)` would attempt to deep-copy a lambda's closure. The chains `dup` the array and `freeze` the
   copy — a shallow copy is what `RECOV-14` asks for, since the requirement is about later mutation
   of the *list* and not about the steps. **P4-22**, because a reader who knows `Model.own` will ask.

## Testing strategy

`test/` mirrors `lib/` one file per file; each file's header comment names the requirement IDs it
exercises and a non-obvious branch names the ID that forced it. Every suite subclasses
`DexpaceTestCase`, so a warning raised by code under test fails the test that triggered it.

**No transport, no socket, no stream.** Roadmap cross-cutting constraint 4 puts phases 1 through 7 on
an in-memory fake transport, and 4b needs exactly that and nothing more: `RECOV-2`'s "the transport
invocation" is a `#call(request, options, cancellation)` duck type, so the fake is fifteen lines.
Nothing in 4b performs I/O, which is what makes every case here deterministic.

**Two fakes and three fixture classes, and they are fakes rather than mocks** (`testing/7ecef8e8`,
`testing/630ba094`):

- `gems/dexpace-core/test/support/fake_transport.rb` — `FakeTransport`, returning a configured
  response or raising a configured error, and recording the request, options and cancellation it was
  handed. It is what `RECOV-2`'s transport half and `RECOV-11`'s token assertion both drive.
- The same file carries `RecordingBody`, a `Dexpace::Body` that **includes `Dexpace::Closeable`** and
  counts `#release` and `#source` calls. It counts `#release` and not `#close` on purpose: two
  assertions in this phase are release **counts** rather than release facts — `RECOV-12`'s "exactly
  once" and `RECOV-13`'s "zero" — and `RECOV-12`'s path calls `#close` **twice** (`buffer_bounded`'s
  `ensure`, then the chain's own close), so a fake counting `#close` would assert 2 where the
  requirement says once and would pass against a chain that had dropped the latch. Neither count is
  expressible against phase 3b's real bodies without reaching into their latches.
- `gems/dexpace-core/test/support/cyclic_errors.rb` — R7's `SelfCause`, the two-way `CyclicPair`, and
  `StructurallyEqualError`, which carries a settable `#cause` override and overrides `hash` and
  `eql?` so the identity assertion discriminates against a `Set` as well as against an `Array`. Its
  instances are **never raised** in the third test: a `raise`-built pair is not `==` on 3.2.11 and
  the assertion stops discriminating there (verified fact 7).

`DEF-29`'s condition — a consumer outside `dexpace-core` — stays unmet; these strengthen the row
without meeting it.

**Steps are lambdas wherever a lambda is honest, and there are three lambda shapes, not two.** Every
`RECOV-3` through `RECOV-8` case drives the folds with `->(request) { … }` for a request step,
`->(response) { … }` for a **response** step and `->(outcome) { … }` for a **recovery** step — R8's
clause 3 and the three proc types above. A suite that wrote the response steps as `->(outcome)` would
be testing a chain this design does not describe and would silently license the `Outcome`-typed
response step `RECOV-4`'s parenthesis forbids. Lambdas are both the cheapest fixture and the
assertion that §5.1's "a lambda qualifies as a step" is true of the recovery chain too. The three
shipped transforms get their own suites and are not used as fixtures for the fold rules, because a
suite that tested the fold through `IdempotencyKeyStep` would fail for two reasons at once.

**The tests a reader would otherwise write wrong.**

- **`RECOV-2`'s defining invariant, driven from the *request* side.** A throwing **request** step
  must surface as a `Failure` to a **recovery** hook — the "a before-request throw MUST NOT skip
  after-error handling" clause. A suite that only throws from the transport passes against an
  orchestrator that wraps the transport call alone, which is the natural first implementation.
- **`RECOV-10`'s "unchanged", asserted as two things, and the fixture has to be built one way.**
  `assert_same` on the surfaced object, because verified fact 6 makes `assert_equal` pass against a
  substituted structurally identical error; and `assert_nil error.cause` **while an unrelated
  exception is in flight**, which is the only assertion that catches the bare `raise` spelling
  (verified fact 5). The test wraps the call in its own `begin; raise "unrelated"; rescue; … end` to
  create the condition, and a comment says why. **The `Failure` must carry an error the test
  *constructed* and never raised** — `ProtocolError.for(response)` or a bare `StandardError.new`,
  which is `RECOV-10`'s own case, "a recovery step constructing the error and returning a Failure".
  An error the fixture *raised* inside that `rescue` already acquired the unrelated exception as its
  cause at its own `raise`, and `cause: nil` does not clear a pre-existing cause, so `assert_nil`
  would fail against the correct implementation. Measured on all three.
- **`RECOV-11`, asserted on the token and not on the error.** Cancel a source, have the transport
  raise `Dexpace::CancelledError`, and assert the token still answers `cancelled?` after the fold and
  after `RECOV-10` rethrows. An assertion that the `Failure` carries a `CancelledError` proves
  nothing about the signal, which is what the requirement is about.
- **`RECOV-12`'s three clauses, one test each.** The response is closed exactly once — a **count** of
  1 on `RecordingBody`; the close error is on `Dexpace.suppressed(raised)` and did **not** replace the
  primary — `assert_same` the primary, which is what verified fact 10 says a bare close in an
  `ensure` would fail; and a `Failure` in hand closes nothing.
- **`RECOV-13`, asserted as a zero.** A **recovery** step deliberately returning a substitute
  `Success` leaves the original's release count at **0**. It is a recovery step and not a response
  step because only a recovery step is handed the outcome and can return a different one. A positive
  test that the substitute arrives proves nothing about ownership.
- **`RECOV-8`'s totality, asserted on the return value.** `testing/26b866e1` forbids
  `assert_nothing_raised`, so each case asserts the returned `Outcome` — a throwing recovery step
  yields a `Failure` carrying its error *and* the next recovery step ran, which one assertion cannot
  cover.
- **`RECOV-5`'s hardest clause.** A response step throws, and a recovery step registered after it
  observes the resulting `Failure`. Building that sequence is three lines and it is the clause a
  suite most often omits, because the natural failure fixture is a transport error.
- **`RECOV-6`'s order, asserted with one log.** One recording array, response steps appending
  `:r1, :r2` and recovery steps `:c1, :c2`; assert `%i[r1 r2 c1 c2]`. Two separate order assertions
  would not catch a chain that interleaved.
- **`RECOV-14`, asserted by mutating the caller's array** after construction, on both chains and all
  three lists.
- **R6's `LoadError` case**, above: a request step raising `LoadError` surfaces as a `LoadError` and
  no recovery step is invoked.
- **R7's three cause-walk cases**, above.
- **`DEF-32`'s fourth `Hooks.notify` case**, above, at the `Cancellation::Source#cancel` site.
- **`DEF-27`'s two `close_quietly` cases**: with `onto:` absent the rescued error is still dropped
  and the existing phase-2 test is unchanged; with `onto:` supplied the rescued error lands on that
  error's trail and `close_quietly` still returns `nil` and still does not raise.
- **The truncation boundary through the constant.** `Recovery.buffer_error_body` over a body of
  `MAX_BUFFERED_ERROR_BODY_BYTES + 1` bytes truncates to the constant, and the assertion names the
  constant rather than `1024 * 1024`, so a second constant would break the test rather than pass it.
  This is the one allocating test in the phase, one 1 MiB allocation per run per matrix row, and it
  reuses phase 3b's precedent for the same allocation.

**Property tests.** `testing/f36a19cd` makes round-trip property tests mandatory for a value object
with parse-constructor invariants. Neither `Outcome` variant has one — both are single-member
carriers with no parsing — so the mandatory case does not arise, and one property test is written
anyway because it is the exhaustiveness claim in executable form: over a seeded generator of
`Success` and `Failure` values, `outcome.fold(on_success: →:s, on_failure: →:f)` returns `:s` exactly
when `#success?` and `:f` exactly when `#failure?`, and the two predicates are never both true and
never both false. Seed pinned and logged (`testing/7ece0212`, `/7b383289`).

## The interface surface 4c and later phases may cite

Stated as a contract, so a later phase cites rather than re-derives.

| Consumer | What it gets, and the obligation |
|---|---|
| **4c**, obligatorily | `Dexpace::Recovery::Transform` — `#phase`, `#apply(value)` and the forwarding `#call(value)` default — and the three transforms. 4c ships **one generic adapter** that reads `#phase` and produces `#call(request, cursor)`, calling `#apply` and not `#call` so a future default cannot change what the pipeline does; it ships **no** second implementation of an idempotency key, a client-identity line or a status mapping, and does not subclass the three. A `:response` transform is `Response -> Response` and **raises** on an error status — no `Outcome` crosses into the `PIPE` layer, which is what the charter's `response -> outcome` would have implied and `RECOV-4`/`RECOV-15` do not. `PIPE-37`'s outermost placement is `ErrorMappingStep`'s and its non-error identity return is already guaranteed. R8 above is the whole contract |
| **4c**, optionally | Nothing else. `Dexpace::Outcome` is not a `PIPE` type, `Dexpace::PipelineError` is 4c's own to name, and a `PIPE` step must not return an `Outcome` |
| **Phase 5**, on `DEF-27` | `Dexpace.close_quietly(resource, onto: nil)`. Phase 5 adds the `http.instrumentation.*` diagnostic for the `onto:`-absent case and **closes the row**; it does not replace the trail and does not remove the keyword |
| **Phase 5**, on `DEF-32` | `Dexpace::Hooks.notify`'s trail. Phase 5 may emit a diagnostic per attached failure; it does not replace the trail |
| **Phase 6**, on `RETRY-34` | `Dexpace.attach_suppressed` with the skip-self guard, applied to **both** retry stacks through this one helper — §5.2's resolution of the third reference asymmetry. Phase 6 writes no second helper |
| **Phase 6**, on `RETRY-25` | `RECOV-2`'s fatal-family passthrough, already implemented: a non-`StandardError` is surfaced unchanged with no trail attached |
| **Phase 6**, on `DEF-35` | `Dexpace::Recovery::ResponseChain` and `Orchestrator` are what the recovery-aware retry stack installs into, and `Dexpace::ProtocolError` is the error `RECOV-19`/`RETRY-36` re-classifies. `Recovery.buffer_error_body` is the one buffering call site and phase 6 adds no second |
| **Phase 6**, on `DEF-38` | `Dexpace::ProtocolError` gains `#retryable?` from `XCUT-5`'s single shared classifier, added to **this** class rather than a second one. Adding a method widens; `NFR-4` permits |
| **Phase 6 and 7**, on `XCUT-9` | `Dexpace.each_cause`, which yields the error first and tracks by reference identity through `#compare_by_identity`. Every classification uses it; none walks `#cause` by hand |
| **Phase 7**, on `SSE-33`–`SSE-36` | `Dexpace::Outcome`, reused with a third variant **in the SSE namespace** and never by adding one here (`RECOV-1`, spec-forced boundary 6) |
| **Phase 7**, on `PAGE-13`/`PAGE-15`/`SSE-29`/`SSE-36` | `Dexpace.attach_suppressed` and `Dexpace.suppressed`. A primary that is not a `Dexpace::Error` is handled; a **frozen** primary is silently not, which is stated |
| **Phase 8**, on `XCUT-4` | `Dexpace::ProtocolError` is branch (a) and is flat; `Dexpace::TransportError < ::IOError` is branch (b) and lands flat beside it. Both include `Dexpace::Error` and therefore both carry the trail |
| **Phase 9**, on `XCUT-8` | `ProtocolError.for` raising for a non-error status and `.for_or_nil` returning `nil` — the two forms the requirement names |
| **Phase 9**, on `XCUT-9` | The audit target: `Dexpace.each_cause` as the single walk, and the repository-wide check that nothing else walks `#cause` |

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`. Numbering continues
from 4a's `P4-11`; `P4-24` and `P4-25` were added by this document's review.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P4-12 | The suppressed trail lives on a **separate** module, `Dexpace::Suppressible`, which `Dexpace::Error` includes — not on `Dexpace::Error` itself as design §5.2 and `error-handling/34f54b5e` both write it | design §5.2 **and design §10 item 6** ("`Dexpace::Error#suppressed` supplies the list"); `DEF-24`; `RECOV-12`; P1-2 | Every primary `RECOV-12`, `DEF-27` and `DEF-32` hand the helper is a **caller's** exception, so the helper must be able to give a trail to a class core does not control, and `Object#extend` is Ruby's only mechanism for that. Verified on all three that `rescue M` matches a module reached through a singleton class, so extending a third-party error with the rescue root would make `rescue Dexpace::Error` catch errors the SDK never raised — the one promise P1-2 made. Two modules keeps both properties; one module cannot. **`Dexpace::Error` still carries `#suppressed`**, by inclusion, so §10 item 6's sentence stays true of an SDK error and is wrong only about where the method is defined and about what else can carry a trail — which is what the consolidation into §10 has to correct, and why item 6 is named in the column beside §5.2 |
| P4-13 | `Dexpace.attach_suppressed` **`extend`s** its primary, mutating an object core did not create, and silently no-ops on a frozen one | `RECOV-12`; `RETRY-34`; `error-handling/a86bc536` | Attaching a trail is a visible side effect on the primary by definition — the requirement asks for exactly that. `extend` and the ivar write both raise `FrozenError` on a frozen exception (verified, all three), and a helper that raises while attaching a *close* error would mask the primary, which is the single failure `RECOV-12` exists to prevent. So the `FrozenError` rescue is the one-class deliberate swallow the styleguide sanctions, with its why-comment, and the loss is stated in the YARD and asserted in a test rather than hidden. Cost measured at roughly 4× a bare exception allocation, on an error path only |
| P4-14 | `#suppressed` is a **frozen array replaced on every attach**, rather than one array frozen at a stated moment | design §5.2's "frozen once populated"; `api-design/c15b29ce` | "At first read" and "at first raise" are both lifecycles nothing in Ruby enforces, and `RETRY-34` attaches after an error may already have been inspected. Replace-on-append makes "frozen once populated" literally true at every moment (verified: `<<` on a returned trail raises), gives a caller who took a handle a stable snapshot, and needs no per-read `dup` |
| P4-15 | Two module functions design §5.2 does not name: `Dexpace.suppressed(error)` and the `Suppressible` module itself as a public constant | `NFR-4`; `api-design/b0e18938`; P2-11, P3-14 and P4-2 precedent | `RECOV-10` rethrows a caller's error unchanged, so a consumer reading a trail off a surfaced error cannot know whether it is `Suppressible` and would otherwise write `respond_to?` at every read site. It is also the only route for a logger that formats an exception itself rather than calling `#full_message` — a real limit of the `#detailed_message` mechanism, verified and stated rather than assumed away. **The module is public rather than a `private_constant`** — phase 2's treatment of `Dexpace::Hooks` — because `extend`ing a caller's exception with it is an observable change to that object: `e.is_a?(Dexpace::Suppressible)` becomes true and `rescue Dexpace::Suppressible` starts matching, on all three (verified fact 2), and a constant a consumer can observe but cannot name is worse than one it can. The cost is that `rescue Dexpace::Suppressible` is a second, broader rescue point beside `rescue Dexpace::Error`, which the YARD states rather than leaves to be discovered |
| P4-16 | `Dexpace.each_cause` yields **the error itself first**, then its causes | `XCUT-9`; design §5.2 | `XCUT-9`'s consumers are classifications, every one of which must inspect the error before its causes, so a walk that skipped the head would put the same two-line preamble at every call site. The name reads the other way, which is why this is a ledger row rather than a comment |
| P4-17 | `RECOV-11` is satisfied **structurally, with no wrapping helper and no token mutation** | `RECOV-11`; design §5.2's "re-asserts the cancellation state on the ambient token"; phase 2's `Cancellation` | The requirement's own portability note says "a port preserves whatever its cancellation primitive is", and the reference restores a JVM interrupt flag that catching the exception cleared. Phase 2's primitive has no clearable flag: `Source#cancel` is idempotent and latched and `#cancelled?` is computed from the sources, so converting a `CancelledError` into a `Failure` cannot swallow the signal. §5.2's word "re-asserts" implies an action that has no spelling here, and inventing one — a token that could be cancelled by a consumer — would be a new capability the requirement does not ask for. Asserted in a test on the token, not implemented |
| P4-18 | The styleguide's block-form resource rule is recorded as not reaching the recovery chain, rather than as a conflict | `resource-management/bf5560dc`; P3-10 and P4-5 precedent | A block form owns a resource for the duration of the block and closes it at the end. The chain's `Success` hands its response **outward** to the caller on the success path — `PIPE-40`'s "MUST NOT close the response it ultimately hands back" from the other layer, and `RECOV-13`'s ownership transfer here — so a block form would close exactly the object that must survive. A rule that does not reach a case is a ledger row, not a corpus note |
| P4-19 | `Dexpace::OutcomeError` is a `StandardError` that the orchestrator **re-raises by name**, so `RECOV-8`'s "MUST NOT throw under any input" holds over `StandardError` with **three** stated exceptions rather than absolutely — `Dexpace::OutcomeError`, the fatal family, and `Dexpace::InvalidArgumentError` for a non-`Outcome` argument | `RECOV-2`, `RECOV-8`, `RETRY-25`; design §5.2; `pipeline/19516188`; `error-handling/3bfdf6f0` | `NoMatchingPatternError` is inside `StandardError` (verified, all three), so the conforming-looking route converts a core defect into an outcome a recovery step may swallow, which is "never demote a programmer error to a handled operational error". Moving the class outside `StandardError` would break `error-handling/e43096c3` and borrow `ScriptError`'s meaning. This is the same trade the port already made for `RECOV-2`'s fatal family and `pipeline/19516188` already records as the port's own choice; one arm, two members, one reason. **The third exception is counted rather than excused**: `#apply` validates its argument at the public boundary and raises `Dexpace::InvalidArgumentError` on a non-`Outcome`, and a non-`Outcome` is an *input*, which is the word `RECOV-8` uses. It is a caller mistake rather than a fold defect and `SEAM-29`'s message form says so, but a row that claimed two exceptions while the code has three is the kind of under-count `NFR-4` and the conformance pass both read literally |
| P4-20 | `Dexpace::ProtocolError` is **one class carrying `#status`**, with no per-status subclass tree | `XCUT-4`, `XCUT-7`, `XCUT-8`, `RECOV-15`; `error-handling/5da8cb17`, `/61ab4fb6` | `XCUT-4` requires exactly two top-level branches and describes no third level; `XCUT-7` decides retry eligibility from a configured status set and never from a class; a subclass is admitted only when callers must distinguish it for different handling, and a caller distinguishes a 404 from a 429 by reading `#status`. A generated SDK that wants its own typed errors passes `factory:` to `ErrorMappingStep` rather than subclassing. Recorded because "the matching typed exception" reads like a tree |
| P4-21 | `Outcome#response_or_nil` and `#error_or_nil` return `nil` for the absent case | `RECOV-1`; `api-design/6ea28c9c` | `RECOV-1` names "response-or-null, error-or-null" as part of the derivable surface, so the `nil` is the requirement's and not a choice — the same documented case `CTX-18` reserved for 4a. `#success?`/`#failure?` and `#fold` are the non-`nil` routes and are what core itself uses; neither accessor has a caller in `lib/` |
| P4-22 | Both chains `dup` and `freeze` their step lists rather than routing them through `Model.own` | `RECOV-14`; `XCUT-15`; phase 1's `Model.own` | `Model.own` is `Ractor.make_shareable(collection, copy: true)`, which deep-copies, and a step is a caller-supplied callable whose closure cannot be copied. `RECOV-14`'s requirement is that later mutation of the caller's **list** cannot alter chain behaviour, which a shallow copy satisfies exactly. Recorded because a reader who knows `Model.own` will ask why it is not used, and because it means **no shareability claim is made for a chain** |
| P4-23 | Public **methods** neither design §5.1 nor §5.2 names: `Suppressible#suppressed` and `#detailed_message`; `Dexpace.attach_suppressed`, `.suppressed`, `.each_cause`; `Outcome::Success`/`Failure`'s `.build`, `#success?`, `#failure?`, `#response_or_nil`, `#error_or_nil`, `#fold`; `OutcomeError#offending_class`; `ProtocolError.for`, `.for_or_nil`, `#response`, `#status`; `Transform#phase`, `#apply` and `#call` (the module's one default implementation, R8 clause 4); `RequestChain.build`, `#apply`, `#steps`; `ResponseChain.build`, `#apply`, `#response_steps`, `#recovery_steps`; `Orchestrator.build`, `#call`; the three steps' `.build` and `#apply`; and `Dexpace.close_quietly`'s new `onto:` keyword | `NFR-4`; `api-design/b0e18938`; P2-11, P3-14 and P4-11 precedent | `NFR-4` locks a public *signature*, not only a public name, and §5.2 describes the whole subsystem while naming three Ruby constants and no method at all. Two deserve naming here. **`#response_or_nil` and `#error_or_nil` have no caller anywhere in core** — `RECOV-1` requires them as derivable accessors and only the suite exercises them, so deleting them later would be an `NFR-4` break for methods core never used, which is exactly what this row exists to make deliberate. And **`close_quietly` gains a keyword rather than a second helper**, which widens and therefore passes the lock in the one direction that matters, on `DEF-28`'s stated precedent. The `Data`-generated readers on both `Outcome` variants are public API too and are invisible to `rbs validate`; the runtime surface snapshot is what holds them, and the phase's last task regenerates both |
| P4-24 | Public **constants** neither design §5.1 nor §5.2 names as Ruby constants: `Dexpace::Outcome` (the shared module), `Dexpace::Recovery::Transform`, `::RequestChain`, `::ResponseChain`, `::Orchestrator`, `::IdempotencyKeyStep`, `::ClientIdentityStep` and `::ErrorMappingStep` | `NFR-4`; `NFR-11`; P1-1; P2-11, P3-14 and P4-2 precedent | The methods are P4-23's and the two module functions are P4-15's; **the constants had no row and `NFR-4` locks a name before it locks a signature**, which is the whole reason P2-11 and P3-14 exist. §5.2 names `Dexpace::Outcome::Success` and `::Failure` and never the `Outcome` module they share; §5.1 names the three steps only in prose ("the idempotency-key step") and names `Dexpace::Recovery.buffer_error_body` but no other member of `Recovery`. Each is deliberate: `Outcome` is the module both variants include so `outcome.is_a?(Dexpace::Outcome)` is one type test and the RBS union has a name (4a's P4-1 reading of "sharing a module"); the three chains-and-orchestrator classes own state (`data-modeling/3e37c086`); `Transform` is R8's crossing contract and must be nameable in the public signature 4c writes (`NFR-11`); the three steps are the objects §5.1 describes. Placement follows P1-1 unchanged — `Recovery` and `Outcome` are namespaces the design itself wrote, everything else is flat |
| P4-25 | `Dexpace::Recovery::Transform` carries **one default implementation**, `#call(value) = apply(value)`, where 4a's `Dexpace::Context` and phase 1's `Dexpace::Error` only declare | R8; §5.1's "a lambda qualifies as a step"; `api-design/88e6bf12` | The two chains invoke a step as `step.call(value)`, because §5.1 requires a bare lambda to be a step and every fold fixture in this phase is one. Without the default, installing a transform into a chain would need either an adapter class — which §5.1's "written once against the step protocol both layers share" and this phase's own "4b writes no adapter" both forbid — or a `Method` object, which is not a `Proc` and would not type-check against the proc types `sig/` declares for the three step lists. One forwarding method buys clause 4 of R8 outright. It is recorded because "a module that only declares" is the shape every other contract module in this repository has, and a reader who knows that will read the exception as an accident |

## Deferrals Filed by Phase 4b

Filed against `docs/deferred-items.md`; each row names an explicit target or pick-up condition, per
the roadmap's execution step 7. (The heading avoids the literal words the housekeeping probe's
`registers` check reserves for the aggregate register, which is where the rows live.)

| ID | Deferral | Target / condition |
|---|---|---|
| `DEF-38` | `XCUT-5`'s baked retryability flag on `Dexpace::ProtocolError`, and the single shared status classifier it must be computed from. 4b ships the class `RECOV-15` needs and gives it no `#retryable?`, because `XCUT-5` requires the flag to come from "a SINGLE shared status classifier" treating 408, 429 and all 5xx except 501 and 505 as retryable — which is `RETRY-1`'s classifier, phase 6's, and the same object `XCUT-6`'s capability path and `XCUT-7`'s configurable set are defined against. Building one here would fix a phase-6 seam a phase early, which is the charter's own argument for moving `RECOV-27` and phase 2's for declining `deadline:` (`DEF-28`) | Phase 6, with `RETRY-1`–`RETRY-45`. The attachment point already exists — a method added to `Dexpace::ProtocolError` **widens** a signature, which `NFR-4`'s "disappears or narrows" lock permits — so phase 6 adds `#retryable?` to this class and writes no second protocol-error type. `DEF-35` lands in the same phase and the two should be read together |

### Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition
every row. All thirty-seven were read; the charter's sweep covered the phase-4-wide dispositions and
is not repeated, so what follows is the 4b-specific delta.

- **`DEF-24` — picked up and discharged.** Its condition names phase 4 explicitly, "with the recovery
  chain that is its first caller", and `RECOV-12` is that caller exactly as the row predicted. 4b
  ships `#suppressed` (frozen from construction, P4-14), `Dexpace.attach_suppressed` with
  `RETRY-34`'s skip-self guard, and the rendering **through `#detailed_message`** per the charter's
  verified fact 1 — with the two corrections this design adds: the trail lives on
  `Dexpace::Suppressible` rather than on `Dexpace::Error` (P4-12), and `#full_message` is not
  overridden (R5). Row moves to `picked-up`. `NFR-4` is not a concern: the lock diffs against a
  release tag that does not exist.
- **`DEF-32` — picked up and discharged.** Implemented exactly as the row words it: "attach each
  later failure to the first through `Dexpace.attach_suppressed`, then re-raise as now." Two lines in
  `Hooks.notify` and their comment: the attach, and `raise failure` becoming
  `raise failure, cause: nil` (verified fact 5 — the site re-raises an error it has been carrying, so
  a bare `raise` hands the caller's in-flight exception to it as a `#cause`; "re-raise as now" is
  honoured because the object surfaced is the same object). **None of phase 2's three tests changes
  its assertions** — each raises from one handler, so the trail is empty — and a fourth test is added
  at the `Cancellation::Source#cancel` site with two raising handlers, which is the only case that
  distinguishes the two behaviours. Row moves to `picked-up`, naming the fourth test; its
  `Dexpace::Error#suppressed` clause is corrected to `Dexpace::Suppressible` in the same edit,
  because the primary at this site is a bare `::IOError` (P4-12).
- **`DEF-27` — half supplied, row stays open, and 4b must not close it.** The row fixes two disposal
  routes and reserves closure for phase 5: "phase 4 supplies the first route with `DEF-24`'s
  `#suppressed` and `Dexpace.attach_suppressed`; **phase 5 supplies the second with §8.1's facade and
  closes this row**." **4b's half, stated precisely:** `Dexpace.close_quietly` gains one optional
  keyword, `onto:`, defaulting to `nil`. With `onto:` absent — every existing call site — the
  behaviour is byte-for-byte today's: rescue `StandardError`, drop it, return `nil`, and phase 2's
  own test that pins that is unchanged. With `onto:` supplied, the rescued error is attached to it
  through `Dexpace.attach_suppressed` and `close_quietly` still returns `nil` and still does not
  raise. **`onto:` is validated at entry, before the close is attempted, and that placement is the
  decision.** `attach_suppressed` raises `Dexpace::InvalidArgumentError` for a non-`Exception`
  argument, and §3.7's whole promise is that `close_quietly` never raises over a primary failure — so
  a bad `onto:` must be rejected while the caller is still the only thing that has gone wrong, not
  from inside the rescue where it would replace the close failure it was passed to carry. A `nil`
  `onto:` stays the documented no-attach default and is not a caller mistake. That is a widening
  (`NFR-4` permits) and adds no second helper, which is what keeps §3.7's "two ways and never a
  third" true. The row gains a dated `Status` line recording the first route and does **not** move to
  `picked-up`; its `Why` names `Dexpace::Error#suppressed` as the trail and 4b's plan corrects that
  clause to `Dexpace::Suppressible` in the same edit, for the same reason `DEF-32`'s does (P4-12).
  `closeable.rb`'s own YARD carries the same sentence and is rewritten with the code.
- **`DEF-5` — picked up as a disposition, not as work.** `RECOV-31` is 4b's only pre-existing ⏳ row.
  Its condition is post-MVP and phase 4 cannot meet it; the row is **not** UNSCHEDULED. 4b's
  checklist carries the row citing `DEF-5` and §11.20 and moves on.
- **`DEF-35` — untouched, and cited by fifteen of 4b's checklist rows.** Filed by the charter. 4b
  neither meets nor widens it, and in particular builds no backoff calculator, no pacing parser and
  no wait.
- **`DEF-1` — untouched.** `SEAM-28` targets phase 5; 4b supplies neither half.
- **`DEF-18` — untouched.** `PIPE-33`'s interrupt clause is 4c's ⏳ row.
- **`DEF-28` — untouched, and named as a constraint.** 4b has no clock, no deadline and no wait.
  `RECOV-20`'s and `RECOV-27`'s dependence on it travels with `DEF-35`.
- **`DEF-29` — untouched.** `FakeTransport`, `RecordingBody` and the three cyclic-error fixtures land
  under `gems/dexpace-core/test/support/`, following phase 2's and phase 3's precedent. The condition
  — a consumer outside `dexpace-core` — is not met.
- **`DEF-30`, `DEF-31`, `DEF-34`, `DEF-36`, `DEF-37` — untouched.** All five target phase 5's
  instrumentation facade or configuration chain. `DEF-27`'s second route is the one of the five 4b's
  work most directly enables.
- **`DEF-2`, `DEF-3`, `DEF-4`, `DEF-6`–`DEF-17`, `DEF-19`–`DEF-23`, `DEF-25`, `DEF-26`, `DEF-33` —
  untouched.** Other prefixes, other phases, release-gated, or already picked up. **`DEF-6` is worth
  one sentence**: it defers `RETRY-38`, `DEF-5`'s twin, so a phase-6 planner meeting `DEF-35` will
  meet all three at once, and the charter already says the cluster's sixteenth ID is not phase 6's
  budget.

### The findings filed against `docs/open-items.md`

**None.** Everything 4b found is either a decision it owns (R5–R9, in the ledger above), a corpus
correction (the three notes), or a finding against a **committed** document that belongs to the
manager rather than to a register.

That last category has **two** members and both are named here rather than filed, because each is a
statement in a committed phase-2 document that 4b's own change makes false rather than a gap anyone
needs to track.

**The first is anticipated and is `DEF-32`'s.** Phase 2's design paragraph "Every handler runs,
whatever an earlier one did", its plan's edge-case bullet "`Hooks.notify` re-raises the **first**
handler failure and drops the rest", and the YARD block the plan's Task 4 step 3 writes into
`lib/dexpace/hooks.rb` all describe the pre-`DEF-32` behaviour. `DEF-32`'s register row already
anticipates the change and is the durable record; the shipped comment is 4b's plan to update, and the
two committed documents are the manager's call. An `OI-` row would duplicate `DEF-32` rather than add
to it.

**The second is not anticipated anywhere, because it is P4-12's finding and not `DEF-32`'s.** Four
committed places name **`Dexpace::Error#suppressed`** as the carrier a handler failure or a
`close_quietly` failure attaches to — phase 2's design `DEF-32` row, the same clause in its plan's
edge-case bullet, `closeable.rb`'s shipped YARD ("the suppressed trail is `Dexpace::Error#suppressed`,
deferred to phase 4"), and the register's own `DEF-32` and `DEF-27` rows. That carrier cannot work at
either site: both primaries are caller-supplied exceptions and phase 2's own tests raise a bare
`::IOError`. The two files 4b edits carry their correction with the edit; the four documents are the
manager's, and the register rows travel with the `picked-up` and `Status` moves 4b's plan makes. It
is still not an `OI-` row — every one of them is a sentence a named change rewrites, not a finding
nobody owns.

`OI-8`, `OI-9`, `OI-12`, `OI-13`, `OI-14`, `OI-15` and `OI-16` are read and untouched. **`OI-14` is
the one a reader would expect 4b to close and 4b cannot**: its prompting instance is `DEF-32`'s own
*Why*, citing a design chapter filename that has never existed, and `DEF-32` is the row this phase
moves to `picked-up`. The row's `Status` line is the only part append-only convention lets a
pick-up touch, so the filename stays wrong and `OI-14` stays open — which is the item's own point,
that nothing mechanically checks the class. `OI-16` is obeyed
rather than merely noted: every `[overridden by notes/…]` marker met while reading this phase's
corpus was resolved by reading the note, and two of them — `error-handling/c1fa7ee8` and
`error-handling/71ef8cb1` — are marked overridden by a note whose own text says it adopts them
verbatim, which is exactly the false signal `OI-16` records.

## Open questions for 4b's own plan

Five, each bounded, none reopening a decision above.

1. **Whether `Dexpace::Recovery::Ownership` earns a file or belongs inside `response_chain.rb`.**
   It is a `private_constant` with one function and exactly one caller.
   Recommendation: its own file, per the layout above, because §5.2's "one shared helper so the
   asymmetry lives in one place" is a claim a reader should be able to check by opening one file, and
   phase 6's recovery-aware retry stack is a second plausible caller. Confirm on the task that writes
   `ResponseChain`; if it is still one caller and forty lines, folding it in is a one-line change to
   the layout and not to the design.
2. **`ErrorMappingStep`'s default `factory:` spelling.** `Dexpace::ProtocolError.method(:for)`
   allocates a `Method` object per `.build` call and reads oddly in a signature.
   Recommendation: a `private_constant` lambda in `error_mapping_step.rb` wrapping
   `ProtocolError.for`, referenced as the default — one frozen object, no `Method` allocation, and
   the RBS type is the same proc type a caller's factory has. Decide on the task that writes the
   step; either way the **default is core's** and that is not open.
3. **Whether `Dexpace.each_cause` should stop at a `#cause` that raises, or propagate.** The design
   says stop, so a classification is never the thing that fails.
   Recommendation: keep it, and add the case to the R7 fixture file as a fourth class — a `#cause`
   that raises is as reachable as one that cycles, from the same source, and the walk's YARD should
   name both. It is one more test and no more code.
4. **Whether the `DEF-32` fourth test belongs at one site or all three.** The design puts it at
   `Cancellation::Source#cancel`.
   Recommendation: one site. All three call the same `Hooks.notify` and phase 2 already proves each
   site reaches it; a second and third copy would assert the helper three times and the sites zero
   extra times. If the plan finds the three sites' hook lists differ in shape, revisit.
5. **Whether `Dexpace::ProtocolError`'s message should include a body preview.** It carries the
   buffered response, so a preview is available.
   Recommendation: **no**, and the reason is `OBS-11`–`OBS-19`'s redaction, which is phase 5's: a
   message is what lands in a log by default, and an error body is the one payload most likely to
   carry a token or a customer identifier. The message names the status; `#response` is how a caller
   who wants the body reads it. Confirm with phase 5's planner rather than reversing it here.
