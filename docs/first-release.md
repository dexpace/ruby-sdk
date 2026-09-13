# First Release

Release-readiness register — and, since 2026-09-13, also the register of what v1 ships without and of
the post-release triggers, recorded here when the deferral register was retired: every postponed item
now lives either in the plan task that will do it or in this file. The find-list register was retired
the same day, on the same rule — a finding is routed to its owner when it is found, not registered —
and four of its items came here: two blockers before first publish (documenting the `include Dexpace`
constant shadow, and the `AuthDescriptor` carrier decision), `CFG-20`'s cancel-with-interrupt clause
under the unsatisfied MUSTs, and the `CTX-7`/`CTX-8` drain proof under the post-release triggers. Two
more left a second home here beside their primary owner: the Minitest 6 trigger, and the red
`gates:bounded_map` blocker phase 10's repair clears. **Nothing has been published.** There is no `gems/`
directory yet, no tag, and no version beyond the `0.0.0` every gem will start at.

## Gems, once they exist

Per `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.1, the MVP is six gems, every one of
them at `0.0.0` until the first release:

| Gem | Published? |
|---|---|
| `dexpace-core` | no — 0.0.0 |
| `dexpace-transport-net_http` | no — 0.0.0 |
| `dexpace-serde-json` | no — 0.0.0 |
| `dexpace-transport-async_http` | no — 0.0.0 |
| `dexpace-async-thread` | no — 0.0.0 |
| `dexpace-conformance` | no — 0.0.0. **Phase 8 owns this gem's gemspec, its version and its first
  release** (the roadmap's phase-8 row; phase 9 adds the remaining suites and owns neither). This is the
  row that moves first: phase 8's phase-level pull request performs the **workspace's first gem release**,
  and the conformance gem's framework-agnostic assertion objects (phase 8a, Tasks 4–8 and 20; phase 9,
  Tasks 2–12a) are what it has to release |

**Supported Ruby is not uniform across this table, from phase 8 onward.**
`dexpace-transport-async_http` declares `required_ruby_version >= 3.3` where every other gem keeps the
repository floor of 3.2 (phase 8c's deviation `P8-36`, whose per-gem Ruby floor gate edit is 8c's plan,
Task 3): `async-http` 0.104.0 and its whole
dependency closure require 3.3, and the last release allowing 3.2 is eleven minor versions behind the one
phase 8c verified against. **A consumer on Ruby 3.2 composes `dexpace-core`,
`dexpace-transport-net_http`, `dexpace-serde-json`, `dexpace-async-thread` and `dexpace-conformance`, and
loses only the reactor transport** — which is `NFR-2`'s separability paying for itself, and it should be
stated in the release notes rather than discovered at `bundle install`.

**One gem's transitive closure contains a native extension.** `dexpace-transport-async_http` depends on
`io-event`, which compiles C (`ext/extconf.rb`). A platform with no toolchain and no precompiled
`io-event` cannot install that gem; the composition above is the answer for such a platform too.

## Blockers before first publish

- [ ] Repository scaffolding: `gems/`, root `Gemfile`, `Rakefile`, `Steepfile`,
      `rbs_collection.yaml`, `.rubocop.yml`, `VERSIONS` (§2.3)
- [ ] CI wired up and green on every gem
- [ ] The `dexpace-conformance` suite passing across the full supported Ruby range, 3.2 through 4.0.
      **Checkable for the first time after phase 8** (2026-09-12): phase 8a writes the suite this line
      names — the conformance gem's assertion protocol (its Tasks 4–8 and 20), the §9.3 `TCPServer`
      fixture and both thin drivers — and
      phase 8a and 8c each run it against a real adapter. **With one stated exception**: the 3.2 row runs
      the suite against `dexpace-transport-net_http` only, because `dexpace-transport-async_http` cannot
      be installed there (see the supported-Ruby note above, `P8-36`, and 8c's plan, Task 3). "Passing across 3.2
      through 4.0" therefore means: every gem on every row it can be installed on
- [ ] **Before release, `docs/sdk-documentation/` must state what a green `dexpace-conformance` run does
      and does not prove, and the run's own report preamble must name the same omissions.** Filed
      2026-09-12 by phase 8a's design (`P8-9`). The wire fixture speaks plaintext only and exercises no
      connect timeout, so `TRANSPORT-4`'s open-timeout half and every TLS property are asserted in
      `dexpace-transport-net_http`'s own suite and **not** in the portable one; phase 8c's adapter
      additionally carries a named waiver listing `TRANSPORT-14`, whose malformed-inbound-header-**name**
      clause is unreachable on `async-http` (`P8-38`; the roadmap's phase-10 inbound list carries §12's
      `TRANSPORT-14` scoping). A third-party adapter author whose adapter
      passes is entitled to know that TLS verification, connect-timeout classification and any waived ID
      were not among the things it passed — which is the difference between a conformance suite and a
      badge. Cites `TRANSPORT-4`, `TRANSPORT-14`, `TRANSPORT-20`, `NFR-2`; the suite itself is phase
      8a's Tasks 4–8 and 20 and phase 9's Tasks 2–12a
- [ ] **Before release, `docs/sdk-documentation/` must document the `include Dexpace` constant-shadow
      hazard.** Filed 2026-09-08 by phase 3a's design; recorded here 2026-09-13. Phase 1 measured
      `Dexpace::Method` shadowing `::Method` and concluded "**verified inert outside core**"; the observation
      is true and the conclusion is wider than it supports, because the measurement was taken at the top level.
      Verified 2026-09-08 on 3.2.11, 3.4.10 and 4.0.6, identically on all three: a **top-level**
      `include Dexpace` is inert, since `include` inserts `Dexpace` into `Object` and `Object`'s own constant
      table is searched first — but a consumer writing `class C; include Dexpace; def check(x) = x.is_a?(IO);`
      gets `Dexpace::IO`, because `include` puts `Dexpace` **ahead of** `Object` in `C.ancestors`
      (`[C, Dexpace, Object, Kernel, BasicObject]`). `C#check` then returns **`false` for a real `::IO`**, with
      no error and no warning; `IO === x` is false and a `case/when IO` falls through. `extend Dexpace` and a
      class with no include are unaffected; a `module M; include Dexpace` behaves like a class. It is about
      **every flat `Dexpace::` constant sharing a name with a core class** — `Dexpace::Method`, `Request`,
      `Response`, `Query`, `Status`, and `Dexpace::IO`, which phase 3a adds and which is the one callers most
      often type-test — and `include Dexpace` is an ordinary Ruby convenience phase 1 deliberately measured, so
      it is a use this port expects. Nothing mechanical can reach a consumer's file: phase 3a's extension of
      `Dexpace/QualifiedCoreConstant` covers `gems/*/lib/**/*.rb` and stops at the gem boundary by
      construction. Renaming is not on the table — design §3.1 and §10.2 name `Dexpace::IO::Buffer`, and `P1-1`
      keeps a namespace the design gave a subsystem. Phase 3a states the hazard in `Dexpace::IO`'s own YARD
      block; what is owed before the tag is the same warning in `docs/sdk-documentation/`, where a consumer
      meets it, and a release decision that has seen it
