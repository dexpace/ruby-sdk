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
  **Amended 2026-09-12 (phase 8 segmentation design, confirmed by `8b`'s and `8c`'s): most of `SEAM-24`'s
  SHOULD is met after phase 8, and what stays deferred is narrower than this row reads.** `SEAM-24`'s
  **first** sentence — "propagate the ambient logging/diagnostic context across the thread handoff" — is
  `ASYNC-8`'s, and `dexpace-async-thread` implements it through `Fiber[]`, within fiber storage;
  `dexpace-transport-async_http` gets the same propagation by construction, since a child `Async::Task`
  inherits `Fiber[]`, and it satisfies `ASYNC-6` for the `Async::Task` **it creates itself**. What stays
  deferred is both §12's "`SEAM-24` … **beyond fiber storage**, ships with `dexpace-async-async`" and the
  requirement's **second** sentence proper — "**Each adapter's cancellation bridge** SHOULD map
  cancellation in both directions per that ecosystem's idiom" — which is a *caller-facing* bridge over the
  host's own primitive, assigned by design §3.3 to `dexpace-async-async` (`DEF-11`, post-v1). **No
  phase-8 gem bridges a caller-held primitive**: the thread pool hands out no `::Thread`, `#post` returns
  `nil`, and the only handle a caller holds is the pivot; the async transport bridges no caller-held task.
  So the row stays **deferred** and is **not** UNSCHEDULED — the condition it names is post-v1 and
  unmeetable here — and this sentence exists so a phase-9 audit does not re-derive it from three
  sub-phase designs.

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
- **Correction, 2026-09-09 (phase 6 segmentation design): the phase-6 target does not fire.** Phase 6
  *carries* a conditional header; it constructs none. `REDIR-3` and `REDIR-4` preserve the original
  headers verbatim, `REDIR-5` removes `Content-*` and drops the body, and `AUTH-30`'s replay copies the
  request — none of the three builds a conditional header, parses an ETag or validates a Range. So
  `HTTP-48`–`HTTP-50` still have no caller when phase 6 ends, and `HTTP-22` is untouched by it. The row
  stays **deferred and is still not UNSCHEDULED**, by the register's own definition: phase 6 does not
  *meet* the condition and decline it, it merely fails to fire it. **What is owed is a new target or the
  event shape** — phase 7's pagination and conditional-request interplay is the next candidate, and the
  alternative is the event shape `DEF-33` and `DEF-3`'s `BODY-36` half were given. See also
  `docs/first-release.md`, whose readiness line named phase 6 on the same stale reasoning.
