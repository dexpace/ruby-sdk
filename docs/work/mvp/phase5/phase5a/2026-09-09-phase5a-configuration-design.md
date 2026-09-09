# Phase 5a — Configuration and the Clock

**Status:** Draft, for review. Written 2026-09-09, against
`docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`, which is this sub-phase's charter.

## Purpose

Sub-phase 5a builds the layered configuration chain every later limit reads from, the injectable time seam
every later wait routes through, the environment-driven proxy model — **which §16.5 gives its own section and
which the charter's rejected cut B keeps welded to the chain, because §8.2's proxy resolution is "one
deviation applied twice, not two deviations"** — and the five free-standing utilities §16.6 files beside
them: RFC 1123 dates, a deliberately non-cryptographic UUID generator, deep value equality, the built-in
retryability classifier and the build/runtime descriptor. Thirty-eight `CFG` IDs, one specification chapter,
one gem.

**It is the sub-phase the most downstream work waits on**, and that is the whole of the charter's reason for
putting it first. Four register rows name it — `DEF-28`, `DEF-34`, `DEF-36`, and, once `R1` below is
resolved, `DEF-38`'s source — and two objects phase 6 cannot start without are built here: `CFG-15`'s
cancellable wait, which is why `RECOV-27` was moved to phase 6 under `DEF-35`, and `CFG-14`'s well-known key
for the retry-attempt cap, which is where `RETRY-12`'s defaults come from. None of that makes 5a a
dependency of `5b` or `5c`; the charter is explicit that every phase-5 boundary is a convenience, and this
document states that independence rather than inheriting a chain by habit.

Six decisions reshape what a plan can write, and each was forced by a fact run on a real interpreter rather
than by taste.

- **`Time.httpdate` is not an RFC 1123 parser, and the normalise-then-delegate route inherits laxities
  `CFG-31` forbids.** The charter recorded that it rejects three of `CFG-30`'s four zone tokens. What the
  charter did not record, and what decides `R2`, is that it also **accepts RFC 850 and asctime** —
  `Time.httpdate("Sun Nov  6 08:49:37 1994")` parses, with no comma anywhere — and accepts a leading space.
  `CFG-31`'s clause is "the weekday strip only applies to the well-formed `'Xxx, '` three-letter-plus-comma
  prefix", so a parser accepting a form with no comma at all is not honouring it, even though the specific
  conformance case (`Mon 01 Jan 2024 00:00:00 GMT`) does fail. 5a owns an anchored grammar and does not
  delegate parsing (`R2`).
- **A `Random` in `Fiber[]` is shared mutable state across threads, and `Thread.current[]` — the carrier
  `CLAUDE.md` warns off — is the correct one here.** Verified: `Fiber[:k] = o` then
  `Thread.new { Fiber[:k].equal?(o) }` is `true`, so fiber storage hands the *same generator object* to a new
  thread; `Thread.current[:k]` is inherited by neither a child fiber nor a new `Thread`, so no two execution
  contexts ever share one. The asymmetry `docs/knowledge/notes/observability.md` records for the diagnostic
  context cuts the other way for a PRNG, and `CFG-32`'s words are "without shared mutable state" (`R3`).
- **`Thread::Queue#pop(timeout:)` really does unmount the fiber under a registered `Fiber.scheduler`, and
  that was measured rather than assumed.** A minimal `Fiber::Scheduler` was written for this document; under
  it, a 50 ms `q.pop(timeout: 0.05)` calls the scheduler's `#block` hook exactly once and `#kernel_sleep`
  zero times. §8.3's conditional claim is therefore verified for the mechanism `CFG-15` ships, on 3.4.10.
  It is also what makes `R6`'s answer honest: with no scheduler registered there is no non-blocking path at
  all, so `CFG-18`'s delay **raises** rather than quietly starting a thread.
- **Neither `SocketError`, `Timeout::Error` nor `OpenSSL::SSL::SSLError` is defined in a bare interpreter,
  and none of the three is an `IOError`.** Verified: `defined?(::SocketError)` is `nil` without
  `require "socket"`, `SocketError < StandardError`, `Errno::ETIMEDOUT < SystemCallError` and
  `Timeout::Error < RuntimeError`. So `CFG-35`'s "IO/timeout error" has no expressible spelling in core, and
  `is_a?(::IOError)` would classify phase 3a's `Dexpace::StreamError` retryable while classifying every real
  transport timeout not retryable — wrong in both directions, and then fixed as a "hard contract". That is
  what splits `R1`.
- **Ruby's `Integer("010")` is 8, and every parse in the chain passes base 10 explicitly.** This is not a
  theoretical hazard: a deployment setting `MAX_RETRY_ATTEMPTS=010` would silently get 8. Verified
  `Integer("010")` → 8 and `Integer("010", 10)` → 10, which is design §6.1's octal reason arriving at its
  second subsystem.
- **A `Data` holding a callable is not Ractor-shareable, so `Configuration` makes no shareability claim.**
  Verified `Ractor.make_shareable` on a frozen `Data` holding a lambda raises `Ractor::IsolationError`.
  `CFG-11` requires the two sources to be callables, so the claim `data-modeling/5bc538ba` already narrows is
  narrowed once more, deliberately.

5a ships no logger, no event, no redactor, no span and no meter. Its whole test surface is value objects, one
process-wide slot behind a mutex, one bounded wait, and six parsers.

## Governing documents

- `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md` — the charter. It fixes 5a's 38 IDs, the
  fifteen spec-forced boundaries and risks `R1`–`R7`. `R8`–`R15` belong to `5b` and `5c` and are not touched
  here.
- `docs/product-spec/16-configuration.md`, read in full — 62 lines, including the per-ID `*Conformance: …*`
  clauses appendix C does not carry — with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text of all 38
  `CFG` IDs and of `XCUT-5`, `XCUT-6`, `XCUT-7`, `XCUT-9`, `XCUT-13`, `XCUT-19`, `XCUT-21`, `ASYNC-3`,
  `ASYNC-4`, `RETRY-12`, `OBS-35`, `SEAM-1`, `SEAM-25`, `SEAM-29` and `NFR-4`, each of which fixes something
  5a must carry, share or deliberately not build.
- `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` in full — §8.2 (the four-tier chain, the
  typed accessors, the proxy model, dates, identifiers, deep equality) and §8.3 (the clock, the wait, the
  prohibition) are 5a's; §8.1 is read because `CFG-21`'s close route and `CFG-24`'s warning both end in it and
  because the duck-typed sink is the sentence 5a must not pre-empt.
  `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items 4, 5, 7, 16 and 17;
  `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` items 1, 4,
  11, 15 and 20; and §12's `CFG` row ("*Deferred:* none").
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-5 row, the five cross-phase
  obligations, the nine cross-cutting constraints and the ✅ / 🚫 / ⏳ / N/A legend this sub-phase's checklist
  uses verbatim.
- `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md` for the require allowlist and
  its denylist; `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` for `Dexpace::Model`,
  the builder split and `Dexpace::InvalidArgumentError`;
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` with its plan for the async pivot,
  `Cancellation`, `Closeable`, `Registry`, `Hooks` and `DEF-28`'s declined `deadline:`; the phase-3a and
  phase-3b designs for `MAX_MATERIALIZED_BYTES` and the two logging bodies; and all three phase-4 sub-phase
  designs for their *interface surface later phases may cite* tables.
- `docs/deferred-items.md`, `docs/open-items.md`, `docs/deviations.md`, `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

## Scope

### The 38 IDs, with dispositions

Thirty-eight IDs: **29 MUST, 8 SHOULD (`CFG-12`, `CFG-13`, `CFG-14`, `CFG-18`, `CFG-19`, `CFG-20`, `CFG-35`,
`CFG-36`), 1 MAY (`CFG-28`)**, derived mechanically from appendix C.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `CFG-1`–`CFG-18`, `CFG-21`–`CFG-33`, `CFG-36`–`CFG-38` | 34 |
| Implemented, satisfied **by construction** — this port's async pivot delivers the caller's own exception, so there is no completion/execution wrapper to unwrap and "a non-wrapper throwable MUST be returned unchanged" holds for every input. No `unwrap` method ships (`P5-11`) | `CFG-19` (SHOULD) | 1 |
| Partially satisfied — the NaN and signed-zero halves implemented; `CFG-34`'s boxed-versus-primitive **container-kind** clause recorded inapplicable per §11.15, and the inapplicability is not extended (`R4`) | `CFG-34` | 1 |
| Partially satisfied — `CFG-20`'s cancel-with-interrupt clause is `ASYNC-3`'s mechanism under a second ID and is unsatisfiable under §8.3; its other three clauses are met. ⏳ citing `DEF-18` **and** `OI-22`, with the unmet clause named in the row (`R7`) | `CFG-20` (SHOULD) | 1 |
| Partially satisfied — the **status** classifier ships here as `XCUT-5`'s single shared object; the **throwable** half is deferred as `DEF-40`, because core cannot name the error classes the clause is about (`R1`) | `CFG-35` (SHOULD) | 1 |

**Nothing in `CFG` is deferred outright**, which design §12's `CFG` row confirms. One clause of one SHOULD is,
and `DEF-40` is filed for it below rather than left in prose.

**Also shipped by 5a without owning a new ID**, per the charter:

- the `deadline:` keyword on `Dexpace::Async::Future#value` and `#wait` and the monotonic clock behind it
  (`DEF-28`);
- the configuration source `DEF-36` names for `Dexpace::ContextStore`'s cap, and the source `DEF-34` names
  for `Dexpace::IO::MAX_MATERIALIZED_BYTES` — `DEF-34`'s other two wirings need `5b`'s enablement setting and
  are `5b`'s;
- `CFG-14`'s well-known key constants, which `RETRY-12` and `OBS-35` both reference by name without either
  owning them.

`CFG-16` is `OI-15`'s **elapsed-time** counter and shares nothing with `CTX-4`'s **call-sequence** counter but
the adjective. This document writes the full phrase everywhere and never "the monotonic counter" unqualified,
which is the mitigation `OI-15` itself names.

### The canonical text the design turns on

Quoted from appendix C rather than paraphrased, because each fixes a decision below.

> **CFG-1** (MUST) — A configuration value lookup for a key MUST resolve in strict precedence order: (1) an
> explicit override registered for that exact key, (2) the environment-variable source queried by the exact
> key name, (3) the system-property source queried by the NORMALIZED key name, (4) the caller-supplied
> default (which MAY be null/absent).

> **CFG-2** (MUST) — An environment-variable value that is present but empty MUST be treated as absent, so
> the lookup falls through to the system-property layer (and ultimately the default) rather than resolving to
> the empty string.

> **CFG-9** (MUST) — Deriving a reconfigured configuration MUST be copy-on-write … The override map MUST be
> copied before the mutator runs (added/replaced/removed overrides never leak back to the receiver), while
> the environment and system-property source seams MUST be inherited by reference (shared, not copied) unless
> the mutator explicitly replaces them.

> **CFG-11** (MUST) — The environment source and the system-property source MUST be substitutable seams
> (injectable functions from key name to optional string), so conformance tests and applications can supply
> hermetic lookups without touching the real process environment.

> **CFG-15** (MUST) — The time abstraction MUST be an injectable seam exposing three operations: current
> wall-clock instant, a monotonic elapsed-time counter, and a blocking interruptible sleep. A shared default
> backed by the platform clock MUST be provided.

> **CFG-17** (MUST) — sleep MUST reject a negative duration with an argument error, MUST allow a zero
> duration (returning promptly, possibly yielding), and MUST honor cooperative cancellation/interruption:
> when interrupted mid-sleep it MUST re-assert the thread's interrupt/cancellation status before propagating
> the interruption so downstream handlers observe the cancelled state. Implementations SHOULD preserve
> sub-millisecond precision where the platform allows.

> **CFG-18** (SHOULD) — The async layer SHOULD provide a scheduled non-blocking delay: an operation that
> yields a future completing (with an empty/void value) after a given non-negative duration elapses on a
> provided scheduler, WITHOUT blocking a thread. A zero delay MUST complete the future immediately; a
> negative delay MUST be rejected; cancelling the returned future MUST cancel the underlying scheduled task
> so the scheduler thread is not held.

> **CFG-19** (SHOULD) — When surfacing the cause of a failed asynchronous operation, the subsystem SHOULD
> unwrap the platform's async-completion wrapper exceptions (the equivalents of a completion/execution
> wrapper) to expose the original underlying throwable … A non-wrapper throwable MUST be returned unchanged.

> **CFG-24** (MUST) — Resolving proxy options from configuration MUST follow this source precedence and MUST
> NOT throw on any malformed input (proxies are optional; invalid config yields null and a warning log): (1)
> the system-property layer first — host is https.proxyHost preferred over http.proxyHost, and the port MUST
> be taken from the SAME layer as the chosen host … credentials are read ONLY from
> https.proxyUser/https.proxyPassword (there is no http.\* credential fallback); (2) if no system-property
> host is set, the environment URL HTTPS_PROXY preferred over HTTP_PROXY, parsed as
> scheme://user:pass@host:port.

> **CFG-25** (MUST) — The proxy port MUST be explicit and within 0..65535; a missing, non-numeric, or
> out-of-range port MUST cause resolution to yield null (with a warning) rather than guessing a default port.
> When parsing a proxy URL, an absent port MUST be treated as invalid (no defaulting to 80/443), because the
> request's target scheme is unrelated to the proxy's listen port.

> **CFG-26** (MUST) — … Both forms MUST honor a backslash escape preceding the literal separator … and MUST
> trim tokens. Fragments that are empty are dropped; the observable order is split -> drop empty (before
> unescape/trim) -> unescape -> trim, so a whitespace-only fragment is retained as an empty token rather than
> removed.

> **CFG-30** (MUST) — RFC 1123 date PARSING MUST be tolerant in these specific ways: month names are
> case-insensitive; the zone token accepts 'GMT', 'UTC', '+0000', and '+00:00' (all normalized to the zero
> offset); and the leading weekday token is informational only and MUST NOT be validated against the actual
> date (a weekday inconsistent with the date is accepted; it is stripped, not parsed).

> **CFG-31** (MUST) — RFC 1123 parsing MUST be strict on the day-of-month-onward grammar: blank/empty input
> MUST fail with a parse error, and a malformed header missing the comma after the weekday MUST fail (the
> weekday strip only applies to the well-formed 'Xxx, ' three-letter-plus-comma prefix).

> **CFG-32** (MUST) — … It MUST be usable concurrently from multiple threads without shared mutable state.
> It MUST use a non-blocking randomness source (per-thread PRNG), and callers MUST treat the output as
> NON-cryptographic (suitable for request/trace IDs, not secrets).

> **CFG-34** (MUST) — Deep value equality MUST follow floating-point array semantics where NaN compares EQUAL
> to NaN and +0.0 compares UNEQUAL to -0.0 (for both primitive and boxed float/double arrays), and hashing
> MUST match that equality. An object array and a primitive array with the same numeric values MUST NOT be
> considered equal (distinct array kinds).

> **CFG-35** (SHOULD) — A shared retryability classifier SHOULD exist and treat these HTTP status codes as
> retryable: 408, 429, and all 5xx EXCEPT 501 and 505; and SHOULD treat a throwable as retryable iff it or
> any throwable in its cause chain is an IO/timeout error. Cause-chain traversal MUST be cycle-safe … Where
> the classifier is implemented, this exact status-code set is a hard contract so exception construction and
> the retry policy agree.

> **CFG-36** (SHOULD) — A static build/runtime descriptor SHOULD expose the SDK version and host runtime
> identity (runtime version, vendor, OS name) resolved once at load time, each falling back to a non-blank
> 'unknown' when unavailable, and SHOULD provide a default ordered identity-token list (SDK token then
> runtime token) for User-Agent-style composition. Every token MUST be non-blank so joined identity strings
> are never malformed.

Two IDs outside `CFG` are quoted because 5a is where each first becomes real:

> **XCUT-5** (MUST) — The baked retryability flag of a protocol (status-carrying) error MUST be computed ONCE
> at construction from a SINGLE shared status classifier, never hardcoded per status subclass. That
> classifier MUST treat 408, 429, and all 5xx EXCEPT 501 and 505 as retryable, and every other status as not
> retryable. The stored flag MUST always agree with the live classifier for that code. NOTE: this baked flag
> is a queryable property of the error; the retry step's actual eligibility gate for a protocol error is the
> configured retryable-status set (see XCUT-7) …

> **OBS-35** (SHOULD) — A log-level value SHOULD be resolvable from layered configuration … **The SDK MUST
> NOT bake in a default config key name.**

`OBS-35`'s embedded MUST and `CFG-14`'s "stable well-known key constants … for … SDK log level" are only
consistent one way, and 5a fixes it so `5b` meets it as an input: `Configuration::Keys::LOG_LEVEL` is a
**published name a caller may pass**, not a name any resolver falls back to. `5b`'s log-level resolution takes
its key as a required argument.

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `OBS-1`–`OBS-20`, `OBS-34`–`OBS-40` — the event object, the duck-typed sink, redaction, the diagnostic-context fold, `OBS-34`'s HTTP instrumentation step | `5b`. 5a emits `CFG-24`/`CFG-25`'s warning through `Kernel#warn` and `5b` adds the event beside it (`P5-8`) |
| `OBS-21`–`OBS-33` — the span, scope, tracer and meter protocols | `5c` |
| `CFG-35`'s **throwable** half — "retryable iff it or any throwable in its cause chain is an IO/timeout error" | 6, `DEF-40` filed below. Needs `XCUT-6`'s capability (phase 6) and `Dexpace::TransportError` (phase 8) |
| `XCUT-5`'s baked `#retryable?` on `Dexpace::ProtocolError` | 6 (`DEF-38`). 5a builds the classifier it computes from; phase 4b shipped the class without the predicate on purpose |
| `XCUT-7`'s **configurable** retryable-status set, default `{408, 429, 500, 502, 503, 504}` | 6. It is a different object from `CFG-35`'s built-in classifier and must not be conflated with it — `XCUT-5`'s own closing NOTE is the sentence a reader must not lose |
| `RETRY-12`'s default tuning constants — 200 ms base, ×2, 8 s cap, 0.2 jitter, 3 sends | 6. 5a ships the **key name** `Keys::MAX_RETRY_ATTEMPTS` and no value |
| `RECOV-27`'s cancellable inter-attempt wait | 6 (`DEF-35`). It is `CFG-15`'s object, which 5a builds; the retry engine that calls it is not 5a's |
| `ASYNC-3`, `ASYNC-4`, `PIPE-33`'s interrupt clause | 8 marks all three (`DEF-18`, §10.5). 5a meets the same prohibition at `CFG-20` and dispositions it rather than adding a fourth (`R7`) |
| `ASYNC-8`–`ASYNC-12` — capture, install and restore of the diagnostic context across a thread hop | 8. Not `CFG`; and `Thread.current[]`'s **non**-inheritance, which `R3` relies on, is exactly why it is the wrong carrier there |
| Propagating a deadline to `open_timeout`/`read_timeout`/`write_timeout` | 8. 5a's deadline bounds a wait; no socket exists in core |
| `XCUT-21`'s CSPRNG path, `AUTH-20`'s cryptographic nonces | 6. `CFG-32` and `XCUT-21` stay two code paths (boundary 8); 5a writes no `require "securerandom"` |
| `XCUT-11`'s shared-instance audit, `XCUT-14`'s bounded-map audit, `XCUT-19`/`XCUT-20`'s totality audits | 9. 5a builds two of the audited objects (`Configuration`, `Clock::SYSTEM`) |
| `TRANSPORT-3`, `TRANSPORT-8` — proxy *use* and header-drop reporting on a real adapter | 8. 5a ships `CFG-22`–`CFG-28`'s proxy **model and resolver**; nothing in core opens a socket |
| `Pipeline.standard` and any preset that installs an instrumentation step | 6 (`DEF-39`). 5a installs nothing |