- [ ] **A decision on where a per-call or operation-level `AuthDescriptor` is carried.** `AUTH-4`–`AUTH-7`'s
      tier resolution takes a per-call, an operation and a client `AuthDescriptor` in that preference order,
      and `6c` ships the resolver as a correct, tested, stateless pure function. What no phase specifies — not
      1 through 5, and not `AUTH`'s own 38 IDs — is **where a per-call or operation-level descriptor is
      carried**: `docs/sdk-design-ruby/` names no field on `Request`, on `RequestOptions`, or on any
      `Operation` construct for it, and no `AUTH` requirement asks for one. `AUTH-1`–`AUTH-7` describe the
      descriptor and the resolver as data and a function, never a carrier. `6c` therefore ships the AUTH
      pillar step accepting an **already-resolved** credential (or a caller-supplied `Scheme => credential`
      table) at construction time, treating the resolver as a standalone library object whose caller —
      presumably Operation-building code, outside `AUTH`'s scope entirely — invokes it and threads the result
      into the step. **Release-gated since 2026-09-13; this line owns the decision**, filed 2026-09-09 by
      phase 6c's design. No v1 phase builds that Operation-level wiring, so `AUTH-4`–`AUTH-7`'s resolver ships
      correct and exercised **only by its own unit tests**, never by an end-to-end call path. The event that
      would reopen it is **the first consumer that needs per-call or per-operation credentials — a worked
      example in `docs/sdk-documentation/`, a `dexpace-conformance` fixture, or a downstream SDK's `SEAM-26`
      operation projection carrying a descriptor**. Until that event: either the release notes state that the
      tier resolver has no carrier and only the client tier is reachable end to end, or a carrier is built
      before the tag
