# Phase 5a — Configuration and the Clock: Checklist

**Written at execution time, 2026-09-17, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The design and the plan were written on
2026-09-09 against phases 0–3's *plans* and phase 4's *designs*, on a machine that then had only
Ruby 3.4.10; phases 1, 2, 3a, 3b, 4a, 4b and 4c were then built and merged to `main` (PRs #40–#62),
every interpreter in the matrix was installed, and this phase was cut from `main` at `993c439`.
Where the plan's text and the built tree disagree the tree wins and this document records it.
Phase 5c is being built in parallel in another worktree off the same base: nothing of 5c's is on
this base, 5a names no 5c constant anywhere, and 5a touches `Dexpace::Instrumentation` not at
all. Phase 5b has not started.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md`. Task numbers are that
plan's. Design: `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md`, whose
Deviation Ledger rows `P5-1`–`P5-15` and as-built rows `P5-51`–`P5-58` are cited below; the charter
is `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`. Every test file named here is
under `gems/dexpace-core/test/`, mirrors its `lib/` file one for one unless the row says the file is
a `private_constant` asserted at its call site, and opens with the IDs it exercises.

## Requirement rows

Thirty-eight own rows, `CFG-1`–`CFG-38` — the design's whole disposition table: **35 ✅**, and
three **✅ in part**, each naming the unmet clause and its owner — `CFG-20` (the fourth clause is
`ASYNC-3`'s mechanism under a second ID, ⏳ against `docs/first-release.md`'s Unsatisfied-MUSTs
entry, `R7`), `CFG-34` (the container-kind clause N/A per §11.15, `P5-14`) and `CFG-35` (the
throwable half ⏳ against phase 6a's plan Task 3, `R1`). Nothing in `CFG` is deferred outright.
Then seven cross-reference rows for the non-`CFG` IDs 5a owns a share of, the way 4b and 4c carried
theirs: `XCUT-5`, `CTX-11`, `IO-9`, `BODY-32`, `SEAM-18`, `XCUT-11` and `NFR-11`.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `CFG-1` | MUST | ✅ | 11 | `Dexpace::Configuration#string` resolves the exact-key override, then the environment seam by the exact key, then the property seam by the NORMALISED key, then the caller's default — in that order even where it inverts Ruby convention (§10.16, boundary 6); the guard that swaps the environment and property tiers runs red below (`dexpace/configuration_test.rb`, `LookupTest`, "CFG-1" and "CFG-1 / §10.16") |
| `CFG-2` | MUST | ✅ | 11 | A present-but-empty environment value falls through to the property tier and the default; an empty override and an empty property both resolve to `""`, asserted in the same case so a later refactor cannot make emptiness a chain-wide rule (`configuration_test.rb`, `LookupTest`, "CFG-2 asymmetry") |
| `CFG-3` | MUST | ✅ | 11 | `Configuration::Guard.normalize` is `downcase.tr("_", ".")` with no argument to `downcase` (`Dexpace/NoLocaleCaseFold`; the `:turkic` guard runs red below); `MAX_RETRY_ATTEMPTS` is queried as `max.retry.attempts`, the override and environment tiers stay exact-name, and the guard that drops the normalisation runs red while `#raw_property` stays exact (`configuration_test.rb`, `LookupTest`, "CFG-3", "CFG-1 / CFG-3") |
| `CFG-4` | MUST | ✅ | 11 | `Configuration#raw_property` reads the property tier alone by the exact name — `https.proxyHost` and `http.nonProxyHosts` keep their casing — and consults neither the override map nor the environment, which is §10.16's "one deviation applied twice" kept one; `Builder#property` stores its key verbatim so the only in-SDK setter reaches the raw accessor (`configuration_test.rb`, `LookupTest`, "CFG-4" ×2; `configuration/builder_test.rb`, `BuilderContractTest`, "CFG-4") |
| `CFG-5` | MUST | ✅ | 10, 11 | `ConfigParsers.parse_integer`, a `private_constant` asserted at its call site: base 10 explicit (`"010"` → 10, the live defect), never throws, negatives returned as-is, Ruby's two tolerances (`"1_000"`, `" 5 "`) documented rather than removed, hex / scientific / junk / a float / a blank env value all yielding the default (`configuration_test.rb`, `AccessorsTest`, "CFG-5") |
| `CFG-6` | MUST | ✅ | 10, 11 | `ConfigParsers.parse_boolean`: exactly `"true"` and `"false"` case-insensitively, no trimming, and `1`/`0`/`yes`/`no`/`on`/`off`/`t`/`f` all fall to the default (`configuration_test.rb`, `AccessorsTest`, "CFG-6") |
| `CFG-7` | MUST | ✅ | 10, 11 | `ConfigParsers.parse_duration`: ISO-8601 (hand-written, `Date._iso8601` parsing no duration), `<number><unit>` with `ms`/`s`/`m`/`h`/`d` case-folded and optional whitespace, then a bare number as MILLISECONDS — Float SECONDS returned (`P5-4`); a negative in any branch, a bare `P`, an unknown unit and garbage yield the default; three patterns each with a per-pattern timeout (`configuration_test.rb`, `AccessorsTest`, "CFG-7" ×2). The guard that reads a bare number as seconds runs red below |
| `CFG-8` | MUST | ✅ | 11 | `.build` copies and deep-freezes the override map through `Model.own` (`Ractor.make_shareable(copy: true)`); later builder mutation and later writes to the caller's source hash never reach a built instance; the guard that aliases the source hash runs red below (`configuration/builder_test.rb`, `BuilderTest`, "CFG-8" ×2; `config_test.rb`, `SlotTest`, "CFG-8 / CFG-13") |
| `CFG-9` | MUST | ✅ | 11 | `#derive` copies the override map before the mutator runs and passes both seams by reference — `assert_same`, never `assert_equal` — unless the mutator replaces one; `#property` over an inherited seam composes (the added entries shadow it) while an untouched inherited seam passes through as the same object (`builder_test.rb`, `BuilderTest`, "CFG-9" ×3) |
| `CFG-10` | MUST | ✅ | 11 | `Builder#remove` drops only the override, so the lookup falls through to the environment as if never overridden; never installs a `nil`; a no-op for a key with no override (`builder_test.rb`, `BuilderTest`, "CFG-10") |
| `CFG-11` | MUST | ✅ | 1, 9 | `Configuration::Sources::ENVIRONMENT` (`::ENV.fetch(key, nil)`, exact name, `""` reported as `""` so CFG-2 stays the chain's rule), `Sources::NONE`, and `Sources.from_hash` over a frozen stringified copy, each a frozen callable of arity one; the seams are validated as callables at every entry; `FakeConfigSource` is what makes every `CFG-1`–`CFG-10` case hermetic, so no test in 5a reads the process environment through the chain (`configuration/sources_test.rb`; `matrix_facts_test.rb`, `DoublesTest`) |
| `CFG-12` | SHOULD | ✅ | 11 | `Configuration::Builder` carries no mutex, by requirement, and includes phase 1's `Dexpace::Builder` contract; the built model is the frozen, shareable thing (`builder_test.rb`, `BuilderContractTest`, "CFG-12") |
| `CFG-13` | SHOULD | ✅ | 12 | `Dexpace.configure` yields a builder seeded from the live slot, builds outside the mutex and publishes one frozen reference under it; `Dexpace.configuration` reads with no lock; `Dexpace.reset_config!` restores `Configuration::EMPTY`, whose seams are `Sources::ENVIRONMENT` and `Sources::NONE` by identity. Last-write-wins at the key level across three configures, a re-entrant block does not deadlock, a block-less or raising configure publishes nothing, no observer exists, and 16 writers against 16 readers see only whole frozen snapshots; the guard that drops the mutex around the swap is recorded below as the one this suite cannot see deterministically (`config_test.rb`, `SlotTest` and `RaceTest`) |
| `CFG-14` | SHOULD | ✅ | 9 | `Configuration::Keys`: the five well-known names plus `MAX_MATERIALIZED_BYTES` and `MAX_TRACKED_CONTEXTS`, frozen Strings; `LOG_LEVEL` is a published name nothing in core reads (`OBS-35`'s embedded MUST, asserted by scanning `lib/`); the seven proxy system-property names are not keys (`configuration/keys_test.rb`) |
| `CFG-15` | MUST | ✅ | 1, 6 | `Dexpace::Clock` with exactly three public instance methods, `#now`, `#monotonic` and `#sleep`, and `Clock::SYSTEM` frozen and shared; `_Clock` in `sig/dexpace/clock.rbs`; `FakeClock` satisfies the seam exactly (`clock_test.rb`, `SeamTest`; `matrix_facts_test.rb`, `DoublesTest`) |
| `CFG-16` | MUST | ✅ | 6 | `#monotonic` is `Process.clock_gettime(CLOCK_MONOTONIC)` in seconds: 10 000 readings non-decreasing, within a second of the raw clock and a day away from `Time.now` — the guard that measures with `#now` runs red below (`clock_test.rb`, `SeamTest`, "CFG-16") |
| `CFG-17` | MUST | ✅ | 6 | `#sleep`: a negative, `nil`, non-numeric duration or a non-token `cancellation:` is refused before any wait (the guard is 5a's — `Queue#pop(timeout: -1)` returns nil and raises nothing, fact 8); zero returns `nil` promptly with no queue and no subscription; a positive duration is a bounded pop on a per-call `Thread::Queue` the token pushes to; an already-cancelled token raises `Dexpace::CancelledError` at once carrying the reason, a cancel DURING a 30 s wait wakes it within the suite's bound, the token reads `cancelled?` afterwards (the re-assertion clause, met structurally through `Cancellation#check!`), the subscription is detached on every path (P2-14), `Cancellation.none` is accepted, and a 2 ms sleep is 2 ms (sub-millisecond, the SHOULD). The file names no `Kernel#sleep`, no `Timeout`, no `Thread#raise` and no `Thread#kill`, asserted by text; the `Kernel#sleep` and dropped-`timeout:` guards run red below (`clock_test.rb`, `SleepTest`) |
| `CFG-18` | SHOULD | ✅ | 1, 7 | `Dexpace::Async.delay` (P5-10): a negative or non-numeric duration is refused before anything is scheduled; zero returns a future already settled with the void value `true` (`SEAM-16` makes a `nil` settlement unconstructible; P5-52) and consults no scheduler even when one is registered; a positive duration with no `Fiber.scheduler` raises `Dexpace::SeamError` naming `CFG-18`, `Fiber.set_scheduler` and `Dexpace::Clock#sleep` (P5-9); under `ParkingScheduler` the wait parks the fiber — `#block` once, `#kernel_sleep` never, the only assertion that tests "WITHOUT blocking a thread" — the future is unsettled while the duration runs and settles once it elapses, and cancelling it wakes the parked fiber promptly (`#unblock` once) with `:test_cancel` readable off the error (`async/delay_test.rb`) |
| `CFG-19` | SHOULD | ✅ | 8 | Satisfied by construction and no `unwrap` method ships (P5-11): `Completer#fail(error)` then `Future#value` raises the IDENTICAL object — `assert_same`, never `assert_kind_of` — with a `nil` cause, through `#then` and through a deadline wait alike; `Dexpace.each_cause` is the one cause walk and 5a writes no second (`async/future_deadline_test.rb`, `UnwrapTest`) |
| `CFG-20` | SHOULD | ✅ in part | 8 | Three of four clauses met and asserted: the non-interrupting cancel is `Future#cancel` (phase 2) and a finished task is untouched by it; the queued-or-finished clause holds because no interrupt is ever delivered; the rejected-submission clause is `Completer#fail`'s routing, delivered through the future and never thrown (`future_deadline_test.rb`, `UnwrapTest`, "CFG-20" ×2). The fourth — cancel-with-interrupt — is `ASYNC-3`'s mechanism under a second ID and is forbidden by §8.3: ⏳ against `docs/first-release.md` § What v1 ships without › Unsatisfied MUSTs, whose entry names `CFG-20`'s fourth clause among the gaps that mechanism covers (`R7`). 5a adds no line to that file and no fourth unsatisfied MUST: `CFG-20` is a SHOULD |
| `CFG-21` | MUST | ✅ | 16 | Phase 2's code, this phase's citation: `Dexpace.close_quietly(nil)` is `nil` and raises nothing, a raising `#close` on the discard path is swallowed after being attempted, and a `Completer#fulfil` that loses the race to a cancel — or to a deadline expiry — closes the late result exactly once (`close_quietly_cfg21_test.rb`) |
| `CFG-22` | MUST | ✅ | 14, 15 | `Dexpace::Proxy`, a frozen `Data` including `Model` with `.new` private and a validating `initialize`: `type` (resolved through `Type.of`), `host` and `port` in place of a socket address (P5-5), an ordered frozen `Array` of `HostPattern`, nullable `username`/`password`/`challenge_handler`, and `bypass_all`; `Proxy::Type` is a closed three-member frozen `Data`; `#to_s` AND `#inspect` mask BOTH credentials as `****` — the requirement's parenthetical is "never emit username/password in cleartext", and review round 0 found the username printed verbatim beside a masked password (R0-2; deviation 24 below) — so a rendering says only which credential is set (`****:****@`, `****@`, `:****@`, nothing), the accessors still return the values, and the handler prints by class only (P5-7). The username-back-in-`#to_s` and username-back-in-`#inspect` guards run red below (`proxy_test.rb`, `ModelTest`; `proxy/type_test.rb`) |
| `CFG-23` | MUST | ✅ | 14 | `Proxy::HostPattern.of(glob)` compiles once at construction — `*` → `.*`, `?` → `.`, every other character `Regexp.escape`d, `\A…\z`, `IGNORECASE`, a per-pattern `timeout:` — as a private instance variable behind a one-member `Data` (P5-53); `#matches?` matches the host exactly as given, never stripped, nil never matching; a trailing or embedded newline never matches (`\z` not `\Z`, no `/m`); `Proxy#bypass?` short-circuits on `bypass_all`, else any pattern decides. The anchoring, escaping and case guards run red below (`proxy/host_pattern_test.rb`; `proxy_test.rb`, `ModelTest`, "CFG-23 / CFG-27") |
| `CFG-24` | MUST | ✅ | 15 | `Dexpace::ProxyResolution` (a `private_constant`, asserted through `Proxy.resolve`): `https.proxyHost` preferred over `http.proxyHost`, the port from the SAME layer as the chosen host through one `LAYERS` lookup (a host under `https.*` with only `http.proxyPort` set is a missing port, never a borrowed one), credentials from `https.proxyUser`/`https.proxyPassword` ONLY with no `http.*` fallback — the chapter's own conformance case, written as a negative; a blank property host is absent; then `HTTPS_PROXY` over `HTTP_PROXY` — the first NON-BLANK of the two, so a blank `HTTPS_PROXY` from an override or a property, which `CFG-2` leaves as an answer, no longer masks `HTTP_PROXY` (review round 0, R0-8; the `||`-preference guard runs red below) — parsed with `URI::RFC3986_PARSER` as `scheme://user:pass@host:port`, credentials decoded with `URI.decode_uri_component` (`+` is not a space; `RFC3986_PARSER.unescape` warns on 3.4.10); the scheme selects `SOCKS4`/`SOCKS5`/`HTTP`; a property host with an unusable port yields nil and never falls through to the environment; every malformed input — `http://h:abc`, `not a url`, `http://:8080`, `http://h:70000`, `://h:1`, a space, `%zz://` — yields `nil` with exactly one `Kernel#warn` (P5-8), captured through phase 2's `WarningCapture` because `DexpaceTestCase` fails a test on any warning; a `rescue ::StandardError` backstops the operation; and one case drives the slot end to end through `Dexpace.configure` (§10.16). The garbage-raises guard runs red below (`proxy_test.rb`, `PropertyLayerTest` and `EnvironmentLayerTest`) |
| `CFG-25` | MUST | ✅ | 14, 15 | The port is read off `URI::RFC3986_PARSER.split(url)[3]` and never off `#port` — a guard case asserts `parse("http://proxy.example").port == 80` beside `split(...)[3].nil?` so the day someone simplifies onto `#port` a test says why it is wrong; an absent port yields nil with a warning naming "no explicit port"; `70000`, `-1`, `abc`, `""`, `80.5`, `0x50` all yield nil with one warning; 0 and 65535 are accepted; and the model's own `port!` refuses a nil, a String and anything outside 0..65535 on `.build` and on `#with`. The 65536-accepted guard runs red below (`proxy_test.rb`, `PropertyLayerTest`, `EnvironmentLayerTest`, `ModelTest`) |
| `CFG-26` | MUST | ✅ | 15 | `http.nonProxyHosts` (pipe-separated) wins over `NO_PROXY` (comma-separated) whichever source supplied the host; split on an unescaped separator (a negative-lookbehind pattern with a per-pattern timeout, limit `-1`) → drop empty → unescape → trim, in that order, with the chapter's four conformance outputs asserted verbatim; a whitespace-only fragment survives the order as an empty token — the design's verified fact 12 lists `"a| |c"` → `["a", "", "c"]`, which is the PRE-compilation token list — and is then dropped before a `HostPattern` is compiled from it, because an empty glob is not a host pattern: the plan's self-review item 4 is the reading that overrides the design's sentence, and the drop is observable only as "no empty pattern in `#non_proxy_hosts`" (review round 0, R0-9); the separators are not interchangeable across the sources; an empty or absent source yields an empty frozen list. The escape guard runs red below (`proxy_test.rb`, `NonProxyTest`) |
| `CFG-27` | MUST | ✅ | 14, 15 | Exactly one bare `*` (trimmed) from either source is bypass-all: resolution returns `nil` and the flag, not a literal entry, carries it on a model built by hand; `*` inside a multi-entry list stays an ordinary any-host glob (`proxy_test.rb`, `NonProxyTest`, "CFG-27"; `ModelTest`, "CFG-23 / CFG-27") |
| `CFG-28` | MAY | ✅ | 15 | The MAY is taken — `Proxy.resolve(configuration = Dexpace.configuration)` — and its prohibition is met structurally: nothing in `lib/` calls `Proxy.resolve`, asserted by scanning the tree's code lines, so no environment read happens unless a caller invokes the resolver. The default-argument half is proven with the slot's environment seam replaced by a fake through `Dexpace.configure` and reset in `ensure` — review round 0 found it asserted against the EMPTY slot, whose seam is the real `ENV`, so the case read the host's `HTTPS_PROXY` and failed wherever one was set (R0-1; deviation 25 below); the `EMPTY`-default guard runs red below (`proxy_test.rb`, `NonProxyTest`, "CFG-28" ×2) |
| `CFG-29` | MUST | ✅ | 5 | `Dexpace::HTTPDate.format` is `time.getutc.httpdate`: the specification's own example byte for byte, a `+02:00` instant rendered in UTC with a literal GMT, a single-digit day zero-padded, sub-seconds dropped; a nil or non-`Time` argument refused with `SEAM-29`'s message. Open question 2 settled at execution: CRuby's `strftime` carries its own English tables, verified under a user-space `de_DE.UTF-8` built with `localedef` into `LOCPATH` where `date` renders "Sonntag November" — on 3.2.11, 3.4.10 and 4.0.6 (`http_date_test.rb`, `FormatTest`) |
| `CFG-30` | MUST | ✅ | 5 | `HTTPDate.parse`, an owned anchored grammar (P5-12, `R2`): `GMT`, `UTC`, `+0000` and `+00:00` all parse to the identical UTC instant; month and zone case do not matter; the weekday is matched as three letters and never compared against the date — `Mon, 06 Nov 1994` and `xyz, 06 Nov 1994` both parse (`http_date_test.rb`, `ParseTest`, "CFG-30" ×2). The `UTC`-rejected guard runs red below |
| `CFG-31` | MUST | ✅ | 5 | `""`, `"   "` and `Mon 01 Jan 2024 00:00:00 GMT` (no comma) each raise `Dexpace::InvalidArgumentError` naming the input, as do RFC 850, asctime, a leading space, an embedded newline (`\s+` would accept it), a trailing newline (`\Z` would), a trailing token, a single-digit day, a missing zone, a non-zero offset, `EST` and a two-digit year — and a well-formed but impossible date (31 November, 29 February 1995, hour 24, minute 60, second 60), which `Time.utc` silently normalises into the next day or minute, so every component is checked against what `Time.utc` built (P5-54). The grammar is one frozen pattern with a per-pattern timeout; `parse(format(t)) == t.floor` over 200 sampled instants with the seed logged. The blank-accepted guard runs red below (`http_date_test.rb`, `ParseTest`) |
| `CFG-32` | MUST | ✅ | 3 | `Dexpace::UUID.generate`: 16 bytes from a `Random` memoised in `Thread.current[:dexpace_prng]` (P5-13), byte 6 masked to version 4, byte 8 to the IETF variant, `unpack1("H*")`, hyphenated, frozen; 10 000 draws with no collision; the version and variant nibbles hold across 1000 draws while the rest varies. Isolation is asserted through the CARRIER, not the output: a child fiber and a new thread each seed their own generator and the parent's slot is untouched, and `Fiber[:dexpace_prng]` is nil. Boundary 8 is checkable by text — the file's code names no `SecureRandom` and requires no `securerandom`; the `SecureRandom.uuid` and wrong-nibble guards run red below (`uuid_test.rb`) |
| `CFG-33` | MUST | ✅ | 10, 11 | `Dexpace::DeepValue` (a `private_constant`, `R4`, asserted at its call sites inside `module Dexpace`): content-based and recursive over Arrays and Hashes, null-safe with `nil` hashing to zero, byte arrays falling back to `String#==` on the BINARY String, a self-referential Array and Hash comparing and hashing without overflowing (P5-15), the visited guard keyed by the PAIR (`[u, v, u]` against `[m, n, n]` refused) and the hash stack unwinding (`[shared, shared]` hashes as `[[1], [1]]`). It has no in-tree caller in v1 and exists to satisfy this conformance clause, which is why it is private rather than `NFR-4`-locked surface (`configuration_test.rb`, `DeepValueTest`, `PrivacyTest`) |
| `CFG-34` | MUST | ✅ in part | 10, 11 | Two distinct NaNs with DIFFERENT payloads (`0.0/0.0` and `-(0.0/0.0)`, both `#nan?`, whose `Float#hash`es differ — the precondition is asserted) are equal and hash alike, and neither equals `[0.0]`; `+0.0` and `-0.0` are unequal and hash apart though Ruby's own `0.0.hash == (-0.0).hash`; `[1]` and `[1.0]` are unequal and hash apart though Ruby says `[1] == [1.0]` — element-kind distinctness (P5-14). The `==`-compared-NaN, identical-NaN and `0.0 == -0.0` guards run red below. The **container-kind** clause ("an object array and a primitive array") is **N/A** per §11.15 — Ruby has one `Array` and no second container to be unequal to — and the inapplicability is not extended to the other clauses (`configuration_test.rb`, `DeepValueTest`) |
| `CFG-35` | SHOULD | ✅ in part | 4 | The STATUS half ships as `Dexpace::Retryability.retryable_status?` — `XCUT-5`'s single shared classifier: 408, 429 and every 5xx except 501 and 505, asserted over the whole 100..599 range plus 0, 99, 600, 999 and −1, accepting an Integer, a `Dexpace::Status` or anything answering `#code` and refusing anything else; a predicate and not an exposed set, with no constants and one singleton method. The 501/505/408 guards run red below. The THROWABLE half is ⏳ against phase 6a's plan Task 3, `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry.md` (`R1`): no method ships, not even one returning `false`, asserted as `refute_respond_to` on `retryable_throwable?`, `retryable_error?` and `retryable?` (`retryability_test.rb`) |
| `CFG-36` | SHOULD | ✅ | 2 | `Dexpace::BuildInfo`: `SDK_VERSION` (`Dexpace::VERSION`), `RUNTIME_VERSION` (`RUBY_ENGINE_VERSION`), `RUNTIME_VENDOR` (`RUBY_ENGINE`) and `OS_NAME` (`RUBY_PLATFORM`'s OS half), each through one blank guard yielding `"unknown"`, resolved once at load into frozen constants — no `rbconfig`, so the require allowlist does not grow (`R5`); `IDENTITY_TOKENS` is the frozen ordered pair `dexpace-ruby/<version>`, `<vendor>-<version>/<os>`, every element non-blank and whitespace-free. The blank-token guard runs red below (`build_info_test.rb`) |
| `CFG-37` | MUST | ✅ | 11, 12, 15 | Every mutating operation fails fast with `Dexpace::InvalidArgumentError`, through `Model.required!`'s one message form where a value is absent: `Builder#override`, `#remove` and `#property` on a nil or blank key and a nil value, `#env_source=` and `#property_source=` on nil or a non-callable, `.build` on a nil map, a nil value in it or a nil seam, `#derive` without a block (`derive block is required`), `Dexpace.configure` without one (`configure block is required`), `Sources.from_hash` on nil, a non-Hash or a nil value, `Proxy.build` on an absent type, host or port, `HostPattern.of` on nil or blank, `Type.of` on nil, and every 5a lookup on a nil name; the documented-nullable slots — a lookup default, the credentials and the challenge handler — accept nil. The bare-`ArgumentError` guard runs red below (`configuration_test.rb`, `LookupTest`; `builder_test.rb`, `BuilderContractTest`; `config_test.rb`; `sources_test.rb`; `proxy_test.rb`, `ModelTest`). `Configuration::Builder.new` is public and takes a seed map: since review round 0 the seeds go through `#override` and the seams through the setters' guard, so a nil seed value, a blank seed key, a non-Hash seed map or a nil or non-callable seam fails fast where before a nil seed value stringified to `""` (R0-6; the stringifying guard runs red below) (`configuration/builder_test.rb`, `BuilderContractTest`, "Builder.new refuses") |
| `CFG-38` | MUST | ✅ | 11 | `#integer`, `#boolean` and `#duration` resolve through `#string` — the whole chain — before parsing: supplied ONLY through the environment seam and through a normalised property they still resolve, which is the case an implementation reading the override map alone fails, and the typed default applies only when the chain is absent or unparseable (`configuration_test.rb`, `AccessorsTest`, "CFG-38" ×2) |
| `XCUT-5` | MUST | ✅ share | 4 | Cross-reference, phase 9's ID: the SINGLE shared status classifier now has one home, `Dexpace::Retryability.retryable_status?`; phase 6a computes `Dexpace::ProtocolError`'s baked flag FROM it (its plan Task 6) and builds no second, and `XCUT-7`'s configurable default set `{408, 429, 500, 502, 503, 504}` is asserted to be a subset of this classification and a different object (`retryability_test.rb`, "XCUT-5 / XCUT-7") |
| `CTX-11` | MUST | ✅ share | 13 | Cross-reference, phase 4a's ID and the cap's configuration source it postponed here: `ContextStore.default` is built on its FIRST call, under one `::Thread::Mutex`, with `Configuration::Keys::MAX_TRACKED_CONTEXTS` read from the chain and `MAX_TRACKED_CONTEXTS = 1024` as the fallback for an absent, unparseable or non-positive value (P5-55). A `Dexpace.configure` — or the environment variable — before the first call sets the process-wide store's cap, driven end to end in a fresh process by filling past the cap; a configure after the first call does not resize it and neither does `reset_config!`; the chain is read OUTSIDE the mutex and only the `||=` runs under it — the rule `Dexpace.configure` follows, no caller-supplied code under a non-reentrant lock, applied to the store since review round 0 (R0-4; deviation 26 below) — with a lock-free read of the published reference in front, so a promotion after the first runs neither seam and takes no lock; 16 threads reaching `.default` first under a `new` slowed to 50 ms get ONE store, which the unsynchronised `||=` guard fails below, a seam observes the mutex unowned while it runs, and a later `.default` runs no seam; no signature changed. Phase 4a's load-time assignment and its fresh-process case changed to say so (`context_store_config_test.rb`; `context_store_test.rb`, `ReachabilityTest`) |
| `IO-9` | MUST | ✅ share | 13 | Cross-reference, phase 3a's ID and the ceiling half of the body-logging caps phase 3b postponed here: `Dexpace::IO.max_materialized_bytes(configuration = Dexpace.configuration)` reads `Keys::MAX_MATERIALIZED_BYTES` on EVERY call, `MAX_MATERIALIZED_BYTES` the default and the fallback for an unparseable or non-positive value, so `Dexpace.configure` and `.reset_config!` govern the live ceiling; the five value-readers — `TypedReads#guard_materialization!` (whose refusal now names the limit that applied and the key), `Buffer#snapshot`, `Body.clamp_cap`, `StreamBody#replayable?` and `BufferBody#==` — read the function rather than the constant (P5-56), each driven through a configured ceiling of 4 or 8 bytes, with the slot's environment seam replaced by an empty fake in every setup and after each mid-case reset, so a host exporting `MAX_MATERIALIZED_BYTES` reaches no read (review round 0, R0-7). Phase 3a's and 3b's own materialisation suites read the ceiling through the slot too and install no fake: they assume, as this suite did before, that the host defines no such variable — stated here rather than fixed, because those suites are their phases' and the assumption held on every row this stack ran. No `ceiling:` keyword exists anywhere (`io_ceiling_test.rb`) |
| `BODY-32` | MUST | ✅ share | 13 | Cross-reference, phase 3b's ID: `Body.buffer_bounded` clamps a cap down to the CONFIGURED ceiling, never up and never to the constant — `Float::INFINITY` and a cap of 1000 both clamp to a configured 4, a cap of 3 stays 3 (`io_ceiling_test.rb`, `ReadersTest`, "BODY-32") |
| `SEAM-18` | MUST | ✅ share | 6, 8 | Cross-reference, phase 2's ID and the `deadline:` keyword its P2-5 postponed here: `Future#value`, `#wait` and `Completer#await` gain `deadline:` (a monotonic INSTANT, never a duration) and `clock:` — widenings only, `#await`'s token positional as phase 2 shipped it; `Clock.deadline_in` names the scale. Expiry is a timed gate pop with `remaining` recomputed from the clock on every iteration, ending in phase 2's own `request_cancel(:deadline_expired)` — one settlement, the producer's `on_cancel` hook fired, a late `fulfil` closed through SEAM-30 — so `#wait` still returns `self`, `#await` still returns `self` and never raises, and `#value` raises the `CancelledError` whose `#reason` is the Symbol `:deadline_expired` (XCUT-2: never a string match). A deadline exactly now is expired; an already-settled future ignores one; a real producer beats a real deadline; a real deadline passing cancels; a cancellation token wins with its own reason; no deadline is phase 2's wait unchanged; a non-numeric deadline or a clock without `#monotonic` is refused — settled or not, since review round 0 moved the validation above the settled short-circuit, because a settled future ignores an expired deadline and not an invalid one (R0-5; the validate-after-return guard runs red below). Not a token composed through `Cancellation.any`, as phase 2 anticipated (`async/future_deadline_test.rb`, `ExpiryTest` and `NonExpiryTest`) |
| `XCUT-11` | MUST | ✅ share | 12, 13 | Cross-reference, phase 9's ID: the two pieces of shared mutable state 5a adds are one frozen `Configuration` reference swapped under a mutex and read without one (16 writers × 50 against 16 readers × 200, and configure racing reset, every reader seeing a whole frozen snapshot), and `ContextStore.default`'s first-call construction under its own mutex (16 first callers, one store, under a `new` slowed to 50 ms so an unsynchronised `||=` publishes sixteen; the seams run outside the lock and a seam asserts `Mutex#owned?` false while it runs); `Clock::SYSTEM` and every `Configuration` are frozen and stateless, no 5a code path holds two locks (`config_test.rb`, `RaceTest`; `context_store_config_test.rb`, `RaceTest`) |
| `NFR-11` | MUST | ✅ share | 4, 6, 9 | Cross-reference, phase 9's ID: the three new RBS interfaces — `_Clock` (`sig/dexpace/clock.rbs`), `_ConfigSource` (`sig/dexpace/configuration/sources.rbs`) and `_RetryableStatus` (`sig/dexpace/retryability.rbs`) — name only `Dexpace::` constants and allowlisted stdlib (`::Time`, `Numeric`); `gates:rbs_surface` is green over the twenty-one `sig/` files 5a adds or changes |

## What was built

Seventeen new `lib/` files under `gems/dexpace-core/lib/dexpace/` — the design's Module Layout
plus one: `build_info.rb`, `uuid.rb`, `retryability.rb`, `http_date.rb`, `clock.rb`,
`async/delay.rb`, `deep_value.rb` (`private_constant`), `configuration.rb`,
`configuration/keys.rb`, `configuration/sources.rb`, `configuration/parsers.rb`
(`private_constant`), `configuration/builder.rb` (the one the design folded into
`configuration.rb`; filed beside it as phase 1 files every builder, P5-51), `config.rb`,
`proxy.rb`, `proxy/type.rb`, `proxy/host_pattern.rb` and `proxy/resolution.rb`
(`private_constant`). Nine existing files changed: `dexpace.rb` (ten new `require_relative`
lines — `configuration.rb` and `proxy.rb` load their own nested files from inside the class body
they declare, because those files reopen the class), `async/completer.rb` and `async/future.rb`
(the `deadline:` and `clock:` keywords), `context_store.rb` (the first-call construction under a
mutex), `io.rb` (the configured ceiling's source), and the four ceiling readers `http/body.rb`,
`http/body/stream_body.rb`, `http/body/buffer_body.rb` and `io/typed_reads.rb`. Seventeen `sig/`
mirrors, one per new file — the three `private_constant`s included, each with the comment
`sig/dexpace/hooks.rbs` carries, because the strict `core` Steep target types every call site
(P5-57) — plus the four changed mirrors `async/completer.rbs`, `async/future.rbs`,
`context_store.rbs` and `io.rbs`; `sig/dexpace.rbs` stays `module Dexpace; end`. Fourteen
`test/` mirrors, one per public file; the three private constants are asserted at their call
sites in `configuration_test.rb` and `proxy_test.rb`. Six further suites carry no mirror because
they exercise a wiring, a fact or a citation rather than a file: `matrix_facts_test.rb`,
`async/future_deadline_test.rb`, `config_test.rb` (the mirror of `config.rb`),
`context_store_config_test.rb`, `io_ceiling_test.rb` and `close_quietly_cfg21_test.rb`. Three
existing suites changed: `context_store_test.rb` (phase 4a's fresh-process case, rewritten for the
first-call construction), `seam_surface_test.rb` (phase 2's non-relative-requires list gains
`time`) and `dexpace_test.rb` (the constant list gains the seven public 5a constants, and `time`
is preloaded so `Date` and `DateTime` are its and not the entry file's). Three test doubles under
`test/support/`: `fake_clock.rb`, `fake_config_source.rb` and `parking_scheduler.rb`, every one a
top-level class, every one a fake by `testing/7ecef8e8`'s definition, none required from `lib/`,
none shadowing a core constant. The repository-root manifest `test/fixtures/surface/dexpace-core.txt`
grew by exactly the 84 rows the object model names, 730 → 814, regenerated once in Task 16 and
read row by row: no private constant, no private method and no `Guard` or `Deadline` helper
contributed a row.

The require allowlist did not grow. Core's non-relative requires are `strscan`, `uri`,
`securerandom` and now `time` (`http_date.rb`, for `Time#httpdate`); `proxy/resolution.rb` reuses
phase 1's `uri`. No `require "date"`, no `rbconfig`, no `logger`, no `timeout`; `uuid.rb` names no
`SecureRandom`, which `uuid_test.rb` asserts by text. Every pattern 5a compiles — the date grammar,
the three duration grammars, the glob translation and the `CFG-26` separator — is
`Regexp.new(source, timeout:)`, never `Regexp.timeout`. Every `downcase`/`upcase` is bare. Every
`Data` includes `Model`, hides `.new`, validates in `initialize` and derives through `Model#with`;
the one closed set, `Proxy::Type`, hides `.[]` too, ships no `.build` and refuses `#with` (P4-56's
shape). Nothing in 5a touches `Dexpace::Instrumentation`, adds a registry, or calls `Proxy.resolve`.

## Guards run red

Every guard the brief asks to be seen red was seen red, on 4.0.6, and restored; the ones the
brief names for the floor were run on 3.2.11 as well. Each is a single-edit mutation against the
finished suites, applied by hand and reverted with `git checkout` before the next.

Every mutation was caught on the first run except one, which was made visible and re-run: guard
14 raised the resolver's port bound by one, and the resolver's own range check was
indistinguishable from the model's refusal caught by the backstop — nil and one warning either
way, on inputs that were all far past the bound. The suite now carries `65536` in its port list
and asserts the warning's own text ("outside 0..65535"), so the resolver's check and the backstop
are told apart. Guard 6 is the one no behavioural case can see: under the GVL a reference
assignment is atomic, so dropping the mutex around the slot swap changes nothing observable;
`config_test.rb` pins the shape by text and says why. Guard 7b hangs by construction — a pop with
no timeout waits forever — and the shell timeout is what reports it.

| # | Guard (single-edit mutation) | Suite | Result on 4.0.6 (and 3.2.11 where run) |
|---|---|---|---|
| 1 | `CFG-1`: the environment and property tiers swapped in `Configuration#string` | `configuration_test.rb` | 2 failures: `CFG-1: override, then exact-name env, then normalised property, then the default … Expected: "from_env" Actual: "from_prop"` |
| 2 | `CFG-3`: `Guard.normalize` returns the key unchanged | `configuration_test.rb`; `configuration/builder_test.rb` | 4 failures and 2 failures: `CFG-38 … Expected: 7 Actual: nil`; `CFG-9: derive is copy-on-write … Expected: "bravo" Actual: nil`; `#raw_property` cases stay green — the raw accessor is exact-name regardless |
| 3 | `CFG-6`: `downcase(:turkic)` in `parse_boolean` | RuboCop over `parsers.rb` | 1 offense: `parsers.rb:62:12: C: Dexpace/NoLocaleCaseFold: Call downcase with no argument: Ruby's fold is opt-in-locale and HTTP-13 needs ASCII folding.` |
| 4 | `CFG-7`: a bare number read as seconds | `configuration_test.rb` | 1 failure: `CFG-7: durations parse … BARE. Expected \|1.5 - 1500.0\| (1498.5) to be <= 1.0e-09.` |
| 5 | `CFG-8`: `Model.own` dropped, the caller's hash aliased and frozen in place | `configuration/builder_test.rb` | 1 failure, 2 errors: `FrozenError: can't modify frozen Hash: {"KEY" => "v1"}` from `Builder#override` — the caller's live hash frozen under it — and `CFG-37 … InvalidArgumentError expected but nothing was raised` (the nil value no longer refused) |
| 6 | `CFG-13`: the slot assigned outside the mutex | `config_test.rb` | 1 failure: `XCUT-11 / CFG-13: both publications happen inside the one mutex … Expected: 2 Actual: 1`. Every behavioural case stays green — recorded as the reason the text pin exists |
| 7a | `CFG-15`: the wait as `Kernel.sleep(seconds)` | `clock_test.rb` | 2 failures: `a cancel DURING the wait wakes it promptly … Expected 30.00016269400021 to be < 5.0` — the full 30 s slept — and the text scan. **Identical on 3.2.11** (`30.029971885000123`) |
| 7b | `CFG-15`: the pop's `timeout:` dropped | `clock_test.rb` | **Hung** on the elapsing case and was killed by the shell timeout after 120 s (exit 124), never reaching a summary — the finding the brief names, not a retry |
| 8 | `CFG-17`: the token not re-asserted after the wake | `clock_test.rb` | 1 failure: `a cancel DURING the wait … Dexpace::CancelledError expected but nothing was raised.` **Identical on 3.2.11** |
| 9 | `CFG-16`: `#monotonic` measured with `Time.now` | `clock_test.rb` | 1 failure: `#monotonic is a non-decreasing Float of seconds on CLOCK_MONOTONIC's scale … Expected \|6143.375241218 - 1789630428.069967\| (1789624284.69) to be <= 1.0.` |
| 10 | the deadline: expiry raises a bare `CancelledError` instead of `request_cancel(:deadline_expired)` | `async/future_deadline_test.rb`; `close_quietly_cfg21_test.rb` | 1 failure, 5 errors, and 1 error: `#wait still settles-or-returns, and never raises … Dexpace::CancelledError: the operation was cancelled: deadline_expired` from `#await`, `an expired deadline settles the completer; it does not merely raise`, and the CFG-21 late-close case. **Identical on 3.2.11** |
| 11 | `CFG-19`: `Future#value` re-raises `error.class, error.message` (a copy) | `async/future_deadline_test.rb` | 6 failures: `a failure surfaces as the identical object … Expected #<RuntimeError: underlying root error> (oid=856) to be the same as #<RuntimeError: underlying root error>`, through `#then`, through a deadline wait, and the rejected-submission case |
| 12a | `CFG-23`: the glob anchored `^…$` | `proxy/host_pattern_test.rb` | 2 failures: `a newline in the host never matches -- \z, not \Z, and no /m … Expected true to not be truthy` (`"evil.com\n"` matched), and the pattern-source case. **Identical on 3.2.11** |
| 12b | `CFG-23`: the glob's characters not escaped | `proxy/host_pattern_test.rb` | 2 failures: `every regexp metacharacter in the glob is literal … Expected true to not be truthy` (`a.b` matched `axb`), and the pattern-source case |
| 12c | `CFG-23`: `IGNORECASE` dropped | `proxy/host_pattern_test.rb` | 3 failures: `* matches any run and ? exactly one character, case-insensitively … Expected false to be truthy`, the metacharacter case, and the property case at `sample 0 of 128, seed 20260905` |
| 13 | `CFG-24`: both rescues dropped, the resolver raising on garbage | `proxy_test.rb` | 2 errors: `a malformed proxy URL yields nil with a warning and never raises: URI::InvalidURIError: bad URI (is not URI?): "http://h:abc"` and `a seam that raises inside the resolution …: IOError: seam exploded` |
| 14 | `CFG-25`: the resolver's `parse_port` accepting 65536 | `proxy_test.rb` | **0 failures on the first run** (see above); 1 failure once `65536` was in the list: `a port outside 0..65535, non-numeric or blank yields nil with a warning … Expected … "proxy resolution failed: Dexpace::InvalidArgumentError: port must be within 0..65535, got 65536" to include "outside 0..65535"` |
| 14b | `CFG-25`: the model's `port!` accepting 65536 | `proxy_test.rb` | 1 failure: `the model refuses an absent, non-Integer or out-of-range port … InvalidArgumentError expected but nothing was raised.` |
| 15 | `CFG-26`: the negative lookbehind dropped from the separator | `proxy_test.rb` | 3 failures: `NO_PROXY splits on unescaped commas … Expected: ["a,b", "c", "d"] Actual: ["a\\", "b", "c", "d"]`, the pipe case (`["a|b", "*.internal"]` → `["a\\", "b", "*.internal"]`) and the chapter's conformance outputs |
| 16a | `CFG-30`: the zone group reduced to `GMT` | `http_date_test.rb` | 1 error: `all four zone tokens parse to the identical UTC instant: Dexpace::InvalidArgumentError: not an RFC 1123 date: "Sun, 06 Nov 1994 08:49:37 UTC"` |
| 16b | `CFG-31`: blank input answered with the epoch | `http_date_test.rb` | 1 failure: `blank input and a missing comma after the weekday fail with a parse error … "". Dexpace::InvalidArgumentError expected but nothing was raised.` |
| 17a | `CFG-32`: `SecureRandom.uuid` behind `require "securerandom"` | `uuid_test.rb` | 2 failures: `three execution contexts get three distinct generators, and none is shared … Expected nil to not be nil` (no generator in the carrier) and the text scan. `gates:require_allowlist` would NOT have caught it — `securerandom` is allowlisted — which is why the text scan exists |
| 17b | `CFG-32`: the version nibble masked to 5 | `uuid_test.rb` | 3 failures: `Expected /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/ to match "76e062c6-f526-564e-9f67-41af333e995d"`, and `the version and variant nibbles hold across 1000 draws … Expected: Set["4"] Actual: Set["5"]` |
| 17c | `CFG-32`: the variant nibble masked to `c`–`f` | `uuid_test.rb` | 3 failures: `… to match "779eb327-491c-4361-caf8-e792f7796634"`, and `Expected: Set["8", "9", "a", "b"] Actual: Set["f", "d", "e", "c"]` |
| 18a | `CFG-34`: the NaN branch dropped (NaN compared by `==`, two DISTINCT objects) | `configuration_test.rb` | 1 failure: `NaN equals NaN, and two NaNs with different payloads hash alike … Expected false to be truthy.` **Identical on 3.2.11** |
| 18b | `CFG-34`: the signed-zero branch dropped (`0.0 == -0.0`) | `configuration_test.rb` | 1 failure: `+0.0 and -0.0 are unequal, and their hashes differ to match … Expected true to not be truthy.` |
| 18c | `CFG-34`: NaN hashed through `Float#hash` (not folded) | `configuration_test.rb` | 1 failure: `… hash alike … Expected: 2381645902746858947 Actual: -2734971840657689398` — the two payloads hashing apart, per process. **Identical on 3.2.11** (`2634424562467063559` against `-899104896666105843`) |
| 19a | `CFG-35`: 501 retryable | `retryability_test.rb` | 1 failure: `every 5xx is retryable except 501 and 505 … 501. Expected: false` |
| 19b | `CFG-35`: 408 not retryable | `retryability_test.rb` | 3 failures: `408 and 429 are retryable … code 408`, the 1xx–4xx case (`408. Expected: true`) and the XCUT-7 subset case |
| 20 | `CFG-36`: the blank guard removed | `build_info_test.rb` | 2 failures: `a blank component resolves to the non-blank 'unknown' … Expected: "unknown" Actual: ""` and `SDK_VERSION. Expected "0.0.0" to be frozen?` |
| 21 | `CFG-37`: `Builder#key!` raising a bare `::ArgumentError` | `configuration/builder_test.rb` | 1 failure: `every mutating operation fails fast … [Dexpace::InvalidArgumentError] exception expected, not Class: <ArgumentError>` |
| 22 | the context-store cap wired as an unsynchronised `@default \|\|= new(cap: …)` | `context_store_config_test.rb` | 1 failure: `XCUT-11: 16 threads reaching .default first get ONE store, even under a slow seam … Expected: "1" Actual: "16"` — sixteen stores published. **Identical on 3.2.11** (`Actual: "16"`) |
| 23a | `HostPattern`'s `Regexp.new` without `timeout:` | `proxy/host_pattern_test.rb` | 1 failure: `the pattern is compiled once at construction with a per-pattern timeout … Expected nil to not be nil.` |
| 23b | `HTTPDate::GRAMMAR` without `timeout:` | `http_date_test.rb` | 1 failure: `the grammar is one pattern, compiled once with a per-pattern timeout … Expected nil to not be nil.` |
| 24 | `TypedReads#guard_materialization!` back on the constant | `io_ceiling_test.rb` | 2 failures: `TypedReads' materialisation guard honours a configured ceiling … Dexpace::StreamError expected but nothing was raised.` and the `Buffer#snapshot` case |
| 25 | `CFG-2`: emptiness made chain-wide (an empty property falling through) | `configuration_test.rb` | 1 failure: `CFG-2 asymmetry … Expected: "" Actual: "fallback"` |

After review round 0's repair (2026-09-17), one per line the repair made load-bearing, each
applied by hand on 4.0.6 against the repaired suites and reverted. Guard 22 is re-run because the
repair moved the seams outside the lock, which the round-0 fixture — a 50 ms seam — can no longer
see: the slowed step is now `new`, and the round-0 shape gives sixteen again.

| # | Guard (single-edit mutation) | Suite | Result on 4.0.6 |
|---|---|---|---|
| 26 | `CFG-22` (R0-2): `#to_s` printing the username again (`user:****@`) | `proxy_test.rb`, `ModelTest` | 2 failures: `#to_s and #inspect mask the username AND the password … Expected "http://AdminUserName:****@proxy.internal:8080" to not include "AdminUserName"` and the one-credential shapes |
| 27 | `CFG-22` (R0-2): `#inspect` printing the username again (`username: username`) | `proxy_test.rb`, `ModelTest` | 2 failures: `… Expected "#<Dexpace::Proxy … username=\"AdminUserName\" password=\"****\" …>" to not include "AdminUserName"` and `Expected … to include "username=\"****\" password=nil"` |
| 28 | `CFG-28` (R0-1): `.resolve` defaulting to `Configuration::EMPTY` rather than `Dexpace.configuration` | `proxy_test.rb`, `NonProxyTest` | 1 error: `an explicit .resolve with no argument reads the process-wide slot: NoMethodError: undefined method 'host' for nil` — the slot's fake seam never read |
| 29 | R0-4: the chain read back under the mutex (`synchronize { @default \|\|= new(cap: configured_cap) }`) | `context_store_config_test.rb`, `RaceTest` | 1 failure: `the configuration seams run outside the store's mutex, never under it … Expected: "true true" Actual: "true false"` — `Mutex#owned?` true inside the seam |
| 30 | R0-4: the lock-free fast path dropped (`def default = build_default`) | `context_store_config_test.rb`, `RaceTest` | 1 failure: `after the first call, .default reads neither seam again … Expected: "true true" Actual: "true false"` — the seams run on every call |
| 22′ | the context-store cap wired as an unsynchronised `@default \|\|= new(cap: cap)`, re-run against the slowed-`new` fixture | `context_store_config_test.rb`, `RaceTest` | 1 failure: `16 threads reaching .default first get ONE store, even under a slow new … Expected: "1" Actual: "16"` |
| 31 | R0-5: `Deadline.validate` moved back below `return self if settled?` | `async/future_deadline_test.rb`, `NonExpiryTest` | 1 failure: `a settled future still refuses a non-numeric deadline and a bad clock … Dexpace::InvalidArgumentError expected but nothing was raised.` |
| 32 | `CFG-37` (R0-6): `Builder.new` stringifying its seeds again (`@overrides[key.to_s] = value.to_s`) | `configuration/builder_test.rb`, `BuilderContractTest` | 1 failure: `Builder.new refuses a nil or blank seed and a nil or non-callable seam … {"K" => nil}. Dexpace::InvalidArgumentError expected but nothing was raised.` |
| 33 | `CFG-24` (R0-8): round 0's `string(HTTPS_PROXY) \|\| string(HTTP_PROXY)` preference restored | `proxy_test.rb`, `EnvironmentLayerTest` | 1 error: `a blank HTTPS_PROXY from any tier does not mask HTTP_PROXY: NoMethodError: undefined method 'host' for nil` — the override's `""` masked `HTTP_PROXY` |

R0-7's repair is a hermeticity change with no line of `lib/` behind it, so it has no mutation;
its proof is the three suites run green with `HTTPS_PROXY=http://corp-proxy.example:3128`, with a
port-less `HTTPS_PROXY=http://corp-proxy.example`, and with `MAX_MATERIALIZED_BYTES=3
MAX_TRACKED_CONTEXTS=2` exported into the test process on 4.0.6 — the first of which reproduced
R0-1 red before the repair, exactly as the review reported.

Beside the mutations, four facts the suites carry as guards of their own were seen holding on
every row: `Data#with` skipping the `initialize` override on 3.2.11 (every 5a `#with` case routes
through `Model#with` and is green there), `Thread.current[]` inherited by neither a child fiber
nor a new thread (fact 3, asserted), `Queue#pop(timeout: -1)` returning nil at once (fact 8,
asserted) and `Float#hash` disagreeing about the two NaN payloads (the precondition every NaN
case asserts before its own claim).

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returns 52 note entries
across 21 files (the design counted 36 across 18; five phases have filed notes since);
`--section conflicts --brief` returns the six harvested conflicts, every one
`[overridden by notes/…]`, and 19 note-side entries. `--prefix-info CFG` reports 38 IDs, 29 MUST
/ 8 SHOULD / 1 MAY, 38 of 38 substantive, 0 roll-ups; `--gaps CFG` returns nothing. `--req` was
run per task over that task's IDs — every `CFG` ID returning at least one `[appendix-B roll-up]`
hit beside its substantive one, exactly as the charter measured, and the substantive entry was
read beside the roll-up in every case. The design's seven audit groups are recorded there; at
implementation the four that bite were re-checked against the built code:

| Group | Result at implementation |
|---|---|
| Observability, configuration and redaction | Clean against the built code: every `CFG` rule under `configuration` is either adopted verbatim or narrowed by a design row that stands (`P5-4` seconds, `P5-14` element kind, `P5-12` the owned grammar). `retry-and-resilience/7954a775`'s conclusion that the status classifier lives in a `Dexpace::Resilience::Policy` module is the design's §5 shape, which the 5a design's `R1` overrides with `Dexpace::Retryability` and records as `P5-1`; phase 6a's `Policy` computes from it. No note added |
| Fiber scheduler, thread safety | Clean against the built code: three mutexes in 5a — `Dexpace.configure`'s slot swap, `ContextStore.default`'s first-call construction (this phase's, replacing 4a's load-time assignment) and `FakeClock`'s (a test double) — each held across an assignment or a construction and never across a callback or a source callable; no 5a code path holds two locks; `Clock#sleep`'s queue is its own synchronisation; `Timeout.timeout`, `Thread#raise` and `Thread#kill` appear nowhere and `clock_test.rb` asserts it by text; every thread every suite starts is joined, which `DexpaceTestCase` enforces. `concurrency-and-async/f414b864`'s note governs the slot exactly as the charter said |
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for every 5a file; `api-design/b0e18938` is why `ConfigParsers`, `DeepValue`, `ProxyResolution`, `Configuration::Guard`, `Clock::Guard`, `Async::Deadline`, `Type::NAMES`/`ALL`, `HTTPDate::MONTHS`/`GRAMMAR`, `UUID::SLOT`, `Async::ELAPSED`/`NO_SCHEDULER` and `HostPattern#matcher` are private; `api-design/6ea28c9c` (never nil for absent) is overruled by requirement for the lookup family, as the design records; `api-design/1d9e6e0b`'s keywords-everywhere shapes every accessor and the two widened pivot methods |
| Minitest conventions | `testing/4ef070df` is honoured: every suite that touches the process-wide slot restores it in `teardown` or an `ensure`, and every case that needs a fresh `ContextStore.default` asks a fresh process; `testing/26b866e1` is honoured: no `assert_nothing_raised`, every never-throw case asserting `assert_nil` and the captured warning; `testing/7ecef8e8`/`630ba094` name the three doubles fakes; `testing/f36a19cd`'s round-trip property tests exist for `Type.of`, `HostPattern.of` and `HTTPDate` with a pinned, logged seed |

The design filed no note and this phase files none: nothing execution found was a harvested rule
stated wrong. Two corrections against *committed phase documents* — the plan's `"nan".to_f`
witness and the design's `nil` void value — are recorded under "Deviations from the plan" and the
design's As-built addendum, where a finding against a phase document goes.

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate.
Items 1 through 9 are where the tree as built overrode the plan's assumptions; the rest are this
build's own.

1. **The configuration-source double is `FakeConfigSource` in `fake_config_source.rb`, not the
   plan's `FakeSource` in `fake_source.rb`.** `test/support/fake_source.rb` exists: it is phase
   3a's `FakeSource`, an `IO-17` double implementing `#read_into(dest, count:)`, required by four
   body suites, and the plan's file would have overwritten it. One double per file (P5-58).
2. **The scheduler double is `ParkingScheduler` in `parking_scheduler.rb`, not the plan's
   `ProbeScheduler`.** `test/support/probe_scheduler.rb` exists: phase 2's `ProbeScheduler`
   records hooks and runs ready fibers in a nested loop with a no-op `#kernel_sleep`, so it cannot
   drive a timed wait; the plan's parking design is a different double at the same path. Phase 2's
   file and suite are untouched. `#fiber_interrupt` is defined, as phase 2's note says 4.0.6 warns
   without it (P5-58).
3. **All three doubles are top-level classes, not `Dexpace::FakeClock` and friends.** Every one of
   the twenty-one doubles under `test/support/` on `main` is top level, and a phase-5 convention
   that departed from twenty-one files for three would need a reason the plan does not give; the
   5b and 5c plans namespace theirs and are theirs to reconcile (P5-58).
4. **`ContextStore.default` is a synchronised first-call construction, not the plan's
   `@default ||= new(cap: …)`.** The plan's fence is the unsynchronised read-modify-write phase
   4a's reviewed design rejected (XCUT-11) and would have failed 4a's fresh-process test. Of the
   two honest options — read the cap at load, which only the environment tier could ever reach,
   or construct under a mutex on the first call — the second is what the design's own words ("at
   first construction"; "a `Dexpace.configure` after the first promotion does not resize it")
   describe and the only one that lets a configure at boot reach the cap. Phase 4a's
   fresh-process case is rewritten to assert the new shape, the change to an earlier phase's test
   recorded as P5-55 with the reason; `context_store_config_test.rb` adds the race the mutex is
   for.
5. **The ceiling's readers moved to the function.** The design's open question 5 recommended "a
   module function … that 3a's call sites call", the plan's Task 13 left the six constant readers
   in place, and a public function nothing in core calls is the `TeeSink#clear_tap` shape both
   documents refuse. The grep found six reads of the constant's value at five sites; all five now
   read `Dexpace::IO.max_materialized_bytes`, so `Dexpace.configure` genuinely governs the ceiling
   (P5-56). `Buffer#snapshot` reaches it through `TypedReads#guard_materialization!`.
6. **`Completer#await`'s cancellation stays positional** — `await(cancellation = nil, deadline:
   nil, clock:)` — as phase 2 shipped it and as the plan's own note says; the RBS mirrors follow.
7. **The sixteenth `lib/` file became seventeen: `configuration/builder.rb`.** The plan nests the
   Builder inside `configuration.rb`; phase 1 files every builder beside its model
   (`headers/builder.rb`, `request/builder.rb`), `Metrics/ClassLength` measures the outer class
   with its nested one, and a file of its own gets its own `sig/` and `test/` mirror (P5-51).
8. **Every `module_function` in the plan's fences is `extend self`**: `Style/ModuleFunction` is
   `extend_self` in `.rubocop.yml` (`data-modeling/3775e9d7`), which the plan's stand-ins never
   met. The manifest therefore carries `Dexpace::UUID#generate`, `HTTPDate#format`/`#parse` and
   `Retryability#retryable_status?` as instance rows, the shape `PercentEncoding` and `URL`
   already have, while `Dexpace::Async.delay`, `Dexpace.configure` and friends are singleton rows
   because their modules are namespaces.
9. **The private constants got `sig/` mirrors.** The design says the three get "neither" a
   `sig/` nor a `test/` mirror; the tree's rule, from `hooks.rbs` through the two pipeline
   drivers, is that a `private_constant` gets its `.rbs` with a comment saying why and no `test/`
   mirror, because the strict `core` Steep target refuses an undeclared constant at a call site
   (P5-57). Steep also needed the private module-level constants declared — `ELAPSED`,
   `NO_SCHEDULER`, `MONTHS`, `GRAMMAR`, `NAMES`, `ALL`, `SLOT` — and three private helper modules,
   `Configuration::Guard`, `Clock::Guard` and `Async::Deadline`, exist because an instance method
   cannot call a private singleton method with the explicit receiver it needs, and `Configuration`
   builds `EMPTY` at the foot of its own class body before a `private` section could define a
   helper.
10. **`Proxy::HostPattern` is a one-member `Data` with the compiled `Regexp` as a private instance
    variable, not the plan's `Data.define(:glob, :matcher)`** whose `.build` had to accept and
    ignore a `matcher:` keyword (P5-53). Equality, `#hash` and `#with` are over the glob alone;
    the ivar survives `dup`, and `Model#with` recompiles it through `.build` on every Ruby.
11. **`Proxy::Type` ships no public `.build`.** The plan's `Type.build(name:)` would mint a second
    `HTTP` that is `==` the constant and not `equal?` to it; a closed set follows `Pipeline::Stage`
    — `.new` and `.[]` private, `.of` the only lookup (which canonicalises a `Type` argument back
    to its constant), `#with` refusing (P4-56's shape, recorded as the row on `CFG-22`).
12. **`HTTPDate.parse` checks every component against what `Time.utc` built** (P5-54): the
    plan's rescue around `Time.utc` catches day 32 and minute 60 but not 31 November, 29 February
    1995, hour 24 or second 60, which `Time.utc` silently normalises into the next month, day or
    minute — found while writing the impossible-date cases the plan's Step 1 lists.
13. **`Async.delay`'s void value is `true`, not the design's `nil`** — the plan's own finding,
    carried through: `SEAM-16` makes a `nil`-response `Settlement` unconstructible (P5-52).
14. **The `CFG-34` NaN witness is `0.0/0.0` and `-(0.0/0.0)`**, the plan's correction of the
    design's `"nan".to_f`, which is `0.0`; `refute_equal(a.hash, b.hash)` makes the precondition
    visible in the test.
15. **Every argument the plan's fences left unchecked is checked**: `Clock#sleep` and
    `Async.delay` refuse a non-numeric duration and a non-token `cancellation:`; `Future#wait` and
    `#value` refuse a non-numeric `deadline:` and a `clock:` without `#monotonic`;
    `IO.max_materialized_bytes`, `Proxy.resolve` and `Retryability.retryable_status?` refuse the
    wrong argument type with `Dexpace::InvalidArgumentError`; `Sources.from_hash` refuses a
    non-Hash and a nil value; `Proxy.build` refuses a non-`HostPattern` entry, a blank host and a
    non-Integer port; a non-positive configured cap or ceiling falls back to the constant rather
    than raising out of the first promotion or the first materialisation.
16. **`Dexpace.configure` raises without a block by `block_given?` and `#derive` likewise**,
    rather than `Model.required!("… block", mutator)` over a captured `&mutator`, so a block is
    never captured into a Proc only to be called once.
17. **`Configuration::Builder` includes `Dexpace::Builder`**, phase 1's builder contract, which
    every other builder in the tree includes and the plan omitted.
18. **`proxy_test.rb` uses phase 2's `WarningCapture.record`** rather than the plan's
    `ProxyWarningSink`, a second capture mechanism the brief forbids.
19. **`Fact 9`'s subprocess clears `RUBYOPT`**: under `bundle exec` the child inherits
    `-rbundler/setup`, which loads RubyGems and `RbConfig` before `--disable-gems` can keep them
    out, so the plan's `ruby --disable-gems -e …` prints `"constant"` from inside the suite. The
    fresh-process cases in `context_store_config_test.rb` clear it for the same reason.
20. **`matrix_facts_test.rb`'s fact 5 checks `Random.const_defined?(:DEFAULT)`** rather than
    `defined?(Random::DEFAULT)`, which `Lint/DeprecatedConstants` flags.
21. **`Metrics/ClassLength` and `Metrics/ModuleLength` shaped three files**: `Completer` gained
    the `Deadline` module beside it rather than a private `#wait_until`; `ProxyResolution`'s URL
    split became `split_url` + `url_problem` and the credentials decode a one-liner; every suite
    over 100 lines is split into nested `DexpaceTestCase` classes, the shape every phase since 3b
    used.
22. **Open question 2 is settled, not deferred**: a user-space `de_DE.UTF-8` built with
    `localedef -i de_DE -f UTF-8` into a scratch `LOCPATH` — nothing installed system-wide —
    renders `date` as "Sonntag November" and `Time#httpdate` as "Sun, 06 Nov 1994 08:49:37 GMT" on
    3.2.11, 3.4.10 and 4.0.6. CRuby's `strftime` is its own implementation over English tables
    and never consults the locale; `HTTPDate.format`'s YARD block says so and `P5-12`'s formatting
    half stands.
23. **Task 1's "install ruby@3.2.11 and ruby@4.0.6" was already done**: all four interpreters are
    mise installs. The six floor-straddling facts were re-run on 3.2.11, 3.4.10 and 4.0.6 as one
    script before any code was written, and `matrix_facts_test.rb` asserts them on every row:
    every fact holds across the range, with the one known split — `Data#with` skips an
    `initialize` override on 3.2.11 and runs it on 3.4.10 and 4.0.6 — deliberately not asserted,
    because `Model#with` is the mitigation and phase 1's suite is its proof.

Items 24 through 26 are review round 0's (2026-09-17), each fixed on the owning branch of the
stack and each a place where the build read a requirement or a rule more narrowly than its text:

24. **`Proxy#to_s` and `#inspect` mask the username as well as the password.** The plan's Task
    14 fence quotes `CFG-22`'s parenthetical — "never emit username/password in cleartext" —
    and then emits the username beneath it, and the build followed the fence (R0-2). Both
    credentials now render as `****` when present and as nothing when absent, so the shape says
    which is set and never what it is; `P5-7`'s reasoning about `#inspect` being the likeliest
    leak path is unchanged and now covers both members. Not a ledger row: it is the
    requirement's own text, not a narrowing of it.
25. **The `CFG-28` default-argument case is hermetic.** The plan's case asserted `assert_nil
    Dexpace::Proxy.resolve` against the empty slot, whose environment seam is the real `ENV`, so
    the suite read the host's `HTTPS_PROXY` and failed wherever one was set — the very failure
    the suite's own header warns about (R0-1). The case now installs a fake seam in the slot
    through `Dexpace.configure`, asserts the argument-less call reads it, and resets in `ensure`.
    `io_ceiling_test.rb` and `context_store_config_test.rb` had the same shape on two improbable
    keys and were closed the same way (R0-7): an empty fake in the slot's environment seam, and
    `MAX_TRACKED_CONTEXTS` cleared in every fresh child by default.
26. **`ContextStore.default` reads the chain outside its mutex.** The round-0 shape ran
    `configured_cap` — two caller-supplied callables — inside `synchronize`, against the rule
    `Dexpace.configure` itself follows and with a non-reentrant mutex a seam could deadlock
    (R0-4). Now the chain is read before the lock, only the `||=` runs under it, and a lock-free
    read of the published reference sits in front, so a promotion after the first takes no lock
    and runs no seam — the shape `Dexpace.configuration` has. A losing racer's read is discarded.
    The race fixture changed with it: a slow seam no longer discriminates the mutex, so the
    slowed step is `new` (guard 22′), and two cases observe the seam running with the mutex
    unowned and a later `.default` running no seam. `P5-55`'s row is amended to say so. Round 0
    also moved `Completer#await`'s keyword validation above the settled short-circuit (R0-5),
    made `Configuration::Builder.new` validate its seeds and seams through the setters' own
    guards (R0-6), and made a blank `HTTPS_PROXY` from any tier absent for the preference
    (R0-8); each is on its ID's row and in the second guard table, none is a deviation.

## Findings routed

- **Phase 4a's context-store cap deferral read "one wiring, no signature change"** and was
  written against a load-time assignment; picking it up honestly changed the construction shape
  (item 4). Recorded as P5-55 in the design's As-built addendum and in the roadmap's status note;
  phase 4a's checklist and design are its records and are not edited.
- **The design's "thirteen `sig/` mirrors" and "no `sig/` mirror" for the private constants**
  disagree with the tree's rule (item 9). Recorded as P5-57; nothing to route — the tree's rule
  is phase 2's P2-15 as phase 4a and 4c already applied it.
- **The design's module layout folds the Builder into `configuration.rb`** (item 7). Recorded as
  P5-51; the design is not edited.
- **`retry-and-resilience/7954a775`** (a harvested conclusion from design §5) places the status
  classifier in `Dexpace::Resilience::Policy`; the 5a design's `R1` and `P5-1` already override
  it and phase 6a computes from `Dexpace::Retryability`. Already owned; nothing to route.
- **The `knowledge-lookup` skill's audit-group finding** (36 of 38 `CFG` IDs from `--section
  rules`) is the design's, already owned by the skill's tenth row; verified, not re-recorded.
- **`CFG-35`'s throwable half** is owned by phase 6a's plan Task 3, recorded in the design;
  verified present there, not re-recorded.
- **Review round 0's nine findings** (2026-09-17) all closed in this stack: the non-hermetic
  `CFG-28` case (R0-1, blocking), the cleartext username (R0-2, should-fix), and the seven nits
  — `CLAUDE.md` citing P5-52 for `Async.delay`'s raise-rather-than-degrade decision, which is
  P5-9 (R0-3); the seams under the store's mutex (R0-4); deadline validation skipped on a settled
  future (R0-5); `Builder.new`'s nil-to-`""` seed (R0-6); the ambient-key reads in the ceiling and
  cap suites (R0-7); a blank `HTTPS_PROXY` override masking `HTTP_PROXY` (R0-8); and the `CFG-26`
  empty-token reading not tied to the plan's self-review item 4 (R0-9). Each is on its ID's row,
  in the second guard table, or in deviations 24–26; nothing was disputed and nothing deferred.
- **`docs/first-release.md`** is untouched: the Unsatisfied-MUSTs entry already names `CFG-20`'s
  fourth clause (added 2026-09-13), which the `CFG-20` row cites; no line of that file changes.
- **`docs/sdk-design-ruby/` §8.2, §8.3, §10.16 and §10.17 are frozen**: the addenda that would
  state the four-tier chain's substituted third source as built, the queue wait, the first-call
  store construction and the configured ceiling, and the consolidation of `P5-1`–`P5-15` and
  `P5-51`–`P5-58` into design §10, are a human's, as they were for 3a, 3b, 4a, 4b and 4c. No
  frozen sentence is contradicted by this build, so `docs/first-release.md`'s `C1`–`C14`
  paragraph gains no `C15`.

## Postponed work

The one item the design postponed keeps its owner: `CFG-35`'s throwable half is phase 6a, Task 3
(`docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry.md`), with `XCUT-6`'s capability and
`Dexpace.each_cause`; `ProtocolError#retryable?`, the baked flag phase 4b postponed, is Task 6 of
the same plan and now computes from `Dexpace::Retryability`. Of the four items earlier phases
postponed to this window, three landed here — the pivot's `deadline:` keyword (phase 2's P2-5,
Task 8), the context store's configured cap (phase 4a, Task 13) and the ceiling half of the
body-logging caps (phase 3b, Task 13) — and the fourth, the two logging-body wirings, needs `5b`'s
enablement setting and is `5b`'s (its plan, Tasks 14–15); the charter puts the mark on whichever
of `5a`/`5b` lands second, and 5a leads. `IO.max_materialized_bytes`'s named callers are the five
readers this phase moved; `5b`'s preview-size wiring and phase 8's adapters are the next. The
items the design lists as untouched — the unsatisfied MUSTs, the recovery-stack retry engine,
`close_quietly`'s second route, presence-gated auto-activation, `SEAM-25`'s event, the no-op
span and tracer protocols, the fakes' move to `dexpace-conformance`, `IO-38` on a GVL-free
interpreter, `Pipeline.standard`, `BODY-36`, `OBS-32` and `OBS-37` — were re-read on 2026-09-17
and keep the owners the design records. The implementation postponed nothing further.