**No segmentation design of its own.** 5a is one spec chapter, one gem, 38 IDs, under a segmentation design
that already exists at the `phase5/` level.

## Prerequisites, and the independence this sub-phase must state

**5a depends on `5b` and `5c` for nothing, and neither depends on 5a.** The charter's finding is that the
`CFG`↔`OBS` edges run in both directions and that no boundary in phase 5 is a dependency: `OBS-35` is a SHOULD
whose embedded MUST is a prohibition, and `CFG-24`/`CFG-25`'s warning and `CFG-21`'s close route are the edges
running back. 5a discharges its half of both without `5b`: the warning is `Kernel#warn` today, following phase
2's P2-6 precedent verbatim ("§8.1's facade does not exist until phase 5 and may add an event then; **it does
not replace this**"), and `CFG-21`'s close is already `Dexpace.close_quietly`, phase 2's. **A `5b` or `5c`
plan whose first task waits on `Dexpace::Configuration` has re-imposed a chain that does not exist.**

### From phase 0 — seventeen blocking gates, unchanged and unlowered

`gates:require_allowlist` — core's `lib/**/*.rb` may `require` only `monitor`, `uri`, `stringio`, `strscan`,
`time`, `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`. **5a adds nothing to
it** and requires exactly two entries already on it: `time`, for `Time#httpdate` (`CFG-29`), and `uri`, for
the proxy URL parse (`CFG-24`). It does **not** require `date` — `Date._iso8601` parses no duration at all
(verified fact 6) and `Date._httpdate` is rejected by `R2` — and it does **not** require `securerandom`, which
is allowlisted and which boundary 8 forbids `CFG-32` from reaching for. `logger` and `timeout` are on the
**denylist by name**, so a `require` of either fails with a message naming the release it left the default set
in, or naming §8.3, rather than a generic "not allowlisted". `R5` is where the allowlist would have grown and
does not.

`Dexpace/NoThreadInterrupt` is not background here: it is the direct and only cause of `CFG-20`'s unmet clause
(`R7`) and it is what makes `CFG-15`'s wait a queue wait rather than a sleep.

`Dexpace/NoTimeParse` bans `Time.parse`, `Date.parse` and `DateTime.parse` and points at `Time.httpdate`. 5a
meets it as a live constraint rather than a formality: `R2` finds that the sanctioned alternative does not
satisfy `CFG-30` either, so 5a writes a grammar and neither cop nor pointer is enough on its own.

`Dexpace/NoUriDefaultParser` binds every URL touch: the proxy resolver pins `URI::RFC3986_PARSER` for every
parse, and — a finding this document owns — uses `URI.decode_uri_component` and never
`URI::RFC3986_PARSER.unescape`, which emits `URI::RFC3986_PARSER.unescape is obsolete` on 3.4.10 against a gate
set that fails the build on warnings (verified fact 10).

`gates:surface_snapshot` and `gates:sig_diff` regenerate once, deliberately, in the phase's last task. Every
public constant below is `NFR-4`-locked at the first release tag, which is why each is named on purpose and
carries a Deviation Ledger row where design §8.2 did not already name it — and §8.2 names exactly two things
in Ruby, `Dexpace.configure` and `Dexpace.reset_config!`.

### From phase 1

- **`Dexpace::Model`** — `Model.required!(name, value)` raising `Dexpace::InvalidArgumentError` with the one
  message form `"<name> is required"` (`SEAM-29`), which is where **every** `CFG-37` guard routes;
  `Model.own(collection)` = `Ractor.make_shareable(collection, copy: true)`, which is how `CFG-8`'s defensive
  copy is made and frozen in one call; `Model.frozen_string`; and the `#with` override that routes through
  the validating `.build`, because `Data#with` does not invoke an `initialize` override on 3.2.11.
- **`Dexpace::InvalidArgumentError < ::ArgumentError`.** `CFG-37`'s fail-fast guards, `CFG-17`'s negative
  duration and `CFG-31`'s parse failure all raise it. **`Dexpace::ArgumentError` is never defined** (P1-3).
- **Public constants are flat unless the design namespaced the subsystem** (P1-1). §8.2 namespaces nothing, so
  `Dexpace::Configuration`, `Dexpace::Clock`, `Dexpace::Proxy`, `Dexpace::HTTPDate`, `Dexpace::UUID`,
  `Dexpace::Retryability` and `Dexpace::BuildInfo` are flat, and each carries a ledger row.
- **No `.build` is a bare `new` wrapper**; validation lives in each `Data` type's `initialize`, and a
  validating constructor coerces as well as checks — which is how `Proxy::HostPattern` compiles its `Regexp`
  once at construction (`CFG-23`) and still round-trips through `#with`.
- **`downcase` takes no argument**, everywhere. `CFG-3`'s key normalisation and `CFG-6`'s `true`/`false` fold
  both depend on it, and `Dexpace/NoLocaleCaseFold` is what makes that a rule rather than a habit.
- **`Regexp.new(source, timeout:)` per pattern, never `Regexp.timeout`.** 5a compiles four families of
  pattern — `CFG-23`'s glob translation, `CFG-26`'s escape-aware separator, `CFG-30`'s date grammar and
  `CFG-7`'s duration grammar — and every one carries its own timeout, including the anchored fixed-width date
  pattern that cannot backtrack. Phase 1 applied the rule to a two-character hex pattern; 5a does not argue
  its way out of it either.
- **`Dexpace::URL.parse!`** exists and converts `URI::InvalidURIError` into `Dexpace::InvalidArgumentError`.
  `CFG-24` may **not** use it: `CFG-24` forbids throwing on any malformed input, so the proxy resolver calls
  `URI::RFC3986_PARSER.parse` inside its own `rescue` and never routes through a helper whose contract is to
  raise.
- **`RequestOptions#timeout` is a `Float` of seconds**, and there is no `Dexpace::Duration` and no integer
  parsing helper anywhere in core. That is what fixes `CFG-7`'s return type (`P5-4`).

### From phase 2

- **`Dexpace::Cancellation`, `Cancellation::Source`, `Cancellation.any`, `Cancellation.over`.** `.over` is
  public *for this*: its in-code comment reads "public because phase 5's deadline source composes here".
  `CFG-17`'s re-assertion clause is met **structurally** by the token — the "interrupt/cancellation status" a
  downstream handler observes is the token's own `cancelled?`, which was set before the wait woke, and
  `Cancellation#check!` is what propagates it.
- **`Dexpace::Async::Future#value(cancellation: nil)` / `#wait(cancellation: nil)` and
  `Async::Completer#await(cancellation)`, with no `deadline:`** (P2-5, `DEF-28`). 5a adds the keyword, which
  widens; `NFR-4` fails only when a signature "disappears or narrows", and 4c confirms no pipeline signature
  changes.
- **`Dexpace::Async::Settlement`** and `Completer#fulfil`'s lost-race close through `Dexpace.close_quietly` —
  which is already `CFG-21`'s discard-path close, shipped, and which `SEAM-30` and design §10.4 argue.