- [ ] **`gates:bounded_map` green: `dexpace-transport-async_http`'s `Clients` is an uncapped
      per-origin client cache, which `XCUT-14` (MUST) forbids.** Found 2026-09-13 by phase 9's planning, and
      the **one true positive** of six `gates:bounded_map` reports over 222 filed Ruby fences at 184 distinct
      `gems/*/lib/**/*.rb` paths, measured identically on 3.2.11, 3.3.12, 3.4.10 and 4.0.6. The map is
      instance-lived and lives as long as the client, its key space is chosen by caller URLs and by a server's
      redirect `Location`, `#fetch` inserts with `||=` and nothing evicts — `#close` closes each client's pool
      and leaves the map populated. The repair is **phase 10's**, because `8c` owns the file and has already
      run by the time phase 9's audit does, and it sits on phase 10's inbound list (the roadmap's 2026-09-13
      status note) with the measured detail and the line numbers. The gate stays red until it lands, and
      `XCUT-14` being a MUST is why this is a blocker rather than a report line
- [ ] An RBS sig-diff baseline established, so a later release can be checked against it for an
      accidental breaking change
- [ ] `SECURITY.md` contact confirmed reachable and monitored
- [ ] RubyGems ownership settled for every gem name above, and trusted publishing configured
      (OIDC-based, no long-lived API key committed anywhere)
- [ ] A decision on the four unbuilt convenience requirements in the HTTP domain model —
      `HTTP-48` (ETag), `HTTP-49` (HTTP range) and `HTTP-50` (the conditional-request aggregator),
      all SHOULD-level, plus `HTTP-22` (header-name interning, a MAY). Phase 1 built none of them.
      **The phase-6 target the deferral originally named was corrected on 2026-09-09: it does not
      fire.** Phase 6 carries a
      conditional header but constructs none — `REDIR-3`/`REDIR-4` preserve, `REDIR-5` strips,
      `AUTH-30` copies — so the four are still unbuilt after phase 6 and this decision is still owed.
      **Release-gated since 2026-09-13; this line owns the decision.** Phase 7's candidate
      does not fire either: the phase-7 segmentation design declined it, `7c` constructs no conditional
      header, `7a` copies the raw `ETag` string, and `SSE-38` forbids the SSE reader from setting a request
      header — so no v1 phase gives the four a caller. The event that would reopen it is **the first
      consumer that constructs a conditional request — a worked example in `docs/sdk-documentation/`, a
      `dexpace-conformance` fixture, or a downstream SDK's `SEAM-26` operation projection asking for one**.
      Until that event, it is a release decision and not a phase's: either the release notes state that
      `HTTP-22`, `HTTP-48`, `HTTP-49` and `HTTP-50` are unbuilt, or the four are built before the tag
- [ ] **Phase 8's first transport adapter must wrap every stdlib I/O and timeout error it lets
      escape** — `Errno::ETIMEDOUT`, `SocketError`, `Timeout::Error` and their kin — in something
      answering `#retryable?` (`Dexpace::TransportError` or equivalent), defaulting to `true` per
      `XCUT-4` branch (b). `RETRY-2`'s classification is a capability-only query (`XCUT-6`;
      `CFG-35`'s throwable half is phase 6a's Task 3, `Policy.throwable_retryable?`), so a bare
      unwrapped stdlib error classifies as **not retryable**, which is a silent
      retry-eligibility regression for exactly the class of failure `RETRY-4` calls "always
      retryable". It is invisible until an adapter exists to test it against, and reachable the
      first time a real socket times out. Recorded by phase 6a's design as deviation `P6-4`.
      **Closed in design 2026-09-12 by phase 8's planning; the box ticks when the class lands, which
      is phase 8a's Task 2.** The question this line asked — *will* phase 8 do it, with what, and who
      owns it — is now answered rather than open. `Dexpace::TransportError` is a **phase-level** task in
      `dexpace-core`, in a different gem from all three sub-phases, with one owner (8a's Task 2; 8c's
      Task 4 is a citation and a verification, and defines the class only in the out-of-order case, in
      the identical shape): `class TransportError < ::IOError; include Dexpace::Error; end`, `#retryable?`
      returning `true` unconditionally with no keyword that can override it, and a `#phase` reader
      (`:connect`/`:write`/`:read`/`:close`) **for diagnostics only, never branched on by `RETRY-2`'s
      capability query**. Phase 8 also supplies the exact list the wrap must cover, which is what makes
      the blocker real rather than theoretical: `Net::OpenTimeout`, `Net::ReadTimeout`,
      `Net::WriteTimeout` (all `< Timeout::Error < RuntimeError`), `SocketError` (`< StandardError`),
      `Errno::*` (`< SystemCallError`), `Async::TimeoutError` (`< StandardError`) and
      `Protocol::HTTP1::Error` (`< StandardError`) — **not one of which is an `::IOError` descendant**.
      It also closes phase 6a's deviation `P6-4`

