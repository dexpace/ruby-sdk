# Phase 6a — Retry: Checklist

**Written at execution time, 2026-09-18, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section below
is where each departure is stated with its reason. The design and the plan were written on 2026-09-09
(reviewed 2026-09-13) against phases 0–3's *plans* and phases 4 and 5's *designs*, on a machine that
then had only Ruby 3.4.10, concurrently with 6b's and 6c's documents. Since then phases 4a, 4b, 4c, 5a,
5b and 5c were all built, reviewed and merged to `main` (PRs #53–#62, #63–#71) and every interpreter in
the matrix was installed. **This phase was cut from `main` at `f1fe848`**, which holds all of phase 5;
phase 6c (issue #24) was being built at the same time in another worktree, also off `main`, and nothing
here describes anything of 6c's as landed. Where the plan's text and the built tree disagree the tree
wins and this document records it.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry.md`. Task numbers are that plan's.
Design: `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-design.md`, whose Deviation Ledger rows
`P6-1`–`P6-12` and as-built rows `P6-51`–`P6-61` are cited below (`P6-59`–`P6-61` from review round 1,
2026-09-18); the charter is
`docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`. Every test file named here is under
`gems/dexpace-core/test/`, mirrors its `lib/` file one for one (one carries no `lib/` mirror and says so
below; two `private_constant`s carry no `test/` mirror and are asserted at their call sites), and opens
with the IDs it exercises.

## Requirement rows

**Sixty own rows** — `RETRY-1`–`RETRY-45` and the fifteen `RECOV` IDs phase 4 postponed here,
`RECOV-17`–`RECOV-30` and `RECOV-34`, each `RECOV` row carrying its `RETRY` twin from the phase-4
segmentation design's table as an *annotation* and never as its disposition — plus the three rows the
charter names outside the budget (`RECOV-31` ⏳ beside `RETRY-38`'s, `CFG-35`'s inherited throwable
half, and the cross-reference rows the design's interface-surface table is the source of, the way 4b,
4c, 5a, 5b and 5c carried theirs). Of the sixty: **fifty-six ✅**, **one owner-elsewhere** (`RETRY-4`,
phase 8a's Task 2, as the design's disposition table says), **three ⏳** (`RETRY-29`, `RETRY-38`,
`RETRY-43`, declined for v1), nothing 🚫, nothing N/A.

### `RETRY` — 45 rows

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `RETRY-1` | MUST | ✅ | 3, 6 | The single-sourced status classifier is 5a's `Dexpace::Retryability.retryable_status?` — 408, 429 and 500–599 less 501 and 505 — and 6a builds no second one: `ProtocolError#retryable_by_status?` reads it once at construction (Task 6) and `Policy::DEFAULT_RETRYABLE_STATUSES` is asserted a SUBSET of it, code by code (`policy_test.rb`, "XCUT-7: the default configurable set"; `error/protocol_error_test.rb`, `RetryableTest`, the whole 400–599 range against the classifier). The recovery stack's configurable allow-list on top is `RETRY-37`'s row |
| `RETRY-2` | MUST | ✅ | 3 | `Policy.throwable_retryable?` is XCUT-6's capability query — `respond_to?(:retryable?) && retryable?` — walked over the error and its whole cause chain through 4b's `Dexpace.each_cause`, whose visited set is `{}.compare_by_identity`, so the cycle clause needs no second walk. Asserted for a capability found at the root, one level down and two levels down; for an `IOError` that answers `false` and phase 3a's `StreamError` (no capability) refused — the two directions a concrete-type match gets wrong; for a `CyclicPair` two-node cycle and a `SelfCause` one-node cycle terminating; and for a non-Exception refused (`policy_test.rb`, `ClassificationTest`). The blind spot is `P6-4`, the `RETRY-4` row. Guard 22 (an `is_a?(::IOError)` query) |
| `RETRY-3` | MUST | ✅ | 6 | `ProtocolError#retryable_by_status?`, computed once in `initialize` from `Dexpace::Retryability.retryable_status?(@status)` — 5a's classifier accepts a `Status` — and stored in `@retryable_by_status`; a subclass inherits the computed flag and no per-subclass constant exists. 4b's constructor keeps its one positional parameter and both factories (`error/protocol_error_test.rb`, `RetryableTest`). Not named `#retryable?`: the `P6-10` row and guard 21 |
| `RETRY-4` | MUST | owner elsewhere — **phase 8a's Task 2** (`docs/work/mvp/phase8/phase8a/`), per the design's disposition table and `docs/first-release.md`'s release-path entry "Phase 8's first transport adapter must wrap every stdlib I/O and timeout error it lets escape", which names `P6-4` | — | Core may not name `Errno::ETIMEDOUT`, `SocketError` or `Timeout::Error` (the bundled-gem rule), so the unconditional flag on a no-response transport failure lives on the wrapper type an adapter raises, `Dexpace::TransportError < ::IOError` with `#retryable?` answering `true`. What 6a supplies is the consumer: a throwable answering the capability is retried on every driver (the `RETRY-2` and `RECOV-17` rows). Verified present at its owner on 2026-09-18, not re-filed |
| `RETRY-5` | MUST | ✅ | 5, 9, 10, 11 | `Resend.eligible?(request)`: body-less iff `request.method.idempotent?`, body-bearing iff `request.body.replayable?`; the four-cell truth table (`resend_test.rb`) and the same rule consulted by all three drivers before any condition is looked at — a replayable POST re-sent, a consumed-body PUT not (`retry_step_test.rb`, `EligibilityTest`; `async_retry_step_test.rb`, `SharedShapeTest`; `recovery_retry_test.rb`, `ClassificationTest`). Phase 3b's `Body.bytes` answers yes and `Body.stream(io, close: true)` no, through the real bodies |
| `RETRY-6` | MUST | ✅ | 5 | The idempotent set is phase 1's `Method::IDEMPOTENT`, read through `#idempotent?` and re-listed nowhere: a text scan over `resend.rb`'s code refutes every method token but `POST`/`PATCH` in a comment, and `{GET, HEAD, OPTIONS, PUT, DELETE}` is asserted against the constant (`resend_test.rb`) |
| `RETRY-7` | MUST | ✅ | 5, 9, 10, 11 | A bare non-idempotent POST gets exactly one attempt, on all three drivers, with a retryable 503 and even with a `should_retry:` answering `true` (`retry_step_test.rb`, "a bare non-idempotent POST gets exactly one attempt"; the async and recovery twins). Guard 27 (the predicate consulted before the gate) |
| `RETRY-8` | MUST | ✅ | 5, 9, 10, 11 | Both axes, neither implying the other: `RetryStepHelpers#decision` checks `Resend.eligible?` FIRST and unconditionally, then the condition, then the budget; `RecoveryRetry#decision` the same. An idempotent PUT with a consumed body is refused; a caller predicate cannot authorise a re-send (`resend_test.rb`; `retry_step_test.rb`, "a should_retry answering true cannot override"). Guard 27 |
| `RETRY-9` | MUST | ✅ | 3 | `Policy.backoff_delay(attempt, …)`: `initial * multiplier**(attempt − 1)` capped at `max_delay`, attempt 1-based, asserted at attempts 1, 2, 3, 6 (6.4) and 7 (12.8 → 8.0), Integer inputs accepted, a Float always returned (`policy_test.rb`, `BackoffAndBudgetTest`) |
| `RETRY-10` | MUST | ✅ | 3 | Symmetric jitter from `[d(1 − j/2), d(1 + j/2)]`: 2,000 seeded draws all inside `[0.75, 1.25]` for d = 1, j = 0.5, with a mean within 0.02 of d and over 1,000 distinct values; j = 0 returns d exactly (delta 0.0); a sub-nanosecond spread returns d exactly, a spread of 1.5 ns draws; a generator answering −0.5 floors at 0.0; the band at the cap is drawn AROUND the cap — 200 seeded draws at j = 1.0 land on BOTH sides of 8.0, which the jitter-then-clip order (every sample exactly 8.0) cannot pass (`policy_test.rb`). Guards 17 and 32 — and the reason the exact-value assertions carry a delta of `0.0` is in the guard table: RuboCop's `assert_in_delta` autocorrection had made them vacuous; guard 32 is review round 0's surviving mutation, R0-7, now caught |
| `RETRY-11` | MUST | ✅ | 3 | Attempt 0, −1 and 1.5 refused with `InvalidArgumentError`; attempt 1,000 and 100,000 saturate to the cap through Ruby's own `2.0**999 → Infinity` and `[Infinity, 8.0].min`; **and the one guard Ruby's arithmetic does not give**: a zero initial delay answers `0.0` at any attempt, because `0.0 * Infinity` is `NaN` and `[NaN, 8.0].min` RAISES — found by the 2,000-attempt trampoline test, `P6-53` (`policy_test.rb`). Guard 18 |
| `RETRY-12` | SHOULD | ✅ | 3, 7 | `Policy::DEFAULT_INITIAL_DELAY = 0.2`, `DEFAULT_MULTIPLIER = 2.0`, `DEFAULT_MAX_DELAY = 8.0`, `DEFAULT_JITTER = 0.2`, `DEFAULT_MAX_RETRIES = 2` — three sends in the stage vocabulary — asserted as values (`policy_test.rb`) and as `RetrySettings.build`'s defaults (`retry_settings_test.rb`), and `RetrySettings` is the first and only reader of 5a's `Keys::MAX_RETRY_ATTEMPTS`, read ONCE at build through a hermetic `FakeConfigSource` seam (the `P6-6` rows). Guard 19 |
| `RETRY-13` | MUST | ✅ | 3, 7, 9, 10, 11, 12 | One calculator, one constant table: `RetrySettings#backoff_arguments` is the exact keyword set `Policy.backoff_delay` takes, all three drivers call it and nothing else, and a text scan over every other resilience file refutes the literals `0.2`, `2.0`, `8.0` and any `DEFAULT_* =` assignment (`retry_step_test.rb`, `TracerAndGuardsTest`); the two clock-driven stacks are asserted to wait on one schedule from one settings object (`budget_equivalence_test.rb`). Guard 1 |
| `RETRY-14` | MUST | ✅ | 12 | The convergence test: `RecoveryRetry`, `RetryStep` and `AsyncRetryStep` built from ONE `RetrySettings`, driven against an identical run of 503s, exhaust after the same number of sends — three under the defaults, `retries + 1` for 0, 1 and 4, and four when `MAX_RETRY_ATTEMPTS=3` is configured (`budget_equivalence_test.rb`, four tests; no `lib/` mirror, and the file says why). The identity is `max_attempts = max_retries + 1` in `RecoveryRetry#max_attempts` (`P6-6`). Guard 4 |
| `RETRY-15` | MUST | ✅ | 2, 4 | `Retry-After` as delta-seconds (integer, fractional, sub-second) and as an RFC 1123 HTTP-date through 5a's ONE parser, `retry-after-ms` and `x-ms-retry-after-ms` as integer milliseconds, `X-RateLimit-Reset` as epoch seconds jittered to `[100%, 120%]` (`policy_test.rb`, `PacingFormsTest`). **R1**: the HTTP-date form's "informational weekday" was already CFG-30's (present, never validated; a wrong weekday parses) and its "single-digit day" was not — 5a's `GRAMMAR` day group was `(\d{2})` and is now `(\d{1,2})`, one edit in `http_date.rb`, and the tolerances after it are stated in "What was built". The absent weekday stays REJECTED, because CFG-31 requires the `Xxx, ` prefix and RETRY-15's word is "informational", CFG-30's own (`http_date_test.rb`, the two `RETRY-15` tests and the amended rejection loop). Guard 11 |
| `RETRY-16` | MUST | ✅ | 4 | The parser is TOTAL and the suite is NEGATIVE: sixteen non-decimal spellings, nine malformed/negative/out-of-range `Retry-After` values, five bad reset and millisecond values, no header at all, a non-String value and a generator that raises all assert `nil`, never `assert_nothing_raised`; a past date is `0.0` and distinct from `nil`; every parser is fenced by `Policy#parse_form`'s rescue besides being total by contract (`policy_test.rb`, `PacingTotalityTest`). Total AND bounded (`P6-61`, round 1's R0-3): a digit run past fifteen digits or a value past 64 bytes is out of range and `nil` before any conversion runs — a 10 MB value in every form answers `nil` in under 50 ms on the parser alone (the wire-value-sized cost is phase 1's inbound `Headers` builder's, not the parser's), and a 400-digit run emits NO Ruby out-of-range warning, recorded with `WarningCapture` because the suite's `NFR-6` raiser and `parse_form`'s fence had turned the warning into a swallowed error the negative suite could not see (`PacingBoundsTest`). Guards 12, 13 and 33 |
| `RETRY-17` | MUST | ✅ | 4 | A valid HTTP-date or epoch already in the past — or exactly now — yields `0.0`, asserted against a fixed `now:` and distinct from the unparseable `nil` (`policy_test.rb`, "a valid HTTP-date or epoch already past is ZERO, not nil") |
| `RETRY-18` | MUST | ✅ | 4 | Every dispatched delay is `[delay, MAX_PACING_DELAY_SECONDS].min` — 365 days, `31_536_000` — asserted for a 400-day delta-seconds, milliseconds, reset and HTTP-date form and for the fifteen-digit run each grammar admits (10^15 seconds, thirty million years, clamped); exactly the ceiling and one below pass unclamped; a sixteen-digit run is out of range and `nil` (`RETRY-16`'s clause, `P6-61` — round 1 moved the boundary from Float overflow at ~309 digits to the grammar's fifteen), and the reset jitter is drawn only over a finite band (`policy_test.rb`) |
| `RETRY-19` | MUST | ✅ | 4 | `PacingParsers::DECIMAL_GRAMMAR`, `\A\d{1,15}(\.\d{1,15})?\z` (bounded runs since round 1, `P6-61`; `INTEGER_GRAMMAR` is `\A\d{1,15}\z`, and `MAX_VALUE_BYTES = 64` sits in front of every parser), screens the delta-seconds form BEFORE `String#to_f`; `0x10`, `1e3`, `5_0`, `5f`, `5d`, `30d`, `5s`, `Infinity`, `NaN`, `5,0`, `+5`, `.5`, `5.`, `0b1`, `1r`, `1i` all fall through to the HTTP-date attempt and then to `nil`, and `Integer("5_0", 10) == 50` is asserted beside them as the reason the screen is load-bearing. The three grammars are anchored, frozen and carry their own `timeout:` (`policy_test.rb`). Guard 26 |
| `RETRY-20` | MUST | ✅ | 4, 9, 10, 11 | A present hint REPLACES the schedule verbatim — `Retry-After: 2` with a 30 s schedule and jitter 0.5 sleeps exactly `2.0`, not 30.0 and not a value in `[1.5, 2.5]` — and on the recovery stack is still clamped by the remaining budget (`retry_step_test.rb`, `DelayTest`; `recovery_retry_test.rb`, `TotalTimeoutTest`). No jitter is applied on top: the reset form's is inside the parser (`RECOV-25`) |
| `RETRY-21` | MUST | ✅ | 4, 7, 9, 11 | `Policy::DEFAULT_PACING_HEADER_ORDER` is the fixed recovery precedence — `Retry-After` numeric then date, `retry-after-ms`, `x-ms-retry-after-ms`, `X-RateLimit-Reset` — and the first parseable value wins; `RecoveryRetry` walks exactly that constant, `RetryStep`/`AsyncRetryStep` walk `RetrySettings#header_order`, the caller's `pacing_header_order:` or the same default (`policy_test.rb`; `retry_step_test.rb`, "the stage stack walks the caller's header order"; `retry_settings_test.rb`) |
| `RETRY-22` | MUST | ✅ | 4, 9, 11 | A malformed header falls through to the next form and, with none usable, to backoff; the original failure stays the surfaced error — `Retry-After: garbage` then `retry-after-ms: 1000` waits 1.0; `Retry-After: junk` with nothing else waits the backoff (`policy_test.rb`; `recovery_retry_test.rb`, "the fixed precedence, and a malformed hint falls back") |
| `RETRY-23` | MUST | ✅ | 9, 10, 11 | Cancellation is never a retryable condition, structurally (`P6-60`, round 1's R0-5): `Policy.cancellation?(error)` walks the cause chain for a `CancelledError`, `Policy.retryable?` answers `false` for one before either branch, and the two stage drivers' decision answers `:stop` for one before the re-sendability gate and BEFORE a caller's `should_retry` is consulted — so a predicate answering `true` never sees a cancellation and cannot retry it, and a cancellation a transport WRAPPED in its own retryable error is terminal on all three drivers, one send, no trail (`retry_step_test.rb`, `CancellationGuardTest`; `async_retry_step_test.rb`, `CancellationTest`; `recovery_retry_test.rb`, `IntegrationTest`; `policy_test.rb`, `ClassificationTest`). During the wait: the sync drivers wait on 5a's `Clock#sleep(duration, cancellation:)`, which wakes on the token's push and re-asserts it (`CFG-17`); the async driver subscribes to the token, cancels the pending `Async.delay` future and fails its own future with the `CancelledError`, the trail attached. At the boundary: every driver calls `cancellation.check!` at the top of EVERY attempt, which is what stands between a cancellation and a second send when the wait is zero-length — `Clock::SYSTEM.sleep(0.0, …)` returns before the token check (verified) — and the one SYSTEM-clock test in the suites is exactly that case (`retry_step_test.rb`, `PredicateAndBudgetTest`, four tests; `async_retry_step_test.rb`, `CancellationTest`; `recovery_retry_test.rb`, `IntegrationTest`). Guards 29, 30, 34 and 35, with the async boundary's honest result in the table |
| `RETRY-24` | MUST | ✅ | 9, 10, 11 | `RetryFixtures::RetryableError < ::IOError` answering `#retryable?` — a read timeout's shape, in the same family a cancellation would be mistaken for — flows through classification and is retried on all three drivers; `UnretryableError < ::IOError` answering `false` is not (`retry_step_test.rb`, "a throwable answering the capability is retried"; the async and recovery twins) |
| `RETRY-25` | MUST | ✅ | 9, 10, 11 | The fatal family is never retried, classified, reported or trail-attached: `RetryStep#drive` and `RecoveryRetry#exchange` rescue `::StandardError` only, so a `NoMemoryError` propagates at the throw site with no `attempt_failed`, an empty trail and no second send; the two response-close fences rescue `::Exception` and re-raise unchanged after the close. **The async driver's path has no rescue arm** — a fatal arrives as a settlement — so `Pump#delivered?` delivers a non-`StandardError` unclassified, unretried and unattached before the decision runs (`P6-55`, found by guard 7's discriminating fixture: `RetryableFatal < ::NoMemoryError` answering the capability was RETRIED four times on the async path until the branch existed). Asserted on all three with both a bare fatal and a lying one (`retry_step_test.rb`, `TerminalPathTest`; `async_retry_step_test.rb`; `recovery_retry_test.rb`). Guards 7, 7a, 7b |
| `RETRY-26` | MUST | ✅ | 9, 10, 11 | Every sync wait is `settings.clock.sleep(delay, cancellation: token)` — asserted by identity on the token the fake clock recorded — and the async wait is `Async.delay`, which parks a fiber under a scheduler (`ParkingScheduler#block_count >= 2`, `kernel_sleep_count == 0`) and never a thread; no `Kernel#sleep`, `Timeout.timeout`, `Thread#raise` or `Thread#kill` anywhere in the layer (the cop and the RETRY-45 scan) (`retry_step_test.rb`, "every wait is the clock's cancellable sleep"; `async_retry_step_test.rb`, `TrampolineTest`) |
| `RETRY-27` | MUST | ✅ | 11 | `RecoveryRetry#delay_within_budget`: the delay against `Policy.budget_remaining(elapsed:, total_timeout:)` — the time REMAINING — aborting when `remaining <= 0.0` or `delay > remaining`; the attempt cap is `RecoveryRetry#decision`'s. On a fake clock advancing by exactly each sleep, `total_timeout 1.0` with a flat 0.4 s delay gives exactly three sends and sleeps `[0.4, 0.4]`; a send that takes the whole budget suppresses the next delay; a zero budget is unbounded (`recovery_retry_test.rb`, `TotalTimeoutTest`). Guards 14 and 15 |
| `RETRY-28` | MUST | ✅ | 9, 10 | No total-timeout on the stage stack, as a property of the source (R6, `P6-5`): a text scan asserts `retry_step.rb`, `async_retry_step.rb` and `retry_step_helpers.rb` never name `budget_remaining` or `total_timeout`, and that `recovery_retry.rb` does (`retry_step_test.rb`, `TracerAndGuardsTest`). Guard 3 |
| `RETRY-29` | MAY | ⏳ | — | Declined for v1, no named trigger: `docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level, the `RECOV-31`/`RETRY-38`/`RETRY-29`/`RETRY-43` entry. No server-driven override header is read by any driver |
| `RETRY-30` | MUST | ✅ | 10 | `AsyncRetryStep::Pump`, an ITERATIVE trampoline: a `loop` on whatever frame is driving, a re-arm flag flipped under the pump's `Thread::Mutex` by an inline settlement, and a fresh loop started only from a callback that fires later on another frame. **Measured, not assumed**: a transport recording `caller.size` at every attempt sees ONE depth across 2,001 sends with 2,000 zero-length retries, on 3.2.11, 3.3.12, 3.4.10 and 4.0.6; the plan's recursive shape raised `SystemStackError` at the same test (guard 9's message) (`async_retry_step_test.rb`, `TrampolineTest`) |
| `RETRY-31` | MUST | ✅ | 10 | A zero-length delay completes inline — `Async.delay(0.0)` settles before its scheduler check, plan fact 2 — and its callback re-arms the running loop without a frame; the future is settled before `#call` returns and `Fiber.scheduler` is nil throughout. A positive delay parks the fiber under a scheduler (`async_retry_step_test.rb`, "a zero-length delay completes inline", "a positive delay under a scheduler parks the fiber"). Guard 10b |
| `RETRY-32` | MUST | ✅ | 10 | `Pump#launch` returns when the completer is settled; `Pump#settled` closes a response arriving from an abandoned attempt; `@completer.on_cancel` cancels the pending delay; the delay callback launches nothing once settled. Asserted with `ScriptedAsyncTransport(settle_later: true)`: cancel the returned future while attempt 1 is in flight, settle it, and the in-flight 503 is closed with no second send; and under a scheduler a cancel during a positive wait stops the loop at one send (`async_retry_step_test.rb`, `TerminalPathsTest`) |
| `RETRY-33` | MUST | ✅ | 10 | Every callback body runs inside `Pump#guarded`, which closes any open response, fails the completer on a `StandardError` and — for the fatal family — fails it and re-raises: a throwing `should_retry`, a throwing tracer callback, a throwing factory, a throwing delay computation (a `NotImplementedError`) and a scheduler-less positive delay's `SeamError` each settle the future exceptionally rather than leaving it hanging, the response closed first (`async_retry_step_test.rb`, `TerminalPathsTest`, five tests) |
| `RETRY-34` | MUST | ✅ | 9, 10, 11 | On terminal failure the WHOLE prior trail is attached to the surfaced instance through `Dexpace.attach_suppressed` — whose skip-self guard is 4b's, so one error instance re-used for every attempt surfaces with an empty trail on all three drivers — and on success or on a returned error-status response the trail is discarded (stated in the source, since a `Response` carries no trail; the `ProtocolError` the tracer sees on an exhausted status carries it instead). The carried raise is `raise error, cause: nil` (`pipeline/7ce4431d`) on both raising drivers; the discriminating fixture is `RecoveryRetry`'s CONSTRUCTED `ProtocolError`, asserted nil-caused from inside a caller's `rescue`, and the sync step's test states why its raised fixture cannot discriminate (`retry_step_test.rb`, `TerminalPathTest`; `async_retry_step_test.rb`; `recovery_retry_test.rb`, `BudgetTest`). Guards 8 and 8a |
| `RETRY-35` | MUST | ✅ | 9, 10, 11 | Three orderings, asserted: the delay is resolved from the still-open response (`Retry-After: 3` read, then closed, then slept 3.0); the response is closed BEFORE the wait (a clock whose `#sleep` records `body.closed?` sees `[true]`); and a throwing decision, delay computation OR tracer `attempt_failed` closes the response before propagating (`fenced` on the sync step, `guarded` on the async one — the sync emission moved inside the fence in round 1, R0-4, where it had leaked the open response while the async driver closed it). On the recovery stack the release is `Recovery.buffer_error_body`, which drains the connection and hands every later line the buffered copy (`retry_step_test.rb`, `DelayTest` and `PredicateAndBudgetTest`; `async_retry_step_test.rb`; `recovery_retry_test.rb`, `IntegrationTest`). Guards 5, 6 and 36 |
| `RETRY-36` | MUST | ✅ | 9, 10, 11 | A 503, 503, 200 sequence terminates on the 200 after three sends on all three drivers, the response handed back unclosed; on the recovery stack each re-sent error status is re-mapped through `Recovery.buffer_error_body` then `ProtocolError.for` (`retry_step_test.rb`; `async_retry_step_test.rb`; `recovery_retry_test.rb`, "503, 503, 200 ends on the 200"). Guard 16 |
| `RETRY-37` | MUST | ✅ | 3, 9, 10, 11 | Authoritative-contains: `Policy.retry_eligible?(status, set:)` is `set.include?(status)` and takes no baked-flag parameter, so the AND `RETRY-37` forbids is a method that does not exist. A set of `[418]` retries a 418 (outside the baked set) and a set of `[429]` refuses a 503 (inside it), on every driver; the dedicated test design §6.1 asks for is `policy_test.rb`'s "retry_eligible? consults the set alone; a NARROWING set narrows". Guard 2 |
| `RETRY-38` | SHOULD | ⏳ | — | Declined for v1 with `RECOV-31`, one attempt-ordinal-header feature under two IDs: `docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level. No header is stamped and no per-attempt request copy is made |
| `RETRY-39` | MUST | ✅ | 9, 10 | `RetryStepHelpers#resolve_delay`: caller delay-override, then the pacing headers on the RESPONSE path only, then exponential backoff — the fixed-delay tier between the last two being `RETRY-43`'s, declined, so three live sources. The override is called with `(attempt, response, error)`, sees the response and no error on one path and the error and no response on the other, and a present override beats a present hint (`retry_step_test.rb`, `DelayTest` and `DelayOverrideTest`; `async_retry_step_test.rb`, "the override sees the response on one path, the error on another") |
| `RETRY-40` | SHOULD | ✅ | 9, 10 | A throwing `delay_override:` is non-fatal — one WARNING `http.instrumentation.hook` diagnostic through 5b's facade, contained (OBS-20), and the precedence falls through; an override answering a negative or non-numeric value is logged the same way. A throwing `should_retry:` aborts as `Dexpace::RetryPredicateError` with the raise as `#cause`, the open response closed first; the fatal family propagates unchanged from both (`retry_step_test.rb`, `DelayOverrideTest` and `PredicateAndBudgetTest`; `async_retry_step_test.rb`) |
| `RETRY-41` | MUST | ✅ | 3, 9, 10, 11 | `Policy.effective_max_retries(override:, configured:, logger:)`: a present per-call `RequestOptions#max_retries` wins (validated non-negative — a negative or non-Integer override raises), else the configured value, a negative configured value clamped to `DEFAULT_MAX_RETRIES` and the clamp logged as one WARNING `http.instrumentation.config` diagnostic through 5b's facade, contained so a raising sink cannot fail the resolution; zero means no retries. Driven through a real pipeline with `max_retries: 1` and `0` overrides on both stage drivers; the recovery stack resolves through the same function. The clamp is REACHABLE where a negative configured value can enter (`P6-59`, round 1's R0-6): `RetrySettings.build` reads `MAX_RETRY_ATTEMPTS` once and resolves what it reads through the same `Policy.effective_max_retries`, so a negative configured value is clamped to the default and logged as one contained config diagnostic through `.build`'s `logger:` — at build, once, so every driver on that settings sees the default and no second clamp or log line; an explicit negative `max_retries:` is a caller's construction input and `RECOV-34` refuses it instead, with the key negative too (`policy_test.rb`, `ResolverAndBudgetTest`; `retry_settings_test.rb`, `ConfiguredTest`; `retry_step_test.rb`; `async_retry_step_test.rb`; `recovery_retry_test.rb`). Guards 20 and 37 |
| `RETRY-42` | MUST | ✅ | 3, 7, 9, 10, 11 | `Policy` is a frozen-constant `extend self` module with no instance variables; `RetrySettings` a frozen `Data`; the three drivers are frozen at `.build` and every per-call quantity is a local — `RetryStep::Run` and `RecoveryRetry::Run` (private `Data` values) and `AsyncRetryStep::Pump` (a private per-call object) — so eight threads through one shared driver keep their attempt counts apart on every driver (`policy_test.rb`; `retry_settings_test.rb`; the three drivers' "eight threads" tests). **The caveat, stated**: `random:` defaults to the `::Random` CLASS, whose `.rand` is the process generator CRuby makes safe to share, and a caller who passes a `::Random.new` shares a mutable generator across calls (`P6-52`) |
| `RETRY-43` | MAY | ⏳ | — | Declined for v1, no named trigger: `docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level. `resolve_delay`'s precedence has no fixed-delay tier; a caller wanting one passes a constant `delay_override:` |
| `RETRY-44` | MUST | ✅ | 9, 10, 11 | Every attempt re-executes the downstream chain through a FRESH `cursor.fork` and re-sends the SAME frozen request object — `assert_same` over every recorded call on all three drivers — and the step writes no cursor state, so a `StateProbe` downstream reads the empty slot under `Stages::RETRY` on every attempt (`retry_step_test.rb`, "every attempt re-sends the SAME request object", "a RETRY fork writes no cursor state"; the async and recovery twins) |
| `RETRY-45` | MUST NOT | ✅ | 10 | The engine installs, reads and shuts down no scheduler: `Async.delay` reads the ambient `Fiber.scheduler` and 6a's code never names it; a text scan over every resilience file refutes `set_scheduler`, `scheduler.close`/`scheduler&.close` and `shutdown`; and under a `ParkingScheduler` whose `#close` is instrumented, the driver never closes it — the interpreter does, at thread end (`async_retry_step_test.rb`, `TrampolineTest`; `retry_step_test.rb`, `TracerAndGuardsTest`). Guard 23 |

### `RECOV` — the fifteen phase 4 postponed here, own rows

| ID | Level | Status | Task(s) | Twin(s), an annotation | What was built, and where it is proven |
|---|---|---|---|---|---|
| `RECOV-17` | MUST | ✅ | 3, 11 | `RETRY-37`, `RETRY-1`, `XCUT-6`/`XCUT-7` | `RecoveryRetry#decision` classifies through `Policy.retryable?`: a `ProtocolError` by the CONFIGURED set alone (widened to 418, narrowed away from 503), anything else by the capability; a THROWN retryable failure is retried and one with no capability surfaced on the first attempt — the engine sits below the orchestrator's rescue region and rescues `::StandardError` itself (`P6-8`); a Success passes through untouched (`recovery_retry_test.rb`, `ClassificationTest`) |
| `RECOV-18` | MUST | ✅ | 5, 11 | `RETRY-5`, `RETRY-6`, `RETRY-7`, `RETRY-8` | `Resend.eligible?` consulted first in `RecoveryRetry#decision`: a bare POST is sent exactly once and its 503 returned, a replayable POST body re-sent, a consumed PUT body not (`recovery_retry_test.rb`, `ClassificationTest`; `resend_test.rb`) |
| `RECOV-19` | MUST | ✅ | 11 | `RETRY-36` | `RecoveryRetry#exchange` buffers every error-status response (`Recovery.buffer_error_body`) and pairs it with `ProtocolError.for(buffered)`, so each re-sent attempt is re-classified against the configured set and a 503, 503, 200 run reaches the 200; a non-retryable status passes through as Success — RETURNED, its body a `BufferBody` readable through `#body_string` — for the outer chain to map (`recovery_retry_test.rb`, "503, 503, 200 ends on the 200", "a NON-retryable error status passes through as Success"). Guard 16 |
| `RECOV-20` | MUST | ✅ | 3, 11 | `RETRY-27`, `RETRY-14` (**contrast, not twin**: `RETRY-28` forbids the same budget on the other stack) | Both bounds: the cap counts the initial send as attempt 1 (`max_retries + 1`, exhausting after three sends by default) and the total-timeout is `Policy.budget_remaining`'s time REMAINING, a delay past it suppressed and the last failure surfaced; zero is unbounded (`Float::INFINITY`), asserted with a 100 s schedule over five sends. Exhausted or disallowed, the terminal throwable is surfaced — raised with the trail — while a never-retryable response is returned (`P6-9`) (`recovery_retry_test.rb`, `BudgetTest` and `TotalTimeoutTest`; `policy_test.rb`). Guards 14 and 15 |
| `RECOV-21` | MUST | ✅ | 3, 11 | `RETRY-9`, `RETRY-10`, `RETRY-11` | The one calculator, its attempt index 1-based and refused below 1, its jitter symmetric, its result clamped so `elapsed + delay` never exceeds the budget — the abort in `delay_within_budget` IS the clamp: a delay that would overshoot is suppressed, never shortened and slept (`policy_test.rb`; `recovery_retry_test.rb`, "the schedule is Policy's own", `TotalTimeoutTest`) |
| `RECOV-22` | MUST | ✅ | 4, 11 | `RETRY-20`, `RETRY-21` | A parsed hint REPLACES the exponential value for that decision and is STILL clamped by the remaining budget — `Retry-After: 2` honoured, the next `Retry-After: 9` against 3 s remaining suppressed — with no second jitter (`recovery_retry_test.rb`, "a pacing hint replaces the schedule and is still budget-clamped") |
| `RECOV-23` | MUST | ✅ | 4 | `RETRY-16`, `RETRY-17` | Total: the negative suite, and a past absolute time as `0.0` distinct from `nil` (`policy_test.rb`, `PacingTotalityTest`, `PacingFormsTest`) |
| `RECOV-24` | MUST | ✅ | 4, 11 | `RETRY-15`, `RETRY-19`, `RETRY-21` | The five forms, the fixed precedence walked by `RecoveryRetry#hinted_delay` over `Policy::DEFAULT_PACING_HEADER_ORDER`, and the decimal screen before any float parse (`policy_test.rb`; `recovery_retry_test.rb`, "the fixed precedence, and a malformed hint falls back") |
| `RECOV-25` | SHOULD | ✅ | 4 | a **clause inside** `RETRY-15` | `PacingParsers.parse_epoch_reset` draws `random.rand(delta..(delta * 1.2))` inside the parser — 500 seeded draws in `[10.0, 12.0]` for a 10 s delta, spanning below 10.5 and above 11.5 — over a finite band only (`policy_test.rb`, "X-RateLimit-Reset as epoch seconds, jittered up to [100%, 120%]") |
| `RECOV-26` | MUST | ✅ | 3, 4, 7 | `RETRY-11`, `RETRY-18` | Overflow-safe throughout: the 365-day clamp on every pacing delta before anything downstream, `Policy::MAX_DURATION_NANOSECONDS` (the signed 64-bit count, ~292 years) as `RetrySettings`' representability ceiling on every duration, a saturating power in the calculator, the zero-times-Infinity guard (`P6-53`), and a reset jitter never drawn over an infinite bound (`policy_test.rb`; `retry_settings_test.rb`, "durations are non-negative, finite and within the ~292-year ceiling") |
| `RECOV-27` | MUST | ✅ | 9, 10, 11 | `RETRY-23`, `RETRY-26`, `XCUT-3` | The wait is 5a's cancellable queue wait, holding no worker: cancelled during it, the sync drivers surface the `CancelledError` the clock re-asserted (a), the timer is the queue's own timeout and dies with it (b), and the loop aborts with no further send (c); the async driver's subscription cancels the pending delay future (b) and fails its own with the `CancelledError` (c). A token cancelled from INSIDE the attempt it is serving is what makes the test deterministic (`recovery_retry_test.rb`, `IntegrationTest`; `retry_step_test.rb`; `async_retry_step_test.rb`, `CancellationTest`) |
| `RECOV-28` | MUST | ✅ | 11 | `RETRY-42` | `RecoveryRetry` is frozen and stateless: the attempt count, the start instant, the request, the options, the token and the trail are one private `Run` value per `#call`; a first-attempt success touches no clock; eight concurrent calls through one engine over one script each land on their own 200 (`recovery_retry_test.rb`) |
| `RECOV-29` | MUST | ✅ | 4, 11 | `RETRY-22` | A malformed hint never masks the failure: `Policy#parse_form` fences every parser and `Policy.pacing_delay` walks on; `hinted_delay` answers `nil` and the engine falls back to backoff with the original `ProtocolError` still the surfaced error (`recovery_retry_test.rb`; `policy_test.rb`) |
| `RECOV-30` | SHOULD | ✅ | 3, 7, 12 | `RETRY-13`, `RETRY-14`, `RETRY-28` | One calculator, one parser, one settings type, one default schedule — `RetrySettings` serves all three drivers, `total_timeout` carried for both stacks and read by one (R6) — and the convergence test asserts the send count and the schedule across stacks (`budget_equivalence_test.rb`; `retry_settings_test.rb`) |
| `RECOV-34` | MUST | ✅ | 7 | design §6.1's construction-time validation, §10.18's ~292-year bound | `RetrySettings#initialize` validates every member and names it (`SEAM-29`): durations non-negative, finite and within `MAX_DURATION_NANOSECONDS` (one second past the ceiling refused, the ceiling itself accepted); `multiplier >= 1.0` and finite; `jitter` in `[0.0, 1.0]`; `max_retries` a non-negative Integer, zero disabling retries (an EXPLICIT negative argument is refused even while the configured key is negative — the configured value's clamp is `RETRY-41`'s, at the same `.build`, `P6-59`); and `retryable_statuses` and `pacing_header_order` copied and deep-frozen through `Model.own`, so the caller's collection and its Strings stay theirs. `#with` re-validates through `.build` on every Ruby, the floor included, because `Data#with` skips `initialize` there (`retry_settings_test.rb`, `ValidationTest`, `ConfiguredTest`) |

### Rows outside the budget

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `RECOV-31` | MAY | ⏳ | — | The attempt-ordinal header, declined for v1 with its twin `RETRY-38`: `docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level. A row, not a budget line (the charter's arithmetic) |
| `CFG-35` | SHOULD | ✅ | 3 | The inherited row: 5a shipped the status half as `Dexpace::Retryability.retryable_status?` and postponed the throwable half here; `Policy.throwable_retryable?` is that half, the capability query over `Dexpace.each_cause`, cycle-safe through 4b's identity-tracked walk. 5a's own `CFG-35` row stays ⏳ pointing here; this row closes it, and the `CFG-35`/`XCUT-5` shared-classifier cross-reference closes with it — 5a's Task 4 the status end, this Task 3 the throwable end (`policy_test.rb`, `ClassificationTest`; `error/protocol_error_test.rb`, `RetryableTest`). Guard 22 |

### Cross-reference rows

The non-`RETRY`/`RECOV` IDs this phase owns a share of, from the design's interface-surface table.

| ID | Status | What 6a built for it, and where it is proven |
|---|---|---|
| `XCUT-5` | ✅ | The baked flag, `ProtocolError#retryable_by_status?`, from 5a's single classifier (phase 4b's deferral, Task 6). Phase 9 audits three objects; this is the first |
| `XCUT-6` | ✅ | The open capability query, `Policy.throwable_retryable?` — the second object. A third-party transport declares an error retryable by defining `#retryable?` on its own class and editing nothing here |
| `XCUT-7` | ✅ | The configurable set, `RetrySettings#retryable_statuses` with `Policy::DEFAULT_RETRYABLE_STATUSES` as its default and `Policy.retry_eligible?` as its consult — the third object, never AND-ed with the first |
| `XCUT-3` | ✅ | By construction: every wait is 5a's cancellable queue wait or `Async.delay`, and a cancellation surfaces as the cancellation (`CancelledError#reason` asserted), never a spurious timeout |
| `XCUT-9` | ✅ | By construction: the one cause walk is `Dexpace.each_cause`, and the cyclic fixtures terminate through it |
| `XCUT-11` | ✅ | `Policy` (frozen module, no ivars) and `RetrySettings` (frozen `Data`) as the audited shared instances; the three drivers frozen at `.build` |
| `OBS-29` | ✅ per-attempt half only | The per-attempt group — `attempt_started` before every drive, `attempt_failed(context, failure, delay)` before every wait, `retries_exhausted(context, failure)` only when a RETRYABLE failure met a spent budget — emitted by all three drivers through `http_tracer_factory:`, called ONCE per operation with the cursor (stage) or the request (recovery), the same object every callback receives (R3, `P6-7`). **The operation-lifecycle triple and the transport milestones are emitted by nothing**, per `docs/first-release.md`'s behavioural-asymmetries entry, and a never-retryable failure emits no `retries_exhausted` (5c's `ordering_test.rb`, third case). 5c's `OBS-29` row stays its own; this row claims the half 6a reaches (`retry_step_test.rb`, `TracerAndGuardsTest`; the async and recovery twins) |
| `OBS-30` | ✅ | A throwing tracer callback propagates and fails the request on the sync drivers, and completes the async future exceptionally; core wraps no tracer callback (`retry_step_test.rb`, "a throwing tracer propagates"; `async_retry_step_test.rb`) |
| `OBS-20` | ✅ | The two log emissions 6a adds — `RETRY-41`'s clamp and `RETRY-40`'s fallback — run inside `Instrumentation.diagnostic`'s containment; a raising sink cannot fail the resolution, nor the build that clamps a negative configured value (`policy_test.rb`, "a raising sink cannot fail the resolution"; `retry_settings_test.rb`, "a raising sink cannot fail the build") |
| `PIPE-15`, `PIPE-16`, `PIPE-40` | ✅ | Both stage drivers fork for EVERY drive, the first included, and never call their own cursor — a recording cursor over the real driver-minted one counts three forks and zero calls across three attempts (guard 9 says what the mixed shape does); each superseded response is closed before the next drive and the one handed back never is |
| `PIPE-39` | **not claimed** | `Pipeline.standard` / `AsyncPipeline.standard` are phase 4c's deferral and phase 6b's Task 13a; 6a ships the two step families the constructors install and neither constructor, and nothing under `docs/` describes them as existing |
| `CTX-14`, `PIPE-11`, `PIPE-17` | ✅ | The cursor widening (Task 8): `Cursor#bundle`, seeded per call by `bundle:` on `Pipeline#call` and `AsyncPipeline#call`, `Bundle::NONE` by default, validated a `Bundle`, carried across `#fork` exactly as `#options` is and untouched by `state:`; 5b's `Step#open_span` takes the bundle's tracer factory when it is not `NONE` and `Tracing.correlate` is handed the same bundle, so a valid seeded bundle pushes its ids onto the diagnostic context. **The meter has no bundle source**: `CTX-14`'s bundle carries no meter and the two instruments are created once at `.build` (`OBS-31`), so its precedence is the keyword then the constant (`pipeline/cursor_test.rb`, `BundleTest`; `pipeline_test.rb` and `async_pipeline_test.rb`, `BundleSeedingTest`; `instrumentation/step_test.rb` and `async_step_test.rb`, `BundlePrecedenceTest`). Guards 24 and 25 |
| `CFG-15`, `CFG-17`, `P2-5` | ✅ | The wait phase 2 postponed to 5a and 5a built is consumed here: `Clock#sleep(duration, cancellation:)` on the sync path, `Async.delay` on the async path, and `Clock#now`/`#monotonic` for the absolute forms and the budget (`CFG-16`: never `Time.now`) |
| `CFG-14`, `CFG-5` | ✅ | `Keys::MAX_RETRY_ATTEMPTS` gains its first reader; its value is parsed by 5a's base-10 integer parser, so `010` reads as 10 and an unparseable value falls to the default (`retry_settings_test.rb`, `ConfiguredTest`) |
| `HTTP-9`, `BODY-1` | ✅ | Consumed, not re-listed: `Method::IDEMPOTENT` through `#idempotent?` and `Body#replayable?` (`resend_test.rb`) |
| `SEAM-11` | ✅ | `RecoveryRetry` is a `Dexpace::Transport` by the duck type (`Transport.conforms?`, `Registry.callable?(…, arity: 3)`), and a `Pipeline` with the `bundle:` keyword still is (`recovery_retry_test.rb`; `pipeline_test.rb`) |
| `RECOV-16` | ✅ | `Recovery.buffer_error_body` is the engine's release-before-wait and every later line sees the buffered copy; the caller's `ErrorMappingStep` factory runs exactly once, on the terminal response, never on a retried one (`recovery_retry_test.rb`, `OrchestratorTest`) |
| `NFR-4` | ✅ | Every addition is a widening: no existing signature moved. The runtime manifest grew by exactly the 48 rows the object model names, read row by row (Task 13); the RBS baseline diff is vacuous until the first tag |
| `NFR-11` | ✅ | `interface _HTTPTracer` lands in `sig/dexpace/instrumentation/http_tracer.rbs` beside the module (R3), `context` untyped by design; `random` is untyped everywhere (`::Random` is outside the allowlist) and `retryable_statuses:` is typed `Enumerable[Integer]` after `gates:rbs_surface` refused `_Each` |
| `NFR-13` | ✅ | Every new `.rb` and `.rbs` opens with the SPDX header |

## What was built

Nine new `lib/` files under `gems/dexpace-core/lib/dexpace/` — the flat `error/retry_predicate_error.rb`
(`Dexpace::RetryPredicateError`, the tree's one-error-per-file convention, `P6-11` as built) and eight
under `resilience/`: `pacing_parsers.rb` (private), `policy.rb` (`Dexpace::Resilience::Policy`, and the
`Resilience` namespace itself), `resend.rb`, `retry_settings.rb`, `retry_step_helpers.rb` (private),
`retry_step.rb` (with its private `Run`), `async_retry_step.rb` (with its private `Pump`) and
`recovery_retry.rb` (with its private `Run`). Every file has a `sig/` mirror — the two `private_constant`s
with `hooks.rbs`'s comment, because the strict `core` Steep target types their call sites — and every
public file a `test/` mirror (`error/retry_predicate_error.rb`'s, `retry_predicate_error_test.rb`, arrived
in review round 1 — R0-2 found the public file without one); `pacing_parsers.rb` and
`retry_step_helpers.rb` have none, their contracts asserted through `Policy` and the two stage drivers,
which makes **thirteen** `private_constant`s without a `test/` mirror in `dexpace-core`. One test file has no `lib/` mirror, `budget_equivalence_test.rb`, and
says why. Three top-level test-support doubles: `ScriptedTransport`, `ScriptedAsyncTransport` and the
`RetryFixtures` module (with its `RetryableError`, `UnretryableError`, `RetryableFatal`, `RecordingCursor`
and `RecordingWrapper`).

Eleven earlier-phase `lib/` files widened in place, each a designed widening with its `sig/` mirror:
`http_date.rb` (the day group, R1), `error/protocol_error.rb` (the baked flag), `pipeline/cursor.rb`
(`#bundle`, `bundle:` on `.build`, copied by `#fork`), `pipeline/sync_driver.rb` and
`pipeline/async_driver.rb` (`bundle:` on `#advance`), `pipeline.rb` and `async_pipeline.rb` (`bundle:` on
`#call`), `instrumentation/step.rb` and `instrumentation/async_step.rb` (`#open_span(request, bundle)`
and the correlation over the cursor's bundle), `instrumentation/http_tracer.rb` (its comment; the
interface in its `sig/`), and comments in `instrumentation/tracing.rb` and `instrumentation/bundle.rb`.
`lib/dexpace.rb` gains a nine-line `# Phase 6a:` block after 5b's, in dependency order. The surface
manifest was regenerated twice, deliberately — from 956 to 1004 rows at implementation, and to 1005 in
review round 1 for `Policy#cancellation?` (`P6-60`) — `Cursor#bundle`, `ProtocolError#retryable_by_status?`,
`RetryPredicateError`, and the 46 rows of the five public `Resilience` constants (`Policy`'s eight
functions and nine constants, `RetrySettings`' ten readers plus `.build`, `#backoff_arguments` and
`#header_order`, the three drivers' `.build`/`#call`/`#stage`, `Resend#eligible?`) — every row read
against the object model and `P6-1`/`P6-2`, and nothing private in it. `RetrySettings.build`'s round-1
`logger:` keyword (`P6-59`) is a signature widening the RBS carries and the manifest cannot see.

**R1 — the HTTPDate widening's exact tolerance list, after Task 2.** Accepted: a one- or two-digit day
(`Sun, 6 Nov 1994 08:49:37 GMT` and `Sun, 06 Nov …`, both 6 November); a wrong weekday (informational,
never validated, CFG-30's clause, already 5a's); month and zone case (already 5a's); the four zone tokens
(already 5a's). Still refused: an absent weekday (`06 Nov 1994 …` — CFG-31's `Xxx, ` prefix is required,
and this row was ADDED to 5a's rejection loop in place of the single-digit one), a day of `0` or three
digits, a doubled space either side of the day, RFC 850, asctime, a leading space, a trailing token, a
two-digit year, a non-zero offset, and every impossible calendar date (`Time.utc`'s round-trip check).

**R2 — the async driver's route.** Route 3, as the design decided, with one measured correction: a
positive `Async.delay` with no `Fiber.scheduler` raises `Dexpace::SeamError` SYNCHRONOUSLY (not through
the future), and `Pump#guarded` catches it and fails the returned future with it, the prior trail
attached — "not a hang, not a blocking fallback" is the assertion. A zero-length delay completes inline
and re-arms the running loop. **R3 — the HTTP-tracer slot.** A FACTORY, `http_tracer_factory:`, called
once per operation with the cursor on the stage drivers and the request on the recovery engine, defaulting
to a lambda answering `Instrumentation::NULL`; `interface _HTTPTracer` is declared, inside 5c's existing
`sig/dexpace/instrumentation/http_tracer.rbs` beside the module rather than in a new file, with 5c's
`Numeric next_delay` kept. **Task 8's exact surface**: `Cursor#bundle` (reader), `Cursor.build(…,
bundle: Bundle::NONE)`, `Cursor#initialize`'s `bundle:`, `Pipeline#call(request, options = EMPTY,
cancellation = none, bundle: Bundle::NONE)`, the same on `AsyncPipeline#call`, `SyncDriver#advance` and
`AsyncDriver#advance` gaining `bundle:` (private), `Step#open_span(request, bundle)` (private), and 5b's
`Step#call` / `AsyncStep#head` correlating over `cursor.bundle`. The three files a runtime gate reads and
the code branch therefore carries: the manifest, `dexpace_test.rb`'s layer table (`RESILIENCE_LAYER`), and
the earlier-phase pins the code invalidated — 4c's `cursor_test.rb` method-set pin (`bundle` added), 5a's
`http_date_test.rb` rejection element (the single-digit day replaced by the bare-date row), and 5b's three
cursor stand-ins in `step_test.rb` and `async_step_test.rb` (each gains `#bundle`).

## Matrix facts, re-run on every interpreter

The plan's Task 1 asked for the seven facts on 3.2.11, 3.4.10 and 4.0.6 (it believed only 3.4.10 was
installed; all four rows were). Re-run on 2026-09-18 as one script per interpreter before any code was
written, then again through the suites on every row:

| Fact | 3.2.11 | 3.3.12 | 3.4.10 | 4.0.6 |
|---|---|---|---|---|
| `HTTPDate::GRAMMAR` rejects a single-digit day before Task 2 / accepts after | yes / yes | same | same | same |
| an absent weekday rejected before and after | yes | same | same | same |
| `Async.delay(0)` settles with no scheduler; a positive delay raises `SeamError` synchronously | yes / yes | same | same | same |
| `Retryability.retryable_status?` on 408, 429, 500, 501, 505, 599, 400 | T T T F F T F | same | same | same |
| `Method::IDEMPOTENT`; `Body#replayable?` default | GET HEAD OPTIONS PUT DELETE; false | same | same | same |
| `Registry.callable?(three positionals, arity: 3)` | true | same | same | same |
| `Recovery.buffer_error_body` twice: same Response / same body | false / false; the original body closed | same | same | same |
| `Cursor.build` keywords before Task 8 | drive request options cancellation | same | same | same |
| `Step` private methods before Task 8 (no `bundle_for`, no `@bundle`) | body? elapsed_ms finish log_failure log_request log_response logged? open_span prepare wrap_request wrap_response | same | same | same |
| `Data#with` runs a validating `initialize` | **no** | yes | yes | yes |
| `Integer("5_0", 10)` | 50 | 50 | 50 | 50 |
| `[0.2 * 2.0**999, 8.0].min`; `2.0**9999` | 8.0; Infinity | same | same | same |
| `0.0 * Float::INFINITY`; `[NaN, 8.0].min` | NaN; **raises** `ArgumentError` | same | same | same |
| `Set` needs no require | yes | yes | yes | yes |
| `Clock::SYSTEM.sleep(0.0, cancellation: cancelled)` / `(0.001, …)` | returns / raises | same | same | same |
| `Future#on_settle` on a settled future runs inline; `Completer#fail` twice | true; false | same | same | same |
| a cause once set survives a bare re-raise and a `cause: nil` re-raise | yes | same | same | same |
| the plan's recursive pump: `SystemStackError` at ~1,500 zero-length attempts | yes | yes | yes | yes |
| the built pump: one stack depth across 2,001 attempts | yes | yes | yes | yes |
| `Random#rand(Infinity..Infinity)` | `Errno::EDOM` | same | same | same |

Every interpreter-sensitive fact is uniform across the range except `Data#with` on the floor, which is
why `RetrySettings` includes `Model` and the suite asserts `#with` re-validates there (the `RECOV-34` row).

## Guards run red

Every guard the brief asks for was seen red on 4.0.6 and on 3.2.11 (the numbered set re-run whole on the
floor after the 4.0.6 pass), each a single mutation of `lib/` applied by script, the owning suite re-run,
the bytes restored, the tree confirmed clean. Four stayed green on the first 4.0.6 pass and each was a gap
in the SUITE or the SOURCE, closed before the second pass: guard 7 (a fatal-family error retried) needed
the discriminating fixture `RetryableFatal < ::NoMemoryError` answering the capability — and with it found
the async driver classifying a settled fatal (`P6-55`); guard 17 (the degenerate jitter range) was green
because RuboCop's `Minitest/AssertInDelta` autocorrection had rewritten every exact float assertion into a
0.001-delta one, and the exact cases now carry an explicit `0.0`; guard 23 (the scheduler scan) missed the
`&.` spelling, now in the pattern; and guard 30 (the async attempt-boundary check) is recorded as it is.
Guards 32–37 are review round 1's (2026-09-18): one is round 0's surviving mutation (m02, R0-7) and five
are the guards behind the round's five should-fix repairs, each seen red on 4.0.6 and 3.2.11 the same way.

| # | Guard | Mutation | Red message, 4.0.6 and 3.2.11 |
|---|---|---|---|
| 1 | `RETRY-13` — a delay literal outside Policy | `0.2 \|\|` prefixed to `RecoveryRetry#delay_within_budget` | "recovery_retry re-types a Policy default" |
| 2 | `RETRY-37` — the configured set AND-ed with the baked flag | `set.include?(status) && Retryability.retryable_status?(status)` | 418 refused: "a NARROWING set narrows" fails twice |
| 3 | `RETRY-28` — `budget_remaining` named from the stage driver | a call inserted into `RetryStep#wait` | the text scan: `retry_step` matches `/budget_remaining/` |
| 4 | `RETRY-14` — the stacks exhausting after a different number of sends | `max_attempts` `+ 2` | all four convergence tests: expected 3, got 4 |
| 5 | `RETRY-35` — the wait before the close | the two lines swapped in `RetryStep#wait` | `closed_at_sleep` `[false]` |
| 6 | `RETRY-35` — the close skipped when the delay computation raises | `fenced` removed from the delay line | "RETRY-35's third ordering": body not closed |
| 7 | `RETRY-25` — the fatal family classified and retried (sync) | `rescue ::Exception` in `RetryStep#drive` | "RetryableFatal expected but nothing was raised" — retried to the 200 |
| 7a | `RETRY-25` — a settled fatal classified and retried (async) | `delivered?` testing `::Exception` | expected 1 send, got 4 |
| 7b | `RETRY-25` — the fatal family classified and retried (recovery) | `rescue ::Exception` in `RecoveryRetry#exchange` | nothing raised |
| 8 | `RETRY-34` — a bare `raise error` (no `cause: nil`) | `RecoveryRetry#surface` | "Expected #<IOError: the caller's own in-flight exception> to be nil" |
| 8a | `RETRY-34` — the terminal error raised without the trail | `attach_trail` removed from `RetryStep#settle` | the two trail assertions: `-[…attempt 1, …attempt 2]` |
| 9 | fork-for-every-drive — `#call` for attempt 1, `#fork` afterwards | `attempt == 1 ? run.cursor.call : run.cursor.fork.call` | `Dexpace::PipelineError: cursor is spent and cannot be forked; #call and #fork are disjoint (PIPE-15)` |
| 10 | R2 — a positive delay under no scheduler blocking the thread | `clock.sleep(delay)` before a zero delay | the SeamError test and the parked-fiber test fail |
| 10b | R2 — a zero-length delay raising `SeamError` | a scheduler check before `Async.delay` | `Dexpace::SeamError: no scheduler` in both RETRY-31 tests |
| 11 | `RETRY-15` — a single-digit day rejected after Task 2 | the day group back to `(\d{2})` | the RETRY-15 test errors with `InvalidArgumentError` |
| 12 | `RETRY-16` — the parser raising on garbage | `Policy#parse_form`'s rescue removed | `RuntimeError: generator down`; a `Float … out of range` warning fatal under `-w` |
| 13 | `RETRY-16` — a parser answering zero for garbage | `parse_retry_after` rescuing to `0.0` | "expected \"not a date\" to be no hint" — `0.0` is not nil |
| 14 | `RECOV-20` — a total-timeout of zero treated as zero | the `INFINITY` branch removed | "a zero total_timeout is unbounded": 1 send, not 5 |
| 15 | `RECOV-20` — the budget not clamping the next delay | `delay > remaining` dropped | "exact, not merely under 11": 4 sends, not 3 |
| 16 | `RECOV-19` — a re-sent response not re-classified | `exchange` never classifying | "503, 503, 200": got 503; the buffered-body assertion |
| 17 | jitter — the degenerate sub-nanosecond range drawn anyway | the `NANOSECOND` return removed | `\|1.0e-12 − 9.585e-13\| … to be <= 0.0` |
| 18 | overflow — the cap not applied | `jittered(raw, …)` | attempt 7: 12.8, not 8.0 |
| 19 | `RETRY-12` — a default differing | `DEFAULT_MAX_DELAY = 9.0` | the defaults test |
| 20 | `RETRY-41` — a clamp not logged | `nil &&` before the diagnostic | "the clamp is logged": `[]` |
| 21 | `P6-10` — the baked flag also answering `#retryable?` | `alias retryable? retryable_by_status?` | "Expected #<ProtocolError: HTTP 503 …> to not respond to retryable?" |
| 22 | `CFG-35` / `RETRY-2` — the query written as `is_a?(::IOError)` | `probe.is_a?(::IOError)` | three failures: `StreamError` accepted, `RetryableByCapability` refused, `UnretryableIOError` accepted |
| 23 | `RETRY-45` — the engine shutting down the scheduler | `::Fiber.scheduler&.close` in `Pump#abort` | "async_retry_step.rb touches a scheduler" |
| 24 | Task 8 — `bundle:` not defaulting to `Bundle::NONE` | a built bundle as the default | "#bundle defaults to NONE" fails |
| 25 | Task 8 — the correlation still passing `Bundle::NONE` | `Tracing.correlate(span, Bundle::NONE)` | the OBS-23 push test: `trace.id` nil |
| 25a | Task 8 — `#bundle` not carried across `#fork` | `bundle: Bundle::NONE` in `Cursor#fork` | "survives #fork" and "a fork of a fork" fail |
| 26 | a Regexp built without `timeout:` | `DECIMAL_GRAMMAR` without it | "DECIMAL_GRAMMAR: per-pattern, never Regexp.timeout" |
| 27 | `RETRY-8` — the predicate consulted before the gate | the two `decision` checks reordered | "a should_retry answering true cannot override": 2 sends |
| 28 | `OBS-29` — `retries_exhausted` for a never-retryable failure | the `EXHAUSTED` condition dropped | the 404 test: `[:attempt_started, :retries_exhausted]` |
| 29 | `RETRY-23` — the token not checked at the top of a sync attempt | `check!` removed from `RetryStep#drive` | "checked at the top of every attempt": no `CancelledError` under `Clock::SYSTEM` |
| 30 | `RETRY-23` — the token not checked at the top of an async attempt | `check!` removed from `Pump#launch` | **stays green**, honestly: the async driver's `on_cancel` subscription fails the future the instant the token is cancelled, before any next attempt could launch, so the boundary check is a belt behind that bridge and no fixture reaches it; the check stays (a cancel raced against the hook's own flag flip is the one window) and the row says so |
| 31 | `RETRY-30` — the recursive pump | `resume` calling `launch` directly | `SystemStackError: 10859 -> 61` on the 2,000-attempt test |
| 32 | `RETRY-10` / `RETRY-9` — jitter BEFORE the cap, then clipped | `[jittered(raw, …), max].min` in `backoff_delay` | "a sample above the cap: jittered after capping": `Expected 8.0 to be > 8.0` (round 0's m02, which the `[4.0, 12.0]` band alone let survive) |
| 33 | `RETRY-16` / `P6-61` — the runs unbounded and the byte ceiling removed | `\d+` back in both grammars, `readable?` reduced to `is_a?(::String)` | four failures: the 10 MB run converted (`0.6 s … the value was read`), the 400-digit run's `Float … out of range` warning recorded, a sixteen-digit run clamped instead of `nil`, and the totality set's `9 * 16` |
| 34 | `RETRY-23` / `P6-60` — the decision's cancellation guard removed | `return STOP if Policy.cancellation?(failure)` deleted from `RetryStepHelpers#decision` | "a should_retry answering true cannot retry a downstream cancellation": status 200 after 2 sends, on both stage drivers |
| 35 | `RETRY-23` / `P6-60` — `Policy.retryable?`'s cancellation guard removed | `return false if cancellation?(error)` deleted | the wrapped-carrier cases: `Policy.retryable?` true for a `RetryableByCapability` carrying a `CancelledError`; the recovery engine re-sends it (2 sends). The sync stage suite stays green under this one alone, because guard 34's check still stands in front — the two guards are a belt and a brace, and each has its own red |
| 36 | `RETRY-35` — the tracer's `attempt_failed` outside the fence | the emission moved after the `fenced` block in `RetryStep#wait` | "closed before the raise propagated": `body.closed?` false |
| 37 | `RETRY-41` / `P6-59` — the configured value not clamped | `resolve_max_retries` returning the configured Integer without `Policy.effective_max_retries` | two errors: `InvalidArgumentError: max_retries must be a non-negative Integer (RECOV-34)` from `.build` on the clamp test and on the contained-log test |

## Audit groups run

`ruby scripts/knowledge.rb --origin note --brief` — 53 note entries across 18 files; `--section
conflicts --brief` — 19 rows, every harvested conflict `[overridden by notes/…]`, none open. The eleventh
audit row, `ruby scripts/knowledge.rb --prefix RETRY,REDIR,AUTH --section rules --brief` — 371 lines, one
`[appendix-B roll-up]` marker in the whole group and none for a `RETRY` ID. The fourteen appendix-C-only
`RECOV` IDs were read out of rows 245–258 (and `RECOV-34` from row 262, `RECOV-31` from 259) and chapter
09 was read in full. The five binding notes were read rather than trusted from their markers:
`pipeline/86343352` (fork for every drive), `pipeline/7ce4431d` (`cause: nil`),
`error-handling/5322e965` (the trail), `execution-context/b58728da`, `url-and-query-encoding/08c54234`.
No knowledge note is filed: nothing found contradicts a harvested rule (the `0.0 * Infinity` finding is a
Float fact, not a corpus correction, and lives in `Policy`'s comment and `P6-53`).

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate. Items
1–18 are where the built tree overrode the plan's assumptions, in the order the brief's as-built list
gives them; the rest are this build's, and the ones that touch public behaviour are also ledger rows
`P6-51`–`P6-58`.

1. **The two test-support files the plan creates already existed and were not overwritten.** Phase 2's
   top-level `FakeTransport` stays untouched; the scripted double is the new top-level `ScriptedTransport`
   (`test/support/scripted_transport.rb`, `.new(script)`, `#calls` frozen triples, a three-positional
   `#call`) with its async twin `ScriptedAsyncTransport(script, settle_later:)` and `#settle_next!`. The
   plan's `ProbeHTTPTracer` was not written: 5c's `Dexpace::RecordingHTTPTracer` records all eleven
   callbacks as `[:name, *args]` tuples and is reused, one double per idea. No `Test` sub-namespace exists.
2. **No `fake_pillar_cursor`, and `ForkingProbe` is a step, not a downstream.** Every driver test runs
   through a REAL `Dexpace::Pipeline::Builder … .append(step).build` (or `.build_async`) over a scripted
   transport, "attempts" is `transport.calls.size`, and the fork-for-every-drive rule is asserted through
   `RetryFixtures::RecordingWrapper`, a step that hands the real driver-minted cursor to the retry step
   inside a `RecordingCursor` that counts `#fork` and `#call` — 5b's checklist item 12's route.
3. **`Step#bundle_for` never existed.** Task 8 changed `#open_span`, exactly as 5b's class comment said it
   would: `open_span(request, bundle)` resolves the factory from the cursor's bundle when it is not `NONE`,
   and `Step#call` / `AsyncStep#head` hand `cursor.bundle` to `Tracing.correlate`. The test needs a REAL
   bundle with a recording span (5c's `RecordingTracerFactory`) to make the push observable, and builds
   it as `bundle_test.rb` does (eight members, three required). The meter half has no bundle source and the
   `CTX-14` row says so.
4. **The widening's collateral.** 4c's `cursor_test.rb` pin of Cursor's public method set gained `bundle`
   (code branch); 5b's three `Object.new` cursor stand-ins gained `#bundle` (code branch; without it the
   step's `cursor.bundle` is a `NoMethodError`); `Cursor#fork` copies `@bundle` beside `@options`; both
   drivers' `#advance` gained `bundle:`; `dexpace_test.rb`'s layer table gained `RESILIENCE_LAYER` and a
   "retry layer resolves" case. `Pipeline#call`'s optional `bundle:` still passes `Transport.conforms?` and
   departs from P4-38's reasoning: `P6-51`.
5. **The plan's async pump recurses and the design's claim about it is false** — measured: `Future#on_settle`
   runs inline on a settled future, so the plan's `pump.call(attempt + 1)` from inside the callback grows
   the stack seven frames per attempt and overflows at ~1,500 on every interpreter, while the plan's own
   200-attempt test passed vacuously. The built `Pump` is a re-arm-flag trampoline (`P6-54`) and the test
   measures `caller.size` at attempt 1 and attempt 2,001. A positive `Async.delay` with no scheduler raises
   synchronously; the fence catches it and fails the future (R2's route 3, the plan's "caught by the same
   rescue" claim corrected to "caught by the fence around the caller, not around the callback").
6. **`Clock#sleep(0.0, …)` returns before the token check**, so every driver calls `cancellation.check!` at
   the top of every attempt (the plan's `RetryStep#call` never did), and the one SYSTEM-clock test is the
   zero-length case.
7. **`sig/dexpace/instrumentation/http_tracer.rbs` existed**; `interface _HTTPTracer` was added inside it
   and its comment rewritten; 5c's `Numeric next_delay` kept. `RecoveryRetry`'s factory is called with the
   request, the stage drivers' with the cursor. `retries_exhausted` fires immediately before the terminal
   raise on the recovery stack and nothing emits `operation_failed` — conforming per `docs/first-release.md`'s
   entry, and the YARD says so rather than "half".
8. **`RetryPredicateError` is the flat `Dexpace::RetryPredicateError`** in `lib/dexpace/error/`, the tree's
   convention; every test and `P6-11` agree (`P6-56`).
9. **RuboCop's rules over the plan's fences**: `extend self` everywhere (never `module_function`, which also
   means the manifest lists `Policy#backoff_delay` as an instance row); no `require "set"`; `=> error`;
   every driver's `#call` split into helpers under `MethodLength 25` and `AbcSize 17`; the five positionals
   of the plan's `initialize` became keywords; `rescue ::Exception` carries its disable-with-reason; every
   suite over 100 lines split into nested `DexpaceTestCase` classes; `Pump` carries a recorded
   `Metrics/ClassLength` exception with its reason (115 lines, one per-call state machine). Every
   `private_constant` has a `sig/` mirror and no `test/` mirror — `P6-11`'s "carry no sig/" is wrong for
   this tree and the As-built addendum corrects it.
10. **`Random` is outside NFR-11's allowlist**: every `random` is `untyped` in `sig/`, and
    `retryable_statuses:` is `Enumerable[Integer]` (the gate refused `_Each`). `Policy::NANOSECOND` is a
    private constant.
11. **The earlier-phase bodies the plan quoted were stale**: `http_date.rb`'s `extend self`, private
    constants and two-literal grammar; `protocol_error.rb`'s `is_a?` guard and `describe`, which gained
    exactly one ivar line, the reader and `require_relative "../retryability"` (`Retryability` accepts a
    `Status`); `StreamError.new` takes no `retryable:` — the suites define `RetryableError < ::IOError`
    and `UnretryableError`; `Response` has no `#closed?` — every fixture response is built over a
    `ResponseBody` and `response.body.closed?` is the assertion; `Recovery.buffer_error_body` returns a NEW
    response each time and nothing asserts identity across it; the engine's response path converts through
    `ProtocolError.for(buffered)` after buffering, so `.for`'s "already buffered" YARD holds.
12. **`lib/dexpace.rb`'s block is after 5b's**, nine files in dependency order (the design's "six new lib
    files" is six public ones; the count is nine).
13. **Hermeticity**: every test that consults the process slot installs `FakeConfigSource` through
    `Dexpace.configure { |c| c.env_source = … }` and calls `Dexpace.reset_config!` in teardown — true
    since review round 1 (R0-1): the three driver suites built their default settings off the LIVE slot
    and a host `MAX_RETRY_ATTEMPTS=0` broke the recovery suite, `-1` all three; each suite's `Fixtures`
    module now carries the seam in `setup`/`teardown`, the shape `retry_settings_test.rb`'s `Hermetic`
    and `budget_equivalence_test.rb` already had, and the seven suites answer identically with the
    variable set to `0` and to `-1`. `RETRY-42`'s
    thread tests run with `jitter: 0.0` and `random:` defaults to the `::Random` class (`P6-52`). `RETRY-40`'s
    throwing override IS logged (the plan swallowed it silently) and `RETRY-41`'s clamp too, both through
    `Instrumentation.diagnostic` under `Events::INSTRUMENTATION_HOOK` and `::INSTRUMENTATION_CONFIG` —
    5b's two existing events, no ninth added (`P6-57`). The HTTP tracer is not contained (OBS-30).
14. **Nothing was installed**: all four interpreters were present; the facts were re-run on 3.2.11, 3.4.10
    and 4.0.6 with the interpreter's bin first on PATH, and the suites on all four rows.
15. **Numbering**: the design's `P6-1`–`P6-12` stand; execution's rows start at `P6-51`.
16. **Documents already carrying what Task 13 verifies** were verified and not re-filed: the phase-8
    transport-wrapping entry naming `P6-4`; the `RECOV-31`/`RETRY-38`/`RETRY-29`/`RETRY-43` declined entry;
    the OBS-29 behavioural-asymmetry entry. Older roadmap notes' "Fourteen numbered tasks" and
    `#retryable?` are not rewritten; this phase's note states the built names.
17. **CLAUDE.md, the READMEs and the pages** were rewritten for 6a only, on top of what `main` says, with the
    counts derived from the tree (150 files under `lib/dexpace/`, thirteen private constants, twelve
    checklists, the manifest at 1004 rows, twelve as-built pages).
18. **`Pipeline.standard` / `AsyncPipeline.standard` are not claimed** (6b's Task 13a) and `Resend` carries
    `.eligible?` alone, its sig and test likewise, with room for 6b's `.replayable_body?` and
    `NotReplayableError`.
19. **`DEFAULT_PACING_HEADER_ORDER` is one public constant on `Policy`**, not the plan's two identical
    private lists in `RetryStepHelpers` and `RecoveryRetry` — a duplicated precedence is the drift
    `RETRY-13` is about, one level up (`P6-1`'s list grows by it).
20. **`retries_exhausted` fires only for a retryable failure that met a spent budget** — the plan emitted
    it on every terminal raise and passed `nil` for a returned error status. 5c's `ordering_test.rb`'s
    third case ("a non-retried failure ends in operation_failed alone, never a retries_exhausted") fixes
    the rule; `RetryStepHelpers#decision` and `RecoveryRetry#decision` answer `:retry`, `:exhausted` or
    `:stop` with the budget checked LAST so `:exhausted` means exactly that, and an exhausted error STATUS
    reports a `ProtocolError` carrying the trail rather than `nil` (`P6-58`).
21. **The recovery engine raises a non-retryable THROWABLE as well** — the plan's `terminal` returned
    `response` when `!retryable`, which for a throwable is `nil`; RECOV-20's "disallowed" case surfaces the
    throwable, trail attached, without `retries_exhausted` (the `P6-9` row, sharpened).
22. **`Policy.backoff_delay` guards a zero initial delay** (`P6-53`) and `PacingParsers.parse_epoch_reset`
    guards an infinite band (`Random#rand` raises `Errno::EDOM` on it).
23. **A negative per-call override raises** rather than falling through: "validated non-negative" read as
    validation, unreachable through `RequestOptions.build` (which refuses it) and reachable through a forged
    options object.
24. **Two guard-driven suite repairs** (the "Guards run red" preface): the `RetryableFatal` fixture, and
    exact deltas on the float assertions RuboCop had loosened.
25. **Review round 1, the parser's bounds (R0-3, `P6-61`)**: the plan's and the design's grammars,
    `\A\d+(\.\d+)?\z` and `\A\d+\z`, converted an unbounded run — a 10 MB header value stalled the
    retry decision for seconds in `String#to_f` / `#to_i` and, past ~309 digits, emitted Ruby's
    out-of-range warning that the suite's `NFR-6` raiser turned into an error `Policy#parse_form`'s fence
    swallowed, so the '9' * 400 cases passed by the rescue and not by the parser. Both grammars now
    bound their runs at fifteen digits and `MAX_VALUE_BYTES = 64` sits in front of every parser (the
    longest well-formed value is the 29-byte RFC 1123 date); the '9' * 300 case moved from the clamp
    test to the out-of-range set, and `PacingTotalityTest`'s unexplained retry-after-ms exemption
    (R0-10) is gone with the cause it was hiding.
26. **Review round 1, the tracer inside the fence (R0-4)**: `RetryStep#wait` emitted `attempt_failed`
    after the `fenced` block, so a tracer that raised left the superseded response open on the sync
    driver while `Pump#retry_after` ran inside `guarded(response)` and closed it; the emission now runs
    inside the same fence as the delay resolution on the sync driver, and both suites assert the close.
27. **Review round 1, the cancellation guard (R0-5, `P6-60`)**: a caller's `should_retry` answering
    `true` retried a downstream `CancelledError` — `RetryStepHelpers#decision` handed the failure straight
    to the predicate. `Policy.cancellation?` is the guard, consulted first by `Policy.retryable?` and by
    the decision, on all three drivers; the plan had no such method and the design's `Policy` table
    gains it.
28. **Review round 1, the configured clamp (R0-6, `P6-59`)**: the plan's Task 7 fence — and the tree as
    built — refused a negative configured `MAX_RETRY_ATTEMPTS` at `RetrySettings.build`, so `RETRY-41`'s
    clamp-and-log was unreachable from any driver. `.build` takes `logger:` (read once, never held, on
    `Proxy.resolve`'s and `Hooks.notify`'s no-validation precedent — a validator pushed the class over
    `Metrics/ClassLength`) and resolves the configured value through `Policy.effective_max_retries`; the
    `retry_settings_test.rb` case that documented the refusal now documents the clamp, and an explicit
    negative argument is still `RECOV-34`'s refusal.
29. **Review round 1, the error's test mirror (R0-2)**: `error/retry_predicate_error.rb`, public, had no
    `test/` mirror while every other `error/*.rb` had one and every count sentence said only the thirteen
    `private_constant`s lack one; `retry_predicate_error_test.rb` pins the class's shape.
30. **Review round 1, R0-8 and R0-9**: `step.rb`'s class comment cited `P6-52` for the no-operation-name
    statement (that row is the `Random` default) and now cites `P6-51` and `docs/first-release.md`'s
    behavioural-asymmetries entry; `RetrySettings#backoff_arguments` and `#header_order`, public surface
    the manifest locks, are named in the design's As-built preamble beside `P6-2`.

## Findings routed

- **The design's three findings were verified at their owners, none re-recorded**: the OBS-29
  operation-triple route and the HTTP-tracer-factory-versus-bundle distinction are on phase 10's inbound
  list and in `docs/first-release.md`'s behavioural-asymmetries entry (read, and the built code matches
  it); the cursor widening was Task 8's and is built; the `RETRY-2` blind spot (`P6-4`) is
  `docs/first-release.md`'s release-path entry naming phase 8a's Task 2.
- **New, routed to phase 10's inbound list** (the roadmap's 2026-09-18 entry): the plan's recursive
  async-pump sketch in the 6a DESIGN's object model and its `RETRY-30` claim ("does not grow the Ruby call
  stack") are false as written — a design correction a human applies, recorded in the As-built addendum
  (`P6-54`) and pointed at from the inbound list so the design's sketch is not copied by 6b's or 6c's async
  work.
- **New, routed to phase 6b's plan, Task 13a** (`docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect.md`):
  the two `standard` constructors should install `RetryStep` with `settings:` and `http_tracer_factory:`
  threaded through, and the async preset's "caller-supplied scheduler for non-blocking backoff" is a
  documentation obligation on the constructor — `AsyncRetryStep` takes no scheduler keyword and reads the
  ambient one (R2, route 2 rejected by the design) — so the constructor's YARD, not the step's, must say
  that a positive backoff with no scheduler fails the future with `SeamError`.
- **New, routed to phase 9's `XCUT-6` disposition**: the capability query probes `#retryable?` untyped and
  a raising `#retryable?` propagates (no fence), the same line `Dexpace.each_cause` draws for a raising
  `#cause` only for `StandardError`; phase 9's audit should state whether a caller's `#retryable?` that
  raises is the caller's bug (as built) or a classification failure to contain.

## Postponed work

**What earlier phases postponed here has landed, and the rows above mark it**: the recovery-stack retry
engine (`RECOV-17`–`RECOV-30`, `RECOV-34`; phase 4's segmentation, whose fifteen ⏳ rows stay as they are);
`ProtocolError#retryable_by_status?` (phase 4b's deferral, the `RETRY-3` and `XCUT-5` rows);
`CFG-35`'s throwable half (phase 5a's, the `CFG-35` row); and the per-attempt half of `OBS-29`'s wiring
(phase 5c's, the `OBS-29` cross-reference row). **What stays where it is**: the operation-lifecycle
triple and the transport milestones (phase 10's inbound list, `docs/first-release.md`); `Pipeline.standard`
and `AsyncPipeline.standard` (6b's Task 13a; `PIPE-39` not claimed); `RECOV-31`, `RETRY-29`, `RETRY-38`
and `RETRY-43` (declined for v1); `ASYNC-3`/`ASYNC-4`/`PIPE-33`'s interrupt clause (phase 8's, and 6a adds
no fourth unsatisfied MUST); `RETRY-4`'s flag (phase 8a's Task 2). **This phase postpones nothing new.**
The consolidation of `P6-1`–`P6-12` and `P6-51`–`P6-58` into design §10 is a human's — `docs/sdk-design-ruby/`
is frozen — recorded here as 5b recorded its own.