- **`Dexpace.close_quietly(resource, onto: nil)`**, null-safe (`CFG-21`'s last clause) with phase 4b's `onto:`
  keyword and its suppressed-trail route. 5a adds no call site and no route; `5b` adds the diagnostic and
  closes `DEF-27`.
- **`Dexpace::Hooks.notify(hooks, argument)`**, `private_constant` (P2-15) — the one fan-out loop. 5a starts
  no new fan-out, and says so because a configuration-change listener would be the obvious place to invent
  one: **`CFG-13` is last-write-wins with safe publication and nothing else, and 5a ships no observer.**
- **`Dexpace::Registry` and three seam registries, with no auto-activation hook and a test asserting its
  absence** (`DEF-30`). **5a adds no fourth registry**; the clock is an injected object, not a discovered
  seam, because `SEAM-2` enumerates five seams and the clock is not one.
- **The error-class shape** — `class X < ::StandardError; include Dexpace::Error; end`. 5a defines **no new
  error class**; every failure it raises is `Dexpace::InvalidArgumentError`, `Dexpace::CancelledError` or
  `Dexpace::SeamError`, all of which exist.
- **`Dexpace/QualifiedCoreConstant`** (P2-8, extended by 3a as P3-7). 5a defines no constant that shadows a
  Ruby core constant — which is a decision and not luck, and the case where it nearly went wrong is named in
  `P5-3`.
- **P2-9's private-snapshot rule**: a `Data` that is public API follows phase 1's construction rule without
  exception; only a `private_constant` snapshot is exempt. `Configuration`, `Proxy`, `Proxy::Type` and
  `Proxy::HostPattern` are public and take the full treatment.

### From phase 3

- **`Dexpace::IO::MAX_MATERIALIZED_BYTES = 64 * 1024 * 1024`**, a frozen constant with no keyword anywhere
  (phase 3a; 3b deliberately declined a `ceiling:` keyword because it would give one stream two ceilings).
  §3.1 asks for it to become "configurable through the same layered chain as every other limit (§8.2)". 5a
  gives it that source and adds no keyword, which is why the phase-3 boundary survives.
- **`Dexpace::RequestLoggingBody.new(delegate, tap_limit: ::Float::INFINITY)`** and
  **`Dexpace::ResponseLoggingBody.new(delegate, preview_bytes:)`** — required, no default. Both are `DEF-34`'s
  other two wirings and both need the body-level-logging enablement predicate, which is `5b`'s. 5a does not
  touch them and does not edit `DEF-34`.
- **`Dexpace::StreamError < ::IOError`**, which is exactly why `is_a?(::IOError)` is the wrong spelling for
  `CFG-35`'s throwable half (`R1`).

### From phase 4

- **4a** — `ContextStore.new(cap:)` with `MAX_TRACKED_CONTEXTS = 1024` and `ContextStore.default`, the
  attachment point `DEF-36` names. Picking it up is one wiring and **no signature change**.
- **4a** — `Dexpace::Instrumentation::Bundle`, `TraceIdFlavour`, `NO_SPAN`, `NO_TRACER_FACTORY` and the empty
  RBS interfaces. **None of it is 5a's**; the five-clause handshake and `DEF-37` are `5c`'s, and 5a neither
  populates nor extends the bundle.
- **4a** — `Dexpace::BoundedMap`, `private_constant`, reachable by a bare name only from the full nesting
  form. **5a is not one of its named consumers and does not become one**: nothing in `CFG` is a keyed map with
  a cap.
- **4b** — `Dexpace.each_cause(error)`, cycle-safe by reference identity through `{}.compare_by_identity`,
  yielding the error first and stopping rather than propagating when `#cause` raises. It is the walk `CFG-19`
  and `CFG-35`'s throwable half would both use, **and 5a writes no second walk** — nor a first one, because
  `CFG-19` needs none and `CFG-35`'s throwable half defers.
- **4b** — `Dexpace::ProtocolError` **without** `#retryable?`, and `DEF-38` reserving the predicate for phase
  6. `R1` decides where its classifier comes from.
- **4c** — `Stages::LOGGING` with `PRE_LOGGING`/`POST_LOGGING` as its slots, and `Builder#install_preset`.
  Both are `5b`'s and `DEF-39`'s. 4c's own note on `DEF-28` is 5a's licence: "when `deadline:` lands on
  `Future#value`, `AsyncTransport.sync_over` gains it and **no pipeline signature changes**."

**Three open items land in 5a's window and none is 5a's to close.** `OI-15` is met by `CFG-16` and mitigated
by writing "elapsed-time counter" in full. `OI-21` is `R1`'s subject and is what `DEF-40` cross-references at
the phase-5 end. `OI-22` is `R7`'s subject and is what 5a's `CFG-20` checklist row cites.

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written.
`ruby scripts/knowledge.rb --origin note --brief` returns **36 entries across 18 note files**;
`--section conflicts --brief` returns **24 entries across 17 topic files, 18 of them notes and six
harvested**, and all six harvested conflicts print `[overridden by notes/…]` — `data-modeling/35fde90f`,
`module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and `/8c0687bf`,
`tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`. **None is open**, so 5a inherits no unresolved
conflict and owns no conflict decision of its own. The counts are unchanged from the charter's, because 5a
files no note (below).

`--prefix-info CFG` reports 38 IDs, 29 MUST / 8 SHOULD / 1 MAY, owning chapter
`docs/product-spec/16-configuration.md`, **38 of 38 substantive, 0 roll-up only, 0 uncited**, and names three
topics carrying `CFG` knowledge: `configuration`, `concurrency-and-async`, `retry-and-resilience`. `--gaps CFG`
returns nothing, so **5a budgets no specification reading beyond chapter 16** — which was read in full anyway,
because it is 62 lines and because its per-ID `*Conformance: …*` clauses are not in appendix C and three of
them are load-bearing: `CFG-26`'s "`a\|b|c` → `[a|b, c]`; `a\,b,c` → `[a,b, c]`" is the only statement
anywhere of what the escape rule produces; `CFG-27`'s "`NO_PROXY="*"` → null; `["*","x"]` → two globs" is the
only statement of the bypass-all/glob boundary; and `CFG-34`'s "a boxed-Integer array not equal to an int
array of the same values" is the clause `R4` has to read into a language with one `Array`.

**The appendix-B roll-up hazard fires on every `CFG` ID**, exactly as the charter said it would: all 38 return
at least one `[appendix-B roll-up]`-tagged hit on `--req`, 36 such entries under `configuration`. The skill's
three-step roll-up path was the normal reading mode for this document, not an exception, and the substantive
entry was located beside the roll-up in every case.

### The audit groups this phase ran

| Group | Query | Result |
|---|---|---|
| **Observability, configuration and redaction** (the tenth row, added by the charter for this material) | `--topic observability,configuration,redaction-and-security --section rules --brief` and `--prefix CFG,OBS --section rules --brief` | 92 + (37 `CFG` / 51 `OBS`) entries. The `CFG` half is a faithful restatement of chapter 16 and adds nothing chapter 16 does not say — which is itself the result: **no harvested rule contradicts a decision here, so no note is filed.** The half of the group that changed something is the discovery that `--section rules` omits two of the 38 IDs — `OI-24`, below |
| **Fiber scheduler, thread safety** | `--topic concurrency-and-async --section rules --brief` (75 entries), narrowed by grep on `mutex\|thread\|fiber\|monotonic\|sleep\|scheduler` | `concurrency-and-async/f414b864` (the note) governs `CFG-8`/`CFG-13`'s process-wide slot exactly as the charter said: one frozen snapshot swapped under a `Thread::Mutex`, read without a lock. `/241fb067`, `/fd3b2e2f`, `/05274309`, `/fcd96ee7`, `/b4489c39`, `/10579527`, `/ed7b9454` are `CFG-15`–`CFG-21` restated and are cited rather than repeated. `/08f1c7be` (`ASYNC-12`) is phase 8's and is what `R3`'s carrier choice must not be confused with |
| **Resource lifecycle and stream ownership** | `--topic resource-management --section rules --brief` | 27 entries. `resource-management/d1f16cad`'s note already records that the styleguide's per-call I/O timeout rules do not reach the streaming layer; they do not reach the clock either, for the second reason the charter gives — §8.3 forbids `Timeout.timeout` outright and `CFG-15`'s wait is a cancellable queue wait, not a timeout. `resource-management/bf5560dc`'s block-form rule reaches nothing 5a builds: the only resource 5a acquires is a per-call `Thread::Queue`, released in an `ensure` in the same method scope |
| **Public API surface** | `--topic api-design,http-domain-model,documentation,module-organization,error-handling --section rules --brief` | 150 entries. `api-design/1d9e6e0b` (keywords everywhere) shapes every accessor signature and takes no exception here; `api-design/6ea28c9c` (never `nil` for absent) is **overruled by requirement** for the lookup family, because `CFG-1` makes an absent value resolve to the caller's default and `CFG-37` documents that default as nullable — the case `6ea28c9c` itself reserves; `api-design/c15b29ce` (every returned collection frozen) is adopted through `Model.own`; `module-organization/64e84d64`'s full-nesting rule is what `R4`'s `private_constant` depends on; `api-design/1d9e6e0b`, `/a9943041` and `/634ccc4b` together make adding an optional keyword non-breaking and changing an existing default a MAJOR change, which is the rule `DEF-28`, `DEF-34` and `DEF-36` are all picked up under |
| **RBS / Steep typing** | `--topic type-system,data-modeling --section rules --brief` | 86 entries. `type-system/545949a5` fixes `Proxy::Type`'s three members as a frozen `Data` over a frozen table with an `.of` factory and never a `T::Enum`; `data-modeling/3e37c086` puts `Clock` in a class because it is an implementation of a duck type; `data-modeling/b74a2869` and `/ec0f41cb` put `Retryability`, `UUID`, `HTTPDate` and `BuildInfo` in modules because they own no state; `data-modeling/6accaff9` (a mutable constant must be frozen at assignment) is why `Configuration::EMPTY` is a frozen `Data` and `Dexpace.configuration` is **not** a constant; `data-modeling/5bc538ba` already narrows the Ractor claim and `P5-6` narrows it once more |
| **Minitest conventions** | `--topic testing,assertions --section rules --brief` | 29 entries. `testing/4ef070df` (every test runs alone, in any order, fresh fixtures) is what forbids a suite that mutates the process-wide slot without restoring it and what forces `Dexpace.reset_config!` to be public; `testing/7ecef8e8` and `/630ba094` name the three doubles 5a builds **fakes**; `testing/26b866e1` forbids `assert_nothing_raised`, which matters for `CFG-24`'s never-throw clause; `assertions/e8c05720` routes every `CFG-37` guard through `Model.required!` |
| **RuboCop and formatting** | `--topic tooling-and-quality-gates --section rules --brief` | Clean. 5a adds no cop: every rule it needs — `NoTimeParse`, `NoUriDefaultParser`, `NoLocaleCaseFold`, `NoThreadInterrupt`, `QualifiedCoreConstant` — already exists and already binds |
| **Styleguide-vs-design conflicts** | `--section conflicts --brief` | All six resolved; none open |

### The notes filed against the corpus by this phase

**None, and that is a decision rather than an omission.** Two candidates were considered and both fail the
test a note has to pass — that a harvested rule is *wrong* for this material.

- **`Fiber[]` versus `Thread.current[]` for a per-execution-context PRNG.** `R3` finds that fiber storage is
  the wrong carrier here and `Thread.current[]` is right, which reads like a contradiction of
  `docs/knowledge/notes/observability.md`. It is not: that note's subject is the **diagnostic context**, where
  inheritance across a child fiber, a new `Thread` and an `Enumerator`'s internal fiber is the property
  wanted. No harvested or note entry states a general rule about `Thread.current[]`; the corpus was queried
  for one (`--topic concurrency-and-async,observability --section rules,constraints`) and the only hits are
  `ASYNC-12`, `OBS-10`, `OBS-23` and `OBS-24`, all about the diagnostic context by name. A note would be
  correcting a rule nobody wrote. The asymmetry is stated in this document's `R3` and in `Dexpace::UUID`'s
  YARD block instead.
- **`Time.httpdate`'s RFC 850 and asctime laxity.** This corrects the **charter's** verified fact 2, not a
  harvested entry — `configuration/9f04d028` and `/7dbebc83` restate `CFG-30` and `CFG-31` faithfully and say
  nothing about Ruby. **The correction is one parenthetical, and naming it precisely matters because the
  charter is committed.** Every measurement the charter reports re-runs identically here; what is wrong is
  the inference from one of them. Its fact 2 says `Time.httpdate` "**rejects** a missing comma after the
  weekday (*satisfying both of `CFG-31`'s strictness clauses*)". The measurement holds —
  `"Mon 01 Jan 2024 00:00:00 GMT"` does raise — but the clause does not follow from it: asctime
  (`"Sun Nov  6 08:49:37 1994"`) has no comma after the weekday either and **parses**, so `CFG-31`'s "a
  malformed header missing the comma after the weekday MUST fail" is not satisfied by the method. Passing
  both of the chapter's conformance cases and failing the clause they are cases of is exactly the distance
  between a conformance case and a requirement. Recorded as verified fact 1 below and as a correction in the
  report, which is where a finding against a committed phase document goes.

## The verified Ruby facts this phase is built on

**Interpreter availability, stated before the facts because it limits every one of them.** Phases 3 and 4 ran
their facts on 3.2.11, 3.4.10 and 4.0.6 via `mise exec ruby@<v>`. **On this machine only 3.4.10 is
installed** — re-checked for this document: `ruby -v` is `ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM
[x86_64-linux]`, `mise ls` lists `bun`, `go`, `node` and `opencode` and no Ruby, `~/.local/share/mise/installs`
holds no ruby directory, and `~/.rbenv`, `~/.rvm` and `/opt/rubies` do not exist. Every fact below was run on
3.4.10 and on nothing else. Facts **1, 3, 5, 8, 9 and 14** are of the floor-straddling kind this repository
has been bitten by three times, and **5a's plan re-runs each on 3.2.11 and 4.0.6 before relying on it**; each
is flagged inline and the inline flags and this list are the same six. Fact **4** is deliberately not among
them: `Random::DEFAULT` was removed at 3.2 and is absent across the whole supported range, and the timings
vary by machine and run rather than by interpreter, which is a different kind of unreliability and is stated
in the fact itself. Nothing here is claimed across a range that was not run.

1. **`Time.httpdate` accepts RFC 850 and asctime, and `Date._httpdate` is stricter but not strict enough.**
   Formatting is exact: `Time.utc(1994,11,6,8,49,37).httpdate` is `"Sun, 06 Nov 1994 08:49:37 GMT"`, and
   `Time#httpdate`'s body in `/usr/lib/ruby/3.4.0/time.rb:695` is literally
   `getutc.strftime('%a, %d %b %Y %T GMT')`. Parsing: it **rejects** `UTC`, `+0000` and `+00:00`
   (`ArgumentError: not RFC 2616 compliant date`), rejects `""`, `"   "`, a single-digit day, a missing zone
   and a trailing junk token; it **accepts** a wrong weekday, a lower-case month, a lower-case weekday, **a
   leading space**, **`"Sunday, 06-Nov-94 08:49:37 GMT"` (RFC 850)** and **`"Sun Nov  6 08:49:37 1994"`
   (asctime)**. `Date._httpdate` rejects the three zone tokens, a single-digit day, a missing zone and a
   trailing junk token, but also accepts RFC 850 and asctime — for asctime returning a hash carrying **no
   `zone` and no `offset` key**. `Time.rfc2822` accepts `GMT`, `UTC` and `+0000` but not `+00:00`.
   *What it licenses:* `R2`'s rejection of both delegation routes. A normalise-then-delegate implementation
   passes `CFG-31`'s two conformance cases and still accepts two whole date formats with no `'Xxx, '` prefix,
   which is the clause `CFG-31` states. *What it does not license:* abandoning `Time#httpdate` for `CFG-29`,
   for which it is byte-exact against the specification's own example. **Floor-straddling** — `time.rb`'s
   parser has changed between releases before.
2. **`Time#httpdate` and the hand-written `strftime` are the same code, and locale independence was not
   verified.** Since `Time#httpdate` *is* `getutc.strftime('%a, %d %b %Y %T GMT')`, the choice between them is
   only whether 5a writes `require "time"`. `%a`/`%b` produced `Sun`/`Nov` under `LC_ALL` set to
   `de_DE.UTF-8`, `fr_FR.UTF-8`, `C.UTF-8` and `tr_TR.UTF-8` — **but `locale -a` on this machine lists only
   `C`, `C.utf8`, `en_US.utf8` and `POSIX`, so every one of those fell back to C and the test proves
   nothing.** *What it licenses:* using `Time#httpdate` and `require "time"`, on the strength of it being the
   stdlib's own canonical HTTP-date formatter. *What it does not license:* the claim that `strftime`'s `%a`
   and `%b` are locale-independent. Open question 2 below.
3. **`Fiber[]` hands the same object to a new thread; `Thread.current[]` is inherited by nothing.**
   `Fiber[:r] = o` then `Thread.new { Fiber[:r].equal?(o) }` is **`true`**, and a child fiber reads the same
   object; a write inside the child is invisible to the parent (copy-on-write of the *map*, not of the
   values). `Thread.current[:x] = 1` then a child `Fiber` reads **`nil`** and a new `Thread` reads **`nil`**.
   `Thread.current.thread_variable_get` is per-thread: visible to a fiber on the same thread, `nil` on a new
   thread. *What it licenses:* `R3` — `Fiber[]` cannot hold a PRNG, because "usable concurrently from multiple
   threads without shared mutable state" is exactly what it breaks; `Thread.current[]` gives every execution
   context its own. *What it does not license:* reading this as a general preference for `Thread.current[]`.
   For the diagnostic context the inheritance is the point and `Fiber[]` is the only correct carrier —
   `docs/knowledge/notes/observability.md` is unamended. **Floor-straddling** for the `Fiber[]` half.
4. **Per-execution-context memoisation is free; a fresh generator per call is 57× dearer.** 200 000 draws of
   `bytes(16)`: `Random.new` per call **2.4896 s**; one hoisted generator **0.0437 s**;
   `Thread.current[:prng] ||= Random.new` **0.0441 s**; `Thread.current.thread_variable_get`-based
   **0.0539 s**; the process-global `Random.bytes` **0.0309 s**; `SecureRandom.bytes` **0.0539 s**;
   `SecureRandom.uuid` **0.3790 s**. `defined?(Random::DEFAULT)` is `nil`. One `Random` shared by 8 threads
   drawing 2000 each produced 16 000 distinct values, as did per-thread generators. *What it licenses:* the
   `Thread.current[]` memoisation, which costs nothing measurable against a hoisted generator and is the only
   candidate with no cross-context sharing. *What it does not license:* concluding that the shared generator
   is unsafe from the 16 000/16 000 result — a distinctness count cannot show a lost update, exactly as
   phase 4a's drain-count measurement could not; the shared generator is excluded by the requirement's words,
   not by that number. The ratios are machine- and run-dependent and are quoted as directions.
5. **The UUID v4 layout is 16 bytes and two `setbyte`s, and `Random#bytes` returns an unfrozen BINARY
   string.** `b.setbyte(6, (b.getbyte(6) & 0x0f) | 0x40)`, `b.setbyte(8, (b.getbyte(8) & 0x3f) | 0x80)`,
   `unpack1("H*")`, hyphenated 8-4-4-4-12: version nibble `4`, variant nibble in `8`..`b`, matches
   `\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z`, 1000 generated with no collision. `Random.new.bytes(16)` is
   `frozen? == false` with encoding `ASCII-8BIT`. *What it licenses:* no `dup` before `setbyte`, and no
   `.b` retag. *What it does not license:* omitting the frozen check from the plan's first task — a future
   Ruby returning a frozen buffer would turn this into a `FrozenError` at the first UUID.
   **Floor-straddling.**
6. **`Date._iso8601` parses no ISO-8601 duration at all**, and `Integer()` has two tolerances worth naming.
   `Date._iso8601("PT5S")`, `("P1D")`, `("PT-5S")`, `("P1DT2H3M4S")`, `("PT0S")` and `("P0D")` all return
   `{}`. `Integer("010")` is **8** and `Integer("010", 10)` is **10**; `Integer("0x10", 10)`, `("1e3", 10)`,
   `("5x", 10)` and `("", 10)` all raise; `Integer("1_000", 10)` is **1000** and `Integer(" 5 ", 10)` is
   **5**; `Integer("5x", 10, exception: false)` is `nil`. *What it licenses:* `CFG-7`'s ISO-8601 branch is
   hand-written alongside its shorthand and bare-number branches, and every integer parse in the chain passes
   base 10 explicitly — a live defect, not a theoretical one, since `MAX_RETRY_ATTEMPTS=010` would otherwise
   resolve to 8. *What it does not license:* silence about `Integer()`'s two tolerances. `"1_000"` and
   `" 5 "` both resolve, which `CFG-5`'s "not a valid integer" neither requires nor forbids; the design
   states them rather than discovering them in a bug report.
7. **Ruby's float equality is wrong for `CFG-34` in both directions, `eql?` does not rescue it, and a naive
   deep comparison stack-overflows where `Array#==` does not.** Two distinct `NaN`s: `a == b` false,
   `[a] == [b]` false, `[a].eql?([b])` false. **The NaN hash depends on the payload, and that is the trap
   in this fact.** `Float#hash` digests the bit pattern, so two NaNs hash equal only when their payloads
   agree: two distinct objects built from the same bits (`[0x7FF8000000000000].pack("Q").unpack1("D")`,
   twice) give `[a].hash == [b].hash` **true**, while `0.0/0.0` and `-(0.0/0.0)` — both NaN, sign bits
   differing — give **false**, reproduced across three interpreter processes. **The witness has to be built
   by arithmetic:** `"nan".to_f` is `0.0` and `#nan?` on it is `false` (`String#to_f` never raises and
   returns `0.0` for an unparseable string), and `Float("nan")` raises `ArgumentError` — so a pair written
   with either one is not a NaN pair at all and asserts something else entirely. So Ruby's array hash agrees
   with `CFG-34` for one NaN and disagrees for another, which is worse than disagreeing consistently. And
   the values themselves are **not quotable**: `Float#hash` is seeded per process, so `(0.0/0.0).hash`
   differs on every run and only the equal/unequal relation within one process is stable — no test asserts a
   literal hash, here or anywhere. Signed zeros: `[0.0] == [-0.0]`, `[0.0].eql?([-0.0])` and
   `0.0.hash == (-0.0).hash` are all true; `1.0/0.0` and `1.0/-0.0` are `Infinity` and `-Infinity`.
   Element kinds: `[1] == [1.0]` is **true**,
   `[1].eql?([1.0])` is **false**, `1.hash == 1.0.hash` is **false**. Cycles: with `x = []; x << x` and
   `y = []; y << y`, `x == y` is `true` and `x.hash` returns an `Integer`, while a hand-written recursive
   comparison raises **`SystemStackError`**. *What it licenses:* `R4` — a hand-written recursive comparison
   with its own hash, delegating to neither `==` nor `eql?` **nor `#hash`** for floats, carrying an
   identity-keyed visited set, and using `eql?` semantics for numeric leaves so an `Integer` array is not
   equal to a `Float` array. *What it does not license:* reading the same-payload result as a general one.
   Every NaN must be folded to **one** hash seed by `DeepValue`, or two NaNs the helper calls equal hash
   differently — which breaks `CFG-33`'s "equals and hashCode MUST be mutually consistent" and `CFG-34`'s
   "hashing MUST match that equality" on an input a test written with a single NaN literal never produces.
   Nor does it license revisiting §11.15: the boxed-versus-primitive **container-kind** clause stays
   inapplicable; the element-kind reading is a different clause and is implemented.
8. **`Thread::Queue#pop(timeout:)` unmounts the fiber under a registered `Fiber.scheduler`, and returns `nil`
   for a negative timeout.** A minimal `Fiber::Scheduler` implementing `block`/`unblock`/`kernel_sleep`/
   `io_wait`/`fiber`/`close` was written for this document. Under it, `q.pop(timeout: 0.05)` inside
   `Fiber.schedule` calls **`#block` exactly once and `#kernel_sleep` zero times** and completes in 50.4 ms;
   a bare `sleep 0.01` in the same harness calls `#kernel_sleep` once, so the two are distinct hooks. With no
   scheduler: `Fiber.scheduler` is `nil`, `Fiber.schedule` raises `RuntimeError: No scheduler is available!`,
   `q.pop(timeout: 0.05)` returns `nil` after 50.4 ms, `q.pop(timeout: 0)` returns `nil` immediately,
   `q.pop(timeout: -1)` returns **`nil` immediately without raising**, a `q << :cancel` from another thread
   wakes a `pop(timeout: 5.0)` in 20.8 ms, and `q.close` also makes `pop` return `nil`.
   `Process.clock_getres(Process::CLOCK_MONOTONIC, :nanosecond)` is 1 and 100 000 successive readings are
   non-decreasing. *What it licenses:* §8.3's conditional claim, now measured rather than asserted — the
   queue wait genuinely pins no carrier under a scheduler; `CFG-17`'s sub-millisecond clause; `CFG-15`'s
   cancellable wait waking on a push; and `R6`'s conclusion that with no scheduler there is no non-blocking
   path at all. *What it does not license:* inheriting `CFG-17`'s negative-duration rejection from the queue —
   `pop(timeout: -1)` returns `nil` and raises nothing, so the guard is 5a's. Nor may the `nil`-versus-value
   discrimination be trusted in general: a closed queue also pops `nil`, and that is sound here **only
   because the queue is per-call, private, and never closed**. **Floor-straddling**; phase 4 verified
   `pop(timeout:)` on 3.2.11 for `RECOV-27`, which is the version half this run does not cover.
9. **`RbConfig` is undefined under `--disable-gems`; the four `RUBY_*` constants are not.** `defined?(RbConfig)`
   is `"constant"` normally and `nil` under `ruby --disable-gems`, where the bare reference raises
   `NameError: uninitialized constant RbConfig`; `require "rbconfig"` then works and yields
   `RbConfig::CONFIG["host_os"] == "linux"`. `rbconfig` is in no `Gem::BUNDLED_GEMS::SINCE` table (28 entries
   on 3.4.10; `logger` at `"4.0.0"`, `base64` at `"3.4.0"`, re-verified). `RUBY_ENGINE` (`"ruby"`),
   `RUBY_ENGINE_VERSION` (`"3.4.10"`), `RUBY_VERSION`, `RUBY_PLATFORM` (`"x86_64-linux"`) and
   `RUBY_DESCRIPTION` need no require and are defined under `--disable-gems`;
   `RUBY_PLATFORM.split("-", 2).last` is `"linux"`, the same token `host_os` gives here. *What it licenses:*
   `R5` — `CFG-36`'s three identity components with **no new allowlist entry**. *What it does not license:*
   the claim that `RbConfig` is unusable; it is requirable and legitimately allowlistable at the cost of a
   reviewed one-line diff, and this is phase 2's `Gem`-under-`--disable-gems` finding arriving at a second
   subsystem. **Floor-straddling** for the bundled-gems table.
10. **`URI::RFC3986_PARSER#port` defaults, `#split` does not, and `#unescape` is obsolete.**
    `P.parse("http://proxy.example")` returns a `URI::HTTP` whose `#port` is **80**, while
    `P.split("http://proxy.example")[3]` is **`nil`**; with an explicit port, `#split[3]` is the raw
    `"8080"`. `P.parse("http://h:70000").port` is **70000** — no range check. `P.parse("http://h:abc")`
    raises `URI::InvalidURIError`. `P.parse("socks5://h:1080")` is a `URI::Generic` with `#port` 1080.
    `P.parse("http://u%40x:p%3As@h:1")` gives `#user == "u%40x"` — userinfo is **not** decoded.
    `URI::RFC3986_PARSER.unescape("u%40x")` returns `"u@x"` and emits
    `warning: URI::RFC3986_PARSER.unescape is obsolete. Use URI::RFC2396_PARSER.unescape explicitly.`;
    `URI.decode_uri_component("u%40x")` is `"u@x"` with no warning and leaves `"a+b"` alone, where
    `URI.decode_www_form_component` turns it into `"a b"`. *What it licenses:* `CFG-25`'s absent-port rule is
    read off `#split[3]` and never off `#port`, and credential decoding is `URI.decode_uri_component`.
    *What it does not license:* using `#port` anywhere in the proxy resolver, including for the range check —
    the value has already been defaulted by the time it is read.
11. **A `\A…\z` glob with `IGNORECASE` satisfies `CFG-23` and misses an embedded newline; `\Z` would be
    wrong.** `*` → `.*`, `?` → `.`, everything else `Regexp.escape`d, anchored `\A…\z`, `IGNORECASE`:
    `*.example.com` matches `A.Example.COM` and not the apex `example.com`; `a?c` matches `abc` and not
    `abbc`; `a.b` does not match `axb`. `*` does **not** match `"a\nb"` without `/m`, and it does with.
    `\Aabc\z` does not match `"abc\n"` while `\Aabc\Z` does. `Regexp.new("x", Regexp::IGNORECASE,
    timeout: 0.05)` is accepted and reports `#timeout == 0.05`. *What it licenses:* `CFG-23`'s four rules with
    `\A`/`\z` and never `^`/`$`, and the per-pattern timeout. *What it does not license:* `\Z`, which would
    let `evil.com\n` match a pattern for `evil.com` — a full-string match that is not one.
12. **`CFG-26`'s escape rule is one negative-lookbehind split away.** With
    `s.split(/(?<!\\)#{sep}/, -1).reject(&:empty?).map { |t| t.gsub("\\#{sep}", sep) }.map(&:strip)`:
    `"a\\|b|c"` → `["a|b", "c"]` and `"a\\,b,c"` → `["a,b", "c"]`, both exactly the chapter's conformance
    outputs; `"a||c"` → `["a", "c"]` (empty dropped); `"a| |c"` → `["a", "", "c"]` — the whitespace-only
    fragment retained as an empty token, which is `CFG-26`'s stated observable order working; `"*"` → `["*"]`.
    *What it licenses:* the order split → drop-empty → unescape → trim, written in that order.
    *What it does not license:* calling the `-1` limit load-bearing. It is not, and that was checked rather
    than assumed: the default limit drops trailing empty fields, but the very next step drops empty fields
    anyway, so `"a|"`, `"a||"` and `"a"` all reach `["a"]` with the limit and without it. The `-1` stays
    because it makes the split's output the literal `split` half of `CFG-26`'s stated observable order
    rather than a pre-filtered one, and it is the form that survives if the drop-empty step ever moves —
    a documentation choice, not a correctness one, and it is written here as that.
13. **`::SocketError`, `::Timeout::Error`, `::OpenSSL` and `::Net` are undefined in a bare interpreter, and
    none of the reachable ones is an `IOError`.** `defined?(::IOError)`, `defined?(::EOFError)` and
    `defined?(::Errno::ETIMEDOUT)` are `"constant"` with and without `--disable-gems`;
    `defined?(::SocketError)`, `defined?(::Timeout)`, `defined?(::OpenSSL)` and `defined?(::Net)` are all
    `nil`. After the requires: `SocketError < StandardError`,
    `Errno::ETIMEDOUT < SystemCallError < StandardError`, `Timeout::Error < RuntimeError`,
    `OpenSSL::SSL::SSLError < OpenSSL::OpenSSLError < StandardError`. `EOFError < IOError`
    is the only one of the family that is. *What it licenses:* `R1`'s split. `CFG-35`'s throwable half has no
    spelling core can write: `is_a?(::IOError)` would classify phase 3a's `Dexpace::StreamError < ::IOError`
    retryable while classifying `Errno::ETIMEDOUT` and every `SocketError` **not** retryable, and `CFG-35`
    then makes that wrongness "a hard contract so exception construction and the retry policy agree".
    *What it does not license:* the reading that all four are forbidden to core. `socket`, `timeout` and
    `net/http` are on phase 0's denylist by name; **`openssl` is on the allowlist**, so `SSLError` is
    nameable at the price of a require, and `R1` rejects it on cost rather than on rule. Nor does it license
    deferring the **status** half with it: the status set is fully expressible in core and is the half
    `XCUT-5` calls SINGLE.
14. **A frozen `Data` holding a callable is not Ractor-shareable, and `Model.own`'s copy semantics hold.**
    `Ractor.make_shareable` on a frozen `Data` whose members include a lambda raises `Ractor::IsolationError`;
    the lambda itself is `frozen? == false`. `Ractor.make_shareable({"a" => ["b"]}, copy: true)` leaves the
    source unfrozen and returns a deep-frozen copy. `{a: 1}.freeze.dup.frozen?` is `false`. `ENV["X"]` returns
    a **frozen** `String`, a **new object each call**, encoded UTF-8; an empty-but-present variable reads back
    `""` with `ENV.key?` true. `Data#with` re-runs an `initialize` override on 3.4.10. *What it licenses:*
    `P5-6`'s narrowed Ractor claim, `CFG-2`'s discrimination between `""` and `nil` off `ENV` directly, and
    `Model.own` for `CFG-8`'s defensive copy. *What it does not license:* the `Data#with` result across the
    range — phase 1 recorded that 3.2.11 skips the override, which is exactly why `Model#with` exists and why
    5a uses it rather than `Data#with`. **Floor-straddling.**

## R1 — `CFG-35`'s classifier: the status half lands here, the throwable half is deferred

**The decision: alternative (c) — build `CFG-35`'s status classifier in 5a as `XCUT-5`'s single shared object,
and defer the throwable half to phase 6 as `DEF-40`.**

**Why the status half belongs here, against `DEF-38`'s argument.** `DEF-38` declined to build a classifier in
phase 4 because "building one in phase 4 would fix a phase-6 seam a phase early and give the SDK two places a
status classification could live, which is the drift the word SINGLE is in the requirement to prevent." That
argument had force against phase 4, **which owned no requirement defining a classifier**. It has none against
phase 5, which owns `CFG-35` — the only requirement in the corpus that states the built-in status set at
requirement level, in a chapter titled "Configuration and utilities" whose subsystem line names "a shared
retryability classifier" among its utilities. Building it here gives `XCUT-5`'s SINGLE exactly one home, and
turns `DEF-38`'s phase-6 work from "build a classifier" into "compute from the classifier phase 5 built",
which is one method rather than a second object. That is precisely the cross-reference `OI-21` records as
missing, supplied from the phase-5 end.

**Why the throwable half cannot be built here, and this is a fact rather than a preference.** `CFG-35`'s
second clause is "SHOULD treat a throwable as retryable iff it or any throwable in its cause chain is an
IO/timeout error". Verified fact 13: in a bare interpreter `::SocketError`, `::Timeout::Error`,
`::OpenSSL::SSL::SSLError` and `::Net::OpenTimeout` are **undefined**, and `socket`, `timeout` and `net/http`
are on phase 0's require **denylist by name**, so three of the four are unreachable by rule rather than by
choice. `openssl` is the exception and is stated rather than elided: it **is** on the allowlist, so core
could load it and name `OpenSSL::SSL::SSLError` — but that buys one class out of a set whose other three
members stay unreachable, at the cost of loading the largest extension in the stdlib at core's require time
for a classification that would still be wrong. What core *can* name is `::IOError`, `::EOFError` and
`::Errno::*`, and those do not
form the set: `SocketError < StandardError`, `Errno::ETIMEDOUT < SystemCallError`, `Timeout::Error <
RuntimeError`, and none of the three is an `IOError`, while phase 3a's `Dexpace::StreamError` **is** one. So
an `is_a?(::IOError)` classifier would mark a short-read stream error retryable and a connection timeout not
retryable — wrong in both directions — and `CFG-35`'s last sentence would then freeze that wrongness as "a
hard contract so exception construction and the retry policy agree". **Shipping a wrong shared object is
worse than shipping half of one**, and that is the inverse of the drift `SINGLE` normally warns about.

The right mechanism exists and is phase 6's: `XCUT-6` requires that "a transport-family or custom error type
that declares itself retryable via the retryability capability MUST be able to participate in retry decisions
without editing the retry classifier — for such errors the classifier queries the **capability**, not a
concrete-type match." A capability is exactly what lets `dexpace-transport-net_http` declare
`Errno::ETIMEDOUT` retryable without core naming it. Phase 8's `Dexpace::TransportError` is the other half.

**What 5a therefore ships:** `Dexpace::Retryability.retryable_status?(status)`, and **no** method for the
throwable half — not a stub, not a predicate returning `false`. A method that answers a question wrongly is
worse under an `NFR-4` lock than an absent one, because the absent one can be added by widening and the wrong
one can only be changed by breaking.

**What it costs.** `CFG-35` becomes a partially-satisfied SHOULD in 5a's checklist and phase 6 must close it,
so two register rows now point at one requirement: `DEF-38` for the baked flag and `DEF-40` for the throwable
half. That is the two-rows-one-feature shape §11.20 warns about, accepted deliberately and mitigated by
`DEF-40` citing `DEF-38` and `OI-21` in its own text — which is more cross-referencing than exists today, not
less. The alternative costs were worse: **(a)** building both halves here would put a knowingly wrong
IO-classification in core under a "hard contract"; **(b)** deferring both would leave `XCUT-5`'s SINGLE
homeless for another phase and leave `OI-21`'s hole exactly as it is.

## R2 — `CFG-30`'s four zone tokens, against a banned `Time.parse` and an over-tolerant `Time.httpdate`

**The decision: an owned, anchored grammar — one `Regexp.new(source, ::Regexp::IGNORECASE, timeout:)` and one
`Time.utc` — for parsing; `Time#httpdate` for formatting. The two directions do not share a mechanism, and
that asymmetry is the answer.**

Verified fact 1 rules out both delegation routes:

- **Normalise-then-delegate to `Time.httpdate`** would pass every conformance case in chapter 16 and still be
  wrong. It accepts `"Sunday, 06-Nov-94 08:49:37 GMT"` and `"Sun Nov  6 08:49:37 1994"` — two whole date
  formats with no `'Xxx, '` prefix and, in the asctime case, no comma anywhere — where `CFG-31` says "the
  weekday strip only applies to the well-formed 'Xxx, ' three-letter-plus-comma prefix". It also accepts a
  leading space. And the route's own structure is the second objection: `CFG-31`'s two failure guarantees
  would be inherited from a method the input no longer reaches unmodified, so the answer to "does blank input
  still fail?" would depend on what the normaliser did to it rather than on anything 5a asserts.
- **`Date._httpdate` components** is the better of the two rejected routes and is recorded as such: it rejects
  a single-digit day, a missing zone and a trailing junk token, and its asctime result is detectable because
  it carries no `offset` key. It still accepts RFC 850, still rejects three of `CFG-30`'s four zone tokens,
  and still hands back a component hash that must be assembled into a `Time`. It buys one rejection that would
  have to be re-checked and costs the same assembly.

**The grammar, stated so a plan implements it rather than re-deriving it.** One pattern, compiled once into a
frozen constant, `IGNORECASE`, anchored `\A…\z`:

- a **required** `'Xxx, '` prefix — exactly three letters, a comma and a space — matched and discarded, never
  compared against the computed weekday (`CFG-30`: "stripped, not parsed");
- a two-digit day, a three-letter month matched case-insensitively against a frozen table, a four-digit year;
- `HH:MM:SS`, two digits each;
- one of `GMT`, `UTC`, `+0000`, `+00:00`, all mapping to the zero offset.

`Time.utc(year, month_index, day, hour, min, sec)` builds the instant. A non-match raises
`Dexpace::InvalidArgumentError` carrying the offending input, which is `CFG-31`'s "MUST fail with a parse
error".

**How `CFG-31`'s blank-input failure survives, which is the half `R2` explicitly asks about.** It survives
because **no normalisation runs before the match**. The pattern is applied to the caller's string exactly as
given: `""` and `"   "` fail the `\A…\z` anchors, and `"Mon 01 Jan 2024 00:00:00 GMT"` fails because
`\A\p{L}{3}, ` does not match `"Mon "`. There is nothing between the input and the assertion, which is the
property a normalise-first design cannot state.

**What it costs.** Three things, each accepted with its reason.

1. **The `'Xxx, '` prefix is required, so a bare `"06 Nov 1994 08:49:37 GMT"` is rejected.** `CFG-31` does not
   say what to do when there is no weekday at all; making the prefix optional would also satisfy its two
   conformance cases. Required is chosen because `CFG-30` and `CFG-31` both describe a strip of a prefix that
   is *there*, and because `Time.httpdate` — the behaviour a Ruby reader will compare against — rejects it
   too, so the port and the stdlib agree.
2. **The whole pattern is case-folded, so `"gmt"` parses.** `CFG-30` makes month names case-insensitive and is
   silent about the zone. Folding everything is a strict superset of what the requirement demands accepted and
   therefore cannot reject a conforming input; the direction `CFG-30` sets is tolerance.
3. **RFC 850 and asctime are rejected**, where `Time.httpdate` accepts them. Chapter 16 is titled "RFC 1123
   date PARSING" throughout and names no other format. A caller who has an asctime date has an obsolete
   HTTP-date and a different problem.

`Dexpace/NoTimeParse` is satisfied without effort: no `Time.parse`, `Date.parse` or `DateTime.parse` appears,
and the cop's suggested alternative is used for the direction it is right for.

## R3 — `CFG-32`'s per-thread PRNG on a Ruby with no `Random::DEFAULT`

**The decision: one `Random` instance per execution context, memoised lazily in `Thread.current[:…]` —
Ruby's fiber-local slot — and never in `Fiber[]`, never a process-global generator, never `SecureRandom`.**

**Why not `Fiber[]`.** Verified fact 3: `Fiber[:k] = o` and then `Thread.new { Fiber[:k].equal?(o) }` returns
**`true`**. Fiber storage is inherited by a new `Thread`, and the inheritance copies the *map*, not the
values — so a generator placed there is handed, by identity, to every thread the process later spawns.
`CFG-32` says "usable concurrently from multiple threads **without shared mutable state**", and a `Random`
reachable from many threads is precisely shared mutable state. This is the one place in phase 5 where the
carrier that is right for the diagnostic context is wrong, and it is wrong for the same property that makes it
right there.

**Why `Thread.current[]`, despite `CLAUDE.md`'s constraint line.** That line — "`Fiber[:key]` is the
diagnostic-context carrier, not `Thread.current[:key]`" — is about the diagnostic context, and its reason is
that `Thread.current[]` is fiber-local and therefore invisible to a child fiber, a new `Thread` and an
`Enumerator`'s internal fiber. For a PRNG that invisibility is the requirement: verified fact 3 shows a child
fiber and a new thread both read `nil`, so **no two execution contexts ever share a generator, under any
composition**. No corpus rule was overruled to get here; the corpus was queried and holds no general rule
about `Thread.current[]` at all (see *The notes filed against the corpus by this phase*).

**Why not the alternatives.** `Random.new` per call is 57× dearer than a reused generator (verified fact 4:
2.4896 s against 0.0437 s over 200 000 draws) and would put ~12 µs on every UUID. The process-global
`Random.bytes` is the fastest at 0.0309 s and is exactly the shared state the requirement excludes.
`Thread#thread_variable_get` gives one generator per *thread*, amortising the seeding better under a
fiber-heavy scheduler — but it is visible to every fiber on that thread, which is sharing even where it cannot
race, and it measured *slower* per draw (0.0539 s) than the fiber-local slot. `SecureRandom.uuid` is excluded
by boundary 8 and by `CFG-32`'s own words, and is 8.6× dearer besides.

**The layout is `CFG-32`'s and is verified** (fact 5): 16 bytes from the memoised generator, byte 6 masked to
version 4, byte 8 masked to the IETF variant, `unpack1("H*")`, hyphenated. `Random#bytes` returns an unfrozen
BINARY string, so no `dup` and no retag.

**What it costs, stated rather than elided.** One `Random` object and one ~12 µs seeding per *fiber* that
generates a UUID. In a fiber-per-request server that is 12 µs on the first UUID of each request and a small
retained object for the fiber's lifetime — cheap, but not free, and it is the number to re-measure if a
fiber-scheduler adapter ever reports UUID generation as hot. The alternative that would fix it,
`thread_variable`, is recorded above with the reason it was not taken.

## R4 — where `CFG-33`/`CFG-34`'s deep equality lives, and what "distinct array kinds" means

**The decision: a `private_constant` module, `Dexpace::DeepValue`, with two module functions —
`DeepValue.equal?(a, b)` and `DeepValue.hash(value)` — and no `sig/` mirror, no YARD gate entry and no
surface-manifest row.**

**Why private.** It has **no caller anywhere in phase 5** — nothing in `CFG`, `OBS` or the chain consumes deep
equality — and `OI-8` names the exact failure a public one would be: `TeeSink#clear_tap`, `NFR-4`-locked
public API with no core caller. Phase 2 set the precedent with `Dexpace::Hooks` (P2-15) and phase 4a repeated
it with `BoundedMap` and `CallKey` (P4-3). The reachability condition is already recorded and already met:
phase 4a verified that a `private_constant` on `Dexpace` is bare-name reachable from **every** file that
reopens `module Dexpace; module …` in the full nesting form — including a separately-required file in another
gem, so `dexpace-conformance` can drive `CFG-33`'s conformance clause — and unreachable through a qualified
reference or the compact `module Dexpace::X` form. The asymmetry that settles it: promoting a private constant
to public later is a widening `NFR-4` permits; the reverse is a break.

**What "distinct array kinds" means.** Two clauses, and only one of them is inapplicable.

- **Container kind is the inapplicable clause, and 5a does not extend the inapplicability.** §11.15 records
  `CFG-34`'s boxed-versus-primitive array inequality as having no Ruby manifestation, and it is right: Java
  has `Integer[]` and `int[]`; Ruby has one `Array`. There is no second container to be unequal to.
- **Element kind is live, and Ruby's `==` gets it wrong for this purpose.** Verified fact 7: `[1] == [1.0]` is
  **true**, `[1].eql?([1.0])` is **false**, `1.hash != 1.0.hash`. `CFG-34`'s sentence is "An object array and
  a primitive array with the same numeric values MUST NOT be considered equal", and the nearest true reading
  in a language with one array type is that an array of `Integer` is not equal to an array of `Float` with the
  same numeric values. `DeepValue` therefore compares numeric leaves with `eql?` semantics — type and value —
  rather than `==`. That is also what keeps `DeepValue.hash` consistent with `DeepValue.equal?`, which
  `CFG-33` makes a MUST, since `1.hash` and `1.0.hash` already differ.

**The float branch, which is the work verified fact 7 shows is real.** `Float` leaves delegate to none of
`==`, `eql?` or `#hash`:

- two NaNs are **equal** (`CFG-34`), which neither `==` nor `eql?` gives — **and the hash side does not come
  free**. `Float#hash` digests the bit pattern, so `(0.0/0.0).hash` and `-(0.0/0.0).hash` differ (verified
  fact 7), and only a NaN built from the same payload as its counterpart hashes equal to it. `DeepValue.hash`
  therefore folds **every** NaN to one fixed seed, tested against two NaNs with different payloads rather
  than against one literal reused;
- `+0.0` and `-0.0` are **unequal**, discriminated by `1.0 / x` (`Infinity` versus `-Infinity`), and hashed
  from distinct seeds so hashing matches equality — Ruby's own `0.0.hash == (-0.0).hash` does not.

Both branches are one rule stated twice: `CFG-33`'s "equals and hashCode MUST be mutually consistent" and
`CFG-34`'s "hashing MUST match that equality" are about `DeepValue`'s own pair, so `DeepValue.hash` computes
a float's contribution from a normalised classification — NaN, negative zero, everything else — and never
from `Float#hash` directly.

**Cycle safety, which no `CFG` ID requires and which is nonetheless implemented.** Verified fact 7: a naive
recursive comparison of two self-referential arrays raises `SystemStackError`, while `Array#==` and
`Array#hash` survive it through Ruby's own recursion guard. A hand-written helper that stack-overflows on the
one input the language handles is a regression against the language, so `DeepValue` carries an
identity-keyed visited set — `{}.compare_by_identity`, the same mechanism `Dexpace.each_cause` uses for
`XCUT-9`. This is stated as the reason rather than as a requirement, because `CFG-33` does not ask for it.

**Null-safety is explicit** (`CFG-33`: "two nulls are equal; null hashes to zero"). `nil.hash` in Ruby is a
large negative integer, verified, so `DeepValue.hash(nil)` returns `0` by an explicit branch and not by
delegation.

**What it costs.** `dexpace-conformance` must use the full nesting form to reach the helper, which is a
condition `docs/knowledge/notes/execution-context.md` already records for `BoundedMap` and which will now bind
a second constant. And `CFG-33`'s "byte arrays" conformance case is satisfied by `String#==` on a BINARY
string rather than by the helper's array path — Ruby's primitive byte array is a `String`, verified unequal to
an `Array` of the same integers — which is `CFG-33`'s own "non-arrays fall back to ordinary equality" and is
stated so a reader does not go looking for a byte-array branch that is not there.

## R5 — `CFG-36`'s host-runtime identity, and the allowlist that does not grow

**The decision: derive all three identity components from constants that need no `require`, and grow the
require allowlist by nothing.**

| `CFG-36` component | Source | Verified value here |
|---|---|---|
| runtime version | `RUBY_ENGINE_VERSION` | `"3.4.10"` |
| vendor | `RUBY_ENGINE` | `"ruby"` |
| OS name | `RUBY_PLATFORM.split("-", 2).last` | `"linux"` |
| SDK version | `Dexpace::VERSION` (phase 0, from the repo-root `VERSIONS`) | `"0.0.0"` |

Each passes through one blank guard substituting the frozen `"unknown"`, so `CFG-36`'s "Every token MUST be
non-blank so joined identity strings are never malformed" is a property of the constant rather than of its
callers. All four are resolved once at load into frozen constants, which is `CFG-36`'s "resolved once at load
time" read literally.

**Why `RbConfig` is rejected, given it would work.** Verified fact 9: `defined?(RbConfig)` is `nil` under
`ruby --disable-gems`, where the bare reference raises `NameError`; `require "rbconfig"` then works, and
`rbconfig` appears in no `Gem::BUNDLED_GEMS::SINCE` table, so it is legitimately allowlistable. The cost is a
reviewed one-line diff to a list that has not changed since phase 0 — **and this would be the first growth of
that list, which is exactly the kind of change that should not happen by accident.** What it buys is
`RbConfig::CONFIG["host_os"]`, which on this machine returns `"linux"`: the same token `RUBY_PLATFORM` already
yields, for a new dependency and a new failure mode under `--disable-gems`. The trade is not close.

**What it costs.** `RUBY_PLATFORM`'s OS half is not always what an operator would call the operating system —
`"java"` on JRuby, `"x86_64-linux-musl"` on Alpine, `"darwin24"` rather than `"macOS"` — and
`RbConfig::CONFIG["host_os"]` is marginally better on some of those. Accepted, because `CFG-36`'s clause is
"OS name … falling back to a non-blank 'unknown'" and the token's destination is a User-Agent, where
`RUBY_PLATFORM` is the string the Ruby ecosystem already publishes. The composition of the User-Agent itself
is not 5a's: `CFG-36` asks only for "a default ordered identity-token list (SDK token then runtime token)",
which is what `BuildInfo::IDENTITY_TOKENS` is.

## R6 — `CFG-18`'s "WITHOUT blocking a thread", and what happens with no scheduler

**The decision: `CFG-18` ships as a scheduler-conditional implementation that raises `Dexpace::SeamError` when
no `Fiber.scheduler` is registered. It is not deferred, and it carries a deviation row (`P5-9`) rather than a
register row.**

**The fact the decision rests on is now measured, not argued.** Verified fact 8: under a registered
`Fiber::Scheduler`, `Thread::Queue#pop(timeout:)` calls the scheduler's `#block` hook exactly once and
`#kernel_sleep` zero times — the fiber is unmounted and the carrier thread is free. With no scheduler,
`Fiber.scheduler` is `nil` and `Fiber.schedule` raises `RuntimeError: No scheduler is available!`. So the
non-blocking property `CFG-18` names is genuinely available on one side of a condition the host controls, and
genuinely unavailable on the other.

**Why not a deferral.** Three of `CFG-18`'s four clauses are MUSTs the port can implement, and §11.11's rule
is that where the port ships the feature it implements every embedded MUST. Two of them hold with no
scheduler at all — "A zero delay MUST complete the future immediately" and "a negative delay MUST be
rejected", both decided before anything is scheduled. The third, "cancelling the returned future MUST cancel
the underlying scheduled task so the scheduler thread is not held", holds in the scheduler branch and is
vacuous in the other, because with no scheduler there is no returned future to cancel; that is stated rather
than counted as a third no-scheduler win. Deferring would defer three implementable MUSTs to carry one
conditional SHOULD clause.

**Why not a silent degradation to a thread.** A `::Thread` doing the wait and completing the completer would
work and would block a thread, which is the one thing the requirement forbids and the one thing the charter
forbids this document from claiming otherwise about. Raising is the only behaviour that neither lies nor
degrades silently. And raising is not the port refusing a requirement it could meet: `CFG-18`'s own words are
"after a given non-negative duration elapses **on a provided scheduler**", so the requirement's antecedent is
a scheduler the caller provides, and with none provided there is nothing for the SHOULD to be measured
against. `P5-9` records the decision anyway, because the *behaviour* a reader meets — an exception where a
degraded delay was plausible — is the part they will question.

**Why the error is `Dexpace::SeamError`, which needs stating because 5a elsewhere insists the clock is not a
seam.** Phase 2 defined it for "a seam in a state the caller must fix but did not pass in", with the
registry's zero-provider and ambiguous-provider cases as its examples, and its own comment draws the line
that decides this: "Nothing was wrong with the argument here; the process is missing a provider." A missing
`Fiber.scheduler` is that shape exactly — a process-level facility the caller installs and did not, with a
correct argument — and `Dexpace::InvalidArgumentError`, the only other existing candidate, would say the
opposite about the caller's duration. It is **not** a claim that `CFG-18`'s scheduler is one of `SEAM-2`'s
five: 5a registers nothing and adds no fourth registry, and the class's name is broader than its
enumeration. The alternative was a new error class, which 5a declines for one call site (`NFR-4` locks it at
the first release tag and a `rescue Dexpace::Error` already catches this one).

**The shape.** `Dexpace::Async.delay(duration) -> Dexpace::Async::Future`:

- negative duration → `Dexpace::InvalidArgumentError`, raised **before** anything is scheduled;
- zero duration → a `Future` already settled with a `nil` value; no fiber, no queue, no scheduler consulted;
- positive duration with `Fiber.scheduler` **nil** → `Dexpace::SeamError` naming `CFG-18`, naming
  `Fiber.set_scheduler`, and naming `Dexpace::Clock#sleep` as the blocking operation to use instead;
- positive duration with a scheduler → `Fiber.schedule` around a bounded pop on a per-call `Thread::Queue`,
  completing the completer with `nil`. `Completer#on_cancel` pushes to that same queue, so cancelling the
  future wakes the parked fiber immediately — which is `CFG-18`'s fourth clause, met by the mechanism
  `CFG-15` already uses rather than by a second one.

The `Fiber.scheduler.nil?` guard is 5a's and not inherited: `Fiber.schedule`'s own failure is a bare
`RuntimeError`, and letting an untyped `RuntimeError` escape a `Dexpace::` method is the shape phase 1's
`URL.parse!` exists to prevent.

**And there is no `clock:` keyword on it**, which is worth one sentence because every other timing-shaped
signature in 5a has one. Nothing in the four branches reads a clock: the wait is `Thread::Queue#pop`'s own
`timeout:`, which takes a duration and not an instant, and no fake clock can make a real queue wake early —
the same limit the `CFG-15` test note records. A `clock:` here would be an `NFR-4`-locked keyword with no
consumer and no test that could drive it, which is `OI-8`'s shape and the thing `P5-2` exists to keep
deliberate.

**Why it lives on `Dexpace::Async` and not on `Clock`.** `CFG-15` says the time seam exposes **three**
operations. A fake clock has to implement the seam, and a fourth method on it would widen what every fake owes
for a requirement that names "the async layer" as its subject. So `Clock` is exactly `#now`, `#monotonic` and
`#sleep`, and `CFG-18` is a module function on the async layer.

**What it costs.** An application with no scheduler cannot call `Async.delay` at all — it gets a `SeamError`
rather than a degraded delay. Nothing in the MVP is blocked by that: `RETRY-26`'s inter-attempt wait is
`CFG-15`'s `Clock#sleep`, not `CFG-18`'s delay, and `Clock#sleep` blocks the *calling* thread by design and
never a shared pool thread. The two operations are different requirements with different contracts and the
`SeamError` message says which is which.

## R7 — the citation `CFG-20`'s checklist row carries

**The decision: ⏳, citing `DEF-18` **and** `OI-22`, with the unmet clause named in the row's own words.**

The row 5a's checklist will carry:

> `| CFG-20 | SHOULD | ⏳ | DEF-18, OI-22 | Three of four clauses met: the non-interrupting cancel is
> Future#cancel (phase 2); the queued-or-finished clause holds because no interrupt is ever delivered; the
> rejected-submission clause is Completer#fail's routing. The fourth — cancel-with-interrupt — is ASYNC-3's
> mechanism under a second ID and is forbidden by §8.3; DEF-18 carries the mechanism and does not cite
> CFG-20, which is what OI-22 records. |`

**Why not ✅-with-clauses.** A ✅ with an unstated missing clause is the failure the roadmap's one-row-per-ID
convention exists to prevent. Phase 2's `SEAM-25` row is ✅-with-a-named-gap only because that gap had a
register row of its own (`DEF-31`). `CFG-20`'s does not — `DEF-18` cites `ASYNC-3` and `PIPE-33` and stops —
which is exactly `OI-22`'s content.

**Why not a marker of 5a's own.** The legend is fixed by the roadmap and used verbatim by every phase; a fifth
symbol invented for one row costs more than a ⏳ whose reason column carries the clause.

**Why 5a files no deferral for it.** `DEF-18` already carries the mechanism and its pick-up condition — "if an
interruptible transport path is ever adopted" — covers `CFG-20` exactly. A second row for the same mechanism
under a second ID is the `RECOV-31`/`RETRY-38` duplication §11.20 warns about, and filing one would make the
port's unsatisfied-clause arithmetic look larger than it is. `CFG-20` is a **SHOULD**, so its unmet clause is
an unmet SHOULD clause and **phase 5 adds no fourth unsatisfied MUST** — the charter's arithmetic, unchanged.

**5a does not edit `DEF-18` and does not close `OI-22`.** `DEF-18`'s `Cites:` line is a committed,
adversarially reviewed row and the register's rules permit only a `Status` edit. `OI-22`'s own stated
resolution is "a citation that names the unmet clause"; the row above **is** that citation, so 5a landing is
what would let a human close it — a judgement about the register, made by whoever owns it.

## Module layout

Every file 5a creates, under `gems/dexpace-core/`. `sig/` mirrors `lib/` one file per file and ships inside
the gem; `test/` mirrors `lib/` one file per file and does not ship.

```
lib/dexpace.rb                                   MODIFIED: explicit requires for the tree below
lib/dexpace/configuration.rb                     Dexpace::Configuration, ::Configuration::Builder
lib/dexpace/configuration/keys.rb                Dexpace::Configuration::Keys
lib/dexpace/configuration/sources.rb             Dexpace::Configuration::Sources
lib/dexpace/configuration/parsers.rb             Dexpace::ConfigParsers                 (private_constant)
lib/dexpace/config.rb                            Dexpace.configure, .configuration, .reset_config!
lib/dexpace/clock.rb                             Dexpace::Clock, Clock::SYSTEM
lib/dexpace/async/delay.rb                       Dexpace::Async.delay
lib/dexpace/proxy.rb                             Dexpace::Proxy
lib/dexpace/proxy/type.rb                        Dexpace::Proxy::Type
lib/dexpace/proxy/host_pattern.rb                Dexpace::Proxy::HostPattern
lib/dexpace/proxy/resolution.rb                  Dexpace::ProxyResolution               (private_constant)
lib/dexpace/http_date.rb                         Dexpace::HTTPDate
lib/dexpace/uuid.rb                              Dexpace::UUID
lib/dexpace/deep_value.rb                        Dexpace::DeepValue                     (private_constant)
lib/dexpace/retryability.rb                      Dexpace::Retryability
lib/dexpace/build_info.rb                        Dexpace::BuildInfo

lib/dexpace/async/future.rb                      MODIFIED: deadline: and clock: on #value and #wait
lib/dexpace/async/completer.rb                   MODIFIED: #await gains deadline: and clock:
lib/dexpace/context_store.rb                     MODIFIED: .default reads its cap from the chain (DEF-36)
lib/dexpace/io.rb                                MODIFIED: a configured source for the ceiling (DEF-34, part)

test/support/fake_clock.rb                       the deterministic clock
test/support/fake_source.rb                      the hermetic env / property source
test/support/probe_scheduler.rb                  the minimal Fiber::Scheduler, for CFG-18 alone
```

Sixteen new `lib/` files, **thirteen** `sig/` mirrors and thirteen `test/` mirrors — `configuration/parsers.rb`,
`proxy/resolution.rb` and `deep_value.rb` are `private_constant`s and get neither, per P2-15 and P4-3, and
their behaviour is asserted at their call sites — **five** already-existing `lib/` files that gain content
(`dexpace.rb`, `async/future.rb`, `async/completer.rb`, `context_store.rb`, `io.rb`), with `sig/` mirrors
updated for the four of those that are public surface — three test-support files, and the repository-root
`test/fixtures/surface/dexpace-core.txt`.

**The placement rule is phase 1's and is applied, not re-decided** (P1-1, `module-organization/6e69ad04`): a
public constant the design names without a namespace is flat, and its file sits under a directory that
organises rather than namespaces. Design §8.2 names exactly two Ruby identifiers — `Dexpace.configure` and
`Dexpace.reset_config!` — so every constant below is 5a's own name and every one carries a ledger row.

`lib/dexpace/configuration/keys.rb` and `sources.rb` define constants **nested inside** `Dexpace::Configuration`
rather than flat, because they are not independent concepts: `Keys` is the set of names the chain understands
and `Sources` is the set of seams it reads through, and both read wrongly as top-level `Dexpace::` constants.
That is the same reading phase 1 gave `Headers::Builder` and `Status::OK`.

## The object model 5a ships

Every public constant, its surface, and the IDs forcing that shape.

### `Dexpace::Configuration` — `CFG-1`–`CFG-13`, `CFG-37`, `CFG-38`

A `Data` including `Dexpace::Model`, `private_class_method :new`, three members.

```
Data.define(:overrides, :env_source, :property_source)
```

| Member | Requirement |
|---|---|
| `overrides` | `CFG-1` tier 1, keyed by the **exact** name. `Model.own`'d at construction, so `CFG-8`'s defensive copy and its deep freeze are one call and later builder mutation cannot reach it |
| `env_source` | `CFG-1` tier 2 and `CFG-11`'s first seam: a callable from exact key name to `String?` |
| `property_source` | `CFG-1` tier 3 and `CFG-11`'s second seam: a callable from **normalised** key name to `String?`. This is §10.16's substituted source — the process-wide defaults `Dexpace.configure` installs, not a second `ENV` read under another name (P11) |

| Method | Requirement |
|---|---|
| `.build(overrides: {}, env_source: Sources::ENVIRONMENT, property_source: Sources::NONE)` | the validating factory; every argument is `Model.required!`'d, so `CFG-37`'s null rejection is the same message form `SEAM-29` fixes |
| `.builder` / `#new_builder` | `HTTP-3`'s builder split. `#new_builder` `dup`s the override map, never aliases it |
| `Configuration::EMPTY` | `CFG-13`'s "MUST default to an empty configuration (no overrides, platform-backed seams)" |
| `#string(name, default: nil) -> String?` | `CFG-1`, `CFG-2`, `CFG-3` |
| `#raw_property(name, default: nil) -> String?` | `CFG-4`: the exact-name property read, **without** normalisation |
| `#integer(name, default: nil) -> Integer?` | `CFG-5`, `CFG-38` |
| `#boolean(name, default: nil) -> bool?` | `CFG-6`, `CFG-38` |
| `#duration(name, default: nil) -> Float?` | `CFG-7`, `CFG-38`. **Seconds**, `P5-4` |
| `#derive { \|builder\| … } -> Configuration` | `CFG-9`, `CFG-10` |

**The string accessor is `#string` and not `#[]`, deliberately.** `#[]` would read as `Hash`-like access over
the override map, which is exactly the assumption `CFG-38` forbids ("they MUST NOT read only the override map
or skip the env/property layers"). Five accessors with five names read as one family and none of them implies
a backing hash.

**`CFG-2`'s emptiness rule applies to the environment layer only**, because that is the only layer `CFG-2`
names. An override of `""` resolves to `""`; a property of `""` resolves to `""`; an environment variable of
`""` falls through. The asymmetry is a requirement, not an oversight, and it is one of the tests a reader
would otherwise write wrong.

**`CFG-3`'s normalisation is `name.downcase.tr("_", ".")`**, with `downcase` taking no argument — the rule
`Dexpace/NoLocaleCaseFold` mechanises, and one whose absence would make `MAX_RETRY_ATTEMPTS` normalise
differently under a Turkish locale symbol.

**`CFG-37`'s guards, exhaustively:** `Builder#override(key, value)` on both arguments, `Builder#property(key,
value)` on both, `Builder#env_source=` and `#property_source=`, `#derive`'s block, and `Dexpace.configure`'s
block. A key must additionally be a non-empty `String`; an empty key raises `Dexpace::InvalidArgumentError`,
which no `CFG` ID requires and which the alternative — a key that can never be matched, silently accepted —
does not justify. `#string(name, default: nil)` accepts a `nil` default, which is `CFG-37`'s
documented-nullable "lookup default".

### `Dexpace::Configuration::Builder` — `CFG-8`, `CFG-9`, `CFG-10`, `CFG-12`

`#override(key, value)`, `#remove(key)`, `#property(key, value)`, `#env_source=`, `#property_source=`,
`#build`.

- `#remove(key)` drops **only** the override entry, is a no-op for a key with no override, and never installs
  a `nil` — `CFG-10`'s three clauses, and the reason `overrides` is a plain map rather than a map with a
  tombstone value.
- **`#property` after an explicit `#property_source=` raises `Dexpace::InvalidArgumentError`.** The two are
  different ways to populate the same tier, and silently discarding an operator's `#property` call because a
  seam was installed later is the failure mode. Last-write-wins is right for `CFG-13`'s process-wide slot and
  wrong inside one builder.
- **No mutex, by requirement.** `CFG-12`: "Configuration builders SHOULD be usable single-threaded only; the
  immutability guarantee applies to the built configuration, not to an in-progress builder." Documented in
  the YARD block, asserted by nothing, and stated here so nobody adds one for symmetry with
  `Dexpace.configure`'s.

### `Dexpace::Configuration::Keys` — `CFG-14`

Frozen `String` constants. Five are `CFG-14`'s own; two are the names 5a's own wirings read.

| Constant | Value | Owner |
|---|---|---|
| `MAX_RETRY_ATTEMPTS` | `"MAX_RETRY_ATTEMPTS"` | `CFG-14`; `RETRY-12`'s **values** are phase 6's |
| `LOG_LEVEL` | `"LOG_LEVEL"` | `CFG-14`. **A published name a caller may pass, never a default any resolver falls back to** — `OBS-35`'s embedded MUST |
| `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` | the three environment names | `CFG-14`, `CFG-24`, `CFG-26` |
| `MAX_MATERIALIZED_BYTES` | `"MAX_MATERIALIZED_BYTES"` | `DEF-34`'s ceiling half |
| `MAX_TRACKED_CONTEXTS` | `"MAX_TRACKED_CONTEXTS"` | `DEF-36` |

`5b` adds the body-preview and body-logging-enablement key names **in the change that reads them**, and 5a
does not pre-declare them: a key constant with no reader is `NFR-4`-locked surface nothing exercises, which is
`OI-8`'s shape.

The seven system-property names `CFG-24` and `CFG-26` read — `https.proxyHost`, `http.proxyHost`,
`https.proxyPort`, `http.proxyPort`, `https.proxyUser`, `https.proxyPassword`, `http.nonProxyHosts` — are
**not** in `Keys`. `CFG-14` does not name them, only the resolver reads them, and putting seven strings under
an API lock for one caller is surface with no reason. They live as `private_constant`s in
`Dexpace::ProxyResolution`.

### `Dexpace::Configuration::Sources` — `CFG-11`

`Sources::ENVIRONMENT = ->(key) { ::ENV[key] }.freeze`, `Sources::NONE = ->(_key) { nil }.freeze`, and
`Sources.from_hash(map) -> Proc` for the seam `Dexpace.configure` installs.

**It is `ENVIRONMENT` and not `ENV`**, and the reason is `Dexpace/QualifiedCoreConstant`'s hazard from the
other side: `Dexpace::Configuration::Sources::ENV` would shadow Ruby's `::ENV` for every bare reference inside
`module Dexpace; class Configuration; module Sources` — including the one in its own body. The cop's fix
("write `::Foo`") is available, but a name chosen so the shadow never exists is better than a cop policing
one, and it is the same reasoning phase 4a used to reject `Dexpace::Context::Request` (P4-1). Recorded as
`P5-3` because the alternative — adding `ENV` to the cop's `SHADOWED` list — was the visible option.

### `Dexpace.configure`, `.configuration`, `.reset_config!` — `CFG-13`

The two names design §8.2 supplies, plus the reader.

- `Dexpace.configure { |builder| … } -> Configuration` yields a `Configuration::Builder` and atomically
  replaces one frozen reference under a `::Thread::Mutex`. The mutex is held across the assignment and
  nothing else — never across the caller's block, which runs before it is taken, so a `configure` block that
  itself calls `Dexpace.configuration` cannot deadlock on a non-reentrant mutex.
- `Dexpace.configuration -> Configuration` reads the reference with **no lock**. That is
  `concurrency-and-async/f414b864`'s shape and `CFG-8`/`CFG-13`'s safe publication: the object is frozen, so a
  reader that observes it observes it whole.
- `Dexpace.reset_config! -> Configuration` restores `Configuration::EMPTY`. It exists because
  `testing/4ef070df` requires every test to run alone in any order, and a suite that mutates a process-wide
  slot without a restore cannot. It is public API and carries a ledger row.
- **`Dexpace.configuration` is a method and not a constant**, because `data-modeling/6accaff9` requires a
  mutable constant to be frozen at assignment and this slot is replaceable by design.

### `Dexpace::ConfigParsers` — `CFG-5`, `CFG-6`, `CFG-7` (`private_constant`)

Three module functions, each total, each returning a sentinel the accessor turns into the caller's default.

- **integer** — `Integer(raw, 10, exception: false)`. Base 10 explicit (verified fact 6: `Integer("010")` is
  8). Negative values are valid and returned as-is (`CFG-5`). Ruby's two tolerances are documented rather than
  removed: `"1_000"` resolves to 1000 and `" 5 "` to 5.
- **boolean** — `raw.downcase` against exactly `"true"` and `"false"`; everything else, `"1"`/`"0"`/`"yes"`/
  `"no"`/`"on"`/`"off"` included, falls to the default (`CFG-6`). **No trimming**: `" true"` falls through,
  because `CFG-6` grants case-insensitivity and nothing else.
- **duration** — three branches in `CFG-7`'s own order, returning `Float` **seconds**:
  ISO-8601 when the string starts `P` or `p`, hand-written because `Date._iso8601` parses none of them
  (verified fact 6); `<number><unit>` with `ms`/`s`/`m`/`h`/`d` folded; and a bare number as
  **milliseconds**. A negative value in any branch and an unknown unit both return the default. Two anchored
  patterns, each `Regexp.new(source, timeout:)`.

### `Dexpace::Clock` and `Clock::SYSTEM` — `CFG-15`, `CFG-16`, `CFG-17`

A class, because it implements behaviour (`data-modeling/3e37c086`), with a frozen shared instance.
**Exactly three instance methods**, because `CFG-15` says "exposing three operations" and a fake owes the seam
what the seam declares.

| Method | Requirement |
|---|---|
| `#now -> Time` | `CFG-15`'s wall clock. `Time.now`. `CFG-16` forbids its use for elapsed time |
| `#monotonic -> Float` | `CFG-16`'s **elapsed-time** counter. `Process.clock_gettime(Process::CLOCK_MONOTONIC)`, seconds, used only for differences. Verified 1 ns resolution and non-decreasing over 100 000 readings |
| `#sleep(duration, cancellation: nil) -> nil` | `CFG-15`'s blocking interruptible sleep and all of `CFG-17` |
| `Clock::SYSTEM` | `CFG-15`'s "shared default backed by the platform clock MUST be provided" |

`#sleep`, clause by clause:

- **negative → `Dexpace::InvalidArgumentError`**, and the guard is 5a's rather than inherited: verified fact 8,
  `Thread::Queue#pop(timeout: -1)` returns `nil` immediately and raises nothing.
- **zero → returns `nil` promptly**, allocating no queue and taking no subscription. `CFG-17`'s "possibly
  yielding" is a MAY and is not taken; a `Thread.pass` would make a zero sleep a scheduling event, which is
  more than the requirement asks for.
- **positive → a bounded wait on a per-call `Thread::Queue`** that the cancellation token pushes to on cancel
  (§10.17, boundary 7). The subscription is detached in an `ensure`, which is what P2-14 made
  `Subscription#detach` public for.
- **cancelled → `Dexpace::CancelledError`**, raised through `Cancellation#check!`. That is `CFG-17`'s "MUST
  re-assert the … cancellation status before propagating", met structurally: the token's `cancelled?` was set
  before the push that woke the wait, so a downstream handler that inspects the token observes the cancelled
  state. `XCUT-3`'s "surfacing the cancellation signal rather than a spurious timeout" is the same clause from
  the other end.
- **sub-millisecond precision** (`CFG-17` SHOULD) is verified fact 8's 1 ns clock resolution and the queue's
  50.4 ms measured against a 50 ms request.

The `nil`-versus-value discrimination on the queue pop — `nil` means the duration elapsed, a value means
cancelled — is sound **only because the queue is per-call, private and never closed**; verified fact 8 shows a
closed queue also pops `nil`. That sentence goes in the code, not only here.

### `Dexpace::Async.delay(duration) -> Async::Future` — `CFG-18`

`R6` in full.

### `Dexpace::Async::Future#value` and `#wait` — modified, `DEF-28`

```
#value(cancellation: nil, deadline: nil, clock: Dexpace::Clock::SYSTEM) -> Object
#wait(cancellation: nil, deadline: nil, clock: Dexpace::Clock::SYSTEM) -> self
```

`Async::Completer#await(cancellation, deadline: nil, clock: Clock::SYSTEM)` gains the same two keywords. All
four additions are **widenings**, which `NFR-4`'s "disappears or narrows" lock permits and which
`api-design/1d9e6e0b`'s corpus rules make a non-breaking change.

**`deadline:` is a monotonic instant, not a duration**, on the scale `Clock#monotonic` returns. A duration
would restart at every pipeline hop, which is the failure "deadlines are explicit values" exists to prevent.
`Dexpace::Clock.deadline_in(duration, clock: Clock::SYSTEM) -> Float` is the one-line helper that names the
scale, and it exists because computing a deadline off `Time.now` is the exact mistake `CFG-16` forbids. It is
a **class** method, deliberately: `_Clock` declares three instance methods and a fake owes the seam exactly
those (`P5-10`), so a convenience that composes them must not join them.

**On expiry the wait cancels the future and then raises**, rather than raising a bare timeout. The
`Dexpace::CancelledError` carries a reason naming the deadline, and cancelling the future is what makes the
producer stop and what lets `SEAM-30`'s orphaned-response rule fire. Two consequences, both stated:

- **no new error class**, which keeps `NFR-4`'s surface unchanged and keeps a caller's single
  `rescue Dexpace::CancelledError` correct for both causes; a caller that must distinguish them reads
  `#reason`, which is what `CancelledError#reason` is for;
- **a deadline in this port bounds a wait; it does not abort work in the background.** Nothing fires when
  nobody is waiting. That is "deadlines are explicit values, not ambient interrupts" taken to its conclusion,
  and it is the sentence a phase-8 transport author needs before threading `deadline:` into
  `open_timeout`/`read_timeout`/`write_timeout`, which is where a deadline does become a socket-level bound.

### `Dexpace::Proxy` — `CFG-22`, `CFG-23`, `CFG-27`

A `Data` including `Dexpace::Model`, `private_class_method :new`.

```
Data.define(:type, :host, :port, :non_proxy_hosts, :username, :password, :challenge_handler, :bypass_all)
```

- **`host` and `port` replace `CFG-22`'s "socket address"**, because Ruby has no `InetSocketAddress` and
  design §10.18's substituted-constant precedent covers a substituted *type* for the same reason (`P5-5`).
  It also puts `CFG-25`'s range check on one member.
- `non_proxy_hosts` is a frozen `Array` of `Proxy::HostPattern`, ordered (`CFG-22`).
- `username`, `password` and `challenge_handler` are the three slots `CFG-37` documents as nullable.
- `bypass_all` is `CFG-27`'s explicit flag, never a literal `"*"` in the list.
- **`#to_s` and `#inspect` are both overridden to mask credentials.** `CFG-22` requires the string rendering
  to mask; `Data`'s generated `#inspect` prints every member including `password`, and `#inspect` is what a
  log line, a `p`, and an `assert_equal` failure message all print. Overriding only `#to_s` would satisfy the
  requirement's letter and leak the password through the path most likely to reach a log — the same reasoning
  phase 4a applied to `Context#inspect`, resolved the other way because here there is a secret (`P5-7`).
- `#bypass?(host)` is `CFG-23`: `true` when `bypass_all`, else `true` iff any pattern matches.

### `Dexpace::Proxy::Type` — `CFG-22`

A frozen `Data` over a frozen table with an `.of` factory, per `type-system/545949a5` — never a `Symbol` and
never a `T::Enum`. `Type::HTTP`, `Type::SOCKS4`, `Type::SOCKS5`; `.of` raises on an unrecognised token, which
is the `Protocol` treatment rather than the `Status` treatment because the set is closed by the requirement.

### `Dexpace::Proxy::HostPattern` — `CFG-23`

`Data.define(:glob, :matcher)`, `.of(glob)` as the parse-constructor, `#matches?(host)`.

`initialize` compiles `matcher` from `glob` when it is `nil`, which is `CFG-23`'s "Patterns SHOULD be compiled
once at construction, not per lookup" and is also what lets `Model#with` round-trip through
`.build(**to_h, **changes)` without a member that cannot be reconstructed. The translation is verified fact
11: `*` → `.*`, `?` → `.`, everything else `Regexp.escape`d, anchored `\A…\z`, `IGNORECASE`, with a
per-pattern `timeout:`.

**`\z` and never `\Z`**, verified: `\Aabc\Z` matches `"abc\n"` and `\Aabc\z` does not. A full-string match that
accepts a trailing newline is not a full-string match, and a host name arriving from configuration is exactly
where a stray newline comes from.

**`*` does not match an embedded newline, and 5a does not add `/m`.** `CFG-23`'s words are "match any run of
characters" and verified fact 11 shows `.*` without `/m` stops at `\n`. The decision is to leave it: a host
name containing a newline is not a host name, `CFG-23`'s subject is host matching, and adding `/m` would make
`*.example.com` match `"evil.com\n.example.com"` — turning a tolerance into a bypass of the very check the
pattern performs. Recorded here because the charter's verified fact 10 asked for the choice or the reason.

### `Dexpace::ProxyResolution` — `CFG-24`, `CFG-25`, `CFG-26`, `CFG-27`, `CFG-28` (`private_constant`)

The resolver behind `Dexpace::Proxy.resolve(configuration = Dexpace.configuration) -> Proxy?`.

- **`CFG-24`'s precedence, exactly:** `raw_property("https.proxyHost")` preferred over
  `raw_property("http.proxyHost")`; the port read from the **same layer as the chosen host**; credentials from
  `https.proxyUser`/`https.proxyPassword` **only**, with no `http.*` fallback, even when the host came from
  the `http.*` pair — which is the chapter's own conformance case and the one a reader will get wrong.
- **Falling back to the environment URL**, `HTTPS_PROXY` preferred over `HTTP_PROXY`, parsed with
  `URI::RFC3986_PARSER`.
- **`CFG-25`'s absent port is read off `URI::RFC3986_PARSER.split(url)[3]` and never off `#port`** (verified
  fact 10): `parse("http://proxy.example").port` is **80**, already defaulted, while `split(...)[3]` is `nil`.
  This is the single most likely defect in the whole sub-phase and it is silent — a proxy URL with no port
  would resolve to port 80 and the requirement's whole point ("the request's target scheme is unrelated to
  the proxy's listen port") would be inverted.
