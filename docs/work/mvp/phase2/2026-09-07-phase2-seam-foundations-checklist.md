# Phase 2 — Seam Foundations: Checklist

**Written at execution time, 2026-09-15, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md`. Task numbers are that plan's.
Design: `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md`, whose Deviation
Ledger rows `P2-n` are cited below. Every test file named here is under `gems/dexpace-core/test/`,
mirrors its `lib/` file one for one, and opens with the IDs it exercises.

## Requirement rows

Thirty: `SEAM-1`–`SEAM-30`.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `SEAM-1` | MUST | ✅ | 15, 16 | Phase 0's three zero-dependency gates run green over twenty more `lib/` files: `gates:gemspec_audit` (zero `add_dependency` lines in `dexpace-core.gemspec`), `gates:require_allowlist` (the only `require`s outside `require_relative` are still phase 1's `uri` and `strscan`, both allowlisted; phase 2 added none) and `gates:clean_bundle` (core loads inside a scratch bundle holding only itself, on 3.2.11 and 4.0.6). Every seam registry starts empty on a bare `require "dexpace"` and core never auto-requires an optional gem (`dexpace/seam_surface_test.rb`, `dexpace/transport_test.rb`, `dexpace/async_transport_test.rb`, `dexpace/serde_test.rb`) |
| `SEAM-2` | MUST | ✅ | 7, 9, 10, 12, 15 | Core names no concrete implementation: the three seam modules are duck types with `.conforms?` predicates, and every zero-candidate error names the seam and the install entry point and **no gem** — asserted by pattern against `net_http`, `async_http`, `net/http`, `async-http`, `json`, `oj`, `httpx`, `excon` and `typhoeus` for all three seams (`dexpace/seam_surface_test.rb`, `dexpace/registry_test.rb`). Phase 0's require denylist still runs |
| `SEAM-3` | MUST | 🚫 | 16 | The byte-stream provider seam is retired (design §10.1): Ruby ships `IO`, `StringIO`, `IO.pipe` and `String` with `Encoding::BINARY` with the interpreter, so choosing them is choosing the platform, and the pluggability apparatus exists only to keep a third-party stream library out of a zero-dependency core, which does not apply. The behavioural contract `IO-1`–`IO-42` is **not** retired with it and is phase 3's (`docs/work/mvp/phase3/phase3a/`, `phase3b/`) |
| `SEAM-4` | MUST | 🚫 | 16 | As `SEAM-3`: the provider-resolution rules for a seam that does not exist. `IO-31`–`IO-36`'s resolution story is phase 3's row, not this phase's |
| `SEAM-5` | MUST | ✅ | 7 | `Dexpace::Registry#resolve`'s four branches: an occupied slot returns the instance with no scan; zero factories raise `Dexpace::SeamError` naming the seam and the install hint; exactly one builds, memoises and returns silently; two or more raise listing every key. An explicit `#install` always wins — a registered factory is never called past an installed provider (`dexpace/registry_test.rb`, the top-level class and `Installation`) |
| `SEAM-6` | MUST | ✅ | 7 | `#install` compares `equal?` on the resolved slot: the identical instance is a no-op with no warning; a different instance over an explicit install raises `Dexpace::InvalidArgumentError` naming incumbent and rejected, leaving the incumbent in place. `#register` carries the rule one level down: the `equal?` factory is a no-op, a different factory under an occupied key raises naming both, with no partial side effect. `#swap(provider) { }` is the unchecked test-scoped override seam the requirement permits, block-scoped and restored in an `ensure` (`dexpace/registry_test.rb`, `Installation` and `Swap`) |
| `SEAM-7` | MUST | ✅ | 7 | A successful resolution is memoised process-wide (one factory call across 32 concurrent resolvers); a failed one memoises nothing, so a later `#register` or `#install` takes effect on the next `#resolve` — including after a `LoadError` from the factory, because the single-flight claim is released in an `ensure` and not on a `rescue StandardError` path (`dexpace/registry_test.rb`, the top-level class, `Concurrency` and `Reentrancy`) |
| `SEAM-8` | SHOULD | ✅ | 7 | Replacing an auto-resolved provider that was already handed out emits one `Kernel#warn` naming the replacement and saying objects built against the previous one may still be in use (P2-6, observed through `WarningCapture`, P2-12). Replacing one that was never handed out is silent — the negative clause, reachable only through the unchecked swap seam and asserted there; the test says in so many words that no production path reaches it, because `#resolve` hands out in the same call that resolves (`dexpace/registry_test.rb`, `Installation`) |
| `SEAM-9` | MUST | ✅ | 7 | State is one frozen `Registry::State` snapshot in one instance variable, swapped under a `Thread::Mutex` held across the swap and nothing else; reads are one unsynchronised reference read. Proven: 32 concurrent first accesses run the factory exactly once and receive one `equal?` instance; 16 concurrent installs admit exactly one; a second resolver arriving mid-build parks on the claim's `Thread::Queue` and receives the winner's instance; a factory that takes the registry's own write lock, or a `.conforms?` predicate that does, cannot deadlock because neither is called under it (`dexpace/registry_test.rb`, `Concurrency`). `IO-39`'s lock-free read survives here as a property, not as a row |
| `SEAM-10` | MUST | N/A | 7, 8 | Vacuous in Ruby (design §10.9): one process-global constant namespace, no classloader, `require` de-duplicates by resolved feature path. Replaced by the version-skew guard phase 0 postponed to this phase: `#register(key, factory, core:)` requires the adapter's `~> MAJOR.MINOR` and compares it against `Dexpace::VERSION` by hand (P2-7), because `Gem` is undefined under `ruby --disable-gems` (re-verified on 3.2.11 and 4.0.6 during the build, and the guard exercised under `--disable-gems` on 4.0.6). Any other requirement form — `>= 0.1`, `~> 0.1.2`, `""`, `nil`, a `Symbol` — is refused as `Dexpace::InvalidArgumentError`, never reinterpreted (`dexpace/registry_version_test.rb`, which cross-checks the comparison against `Gem::Requirement#satisfied_by?` over a seeded grid and an exhaustive 6 × 12 square of running versions and requirements) |
| `SEAM-11` | MUST | ✅ | 9 | `Dexpace::Transport`: any object responding to `#call(request, options, cancellation)`; a bare lambda, a non-lambda proc, a `->(*)` and any object with a `#call` of that arity conform; the wrong arity, a non-callable and — since review round 1 — a callable with a required keyword (`->(r, o, c, must:) {}`, which would pass registration and raise `ArgumentError` at the first send) do not, the last asserted on both transport seams and on `Registry.callable?` itself. Single operation: one `#call`, one response. Options may be ignored: an options-ignoring transport returns the same thing for `RequestOptions::EMPTY` and a populated `RequestOptions`, because options are inert immutable data. No pre-buffering is stated at the seam (the module's YARD block) and is phase 8a's to prove over a socket (`dexpace/transport_test.rb`) |
| `SEAM-12` | MUST | ⏳ | 9 | Phase 8a, Tasks 4–8 and 20 (`dexpace-conformance`'s `TransportSuite`, `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance.md`). What the seam owes is that nothing forces per-request state onto shared storage — `#call` takes everything it needs and returns everything it produces — and the 32-thread concurrent-call test exercises that harness against the fake. Concurrency safety is a property of an implementation, and this phase ships none |
| `SEAM-13` | SHOULD | ✅ | 4, 9 | Cancellation reaches a transport as the third argument, an ordinary `Dexpace::Cancellation` value and never an ambient interrupt; a transport honours it by re-checking `#cancelled?` at every resume point, and `#check!` is the one-call form of that check. The token, `.none`, `.source`, `.any` and `#on_cancel` are built and tested (`dexpace/cancellation_test.rb`, `dexpace/cancellation/source_test.rb`); `FakeTransport` records the token it was handed (`dexpace/bridge/async_over_test.rb`). Phase 8's adapters honour it; `dexpace-conformance` asserts it |
| `SEAM-14` | MUST | ✅ | 2, 9, 10 | `Dexpace::Closeable`: a latch flipped under a mutex held across the flip only, `#release` run exactly once under 16-way contention, a raising `#release` leaving the latch flipped and propagating once, ownership a frozen construction-time boolean so a borrowed resource latches but is never released, and a loud `Dexpace::SeamError` for an includer that never initialised the latch. Both transports this phase ships — `Bridge::AsyncOver` and `Bridge::SyncOver` — include it with `owned: false`, answer `#close`/`#closed?`/`#owned?`, release nothing and stay usable after close (`dexpace/closeable_test.rb`, `dexpace/bridge/async_over_test.rb`, `dexpace/bridge/sync_over_test.rb`) |
| `SEAM-15` | MAY | ✅ with a named gap | 1, 9 | The MAY is taken and documented: `Dexpace::ClosedError` (Task 1), and the rule — stated in `Dexpace::Transport`'s YARD block and in the class's own — that **an owning transport raises it from a later send** while a borrowing wrapper closes nothing and stays usable (`XCUT-22`). What ships is the class and the rule and **no raise site**: `Dexpace::ClosedError` is referenced nowhere in `lib/` outside its own file, and the tests assert its ancestry and its `rescue Dexpace::Error` catch (`dexpace/error/closed_error_test.rb`, `dexpace/transport_test.rb`). Phase 8's adapters are the first owners; `dexpace-conformance` asserts the raise per adapter (phase 8a's `TransportSuite`) |
| `SEAM-16` | MUST | ✅ | 5, 6, 10 | `Dexpace::AsyncTransport` returns a `Dexpace::Async::Future`. Settling means writing exactly one of a response or an error — `Settlement#initialize` refuses both and neither, and `cancelled` implies an error — so a null success is unrepresentable; a delivered response is never closed by the pivot, and `#cancel` after settlement is a no-op that closes nothing (`ASYNC-20`). `#value` blocks on a `Thread::Queue` pop rather than spinning, proven by a producer that sleeps first, and honours a cancellation token by settling the future as cancelled and raising `Dexpace::CancelledError` carrying the reason (`dexpace/async/settlement_test.rb`, `dexpace/async/completer_test.rb`, `dexpace/async/future_test.rb`, `dexpace/async_transport_test.rb`) |
| `SEAM-17` | SHOULD | ✅ | 5, 6 | The pivot is core-owned and dependency-free (design §10.3, roadmap cross-phase obligation 5): `Completer` holds the state, `Future` is a facade over it, and the third-party async types stay out of every public signature — `gates:rbs_surface` is load-bearing for the first time and was watched go red on a temporary `Async::Task` in `sig/`. The scheduler-transparency claim is asserted rather than restated: a `Fiber.schedule`d consumer blocking in `#value` routes through the probe scheduler's `#block`/`#unblock` hooks for a `Thread::Queue`, and a settled future touches the scheduler not at all (`dexpace/async/future_scheduler_test.rb`, `test/support/probe_scheduler.rb`, with `#fiber_interrupt` defined so 4.0.6 emits no warning). The constant-shadowing proof defines a stand-in `Dexpace::Async::Thread` and re-runs the pivot; with one `::` removed it fails `NameError: uninitialized constant Dexpace::Async::Thread::Mutex` and the cop flags the same line (`dexpace/async/future_shadowing_test.rb`, `.rubocop/cops/dexpace/qualified_core_constant.rb`) |
| `SEAM-18` | MUST | ✅ | 4, 9, 10, 11 | `Dexpace::Transport.async_over(transport, executor:)` — the executor is required, refused without `#post`, and there is intentionally no default — and `Dexpace::AsyncTransport.sync_over(transport)`, both in `Dexpace::Bridge` (P2-13). Clause by clause: the original failure comes back as the identical object, because the pivot never wraps; the blocking wait honours interruption by cancelling the in-flight future and raising `Dexpace::CancelledError` with the reason (P2-4); per-call options arrive at the wrapped transport as the exact object; a raise from `#post` itself is normalised to the failure channel; an async transport handed to `async_over` raises `Dexpace::SeamError` at the first send rather than delivering a future of a future; a token already cancelled when the posted block runs never reaches the transport; and two blocking waits on one token both unblock when it is cancelled, which is the guard `#on_cancel`'s per-registration flag exists for. Nine deliberate breaks were each run red and restored (see "Guards run red" below) (`dexpace/bridge/async_over_test.rb`, `dexpace/bridge/sync_over_test.rb`) |
| `SEAM-19` | MUST | ✅ | 12 | `Dexpace::Serde.conforms?` requires `#media_type` among the six seam methods; the module supplies no default and answers no `media_type` itself, so a codec that forgets it fails conformance — and `Serde.missing_methods` names which of the six it forgot — rather than stamping a wrong `Content-Type`. That the value is correct is phase 7's (`dexpace/serde_test.rb`) |
| `SEAM-20` | MUST | ✅ | 12 | All four allocation profiles are in the contract — `#dump_string`, `#dump_bytes`, `#dump_to(value, sink)` and `#dump_into(value, buffer, offset:)` — and `#dump_bytes` differs from `#dump_string` exactly in the `Encoding::BINARY` tag (design §10.13). The streaming variant never closes the caller's sink and the buffer variant raises `IndexError` on overflow, asserted against `FakeCodec`; `#dump` is a permitted shorthand and deliberately not in the contract. The encode failure type is `Dexpace::Serde::SerializationError` (`dexpace/serde_test.rb`, `dexpace/serde/serialization_error_test.rb`) |
| `SEAM-21` | MUST | ✅ | 12 | `#load(source, witness)` reads to EOF and never closes the caller's source, asserted against the fake; a genuine stream I/O error is not reclassified — `Dexpace::Serde::Error` is deliberately outside `IOError` — and the decode failure type is `Dexpace::Serde::DeserializationError` (`dexpace/serde_test.rb`, `dexpace/serde/deserialization_error_test.rb`) |
| `SEAM-22` | MUST | 🚫 mechanism; surviving clause ✅ | 12 | The reflective generic type capture is a JVM artefact, replaced by the witness protocol (design §10.14), which is §7.3's and phase 7's. The clause that survives the substitution is fixed here: `#load` takes an explicit witness and there is no witness-less overload — `FakeCodec.new.load(source)` is an `ArgumentError` (`dexpace/serde_test.rb`). Read out of appendix C row 28 verbatim, as the roadmap and the design require |
| `SEAM-23` | MUST | ✅ | 12 | `Dexpace::Serde::Error < ::StandardError` including `Dexpace::Error`, with `SerializationError` and `DeserializationError` beneath it: a class root, inverting phase 1's module root deliberately (P2-2), open for an adapter to subclass, caught by `rescue Dexpace::Error`, and chaining the backing library's failure as `#cause` when raised from inside its rescue. Inside `module Dexpace::Serde` a bare `Error` is the seam root, asserted, which is why core writes `Dexpace::Error` fully qualified (`dexpace/serde/error_test.rb`) |
| `SEAM-24` | SHOULD | ⏳ | — | Post-v1, riding on `dexpace-async-async` — `docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level requirements declined for v1, the `SEAM-24` entry. Tasks 4 and 5 fix the contract its bidirectional mapping will map: `Dexpace::Cancellation` in one direction and `Completer#on_cancel` in the other |
| `SEAM-25` | MUST | ✅ with a named gap | 2, 9, 10 | The idempotent, ownership-aware release is `Dexpace::Closeable` (Task 2) and both bridges take it (Tasks 9, 10): only the first close runs `#release`, a caller-supplied transport or executor is never touched. The clause "**and emits the lifecycle event**" has no event to emit until §8.1's instrumentation facade exists — emitted by phase 8b, Tasks 6 and 10 (`docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter.md`), harnessed by phase 9, Task 11 (`docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance.md`). Named rather than claimed |
| `SEAM-26` | MUST | ✅ | 13, 14 | `Dexpace::Operation = Data.define(:method, :template, :projections)` including `Dexpace::Model`: `private_class_method :new`, a validating `.build(method:, template:, projections: {})`, `method` coerced through `Dexpace::Method.of`, the template a frozen `String`, the projections table copied and deep-frozen through `Model.own`. A parameterless GET is the default construction. Validation at construction: a projection is a `[target, wire name]` pair, the target one of `:path`/`:query`/`:header`/`:body` (the error names all four), the wire name non-empty, at most one body projection, and the set of `:path` wire names equal to the set of `{name}` placeholders in both directions. `#with` re-validates on the 3.2 floor through phase 1's `Model#with`. The body is carried, not encoded — the input object arrives on the request as itself (`dexpace/operation_test.rb`, `dexpace/operation_build_request_test.rb`) |
| `SEAM-27` | MUST | ✅ | 14 | `#build_request(base_url:, inputs: {})`. Path values go through phase 1's `PercentEncoding.encode_component`, so `"a/b"` becomes `a%2Fb` and never a second segment — a 40-sample property over an alphabet including `/`, `?`, `#`, `&`, a space, `%` and invalid UTF-8 asserts the assembled URL re-parses through `URL.parse!` with exactly one segment added; a `nil` path input is missing and raises naming the input key and the placeholder, `false` is a value. The query is phase 1's `Query#encode`, one parameter per value of a repeated projection, a structured value refused rather than rendered as an inspect string. Headers go through the outbound `Headers::Builder`, so a CRLF is rejected at assembly. The composition is hand-built (P2-3): the specification's own example `https://host/c?sig=abc` + `/pets` + `limit=1` → `https://host/c/pets?sig=abc&limit=1`, trailing and leading slashes normalised to one separator, an empty operation path leaving the base untouched, a dangling `&` dropped, already-encoded octets surviving verbatim, a fragment on the base rejected naming it, and the base URI left untouched. The three places a stdlib `URI` error could otherwise escape the composition are closed (review rounds 2 and 3): a template whose literal text between placeholders is not an RFC 3986 path — `/x?y`, `/a b`, `/pets/ü`, `/100%`, a bare `%`, `<`, `[`, a quote, a tab, a newline — is refused at construction naming the template, a base with no hierarchical part to compose onto (`mailto:x@y`, `urn:isbn:123`) is refused naming the base, and a base whose query is not RFC 3986 — `?sig=100%`, `?;~%`, `?a=%z`, `?a=[1]`, all of which `URL.parse!` admits — is refused naming the base whether or not an operation query is appended (`?sig=100%25` composes); two 200-sample properties, one over templates drawn from pchars, `/`, `?`, `#`, `%`, braces, a space and `ü` and one over base queries drawn from the same plus `&`, `=`, `;`, `[` and `]`, assert that every input either fails as `Dexpace::InvalidArgumentError` or composes a URL that re-parses to itself. `URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets")` was re-verified as `https://host/pets` on 3.2.11 and 4.0.6 during the build (`dexpace/operation_build_request_test.rb`) |
| `SEAM-28` | MAY | ⏳ | — | Phase 5c, Task 4 (`docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics.md`), over phase 4a, Task 7's `RequestContext#operation_name` — a target this phase supplied. Both halves need machinery phase 2 does not have: the context chain (`CTX`, phase 4) and a consumer for the identifier (phase 5). Read out of appendix C row 34 verbatim |
| `SEAM-29` | MUST | ✅ in phase 1 | — | A cross-reference row: phase 1's `Dexpace::Model.required!` (the uniform `<name> is required` message, which `Operation.build(method: nil, …)` and `(template: nil)` produce) and `Dexpace::Builder` (the generic contract `Operation#build_request` builds through, via `Request::Builder`). Not re-satisfied here; `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-checklist.md` is its row |
| `SEAM-30` | MUST | ✅ | 5, 11 | `Completer#fulfil` on an already-settled future returns `false` **and** closes the response it was handed, exactly once, through `Dexpace.close_quietly` — so the rule holds for every adapter that settles through a `Completer`, and for a mapped value that loses the race in `Future#then`. `Bridge::AsyncOver`'s posted block is the one place phase 2 itself produces a response nobody will receive: it re-checks the token after the send and closes the response before settling through the failure channel, and it checks before dispatch too, so a token already cancelled never reaches the transport. A registry build that loses to a concurrent `#install` is closed the same way (`dexpace/async/completer_test.rb`, `dexpace/async/future_test.rb`, `dexpace/bridge/async_over_test.rb`) |

Thirty rows: 23 ✅ (two of them with a named gap — `SEAM-15`, `SEAM-25`; one in phase 1 —
`SEAM-29`), 3 ⏳ (`SEAM-12`, `SEAM-24`, `SEAM-28`), 3 🚫 (`SEAM-3`, `SEAM-4`, and `SEAM-22`'s
mechanism, whose surviving clause is ✅), 1 N/A (`SEAM-10`, with the version-skew guard built in
its place) — 23 + 3 + 3 + 1 = 30, recounted from the table. `XCUT-13`, `XCUT-22` and `XCUT-23`
are implemented here — the latch, the ownership rule and the deterministic three-registry
resolution — and are phase 9's to disposition; none is a row.

## What was built

Twenty new `lib/` files under `gems/dexpace-core/lib/dexpace/` — exactly the design's Module Layout,
including `hooks.rb` and the two `bridge/` files — each with a `sig/` mirror (twenty, one more than
the design's nineteen: `sig/dexpace/hooks.rbs` exists, see deviation 1) and, for every file but
`hooks.rb`, a `test/` mirror (nineteen), plus five further suites — `async/future_scheduler_test.rb`,
`async/future_shadowing_test.rb`, `registry_version_test.rb`, `operation_build_request_test.rb`,
`seam_surface_test.rb` — and eight files under `test/support/`: the three fakes the roadmap's
constraint 4 asks for (`fake_transport.rb`, `fake_async_transport.rb`, `fake_codec.rb`) with their
companions one class per file (`options_ignoring_transport.rb`, `inline_executor.rb`,
`incomplete_codec.rb`), `probe_scheduler.rb` and `warning_capture.rb`. The cop the design's §9
addendum A1 calls the sixth — the seventh in the tree, phase 1 having added `Dexpace/NoKeywordSplat`
after the design was written —
`.rubocop/cops/dexpace/qualified_core_constant.rb`, with seventeen cases in `.rubocop/test/cops_test.rb`.
The entry file `lib/dexpace.rb` gained the twenty `require_relative`s as one block in dependency
order; `sig/dexpace.rbs` needed nothing. `require "uri"` and `require "strscan"` are still the only
`require`s outside `require_relative`, both phase 1's; the gemspec still has zero `add_dependency`
lines.

The gates, all seventeen, on **4.0.6** (`bundle exec rake`, 2026-09-15): green, exit 0 —
`cops:test` 82 runs, `steep` no type error over the strict `core` target, `test:gems` 529 runs /
3376 assertions with **99.93% line coverage (1521/1522)** against the 80% floor (the one uncovered
line is the race-only branch of the registry's claim swap, reachable only when a resolution
completes between a resolver's unsynchronised read and its locked claim), `test:gates` 128 runs, the
nine `gates:*` tasks, `yard` 100.00% documented, `bundler_audit` clean. The same caveat about
`rubocop` that phase 1 recorded: run through `rake` from this worktree it inspects 9 files, because
the parent checkout's `.rubocop.yml` excludes `.claude/**/*`; run as
`bundle exec rubocop --fail-level=convention --ignore-parent-exclusion` it inspected **179 files, no
offenses**, and that is the run these rows rest on (already on phase 10's inbound list from phase 1).

`test:gems` green on **3.2.11** (529 runs, 99.93% line coverage), with its own lockfile resolved
fresh; the seeded order-independence runs are recorded in the roadmap's status note. The 3.2.11 run
is the one that proves phase 1's `Model#with` still carries this phase's two public `Data` types —
`Settlement` and `Operation` both assert that `#with` re-validates.

The surface manifest `test/fixtures/surface/dexpace-core.txt` grew from 212 to 318 lines through
`bundle exec rake surface:regenerate`, once, after Task 15; the diff was read line by line and is
exactly the 106 public constants and methods the twenty files define. Checked specifically: no
`REGISTRY` constant appears (all three are `private_constant`), no `Dexpace::Hooks`,
`Dexpace::Cancellation::Subscription` **does** appear, and `Registry::State`, `Registry::Claim`,
`Cancellation::Source::State`, `Operation::PLACEHOLDER`, `Operation::Validation` and
`Operation::Composition` do not — phase 0's generator walks `constants(false)`, which honours
`private_constant`. The four adapter manifests each lost one line — `Dexpace::Transport`,
`Dexpace::Serde` or `Dexpace::Async` — because core now defines those namespaces and an adapter's
manifest is what it adds beyond core's; the gate test that had pinned the phase-0 shape is corrected
(deviation 24). `gates:sig_diff` still prints "no release tag yet". `gates:rbs_surface` was watched
go red on a temporary `Async::Task` in `sig/dexpace/async/future.rbs` and green once removed.

## Guards run red

Every concurrency guard the plan's planning-verification table lists, plus Task 6's shadowing break
and Task 11's eight, was run red by reverting its fix in the built tree, on 4.0.6, and restored;
each hang was run under the coreutils `timeout`. What each said:

| Fix reverted | Guard | What it said |
|---|---|---|
| `#complete_resolution` releases the claim on `rescue StandardError`, not in `ensure` | `registry_test.rb`, `Reentrancy` | "the registry wedged into a spin instead of re-evaluating" (the join timeout) |
| `#swap`'s `ensure` restores the captured snapshot wholesale | `registry_test.rb`, `Swap` | "swap restored a closed gate and wedged the registry" |
| `#swap`'s `ensure` restores `factories` from the snapshot | `registry_test.rb`, `Swap` | "Expected: `[:key]`, Actual: `[]`" |
| `#resolve` does not check the claim's owner | `registry_test.rb`, `Reentrancy`, three tests | run alone: "`[Dexpace::SeamError]` exception expected, not `Class: <fatal>`" (Ruby's deadlock detector); the trio together: a hang, killed by `timeout` after 120 s |
| the factory call moves back under `@write` | `registry_test.rb`, `Concurrency`, two tests | `ThreadError: deadlock; recursive locking` |
| `Completer#await` does not detach what it armed | `cancellation_test.rb`, `Subscriptions` | "the await armed a hook on a client-lifetime source and never detached it. Expected: 0" |
| `#request_cancel` notifies the abort hooks before publishing the outcome | `async/completer_test.rb`, `Hooks` | "cancellation must always publish an outcome" |
| `Hooks.notify` becomes a bare `each` in `Source#cancel` | `cancellation_test.rb`, `Subscriptions` | "Expected: `[:first, :third]`, Actual: `[:first]`" |
| `Hooks.notify` becomes a bare `each` in `Completer#settle` | `async/completer_test.rb`, `Hooks` | "Expected: `[:first, :third]`, Actual: `[:first]`" |
| `Cancellation.over`'s `is_a?(Source)` guard | `cancellation_test.rb`, `Composition` | "`Dexpace::InvalidArgumentError` expected but nothing was raised" |
| `deliver`'s delivery branch as a method-level `else` | `bridge/async_over_test.rb` | "the future never settled and `#value` would block" (with a `nil`-returning transport, deviation 12) |
| `#on_cancel`'s per-registration guard becomes one token-level flag | `bridge/sync_over_test.rb` | "a waiter never unblocked: SEAM-18's interruption clause is violated", after the five-second join — and with the token still frozen the break cannot even be written: `FrozenError` |
| one `::` dropped from `completer.rb` | `async/future_shadowing_test.rb` | `NameError: uninitialized constant Dexpace::Async::Thread::Mutex`; the cop flags the same line |
| `options` dropped from `AsyncOver#deliver`'s call | `bridge/async_over_test.rb` | "Expected nil to be the same as `#<data Dexpace::RequestOptions …>`" |
| the failure wrapped in a `RuntimeError` | `bridge/async_over_test.rb` | "`[IOError]` exception expected, not `Class: <RuntimeError>`" |
| the check-after-resume branch deleted | `bridge/async_over_test.rb` | "`Dexpace::CancelledError` expected but nothing was raised" |
| `future.value` without `cancellation:` in `SyncOver#call` | `bridge/sync_over_test.rb` | a hang, killed by `timeout` after 120 s |
| the `rescue` around `@executor.post` removed | `bridge/async_over_test.rb` | `IOError: the pool is shut down` escaping `#call` |
| `#deliver`'s `Dexpace::Async::Future` guard deleted | `bridge/async_over_test.rb` | "`Dexpace::SeamError` expected but nothing was raised" |
| `#deliver`'s pre-dispatch check deleted | `bridge/async_over_test.rb` | "check-before-dispatch: the send was never made. Expected `[[:request, nil, …]]` to be empty" |
| `>=` on the minor changed to `==`, then to `>` | `registry_version_test.rb` | the grid: two failures ("Expected: true, Actual: false"); the own-version test: three — **but only once the grid varied the running version** (deviation 8) |

Review round 1 (2026-09-15) added two tests that were run red against the code branch before its
fix landed, on 4.0.6, and green on 4.0.6 and 3.2.11 after it:

| Fix not yet applied | Guard | What it said |
|---|---|---|
| `accepts_positionals?` ignores `:keyreq` | `registry_test.rb`, `Callable`; `transport_test.rb`; `async_transport_test.rb` | "callable? refuses a required keyword and admits the optional keyword shapes: Expected true to not be truthy" |
| `render_headers` renders a `nil` input as `""` | `operation_build_request_test.rb`, `Projections` | "Expected `#<data Dexpace::Headers values={"x-trace" => [""]} …>` to not include "X-Trace"" |

Review round 2 (2026-09-15) added three more, run the same way — red against an export of the
code branch's tip before the fix, green on 4.0.6 and 3.2.11 after it (deviation 28):

| Fix not yet applied | Guard | What it said |
|---|---|---|
| the template literal is not checked against the path grammar | `operation_test.rb` | ""/x?y". `Dexpace::InvalidArgumentError` expected but nothing was raised" |
| `validated_base` admits an opaque base | `operation_build_request_test.rb` | "mailto:x@y. `[Dexpace::InvalidArgumentError]` exception expected, not `Class: <URI::InvalidURIError>` Message: <"path conflicts with opaque">" |
| both, under the 200-sample template property | `operation_build_request_test.rb`, `Templates` | `URI::InvalidComponentError: bad component(expected absolute path component): /c/F/ #ü` escaping `#build_request` |

Review round 3 (2026-09-15) added three more, run the same way (deviations 29 and 30):

| Fix not yet applied | Guard | What it said |
|---|---|---|
| `validated_base` admits a base query ending in a bare `%` | `operation_build_request_test.rb` | "https://host/c?sig=100%. `[Dexpace::InvalidArgumentError]` exception expected, not `Class: <URI::InvalidURIError>` Message: <"invalid percent escape: %&l">" from `operation.rb:318` `Composition#compose` |
| the same, under the 200-sample base property | `operation_build_request_test.rb`, `Bases` | `URI::InvalidURIError: invalid percent escape: %&l` escaping `#build_request` |
| `Registry#register` and `#install` build their conflict message under `@write` | `registry_test.rb`, `Reentrancy` | "`[Dexpace::InvalidArgumentError]` exception expected, not `Class: <ThreadError>` Message: <"deadlock; recursive locking">" from `registry.rb:120` `Registry#register`, and from `registry.rb:144` via `conflict!` inside `#install`'s block |

## Audit groups run

The phase-start pair first, at implementation: `--section conflicts --brief` returns the six
harvested conflicts, every one `[overridden by notes/…]`, and nineteen note-side entries; `--origin
note --brief` returns fifty-two note entries across twenty files, none contradicting this plan.
`--prefix-info SEAM` reports 30 IDs, 28 substantive, 0 roll-ups; `--gaps SEAM` names `SEAM-22` and
`SEAM-28` as appendix-C only, with the `grep` line, and both were read out of appendix C verbatim
(rows 28 and 34). `--req` was run for each task's IDs before that task; none came back a roll-up. The
six groups the design ran at planning are recorded there with their results; at implementation the
two that bite were re-checked against the built code rather than re-run in full:

| Group | Result at implementation |
|---|---|
| Fiber scheduler, thread safety | Clean against the built code: every mutex is held across a flag flip or a snapshot swap and nothing else (`Closeable#close`, `Cancellation::Source#cancel`, `Cancellation#once_only`, `Completer#settle`, `Registry#register`/`#swap_in`/`#take_or_join_claim`/`#swap`/`#complete_resolution`/`#hand_out`); no factory, predicate, callback, `warn` or — since review round 3, deviation 30 — conflict message's `#inspect` runs under one; the pivot's wait and the registry's gate are both `Thread::Queue#pop`; `Timeout.timeout`, `Thread#raise` and `Thread#kill` appear nowhere and phase 0's cop stands guard |
| Public API surface | One rule bit at implementation and is answered in place: `module-organization/1828a984` (one public constant per file) is honoured by the twenty files; the two extra `private_constant` modules inside `Operation` and the three snapshot `Data` types are not public constants. `api-design/b0e18938` is why every public name that arrived by accident is in P2-11 |

`data-modeling/677b01de`'s `Data`-everywhere rule and P2-9's boundary held: the three snapshots are
`Data` without `Model`; the two public `Data` types — `Settlement`, `Operation` — follow phase 1's
construction rule without exception. The four notes the design filed stand as written; no fifth was
needed.

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate. One
changes a gate's own test in the corrected direction (item 24).

1. **`sig/dexpace/hooks.rbs` exists.** The plan says `lib/dexpace/hooks.rb` gets no `sig/` mirror
   because `Dexpace::Hooks` is a `private_constant`. Strict Steep on the `core` target checks every
   file under `lib/` and refuses an undeclared module, and the target never relaxes; so the module
   and its one method are declared, with a comment saying the declaration exists for Steep and the
   privacy lives in `lib/`. Phase 1 declared its private constants in `sig/` for the same reason.
   `Dexpace::Hooks` is still not public API: not in the surface manifest, unreachable from outside
   `module Dexpace` (asserted in `dexpace_test.rb`).
2. **`Completer#settle` steals both callback lists under the lock that publishes the outcome, and
   `#request_cancel` is one `settle` call.** The plan's `#request_cancel` took the abort hooks under
   the mutex, then settled, then notified — leaving a window in which a concurrent `#fulfil` wins
   the race and the producer's abort hook still fires. As built the hooks are taken in the same
   swap that writes the outcome, so an abort hook fires only when the cancellation actually won;
   on a cancellation the abort hooks run first and the settle callbacks run whatever the abort
   hooks did (an `ensure`). The "outcome published before any hook" guard was run red the same way.
3. **The cop's cases are a nested class, `CopsTest::QualifiedCoreConstantTest`**, with its
   own tables, rather than rows appended to phase 0's. Seventeen more rows put `CopsTest` at 147
   lines against `Metrics/ClassLength`'s 100, whose inner-class exclusion is the sanctioned shape
   (phase 1's test files do the same). Nine rejected and eight accepted cases, the four the plan's
   review added included.
4. **Test files nest a class per behaviour group** — `cancellation_test.rb` (`Composition`,
   `Subscriptions`), `async/completer_test.rb` (`Hooks`), `async/future_test.rb` (`Then`),
   `registry_test.rb` (`Callable`, `Installation`, `Concurrency`, `Reentrancy`, `Swap`), `operation_test.rb`
   (`Projections`), `operation_build_request_test.rb` (`Projections`) — for the same cap.
5. **The fakes are one class per file.** `Style/OneClassPerFile` refuses a second top-level class,
   so `OptionsIgnoringTransport`, `InlineExecutor` and `IncompleteCodec` have their own files
   beside the three fakes; suites require the ones they use.
6. **`Dexpace::Registry` is reshaped internally, not in contract:** `#resolve` is a loop over an
   unsynchronised read, a `#take_or_join_claim` swap returning the claim and whether it is fresh,
   and a `#wait_on` that raises the re-entrancy error or parks; `#conflict!`, `#sole_key`,
   `#warn_replaced` and `.accepts_positionals?` are extracted, all for the metric cops. The class
   carries one `Metrics/ClassLength` directive with its reason (one snapshot, one class). The
   `resolving` slot holds a `Claim` (gate plus owning `Fiber`), as the plan's amendment says.
   `assert_core_version!` refuses a non-`String` `core:` (a `Symbol` that stringifies to `~> 0.0`
   would otherwise pass).
7. **`Dexpace::Operation`'s checks and composition live in two `private_constant` modules,
   `Operation::Validation` and `Operation::Composition`**, so the descriptor's body reads as the
   contract and each half is reviewable alone — the split Tasks 13 and 14 draw — and the class
   stays under the length cap. `validated_base` carries the fragment rule and, since review
   round 2, the no-hierarchical-part rule; `Validation.literal!` holds the brace check and the
   path-grammar check on the template's literal text (deviation 28). A template must be a
   `String`; a projection must be a two-element `Array`. Both modules are declared in `sig/` and
   absent from the manifest.
8. **The version-skew grid varies the running version.** With every gem at `0.0.0` the plan's
   grid — twenty-four requirements against the one running version — cannot tell `>=` from `==`
   on the minor: `~> 0.0` is the only satisfiable form, and the plan's own break-it step (`>=` to
   `==`) stayed green. `registry_version_test.rb` swaps `Dexpace::VERSION` for the duration of a
   block through `remove_const`/`const_set` (no "already initialized constant" warning, restored in
   an `ensure`, asserted restored) over six running versions, and adds the exhaustive 6 × 12 square
   beside the seeded grid. Both breaks then go red.
9. **`Cancellation#on_cancel` builds its per-registration guard through a private `#once_only`
   helper and yields to the block**, rather than a `block.call` inside a hand-rolled lambda
   (`Performance/RedundantBlockCall`); `yield` inside a lambda that outlives the method reaches the
   captured block on 3.2.11 and 4.0.6, verified. `NONE = new([])` — `#initialize` freezes the list
   — replaces the plan's `new([].freeze)`, which strict Steep refuses as an unannotated empty
   literal.
10. **`.rubocop.yml`'s `Include:` for the cop names `lib/dexpace/serde.rb` as a third
    pattern.** The seam module itself reopens `Dexpace::Serde` from one directory up, so a bare
    `JSON` there is the same hazard as one under `serde/`; verified the cop fires on it. Broadened
    by one file, never narrowed.
11. **Two `Naming/PredicateMethod` directives, each with its reason** — `Cancellation::Source#cancel`
    and `Completer#settle` — because the design fixes `#cancel`, `#fulfil`, `#fail` and
    `#request_cancel` as commands that report whether they took effect, and a `?` suffix would
    misname a mutator as a query; the cop is a `NewCops`-enabled one phase 0 had not met. The
    probe scheduler's `#block` carries the same directive for Ruby's own hook name.
12. **The method-level-`else` guard uses a transport that returns `nil`**, not the plan's
    `:not_a_token`. With the pre-dispatch check at the top of `#deliver`, `:not_a_token` raises in
    the body and is rescued, so the plan's scenario passes under the break; a `nil` response trips
    `Settlement`'s "exactly one of response or error" inside `Completer#fulfil`, which is
    `SEAM-16`'s null-success rule arriving as a real failure — and the break then leaves the future
    unsettled, as the guard says.
13. **`Future#value` guards a `nil` outcome with `Dexpace::SeamError`.** Steep cannot see that
    `#wait` returns only once the outcome is written; the branch is unreachable and costs one line.
    `Future#then`'s forwarding is two private methods, `#forward` and `#map`, so the rescue sits
    around the block call alone.
14. **`bool`, not `boolish`, in `registry.rbs`.** `gates:rbs_surface` reads RBS's built-in
    `boolish` alias as a name outside the allowlist; the gate is right that the alias is not a
    `Dexpace::` constant, and `bool` is the type anyway.
15. **The two `require_relative` blocks the plan placed differently are one block**, appended
    after phase 1's, in Task 15's dependency order (the plan's Task 1 said "immediately after
    `error/invalid_argument_error`"; Task 15's order wins).
16. **`Completer#on_cancel` runs the block through `yield` and a `#cancel_reason` helper**, so a
    cancelled settlement's reason is read off its `Dexpace::CancelledError` under a type check
    rather than off an `Exception?`.
17. **The three seam suites clean a registration out of the private registry in an `ensure`.**
    A registration is process-global and kept across `#swap` by design, so a test of the
    module-level `register` reaches into `REGISTRY`'s snapshot afterwards to remove its key; an
    install is exercised inside a `swap` block instead, because an install is part of the override
    and restored with it.
18. **Eager type checks the plan did not have**, in the shape of phase 1's Task 1 rule:
    `Future.new` refuses a non-`Completer`, `Completer#fail` a non-`Exception`, `Completer#await`
    a non-token, `Cancellation.over`/`.any`/`#merged_with` the wrong class, `Operation` a
    non-`String` template and a non-pair projection; each is the SDK's error rather than a
    `NoMethodError` from inside the seam.
19. **A second-resolver test** (`registry_test.rb`, `Concurrency`) holds the factory open until a
    waiter is known to be parked on the claim's gate, because the 32-thread test cannot promise a
    waiter ever parks under the GVL — the gate's wait path had no coverage without it.
20. **`callable?` admits an object whose `respond_to?(:call)` is true but whose `#method(:call)`
    raises `NameError`**, asserted; the plan's rescue existed but no test reached it.
21. **`serde/serialization_error_test.rb` and `serde/deserialization_error_test.rb` exist**, so
    every `lib/` file but `hooks.rb` has its one-for-one mirror as the design states; the plan
    folded both into `serde/error_test.rb`.
22. **`Subscription#detach` guards a `nil` hook**, the `.none` handle's, rather than calling
    `off_cancel(nil)` on an empty source list.
23. **A nil query input contributes nothing**, exactly as an unsupplied one; the plan's
    `Array(inputs.fetch(key))` already behaved so, and the test says why the path side treats
    `nil` differently.
24. **`test/gates/surface_snapshot_test.rb`'s "starts at the namespace it shares" case is
    corrected to the property its own comment states.** It asserted that each adapter's manifest
    *begins with* the shared namespace line (`Dexpace::Transport`, `Dexpace::Serde`,
    `Dexpace::Async`) — true in phase 0 only because core did not define those modules. Core now
    does, so an adapter's contribution begins at its own constant inside the namespace and the
    namespace line belongs to core's manifest, which is the gate's contract ("what that gem adds
    beyond core's"). The test now asserts the first line is *inside* the shared namespace, that
    the namespace line is absent, and that `Dexpace` is absent; it goes red against the phase-0
    manifests and green against the regenerated ones. On the code branch, because that branch's
    `test:gates` must be green on its own tree.
25. **Run counts exceed the plan's.** `test:gems` is 529 runs where the plan's built-tree run was
    179; Minitest is 5.27.0 on 4.0.6 here, not the 6.0.0 the plan mentions, and assertion counts
    match across 3.2.11 and 4.0.6.
26. **`Registry.accepts_positionals?` refuses a required keyword** (review round 1). The design's
    stated predicate — "required count ≤ 3 and (a rest parameter is present or required +
    optional ≥ 3)" — omits keywords, and the plan reproduced it, so
    `->(request, options, cancellation, must:) {}` passed `Transport.conforms?` and
    `AsyncTransport.conforms?`, was accepted by `#install` and `#register`, and raised Ruby's
    `ArgumentError: missing keyword` from inside the seam at the first send: failure at use where
    the predicate exists to fail at registration, and a stdlib error where the seam promises
    `Dexpace::InvalidArgumentError`. One clause (`return false if kinds.include?(:keyreq)`) closes
    it; an optional keyword, a keyword rest and a block parameter leave the three-positional call
    intact and stay admitted. Verified on 3.2.11 and 4.0.6; the design's "as built" notes record
    the refinement. `registry_test.rb`'s three `callable?` tests moved into a nested `Callable`
    class for the 100-line cap (deviation 4).
27. **A `nil` header input is absent** (review round 1), exactly as deviation 23 made a `nil`
    query input, where the plan's `inputs.key?(key)` sent the header with an empty value: a
    generated client passing an unset optional header as `nil` would have emitted `X-Trace:`
    silently. The path side still makes `nil` an error, because a placeholder cannot be left out,
    and an empty `String` is a value on every side. `docs/sdk-documentation/seams.md` states the
    three readings together.
28. **A template literal that is not a URI path, and a base with no hierarchical part, are
    refused as `Dexpace::InvalidArgumentError`** (review round 2). The design's construction-time
    checks were brace balance and placeholder/projection agreement, and its composition row maps
    "resolving to a malformed URL" to `URL.parse!` — the base only. The literal text between
    placeholders was never checked, so `Operation.build(method: :get, template: "/x?y")` — a
    generator putting a literal query in the template — and `"/a b"`, `"/pets/ü"`, `"/100%"`
    constructed and then raised `URI::InvalidComponentError` from `URI::Generic#path=` inside
    `Composition.compose` at the first `#build_request`: a stdlib error, outside `rescue
    Dexpace::Error`, where the plan's global constraints promise `InvalidArgumentError` for a
    malformed template and `SEAM-27` a context-bearing error. Path *values* were never at risk
    (`encode_component` yields pchars; the 40-sample property proves it). `Validation.literal!`
    now checks the template with its placeholders removed against RFC 3986 `path` — every
    character a pchar or `/`, every `%` opening a two-hex-digit escape, the grammar `#path=`
    enforces at assembly — at construction, naming the template; `/a%20b`, `pets` and `""` pass
    as before. The set is spelled out in a per-pattern-timeout `Regexp` rather than borrowed from
    `URI`, because phase 1's `URL` is the one place core reaches `URI`. The probe that found the
    literal found its sibling: an opaque base (`mailto:x@y`, `urn:isbn:123`) is absolute, so
    `URL.parse!` admits it, and carries no fragment, so the one rule `validated_base` had let it
    through to leak `URI::InvalidURIError: path conflicts with opaque` from the same `#path=`;
    `validated_base` refuses it beside the fragment, naming the base (`#hierarchical?`, which the
    rbs stdlib signature declares). Verified identical on 3.2.11 and 4.0.6 before and after; the
    red runs are recorded in the tests commit. No rescue was added to `Composition.compose`, on
    the claim that with both inputs validated it could not raise — a claim round 3 found false on
    the query side (deviation 29), and which now rests on both writers' grammars rather than on
    the path side alone.
29. **A base URL whose query is not RFC 3986 is refused as `Dexpace::InvalidArgumentError`**
    (review round 3), before anything is composed onto it. Deviation 28 validated the template
    literal and the opaque base and then claimed the composition could not raise; the base's
    *query* was validated by nothing phase 2 owns. Phase 1's `URL.parse!` reaches
    `URI::Generic#query=`, whose percent check is `/(%\H\H)/` — a `%` followed by two *non-hex*
    characters — so a query ending in a bare `%` or in `%z` (`https://host/c?sig=100%`,
    `https://host/c?;~%`, `https://host/c?a=%z`) is accepted at parse time; `compose_query` then
    appends `&limit=1`, `composed.query=` sees `%&l` and `URI::InvalidURIError: invalid percent
    escape: %&l` escapes `#build_request` — a stdlib class, outside `rescue Dexpace::Error`,
    where `SEAM-27` requires a composition resolving to a malformed URL to be rejected with a
    context-bearing error and where deviation 28's round-2 property could not see it, because it
    fixes the base at `https://host/c?sig=1`. `Operation::QUERY_LITERAL` is RFC 3986 `query` —
    `PATH_LITERAL`'s set plus `?`, every `%` a two-hex escape — and `validated_base` checks the
    parsed base's query against it beside the fragment and hierarchical-part rules, naming the
    base. The check runs whether or not the operation query is empty, so a base malformed on its
    own (`?sig=100%` with no `limit`) is refused rather than composed into a malformed URL
    silently; `?sig=100%25` composes as before. The fix is validation and not the belt-and-braces
    `rescue ::URI::Error` round 1 offered, for the reason deviation 28 gave and with the argument
    it lacked: RFC 3986 `query` is strictly tighter than `#query=`'s check, the operation query is
    `Query#encode`'s and RFC 3986 by construction, and the `&` between them can complete no
    escape; on the path side the parser's `segment` set is `#path=`'s `ABS_PATH` set, the
    operation path is `PATH_LITERAL` literal plus `encode_component` values, and one `/` joins
    them — so neither writer can reach its raise, and `Composition.compose`'s comment now says
    so. Measured rather than argued as well: a 40,000-base fuzz over nine base shapes (`https`,
    `http:` with no authority, `ftp`, `file`, an IPv6 literal) and four operations, on 3.2.11
    and 4.0.6, 29,738 bases accepted by `URL.parse!`, 5,031 stdlib leaks before and 0 after,
    identical on both. The 200-sample `Bases` property — the base-varying twin of the `Templates`
    one, with a non-empty operation query so the append runs on every sample — pins it.
30. **`Registry#register` and `#install` raise their conflict outside the lock** (review round
    3). Both messages interpolate `#inspect` of two user objects — the incumbent and the rejected
    factory or provider — and both were built inside `@write.synchronize`, so a factory or
    provider whose `#inspect` reached back into the registry (an install, a registration) met
    `ThreadError: deadlock; recursive locking` instead of the documented
    `Dexpace::InvalidArgumentError`: the file's own rule that a synchronize body is a snapshot
    swap and nothing else, broken on its two conflict paths while `warn_replaced` already obeyed
    it. `#register`'s block now returns the incumbent and the raise follows it; `#install`'s swap
    moved into a private `#swap_in` that reports the conflicting incumbent and the handed-out
    flag out of the block, and `conflict!` takes the incumbent rather than the snapshot. A
    class's or a lambda's `#inspect` is trivial, which is why this was filed as a nit; the guard
    (`registry_test.rb`, `Reentrancy`) uses an object whose `#inspect` registers a second key.

## Findings routed

- **The plan's version grid is vacuous while every gem is at `0.0.0`** — fixed in place
  (deviation 8), no register.
- **`Naming/PredicateMethod`, `Performance/RedundantBlockCall`, `Style/OneClassPerFile` and the
  metric cops shaped the tree** in ways the plan's fences did not anticipate; each is answered in
  the file it bit (deviations 3–7, 9, 11) and none is a finding against a gate.
- **A phase-0 gate test pinned a phase-0 fact** (deviation 24) — repaired on the code branch,
  where the layering rule requires it; not a finding against phase 0's gate, whose contract held.
- **`rake rubocop` is vacuous in a worktree nested under the parent checkout's `.claude/`** —
  already the thirty-fourth phase-10 inbound bullet, from phase 1; the honest run is recorded above.

## Postponed work

The six items phase 2 postponed keep the owners the design's "Work Phase 2 Postponed, and Who Owns
It Now" section records — `close_quietly`'s two routes (phase 4b, Task 2; phase 5b, Task 14), the
`deadline:` keyword (phase 5a, Task 8), the fakes' move (declined by phase 8a), presence-gated
activation (`docs/first-release.md` § What v1 ships without), `Hooks.notify`'s dropped failures
(phase 4b, Task 2) and `SEAM-25`'s lifecycle event (phase 8b, Tasks 6 and 10; phase 9, Task 11) —
and were re-checked on 2026-09-15. The version-skew guard phase 0 postponed to this phase is built
(Tasks 7 and 8). The implementation postponed nothing further.