## What v1 ships without

Recorded here on 2026-09-13, when the deferral register was retired: every postponed item now lives
either in the plan task that will do it or in this file. The items below were reconciled against the ten
phases planned so far, 0 through 9, before they landed here. **The release notes MUST state every item in
this section.** None is a blocker: each is a requirement below MUST level that v1 declines, a gem design
§2.2 places after v1, or — in exactly one entry — a pair of MUSTs the port cannot satisfy under its own
rules and says so. Every entry leads with its subject and requirement IDs, and a checklist row marked ⏳
for one of those IDs cites the entry here rather than a phase.

### Unsatisfied MUSTs

- **Cancel-with-interrupt against a blocking worker — `ASYNC-3` and `PIPE-33`'s interrupt clause
  (MUST).** Design §10.5 records both as **unsatisfied** and `ASYNC-4` as **vacuous**, and the distinction
  is load-bearing: `ASYNC-4` was never part of this item — the deferral, from the day phase 2 filed it,
  cited `ASYNC-3` and `PIPE-33` only — and `8b` marks it N/A citing §10.5 directly, so it is not added to
  this entry. **Why the condition is unmeetable.** The pick-up condition was "an interruptible transport
  path", and
  design §8.3 forbids `Timeout.timeout`, `Thread#raise` and `Thread#kill` in every gem here, because an
  asynchronous interrupt can land on any bytecode instruction, including inside an `ensure` releasing a
  pooled connection; the check-after-resume rule and `Completer#on_cancel` mitigate but do not close the
  gap, since a transport blocked inside an uninterruptible C-extension read cannot be aborted early. No v1
  phase adopts such a path and none may, which is why the item is recorded as post-v1 rather than left
  waiting for a phase. **Where it is carried.** `8b`'s checklist marks `ASYNC-3` ⏳ and `PIPE-33`'s
  cross-reference row ⏳, both citing this entry; phase 9's `ExecutorSuite` asserts `ASYNC-3` so that it
  **genuinely fails**
  and the thread driver waives it by ID (phase 9, Task 11 and Task 16 Step 4) — a waived failing assertion,
  never a green one; phase 10 audits the §10.5 ledger and may not re-open the trade (roadmap cross-cutting
  constraint 8). That `dexpace-transport-async_http` *can* abort an in-flight exchange through a parent
  task's cancellation does not close `ASYNC-3`, whose antecedent is a blocking task on a **worker thread**.
  **`CFG-20`'s cancel-with-interrupt clause is this same unmet clause under a second ID**, added here
  2026-09-13 (found 2026-09-09 by the phase-5 segmentation design). `CFG-20` is a SHOULD, three of its four
  clauses are met, and the fourth is the prohibition §10.5 already settles — so **the port gains no fourth
  unsatisfied MUST** and `CFG-20` does not join this entry's heading. What it gains is a citation that states
  the gap, which it did not have: design §10.5 names `ASYNC-3`, `ASYNC-4` and `PIPE-33` and stops; §12's `CFG`
  row says `CFG-20` is "reshaped as the pivot", which does not say a clause is unmet; and §10 item 4 lists
  `CFG-20` among the IDs it touches but argues the mechanism substitution rather than the gap — three
  citations available to a `CFG-20` checklist row and not one of them saying what is missing, which is exactly
  the ✅-or-⏳-with-an-unstated-clause the roadmap's one-row-per-ID convention exists to stop. Phase 5a's `R7`
  owns the row's form (⏳ against this entry with a note that the entry does not cite `CFG-20`, ✅-with-clauses
  naming the three that are met, or a partial marker of its own). The parallel worth reading beside it is
  §11.20's `RECOV-31`/`RETRY-38`, "the same feature under two IDs", and phase 4's treatment of it.