- **Range check 0..65535 is 5a's**, verified: `parse("http://h:70000").port` is 70000 with no complaint.
- **Credentials are decoded with `URI.decode_uri_component`**, never `URI::RFC3986_PARSER.unescape`, which
  emits an obsolescence warning on 3.4.10 (verified fact 10) against a gate set that fails on warnings, and
  never `URI.decode_www_form_component`, which would turn `+` in a password into a space.
- **`CFG-24`'s never-throw is a `rescue` around the parse**, because `parse("http://h:abc")` raises
  `URI::InvalidURIError` (verified). `Dexpace::URL.parse!` is deliberately not used: its contract is to raise.
- **`CFG-26`'s list** is verified fact 12's split — negative-lookbehind separator, `-1` limit, drop-empty,
  unescape, trim, in that order — with the system property `http.nonProxyHosts` (pipe-separated) winning over
  `NO_PROXY` (comma-separated).
- **`CFG-27`'s bypass-all** fires when the resolved list is exactly one bare `"*"`; resolution then returns
  `nil` so the caller routes directly, and the flag rather than a literal entry is what carries it. A `"*"`
  inside a multi-entry list stays a normal any-host glob.
- **`CFG-28`'s MAY is taken**, and its prohibition is met structurally: `Proxy.resolve` defaults its argument
  to `Dexpace.configuration`, and **nothing in core calls `Proxy.resolve`**. No environment read happens
  unless a caller invokes the resolver, which is "nothing may read proxy configuration implicitly at
  construction/startup" enforced by the absence of a call site rather than by a comment.
