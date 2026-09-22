# Phase 8c — Asynchronous Transport: Checklist

**Written at execution time, 2026-09-21, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The design and the plan were written on
2026-09-11 (reviewed 2026-09-12 and 2026-09-13) against phases 0–7's documents and `async-http`
0.104.0, concurrently with 8a's and 8b's documents, on a machine that then had only Ruby 3.4.10.
Since then every phase through 7 and phase 8a were built and merged; this phase was cut from `main`
at `a7cfeb6`, which holds all of them, and it executed **concurrently with phase 8b** off the same
base — so nothing here names an 8b constant, the `Transport.async_over`-over-a-socket half of the
seam stays 8b's, and this document describes only what this lane built. It is the phase-8 lane that
lands **second of the two off this base**, and the one that makes the wire-boundary re-validation
complete in both adapters. Where the plan's text and the built tree disagree the tree wins and this
document records it. The bundle the whole run used resolved `async-http` **0.105.0**, `async` 2.46.0,
`async-pool` 0.12.0, `protocol-http` 0.72.0, `protocol-http1` 0.41.0, `protocol-http2` 0.28.0,
`io-event` 1.22.0 and, on every row this gem builds on, `openssl` 4.0.2 — the design's facts were
measured on 0.104.0 and re-run on these (the *Matrix facts* section).

