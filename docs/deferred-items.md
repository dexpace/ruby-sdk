# Deferred Items

Register of work consciously postponed while building the Ruby SDK. A deferral is a decision made
**before** the work: "not this phase, that one" — or, for the MVP-scope entries seeded below,
"not this release, a later one." Compare against the other two registers at the `docs/` root:

| Register | Holds | Item is |
|---|---|---|
| `deferred-items.md` (this file) | Work consciously postponed while building the SDK | A decision made **before** the work |
| [`open-items.md`](./open-items.md) | Everything found unmet, unverified, misreported, or surprising | A gap discovered **after** the work |
| [`deviations.md`](./deviations.md) | The as-built audit of `sdk-design-ruby/10`'s deviation ledger | A place the port deliberately differs from the reference contract, and whether that has landed in code |

The same requirement ID can legitimately appear in more than one register at once.

## Item format

```
### DEF-<n> — <title>

- **Deferred by:** <phase>, <date>
- **Why:** <what would have to be true for this to be worth doing now, and why it isn't yet>
- **Pick-up condition:** <the trigger that makes this worth revisiting>
- **Cites:** <requirement IDs this touches, comma-separated, or "none">
- **Status:** deferred | picked-up (<date>, <phase>)
```

## The rule

Item IDs are **permanent**: never renumbered, never reused, cited from source comments, tests, and
design documents as well as from this file. A deferral that is later picked up is never deleted —
`Status` moves to `picked-up (<date>, <phase>)` and the row stays, so a citation of `DEF-<n>`
written while the work was still deferred continues to resolve to something.

A new deferral takes the next id below and appends.

---

## Seeded from the MVP-scope design

Nineteen entries below are seeded from the Ruby design's own record of what the MVP declines to
build, so that a decision already made in the design carries forward into a register a citation
can point at, rather than living only in prose inside a frozen chapter. All nineteen predate any
phase — the design was locked 2026-09-05, before implementation started — so each is recorded
against the design pass itself rather than an implementation phase.

### DEF-1 — SEAM-24, SEAM-28: cross-thread diagnostics and a stable operation identifier

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** Both are below MUST level. SEAM-24 (SHOULD) asks for cross-thread diagnostic-context
  propagation beyond fiber-local storage; SEAM-28 (MAY) asks for a stable operation identifier on
  the projection. Neither is needed for the fiber-local context storage the MVP ships.
- **Pick-up condition:** SEAM-24 ships together with `dexpace-async-async` (see DEF-11).
  **SEAM-28 targets phase 5 (Configuration and Observability)**, named by phase 2's register sweep
  on 2026-09-07 — it had no trigger, and "picked up opportunistically" was not a condition any
  phase could meet.
- **Cites:** SEAM-24, SEAM-28
- **Status:** deferred. Phase 2 owns both IDs and ships the gem they would live in, and built
  neither. **SEAM-28 is not UNSCHEDULED**: that status is for a row whose pick-up condition a phase
  *met* and declined to act on, and this row's condition never fired, because the opportunity does
  not exist yet. Both halves of the MAY need machinery phase 2 does not have — the request's
  context chain (`CTX`, phase 4) for "attached to the request's context chain", and a consumer for
  the identifier (instrumentation, phase 5) for "for instrumentation/tracing" — and **phase 5 is
  the first phase that has both**, which is why it is the target rather than phase 4. Phase 2 does
  fix the contract SEAM-24's cancellation half will map in both directions:
  `Dexpace::Cancellation` in one and `Dexpace::Async::Completer#on_cancel` in the other.

### DEF-2 — HTTP-22, HTTP-48, HTTP-49, HTTP-50: name interning and ETag/Range/conditional-request helpers

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** HTTP-22 (MAY) is header-name interning. HTTP-48–HTTP-50 (SHOULD) are convenience
  helpers layered on the header model that already exists; none of the four changes what the MVP's
  HTTP domain model is required to do.
- **Pick-up condition:** originally none. **Target: phase 6 (Retry, Redirect and
  Authentication)**, named by phase 1's register sweep on 2026-09-05 — that is where the helpers
  first get a caller, because a re-issued request carries `If-Match`/`If-None-Match` (HTTP-50's
  aggregator) and an entity-tag (HTTP-48). Until then they are unbuilt SHOULDs and a MAY, and
  `docs/first-release.md` carries them in its readiness list so a release decision sees them
  without reading this register.
- **Cites:** HTTP-22, HTTP-48, HTTP-49, HTTP-50
- **Status:** deferred. Phase 1 owns all four IDs and ships the gem they would live in, and built
  none of them: HTTP-22 is a MAY whose observable contract (value equality by folded name) already
  holds without interning, and HTTP-48–HTTP-50 are SHOULD-level helpers over a header model that
  has no caller for them yet. **Not UNSCHEDULED**: that status is for a row whose pick-up condition
  a phase met and declined to act on, and this row's condition — convenience helpers prioritized
  over minimal public surface — never fired, because phase 1 deliberately kept the surface minimal.
  What the row lacked was a target phase, which the sweep supplied.

### DEF-3 — BODY-36, BODY-12: memory-mapped view and platform zero-copy file transfer

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** BODY-36 (MAY) has no stdlib mmap to build on. BODY-12 (SHOULD) platform zero-copy file
  transfer is an optimisation over the file-backed body the MVP already ships correctly, just not
  zero-copy.
