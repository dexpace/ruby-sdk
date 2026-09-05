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
- **Pick-up condition:** SEAM-24 ships together with `dexpace-async-async` (see DEF-11); SEAM-28
  has no named trigger and is picked up opportunistically.
- **Cites:** SEAM-24, SEAM-28
- **Status:** deferred

### DEF-2 — HTTP-22, HTTP-48, HTTP-49, HTTP-50: name interning and ETag/Range/conditional-request helpers

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** HTTP-22 (MAY) is header-name interning. HTTP-48–HTTP-50 (SHOULD) are convenience
  helpers layered on the header model that already exists; none of the four changes what the MVP's
  HTTP domain model is required to do.
- **Pick-up condition:** no named trigger; picked up when convenience helpers are prioritized over
  minimal public surface.
- **Cites:** HTTP-22, HTTP-48, HTTP-49, HTTP-50
- **Status:** deferred

### DEF-3 — BODY-36, BODY-12: memory-mapped view and platform zero-copy file transfer

- **Deferred by:** MVP scope design, 2026-09-05
- **Why:** BODY-36 (MAY) has no stdlib mmap to build on. BODY-12 (SHOULD) platform zero-copy file
  transfer is an optimisation over the file-backed body the MVP already ships correctly, just not
  zero-copy.
- **Pick-up condition:** BODY-12 lands with an `IO.copy_stream` path post-MVP; BODY-36 has no
  named trigger.
- **Cites:** BODY-36, BODY-12
- **Status:** deferred

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

next id: DEF-20
