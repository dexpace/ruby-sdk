# Phase 6c — Authentication

**Status:** Draft, for review. Written 2026-09-09.

## Purpose

Implement `AUTH-1`–`AUTH-38`: the descriptor/resolver model, the four credential types with
variant-specific equality and redaction, the RFC 7235 challenge parser, the Basic and Digest
handlers with the bounded per-nonce counter store, the composing challenge handler, static
key-credential stamping, and the AUTH pillar step — its HTTPS guard, cross-origin suppression,
401 re-challenge replay, and bearer-token cache — on both the sync and async runtimes.

This document does not re-derive what `docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`
already decided: the three-way cut, the budget (`6c` is 38 IDs, all `AUTH`, with no ⏳ row), the
independence of `6a`/`6b`/`6c`, and the fact that the cross-origin marker mechanism (`Cursor#fork(state:)`,
`Cursor#state(stage)`) is phase 4c's and is not open to revision here. It consumes that document's
Prerequisites section, its verified Ruby facts, and its risks `R10`, `R11` and `R12`, which it resolves.

## Governing documents

- `docs/product-spec/11-authentication.md`, all 28 lines, and the appendix-C canonical text of
  `AUTH-1`–`AUTH-38` (`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`,
  the `AUTH` rows).
- `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.3 in full, and §6.2's cross-origin
  marker paragraph, which is what `AUTH-29` reads.
- `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` item 15.
- `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1 (cursor-scoped state and the write
  restriction).
- `docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md` — the governing document for this
  sub-phase. Its Prerequisites section, verified Ruby facts, spec-forced boundaries, and `R10`–`R15`
  are consumed rather than restated except where quoted.
- `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md` — the stage table,
  `Cursor#fork(state:)`, `Cursor#state(stage)`, `Cursor#may_fork?`, the five negative assertions
  (R11 there), and `test/support/ForkingProbe`/`StateProbe`.
- `docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-design.md` — `Dexpace::BoundedMap`
  (`private_constant`), its shipped surface, its full-nesting reachability condition, and its own
  forward table row naming phase 6's `#update(key) { |old| new }` addition.
- `docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md` — `Dexpace::Async::Future`,
  `::Completer`, `::Settlement`, `#on_settle`.
- Phase 4a's deferral of the context store's configured cap (picked up by phase 5a, Task 13; read and found not to
  extend here), and `6a`'s Task 8 `Cursor` context-bundle widening (consumed if present, not built here).

## Scope

**38 IDs, all `AUTH`, 36 MUST and 2 SHOULD (`AUTH-19`, `AUTH-38`).** `AUTH-1`–`AUTH-28` and
`AUTH-30`–`AUTH-38` implemented in full; `AUTH-29` implemented with its stripping clause satisfied
by construction (nothing is ever added to the request, so there is nothing to strip) and its
suppression and HTTPS-guard-skip clauses executable and implemented. No ⏳ row — `6c` is the only
sub-phase of phase 6 none of whose IDs is declined for v1 or postponed to a later phase.

The canonical text of every `AUTH` ID is appendix C's; it is not reproduced here except where a
decision turns on an exact clause, quoted inline at that decision.

## Independence

**`6c` depends on phases 0–5 only. Its dependency on `6a` and `6b` is empty, with the single
exception of the `Cursor` context-bundle widening, which `6c` consumes if `6a` has already built it and does
not require and does not build.** This is the segmentation design's own instruction (`R13`) that
every sub-phase's Prerequisite section say so explicitly rather than inherit a chain by habit, and
it is stated here plainly:

- `6c` does not wait on `6a`'s `Dexpace::Resilience::Policy` or its retry step. `AUTH-27`'s "redirect
  wraps retry wraps auth" is `PIPE-2`'s stage order, already fixed and tested by phase 4c; `6c`'s
  AUTH step occupies `Stages::AUTH` regardless of whether a RETRY step is installed at all, and
  `Stages::RETRY`'s namespaced state (4c's R11, negative assertion 4) is invisible under
  `Stages::AUTH` to begin with, so `6c` has nothing to read from `6a` even by accident.
- `6c` does not wait on `6b`'s real REDIRECT step. It reads `cursor.state(Stages::REDIRECT)`, which
  4c guarantees is a shared frozen empty hash when nothing wrote it — the same value a pipeline with
  no REDIRECT step at all produces. `6c`'s own test doubles a `REDIRECT`-stage probe step (phase 4c's
  `ForkingProbe`/`StateProbe`, the worked example already shipped) that forks with `state: {
  cross_origin: true }` and with it unset, and asserts against both without any of `6b`'s code.
  Convergence point 1 in the segmentation design — the real end-to-end cross-origin credential-leak
  test with `6b`'s real REDIRECT step — is owned by whichever of `6b`/`6c` lands second; under the
  document's own recommended order that is `6c`, and this design names the task (Task 14 below) so it
  is not silently assumed by the other side.
- **`6c` does not consume `6a`'s `Dexpace::Resilience::Resend.eligible?(request)`.** `AUTH-31`'s
  replayability gate — "if the replacement request carries a body that is not replayable, the step
  MUST skip the replay" — is discharged by calling `request.body&.replayable?` directly: phase 3b's
  own shipped predicate, with no `6a` object between `6c` and it. If `6a`'s `R5` settles
  `Resend.eligible?(request)` as an exact synonym for that same call — which is what 3b's forward
  table anticipates — the two computations agree with nothing to reconcile; if `6a`'s `R5` gives it
  additional clauses, that is a decision `6a` makes with all three call sites (`RETRY-5`, `REDIR-6`,
  `AUTH-31`) in view, not one `6c` pre-empts by guessing at a name that may not exist when `6c` runs.