- **The warning `CFG-24` and `CFG-25` both require is `Kernel#warn`**, following phase 2's P2-6 verbatim.
  `5b` adds the `http.instrumentation.*` event beside it and does not remove it (`P5-8`).

### `Dexpace::HTTPDate` — `CFG-29`, `CFG-30`, `CFG-31`

`.format(time) -> String` — `time.httpdate`, verified byte-exact against `CFG-29`'s own example, requiring
`time`. `.parse(text) -> Time` — `R2`'s owned grammar, raising `Dexpace::InvalidArgumentError` carrying the
input.

### `Dexpace::UUID` — `CFG-32`

`.generate -> String`. `R3`'s carrier, verified fact 5's layout. Its YARD block states, because the
requirement does and because a caller will otherwise assume the opposite, that the output is
**non-cryptographic** and that `XCUT-21`'s security-relevant values come from a different path.

### `Dexpace::DeepValue` — `CFG-33`, `CFG-34` (`private_constant`)

`R4` in full. `.equal?(a, b) -> bool` and `.hash(value) -> Integer`.

### `Dexpace::Retryability` — `CFG-35`'s status half, `XCUT-5`

`.retryable_status?(status) -> bool`, accepting an `Integer` or a `Dexpace::Status`.

**A predicate and not an exposed set.** `XCUT-7`'s configured retryable-status set is enumerable, mutable by
configuration and phase 6's; publishing `CFG-35`'s built-in classification as a second enumerable constant
beside it is how the two get confused, which `XCUT-5`'s closing NOTE exists to prevent. The classifier is a
rule; the configurable set is data; only the second is a collection.