### SHOULD- and MAY-level requirements declined for v1

Each bullet: the IDs with their level, why v1 declines them, the trigger that would reopen the decision,
and the phase whose checklist carries the ⏳ row citing the entry here.

- **`SEAM-24`'s second sentence (SHOULD) — each adapter's caller-facing cancellation bridge over the
  host's own primitive.** The requirement's first sentence, propagating the diagnostic context across the
  thread handoff, *is* met: it is `ASYNC-8`'s, `dexpace-async-thread` implements it through `Fiber[]`, and
  `dexpace-transport-async_http` inherits it by construction. What v1 declines is the second sentence,
  because no v1 gem hands a caller a primitive to bridge — the thread pool hands out no `::Thread`,
  `#post` returns `nil`, and the only handle a caller holds is the pivot. Trigger: the post-v1
  `dexpace-async-async` gem, below, to which design §3.3 assigns the bridge. ⏳ row: phase 2, which owns
  `SEAM-24`; the narrowing is recorded by the phase-8 segmentation design and `8b`'s and `8c`'s. (The
  same deferral's other half, `SEAM-28`'s stable operation identifier, is not here: it is phase 5c's Task
  4, over the `RequestContext#operation_name` phase 4a's Task 7 built.)
- **`BODY-36` (MAY) — a read-only memory-mapped view of a file-backed body.** Ruby's
  standard library has no `mmap`; the only routes are a C extension or the `mmap` gem, both barred from
  `dexpace-core` by `SEAM-1`/`NFR-1`. Trigger: core's dependency budget changes — an event, and no phase in
  v1 can produce it. ⏳ row: phase 3b, which owns the ID. Its companion **`BODY-12` clause 2 (SHOULD)** —
  the transport dispatching a true zero-copy kernel path for a `Dexpace::FileBody` — is not a deferral but
  an **UNSCHEDULED** decision (2026-09-12, phase 8a's design, R5; confirmed at execution by 8a's Task 25)
  and is stated here so the release notes carry it: `Net::HTTP` streams a body through `::IO.copy_stream`
  into a `Net::BufferedIO` whose `is_a?(::IO)` is false, so the kernel path is unreachable without
  rewriting the library's own write path. Clause 1 was discharged by phase 3b (`::IO.copy_stream` with the
  `(length, offset)` window) and is not owed.
- **`PIPE-36` (SHOULD), pillar-step stage locking.** Post-MVP per the design's own coverage
  index; nothing in v1 implements any part of it, and 4c's design names `#stage`'s precedence table (its
  R10) as where a lock would go. Trigger: none narrower than post-MVP has been named. ⏳ row: phase 4c.
- **`RECOV-31` (MAY), `RETRY-38` (SHOULD by tag, MAY by prose; the conflict is
  recorded at design §11.10), `RETRY-29` (MAY) and `RETRY-43` (MAY).** The per-attempt ordinal header is
  one feature seen from two requirement angles (`RECOV-31`/`RETRY-38`); the server-driven retry override
  and the fixed-delay mode are opt-in modes the MVP's retry engine does not need. Trigger: per-attempt
  observability being prioritised, at which point all four are revisited together. ⏳ rows: phase 6a, one
  per ID, `RECOV-31`'s beside `RETRY-38`'s.
- **`REDIR-27` (MAY), a configurable redirect-target header.** `Location` is the only header v1
  reads. Trigger: none named. ⏳ row: phase 6b.
- **`SSE-41` (MAY), a reactive adapter's error and lifecycle latitude.** Scoped to a reactive
  SSE adapter, and v1 ships only the pull-based SSE view. Trigger: a reactive SSE adapter being built. ⏳
  row: phase 7b.