- **The `Cursor` context-bundle widening (`6a`'s Task 8).** If `6c` runs before `6a`, `6c` builds no `Cursor` accessor for a
  per-call instrumentation bundle and files no such task — `6c` ships its own `logger:`/`redactor:`
  constructor keywords on its step exactly as `6b`'s `R8` does, and consumes the widened reader only
  if it is already there. `6c` neither builds that widening nor silently re-implements a
  second one.

## Prerequisites, verified to exist

Everything below is drawn from the segmentation design's own Prerequisites section, restated only
to the depth `6c`'s tasks touch, and not re-verified independently — this document does not re-open
that verification.

- **Phase 0.** The require allowlist already carries `digest`, `securerandom` and `openssl`; the
  denylist carries `base64` by name. `Dexpace/NoLocaleCaseFold` (the `downcase`-with-no-arguments
  cop) and the general "no `Regexp.timeout`" house rule bite `6c` at the scheme/parameter-name
  normalisation and at the (absent) temptation to parse the challenge grammar with a regexp.
- **Phase 1.** `Dexpace::Request`, `Response`, `Headers`, `RequestOptions`, `Status`, `Method`,
  `HeaderName` and their builders. `6c` reads and writes headers through these, never a raw `Hash`.
- **Phase 2.** `Dexpace::Async::Future`, `::Completer`, `::Settlement` — *not* `Dexpace::Future` —
  with `Future#on_settle`, `#value(cancellation:)`, `#wait`, `#cancel`; `Completer#fulfil`,
  `#fail`, `#request_cancel`, `#await`. `AUTH-37`'s mechanism is `Future#on_settle`, used with no
  blocking `#value`/`#wait` call anywhere in `6c`'s async path (see `R12` below).
- **Phase 3b.** `Dexpace::Body#replayable?` (default `false`), `Response#close`. `AUTH-31`'s gate
  calls `request.body&.replayable?` directly.
- **Phase 4a.** `private_constant Dexpace::BoundedMap` with `.new(cap:)`, `#set`, `#put`, `#[]`,
  `#delete_if_identical`, `#size` — **and phase 4a's own forward table names the addition `6c`
  makes**: "`Dexpace::BoundedMap`, reached by a bare unqualified name from `module Dexpace; module …`
  in the full nesting form, with `#update` added to it rather than a second map written." `6c` adds
  `#update(key) { |old| new }`, executing the block while the map's internal mutex is held — 4a's
  design states the block "must touch only in-memory state" and that constraint is written into the
  method's own comment when `6c` adds it, per 4a's own instruction. The reachability condition —
  `module Dexpace; module Auth; module Digest` with a bare, unqualified `BoundedMap` reference, never
  `module Dexpace::Auth::Digest` and never a qualified `Dexpace::BoundedMap` — is
  `execution-context/b58728da`, quoted in the segmentation design and not re-verified here.
- **Phase 4c.** `Dexpace::Pipeline::Cursor` — `#fork(state:)`, `#state(stage)`, `#may_fork?`,
  `#request`, `#options`, `#cancellation`, `#spent?`; `Dexpace::Pipeline::Stages::AUTH` (order 800)
  and `::REDIRECT` (order 200); the step duck type `#call(request, cursor) -> Response` (or
  `-> Future`) with `#stage` read once at install. `test/support/ForkingProbe` and `StateProbe`.
  **Spec-forced boundary 1** (segmentation design): the AUTH pillar step forks for every drive
  including the first (`AUTH-30`'s replay) and never calls `Cursor#call`.
- **Phase 5a.** `Dexpace::Clock` (`#now`, `#monotonic`) — `6c` needs no `#sleep`, since nothing in
  `AUTH-1`–`AUTH-38` waits on a timer; the bearer refresh margin (`AUTH-34`) is a plain
  `Clock#now`/expiry comparison, not a scheduled wait. `Dexpace::Configuration` and
  `Configuration::Keys`/`::Sources` exist and are live (unlike phase 4a's situation when it deferred
  the context store's cap to phase 5) — relevant to `R11` below.
- **Nothing from `5b`/`5c` is a hard dependency.** `6c`'s AUTH step accepts its own optional
  `logger:`/`redactor:` keywords defaulting to the no-op pair, exactly as `6b`'s `R8` does for the
  same reason: `Stages::AUTH` (800) is outside `Stages::LOGGING` (1100) and cannot borrow that step's
  logger.

## Corpus reading, and what it settled

The phase-start pair was run for this sub-phase. `ruby scripts/knowledge.rb --origin note --brief`
returns the same 37 entries across 18 note files the segmentation design already read; none is
`authentication`-specific, and the one bearing on `6c`'s own mechanism —
`execution-context/b58728da`, the `BoundedMap` full-nesting reachability condition — is quoted above
and is not re-derived. `--section conflicts --brief` returns the same 24 entries, all six
harvested-vs-styleguide contradictions already marked `[overridden by notes/…]`; none is open and
`6c` inherits no unresolved conflict.

`ruby scripts/knowledge.rb --prefix AUTH --section rules --brief` returns 45 entries across three
topic files (`authentication.md`, `redaction-and-security.md`, `retry-and-resilience.md`), **zero
tagged `[appendix-B roll-up]`** — confirming the segmentation design's own coverage claim
(`AUTH` 38 of 38 substantive, `ruby scripts/knowledge.rb --gaps AUTH` reports the same). Every rule
returned restates a clause already quoted from appendix C or design §6.3 above; none contradicts
either. `ruby scripts/knowledge.rb --topic execution-context --section rules --brief` returns 14
entries, none naming `AUTH-19` beyond the `(Constraints)`/`(Conclusions)` entries already folded into
`R11` below (`authentication/de3163e0`, the bounded-1024-with-drain-to-cap constraint, and
`authentication/6e10bbf7`, the bearer hot-path-without-a-lock conclusion — both restated from design
§6.3 and not new information).

`ruby scripts/knowledge.rb --req AUTH-19,AUTH-21,AUTH-24,AUTH-34,AUTH-37 --brief` returns four
entries beyond the `--prefix AUTH` set, all `Constraints`/`Conclusions`/`Reference` role, none tagged
roll-up, none in conflict with the design chapter. **No corpus query for this sub-phase returned a
roll-up-only hit**, so the three-step roll-up path is not exercised here, matching the segmentation
design's own finding that `AUTH` fires the hazard zero times.

**No knowledge note is filed by this document.** Nothing found during this design contradicts a
harvested entry; the one candidate correction — Ruby's `String#unpack1("m")` leniency on Basic
decode — is already recorded as the segmentation design's verified fact 5 and is not `6c`'s finding
to duplicate.

## Verified Ruby facts this sub-phase relies on

All nine of the segmentation design's verified facts on 3.4.10 are inherited unchanged; facts 5, 6,
7 and 8 are `6c`'s own and are restated here because a task cites them directly:

1. **`["u:p"].pack("m0")` returns a US-ASCII string encoding the UTF-8 bytes of the input, and needs
   no `require "base64"`.** `["alice:s3cr3t"].pack("m0")` → `"YWxpY2U6czNjcjN0"`;
   `["ü:pä"].pack("m0")` → `"w7w6cMOk"`. `AUTH-14`'s spelling.
2. **`String#unpack1("m")` never raises and silently decodes a valid subset of garbage input.**
   `"!!a b c!!".unpack1("m")` returns the two-byte string `"i\xB7"`, decoded from the surviving
   `abc`; it returns `""` only when no valid base64 octet exists at all. The length-and-colon check
   after decode is what `AUTH-14`'s Basic decode (used by the composing handler when acting as a
   client, not a server — see the object model below for where this actually applies) relies on,
   not an emptiness check.
3. **`Digest::MD5.hexdigest` and `Digest::SHA256.hexdigest` return lower-case hex** (`AUTH-17`), and
   `format("%08x", n & 0xFFFFFFFF)` renders exactly 8 lower-case hex digits, wrapping
   `0x100000001` to `"00000001"` (`AUTH-18`).
4. **`String#encode("ISO-8859-1")` raises `Encoding::UndefinedConversionError` on an unmappable
   character** (`"日".encode("ISO-8859-1")`) and succeeds byte-for-byte on a mappable one
   (`"pä".encode("ISO-8859-1")` → bytes `[112, 228]`). `AUTH-21`'s default (non-`charset=UTF-8`)
   branch is therefore a **raising** path on a credential the caller legitimately supplied — `R10`.
5. **`digest`, `securerandom` and `openssl` are on phase 0's require allowlist already**; `6c` needs
   no allowlist diff (segmentation design, Prerequisites, phase 0).

## `R10` — `AUTH-21`'s ISO-8859-1 branch: a documented raise via a typed failure

**Decision: a typed `Dexpace::Auth::UnencodableCredentialError`, naming the credential field and
the target encoding, raised from the point the Digest handler materialises the hash input — never
`:replace`, and never a bare `Encoding::UndefinedConversionError` escaping unwrapped.**

`AUTH-21` reads: "The byte encoding used to materialize Digest hash inputs MUST be UTF-8 when the
challenge advertises `charset=UTF-8` (case-insensitive) and ISO-8859-1 (Latin-1) otherwise." Verified
fact 4 establishes that the default branch is not merely lossy but **raising** on ordinary input — a
password containing "日" is a legitimate credential, and the server's own challenge (not the caller)
decides which encoding applies.

Three routes were open and two are rejected:

- **`:replace`** (substituting `?` or `U+FFFD` for the unmappable byte) produces a syntactically
  valid but *wrong* Digest response. The request is sent, the server rejects it with a 401 that
  carries no information distinguishing "wrong password" from "password silently mangled by the
  client library," and `AUTH-24`'s and `AUTH-36`'s machinery would then treat it as an ordinary
  failed-auth case rather than a client-side encoding defect. This is the same failure shape design
  §6.3 already rejects for a misbehaving provider (`AUTH-35`): "the failure mode a permissive port
  produces is a 401 from the server with no indication that the SDK is what dropped the credential."
  Rejected on that precedent.
- **A bare raise** (letting `Encoding::UndefinedConversionError` propagate) is idiomatic Ruby but
  gives the caller no `Dexpace::` type to `rescue`, no credential-field name, and no target encoding
  — a debugging dead end for an error a caller cannot fix by retrying, only by using a different
  password or a server that advertises `charset=UTF-8`. Every other error boundary in this codebase
  wraps a foreign exception in a named `Dexpace::` type carrying the offending input (phase 1's
  `Dexpace::InvalidArgumentError` around `URI::InvalidURIError`, per `url-and-query-encoding/08c54234`);
  a bare raise here would be the one exception boundary that does not.
- **A typed failure — adopted.** `Dexpace::Auth::UnencodableCredentialError < Dexpace::Error`,
  constructed with `field:` (one of `:username`, `:realm`, `:password`), `:encoding` (`"ISO-8859-1"`),
  and `#cause` set to the rescued `Encoding::UndefinedConversionError` via `raise …, cause: e` — never
  a bare re-raise of a stored value (`pipeline/7ce4431d`, though that note is about *carried* errors
  and this one is raised fresh, so the note's rule does not literally apply; the discipline is kept
  anyway because it is free and consistent). The message names which field failed and states the
  challenge advertised no `charset=UTF-8`, so a caller reading the error knows exactly what to do
  next: either the server needs to advertise `charset=UTF-8`, or the credential cannot authenticate
  against this realm under RFC 7616's default encoding.

**Delivery.** On the sync AUTH step this raises synchronously from `#call`, exactly where any other
Digest-handler failure would. On the async step, per `AUTH-38`'s SHOULD and the general rule this
design adopts uniformly for the async path (see `R12`'s closing paragraph), it is caught at the
step's top level and settles the returned `Future` as a failure — it is not a case the async step
special-cases, because nothing about it is specific to encoding; any error raised inside the async
step's body settles the future, by construction.

**What the Digest test matrix asserts, per algorithm.** The encoding-selection step runs once, before
any of the four algorithms hash anything, so the test is written once and parametrised over all four
(`MD5`, `MD5-sess`, `SHA-256`, `SHA-256-sess`) rather than four independent tests:

1. A challenge with no `charset` parameter and an ISO-8859-1-representable credential (`"café"`)
   succeeds and produces the RFC 7616 test-vector-shaped response for that algorithm.
2. A challenge with `charset=UTF-8` (and `charset=utf-8`, case-insensitively) and a credential
   containing "日" succeeds, hashing the UTF-8 bytes.
3. A challenge with no `charset` parameter and a credential containing "日" raises
   `Dexpace::Auth::UnencodableCredentialError` with `#field == :password` and `#encoding ==
   "ISO-8859-1"`, for every one of the four algorithms — proving the raise is a property of the
   shared encoding-selection step and not an accident of one hash routine.

## `R11` — `AUTH-19`'s per-nonce counter store: per-handler, and no configuration-chain deferral

**Decision: the store is owned by the `Dexpace::Auth::DigestHandler` instance that uses it — one
`BoundedMap` per handler, constructed in `#initialize` and never shared across handler instances —
and its cap is an ordinary constructor keyword, not a value read from `Dexpace.configuration`, so no
deferral is filed.**

`execution-context/b58728da` fixes the *reachability* condition (full nesting, bare reference) and
is not re-argued. Two questions are `6c`'s own, per the segmentation design's own naming of `R11`.

**Per-handler, not process-wide.** A `DigestHandler` is constructed once per credential — typically
once per server/realm a caller authenticates against — and a process may build more than one when it
talks to more than one Digest-protected API with different credentials. Scoping the nonce-counter
store to the handler instance rather than to a class-level or module-level singleton:

- Matches `data-modeling/3e37c086`'s "state-owning behaviour lives in a class" rule, applied the same
  way 4a applied it to `BoundedMap` itself and to `ContextStore` — a class instantiated by its owner,
  never a bare module-level `Hash`.
- Avoids the exact shape `PIPE-11` forbids for a different object ("per-request mutable state MUST
  live in the per-call cursor … never on the step" — here read for its underlying principle: no
  ambient, caller-invisible global mutable state where a constructor-owned instance suffices).
  `AUTH-24`'s "safe for concurrent invocation across requests" is satisfied per-instance, since a
  `Thread::Mutex` inside one handler's store serialises access to that handler's counters and needs
  no coordination with any other handler.
- Means one server's aggressive nonce rotation cannot evict another, unrelated server's live nonce
  out of a shared cap — a property `AUTH-19` does not require (eviction of a live nonce is explicitly
  "acceptable" even within one store) but that a per-handler store gets for free rather than by
  argument.

Nothing in `AUTH-15`–`AUTH-24` requires cross-handler nonce visibility — a nonce is meaningful only
to the realm that issued it, and a `DigestHandler` is already scoped to one credential — so
per-handler is the narrower, correct reading and the one that needs no new process-wide singleton.

**No configuration-chain deferral, because there is nothing to defer.** Phase 4a deferred the
**context store's** cap (picked up by phase 5a, Task 13) specifically because phase 4a shipped before phase 5's configuration chain
existed, and its own pick-up condition is "phase 5, with `CFG-1`–`CFG-4`'s layered chain … read the
cap from the chain when constructing the process-wide store." That reasoning does not transfer here
unmodified: that deferral names the context store by name, not "every `BoundedMap` consumer's cap,"
and its precondition — no config chain yet — is false for `6c`, which runs after `5a` has already
shipped `Dexpace::Configuration`. More importantly, `ContextStore` is built implicitly by the SDK
itself with no caller-visible construction call, which is *why* its cap needed a configuration-chain
route to be tunable at all. `DigestHandler` is the opposite shape: it is explicitly instantiated by
whoever assembles the pipeline (the caller, or a future convenience the caller invokes), so
`DigestHandler.build(credential:, cap: 1024, …)` is already tunable through the ordinary constructor
keyword phase 6 ships, with no ambient global to route through configuration. `AUTH-19`'s "default
cap 1024" is the keyword's default; a caller who wants a different bound passes one. `6c` therefore
files no deferral of that shape of its own — this is the reasoning stated in the segmentation
design's own `R11` phrasing ("whether the context-store cap's configuration-source treatment applies to this cap
too"): it does not, and the reason is that `6c`'s knob was never ambient in the first place.

## `R12` — `AUTH-37`'s three-zone async policy against the pivot

**Decision: "kick off an off-thread background refresh" means calling the bearer provider's async
fetch method and attaching `Future#on_settle` to cache success or log-and-swallow failure, without
ever calling `#value` or `#wait` on it — the "off-thread" property belongs to the provider's own
implementation, exactly as `AUTH-11` already establishes for the default-mirrored case, and the
mechanism needs `Fiber.scheduler` for nothing at all, because it never calls `Dexpace::Async.delay`.**

The apparent tension the segmentation design names — a library with no thread pool, and
`Async.delay` raising `Dexpace::SeamError` with no scheduler (`P5-9`) — dissolves once the two
mechanisms are told apart. `Async.delay` exists for a **timed wait** (backoff between attempts,
`6a`'s concern, `R2` there). A bearer-token refresh is not a wait; it is a **fetch**, and `AUTH-11`
already fixes its asynchronous shape in full: "Async callers MUST observe a provider error through
the asynchronous result channel (a failed future/promise), never as a synchronous throw: the default
async fetch mirrors the blocking fetch's outcome into an already-failed future, and the async bearer
step additionally normalizes a synchronous throw from a misbehaving async override into a failed
future." That sentence already answers "how does the SDK get a `Future` out of a provider" for the
zone that must *await* a fetch (expired/missing); `AUTH-37`'s expiring-but-valid zone only adds "and
do not wait for it."

So the mechanism, stated concretely:

1. **Expiring-but-valid.** Stamp the still-valid cached token on the current request immediately.
   Separately, call `provider.fetch_async` (or the normalised wrapper around a synchronous provider's
   `#fetch`, per `AUTH-11`), obtaining a `Dexpace::Async::Future`. Attach one `#on_settle` block to
   it: on success, validate the result under `AUTH-35`'s rule (non-nil, not already expired with no
   margin) and, if valid, write it into the cached-token instance variable under the per-credential
   `Thread::Mutex` (the same lock `AUTH-34`'s sync path uses, held only across the flag flip, never
   across the fetch — the fetch already completed by the time `#on_settle` runs); on failure, log and
   do nothing else — `AUTH-37`'s "a failed/unusable BACKGROUND refresh MUST NOT fail the in-flight
   request." **The dispatching fiber never calls `#value` or `#wait` on this future**, so it returns
   to the caller immediately having stamped the already-valid token; whatever runs the actual fetch
   work runs on whatever the provider's own async implementation uses (a real background thread via a
   later phase's `dexpace-async-thread`, a genuinely async I/O call under a registered
   `Fiber.scheduler`, or — in the unavoidable worst case of a caller who supplied no genuinely async
   provider — inline, mirrored-into-a-future execution exactly as `AUTH-11` already sanctions for the
   default). The SDK's obligation is "do not await," not "manufacture a thread it does not own," and
   phase 6 manufactures none.
2. **Expired/missing, with single-flight coalescing.** Under the per-credential mutex, check for an
   already-in-flight refresh `Future` (held in an instance variable, written only under the lock).
   If one exists, attach this request's own continuation via a **second** `#on_settle` on the *same*
   future object — phase 2's `Future#on_settle` is documented to run every registered callback exactly
   once "whether registered before or after settlement," so a second caller coalescing onto an
   in-flight fetch costs one more callback registration and nothing else. If none exists, create a
   `Completer`, store its `Future` in the instance variable (still under the lock), release the lock,
   call `provider.fetch_async`, and arrange its settlement to `fulfil`/`fail` the shared `Completer`.
   Either way, the calling request's *own* returned value is a `Future` derived from the shared one —
   built by chaining through `#on_settle` and a second `Completer`, never by calling `#value` — that
   settles as a stamped request on success and as a failed step on failure. **No blocking wait exists
   anywhere on this path**, which is what "await a fresh single-flight fetch" means on the async
   runtime: the *caller's* future does not resolve until the fetch does, but nothing inside `6c`'s
   code blocks a thread or a fiber waiting for it.
3. **Fresh.** Stamp the cached token; make no provider call at all.

**`AUTH-38`'s SHOULD, and the no-scheduler question it raises, answered uniformly.** The async AUTH
step's `#call` is written so that its entire body — the HTTPS guard (`AUTH-28`), the challenge-hook
invocation (`AUTH-30`/`AUTH-32`), and the bearer zones above — runs inside one `Completer`-backed
frame: any exception raised anywhere inside it settles the returned `Future` as a failure rather than
propagating synchronously, by construction, not by a per-error-type special case. This makes
`AUTH-38`'s SHOULD unconditional on the async step rather than something that depends on whether a
`Fiber.scheduler` happens to be registered — because nothing in `6c`'s async path ever calls
`Async.delay`, `Dexpace::SeamError`'s no-scheduler raise (`P5-9`) never enters `6c`'s call graph at
all. The three-zone policy, the HTTPS guard, and the challenge hook are all fetches and comparisons,
never timed waits, so the async pivot's one raising edge (`Async.delay` with no scheduler) is a
non-issue for every one of `AUTH-27`–`AUTH-38`. This is `6c`'s own finding, distinct from `6a`'s `R2`,
which is a genuine tension for the retry step's backoff and is not resolved by this reasoning.

## Other decisions this design makes

**The descriptor/resolver's wiring boundary, and what phase 6 does not build.** `AUTH-1`–`AUTH-7`
describe pure data (`Requirement`, `Descriptor`) and a pure function (`Resolver`) over three tiers —
per-call, operation, client — with no earlier phase naming where a per-call or operation-level
`AuthDescriptor` is carried on a `Request`, `RequestOptions`, or `Operation` (verified: no occurrence
of "descriptor" in that sense anywhere under `docs/sdk-design-ruby/` outside §6.3's own sentence, and
none of `AUTH-1`–`AUTH-38` specifies such a carrier). `6c` ships the resolver as a correct, tested,
stateless pure function of its three tier arguments and a set of available schemes (`AUTH-7`), and
ships the AUTH pillar step accepting an **already-resolved** credential (or a small caller-supplied
`Scheme => credential` table when a caller wants the step itself to pick among several, using the
resolver internally) at step-construction time. Threading a resolver's *output* from a genuinely
per-call override into the pipeline is Operation-level work with no `AUTH` ID behind it — see
*Findings, and who owns them now* below, which records this as a candidate for the release decision rather
than building speculative plumbing for it.

**The challenge-handler interface is one method, not two.** `AUTH-23`'s "delegate to the first
handler … whose can-handle check passes" and `AUTH-25`'s "return no header … when it cannot satisfy"
are both satisfied by a single `#authorization_for(challenges, request, proxy:) -> String | nil` per
handler: the composing handler tries each in declared order and returns the first non-nil result.
This is behaviourally identical to a design with a separate `#can_handle?` query followed by a
build call — no requirement mandates the query be independently inspectable — and it halves the
handler protocol's public surface under `NFR-4`, matching `api-design/b0e18938`'s minimal-surface
preference. Recorded as a deviation candidate (`P6-<n>` below) because a reader expecting two methods
from the reference's shape should find the reason rather than rediscover it.

**`PasswordCredential`'s validation lives at the handler, not at construction.** `AUTH-9` names
exactly three types — `BearerToken`, `KeyCredential`, `NamedKeyCredential` — for the non-blank
construction-time check; it does not name a username/password credential at all, and `AUTH-14`
separately specifies a **laxer** rule for Basic ("non-empty … permitting whitespace-only values …
intentionally laxer than the non-blank rule used elsewhere"). `6c` therefore does not apply `AUTH-9`'s
guard to the Basic/Digest credential type: `Dexpace::Auth::PasswordCredential` (`Data.define(:username,
:password)`, redacting `#password` in both `#to_s` and `#inspect` per `AUTH-8`, no override of `==`
needed since `AUTH-8` names no equality rule for this type and `Data`'s generated value equality is
the harmless default) validates nothing in `initialize`; `BasicHandler` and `DigestHandler` each
apply `AUTH-14`'s non-empty check at the point they use it, so a blank value is rejected exactly
once, by the rule that actually governs it, and `AUTH-9`'s stricter rule is never silently applied to
a type it does not name.

## Module layout

Every file under `gems/dexpace-core/`. `sig/` mirrors `lib/` one file per file; `test/` mirrors
`lib/` one file per file and does not ship.

```
lib/dexpace/auth.rb                                   Dexpace::Auth                          (module)
lib/dexpace/auth/scheme.rb                             Dexpace::Auth::Scheme
lib/dexpace/auth/requirement.rb                        Dexpace::Auth::Requirement
lib/dexpace/auth/descriptor.rb                         Dexpace::Auth::Descriptor
lib/dexpace/auth/resolver.rb                           Dexpace::Auth::Resolver                (module)
lib/dexpace/auth/bearer_token.rb                       Dexpace::Auth::BearerToken
lib/dexpace/auth/key_credential.rb                     Dexpace::Auth::KeyCredential
lib/dexpace/auth/named_key_credential.rb               Dexpace::Auth::NamedKeyCredential
lib/dexpace/auth/password_credential.rb                Dexpace::Auth::PasswordCredential
lib/dexpace/auth/challenge.rb                          Dexpace::Auth::Challenge
lib/dexpace/auth/challenges.rb                         Dexpace::Auth::Challenges              (module, parser)
lib/dexpace/auth/basic_handler.rb                      Dexpace::Auth::BasicHandler
lib/dexpace/auth/digest_handler.rb                     Dexpace::Auth::DigestHandler
lib/dexpace/auth/key_stamper.rb                        Dexpace::Auth::KeyStamper
lib/dexpace/auth/challenge_handler_chain.rb            Dexpace::Auth::ChallengeHandlerChain
lib/dexpace/auth/bearer_provider.rb                    Dexpace::Auth::BearerProvider           (duck-type doc only)
lib/dexpace/auth/bearer_stamper.rb                     Dexpace::Auth::BearerStamper
lib/dexpace/auth/async_bearer_stamper.rb               Dexpace::Auth::AsyncBearerStamper
lib/dexpace/auth/replayability.rb                      Dexpace::Auth::Replayability     (module)
lib/dexpace/auth/validation.rb                         Dexpace::Auth::Validation        (private_constant)
lib/dexpace/auth/step.rb                               Dexpace::Auth::Step
lib/dexpace/auth/async_step.rb                         Dexpace::Auth::AsyncStep
lib/dexpace/error/auth_resolution_error.rb             Dexpace::AuthResolutionError
lib/dexpace/error/unencodable_credential_error.rb      Dexpace::Auth::UnencodableCredentialError
lib/dexpace/error/https_required_error.rb              Dexpace::Auth::HTTPSRequiredError
lib/dexpace/error/provider_error.rb                    Dexpace::Auth::ProviderError
lib/dexpace/bounded_map.rb                             MODIFIED: adds #update(key) { |old| new }
lib/dexpace.rb                                         MODIFIED: explicit requires for the tree above
```

**`Dexpace::Auth::Validation` is `6c`'s own non-blank helper, and it is not `SEAM-29`'s.** Phase 1's
`Dexpace::Model.required!(name, value)` raises `"<name> is required"` **only when the value is `nil`**
— that is `SEAM-29`'s fixed message form and `HTTP-4`'s missing-field rule, and it is deliberately not
a blank check. `AUTH-9` asks for something strictly stronger ("MUST validate secret and identity
fields as non-blank and reject blanks"), so `6c` adds one `private_constant` module function,
`Validation.non_blank!(value, name)`, raising `Dexpace::InvalidArgumentError` with the message
`"<name> must not be blank"`. **The relation to `SEAM-29` is that the two do not overlap**: a `nil`
field still goes through `Model.required!` and still reads `"<name> is required"`, so `SEAM-29`'s one
message form for a *missing* field is untouched, and the new form names a *blank* field, which
`SEAM-29` does not legislate. `AUTH-14`'s laxer non-**empty** rule is a third check and lives at the
handler, per *Other decisions* above; `Validation` is never applied to `PasswordCredential`.

`Dexpace::Auth::Digest` does **not** exist as a separate namespace level in this layout —
`DigestHandler` and its nonce store live directly under `Dexpace::Auth`. This departs from the
segmentation design's and phase 4a's own illustrative phrasing (`module Dexpace; module Auth; module
Digest`), which names the nesting depth the `BoundedMap` reachability condition needs, not a
commitment to a `Digest` sub-module as a public namespace. `execution-context/b58728da`'s condition
is about **lexical nesting depth**, not about a particular module name at that depth, and it is
satisfied identically by `module Dexpace; module Auth; class DigestHandler` — a `class` body nests
exactly like a `module` body for constant lookup — so `6c` does not add a namespace level with no
other member. The nonce store itself is created inside `DigestHandler#initialize`, still lexically
inside `module Dexpace; module Auth; class DigestHandler`, so the bare `BoundedMap` reference is
resolved from that body regardless.

## The object model 6c ships

### `Dexpace::Auth::Scheme` — `AUTH-1`

`Data.define(:name)` including `Dexpace::Model`, `private_class_method :new`, its five constants built
through `Scheme.send(:new, name: …)` exactly as phase 1's `Method` builds its constants (never
`allocate` plus `instance_variable_set`: verified on 3.4.10, a `Data`'s members are not ivars, so
`D.allocate.instance_variable_set(:@name, "X").name` is `nil` and the trick fails silently), and
`.of(name) -> Scheme` raising `Dexpace::InvalidArgumentError` on an unrecognised name — the same closed-domain shape phase 4c used for `Stage` (`type-system/545949a5`,
P4-32's precedent). `NO_AUTH` is the sentinel meaning "this operation may run anonymously," never a
wire scheme (`AUTH-1`'s own text).

### `Dexpace::Auth::Requirement` — `AUTH-2`

`Data.define(:scheme, :scopes, :params)`, `private_class_method :new`, `.build(scheme:, scopes: [],
params: {})` — validates `scheme` is a `Scheme` and takes ownership of `scopes` (`Array`) and `params`
(`Hash`) through **`Dexpace::Model.own`**, phase 1's `Ractor.make_shareable(collection, copy: true)`
helper, exactly once at construction (§4's domain-model pattern). `Model.own` and not `dup.freeze`:
`dup` is shallow, and `AUTH-2`'s "retained input collections mutated by the caller after construction
MUST NOT affect the stored value" covers a caller mutating a `String` *inside* the array — verified on
3.4.10, `stored = ["read"].dup.freeze` followed by the caller's `scopes[0] << ":write"` leaves
`stored == ["read:write"]`, while `Model.own` deep-copies and deep-freezes. `scopes`/`params` are retained and
exposed for every scheme, per `AUTH-2`'s "preserved for caller inspection" even though resolution
itself (`AUTH-5`) never inspects them for any scheme but `OAUTH2`'s own bookkeeping. Value equality
over all three members (`Data`'s default) is `AUTH-2`'s own text.

### `Dexpace::Auth::Descriptor` — `AUTH-3`

`Data.define(:requirements)`, `private_class_method :new`, `.build(requirements)` — rejects an empty
array with `Dexpace::InvalidArgumentError` and takes ownership of it through `Dexpace::Model.own`. `#allows_anonymous?` — true
iff any requirement's scheme is `Scheme::NO_AUTH`. Immutable in and immutable out: `#requirements`
returns the same frozen array reference at every call (`HTTP-5`'s pattern, applied here for the same
reason it is applied to every other model collection).

### `Dexpace::Auth::Resolver` — `AUTH-4`–`AUTH-7`

A module, no instance, all methods `module_function` — the same shape §6.1 gives
`Dexpace::Resilience::Policy` ("frozen constants and pure functions") and 5a gives
`Dexpace::Retryability`, applied here because `AUTH-7` requires the resolver to be "stateless and safe
for concurrent use … and a single shared instance MUST be a valid entry point": a module *is* the
single shared entry point, trivially, with nothing to instantiate and nothing to race on.

```ruby
def self.resolve(per_call:, operation:, client:, available_schemes:)
  descriptor = per_call || operation || client
  raise Dexpace::InvalidArgumentError, "no auth descriptor supplied at any tier" unless descriptor

  requirement = descriptor.requirements.find do |req|
    req.scheme == Dexpace::Auth::Scheme::NO_AUTH || available_schemes.include?(req.scheme)
  end
  return requirement if requirement

  raise Dexpace::AuthResolutionError.new(
    required: descriptor.requirements.map(&:scheme),
    available: available_schemes
  )
end
```

Tier selection is strict — the first present tier is the *only* one consulted (`AUTH-4`: "A higher
tier that is present but cannot be satisfied MUST NOT fall through to a lower tier"), which the `||`
chain gets right by construction: once `per_call` is non-`nil` it is used exclusively, whether or not
its search finds a satisfiable requirement. `AUTH-6`'s two distinct failures are two distinct
`Dexpace::` types: `Dexpace::InvalidArgumentError` when every tier is absent, and
`Dexpace::AuthResolutionError` (new, carrying `#required` in preference order and `#available`) when
a descriptor is present but lists no satisfiable scheme. `AUTH-5`'s "MUST NOT inspect any concrete
credential to decide satisfiability" is honoured because `resolve` never receives one — only
`available_schemes`, a set of `Scheme` values the caller already knows it can supply credentials for.

### Credential types — `AUTH-8`, `AUTH-9`, `AUTH-10`, `AUTH-11`

`Dexpace::Auth::BearerToken` — `Data.define(:token, :expiry)`, validating `token` non-blank in
`initialize` (`AUTH-9`; the shared "non-blank" helper `SEAM-29` fixes, per §4's pattern) and
`expiry` optional (`nil` meaning never-locally-expires, `AUTH-10`). `#expired?(now:, margin: 0)` —
`expiry && (now + margin) > expiry`. `#to_s`/`#inspect` both redact `token` to a fixed placeholder
and show `expiry`, which is non-secret (`AUTH-8`). Value equality over `token` and `expiry` is
`Data`'s default and is `AUTH-8`'s own "unaffected by the redacted string form" — the override lives
only in `#to_s`/`#inspect`, never in `==`/`hash`/`eql?`.

`Dexpace::Auth::KeyCredential` and `::NamedKeyCredential` — plain classes, not `Data`, per design
§6.3's "the key credentials … do not define `==`, so Ruby's default identity equality is what they
get." `KeyCredential.new(api_key:, header_name: "Authorization", prefix: nil)`; `NamedKeyCredential.new(name:,
key:, header_name: "Authorization", prefix: nil)`. **Both** carry `#prefix` (defaulting to `nil`) and
`#key_value`, because `AUTH-26`'s prefix clause and `KeyStamper` are written against the pair and a
`KeyCredential` with no `#prefix` reader would be a `NoMethodError` at the stamper. Both validate their secret/identity fields
non-blank in `initialize` (`AUTH-9`), freeze themselves at the end of construction, and override
`#to_s`/`#inspect` to redact `api_key`/`key` while showing `header_name`/`prefix`/`name` (non-secret,
`AUTH-8`). Neither overrides `==`, `eql?` or `hash`, so `KeyCredential.new(api_key: "x") ==
KeyCredential.new(api_key: "x")` is `false` — `AUTH-8`'s own text, and the reason writing nothing is
correct here (§6.3).

`Dexpace::Auth::PasswordCredential` — `Data.define(:username, :password)`, no construction-time
validation (see *Other decisions* above), redacting `password` in `#to_s`/`#inspect`. Used by both
`BasicHandler` and `DigestHandler`.

**The bearer provider is a duck type, not a class.** `Dexpace::Auth::BearerProvider` is a
documentation-only module (no methods, `NFR-11`'s RBS scan needs a named interface to point at) for
an object responding to `#fetch -> BearerToken` and, optionally, `#fetch_async -> Future`. When a
supplied provider responds to `#fetch` alone, the async step wraps it per `AUTH-11`'s own text: "the
default async fetch mirrors the blocking fetch's outcome into an already-failed future" — meaning the
wrapper calls `#fetch`, and on a raised error settles an already-failed `Future` rather than letting
the raise propagate synchronously out of `#fetch_async`'s caller. `AUTH-11`'s "MUST NOT be cached" and
"async … additionally normalizes a synchronous throw from a misbehaving async override into a failed
future" are both this wrapper's job, in one place, so no caller-provided override that itself raises
synchronously from a real `#fetch_async` can escape unnormalised.

### `Dexpace::Auth::Challenge` and `Dexpace::Auth::Challenges` — `AUTH-12`, `AUTH-13`

`Challenge` — `Data.define(:scheme, :params)`, `params` a frozen `Hash` with lower-cased `String`
keys and verbatim (unquoted, unescaped) `String` values, `private_class_method :new`. A token68 value
is recorded under the synthetic key `"token68"`, per `AUTH-12`'s own text.

`Challenges.parse(header_value) -> Array<Challenge>` — the hand-written character-level state
machine `CLAUDE.md` and design §6.3 require, never a regexp: "the grammar is not regular and … a
hostile `WWW-Authenticate` should not be able to drive a backtracking engine." Sketch of the state
machine's shape (full case analysis in the plan's Task 4, not reproduced here):

```ruby
module Dexpace
  module Auth
    module Challenges
      module_function

      # AUTH-12, AUTH-13. Never raises; a malformed challenge recovers to the next
      # top-level comma; an unterminated quoted string terminates at end-of-input;
      # parameters parsed before a malformed tail are preserved on the emitted challenge.
      def parse(header_value)
        return [] if header_value.nil? || header_value.strip.empty?

        scanner = ::StringScanner.new(header_value)
        challenges = []
        until scanner.eos?
          scheme = scan_token(scanner)
          break if scheme.nil? # malformed tail with no recoverable scheme; stop, keep what we have

          scanner.skip(/[ \t]+/)
          params, consumed_ok = scan_params_or_token68(scanner)
          challenges << Challenge.build(scheme: scheme.downcase, params: params)
          break unless consumed_ok || scanner.skip(/[ \t]*,[ \t]*/)
        end
        challenges
      end

      private_class_method def self.scan_token(scanner) = scanner.scan(/[!#$%&'*+\-.^_`|~0-9A-Za-z]+/)
      # scan_params_or_token68 walks comma-separated `name=value` pairs, handling a quoted-string
      # value (backslash-escape aware, tolerant of an unterminated quote at end-of-input per
      # AUTH-13) and a bare token68 fallback, recovering to the next top-level comma on anything
      # it cannot parse rather than raising. Full grammar in the plan.
    end
  end
end
```

`Challenges` is a **public** module (not `private_constant`): a caller writing a custom challenge
handler for a scheme this SDK does not implement (e.g. `NTLM`) needs the same lenient parser, and
`AUTH-12`/`AUTH-13` describe a self-contained, generally useful RFC 7235 primitive with no
credential-shaped state behind it — the same reasoning that keeps `Dexpace::HTTPDate` public.

### `Dexpace::Auth::BasicHandler` — `AUTH-14`

```ruby
class BasicHandler
  def initialize(credential)
    raise Dexpace::InvalidArgumentError, "username/password must be non-empty" \
      if credential.username.empty? || credential.password.empty?

    @value = "Basic #{["#{credential.username}:#{credential.password}"].pack("m0")}".freeze
  end

  # AUTH-14 preemptively: the stamper duck type Step takes. This is the path OpenAPI's
  # `http` / `basic` security scheme uses -- a generated SDK sends the credential on the FIRST
  # request and never waits for a 401, which is universal convention for that scheme.
  def call(request) = request.new_builder.header("Authorization", @value).build

  # AUTH-14 as a challenge answer: the same precomputed value, returned only when a Basic challenge
  # was actually offered. This is the path ChallengeHandlerChain drives.
  def authorization_for(challenges, _request, proxy:)
    return nil unless challenges.any? { |c| c.scheme.casecmp?("basic") }

    @value
  end
end
```

**One class, two roles, one precomputed value.** `#call` is preemptive stamping and `#authorization_for`
is challenge answering; `AUTH-14` describes both ("Basic stamping MUST produce … computed once" and
"MUST accept a Basic challenge case-insensitively") and a second class would compute the same
`pack("m0")` value twice.

Computed once at construction and reused (`AUTH-14`'s own text) — never per request. `String#casecmp?`
is a locale-independent, no-argument comparison (`downcase`'s no-argument rule extended to its sibling
predicate; verified: `casecmp?` takes no locale argument at all, so there is nothing to get wrong
here). The non-empty check is `AUTH-14`'s own laxer rule — "permitting whitespace-only values" — not
`AUTH-9`'s, per the *Other decisions* section above.

### `Dexpace::Auth::DigestHandler` — `AUTH-15`–`AUTH-24`

```ruby
class DigestHandler
  ALGORITHMS = %w[MD5 MD5-sess SHA-256 SHA-256-sess].freeze
  HASHES = { "MD5" => ::Digest::MD5, "SHA-256" => ::Digest::SHA256 }.freeze

  def initialize(credential, preference: ALGORITHMS, cap: 1024, cnonce_source: ::SecureRandom)
    @credential = credential
    @preference = preference.freeze
    @cnonce_source = cnonce_source
      # BARE and unqualified, resolved from the `module Dexpace; module Auth; class DigestHandler`
      # lexical scope: `BoundedMap` is a `private_constant` of `Dexpace`, so the qualified spelling
      # `Dexpace::BoundedMap` raises `NameError: private constant Dexpace::BoundedMap referenced`
      # (verified on 3.4.10). `execution-context/b58728da`; spec-forced boundary 8.
      @nonces = BoundedMap.new(cap: cap) # per-handler; never shared (R11)
  end

  def authorization_for(challenges, request, proxy:)
    challenge = select(challenges)
    return nil unless challenge

    algorithm = challenge.params.fetch("algorithm", "MD5")
    base_algorithm = algorithm.delete_suffix("-sess")
    session = algorithm.end_with?("-sess")
    charset_utf8 = challenge.params["charset"]&.casecmp?("utf-8") || false

    # AUTH-21 + R10: each component is materialised UNDER ITS OWN FIELD NAME, so the typed failure
    # can name :username, :realm or :password rather than a joined string (R10's test matrix asserts
    # `#field == :password`).
    ha1_input = join(
      materialize(@credential.username, :username, charset_utf8),
      materialize(challenge.params.fetch("realm"), :realm, charset_utf8),
      materialize(@credential.password, :password, charset_utf8)
    )
    hasher = HASHES.fetch(base_algorithm)
    ha1 = hasher.hexdigest(ha1_input)

    cnonce = @cnonce_source.hex(16) # AUTH-20, XCUT-21: 128 bits, never Random
    ha1 = hasher.hexdigest(join(ha1.b, challenge.params.fetch("nonce").b, cnonce.b)) if session # hex/nonce/cnonce are ASCII

    uri = request_target(request)
    ha2 = hasher.hexdigest(join(request.method.to_s.b, uri.b)) # method and request-target are ASCII

    qop = qop_auth?(challenge) ? "auth" : nil
    nc = next_count(challenge.params.fetch("nonce"))

    response =
      if qop
        hasher.hexdigest("#{ha1}:#{challenge.params.fetch("nonce")}:#{nc}:#{cnonce}:#{qop}:#{ha2}")
      else
        hasher.hexdigest("#{ha1}:#{challenge.params.fetch("nonce")}:#{ha2}")
      end

    build_header(challenge, uri, cnonce, nc, qop, response, algorithm)
  end

  private

  # AUTH-16: satisfiable iff scheme is Digest (case-insensitive), realm and nonce present, qop
  # absent or contains "auth", algorithm supported or absent (defaulting to MD5). Prefer the
  # earliest-preferred algorithm among satisfiable challenges, independent of wire order.
  def select(challenges)
    satisfiable = challenges.select do |c|
      c.scheme.casecmp?("digest") &&
        c.params.key?("realm") && c.params.key?("nonce") &&
        (c.params["qop"].nil? || qop_auth?(c)) &&
        (c.params["algorithm"].nil? || ALGORITHMS.include?(c.params["algorithm"]))
    end
    @preference
      .map { |alg| satisfiable.find { |c| c.params.fetch("algorithm", "MD5") == alg } }
      .compact.first
  end

  # AUTH-15, AUTH-16: the qop parameter is a comma-separated TOKEN LIST and the comparison is
  # token-exact, never a substring test -- verified on 3.4.10, `"auth-int".include?("auth")` is
  # `true`, so a substring test accepts exactly the auth-int-only challenge AUTH-15 requires be
  # declined.
  def qop_auth?(challenge)
    (challenge.params["qop"] || "").split(",").any? { |token| token.strip.casecmp?("auth") }
  end

  # AUTH-21. Raises Dexpace::Auth::UnencodableCredentialError (R10), never :replace.
  def materialize(string, field, charset_utf8)
    return string.b if charset_utf8 # already UTF-8; binary-tag for hashing, no transcode

    begin
      string.encode(::Encoding::ISO_8859_1).b
    rescue ::Encoding::UndefinedConversionError => e
      raise Dexpace::Auth::UnencodableCredentialError.new(field: field, encoding: "ISO-8859-1"),
            cause: e
    end
  end

  # Components are already BINARY here, so the joiner is BINARY too (HTTP-13's outbound rule).
  def join(*parts) = parts.join(":".b)

  # AUTH-18, AUTH-19, AUTH-24: increments under BoundedMap's own mutex via #update; starts at 1 for
  # a nonce the map has not seen (including a nonce the drain evicted, restarting at 1 per AUTH-19's
  # "spec-legal for a fresh nonce"); rendered as 8 lower-case hex digits, low 32 bits on overflow.
  def next_count(nonce)
    count = @nonces.update(nonce) { |old| (old || 0) + 1 }
    format("%08x", count & 0xFFFFFFFF)
  end

  def request_target(request)
    path = request.url.path.empty? ? "/" : request.url.path
    request.url.query ? "#{path}?#{request.url.query}" : path
  end

  # AUTH-22: quote username/realm/nonce/uri/response/cnonce/opaque with backslash-escaping; leave
  # qop/nc/algorithm unquoted with the full RFC spelling; emit cnonce/nc/qop only when qop negotiated.
  def build_header(challenge, uri, cnonce, nc, qop, response, algorithm)
    parts = [
      %(username="#{quote(@credential.username)}"),
      %(realm="#{quote(challenge.params.fetch("realm"))}"),
      %(nonce="#{quote(challenge.params.fetch("nonce"))}"),
      %(uri="#{quote(uri)}"),
      %(response="#{quote(response)}"),
      "algorithm=#{algorithm}"
    ]
    parts << %(cnonce="#{quote(cnonce)}") << "nc=#{nc}" << "qop=#{qop}" if qop
    parts << %(opaque="#{quote(challenge.params["opaque"])}") if challenge.params["opaque"]
    "Digest #{parts.join(", ")}"
  end

  def quote(value) = value.gsub(/[\\"]/) { |m| "\\#{m}" }
end
```

`select`'s two-pass shape (filter to satisfiable, then walk the *preference* list rather than the
*challenge* list) is what makes `AUTH-16`'s "independent of the order challenges arrived in" literal
rather than incidental. The nonce-counter store is the `@nonces` instance variable — `R11`'s
resolution — constructed once per handler with the cap defaulting to `AUTH-19`'s 1024 and overridable
by the caller with no configuration-chain plumbing.

### `Dexpace::Auth::ChallengeHandlerChain` — `AUTH-23`, `AUTH-25`

```ruby
class ChallengeHandlerChain
  def initialize(handlers)
    @handlers = handlers.dup.freeze # AUTH-23: defensive copy at construction
  end

  def authorization_for(header_value, request, proxy: false)
    challenges = Dexpace::Auth::Challenges.parse(header_value)
    @handlers.each do |handler|
      value = handler.authorization_for(challenges, request, proxy: proxy)
      return value if value
    end
    nil # AUTH-25: no header, not an empty one
  end

  def header_name(proxy:) = proxy ? "Proxy-Authorization" : "Authorization"

  # AUTH-23, AUTH-25, AUTH-30. The adapter that makes the chain reachable from the pillar step.
  # AUTH-30's hook contract is "a replacement REQUEST or nil", while a handler returns a header
  # VALUE; this is the one place the two meet, and it is where AUTH-25's proxy-selected header NAME
  # is actually written onto a request rather than merely computed. It is never installed by
  # default -- AUTH-30's "The default hook MUST yield no replacement" is not negotiable -- so a
  # caller (or a generated SDK's client constructor) opts in by passing it.
  def as_challenge_hook(proxy: false)
    lambda do |header_value, request, _response|
      value = authorization_for(header_value, request, proxy: proxy)
      next nil unless value

      request.new_builder.header(header_name(proxy: proxy), value).build
    end
  end
end
```

`#as_challenge_hook` is what gives `AUTH-15`–`AUTH-25` — Digest above all, which is challenge-driven
by construction and cannot be stamped preemptively — a call path from the pillar step. Without it the
Digest handler would ship correct and unreachable, which is the failure shape this design already
records once for the tier resolver.

Caller-supplied ordering is the documented responsibility `AUTH-23`'s own text assigns ("Callers MUST
order stronger schemes first … since a server offering both is answered by the first matching
handler") — `6c` does not reorder handlers by any notion of strength.

### `Dexpace::Auth::KeyStamper` — `AUTH-26`

```ruby
class KeyStamper
  def initialize(credential)
    @header_name = credential.header_name
    @value = credential.prefix ? "#{credential.prefix} #{credential.key_value}" : credential.key_value
    @value = @value.dup.freeze
  end

  # phase 1 ships no `Request#with_header`; the builder-shaped copy IS the phase-1 idiom, and it is
  # the one 6b's re-issue path already uses (`request.new_builder.header(…).build`). 6c adds no
  # convenience method to a phase-1 model.
  def call(request) = request.new_builder.header(@header_name, @value).build
end
```

`credential.key_value` is `api_key` for `KeyCredential` and `key` for `NamedKeyCredential` — the
stamper is constructed against whichever credential type the resolver selected, and is stateless
after construction (`AUTH-26`'s own text).

### `Dexpace::Auth::Step` — `AUTH-27`–`AUTH-36`, `AUTH-9` (bearer half), `AUTH-11` (sync half)

Declares `#stage` returning `Dexpace::Pipeline::Stages::AUTH`. **The constructor signature is pinned
here, because it is the one object a generated SDK installs and everything else in this chapter is
reachable only through it:**

```ruby
Dexpace::Auth::Step.new(
  stamper:,                        # REQUIRED. Anything responding to #call(request) -> Request:
                                   #   KeyStamper      -- API key in a header (AUTH-26)
                                   #   BasicHandler    -- preemptive Basic (AUTH-14)
                                   #   BearerStamper   -- OAuth2/OIDC/bearer (AUTH-34..AUTH-36)
                                   #   Step::NO_STAMP  -- the NO_AUTH sentinel's stamper (AUTH-1)
  challenge_hook: Step::NO_REPLACEMENT,  # AUTH-30's default: yields no replacement, no retry.
                                   #   ChallengeHandlerChain#as_challenge_hook is how Digest and
                                   #   challenge-answered Basic are opted into.
  logger: nil, redactor: nil       # R8 of 6b's reasoning, applied identically
)

Step::NO_REPLACEMENT = ->(_challenge, _request, _response) { nil }   # AUTH-30's default hook
Step::NO_STAMP       = ->(request) { request }                       # AUTH-1's NO_AUTH sentinel
```

`refresh_margin:` is **not** a `Step` keyword: it belongs to `BearerStamper.new(provider:, clock:,
refresh_margin: 30)`, because the margin is a property of one credential's cache and a `Step` holding
a bearer-only knob it forwards to nothing would be a signature `NFR-4` locks for no reason.

```ruby
def call(request, cursor)
  return cursor.fork.call(request) if cross_origin?(cursor)     # AUTH-29: no guard, no stamp -- and
                                                                # still a FORK (P4-39: a pillar step
                                                                # forks for every drive or calls once
                                                                # and never forks; 6c is the first)
  enforce_https!(request)                                       # AUTH-28, before any fetch/stamp
  stamped = @stamper.call(request)                              # preemptive: key / Basic / bearer
  response = cursor.fork.call(stamped)                          # spec-forced boundary 1

  return response unless response.status.code == 401

  challenge = response.headers["WWW-Authenticate"]
  return response unless challenge                              # AUTH-33: hook never consulted

  evicted = bearer_retry(challenge, stamped, response, cursor)  # AUTH-36
  return evicted if evicted

  replacement = @challenge_hook.call(challenge, stamped, response) # AUTH-30
  return response unless replacement
  return response unless Replayability.replayable?(replacement)   # AUTH-31: surfaced UNCLOSED

  response.close                                                  # AUTH-30: close before the replay
  cursor.fork.call(replacement)                                   # exactly once, no further handling
rescue => e
  response&.close                                                 # AUTH-32
  raise
end

# AUTH-36, the bearer step's own 401 branch, which is NOT the generic challenge hook: it fires only
# for a stamper that owns a token cache, and it fires regardless of HTTP method (never gated by
# idempotency). Its three "surface the 401 unchanged" conditions are the first three guards.
def bearer_retry(challenge, stamped, response, cursor)
  return nil unless @stamper.respond_to?(:evict_if_matches)         # not a bearer stamper
  rejected = stamped.headers["Authorization"]
  return nil unless rejected                                        # cross-origin suppression: no header
  return nil unless bearer_offered?(challenge)                      # no Bearer challenge advertised
  return nil unless Replayability.replayable?(stamped)              # AUTH-31, uniformly (see below)

  @stamper.evict_if_matches(rejected) # evicts ONLY the exact token that produced this 401; a token
                                      # another request already refreshed does not match and survives
  response.close
  cursor.fork.call(@stamper.call(stamped)) # ONE retry, re-stamped with the freshly fetched token
end

def bearer_offered?(header_value)
  Dexpace::Auth::Challenges.parse(header_value).any? { |c| c.scheme == "bearer" } # already lower-cased
end
```

**`AUTH-31`'s gate is applied to the `AUTH-36` retry as well**, which the requirement does not say in
so many words. The reading is stated rather than assumed: `AUTH-31` exists because a non-replayable
body cannot be sent twice, and that is a property of the body, not of which of the two 401 paths is
re-driving it. §11.12's "toward the stricter, uniform behaviour, each through a single shared
implementation" is the same instruction one level up. The shared implementation is
`Dexpace::Auth::Replayability.replayable?`, called from all four sites (sync hook replay, sync bearer
retry, and both async mirrors).

`cross_origin?(cursor)` reads `cursor.state(Dexpace::Pipeline::Stages::REDIRECT).fetch(:cross_origin,
false)` — the whole mechanism §10.15 and `AUTH-29` describe, with no header on the request read or
written anywhere in this method. **AUTH-29's ordering is load-bearing and stated explicitly**: the
cross-origin check runs *before* the HTTPS guard, which is what makes "MUST skip the HTTPS guard" true
for a deliberately-allowed downgrade hop rather than a hard failure, exactly as `AUTH-29`'s text
requires ("because no credential is attached on this path, MUST skip the HTTPS guard").

`AUTH-33` ("A 401 response that does not carry a `WWW-Authenticate` header MUST be returned unchanged
without consulting the challenge hook") is the two `return response unless …` guards before
`bearer_retry` — neither the bearer branch nor the hook is reached when either short-circuits.

**How a generated SDK expresses each OpenAPI security scheme, in one table**, because `6c`'s purpose
is to be the runtime a generator targets and "the objects exist" is not the same claim as "a
generator can reach them":

| OpenAPI scheme | What the generator constructs |
|---|---|
| `http` `bearer`, `oauth2`, `openIdConnect` | `Step.new(stamper: BearerStamper.new(provider:, clock:))`, where `provider` is the user's static-token or refresh callback object (`#fetch`, optionally `#fetch_async`) |
| `http` `basic` | `Step.new(stamper: BasicHandler.new(PasswordCredential.new(username:, password:)))` — preemptive, no 401 round trip |
| `http` `digest` | `Step.new(stamper: Step::NO_STAMP, challenge_hook: ChallengeHandlerChain.new([DigestHandler.new(credential)]).as_challenge_hook)` — challenge-driven by construction |
| `apiKey` in `header` | `Step.new(stamper: KeyStamper.new(KeyCredential.new(api_key:, header_name:, prefix:)))` |
| `apiKey` in `query` or `cookie` | **Not expressible through the AUTH step.** `AUTH-26` is header-only and no `AUTH` ID covers the other two carriers. See *Findings* below |

The bearer variant's `stamp` implements `AUTH-34`'s double-checked single-flight: read `@token`
(an instance variable, written only under `@lock`) with no lock; if valid-and-fresh (`AUTH-35`
validated, not expired with the refresh margin), stamp it; otherwise acquire `@lock` (a per-credential
`Thread::Mutex`, `XCUT-12`'s scope), re-check under the lock, and if still needed call
`@provider.fetch` **while holding the lock** — `XCUT-12`'s explicitly sanctioned exception to "never
hold a mutex across a suspension point," because the fetch is exactly the operation the single-flight
coordination exists to serialise, and it is scoped to one credential's own lock so it can never
serialise unrelated requests. `AUTH-35`'s validation (non-nil, not already-expired-with-no-margin)
runs on the fetched result before it is written into `@token`; a raise from `@provider.fetch`
propagates with `@token` untouched, so a later request retries the fetch (`AUTH-35`'s "MUST NOT be
cached").

`AUTH-36`'s eviction — on a 401 whose challenge advertises `Bearer`, evict **only** the exact cached
token that produced it, matched by comparing the stamped header value — is a compare-and-clear under
the same lock: `@lock.synchronize { @token = nil if @token && stamped_header_for(@token) ==
rejected_header }`, so a token another request already refreshed (and which therefore no longer
equals the rejected header) survives.

### `Dexpace::Auth::AsyncStep` — `AUTH-27`–`AUTH-38` on the async runtime

Same `#stage`, same `#call(request, cursor) -> Future` shape as every other async pillar step. Its
whole body runs inside one `Completer`-backed frame (`R12`'s closing paragraph): the HTTPS guard, the
challenge hook, and the bearer three-zone policy (`R12`'s mechanism) all settle the one returned
`Future` rather than raising synchronously, uniformly, which is what makes `AUTH-38`'s SHOULD true
without a scheduler-presence branch anywhere in this class. `AUTH-36`'s bearer 401 branch is mirrored here with one addition `AUTH-37` makes explicit: **the
post-eviction path MUST await a genuinely fresh fetch**, so the retry can never re-send the token the
server just rejected. `AsyncBearerStamper#stamp_fresh(request) -> Future` is that method — it bypasses
the three-zone read entirely and settles on a coalesced fetch — and `AsyncStep` calls it, never
`#stamp`, after an eviction. `AUTH-31`'s replayability gate is applied
identically on this path — `RETRY-34`'s sync/async uniformity (§11.12, item 13 of the segmentation
design's spec-forced boundaries) extended to `AUTH-31` by the same reasoning §11.12 already gives:
"toward the stricter, uniform behaviour, each through a single shared implementation." Concretely,
both `Step#call` and `AsyncStep#call` call the same private `replayable?(request)` helper
(`request.body.nil? || request.body.replayable?`) rather than each writing the check independently —
one implementation, two drivers, the same shape `6a`'s retry step and the pillar-step runtime already
use for their own shared logic.

## The spec-forced boundaries, honoured

Restated only where `6c`'s object model above is the direct consequence, from the segmentation
design's own numbered list:

1. **The AUTH pillar step forks for every drive, including the first, and never calls
   `Cursor#call`.** `Step#call` above forks unconditionally before its first downstream drive and
   again for `AUTH-30`'s replay — there is no code path where `cursor.call` is invoked on the cursor
   `6c`'s step was handed.
2. **The cross-origin marker is cursor state, never a header.** `cross_origin?` reads
   `cursor.state(Stages::REDIRECT)`; `6c` writes nothing to the request and strips nothing.
8. **`Dexpace::BoundedMap` is reachable only from a full-nesting form.** `DigestHandler`'s nonce
   store is created inside `module Dexpace; module Auth; class DigestHandler`, satisfying the
   condition as argued in *Module layout* above.
9. **Basic is `["u:p"].pack("m0")`; Digest is `Digest::MD5`/`Digest::SHA256`.** `BasicHandler` and
   `DigestHandler::HASHES` above; no `Base64`, no `OpenSSL::Digest`.
10. **`SecureRandom` for the cnonce, never `Random`.** `DigestHandler#initialize`'s
    `cnonce_source: ::SecureRandom` default, used via `#hex(16)`.
13. **`AUTH-31` applies on both the sync and async paths, through one shared implementation.**
    The shared `replayable?` helper both `Step` and `AsyncStep` call.

## Cross-cutting constraints that bite 6c specifically

- **`Thread::Mutex` is per-fiber-owned and non-reentrant; hold it across the flag flip only, except
  the one sanctioned exception.** `DigestHandler`'s nonce increment holds `BoundedMap`'s internal
  lock only across the get-and-increment (`#update`'s own contract). The bearer step's hot-path read
  takes no lock at all (`XCUT-12`); its refresh acquires the lock and — the one sanctioned
  exception, stated in `XCUT-12`'s own text and quoted in the segmentation design — holds it across
  the blocking `#provider.fetch` call, deliberately, scoped to one credential.
- **`downcase`/`casecmp?` take no arguments, everywhere.** `Scheme` comparisons, the challenge
  parser's scheme/parameter-name lower-casing, `BasicHandler`'s and `DigestHandler`'s scheme checks —
  all locale-independent by construction, never `downcase(:turkic)` or a locale-aware `casecmp`.
- **Regexp timeouts are per-pattern, never process-global — discharged by not writing the regexp.**
  `Challenges.parse` is a `StringScanner`-driven state machine; the one place a pattern appears
  (`scan_token`'s token-character class) is a fixed, non-backtracking character class, not a pattern a
  hostile header could drive into pathological backtracking.
- **`Ractor` is never load-bearing.** `AUTH-7`'s stateless resolver and `AUTH-24`'s thread-safe
  handlers are `Data`/frozen-constant shaped exactly as phase 4 and `6a` are; Ractor-shareability is a
  free side effect, never part of the claim.
- **Bytes on the wire are `Encoding::BINARY`.** `DigestHandler#materialize` tags its result `.b`
  after the UTF-8/ISO-8859-1 branch resolves, so the hash input is binary before it reaches
  `Digest::MD5`/`Digest::SHA256`, matching `HTTP-13`'s house rule for outbound bytes.

## Convergence points

Only convergence point 1 from the segmentation design touches `6c`: the end-to-end cross-origin
credential-leak test needing `6b`'s real REDIRECT step. `6c`'s own tests (Task 13 below) are complete
against phase 4c's `ForkingProbe` doubling a REDIRECT-stage fork with the marker set and unset; the
end-to-end test with `6b`'s real step is named as Task 14, owned by `6c` under the segmentation
design's "whichever of `6b`/`6c` lands second" rule and the recommended order (`6a → 6b → 6c`).
`RETRY-14`'s and `Pipeline.standard`'s convergence points are `6a`'s and the phase-level task's (`6b` Task 13a) respectively and
do not touch `6c` at all.

## Testing strategy

TDD throughout: each task's tests are written and confirmed failing before the implementation lands,
per `CLAUDE.md`'s workflow rule. Three kinds of test recur across `6c`'s tasks:

1. **Pure-function/data tests**, requiring nothing else in the repository beyond phases 0–3's model
   primitives — `Scheme`, `Requirement`, `Descriptor`, `Resolver`, the four credential types,
   `Challenge`/`Challenges`.
2. **Handler tests against RFC 7616's own test vectors** for Digest (the classic `Mufasa`/`circle of
   life` MD5 vector, asserted against the `qop=auth` challenge it is actually a vector for, plus a
   separately computed legacy no-`qop` expectation; and both SHA-256 expectations **derived** from
   RFC 7616 §3.9.1's inputs rather than transcribed from its printed response, which is 63 hex
   characters and cannot be a SHA-256 digest) and against verified fact 1 for Basic.
3. **Pillar-step tests against phase 4c's test doubles** — `ForkingProbe` standing in for REDIRECT to
   exercise `AUTH-29`'s two branches, and a bare `Cursor.build` plus a stub downstream step standing
   in for the rest of the pipeline for `AUTH-27`, `AUTH-28`, `AUTH-30`–`AUTH-38`. No real transport,
   no real network, throughout — every 401/response fixture is a `Dexpace::Response` built in-memory.

The nonce-counter concurrency test (`AUTH-24`) follows 4c's own measured-rather-than-assumed
discipline: a fixed-thread-count, fixed-iteration-count assertion that the final count equals the
number of successful increments exactly, run on the matrix, not a timing-sensitive race detector.

## The interface surface later phases may cite

| Consumer | What it gets, and the obligation |
|---|---|
| **Phase 7**, on pagination/SSE | Nothing from `6c` specifically; `AUTH`'s pillar step sits inside the pipeline a paginator wraps unmodified. |
| **Phase 8**, on `TRANSPORT-1`/`TRANSPORT-2` | `Stages::AUTH` as one of the two stages an adapter's own native mechanism must be disabled in favour of — `6c` is not itself cited beyond confirming the stage exists and is occupied. |
| **Phase 9**, on `XCUT-14`'s audit | `Dexpace::BoundedMap`'s second consumer (`DigestHandler`'s nonce store), confirming "one implementation" holds under the full-nesting condition, per-handler-instance rather than process-wide. |
| **Phase 9**, on `NFR-11`'s RBS scan | `Dexpace::Auth::BearerProvider` as the one documented duck-type interface `6c` names without enforcing via `include`. |

## Deviation Ledger

Numbering continues from the highest `P6-<n>` any sibling sub-phase design has claimed as of this
writing; none has, so this ledger starts at `P6-1`. A sibling sub-phase design may claim a lower
number first if it lands first — this is a naming collision risk inherent to three sub-phases writing
ledgers concurrently, and is resolved at consolidation into design §10, not here.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P6-1 | `AUTH-21`'s ISO-8859-1 branch is a raising path, surfaced as a typed `Dexpace::Auth::UnencodableCredentialError` rather than `:replace` or a bare `Encoding::UndefinedConversionError` | `AUTH-21`; design §6.3's own "the default Digest branch is a raising path" observation | Argued in full under `R10`. `:replace` produces a silently wrong Digest response the server rejects with no diagnostic; a bare raise gives no `Dexpace::` type, field name, or target encoding to act on. |
| P6-2 | The challenge-handler protocol is one method, `#authorization_for(challenges, request, proxy:) -> String \| nil`, not a separate `#can_handle?` query plus a build call | `AUTH-23`, `AUTH-25`; `api-design/b0e18938` | Behaviourally identical to a two-method protocol; halves the public surface `NFR-4` locks. |
| P6-3 | `Dexpace::Auth::PasswordCredential` performs no construction-time validation; `AUTH-14`'s laxer non-empty check is applied by `BasicHandler`/`DigestHandler` at use time | `AUTH-9` (which does not name this type), `AUTH-14` | `AUTH-9` enumerates exactly three types; applying its stricter non-blank rule to a fourth would silently over-apply a rule the requirement does not extend to it. |
| P6-4 | The Digest nonce-counter store is owned by the `DigestHandler` instance, not by a process-wide or class-level singleton | `AUTH-19`, `AUTH-24`; `data-modeling/3e37c086` | Argued in full under `R11`. One handler per credential/realm is the natural unit; a shared singleton would let one server's nonce rotation evict another's live nonce for no requirement-driven reason. |
| P6-6 | `Dexpace::Auth::Validation.non_blank!` raises a **second** construction-failure message form, `"<name> must not be blank"`, beside `SEAM-29`'s `"<name> is required"` | `AUTH-9`, `SEAM-29`; phase 1's `Model.required!` | `Model.required!` fires only on `nil`; `AUTH-9` requires blanks rejected too. The two forms do not overlap — a missing field still reads `"<name> is required"` — so `SEAM-29`'s single form for a missing field is preserved rather than widened. |
| P6-7 | `AUTH-31`'s replayability gate is applied to `AUTH-36`'s eviction-driven bearer retry as well, which `AUTH-36` does not require | `AUTH-31`, `AUTH-36`; §11.12 | A non-replayable body cannot be sent twice whichever of the two 401 paths re-drives it; §11.12 already resolves the four sync/async drifts "toward the stricter, uniform behaviour, each through a single shared implementation". Strictly narrows what is sent, never what is accepted. |
| P6-5 | "Kick off an off-thread background refresh" (`AUTH-37`) is implemented as calling the provider's async fetch and attaching `#on_settle` without awaiting it — no thread is spawned by phase 6 itself | `AUTH-37`, `AUTH-11`; `Dexpace::Async::Future#on_settle` | Argued in full under `R12`. The SDK owns no thread pool; "off-thread"-ness is a property of the caller's provider implementation, exactly as `AUTH-11` already establishes for the default-mirrored case. |

### As built, 2026-09-18

P6-1 through P6-7 stand as written; every one is implemented as its row says, and the plan's
open-question answers were carried through — the SHA-256 expectations derived and never transcribed,
the constants namespaced, `KeyStamper` and `BasicHandler#call` shared by both runtimes. This phase was
cut from `main` at `f1fe848`, which holds all of phase 5 and nothing of phase 6a, so the `Cursor`
context-bundle widening was consumed not at all and the step takes its own `logger:`. Execution added
the rows below, numbered from **P6-71** because the three phase-6 lanes are numbered apart — 6a's
as-built additions start at P6-51, 6b's at P6-91 — and the design's own P6-1–P6-7 knowingly collide with
6a's P6-1–P6-12, which the roadmap's 2026-09-10 catch-up entry records and phase 10's consolidation
resolves; outside this document every citation reads "6c's P6-n". The checklist's "Deviations from
the plan" is the itemised list against the plan's text; the rows here are the ones that touch public
behaviour, the contract a later phase cites, or a statement this document makes.

Five statements above read differently against the source, and the difference is recorded here
rather than by rewriting the text it corrects:

- **The pinned constructor is `Step.build`, not `Step.new`, and it has no `redactor:` keyword.** Phase
  5b's step took `.build` with `.new` private (P5-34) and one redactor per path — the logger's (P5-95);
  the built step follows both. It emits no log event of its own, so `redactor:` would have been a
  keyword nothing reads, which is the argument this document itself makes against `refresh_margin:`
  on the step. `logger:` stays, because a superseded 401 is closed through `Dexpace.close_quietly` and
  §3.7's second disposal route needs somewhere to report a close failure (P6-71).
- **`AUTH-8` has three renderings, not two.** The object model's "`#to_s`/`#inspect` both redact" is
  one short for a `Data`: `pp` walks the members. Both `Data` credentials override `#pretty_print` too
  (P6-72), and `docs/knowledge/notes/authentication.md` records the fact against the corpus's rule.
- **`Dexpace::Auth::Replayability` does not exist.** The layout's public module became one private
  predicate on `Step` that `AsyncStep` inherits — still "one implementation, two drivers", with no third
  public spelling of the predicate beside 6a's and 6b's (P6-80).
- **`BearerProvider` is not documentation-only.** It ships `AUTH-11`'s default async fetch as a real
  function, which the plan never wrote (P6-81).
- **The three `Auth::` errors are filed under `lib/dexpace/auth/`**, not flat under `error/`: the constant
  path decides the file path, as phase 2's `Serde` errors sit under `serde/` (P6-82). The resolved open
  question 2 above stands for the constants and not for the files.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P6-71 | `Dexpace::Auth::Step.build(stamper:, challenge_hook: NO_REPLACEMENT, logger: Instrumentation::Logger::NULL)` with `.new` private, frozen, the same three keywords on `AsyncStep` — no `redactor:`; the sync stamper is anything `Registry.callable?` accepts at arity 1 and the async step additionally accepts an object answering `#stamp(request) -> Future`, adapting a `#call`-shaped one into a settled future | The pinned constructor above; 5b's P5-34, P5-95; `AUTH-27`, `AUTH-30` | One construction shape per phase since 5b; a keyword nothing reads is a signature NFR-4 locks for no reason; a sync `BearerStamper`, `KeyStamper` or `BasicHandler` installed on the async step should work, and does |
| P6-72 | `BearerToken` and `PasswordCredential` override `#pretty_print(printer)` beside `#to_s` and `#inspect` | `AUTH-8`; design §6.3's two-rendering sentence; `docs/knowledge/notes/authentication.md` | `pp` gives a `Data` its own `#pretty_print` over `members` and never calls `#inspect` (verified on every supported Ruby); `pp token` printed the secret with the two overrides alone |
| P6-73 | `PasswordCredential#to_s`/`#inspect`/`#pretty_print` redact the username as well as the password; `NamedKeyCredential#name` stays visible | `AUTH-8`; phase 5a's checklist item 24 (`CFG-22`) | The username is half of the value Basic puts on the wire and `AUTH-8` does not list it among the non-secret fields that MAY remain visible; 5a's review masked the proxy username for the same pair. The key NAME is on `AUTH-8`'s visible list and is the half a caller needs to tell two credentials apart |
| P6-74 | `Challenges.parse` scans a header value whose bytes are invalid under its own tag as BINARY, and keeps a valid value's tag | `AUTH-13`; `HTTP-19` (inbound values admit obs-text and carry the transport's tag) | `StringScanner#scan` and `String#downcase` both raise `ArgumentError` on a UTF-8-tagged String with an invalid byte, so the plan's fence would have raised from the parser `AUTH-13` says never raises |
| P6-75 | `BasicHandler` refuses a username containing `:` and transcodes the `username:password` pair to UTF-8 before `pack("m0")` | `AUTH-14`; RFC 7617 §2 | A colon makes the pair unparseable by the server, silently; the requirement names "UTF-8 bytes of `username:password`", and a Latin-1-tagged credential would otherwise pack Latin-1 bytes |
| P6-76 | `DigestHandler` sends a non-ASCII username as RFC 7616 §3.4's `username*=UTF-8''<pct-encoded>` (hashing the raw username), declines a challenge whose `realm`, `nonce` or `opaque` the outbound header grammar cannot carry, and matches the `algorithm` token case-insensitively | `AUTH-16`, `AUTH-22`, `AUTH-25`; `HTTP-18` | `HTTP-18` refuses a byte above 0x7F in an outbound value, so RFC 7616 §3.9.1's `username="Jäsøn Doe"` cannot be stamped as printed; `username*` is the RFC's own wire form for it, and RFC 7616 defines no encoded form for the three echoed values, so a challenge carrying one is unsatisfiable rather than an `InvalidArgumentError` out of the hook |
| P6-77 | `Instrumentation::Events::AUTH_REFRESH = "http.auth.refresh"`, the ninth event and the first outside the `http.instrumentation.` prefix; `AsyncBearerStamper.new(…, logger: Logger::NULL)` reports a failed background refresh through `Instrumentation.diagnostic` at WARNING with the cause | `AUTH-37`'s "log-and-continue"; `OBS-39`, `OBS-20` | The requirement asks for a log; the vocabulary home is 5b's `Events`, extended in place rather than split across namespaces; the diagnostic runs inside `Instrumentation.contain`, so a raising sink cannot fail the refresh callback either |
| P6-78 | `AsyncStep`'s challenge hook may answer a `Dexpace::Async::Future` of a replacement (or of nil) as well as a request or nil; a failed hook future closes the 401 and fails the step's future | `AUTH-32`'s three clauses ("its async future completes exceptionally"), `AUTH-30` | Without it the second of `AUTH-32`'s three clauses has no path on this port |
| P6-79 | Every inner future the async step watches — the stamp, the drive, the re-stamp, the hook's future, the replay — is registered through one `observe(future, completer)` that runs the settlement inside the frame, forwards a cancellation as a cancellation, and cancels the inner future when the step's future is cancelled | `SEAM-18`, `ASYNC-6`; 4c's `Future#then` rules | The first draft wired cancellation only on the cross-origin path; cancelling the step's future left the transport's drive running |
| P6-80 | No `Dexpace::Auth::Replayability`: `AUTH-31`'s gate is one private `Step#replayable?` that `AsyncStep < Step` inherits | `AUTH-31`; spec-forced boundary 13; `api-design/b0e18938`; `NFR-4` | 6a's `Resend.eligible?` and 6b's `Resend.replayable_body?` are already two public spellings of the same predicate; a third, NFR-4-locked, buys nothing over an inherited method, and the sharing between the two runtimes is inheritance, 5b's P5-34 shape |
| P6-81 | `Dexpace::Auth::BearerProvider` is a module with two functions, `.fetch_async(provider)` and `.conforms?(provider)`, beside the two RBS interfaces `_BearerProvider` and `_AsyncBearerProvider`; `.fetch_async` never raises: a `#fetch`-only provider mirrors into a settled or already-failed future, a nil token into a failed `ProviderError` future, a `#fetch_async` override's synchronous raise or non-`Future` return into a failed future | `AUTH-11`; `NFR-11` | The requirement's own text fixes the default async fetch and the normalisation, and the plan wrote neither; the interfaces are what the scan can name |
| P6-82 | `unencodable_credential_error.rb`, `https_required_error.rb` and `provider_error.rb` live under `lib/dexpace/auth/`; `bounded_map.rb` gains a true `test/` mirror (`bounded_map_test.rb`) and leaves `CLAUDE.md`'s private-constant exception list as `auth/validation.rb` joins it | Resolved open question 2 (files); phase 4a's P4-3; `XCUT-14` | The constant path decides the file path (phase 2's `serde/`); `#update` is the first `BoundedMap` method with no consumer of its own to assert it through, and `AUTH-24`'s deterministic proof needs the map directly |
| P6-83 | `Requirement.build(scheme:)` resolves a String, a Symbol or a copied constant through `Scheme.of`; `Descriptor.build(requirements:)` is keyword-shaped; `Scheme::ALL` is public with `.[]` hidden beside `.new`; `Challenge.build` is the one place the scheme and parameter names are folded and exposes `#token68`; the resolver's `available_schemes` are resolved the same way | `AUTH-1`–`AUTH-5`, `AUTH-12`; design §4's construction pattern; `HTTP-3`'s `#with` | `Model#with` is `self.class.build(**to_h, **changes)`, so a positional `.build` breaks derivation; a `Data`'s generated `.[]` is a second public constructor; one fold point means a hand-built and a parsed challenge meet a handler in one shape |


## Work phase 6c postpones, and who owns it now

**None.** Every one of `6c`'s 38 IDs is implemented in full (`AUTH-29`'s stripping clause satisfied
by construction, not deferred — it has no code because nothing is ever added to strip). `6c` carries
no ⏳ row, matching the segmentation design's own statement that `6c` is the only sub-phase of phase
6 none of whose IDs is declined or postponed.

### Items earlier phases postponed that touch `6c`

The roadmap's execution step 1 requires every outstanding deferral read and dispositioned; the segmentation design
already performed this sweep at phase scope and this document does not repeat it. Two items the
segmentation design named as touching `6c`'s area are confirmed here and neither changes:

- **Wire-boundary re-validation of header names and outbound values** — untouched by
  `6c`, confirmed: it is phase 8's (phase 8a Task 16 and phase 8c Task 9, with the portable assertion in phase 9 Task 7),
  and `6c`'s stamped `Authorization`/`Proxy-Authorization` values
  are among the values that re-validation will eventually cover. `6c` builds no second validation
  pass of its own.
- **The context store's configured cap** (phase 4a's deferral, picked up by phase 5a Task 13) — confirmed **not** to
  extend to `AUTH-19`'s cap, per `R11` above. No new deferral is
  filed in its place, because `6c`'s cap needed no configuration-chain route to begin with.

## Findings, and who owns them now

Two, each with the owner that carries it. **Not acted on by this document, and no file outside
`docs/work/mvp/phase6/phase6c/` is edited by it.**

**Owner: `docs/first-release.md` § Blockers before first publish — a standing decision line in the shape of the
existing `HTTP-22`/`HTTP-48`/`HTTP-49`/`HTTP-50` line, carrying the verdict below and naming the reopening
event: the first phase that builds Operation-level request construction.**
**`AUTH-4`–`AUTH-7`'s tier resolution presupposes a producer for its three inputs that no phase
names.** The resolver takes a per-call, an operation, and a client `AuthDescriptor`, in that
preference order, and `6c` ships it as a correct, tested, stateless pure function. What no phase —
not 1 through 5, and not `AUTH`'s own 38 IDs — specifies is where a per-call or operation-level
`AuthDescriptor` is carried: `docs/sdk-design-ruby/` names no field on `Request`, `RequestOptions`, or
any `Operation` construct for it, and no `AUTH` requirement asks for one (`AUTH-1`–`AUTH-7` describe
the descriptor and the resolver as data and a function, never a carrier). `6c` ships the AUTH pillar
step accepting an already-resolved credential (or a caller-supplied `Scheme => credential` table) at
construction time, treating the resolver as a standalone library object whose caller — presumably
Operation-building code, which is outside `AUTH`'s scope entirely — is responsible for invoking it
and threading the result into the step. If that Operation-level wiring is never built in any later
phase, `AUTH-4`–`AUTH-7`'s resolver ships correct and exercised only by its own unit tests, never by
an end-to-end call path. This is the same shape the phase-5 charter's `OBS-19` cell, its `OBS-24` arithmetic
and `6a`'s Task 8 cursor widening all have — a sentence that reads correctly and resolves to something not yet
built — and it is recorded here as a candidate rather than assumed settled by shipping the resolver alone.
Cites: `AUTH-1`, `AUTH-4`, `AUTH-5`, `AUTH-6`, `AUTH-7`.

**Owner: `docs/first-release.md` § What v1 ships without — a line naming the reopening event.**
**An `apiKey` credential carried in a query parameter or a cookie has no AUTH-step path, and that is a
purpose-fit gap rather than a missing implementation.** `AUTH-26` is explicit and header-only ("static
key-credential stamping MUST write the key value into the credential's configured **header**"), and no
`AUTH` ID names a query or cookie carrier; `AUTH-1`'s scheme set has one `API_KEY` member and does not
distinguish the three. OpenAPI's `apiKey` scheme admits `in: header | query | cookie`, so a generator
targeting a query-keyed API can still send the credential — it builds the query itself, at the
Operation layer — but it then loses everything the AUTH step is for on that credential: `AUTH-28`'s
HTTPS guard, `AUTH-29`'s cross-origin suppression (the query survives a redirect re-issue that
`REDIR-7` would have stripped a header on), and `AUTH-8`'s redaction. That makes it a **release
decision with a security consequence**, not a feature request: v1 either states that query- and
cookie-carried API keys are outside the AUTH layer, or a later phase widens `AUTH-26`'s carrier. The
event that would reopen it is **the first consumer that needs one — a worked example in
`docs/sdk-documentation/`, a `dexpace-conformance` fixture, or a downstream SDK's `SEAM-26` operation
projection carrying a non-header `apiKey`**. Widening `AUTH-26` is a specification change and is not
`6c`'s to make. Cites: `AUTH-1`, `AUTH-8`, `AUTH-26`, `AUTH-28`, `AUTH-29`, `REDIR-7`.

## Open questions for 6c's own plan

1. **Resolved, and the resolution is not "lift the RFC".** The SHA-256 worked example is RFC 7616
   **§3.9.1** (§5 is Security Considerations and carries no vector), and its printed `response` could
   not be reproduced on 3.4.10 from the example's own inputs. Both the plan's SHA-256 and
   SHA-256-sess expectations are therefore **derived here** with `Digest::SHA256` from the RFC's
   inputs and committed as 64-hex values that were actually produced, with the derivation printed in
   the task so it can be re-run. The MD5 vector is RFC 2617 §3.5's and is genuine — but it is the
   **`qop=auth`** form (`nc=00000001`, `cnonce="0a4f113b"`), so it is asserted against a `qop=auth`
   challenge and a fixed cnonce source, and the legacy no-`qop` expectation is computed separately.
2. **Resolved.** Every error **file** is flat under `lib/dexpace/error/` (`P1-1`'s precedent), while
   the **constant** is namespaced where the requirement scopes it: `Dexpace::AuthResolutionError` is
   flat because `AUTH-6` describes a general resolution failure, and
   `Dexpace::Auth::UnencodableCredentialError`, `Dexpace::Auth::HTTPSRequiredError` and
   `Dexpace::Auth::ProviderError` are under `Auth` because each names a condition only this subsystem
   can raise. File placement and constant nesting are independent here and the module layout above is
   the authority for both.
3. **Resolved.** `KeyStamper` and `BasicHandler#call` perform no I/O, no fork and touch no cursor, so
   both runtimes call the identical object; only `BearerStamper`/`AsyncBearerStamper` are a pair, and
   they are a pair because only they fetch.