**Reconciled 2026-09-22.** 8b is the sibling that lands first — its reconciled docs tip
`5755267` holds, byte for byte, the tree its three squashes put on `main`, which is still `a7cfeb6`
during this pass — so this phase's three branches were rebased onto that tree by `git rebase
--onto` with rerere disabled, every 8c commit preserved and none reordered or reworded: code
`c830725` → `c05ada2` (seven commits), tests `2449b6c` → `a56336e` (four) and docs `13873e5` →
`6cc9d52` (four) plus the pass's one commit of its own, which carries this note, the roadmap's
reconciliation paragraph, the `CLAUDE.md` checklist count re-derived to twenty, and the three
documentation nits review round 3 left (guard
row 18's status, guard rows 8 and 17's citations, and the roadmap note's 97.55 %). The sentences here
that count the tree or say what landed first describe **this phase's own base**, `a7cfeb6`, and are
left as written; on the combined tree the figures are: every one of the six gems real — no phase-0
skeleton remains — **220** `lib/dexpace/` files beside `version.rb` with 220 `sig/` mirrors and the
same **nineteen** `private_constant` test-mirror exceptions (this phase adds none in core: its one
core edit, `configuration/keys.rb`, is an existing public file), **twenty** checklists,
**twenty-one** as-built pages beside `architecture.md`, eighteen gates, the core manifest
1 335 → 1 336, this gem's 2 → 25 and `dexpace-async-thread`'s 14 (8b's rows, already on the base);
a `surface:regenerate` on the rebased tests tip changed nothing. The six files both lanes rewrote —
`CLAUDE.md`, `README.md`, `docs/README.md`, `docs/sdk-documentation/architecture.md`,
`docs/first-release.md` and the roadmap — were reconciled inside the replayed 8c commits. Deviation
40 below is the one sentence here that 8b's presence makes false: it counts nineteen checklists, and
the combined tree carries twenty.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport.md`. Task numbers are
that plan's (nineteen numbered tasks). Design:
`docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md`, whose Deviation
Ledger carries `P8-36`–`P8-40` and whose As-built addendum, written with this checklist, adds
**`P8-91`–`P8-102`** (the charter fixes the bands: `P8-36`–`P8-50` for 8c's design rows, as-built rows
from `P8-91`; nothing is renumbered). The charter is
`docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`. Test files are named with their gem:
`async_http/…` is `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/`,
`conformance/…` is `gems/dexpace-conformance/test/dexpace/conformance/`, and `core/…` is
`gems/dexpace-core/test/dexpace/`. Every `lib/` file in this gem has a `sig/` mirror (the eight
`private_constant`s with `hooks.rbs`'s comment) and every one but `exchange.rb` a `test/` mirror —
`Exchange` is the per-call object and is proven through `async_http/cancellation_test.rb`,
`async_http/parent_cancellation_test.rb` and `async_http/adapter_test.rb`, the three suites that
drive it, and nowhere else; the files with no `lib/` mirror say so in their headers.

## Requirement rows

Ten own rows — `TRANSPORT-7`, `-8`, `-9`, `-12`, `-13`, `-21`, `-23`, `ASYNC-6`, `-21`, `-22` — plus the
cross-reference rows for the IDs this phase exercises and does not own. **Nine ✅ and one N/A**
(`ASYNC-21`, §11.21's reactive SSE bridge, whose one property this adapter can honour is asserted on
`ResponseBody` beside the row), nothing 🚫, nothing ⏳; `TRANSPORT-8`'s row states that it is
**satisfied on this adapter** where §12 records it vacuous, `TRANSPORT-12`'s that the drop is applied
on both protocols by construction and its antecedent is the seventeen delimiter bytes `HTTP-17` admits,
`TRANSPORT-13`'s that the bound is sixty-four names, and `ASYNC-22`'s that cross-thread safety is
structural through a client map keyed by reactor.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `TRANSPORT-7` | MUST | ✅ | 11, 12, 16, 19 | Cancelling the token or the future reaches the in-flight exchange through the queue-marshalled watcher (`Exchange#watch` cancels the exchange task while it is in flight — with the reason wrapped in a `CancelledError` as the `cause:`, which names it on the task's own `Async::Cancel` for whoever reads the task and which nothing in the adapter reads back, the pivot being settled with the reason before the watcher acts — and closes the delivered response afterwards), the connection is released and the future settles a terminal, non-retryable `Dexpace::CancelledError` with the token's reason (`async_http/cancellation_test.rb`, "TRANSPORT-7/ASYNC-6: cancelling the token aborts a blocked native call…", "a token cancelled from a foreign OS thread still reaches the exchange, promptly", "TRANSPORT-7 on the body path: a token cancelled under a blocked body read wakes the reader…", which since review round 1 refutes `Async::TimeoutError` as the cancellation's cause — the wake must be the watcher's close, a bare `IOError` under the read, and never the test's own bound, because the token-first classifier turns the bound's expiry into the same `CancelledError` with the body closed (guard 37); the portable assertion `conformance/transport_suite/asynchronous_test.rb` "TRANSPORT-7", passing against `RawWireTransport` and failing against its `misclassify_cancel` defect, and green against this adapter through the driver, `async_http/conformance_test.rb` — proving the in-flight clause on every adapter and the delivered-body clause only when its cancel lands after the consumer's read has blocked, a race between the server's signal and the client's head parse that the contract's primitives cannot settle (measured against the mutant of guard 37: half the runs on 4.0.6 and a third on 3.3.12 took the body path; the body path's deterministic proof is the adapter's own test above, and the driver's bounded `around:` is what turns that mutant's hang into a flunk). A cancel in flight while the exchange finishes on its own never raises back into the canceller: `Source#cancel` steals its hooks and runs them outside its mutex, so the adapter's hook can run after check-after-resume has settled the pivot and closed the queue, and `Exchange#signal` swallows the `ClosedQueueError` that push would otherwise hand back through `Hooks.notify` to the caller's own `Source#cancel` ("a token cancel in flight while the exchange finishes never raises out of Source#cancel on the canceller's thread, and the future is cancelled", deterministic through an ordinary caller hook registered first; review round 2's R2-1, guard 51). Guards 15, 16, 17, 37 and 51. |
| `TRANSPORT-8` | MUST | ✅ | 13, 19 | **Satisfied on this adapter, where §12 records it vacuous** (`R14`): a cancellation the host runtime originates — a parent task cancelled while the exchange is its live child — arrives as `Async::Cancel`, leaves `Exchange#run` through its `rescue ::Exception` arm after settling the pivot with `request_cancel(:async_cancelled)`, and surfaces as a terminal, non-retryable `CancelledError` with the future reading `cancelled?`; a `with_timeout` expiry on the **same** withheld-head path settles a retryable `TransportError` carrying `Async::TimeoutError`, discriminated by class and never by message (`async_http/parent_cancellation_test.rb`, "TRANSPORT-8: cancelling a PARENT task…" and "TRANSPORT-8's pair…"; `async_http/adapter_test.rb` `TimeoutTest` "TRANSPORT-4/TRANSPORT-8's pair"). Not a portable assertion: its antecedent is a cancellation only an adapter's own suite can originate, and `TransportSuite::PREAMBLE` says so in every report (`conformance/transport_suite/lifecycle_test.rb` and `asynchronous_test.rb` assert the absence and the sentence). Guards 14 (equivalent, measured), 19 and 35 (a runtime cancellation landing inside an exit arm — the native close of an undelivered body suspending, the parent cancelled there — is settled by `#run`'s `ensure` net, `parent_cancellation_test.rb` "a runtime cancellation landing inside an exit arm's native close still settles the pivot cancelled, through the ensure's net", review round 0's R0-4). |
| `TRANSPORT-9` | MUST | ✅ | 11, 12 | A native response obtained after the token was cancelled mid-flight is closed exactly once and never delivered: the exchange re-checks the token after `Client#call` returns (`Exchange#perform`'s `check!`), and independently core's `Completer#fulfil` closes a response handed to an already-settled pivot — so the close holds even without the check, which guard 18 measures (`async_http/cancellation_test.rb`, "TRANSPORT-9: a native response obtained after the token was cancelled mid-flight is closed exactly once"; the portable assertion `asynchronous_test.rb` "TRANSPORT-9", failing against the `ignore_cancel` defect; `async_http/parent_cancellation_test.rb` "R13" for the two paths that reach the undelivered close). |
| `TRANSPORT-12` | MUST | ✅ | 9, 15, 19 | The RFC 7230 token predicate (`HeaderSyntax.token?`) is applied **before dispatch on both protocols** (`P8-40`): a name the SDK model admits and the grammar refuses is dropped, reported through `DropPolicy`, and the rest of the headers and the body dispatch — measured over HTTP/1.1, plaintext HTTP/2 and TLS HTTP/2 against the in-process `async-http` server (`async_http/wire_grammar_test.rb` `TokenPredicateTest`, one test per protocol shape), with the antecedent measured on `protocol-http1` 0.41.0 (a `RefusedError` wrapping `BadHeader`, **after** the request line is on the wire) and on `protocol-http2` 0.28.0 (the name transmitted lowercased and unvalidated). The seventeen bytes `HTTP-17` admits and the grammar refuses — `"(),/:;<=>?@[\]{}` — are asserted one by one (`async_http/request_mapper_test.rb` `HeaderGatesTest` "TRANSPORT-12: the seventeen bytes…"). The portable assertion `conformance/transport_suite/header_drops_test.rb` "TRANSPORT-12" passes against `RawWireTransport`'s drop mode, fails against its `refuse_non_token` defect, resolves **vacuous by measurement** against the plain double (and against `Net::HTTP` through 8a's driver, which now carries the row as a skip), and is real here. Guards 1, 2, 6. |
| `TRANSPORT-13` | SHOULD | ✅ | 7, 9, 15, 19 | `DropPolicy` with the closed three-mode set `EVERY`, `ONCE_PER_NAME` (the default) and `QUIET`, `DropPolicy.build(mode:)` refusing anything else; the per-name latch is keyed on the **folded** name (`HTTP-13`), warns once and is quiet (verbose) afterwards, and is bounded at `MAX_TRACKED_NAMES` (64) distinct names, beyond which every drop is quiet — one frozen `Snapshot` replaced under the policy's own mutex, never a growing map (`async_http/drop_policy_test.rb`, nine cases); a real dispatch through the default policy warns once per distinct bad name across three requests (`async_http/wire_grammar_test.rb` "TRANSPORT-13: a real dispatch through the default policy…"); the framing set is reported at verbose on a **separate** path and never through the policy (`request_mapper_test.rb` "TRANSPORT-11"). This is the header-drop policy phase 5b postponed to phase 8 as `OBS-19`, landed. The portable assertion `header_drops_test.rb` "TRANSPORT-13" is proven in both directions and vacuous by measurement against a client that sends the name. Guards 3, 4a, 4b, 5. |
| `TRANSPORT-21` | MUST | ✅ | 11, 16, 19 | Every failure before dispatch is delivered through the returned future and never thrown: a call outside a reactor settles `Dexpace::SeamError` carrying `REACTOR_MESSAGE` (`P8-39`), a send after close on an owning adapter settles `ClosedError`, a header the re-validation refuses settles `InvalidArgumentError`, an `ftp://` URL settles `InvalidArgumentError` from `Endpoints.screen!` before anything is dialled, an already-cancelled token settles a cancellation before anything is mapped, and a native failure raised inline settles a retryable `TransportError` — all through `Adapter#dispatch`'s one `rescue ::StandardError` fence into `Errors.settle` (`async_http/adapter_test.rb` `PreDispatchTest`, eight tests; the portable assertion `asynchronous_test.rb` "TRANSPORT-21", failing against the `bare_adaptation` defect). Guards 28, 29 (equivalent by construction), 29b, 30. |
| `TRANSPORT-23` | MUST | ✅ | 11, 16, 19 | The pivot settles with the `Dexpace::Response` `ResponseMapper.call` built and nothing else, for a 200 with a body and a 204 with none alike; the mapper hands on the native **body** (`Protocol::HTTP::Body::Readable`), never the response, whose `#read` would be the whole body joined (`async_http/adapter_test.rb` "TRANSPORT-23: a successful dispatch never settles with a nil response"; `async_http/dispatch_conformance_test.rb` `DeliveryTest` "TRANSPORT-23… through a real reactor"; `async_http/response_mapper_test.rb` `BodyTest` "the body handed on is a ResponseBody over the native BODY"; the portable assertion `asynchronous_test.rb` "TRANSPORT-23", failing against the `null_success` defect). Guard 24b. |
| `ASYNC-6` | MUST | ✅ | 11, 12, 13 | Both directions through the queue-marshalled bridge (`P8-91`): the token's hook settles the pivot cancelled and pushes its reason, `Future#cancel` settles the pivot whose own `on_cancel` hook pushes, and the watcher task acts on the reactor's thread (`async_http/cancellation_test.rb` "TRANSPORT-7/ASYNC-6" and "ASYNC-6: cancelling the future reaches the native exchange"); the runtime's own cancellation of the exchange settles the pivot (`parent_cancellation_test.rb` "TRANSPORT-8"); and a cancellation is settled through `#request_cancel`, never `#fail`, so `Future#cancelled?` reads true (`async_http/errors_test.rb` "settle routes a cancelled token to #request_cancel"; guard 17). Both hooks push through `Exchange#signal`, which is total over the exchange's end: the source and the completer each steal their hook list under their mutex and run it outside, so a hook can run after the exchange has settled the pivot itself and closed the queue, and the `ClosedQueueError` that push raises is swallowed there rather than handed back to the caller's `Source#cancel` or `Future#cancel` ("a token cancel in flight while the exchange finishes…", guard 51; review round 2's R2-1). The `CancelledError` the watcher wraps into `Task#cancel(cause:)` is for whoever reads the cancelled task — a non-Exception cause is replaced by the runtime's own — and is read back by nothing here: the pivot's reason travels through the token and the completer, both settled before the watcher acts, which is why dropping the wrap is an equivalent mutant (guard 46; R2-4). The design's direct `#cancel` from the hook is superseded: `Async::Task#cancel` from a foreign OS thread raises `NoMethodError` and cancels nothing (matrix fact, `async_http/matrix_facts_test.rb`). |
| `ASYNC-21` | MUST | N/A | 10 | §11.21's reactive SSE bridge is `dexpace-async-thread`'s and the reactive form post-v1 (`docs/first-release.md`); the one property of it this adapter can honour — the source is polled at most once per unit of demand, never eagerly — is asserted on `ResponseBody` on 7b's precedent: one native `#read` per yield and nothing read ahead (`async_http/response_body_test.rb` `PullAndCloseTest` "ASYNC-21's property"). |
| `ASYNC-22` | MUST | ✅ | 8, 11, 16 | Structural: nothing per-call lives on the adapter — the ivar set is pinned (`async_http/adapter_test.rb` "ASYNC-22: nothing per-call lives on the adapter"), every per-call value is on the `Exchange` and the `Completer`; and the client map is keyed by **(reactor, origin)** (`P8-92`), so every OS thread running its own reactor gets its own `Async::HTTP::Client` per origin and fibers inside one reactor share one — sixteen concurrent calls through one owning adapter over HTTP/1.1 (pool ≤ 8) and over TLS HTTP/2 (one multiplexed connection) each resolve to their own response, and two threads in two reactors through one adapter mismatch nothing (`async_http/dispatch_conformance_test.rb` `DeliveryTest`, "ASYNC-22 over http1", "ASYNC-22 over tls", "ASYNC-22 across threads"; `async_http/clients_test.rb` `FetchTest` "the same origin under a different reactor is a different client"). Guards 11, 12a, 12b. |

**Cross-reference rows** — IDs this phase exercises and does not own, one line each, none counted
above:

| ID | Owner | What this phase adds |
|---|---|---|
| `HTTP-17`, `HTTP-18`, `XCUT-18` | phase 1 (postponed to the adapters) | The wire-boundary re-validation's **second** call site: `RequestMapper#revalidate!` runs `HeaderSyntax.validate_name!` and `.validate_outbound_value!` before anything is mapped, on every name and value, so a forged request that met no builder is refused through the future (`request_mapper_test.rb` "HTTP-17", "HTTP-18"; `adapter_test.rb` "TRANSPORT-21 / HTTP-17"), and over HTTP/2 — where nothing below the model validates and a CRLF value reaches the peer verbatim without it — the h2 half is measured against the in-process server (`wire_grammar_test.rb` `RevalidationTest`, with its antecedent). **With 8a's Task 16 already on the tree, the re-validation phase 1 postponed has landed in both adapters** (the roadmap's status note says so); phase 9's Task 7 adds the portable assertion beyond 8a's two. Guard 1. |
| `XCUT-14` | phase 9 | The second bounded map: `Clients` at `MAX_ORIGINS` (32), drained back to the cap in a loop after every insert — closed reactors first, then the oldest — with every evicted client's pool retired and closed; the `gates:bounded_map` blocker in `docs/first-release.md` gains its dated status and stays open only for the gate itself, which phase 9 builds (`clients_test.rb` `ReleaseTest`, three "XCUT-14" cases). |
| `TRANSPORT-1`, `-2`, `-10`, `-11`, `-14`, `-15`, `-16`, `-17`, `-18`, `-19`, `-20`, `-22`, `-24`, `-25`, `-26`, `-27`, `-28`, `-29` | phase 8a | The **second driver**: `async_http/conformance_test.rb` runs the whole shared suite — thirty-four assertions — against the real adapter through `MinitestDriver` with `settle:` (call, then await the future; from a thread of the assertion's own, a reactor per settle with the body materialised inside it, `P8-94`), `around:` (a `Sync` running the assertion as a child task under a thirty-second bound kept on the PARENT's wait, `AROUND_BOUND`, which cancels the child and flunks the row by name when it expires — a bound raised into the assertion's own fiber would meet the token-first classifier and pass the cancellation rows late; review round 1's R1-1) and `borrow:` (a caller's own `Async::HTTP::Client` with `retries: 0`), waiving `TRANSPORT-14` and `TRANSPORT-27` by id (`P8-38`; both heads refused out of the read by `protocol-http1`, measured as retryable `TransportError`s carrying `Protocol::HTTP1::Error` in the driver's own second test) — **four skips**: three waived (two assertions carry `TRANSPORT-14`) and `TRANSPORT-18` vacuous by measurement, exactly as on 8a's adapter. `TRANSPORT-2`: every owned client is built with `retries: 0` and a borrowed one is refused unless it already is (`clients_test.rb`, `adapter_test.rb`). `TRANSPORT-11`: the ten folded `FRAMING_HEADERS` are never copied, because `async-http` appends a caller's `Host` beside its own (`request_mapper_test.rb`, two "TRANSPORT-11" cases). `TRANSPORT-10`/`-26`: the explicit header, then the body's media type, then **nothing** — no octet-stream default, `P8-97`; and dispatch step 8's "a body-forbidden method gets no body attached" is proven over a forged GET and HEAD carrying a body, the only shape that reaches the guard since `HTTP-7` makes a built GET's body nil (`request_mapper_test.rb` "a body-forbidden method attaches none, even on a forged request carrying one"; guard 47v, review round 2's R2-2). `TRANSPORT-14`'s value clauses and `TRANSPORT-24`/`-27` on `ResponseMapper` (`response_mapper_test.rb`, fourteen cases). `TRANSPORT-15`/`-16`: `P8-37` as built — retire every pooled resource, then `pool.close`, never `Client#close`; a close under an open response returns at once (`clients_test.rb` `ReleaseTest`; `adapter_test.rb` `ConstructionTest`). `TRANSPORT-20`/`-4`/`-3`: `Errors.wrap` asks the token first and wraps every native family retryable with `#cause` (`errors_test.rb`). `TRANSPORT-22`: an adaptation failure after the head closes the native body exactly once (`parent_cancellation_test.rb` `CloseDisciplineTest`). `TRANSPORT-30` stays 8a's and ⏳ there (no proxy route exists in `async-http` for this adapter to carry). |
| `ASYNC-7` | phase 8b | This gem's half of §3.3's contrast: the README's `ASYNC-7` section states the sentence verbatim, and `dispatch_conformance_test.rb` `CompositionTest` "ASYNC-7" measures a blocked read abandoned at the next scheduler checkpoint, well under the time the response would have taken. |
| `OBS-19` | phase 5b (postponed to phase 8) | **Landed**: `DropPolicy` (Task 7), the predicate at dispatch (Task 9), the both-protocols dispatch test (Task 15), the antecedent confirmed on `protocol-http1` 0.41.0's grammar. |
| `OBS-29`, `OBS-28` | phase 5c / phase 10 | Not wired, and no route exists: the adapter takes a `logger:` and no tracer (8a's `R6`, `P8-7`, on phase 10's inbound list); stated in the as-built page. |
| `SEAM-5`, `SEAM-6`, `SEAM-16` | phase 2 | The require-time `AsyncTransport.register(:async_http, …, core: "~> 0.0")` — the version-skew guard's third real registration — and its consequence for core's suite: the in-process "starts empty" and "nothing resolved after a swap" pins on the async seam moved to a child process (`core/async_transport_bare_require_test.rb`, 8a's shape on the sync seam). |
| `SEAM-24` | phase 2 / post-v1 | First sentence by construction (the adapter is a `Dexpace::AsyncTransport`); the second sentence's cancellation bridge to a third-party runtime stays post-v1 per the phase-8 charter. |
| `CFG-7` | phase 5a | `REQUEST_TIMEOUT` is read through `Configuration#duration`, so a bare number is milliseconds; `TRANSPORT_CONNECTION_LIMIT` — the one core widening this phase adds, `Configuration::Keys`' tenth key — through `#integer` (`adapter_test.rb` `TimeoutTest`; `clients_test.rb` `FetchTest`, two configuration cases). |
| `NFR-2`, `NFR-3`, `NFR-11`, `NFR-13` | phase 9 | The gemspec declares `dexpace-core` and `async-http ~> 0.104` and nothing else, and `gates:gemspec_audit` reads it; every file mirrored in `sig/` with no `Async::`, `Protocol::` or `OpenSSL::` type in any signature (`gates:rbs_surface`), the `:async_http` Steep target relaxed exactly as `:serde_json` is (`P8-99`); every file opens with the SPDX header. |
| `NFR-10`, `NFR-14` | phase 0 / phase 9 | The per-gem Ruby floor: `VERSIONS` gains `ruby floor:dexpace-transport-async_http 3.3`, `DexpaceVersions.ruby_floor(gem)` and `.gem_supported?` read it, `gates:versions` and `gates:gemspec_audit` assert it per gem, and the `Gemfile`, `test:gems` and `gates:clean_bundle` skip the gem on a row below its floor (`test/gates/versions_gate_test.rb` and `gemspec_audit_test.rb`'s `per_gem_floor_ahead` fixtures; `P8-36`, and `P8-95` for the shape). |

## What was built

**`dexpace-core`**: one constant, `Configuration::Keys::TRANSPORT_CONNECTION_LIMIT`, with its `sig/`
line; three pins moved on the code branch (`core/configuration/keys_test.rb`, ten keys, and
`core/instrumentation/downstream_wirings_test.rb`, ten), and the four in-process registry pins on the
async seam that the require-time registration invalidated converted to a child-process suite,
`core/async_transport_bare_require_test.rb` over the shared `BareRequire` helper, with
`core/async_transport_test.rb` keeping the in-process halves — 8a's conversion of the sync seam,
applied to the other one.

**`dexpace-transport-async_http`**: `lib/dexpace/transport/async_http.rb` gains its six constants
(`DEFAULT_TIMEOUT_SECONDS`, `DEFAULT_CONNECTION_LIMIT`, `MAX_ORIGINS`, `REGISTRY_KEY`,
`FRAMING_HEADERS`, `ALPN_PROTOCOLS`), `.build(timeout:, logger:, drop_policy:, connection_limit:,
ssl_context:, configuration:)`, `.using(client, logger:, drop_policy:)`, `.default` and the
registration; ten new files under `async_http/` — `adapter.rb` and `drop_policy.rb` public, and the
eight `private_constant`s `clients.rb`, `endpoints.rb`, `errors.rb`, `exchange.rb`, `request_body.rb`,
`request_mapper.rb`, `response_body.rb`, `response_mapper.rb` — every one mirrored in `sig/` (with the
`_Release` interface for the body's release hook) and every one but `exchange.rb` in `test/`; the
gemspec declares `async-http ~> 0.104` and `required_ruby_version >= 3.3` read from `VERSIONS`'
per-gem row. Its `test/support/` holds eight doubles and fixtures, every top-level name prefixed
`AsyncHTTP` because `test:gems` loads every gem's suite into one process: `AsyncHTTPRecordingSink`,
`AsyncHTTPRecordingBody`, `AsyncHTTPHoldingServer`, `AsyncHTTPSilentServer`, `AsyncHTTPServerFixture`
(an in-process `async-http` server over HTTP/1.1, plaintext prior-knowledge HTTP/2 and TLS HTTP/2 by
real ALPN over a per-run self-signed certificate, wrapping the library's server in a `QuietServer`
that swallows a peer's mid-head EOF), `AsyncHTTPReactor` (`reactor_over(server)` and
`assert_exchange_released(task)`), `AsyncHTTPHermeticConfiguration` (`hermetic_configuration(overrides)`,
a chain whose environment tier answers nothing — review round 0's R0-1) and the repository-level
`test/support/async_http_warmup.rb`.
Sixteen suites: the smoke suite, `matrix_facts_test.rb`, the ten unit suites, and the four behavioural
ones — `cancellation_test.rb`, `parent_cancellation_test.rb`, `dispatch_conformance_test.rb`,
`wire_grammar_test.rb` — plus the second driver, `conformance_test.rb`.

**`dexpace-conformance`**: two new `private_constant` groups and their suites — `Asynchronous`
(`TRANSPORT-7`, `-9`, `-21`, `-23`) and `HeaderDrops` (`TRANSPORT-12`, `-13`) — so the suite is
thirty-four assertions in seven groups with `TransportSuite::PREAMBLE` naming `TRANSPORT-8` as the
third thing a green run does not prove; `Scripts.write_response` gains `close:` and every head a script
writes carries `Connection: close` (`P8-96`); `RawWireTransport` gains six defects and a drop mode;
`lifecycle_test.rb`'s size pin moves to thirty-four in seven.

**`dexpace-transport-net_http`**: two test-side changes only — `adapter_fixtures.rb`'s
`keep_alive_twice` passes `close: false` for its first response, and `conformance_test.rb`'s
generated-test pin moves to thirty-four with `TRANSPORT-12` and `TRANSPORT-13` now present (and
vacuous by measurement there).

**The repository**: `VERSIONS`' `floor:<gem>` grammar and row; `tools/versions.rb`'s `ruby_floor(gem)`
and `gem_supported?`; `tools/versions_gate.rb` and `tools/gemspec_audit.rb` reading the per-gem floor;
the `Gemfile`, `tasks/quality.rake`'s `supported_gem_dirs` and `tasks/gates.rake`'s `clean_bundle`
skipping an unsupported gem; the two gate fixtures under `test/fixtures/gates/{versions,gemspec_audit}/
per_gem_floor_ahead/`; the `Steepfile`'s `:async_http` target with `library "openssl", "uri"` and the
`UnknownConstant` relaxation; three surface manifests regenerated once — core 1 335 → 1 336
(`TRANSPORT_CONNECTION_LIMIT`), `async_http` 2 → 25, `conformance` unchanged (both new groups are
private) — with every added row read against the object model.

## Matrix facts, re-run on every interpreter

The design's thirteen facts and the plan's were run on 2026-09-21 on 3.3.12, 3.4.10 and 4.0.6 against
the bundle's `async-http` 0.105.0 / `async` 2.46.0 (the design measured 0.104.0), first as a scratch
script and then, for the eight the adapter's shape rests on, as `async_http/matrix_facts_test.rb` on
every row, which prints the row's versions. The 3.2.11 row has no bundle for this gem (`P8-36`; the
whole closure declares `>= 3.3`, and `bundle install` there refuses it), which the per-gem floor
machinery turns into a skipped gem rather than a red row. What holds identically on every row:
`Async::Cancel < Exception` outside `StandardError` and `Async::TimeoutError < StandardError`, with
`Async::Stop` the same class; outside a reactor `Task.current?` and `Fiber.scheduler` are nil;
`Task#cancel` from a foreign OS thread raises `NoMethodError: private method 'raise' called for nil`
and cancels nothing; `Task#cancel(cause:)` keeps an `Exception` cause and replaces a Symbol with the
runtime's own `Cancel::Cause`; `Task#async` runs the child eagerly to its first suspension and hands
control back to the caller's fiber; `Fiber.scheduler` is one object across a reactor's tasks and a
different one on another thread, closed once its `Sync` returns; `Client.new(endpoint, retries: 0,
limit:)` opens no socket and a caller's `ssl_context` reaches the endpoint verbatim;
`Async::HTTP::Endpoint` builds for an `ftp` URL, so the scheme screen is the adapter's; the response
body is lazy, pull-shaped, BINARY and unfrozen; `Protocol::HTTP::Headers#add` keeps a duplicate name.
**What the design stated that 2.46.0 does not bear out**, each a ledger row or a note: `Kernel#Async`
inside a running task **is** that task's child (the design's fact 10 said otherwise; guard 14 is
therefore equivalent), and `cause:` does not carry a Symbol (the design's fact 8). **What differs by
row**: on 4.0.6 alone the first `IO::Buffer` under a scheduler prints Ruby's once-per-process
experimental warning, parked by `test/support/async_http_warmup.rb` (`P8-98`); on 3.3.12 the bundle
must carry a compiled `openssl` 4.0.2 because the interpreter's own 3.2.4 is older than `io-stream`
requires, on 3.4.10 the interpreter's 3.3.3 would satisfy it and the bundle used here resolved the
installed 4.0.2 anyway (`matrix_facts_test.rb` prints "installed gem" on both rows), and 4.0.6's own is
4.0.2 (its row prints "installed gem" too, for the reason 8a's checklist gives about this machine's
gem directories).

## Guards run red

The reviewer's thirty mutations were run one at a time through a harness that applies the edit, runs
the owning suites under `ruby -w`, captures the first failure and restores the file — on **4.0.6 and
3.3.12** (the gem's floor row; 3.2.11 has no bundle for it). **Thirty-four of the thirty-six rows
they make (the a/b splits counted) are red on both interpreters, and the two equivalent mutants
are recorded with their measurement.** Five guards the
first pass found missing were added before the second pass and are what make rows 11, 13a, 13b, 15,
16, 20 and 27b red rather than surviving or hanging: the mutex scan reaches `build_client`;
`assert_exchange_released` proves the watcher is gone after an undelivered settlement; `reactor_over`
closes a holding fixture *inside* the reactor so an exchange a defect left blocked is released and the
failed assertion surfaces instead of the reactor waiting forever; every wait in a cancellation or
timeout test is bounded (`value_within`, `with_timeout`) so a missing timeout or a lost cancel is a
failed assertion, not a hang; and `TRANSPORT-3`'s test feeds the classifier the SDK's own errors under
a cancelled token. Review round 0 ran six mutations of its own beyond the thirty; two survived and
are rows 34 and 35 below, each made red on 2026-09-21 by the guard its row names. Review round 1 re-ran
every row and seven extras of its own: five caught by existing tests (its 36, 39, 41, 42 and 43), one
equivalent by measurement (its 40 — `RequestBody#read`'s `String#b` is redundant behind 3a's ingress
retag) and one surviving, row 37 below, made red the same day by the cause the body-path test now
refutes. Review round 2 re-ran every row and seven extras of its own: three caught by existing
tests (its 45, 48v and 49), one equivalent by measurement (its 46, row 46 below — the
`CancelledError` wrapped into `Task#cancel(cause:)` is read back by nothing, and its
documentation was the fix), and three surviving, rows 44, 47v and 51 below, each made red on
2026-09-21 by the guard its row names — **forty of forty-three rows red**, three equivalent.

| # | Mutation | Caught by (first failure) | Rows |
|---|---|---|---|
| 1 | `revalidate!` skipped | `request_mapper_test.rb` `HeaderGatesTest` "HTTP-17: a header name HeaderSyntax rejects raises before anything is mapped" (no raise), "HTTP-18"; `wire_grammar_test.rb` `RevalidationTest` (the CRLF value reaches the h2 peer) | 4.0.6, 3.3.12 |
| 2 | the token predicate replaced by `HeaderSyntax.valid_name?` | `wire_grammar_test.rb` `TokenPredicateTest` over http1 (`RefusedError` through the future, no 200), over plaintext and tls (`x-bad:name` in `received`); `request_mapper_test.rb` "TRANSPORT-12/13, P8-40" | 4.0.6, 3.3.12 |
| 3 | the latch keyed on the raw name | `drop_policy_test.rb` "the per-name latch is case-insensitive on the folded name (HTTP-13)" (`[:warn, :warn]`) | 4.0.6, 3.3.12 |
| 4a | `MAX_TRACKED_NAMES` bound removed | "bounded at MAX_TRACKED_NAMES distinct names; the next degrades to quiet" (`:warn` for the 65th) | 4.0.6, 3.3.12 |
| 4b | `DropPolicy.build(mode: :bogus)` accepted | "a rejected mode raises Dexpace::InvalidArgumentError rather than degrading silently" | 4.0.6, 3.3.12 |
| 5 | a framing drop routed through the policy | `request_mapper_test.rb` "TRANSPORT-11: the ten framing headers are dropped and logged verbose" (`:warn` where `:debug` was expected) | 4.0.6, 3.3.12 |
| 6 | `FRAMING_HEADERS` loses `host` | "TRANSPORT-11: the drop set is exactly the ten folded names", "a body maps to a RequestBody…; framing is never copied" (a second `host:`) | 4.0.6, 3.3.12 |
| 7 | `Endpoints.for` through `Endpoint.parse(url.to_s)` | `endpoints_test.rb` "never calls Endpoint.parse or URI.parse anywhere under lib/" (the source scan) | 4.0.6, 3.3.12 |
| 8 | the default context drops `alpn_protocols` | `endpoints_test.rb` "the adapter-supplied ssl_context offers h2 and http/1.1 by ALPN" — the default context's ALPN is asserted at unit level only, because `dispatch_conformance_test.rb`'s tls variant builds its adapter with the fixture's own caller `ssl_context`, a context that never reaches the default line | 4.0.6, 3.3.12 |
| 9 | the default context at `VERIFY_NONE` | `endpoints_test.rb` "an https URL always gets an adapter-supplied ssl_context that verifies the peer" | 4.0.6, 3.3.12 |
| 10 | `retries: 0` dropped from `build_client` | `clients_test.rb` `FetchTest` "every client disables the native retry loop (TRANSPORT-2, 17, 18)" | 4.0.6, 3.3.12 |
| 11 | the client built inside the mutex | `clients_test.rb` "the client is built outside the mutex: no Endpoints call inside a synchronize block" (the scan now reaches `build_client`; the first pass survived) | 4.0.6, 3.3.12 |
| 12a | the `MAX_ORIGINS` drain removed | "XCUT-14: the map is bounded at MAX_ORIGINS…" (33), "…a client whose reactor has closed is evicted before a live one", "…an evicted client's pool is retired and closed" | 4.0.6, 3.3.12 |
| 12b | an evicted client dropped, never retired | "XCUT-14: an evicted client's pool is retired and closed, never merely dropped" | 4.0.6, 3.3.12 |
| 13a | `Clients.release` through `Client#close` | `clients_test.rb` `ReleaseTest` "close returns at once with a response still open" (the bounded close flunks: "close waited on the open response instead of retiring it (P8-37)"), "close retires every pooled resource… never through Client#close" — the first pass **hung** until the test released the open response inside the reactor | 4.0.6, 3.3.12 |
| 13b | `pool.close` without retiring busy resources first | the same two, the drain waiting on the busy connection | 4.0.6, 3.3.12 |
| 14 | the exchange spawned with `Async { }` instead of `caller_task.async` | **Equivalent on async 2.46.0**: `Kernel#Async` inside a running task delegates to `Task.current.async`, so the exchange is the supervisor's child either way (`inner.parent.equal?(task)` measured true; `matrix_facts_test.rb` "P8-39 fact: Task#async runs the child eagerly…" and the design's fact 10 corrected in the knowledge note); `parent_cancellation_test.rb` stays green, honestly | measured on 4.0.6, 3.3.12 |
| 15 | the token hook cancels the exchange directly | `cancellation_test.rb` "a token cancelled from a foreign OS thread still reaches the exchange, promptly" (`NoMethodError: private method 'raise' called for nil` out of the hook on the canceller's thread) — the first pass hung after the error until the body-path read was bounded | 4.0.6, 3.3.12 |
| 16 | `queue.close` missing from `release_watch` | `parent_cancellation_test.rb` "TRANSPORT-8's pair", `adapter_test.rb` `TimeoutTest` — "the exchange task or its watcher outlived the settlement by 10 turns" (the first pass survived: nothing asserted the watcher's release) | 4.0.6, 3.3.12 |
| 17 | a cancellation settled through `#fail` | `errors_test.rb` "settle routes a cancelled token to #request_cancel and everything else to #fail" (`Future#cancelled?` false); `adapter_test.rb` "an already-cancelled token settles a CANCELLATION before anything is mapped or sent" (the `check!` raise goes through `#dispatch`'s fence into `Errors.settle`) | 4.0.6, 3.3.12 |
| 18 | check-after-resume removed | `cancellation_test.rb` "a token cancel in flight while the exchange finishes never raises out of Source#cancel on the canceller's thread, and the future is cancelled" — with the check gone the fake 204 is delivered once the flag is up and the `Dexpace::CancelledError` the test expects is never raised (the second 4.0.6 failure is the knock-on leaked canceller thread); the close count measured separately stands: core's `Completer#fulfil` closes a response handed to an already-settled pivot (`close_quietly` inside `fulfil`, phase 2), so `TRANSPORT-9`'s native body is closed exactly once either way and the check is a shortcut past the mapping, not the guarantee | 4.0.6, 3.3.12 |
| 19 | the undelivered native body not closed on `finish` | `parent_cancellation_test.rb` `CloseDisciplineTest` "TRANSPORT-22: an adaptation failure after the head closes the native body exactly once" (0), "R13" | 4.0.6, 3.3.12 |
| 20 | the per-call `with_timeout` removed | `adapter_test.rb` `TimeoutTest` "TRANSPORT-4/TRANSPORT-8's pair" (a `:deadline_expired` cancellation where a `TransportError` was expected), `parent_cancellation_test.rb` "TRANSPORT-8's pair" — the first pass hung until the waits were bounded | 4.0.6, 3.3.12 |
| 21 | `ResponseBody#each` delegating to the native `#each` | `response_body_test.rb` `PullAndCloseTest`, six failures: the double close, the read-after-close, the release hook's count | 4.0.6, 3.3.12 |
| 22 | `#source` not memoised | "#source is built with BufferedSource.over and is the same handle every call (BODY-14)", "reading through #source twice continues where the first read stopped" | 4.0.6, 3.3.12 |
| 23 | the mid-stream `StreamError` classification removed | `ReadSurfaceTest` "P3-3: a native failure mid-stream surfaces as StreamError with the cause, and closes" (a bare `EOFError` escapes) | 4.0.6, 3.3.12 |
| 24a | the mapper reads the response's length | `response_mapper_test.rb`, ten errors (`NoMethodError`) and the length test | 4.0.6, 3.3.12 |
| 24b | a nil native body (204) unhandled | `BodyTest` "a response the library delivers with no body — a 204 — gets body nil" (`NoMethodError` on nil) | 4.0.6, 3.3.12 |
| 25 | `media_type_for` loses its rescue | "TRANSPORT-27: a malformed Content-Type downgrades to no media type" (`InvalidArgumentError` escapes) | 4.0.6, 3.3.12 |
| 26 | `inbound_headers` loses the per-value guard | `HeadTest` "TRANSPORT-14: a control byte in an inbound value is dropped, that header only" (`Headers::Builder#add` raises `HTTP-19`) | 4.0.6, 3.3.12 |
| 27a | `Errors.wrap` re-wraps a `Dexpace::` error | `errors_test.rb` "a Dexpace:: error is passed through unwrapped, unchanged" (`assert_same`) | 4.0.6, 3.3.12 |
| 27b | `Errors.wrap` consults the class before the token | "TRANSPORT-3: asks the cancellation token first… an IOError and a Dexpace:: error included" (a `ClosedError` under a cancelled token passed through) — the first pass survived because the list held native families only | 4.0.6, 3.3.12 |
| 28 | the reactor check removed | `adapter_test.rb` `PreDispatchTest` "TRANSPORT-21: calling outside a reactor settles a SeamError through the future" (`RuntimeError: No async task available!` wrapped retryable instead) | 4.0.6, 3.3.12 |
| 29 | the post-close guard raises inside `#dispatch` | **Equivalent by construction**: `Adapter#dispatch`'s one `rescue ::StandardError` fence settles the raise through the future, so the guard's channel is structural (`TRANSPORT-21`); measured green | measured on 4.0.6, 3.3.12 |
| 29b | the post-close guard raises from `#call`, outside the fence | "a send after close settles ClosedError through the future on an owning adapter" (a synchronous `ClosedError`) | 4.0.6, 3.3.12 |
| 30 | `Endpoints.screen!` admits every scheme | `endpoints_test.rb` "a scheme other than http or https is refused as InvalidArgumentError, not dialled"; `adapter_test.rb` "TRANSPORT-21: a URL the endpoint cannot dispatch settles InvalidArgumentError" (a `TransportError` from dialling port 21 instead) | 4.0.6, 3.3.12 |
| 34 | `ResponseBody#each` yields the chunk without the `String#b` retag (review round 0's R0-3) | `response_body_test.rb` "#each yields one native #read per chunk, retagged BINARY, and stops at nil" — the first chunk the double hands over is now a UTF-8 literal, so the yielded encodings `[UTF-8, BINARY]` fail the `[BINARY, BINARY]` pin; the round-0 fixture fed BINARY chunks alone and the mutant survived it | 4.0.6, 3.3.12 |
| 35 | `Exchange#net`'s `request_cancel(:async_cancelled) unless settled?` removed (review round 0's R0-4) | `parent_cancellation_test.rb` `CloseDisciplineTest` "a runtime cancellation landing inside an exit arm's native close still settles the pivot cancelled, through the ensure's net" — the adaptation-failure arm is parked inside a native `#close` that waits on a queue, the parent is cancelled there, and with the net gone the future stays pending until the bounded wait expires (`:deadline_expired` where `:async_cancelled` is pinned, 5.2 s); no fixture reached the path before this case, and no sleep is involved | 4.0.6, 3.3.12 |
| 37 | `Exchange#watch` no longer closes the DELIVERED response on a cancel (review round 1's R1-1) | `cancellation_test.rb` "TRANSPORT-7 on the body path: a token cancelled under a blocked body read wakes the reader with CancelledError and releases the body" — `refute_kind_of(::Async::TimeoutError, error.cause)`: with the close gone the read is woken by the test's own five-second bound, the token-first classifier still answers `CancelledError(:reader_cancelled)` with the body closed, and only the cause (`Async::TimeoutError` where the watcher's close leaves a bare `IOError`) tells the two wakes apart — the round-1 fixture passed in 5.0 s where the real code takes 16 ms. The same mutant hung the portable `TRANSPORT-7` row under the driver whenever the race fell on the body path (half the runs on 4.0.6, a third on 3.3.12; the rest take the in-flight path and pass) until `around:` bounded the assertion from a parent task: a flunk at thirty seconds now on both rows, no hang, nothing on stderr | 4.0.6, 3.3.12 |
| 44 | the watcher spawned without `transient: true` (review round 2's R2-3) | `cancellation_test.rb` "ASYNC-20: cancelling the future after delivery does not close the delivered response; its watcher stays, transient, until the body is released" — the watcher's `transient?` is read while the body is open and asserted after its release (`[false]` where `[true]` is pinned, 18 ms); before this guard the mutant surfaced only as `adapter_test.rb`'s borrowing case holding its reactor open until the run was killed, because a non-transient watcher under a never-closed body keeps `Sync` from returning | 4.0.6, 3.3.12 |
| 46 | `Task#cancel(cause: reason)` instead of `cause: CancelledError.new(reason)` (review round 2's R2-4) | **Equivalent, measured**: `cancellation_test.rb` and `parent_cancellation_test.rb` stay green (12 runs) because the pivot is settled with the reason before the watcher acts — the token's hook settles it before it pushes, `Future#cancel` settled it to run its hook at all — so `#run`'s exit arm never reads the `Cancel`'s cause; the wrap stays for whoever reads the cancelled task (a Symbol is replaced by `Async::Cancel::Cause`) and the record says so instead of calling it load-bearing | measured on 4.0.6, 3.3.12 |
| 47v | `RequestMapper#body_for`'s `body_forbidden?` guard removed (review round 2's R2-2) | `request_mapper_test.rb` "a body-forbidden method attaches none, even on a forged request carrying one" (a `RequestBody` where nil is pinned, for the forged GET) — the former assertion built its GET through the model, whose `HTTP-7` had already made the body nil, so the guard was reachable by no test | 4.0.6, 3.3.12 |
| 51 | `Exchange#signal`'s `rescue ::ClosedQueueError` removed — the bare push of the pre-fix tree (review round 2's R2-1) | `cancellation_test.rb` "a token cancel in flight while the exchange finishes never raises out of Source#cancel on the canceller's thread, and the future is cancelled" — `Source#cancel` returns `ClosedQueueError: queue closed` where `true` is pinned: a caller hook registered first parks the canceller between the flag flip and the adapter's hook, a fake client answers a 204 once the flag is up, check-after-resume settles the pivot and closes the queue, and the adapter's hook then pushes onto it | 4.0.6, 3.3.12 |

Beside the thirty: `async_http_test.rb`'s two source scans (every `Async`, `Protocol`, `OpenSSL` and
`Console` reference under `lib/` `::`-qualified, and the require set exactly `dexpace`, `async/http`
and `openssl`), the ivar pin behind `ASYNC-22`, and `conformance/transport_suite/asynchronous_test.rb`
and `header_drops_test.rb`, which run every portable assertion against `RawWireTransport`'s
correct behaviour and against a named defect for each direction the assertion has.

## Audit groups run

The phase-start pair first, at implementation on 2026-09-21: `--origin note --brief` (the notes on
`transport-adapter`, `concurrency-and-async` and the phase-8 facts among them) and
`--section conflicts --brief` with every one of the six harvested conflicts
`[overridden by notes/…]` and none open. The thirteenth audit group's two halves,
`--prefix TRANSPORT --section rules --brief` and `--prefix ASYNC --section rules --brief`, and
`--req` per task against the IDs each task names; the corpus's `ASYNC-21`/`-22` hits are
appendix-B roll-ups, so both were read from chapter 18 itself.

| Group | Result at implementation |
|---|---|
| Public API surface | One public constant per file; `async_http.rb` carries the module's constants and functions on the entry-file precedent; the eight helpers are `private_constant`s, `Adapter.new` is private behind the two factories, `DropPolicy.new` behind `.build`; the manifest lists `Adapter`, `DropPolicy`, the entry-file constants and nothing private |
| Gem layout, zero-dependency core | `gates:gemspec_audit` (`dexpace-core` + `async-http`), `gates:require_allowlist` (the adapter's `openssl` is on the allowlist; `async/http` is the gem's own declaration) and `gates:clean_bundle` (six gems on 4.0.6, five on 3.2.11) green; nothing in core names the gem beyond the one configuration key |
| RBS / Steep typing | Every new file mirrored; the `:async_http` target relaxed for `UnknownConstant` exactly as `:serde_json` is, with `library "openssl", "uri"`; `_Release` is the one new interface; three typing facts the build met are under Deviations (`Dexpace::Error` is a module, so the classifier's pass-through predicate lives in `own?`; `URI::Generic#request_uri` exists only on `URI::HTTP`, so the mapper asserts the class the screen guarantees; a `Method` does not satisfy a proc type, so the release hook is a lambda over an interface) |
| Minitest conventions | Every suite subclasses `DexpaceTestCase`; nine suites split into nested classes under `Metrics/ClassLength` (8a's shape); no `.stub`; every wait bounded — a queue pop, a `with_timeout`, a `value(deadline:)` — and no `sleep` outside `matrix_facts_test.rb`'s scheduler facts; every thread a test starts is joined before it returns |
| Fiber scheduler, thread safety | The adapter is frozen in effect; the one mutable per-call object is the `Exchange`, whose cross-thread state is one `Thread::Queue`; `Clients`' mutex guards a `Hash` read and insert and nothing else (the client is built outside it, asserted by scan); the pool's own gardener is the one transient task that outlives an exchange, by the library's design |
| Transport and async-runtime adapters | Every `TRANSPORT` rule in the group restates a clause proven above; `transport-adapter/cb7901ef`'s per-protocol grammar entry is the note the design filed and stands; the two new note entries record what 2.46.0 and 0.105.0 measured that the design did not (the cancel-across-threads facts; the reactor-exit drain and the h2 double release) |
| Observability, configuration and redaction | Every emission inside `Instrumentation.contain`; the drop record carries the header name and the reason under `TRANSPORT_HEADER_DROPPED`; `REQUEST_TIMEOUT` through `#duration`, `TRANSPORT_CONNECTION_LIMIT` through `#integer`, both read at construction — and every test that pins a value the chain resolves builds its chain through `AsyncHTTPHermeticConfiguration` (`Sources::NONE` on the environment tier), because `Configuration.build`'s default reads the real process environment and the two default pins and the `ASYNC-22` pool bound moved under an exported `TRANSPORT_CONNECTION_LIMIT` / `REQUEST_TIMEOUT` until review round 0's R0-1 (measured: 3 where 8 was pinned, 5.0 where 60.0, 16 connections where at most 8); a `.build` with no `configuration:` still reads `Dexpace.configuration`, as `dexpace-transport-net_http`'s does, and no test pins a default through it |

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate. Items
1–13 are where the built tree or the manager's binding decisions overrode the plan's assumptions,
in the order the brief's as-built list gives them; 14–42 are this build's. The ones that touch public
behaviour or a statement the design makes are also the as-built ledger rows `P8-91`–`P8-102`.

1. **`Dexpace::TransportError`, `Events::TRANSPORT_HEADER_DROPPED` and `Keys::REQUEST_TIMEOUT` were
   already on the base** (8a's Task 2), so Task 4 verified and added nothing; the one core widening
   is `Keys::TRANSPORT_CONNECTION_LIMIT`, and its two pins were flipped on the code branch.
2. **The client map is keyed by (reactor, origin), not by origin alone** — the manager's decision on
   the cross-check's open question 1 (`P8-92`); `MAX_ORIGINS` caps pairs.
3. **The adapter opens no reactor of its own, and the conformance driver opens one per settle on a
   foreign thread** (`P8-94`).
4. **8a's `Scripts` gained `Connection: close` on every head** with identical counts, and a `close:`
   keyword for the one keep-alive fixture (`P8-96`).
5. **The require set is `dexpace`, `async/http` and `openssl` only**, asserted by scan; the design's
   two extra `require` lines are not written.
6. **`TRANSPORT-8` is in this gem's own suite, and the portable groups carry six assertions plus the
   `PREAMBLE` sentence**, not the plan's seven (`P8-93`).
7. **The cancellation bridge is queue-marshalled** (`P8-91`), not the design's direct `#cancel`.
8. **`TRANSPORT_CONNECTION_LIMIT` is the one core widening.**
9. **The `:async_http` Steep target relaxes `UnknownConstant` to `:information`** with `library
   "openssl", "uri"`, and `rbs_collection.yaml` carries the plan's `- name: async / ignore: true`
   row (`P8-99`). The first cut of this record said the row was unnecessary because "the collection
   carries none"; review round 0's R0-2 measured otherwise: `ruby/gem_rbs_collection` carries
   `gems/async/2.12` — a `Task` with `#stop` and neither `#cancel` nor `.current?` — and `rbs
   collection install` installed it the moment the workspace gem's own `ignore: true` was lifted,
   turning `steep` red; rbs 4.2.0 cuts its dependency walk at an ignored gem, which is the only
   reason the walk never reached `async` on the committed tree. The row keeps the stale signatures
   out however the walk is reached (measured on 2026-09-21: with the workspace gem un-ignored the
   walk reaches 38 gems and installs no `async`; with it ignored the lock is unchanged and `steep`
   green), and nothing else in the closure has a collection entry or ships a `sig/`.
10. **Every top-level test double is prefixed `AsyncHTTP`** (`test:gems` loads six gems' `test/support/`
    into one process).
11. **`ResponseMapper` hands the native body, never the response.**
12. **The bare-require child process carries `GEM_PATH`** so the scratch bundle resolves there.
13. **`Adapter.new` is private**, `openssl` 4.0.2 on 3.3 is stated in `docs/first-release.md`, and
    8a's `R3-1` chunked-length case is reported on 8a's row (unreachable here: `protocol-http1`
    refuses the head).
14. **The gemspec reads its floor from `VERSIONS`** — `DexpaceVersions.ruby_floor("dexpace-transport-async_http")`
    — rather than the literal `">= 3.3"` the plan wrote, so the file has one source of truth (`P8-95`);
    `gates:versions` and `gates:gemspec_audit` read the same row.
15. **`P8-37` as built retires every pooled resource before `pool.close`**, because `pool.close`
    alone drains and waits on a busy connection (`P8-100`).
16. **The native body's close goes through `Dexpace.close_quietly`**, because closing an unread HTTP/2
    body double-releases the pooled connection inside the library (`P8-101`).
17. **`test/support/async_http_warmup.rb`** spends Ruby 4.0's `IO::Buffer` warning before the fatal
    hook can see it (`P8-98`).
18. **No `application/octet-stream` default** (`P8-97`): `async-http` stamps no `Content-Type`, so
    8a's reason does not exist here and inventing a type would be a claim about the bytes.
19. **`Endpoints.screen!` is called first in `RequestMapper.call`**, so an undispatchable scheme is
    `InvalidArgumentError` and never a `NoMethodError` wrapped retryable.
20. **`AsyncHTTPServerFixture` needs no readiness probe** (`Task#async` runs the server to its first
    suspension, the listener bound), closes through `#cancel`, exposes `closed?` over the task tree,
    and wraps the library's server in `QuietServer` so a peer that closes mid-head — an exchange
    cancelled during its send — is not a Console line on stderr.
21. **HTTP/2 through the owning adapter is reached over TLS by ALPN** (`build(ssl_context:)` trusting
    the fixture's certificate); plaintext prior-knowledge h2 is a borrowed client's.
22. **The parent-cancellation supervisor parks on a queue**, never a sleep, and hands its future
    back through a `ready` queue, because `Task#async` returns to the caller before the child's
    block has assigned it.
23. **Nine suites are wrapped in a module holding nested classes** under `Metrics/ClassLength` (8a's
    shape), `Style/OneClassPerFile` and `Style/Documentation`.
24. **The conformance groups are two files**, `asynchronous.rb` and `header_drops.rb`, under
    `Metrics/ModuleLength`; the suite is seven groups, and the counting pins say so.
25. **`Scripts` gained a private `head(*fields)`** so the module stays under its length cap with the
    `Connection: close` lines.
26. **`RawWireTransport`'s `header_lines` folds the drop into `copied?(name, folded)`**, its `attempt`
    into `subscribe`, its `build_response` into `reason_for`, and the fixture's `certificate_for`
    applies its attributes from a hash — all `Metrics` cops, no behaviour.
27. **`Adapter#exchange_for`, `Exchange#net`, `Clients#drain`, `Errors#own?`** are extractions the
    `AbcSize` cop asked for; `own?` also keeps `Errors.wrap`'s parameter typed `Exception` for Steep,
    because `is_a?(Dexpace::Error)` narrows to a module type.
28. **`RequestMapper` asserts `URI::HTTP`** (`url = request.url #: URI::HTTP`) after the scheme
    screen, because rbs declares `#request_uri` on `URI::HTTP` alone.
29. **The body's release hook is a lambda over the `_Release` interface**, never a `Method`, which
    Steep does not accept for a proc type.
30. **`Exchange::WATCHER_ANNOTATION`** names the watcher in the task tree, for the suite's release
    assertion and for anyone reading a reactor's hierarchy.
31. **`AsyncHTTPReactor`** — `reactor_over(server)` and `assert_exchange_released(task)` — was added
    after the first mutation pass, for the reasons the *Guards* section gives; and
    **`AsyncHTTPHermeticConfiguration`** after review round 0, because the plan's tests built every
    chain through `Dexpace::Configuration.build`'s defaults and the two default pins and the
    `ASYNC-22` pool bound read the host's environment (R0-1; the *Audit groups* row has the
    measurement).
32. **The three cancellation tests and both timeout pairs assert the exchange and its watcher are
    gone** within ten reactor turns (measured: two on a cancellation, one on a timeout).
33. **The driver's foreign-thread settle materialises the body inside its reactor** through
    `Response#body_bytes` into a `BufferBody` (`P8-94`); the plan's plain `Sync { value }` hangs.
34. **The driver reports four skips, not three**: the suite carries two assertions under
    `TRANSPORT-14`, and a waiver is by id.
35. **`matrix_facts_test.rb`** re-runs eight facts per row on 8a's precedent; the plan ran them once
    in a scratch script.
36. **`errors_test.rb`'s `TRANSPORT-3` list includes the SDK's own errors** under a cancelled token,
    because the native-only list let mutation 27b survive.
37. **The clients suite's open-response close runs over `reactor_over` and releases the response in
    its ensure**, because a close that waited leaves the reactor unable to exit.
38. **`docs/first-release.md` changes in existing entries only**: the conformance-suite blocker and
    the `P8-9` documentation blocker each gain a dated status sentence and the latter's box ticks,
    the `gates:bounded_map` blocker gains its status, and the supported-Ruby note names 0.105.0.
39. **Two knowledge-note entries were added and none edited**: `transport-adapter.md` (the reactor
    exit drain, `P8-37` as built, the h2 double release, the 4.0 warning) and
    `concurrency-and-async.md` (the three `Task#cancel`/`Kernel#Async` facts).
40. **`CLAUDE.md`'s built-phases paragraph, gem sentences, floor sentence and counts were re-derived
    from the tree**: 220 `lib/dexpace/` files unchanged, nineteen checklists, twelve files in this
    gem's `lib/` and twenty-five in `dexpace-conformance`'s.
41. **The `TRANSPORT-8` and `ASYNC-21` rows state their disposition rather than tick**, as the
    cross-check's summary directed.
42. **The driver's `around:` runs each assertion as a child task under `finished: false` and bounds
    the PARENT's wait** (`AROUND_BOUND`, thirty seconds; review round 1's R1-1). The plan's shape
    with a bound added — `with_timeout` around the assertion's body — raises into the assertion's
    own fiber, where the adapter's token-first classifier turns it into the `CancelledError` the
    cancellation rows expect: measured passing the mid-body row thirty seconds late against the
    mutant of guard 37. On expiry the driver cancels the child instead (`Async::Cancel`, which no
    classifier converts, and `Response#body_string`'s ensure releases the connection so the reactor
    drains) and raises its own `Failure`, a flunk naming the row's ids.
43. **Both cancellation hooks push through `Exchange#signal`, which rescues `ClosedQueueError`**
    (review round 2's R2-1). The plan's hooks pushed onto the queue bare; `Cancellation::Source#cancel`
    and `Completer#settle` each steal their hook list under their own mutex and run it outside, so
    an exchange that finished between the steal and the run — check-after-resume saw the flag the
    cancel had already flipped, settled the pivot cancelled and closed the queue — met a push onto
    a closed queue, and `Hooks.notify` handed that `ClosedQueueError` back to the caller's own
    `Source#cancel` on the cancelling thread while the future read cancelled. Reproduced
    deterministically on 4.0.6 and 3.3.12 with an ordinary caller hook registered first; a
    `closed?` check first would be the same race one instruction later, so the push is total
    instead. The `CancelledError` the watcher wraps into `Task#cancel(cause:)` is kept, and the
    record now says what it is for: the task's own `Async::Cancel` names the SDK's reason for
    whoever reads the task, and nothing in the adapter reads it back (R2-4, guard 46 equivalent).

## Findings routed

Anything execution found, routed to its owner when found; a finding the design already routed is
**verified still owned** and not re-recorded:

- **Verified still owned, on phase 10's inbound list**: §12's `TRANSPORT-14` scoping and its
  `TRANSPORT-8` vacuity claim (the design's two entries); 8a's `R6` no-route-to-a-tracer finding
  (`P8-7`); phase 2's `Transport.async_over` return-type check (the plan's README item 5, verified
  open and stated in the README rather than fixed here).
- **New, to phase 10's inbound list, by date and content (2026-09-21)**: the design's verified facts 8
  and 10 are stale on `async` 2.46.0 (`cause:` drops a Symbol; `Kernel#Async` inside a task is the
  task's child) — the design is frozen to this phase and the correction is a knowledge-note entry, so
  the roadmap bullet is the pointer for whoever consolidates the ledger; and `async-http`'s server
  letting a mid-head `EOFError` escape to Console, worked around in the test fixture and worth an
  upstream report.
- **New, to phase 10's inbound list, by date and content (2026-09-21, review round 1)**: the portable
  `TRANSPORT-7` row's path against a streaming adapter is a race — the cancel lands before or after
  the adapter has checked its token on the delivered head — so the row proves the in-flight clause
  everywhere and the delivered-body clause by chance; the contract's primitives cannot settle it for
  an eager and a streaming adapter alike without a bound inside the assertion, the row's own
  comment states the race (the code branch), and a deterministic portable form — the consumer
  signalling from inside the read, an eager adapter measured vacuous — is conformance-gem work
  routed rather than done in a fix round.
- **To `docs/first-release.md`**, in existing entries only: the conformance-suite line's status (the
  `async-http` half ran, four skips accounted for), the `P8-9` box ticked with 8c's waivers stated in
  `conformance.md` and the `PREAMBLE`, the `gates:bounded_map` line's status.
- **To the knowledge notes**: the two Reference entries named above.
- **Fixed in material this phase may write, not findings**: the reactor-exit hang in the driver, the
  h2 double release, the stale keep-alive race in `Scripts`, the surviving and hanging mutants, the
  fixture's Console line; and, from review round 1, the body-path test's bound indistinguishable
  from the watcher's close and the driver's unbounded `around:` (guard 37, deviation 42); and, from
  review round 2, the hook's push racing the exchange's own end (guard 51, deviation 43), the
  body-forbidden guard no test reached (guard 47v), the watcher's transience provable only by a
  hang (guard 44), and the record calling the `cause:` wrap load-bearing (guard 46).

## Postponed work

Task 19 Step 5a's two items, as the design's *Work phase 8c postponed* section directs:

- **`OBS-19`'s header-drop policy (phase 5b postponed it to phase 8) — landed.** `DropPolicy` (Task 7),
  the predicate at dispatch (Task 9), the both-protocols test (Task 15), the antecedent confirmed on
  `protocol-http1` 0.41.0; the roadmap's status note says so.
- **The wire-boundary re-validation (phase 1 postponed it to the adapters) — complete in both
  adapters.** 8a's Task 16 landed first on this tree, this phase's Task 9 second, and this phase says
  so in the roadmap's status note; phase 9's Task 7 adds the portable assertion beyond 8a's two.

The consolidation of `P8-36`–`P8-40` and `P8-91`–`P8-102` into design §10 is a human's:
`docs/sdk-design-ruby/` is frozen, as it was for every phase before, and `docs/deviations.md` waits
for phase 10 to flip.