- **`OBS-32` and `OBS-37` (SHOULD), OpenTelemetry metric conventions and the async body-capture
  skip.** Both presuppose infrastructure v1 does not ship: the metric conventions need an OTel adapter,
  and the body-capture skip needs the async-runtime bridge to have observability wired through it.
  Trigger: the post-v1 `dexpace-instrumentation-otel` gem together with the post-v1 async adapters,
  `dexpace-async-async` and `dexpace-async-concurrent_ruby`, all below.
  ⏳ rows: phase 5c (`OBS-32`) and phase 5b (`OBS-37`).
- **`TRANSPORT-28`'s zero-copy clause and `TRANSPORT-30` (SHOULD), both per-adapter.** The two
  MVP transports do not need either to satisfy the transport contract; `8a`'s R5 finds `TRANSPORT-28`'s
  reachable half satisfiable on `Net::HTTP` and only its zero-copy clause outstanding. Trigger: a transport
  adapter beyond the two the MVP ships. ⏳ rows: phase 8a — `TRANSPORT-30` whole, `TRANSPORT-28`'s
  zero-copy clause.
- **Presence-gated auto-activation for instrumentation (design §3.6; cites `SEAM-5`, `SEAM-2`,
  `OBS-31`).** Phase 2 shipped the three seam registries and no auto-activation hook of any kind, with a
  test asserting the hook is absent; phase 5c read the deferral's condition — "an instrumentation seam
  exists to activate" — and found it **not met**, because `SEAM-2` enumerates five seams and
  instrumentation is not one, so the item is post-v1 and not UNSCHEDULED. Its first and only sanctioned
  user is the post-v1 `dexpace-instrumentation-otel` gem, below. **The restriction travels with this
  entry: no transport or
  codec adapter may ever use it** — for a transport or a codec, "whatever happens to be installed silently
  wins" is the auditability failure `SEAM-5`'s loud-failure branches exist to prevent, whereas for
  instrumentation the worst outcome of guessing wrong is a span that is or is not emitted. Trigger:
  that gem. No ⏳ row carries it — it names a mechanism, not a requirement of its own; phase 2's absence
  test is the artefact.

### Post-v1 gems

Design §2.2 is the authority, and the roadmap's "Post-v1" paragraph already states the rule: these seven
are **entries here, not phases**. The line is not usefulness but what would be unproven without it —
a seam ships in the MVP with at least one adapter exercising the property the seam exists for, and a
second adapter over an already-proven property waits. Each entry names its trigger, as the MVP scope
design of 2026-09-05 stated it.

- **`dexpace-async-async`**, bridging the core async pivot to `Async::Task`. Trigger: a
  reactor-native async adapter is needed beyond the thread-pool-backed `dexpace-async-thread`, which is
  the adapter that proves the pivot. `SEAM-24`'s cancellation bridge (above) and the `XCUT-12`
  fiber-scheduler trigger (under Post-release triggers, below) ride on it.
- **`dexpace-async-concurrent_ruby`**, bridging the pivot to `Concurrent::Promises::Future`.
  Trigger: `concurrent-ruby` interop is needed beyond `dexpace-async-thread`.
- **`dexpace-transport-httpx`**, HTTP/2 without a reactor; a third transport over properties
  the MVP's two already prove. Trigger: HTTP/2 support is needed without adopting a reactor.
- **`dexpace-transport-excon`.** Trigger: `excon` interop is requested.
- **`dexpace-transport-typhoeus`.** Trigger: `typhoeus` interop is requested.
- **`dexpace-serde-oj`**, a faster codec over a seam `dexpace-serde-json` already proves with
  the reference wire codec. Phase 7a's design (2026-09-10) added a second motive beyond throughput, which
  `P7-1` makes visible: `oj` has a genuine streaming parser, so an `oj` adapter would satisfy `SERDE-27`'s
  "without first materializing the whole body" clause that `dexpace-serde-json` measurably cannot at its
  gemspec floor — a new property, not merely a faster codec (cites `SERDE-27`, `SEAM-21`, `IO-9`). That
  does not change the trigger, since throughput is still what a user will feel first, but it changes what
  the gem is worth. Trigger: JSON throughput is identified as a bottleneck the stdlib `json` gem cannot
  meet.
- **`dexpace-instrumentation-otel`.** The §8.1 instrumentation seam is duck-typed and already
  accepts an OpenTelemetry object with no adapter, so the gem is packaging convenience, not a new
  property. Trigger: a first-class OTel integration — helpers, defaults or bundled wiring — is worth
  shipping as its own gem. `OBS-32`/`OBS-37` and presence-gated auto-activation's only sanctioned user
  (both above) ride on it.