**No method for the throwable half** — `R1`, `DEF-40`.

### `Dexpace::BuildInfo` — `CFG-36`

Frozen constants resolved once at load: `SDK_VERSION`, `RUNTIME_VERSION`, `RUNTIME_VENDOR`, `OS_NAME`,
`UNKNOWN = "unknown"`, and `IDENTITY_TOKENS`, the ordered pair `CFG-36` names — the SDK token then the runtime
token — every element non-blank by construction.

### The two picked-up wirings

- **`Dexpace::ContextStore.default`** reads `Keys::MAX_TRACKED_CONTEXTS` from `Dexpace.configuration` at first
  construction, falling back to `MAX_TRACKED_CONTEXTS = 1024`. No signature changes, which is `DEF-36`'s own
  claim. **The consequence is stated because it is not obvious:** the store is memoised, so a
  `Dexpace.configure` after the first promotion does not resize it, and neither does `Dexpace.reset_config!`.
  A cap is a process-lifetime property here, and a test that needs a different one builds its own
  `ContextStore.new(cap:)` — which is what phase 4a made the keyword for.
- **`Dexpace::IO`** gains a configured source for `MAX_MATERIALIZED_BYTES`, reading `Keys::MAX_MATERIALIZED_BYTES`
  with the frozen constant as the default. **No `ceiling:` keyword is added anywhere**, so phase 3's boundary
  8 — "a `ceiling:` keyword on a preview operation would give one stream two ceilings" — is untouched, and
  §3.1's "configurable through the same layered chain as every other limit" is satisfied by the source rather
  than by a parameter. `DEF-34`'s other two wirings need `5b`'s enablement setting; **5a does not edit the
  `DEF-34` row**, because the charter puts that on whichever of `5a`/`5b` lands second.

### The RBS interfaces

Three, all new, all under `Dexpace::`:

```
interface _Clock
  def now: () -> ::Time
  def monotonic: () -> Float
  def sleep: (Numeric duration, ?cancellation: Dexpace::Cancellation?) -> nil
end

interface _ConfigSource
  def call: (String key) -> String?
end

interface _RetryableStatus            # what .retryable_status? accepts beside an Integer
  def code: () -> Integer
end
```

Declaring them as interfaces rather than typing the parameters `untyped` keeps `NFR-11` mechanical: no
constant outside `Dexpace::` and the fixed stdlib allowlist appears in any public signature. `::Time` and
`Numeric` are stdlib and allowlisted; `_Clock` is what a fake clock satisfies and what `Future#value(clock:)`
types against.

## The spec-forced boundaries, honoured

Eight of the charter's fifteen bind 5a; each is honoured by a named mechanism rather than by intent.

1. **The bundled-gem rule (boundary 1).** 5a requires `time` and `uri`, both allowlisted, and nothing else.
   It writes no `require "logger"`, no `require "base64"`, no `require "timeout"` and no
   `require "securerandom"`. `R5` is where the allowlist would have grown and does not.
2. **`CFG-1`'s ordering is preserved even where it inverts Ruby convention (boundary 6).** Four tiers,
   call-site override > `ENV` > `configure` defaults > caller default, with the `configure` tier a genuinely
   distinct in-process source and not a second `ENV` read under another name (P11). `CFG-3`'s normalised-key
   accessor (`#string`) and `CFG-4`'s raw exact-name accessor (`#raw_property`) stay distinct methods with
   distinct names, and the proxy resolver uses only the second — which is §10.16's "one deviation applied
   twice, not two deviations".
3. **`CFG-15`'s wait is a cancellable queue wait and not `Kernel#sleep` (boundary 7).** §10.17. No
   `Timeout.timeout`, no `Thread#raise`, no `Thread#kill`; `Dexpace/NoThreadInterrupt` and the `timeout`
   denylist entry are the mechanised halves.
4. **`CFG-32`'s non-cryptographic UUID and `XCUT-21`'s CSPRNG stay two code paths (boundary 8).** `R3` writes
   no `require "securerandom"` and reaches no `SecureRandom` constant, which is checkable by text.
5. **`CFG-34`'s boxed-versus-primitive clause is recorded inapplicable, and only that clause (boundary 9).**
   `R4` implements the NaN and signed-zero halves and reads the element-kind half into a language with one
   `Array`.
6. **The three unsatisfied MUSTs are settled and phase 5 does not re-open them (boundary 13).** `R7` carries
   `CFG-20` as a SHOULD with a named clause and files no fourth entry.
7. **`Fiber[:key]` is the diagnostic-context carrier and `CTX`'s store is not it (boundary 14).** 5a puts no
   diagnostic context anywhere; `R3` uses `Thread.current[]` for a PRNG and the section says in as many words
   why that is not a counter-example.
8. **Phase 4a's five-clause handshake over the instrumentation bundle (boundary 10).** 5a touches
   `Dexpace::Instrumentation` not at all — no member added, no singleton replaced, no second `NONE`. It is
   named here because it is on the charter's closed list and a reader must be able to see that 5a met it by
   staying out.

## Cross-cutting constraints that bite 5a specifically