- **Pick-up condition:** **BODY-12, clause 1 — met and discharged by phase 3b, 2026-09-08.** The
  file-backed body's write is `::IO.copy_stream(handle, sink, count, offset)`, verified on 3.2.11,
  3.4.10 and 4.0.6 to accept a duck-typed `#write` destination, honour the `(length, offset)` window,
  leave the source handle's own cursor untouched, and return the byte count that gives `BODY-13` its
  short-write detection. **BODY-12, clause 2 — the transport recognising a file-backed body by type
  and dispatching a true zero-copy kernel path — targets phase 8**, alongside `DEF-10`, which is the
  same feature seen from the transport side; phase 3b discharges the body-layer half of it by making
  `Dexpace::FileBody` a named public class exposing `#path`, `#offset` and `#count` (and deliberately
  *not* `#to_path`, which would make `IO.copy_stream(body, sink)` copy the whole file and ignore the
  body's window). **BODY-36 — core's dependency budget changes.** Ruby's standard library has no
  `mmap`; the only routes are a C extension or the `mmap` gem, both barred from `dexpace-core` by
  `SEAM-1`/`NFR-1`, so this names the **event** rather than a phase and no phase in v1 can meet it.
  Recorded so a later reader does not mistake an unmeetable condition for a forgotten one. Both
  sharpenings were stated by the phase-3 segmentation design's deferral sweep and are performed here
  by phase 3b, which owns both IDs.
- **Cites:** BODY-36, BODY-12, BODY-11, BODY-13, TRANSPORT-28
- **Status:** deferred (BODY-12 clause 1 discharged 2026-09-08, phase 3b)

### DEF-4 — PIPE-36: pillar-step stage locking

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** SHOULD-level. Post-MVP per the design's own coverage index.
- **Pick-up condition:** post-MVP; no narrower trigger named yet.
- **Cites:** PIPE-36
- **Status:** deferred

### DEF-5 — RECOV-31: per-attempt ordinal header

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** MAY-level. The same feature as RETRY-38 (see DEF-6); a single feature, deferred from
  two requirement angles.
- **Pick-up condition:** picked up together with RETRY-38 if the per-attempt ordinal header
  feature is ever built.
- **Cites:** RECOV-31, RETRY-38
- **Status:** deferred

### DEF-6 — RETRY-29, RETRY-38, RETRY-43: server-driven retry override, attempt-ordinal header, fixed-delay mode

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** All three are below MUST level. RETRY-38's tag/prose conflict is recorded at design
  §11.10, separately from the deferral itself.
- **Pick-up condition:** no named trigger; revisit together if per-attempt observability
  (RETRY-38/RECOV-31, see DEF-5) is prioritized.
- **Cites:** RETRY-29, RETRY-38, RETRY-43
- **Status:** deferred

### DEF-7 — REDIR-27: configurable target header

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** MAY-level.
- **Pick-up condition:** no named trigger.
- **Cites:** REDIR-27
- **Status:** deferred

### DEF-8 — SSE-41: reactive-adapter error and lifecycle latitude

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** MAY-level, and scoped to a reactive (e.g. RxJS-analogue) adapter; the MVP ships only the
  pull-based SSE view and no reactive adapter.
- **Pick-up condition:** revisit if a reactive SSE adapter is ever built.
- **Cites:** SSE-41
- **Status:** deferred

### DEF-9 — OBS-32, OBS-37: OpenTelemetry metric conventions and async body-capture skip

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** Both SHOULD-level, and both presuppose infrastructure the MVP does not ship: OTel metric
  conventions need an OTel adapter, and the async body-capture skip needs the async-runtime bridge
  to have observability wired through it.
- **Pick-up condition:** land together with the OTel adapter (`dexpace-instrumentation-otel`, see
  DEF-17) and the async adapters (see DEF-11, DEF-12).
- **Cites:** OBS-32, OBS-37
- **Status:** deferred

### DEF-10 — TRANSPORT-28, TRANSPORT-30: zero-copy file body and undiscoverable proxy features

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** Both SHOULD-level and per-adapter; the MVP's two transports (`net_http`, `async_http`)
  do not need either to satisfy the transport contract.
- **Pick-up condition:** post-MVP; revisit when a transport adapter beyond the two MVP transports
  ships.
- **Cites:** TRANSPORT-28, TRANSPORT-30
- **Status:** deferred

### DEF-11 — Later gem: `dexpace-async-async`

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** Bridges the core async pivot to `Async::Task`. Per
  `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.2, a seam ships in the MVP together with
  one adapter that proves the property it exists for (`dexpace-async-thread` proves the pivot); a
  second adapter over the same property is a later gem, not an MVP one.
- **Pick-up condition:** when a reactor-native async adapter is needed beyond the
  thread-pool-backed `dexpace-async-thread`.
- **Cites:** none
- **Status:** deferred

### DEF-12 — Later gem: `dexpace-async-concurrent_ruby`

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** Bridges the core async pivot to `Concurrent::Promises::Future`. Same §2.2 rationale as
  DEF-11: a second adapter over an already-proven property.
- **Pick-up condition:** when `concurrent-ruby` interop is needed beyond `dexpace-async-thread`.
- **Cites:** none
- **Status:** deferred

### DEF-13 — Later gem: `dexpace-transport-httpx`

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** HTTP/2 without a reactor. Per §2.2, the MVP's two transports
  (`dexpace-transport-net_http`, `dexpace-transport-async_http`) already prove the synchronous and
  asynchronous transport-seam properties; `httpx` would be a third transport over properties
  already proven.
- **Pick-up condition:** when HTTP/2 support is needed without adopting a reactor.
- **Cites:** none
- **Status:** deferred

### DEF-14 — Later gem: `dexpace-transport-excon`

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** Same §2.2 rationale as DEF-13: an additional transport adapter over an already-proven
  seam.
- **Pick-up condition:** when `excon` interop is requested.
- **Cites:** none
- **Status:** deferred

### DEF-15 — Later gem: `dexpace-transport-typhoeus`

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** Same §2.2 rationale as DEF-13/DEF-14.
- **Pick-up condition:** when `typhoeus` interop is requested.
- **Cites:** none
- **Status:** deferred

### DEF-16 — Later gem: `dexpace-serde-oj`

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** `dexpace-serde-json` already proves the serde seam with the reference wire codec; `oj`
  would be a faster codec over an already-proven seam, not a new property.
- **Pick-up condition:** when JSON throughput is identified as a bottleneck the stdlib `json` gem
  cannot meet.
- **Cites:** none
- **Status:** deferred

### DEF-17 — Later gem: `dexpace-instrumentation-otel`

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** The MVP's instrumentation seam (§8.1) is duck-typed and already accepts an
  OpenTelemetry object with no adapter; a dedicated gem is packaging convenience, not a proof of a
  new property.
- **Pick-up condition:** when a first-class OTel integration (helpers, defaults, or bundled
  wiring) is worth shipping as its own gem.
- **Cites:** OBS-32 (see DEF-9)
- **Status:** deferred

### DEF-18 — ASYNC-3, PIPE-33's interrupt clause: cancel-with-interrupt against a blocking worker

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** Both are MUST-level requirements this port does not satisfy — see
  `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` item 5 and
  `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md`. Ruby's §8.3 prohibition on
  `Timeout.timeout`, `Thread#raise` and `Thread#kill` forbids landing an asynchronous interrupt on
  a worker thread, because it can land inside an `ensure` releasing a pooled connection. The
  check-after-resume rule and `Completer#on_cancel` mitigate but do not close the gap: a transport
  blocked inside an uninterruptible C-extension read cannot be aborted early.
- **Pick-up condition:** if an interruptible transport path is ever adopted.
- **Cites:** ASYNC-3, PIPE-33
- **Status:** deferred

### DEF-19 — The fence-checker analogue for `.claude/skills/housekeeping/`

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** The Node original ships a ninth housekeeping tool, `check-fences.mjs`, which extracts
  every fenced TypeScript example that imports from the workspace and typechecks it against built
  declaration files. `.claude/skills/housekeeping/SKILL.md` ("Deliberately not ported from the
  Node original") records why it is not ported as-is: the mechanism is a TypeScript compiler
  invocation, and Ruby has no equivalent build step to hang it on. The named Ruby analogue is not a
  typechecker but an **executor** — extract a ```ruby fence that `require`s a `dexpace-*` gem, run
  it under `ruby -w` with that gem's `lib/` on `$LOAD_PATH` and a stubbed transport, and assert it
  exits 0 with no warnings.
- **Pick-up condition:** needs published gems to point at, so it waits for them (per the SKILL.md
  note this deferral is drawn from).
- **Cites:** none
- **Status:** deferred

## Filed by phase 0 — Scaffold and Quality Gates

Every entry below names a target phase or an explicit pick-up condition, per the roadmap's
execution step 7.

### DEF-20 — The release path: signed publication and the release half of NFR-12

- **Deferred by:** phase 0, 2026-09-05
- **Why:** `NFR-16` asks for cryptographically signed artifacts with signing enforced on the
  release/CI path and gracefully optional locally. There is no release path: nothing is
  published, every gem is at `0.0.0`, RubyGems ownership is unsettled and trusted publishing is
  not configured (`docs/first-release.md`). A signing step wired to a path that does not exist
  would be a gate over nothing, which is the failure mode phase 0 is built to avoid. Phase 0
  does build `gates:reproducible`, so `NFR-12`'s build half is satisfied; the release half — a
  published artifact byte-identical to a rebuild from its tag — waits with the rest.
- **Pick-up condition:** the RubyGems-ownership and trusted-publishing blockers in
  `docs/first-release.md` close. No phase owns it; it is release-gated, like `DEF-19`.
- **Cites:** NFR-16, NFR-12
- **Status:** deferred

### DEF-21 — The runtime half of the version-skew guard

- **Deferred by:** phase 0, 2026-09-05
- **Why:** Design §2.3 pairs the `~> MAJOR.MINOR` constraint with a registration-time assertion
  on `Dexpace::VERSION`, so a mismatched core/adapter pair fails loudly at `require` time rather
  than at the first seam call. Phase 0 builds the static half — `gates:gemspec_audit` derives
  the expected constraint from `VERSIONS` and asserts every adapter declares it. The runtime
  half hangs on require-time seam self-registration, which is design §10 item 8 and phase 2's
  scope; defining a public `Dexpace.register` in phase 0 would fix an API phase 2 must be free
  to shape.
- **Pick-up condition:** phase 2 (Seam Foundations), with the registration call it belongs to.
- **Cites:** NFR-14, SEAM-5, SEAM-6, SEAM-7
- **Status:** picked-up (2026-09-07, phase 2). `Dexpace::Registry#register(key, factory, core:)`
  takes the adapter's `~> MAJOR.MINOR` requirement as a **required** keyword and raises
  `Dexpace::SeamError` naming the key, the requirement and `Dexpace::VERSION` on skew — required
  rather than optional, because an optional skew check is a skew check nobody passes. The
  comparison is hand-rolled and accepts only the two-segment pessimistic form design §2.3 mandates,
  refusing anything else rather than partially reinterpreting it: `Gem` is undefined under
  `ruby --disable-gems` (verified on 3.2.11 and 4.0.6) and `rubygems` is not on phase 0's require
  allowlist, so `Gem::Requirement` cannot be a runtime dependency. It appears in the **test**
  instead, where the comparison is cross-checked against `Gem::Requirement#satisfied_by?` over a
  grid of versions. Recorded as deviation P2-7. This is also what replaces `SEAM-10`, whose
  multi-loader de-duplication is vacuous in Ruby (design §10.9).

### DEF-22 — `dexpace-conformance`'s framework-agnostic assertion objects

- **Deferred by:** phase 0, 2026-09-05
- **Why:** Design §9.3 fixes the shape: each assertion is a callable that returns cleanly or
  raises a `Dexpace::Conformance::Failure` carrying the expected and actual values, with thin
  Minitest and RSpec drivers over it, so Minitest never becomes a runtime constraint on a
  consumer. Phase 0 creates the gem skeleton because the roadmap's phase-0 row lists all six MVP
  gems, and lays the test-directory convention and one shared Minitest base — but an assertion
  object with no transport contract to assert against would fix an interface before the
  contract it serves exists.
- **Pick-up condition:** phase 8, which owns this gem's gemspec, its version and its first
  release; phase 9 adds the remaining suites.
- **Cites:** none
- **Status:** deferred

### DEF-23 — A Steep target over a test tree

- **Deferred by:** phase 0, 2026-09-05
- **Why:** The styleguide holds test helpers to the same type discipline as `lib/`
  (`testing/de6fe7e3`), which this port answers in `docs/knowledge/notes/testing.md`: there is
  no Sorbet sigil to write, and a test tree gets RBS coverage only where the `Steepfile` names a
  test target. Phase 0 names six targets, one per gem, and none over `test/` — the only test
  code that exists is a shared base class and six smoke suites, and adding a seventh target over
  them would buy a checked `assert_equal` call.
- **Pick-up condition:** when a gem's test support becomes production-quality code worth
  checking — phase 8's conformance helpers at the earliest.
- **Cites:** NFR-3
- **Status:** deferred

## Filed by phase 1 — Core HTTP Domain Model

Every entry below names a target phase or an explicit pick-up condition, per the roadmap's
execution step 7.

### DEF-24 — The suppressed-exception trail on the error root

- **Deferred by:** phase 1, 2026-09-05
- **Why:** Design §5 gives `Dexpace::Error` a `#suppressed` array frozen once populated, a
  `#full_message` override that renders the trail, and a `Dexpace.attach_suppressed(primary,
  secondary)` helper carrying RETRY-34's self-suppression guard. Phase 1 creates the root — and
  fixes its shape, a module rather than a base class, so XCUT-4's "transport errors belong to the
  runtime's I/O-error family" stays reachable under Ruby's single inheritance — but ships it
  empty. The trail exists for RECOV-12's close-while-throwing rule and for PAGE-13/PAGE-15,
  SSE-29/SSE-36 and RETRY-34; none of those has a caller until the recovery chain lands, and an
  attach helper with no chain to attach in would fix an interface before its first use.
- **Pick-up condition:** phase 4 (Execution Context and Pipelines), with the recovery chain that
  is its first caller.
- **Cites:** RECOV-12, RETRY-34, PAGE-13, PAGE-15, SSE-29, SSE-36, XCUT-4
- **Status:** deferred

### DEF-25 — Wire-boundary re-validation of header names and outbound values

- **Deferred by:** phase 1, 2026-09-05
- **Why:** Design §4 and §10.10 admit that HTTP-2/SEAM-29's constructor privacy cannot be closed
  in Ruby — `send` reaches a private `new` by design, and duck typing admits impersonation — and
  name one mitigation that matters: header-name and outbound-value validation (HTTP-17, HTTP-18,
  XCUT-18) runs **again** inside every transport adapter, immediately before dispatch, so a forged
  model cannot smuggle a CRLF into a header name even if it never met a builder. Phase 1 ships the
  predicate as public API — `Dexpace::HeaderSyntax`, with YARD, an RBS signature and a row in the
  runtime surface manifest — precisely so an adapter in another gem can call it. The call site is
  a transport, and phase 1 ships none.
- **Pick-up condition:** phase 8 (Transports and Async Runtime), in each adapter's dispatch path;
  phase 9's conformance suite is where the assertion that it happened belongs.
- **Cites:** HTTP-2, HTTP-17, HTTP-18, XCUT-18, SEAM-29
- **Status:** deferred

### DEF-26 — The body member's type and HTTP-46's by-value body comparison

- **Deferred by:** phase 1, 2026-09-05
- **Why:** HTTP-6 requires a request and a response to carry an optional body, and HTTP-46
  requires request equality to compare the body by value. The BODY model is spec ch.06 and phase
  3's, so phase 1 carries the member opaquely: HTTP-7's presence check is the only thing asked of
  it, its RBS type is `untyped`, and equality delegates to whatever `==` the object has. Giving it
  a type here would fix the body interface a phase ahead of the requirements that shape it.
- **Pick-up condition:** phase 3 (I/O and Body Lifecycle) — it narrows `Request#body` and
  `Response#body` in `sig/` and adds the by-value equality test against a real body type. Both are
  a narrowing of a public signature, which is why it is recorded rather than left to be noticed.
- **Cites:** HTTP-6, HTTP-46, BODY-1, NFR-4
- **Status:** picked-up (2026-09-08, phase 3b) — `sig/` narrows `Request#body` and `Response#body` to
  `Dexpace::Body?`, the production contract of `HTTP-36`/`BODY-1` rather than design §10.2's `#each`
  duck type, and `HTTP-46`'s by-value body comparison is tested against real body types. Deviation
  P3-15 records why the narrowing target is the module and not the duck type, and why no coercion is
  added at `Request::Builder`. `HTTP-46` stays phase 1's ID and carries a cross-reference row in phase
  3b's checklist

## Filed by phase 2 — Seam Foundations

Every entry below names a target phase or an explicit pick-up condition, per the roadmap's
execution step 7.

### DEF-27 — `Dexpace.close_quietly`'s two error-disposal routes

- **Deferred by:** phase 2, 2026-09-07
- **Why:** Design §3.7 makes `Dexpace.close_quietly(resource)` the single sanctioned exit for a
  close on a cleanup or discard path, and fixes exactly two ways the rescued failure may be
  disposed of and never a third: **attached to the primary exception's suppressed trail when there
  is a primary exception in flight, and emitted as an `http.instrumentation.*` diagnostic through
  §8.1's facade when there is not.** Phase 2 has neither. The suppressed trail is
  `Dexpace::Error#suppressed`, which phase 1 deferred to phase 4 as `DEF-24`; the diagnostic needs
  the instrumentation facade, which is phase 5's. Building either here would fix an interface a
  later phase must be free to shape — the same objection phase 0 raised against defining
  `Dexpace.register` early, and it applies unchanged. So phase 2 ships the helper with its
  null-safety (`CFG-21`'s last clause) and its `rescue StandardError`, **drops the rescued error**,
  says so in the YARD block, and asserts the current behaviour in a test so the day a route lands
  that test is what has to change. The two loud exceptions §3.7 names are honoured from the start
  and do not come through here: an explicit `#close` by a caller propagates its failure
  (`SSE-30`), and a `#release` raising during the latched close propagates once (`BODY-27`).
- **Pick-up condition:** phase 4 supplies the first route with `DEF-24`'s `#suppressed` and
  `Dexpace.attach_suppressed`; **phase 5 supplies the second with §8.1's facade and closes this
  row**. A close failure swallowed with no diagnostic is a leaked connection nobody can diagnose,
  which is why the row exists rather than the behaviour being accepted.
- **Cites:** SEAM-30, CFG-21, RECOV-12, XCUT-13, OBS-3
- **Status:** deferred

### DEF-28 — The pivot's `deadline:` keyword and the clock behind it

- **Deferred by:** phase 2, 2026-09-07
- **Why:** Design §3.3 writes the pivot's blocking wait as `#value(deadline: nil)` and
  `#wait(deadline: nil)`. Phase 2 ships `#value(cancellation: nil)` and `#wait(cancellation: nil)`
  instead, and no `deadline:`. `SEAM-18`'s interruption clause — the only seam requirement the
  blocking wait has to satisfy — is about **cancellation**, and a cancellation token is what both
  transport seams already thread as their third argument. A deadline is a different thing: it needs
  a clock, a monotonic time source and an interruptible delay, all of which are `CFG-15`–`CFG-21`
  and phase 5's, and building one here would fix their shape a phase ahead of the requirements that
  define them. Recorded as deviation P2-5. The narrowing is safe against the `NFR-4` API lock in
  the one direction that matters: adding a keyword later **widens** a signature, and the lock fails
  when a public signature "disappears or narrows".
- **Pick-up condition:** phase 5 (Configuration and Observability), with `CFG-15`–`CFG-21`'s clock
  and interruptible-delay primitives. `Dexpace::Cancellation.any` is the composition point a
  deadline-derived token plugs into, and `Cancellation.over` is public for exactly that.
- **Cites:** SEAM-18, CFG-15, CFG-17, CFG-18, CFG-20, CFG-21, NFR-4
- **Status:** deferred

### DEF-29 — Moving the in-memory fakes into `dexpace-conformance`

- **Deferred by:** phase 2, 2026-09-07
- **Why:** The roadmap's cross-cutting constraint 4 has phases 1 through 7 test against an
  in-memory fake transport implementing only the `SEAM-11`/`SEAM-16` seams. Phase 1 needed none —
  every type it shipped was a pure value — so phase 2 is the first phase that needs one and decides
  where it lives: `gems/dexpace-core/test/support/`, as `FakeTransport`, `FakeAsyncTransport` and
  `FakeCodec`, **not public API**. Four reasons. `NFR-11`'s scan is over `sig/`, so a fake in
  `test/` is invisible to it, which is the correct outcome. A published fake would need a YARD
  block, an RBS mirror and a row in the runtime surface manifest, after which changing its shape is
  a public API change diffed against a release tag (`NFR-4`) — a real cost paid forever for a
  convenience. `dexpace-conformance` is the gem chartered to publish adapter test doubles
  (design §9.3) and is phase 8's, so publishing a competing fake from core would give a third-party
  adapter author two answers to one question. And phases 3 through 7 all ship `dexpace-core`, so a
  core test-support file is reachable by every phase the constraint names, with nothing published.
- **Pick-up condition:** the first consumer outside `dexpace-core`. Phase 8 at the earliest,
  alongside `DEF-22`'s framework-agnostic assertion objects — and the moment they move is also the
  moment `DEF-23`'s "a gem's test support becomes production-quality code worth checking" condition
  is worth re-reading.
- **Cites:** SEAM-11, SEAM-16, NFR-4, NFR-11
- **Status:** deferred

### DEF-30 — Presence-gated auto-activation for instrumentation

- **Deferred by:** phase 2, 2026-09-07
- **Why:** Design §3.6 permits activating an adapter because a library happens to be loaded **for
  instrumentation only**, and argues the asymmetry rather than assuming it: for a transport or a
  codec, "whatever happens to be installed silently wins" is an auditability failure — a `Gemfile`
  change could reroute every request through a different HTTP library with different TLS defaults
  and different timeout semantics, which is what `SEAM-5`'s loud-failure branches exist to prevent
  — while for instrumentation the worst outcome of guessing wrong is a span that is or is not
  emitted. Phase 2 ships all three seam registries and **no auto-activation hook of any kind**,
  because it ships no instrumentation seam and so has nothing to activate; a mechanism in the
  registry with no caller and one obvious wrong use is worse than its absence. A test asserts the
  hook is absent, so this is a recorded decision rather than an omission.
- **Pick-up condition:** an instrumentation seam exists to activate — phase 5 (Configuration and
  Observability) at the earliest — and its first and only sanctioned user is
  `dexpace-instrumentation-otel` (see DEF-17), which is post-v1. No transport or codec adapter may
  ever use it, and that restriction travels with this row.
- **Cites:** SEAM-5, SEAM-2, OBS-31
- **Status:** deferred

### DEF-31 — SEAM-25's lifecycle event on the first close of an owned executor

- **Deferred by:** phase 2, 2026-09-07
- **Why:** `SEAM-25` requires an async-runtime adapter that owns an executor to implement close as
  "an idempotent, ownership-aware release: **only the first close shuts the owned executor and
  emits the lifecycle event**, later closes are true no-ops." Phase 2 ships the whole of that
  sentence except the event. `Dexpace::Closeable` supplies the latch, the ownership rule and the
  once-only `#release`, verified under contention; there is nothing to emit an event *through*,
  because the instrumentation facade is `docs/sdk-design-ruby/08-instrumentation-and-configuration.md`
  §8.1 and phase 5's. Defining an event shape here would fix the facade's interface two phases
  ahead of the requirements that define it, which is the objection phase 0 raised against defining
  `Dexpace.register` early and phase 2 raised again against `close_quietly`'s disposal routes
  (`DEF-27`). Recorded rather than left implicit because the phase-2 checklist marks `SEAM-25` ✅
  for the release half, and a ✅ with an unstated missing clause is exactly the drift the
  one-row-per-ID convention exists to prevent.
- **Pick-up condition:** phase 5 (Configuration and Observability), with §8.1's facade — that is
  where the event can be emitted. The first thing in this repository that actually **owns** an
  executor is phase 8's `dexpace-async-thread`, so phase 8 is where the emission gets a real
  subject and where `dexpace-conformance` asserts "close twice → executor shut once, one event".
- **Cites:** SEAM-25, ASYNC-15, ASYNC-16, XCUT-13, OBS-3
- **Status:** deferred

### DEF-32 — the handler failures `Hooks.notify` drops after the first

- **Deferred by:** phase 2, 2026-09-08
- **Why:** Three phase-2 sites publish state under a mutex and then notify a list of caller-supplied
  callbacks outside it: `Cancellation::Source#cancel`, `Async::Completer#settle` and
  `Async::Completer#request_cancel`. Written as a bare `hooks.each { |hook| hook.call(…) }`, one
  raising handler drops every later-registered handler and propagates to whoever published the
  state — the same `SEAM-18` failure as "a second waiter on one token blocks forever", arriving from
  the write side, and verified on 3.2.11, 3.4.10 and 4.0.6. `Dexpace::Hooks.notify` runs the whole
  list and then re-raises the **first** failure. The failures **after** the first are dropped, and
  that is the deferral: `docs/sdk-design-ruby/03-seam-and-adapter-mapping.md` §3.7 names two
  disposal routes for a rescued error and phase 2 has neither. Dropping every failure instead was
  rejected for the reason `close_quietly`'s own row gives (`DEF-27`): a handler that raises into a
  void is a bug nothing reports, and phase 2 has no diagnostic channel at all.
- **Pick-up condition:** phase 4, with `DEF-24`'s `Dexpace::Error#suppressed`. That is the first
  carrier a second failure can be attached to, and the change is confined to `Hooks.notify`: attach
  each later failure to the first through `Dexpace.attach_suppressed`, then re-raise as now. Phase 5
  may additionally emit an `http.instrumentation.*` diagnostic per dropped failure once §8.1's
  facade exists (`DEF-27` waits on the same two routes); it does not replace the trail.
- **Cites:** SEAM-13, SEAM-18, SEAM-16, XCUT-13
- **Status:** deferred

### DEF-33 — exercising IO-38's cross-thread close guarantee on a Ruby without a GVL

- **Deferred by:** phase 3a, 2026-09-08
- **Why:** `IO-38` requires that "the CLOSE state of a source/buffer MUST be observable across threads
  to the slices derived from it, so that a close on one thread reliably invalidates a slice being read
  on another (no torn or stale reads)", and
  `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1 fixes the mechanism: the flag is
  "written and read through a `Thread::Mutex` rather than relying on the GVL, **so the guarantee
  survives JRuby and TruffleRuby**". Phase 3a ships all of that — the synchronised write phase 2
  already had, the synchronised **read** phase 2 did not (deviation P3-6), the invalidation of every
  derived view, and a cross-thread test sequenced through a `Thread::Queue` so it is deterministic
  rather than flaky. What it cannot ship is an interpreter on which the mechanism is load-bearing. The
  CI matrix is CRuby 3.2 / 3.3 / 3.4 / 4.0, and on every row of it the GVL would hide a missing lock:
  the test passes with the mutex and passes without it, so it proves the behaviour and not the
  mechanism. Recorded rather than left implicit because the phase-3a checklist marks `IO-38` ✅ and a
  ✅ whose only evidence is an argument about a platform nobody runs is exactly the drift the
  one-row-per-ID convention exists to prevent.
- **Pick-up condition:** a non-CRuby row is added to the CI matrix. No phase in v1 plans one, so this
  names the **event** rather than a phase — the same shape `DEF-3`'s `BODY-36` half was given by
  phase 3's segmentation sweep, and recorded so a later reader does not mistake an unscheduled
  condition for a forgotten one. When it is met, the work is one job, not new code: run
  `gems/dexpace-core`'s `IO` suite unchanged and confirm the cross-thread close test still passes.
- **Cites:** IO-38, IO-37, IO-22, IO-42, NFR-17
- **Status:** deferred

## Filed by phase 3b — Body Lifecycle

### DEF-34 — the configuration source for the body-logging caps and the enablement predicate

- **Deferred by:** phase 3b, 2026-09-08
- **Why:** `BODY-34` requires that "the in-memory capture on both sides MUST be bounded by one shared
  preview-size configuration" and that body logging "MUST be engaged only when body-level logging is
  enabled"; `BODY-19` requires the request-side tap to be "bounded by a configurable cap"; and
  `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1 asks for `IO-9`/`BODY-32`'s
  materialisation ceiling to be "configurable through the same layered chain as every other limit (§8.2)
  rather than a frozen constant". **There is no configuration chain until phase 5**, and there is no
  instrumentation facade to ask whether body-level logging is on. Phase 3b ships everything that does
  not need one: `Dexpace::RequestLoggingBody` takes `tap_limit:` (defaulting to `::Float::INFINITY`,
  which is `BODY-19`'s own stated default for direct wrapper use) and `Dexpace::ResponseLoggingBody`
  takes a **required** `preview_bytes:`, so one value can drive both sides the moment something has one;
  and the enablement clause is satisfied *structurally* — nothing in core constructs either wrapper, so
  they are off the path unless the instrumentation layer builds one. Phase 3a made the matching decision
  for the ceiling, shipping `Dexpace::IO::MAX_MATERIALIZED_BYTES` as a frozen constant with no keyword,
  and phase 3b deliberately adds none either: a `ceiling:` keyword on a preview operation would give one
  stream two ceilings, which is the failure the phase-3 segmentation design's boundary 8 pins.
- **Pick-up condition:** phase 5, when `CFG-1`–`CFG-4`'s layered chain and `OBS-35`'s body-level-logging
  setting exist. The work is then three wirings and no new mechanism: read the shared preview size from
  the chain into both wrappers, gate their construction on the enablement setting, and give
  `MAX_MATERIALIZED_BYTES` a configured source. Every one of those is a **widening** of a signature that
  is narrower today — adding a default to `preview_bytes:`, adding an optional keyword — so `NFR-4`'s
  API lock is not prejudiced by shipping the narrow surface now. This is `DEF-28`'s precedent applied
  verbatim: phase 2 shipped `#value(cancellation:)` and deferred `deadline:` for the same reason.
- **Cites:** BODY-19, BODY-22, BODY-32, BODY-34, IO-9, CFG-1, CFG-2, CFG-3, CFG-4, OBS-35, NFR-4
- **Status:** deferred

### DEF-35 — RECOV-17–RECOV-30 and RECOV-34: the recovery-stack retry engine

- **Deferred by:** phase 4 segmentation, 2026-09-08
- **Why:** These fifteen `RECOV` IDs describe the recovery-aware **retry stack**, not recovery-chain
  machinery: eligibility classification off a capability (`RECOV-17`), the re-sendability gate
  (`RECOV-18`), re-classification of each re-sent response (`RECOV-19`), the attempt cap and
  total-timeout budget (`RECOV-20`), the exponential-plus-jitter formula (`RECOV-21`), the pacing
  hint's precedence over it (`RECOV-22`), the parser's totality (`RECOV-23`), its four recognised
  forms (`RECOV-24`), the X-RateLimit-Reset jitter (`RECOV-25`), overflow-safe duration arithmetic
  (`RECOV-26`), the cancellable inter-attempt wait (`RECOV-27`), per-call statelessness
  (`RECOV-28`), the parse-failure-never-masks rule (`RECOV-29`), the one-calculator-one-parser rule
  (`RECOV-30`) and construction-time configuration validation (`RECOV-34`). Every one has a `RETRY`
  twin whose Ruby mapping is written in
  `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.1, and
  `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md`'s `RECOV` row already places
  `RECOV-34` there; `docs/sdk-design-ruby/` cites `RECOV-17` through `RECOV-30` nowhere at all.
  Two of the fifteen make the deferral **forced rather than preferred**. `RECOV-27` requires a wait
  that is cancellable and does not pin an execution carrier, whose Ruby mechanism — §8.3's
  `Clock#sleep(duration, cancellation:)` over a `Thread::Queue` — sits behind `CFG-15`'s injectable
  time seam, which is phase 5's and which phase 2 deliberately kept off the async pivot until then
  (`DEF-28`); the alternative, `Kernel#sleep`, is named non-conforming by the requirement itself.
  And `RETRY-13` requires both stacks to compute backoff "via the one shared calculator using the
  one shared set of constants … the stacks MUST NOT carry independent backoff formulas or duplicated
  constants", which `RECOV-30` restates at SHOULD level from this side — so building the recovery
  half two phases before the stage half is exactly the drift both requirements exist to prevent, and
  `RETRY-12`'s default tuning constants come from phase 5's configuration chain in any case. Phase 4
  ships the recovery **chain** (`RECOV-1`–`RECOV-16`, `RECOV-32`, `RECOV-33`) the engine installs
  into, which is the substrate the roadmap's cross-phase obligation 3 names.
- **Pick-up condition:** **phase 6 (Retry, Redirect and Authentication)**, with `RETRY`'s two stacks
  and the one shared calculator the roadmap's phase-6 segmentation bullet already requires to land
  before either stack. Phase 6's segmentation design carries these fifteen alongside
  `RETRY-1`–`RETRY-45` and decides whether each is a separate checklist row or a cross-reference to
  its twin; none may be dropped on the grounds that the twin is satisfied, because the roadmap's
  phase-4 row states the range `RECOV-1`–`RECOV-34`. Read this row together with `DEF-6`, which
  defers `RETRY-29`/`RETRY-38`/`RETRY-43` into the same phase, and with `DEF-5`, which already
  defers `RECOV-31` — the sixteenth ID of this cluster — post-MVP.
- **What this costs phase 6, stated plainly so its segmentation design does not have to count.**
  The roadmap already calls phase 6 the largest at **111** prefix IDs (`RETRY` 45, `REDIR` 28,
  `AUTH` 38). **This row adds the work of fifteen more on top of that 111** — the implementation of
  `RECOV-17`–`RECOV-30` and `RECOV-34`, which is this row's whole scope — so phase 6's segmentation
  design budgets for **111 + 15**. **`RECOV-31` is the cluster's sixteenth ID and is deliberately not
  counted here**: `DEF-5` defers it post-MVP ("picked up together with `RETRY-38` if the per-attempt
  ordinal header feature is ever built") and `DEF-6` defers `RETRY-38` itself with "no named
  trigger", so no register schedules its implementation in phase 6 and budgeting for it would book
  work nothing has scheduled. Phase 6 may carry a ⏳ row for it beside `RETRY-38`'s; a row is not a
  budget. Fifteen and sixteen are both correct numbers about different sets — fifteen is this
  deferral, sixteen is the cluster the phase-4 segmentation design identified — and conflating them
  is the one arithmetic mistake this row exists to prevent. No requirement ID moves: the fifteen keep
  their phase-4 checklist rows as ⏳ citing this row, and phase 6 carries its own rows or
  cross-references for them, which is the two-rows-one-obligation treatment phase 2 gave `SEAM-29`
  and phase 3b gave `HTTP-46`. The roadmap's phase-6 segmentation bullet was corrected in place on
  2026-09-08 to say so.
- **The twin-by-twin mapping, so it is not re-derived.** Each of the sixteen restates, scoped to the
  recovery stack, a rule the `RETRY` chapter states in prose phase 6 can actually read — which is
  also why the corpus has no entry for fifteen of them (see `OI-12`): `RECOV-17` ↔ `RETRY-37`,
  `RETRY-1`, `XCUT-6`/`XCUT-7`; `RECOV-18` ↔ `RETRY-5`, `RETRY-6`, `RETRY-7`, `RETRY-8`;
  `RECOV-19` ↔ `RETRY-36`; `RECOV-20` ↔ `RETRY-27`, `RETRY-14`; `RECOV-21` ↔ `RETRY-9`, `RETRY-10`,
  `RETRY-11`; `RECOV-22` ↔ `RETRY-20`, `RETRY-21`; `RECOV-23` ↔ `RETRY-16`, `RETRY-17`;
  `RECOV-24` ↔ `RETRY-15`, `RETRY-19`, `RETRY-21`; `RECOV-25` ↔ `RETRY-15`'s X-RateLimit-Reset
  jitter clause; `RECOV-26` ↔ `RETRY-11`, `RETRY-18`; `RECOV-27` ↔ `RETRY-23`, `RETRY-26`, `XCUT-3`;
  `RECOV-28` ↔ `RETRY-42`; `RECOV-29` ↔ `RETRY-22`; `RECOV-30` ↔ `RETRY-13`, `RETRY-14`,
  `RETRY-28`; `RECOV-31` ↔ `RETRY-38` (design §11.20: "the same feature under two IDs at two modal
  levels", already `DEF-5`); `RECOV-34` ↔ design §6.1's construction-time validation and §10.18's
  substituted ~292-year bound. Derived and verified by the phase-4 segmentation design against
  appendix C; `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md` carries it as a table
  with the same content.
- **Cites:** RECOV-17, RECOV-18, RECOV-19, RECOV-20, RECOV-21, RECOV-22, RECOV-23, RECOV-24,
  RECOV-25, RECOV-26, RECOV-27, RECOV-28, RECOV-29, RECOV-30, RECOV-34, RECOV-31 (see DEF-5),
  RETRY-13, RETRY-27, RETRY-28, RETRY-37, RETRY-42, CFG-15
- **Status:** deferred

### DEF-36 — the configuration source for the execution-context store's cap

- **Deferred by:** phase 4a, 2026-09-08
- **Why:** `CTX-11` requires the context store to "enforce a maximum number of tracked entries" and names
  no number; `XCUT-14` states the same general rule for every bounded map and names none either. Phase 4a
  ships `Dexpace::ContextStore::MAX_TRACKED_CONTEXTS = 1024`, a `ContextStore.new(cap:)` keyword that
  reaches it, and one process-wide store built with the default. What it cannot ship is any way for an
  application to change the **process-wide** store's bound, because the configuration chain does not
  exist until phase 5. A fixed 1024 is conforming — `CTX-11` asks for a bound, not for a tunable one, and
  `CTX-19` makes that bound "the leak backstop" rather than the primary cleanup mechanism — but an
  application running many thousands of concurrent calls would legitimately want to raise it, and an
  application with a tight memory budget to lower it. The value 1024 is `AUTH-19`'s stated default for a
  bounded store of exactly this shape and is the only number the specification supplies for one; phase
  4a's deviation `P4-9` argues it.
- **Pick-up condition:** phase 5, with `CFG-1`–`CFG-4`'s layered chain. The attachment point already
  exists and the work is one wiring: read the cap from the chain when constructing the process-wide
  store. **No signature changes** — `ContextStore.new(cap:)` is already keyword-shaped with a documented
  default — so `NFR-4`'s API lock is not prejudiced. The same shape as `DEF-34`, which defers the
  configuration source for phase 3b's body-logging caps, and as `DEF-28` before it.
- **Cites:** CTX-11, CTX-13, CTX-19, XCUT-14, AUTH-19, CFG-1, CFG-2, CFG-3, CFG-4, NFR-4
- **Status:** deferred

### DEF-37 — the no-op span and tracer protocols behind phase 4a's three instrumentation singletons

- **Deferred by:** phase 4a, 2026-09-08
- **Why:** `CTX-14` requires the correlation bundle to expose "an active span, and a per-operation tracer
  factory", and `CTX-15` requires the disabled-tracing default to carry "a no-op span and no-op tracer
  factory". Roadmap cross-phase obligation 1 makes the bundle's **shape** phase 4's and forbids deferring
  it — "Phase 4 fixes the shape and ships the bundle in core; phase 5 implements the sentinels and
  populates rather than replaces it. Phase 4 cannot defer the decision to phase 5, and phase 5 cannot
  redefine it." The *protocols* of a span and a tracer are a different matter: they are `OBS-21`–`OBS-25`,
  phase 5's, and fixing them in phase 4 would be the same error in the other direction. So phase 4a ships
  three frozen singletons — `Dexpace::Instrumentation::NO_SPAN`, `NO_TRACER_FACTORY` and the
  `private_constant` `NO_TRACER` — and exactly **one** method between them,
  `NO_TRACER_FACTORY#tracer(name = nil, version = nil)`, which `CTX-20`'s embedded MUST ("Its factory
  method MUST be safe to invoke concurrently from multiple threads") forces into existence: a factory
  with no factory method cannot satisfy a MUST about that method. `NO_SPAN` responds to nothing beyond
  `Object`'s own surface, and the RBS interfaces `_Span` and `_Tracer` are declared **empty** on purpose,
  so the type system states the deferral rather than a comment doing it.
- **Pick-up condition:** phase 5, with `OBS-25` ("a no-op Tracer returning a shared no-op Span, a no-op
  Span whose current-scope is a cached singleton … Selecting a no-op path MUST NOT allocate per call").
  The classes behind all three singletons are `private_constant` and therefore **not** `NFR-4`-locked, so
  phase 5 gives them their methods and widens `_Span`/`_Tracer`, and the three objects keep the identity
  phase 4 published — which is what makes `OBS-25`'s allocation clause assertable by reference identity
  from `dexpace-conformance`, and why those two constants are public where phase 4a's other new
  internals are not. **What phase 5 may not do**, per obligation 1: introduce a second no-op span or
  tracer, replace either published singleton, rename or remove a `Bundle` member, change `Bundle#valid?`
  from derived to stored, replace `TraceIdFlavour` with a bare `Symbol`, or give `Bundle` a second
  `NONE`. Phase 4a's deviations `P4-6`, `P4-7` and `P4-8` record the three shape decisions phase 5
  inherits.
- **Cites:** CTX-14, CTX-15, CTX-20, OBS-21, OBS-25, OBS-26, OBS-27, NFR-4
- **Status:** deferred

### DEF-38 — XCUT-5's baked retryability flag on the protocol error, and the shared status classifier

- **Deferred by:** phase 4b, 2026-09-08
- **Why:** `RECOV-15` requires the error-mapping step to map a 400..599 response to "the matching typed
  exception", and phase 3b's own API table assigns that step and `XCUT-8`'s exception factory to phase 4,
  so phase 4b must ship something to map **to**: `Dexpace::ProtocolError`, `XCUT-4`'s branch (a), carrying
  `#response` and `#status`, with `ProtocolError.for(response)` raising for a non-error status and
  `.for_or_nil(response)` returning `nil` — `XCUT-8`'s two forms verbatim. What phase 4b does **not**
  ship is the error's retryability flag. `XCUT-5` fixes both the flag and its source in one sentence:
  "The baked retryability flag of a protocol (status-carrying) error MUST be computed ONCE at
  construction from a SINGLE shared status classifier, never hardcoded per status subclass. That
  classifier MUST treat 408, 429, and all 5xx EXCEPT 501 and 505 as retryable" — and that classifier is
  `RETRY-1`'s, the same object `XCUT-6`'s open-capability path and `XCUT-7`'s configurable
  retryable-status set are defined against, all three of them phase 6's. Building one in phase 4 would
  fix a phase-6 seam a phase early and give the SDK two places a status classification could live, which
  is the drift the word SINGLE is in the requirement to prevent. It is the same objection the phase-4
  segmentation design used to move `RECOV-27` under `DEF-35` (its wait is `CFG-15`'s object, phase 5's)
  and that phase 2 used to decline `deadline:` (`DEF-28`).
- **Pick-up condition:** phase 6, with `RETRY-1`–`RETRY-45`. The attachment point already exists and the
  work is one method: add `#retryable?` to `Dexpace::ProtocolError`, computed once at construction from
  the classifier phase 6 builds for `RETRY-1`, and add **no** second protocol-error type. Adding a method
  **widens** a signature, which `NFR-4`'s "disappears or narrows" lock permits, so shipping the class
  without the predicate now prejudices nothing. `DEF-35` targets the same phase and the two are read
  together: `DEF-35`'s `RECOV-17` is the eligibility rule that consults `XCUT-7`'s configured set rather
  than this flag, and getting that relationship backwards is what `XCUT-5`'s own closing NOTE warns
  against.
- **Cites:** XCUT-4, XCUT-5, XCUT-6, XCUT-7, XCUT-8, RECOV-15, RECOV-17, RETRY-1, RETRY-37, NFR-4
- **Status:** deferred

### DEF-39 — PIPE-39's standard-resilience constructors, and PIPE-32's `redirect: :unsupported` argument

- **Deferred by:** phase 4c, 2026-09-08
- **What is deferred:** `Dexpace::Pipeline.standard(transport, …)` and
  `Dexpace::AsyncPipeline.standard(transport, …)` — the second of the two convenience constructors
  `PIPE-39` names, "a standard pipeline that installs the default resilience pillars over a transport
  (sync: redirect+retry+instrumentation; async: retry+instrumentation with a caller-supplied scheduler
  for non-blocking backoff)" — together with the explicit `redirect: :unsupported` argument design
  §5.3 specifies on the async one, which is how `PIPE-32`'s sync/async asymmetry is made visible at the
  call site rather than silent.
- **What is not deferred, stated because the row is easy to read as larger than it is:** `PIPE-24`'s
  installation semantics ship in full and are tested. `Dexpace::Pipeline::Builder#install_preset(entries)`
  validates up front that no target pillar is occupied, rejects the whole call installing nothing on any
  collision, never overlays, and shares one validate-then-commit implementation with `PIPE-23`'s
  `#reload`. `PIPE-39`'s **first** constructor ships as `Pipeline.direct` / `AsyncPipeline.direct`, and
  `PIPE-35`'s two seeding constructors — `Builder.flattening` and `Builder.nesting`, which design §12's
  `PIPE` row also counts under `PIPE-39` — ship in full.
- **Why:** the three step families the constructor installs do not exist in phase 4. The redirect and
  retry pillar steps are phase 6's (`REDIR-1`–`REDIR-28`, `RETRY-1`–`RETRY-45`) and the instrumentation
  step is phase 5's. A constructor named for the defaults it installs, installing nothing, is worse than
  its absence: a caller reaches for it *instead of* composing the pillars by hand and gets a bare
  transport with the word "standard" on it. `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`
  forbids exactly that in its R14 — "must not ship a preset that silently installs nothing while claiming
  to install the defaults". A middle option was considered and rejected in phase 4c's R14:
  `Pipeline.standard(transport, redirect:, retry:, instrumentation:)` with three required keyword
  arguments would install what the caller names and be testable today, but it is `#install_preset` under
  a second name and it locks three public keyword names under `NFR-4` before the objects they name
  exist — phase 2's own objection to building `deadline:` early (`DEF-28`, deviation P2-5) and phase 0's
  against defining `Dexpace.register` early.
- **Pick-up condition:** **phase 6**, the first phase in which all three families exist. Phase 6 writes
  the two constructors **over** `Builder#install_preset` and writes no second installation path; the
  mechanism is built and waiting, so what phase 6 adds is a step set and two names. `PIPE-32`'s
  documentation clause is already discharged in phase 4 (the asymmetry is stated in the design and in
  `Dexpace::AsyncPipeline`'s YARD); what travels here is the argument that makes it visible at the call
  site.
- **Consequence for the checklists:** phase 4c carries `PIPE-39` as ⏳ citing this row with its met half
  named, `PIPE-24` as ✅, and `PIPE-32` as ✅ whose substantive clause — "the async standard pipeline
  MUST NOT follow HTTP redirects at the pipeline layer" — holds vacuously until this row is picked up,
  because until then there is no async standard pipeline. Phase 4c deliberately does **not** make
  `Stages::REDIRECT` un-installable on the async path: `PIPE-28` requires "the identical stage identities
  and staging policy" in both runtimes, and a builder that rejected a REDIRECT step for one build method
  and accepted it for the other would be two staging policies.
- **Cites:** PIPE-24, PIPE-28, PIPE-32, PIPE-39, NFR-4
- **Status:** deferred

next id: DEF-40