## Release path

Not yet defined. `NFR-16`'s signing requirement is enforced on the release path only once that
path exists (see `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md`, NFR row); until
then there is no path to enforce it on.

Two items recorded here on 2026-09-13 because they belong to the release and to no phase:

- **Signed publication and the release half of `NFR-12` — `NFR-16`.** `NFR-16` asks for cryptographically
  signed artifacts with signing enforced on the release/CI path and gracefully optional locally; a signing
  step wired to a path that does not exist would be a gate over nothing, which is the failure mode phase 0
  was built to avoid. Phase 0 did build `gates:reproducible`, so `NFR-12`'s **build** half is satisfied;
  its **release** half — a published artifact byte-identical to a rebuild from its tag — waits with the
  rest of the path. Its condition is two blockers already listed above: RubyGems ownership settled and
  trusted publishing configured.
- **`PackagingSuite`'s `NFR-12` and `NFR-16` assertions against a published artifact.** Phase 9
  writes neither — no task in its plan writes an `NFR-12` or `NFR-16` assertion — so both are written at
  the first `v*` tag and the first `gem push`, alongside the signing step above. `NFR-15` is **not** in
  this entry: phase
  9's Task 9 asserts it against a locally built `.gem`, comparing the loaded `VERSION` to the resolved
  gemspec. `NFR-12`'s cross-toolchain half stays out of scope by phase 0's `P0-7`, which reads the
  requirement as byte-identity for one gem built twice on one interpreter.

### After the first publish

- **The fence executor for `.claude/skills/housekeeping/`.** The Node original's ninth
  housekeeping tool, `check-fences.mjs`, extracts every fenced TypeScript example that imports from the
  workspace and typechecks it against built declaration files; Ruby has no build step to hang that on, so
  the analogue is not a typechecker but an **executor** — extract every ```ruby fence that `require`s a
  `dexpace-*` gem, run it under `ruby -w` with that gem's `lib/` on `$LOAD_PATH` and a stubbed transport,
  and assert it exits 0 with no warnings. It needs published gems to point at (the SKILL.md note this
  entry was drawn from), so it waits for them; closable by no phase.

## Post-release triggers

Recorded here on 2026-09-13, when the deferral register was retired: every postponed item now lives
either in the plan task that will do it or in this file. Each entry names an **event** no v1 phase can
produce, recorded so a later reader does not mistake an unmet condition for a forgotten one. For each:
the trigger, then the one job to do when it fires.

- **A Steep target over a `test/` tree — a gem's `test/` tree becomes production-quality code worth
  checking** → add a Steep target
  over it. `8a` and phase 9 both place `dexpace-conformance`'s assertion objects and fixtures under `lib/`,
  where phase 0's per-gem target already checks them as production code, so the trigger is genuinely a
  `test/` tree and not the conformance gem.
- **`IO-38` on a Ruby without a GVL — a non-CRuby row enters the CI matrix** → run `gems/dexpace-core`'s
  `IO` suite unchanged
  and confirm the cross-thread close test (`IO-38`) still passes. On every CRuby row the GVL hides a
  missing lock, so the test proves the behaviour and not the `Thread::Mutex` mechanism design §3.1 fixes
  for JRuby and TruffleRuby. **The same row is what proves `ContextStore`'s drain, added here 2026-09-13**
  (found 2026-09-08 by phase 4a's plan review): `CTX-7`'s "registered, overwritten, and removed concurrently
  without external locking" and `CTX-8`'s "deterministically admit exactly one winner" both rest on
  `BoundedMap`'s one-`synchronize` insert-and-drain, and **no test holds it** — the discriminating
  measurement, "the maximum size ever observed", is unreachable from the public surface, because
  `ContextStore#size` delegates to `BoundedMap#size`, which takes the same `Thread::Mutex` as the insert, so a
  reader can never observe the transient `cap + 1`. Measured: a split-lock `BoundedMap`, acquiring the mutex
  separately for the insert and for the drain, sampled by four concurrent `#size` readers across 64 000
  inserts from 32 threads at `cap` 8, reported a maximum of **exactly 8 on six consecutive runs**, identical
  to six runs of the shipped one-`synchronize` form; the corpus note's own `9`-at-`cap`-8 observation was
  taken from **inside** the prototype's hash, which no test written against the public surface can reach.
  Phase 4a's plan ships the other discriminating measurement, "the maximum iterations in any one call", in its
  observable form. So narrowing that lock's scope is invisible to the suite on CRuby, exactly as a missing
  lock is for `IO-38`: when this trigger fires, add the `CTX-7`/`CTX-8` drain assertion beside it. The
  alternative repair — an internal probe seam on `BoundedMap` a test can read without the mutex — is a
  `private_constant`'s test surface phase 2 declined for `Dexpace::Hooks`, and would need the same argument
  made deliberately.