- **Cites:** HTTP-22, HTTP-48, HTTP-49, HTTP-50, REDIR-3, REDIR-5, AUTH-30
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
- **BODY-12 clause 2: condition met, action declined, 2026-09-12 (phase 8 segmentation design and
  `8a`'s design).** The clause targets phase 8 explicitly, and phase 8 has now planned the adapter it
  names. Measured on `net-http` 0.6.0 under Ruby 3.4.10: `Net::HTTP#send_request_with_body_stream` streams
  a body through `::IO.copy_stream` to a `Net::BufferedIO`, whose `is_a?(::IO)` is **false**, so the
  kernel path is not reachable without bypassing the library's own write path — which would mean writing
  the request framing, the chunked encoder and the `100-continue` handshake by hand, inside an adapter
  whose whole design is to be thin over one library. `8c` reports from the other side that
  `Protocol::HTTP::Body::File` makes the *reachable* half of `TRANSPORT-28` more reachable on
  `dexpace-transport-async_http` — a report to `8a`'s `R5`, not a route to a kernel transfer. Per the
  roadmap's retirement rule the clause is **UNSCHEDULED with the phase named**, not silently carried.
  **`BODY-36`'s half is untouched** — its condition is core's dependency budget changing, which phase 8
  does not do — and neither is `BODY-12` clause 1, discharged by phase 3b.
- **Cites:** BODY-36, BODY-12, BODY-11, BODY-13, TRANSPORT-28, DEF-10
- **Status:** deferred (BODY-12 clause 1 discharged 2026-09-08, phase 3b; **BODY-12 clause 2 UNSCHEDULED
  2026-09-12, phase 8a**, which performs the mark when it executes unless it finds a route this planning
  pass did not; BODY-36 deferred on an unmeetable condition)

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
- **Read and left alone, 2026-09-12 (phase 8 segmentation design and `8a`'s design), and the distinction
  from `DEF-3` is the point.** Phase 8 ships exactly the two MVP transports, so the condition — an adapter
  **beyond** them — is **not met**, and this row is therefore **not** UNSCHEDULED, where `DEF-3`'s
  `BODY-12` clause 2 is: that clause named phase 8 itself. `TRANSPORT-30` is carried ⏳ whole inside
  `8a`'s 23 checklist rows citing this row, and `TRANSPORT-28` is **narrowed from ⏳-whole to partially
  satisfied** — `8a`'s `R5` finds the requirement's reachable half satisfiable on `Net::HTTP` and only its
  zero-copy clause ⏳ — the same two-rows-one-obligation treatment phase 2 gave `SEAM-29`. No status
  change and no `Cites` change; a ⏳ checklist row against an open deferral is not a pick-up.
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
- **Read and left alone, 2026-09-12 (phase 8 segmentation design and `8b`'s design). No `Cites` edit and
  no `Status` edit is made, deliberately.** §8.3 forbids an interruptible transport path and phase 8 does
  not adopt one, so the condition is **not met** and the row is **not** UNSCHEDULED. What phase 8 adds is
  the disposition a reader of the roadmap will otherwise expect to find here: `8b` carries `ASYNC-3` ⏳
  **citing this row** and `PIPE-33`'s cross-reference row citing it too, while **`ASYNC-4` is N/A, citing
  design §10.5 and no register row at all** — §10.5, §12 and the checklist legend each distinguish an
  *unsatisfied* MUST from a *vacuous* one, and this row's `Cites:` line has always been `ASYNC-3, PIPE-33`.
  `ASYNC-4` is deliberately absent from it and should stay absent; the roadmap's cross-cutting constraint
  8 said "phase 8 marks all three ⏳ citing it" and is corrected in place there. Counter-intuitively,
  `dexpace-transport-async_http` **can** abort an in-flight operation (a parent task's cancellation
  reaches an in-flight exchange and runs its `ensure`), and that does **not** close `ASYNC-3`, whose
  antecedent is a blocking task on a **worker thread** and whose row belongs to the gem that has one.
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
- **Pick-up recorded in planning, 2026-09-12 (phase 8 segmentation design and `8a`'s design): the
  condition names this phase in as many words, and `8a` is the sub-phase that meets it.** `8a` writes
  `Dexpace::Conformance::Failure`, the callable assertion protocol with its five result statuses and its
  ID-keyed waivers, the §9.3 `TCPServer` fixture (`WireServer`), the transport suite, and both thin
  drivers — Minitest and RSpec — referenced at call time so neither framework becomes a runtime
  constraint on a consumer. The assertion objects and the fixture live in **`lib/`**, not `test/`, which
  is what leaves `DEF-23`'s condition unmet (see that row). The suite contract is one twelve-clause list
  owned by `8a`'s design; `8c` drives the same suite over an asynchronous adapter. The gem's version bump
  and first release are the phase's, not the sub-phase's, and land with `docs/first-release.md`'s table.
- **The second half of the condition recorded in planning, 2026-09-12 (phase 9's design).** The condition
  reads "phase 8 … **phase 9 adds the remaining suites**", and phase 9 is the phase that adds them:
  `InvariantSuite` (appendix `B.8`, 24 assertions, one per `XCUT` requirement), `PackagingSuite`
  (appendix `B.9`), `CodecSuite` (the lift of `7a`'s named target,
  `gems/dexpace-serde-json/test/support/serde_seam_assertions.rb`), `ExecutorSuite` (this register's own
  `DEF-31` harness half), `Runner`, `SharedInstance` and `Aggregate`, plus `Report#to_h` — the structured
  renderer `8a` deferred *for* this phase, on the grounds that it was "`NFR-4`-locked surface with no
  caller until phase 9 aggregates three suites". **Phase 9 extends the protocol and changes none of it**:
  `Assertion` keeps `Data.define(:ids, :name, :body)` with `#body` typed `^(untyped) -> void` precisely so
  a suite for a seam that is not a transport supplies its own subject, the five statuses are unchanged, and
  `TransportSuite` is not refactored onto the shared `Runner` — phase 8 owns that file. Phase 9 owns
  neither the gemspec nor the version nor the release, which stay in `docs/first-release.md` as phase 8's.
- **Cites:** NFR-2, NFR-4, SEAM-12, SEAM-14, SEAM-15, TRANSPORT-1–TRANSPORT-30, OBS-21, OBS-25, PAGE-36
- **Status:** deferred — both dispositions above are planning decisions; `8a`'s plan moves this line to
  `picked-up (<date>, phase 8a)` when it executes, and phase 9's plan records the second half against the
  same row, as every plan performs its own register edits

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
- **Checked and still not met, 2026-09-12 (phase 8 segmentation design and `8a`'s design).** The
  condition was checked rather than assumed, because the row's own text invites phase 8 to meet it.
  `8a` places `dexpace-conformance`'s assertion objects and the `TCPServer` fixture in **`lib/`** — §9.3's
  whole argument is that a third-party adapter author *runs* them, which means they ship in the gem — and
  phase 0 already gave that `lib/` its own Steep target, so they are checked as production code already.
  Nothing `8a` writes under `test/` is production-quality code worth a seventh target. The condition is a
  Steep target over a **`test/`** tree, and it is still unmet; the row is **not** UNSCHEDULED, because
  phase 8 does not meet the condition and decline it. If `8a` instead places the fixture under `test/`
  when it executes, it picks the row up and says so. `DEF-29`'s "the moment they move is also the moment
  `DEF-23`'s condition is worth re-reading" is the re-reading, performed here.
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
- **Pick-up recorded in planning, 2026-09-12 (phase 8 segmentation design, `8a`'s and `8c`'s): both
  halves have a call site, and on one of them this is not a mitigation but the only defence.** Each
  adapter calls `Dexpace::HeaderSyntax.validate_name!` and `.validate_outbound_value!` over every outbound
  header immediately before the native request is built, and each sub-phase carries its own checklist row
  and its own forged-request test, which proves the **call site** rather than re-asserting the module.
  What phase 8 adds to this row is measured: `protocol-http2` 0.28.0 performs **no outbound header
  validation at all** — a space in a name and a CRLF in a value both reached the peer — so on
  `dexpace-transport-async_http`'s HTTP/2 path this re-validation is the sole barrier between a forged
  `Dexpace::Request` and an injected header, a stronger statement than design §10.10's
  "a correctness-of-shape gap, not a request-splitting gap".
- **The second clause recorded in planning, 2026-09-12 (phase 9's design).** The condition's own second
  half reads "**phase 9's conformance suite is where the assertion that it happened belongs**", and phase 9
  writes it: `Dexpace::Conformance::InvariantSuite`'s `XCUT-18` assertion drives a **forged**
  `Dexpace::Request` — one that never met a builder, which `send(:new, …)` reaches by a documented Ruby
  feature — through a transport factory and asserts the dispatch is refused. Phase 8's two per-adapter
  tests prove the **call site**; this proves the **property**, portably, for any adapter a third party
  writes. The division matters because `protocol-http2`'s measured absence of outbound validation makes
  this the sole barrier on one shipped path, and a property asserted only in the first-party adapters'
  suites is a property a third-party adapter can omit silently.
- **Cites:** HTTP-2, HTTP-17, HTTP-18, XCUT-18, SEAM-29, TRANSPORT-12
- **Status:** deferred — both dispositions above are planning decisions; the line moves to `picked-up` at
  phase 8's phase-level pull request, once **both** adapters' call sites exist, and phase 9's plan records
  the portable-assertion clause against the same row

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
- **Condition met, action declined, 2026-09-12 (phase 8 segmentation design and `8a`'s design).** The
  condition — the first consumer outside `dexpace-core` — is met: phase 8 ships three gems with suites
  outside core. The row's *action*, and its whole content, is the literal move named in its title, and it
  is declined on an argument the implementation confirms from the inside: moving
  `gems/dexpace-core/test/support/`'s three fakes into `dexpace-conformance` would make `dexpace-core`'s
  own suite depend on a gem that depends on `dexpace-core` — a development-dependency cycle between the
  workspace's two most load-bearing gems — for no gain core's suite can see. **The row's *purpose* is met
  by a different route, which is stated here rather than used to close the row**: `dexpace-conformance`
  publishes its **own** doubles (`RecordingSpan`, `Allocations`, `WireServer`, and the non-conforming
  transport its own suite drives), which is what a third-party adapter author actually needs, and core
  keeps the three it already has. **`8b` corrects one premise of the argument and strengthens it**: the
  charter said `8b` drives phase 2's `FakeTransport` from a suite outside core, and it does not — phase
  0's `test_helper.rb` puts only that gem's own `lib` on the load path, and a `require_relative` into
  another gem's `test/support/` is the cross-gem reach styleguide 12.6 forbids — so `8b` writes its own
  ten-line doubles, as 3a, 4c, 5b and 7a each did. The first consumer outside core found a local double
  cheaper than a shared fake, which is evidence that the three fakes are not in fact shared.
- **Cites:** SEAM-11, SEAM-16, NFR-4, NFR-11, DEF-22, DEF-23
- **Status:** **UNSCHEDULED** (2026-09-12, phase 8a) — per the roadmap's retirement rule, a row whose
  pick-up condition a phase met and declined to act on is UNSCHEDULED with the phase named, not
  `picked-up` and not silently carried. `8a`'s plan performs the mark when it executes, and reverses it
  only if it finds a route past the dependency cycle, in which case it says what it did about the cycle

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
- **Pick-up recorded in planning, 2026-09-12 (phase 8 segmentation design and `8b`'s design): the
  condition's second half names this gem, and `8b` supplies the subject the event was missing.**
  `Dexpace::Async::Thread::Pool#release` emits `Events::INSTRUMENTATION_SHUTDOWN` — phase 5b's event name
  and field shape, unchanged — at `Severity::INFO`, inside `Instrumentation.contain`, **exactly once**,
  asserted under sixteen-way concurrent close. The two adapter-private field keys
  (`"dexpace.executor.worker_count"`, `"dexpace.executor.drained"`) are `private_constant`s in the pool
  and are deliberately **not** added to core's `Keys`, because the portable assertion needs the event name
  only. The *harness* half of the condition — the assertion living in `dexpace-conformance` — is `8a`'s,
  and `8b` hands it the shape rather than writing it. Phase 5b specified a dated `Status` line for this
  row without moving it; that edit lands when 5b executes and is not performed here.
- **The harness half is reassigned to phase 9, and this is a CORRECTION to the row above rather than
  a restatement of it, 2026-09-12 (phase 9's design).** The paragraph above says "The *harness* half
  of the condition — the assertion living in `dexpace-conformance` — is **`8a`'s**, and `8b` hands it
  the shape rather than writing it." 8a wrote the protocol, the §9.3 `WireServer` fixture and the
  transport suite, and wrote **no executor suite**; 8b supplied the shape as promised. So the harness
  half is unwritten after phase 8, and **phase 9 writes it** as
  `Dexpace::Conformance::ExecutorSuite` — six assertions over an executor factory, covering
  `SEAM-12`, `SEAM-25` and `ASYNC-15`–`ASYNC-17`, with the `SEAM-25` one asserting exactly the shape
  this row names: close twice, executor shut once, **one** event, matched on the event **name** only
  because `8b`'s two field keys are `private_constant`s in the pool. Two clauses are scoped out with
  reasons rather than dropped: `SEAM-18` is the seam's shape rather than an implementation property
  and 8b asserts it, and `ASYNC-15`'s clause (c) needs a pending interrupt, which §8.3 bans every
  primitive for. The row is wrong about *which phase delivers the harness*, and saying so out loud is
  the point — a claim that corrects a committed document while presenting itself as a restatement is
  the failure mode phase 4b shipped.
- **Cites:** SEAM-25, SEAM-12, SEAM-18, ASYNC-15, ASYNC-16, ASYNC-17, XCUT-13, XCUT-22, OBS-3, DEF-22
- **Status:** deferred — the dispositions above are planning decisions; `8b`'s plan moves this line to
  `picked-up (<date>, phase 8b)` when it executes, and this is the row's **closing** pick-up

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

## Filed by phase 5a — Configuration and the Clock

### DEF-40 — CFG-35's throwable half: classifying an error as retryable from its cause chain

- **Deferred by:** phase 5a, 2026-09-09
- **What is deferred:** the second clause of `CFG-35` (SHOULD) — "and SHOULD treat a throwable as
  retryable iff it or any throwable in its cause chain is an IO/timeout error. Cause-chain traversal
  MUST be cycle-safe (terminate on a self-referential chain)." Phase 5a ships the **status** half of
  the same requirement as `Dexpace::Retryability.retryable_status?`, which is `XCUT-5`'s "SINGLE
  shared status classifier" with the exact set 408, 429 and all 5xx except 501 and 505. It ships
  **no** method for the throwable half — not a stub and not a predicate returning `false`.
- **Why:** the clause names a class of error that `dexpace-core` cannot name. Verified on Ruby
  3.4.10, with and without `--disable-gems`: `defined?(::SocketError)`, `defined?(::Timeout)`,
  `defined?(::OpenSSL)` and `defined?(::Net)` are all `nil` in a bare interpreter, and core may
  `require` none of `socket`, `timeout` or `net/http` — all three are on phase 0's require
  **denylist by name**. `openssl` is the one exception and is not elided: it is on the require
  **allowlist**, so `OpenSSL::SSL::SSLError` is nameable at the price of loading the largest
  extension in the stdlib at core's require time, for one class out of a set whose other three
  members stay unreachable — a cost, not a prohibition, and the reason phase 5a declined it.
  What core can reference without a require is `::IOError`, `::EOFError` and
  `::Errno::*`, and those do not form the set the clause is about: `SocketError < StandardError`,
  `Errno::ETIMEDOUT < SystemCallError < StandardError` and `Timeout::Error < RuntimeError`, so none
  of the three is an `IOError`, while phase 3a's `Dexpace::StreamError` **is** one. An
  `is_a?(::IOError)` classifier would therefore mark a short-read stream error retryable and a
  connection timeout not retryable — wrong in both directions — and `CFG-35`'s own last sentence
  would then freeze that wrongness: "Where the classifier is implemented, this exact status-code set
  is a hard contract so exception construction and the retry policy agree." Shipping a wrong shared
  object is worse than shipping half of one, which is the inverse of the drift the word SINGLE
  usually warns about, and it is why the status half is **not** deferred with it: the status set is
  fully expressible in core and is the half `XCUT-5` calls SINGLE.
- **Pick-up condition:** phase 6, with `XCUT-6`'s retryability capability and `RETRY-1`. `XCUT-6`
  requires that "for such errors the classifier queries the **capability** (is-Retryable and the
  flag), not a concrete-type match", which is exactly the mechanism that lets
  `dexpace-transport-net_http` declare `Errno::ETIMEDOUT` retryable without core naming it; phase
  8's `Dexpace::TransportError` is the other half. The walk is `Dexpace.each_cause`, phase 4b's,
  already cycle-safe by reference identity (`XCUT-9`), so `CFG-35`'s cycle-safety clause needs no
  second implementation. Adding a method **widens**, which `NFR-4`'s "disappears or narrows" lock
  permits, so shipping the status half alone now prejudices nothing.
- **The cross-reference `OI-21` records as missing, supplied from the phase-5 end:** `DEF-38` says
  the shared classifier is "`RETRY-1`'s, the same object `XCUT-6`'s open-capability path and
  `XCUT-7`'s configurable retryable-status set are defined against, all three of them phase 6's",
  and does not mention `CFG-35`. Phase 5a's `R1` resolves that: **the status classifier is phase
  5's and lives in `Dexpace::Retryability`**, phase 6 computes `DEF-38`'s baked `#retryable?` from
  it rather than building a second one, and only this row's clause travels to phase 6. `XCUT-7`'s
  configurable set — default `{408, 429, 500, 502, 503, 504}` — remains a different object, which
  `XCUT-5`'s own closing NOTE is there to keep separate.
- **Consequence for the checklists:** phase 5a carries `CFG-35` as ⏳ citing this row with its met
  half named, and phase 6 carries its own row.
- **Cites:** CFG-35, XCUT-5, XCUT-6, XCUT-7, XCUT-9, RETRY-1, DEF-38, OI-21, NFR-4
- **Status:** deferred

### DEF-41 — OBS-19's header-drop verbosity policy

- **Deferred by:** phase 5b, 2026-09-09
- **What is deferred:** the whole of `OBS-19` (SHOULD) — "A transport that drops a caller-set request
  header it cannot encode SHOULD surface the drop with a configurable verbosity policy offering at
  least: log every occurrence at WARN; log the first drop per header name at WARN and subsequent
  drops of that name at verbose; or log only at verbose. The default SHOULD be the
  once-per-header-name policy." Phase 5b ships **no** policy object, no mode constants and no
  reporting method.
- **Why:** the requirement's subject is stated in its first six words — *a transport that drops*. Core
  has no transport and drops no header: `HTTP-17`/`HTTP-18`'s wire-boundary re-validation is `DEF-25`,
  phase 8's, and it **raises** rather than drops, which is the port's general shape and not an
  accident. Design §12's `OBS` row already records the emission site as "vacuous for `Net::HTTP`,
  which raises on an unencodable header rather than dropping it, and binds any adapter that drops".
  A public, `NFR-4`-locked three-mode policy with no core caller and no core test is `OI-8`'s exact
  shape, and the phase-5 segmentation design's `R10` forbids it in as many words: "It must not ship a
  policy with no caller and no test that exercises it." Before the first release tag not shipping a
  method costs one edit; after it, removing one is a public signature disappearing, which `NFR-4`
  treats as breaking.
- **What is NOT deferred, stated because the row is easy to read as larger than it is:** both halves
  the policy is built from ship in phase 5b and are exercised. `Dexpace::Instrumentation::Severity`
  supplies the two levels the three modes are expressed in (`WARNING` and `VERBOSE`), and the
  once-per-key latch supplies the throttle, with `OBS-40`'s once-per-logger collision diagnostic as
  its caller and its test. Phase 8 writes a small `Data` over both.
- **Pick-up condition:** **phase 8**, at the first adapter that drops a caller-set header rather than
  raising on it — which is **`TRANSPORT-12`**'s subject, with **`TRANSPORT-13`** the transport-side twin
  of `OBS-19`'s three-mode policy over that drop — and is not `dexpace-transport-net_http`. The
  policy lands at that call site, with a test that drops the same header name twice and asserts one
  WARN then one verbose line. If no v1 adapter drops, the row names the **event** rather than a
  phase, in the shape `DEF-33` and `DEF-3`'s `BODY-36` half were given.
- **Requirement ID corrected in place, 2026-09-12 (phase 8 segmentation design, confirmed from the
  adapter's side by `8c`'s).** The condition read "which is **`TRANSPORT-8`**'s subject". `TRANSPORT-8`'s
  subject is a cancellation originating inside the native client. The antecedent of the row's "which" is
  *the adapter that drops*, and dropping is `TRANSPORT-12`'s subject; `TRANSPORT-13` is the logging policy
  over that drop — "A transport SHOULD expose a configurable policy for how such header drops are logged
  (every drop loudly; first per name loudly then quiet, default; all quiet)" — which is `OBS-19` from the
  transport side, three modes for three modes. **The route the row describes is right and the requirement
  it named was wrong.** The same wrong ID was repeated in phase 5b's forward table
  (`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`) and is corrected in
  the same change, because a corrected register row pointing at an uncorrected phase document is how a
  correction gets lost.
- **Condition met, and pick-up recorded in planning, 2026-09-12 (`8c`'s design).** `protocol-http1` 0.41.0
  rejects a header name `HTTP-17` accepts — `Protocol::HTTP1::Connection#write_headers` checks the RFC 7230
  token set and raises `Protocol::HTTP1::BadHeader`, and it does so **after** the request line is already
  on the socket, so the drop must be a pre-dispatch predicate rather than a rescue. So `TRANSPORT-12`
  obliges `dexpace-transport-async_http` to drop that header only, and `TRANSPORT-13` obliges it to log
  the drop under a three-mode policy whose two ingredients — `Severity`'s two levels and the once-per-key
  latch — phase 5b already shipped. `8c` ships `AsyncHTTP::DropPolicy`, bounded at 64 distinct folded
  names per adapter instance (the requirement's own "MUST be bounded" clause, answered with a number).
  **One sentence the row needs, because a reader of the closed row would otherwise over-generalise:** the
  condition is met by this adapter's **HTTP/1.1** path specifically — `protocol-http2` 0.28.0 transmits
  the same name unvalidated — and the adapter drops on **both** protocols anyway (`P8-40`), so "the first
  adapter that drops" is true of the gem rather than of every exchange it performs. A `TRANSPORT-11`
  **framing**-header drop is a different rule and never goes through this policy: it is always logged at
  verbose on both adapters, because three modes over a set the caller controls would let an attacker
  suppress a `WARNING` by exhausting the per-name bound.
- **Consequence for the checklists:** phase 5b carries `OBS-19` as ⏳ citing this row; phase 8 carries
  its own row. Deviation `P5-32` records that design §12 words the same disposition as "vacuous", and
  `OI-27` records that the phase-5 charter's 5b scope table words it as shipping.
- **Cites:** OBS-19, TRANSPORT-12, TRANSPORT-13, HTTP-17, HTTP-18, XCUT-19, NFR-4, DEF-25, OI-8, OI-27
- **Status:** deferred — the disposition above is a planning decision; `8c`'s plan moves this line to
  `picked-up (<date>, phase 8c)` when it executes, and this is the row's **closing** pick-up

### DEF-42 — OBS-29's HTTP-tracer lifecycle wiring: the vocabulary ships with no emitter

- **Deferred by:** phase 5c, 2026-09-09
- **Why:** `OBS-29`'s own last sentence anticipates this — "This is a documented emission contract;
  pipeline/transport wiring to emit it is a follow-up, so it is not yet runtime-enforced." Phase 5c
  ships `Dexpace::Instrumentation::HTTPTracer` (eleven no-op methods across `OBS-28`'s three
  groups), the frozen `NULL` instance design §8.1 names, the `CallableAdapter` bus shape, and the
  ordering test §8.1 requires, driven through a conformant emitter fake exactly as `OBS-29`'s
  conformance clause prescribes. **Nothing in phase 5 emits any of it.** The per-attempt group —
  attempt started, attempt failed with next delay, retries exhausted — has no emitter until phase
  6's retry step exists; the five transport milestones have none until phase 8's adapters open a
  socket. Wiring only the operation-lifecycle triple was considered and rejected: it needs a third
  slot on `5b`'s instrumentation step, which the phase-5 charter's boundary 15 does not grant, and
  `OBS-29`'s ordering clauses are not separable — "retries-exhausted (when it fires) is immediately
  followed by operationFailed with the same throwable" cannot be honoured by a step that cannot see
  attempts, so a partial wiring satisfies three clauses and structurally cannot satisfy the fourth
  while reading as wired. Phase 5b's design confirms the two-slot reading from the other side and
  adds no third slot.
- **Pick-up condition:** phase 6, with the retry step that emits the per-attempt group and with
  `DEF-39`'s `Pipeline.standard`, which `PIPE-24`/`PIPE-39` already target at phase 6 as "the first
  phase in which all three families exist". The transport-milestone group follows in phase 8 with
  the first adapter. The vocabulary itself does not change: `OBS-28`'s "Every event method SHOULD
  default to a no-op so adding a new event is a non-breaking change" is what makes wiring a subset
  safe, and phase 5c's ordering test is the regression the wiring must keep green.
- **Consequence for the checklists:** phase 5c carries `OBS-29` as ✅ with the unwired halves named
  in the row and this row cited; phase 6 carries its own row. `OI-29` records the separate finding
  that `CTX-14`'s bundle member and `OBS-29`'s per-operation factory are two different objects,
  which phase 6 is the first phase to need distinguished.
- **Correction, 2026-09-09 (phase 6 segmentation design and `6a`'s design): the stated route for the
  operation-lifecycle triple is unavailable in the phase this row's condition names.** "A third slot on
  `5b`'s instrumentation step" is a statement about a *slot*, which leaves the *stage* implicit. `5b`'s
  `Dexpace::Instrumentation::Step` declares `#stage` returning `Stages::LOGGING` (order 1100) and phase 4c
  rejects any install supplying a different `stage:` for a step that declares one, so the step cannot be
  moved; `REDIRECT`, `RETRY` and `AUTH` are 200, 500 and 800, so a step at `LOGGING` runs once per hop, per
  attempt and per auth replay, and an operation-scoped triple emitted there fires many times per operation.
  The site that works is `Stages::PRE_REDIRECT` (order 100, `PIPE-37`) — a **new step**, not a slot on an
  existing one, and no phase-6 ID justifies its `NFR-4` surface. Phase `6a` therefore discharges the
  **per-attempt half only** (its retry step emits attempt-started, attempt-failed-with-next-delay and
  retries-exhausted) and leaves the operation-lifecycle triple unwired, per its `R15`. Filed as `OI-32`.
  **This row is picked up but not closed by phase 6**: the transport-milestone group still waits for phase
  8's first adapter, and the triple now waits on whoever ships the `PRE_REDIRECT`-adjacent step.
- **Partly picked up, and the transport half is declined with a reason, 2026-09-12 (phase 8 segmentation
  design, `8a`'s and `8c`'s).** This row's remaining sentence — "the transport-milestone group follows in
  phase 8 with the first adapter" — names a phase that has now planned, and **no route exists**. Phase 5c
  fixed the five transport methods' argument lists, each taking a `context`; the transport seam is
  `#call(request, options, cancellation)` and `NFR-4` locks that three-argument shape; `Request`'s members
  are `(:method, :url, :headers, :body)` and `RequestOptions`'s are `(:timeout, :max_retries, :tags)`;
  `PIPE-11` forbids ambient carriage; and the adapter is in a different gem. So an adapter can reach a
  tracer only through its **own constructor**, which gives one tracer for the adapter's lifetime rather
  than `OBS-29`'s "1:1 to a single logical operation lifecycle", or through a widening of
  `RequestOptions`, which is a core type, a phase-1 surface and a real `NFR-4` widening no sub-phase
  should take alone. **Both adapters therefore wire no emitter and say so**: `8a` declines under its `R6`,
  and `8c` declines for the same reason rather than inventing a second route. Filed as `OI-36`. **The row
  does not close and does not become UNSCHEDULED**: the condition is not met-and-declined, it is
  unreachable as stated, and a route could exist after a deliberate `RequestOptions` widening. Phase 8
  supplies what it can — `8a`'s `dexpace-conformance` is where the assertion would live — and the row now
  waits on the same kind of surface decision the operation-lifecycle triple waits on, which is what
  `OI-32` already records for that half.
- **Cites:** OBS-28, OBS-29, DEF-39, PIPE-24, PIPE-39, OI-29, OI-32, OI-36, PIPE-2, PIPE-37
- **Status:** deferred

## Filed by phase 9 — Cross-Cutting Invariants and Conformance

### DEF-43 — a regeneration guard over the require-allowlist itself: `NFR-9`'s content that the §10.19 retarget does not cover

- **Deferred by:** phase 9, 2026-09-12
- **What is deferred:** an automated check that §9.2's require-allowlist is still *complete for the
  interpreters in the matrix* — the piece of `NFR-9` that survives the retarget. Design §10.19 retargets
  `NFR-8`/`NFR-9` at the require-allowlist audit and the clean-bundle isolation run, and both of those
  check that **today's** allowlist holds. Neither checks that the allowlist is still the right list.
- **Why:** `NFR-9`'s content is a guard over the shipped **keep-configuration**, not over the program:
  "drop a shipped keep-rule or rename a runtime-wired type → the guard fails the ordinary build." The Ruby
  analogue of dropping a keep-rule is an interpreter where a name the allowlist permits has become a
  bundled gem, and that is not hypothetical — `package-and-dependency-layout/70fbcaee` records the
  allowlist's basis moving once already, from the six names the corpus held to the 23 a real 4.0.6
  interpreter reports, with `tsort` leaving the default set at 4.1 and `Gem::BUNDLED_GEMS::SINCE`
  undefined on the 3.2 floor. Phase 0 handled that by filtering against the whole `SINCE` table rather
  than the supported range, which is the right shape and is still a snapshot.
- **Pick-up condition:** names the **event** rather than a phase, in the shape `DEF-33` and `DEF-3`'s
  `BODY-36` half were given: **a new Ruby minor version entering the CI matrix**. No phase in v1 adds one
  — the matrix is fixed at 3.2 / 3.3 / 3.4 / 4.0 — so recording the event is what stops a later reader
  mistaking an unmet condition for a forgotten one. The work when it fires is one gate, not new code:
  re-derive the name list on the new interpreter and diff it against the committed allowlist.
- **Cites:** NFR-8, NFR-9, NFR-1, NFR-10, SEAM-1, DEF-33
- **Status:** deferred

### DEF-44 — `PackagingSuite`'s `NFR-12` and `NFR-16` assertions against a published artifact

- **Deferred by:** phase 9, 2026-09-12 (narrowed 2026-09-13)
- **What is deferred:** the two appendix-`B.9` assertions whose subject is a **released** gem rather than a
  built one — `NFR-12`'s byte-identical rebuild across a release boundary and `NFR-16`'s signature.
  **Phase 9 ships neither**: no task in its plan writes an `NFR-12` or `NFR-16` assertion, so both are
  written at the pick-up. `NFR-15` is **not** in this row: phase 9's Task 9 asserts it against a locally
  built `.gem`, comparing the loaded `VERSION` to the resolved gemspec. (As first filed, this row named all
  three and said phase 9 shipped them as `Vacuous` placeholders; no task does, so the row is corrected
  rather than left to mislead whoever picks it up.)
- **Why:** `NFR-16`'s signing is "enforced on the release/CI path" and there is no release path
  (`docs/first-release.md`'s "Release path: not yet defined"); `NFR-12`'s cross-toolchain half is
  explicitly out of scope by phase 0's `P0-7`, which reads `NFR-12` as byte-identity for one gem built
  twice on one interpreter; and `NFR-15` is assertable against a locally built `.gem` today, which phase 9
  does.
- **Pick-up condition:** the first `v*` tag and the first `gem push`, alongside `DEF-20`, whose own
  condition is "the RubyGems-ownership and trusted-publishing blockers in `docs/first-release.md` close".
  Release-gated; no phase owns it. `DEF-19` is the third row in the same family.
- **Cites:** NFR-12, NFR-15, NFR-16, NFR-4, DEF-20, DEF-22
- **Status:** deferred

### DEF-45 — lifting appendix `B.1`, `B.2` and `B.5`'s assertions into `dexpace-conformance`

- **Deferred by:** phase 9, 2026-09-12
- **What is deferred:** moving the pagination (`B.1`, 10 items), SSE (`B.2`, 6 items) and configuration
  (`B.5`, 6 items) checklist items out of their owning phases' suites and into portable assertions. Phase 9
  dispositions all 22 **by reference** — a row in `gems/dexpace-conformance/APPENDIX_B.md` naming the
  owning phase's test file — and records the decision as deviation `P9-1`.
- **Why:** §9.3's argument for shipping `dexpace-conformance` as a gem is portability across
  *implementations of one seam*: "the *same* assertions could not run unchanged against
  `dexpace-transport-async_http` or a future `httpx` adapter — which is the whole point." Pagination, SSE
  and the configuration chain each have exactly one implementation, and `PAGE-8` makes the pagination
  engine stateless and shareable rather than pluggable. A lifted assertion over a single subject is not
  more true for having moved gems; it is a test with one subject living in a package whose purpose is many,
  and it costs a second file to keep in step. What phase 9 keeps from the lift is the part that carries
  information — the 61-row map, which says for every item where its evidence is.
- **Pick-up condition:** names the **event**: a **second implementation** of the pagination engine, the SSE
  reader or the configuration chain exists. None is planned in v1 and none is on the post-v1 gem list —
  `DEF-11`–`DEF-17` are transports, async runtimes, a codec and an instrumentation adapter, not a second
  paginator — so this is a genuinely open-ended condition rather than a near-term one, and it is recorded
  so a later reader does not read `P9-1` as an oversight.
- **Cites:** PAGE-8, SSE-37, CFG-1, NFR-2, DEF-22, DEF-16
- **Status:** deferred

### DEF-46 — `XCUT-12`'s single-flight assertion under a fiber scheduler rather than threads

- **Deferred by:** phase 9, 2026-09-12
- **What is deferred:** the fiber-scheduler form of `XCUT-12`'s conformance clause — "race N threads on an
  expiring token; assert exactly one fetch, cached reads take no lock, and requests through a different
  credential cache are not serialized". Phase 9 ships the **thread** form in `InvariantSuite`.
- **Why:** `Thread::Mutex` ownership in Ruby is **per-fiber, not per-thread, and non-reentrant**
  (`CLAUDE.md`'s constraints that will bite, design §3.1/§3.7/§7.2), so a lock held across a suspension
  point deadlocks two fibers of one thread and a thread-only race cannot see it. `8b`'s design handed
  forward exactly this shape for `XCUT-11` — "the **two-fibers-on-one-thread** test, which is the only
  shape that proves a per-fiber mutex is not held across a suspension point" — and phase 9 adopts it there.
  For `XCUT-12` it needs a *credential* path running under a reactor, which means
  `dexpace-transport-async_http` driving `6c`'s bearer or digest cache: a composition no first-party suite
  assembles today, because `dexpace-conformance` declares `dexpace-core` and nothing else and so cannot
  open a reactor itself. The suite contract's clause 9 `around:` wrapper is the route — an async driver
  passes `->(&blk) { Sync { blk.call } }` — and supplying such a driver for a credential assertion is a
  piece of work, not a line.
- **Pick-up condition:** **phase 10**, if its audit of `XCUT-12` finds the thread-only form insufficient —
  which is a judgement phase 10 is entitled to make and phase 9 is not, since phase 9 reports and phase 10
  repairs (`P9-6`). Failing that, the condition is `DEF-11`'s reactor-native async adapter, which is the
  first artifact that would make a second fiber-scheduler subject available.
- **Cites:** XCUT-12, XCUT-11, AUTH-35, AUTH-36, ASYNC-9, DEF-11, DEF-22
- **Status:** deferred

### DEF-47 — the MUST-level vacuity report blocker exists only in prose

- **Deferred by:** phase 9, 2026-09-13 (plan re-verification fix round)
- **What is deferred:** the mechanism behind phase 9's rule that an un-waived `:vacuous` result on a
  MUST-level requirement ID is a **phase-9 report blocker** and earns a `docs/first-release.md` line
  (design `R3`; plan Task 15, step 4). As filed the rule is prose and nothing enforces it: `Report#passed?`
  is true when results are vacuous (8a's own report test asserts exactly that), and nothing in
  `dexpace-conformance` knows whether an ID is MUST or SHOULD, so no run can list MUST-level vacuities
  separately.
- **Why:** building it needs a requirement-level map derived from appendix C
  (`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`) plus an aggregate section
  over it — new machinery the fix round was not scoped to add. **This is a manager decision and must not
  be lost**: `R3`'s absent-artifact `:vacuous` rule is safe only because this blocker exists, and without
  it an unbuilt MUST reads as a green run.
- **Pick-up condition:** phase 9 execution, **before Task 15's disposition run** — that run's verdicts are
  not trustworthy without it.
- **Cites:** NFR-17, DEF-22, DEF-18
- **Status:** deferred

next id: DEF-48