1. **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden.** In 5a this is not background: it is
   why `CFG-15`'s wait is a queue wait and the only reason `CFG-20`'s fourth clause cannot be built. It is
   also why `Clock#sleep`'s cancellation path raises **at the caller's own next instruction** after the wait
   returns, rather than at an arbitrary bytecode.
2. **Deadlines are explicit values, never ambient interrupts.** `DEF-28`'s `deadline:` is a monotonic instant
   that bounds a wait and cancels a future; it starts no timer, installs no signal handler, and does nothing
   when nobody is waiting. Propagation to `open_timeout`/`read_timeout`/`write_timeout` is phase 8's.
3. **`Thread::Mutex` is per-fiber-owned and non-reentrant.** Two mutexes exist in 5a: `Dexpace.configure`'s
   process-wide slot swap and nothing else — `Clock#sleep`'s queue is its own synchronisation. The
   `configure` mutex is held across the assignment only, never across the caller's block (which runs first)
   and never across a source callable, so a `configure` block calling `Dexpace.configuration` cannot
   deadlock. No 5a code path holds two locks, so no lock order exists to get wrong.
4. **An `Enumerator` abandoned mid-`#next` never runs its `ensure`.** 5a returns no enumerator and yields no
   block that holds a resource. The one resource it acquires — `Clock#sleep`'s per-call `Thread::Queue` and
   its cancellation `Subscription` — lives in one method's own scope with an `ensure` beside it, which is the
   engine-owns-the-resource shape §7.1 fixes.
5. **Bytes on the wire are `Encoding::BINARY`.** 5a produces no wire bytes, and the one place the rule shows
   up is `CFG-32`: `Random#bytes` returns ASCII-8BIT (verified), and `UUID.generate`'s hex rendering is
   produced by `unpack1("H*")` rather than by any encoding-sensitive conversion. `ENV` values arrive UTF-8
   (verified) and are configuration, not wire bytes.
6. **Pin `URI::RFC3986_PARSER` explicitly.** Every parse in `ProxyResolution` does. The lint rule that forbids
   `Time.parse` is the same one that enforces it, and 5a meets both in the same file family.
7. **Regexp timeouts are per-pattern.** Four families of pattern — the date grammar, the two duration
   grammars, the glob translation and the `CFG-26` separator — each `Regexp.new(source, timeout:)`, each
   compiled once into a frozen constant or a `Data` member, and never `Regexp.timeout`.
8. **`Ractor` is never load-bearing, and 5a narrows the claim.** `Configuration` holds two callables and a
   frozen `Data` holding a lambda raises `Ractor::IsolationError` (verified fact 14), so **no shareability
   claim is made for a `Configuration`** despite it being a frozen `Data`. `Proxy` is shareable when its
   `challenge_handler` is `nil` and is not when it is not, so no claim is made for it either.
   `data-modeling/5bc538ba` and P1-9 already narrow the general claim; `P5-6` narrows it once more.
9. **`downcase` takes no argument.** `CFG-3`'s key normalisation, `CFG-6`'s boolean fold, `CFG-7`'s unit fold
   and `CFG-30`'s month fold are four call sites in one sub-phase — more than any phase so far — and every one
   is bare.

## Testing strategy

`test/` mirrors `lib/` one file per file; each file's header comment names the requirement IDs it exercises,
and a non-obvious branch names the ID that forced it. Every suite subclasses `DexpaceTestCase`, so a warning
raised by code under test fails the test that triggered it.

**No transport, no socket, no stream.** Roadmap cross-cutting constraint 4 puts phases 1 through 7 on an
in-memory fake transport; 5a touches no transport at all. The only real I/O in the sub-phase is `::ENV`, and
`CFG-11` makes it injectable **by requirement**, so no test in 5a reads or writes the process environment.

**Three doubles, and all three are fakes** (`testing/7ecef8e8`, `/630ba094`), under
`gems/dexpace-core/test/support/`, each required explicitly by the suites that use it (phase 2's precedent).

- **`FakeClock`** — a real in-memory `_Clock`: `#now` and `#monotonic` return values the test advances, and
  `#sleep` records its arguments and returns without waiting.
- **`FakeSource`** — `->(key) { hash[key] }` over a test-owned hash, which is `CFG-11`'s whole point and what
  makes every `CFG-1`–`CFG-10` case hermetic.
- **`ProbeScheduler`** — the minimal `Fiber::Scheduler` written for verified fact 8, used by `CFG-18`'s suite
  **and nowhere else**. It exists because `CFG-18`'s only interesting clause is conditional on a scheduler
  and there is no scheduler gem in the MVP's dependency budget; it implements `block`, `unblock`,
  `kernel_sleep`, `io_wait`, `fiber` and `close` and asserts nothing about performance.

**The tests a reader would otherwise write wrong.**

- **`CFG-25`'s absent port, and the accessor that hides it.** Assert that a proxy URL with no port resolves to
  `nil` — and write the assertion against `URI::RFC3986_PARSER.split(url)[3]`, not `#port`. A test that builds
  the resolver on `#port` passes for `"http://h:8080"` and passes for `"http://h"` **by resolving to port 80**,
  which is the exact behaviour `CFG-25` forbids. The suite therefore carries a direct assertion on the parser
  (`P.parse("http://proxy.example").port == 80`) as a **guard**, so the day someone "simplifies" the resolver
  to use `#port`, a test says why it is wrong rather than merely failing.
- **`CFG-24`'s credential rule, which is a negative.** Set `http.proxyHost` and `http.proxyPort` only, plus
  `https.proxyUser` and `https.proxyPassword`, and assert the resolved proxy carries **those** credentials —
  the chapter's own conformance case. A test that sets the `https.*` host too proves nothing, because the
  cross-layer read is what the requirement is about.
- **`CFG-24`'s never-throw, without `assert_nothing_raised`.** `testing/26b866e1` forbids it, so each
  malformed input asserts `assert_nil` on the result **and** asserts on the captured warning. That second half
  is not optional: `Kernel#warn` routes through `Warning.warn`, and a test that lets it escape fails under
  `DexpaceTestCase` for a warning the code was required to emit. Every never-throw case captures.
- **`CFG-2`'s asymmetry.** Assert that an **environment** value of `""` falls through to the property layer,
  and, in the same test, that an **override** of `""` resolves to `""`. The second half is what stops a later
  refactor from making emptiness a chain-wide rule.
- **`CFG-38` against `CFG-5`.** Supply a value only through the env seam and assert `#integer`, `#boolean` and
  `#duration` all resolve it rather than returning their typed defaults. A test that supplies the value as an
  override passes against an implementation that reads only the override map — which is the implementation
  `CFG-38` exists to forbid.
- **`CFG-9`'s copy-on-write, both halves.** Derive with an added override and assert the **receiver** is
  unchanged; and assert `derived.env_source.equal?(source.env_source)` — `assert_same`, never `assert_equal` —
  because `CFG-9` says the seams are "inherited by reference (shared, not copied)" and a value comparison
  passes against an implementation that duplicated them.
- **`CFG-8` against the builder.** Build, mutate the builder, rebuild, and assert the **first** instance is
  unchanged; then assert `configuration.overrides.frozen?` and that `overrides["x"] = 1` raises `FrozenError`.
  The mutate-and-rebuild half alone passes against a builder that happens not to alias.
- **`CFG-17`'s negative duration.** Assert `Dexpace::InvalidArgumentError`. A test that asserts "returns
  promptly" passes against a missing guard, because verified fact 8 shows the underlying
  `Queue#pop(timeout: -1)` returns `nil` immediately and raises nothing.
- **`CFG-15`'s cancellation, and the two branches a fake can and cannot drive.** The cancelled branch is
  deterministic: cancel the source, then call `#sleep(5.0, cancellation:)` and assert it raises
  `Dexpace::CancelledError` promptly and that the token reads `cancelled?` true afterwards (`CFG-17`'s
  re-assertion). The **elapsing** branch cannot be faked — no fake clock makes a real `Thread::Queue` wake
  early — so it is a short real interval with a monotonic-difference assertion and a generous upper bound,
  which is the shape phase 2's own wait tests already use.
- **`CFG-18` under and without a scheduler.** Two suites. Without: assert zero completes immediately, negative
  raises, and a positive duration raises `Dexpace::SeamError` whose message names `Fiber.set_scheduler`.
  With `ProbeScheduler`: assert the future settles, and assert the scheduler's `#block` hook fired and its
  `#kernel_sleep` hook did not — which is the only assertion that actually tests "WITHOUT blocking a thread"
  rather than testing that a delay delays.
- **`CFG-34`'s NaN case, and the two traps that make it pass wrongly.** Build **two distinct** NaN objects.
  `[n] == [n]` with the *same* object is `true`, because `Array#==` short-circuits on identity, so a test
  written with one NaN passes against a broken implementation. Assert `DeepValue.equal?([a], [b])` is true
  with `a` and `b` distinct, and assert `!a.equal?(b)` in the same test so the precondition is visible. The
  second trap is on the hash side and is the one verified fact 7 exists to expose: build the pair as
  `0.0/0.0` and `-(0.0/0.0)`, whose **payloads differ** and both of which are genuinely
  `#nan?` — `"nan".to_f` is `0.0`, and assert
  `DeepValue.hash([a]) == DeepValue.hash([b])`. A pair built from one bit pattern hashes equal through
  `Float#hash` alone, so it passes against an implementation that never folds NaN — and that implementation
  breaks `CFG-33`'s mutual consistency on the first NaN a caller did not construct the same way.
- **`CFG-34`'s signed zeros, both directions.** `DeepValue.equal?([0.0], [-0.0])` false **and**
  `DeepValue.hash([0.0]) != DeepValue.hash([-0.0])` — `CFG-34` says "hashing MUST match that equality", and
  the equality half alone passes against an implementation whose hash is `Array#hash`.
- **`CFG-33`'s cycle case, which no requirement asks for.** `x = []; x << x` compared against a structurally
  identical `y`: assert it returns rather than raising `SystemStackError`. Verified fact 7 shows a naive
  implementation raises, so this is a real discriminator and not a tautology.
- **`CFG-19`'s satisfied-by-construction disposition, asserted rather than declared.** `Completer#fail(error)`
  then `Future#value` raises — **`assert_same` on the error object**, not `assert_kind_of`. That is the whole
  observable content of "a non-wrapper throwable MUST be returned unchanged" in a port with no wrapper, and
  writing it as a kind check would pass against an implementation that rewrapped.
- **`CFG-31`'s two failures and `CFG-30`'s four tolerances in one table.** Four zone tokens parsing to the
  identical instant; a wrong weekday accepted; a lower-case month accepted; `""`, `"   "` and
  `"Mon 01 Jan 2024 00:00:00 GMT"` each raising. And — the row a reader would not think to add — **RFC 850
  and asctime rejected**, because verified fact 1 shows `Time.httpdate` accepts both and that row is what
  fails the day someone replaces the grammar with a delegation.
- **`CFG-23`'s newline row.** `\Aabc\z` against `"abc\n"` must not match. Written as a `HostPattern` case
  (`HostPattern.of("evil.com").matches?("evil.com\n")` is false), because that is the form the defect would
  take.
- **`CFG-32`'s isolation, asserted through the carrier.** Generate in the main fiber and in a child fiber and
  a new thread, and assert the three generators are **three distinct objects** by reading
  `Thread.current[:…]` in each — plus the property assertions (version nibble 4, variant in `8`..`b`, 10 000
  with no collision). A distinctness-of-output test alone would pass against a shared generator, which
  verified fact 4 shows produces 16 000 distinct values from 8 threads.
- **`CFG-21`, which phase 2 already satisfies.** One test citing `CFG-21`: `Dexpace.close_quietly(nil)`
  returns `nil` and raises nothing, and a `Completer#fulfil` that loses a race to a cancel closes the response
  exactly once. 5a adds no code for it and adds the citation so the checklist row has a test to name.
- **`CFG-13`'s process-wide slot, restored.** Every test that calls `Dexpace.configure` calls
  `Dexpace.reset_config!` in `teardown`. `testing/4ef070df` is the rule and a leaked global configuration is
  the one way this sub-phase can make an unrelated suite fail in a way that depends on file order.

**Property tests.** `testing/f36a19cd` makes round-trip property tests mandatory for "any value object with
parse-constructor invariants", which reaches `Proxy::Type.of`, `Proxy::HostPattern.of` and `HTTPDate`. Three,
each with a fixed iteration count and a pinned, logged seed (`testing/7ece0212`, `/7b383289`):
`Type.of` round-trips its token; `HostPattern.of(g).glob == g` and `#matches?(g)` is true for every glob with
no metacharacter; and `HTTPDate.parse(HTTPDate.format(t)) == t.floor` for every generated instant — **floored,
because RFC 1123 has no sub-second field**, and a property test written without the floor fails on its first
draw for the right reason and the wrong assertion.

## The interface surface later phases may cite

**The load-bearing statement is a negative one, and it is the charter's.** `5b` and `5c` are not obliged to
consume any of this, and a `5b` plan whose first task waits on `Dexpace::Configuration` has re-imposed a chain
that does not exist. What 5a ships as a stable contract:

| Consumer | What it gets, and when |
|---|---|
| **`5b`**, on `OBS-35` | `Configuration#string(name, default:)` and `Configuration::Keys::LOG_LEVEL`. **`LOG_LEVEL` is a published name a caller may pass, not a default any resolver falls back to** — `OBS-35`'s embedded MUST is "The SDK MUST NOT bake in a default config key name", so `5b`'s log-level resolution takes its key as a **required** argument |
| **`5b`**, on `DEF-34` | The chain, plus `Keys`. `5b` adds the body-preview and enablement key names in the change that reads them, wires `RequestLoggingBody`/`ResponseLoggingBody`, and — landing second — edits the `DEF-34` row. 5a has already given `MAX_MATERIALIZED_BYTES` its source |
| **`5b`**, on `CFG-24`/`CFG-25` | `Dexpace::ProxyResolution`'s `Kernel#warn` call sites. `5b` adds an `http.instrumentation.*` event **beside** each and removes neither, which is P2-6's shape (`P5-8`) |
| **`5b`**, on `CFG-22` | `Proxy#to_s`/`#inspect` already mask credentials, so a proxy reaching a log line is not a redaction case `OBS-11`–`OBS-19` has to catch. `5b` may not rely on that for any other type |
| **`5c`** | Nothing. 5a touches `Dexpace::Instrumentation` not at all |
| **Phase 6**, on `RETRY-1`/`XCUT-5` | `Dexpace::Retryability.retryable_status?`. Phase 6 computes `DEF-38`'s baked flag **from it** and builds no second status classifier; `XCUT-7`'s configurable set is a different object and its default `{408, 429, 500, 502, 503, 504}` is a subset of this one |
| **Phase 6**, on `CFG-35`'s throwable half | `DEF-40`. Phase 6 adds the classification through `XCUT-6`'s capability, not through a concrete-type match, and `Dexpace.each_cause` is the walk it uses |
| **Phase 6**, on `RECOV-27` / `DEF-35` | `Dexpace::Clock#sleep(duration, cancellation:)` and `Clock::SYSTEM`. This is the object `DEF-35` moved fifteen `RECOV` IDs to phase 6 to reach |
| **Phase 6**, on `RETRY-12` | `Keys::MAX_RETRY_ATTEMPTS`. The **name** only; the 200 ms / ×2 / 8 s / 0.2 / 3-sends values are phase 6's |
| **Phase 6 and 8**, on `DEF-28` | `Future#value(cancellation:, deadline:, clock:)` and `#wait(...)`, and `Clock.deadline_in`. A deadline **bounds a wait**; it aborts nothing in the background |
| **Phase 8**, on `TRANSPORT-3` | `Dexpace::Proxy` with `#bypass?`, and `Dexpace::Proxy.resolve(configuration)`. Core opens no socket; the adapter decides how to use the model |
| **Phase 8**, on `CFG-15` | `_Clock`. Every phase-8 adapter takes `clock:` rather than calling `Time.now`, which is `CFG-15`'s "Time-dependent logic … SHOULD route through this seam" |
| **Phase 9**, on `XCUT-11` | `Configuration` (frozen, no per-call state) and `Clock::SYSTEM` (stateless) as the audited shared instances |
| **Phase 9**, on `XCUT-19`/`XCUT-21` | `Dexpace::UUID` as the path that is deliberately **not** the CSPRNG one, and `Proxy`'s masked rendering |

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`. Numbering starts at `P5-1`; the
phase-5 segmentation design left the ledger empty, and no `P5-<n>` exists anywhere in `docs/` (verified).

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P5-1 | Public constants design §8.2 does not name: `Dexpace::Configuration` with `::Builder`, `::Keys` (seven constants), `::Sources` (two constants) and `::EMPTY`; `Dexpace::Clock` with `::SYSTEM`; `Dexpace::Proxy` with `::Type` (three constants) and `::HostPattern`; `Dexpace::HTTPDate`; `Dexpace::UUID`; `Dexpace::Retryability`; `Dexpace::BuildInfo` (six constants); and the RBS interfaces `_Clock`, `_ConfigSource`, `_RetryableStatus` | `NFR-4`; `api-design/b0e18938`; phase 2's P2-11 and phase 4a's P4-2 precedent | §8.2 names exactly two Ruby identifiers, `Dexpace.configure` and `Dexpace.reset_config!`, and describes everything else in prose. `NFR-4` locks every public name at the first release tag, so a name arriving by accident is locked by accident. Each is chosen for a stated reason in the object-model section |
| P5-2 | Public **methods** design §8.2 does not name: `Configuration#string`, `#raw_property`, `#integer`, `#boolean`, `#duration`, `#derive`, `#new_builder`, `.build`, `.builder`; `Configuration::Builder#override`, `#remove`, `#property`, `#env_source=`, `#property_source=`, `#build`; `Configuration::Sources.from_hash`; `Dexpace.configuration`; `Clock#now`, `#monotonic`, `#sleep`, `Clock.deadline_in`; `Dexpace::Async.delay`; `Proxy.resolve`, `Proxy#bypass?`, `#to_s`, `#inspect`; `Proxy::Type.of`; `Proxy::HostPattern.of`, `#matches?`; `HTTPDate.format`, `.parse`; `UUID.generate`; `Retryability.retryable_status?`; plus the `deadline:` and `clock:` keywords on `Future#value`/`#wait` and `Completer#await` | `NFR-4`; phase 2's P2-11 and phase 4a's P4-11, both of which cover methods as well as constants | `NFR-4` locks a public *signature*, not only a name. Two deserve naming here because a later reader will question them. **`Clock.deadline_in` has exactly one caller and it is a caller's convenience**, kept because computing a deadline off `Time.now` is the mistake `CFG-16` forbids and a helper that names the monotonic scale is the cheapest way to make it hard; it is a class method so it stays outside the three-operation seam `_Clock` declares. **`Configuration::Sources.from_hash` is exercised only by `Dexpace.configure`** and is public because a hermetic test needs the same construction (`CFG-11`) |
| P5-3 | The environment seam constant is `Sources::ENVIRONMENT`, not `Sources::ENV` | `CFG-11`; `Dexpace/QualifiedCoreConstant` (P2-8, P3-7); phase 4a's P4-1 | `Sources::ENV` would shadow Ruby's `::ENV` for every bare reference inside `module Dexpace; class Configuration; module Sources`, including the one in the constant's own definition. The cop's fix is "write `::Foo`", which works and leaves the shadow in place; adding `ENV` to `SHADOWED` would flag every legitimate bare `ENV` in the repository. A name with no shadow is better than a cop policing one, which is the reading phase 4a gave the three context flavours |
| P5-4 | `Configuration#duration` returns a `Float` of **seconds**, and no `Dexpace::Duration` type is introduced | `CFG-7` ("a bare number … MUST be interpreted as MILLISECONDS"); phase 1's `RequestOptions#timeout` | `CFG-7` fixes the *input* unit for one branch and says nothing about the return type; the reference returns a platform `Duration` object Ruby has none of. Seconds as a `Float` is what `Kernel#sleep`, `Thread::Queue#pop(timeout:)`, every Ruby socket API and phase 1's own `RequestOptions#timeout` already speak, so no unit conversion sits between the accessor and its consumer. A `Dexpace::Duration` value type was considered and rejected: it would be a type every later phase unwraps, which is the reason phase 1 gave for `URL.parse!` returning a `URI::Generic` |
| P5-5 | `CFG-22`'s "socket address" is two members, `host:` and `port:`, rather than one address type | `CFG-22`; design §10.18's substituted-constant precedent | Ruby has no `InetSocketAddress` and `URI::Generic` is not one — its `#port` defaults (verified fact 10), which is precisely what `CFG-25` forbids. Two members put `CFG-25`'s range check on one field and make an absent port representable as `nil` rather than as a defaulted integer |
| P5-6 | No `Ractor` shareability claim is made for `Dexpace::Configuration`, and the claim for `Dexpace::Proxy` is conditional | `CFG-11`; `data-modeling/5bc538ba`; phase 1's P1-9 | Verified: `Ractor.make_shareable` on a frozen `Data` holding a lambda raises `Ractor::IsolationError`. `CFG-11` **requires** the two sources to be callables, so an unconditionally shareable `Configuration` is unreachable by requirement rather than by choice. `Proxy` is shareable exactly when its `challenge_handler` is `nil`, and a claim that holds sometimes is not a claim |
| P5-7 | `Dexpace::Proxy` overrides **both** `#to_s` and `#inspect`; phase 1 overrode neither on `Request`/`Response` and phase 4a deliberately overrode neither on a context | `CFG-22` ("Its string rendering MUST mask credentials"); `XCUT-19`(d); phase 4a's `#inspect` finding | `Data`'s generated `#inspect` prints every member, and `#inspect` — not `#to_s` — is what `p`, a log interpolation and an `assert_equal` failure message print. Overriding only `#to_s` satisfies the requirement's letter and leaks the password through the likeliest path. Phase 4a reached the opposite conclusion for a context because a context holds no secret and a redaction-aware rendering was phase 5's; here the secret is a member of the model |
| P5-8 | `CFG-24`'s and `CFG-25`'s required warning is `Kernel#warn` in 5a, with `5b` adding an `http.instrumentation.*` event beside it rather than replacing it | `CFG-24`, `CFG-25`; §8.1; phase 2's P2-6 | The charter fixes that every phase-5 boundary is a convenience and requires each sub-phase to state its independence. A warning routed through a facade that does not exist yet would make 5a depend on 5b, which is the chain the cut exists to avoid. P2-6 set the shape for `SEAM-8` — "§8.1's facade does not exist until phase 5 and may add an event then; **it does not replace this**" — and it applies unchanged one sub-phase in. The cost is one warning path that stays after the event lands, which is what P2-6 already accepted |
| P5-9 | `CFG-18`'s delay **raises `Dexpace::SeamError`** when no `Fiber.scheduler` is registered, rather than degrading to a thread-backed delay | `CFG-18`; §8.3; the charter's `R6` | Verified: `Thread::Queue#pop(timeout:)` calls a registered scheduler's `#block` hook and unmounts the fiber, and `Fiber.scheduler` is `nil` by default. There is no non-blocking path without one. A thread-backed delay would satisfy the three MUST clauses and violate the SHOULD's headline while appearing to satisfy it, which the charter forbids in as many words. Raising is the only option that neither lies nor degrades silently, and `Clock#sleep` remains available for the blocking case the `SeamError` message names |
| P5-10 | `CFG-18`'s delay is `Dexpace::Async.delay`, not a fourth method on `Clock` | `CFG-15` ("exposing three operations"); `CFG-18` ("The async layer SHOULD provide") | A fourth method on the time seam would widen what every fake clock owes for a requirement whose stated subject is the async layer. Three operations is what `_Clock` declares and what `FakeClock` implements |
| P5-11 | `CFG-19` ships **no** `unwrap` method; the requirement is satisfied by construction | `CFG-19`; §11.15's clauses-with-no-Ruby-manifestation family; `OI-8`'s shape | Ruby has no completion/execution wrapper — `Thread#value` re-raises the original and phase 2's `Completer#fail(error)`/`Future#value` deliver the caller's own object — so "a non-wrapper throwable MUST be returned unchanged" holds for every input and an implementation would be an identity function under an `NFR-4` lock with no caller. That is `OI-8`'s exact shape. The requirement's observable content is asserted (`assert_same` on the error object) rather than implemented, and `Dexpace.each_cause` already exists if a later phase finds a wrapper |
| P5-12 | `CFG-30`/`CFG-31` are parsed by an owned anchored grammar rather than by `Time.httpdate` or `Date._httpdate`, while `CFG-29` formats through `Time#httpdate` | `CFG-30`, `CFG-31`; `Dexpace/NoTimeParse` | Verified fact 1: `Time.httpdate` accepts RFC 850, asctime and a leading space, so a delegating parser accepts two date formats with no `'Xxx, '` prefix — the exact prefix `CFG-31`'s strictness clause is about — while still passing the chapter's two conformance cases. And a normalise-first route makes `CFG-31`'s failures a property of a method the input no longer reaches unmodified. The formatting direction has no such problem and `Time#httpdate` is byte-exact against the specification's example |
| P5-13 | `Dexpace::UUID`'s generator is memoised in `Thread.current[:…]`, the carrier `CLAUDE.md`'s constraint list names as the wrong one | `CFG-32`; `docs/knowledge/notes/observability.md`; `CLAUDE.md`'s diagnostic-context constraint | Verified: `Fiber[]` hands the same object to a new `Thread` by identity, which is the shared mutable state `CFG-32` forbids; `Thread.current[]` is inherited by neither a child fiber nor a new thread, so no two execution contexts share a generator. The `CLAUDE.md` line is about the diagnostic context, where inheritance is the property wanted; here non-inheritance is. Recorded as a deviation because the sentence a reader will check reads as a blanket rule |
| P5-14 | `CFG-34`'s "distinct array kinds" is implemented as **element**-kind distinctness (`[1]` ≠ `[1.0]`) while the **container**-kind clause stays inapplicable per §11.15 | `CFG-34`; §11.15 | Ruby has one `Array`, so there is no second container to be unequal to — that is §11.15's clause and it is not extended. What Ruby does have is `[1] == [1.0]` true with `[1].eql?([1.0])` false and `1.hash != 1.0.hash` (verified), so an `Integer` array and a `Float` array of the same numeric values are the nearest true reading of the requirement's sentence, and `eql?` semantics for numeric leaves is also what keeps the helper's hash consistent with its equality, which `CFG-33` makes a MUST |
| P5-15 | `Dexpace::DeepValue` carries an identity-keyed visited set, which no `CFG` ID requires | `CFG-33`; `XCUT-9`'s mechanism; verified fact 7 | A naive recursive comparison of two self-referential arrays raises `SystemStackError` where `Array#==` survives through Ruby's own recursion guard. A hand-written helper that is less robust than the language on the one input the language handles is a regression, so the guard is `{}.compare_by_identity` — the same mechanism `Dexpace.each_cause` uses — and no second walk is written |

## Deferrals Filed by Phase 5a

Filed against `docs/deferred-items.md`; the row names an explicit target and pick-up condition, per the
roadmap's execution step 7. (The heading avoids the literal words the housekeeping probe's `registers` check
reserves for the aggregate register, which is where the row lives.)

