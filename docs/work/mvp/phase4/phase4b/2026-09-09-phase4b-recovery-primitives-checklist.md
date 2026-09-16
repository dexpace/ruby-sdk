# Phase 4b — Recovery-Chain Primitives: Checklist

**Written at execution time, 2026-09-16, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The design was written on 2026-09-08 and
the plan on 2026-09-09, against phases 0–3's *plans*; phases 1, 2, 3a and 3b were then built and
merged (PRs #40–#52), and where the plan's text and the built tree disagree the tree wins and this
document records it. Phase 4a was built in parallel in another worktree and nothing of 4a's is on
`main` at this build: 4b names no 4a constant anywhere, exactly as its design promised.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase4/phase4b/2026-09-09-phase4b-recovery-primitives.md`. Task numbers are
that plan's. Design: `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`,
whose Deviation Ledger rows `P4-12`–`P4-25` and as-built rows `P4-40`–`P4-49` are cited below; the
charter is `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`. Every test file named
here is under `gems/dexpace-core/test/`, mirrors its `lib/` file one for one, and opens with the IDs
it exercises.

## Requirement rows

Thirty-four own rows — `RECOV-1`–`RECOV-34` — plus the seven cross-reference rows the design names
for the non-`RECOV` IDs this phase owns a share of: `XCUT-4` (a), `XCUT-8`, `XCUT-9`, `BODY-30`,
`PIPE-37`, `RETRY-34` and `RETRY-25`, the way 3b carried `HTTP-46` and `HTTP-3`. Eighteen ✅,
fifteen ⏳ to phase 6a's recovery-stack retry engine with the charter's twin `RETRY` ID per row, one
⏳ (`RECOV-31`) to `docs/first-release.md`.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `RECOV-1` | MUST | ✅ | 6 | `Dexpace::Outcome` is a module both variants include and nothing else; `Outcome::Success = Data.define(:response)` and `Outcome::Failure = Data.define(:error)`, each with `private_class_method :new`, a validating `initialize` (a `Response`; an `Exception`, any `Exception`) and `.build`, `Model#with` routing through `.build` on the floor. The derivable surface is exactly RECOV-1's: `#success?`, `#failure?`, `#response_or_nil`, `#error_or_nil` (the requirement's own `nil`, P4-21) and `#fold(on_success:, on_failure:)`, one branch invoked at most once, both branches required (P4-44). `case/in` reaches both variants under a private `new`, an unmatched value raises `NoMatchingPatternError` inside `StandardError`, and a 64-sample seeded property has the fold agreeing with the predicates and the two never both true or both false (`dexpace/outcome_test.rb`, `outcome/success_test.rb`, `outcome/failure_test.rb`) |
| `RECOV-2` | MUST | ✅ | 14 | `Recovery::Orchestrator#call` runs the request chain and the transport inside one `rescue ::StandardError` region and converts the raise into a `Failure` threaded through the response chain. **The defining invariant is driven from the request side**: a throwing request step surfaces to a recovery hook as the same object and the transport's call list stays empty; a transport raise is observed the same way; a transport returning a non-`Response` is a `Failure` too (P4-45). The guard that moves the request chain outside the region fails exactly the request-side test (`dexpace/recovery/orchestrator_test.rb`) |
| `RECOV-3` | MUST | ✅ | 12 | `Recovery::RequestChain#apply` is `Array#reduce` over the frozen list, step N's output being step N+1's input; an empty chain returns the request by identity; a throwing step propagates and the steps after it are not invoked — both halves asserted in one test. A step's non-`Request` return is refused before the next step (P4-45), and a transform installs as a step through its own `#call` (`dexpace/recovery/request_chain_test.rb`) |
| `RECOV-4` | MUST | ✅ | 13 | `Recovery::ResponseChain` runs its response steps only while the outcome is a `Success`, handing each the *response* and rewrapping the result (by identity when the step handed the same response back, P4-46); on a `Failure` the whole response phase is skipped and the recovery steps still run. The `sig/` types the response-step list `Response -> Response` and never `Outcome -> Outcome`, so Steep refuses a response step that returns a `Failure` (`dexpace/recovery/response_chain_test.rb`) |
| `RECOV-5` | MUST | ✅ | 13 | Recovery steps run on every outcome, always — including a failure a response step just produced by throwing, which is the clause the suite builds explicitly: a throwing response step, then a recovery step that receives the resulting `Failure` by identity, with no later response step run (`response_chain_test.rb`) |
| `RECOV-6` | MUST | ✅ | 13 | Every response step first, then every recovery step, in declared order within each group; asserted with one recording array as `%i[r1 r2 c1 c2]`, and the interleaving guard (`zip`) fails that test with `[:r1, :c1, :r2, :c2]` (`response_chain_test.rb`) |
| `RECOV-7` | MUST | ✅ | 13 | A throwing response step's error becomes a `Failure` fed to the recovery steps, through `Recovery::Ownership.close_on_throw`; the error-mapping transform installed as a response step has its `ProtocolError` flow through recovery exactly like a transport error (`response_chain_test.rb`) |
| `RECOV-8` | MUST | ✅ | 13 | A throwing recovery step's error is wrapped into a `Failure` fed to the NEXT recovery step — the next step's receipt and the wrapped error asserted together, because one assertion cannot cover both — and `#apply` raises for no `Outcome` input and no step behaviour inside `StandardError`. Held with three stated exceptions, counted rather than excused (P4-19): the fatal family (a `NotImplementedError` from a response step and a `NoMemoryError` from a recovery step both escape untrailed), `Dexpace::OutcomeError`, and a non-`Outcome` argument refused at the boundary (`response_chain_test.rb`, `TotalityTest`) |
| `RECOV-9` | SHOULD | ✅ | 13 | A SHOULD about *step authors*, and 4b ships no recovery step, so it is satisfied in the only sense it can be: the chain tolerates a throwing recovery step (`RECOV-8`'s row) and `ResponseChain`'s YARD states the preference and names `Outcome::Failure.build(error:)` as the way to honour it, with the cost of not doing so — the wrapped error is the chain's defensive catch's and not the step's. Phase 6a's `RecoveryRetry` (its Task 11) is the first recovery step of core's own |
| `RECOV-10` | MUST | ✅ | 14 | `Orchestrator#unwrap` folds the chain's return with `case/in` and a raising `else`: on `Success` the response, on `Failure` `raise error, cause: nil`. Asserted as two things: `assert_same` on the surfaced object (never `assert_equal`, `Exception#==` being structural) and `assert_nil error.cause` **while an unrelated exception is in flight**, over a `Failure` carrying an error the test *constructed* and never raised — RECOV-10's own named case. The bare-`raise` guard fails that test with the caller's in-flight `RuntimeError` as the cause on 3.2.11, 3.4.10 and 4.0.6 (`orchestrator_test.rb`, `UnwrapTest`) |
| `RECOV-11` | MUST | ✅ | 14 | Satisfied structurally with no wrapping helper and no token mutation (P4-17): a `Dexpace::CancelledError` from the transport is converted like any `StandardError`, and the test cancels a `Cancellation::Source`, passes its token, and asserts the token still answers `#cancelled?` inside the recovery fold, after the unwrap, with its reason intact — the property the requirement is about, not the error's class (`orchestrator_test.rb`) |
| `RECOV-12` | MUST | ✅ | 13 | Three clauses, one test each, plus the one the design singles out. A throw with a `Success` in hand releases the response **exactly once** — a count of 1 on `RecordingBody#release`, from a response step and from a recovery step; the close error lands on the primary's suppressed trail through `Dexpace.close_quietly(response, onto: error)` (P4-47) and the primary is the same object; a `Failure` in hand closes nothing. And the error-mapping step's own close (buffering) plus the chain's close leave the release count at 1: "exactly once" is `Closeable`'s latch, not bookkeeping, asserted by the only count that would catch a chain that started bookkeeping (`response_chain_test.rb`, `OwnershipTest`) |
| `RECOV-13` | MUST | ✅ | 13 | Asserted as a **zero**: a recovery step deliberately returning a substitute `Success` leaves the original's release count at 0, so does a deliberate `Success`-to-`Failure` transform, and so does a response step returning a different response. The absence of a close on the return path is `Ownership.close_on_throw`'s normal return, which is why the helper is named for the throw path (`response_chain_test.rb`, `OwnershipTest`) |
| `RECOV-14` | MUST | ✅ | 12, 13 | Both chains `dup` and `freeze` every step list at construction — `RequestChain#steps`, `ResponseChain#response_steps` and `#recovery_steps` — asserted by mutating the caller's arrays afterwards on all three lists and by `FrozenError` on the returned copy, which is the frozen copy itself (`HTTP-5`'s second tier). A shallow copy and not `Model.own` (P4-22); the chains hold no other state, and the two transforms with a list (`IdempotencyKeyStep#methods`, `ClientIdentityStep#tokens`) copy theirs the same way (`request_chain_test.rb`, `response_chain_test.rb`, the two step suites) |
| `RECOV-15` | MUST | ✅ | 11 | `Recovery::ErrorMappingStep#apply` treats only 400..599 as errors through phase 1's `Status#error?` — no second predicate — and returns a 1xx, 2xx or 3xx **by identity with the body's `#source` never called and its latch never flipped**, over six codes; an error status is buffered, mapped through the factory (`ProtocolError.for` by default, one frozen lambda) and raised with `cause: nil`, asserted with an unrelated exception in flight. `Dexpace::ProtocolError` (Task 5) is what it maps to: `#response`, `#status`, `.for`, `.for_or_nil`, a message naming the code and its canonical name and never the body. **The row also records what Task 5 shipped without**: `XCUT-5`'s baked retryability flag, postponed by the design to phase 6a, Task 6 (`docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry.md`, `Dexpace::ProtocolError#retryable_by_status?`), which extends Task 5's suite rather than replacing it, so no assertion pins the predicate's absence (`dexpace/recovery/error_mapping_step_test.rb`, `dexpace/error/protocol_error_test.rb`) |
| `RECOV-16` | MUST | ✅ | 7, 11 | `Recovery.buffer_error_body(response)` implements the contract phase 3b fixed: identity for a non-error status or a `nil` body, otherwise `Body.buffer_bounded(body, cap: Body::MAX_BUFFERED_ERROR_BODY_BYTES)` and `response.with(body:)`, the original closed in `buffer_bounded`'s own `ensure`. **One bound**: the truncation test names the constant and not `1024 * 1024`, and a second bound of either spelling is a red test; no constant with `BYTES` in its name exists under `Recovery` and no literal in `recovery.rb`. `ErrorMappingStep` calls it *before* the factory, asserted by the factory seeing a `BufferBody` (`dexpace/recovery_test.rb`, `error_mapping_step_test.rb`) |
| `RECOV-17` | MUST | ⏳ | — | Retry eligibility off a capability with the configured status set authoritative: the recovery-stack retry engine, postponed by the charter (`docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`, "Why the sixteen move") to phase 6a, Tasks 3, 4, 5, 7 and 11 (`docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry.md`); twin `RETRY-37`, `RETRY-1`, `XCUT-6`/`XCUT-7` |
| `RECOV-18` | MUST | ⏳ | — | The re-sendability gate: phase 6a, Tasks 3, 4, 5, 7 and 11, per the charter; twin `RETRY-5`–`RETRY-8`. Phase 3b's `Body#replayable?` is the property it reads |
| `RECOV-19` | MUST | ⏳ | — | Re-classifying each re-sent attempt's response: phase 6a, per the charter; twin `RETRY-36`. It reads like `ErrorMappingStep` and is not — it is the retry loop's re-entry into that step, and `Recovery.buffer_error_body` is the one buffering call site it will reuse |
| `RECOV-20` | MUST | ⏳ | — | Max-attempts cap and total-timeout budget: phase 6a, per the charter; twin `RETRY-27`, `RETRY-14`. The budget's clock is phase 5a's `deadline:` (Task 8) |
| `RECOV-21` | MUST | ⏳ | — | The exponential/jitter/clamp formula: phase 6a, Task 3, per the charter; twin `RETRY-9`–`RETRY-11`. `RETRY-13` forbids a second calculator, which is the charter's forcing argument |
| `RECOV-22` | MUST | ⏳ | — | A pacing hint replaces, is still clamped, gains no jitter: phase 6a, Tasks 3 and 4; twin `RETRY-20`, `RETRY-21` |
| `RECOV-23` | MUST | ⏳ | — | The parser is total, malformed → no hint, past → zero: phase 6a, Task 4; twin `RETRY-16`, `RETRY-17` |
| `RECOV-24` | MUST | ⏳ | — | The four recognised pacing forms and their precedence: phase 6a, Task 4; twin `RETRY-15`, `RETRY-19`, `RETRY-21` |
| `RECOV-25` | MUST | ⏳ | — | `X-RateLimit-Reset` positive jitter to [100%, 120%]: phase 6a, Task 4; twin `RETRY-15`'s own last clause |
| `RECOV-26` | MUST | ⏳ | — | Overflow-safe duration arithmetic and the 365-day clamp: phase 6a, Task 3; twin `RETRY-11`, `RETRY-18` |
| `RECOV-27` | MUST | ⏳ | — | The cancellable, non-pinning inter-attempt wait: phase 6a, Task 5, behind `CFG-15`'s seam, which is the charter's second forcing argument; twin `RETRY-23`, `RETRY-26`, `XCUT-3`. 4b builds no wait of any kind |
| `RECOV-28` | MUST | ⏳ | — | The engine is stateless across calls: phase 6a, Task 11; twin `RETRY-42` |
| `RECOV-29` | MUST | ⏳ | — | A pacing-parse failure never masks the upstream failure: phase 6a, Task 4; twin `RETRY-22`. `Dexpace.attach_suppressed` is the carrier it will use |
| `RECOV-30` | SHOULD | ⏳ | — | One calculator and one parser across both stacks: phase 6a, Tasks 3 and 4; twin `RETRY-13`, `RETRY-14`, `RETRY-28` |
| `RECOV-31` | MAY | ⏳ | — | The per-attempt ordinal header, declined post-MVP by the MVP-scope design together with `RETRY-38`: `docs/first-release.md` § What v1 ships without › SHOULD/MAY, the `RECOV-31`/`RETRY-38`/`RETRY-29`/`RETRY-43` entry, whose trigger is per-attempt observability being prioritised; design §11.20. Not phase 6's budget, and not UNSCHEDULED |
| `RECOV-32` | MUST | ✅ | 9 | `Recovery::IdempotencyKeyStep.build(header:, strategy:, methods: [POST, PUT, PATCH], mode: :respect_existing)`, a `:request` transform. The header is stamped only for a method in the set — GET, HEAD, DELETE and OPTIONS pass by identity with the strategy uncalled; in `:respect_existing` a request already carrying the header returns by identity **and the strategy's call count is zero**; in `:overwrite` the strategy's value replaces every existing one; the strategy is invoked exactly once per applicable request and receives the request; a configured set replaces the default; the set is copied and frozen. The mode-inverted guard and the strategy-before-the-check guard each fail (`dexpace/recovery/idempotency_key_step_test.rb`) |
| `RECOV-33` | MUST | ✅ | 10 | `Recovery::ClientIdentityStep.build(header:, tokens:, mode: :append)`, a `:request` transform. The joined line is the sole value when the header is absent; `:append` puts it after the FIRST existing value and preserves every other value in order (a three-valued fixture, which a single-valued one cannot catch); `:replace` overwrites all; an empty list or one joining to a blank line is a no-op by identity in both modes; an empty first existing value is treated as absent so no leading space is emitted. Tokens are stripped and blank ones dropped (P4-49). Four guards fail: the mode inverted, `#set` alone, the no-op dropped, the empty-first rule dropped (`dexpace/recovery/client_identity_step_test.rb`) |
| `RECOV-34` | MUST | ⏳ | — | Construction-time validation and defensive copies of the retry stack's settings: phase 6a, Task 7 (`RetrySettings`), per the charter; twin design §6.1 and §10.18. 4b's own chains validate and copy at construction (`RECOV-14`'s row), which is the same discipline and not this ID |
| `XCUT-4` (a) | MUST | ✅ | 5 | Cross-reference, phase 9's ID: branch (a), `Dexpace::ProtocolError < ::StandardError` including `Dexpace::Error`, carrying `#response` (buffered) and `#status`, flat under `Dexpace::` beside where phase 8's branch (b) `TransportError < ::IOError` lands. One class and no per-status tree (P4-20); no `#retryable_by_status?` (phase 6a, Task 6). Branch (b) and the always-retryable clause are phase 8's (`dexpace/error/protocol_error_test.rb`) |
| `XCUT-8` | MUST | ✅ | 5 | Cross-reference: `ProtocolError.for` raises `Dexpace::InvalidArgumentError` naming the code for 100, 200, 201, 301, 304 and 399; `.for_or_nil` returns `nil` for a non-error status and the error otherwise — the two forms verbatim. The step only ever calls a caller's factory for an error status, and a factory returning a non-`Exception` is refused (P4-45) (`protocol_error_test.rb`, `error_mapping_step_test.rb`) |
| `XCUT-9` | MUST | ✅ | 3 | Cross-reference, phase 9's ID: `Dexpace.each_cause(error)` yields the error first (P4-16) then each `#cause`, tracking visited objects in a `Hash` built with `#compare_by_identity`. R7's three cases plus two: termination on a self-cycle (a count of 1), on a two-node cycle (`assert_same` per element), the `equal?`-not-`==` discrimination over two **never-raised** `StructurallyEqualError`s chained through a `#cause` override and overriding `hash`/`eql?` (an `Array`-tracked and a `Set`-tracked visited set each yield 1 — measured red on 4.0.6 **and 3.2.11**, the construction the design says survives the floor), a raising `#cause` ends the chain, and so does a lying one (P4-48). Returns an `Enumerator` without a block. The repository-wide "nothing else walks `#cause`" audit is phase 9's (`dexpace/each_cause_test.rb`) |
| `BODY-30` | MUST | ✅ | 7 | Cross-reference, phase 3b's ID: its "a response with no body is returned unchanged" clause, which 3b's checklist hands to `Recovery.buffer_error_body`, is discharged — identity for a `nil` body, and the buffered copy readable repeatably through `#body_string` and `#body_bytes` (`dexpace/recovery_test.rb`) |
| `PIPE-37` | MUST | ✅ honourable half | 11 | Cross-reference, phase 4c's ID: the parenthesised clause is made honourable here — `ErrorMappingStep#apply` returns a non-error response by identity with the body not read, consumed or closed, asserted with `RecordingBody#source_count` and `#release_count` both 0 and the latch unflipped, and the reading and closing guards each fail. The outermost pre-redirect placement is 4c's to honour and stays its row (`error_mapping_step_test.rb`) |
| `RETRY-34` | MUST | ✅ skip-self guard | 1 | Cross-reference, phase 6a's ID: `Dexpace.attach_suppressed(primary, secondary)` skips self **by identity and never by `==`** — a `==`-equal twin is attached, self is not — and the guard's removal fails two tests. The failed-attempt trail itself and its discard on success are phase 6a's, through this one helper on both stacks (`dexpace/suppressible_test.rb`, `AttachTest`) |
| `RETRY-25` | MUST | ✅ as `RECOV-2`'s rule | 13, 14 | Cross-reference, phase 6a's ID: the fatal family — `LoadError` from a request step, `NotImplementedError` from a response step, `NoMemoryError` from a recovery step — is surfaced unchanged, unobserved by any recovery hook, with an empty trail; `Dexpace::OutcomeError` joins that arm by name (P4-19). Converting `LoadError` is a red guard. The retry-time behaviour is phase 6a's (`orchestrator_test.rb`, `response_chain_test.rb`) |

## What was built

Sixteen new `lib/` files under `gems/dexpace-core/lib/dexpace/` — exactly the design's Module
Layout: `suppressible.rb` (`Dexpace::Suppressible`, `Dexpace.attach_suppressed`,
`Dexpace.suppressed`), `each_cause.rb` (`Dexpace.each_cause`), `error/outcome_error.rb`,
`error/protocol_error.rb`, `outcome.rb` with `outcome/success.rb` and `outcome/failure.rb`,
`recovery.rb` (`Dexpace::Recovery`, `.buffer_error_body`) and, under `recovery/`, `transform.rb`,
`idempotency_key_step.rb`, `client_identity_step.rb`, `error_mapping_step.rb`, `request_chain.rb`,
`ownership.rb` (the `private_constant`) and `response_chain.rb`, `orchestrator.rb` — each with a
`sig/` mirror declaring every method, private ones and instance variables included, for the strict
`core` Steep target (sixteen mirrors, `ownership.rbs` among them, P4-41), and every one but
`ownership.rb` with a `test/` mirror. Four `lib/` files changed as the design said: `error.rb`
gains the `include` and a rewritten comment; `hooks.rb`'s `notify` attaches every later handler
failure to the first and re-raises it with `cause: nil`; `closeable.rb`'s `close_quietly` gains
`onto:`, validated at entry; and the entry file gains `suppressible` above `error` — the one
load-bearing line — and a fifteen-line `# Phase 4b:` block at its end in the plan's Task 15 order.
Two `sig/` files changed: `error.rbs` (the `include` and the `::Exception` self-type) and
`closeable.rbs` (`?onto: ::Exception?`); `hooks.rbs` is untouched. Three existing suites gained
tests: `cancellation_test.rb` (the fourth `Hooks.notify` test and its `cause: nil` twin, in
`Subscriptions`), `closeable_test.rb` (four `onto:` tests in a nested `QuietlyOntoTest`) and the
smoke suite `dexpace_test.rb` (`RECOVERY_LAYER` and the recovery-layer-resolves test). Three
test-support files are new — `recording_body.rb`, `cyclic_errors.rb`, `recovery_fixtures.rb` — and
phase 2's `fake_transport.rb` is reused unchanged (P4-43). The surface manifest gains 71 rows, from
515 to 586. The gemspec is untouched — zero `add_dependency` lines — and 4b adds no `require` of any
kind beyond `require_relative`: `seam_surface_test.rb`'s pinned list stays `securerandom strscan
uri`. `docs/knowledge/notes/` is untouched: the design's three notes stand, and execution found the
corpus wrong about nothing further. `docs/deviations.md` is untouched, for phase 10 to flip.

The gates, all seventeen, on **4.0.6** (`bundle exec rake`, 2026-09-16), on the working branch
before the cut and again at the tests tip: green, exit 0 — `cops:test` 100 runs / 326 assertions,
`steep` no type error over the strict `core` target, `test:gems` **1,289 runs / 6,964 assertions**
across the six gems (129 of them the fifteen new suites, seven more the phase-2 and smoke suites
gained), with **99.97% line coverage (3,396 / 3,397)** against the 80% floor — the one uncovered
line is the same registry-claim race branch phases 2, 3a and 3b recorded — `test:gates` 129 runs,
the nine `gates:*` tasks (`gates:require_allowlist` clean, 23 bundled gems known;
`gates:surface_snapshot` six manifests matching; `gates:rbs_surface` no foreign constant), `yard`
100.00% documented (418 methods, 0 undocumented), `bundler_audit` clean. The matrix set is green on
3.2.11 (`test:gems` 1,289 runs, 99.97% line coverage there too — 3,350 / 3,351 — and the four
gates), 3.3.12 and 3.4.10. The same caveat about `rubocop` that phases 1, 2, 3a and 3b recorded: run through `rake`
from a worktree nested under the parent checkout's `.claude/` it inspects 9 files; run as
`bundle exec rubocop --fail-level=convention --ignore-parent-exclusion` it inspected **261 files,
no offenses**, and every RuboCop claim here rests on that run. The code tip's own numbers are in
the roadmap's status note beside the tests tip's.

## Guards run red

Every guard the plan and the brief ask to be seen red was seen red, on 4.0.6, and restored; the
two `XCUT-9` container guards and the `RECOV-10` unwrap guard were run on 3.2.11 as well (and the
unwrap guard on 3.4.10), because those are the assertions the design says an interpreter could
hide. Thirty-nine single-edit mutations in all, one file at a time, the owning suite re-run and the
file restored byte-for-byte after each; **thirty-eight were caught, and the one that was not is a
mutation that does not change behaviour** (`break` for `next` on the response loop's guard, both of
which skip the step). Two mutations were re-spelled because their first form tripped `NFR-6`'s
warning gate at load (a discarded `nil`) — a mutation caught by a warning, not evidence about a test
— and the require-order guard needed two edits at once, because `error.rb`'s own
`require_relative "suppressible"` makes the entry file's order redundant on its own.

| Fix reverted | Guard | What it said |
|---|---|---|
| `RETRY-34`: the skip-self guard removed | `suppressible_test.rb` | `Expected: [] Actual: [#<StandardError: same>]`, and the empty-trail rendering test gains a `(1) StandardError: plain` line |
| P4-13: the `FrozenError` rescue removed | `suppressible_test.rb` | `FrozenError: can't modify frozen StandardError`, and the same for a frozen `Dexpace::SeamError` |
| P4-14: the trail returned unfrozen | `suppressible_test.rb` | `Expected [#<RuntimeError: cleanup failure>] to be frozen?`, twice |
| P4-12: the `include` dropped from `error.rb` | `suppressible_test.rb` | `NoMethodError: undefined method 'suppressed' for an instance of Dexpace::SeamError`; `Expected Dexpace::Error to be < Dexpace::Suppressible` |
| The require order swapped — `suppressible` after `error` in the entry file **and** `error.rb`'s own require dropped | every suite, at load | `error.rb:26:in '<module:Error>': uninitialized constant Dexpace::Suppressible (NameError)` |
| `Hooks.notify` dropping the later failures again (`failure ||= error`) | `cancellation_test.rb` | `Expected #<IOError: first handler failed> to be a kind of Dexpace::Suppressible, not IOError` |
| `Hooks.notify` re-raising with a bare `raise failure` | `cancellation_test.rb` | `Expected #<RuntimeError: unrelated caller in-flight exception> to be nil` |
| `close_quietly` ignoring `onto:` | `closeable_test.rb` | `Expected: 1 Actual: 0` on the trail size |
| `close_quietly` validating `onto:` inside the rescue (the entry check dropped) | `closeable_test.rb` | the "validates onto: before it touches the resource" test: `InvalidArgumentError` expected, and the spy was released |
| `XCUT-9`: the visited set as an `Array` | `each_cause_test.rb` | `Expected: 2 Actual: 1` on the never-raised `==` pair — **on 4.0.6 and on 3.2.11** |
| `XCUT-9`: the visited set as a `Set` | `each_cause_test.rb` | `Expected: 2 Actual: 1` on the same pair, whose `hash`/`eql?` overrides defeat it — **on 4.0.6 and on 3.2.11** |
| Open question 3: the raising-`#cause` rescue removed | `each_cause_test.rb` | `StandardError: broken #cause` |
| `RECOV-16`: `buffer_error_body` reading a literal `1024 * 1024` | `recovery_test.rb` | the no-second-bound test: `Expected /1024 \* 1024|…/ to not match` the file |
| `RECOV-16`: `buffer_error_body` reading a second, smaller constant (`65_536`) | `recovery_test.rb` | `Expected: 1048576 Actual: 65536` |
| `RECOV-32`: `IdempotencyKeyStep` with its mode inverted | `idempotency_key_step_test.rb` | `:overwrite` returned the request by identity; `:respect_existing` stamped `fresh-key` over `existing-key` |
| `RECOV-32`: the strategy called before the respect-existing check | `idempotency_key_step_test.rb` | `Expected: 0 Actual: 1` on the strategy's call count |
| `RECOV-33`: `ClientIdentityStep` with its mode inverted | `client_identity_step_test.rb` | four failures: `Expected: ["host-client/3.0 sdk/1.0"] Actual: ["sdk/1.0"]` among them |
| `RECOV-33`: `:append` through `#set` alone | `client_identity_step_test.rb` | `Expected: ["sdk/1.0", "proxy/1.2"] Actual: ["sdk/1.0"]` — the other values dropped |
| `RECOV-33`: the blank-line no-op dropped | `client_identity_step_test.rb` | the request came back a copy carrying `[""]` |
| `RECOV-33`: an empty first value not treated as absent | `client_identity_step_test.rb` | `Expected: ["sdk/1.0"] Actual: [" sdk/1.0"]` |
| `PIPE-37`: `ErrorMappingStep` reading the body of a non-error response | `error_mapping_step_test.rb` | `Expected: 0 Actual: 1` on `source_count` |
| `PIPE-37`: `ErrorMappingStep` closing the body of a non-error response | `error_mapping_step_test.rb` | `Expected: 0 Actual: 1` on `release_count` |
| `RECOV-15`: the mapping step raising with a bare `raise` | `error_mapping_step_test.rb` | `Expected #<RuntimeError: unrelated caller in-flight exception> to be nil` |
| `RECOV-16`: mapping before buffering | `error_mapping_step_test.rb` | the original body `to be closed?`, and the factory saw a `ResponseBody`, `not Dexpace::BufferBody` |
| `RECOV-14`: `RequestChain` aliasing the caller's list | `request_chain_test.rb` | `Expected [] to be frozen?`; `Expected: 1 Actual: 2` |
| `RECOV-12`: `Ownership` closing twice (a second release outside the latch) | `response_chain_test.rb` | `Expected: 1 Actual: 2`, twice, and a `NoMethodError` from the close-failure double |
| `RECOV-12`: `Ownership` not closing on a throw | `response_chain_test.rb` | `Expected: 1 Actual: 0`, three times |
| `RECOV-13`: `Ownership` closing on a normal return (a substitute outcome) | `response_chain_test.rb` | `Expected: 0 Actual: 1`, on all three RECOV-13 tests |
| R6: `OutcomeError` converted to a `Failure` by `Ownership` | `response_chain_test.rb` | the OutcomeError-escapes test: nothing raised |
| `RECOV-14`: `ResponseChain`'s lists aliased | `response_chain_test.rb` | `Expected: 1 Actual: 2` |
| `RECOV-4`: response steps run on a `Failure` (unwrapping `#error`) | `response_chain_test.rb` | `Expected: [:c1] Actual: [:r1, :c1]`; `Expected [:r2] to be empty` |
| `RECOV-5`: recovery steps skipped on a `Failure` | `response_chain_test.rb` | `Expected: [:c1] Actual: []`, and three more |
| `RECOV-6`: the chain interleaving `r1 c1 r2 c2` (`zip`) | `response_chain_test.rb` | `Expected: [:r1, :r2, :c1, :c2] Actual: [:r1, :c1, :r2, :c2]` |
| `RECOV-8`: a recovery step's throw propagating | `response_chain_test.rb` | `StandardError: c1 threw` escaped `#apply`, three errors |
| `RECOV-10`: the unwrap spelled `raise error` — **on 3.2.11, 3.4.10 and 4.0.6** | `orchestrator_test.rb` | `Expected #<RuntimeError: unrelated caller in-flight exception> to be nil`, identically on all three |
| `RETRY-25`: `LoadError` converted to a `Failure` | `orchestrator_test.rb` | the fatal-family test: the recovery hook ran |
| R6: `OutcomeError` converted to a `Failure` by the orchestrator | `orchestrator_test.rb` | the OutcomeError-escapes test: nothing raised |
| `RECOV-2`: the request chain moved outside the rescue region | `orchestrator_test.rb` | `Expected nil to be the same as #<IOError: pre-request explosion>` — no hook observed it |
| `RECOV-4`: `break` for `next` on the response loop's Success guard | `response_chain_test.rb` | **green, 22 runs** — both skip the step; a no-op mutation, recorded so nobody counts it |

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returns 52 note entries
across 21 files (the design's three among them); `--section conflicts --brief` returns 19
note-side entries and no open conflict. `--prefix-info RECOV` reports 34 IDs, 19 substantive,
0 roll-ups, 15 uncited — the fifteen the charter dispositioned, appendix C their only statement;
`--gaps RECOV` names exactly those. `--req` was run for each task's IDs before that task; none came
back a roll-up. The seven groups the design ran at planning are recorded there; at implementation
the three that bite were re-checked against the built code:

| Group | Result at implementation |
|---|---|
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for all sixteen files — `suppressible.rb` defines one module and two module functions on `closeable.rb`'s precedent, `each_cause.rb` a function and no constant; `api-design/b0e18938` is why every name is in P4-15, P4-23, P4-24 or P4-40–P4-49, and why `DEFAULT_METHODS`, `MODES`, `DEFAULT_FACTORY` and `Suppressible::EMPTY` are `private_constant`; `api-design/88e6bf12` is honoured by `respond_to?(:call)` at every step and transport, `Registry.callable?` at every factory and strategy, and no `is_a?(IO)` anywhere; `api-design/c15b29ce` holds for every returned collection (the trail, three step lists, two token/method lists), each frozen |
| Fiber scheduler, thread safety | Clean against the built code: no mutex, because no mutable shared state — a chain is frozen lists, an orchestrator three frozen references, a transform frozen configuration; the trail's single-writer claim is stated in `Suppressible`'s YARD with the 3.2.11 loss named; `Timeout.timeout`, `Thread#raise` and `Thread#kill` appear nowhere; nothing waits |
| Resource lifecycle and stream ownership | Clean against the built code: exactly one close site in the layer, `Ownership.close_on_throw` through `close_quietly(onto:)`; `buffer_error_body` delegates every byte and every close to 3b's `buffer_bounded`; a non-error response passes `ErrorMappingStep` with its body untouched, asserted by count; `resource-management/bf5560dc`'s block form does not reach a fold that hands its resource outward (P4-18) |

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate.
Items 1–8 are where phases 1–3b as built overrode the plan's assumptions, the brief's as-built list
in the order it gives them; the rest are this build's, and the ones that touch public behaviour or
a stated count are also ledger rows P4-40–P4-49.

1. **`test/support/fake_transport.rb` is phase 2's and is reused, not created.** The plan's Task
   13 writes a fresh `FakeTransport.new(response:, error:)`; phase 2's takes `raises:` and records
   `[request, options, cancellation]` triples under a mutex, which is exactly what `RECOV-2`'s
   transport half and `RECOV-11`'s token assertion need. `RecordingBody` went to its own file,
   `recording_body.rb`, one double per file as 3b's fakes are (P4-43).
2. **`Dexpace::Body` is a module and `RecordingBody` includes it before `Closeable`**, as the plan
   knew; the plan's Task 11 `SpyingBody` was not written, because `RecordingBody` already counts
   `#source` and that suite uses it.
3. **Every response is built through `Response.builder`** with a bare code for `status=` and
   `Protocol::HTTP_1_1`, and every request through `Request.build(method:, url:, headers:, body:)`
   — once, in `test/support/recovery_fixtures.rb`, rather than in seven copies of the plan's
   `build_response`. `Headers#[]` is the value list, so every header assertion compares an Array.
4. **The plan's Task 1 suite named `Dexpace::ContextConflictError`**, a phase-4a constant not on
   `main`; `Dexpace::SeamError` stands in as the frozen-SDK-error fixture. No 4a constant is named
   anywhere in 4b.
5. **`hooks.rb`'s and `closeable.rb`'s comments were rewritten with the code**, as the brief
   says: each now names `Dexpace::Suppressible` as the carrier and says which route landed and
   which stays phase 5b's. `module Closeable` itself is untouched.
6. **The three module functions are declared beside their defining file's `sig/`**, not in
   `sig/dexpace.rbs`, which stays `module Dexpace; end` (P4-42).
7. **A sixteenth `sig/` mirror exists**, `recovery/ownership.rbs`, with `hooks.rbs`'s comment
   (P4-41); the design's "fifteen sig/ mirrors" is corrected in its As-built addendum.
8. **The manifest diff was read row by row against the object model** rather than against the
   plan's Task 15 list, which is in a stale `Class# m1 m2` shape: the Data readers
   `Success#response` and `Failure#error` appear, every `.build`/`.for`/`.for_or_nil` singleton has
   its own row, `Transform#call` is one row on the module and not one per step, and `Ownership`
   contributes nothing. 71 rows, every one intended.
9. **`Suppressible#detailed_message(options = nil)`, not `(**kwargs)`**: the `Dexpace/NoKeywordSplat`
   cop, which the plan's Global Constraints do not list, forbids a `**` rest parameter on a public
   `lib/` method. The positional-`Hash` spelling is `Model#with`'s and was measured on all three
   interpreters before it was written (P4-40).
10. **`Suppressible::EMPTY` is a private frozen constant** the reader returns, and
    `Dexpace.suppressed` allocates a fresh frozen `[]` for a non-`Suppressible` argument: a private
    constant is not reachable by scope resolution from outside the module.
11. **`Dexpace.attach_suppressed`'s RBS is `(::Exception, ::Exception) -> ::Exception`**, not the
    plan's generic `[E < ::Exception] (E, ::Exception) -> E`: strict Steep narrows `E` to
    `::Exception` after the `is_a?` guard and refuses to return it as `E`.
12. **`Dexpace.each_cause` refuses a non-`Exception` argument and stops at a lying `#cause`**
    (P4-45, P4-48); its one `#cause` call sits in a private `Dexpace.next_cause`, declared under
    `private` in its `sig/`. The plan's first test built its three-deep chain with a modifier
    `rescue $!`; the suite builds it with explicit `begin`/`rescue` blocks under `-w`.
13. **`OutcomeError`'s message is `expected a Dexpace::Outcome from a step, got a String`**, not
    the plan's `(R6, P4-19)`-suffixed form — a deviation ID is not a message for a caller — and
    `.new` refuses a non-`Module` (P4-45).
14. **`ProtocolError.for` is written over `.for_or_nil`** (one status test, one message naming the
    code and `XCUT-8`), both refuse a non-`Response`, and the message helper is private.
15. **`Outcome#fold` requires both branches** (P4-44), which is also what replaces the plan's unused
    `on_failure:` parameter on `Success#fold` without a lint waiver.
16. **`Recovery.buffer_error_body` refuses a non-`Response`**, and the suite mechanically asserts no
    `BYTES` constant under `Recovery` and no `1024 * 1024` literal in `recovery.rb` (boundary 10).
17. **`Transform`'s RBS is `[T] (T value) -> T`** on `#apply` and `#call`, and the interface
    `_Transform` the same, rather than an overload over `Request` and `Response`: Steep cannot
    resolve the overloaded forward in `#call`, and the generic is clause 1 stated as a type.
18. **Both request transforms validate `header:` through `HeaderName.of` at `.build`** and store
    its `#original`; `IdempotencyKeyStep` refuses a non-`Array`-of-`Method` set and a strategy that
    is not `Registry.callable?` with arity 1; `ClientIdentityStep` refuses a non-`Array`-of-`String`
    token list and strips and drops blank tokens (P4-45, P4-49). Both keep `MODES` as a
    `private_constant` and `private_class_method :new`.
19. **`ErrorMappingStep.build` validates the factory** as callable with arity 1, and `#apply`
    refuses a non-`Response` argument and a non-`Exception` factory result (P4-45).
20. **`RequestChain#apply` and `ResponseChain` check a step's return type** — a non-`Request`
    propagates from the request chain, a non-`Response` takes the response chain's throw path
    (P4-45) — and `ResponseChain` keeps the outcome by identity on a pass-through (P4-46). Its
    two loops are private `#respond` and `#recover`, the `case/in` is a one-arm
    `Success | Failure` pattern in `#check_outcome`, and `.copy` is a private singleton the two
    lists share.
21. **`Ownership.close_on_throw` rescues `StandardError` only and closes through
    `close_quietly(onto:)`** (P4-47), rather than the plan's `rescue ::Exception … raise unless
    StandardError` and inline `begin`/`rescue` close. Equivalent behaviour, one arm and one helper
    fewer.
22. **`Orchestrator#call(request, options, cancellation)` takes three required positionals**, the
    shape phase 2's bridges have and `Transport.conforms?` checks with arity 3, rather than the
    plan's two optionals; `.build` refuses a transport that is not callable with three positionals;
    and a transport's non-`Response` return is a `Failure` (P4-45). The region is
    `rescue OutcomeError; raise; rescue ::StandardError`, with no `rescue ::Exception; raise` arm —
    the fatal family passes through an absent arm as it would through a re-raising one.
23. **The smoke suite `dexpace_test.rb` gained `RECOVERY_LAYER`** and a recovery-layer-resolves
    test asserting `Ownership` is private, and two of its assertions were tightened to keep the
    class under `Metrics/ClassLength`'s 100 lines. It lives on the code branch, as the brief
    fixes, because the code tip must keep it green.
24. **Six suites are split into nested `DexpaceTestCase` classes** (`suppressible_test.rb`,
    `idempotency_key_step_test.rb`, `client_identity_step_test.rb`, `response_chain_test.rb`,
    `orchestrator_test.rb`, and `closeable_test.rb`'s new group), on phase 3b's precedent, because
    `Metrics/ClassLength` caps a class at 100 lines.
25. **The plan's Task 15 Step 6 named `mise exec ruby@3.3.7`**; the installed row is 3.3.12, and
    the matrix rows were run by putting each interpreter's `bin` first on `PATH` with a fresh
    `Gemfile.lock` per interpreter, as `CLAUDE.md` prescribes.
26. **The plan's Task 15 Step 8 "record the as-built state of the fourteen rows in
    `docs/deviations.md`" was not done**, as the brief fixes: `docs/deviations.md` is left as phase
    2 left it for phase 10 to flip, and the as-built state is the design's own "As built" addendum.
27. **The plan's Task 15 Step 9 "write no replacement sentence" in `CLAUDE.md` is stale on one
    point**: the claims sentence's lib-file count and mirror clauses had changed under phases 3a
    and 3b and were re-derived from the tree (79 files, the two test-mirror exceptions); the
    phase-directory sentence it was about is unchanged.

## Findings routed

- **Two sentences in committed phase-2 documents are made false by this phase's change, and are
  the manager's to rewrite, not 4b's** — recorded here exactly as the design says, and not edited:
  the phase-2 design's "Every handler runs, whatever an earlier one did" paragraph and its plan's
  edge-case bullet, which say the failures after the first are dropped (they are now attached); and
  the four places the phase-2 design, its plan and its `close_quietly` postponement name
  **`Dexpace::Error#suppressed`** as the carrier, which is `Dexpace::Suppressible` (P4-12). The two
  shipped comments that carried the same clause, in `hooks.rb` and `closeable.rb`, are rewritten
  with the code.
- **Design §10 item 6's "`Dexpace::Error#suppressed` supplies the list" and §5.2's placement of the
  trail** are frozen-chapter sentences the built code contradicts: routed to
  `docs/first-release.md` § Blockers, the `C1`–`C13` paragraph, as its fourteenth (`C14`), with
  the replacement sentence written out in the design's As-built addendum. `docs/sdk-design-ruby/`
  is not edited.
- **`Dexpace/NoKeywordSplat` is a constraint the plan did not list** and the design's "`**kwargs`
  is forwarded to `super` verbatim" could not be written as such. Fixed in the writable material
  (P4-40); not a gate finding — the cop is right about the allocation and was not narrowed.
- **The fakes' move to `dexpace-conformance`** (phase 2's condition) is strengthened by three more
  doubles and still unmet; declined by phase 8a's design. Nothing to route.
- **The design's ledger** gains an "As built" addendum (P4-40–P4-49); the consolidation of
  P4-12–P4-25 and P4-40–P4-49 into design §10, and the §5.1, §5.2 and §6.1 addenda, are a human's,
  as they were for 3a and 3b, because `docs/sdk-design-ruby/` is frozen.

## Postponed work

The one item the design postponed keeps its owner: `XCUT-5`'s baked retryability flag on
`Dexpace::ProtocolError` is phase 6a, Task 6 (`#retryable_by_status?`, computed once at
construction from phase 5a's `Dexpace::Retryability`), cited at `RECOV-15`'s and `XCUT-4`'s rows;
Task 5 shipped the class with `#response`, `#status`, `.for` and `.for_or_nil` and no predicate, as
the design's postponement reads. The items earlier phases postponed and this phase picked up are
recorded in the roadmap's phase-4b status note and here: **the suppressed-exception trail phase 1
postponed to phase 4 has landed** (Task 1, as `Dexpace::Suppressible`, `Dexpace.attach_suppressed`,
`Dexpace.suppressed` and `#detailed_message` — the carrier and the method name both differ from
phase 1's wording, P4-12 and R5); **the handler failures `Hooks.notify` dropped after the first
have landed** (Task 2, naming the fourth test, `"two raising handlers surface the first with the
second on its suppressed trail"` in `cancellation_test.rb`'s `Subscriptions`); and
**`close_quietly`'s FIRST disposal route has landed** (Task 2, `onto:`) while the item stays open —
the second route, §8.1's diagnostic for the `onto:`-absent case, is phase 5b, Task 14, and
`Ownership.close_on_throw` is the route's first core caller. The fifteen recovery-stack IDs stay
with phase 6a (Tasks 3, 4, 5, 7 and 11) and `RECOV-31` with `docs/first-release.md`, per their
rows. The other items were re-read on 2026-09-16 and keep their owners: the pivot's `deadline:`
(phase 5a, Task 8), `SEAM-24`/`SEAM-28` (phase 5c, Task 4), `PIPE-33`'s interrupt clause
(`docs/first-release.md`, phase 4c's row), the fakes' move to `dexpace-conformance` (declined by
8a), and 3a's two findings (its plan's Tasks 10 and 14, both closed in 3a as built per 3b's
checklist). The implementation postponed nothing further.