- **The require-allowlist regeneration guard — a new Ruby minor version enters the CI matrix** →
  re-derive the require-allowlist's name
  list on the new interpreter and diff it against the committed allowlist. This is `NFR-9`'s content that
  §10.19's retarget does not cover: the allowlist audit and the clean-bundle run check that today's list
  holds, not that it is still the right list.
- **Minitest 6 — no fence in the repository requires `minitest/mock`** → lift the root `Gemfile`'s `minitest`
  pin. Recorded 2026-09-13; found 2026-09-12 by phase 9's design. Phase 0's Task 2 pins `minitest` to
  `~> 5.25` — a **development** dependency, so the zero-runtime-dependency rule is untouched — because
  Minitest is a different major at the top of the supported range and the version there has removed
  `minitest/mock`. Measured on all three installed interpreters: `minitest 5.25.1` on **3.2.11**, `5.25.4` on
  **3.4.10** and **`6.0.0` on 4.0.6**, with
  `Gem::Specification.find_by_name("minitest").default_gem?` `false` on every one. On 5.25.x the gem ships
  `minitest/mock.rb`; **on 6.0.0 it does not** — `require "minitest/mock"` raises `LoadError` on 4.0.6, and
  that gem's `lib/` listing has neither `minitest/mock.rb` nor `minitest/unit.rb`, while `assertions.rb`,
  `test.rb`, `autorun.rb`, `spec.rb` and `benchmark.rb` all remain. Every assertion name this repository uses
  survives: 22 were checked, from `assert_equal` to `assert_in_delta`, and all 22 are still defined on
  `Minitest::Assertions` in 6.0.0. What disappears is `Minitest::Mock` and `Object#stub` — which **phase 8a's
  plan uses twice** (`Dexpace::Conformance::TransportSuite.stub(:assertions, assertions)`, in its driver test
  and again in its `test/` fence) and which two corpus rules name (`testing/e27df4c7`, `testing/70473c9d`).
  The pin keeps the same framework major and a working `stub` on every matrix row, at the cost of the 4.0 row
  not exercising the Minitest its interpreter ships; without it that row runs **red**, which would falsify the
  standing blocker above — the `dexpace-conformance` suite passing across 3.2 through 4.0 — and is exactly the
  trap §9.2's "run the real suite on each Ruby" argument exists for, since `TargetRubyVersion` catches syntax
  and not library availability. The job when this fires: drop the pin, and re-check that no fence requires
  `minitest/mock`.
- **Lifting appendix `B.1`, `B.2` and `B.5` — a second implementation of the pagination engine, the SSE
  reader or the configuration chain exists** → lift their assertions into `dexpace-conformance`. Until
  then a lifted assertion over a single subject is a test with one subject living in a package whose
  purpose is many; phase 9's 61-row `APPENDIX_B.md` map, dispositioning the 22 items by reference
  (`P9-1`), stands and is phase 9's.
- **`XCUT-12` under a fiber scheduler, the fallback — the post-v1 `dexpace-async-async` reactor-native
  adapter (above) ships** → run `XCUT-12`'s single-flight assertion under a fiber scheduler, driving
  `6c`'s bearer or digest cache through a reactor via the suite contract's clause 9 `around:` wrapper. The
  primary disposition is phase 10's, on whose inbound list it sits (the roadmap's 2026-09-13 status
  note): judge whether the thread-only form phase 9 ships (Tasks 7–8) suffices, a judgement phase 9 may
  not make (`P9-6`). This trigger is what fires if phase 10 leaves that judgement open, because the
  reactor adapter is the first artifact that makes a second fiber-scheduler subject available.