| ID | Deferral | Target / condition |
|---|---|---|
| `DEF-40` | `CFG-35`'s **throwable** half — "SHOULD treat a throwable as retryable iff it or any throwable in its cause chain is an IO/timeout error", with cycle-safe traversal. 5a ships the status half as `Dexpace::Retryability.retryable_status?` and **no** method for the throwable half, not a stub and not a predicate returning `false` | Phase 6, with `XCUT-6`'s retryability capability and `RETRY-1`. Verified: `::SocketError`, `::Timeout::Error` and `::OpenSSL::SSL::SSLError` are undefined in a bare interpreter; `socket`, `timeout` and `net/http` are denylisted, and `openssl` is allowlisted but buys one class of four at the cost of loading it at core's require time; and of the classes core *can* name, none of `SocketError`, `Errno::ETIMEDOUT` or `Timeout::Error` is an `IOError`, while `Dexpace::StreamError` is. `XCUT-6`'s capability is what lets an adapter declare its own errors retryable without core naming them, and `Dexpace::TransportError` (phase 8) is the other half |

## Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every row.
All thirty-nine were read; the charter's own sweep covered the phase-5-wide dispositions and is not repeated,
so what follows is the **5a-specific delta**. As with phases 3 and 4, this document **states** each
disposition and 5a's **plan performs** the register edit.

- **`DEF-28` — picked up, and the row moves to `picked-up` when 5a's plan lands.** Its condition names phase 5
  "with `CFG-15`–`CFG-21`'s clock and interruptible-delay primitives" and names the composition point:
  "`Dexpace::Cancellation.any` is the composition point a deadline-derived token plugs into, and
  `Cancellation.over` is public for exactly that." 5a adds `deadline:` and `clock:` to `Future#value`,
  `#wait` and `Completer#await`. `NFR-4` is not prejudiced — adding a keyword widens — and 4c confirms no
  pipeline signature changes.
- **`DEF-36` — picked up.** `ContextStore.default` reads its cap from the chain at first construction. One
  wiring, no signature change, exactly as the row promises. The memoisation consequence is stated in the
  object model rather than left for a later reader.
- **`DEF-34` — half supplied, row **not** edited by 5a.** 5a ships the chain and gives
  `MAX_MATERIALIZED_BYTES` its configured source; the two logging-body wirings need `5b`'s enablement
  setting. The charter fixes that the row is edited by whichever of `5a`/`5b` lands second, and 5a leads.
- **`DEF-38` — untouched, and 5a changes its *source* rather than its content.** The row targets phase 6 and
  `#retryable?` on `Dexpace::ProtocolError` stays there. What changes is that phase 6 computes the flag from
  `Dexpace::Retryability`, which 5a built, instead of building a classifier — `R1`. The row's `Cites:` line is
  committed and 5a does not edit it; `DEF-40` and `OI-21` are where the cross-reference now lives.
- **`DEF-18` — untouched, and cited by 5a's `CFG-20` row.** 5a neither meets nor re-opens it; `R7`.
- **`DEF-35` — untouched, and 5a is what unblocks it.** Its forcing argument was that `RECOV-27`'s conforming
  wait "is the object `CFG-15` defines, which is phase 5's". 5a builds that object; the fifteen `RECOV` IDs
  stay in phase 6.
- **`DEF-27` — untouched, and 5a is deliberately not its second route.** The row's second disposal route is an
  `http.instrumentation.*` diagnostic through §8.1's facade, which is `5b`'s. 5a adds no `close_quietly` call
  site. `CFG-21`'s null-safety clause — the part of the row that is already shipped — is asserted by a 5a test
  and by nothing new.
- **`DEF-30` — untouched, and 5a strengthens the charter's reading without acting on it.** Its condition is
  "an instrumentation seam exists to activate". **5a adds no fourth registry**: the clock is an injected
  object with a shared default, not a discovered seam, and `SEAM-2` enumerates five seams of which the clock
  is none. The row's disposition is `5c`'s to record, as the charter's `R15` says.
- **`DEF-31`, `DEF-32` — untouched.** Both need §8.1's facade; `5b`'s.
- **`DEF-37`, `DEF-1`'s `SEAM-28` half — untouched.** Both are `5c`'s. 5a touches `Dexpace::Instrumentation`
  not at all.
- **`DEF-29` — untouched, and 5a adds three doubles under `gems/dexpace-core/test/support/`.** `FakeClock`,
  `FakeSource` and `ProbeScheduler`, following phases 2, 3 and 4. `CFG-11` makes the env and property seams
  injectable **by requirement** and `CFG-15` does the same for the clock, so a hermetic test never touches
  real `ENV` and never waits on a real interval it could fake. The row's condition — a consumer outside
  `dexpace-core` — is not met. `ProbeScheduler` is worth naming beside `DEF-22`: it is the only double in the
  repository that implements a *host* protocol rather than an owned one, and if `dexpace-conformance` ever
  restates `CFG-18` it will need one too.
- **`DEF-33` — untouched, and its value has grown again.** 5a is the third phase whose concurrency guarantee
  rests on a `Thread::Mutex` the GVL would hide the absence of, and the first whose PRNG isolation rests on
  `Thread.current[]`'s fiber-locality — a property no non-CRuby row currently exercises.
- **`DEF-39` — untouched.** 5a installs no step and writes no preset.
- **`DEF-3` — untouched, and one clause is worth naming.** `BODY-36`'s condition is core's dependency budget
  changing, which 5a explicitly does not do: `R5` is where the allowlist would have grown and did not.
- **`DEF-9` — untouched.** `OBS-32` and `OBS-37` are `5c`'s and `5b`'s ⏳ rows.
- **`DEF-2`, `DEF-4`–`DEF-8`, `DEF-10`–`DEF-17`, `DEF-19`, `DEF-20`, `DEF-22`, `DEF-23`, `DEF-25` —
  untouched.** Other prefixes, later phases, post-v1 gems, or release-gated.
- **`DEF-21` — already picked up** by phase 2. **`DEF-24`, `DEF-26` — already picked up** by phases 4b and 3b.

## The findings filed against `docs/open-items.md`

One, filed by this document.

**`OI-24` — the audit group for this material returns 36 of 38 `CFG` IDs, and `--prefix-info` says 38 of 38.**
The `knowledge-lookup` skill's tenth audit-group row, added by the charter for exactly this phase, is
`--topic observability,configuration,redaction-and-security --section rules --brief` **and**
`--prefix CFG,OBS --section rules --brief`. Running the second half returns 37 entries covering **36 distinct
`CFG` IDs**: `CFG-14` and `CFG-29` are absent, because the corpus files both under the `Reference` section
rather than `Rules` (`configuration/8b79358e` and `configuration/60b0e938`, both `spec ·
docs/product-spec/16-configuration.md`). Meanwhile `--prefix-info CFG` reports "38 of 38 IDs have a
substantive entry, 0 are roll-up only, 0 are uncited", and `--gaps CFG` reports nothing. So a designer who
runs the skill's own row and counts what comes back reads 36 rules, is told separately that there are 38, and
has no signal that the two numbers are about different things. Checked mechanically on 2026-09-09; the `OBS`
half of the same group loses none of its 40, so this is not a general property of `--section rules` but a
per-ID filing decision that happens to fall on two `CFG` IDs — which is worse, because it is invisible by
comparison. `CFG-14` (the well-known key constants) and `CFG-29` (RFC 1123 formatting) are both load-bearing
in this sub-phase and were read from the chapter and from appendix C instead.

This is the `OI-14` and `OI-16` family — a mechanism that reports clean over a set it never looked at — and it
is filed rather than fixed because the fix is a judgement about the tool or the harvest (should `--section
rules` fall back to `Reference` for an ID with no `Rules` entry? should `--prefix-info` report the per-section
split? should the two entries be re-harvested as rules?) and belongs with whoever owns the corpus. The
mitigation available today is one line and is stated for the next phase to copy: **run `--prefix <P>
--section rules` and then diff the IDs it returns against the prefix's canonical range**, rather than trusting
the entry count.

## Open questions for 5a's own plan

Five, each bounded, none reopening a decision above.

1. **Re-run the six floor-straddling facts on 3.2.11 and 4.0.6 before the code that rests on them is written.**
   Facts 1 (`Time.httpdate`'s laxity and `Date._httpdate`'s), 3 (`Fiber[]`'s cross-thread identity), 5
   (`Random#bytes` unfrozen), 8 (`Queue#pop(timeout:)` under a scheduler, and its negative-timeout return),
   9 (`Gem::BUNDLED_GEMS::SINCE` and `RbConfig` under `--disable-gems`) and 14 (`Data#with`'s `initialize`
   override, `ENV`'s frozen return and `Ractor.make_shareable`'s copy semantics). **Only 3.4.10 is installed on this
   machine**, verified. Recommendation: the plan's first task installs the two interpreters and re-runs all
   six as a single script whose output is pasted into the plan, exactly as phases 3 and 4 did. If fact 8's
   scheduler result does not hold on 3.2.11, `P5-9` is unaffected — the `SeamError` branch is the one that
   ships without a scheduler — but `CFG-15`'s non-pinning claim in `Clock#sleep`'s YARD would have to narrow
   to the versions where it was observed.
2. **Whether `strftime`'s `%a` and `%b` are locale-independent.** Verified fact 2: `Time#httpdate` *is*
   `getutc.strftime('%a, %d %b %Y %T GMT')`, and the four locales tested all fell back to C because none is
   installed (`locale -a` lists `C`, `C.utf8`, `en_US.utf8`, `POSIX`). Recommendation: install one non-English
   locale in the plan's environment and assert `Time.utc(1994,11,6,8,49,37).httpdate` byte-for-byte under it.
   If it turns out to be locale-sensitive, `CFG-29` needs a hand-rolled formatter over frozen English tables
   and `P5-12`'s formatting half changes — the parsing half does not, because `R2`'s grammar already carries
   its own month table.
3. **`Completer#await`'s exact bounded-wait shape.** 5a adds `deadline:` and `clock:` to a method whose body
   is `@gate.pop until settled?`. The deadline must bound the *total* wait, not each pop, and a spurious
   wake-up must not extend it. Recommendation: compute `remaining` from `clock.monotonic` on each iteration
   and pass it to `@gate.pop(timeout: remaining)`, treating `remaining <= 0` as expiry — which also makes the
   already-expired branch deterministic under `FakeClock`, since that is the only branch a fake can drive.
   Confirm against phase 2's shipped body on the first task rather than against the plan's quotation of it.
4. **Whether `Dexpace::ProxyResolution`'s seven property names want a `private_constant` module of their own
   or a frozen hash.** The object model puts them as `private_constant`s in the resolver.
   Recommendation: a frozen hash keyed by the layer (`:https`, `:http`) so `CFG-24`'s "the port MUST be taken
   from the SAME layer as the chosen host" is a lookup rather than a branch — the clause most likely to be
   implemented as two independent reads and most likely to pass a test that sets both layers.
5. **Where `Dexpace::IO`'s configured ceiling is read.** `DEF-34` says "give `MAX_MATERIALIZED_BYTES` a
   configured source" and phase 3a reads the constant at its call sites. Recommendation: a module function
   `Dexpace::IO.max_materialized_bytes(configuration = Dexpace.configuration)` that 3a's call sites call,
   rather than a memoised value — a memoised ceiling would make `Dexpace.configure` ineffective after the
   first materialisation, which is the `DEF-36` consequence repeated where it is avoidable. Confirm the call
   sites on the first task; if there is exactly one, inline the read there and add no module function, which
   is one fewer `NFR-4`-locked name.
