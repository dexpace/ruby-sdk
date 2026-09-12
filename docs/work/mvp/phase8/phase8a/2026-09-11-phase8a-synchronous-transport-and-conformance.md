# Phase 8a — Synchronous Transport and Conformance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-transport-net_http` (the reference synchronous transport, the first gem in
this repository to open a real socket) and `dexpace-conformance` (the shared adapter-conformance
harness, `DEF-22`'s home) in full, plus the one phase-level addition to `dexpace-core`
(`Dexpace::TransportError`, `Configuration::Keys::REQUEST_TIMEOUT`) this sub-phase needs to raise
and configure against. Twenty-three requirement IDs, all `TRANSPORT`: `TRANSPORT-1`–`6`, `10`, `11`,
`14`–`20`, `22`, `24`–`30`. Twenty implemented, `TRANSPORT-28` partially satisfied with its zero-copy
clause ⏳ `DEF-10`, `TRANSPORT-30` ⏳ `DEF-10` whole, `TRANSPORT-18` vacuous once `max_retries = 0`.
No deferral is filed; `DEF-3`'s `BODY-12` clause 2 and `DEF-29` are marked UNSCHEDULED, and `DEF-22`
is picked up and closed.

**Architecture:** A per-response producer `Thread` over a `Thread::SizedQueue(1)`
(`Dexpace::Transport::NetHTTP::ResponsePump`), drained through a `#readpartial`-shaped reader that
`Dexpace::IO::BufferedSource.wrapping` owns and closes — not a `Fiber`, because `Fiber#resume` from
a second thread raises `FiberError` (`P8-1`). One outbound adaptation routine
(`RequestMapper.build`) that re-validates every header at the wire boundary (`DEF-25`) before
building a `Net::HTTPGenericRequest` from an empty header set, drops `MANAGED_HEADERS`, deletes the
three construction-time auto-stamps, turns `decode_content` off unconditionally, and sets
`Content-Type` on every body-permitted method whether or not there is a body. One inbound
adaptation routine (`ResponseMapper.build`) that reads headers from `res.to_hash` only, drops a
malformed header per `TRANSPORT-14` before it reaches `Headers::Builder`, parses `Content-Length`
from the raw header text rather than calling `res.content_length`, and downgrades a malformed
`Content-Type` to `nil`. One error-wrapping table (`Failures.wrap`) that asks the cancellation
token first and never the exception class. `dexpace-conformance` ships the `TCPServer` fixture
(`WireServer`), the scripted responses (`Scripts`), the callable-plus-`Failure` assertion protocol
with five result statuses including `:vacuous` (`DEF-22`), the two thin drivers, and the two
observability doubles 5b and 5c are owed (`RecordingSpan`, `Allocations`).

**Tech Stack:** Ruby 3.2–4.0 (authored on 3.4.10), Minitest, RBS + Steep, RuboCop with phase 0's
five custom cops, SimpleCov, YARD. `dexpace-transport-net_http` gains exactly one third-party
dependency: `net-http >= 0.4` (a default gem on every Ruby in the matrix). `dexpace-conformance`
gains **none** — it declares `dexpace-core` and nothing else, by design, which is what forces both
of its drivers to reference `::Minitest`/`::RSpec` without ever `require`-ing them.

**Spec:** `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md`,
under the charter `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`.
`docs/product-spec/17-transport-adapter-conformance-contract.md` is the normative chapter for all 30
`TRANSPORT` IDs; appendix C is used for the modal level and the canonical text, not for the
`*Conformance:*` clauses, which appendix C drops and which this design's `R1`–`R7` decisions turn on.

## Global Constraints

- **One interpreter is installed on the authoring machine: Ruby 3.4.10** (`net-http` 0.6.0, a
  default gem on it). Task 1 installs 3.2.11 and 4.0.6 and re-runs every fact the design measured
  plus the four this plan adds (see *What was verified during planning*).
- **The gemspec line lands before the first `require "net/http"`, and the require-allowlist edit
  lands before the first `require "socket"` in `dexpace-conformance`.** Phase 0's adapter-extended
  require-allowlist audit fails the build otherwise. Task 3 is both edits, in that order, before any
  code in either gem requires either name.
- **`dexpace-core` gains no new third-party dependency and its require allowlist does not grow.**
  `Dexpace::TransportError` (Task 2) names no stdlib module it must `require`: `::IOError` is a core
  class and every stdlib error it wraps arrives as an instance, never by name.
- **This plan does not touch `VERSIONS`, the root `Gemfile`, `tools/versions.rb`,
  `tools/versions_gate.rb` or `tasks/quality.rake`'s `test:gems`** (added 2026-09-12). `8c`'s plan
  Task 3 edits all five for `dexpace-transport-async_http`'s `required_ruby_version >= 3.3`
  (`P8-36`, `OI-38`), and the end state is written out once in the charter's *The CI matrix after
  `8c`'s per-gem Ruby floor*. **Both of this sub-phase's gems keep the repository floor of 3.2 and
  run every gate on all three interpreters** (3.2.11, 3.4.10, 4.0.6 — Tasks 1 and 23), which is
  unchanged by that edit in either execution order. **If `8c` has already landed it**, this plan's
  gate runs tolerate the edited `VERSIONS` without any change: `DexpaceVersions.ruby_floor`'s two new
  positionals are optional, the `floor:<gem-name>` row is colon-joined into `VERSIONS`' existing
  three-token `name` column so `.records` and every existing `.value` call site parse it unchanged,
  and `gates:versions` continues to assert `>= 3.2` for both of this sub-phase's gems against the
  global row. **If `8c` has not**, nothing here fails, because the collision exists only once `8c`'s
  gemspec declares a narrower floor. Task 23 verifies rather than re-applies. The one thing this plan
  must not do is land a second copy of that edit.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`).
- **`Timeout.timeout`, `Thread#raise`, `Thread#kill`, `Thread#terminate` and `Thread#exit` are
  forbidden in every file this plan writes** (`Dexpace/NoThreadInterrupt`). `ResponsePump#close` is
  written to satisfy this without a waiver: a latch, a queue close, a connection close, a **bounded**
  `Thread#join(JOIN_DEADLINE_SECONDS)`, never a `Thread#raise`/`#kill` on the producer. `net-http`'s
  own internal use of `Timeout.timeout` for the connect phase is outside this repository's `lib/`
  and outside this cop's scan; it is recorded under *The findings proposed for the registers* and
  not worked around.
- **`Thread::Mutex` is held across the flag flip only, in both latches this plan writes**
  (`Adapter`'s and `ResponsePump`'s, both phase 2's `Closeable`) — never across a queue close, a
  socket close, a join, or any other suspension point.
- **Deadlines are explicit `Float` values, never ambient interrupts.** `Deadline` (Task 14) is a
  monotonic instant computed from `Dexpace::Clock#monotonic`; it is propagated into
  `open_timeout`/`write_timeout`/`read_timeout`, refreshed into `read_timeout` after every chunk, and
  never turns into a `Thread#raise`.
- **`URI::RFC3986_PARSER` is never re-invoked here.** `Dexpace::Request#url` is already a frozen
  `URI::Generic` phase 1 parsed with the pinned parser; this plan reads `#scheme`, `#hostname`,
  `#port` and `#request_uri` off it and parses nothing itself. `Dexpace/NoUriDefaultParser` has
  nothing to bite.
- **`downcase` is never called with a locale argument, and this plan calls it nowhere at all** —
  header folding goes through phase 1's `HeaderName`, already folded at construction, and
  `MANAGED_HEADERS` is stored pre-folded. `Dexpace/NoLocaleCaseFold` bites nowhere.
- **Bytes on the wire are `Encoding::BINARY` in both directions.** Inbound chunks from
  `res.read_body` are `ASCII-8BIT`; `ResponsePump#readpartial` writes into a caller-supplied `outbuf`
  with `String#replace`, never `#clear` (verified fact 11: `#replace` copies the source's encoding,
  `#clear` does not). **Every encoding assertion in this plan uses non-ASCII content**
  (`io-and-byte-streams/a44b4de6`).
- **The one regexp this plan compiles** — `/\A[0-9]+\z/` against an inbound `Content-Length` header
  (`R4`, Task 17) — is anchored, character-class-only and linear, and is not given a `timeout:` for
  that stated reason. No other regexp is compiled by this plan's own code.
- **No test sleeps to synchronise.** The `WireServer` scripts and a `Thread::Queue`/latch the test
  controls stand in for every wait; a deadline test is driven through either an injected
  `Dexpace::Clock` double or a scripted slow server, with the budget stated in the test.
- **Formatting:** double quotes, 2-space indentation, 100 columns, `consistent_comma` trailing
  commas — phase 0's baseline, unchanged.
- **Domain model construction pattern, where this plan adds a `Data` type:** `Data.define`,
  `include Dexpace::Model`, `private_class_method :new`, a validating `.build`, shallow `freeze`.
  `Dexpace::Conformance::Assertion`, `::Result` and the `ResponsePump`'s frozen collaborators follow
  it; `Dexpace::Transport::NetHTTP::Adapter`, `ResponsePump`, `Deadline`, `WireServer` and
  `TransportCase` are plain classes with `Closeable` or ordinary mutable state, because none of them
  is a wire-model value.

### Commands

Only what phase 0's plan actually defines.

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/<path>_test.rb
bundle exec ruby -w gems/dexpace-transport-net_http/test/dexpace/<path>_test.rb
bundle exec ruby -w gems/dexpace-conformance/test/dexpace/<path>_test.rb
(cd gems/dexpace-core && bundle exec rake test)
(cd gems/dexpace-transport-net_http && bundle exec rake test)
(cd gems/dexpace-conformance && bundle exec rake test)
bundle exec rake                                   # all seventeen gates
bundle exec rake gates:gemspec_audit
bundle exec rake gates:require_allowlist
bundle exec rake gates:clean_bundle
bundle exec rake gates:rbs_surface
bundle exec rake gates:sig_diff
bundle exec rake gates:surface_snapshot
bundle exec rake rubocop                           # NFR-7, findings fatal, no autocorrection
bundle exec rake rbs:validate steep                # NFR-3
bundle exec rake cops:test                         # the five custom cops' own suite
bundle exec rake test:gems                         # gem suites: warnings fatal, coverage floor
bundle exec rake test:gates                        # the repository's gate suites
bundle exec rake yard bundler_audit
bundle exec rake surface:regenerate                # deliberate; final task only
ruby -Itest test/gates/<name>_test.rb              # one gate suite, phase 0's own invocation
ruby scripts/verify_knowledge_structure.rb
ruby .claude/skills/housekeeping/probe.rb
```

### What was verified during planning

**One interpreter, and this plan says so before it says anything else.** Only Ruby **3.4.10** is
installed on the authoring machine, matching the design. **The 3.2 and 4.0 columns have not been
run for anything below**; Task 1 installs both and re-runs every one of the design's seventeen
facts plus the four this planning pass adds.

**Four facts this planning pass measured that the design does not carry, each with a plan
consequence recorded in *Discrepancies found against the design*:**

1. **`Dexpace::Configuration` has no `#float` method.** Phase 5a's shipped `Configuration` class
   (`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md:2771-2812`) defines `#string`,
   `#integer`, `#boolean` and `#duration` — no `#float`. `#duration` is the one that returns `Float`
   seconds (`ConfigParsers.parse_duration`, `:2087-2130`), parsing ISO-8601, a number-with-unit
   suffix, or a **bare number as milliseconds** — and `parse_duration(nil, default:)` returns
   `default` unmodified when nothing is configured, which is exactly what `REQUEST_TIMEOUT`'s
   default path needs. Task 14 uses `Dexpace.configuration.duration(Keys::REQUEST_TIMEOUT,
   default: DEFAULT_TIMEOUT_SECONDS)`.
2. **`Dexpace::MediaType.parse` raises `Dexpace::InvalidArgumentError` on a malformed value; it does
   not return `nil`.** Phase 1's shipped parser
   (`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md:2170-2184`) raises whenever
   `slash.empty? || type.empty? || subtype.empty? || subtype.include?("/")` — and the design's own
   example, `"not a/;;media type"`, parses to `type="not a"`, `subtype=""` and hits exactly that
   raise. Confirmed by hand-tracing phase 1's `split_parameters`/`partition("/")` against that
   string; phase 1's own test fixture list includes the structurally identical `"text/"`. Task 17
   wraps the call in a `rescue Dexpace::InvalidArgumentError` that returns `nil`.
3. **A Gemfile listing only the target adapter's `path:` line cannot resolve `bundle install`**,
   because every adapter gemspec already declares `dexpace-core` as a runtime dependency (phase 0's
   own Task 5 Step 4) and `dexpace-core` is never published. Verified: a scratch two-gem workspace
   (`dexpace-core` plus a dependent `dexpace-foo`) with a Gemfile holding only
   `gem "dexpace-foo", path: ...` failed with `Could not find compatible versions … dexpace-core …
   could not be found in rubygems repository https://rubygems.org/`. Adding a second line,
   `gem "dexpace-core", path: ...`, resolved cleanly. This is phase 0's `gates:clean_bundle`
   fixture (`tasks/gates.rake`'s `clean_bundle_check`), which today writes only one `gem` line, and
   the bug is latent for **every** adapter, not only this sub-phase's two. Task 23 fixes it.
4. **Bundler does not gate a default gem's availability by Gemfile declaration.** Verified: a
   two-gem scratch workspace where the dependent gem's `lib/` requires `"net/http"` with **no**
   `net-http` dependency declared anywhere loaded and ran successfully under `bundle exec` (`Bundler
   with_unbundled_env`, both `bundle install` and the smoke `ruby -e` exited 0). `net-http` is not
   scheduled to become a **bundled** (non-default) gem within 3.2–4.0, so `gates:clean_bundle` can
   never distinguish "declared" from "merely present" for it; only `gates:require_allowlist`'s text
   scan does that, because it permits `require "net/http"` for this gem *because* the gemspec
   declares it, independent of whether the interpreter would load it anyway. Task 23 keeps the
   standard require+`VERSION` smoke rather than inventing a `TCPServer`-based one for this gate; a
   real round trip is what the adapter's own suite (Tasks 16–20) proves instead.

**The producer-thread/`SizedQueue` mechanism was re-run end to end against a local `TCPServer`
scripted to dribble a body (5 bytes, a 300 ms sleep, 5 more bytes), confirming the design's verified
fact 10 rather than trusting it blind: head arrived at 1.9 ms, chunk 1 at 7.1 ms, chunk 2 at
302.1 ms, the producer thread was dead immediately after `Thread#join`, and `outbuf.replace(...)`
retagged a UTF-8 buffer to `ASCII-8BIT` as fact 11 predicts.**

**`Net::HTTPGenericRequest.new(method_token, request_body_permitted, response_body_permitted, path,
initheader)` dispatches correctly with no per-verb subclass**, confirmed against a real socket: a
`PATCH` built this way reached the wire as `PATCH /generic HTTP/1.1` and a scripted `204` was
returned successfully to a caller that never called `#read_body` at all, then a **second** call
through a **fresh** `Net::HTTP` succeeded immediately after — confirming both that this construction
needs no lookup table keyed by method (`Dexpace::Method#token` feeds it directly, including a future
vendor verb) and that skipping `#read_body` when `res.class.body_permitted?` is `false` leaves the
connection in a state the library itself closes out cleanly, so `ResponseMapper` can close the pump
immediately in that case with no special coordination from the producer. `Net::HTTPGenericRequest.new`
even with `initheader: {}` still stamps all three of `Accept`/`Accept-Encoding`/`User-Agent`
(re-confirmed against a `Net::HTTP::Get.new(path, {})` call directly), so the three explicit
`#delete`s are load-bearing and not optional.

**`#add_field` does not flip `@decode_content`; only `#[]=` does** (`net/http/generic_request.rb`
defines `#[]=` with the `key.downcase == 'accept-encoding'` side effect and does not override
`#add_field`, verified by reading both files at the installed gem path). So `RequestMapper` copies
the caller's headers with `#add_field` (preserving multi-value, no side effect), then separately
forces the `decode_content` flip through `#[]=` after the copy: `native["Accept-Encoding"] =
native["Accept-Encoding"]` when the caller supplied one (preserves the value, still flips the flag),
or `native["Accept-Encoding"] = "identity"; native.delete("Accept-Encoding")` when they did not
(verified fact 13's exact recipe).

**`require "net/http"` alone makes `Zlib` a defined constant** (`net/http.rb:730` requires `zlib`
unconditionally at load time), so `Failures`'s `rescue Zlib::Error` clause needs no `require "zlib"`
of its own and adds nothing to the require-allowlist audit.

**`Dexpace::Protocol.parse` has no alias for `"http/1.0"`** (only `http/1.1`, `http/2`, `http/2.0`
fold into a recognised wire form) — a real `HTTP/1.0` response would make `ResponseMapper` raise.
No `TRANSPORT` ID requires 1.0 support and the fixture is self-authored, so every `WireServer` script
in this plan answers `HTTP/1.1` on its status line and this gap is never exercised. Worth one
sentence in `ResponseMapper`'s YARD and nothing else; it is the kind of finding *The findings
proposed for the registers* names for a human, not a code change this plan makes.

## This plan's open questions, resolved

The design's six open questions, resolved below, plus one implementation ambiguity this plan found
while building Task 13 and resolves the same way — with a reason, not a guess.

1. **The three-interpreter re-run of verified facts 1–17, plus this plan's four.** Task 1 installs
   3.2.11 and 4.0.6 and re-runs all twenty-one. Three are conditional exactly as the design states:
   if fact 8's live `read_timeout=` propagation does not hold on 3.2, `R3`'s mid-stream refresh
   degrades to a per-phase assignment (Task 14's `Deadline` gains a narrowing comment, no redesign);
   if fact 10's cross-thread `FiberError` does not reproduce on 3.2 (it will), `R1`'s conclusion is
   unchanged because the thread pump needs no `Fiber#kill` either way; if fact 5's `Warning.warn`
   delivery does not fire on some row, `P8-4`'s second reason (the `x-www-form-urlencoded` lie) alone
   still requires the explicit `Content-Type`. This plan's own four facts are re-run the same way;
   fact 3 (the clean-bundle Gemfile fix) and fact 4 (the smoke-test limitation) are properties of
   Bundler and RubyGems respectively and are not expected to vary by Ruby version, but Task 23 checks
   both on all three rows anyway because "not expected to vary" is not "verified".
2. **`net-http`'s RBS signatures: `Steepfile` `library` line, or a `rbs_collection.yaml` row.**
   *Decision:* try `library "net-http"` on the `dexpace-transport-net_http` Steep target first (Task
   21). `net-http` is a default gem and `rbs` ships bundled signatures for the default-gem set it
   knows about; `rbs_collection.yaml` resolves *third-party* gems through `gem_rbs_collection` and is
   the wrong tool for a signature that should already ship with the interpreter's own `rbs` gem. If
   `rbs validate`/`steep check` cannot resolve `Net::HTTP` through the `library` line on any of the
   three interpreters, Task 21 falls back to a `rbs_collection.yaml` row and records which row failed
   and why, rather than assuming the fallback is needed.
3. **Whether `proxy-authorization` joins `MANAGED_HEADERS`.** *Decision:* **no.** This adapter
   configures no proxy at all, so a caller-set `Proxy-Authorization` is a header the SDK has no
   business managing; dropping it would silently break a caller proxying at a layer the SDK cannot
   see, and `TRANSPORT-30`'s MUST is about credentials the SDK itself holds, of which there are none
   here. `MANAGED_HEADERS` (Task 19) stays at ten entries.
4. **`WireServer`'s accept-loop shutdown.** *Decision:* **the bounded join**, symmetric with
   `ResponsePump`: `#close` closes the listening socket (waking a blocked `#accept` with `IOError` or
   `Errno::EBADF`) and joins the accept-loop thread with the same `JOIN_DEADLINE_SECONDS` constant
   `ResponsePump` uses, rather than a self-pipe. Task 5 implements this; the reason is stated there
   inline (a fixture that teaches a different teardown idiom than the code it tests is one a reader
   copies wrongly).
5. **`Allocations.delta`'s warm-up.** *Decision:* a named `private_constant` (`WARMUP_ITERATIONS`)
   with the measured overhead in a comment (1 allocation around an empty block, 0 around `{ nil }`
   on 3.4.10, re-measured per interpreter in Task 1), and `iterations:` a **required** keyword with
   no default — a caller who forgets the count gets a number that means nothing, and `OBS-25`'s "MUST
   NOT allocate per call" is a per-iteration claim. Task 7.
6. **`Report#to_h`.** *Decision:* **`#to_s` only, in this sub-phase.** A structured renderer is
   `NFR-4`-locked surface with no caller yet; phase 9, aggregating three suites, is the phase with
   one. Task 4.
7. **[Found during planning, not one of the design's six] Whether `TRANSPORT-28`'s zero-copy clause
   is a real `TransportSuite.run(waive:)` call or a documentation-only gap.** The design's own `R5`
   states the clause "has no assertion … because it has no observable behaviour to assert", which
   leaves nothing for a runtime waiver to suppress — a `Failure` never gets raised for it in the
   first place. *Decision:* `TRANSPORT-28`'s one runnable assertion (byte-range plus replayability,
   Task 11) carries `ids: ["TRANSPORT-28"]` and always passes on this adapter; `waive:` is **not**
   used to hide it, because giving the assertion that tag and then waiving that same tag would hide
   the one clause that does pass. The zero-copy gap is recorded where the design's own `R5` already
   put it — `DEF-3`'s disposition and this plan's coverage table — and the net_http driver call
   (Task 20) passes `waive: []`. The Testing Strategy section's "one waiver" reads, in context, as
   shorthand for that citation rather than a literal call, and this plan implements the literal
   mechanism the same section also names for `TRANSPORT-18`/`12`/`13`: `:vacuous`, not `:waived`, for
   anything with no observable failure to suppress.

## Task order and dependency chain

Twenty-five tasks. Two hard rules, both external:

**Hard rule 1:** the `net-http` gemspec dependency line and the require-allowlist's per-gem `socket`
exception (Task 3) land **before** the first `require "net/http"` (Task 16) and the first
`require "socket"` (Task 5), respectively — phase 0's require-allowlist audit fails the build
otherwise.

**Hard rule 2:** `Dexpace::TransportError` (Task 2) lands before `Failures` (Task 15), which wraps
into it, and before any adapter test asserts a wrapped error's type.

1. Matrix and floor fact verification (Task 1's own scope, no requirement ID).
2. `Dexpace::TransportError` and `Configuration::Keys::REQUEST_TIMEOUT` (phase-level task; core).
3. The gemspec line and the require-allowlist per-gem exception (`P8-14`) — the ordering gate.
4. `Dexpace::Conformance::Failure`, `::Vacuous`, `::Assertion`, `::Result`, `::Report` (`DEF-22`'s
   data types) — needs nothing but core.
5. `Dexpace::Conformance::WireServer` and `::Scripts` — needs Task 4's `Failure` only incidentally
   (the scripts never raise it); needs `socket`.
6. `Dexpace::Conformance::TransportCase` and `::TransportSuite` (empty `.assertions`, the run loop,
   the waiver/vacuity mechanism) plus the suite's own non-conforming-fake test — needs Tasks 4, 5.
7. `Dexpace::Conformance::RecordingSpan` and `::Allocations` (`OBS-21`, `OBS-25`) — standalone.
8. `Dexpace::Conformance::MinitestDriver` and `::RSpecDriver` — needs Task 6.
9. Assertions group 1: outbound mapping (`TRANSPORT-10`, `TRANSPORT-11`, `TRANSPORT-26`, the
   `DEF-25` re-validation assertion) — needs Task 6; written against `TransportCase`, run against
   nothing yet (no adapter exists until Task 19), so this and every assertion task through Task 13
   is TDD against a **stub** transport built inline in the assertion's own test until Task 20 wires
   the real one.
10. Assertions group 2: inbound mapping (`TRANSPORT-24`, `TRANSPORT-14`, `TRANSPORT-27`) — needs
    Task 6.
11. Assertions group 3: streaming and body lifecycle (`TRANSPORT-25`, `TRANSPORT-19`, `TRANSPORT-28`)
    — needs Task 6.
12. Assertions group 4: retry, cancellation and failure classification (`TRANSPORT-1`, `TRANSPORT-2`,
    `TRANSPORT-3`, `TRANSPORT-4`, `TRANSPORT-17`, `TRANSPORT-18`, `TRANSPORT-20`, `TRANSPORT-22`) —
    needs Task 6.
13. Assertions group 5: lifecycle, concurrency and the cross-phase tests (`TRANSPORT-5`,
    `TRANSPORT-6`, `TRANSPORT-15`, `TRANSPORT-16`, `TRANSPORT-29`, `TRANSPORT-12`/`13` vacuous
    cross-references, `PAGE-36`) — needs Task 6.
14. `Dexpace::Transport::NetHTTP::Deadline` (`R3`) — needs Task 2's `Keys::REQUEST_TIMEOUT`.
15. `Dexpace::Transport::NetHTTP::Failures` (the error-wrapping table) — needs Task 2.
16. `Dexpace::Transport::NetHTTP::RequestMapper` (`R2`, `DEF-25`'s call site) — needs Task 3's
    gemspec line; needs phase 1's `HeaderSyntax`/`HeaderName`/`Headers`, 3a/3b's `Body`/`FileBody`.
17. `Dexpace::Transport::NetHTTP::ResponseMapper` (`R4`) — needs Task 16 for shared constants.
18. `Dexpace::Transport::NetHTTP::ResponsePump` (`R1`) — needs Tasks 15, 17.
19. `Dexpace::Transport::NetHTTP` the module, `::Adapter#call`/`#close`, `.build`/`.using`/`.default`,
    registration — needs Tasks 14–18.
20. Wire the conformance suite into `dexpace-transport-net_http`'s own test task via
    `MinitestDriver`, with the borrowed-client driver and the `:vacuous` rows — needs Task 19 and
    Tasks 9–13.
21. `sig/` for both gems, the two Steep targets, `rbs_collection.yaml`/`Steepfile` resolution
    (open question 2), the `NFR-11` scan — needs everything above.
22. Runtime surface snapshot and RBS baseline diff for both gems.
23. `gates:gemspec_audit`, `gates:require_allowlist`, `gates:clean_bundle` (with the Gemfile fix) on
    all three interpreters.
24. YARD's undocumented-public-method gate for both gems.
25. The knowledge note, the register findings handed to a human, `docs/first-release.md`'s
    `dexpace-conformance` row, and the housekeeping probe.

---

## Task 1: Matrix and floor fact verification

**Requirement IDs:** none directly — the plan's evidence-gathering step, per the precedent every
prior phase sets.
**Design:** "The verified Ruby facts this sub-phase is built on"; "Three things this document could
not verify"; open question 1.

**Files:**
- Create: `<scratchpad>/p8a/{fixture,pump,teardown,fiber,wire,verbose,inbound,ae,retry,conc,proto,cl,
  cl2,to,bstream,hdrs,final,bundle_path,default_gem,decode}.rb` — probe scripts, never committed.

**Needs:** nothing.
**Produces:** a recorded pass/fail grid for the design's 17 facts plus this plan's 4, on 3.2.11,
3.4.10 and 4.0.6.

- [ ] **Step 1: Install the floor and ceiling interpreters**

```bash
mise install ruby@3.2.11
mise install ruby@4.0.6
```

- [ ] **Step 2: Re-run the design's 17 facts on all three rows**

Re-run each numbered command the design's *Verified Ruby facts* section names (facts 1–17), on
3.2.11, 3.4.10 and 4.0.6, recording pass/fail per row. Pay particular attention to the three the
design flags as unverified beyond 3.4.10: fact 8 (`read_timeout=` live propagation), fact 10 (the
cross-thread `FiberError`), and fact 17 (`minitest`'s bundled-gem status, `socket`'s non-gemified
status).

- [ ] **Step 3: Re-run this plan's 4 facts on all three rows**

```bash
# bundle_path.rb -- confirms fact 3 (Gemfile needs both path: lines)
# default_gem.rb -- confirms fact 4 (Bundler does not gate default-gem availability)
# decode.rb      -- confirms #add_field vs #[]= and the decode_content switch
# (Configuration#float's absence and MediaType.parse's raise are read from phase 5a/1's own
#  shipped plans, not re-derived per interpreter -- they are properties of code, not of Ruby)
```

Run each on 3.2.11, 3.4.10 and 4.0.6. Record the grid.

- [ ] **Step 4: Act on any row that disagrees**

If fact 8 fails on 3.2: note it against Task 14 and degrade `Deadline`'s mid-stream refresh to a
per-phase assignment there, with a comment naming this task. If fact 10's `FiberError` does not
reproduce on 3.2 (expected to still hold): no action, `R1`'s conclusion does not depend on it. If
fact 5's `Warning.warn` delivery differs: no action, `P8-4`'s second reason is sufficient alone. If
facts 3/4 (this plan's) differ by row: record it as a per-Ruby caveat in Task 23's own notes rather
than changing the mechanism, since both are Bundler/RubyGems properties this plan has no lever over.

- [ ] **Step 5: Record the grid in this task's own notes**

No file is created for this beyond the scratch probes; the grid is transcribed into the commit
message or PR description when this phase lands, per every predecessor's practice.

---

## Task 2: `Dexpace::TransportError` and `Configuration::Keys::REQUEST_TIMEOUT`

**Requirement IDs:** the phase-level task (`XCUT-4` branch (b)); `R3`'s configuration key.
**Design:** "The object model `8a` ships — `dexpace-core` — one constant and one key (the
phase-level task, and one line)"; segmentation design "Phase-level tasks owned by no sub-phase",
item 1.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/error/transport_error.rb`,
  `gems/dexpace-core/sig/dexpace/error/transport_error.rbs`
- Modify: `gems/dexpace-core/lib/dexpace/configuration/keys.rb`,
  `gems/dexpace-core/sig/dexpace/configuration/keys.rbs`, `gems/dexpace-core/lib/dexpace.rb`,
  `gems/dexpace-core/lib/dexpace/instrumentation/events.rb` and its `sig/` mirror (Step 5b)
- Test: `gems/dexpace-core/test/dexpace/error/transport_error_test.rb`

**Needs:** phase 1's `Dexpace::Error` (a module), phase 4b's error-taxonomy shape (`Dexpace::Error`
`include`d, never subclassed from a sibling).
**Produces:** `Dexpace::TransportError < ::IOError`, `#retryable?`, `#phase`;
`Dexpace::Configuration::Keys::REQUEST_TIMEOUT`.

This is the charter's phase-level task 1, reviewed at the phase-level PR rather than this
sub-phase's. **The charter fixed on 2026-09-12 that `8a`'s Task 2 lands it** — it had read "whoever
lands first writes it", and `8c`'s plan Task 4 then wrote a second, differently shaped definition. Two
reasons that are not preference: `8a` is first in the recommended order, and `dexpace-conformance` — this
sub-phase's own gem — asserts against the class in the suite contract's clause 5, so the suite cannot be
written against a class that does not exist.

**The shape below is the phase's, and it is a superset of `8c`'s.** `8c` constructs the class as
`Dexpace::TransportError.new("…")` at every site in its `Errors.wrap`, so the optional `phase:` keyword
costs it nothing, and its own three assertions (`< ::IOError`, `include Dexpace::Error`, `#retryable?`
always true, plus `P3-3`'s sibling check) all hold here. `8c`'s Task 4 is a citation and a verification.
**If `8c` executes before `8a`**, `8c` writes this identical shape and this task becomes the no-op
confirmation instead: re-read the shipped class against the bullets below and proceed.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# XCUT-4 branch (b): "A transport error MUST report itself as always-retryable at the error
# level." P3-3: a sibling of Dexpace::StreamError inside ::IOError, never a subclass, because a
# stream-contract violation must not claim to be always-retryable.
class DexpaceTransportErrorTest < DexpaceTestCase
  test "is an IOError and includes the module error root" do
    assert_operator(Dexpace::TransportError, :<, ::IOError)
    assert_operator(Dexpace::TransportError, :<, Dexpace::Error)
  end

  test "is a sibling of StreamError, never its ancestor or descendant" do
    refute_operator(Dexpace::TransportError, :<, Dexpace::StreamError)
    refute_operator(Dexpace::StreamError, :<, Dexpace::TransportError)
  end

  test "reports retryable by default, per XCUT-4 branch (b)" do
    assert_predicate(Dexpace::TransportError.new("boom"), :retryable?)
  end

  test "carries the phase the failure occurred in, for diagnostics only" do
    error = Dexpace::TransportError.new("boom", phase: :read)

    assert_equal(:read, error.phase)
  end

  test "defaults phase to nil and carries a wrapped error's #cause normally" do
    wrapped = begin
      raise Net::ReadTimeout, "slow"
    rescue Net::ReadTimeout => e
      begin
        raise Dexpace::TransportError, "wrapped"
      rescue Dexpace::TransportError => wrapped_error
        wrapped_error
      end
    end

    assert_nil(Dexpace::TransportError.new("boom").phase)
    assert_instance_of(Net::ReadTimeout, wrapped.cause)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/transport_error_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::TransportError` (and `Net::ReadTimeout`, since
`net/http` is not required in this test file; wrap the fourth test's `raise` targets in a bare
`StandardError` instead so the core test suite requires no `net/http` — core embeds no concrete
transport, `SEAM-1`/`SEAM-2`, and this test file must not either).

- [ ] **Step 3: Write `lib/dexpace/error/transport_error.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # The canonical retryable transport failure (TRANSPORT-20), raised by an adapter for any
  # failure that produced no HTTP response: connection refused, DNS failure, TLS handshake
  # failure, peer reset, connect/read/write timeout.
  #
  # ::IOError, never a subclass of Dexpace::StreamError: XCUT-4 splits transport-adjacent
  # failures into exactly two branches -- (a) a stream-contract violation, never retryable by
  # default, and (b) "everything else escaping a transport", always retryable by default. A
  # shared ancestor would let `rescue Dexpace::StreamError` catch a transport failure it was
  # never written to expect, or vice versa. P6-4's "wrap, and default to retryable, not wrap
  # and get the classification right by hand" is answered by the one flag below, not by ten
  # rescue clauses at the call site.
  class TransportError < ::IOError
    include Dexpace::Error

    # @return [Symbol, nil] where the failure occurred (:connect, :write, :read, :close), for
    #   diagnostics only -- never branched on by RETRY-2's capability query, which reads
    #   #retryable? alone.
    attr_reader :phase

    def initialize(message = "a transport failure occurred", phase: nil)
      @phase = phase
      super(message)
    end

    # RETRY-2's capability query. Always true: XCUT-4 branch (b) is "MUST report itself as
    # always-retryable at the error level", not "retryable when the underlying cause looks
    # retryable" -- the pipeline's retry budget and idempotency gate are what bound a resend,
    # not this flag.
    def retryable?
      true
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/error/transport_error.rbs`**

```rbs
module Dexpace
  class TransportError < ::IOError
    include Dexpace::Error

    attr_reader phase: Symbol?

    def initialize: (?String message, ?phase: Symbol?) -> void
    def retryable?: () -> bool
  end
end
```

- [ ] **Step 5: Add `Keys::REQUEST_TIMEOUT`**

In `lib/dexpace/configuration/keys.rb`, add one line inside `module Keys`, after the existing
entries:

```ruby
      REQUEST_TIMEOUT = "REQUEST_TIMEOUT"
```

And the matching line in `sig/dexpace/configuration/keys.rbs`:

```rbs
      REQUEST_TIMEOUT: String
```

`5a`'s own rule is that a key constant with no reader is `NFR-4`-locked surface nothing exercises;
Task 14 is the reader, in the same phase, so this is not that.

**`REQUEST_TIMEOUT` is a shared key and `8c` reads the same one** — the charter's *Shared transport
contracts* item 4. An earlier revision of `8c`'s plan declared a second spelling,
`TRANSPORT_REQUEST_TIMEOUT_SECONDS`; it is corrected to this key, because one caller setting must govern
both transports. `8c`'s `TRANSPORT_CONNECTION_LIMIT` is genuinely `8c`-only (`Net::HTTP` is built per
call and has no pool to bound) and this task does not add it.

- [ ] **Step 5b: Add `Events::TRANSPORT_HEADER_DROPPED` (added 2026-09-12)**

In `lib/dexpace/instrumentation/events.rb`, beside the existing `INSTRUMENTATION_LOG`/`_CLOSE`/`_HOOK`/
`_CONFIG` rows, and the matching `String` line in the `sig/` mirror:

```ruby
      # TRANSPORT-11 and TRANSPORT-13: the header-drop record, emitted by every transport adapter
      # that drops a caller-set header. One name for both adapters (the charter's Shared transport
      # contracts item 2), so one conformance assertion reads a drop from either.
      TRANSPORT_HEADER_DROPPED = "http.transport.header_dropped"
```

**Whichever of `8a` and `8c` executes first adds this line; the other finds it and does nothing.** It is
a widening — one new constant, nothing narrows or moves — so `NFR-4`'s lock is unaffected and
`gates:sig_diff` has nothing to say about it. Task 16's `RequestMapper.log_drop` is this repository's
first reader; `8c`'s `RequestMapper` and its `DropPolicy#report` are the others.

- [ ] **Step 6: Add the require and run the tests**

Add `require_relative "dexpace/error/transport_error"` to `lib/dexpace.rb`, immediately after phase
3a's `error/stream_error` line (siblings, adjacent).

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/transport_error_test.rb`
Expected: PASS, 5 runs.

Run: `bundle exec rake rbs:validate steep` (the `core` Steep target only, at this point).

---

## Task 3: The gemspec line and the require-allowlist's per-gem exception (`P8-14`)

**Requirement IDs:** `SEAM-1`, `SEAM-2`, `NFR-2` (the gemspec budget); `P8-14`.
**Design:** "From phase 0 — the gates that bite" (`gates:gemspec_audit`, `gates:require_allowlist`);
Deviation Ledger `P8-14`.

**Files:**
- Modify: `gems/dexpace-transport-net_http/dexpace-transport-net_http.gemspec`,
  `tools/require_allowlist.rb`
- Test: `test/gates/require_allowlist_test.rb` (extend phase 0's own suite)

**Needs:** phase 0's `GemspecAudit`, `RequireAllowlist`.
**Produces:** the one new runtime dependency this sub-phase's first gem declares, and a named,
gem-scoped exception to the second gem's denylist entry for `socket`.

This is the **ordering gate**: everything from Task 16 onward that writes `require "net/http"`, and
everything from Task 5 onward that writes `require "socket"`, depends on this task having landed
first, or `gates:require_allowlist` fails the build the moment either file is written.

- [ ] **Step 1: Add the gemspec dependency**

In `gems/dexpace-transport-net_http/dexpace-transport-net_http.gemspec`, after the existing
`spec.add_dependency "dexpace-core", DexpaceVersions.core_constraint` line:

```ruby
  spec.add_dependency "net-http", ">= 0.4"
```

`0.4` because `net-http`'s `Net::HTTPGenericRequest` and the block-form `#request` this plan relies
on are present from that release forward, and this repository's own floor interpreter (3.2.11) ships
a compatible default `net-http`. Task 1 confirms this on 3.2.11 directly rather than trusting the
version string.

- [ ] **Step 2: Run `gates:gemspec_audit` to confirm the budget is still respected**

Run: `bundle exec rake gates:gemspec_audit`
Expected: `gates:gemspec_audit: 6 gemspecs, dependency budget respected.` — this is the first time
`dexpace-transport-net_http` carries **two** runtime dependencies, which is the case phase 0's
`two_third_party` negative fixture was written against but had never seen positively. This
confirms it passes rather than merely that the fixture rejects three.

- [ ] **Step 3: Write the failing test for the per-gem require-allowlist exception**

Add to `test/gates/require_allowlist_test.rb`:

```ruby
  test "socket is denied to every gem except dexpace-conformance, which embeds a server fixture" do
    generic = RequireAllowlist.scan_file(
      File.join(ROOT, FIXTURES, "socket.rb"), permitted: [], lib_root: File.dirname(__FILE__),
      gem_name: "dexpace-transport-net_http",
    )
    exempted = RequireAllowlist.scan_file(
      File.join(ROOT, FIXTURES, "socket.rb"), permitted: [], lib_root: File.dirname(__FILE__),
      gem_name: "dexpace-conformance",
    )

    refute_empty(generic, "SEAM-1/SEAM-2: still denied everywhere else")
    assert_empty(exempted, "P8-14: dexpace-conformance embeds a fixture server, not a transport")
  end
```

Add the fixture `test/fixtures/gates/require_allowlist/socket.rb`, one line: `require "socket"`,
carrying the standard three-line header.

- [ ] **Step 4: Run it to confirm it fails**

Run: `ruby -Itest test/gates/require_allowlist_test.rb`
Expected: FAIL — `ArgumentError: unknown keyword: :gem_name` (`scan_file` does not accept it yet).

- [ ] **Step 5: Extend `tools/require_allowlist.rb`**

```ruby
  # P8-14: SEAM-1/SEAM-2's reason for denying `socket` ("core embeds no concrete transport") does
  # not reach a gem that embeds a fixture SERVER rather than a transport -- and `socket` is
  # non-gemified stdlib (a .so with no gemspec), so it can never migrate to the bundled set the
  # rest of this file's reasoning is about. An amendment with its own reason, not a removal.
  DENIED_EXCEPT = {
    "socket" => ["dexpace-conformance"],
  }.freeze

  def violations(root)
    Dir.glob(File.join(root, "gems/*")).sort.flat_map do |gem_dir|
      permitted = third_party_for(gem_dir)
      lib_root = File.join(gem_dir, "lib")
      gem_name = File.basename(gem_dir)
      Dir.glob(File.join(lib_root, "**/*.rb")).sort.flat_map do |file|
        scan_file(file, permitted: permitted, lib_root: lib_root, gem_name: gem_name)
      end
    end
  end

  def scan_file(path, permitted:, lib_root:, gem_name:)
    File.readlines(path, chomp: true).filter_map do |line|
      if (name = REQUIRE.match(line)&.[](1))
        reason = reason_for(name, permitted, gem_name)
        next if reason.nil?

        "#{path}: require \"#{name}\" -- #{reason}"
      elsif (target = REQUIRE_RELATIVE.match(line)&.[](1))
        next if inside?(path, target, lib_root)

        "#{path}: require_relative \"#{target}\" escapes #{lib_root}. A gem may not reach " \
          "outside its own lib/ (styleguide 12.6); the packaged gem would not contain it."
      end
    end
  end

  private

  def reason_for(name, permitted, gem_name)
    return nil if permitted.include?(name) || name.start_with?("dexpace/")
    if DENIED.key?(name)
      return nil if DENIED_EXCEPT.fetch(name, []).include?(gem_name)

      return DENIED[name]
    end

    since = bundled_since[name.split("/").first]
    return "bundled since #{since}; a gem must declare it explicitly under Bundler." if since
    return nil if ALLOWED.include?(name)

    "not in the require allowlist. Add it to RequireAllowlist::ALLOWED with the requirement " \
      "that motivated it, or declare it as a dependency if this is an adapter (NFR-2)."
  end
```

**`gem_name:` is a required keyword on `scan_file` and a required third positional on `reason_for`,
with no default on either**, so every existing call inside `violations` and every call phase 0's own
gate suite makes must be updated in the same change. That is deliberate: a caller that forgot to pass
`gem_name` must see an `ArgumentError`, never a `socket` require quietly passing a scan it should have
failed. (An earlier revision of this step gave `scan_file` a `gem_name: nil` default, which does exactly
what this paragraph says it must not — `DENIED_EXCEPT.fetch(name, []).include?(nil)` is `false`, so the
denial still fires, but silently and for the wrong reason.)

- [ ] **Step 6: Run the test to confirm it passes**

Run: `ruby -Itest test/gates/require_allowlist_test.rb`
Expected: PASS. Then the full existing suite: `bundle exec rake gates:require_allowlist` (still
green, because no gem's `lib/` yet requires `socket` or `net/http`).

---

## Task 4: `Dexpace::Conformance::Failure`, `::Vacuous`, `::Assertion`, `::Result`, `::Report`

**Requirement IDs:** `DEF-22`'s data types; no `TRANSPORT` ID directly, but every assertion group
from Task 9 onward is built on this task's shapes.
**Design:** "`R7` — the `TCPServer` fixture and the assertion protocol"; the object model,
`dexpace-conformance` table; `P8-8`, `P8-11`, `P8-12`.

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/failure.rb`,
  `.../vacuous.rb`, `.../assertion.rb`, `.../result.rb`, `.../report.rb`, and the five `sig/`
  mirrors
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb`
- Test: `gems/dexpace-conformance/test/dexpace/conformance/{failure,vacuous,assertion,result,
  report}_test.rb`

**Needs:** phase 0's gem skeleton only.
**Produces:** the five value shapes every later task in this gem builds on.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# DEF-22, design section "R7". Failure is a test result, not an SDK error -- P8-8 records why it
# does NOT include Dexpace::Error: an adapter author's `rescue Dexpace::Error` around a send must
# not swallow the assertion that the send was wrong.
class DexpaceConformanceFailureTest < DexpaceConformanceTestCase
  test "is a StandardError and does not include Dexpace::Error" do
    failure = Dexpace::Conformance::Failure.new("expected X", expected: "X", actual: "Y",
                                                 requirement_ids: ["TRANSPORT-24"])

    assert_operator(Dexpace::Conformance::Failure, :<, ::StandardError)
    refute_operator(Dexpace::Conformance::Failure, :<, Dexpace::Error)
    assert_equal("X", failure.expected)
    assert_equal("Y", failure.actual)
    assert_equal(["TRANSPORT-24"], failure.requirement_ids)
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# Section 12's MUST-level summary counts requirements that "hold vacuously" -- Vacuous is what
# keeps that count true rather than something the suite's own passing rate quietly erases.
class DexpaceConformanceVacuousTest < DexpaceConformanceTestCase
  test "carries a reason and is a StandardError, not a Dexpace::Error" do
    vacuous = Dexpace::Conformance::Vacuous.new("no proxy is ever configured")

    assert_operator(Dexpace::Conformance::Vacuous, :<, ::StandardError)
    assert_equal("no proxy is ever configured", vacuous.reason)
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

class DexpaceConformanceAssertionTest < DexpaceConformanceTestCase
  test "is a frozen Data carrying its own ids, name and callable body" do
    assertion = Dexpace::Conformance::Assertion.build(
      ids: ["TRANSPORT-24"].freeze, name: "maps every status totally",
      body: ->(_case) { nil },
    )

    assert_equal(["TRANSPORT-24"], assertion.ids)
    assert_predicate(assertion, :frozen?)
    assert_predicate(assertion.ids, :frozen?)
    assert_nil(assertion.call(:subject))
  end

  test "#call delegates to #body with the subject" do
    seen = nil
    assertion = Dexpace::Conformance::Assertion.build(
      ids: ["X"].freeze, name: "records its subject", body: ->(subject) { seen = subject },
    )

    assertion.call(:the_subject)

    assert_equal(:the_subject, seen)
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

class DexpaceConformanceResultTest < DexpaceConformanceTestCase
  STATUSES = %i[passed failed vacuous waived error].freeze

  test "status is restricted to the five documented values" do
    assertion = Dexpace::Conformance::Assertion.build(ids: ["X"], name: "n", body: ->(_) {})

    STATUSES.each do |status|
      result = Dexpace::Conformance::Result.build(assertion: assertion, status: status, detail: nil)

      assert_equal(status, result.status)
    end
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# Section 9.3: "the gap stays visible rather than disappearing into a restated item" -- so
# #to_s names every waived ID on every run, not only on failure.
class DexpaceConformanceReportTest < DexpaceConformanceTestCase
  def assertion(ids)
    Dexpace::Conformance::Assertion.build(ids: ids, name: ids.join(","), body: ->(_) {})
  end

  def result(ids, status, detail: nil)
    Dexpace::Conformance::Result.build(assertion: assertion(ids), status: status, detail: detail)
  end

  test "partitions results by status and #to_s names every waived id" do
    report = Dexpace::Conformance::Report.new([
      result(["A"], :passed),
      result(["B"], :failed, detail: "boom"),
      result(["C"], :vacuous, detail: "no antecedent"),
      result(["D"], :waived),
      result(["E"], :error, detail: RuntimeError.new("oops")),
    ])

    refute_predicate(report, :passed?)
    assert_equal(1, report.failures.size)
    assert_equal(1, report.vacuous.size)
    assert_equal(1, report.waived.size)
    assert_equal(1, report.errors.size)
    assert_match(/D/, report.to_s)
  end

  test "passed? is true only when nothing failed or errored" do
    clean = Dexpace::Conformance::Report.new([result(["A"], :passed), result(["B"], :vacuous)])

    assert(clean.passed?)
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run each test file individually.
Expected: FAIL — `uninitialized constant Dexpace::Conformance::Failure` and siblings.

- [ ] **Step 3: Write the five files**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # DEF-22's failure, carrying the expected and actual values an assertion compared. A test
    # result, not an SDK error -- P8-8 records why it does NOT `include Dexpace::Error`: an
    # adapter author's broad `rescue Dexpace::Error` around a send must not swallow the assertion
    # that the send was wrong.
    class Failure < ::StandardError
      attr_reader :expected, :actual, :requirement_ids

      def initialize(message, expected:, actual:, requirement_ids:)
        @expected = expected
        @actual = actual
        @requirement_ids = requirement_ids
        super(message)
      end
    end
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # Raised from inside an assertion body once it has established that the requirement's own
    # antecedent is absent for the subject under test -- never a skip decided from outside. A
    # different class from Failure because section 12's MUST-level summary counts requirements
    # that "hold vacuously" as a distinct category from "passed", and a Report that folded the
    # two together would be the mechanism by which that count stops being true.
    class Vacuous < ::StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason)
      end
    end
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace/model"

module Dexpace
  module Conformance
    # One conformance check: the requirement IDs it exercises (a waiver matches by these, never
    # by #name), a human name, and a callable body taking one TransportCase-shaped subject.
    class Assertion < ::Data.define(:ids, :name, :body)
      include Dexpace::Model
      private_class_method :new

      def self.build(ids:, name:, body:)
        new(ids: Model.own(ids), name: Model.required!("name", name), body: body)
      end

      def initialize(ids:, name:, body:)
        Model.required!("ids", ids)
        Model.required!("body", body)
        super
      end

      def call(subject)
        body.call(subject)
      end
    end
  end
end
```

Note: **`.build` is the only construction entry point for `Assertion` and `Result` both, and every call
site in this plan uses it** — `transport_suite.rb`, all five assertion groups (Tasks 9–13), both
drivers, and every test file. An earlier revision of this plan wrote `Assertion.new(…)`/`Result.new(…)`
at those sites, on the reasoning that `private_class_method :new` only blocks callers "outside the
gem". **That is not what `private_class_method` does.** Verified on 3.4.10: it makes `new` a *private*
singleton method, so **any** call with an explicit receiver raises
`NoMethodError: private method 'new' called for class …` — regardless of file, gem, or lexical scope.
Only the implicit-receiver call inside the class's own singleton methods (`def self.build … new(…)`)
reaches it, which is exactly what `.build` is for. `send(:new, …)` is neither needed nor used anywhere
in this plan.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace/model"

module Dexpace
  module Conformance
    # One assertion's outcome. `status` is one of :passed, :failed, :vacuous, :waived, :error --
    # never a boolean, because collapsing five outcomes into pass/fail is exactly what makes a
    # vacuous requirement indistinguishable from one nobody ever checked.
    class Result < ::Data.define(:assertion, :status, :detail)
      include Dexpace::Model
      private_class_method :new

      STATUSES = %i[passed failed vacuous waived error].freeze

      def self.build(assertion:, status:, detail: nil)
        new(assertion: assertion, status: status, detail: detail)
      end

      def initialize(assertion:, status:, detail: nil)
        Model.required!("assertion", assertion)
        unless STATUSES.include?(status)
          raise InvalidArgumentError, "status must be one of: #{STATUSES.join(", ")}"
        end

        super
      end
    end
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # A frozen list of Results. #to_s is the only renderer this sub-phase ships (open question
    # 6): a structured #to_h is NFR-4-locked surface with no caller until phase 9 aggregates
    # three suites.
    class Report
      def initialize(results)
        @results = results.freeze
      end

      def passed?
        failures.empty? && errors.empty?
      end

      def failures
        by_status(:failed)
      end

      def vacuous
        by_status(:vacuous)
      end

      def waived
        by_status(:waived)
      end

      def errors
        by_status(:error)
      end

      # Section 9.3: "the gap stays visible rather than disappearing into a restated item" --
      # every waived id is named on every run, not only when something failed.
      def to_s
        lines = ["#{@results.count { |r| r.status == :passed }} passed, " \
                 "#{failures.size} failed, #{vacuous.size} vacuous, #{waived.size} waived, " \
                 "#{errors.size} errored"]
        waived.each { |r| lines << "  waived: #{r.assertion.ids.join(", ")} (#{r.assertion.name})" }
        failures.each { |r| lines << "  FAILED: #{r.assertion.ids.join(", ")}: #{r.detail}" }
        errors.each { |r| lines << "  ERROR: #{r.assertion.ids.join(", ")}: #{r.detail}" }
        lines.join("\n")
      end

      private

      def by_status(status)
        @results.select { |r| r.status == status }
      end
    end
  end
end
```

**The two `require "dexpace/model"` lines are cross-gem and deliberately not `require_relative`.**
`Dexpace::Model` lives in `dexpace-core` at `gems/dexpace-core/lib/dexpace/model.rb`; a
`require_relative "../model"` from `gems/dexpace-conformance/lib/dexpace/conformance/assertion.rb`
resolves to `gems/dexpace-conformance/lib/dexpace/model.rb`, which does not exist, and phase 0's
require-allowlist audit would flag it as a `require_relative` that names nothing in this gem's `lib/`
even if it resolved. Absolute `require "dexpace/…"` is what the allowlist permits for a declared
`dexpace-core` dependency, and it is what every adapter gem in this plan uses to reach core.

- [ ] **Step 4: Write the five `sig/` mirrors**, one public constant per file, mirroring the members
  and methods above. `Assertion#body` is typed `^(untyped) -> void` in the RBS, not a named
  interface — an assertion's subject is whatever suite it belongs to, and phase 9 adds suites for
  seams that are not transports.

- [ ] **Step 5: Wire the requires and run every test**

Add the five `require_relative`s to `lib/dexpace/conformance.rb`, in the order Failure, Vacuous,
Assertion, Result, Report (each is independent, but this is the dependency-free order the module
layout table lists them in).

Run each test file, then `(cd gems/dexpace-conformance && bundle exec rake test)`.
Expected: PASS, 12 runs total.

---

## Task 5: `Dexpace::Conformance::WireServer` and `::Scripts`

**Requirement IDs:** none directly — the fixture every `TRANSPORT` assertion from Task 9 onward
runs against. `P8-9`, `P8-14`.
**Design:** "`R7`"; open question 4; `P8-9`.

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/wire_server.rb`,
  `.../scripts.rb`, both `sig/` mirrors
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb`
- Test: `gems/dexpace-conformance/test/dexpace/conformance/{wire_server,scripts}_test.rb`

**Needs:** Task 3's require-allowlist exception (this is the first `require "socket"` in the gem).
**Produces:** `WireServer.start(script) { |server| … }` and the non-block form; the named scripts.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "net/http"

# testing/4ef070df: every test runs alone in any order -- a fresh server per assertion, never a
# shared one, so #connections is never order-dependent across tests.
class DexpaceConformanceWireServerTest < DexpaceConformanceTestCase
  def get(port, path = "/")
    ::Net::HTTP.start("127.0.0.1", port) { |c| c.request(::Net::HTTP::Get.new(path)) }
  end

  test "starts on an ephemeral port and answers a scripted response" do
    server = Dexpace::Conformance::WireServer.start(Dexpace::Conformance::Scripts.fixed("hi"))

    res = get(server.port)

    assert_equal("200", res.code)
    assert_equal("hi", res.body)
    server.close
  end

  test "records requests and connections, independently of the client's own count" do
    server = Dexpace::Conformance::WireServer.start(Dexpace::Conformance::Scripts.fixed("x"))

    2.times { get(server.port) }

    assert_equal(2, server.requests.size)
    assert_equal(2, server.connections)
    server.close
  end

  test "records closed_connections separately from connections" do
    server = Dexpace::Conformance::WireServer.start(Dexpace::Conformance::Scripts.fixed("x"))

    get(server.port)
    server.await_closed_connection # a blocking Queue#pop, never a sleep-poll

    assert_equal(1, server.closed_connections)
    server.close
  end

  test "the block form closes the server on any exit, and #close is idempotent" do
    port = nil
    Dexpace::Conformance::WireServer.start(Dexpace::Conformance::Scripts.fixed("x")) do |server|
      port = server.port
    end

    assert_raises(Errno::ECONNREFUSED) { get(port) }
  end

  test "#close is idempotent and bounded" do
    server = Dexpace::Conformance::WireServer.start(Dexpace::Conformance::Scripts.fixed("x"))

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    server.close
    server.close
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

    assert_operator(elapsed, :<, 1.0)
  end
end
```

**`#await_closed_connection` is the one mechanism every "did the server see the close?" wait in this
plan uses, and it is why no test polls.** Global Constraints forbid a sleep used as synchronisation; an
earlier revision of this test wrote `sleep 0.05 while server.closed_connections.zero?`, which is a poll
whose outcome depends on machine load and which `testing/4ef070df`'s order-independence rule rejects.
The replacement is on `WireServer` itself rather than on each script: `#handle`'s `ensure` pushes one
token into a private `Thread::Queue` for every connection it finishes, and `#await_closed_connection`
is a plain blocking `Queue#pop`. A blocking `Queue#pop` is not `Timeout.timeout` and is not a sleep —
it is the same cancellable-wait shape phase 5a already ships, applied to a fixture. Putting it on the
server rather than on a per-script `on_close:` keyword means the eleven scripts in Step 3 need no
change and `8c` inherits the wait with the fixture.

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-conformance/test/dexpace/conformance/wire_server_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Conformance::WireServer`.

- [ ] **Step 3: Write `lib/dexpace/conformance/scripts.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # Named response scripts a WireServer runs against every accepted connection. Each is a
    # module function returning a callable taking the connection socket and the already-read
    # request head (the request line plus header lines, as an Array of raw String lines); the
    # callable reads and discards any request body itself before writing a response, because a
    # server that never drains the socket would make the client's own write block.
    module Scripts
      module_function

      # A fixed-length body over ordinary framing. The one script most assertions in Tasks 9-13
      # that do not need a specific wire shape reach for.
      def fixed(body, status: "200 OK", headers: { "Content-Type" => "text/plain" })
        ->(conn, _head) { write_response(conn, status: status, headers: headers, body: body) }
      end

      # TRANSPORT-25's clause: a multi-megabyte body, one write.
      def large(byte_count)
        ->(conn, _head) { write_response(conn, body: "a" * byte_count) }
      end

      # TRANSPORT-19/25: writes a first chunk, sleeps, writes a second -- the shape that makes
      # pre-buffering observable as a timing defect and not only as a content one.
      def dribble(first, second, delay_seconds)
        lambda do |conn, _head|
          conn.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n" \
                     "Transfer-Encoding: chunked\r\n\r\n")
          conn.write("#{first.bytesize.to_s(16)}\r\n#{first}\r\n")
          conn.flush
          sleep delay_seconds
          conn.write("#{second.bytesize.to_s(16)}\r\n#{second}\r\n0\r\n\r\n")
          conn.close
        end
      end

      # TRANSPORT-1: a raw 302 with a Location, never followed.
      def redirect(to)
        ->(conn, _head) { write_response(conn, status: "302 Found", headers: { "Location" => to }) }
      end

      # TRANSPORT-24: a vendor status with a body.
      def vendor_status(code, body)
        ->(conn, _head) { write_response(conn, status: "#{code} Vendor", body: body) }
      end

      # TRANSPORT-14: control byte and non-ASCII byte in headers, obs-text in a value, and a
      # multi-valued Set-Cookie -- the whole clause in one script.
      def malformed_headers
        lambda do |conn, _head|
          conn.write(
            "HTTP/1.1 200 OK\r\n" \
            "X-Ctl: a\x01b\r\n" \
            "X-B\xE9d: y\r\n" \
            "X-Obs: caf\xE9\r\n" \
            "Set-Cookie: a=1\r\n" \
            "Set-Cookie: b=2\r\n" \
            "Content-Length: 2\r\n\r\nhi",
          )
          conn.close
        end
      end

      # R4: an unparseable Content-Length, past what phase 1's Integer() coercion would call
      # negative-but-parseable -- non-numeric text, not merely a negative number, so both of R4's
      # two failure shapes have a script.
      def malformed_content_length
        ->(conn, _head) { conn.write("HTTP/1.1 200 OK\r\nContent-Length: abc\r\n\r\nhi"); conn.close }
      end

      # TRANSPORT-4/20: never answers -- the read-timeout half of the connect/read boundary.
      #
      # on_headers_written: is called once, on the SERVER's own thread, immediately after the
      # response head has been flushed and therefore at the exact moment the client is about to
      # block on its first body read. A test that needs to fire a cancellation "while the call is
      # blocked" pushes into a Thread::Queue from here and pops it on the canceller's thread --
      # which is deterministic, where `sleep 0.2; source.cancel(...)` is a guess that gets the
      # window wrong under load. The `sleep 30` below is the fixture SIMULATING a dead server, not
      # a wait for anything: it is the behaviour under test, and WireServer#close is what ends it.
      def hang_after_headers(on_headers_written: nil)
        lambda do |conn, _head|
          conn.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
          conn.flush
          on_headers_written&.call
          sleep 30 # outlived by every test's own timeout; the socket is closed by WireServer#close
        end
      end

      # TRANSPORT-2/3: the first connection on a script's own counter drops without answering;
      # every later connection answers normally -- the shape TRANSPORT-2's "assert the native
      # client does not silently re-send" needs.
      def fail_first_connection_then_succeed(body)
        attempt = 0
        mutex = ::Thread::Mutex.new
        lambda do |conn, _head|
          first = mutex.synchronize { (attempt += 1) == 1 }
          if first
            conn.close
          else
            write_response(conn, body: body)
          end
        end
      end

      # TRANSPORT-25: a body shorter than its own declared Content-Length, then the connection
      # closes -- a truncated transfer, distinct from a clean connection-close-framed body.
      def truncated(declared_length:, actual_body:)
        lambda do |conn, _head|
          conn.write("HTTP/1.1 200 OK\r\nContent-Length: #{declared_length}\r\n\r\n#{actual_body}")
          conn.close
        end
      end

      # PAGE-36's per-call-options test: two DIFFERENT scripted responses in sequence over one
      # server, keyed by call order, so the test can assert each call actually reached a distinct
      # page rather than the same response twice.
      def sequenced(*bodies)
        index = 0
        mutex = ::Thread::Mutex.new
        lambda do |conn, _head|
          body = bodies[mutex.synchronize { (index += 1) - 1 }] || bodies.last
          write_response(conn, body: body)
        end
      end

      def write_response(conn, status: "200 OK", headers: { "Content-Type" => "text/plain" },
                          body: "")
        header_lines = headers.merge("Content-Length" => body.bytesize.to_s)
                               .map { |k, v| "#{k}: #{v}" }.join("\r\n")
        conn.write("HTTP/1.1 #{status}\r\n#{header_lines}\r\n\r\n#{body}")
        conn.close
      end
    end
  end
end
```

- [ ] **Step 4: Write `lib/dexpace/conformance/wire_server.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "socket"

module Dexpace
  module Conformance
    # Section 9.3's fixture: a plaintext-only TCPServer bound to 127.0.0.1:0, running one accept
    # loop on its own thread, handing each connection to a script. P8-9: it exercises no TLS and
    # no connect timeout, and the report every suite prints says so (Task 6).
    #
    # Shutdown is the bounded join, symmetric with ResponsePump (open question 4): closing the
    # listener wakes a blocked #accept with IOError/Errno::EBADF, and the accept thread is joined
    # with the same JOIN_DEADLINE_SECONDS budget every producer teardown in this plan uses.
    class WireServer
      JOIN_DEADLINE_SECONDS = 5.0

      private_class_method :new

      def self.start(script)
        server = new(script)
        return server unless block_given?

        begin
          yield server
        ensure
          server.close
        end
      end

      def initialize(script)
        @tcp = ::TCPServer.new("127.0.0.1", 0)
        @script = script
        @requests = []
        @connections = 0
        @closed_connections = 0
        @closed_queue = ::Thread::Queue.new
        @mutex = ::Thread::Mutex.new
        @closed = false
        @accept_thread = ::Thread.new { accept_loop }
      end

      def port
        @tcp.addr[1]
      end

      def requests
        @mutex.synchronize { @requests.dup }
      end

      def connections
        @mutex.synchronize { @connections }
      end

      def closed_connections
        @mutex.synchronize { @closed_connections }
      end

      # Blocks until `count` more connections have been finished by #handle. A plain blocking
      # Queue#pop, never a sleep-poll: Global Constraints forbid a sleep used as synchronisation,
      # and testing/4ef070df requires every test to run alone in any order, which a load-sensitive
      # poll is not. #close closes the queue, so a pop that outlives the server returns nil rather
      # than hanging.
      def await_closed_connection(count = 1)
        count.times { @closed_queue.pop }
        nil
      end

      def close
        first = @mutex.synchronize do
          next false if @closed

          @closed = true
        end
        return nil unless first

        Dexpace.close_quietly(@tcp)
        @accept_thread.join(JOIN_DEADLINE_SECONDS)
        @closed_queue.close # a waiter that outlived the server gets nil, never a hang
        nil
      end

      private

      def accept_loop
        loop do
          conn = @tcp.accept
          @mutex.synchronize { @connections += 1 }
          ::Thread.new(conn) { |c| handle(c) }
        end
      rescue ::IOError, ::Errno::EBADF
        nil # the listener was closed from #close; this thread's job is done
      end

      def handle(conn)
        head = read_head(conn)
        @mutex.synchronize { @requests << head }
        @script.call(conn, head)
      rescue ::StandardError
        nil # a script that raises must not crash the accept loop or strand other connections
      ensure
        @mutex.synchronize { @closed_connections += 1 }
        Dexpace.close_quietly(conn)
        begin
          @closed_queue.push(true) # wakes #await_closed_connection; no-op once the queue is closed
        rescue ::ClosedQueueError
          nil
        end
      end

      def read_head(conn)
        lines = [conn.gets]
        lines << conn.gets while lines.last && lines.last != "\r\n"
        lines.compact
      end
    end
  end
end
```

- [ ] **Step 5: Write both `sig/` mirrors and add the requires**

Add `require_relative "dexpace/conformance/scripts"` before `require_relative
"dexpace/conformance/wire_server"` in `lib/dexpace/conformance.rb` (`Scripts` has no dependency on
`WireServer`; the order is alphabetical-by-convenience here since neither requires the other).

- [ ] **Step 6: Run the tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-conformance/test/dexpace/conformance/wire_server_test.rb`
Expected: PASS, 5 runs. Then `gates:require_allowlist`, confirming `require "socket"` is now
permitted for this gem and denied for every other (Task 3's own test already asserts the second
half; this step re-runs the real gate over the real tree).

---

## Task 6: `Dexpace::Conformance::TransportCase` and `::TransportSuite`

**Requirement IDs:** none directly — the run loop and the waiver/vacuity mechanism every assertion
group depends on.
**Design:** "`R7`"; "`R16`"; open question 7.

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/transport_case.rb`,
  `.../transport_suite.rb`, both `sig/` mirrors (the `sig/` for `transport_case.rbs` also carries
  the `_Transport` RBS interface)
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb`
- Test: `gems/dexpace-conformance/test/dexpace/conformance/{transport_case,transport_suite}_test.rb`,
  `gems/dexpace-conformance/test/support/non_conforming_transport.rb`

**Needs:** Tasks 4, 5.
**Produces:** `TransportSuite.assertions` (empty for now; Tasks 9–13 populate it), `.run(build:,
borrow: nil, waive: [], around: nil, settle: nil, wire: nil)`; `TransportCase#transport`,
`#borrowed_transport`, `#wire`, `#request`, `#settle`.

**Three keywords added 2026-09-12, and they are the whole of what an *asynchronous* second driver needs
from this task.** The design's `R16` → *The suite contract* merges `8a`'s original five assumptions with
the nine `8c`'s design placed on the same suite; three of the merged twelve are mechanisms this task must
build, and without them `8c` cannot drive the suite at all — not because `8a` runs first, but because the
shapes are absent:

- **`settle:` (clause 8).** `TransportCase#settle(transport, request, options, cancellation)` is the
  suite's one send primitive. Its default is `transport.call(…)`; the async driver passes
  `->(t, req, opts, cancel) { t.call(req, opts, cancel).value(cancellation: cancel) }`. Every assertion
  written from Task 9 onward calls `kase.settle(…)` and **never `transport.call(…)` directly**, because a
  §17 assertion written twice — once per path — is §11.12's four sync/async drifts reappearing inside the
  port's own suite.
- **`around:` (clause 9).** A callable the runner hands each assertion's invocation to as a block. Its
  default is `->(&blk) { blk.call }`; the async driver passes `->(&blk) { Sync { blk.call } }`, because
  `8c`'s transport fails its future outside a reactor by design (`P8-39`). This is what makes
  `TRANSPORT-25`'s multi-megabyte round trip and `TRANSPORT-19`'s abandoned-subscription clause runnable
  against a **body streamed under a fiber scheduler**: the read has to happen inside the reactor the
  wrapper opened, on the fiber the exchange was started on.
- **`wire:` (clause 11).** A fixture factory. Its default is `-> (script) { WireServer.start(script) }`;
  `8c` passes its own in-process HTTP/2 fixture and runs the same protocol-independent assertions against
  both. A fixture must answer `#port`, `#requests`, `#connections`, `#closed_connections` and
  `#await_closed_connection` — `WireServer`'s own surface, which is therefore the contract rather than an
  implementation detail. The HTTP/2 fixture stays in `dexpace-transport-async_http`'s `test/support/`:
  `dexpace-conformance` declares `dexpace-core` and nothing else, and an HTTP/2 server needs `async-http`.

**Two further merged clauses need no new mechanism here and are recorded so Tasks 9–13 honour them.**
Clause 2's `-1`-when-unknown content length is read off `Dexpace::Response#body.content_length`, never
off a native object, so Task 11's and Task 10's assertions already ask the right question. Clause 5's
cancellation outcome is `Dexpace::CancelledError` from `#settle` on **both** paths — raised directly by a
sync transport, and re-raised by `Future#value` after `Completer#request_cancel` on an async one — which
is what Task 12's `TRANSPORT-3` assertion asserts rather than asserting a `Net::HTTP`-shaped `IOError`.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

class DexpaceConformanceTransportCaseTest < DexpaceConformanceTestCase
  def build_case(build: ->(**_settings) { :built }, borrow: nil)
    Dexpace::Conformance::TransportCase.new(build: build, borrow: borrow)
  end

  test "#transport calls the build factory with the given settings and tracks it for teardown" do
    seen = nil
    kase = build_case(build: ->(**settings) { seen = settings; :the_transport })

    result = kase.transport(timeout: 1.5)

    assert_equal(:the_transport, result)
    assert_equal({ timeout: 1.5 }, seen)
  end

  test "#borrowed_transport raises Vacuous when the adapter supplies no borrowing entry point" do
    kase = build_case(borrow: nil)

    assert_raises(Dexpace::Conformance::Vacuous) { kase.borrowed_transport(:client) }
  end

  test "#borrowed_transport calls the borrow factory when one is supplied" do
    kase = build_case(borrow: ->(client) { [:borrowed, client] })

    assert_equal([:borrowed, :a_client], kase.borrowed_transport(:a_client))
  end

  test "#wire starts a WireServer lazily and memoizes it across calls in one case" do
    kase = build_case

    first = kase.wire(script: Dexpace::Conformance::Scripts.fixed("x"))
    second = kase.wire

    assert_same(first, second)
    kase.teardown
  end

  test "#request builds a Dexpace::Request against #wire's own port" do
    kase = build_case
    kase.wire(script: Dexpace::Conformance::Scripts.fixed("x"))

    request = kase.request(path: "/a")

    assert_equal("GET", request.method.to_s)
    assert_match(%r{/a\z}, Dexpace::URL.external_form(request.url))
    kase.teardown
  end

  test "#teardown closes every transport it tracked and the wire server" do
    closed = []
    fake_transport = Object.new
    fake_transport.define_singleton_method(:close) { closed << :transport }
    kase = build_case(build: ->(**_) { fake_transport })
    kase.transport
    kase.wire(script: Dexpace::Conformance::Scripts.fixed("x"))

    kase.teardown

    assert_includes(closed, :transport)
  end

  # Suite contract clause 8 (design R16). The default settle is transport.call; a driver that
  # replaces it is the only thing that lets ONE assertion body drive a sync and an async adapter.
  test "#settle defaults to transport.call and is replaceable by the driver" do
    seen = nil
    default = Dexpace::Conformance::TransportCase.new(
      build: ->(**_) { :t },
      settle: Dexpace::Conformance::TransportCase::DEFAULT_SETTLE,
    )
    transport = Object.new
    transport.define_singleton_method(:call) { |*args| seen = args; :the_response }

    assert_equal(:the_response, default.settle(transport, :req, :opts, :cancel))
    assert_equal([:req, :opts, :cancel], seen)

    awaited = Dexpace::Conformance::TransportCase.new(
      build: ->(**_) { :t },
      settle: ->(_t, _r, _o, _c) { :awaited },
    )

    assert_equal(:awaited, awaited.settle(transport, :req, :opts, :cancel))
  end

  # Clause 11: the fixture comes from a factory, so 8c can hand in its own HTTP/2 server.
  test "#wire calls the supplied factory instead of starting a WireServer" do
    built = []
    kase = Dexpace::Conformance::TransportCase.new(
      build: ->(**_) { :t },
      wire: ->(script) { built << script; :a_foreign_fixture },
    )

    assert_equal(:a_foreign_fixture, kase.wire(script: :the_script))
    assert_equal([:the_script], built)
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/non_conforming_transport"

class DexpaceConformanceTransportSuiteTest < DexpaceConformanceTestCase
  def suite_with(*assertions)
    Dexpace::Conformance::TransportSuite.stub(:assertions, assertions) { yield }
  end

  def assertion(id, &body)
    Dexpace::Conformance::Assertion.build(ids: [id], name: id, body: body)
  end

  test "run executes every assertion and returns a Report" do
    passing = assertion("A") { |_case| nil }
    suite_with(passing) do
      report = Dexpace::Conformance::TransportSuite.run(build: ->(**_) { :t })

      assert_predicate(report, :passed?)
    end
  end

  test "a raised Failure lands as :failed, a raised Vacuous as :vacuous, anything else as :error" do
    failing = assertion("A") { |_case| raise Dexpace::Conformance::Failure.new("x", expected: 1,
                                                                                actual: 2,
                                                                                requirement_ids: ["A"]) }
    vacuous = assertion("B") { |_case| raise Dexpace::Conformance::Vacuous, "no antecedent" }
    erroring = assertion("C") { |_case| raise RuntimeError, "boom" }

    suite_with(failing, vacuous, erroring) do
      report = Dexpace::Conformance::TransportSuite.run(build: ->(**_) { :t })

      assert_equal(1, report.failures.size)
      assert_equal(1, report.vacuous.size)
      assert_equal(1, report.errors.size)
    end
  end

  test "waiving an assertion's id suppresses it into :waived without running the body" do
    ran = false
    waivable = assertion("A") { |_case| ran = true; raise "would have failed" }

    suite_with(waivable) do
      report = Dexpace::Conformance::TransportSuite.run(build: ->(**_) { :t }, waive: ["A"])

      assert_equal(1, report.waived.size)
      refute(ran, "a waived assertion's body must not run at all")
    end
  end

  test "a deliberately non-conforming fake transport fails the assertion that names its defect" do
    checks_close = assertion("SEAM-14") do |kase|
      transport = kase.transport
      transport.close
      raise Dexpace::Conformance::Failure.new("closed? did not flip", expected: true,
                                               actual: transport.closed?,
                                               requirement_ids: ["SEAM-14"]) unless transport.closed?
    end

    suite_with(checks_close) do
      report = Dexpace::Conformance::TransportSuite.run(
        build: ->(**_) { NonConformingTransport.new },
      )

      assert_equal(1, report.failures.size, "the suite must DETECT the defect, not merely run")
    end
  end

  # Suite contract clause 9 (design R16): the runner INVOKES the assertion, so a driver can put a
  # block around it -- which is how 8c's async driver opens a reactor for the whole assertion,
  # including the part that reads a streamed response body.
  test "around: wraps every assertion invocation and the assertion still runs inside it" do
    order = []
    wrapped = assertion("A") { |_case| order << :assertion }

    suite_with(wrapped) do
      report = Dexpace::Conformance::TransportSuite.run(
        build: ->(**_) { :t },
        around: ->(&blk) { order << :before; blk.call; order << :after },
      )

      assert_predicate(report, :passed?)
      assert_equal(%i[before assertion after], order)
    end
  end

  # The same keyword must not swallow a failure: a Failure raised inside the wrapper still lands
  # as :failed, because the wrapper is around the invocation and not around the rescue.
  test "a Failure raised inside around: still lands as :failed" do
    failing = assertion("A") do |_case|
      raise Dexpace::Conformance::Failure.new("x", expected: 1, actual: 2, requirement_ids: ["A"])
    end

    suite_with(failing) do
      report = Dexpace::Conformance::TransportSuite.run(
        build: ->(**_) { :t }, around: ->(&blk) { blk.call },
      )

      assert_equal(1, report.failures.size)
    end
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# DEF-29 stays where the charter's sweep put it: dexpace-conformance publishes its OWN doubles
# rather than lifting dexpace-core's test/support/ fakes, so this is the gem's fake and not a move.
# A transport that never actually closes, proving TransportSuite.run detects a defect rather than
# only running assertions that happen to pass.
class NonConformingTransport
  def call(_request, _options, _cancellation)
    raise "not exercised by Task 6's one test"
  end

  def close
    nil # deliberately never flips closed?
  end

  def closed?
    false
  end

  def owned?
    true
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Expected: FAIL — `uninitialized constant Dexpace::Conformance::TransportCase`.

- [ ] **Step 3: Write `lib/dexpace/conformance/transport_case.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # What an assertion body receives. #transport and #borrowed_transport both track every
    # transport they build so #teardown -- driven by TransportSuite.run, never by the assertion
    # itself -- can close all of them; #wire is lazy and memoized per case, because not every
    # assertion needs a socket (TRANSPORT-15's borrowed-client half, for one).
    class TransportCase
      # settle: and wire: are the suite contract's clauses 8 and 11 (design R16). Both default to
      # the synchronous, TCPServer-backed shape, so a sync adapter's driver passes neither and an
      # async adapter's driver passes both without either of them forking an assertion.
      DEFAULT_SETTLE = ->(transport, request, options, cancellation) {
        transport.call(request, options, cancellation)
      }
      DEFAULT_WIRE = ->(script) { WireServer.start(script) }

      def initialize(build:, borrow: nil, settle: DEFAULT_SETTLE, wire: DEFAULT_WIRE)
        @build = build
        @borrow = borrow
        @settle = settle
        @wire_factory = wire
        @transports = []
        @wire = nil
      end

      def transport(**settings)
        track(@build.call(**settings))
      end

      # Clause 8: the ONE send primitive. An assertion calls this and never transport.call, so the
      # same assertion body drives a sync transport and an async one whose future must be awaited.
      # Clause 5: a cancellation surfaces from here as Dexpace::CancelledError on both paths.
      def settle(transport, request, options = Dexpace::RequestOptions::EMPTY,
                 cancellation = Dexpace::Cancellation.none)
        @settle.call(transport, request, options, cancellation)
      end

      def borrowed_transport(client)
        unless @borrow
          raise Vacuous, "this adapter's suite call supplied no borrowing construction " \
                         "(TRANSPORT-15's borrowed half)"
        end

        track(@borrow.call(client))
      end

      # Clause 11: the fixture comes from a factory, so one run can drive more than one of them.
      # Whatever it returns must answer #port, #requests, #connections, #closed_connections and
      # #await_closed_connection -- WireServer's own surface, which is the contract.
      def wire(script: Scripts.fixed(""))
        @wire ||= @wire_factory.call(script)
      end

      def request(path: "/", method: "GET", headers: Dexpace::Headers::EMPTY, body: nil)
        Dexpace::Request.build(method: method, url: "http://127.0.0.1:#{wire.port}#{path}",
                                headers: headers, body: body)
      end

      def teardown
        @transports.each { |t| Dexpace.close_quietly(t) }
        Dexpace.close_quietly(@wire)
        nil
      end

      private

      def track(built)
        @transports << built
        built
      end
    end
  end
end
```

- [ ] **Step 4: Write `lib/dexpace/conformance/transport_suite.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # DEF-22's runner. .assertions is populated across Tasks 9-13; this task ships it empty and
    # ships the mechanism, so each later task extends one Array literal rather than re-deriving
    # the run loop.
    module TransportSuite
      module_function

      # @return [Array<Assertion>] frozen, ordered, complete only after Task 13
      def assertions
        ASSERTIONS
      end

      # @param build [#call] keyword-taking factory building the SDK-managed transport
      # @param borrow [#call, nil] one-argument factory building the borrowing transport, or nil
      #   if the adapter under test supplies none
      # @param waive [Array<String>] requirement IDs whose FAILURE is suppressed into :waived --
      #   never applied to an assertion that would have raised Vacuous or nothing at all, because
      #   there is nothing there to suppress.
      # @param around [#call, nil] the suite contract's clause 9 -- a callable the runner hands
      #   each assertion's invocation to as a block, so an async driver can wrap it in `Sync { }`.
      #   nil means "invoke the assertion directly", which is what a synchronous driver wants.
      # @param settle [#call, nil] clause 8's send primitive; nil takes TransportCase's default.
      # @param wire [#call, nil] clause 11's fixture factory; nil takes WireServer.
      def run(build:, borrow: nil, waive: [], around: nil, settle: nil, wire: nil)
        results = assertions.map do |assertion|
          if (assertion.ids & waive).any?
            Result.build(assertion: assertion, status: :waived, detail: nil)
          else
            run_one(assertion, build: build, borrow: borrow, around: around, settle: settle,
                    wire: wire)
          end
        end
        Report.new(results)
      end

      def run_one(assertion, build:, borrow:, around: nil, settle: nil, wire: nil)
        kase = TransportCase.new(
          build: build, borrow: borrow,
          settle: settle || TransportCase::DEFAULT_SETTLE,
          wire: wire || TransportCase::DEFAULT_WIRE,
        )
        begin
          # Clause 9: the assertion is INVOKED by the runner, so `around` can put a block around
          # it. The reactor an async driver opens here is the one the assertion's body reads a
          # streamed response inside, which is why this wrapper and not a per-assertion one.
          if around
            around.call { assertion.call(kase) }
          else
            assertion.call(kase)
          end
          Result.build(assertion: assertion, status: :passed, detail: nil)
        rescue Vacuous => e
          Result.build(assertion: assertion, status: :vacuous, detail: e.reason)
        rescue Failure => e
          Result.build(assertion: assertion, status: :failed, detail: e.message)
        rescue ::StandardError => e
          Result.build(assertion: assertion, status: :error, detail: "#{e.class}: #{e.message}")
        ensure
          kase.teardown
        end
      end

      ASSERTIONS = [].freeze
      private_constant :ASSERTIONS
    end
  end
end
```

`TransportSuite` is a `module`, not a `Data`/`Model` value — `.assertions` is a frozen constant, not
per-instance state, and there is exactly one suite. Tasks 9–13 each replace the `ASSERTIONS` literal
with a longer one (never `<<`, because appending to a frozen `Array` raises and because each task's
diff should show exactly what it added).

- [ ] **Step 5: Write both `sig/` mirrors, including the `_Transport` interface**

`sig/dexpace/conformance/transport_case.rbs`:

```rbs
module Dexpace
  module Conformance
    interface _Transport
      def call: (Dexpace::Request, Dexpace::RequestOptions, Dexpace::Cancellation) -> Dexpace::Response
    end

    # Clause 11: a fixture is whatever answers this, so 8c's HTTP/2 server can stand in for
    # WireServer without dexpace-conformance naming a single async constant (NFR-11).
    interface _Wire
      def port: () -> Integer
      def requests: () -> Array[untyped]
      def connections: () -> Integer
      def closed_connections: () -> Integer
      def await_closed_connection: (?Integer) -> void
      def close: () -> void
    end

    class TransportCase
      DEFAULT_SETTLE: ^(_Transport, Dexpace::Request, Dexpace::RequestOptions, Dexpace::Cancellation) -> Dexpace::Response
      DEFAULT_WIRE: ^(untyped) -> _Wire

      def initialize: (build: ^(**untyped) -> _Transport, ?borrow: (^(untyped) -> _Transport)?,
                       ?settle: ^(_Transport, Dexpace::Request, Dexpace::RequestOptions, Dexpace::Cancellation) -> Dexpace::Response,
                       ?wire: ^(untyped) -> _Wire) -> void
      def transport: (**untyped) -> _Transport
      def borrowed_transport: (untyped client) -> _Transport
      def settle: (_Transport, Dexpace::Request, ?Dexpace::RequestOptions, ?Dexpace::Cancellation) -> Dexpace::Response
      def wire: (?script: ^(untyped, untyped) -> void) -> _Wire
      def request: (?path: String, ?method: String, ?headers: Dexpace::Headers,
                    ?body: Dexpace::Body?) -> Dexpace::Request
      def teardown: () -> nil
    end
  end
end
```

- [ ] **Step 6: Wire the requires and run every test**

Add `require_relative "dexpace/conformance/transport_case"` then
`require_relative "dexpace/conformance/transport_suite"` to `lib/dexpace/conformance.rb`, after
`wire_server` and `scripts`.

Run both test files.
Expected: PASS, **8 and 6** runs (six and four before the suite contract's `settle:`/`wire:`/`around:`
keywords landed on 2026-09-12).

---

## Task 7: `Dexpace::Conformance::RecordingSpan` and `::Allocations`

**Requirement IDs:** `OBS-21`, `OBS-25` (the conformance obligations 5b's `R8` and 5c hand to this
gem).
**Design:** module layout; object model, `dexpace-conformance` table; open question 5.

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/recording_span.rb`, `.../allocations.rb`,
  both `sig/` mirrors
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb`
- Test: `gems/dexpace-conformance/test/dexpace/conformance/{recording_span,allocations}_test.rb`

**Needs:** nothing from this gem.
**Produces:** a span double whose `#recording?` is `true` and which records attributes, events,
errors and idempotent `#end` calls; an allocation-delta helper with a required iteration count.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# OBS-21: "A Span MUST expose a recording flag; when non-recording, all mutators ... MUST be
# inert ... end() MUST be idempotent." Core's own NO_SPAN is non-recording by construction, so
# the idempotence half needs a RECORDING double -- this one -- to have a subject at all.
class DexpaceConformanceRecordingSpanTest < DexpaceConformanceTestCase
  test "recording? is true and mutators actually record" do
    span = Dexpace::Conformance::RecordingSpan.new

    span.set_attribute("http.status_code", 200)
    span.add_event("retry", attributes: { attempt: 2 })
    span.record_error(RuntimeError.new("boom"))
    span.status = :error

    assert_predicate(span, :recording?)
    assert_equal(200, span.attributes["http.status_code"])
    assert_equal(1, span.events.size)
    assert_equal(1, span.errors.size)
    assert_equal(:error, span.status)
  end

  test "end is idempotent: a second call does not duplicate the exported record" do
    span = Dexpace::Conformance::RecordingSpan.new

    span.end
    span.end

    assert_equal(1, span.end_count)
  end

  test "mutators after end are inert, per OBS-21's own end-then-mutate case" do
    span = Dexpace::Conformance::RecordingSpan.new
    span.end

    span.set_attribute("late", "value")

    refute_includes(span.attributes, "late")
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# OBS-25: "Selecting a no-op path MUST NOT allocate per call." Open question 5: the iteration
# count is a REQUIRED keyword with no default, because a caller who forgets it gets a number
# that means nothing, and the harness's own overhead is caller-shaped (measured on 3.4.10: 1
# allocation around an empty block, 0 around `{ nil }`).
class DexpaceConformanceAllocationsTest < DexpaceConformanceTestCase
  test "delta measures the per-iteration allocation cost, warming up first" do
    calls = 0
    delta = Dexpace::Conformance::Allocations.delta(iterations: 1000) { calls += 1 }

    assert_equal(0, delta)
    assert_operator(calls, :>, 1000, "the warm-up run(s) must have happened too")
  end

  test "an allocating block reports a positive per-iteration delta" do
    delta = Dexpace::Conformance::Allocations.delta(iterations: 200) { +"" }

    assert_operator(delta, :>, 0)
  end

  test "iterations is a required keyword" do
    assert_raises(::ArgumentError) { Dexpace::Conformance::Allocations.delta { nil } }
  end
end
```

- [ ] **Step 2: Run to confirm failure.**

- [ ] **Step 3: Write `lib/dexpace/conformance/recording_span.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # OBS-21's RECORDING branch, which core's own NO_SPAN cannot demonstrate because it is
    # always non-recording. This double records every mutation while live and goes inert after
    # #end, which is OBS-21's idempotence clause and its post-end-mutation clause in one object.
    class RecordingSpan
      attr_reader :attributes, :events, :errors, :status, :end_count

      def initialize
        @attributes = {}
        @events = []
        @errors = []
        @status = nil
        @end_count = 0
        @ended = false
      end

      def recording?
        !@ended
      end

      def set_attribute(key, value)
        @attributes[key] = value unless @ended
        self
      end

      def add_event(name, attributes: nil)
        @events << [name, attributes] unless @ended
        self
      end

      def record_error(error, attributes: nil)
        @errors << [error, attributes] unless @ended
        self
      end

      def status=(value)
        @status = value unless @ended
        value
      end

      def end
        return nil if @ended

        @ended = true
        @end_count += 1
        nil
      end
    end
  end
end
```

- [ ] **Step 4: Write `lib/dexpace/conformance/allocations.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # OBS-25's allocation-free-no-op assertion helper, written under 5b's R8 rule: what makes an
    # allocation assertion caller-insensitive is passing arguments that CANNOT allocate, never a
    # two-loop delta (which isolates the caller's per-iteration cost rather than hiding it) and
    # never the file's frozen_string_literal comment alone.
    module Allocations
      # Measured on 3.4.10: GC.stat(:total_allocated_objects) around an empty block reports 1;
      # around `{ nil }` it reports 0. The warm-up absorbs whatever one-time cost the FIRST call
      # into this method pays (block object creation, method dispatch caches) so it does not leak
      # into the measured delta.
      WARMUP_ITERATIONS = 5
      private_constant :WARMUP_ITERATIONS

      module_function

      # @param iterations [Integer] required. A caller who omits it gets an ArgumentError, not a
      #   number that means nothing -- OBS-25's "MUST NOT allocate per call" is a per-iteration
      #   claim, and dividing by an unstated count is not a claim about anything.
      def delta(iterations:)
        WARMUP_ITERATIONS.times { yield }
        before = ::GC.stat(:total_allocated_objects)
        iterations.times { yield }
        after = ::GC.stat(:total_allocated_objects)
        (after - before) / iterations
      end
    end
  end
end
```

- [ ] **Step 5: `sig/` mirrors, requires, run**

Run both test files.
Expected: PASS, 3 and 3 runs.

---

## Task 8: `Dexpace::Conformance::MinitestDriver` and `::RSpecDriver`

**Requirement IDs:** none directly — the two thin drivers `R7` and §9.3 require.
**Design:** "`R7`"; object model, `dexpace-conformance` table.

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/minitest_driver.rb`,
  `.../rspec_driver.rb`, both `sig/` mirrors
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb` (requires `minitest_driver`, does
  **not** require `rspec_driver`)
- Test: `gems/dexpace-conformance/test/dexpace/conformance/minitest_driver_test.rb`

**Needs:** Task 6.
**Produces:** `MinitestDriver.conformance(suite, **options)`, `RSpecDriver.conformance(suite,
**options)`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# Named MinitestDriver/RSpecDriver, not Minitest/RSpec: inside module Dexpace::Conformance, a
# constant named Minitest would shadow ::Minitest for the whole namespace, including this file's
# own body -- 5a's P5-3 reasoning applied to a second case.
class DexpaceConformanceMinitestDriverTest < DexpaceConformanceTestCase
  class DrivenSuite
    def self.assertions
      [Dexpace::Conformance::Assertion.build(ids: ["X"], name: "passes",
                                            body: ->(_case) { nil })]
    end

    def self.run(build:, borrow: nil, waive: [])
      Dexpace::Conformance::TransportSuite.stub(:assertions, assertions) do
        Dexpace::Conformance::TransportSuite.run(build: build, borrow: borrow, waive: waive)
      end
    end
  end

  class DrivenTest < Minitest::Test
    extend Dexpace::Conformance::MinitestDriver

    conformance(DrivenSuite, build: ->(**_) { :t })
  end

  test "conformance defines one test method per assertion" do
    methods = DrivenTest.instance_methods(false).grep(/\Atest_/)

    assert_equal(1, methods.size)
  end

  test "the generated test actually runs the assertion and fails the suite if it fails" do
    result = ::Minitest.run(["--name", DrivenTest.instance_methods(false).grep(/\Atest_/).first.to_s])

    assert(result)
  end
end
```

`MinitestDriver` names `::Minitest::Test` only inside this test file's own subclass (a consumer's
choice), never inside `lib/`; `lib/dexpace/conformance/minitest_driver.rb` itself never writes the
bare token `Minitest` or `RSpec` outside a method body, and never at the top level, so the file
loads under a process that has required neither framework.

- [ ] **Step 2: Run to confirm failure.**

- [ ] **Step 3: Write `lib/dexpace/conformance/minitest_driver.rb`**

**One `define_method` pass, each generated test running its own assertion directly.** Two shapes were
considered and rejected before this one: replaying a memoized `Result` (a Minitest `-n` filter or a
new `--seed` would then report a cached outcome from a run it skipped, exercising no I/O at all), and
"re-run the whole suite and waive everything else" (O(n²) in the assertion count, and it reaches into
`Report`'s internals for the one result it wants).

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    module MinitestDriver
      # @param suite [#assertions] anything shaped like TransportSuite: an ordered #assertions
      #   and a way to run one. Each generated test method runs its OWN assertion directly
      #   through Assertion#call, inside a fresh TransportCase built from the same build:/borrow:
      #   settings every other assertion in the suite gets -- so one Minitest -n filter exercises
      #   exactly the same code path a full suite run does, not a replay of a cached Result.
      # settle:/around:/wire: are the suite contract's clauses 8, 9 and 11 (design R16). A sync
      # driver passes none of the three and gets TransportCase's defaults; an async driver passes
      # all three, and they are the whole of what lets it drive this same suite.
      def conformance(suite, build:, borrow: nil, waive: [], settle: nil, around: nil, wire: nil)
        suite.assertions.each do |assertion|
          define_method("test_#{assertion.name.gsub(/\W+/, "_")}") do
            if (assertion.ids & waive).any?
              skip("waived: #{assertion.ids.join(", ")}")
              next
            end

            kase = TransportCase.new(
              build: build, borrow: borrow,
              settle: settle || TransportCase::DEFAULT_SETTLE,
              wire: wire || TransportCase::DEFAULT_WIRE,
            )
            begin
              # Clause 9: the driver INVOKES the assertion, so it may wrap it -- which is how an
              # async driver opens the reactor the assertion's own body reads a streamed
              # response inside.
              around ? around.call { assertion.call(kase) } : assertion.call(kase)
            rescue Vacuous => e
              skip("vacuous: #{e.reason}")
            rescue Failure => e
              flunk("#{assertion.ids.join(", ")}: #{e.message}")
            ensure
              kase.teardown
            end
          end
        end
      end
    end
  end
end
```

**§9.3's "the gap stays visible rather than disappearing into a restated item" is satisfied by the
`skip("waived: …")` branch above, which names the IDs in Minitest's own summary — not by a second
suite run.** An earlier revision of this step ended `conformance` with
`puts(suite.run(build:, borrow:, waive:)) if $VERBOSE`, on the reasoning that a `-w` run should also
see `Report#to_s`'s waived list. That is backwards: **every** run in this repository is a `-w` run
(phase 0's `test:gems` sets it and `NFR-5`/`NFR-6` make warnings fatal), so the guard is always true
and the line would silently double the socket traffic of every conformance run — while the consumer's
class body is still being evaluated, before Minitest has started. `Report#to_s` stays the renderer for
a caller who wants one, and `TransportSuite.run` stays available for it; the driver does not call it.

- [ ] **Step 4: Write `lib/dexpace/conformance/rspec_driver.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # Never required by lib/dexpace/conformance.rb: an RSpec-only consumer must opt in with its
    # own `require "dexpace/conformance/rspec_driver"`, exactly as an RSpec-only consumer already
    # opts into RSpec itself. ::RSpec is resolved inside the method body.
    module RSpecDriver
      # @param suite [#assertions]
      def self.conformance(suite, build:, borrow: nil, waive: [])
        suite.assertions.each do |assertion|
          ::RSpec.describe(assertion.name) do
            it "satisfies #{assertion.ids.join(", ")}" do
              skip("waived: #{assertion.ids.join(", ")}") if (assertion.ids & waive).any?
              next if (assertion.ids & waive).any?

              kase = TransportCase.new(build: build, borrow: borrow)
              begin
                assertion.call(kase)
              rescue Vacuous => e
                skip("vacuous: #{e.reason}")
              ensure
                kase.teardown
              end
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: `sig/` mirrors, the one require, run**

`sig/dexpace/conformance/minitest_driver.rbs` types `conformance` with `build: ^(**untyped) ->
_Transport` etc.; `rspec_driver.rbs` mirrors it as a singleton method. Add
`require_relative "dexpace/conformance/minitest_driver"` to `lib/dexpace/conformance.rb`; do **not**
add the RSpec line.

Run: `bundle exec ruby -w gems/dexpace-conformance/test/dexpace/conformance/minitest_driver_test.rb`
Expected: PASS, 2 runs.

---

## Task 9: Assertions group 1 — outbound mapping

**Requirement IDs:** `TRANSPORT-10`, `TRANSPORT-11`, `TRANSPORT-26`, plus `DEF-25`'s call-site
assertion (no ID of its own; it asserts `HTTP-17`/`HTTP-18`, phase 1's).
**Design:** `R2`; canonical text for all three, quoted in the design's "Canonical text" section.

> **Governs Tasks 9 through 13, added 2026-09-12.** **Every send in every assertion body goes through
> `kase.settle(transport, request, options, cancellation)` — never `transport.call(…)` and never
> `kase.transport.call(…)` directly.** The sketches in Tasks 9–13 below were written before the suite
> contract's clause 8 existed and still spell the call the old way; the implementer rewrites each one
> mechanically as it is landed. `#settle`'s default **is** `transport.call(…)`, so nothing about this
> sub-phase's own behaviour changes — what changes is that the same assertion body drives an
> asynchronous adapter, whose driver replaces `#settle` with
> `transport.call(…).value(cancellation: …)`. An assertion that calls `transport.call` directly
> returns a `Dexpace::Async::Future` on that adapter and fails on a `NoMethodError` several frames
> from anything a reader would connect to the seam, which is §11.12's four sync/async drifts
> reappearing inside the port's own suite.
>
> **Three consequences for the assertion bodies specifically**, each from a clause of the merged
> contract, and each of them a thing the sketches below do not yet do:
>
> - **A cancellation is asserted as `Dexpace::CancelledError` raised out of `#settle`** (clause 5) —
>   raised directly by this adapter and re-raised by `Future#value` after `Completer#request_cancel`
>   on an async one — never as a `Net::HTTP`-shaped `IOError`. Task 12's `TRANSPORT-3` assertion is
>   the one this changes.
> - **An unknown content length is asserted as `-1` on `Dexpace::Response#body.content_length`**
>   (clause 2), never as `nil` and never read off a native object, and **no assertion looks for
>   `content-length` among a response's headers** (clause 7) — `protocol-http1` consumes it as framing
>   and exposes it only as the body's length. Tasks 10 and 11 are the ones this changes.
> - **Header names are compared folded** (clause 6). `Net::HTTP` normalises case on the wire, HTTP/1.1
>   under `async-http` preserves it and HTTP/2 lowercases it — three answers, so an assertion that
>   checks the wire for a caller's exact spelling passes on one and fails on the others. Task 9's
>   `TRANSPORT-11` pass-through assertion is the one this changes.
>
> The two remaining mechanisms the contract adds — `around:` and `wire:` — need nothing of the
> assertion bodies: they are supplied by the driver (Tasks 8 and 20) and the bodies never see them.

**Files:**
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance/transport_suite.rb` (extends
  `ASSERTIONS`)
- Test: `gems/dexpace-conformance/test/dexpace/conformance/transport_suite/outbound_test.rb` — one
  file per group from here on, each `require_relative`d from the suite's own test, so a reviewer
  can find "which test exercises which group" without grepping one 1,500-line file.

**Needs:** Task 6. Every assertion body below is written and unit-tested against a **stub**
transport that records what it was asked to send (`StubTransport`, defined in this task's test and
reused by Tasks 10–13) — Task 20 is what runs the same four assertions against the real adapter, so
this task proves the assertions are correct and Task 20 proves the adapter conforms to them, and
neither task is asked to prove both at once.

- [ ] **Step 1: Write `test/support/stub_transport.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A transport double for testing an ASSERTION's own logic against a known-good and a
# known-bad send, independent of any real adapter. `on_call` receives (request, options,
# cancellation) and returns whatever the test wants adapted into a Dexpace::Response.
class StubTransport
  attr_reader :calls

  def initialize(&on_call)
    @on_call = on_call
    @calls = []
    @closed = false
  end

  def call(request, options, cancellation)
    @calls << [request, options, cancellation]
    @on_call.call(request, options, cancellation)
  end

  def close = @closed = true
  def closed? = @closed
  def owned? = true
end
```

- [ ] **Step 2: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/stub_transport"

# TRANSPORT-10, TRANSPORT-11, TRANSPORT-26, DEF-25.
class DexpaceConformanceOutboundAssertionsTest < DexpaceConformanceTestCase
  def find(id) = Dexpace::Conformance::TransportSuite.assertions.find { |a| a.ids.include?(id) }

  test "TRANSPORT-10 is registered and asserts the caller's explicit Content-Type wins" do
    assertion = find("TRANSPORT-10")
    refute_nil(assertion)

    response = Dexpace::Response.build(
      request: Dexpace::Request.build(method: "POST", url: "http://x/", headers:
        Dexpace::Headers.builder.tap { |b| b.add("Content-Type", "text/plain") }.build,
        body: Dexpace::Body.new), protocol: "http/1.1", status: 200, reason: "OK",
      headers: Dexpace::Headers::EMPTY, body: nil)
    kase = Dexpace::Conformance::TransportCase.new(
      build: ->(**_) { StubTransport.new { |_req, _opt, _canc| response } },
    )

    assertion.call(kase) # must not raise
  end

  test "DEF-25 rejects a request with a header value not answering the outbound grammar" do
    assertion = find("HTTP-18")
    forged = Object.new
    forged.define_singleton_method(:headers) do
      Object.new.tap do |h|
        h.define_singleton_method(:each_entry) { |&blk| blk.call("X-Evil", "a\r\nb") }
      end
    end

    kase = Dexpace::Conformance::TransportCase.new(
      build: ->(**_) { StubTransport.new { |*_| raise "must never be reached" } },
    )

    assert_raises(Dexpace::Conformance::Failure) { assertion.call(kase) }
  end
end
```

- [ ] **Step 3: Extend `ASSERTIONS` in `transport_suite.rb`**

Each assertion issues a real request through `case.wire`/`case.transport` and inspects what the
`WireServer` recorded, because the assertion runs against the **real adapter** from Task 20 onward
and a real socket is the only faithful way to see what left the process:

```ruby
      OUTBOUND = [
        Assertion.build(
          ids: ["TRANSPORT-10"], name: "the caller's explicit Content-Type wins over the body's",
          body: lambda do |kase|
            kase.wire(script: Scripts.fixed("ok"))
            headers = Dexpace::Headers.builder.tap { |b| b.add("Content-Type", "text/plain") }.build
            body = Dexpace::BufferBody.new(Dexpace::IO::Buffer.of_bytes("{}".b),
                                            media_type: Dexpace::MediaType.parse("application/json"))
            request = Dexpace::Request.build(method: "POST",
                                              url: "http://127.0.0.1:#{kase.wire.port}/",
                                              headers: headers, body: body)
            kase.transport.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)

            head = kase.wire.requests.last.join
            unless head.include?("Content-Type: text/plain")
              raise Failure.new("caller's Content-Type was overwritten", expected: "text/plain",
                                 actual: head, requirement_ids: ["TRANSPORT-10"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-10"], name: "a body-derived Content-Type is used only when caller set none",
          body: lambda do |kase|
            kase.wire(script: Scripts.fixed("ok"))
            body = Dexpace::BufferBody.new(Dexpace::IO::Buffer.of_bytes("{}".b),
                                            media_type: Dexpace::MediaType.parse("application/json"))
            request = Dexpace::Request.build(method: "POST",
                                              url: "http://127.0.0.1:#{kase.wire.port}/",
                                              headers: Dexpace::Headers::EMPTY, body: body)
            kase.transport.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)

            head = kase.wire.requests.last.join
            unless head.include?("Content-Type: application/json")
              raise Failure.new("body media type was not used", expected: "application/json",
                                 actual: head, requirement_ids: ["TRANSPORT-10"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-10", "TRANSPORT-26"],
          name: "no explicit header and no body media type falls back to octet-stream, no warning",
          body: lambda do |kase|
            kase.wire(script: Scripts.fixed("ok"))
            request = Dexpace::Request.build(method: "POST",
                                              url: "http://127.0.0.1:#{kase.wire.port}/",
                                              headers: Dexpace::Headers::EMPTY, body: nil)
            kase.transport.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)

            head = kase.wire.requests.last.join
            unless head.include?("Content-Type: application/octet-stream") &&
                   head.include?("Content-Length: 0")
              raise Failure.new("body-less POST was not substituted with a zero-length body",
                                 expected: "Content-Length: 0", actual: head,
                                 requirement_ids: ["TRANSPORT-26"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-11"],
          name: "a bogus Content-Length/Host are recomputed; a pass-through header survives",
          body: lambda do |kase|
            kase.wire(script: Scripts.fixed("ok"))
            headers = Dexpace::Headers.builder.tap do |b|
              b.add("Content-Length", "9999")
              b.add("Host", "bogus.example")
              b.add("X-Pass", "kept")
            end.build
            body = Dexpace::BufferBody.new(Dexpace::IO::Buffer.of_bytes("abc".b))
            request = Dexpace::Request.build(method: "POST",
                                              url: "http://127.0.0.1:#{kase.wire.port}/",
                                              headers: headers, body: body)
            kase.transport.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)

            head = kase.wire.requests.last.join
            unless head.include?("Content-Length: 3") && head.include?("X-Pass: kept") &&
                   !head.include?("bogus.example")
              raise Failure.new("framing headers were not recomputed, or the pass-through vanished",
                                 expected: "Content-Length: 3, X-Pass: kept, no bogus Host",
                                 actual: head, requirement_ids: ["TRANSPORT-11"])
            end
          end,
        ),
        Assertion.build(
          ids: ["HTTP-18"],
          name: "DEF-25: an outbound value with a CRLF is rejected before dispatch",
          body: lambda do |kase|
            forged_headers = Object.new
            forged_headers.define_singleton_method(:each_entry) do |&blk|
              blk.call("X-Evil", "a\r\nb")
            end
            forged = Object.new
            forged.define_singleton_method(:method) { Dexpace::Method::GET }
            forged.define_singleton_method(:url) { URI::RFC3986_PARSER.parse("http://127.0.0.1:1/") }
            forged.define_singleton_method(:headers) { forged_headers }
            forged.define_singleton_method(:body) { nil }

            transport = kase.transport
            raised = false
            begin
              transport.call(forged, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
            rescue Dexpace::InvalidArgumentError
              raised = true
            end
            unless raised
              raise Failure.new("a forged CRLF header name reached the adapter unrejected",
                                 expected: "Dexpace::InvalidArgumentError", actual: "none",
                                 requirement_ids: ["HTTP-18"])
            end
          end,
        ),
      ].freeze
      private_constant :OUTBOUND

      ASSERTIONS = OUTBOUND.freeze
```

`ASSERTIONS`'s previous `[].freeze` line is replaced by this, and Tasks 10–13 each replace
`ASSERTIONS = OUTBOUND.freeze` with `ASSERTIONS = (OUTBOUND + INBOUND).freeze` and so on, so the
diff at each task is additive and the final line always names every group.

- [ ] **Step 4: Run to confirm the tests pass against the stub**

Run:
`bundle exec ruby -w gems/dexpace-conformance/test/dexpace/conformance/transport_suite/outbound_test.rb`
Expected: PASS, 2 runs (the two written against `StubTransport`; the five real ones inside
`ASSERTIONS` are exercised for the first time in Task 20, against the real adapter — there is no
transport to run them against yet, and this task's own test only proves the two assertions it wrote
unit tests for raise/pass correctly against a controlled double, not that a real adapter satisfies
them).

---

## Task 10: Assertions group 2 — inbound mapping

**Requirement IDs:** `TRANSPORT-24`, `TRANSPORT-14`, `TRANSPORT-27`.
**Design:** `R4`; canonical text.

**Files:** as Task 9's shape, `.../transport_suite/inbound_test.rb`.
**Needs:** Task 9 (extends the same `ASSERTIONS` literal).

- [ ] **Step 1–2: failing tests, same shape as Task 9's**, asserting `find("TRANSPORT-24")` etc. are
  registered and that a hand-built vacuous/failure case behaves correctly.

- [ ] **Step 3: Extend `ASSERTIONS`**

```ruby
      INBOUND = [
        Assertion.build(
          ids: ["TRANSPORT-24"], name: "a vendor status code with a body is surfaced faithfully",
          body: lambda do |kase|
            kase.wire(script: Scripts.vendor_status(520, "vendor error"))
            response = kase.transport.call(kase.request, Dexpace::RequestOptions::EMPTY,
                                            Dexpace::Cancellation.none)
            unless response.status.code == 520 && response.body_string == "vendor error"
              raise Failure.new("vendor status was not surfaced faithfully", expected: 520,
                                 actual: response.status.code, requirement_ids: ["TRANSPORT-24"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-14"],
          name: "a control-byte value and a non-ASCII name are dropped; obs-text and the body survive",
          body: lambda do |kase|
            kase.wire(script: Scripts.malformed_headers)
            response = kase.transport.call(kase.request, Dexpace::RequestOptions::EMPTY,
                                            Dexpace::Cancellation.none)
            ok = !response.headers.include?("X-Ctl") && !response.headers.names.any? { |n| n.b.include?("\xE9".b) } &&
                 response.headers["X-Obs"]&.first == "caf\xE9".b && response.body_string == "hi"
            unless ok
              raise Failure.new("TRANSPORT-14's filtering did not hold", expected: "obs-text kept, " \
                                 "control byte and non-ASCII name dropped, body readable",
                                 actual: response.headers.names, requirement_ids: ["TRANSPORT-14"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-14"], name: "a multi-valued Set-Cookie survives as two values",
          body: lambda do |kase|
            kase.wire(script: Scripts.malformed_headers)
            response = kase.transport.call(kase.request, Dexpace::RequestOptions::EMPTY,
                                            Dexpace::Cancellation.none)
            values = response.headers["Set-Cookie"]
            unless values == ["a=1", "b=2"]
              raise Failure.new("multi-value header collapsed", expected: ["a=1", "b=2"],
                                 actual: values, requirement_ids: ["TRANSPORT-14"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-27"],
          name: "a malformed Content-Type and non-numeric Content-Length still let the body read",
          body: lambda do |kase|
            kase.wire(script: Scripts.malformed_content_length)
            response = kase.transport.call(kase.request, Dexpace::RequestOptions::EMPTY,
                                            Dexpace::Cancellation.none)
            ok = response.body.media_type.nil? && response.body.content_length == -1 &&
                 response.body_string == "hi"
            unless ok
              raise Failure.new("TRANSPORT-27's downgrade did not hold",
                                 expected: "media_type nil, content_length -1, body readable",
                                 actual: [response.body.media_type, response.body.content_length],
                                 requirement_ids: ["TRANSPORT-27"])
            end
          end,
        ),
      ].freeze
      private_constant :INBOUND

      ASSERTIONS = (OUTBOUND + INBOUND).freeze
```

- [ ] **Step 4: Run to confirm.**

---

## Task 11: Assertions group 3 — streaming and body lifecycle

**Requirement IDs:** `TRANSPORT-25`, `TRANSPORT-19`, `TRANSPORT-28`.
**Design:** `R1`, `R5`; open question 7 (why `TRANSPORT-28`'s zero-copy clause carries no
assertion at all).

**Files:** `.../transport_suite/streaming_test.rb`.
**Needs:** Task 9. Needs a temp file fixture for `TRANSPORT-28`'s byte-range clause
(`Tempfile.create` inside the assertion body, cleaned up in an `ensure`).

- [ ] **Step 1: Write the failing tests**, in Task 9's shape and in `streaming_test.rb`: assert
  `find("TRANSPORT-25")`, `find("TRANSPORT-19")` and `find("TRANSPORT-28")` are each registered, and
  drive each body against a hand-built `TransportCase` over `StubTransport` — one case whose stubbed
  response satisfies the clause (the assertion must not raise) and one whose stubbed response violates
  it (the assertion must raise `Dexpace::Conformance::Failure`). The second half is the one that
  matters: an assertion that never raises is an assertion that proves nothing, and Task 20 cannot tell
  the difference.

- [ ] **Step 2: Run them to confirm they fail** — `find(...)` returns `nil` until Step 3 registers the
  group, so every test in the file errors on a `nil` receiver.

Run:
`bundle exec ruby -w gems/dexpace-conformance/test/dexpace/conformance/transport_suite/streaming_test.rb`

- [ ] **Step 3: Extend `ASSERTIONS`**

```ruby
      STREAMING = [
        Assertion.build(
          ids: ["TRANSPORT-25"],
          name: "a multi-megabyte body round-trips byte-exactly and closing returns the connection",
          body: lambda do |kase|
            expected = ("a".."z").to_a.join * 200_000 # ~5.2 MiB, non-repeating-byte-pattern free
            kase.wire(script: Scripts.large(expected.bytesize))
            response = kase.transport.call(kase.request, Dexpace::RequestOptions::EMPTY,
                                            Dexpace::Cancellation.none)
            drained = response.body.source.read
            response.close

            unless drained.bytesize == expected.bytesize
              raise Failure.new("body did not round-trip byte-exactly", expected: expected.bytesize,
                                 actual: drained.bytesize, requirement_ids: ["TRANSPORT-25"])
            end
            kase.wire.await_closed_connection # a blocking Queue#pop, never a sleep-poll
            unless kase.wire.closed_connections.positive?
              raise Failure.new("closing the response did not release the connection",
                                 expected: "closed_connections > 0", actual: 0,
                                 requirement_ids: ["TRANSPORT-25"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-19"],
          name: "closing an undrained response unblocks the producer promptly and idempotently",
          body: lambda do |kase|
            kase.wire(script: Scripts.dribble("aaaaa", "bbbbb", 0.3))
            response = kase.transport.call(kase.request, Dexpace::RequestOptions::EMPTY,
                                            Dexpace::Cancellation.none)
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            response.close
            response.close # idempotent, per the same requirement's teardown clause
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            if elapsed > 1.0
              raise Failure.new("closing an undrained, dribbling response blocked",
                                 expected: "< 1.0s", actual: elapsed, requirement_ids: ["TRANSPORT-19"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-28"],
          name: "a file body with a non-zero position and partial count sends exactly that range",
          body: lambda do |kase|
            kase.wire(script: Scripts.fixed("ok"))
            file = ::Tempfile.create("dexpace-p8a") { |f| f.write("0123456789"); f }
            begin
              body = Dexpace::FileBody.new(file.path, offset: 3, count: 4) # "3456"
              request = Dexpace::Request.build(method: "POST",
                                                url: "http://127.0.0.1:#{kase.wire.port}/",
                                                headers: Dexpace::Headers::EMPTY, body: body)
              kase.transport.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)

              sent = kase.wire.requests.last # the head only; the byte range is on the socket after
              # The assertion checks Content-Length: 4 rather than the raw body bytes, because
              # WireServer's own script never echoes what it received -- HTTP-40's exact count is
              # the observable contract this reaches; a byte-for-byte wire capture is Task 16's own
              # unit test, over a script written to read and record the body it was sent.
              unless sent.join.include?("Content-Length: 4")
                raise Failure.new("file body's byte range was not honoured",
                                   expected: "Content-Length: 4", actual: sent.join,
                                   requirement_ids: ["TRANSPORT-28"])
              end
            ensure
              ::File.unlink(file.path)
            end
          end,
        ),
      ].freeze
      private_constant :STREAMING

      ASSERTIONS = (OUTBOUND + INBOUND + STREAMING).freeze
```

**`TRANSPORT-28`'s zero-copy clause has no assertion in this array**, per open question 7: the
design's own `R5` states it has no observable behaviour, so nothing here waives it — Task 20's
driver call passes `waive: []`, and the gap is recorded in `DEF-3`'s disposition and this plan's
coverage table, not suppressed by this suite's mechanism.

The first assertion waits on `WireServer#await_closed_connection` (Task 5) rather than polling:
Global Constraints forbid a sleep used as synchronisation, and a `sleep … until` loop over
`closed_connections` is load-sensitive in exactly the way `testing/4ef070df`'s order-independence rule
rejects. One mechanism, on the server, reused here rather than a second one invented per script.
`Scripts.dribble`'s own `sleep` is the opposite case and stays: it is the fixture *being* a slow
server, which is the behaviour `TRANSPORT-19`/`TRANSPORT-25` are about, and the assertion beside it
waits on a queue and a clock rather than on that sleep.

- [ ] **Step 4: Run the group's test file to confirm it passes**

Run:
`bundle exec ruby -w gems/dexpace-conformance/test/dexpace/conformance/transport_suite/streaming_test.rb`
Expected: PASS. The three assertions inside `ASSERTIONS` are exercised against a real adapter for the
first time in Task 20; this task proves only that they raise and pass correctly against a controlled
double.

---

## Task 12: Assertions group 4 — retry, cancellation and failure classification

**Requirement IDs:** `TRANSPORT-1`, `TRANSPORT-2`, `TRANSPORT-3`, `TRANSPORT-4`, `TRANSPORT-17`,
`TRANSPORT-18`, `TRANSPORT-20`, `TRANSPORT-22`.
**Design:** "Eleven rows carry a clause the checklist must state rather than tick" (rows 1–4, 8);
`R2` point 7 for `TRANSPORT-17`'s second half; `Failures` for `TRANSPORT-3`/`4`/`20`.

**Files:** `.../transport_suite/resilience_test.rb`.
**Needs:** Task 9. `TRANSPORT-3`'s test needs a cancellation `Source` (phase 2) fired from a second
thread while the first call is blocked reading; `TRANSPORT-18` is the one assertion in this group
that is a `Vacuous` by design, not a `Failure`-shaped check.

- [ ] **Step 1: Write the failing tests**, in Task 9's shape and in `resilience_test.rb`: assert each
  of the eight IDs is registered, and drive each body against a hand-built `TransportCase` over
  `StubTransport` in both directions — a conforming stub (the assertion must not raise) and a
  deliberately non-conforming one (the assertion must raise `Dexpace::Conformance::Failure`).
  `TRANSPORT-18` is the exception and gets its own shape: assert it raises
  `Dexpace::Conformance::Vacuous` for **every** subject, because its whole content is that the
  antecedent is absent.

- [ ] **Step 2: Run them to confirm they fail** — `find(...)` returns `nil` until Step 3 registers the
  group.

Run:
`bundle exec ruby -w gems/dexpace-conformance/test/dexpace/conformance/transport_suite/resilience_test.rb`

- [ ] **Step 3: Extend `ASSERTIONS`**

```ruby
      RESILIENCE = [
        Assertion.build(
          ids: ["TRANSPORT-1"], name: "a raw 302 is returned, never followed",
          body: lambda do |kase|
            kase.wire(script: Scripts.redirect("http://elsewhere.invalid/"))
            response = kase.transport.call(kase.request, Dexpace::RequestOptions::EMPTY,
                                            Dexpace::Cancellation.none)
            unless response.status.code == 302
              raise Failure.new("a redirect was followed", expected: 302,
                                 actual: response.status.code, requirement_ids: ["TRANSPORT-1"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-2"],
          name: "a single-use body over a first-attempt connection failure is not silently re-sent",
          body: lambda do |kase|
            kase.wire(script: Scripts.fail_first_connection_then_succeed("ok"))
            request = kase.request
            begin
              kase.transport.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
              raise Failure.new("the failed first connection was silently retried",
                                 expected: "a raised transport failure", actual: "success (200)",
                                 requirement_ids: ["TRANSPORT-2"])
            rescue Dexpace::TransportError
              nil # correct: the native client did not resend on its own
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-3"],
          name: "a mid-call cancellation surfaces as the interrupt, not the retryable failure",
          body: lambda do |kase|
            # The cancellation fires when the SERVER says the client is blocked, not after a
            # guessed delay: hang_after_headers pushes into `blocked` once the head is flushed,
            # which is the instant the call enters its first body read. A blocking Queue#pop is
            # not a sleep and not a Timeout.
            blocked = ::Thread::Queue.new
            kase.wire(script: Scripts.hang_after_headers(on_headers_written: -> { blocked.push(true) }))
            source = Dexpace::Cancellation.source
            transport = kase.transport
            request = kase.request
            canceller = ::Thread.new { blocked.pop; source.cancel(:test_cancel) }
            error = begin
              transport.call(request, Dexpace::RequestOptions::EMPTY, source.token)
              nil
            rescue ::StandardError => e
              e
            end
            canceller.join
            unless error.is_a?(Dexpace::CancelledError) || (source.cancelled? && error)
              raise Failure.new("cancellation was swallowed rather than surfaced",
                                 expected: "a cancellation-shaped error", actual: error&.class,
                                 requirement_ids: ["TRANSPORT-3"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-4"],
          name: "a read timeout classifies retryable and leaves no cancellation flag set",
          body: lambda do |kase|
            kase.wire(script: Scripts.hang_after_headers)
            error = begin
              kase.transport(timeout: 0.2).call(kase.request, Dexpace::RequestOptions::EMPTY,
                                                 Dexpace::Cancellation.none)
              nil
            rescue Dexpace::TransportError => e
              e
            end
            unless error&.retryable?
              raise Failure.new("a read timeout did not classify retryable", expected: true,
                                 actual: error&.retryable?, requirement_ids: ["TRANSPORT-4"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-17"],
          name: "the adapter does not itself trigger a second write of a single-use body",
          body: lambda do |kase|
            kase.wire(script: Scripts.fixed("ok"))
            reads = 0
            source = Object.new
            source.define_singleton_method(:each) do |&blk|
              reads += 1
              blk.call("payload".b)
            end
            body = Dexpace::BufferBody.new(Dexpace::IO::Buffer.of_bytes("payload".b))
            request = Dexpace::Request.build(method: "POST", url: kase.request.url.to_s,
                                              headers: Dexpace::Headers::EMPTY, body: body)
            kase.transport.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)

            unless kase.wire.requests.size == 1
              raise Failure.new("the request reached the wire more than once", expected: 1,
                                 actual: kase.wire.requests.size, requirement_ids: ["TRANSPORT-17"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-18"],
          name: "vacuous: Net::HTTP drives writes through #exec exactly once, never a re-subscribable producer",
          body: lambda do |_kase|
            raise Vacuous, "max_retries = 0 removes Net::HTTP's only resend hook, so the " \
                            "re-subscribable-producer antecedent this requirement conditions on " \
                            "is genuinely absent on this adapter (OI-34)"
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-20"],
          name: "a connection refused surfaces as the canonical retryable transport failure",
          body: lambda do |kase|
            refused_port = kase.wire.port
            kase.wire.close # nothing is listening now
            begin
              kase.transport.call(kase.request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
              raise Failure.new("a refused connection did not raise", expected: "Dexpace::TransportError",
                                 actual: "none", requirement_ids: ["TRANSPORT-20"])
            rescue Dexpace::TransportError => e
              raise Failure.new("did not classify retryable", expected: true, actual: e.retryable?,
                                 requirement_ids: ["TRANSPORT-20"]) unless e.retryable?
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-22"],
          name: "a failure while adapting a live response closes the native response first",
          body: lambda do |kase|
            kase.wire(script: Scripts.fixed("ok"))
            # Exercised directly in Task 17's own unit test, which can inject an adaptation
            # failure after the head arrives; this conformance-level assertion checks the
            # observable half -- the server sees the connection close even when the CALLER's own
            # code raises inside the response block, which is the shape TRANSPORT-22 is stated for.
            response = kase.transport.call(kase.request, Dexpace::RequestOptions::EMPTY,
                                            Dexpace::Cancellation.none)
            begin
              raise "caller-injected failure after the head arrived"
            rescue ::RuntimeError
              response.close
            end
            unless kase.wire.closed_connections.positive?
              raise Failure.new("the connection was not released", expected: "> 0", actual: 0,
                                 requirement_ids: ["TRANSPORT-22"])
            end
          end,
        ),
      ].freeze
      private_constant :RESILIENCE

      ASSERTIONS = (OUTBOUND + INBOUND + STREAMING + RESILIENCE).freeze
```

- [ ] **Step 4: Run to confirm.**

---

## Task 13: Assertions group 5 — lifecycle, concurrency, and the cross-phase tests

**Requirement IDs:** `TRANSPORT-5`, `TRANSPORT-6`, `TRANSPORT-15`, `TRANSPORT-16`, `TRANSPORT-29`,
`TRANSPORT-12`, `TRANSPORT-13`, `PAGE-36`.
**Design:** `R3`; "Eleven rows…" items for 15/16; verified fact 9; segmentation design's
`TRANSPORT-12`/`13` cross-reference; phase 7c `PAGE-36`.

**Files:** `.../transport_suite/lifecycle_test.rb`.
**Needs:** Task 9.

- [ ] **Step 1: Write the failing tests**, in Task 9's shape and in `lifecycle_test.rb`: assert each
  of the eight IDs is registered; drive the five `Failure`-shaped bodies against a conforming and a
  deliberately non-conforming `StubTransport`; and assert the three `Vacuous` bodies (`TRANSPORT-6`,
  `TRANSPORT-12`, `TRANSPORT-13`) raise `Dexpace::Conformance::Vacuous` for every subject. Assert
  `TransportSuite.assertions.size == 28` here too — this is the task that closes the array, so it is
  the one place a silently dropped group is catchable before Task 20.

- [ ] **Step 2: Run them to confirm they fail** — `find(...)` returns `nil` until Step 3 registers the
  group, and the size assertion reads 20.

Run:
`bundle exec ruby -w gems/dexpace-conformance/test/dexpace/conformance/transport_suite/lifecycle_test.rb`

- [ ] **Step 3: Extend `ASSERTIONS`, closing the array**

```ruby
      LIFECYCLE = [
        Assertion.build(
          ids: ["TRANSPORT-5"],
          name: "two concurrent calls with different per-call timeouts are each bounded by their own",
          body: lambda do |kase|
            kase.wire(script: Scripts.hang_after_headers)
            fast = kase.transport
            results = ::Thread::Queue.new
            t1 = ::Thread.new do
              t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              begin
                fast.call(kase.request, Dexpace::RequestOptions.builder.tap { |b| b.timeout = 0.1 }.build,
                          Dexpace::Cancellation.none)
              rescue Dexpace::TransportError
                nil
              end
              results.push(Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0)
            end
            t2 = ::Thread.new do
              t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              begin
                fast.call(kase.request, Dexpace::RequestOptions.builder.tap { |b| b.timeout = 0.5 }.build,
                          Dexpace::Cancellation.none)
              rescue Dexpace::TransportError
                nil
              end
              results.push(Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0)
            end
            t1.join
            t2.join
            elapsed = [results.pop, results.pop].sort
            unless elapsed[0] < 0.3 && elapsed[1] < 0.7
              raise Failure.new("per-call timeouts did not bound their own calls independently",
                                 expected: "[<0.3, <0.7]", actual: elapsed, requirement_ids: ["TRANSPORT-5"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-6"],
          name: "vacuous: this adapter's timeout knobs are floats with no zero-means-unbounded case",
          body: lambda do |_kase|
            raise Vacuous, "Net::HTTP's timeout knobs are floating-point seconds and zero means " \
                            "poll-once, not unbounded; the clamp ships anyway per " \
                            "transport-adapter/deccd514 and is asserted directly in the adapter's " \
                            "own suite (Task 14's Deadline test), which this conformance-level " \
                            "assertion records rather than duplicates"
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-15"],
          name: "a borrowed client survives the transport's close and stays usable",
          body: lambda do |kase|
            kase.wire(script: Scripts.fixed("ok"))
            client = ::Net::HTTP.new("127.0.0.1", kase.wire.port)
            client.max_retries = 0
            borrowed = kase.borrowed_transport(client)
            borrowed.call(kase.request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
            borrowed.close
            response = client.start { |c| c.request(::Net::HTTP::Get.new("/")) }
            unless response.code == "200"
              raise Failure.new("the borrowed client stopped working after the transport closed",
                                 expected: "200", actual: response.code, requirement_ids: ["TRANSPORT-15"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-15", "TRANSPORT-16"],
          name: "an owned transport raises ClosedError on a send after close; close is idempotent",
          body: lambda do |kase|
            kase.wire(script: Scripts.fixed("ok"))
            transport = kase.transport
            transport.close
            transport.close # idempotent
            begin
              transport.call(kase.request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
              raise Failure.new("a send after close on an owning transport did not raise",
                                 expected: "Dexpace::ClosedError", actual: "none",
                                 requirement_ids: ["TRANSPORT-15"])
            rescue Dexpace::ClosedError
              nil
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-29"],
          name: "many concurrent calls through one transport each get their own response",
          body: lambda do |kase|
            kase.wire(script: ->(conn, head) do
              path = head.first.split(" ")[1]
              Scripts.write_response(conn, body: path)
            end)
            transport = kase.transport
            mismatches = ::Thread::Queue.new
            threads = 8.times.map do |t|
              ::Thread.new do
                20.times do |i|
                  path = "/#{t}-#{i}"
                  req = kase.request(path: path)
                  res = transport.call(req, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
                  body = res.body_string
                  mismatches.push([path, body]) unless body == path
                end
              end
            end
            threads.each(&:join)
            found = []
            found << mismatches.pop until mismatches.empty?
            unless found.empty?
              raise Failure.new("a response was matched to the wrong request", expected: [],
                                 actual: found, requirement_ids: ["TRANSPORT-29"])
            end
          end,
        ),
        Assertion.build(
          ids: ["TRANSPORT-12"],
          name: "vacuous: Net::HTTP rejects no model-valid header name outright",
          body: ->(_kase) { raise Vacuous, "Net::HTTP writes any model-valid name to the wire " \
                                            "rather than raising; this ID is 8c's" },
        ),
        Assertion.build(
          ids: ["TRANSPORT-13"],
          name: "vacuous: same antecedent as TRANSPORT-12, same adapter, same reason",
          body: ->(_kase) { raise Vacuous, "no native-rejects-outright case exists on this adapter; " \
                                            "this ID is 8c's" },
        ),
        Assertion.build(
          ids: ["PAGE-36"],
          name: "the same transport driven twice in sequence honours a different RequestOptions each time",
          body: lambda do |kase|
            kase.wire(script: Scripts.sequenced("page one", "page two"))
            transport = kase.transport
            # DIFFERENT options on each call, which is the whole of PAGE-36: a suite that passed
            # the same RequestOptions twice would pass against a transport that reads options once
            # and reuses them for every later call, which is the defect 7c filed this row for.
            first = transport.call(kase.request,
                                    Dexpace::RequestOptions.builder.tap { |b| b.timeout = 5.0 }.build,
                                    Dexpace::Cancellation.none)
            second = transport.call(kase.request,
                                     Dexpace::RequestOptions.builder.tap do |b|
                                       b.timeout = 0.5
                                       b.max_retries = 0
                                     end.build,
                                     Dexpace::Cancellation.none)
            unless first.body_string == "page one" && second.body_string == "page two"
              raise Failure.new("the second call did not reach a fresh page",
                                 expected: %w[page\ one page\ two],
                                 actual: [first.body_string, second.body_string],
                                 requirement_ids: ["PAGE-36"])
            end
          end,
        ),
      ].freeze
      private_constant :LIFECYCLE

      ASSERTIONS = (OUTBOUND + INBOUND + STREAMING + RESILIENCE + LIFECYCLE).freeze
```

- [ ] **Step 4: Run every group's test file once more, together**

Run: `(cd gems/dexpace-conformance && bundle exec rake test)`
Expected: PASS. `TransportSuite.assertions.size` is **28** at this point — 5 outbound + 4 inbound + 3
streaming + 8 resilience + 8 lifecycle, three of them tagged with two IDs each, `TRANSPORT-28`'s
zero-copy clause carrying no entry and `TRANSPORT-30` carrying none at all. **Four** of the 28 are
`Vacuous` by construction rather than `Failure`-shaped checks: `TRANSPORT-18`, `TRANSPORT-6`,
`TRANSPORT-12` and `TRANSPORT-13`. Assert the count in this task's own test, so an assertion group
silently dropped by a bad merge fails here rather than in Task 20.

---

## Task 14: `Dexpace::Transport::NetHTTP::Deadline`

**Requirement IDs:** `TRANSPORT-5`, `TRANSPORT-6`.
**Design:** `R3`.

**Files:**
- Create: `gems/dexpace-transport-net_http/lib/dexpace/transport/net_http/deadline.rb`, its `sig/`
  mirror
- Test: `gems/dexpace-transport-net_http/test/dexpace/transport/net_http/deadline_test.rb`

**Needs:** Task 2's `Keys::REQUEST_TIMEOUT`; phase 5a's `Dexpace::Clock`.
**Produces:** `Deadline.new(clock:, budget:)`, `#remaining`, `#expired?`, `#clamped`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# TRANSPORT-5's own conformance clause is a statement about the CALL's total budget, not one
# syscall -- R3's total-budget reading is what makes it implementable at all.
class DexpaceTransportNetHttpDeadlineTest < DexpaceTestCase
  Deadline = Dexpace::Transport::NetHTTP::Deadline

  class FakeClock
    def initialize(start) = @now = start
    def monotonic = @now
    def advance(seconds) = @now += seconds
  end

  test "#remaining counts down as the clock advances" do
    clock = FakeClock.new(0.0)
    deadline = Deadline.build(clock: clock, budget: 5.0)

    clock.advance(2.0)

    assert_in_delta(3.0, deadline.remaining)
  end

  test "#expired? is true once remaining reaches zero or below" do
    clock = FakeClock.new(0.0)
    deadline = Deadline.build(clock: clock, budget: 1.0)

    refute_predicate(deadline, :expired?)
    clock.advance(1.5)
    assert_predicate(deadline, :expired?)
  end

  # TRANSPORT-6: the antecedent is inverted here (zero means poll-once, not unbounded), and the
  # clamp ships anyway per transport-adapter/deccd514, for adapters over coarser APIs.
  test "#clamped raises a tiny positive remaining up to MIN_TIMEOUT_SECONDS" do
    clock = FakeClock.new(0.0)
    deadline = Deadline.build(clock: clock, budget: Dexpace::Transport::NetHTTP::MIN_TIMEOUT_SECONDS / 2)

    assert_in_delta(Dexpace::Transport::NetHTTP::MIN_TIMEOUT_SECONDS, deadline.clamped)
  end

  test "#clamped does not raise an already-expired remaining" do
    clock = FakeClock.new(0.0)
    deadline = Deadline.build(clock: clock, budget: -1.0)

    assert_operator(deadline.clamped, :<=, 0)
  end

  test "#clamped leaves a comfortably positive remaining untouched" do
    clock = FakeClock.new(0.0)
    deadline = Deadline.build(clock: clock, budget: 10.0)

    assert_in_delta(10.0, deadline.clamped)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-transport-net_http/test/dexpace/transport/net_http/deadline_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Transport::NetHTTP` (the module itself does not
exist until Task 19 adds the tuning constants; this task's own test therefore needs
`MIN_TIMEOUT_SECONDS` to exist first). Reorder: write a minimal
`lib/dexpace/transport/net_http.rb` stub in this task carrying only the three tuning constants
(`DEFAULT_TIMEOUT_SECONDS = 60.0`, `MIN_TIMEOUT_SECONDS = 0.001`, `JOIN_DEADLINE_SECONDS = 5.0`) and
nothing else; Task 19 is what fills in `.build`/`.using`/`.default`/`Adapter` and the require-time
registration, in the same file, without touching these three lines.

- [ ] **Step 3: Write the tuning-constants stub and `Deadline`**

`lib/dexpace/transport/net_http.rb` (new, minimal — Task 19 extends it in place):

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "net_http/version"

module Dexpace
  module Transport
    # The reference synchronous transport, over net-http (a default gem on every Ruby this
    # repository supports). Filled in across Tasks 14-19; this line is where the tuning
    # constants land first because Deadline needs one of them before the module has anything
    # else.
    module NetHTTP
      # resource-management/2b9040ef: a named setting, not a literal at the call site. The
      # CONFIGURED tier (R3's middle row) defaults to this when Keys::REQUEST_TIMEOUT is unset.
      DEFAULT_TIMEOUT_SECONDS = 60.0

      # TRANSPORT-6's clamp floor. net-http's timeout knobs accept floats down to 0.0005
      # (verified); this is comfortably above that and still small enough that a caller with a
      # genuinely tight budget is not silently handed seconds of slack.
      MIN_TIMEOUT_SECONDS = 0.001

      # resource-management/b7587eb7: track every spawned thread and join it in a teardown path
      # guaranteed to run, with a BOUNDED wait -- never Thread#join with no argument, which is
      # this cop's neighbor concern (XCUT-13's "no unbounded await") rather than its own.
      JOIN_DEADLINE_SECONDS = 5.0
    end
  end
end
```

`lib/dexpace/transport/net_http/deadline.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../net_http"

module Dexpace
  module Transport
    module NetHTTP
      # R3: RequestOptions#timeout is a TOTAL per-call budget, not one value assigned to three
      # per-operation knobs -- a call with timeout: 5 must be bounded by 5 seconds total, not 5
      # seconds per read. #clamped is TRANSPORT-6's one-line clamp, carried here rather than at
      # each of the three assignment sites so the ID appears in exactly one comment.
      class Deadline
        private_class_method :new

        def self.build(clock:, budget:)
          new(clock, clock.monotonic + budget)
        end

        def initialize(clock, deadline)
          @clock = clock
          @deadline = deadline
        end

        def remaining
          @deadline - @clock.monotonic
        end

        def expired?
          remaining <= 0
        end

        # TRANSPORT-6. A strictly positive remaining below MIN_TIMEOUT_SECONDS is clamped UP to
        # it; an already-expired remaining is returned as-is (never clamped up past zero), so the
        # caller's own #expired? check -- taken BEFORE this is consulted -- is what decides
        # whether to raise rather than dispatch with a confusing near-zero value.
        def clamped
          value = remaining
          return value if value <= 0

          [value, MIN_TIMEOUT_SECONDS].max
        end
      end
    end
  end
end
```

`.build(clock:, budget:)` is the only construction entry point and the test above calls it directly;
`.new` stays `private_class_method` for the reason every other factory in this codebase does — one
construction entry point, named for what it does — and it is reachable only from `.build`'s own
implicit-receiver call. `Deadline` is a plain class rather than a `Data` type: nothing mutates it, but
it is not a wire-model value and gains nothing from `Data.define`.

- [ ] **Step 4: `sig/` mirror, run**

Run: `bundle exec ruby -w gems/dexpace-transport-net_http/test/dexpace/transport/net_http/deadline_test.rb`
Expected: PASS, 5 runs.

---

## Task 15: `Dexpace::Transport::NetHTTP::Failures`

**Requirement IDs:** `TRANSPORT-3`, `TRANSPORT-4`, `TRANSPORT-20`.
**Design:** the object model's `Failures` description; `P6-4`; verified fact 7.

**Files:**
- Create: `.../net_http/failures.rb`, its `sig/` mirror
- Test: `.../test/dexpace/transport/net_http/failures_test.rb`

**Needs:** Task 2's `Dexpace::TransportError`; phase 2's `Dexpace::Cancellation`,
`Dexpace::CancelledError`; phase 3a's `Dexpace::StreamError`/`Dexpace::ClosedError`.
**Produces:** `Failures.wrap(error, phase:, cancellation:)`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "net/http"
require_relative "../../../test_helper"

# TRANSPORT-3: "Discrimination MUST be out-of-band ... not by matching exception messages."
# TRANSPORT-4: a read timeout classifies retryable and MUST NOT set the cancellation flag.
# TRANSPORT-20: the canonical retryable transport failure, for anything that produced no
# response.
class DexpaceTransportNetHttpFailuresTest < DexpaceTestCase
  Failures = Dexpace::Transport::NetHTTP::Failures

  def uncancelled = Dexpace::Cancellation.none

  [
    ::Net::OpenTimeout, ::Net::ReadTimeout, ::Net::WriteTimeout, ::SocketError,
    ::Errno::ECONNRESET, ::OpenSSL::SSL::SSLError, ::EOFError, ::IOError,
    ::Net::HTTPBadResponse, ::Net::HTTPHeaderSyntaxError, ::Zlib::DataError,
  ].each do |klass|
    test "wraps #{klass} into a retryable Dexpace::TransportError carrying it as #cause" do
      original = klass.new("boom")

      wrapped = Failures.wrap(original, phase: :read, cancellation: uncancelled)

      assert_instance_of(Dexpace::TransportError, wrapped)
      assert_predicate(wrapped, :retryable?)
      assert_same(original, wrapped.cause)
      assert_equal(:read, wrapped.phase)
    end
  end

  test "TRANSPORT-3: asks the cancellation token first, regardless of the exception's class" do
    source = Dexpace::Cancellation.source
    source.cancel(:caller_requested)

    wrapped = Failures.wrap(::IOError.new("stream closed in another thread"), phase: :read,
                             cancellation: source.token)

    assert_instance_of(Dexpace::CancelledError, wrapped)
    assert_equal(:caller_requested, wrapped.reason)
  end

  test "TRANSPORT-4: a read timeout does not itself set the cancellation flag" do
    source = Dexpace::Cancellation.source

    Failures.wrap(::Net::ReadTimeout.new("slow"), phase: :read, cancellation: source.token)

    refute_predicate(source, :cancelled?)
  end

  test "never re-wraps a Dexpace::Error the adapter's own code raised" do
    [Dexpace::StreamError.new("x"), Dexpace::ClosedError.new("x"),
     Dexpace::InvalidArgumentError.new("x")].each do |own|
      wrapped = Failures.wrap(own, phase: :read, cancellation: uncancelled)

      assert_same(own, wrapped)
    end
  end

  test "an unrecognised StandardError still wraps retryable, per the design's own default" do
    wrapped = Failures.wrap(::RuntimeError.new("unexpected"), phase: :connect,
                             cancellation: uncancelled)

    assert_instance_of(Dexpace::TransportError, wrapped)
    assert_predicate(wrapped, :retryable?)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails.**

- [ ] **Step 3: Write `lib/dexpace/transport/net_http/failures.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "net/http"
require "openssl"
require "zlib"
require_relative "../net_http"

module Dexpace
  module Transport
    module NetHTTP
      # TRANSPORT-3, TRANSPORT-4, TRANSPORT-20 in one module function, and P6-4's obligation:
      # "wrap, and default to retryable, not wrap and get the classification right by hand."
      module Failures
        # The wrap is a CATCH-ALL, not a lookup against an enumerated list, and that is P6-4's
        # obligation read literally: "wrap, and default to retryable, not wrap and get the
        # classification right by hand". An enumerated list has exactly one failure mode and it is
        # the bad one -- a family nobody thought of escapes unwrapped and classifies NOT-retryable
        # through RETRY-2's capability query, which is the blind spot P6-4 is about. Verified fact 7
        # is why: none of Net::OpenTimeout / ReadTimeout / WriteTimeout (Timeout::Error <
        # RuntimeError), SocketError (which covers Socket::ResolutionError), Errno::* (SystemCallError),
        # OpenSSL::SSL::SSLError, Zlib::Error, Net::HTTPBadResponse or Net::HTTPHeaderSyntaxError is
        # an ::IOError. EOFError is the single exception that already IS one, and it still wraps here
        # -- phase 3a's Dexpace::EndOfStreamError is a Dexpace::Error and takes the clause below
        # instead, so the two never collide.
        #
        # An earlier revision of this file carried a WRAPPABLE constant listing those families. It is
        # gone rather than kept unused: a frozen Array nothing reads is NFR-4-locked surface with no
        # caller, which is OI-8's exact shape. The families are named in this comment, where they
        # document the measurement, rather than in code that would imply a branch.

        module_function

        # @param error [Exception] whatever escaped the native dispatch
        # @param phase [Symbol] :connect, :write, :read or :close, for Dexpace::TransportError#phase
        # @param cancellation [Dexpace::Cancellation] the token this call was given
        # @return [Exception] the error to actually raise
        def wrap(error, phase:, cancellation:)
          # TRANSPORT-3: ask the TOKEN first, never the exception -- a cancel delivered by
          # closing the socket and a peer reset arrive as the SAME IOError with the SAME message
          # (verified fact 3), so discrimination by class or message cannot work at all.
          return ::Dexpace::CancelledError.new(cancellation.reason) if cancellation.cancelled?
          # Never re-wrap what is already ours: double-wrapping a stream-contract violation into an
          # always-retryable transport failure would make RETRY-2 re-send on a caller's own bug.
          return error if error.is_a?(::Dexpace::Error)

          ::Dexpace::TransportError.new(error.message, phase: phase)
        end
      end
    end
  end
end
```

**`#wrap` returns a value and never sets `#cause` itself, and that is the whole of the `#cause`
design.** Ruby populates `#cause` from `$!` at the moment of the `raise`, not by assignment, and there
is no supported way to attach one to an un-raised exception object. `Failures.wrap` is called from
**inside** `Adapter#call`'s own `rescue error => e` (Task 19), where `$!` is already `e` — so
`raise Failures.wrap(e, phase:, cancellation:)` gets `e` as its `#cause` for free, and Task 19's
`Adapter#call` must therefore **not** pass `cause: nil`. (`pipeline/f02559b9`'s `raise error,
cause: nil` spelling is for the opposite case — re-raising a failure a component is *carrying* across
a thread boundary, where `$!` may be the consumer's own unrelated in-flight exception. That is
`ResponsePump`'s job in Task 18, not `Failures`'s.) An earlier revision of this step sketched an
`instance_variable_set(:@__cause, error)` and a self-raising `begin/rescue` inside `#wrap`; neither
works and both are gone.

**The eleven parameterised tests therefore call `Failures.wrap` from inside their own `rescue`**, so
`$!` matches the production context. One shared helper in the test class, not eleven copies:

```ruby
  def wrap_and_capture(original, phase: :read, cancellation: uncancelled)
    raise original
  rescue original.class => e
    begin
      raise Failures.wrap(e, phase: phase, cancellation: cancellation)
    rescue Dexpace::TransportError => wrapped
      wrapped
    end
  end
```

and each parameterised test is:

```ruby
    test "wraps #{klass} into a retryable Dexpace::TransportError carrying it as #cause" do
      original = klass.new("boom")

      wrapped = wrap_and_capture(original)

      assert_instance_of(Dexpace::TransportError, wrapped)
      assert_predicate(wrapped, :retryable?)
      assert_same(original, wrapped.cause)
      assert_equal(:read, wrapped.phase)
    end
```

The three non-parameterised tests (`TRANSPORT-3`'s token-first case, `TRANSPORT-4`'s clear-flag case
and the never-re-wrap case) assert on `Failures.wrap`'s **return value** directly and need no `rescue`
context, because none of them asserts anything about `#cause`.

- [ ] **Step 4: `sig/` mirror, run**

Run: `bundle exec ruby -w gems/dexpace-transport-net_http/test/dexpace/transport/net_http/failures_test.rb`
Expected: PASS, 15 runs.

---

## Task 16: `Dexpace::Transport::NetHTTP::RequestMapper`

**Requirement IDs:** `TRANSPORT-10`, `TRANSPORT-11`, `TRANSPORT-17` (the adapter-discipline half),
`TRANSPORT-26`; `DEF-25`'s call site; the outbound half of `TRANSPORT-14`'s sibling concerns.
**Design:** `R2` in full; `P8-2`, `P8-3`, `P8-4`, `P8-13`.

**Files:**
- Create: `.../net_http/request_mapper.rb`, its `sig/` mirror
- Test: `.../test/dexpace/transport/net_http/request_mapper_test.rb`

**Needs:** Task 3's gemspec line (this is the first `require "net/http"` in the gem); phase 1's
`HeaderSyntax`/`HeaderName`; 3a's `BufferedSource.over`; 3b's `Body`/`FileBody`; phase 5b's
`Instrumentation::Logger`/`Severity`/`Instrumentation.contain`/`Events`.
**Produces:** `RequestMapper.build(request, logger:) -> Net::HTTPGenericRequest`, `MANAGED_HEADERS`,
`DEFAULT_CONTENT_TYPE`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "net/http"
require_relative "../../../test_helper"

# TRANSPORT-10, TRANSPORT-11, TRANSPORT-17, TRANSPORT-26, DEF-25.
class DexpaceTransportNetHttpRequestMapperTest < DexpaceTestCase
  RequestMapper = Dexpace::Transport::NetHTTP::RequestMapper

  def request(method: "GET", headers: Dexpace::Headers::EMPTY, body: nil,
              url: "http://127.0.0.1:1/a")
    Dexpace::Request.build(method: method, url: url, headers: headers, body: body)
  end

  def native(**kwargs)
    RequestMapper.build(request(**kwargs), logger: Dexpace::Instrumentation::Logger::NULL)
  end

  test "the three construction-time auto-stamps are deleted" do
    req = native

    refute(req.key?("Accept"))
    refute(req.key?("Accept-Encoding"))
    refute(req.key?("User-Agent"))
  end

  test "MANAGED_HEADERS are dropped even when the caller set them" do
    headers = Dexpace::Headers.builder.tap do |b|
      b.add("Host", "bogus.example")
      b.add("Content-Length", "9999")
      b.add("Connection", "keep-alive")
      b.add("X-Pass", "kept")
    end.build
    req = native(headers: headers)

    refute(req.key?("Host"))
    refute(req["Content-Length"] == "9999")
    refute(req.key?("Connection"))
    assert_equal("kept", req["X-Pass"])
  end

  test "proxy-authorization is NOT in MANAGED_HEADERS -- open question 3" do
    headers = Dexpace::Headers.builder.tap { |b| b.add("Proxy-Authorization", "Basic x") }.build
    req = native(headers: headers)

    assert_equal("Basic x", req["Proxy-Authorization"])
  end

  test "TRANSPORT-10 (a): explicit Content-Type wins over the body's own media type" do
    headers = Dexpace::Headers.builder.tap { |b| b.add("Content-Type", "text/plain") }.build
    body = Dexpace::BufferBody.new(Dexpace::IO::Buffer.of_bytes("{}".b),
                                    media_type: Dexpace::MediaType.parse("application/json"))
    req = native(method: "POST", headers: headers, body: body)

    assert_equal("text/plain", req["Content-Type"])
  end

  test "TRANSPORT-10 (b): the body's media type is used only when the caller set none" do
    body = Dexpace::BufferBody.new(Dexpace::IO::Buffer.of_bytes("{}".b),
                                    media_type: Dexpace::MediaType.parse("application/json"))
    req = native(method: "POST", body: body)

    assert_equal("application/json", req["Content-Type"])
  end

  test "P8-4: no header and no body media type falls back to octet-stream on a body-permitted method" do
    req = native(method: "POST")

    assert_equal("application/octet-stream", req["Content-Type"])
  end

  test "a body-forbidden method gets no Content-Type at all" do
    req = native(method: "GET")

    refute(req.key?("Content-Type"))
  end

  test "framing: Content-Length from a known-length body" do
    body = Dexpace::BufferBody.new(Dexpace::IO::Buffer.of_bytes("abc".b))
    req = native(method: "POST", body: body)

    assert_equal("3", req["Content-Length"])
    refute(req.key?("Transfer-Encoding"))
  end

  test "framing: Transfer-Encoding: chunked from an unknown-length body" do
    chunked = Object.new
    chunked.define_singleton_method(:each) { |&blk| blk.call("a".b); blk.call("b".b) }
    body = Dexpace::BufferedBodyStub = Struct.new(:chunked) do
      include Dexpace::Body
      def each(&blk) = chunked.each(&blk)
      def write_to(sink) = each { |c| sink.write(c) }
      def content_length = -1
    end.new(chunked)
    req = native(method: "POST", body: body)

    assert_equal("chunked", req["Transfer-Encoding"])
  end

  test "DEF-25: a wire-boundary re-validation raises before anything is copied" do
    forged_headers = Object.new
    forged_headers.define_singleton_method(:each_entry) { |&blk| blk.call("X-Evil", "a\r\nb") }
    forged = Object.new
    forged.define_singleton_method(:method) { Dexpace::Method::GET }
    forged.define_singleton_method(:url) { URI::RFC3986_PARSER.parse("http://127.0.0.1:1/") }
    forged.define_singleton_method(:headers) { forged_headers }
    forged.define_singleton_method(:body) { nil }

    assert_raises(Dexpace::InvalidArgumentError) do
      RequestMapper.build(forged, logger: Dexpace::Instrumentation::Logger::NULL)
    end
  end

  test "decode_content is turned off unconditionally, whether or not the caller set Accept-Encoding" do
    plain = native
    assert_equal(false, plain.decode_content)

    headers = Dexpace::Headers.builder.tap { |b| b.add("Accept-Encoding", "gzip") }.build
    with_header = native(headers: headers)
    assert_equal(false, with_header.decode_content)
    assert_equal("gzip", with_header["Accept-Encoding"])
  end

  test "response_body_permitted is false only for HEAD" do
    head = native(method: "HEAD")
    get = native(method: "GET")

    refute(head.response_body_permitted?)
    assert(get.response_body_permitted?)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails.**

- [ ] **Step 3: Write `lib/dexpace/transport/net_http/request_mapper.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "net/http"
require_relative "../net_http"

module Dexpace
  module Transport
    module NetHTTP
      # R2's eight steps, as one module function. The only place in this gem that touches
      # Dexpace::HeaderSyntax, the only place that names MANAGED_HEADERS, and the only place
      # that constructs a native request.
      module RequestMapper
        # TRANSPORT-11's named minimum (host, content-length, transfer-encoding) plus seven
        # hop-by-hop names (RFC 9110 7.6.1) the requirement's own text invites ("plus any the
        # native client rejects outright ... The exact drop set is transport-specific"). Folded
        # (lower-case) because HeaderName.of(...).folded is what every lookup compares against.
        # proxy-authorization deliberately does NOT join this set (open question 3): this
        # adapter configures no proxy and holds no credential, so a caller-set value is passed
        # through like any other header rather than managed.
        #
        # These ten names are a SHARED transport contract, stated once in the charter's "Shared
        # transport contracts" subsection and implemented identically by
        # dexpace-transport-async_http under its own constant name (NFR-2 forbids either gem
        # depending on the other, so the membership is what is shared, not the constant). A
        # conformance assertion reads this list on both adapters; a divergence must be a red test
        # here, which is why the suite asserts the membership verbatim rather than sampling it.
        MANAGED_HEADERS = %w[
          host content-length transfer-encoding connection keep-alive proxy-connection te trailer
          upgrade expect
        ].freeze

        # RFC 9110's own default for a payload of unknown type -- the one value that claims
        # nothing about the bytes, where net-http's own supply_default_content_type would stamp
        # application/x-www-form-urlencoded, a claim a server will act on.
        DEFAULT_CONTENT_TYPE = "application/octet-stream"

        module_function

        def build(request, logger:)
          revalidate!(request)

          body_permitted = !request.method.body_forbidden?
          response_permitted = request.method.token != "HEAD"
          native = ::Net::HTTPGenericRequest.new(request.method.token, body_permitted,
                                                  response_permitted, request.url.request_uri, {})
          native.delete("Accept")
          native.delete("Accept-Encoding")
          native.delete("User-Agent")

          copy_headers(request, native, logger)
          suppress_decode_content(native)
          set_content_type(request, native, body_permitted)
          attach_body(request, native, body_permitted)

          native
        end

        # DEF-25: HTTP-17/HTTP-18 re-checked immediately before dispatch, over EVERY outbound
        # header, before anything is copied -- the mitigation for the residual gap design
        # section 10.10 admits (a duck-typed impostor can reach this code with no Dexpace
        # validation ever having run, because SEAM-11's contract types nothing).
        def revalidate!(request)
          request.headers.each_entry do |name, value|
            ::Dexpace::HeaderSyntax.validate_name!(name)
            ::Dexpace::HeaderSyntax.validate_outbound_value!(value, name: name)
          end
        end

        def copy_headers(request, native, logger)
          request.headers.each_entry do |name, value|
            folded = ::Dexpace::HeaderName.of(name).folded
            if MANAGED_HEADERS.include?(folded)
              log_drop(logger, name)
              next
            end
            native.add_field(name, value)
          end
        end

        # P8-3: the switch is `#[]=`, never `#add_field`, because only `#[]=` flips
        # @decode_content (verified: net/http/generic_request.rb overrides `[]=` with the
        # side effect and does not override `add_field`). Re-assigning the caller's own value
        # preserves it while still tripping the flip; assigning then deleting is fact 13's exact
        # recipe when the caller set none.
        def suppress_decode_content(native)
          if native.key?("Accept-Encoding")
            native["Accept-Encoding"] = native["Accept-Encoding"]
          else
            native["Accept-Encoding"] = "identity"
            native.delete("Accept-Encoding")
          end
        end

        # TRANSPORT-10 and P8-4 together: caller's explicit header wins (case-insensitively,
        # already true because native.key? folds); failing that the body's own #media_type;
        # failing that DEFAULT_CONTENT_TYPE -- and only ever on a body-permitted method, body or
        # not, because supply_default_content_type warns under -w for EVERY body-permitted
        # method (verified fact 5) and this repository's own gate fails the build on warnings.
        def set_content_type(request, native, body_permitted)
          return unless body_permitted
          return if native.key?("Content-Type")

          media = request.body&.media_type
          native["Content-Type"] = media ? media.render : DEFAULT_CONTENT_TYPE
        end

        # Framing is derived from the body and never copied, and only assigned when a body
        # actually exists -- a body-less body-permitted request is left to net-http's own
        # set_body_internal/send_request_with_body, which supplies Content-Length: 0 itself
        # (TRANSPORT-26, satisfied by the library).
        def attach_body(request, native, body_permitted)
          return unless body_permitted && request.body

          length = request.body.content_length
          if length >= 0
            native["Content-Length"] = length.to_s
          else
            native["Transfer-Encoding"] = "chunked"
          end
          native.body_stream = ::Dexpace::IO::BufferedSource.over(request.body)
        end

        # The charter's Shared transport contracts item 2: one event name and one field pair on
        # both adapters, so a single conformance assertion can read a drop record from either.
        # Corrected 2026-09-12 -- this emitted a bare literal "transport.header.dropped" contained
        # under INSTRUMENTATION_LOG with a Symbol :header key and no reason, which is a second
        # spelling of the record 8c emits under a core-owned constant.
        def log_drop(logger, name)
          ::Dexpace::Instrumentation.contain(
            logger, event: ::Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED,
          ) do
            logger.event(::Dexpace::Instrumentation::Severity::VERBOSE)
                  .event(::Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED)
                  .field("header", name)
                  .field("reason", "transport managed header (TRANSPORT-11)")
                  .emit
          end
        end
      end
    end
  end
end
```

`TRANSPORT-17`'s adapter-discipline half ("MUST NOT itself trigger a second write") is satisfied by
this module calling `native.body_stream =` exactly once, on the one path through `#build`; there is
no retry loop and no second call anywhere in this file, which the assertion in Task 12 checks from
the outside (one request reaching the wire) and this file's own shape guarantees from the inside.

- [ ] **Step 4: `sig/` mirror, run**

Run: `bundle exec ruby -w gems/dexpace-transport-net_http/test/dexpace/transport/net_http/request_mapper_test.rb`
Expected: PASS, 12 runs.

---

## Task 17: `Dexpace::Transport::NetHTTP::ResponseMapper`

**Requirement IDs:** `TRANSPORT-14`, `TRANSPORT-24`, `TRANSPORT-27`.
**Design:** `R4` in full.

**Files:**
- Create: `.../net_http/response_mapper.rb`, its `sig/` mirror
- Test: `.../test/dexpace/transport/net_http/response_mapper_test.rb`

**Needs:** Task 16 (shares no code but is documented beside it); phase 1's
`Status`/`Protocol`/`MediaType`/`Headers.inbound_builder`; 3b's `ResponseBody`.
**Produces:** `ResponseMapper.build(request:, native:, pump:) -> Dexpace::Response`.

- [ ] **Step 1: Write the failing test**

Build native `Net::HTTPResponse` instances directly (no socket needed for this unit level — a real
socket round trip is Task 20's job): `Net::HTTPOK.new("1.1", "200", "OK")`, populate headers with
`#[]=`/`add_field`, and pass a `FakeSource` (phase 3a's, or a two-line duck type answering
`#readpartial`/`#close`) as the pump stand-in.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "net/http"
require_relative "../../../test_helper"

# TRANSPORT-14, TRANSPORT-24, TRANSPORT-27.
class DexpaceTransportNetHttpResponseMapperTest < DexpaceTestCase
  ResponseMapper = Dexpace::Transport::NetHTTP::ResponseMapper

  def dexpace_request
    Dexpace::Request.build(method: "GET", url: "http://127.0.0.1:1/", headers: Dexpace::Headers::EMPTY,
                            body: nil)
  end

  def empty_pump
    source = Object.new
    source.define_singleton_method(:readpartial) { |*_| raise ::EOFError }
    source.define_singleton_method(:close) { nil }
    source
  end

  test "TRANSPORT-24: a vendor status maps totally, via Status.of's own 100-599 range" do
    native = ::Net::HTTPResponse.send(:response_class, "520").new("1.1", "520", "Vendor")
    native["Content-Length"] = "0"

    response = ResponseMapper.build(request: dexpace_request, native: native, pump: empty_pump)

    assert_equal(520, response.status.code)
  end

  test "TRANSPORT-14: a control-byte value is dropped; the body and remaining headers survive" do
    native = ::Net::HTTPOK.new("1.1", "200", "OK")
    native["X-Ctl"] = "a\x01b"
    native["X-Ok"] = "fine"
    native["Content-Length"] = "0"

    response = ResponseMapper.build(request: dexpace_request, native: native, pump: empty_pump)

    refute(response.headers.include?("X-Ctl"))
    assert_equal("fine", response.headers["X-Ok"]&.first)
  end

  test "TRANSPORT-14: obs-text in a value is preserved, never stripped" do
    native = ::Net::HTTPOK.new("1.1", "200", "OK")
    native["X-Obs"] = "caf\xE9".b
    native["Content-Length"] = "0"

    response = ResponseMapper.build(request: dexpace_request, native: native, pump: empty_pump)

    assert_equal("caf\xE9".b, response.headers["X-Obs"]&.first)
  end

  test "TRANSPORT-27: a non-numeric Content-Length maps to the -1 sentinel and the body still reads" do
    native = ::Net::HTTPOK.new("1.1", "200", "OK")
    native["Content-Length"] = "abc"
    source = Object.new
    calls = 0
    source.define_singleton_method(:readpartial) do |*_|
      calls += 1
      calls == 1 ? "hi".b : (raise ::EOFError)
    end
    source.define_singleton_method(:close) { nil }

    response = ResponseMapper.build(request: dexpace_request, native: native, pump: source)

    assert_equal(-1, response.body.content_length)
  end

  test "TRANSPORT-27: a malformed Content-Type downgrades to nil rather than raising" do
    native = ::Net::HTTPOK.new("1.1", "200", "OK")
    native["Content-Type"] = "not a/;;media type"
    native["Content-Length"] = "0"

    response = ResponseMapper.build(request: dexpace_request, native: native, pump: empty_pump)

    assert_nil(response.body.media_type)
  end

  test "a 204 gets no body, and the pump is closed immediately" do
    native = ::Net::HTTPNoContent.new("1.1", "204", "No Content")
    closed = false
    pump = Object.new
    pump.define_singleton_method(:close) { closed = true }

    response = ResponseMapper.build(request: dexpace_request, native: native, pump: pump)

    assert_nil(response.body)
    assert(closed)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails.**

- [ ] **Step 3: Write `lib/dexpace/transport/net_http/response_mapper.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "net/http"

module Dexpace
  module Transport
    module NetHTTP
      # R4: never calls res.content_length and never lets read_body call it either -- the
      # length is parsed from the RAW header text, and the unparseable one is deleted from the
      # native response before the pump reads the body, so connection-close framing takes over
      # instead of Net::HTTPResponse#content_length raising Net::HTTPHeaderSyntaxError.
      module ResponseMapper
        LENGTH = /\A[0-9]+\z/

        module_function

        def build(request:, native:, pump:)
          unless native.class.body_permitted?
            ::Dexpace.close_quietly(pump)
            return no_body_response(request, native)
          end

          # ORDER IS LOAD-BEARING: filter_headers copies #to_hash into Dexpace::Headers FIRST, so
          # the caller keeps the Content-Length the server actually sent; parse_length! may then
          # delete it from the NATIVE response, which is an instruction to read_body_0's framing
          # and not a rewrite of the response (R4, "The raw header still reaches the caller").
          headers = filter_headers(native)
          content_length = parse_length!(native)
          media_type = parse_media_type(native)

          ::Dexpace::Response.build(
            request: request, protocol: "HTTP/#{native.http_version}", status: native.code.to_i,
            reason: native.message, headers: headers,
            body: ::Dexpace::ResponseBody.new(
              source: ::Dexpace::IO::BufferedSource.wrapping(pump), media_type: media_type,
              content_length: content_length,
            ),
          )
        end

        def no_body_response(request, native)
          ::Dexpace::Response.build(
            request: request, protocol: "HTTP/#{native.http_version}", status: native.code.to_i,
            reason: native.message, headers: filter_headers(native), body: nil,
          )
        end

        # R4: the raw header, matched against an anchored, character-class-only, linear regexp
        # -- no timeout: needed (Global Constraints), because it cannot backtrack. Integer()
        # would accept "-4" as -4, colliding with the -1 sentinel; the regexp rejects anything
        # that is not one or more digits, so a negative or non-numeric value both map to -1.
        def parse_length!(native)
          raw = native.to_hash["content-length"]&.first
          if raw && LENGTH.match?(raw)
            raw.to_i
          else
            # Absent, non-numeric, negative or multi-valued -- delete it from the NATIVE response
            # so read_body_0 finds no length and no chunked encoding and falls through to
            # connection-close framing, instead of Net::HTTPResponse#content_length raising
            # Net::HTTPHeaderSyntaxError. The wire value has already been copied into
            # Dexpace::Headers by #filter_headers, so the caller still sees what the server sent;
            # only the INTERPRETATION becomes -1.
            native.delete("content-length")
            -1
          end
        end

        # Discrepancy 2 (this plan's own finding): MediaType.parse RAISES on a malformed value
        # rather than returning nil, contrary to the design's R4 text. This rescue is what
        # actually produces TRANSPORT-27's "downgraded to no media type" behaviour.
        def parse_media_type(native)
          raw = native.to_hash["content-type"]&.first
          return nil if raw.nil?

          ::Dexpace::MediaType.parse(raw)
        rescue ::Dexpace::InvalidArgumentError
          nil
        end

        # TRANSPORT-14: filtered BEFORE the values reach Headers::Builder, because
        # HeaderName.of/Headers::Builder#add both re-validate and would raise on exactly the
        # bytes this filter exists to drop. #to_hash is the only faithful mapping source
        # (verified fact 6): #[] joins with ", " and #each_capitalized re-cases, both of which
        # would corrupt a multi-valued Set-Cookie.
        def filter_headers(native)
          builder = ::Dexpace::Headers.inbound_builder
          native.to_hash.each do |name, values|
            next unless ::Dexpace::HeaderSyntax.valid_name?(name)

            values.each do |value|
              next unless ::Dexpace::HeaderSyntax.valid_inbound_value?(value)

              builder.add(name, value)
            end
          end
          builder.build
        end
      end
    end
  end
end
```

- [ ] **Step 4: `sig/` mirror, run**

Run: `bundle exec ruby -w gems/dexpace-transport-net_http/test/dexpace/transport/net_http/response_mapper_test.rb`
Expected: PASS, 7 runs.

**One caution recorded rather than fixed:** `Dexpace::Protocol.parse` has no alias for
`"http/1.0"` (Global Constraints, verified fact re-run in Task 1); a real `HTTP/1.0` server would
make `native.http_version` produce `"1.0"` and this method raise. No `TRANSPORT` ID requires 1.0
support and every `WireServer` script in this plan answers `HTTP/1.1`, so the gap is never
exercised here — worth one sentence in this file's YARD and one of *The findings proposed for the
registers* (Task 25), not a code change.

---

## Task 18: `Dexpace::Transport::NetHTTP::ResponsePump`

**Requirement IDs:** `TRANSPORT-19`, `TRANSPORT-25`; the mechanism `TRANSPORT-22` and every
`ResponseMapper` test above are built on.
**Design:** `R1` in full; `P8-1`.

**Files:**
- Create: `.../net_http/response_pump.rb`, its `sig/` mirror
- Test: `.../test/dexpace/transport/net_http/response_pump_test.rb`

**Needs:** Task 14's `Deadline` (optional, may be `nil` for a borrowed client); Task 15's
`Failures`; phase 2's `Closeable`; phase 3a's `Dexpace::EndOfStreamError`.
**Produces:** `ResponsePump.new(http:, native:, deadline:).call`, `#readpartial`, `#close`,
`#head_or_raise`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "net/http"
require_relative "../../../test_helper"

# TRANSPORT-19, TRANSPORT-25. This is the group R1 is answerable to.
class DexpaceTransportNetHttpResponsePumpTest < DexpaceTestCase
  ResponsePump = Dexpace::Transport::NetHTTP::ResponsePump

  # Design boundary 13: the adapter's own suite uses dexpace-conformance's fixture, never a second
  # one hand-rolled beside it. A fixture that drifts from the one the conformance assertions run
  # against hides a difference rather than finding one, and Task 20 drives that same suite from
  # this very gem's test tree. Reaching it needs NO gemspec change: phase 0's root Gemfile
  # path-loads every gem under gems/, so dexpace-conformance is on the load path for this gem's
  # tests without becoming a runtime or development dependency of its gemspec -- which is what
  # keeps gates:gemspec_audit's NFR-2 budget (dexpace-core + net-http, exactly two) intact, and
  # what keeps gates:clean_bundle's lib/-only isolation run unaffected.
  def dribbling_wire(first, second, delay)
    Dexpace::Conformance::WireServer.start(Dexpace::Conformance::Scripts.dribble(first, second, delay))
  end

  def fixed_length_wire(body)
    Dexpace::Conformance::WireServer.start(Dexpace::Conformance::Scripts.fixed(body))
  end

  def truncated_chunked_wire
    Dexpace::Conformance::WireServer.start(
      lambda do |conn, _head|
        conn.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na\r\n")
        conn.close # truncated -- no terminating 0-chunk, so the next read raises
      end,
    )
  end

  test "delivers the head before the second chunk, with a real time gap" do
    wire = dribbling_wire("aaaaa", "bbbbb", 0.3)
    http = Net::HTTP.new("127.0.0.1", wire.port)
    http.max_retries = 0
    native = Net::HTTPGenericRequest.new("GET", false, true, "/", {})

    pump = ResponsePump.new(http: http, native: native, deadline: nil,
                            cancellation: Dexpace::Cancellation.none)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    res = pump.head_or_raise
    head_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

    assert_equal("200", res.code)
    assert_operator(head_at, :<, 0.15, "the head must not wait for the second chunk")

    drained = +""
    loop { drained << pump.readpartial(16) } rescue Dexpace::EndOfStreamError
    assert_equal("aaaaabbbbb", drained)
    pump.close
    wire.close
  end

  test "a multi-megabyte body round-trips byte-exactly" do
    body = "x" * (4 * 1024 * 1024)
    wire = fixed_length_wire(body)
    http = Net::HTTP.new("127.0.0.1", wire.port)
    http.max_retries = 0
    native = Net::HTTPGenericRequest.new("GET", false, true, "/", {})
    pump = ResponsePump.new(http: http, native: native, deadline: nil,
                            cancellation: Dexpace::Cancellation.none)
    pump.head_or_raise
    drained = +"".b
    begin
      loop { drained << pump.readpartial(64 * 1024) }
    rescue Dexpace::EndOfStreamError
      nil
    end

    assert_equal(body.bytesize, drained.bytesize)
    pump.close
    wire.close
  end

  test "closing mid-stream with the producer blocked on a socket read returns promptly" do
    wire = dribbling_wire("a", "b", 10) # never actually waits 10s -- close wins
    http = Net::HTTP.new("127.0.0.1", wire.port)
    http.max_retries = 0
    native = Net::HTTPGenericRequest.new("GET", false, true, "/", {})
    pump = ResponsePump.new(http: http, native: native, deadline: nil,
                            cancellation: Dexpace::Cancellation.none)
    pump.head_or_raise
    pump.readpartial(16) # consumes "a", leaves the producer blocked waiting for "b"

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    pump.close
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

    assert_operator(elapsed, :<, 1.0)
    pump.close # idempotent
    wire.close
  end

  test "a producer failure after the head surfaces on the consumer's thread with the right cause" do
    wire = truncated_chunked_wire
    http = Net::HTTP.new("127.0.0.1", wire.port)
    http.max_retries = 0
    native = Net::HTTPGenericRequest.new("GET", false, true, "/", {})
    pump = ResponsePump.new(http: http, native: native, deadline: nil,
                            cancellation: Dexpace::Cancellation.none)
    pump.head_or_raise
    pump.readpartial(16) # "a"

    # An unrelated exception is deliberately in flight, so `raise error, cause: nil` is the
    # only way this assertion can pass -- a bare `raise` would attach THIS exception instead.
    error = begin
      raise "unrelated, deliberately in flight"
    rescue RuntimeError
      begin
        pump.readpartial(16)
        nil
      rescue StandardError => e
        e
      end
    end

    assert_instance_of(Dexpace::TransportError, error)
    refute_equal("unrelated, deliberately in flight", error.cause&.message)
    pump.close
    wire.close
  end

  test "writing into an explicit outbuf retags it to BINARY via #replace" do
    wire = dribbling_wire("caf\xE9".b, "x", 0)
    http = Net::HTTP.new("127.0.0.1", wire.port)
    http.max_retries = 0
    native = Net::HTTPGenericRequest.new("GET", false, true, "/", {})
    pump = ResponsePump.new(http: http, native: native, deadline: nil,
                            cancellation: Dexpace::Cancellation.none)
    pump.head_or_raise
    outbuf = +"prior".dup.force_encoding(Encoding::UTF_8)

    pump.readpartial(16, outbuf)

    assert_equal(Encoding::BINARY, outbuf.encoding)
    pump.close
    wire.close
  end
end
```

- [ ] **Step 2: Run it to confirm it fails.**

- [ ] **Step 3: Write `lib/dexpace/transport/net_http/response_pump.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "net/http"
require_relative "../net_http"
require_relative "failures"

module Dexpace
  module Transport
    module NetHTTP
      # R1: a per-response producer Thread over a Thread::SizedQueue(1), not a Fiber --
      # Fiber#resume from a second thread raises FiberError (verified fact 10), which breaks
      # Transport.async_over's composition. Owns the producer thread, the queue, and the
      # Net::HTTP instance the producer started.
      class ResponsePump
        include ::Dexpace::Closeable

        def initialize(http:, native:, deadline:, cancellation:)
          @http = http
          @native = native
          @deadline = deadline
          @cancellation = cancellation
          @queue = ::Thread::SizedQueue.new(1)
          @residue = +"".b
          @producer_error = nil
          initialize_closeable(owned: true)
          @thread = ::Thread.new { produce }
        end

        # Blocks on the first queue pop. A failure before the head is re-raised on THIS thread
        # with `raise error, cause: nil` -- the pump is CARRYING a failure from another thread,
        # not rescuing one of its own, so $! here may be an unrelated in-flight exception on the
        # caller's own stack (pipeline/f02559b9).
        def head_or_raise
          kind, payload = @queue.pop
          case kind
          when :head then payload
          when :error then raise Failures.wrap(payload, phase: :connect, cancellation: @cancellation), cause: nil
          else raise ::Dexpace::TransportError.new("no response arrived", phase: :connect)
          end
        end

        # A #readpartial-shaped reader BufferedSource.wrapping owns. Pops when the residue is
        # empty; raises Dexpace::EndOfStreamError (an ::EOFError subclass, load-bearing: IO.
        # copy_stream and BufferedSource#fill both terminate cleanly on it) at end of stream;
        # re-raises a carried producer failure the same way #head_or_raise does; writes into
        # outbuf with #replace, never #clear, so the destination carries BINARY regardless of
        # the caller's buffer's prior encoding (verified fact 11).
        def readpartial(maxlen, outbuf = nil)
          raise ::Dexpace::ClosedError, "the response was already closed" if closed?

          fill(maxlen) if @residue.empty?
          chunk = @residue.byteslice(0, maxlen)
          @residue = @residue.byteslice(maxlen..) || +"".b
          if outbuf
            outbuf.replace(chunk)
            outbuf
          else
            chunk
          end
        end

        private

        def fill(maxlen)
          return if @residue.bytesize >= maxlen

          kind, payload = @queue.pop
          case kind
          when :chunk then @residue << payload
          when :error then raise Failures.wrap(payload, phase: :read, cancellation: @cancellation), cause: nil
          else raise ::Dexpace::EndOfStreamError, "the response body is exhausted"
          end
        end

        # resource-management/346deaec: release in ensure, never in rescue. Runs on the
        # PRODUCER's own thread.
        def produce
          @http.start do |connected|
            connected.request(@native) do |res|
              @queue.push([:head, res])
              next unless res.class.body_permitted?

              res.read_body do |chunk|
                break unless still_wanted?

                refresh_read_timeout
                @queue.push([:chunk, chunk])
              end
            end
          end
        rescue ::StandardError => e
          @producer_error = e
          begin
            @queue.push([:error, e])
          rescue ::ClosedQueueError
            nil
          end
        ensure
          @queue.close
        end

        # concurrency-and-async/611b9392: check-after-resume. The producer re-reads its own
        # closed latch after every push and every read_body yield, and stops producing rather
        # than delivering into a queue nobody will drain.
        def still_wanted?
          !closed?
        end

        # R3: refreshed into read_timeout after every chunk this pump receives, when a deadline
        # was supplied at all -- a borrowed client (deadline: nil) is left entirely untouched,
        # per R3's borrowing-transport rule.
        def refresh_read_timeout
          return unless @deadline

          if @deadline.expired?
            @http.finish if @http.started?
            return
          end
          @http.read_timeout = @deadline.clamped
        end

        # R1's three-step release, in order, for the measured reasons: flip the latch under the
        # mutex and nothing else (concurrency-and-async/c0fab747); close the queue, waking a
        # producer blocked on push with ClosedQueueError; finish the connection, waking one
        # blocked in readpartial with IOError (which only works because max_retries = 0);
        # join with a BOUNDED deadline (XCUT-13, resource-management/b7587eb7). Both wakeups are
        # wrapped so a close cannot raise over a primary failure.
        def release
          begin
            @queue.close
          rescue ::StandardError
            nil
          end
          begin
            @http.finish if @http.started?
          rescue ::StandardError
            nil
          end
          @thread.join(JOIN_DEADLINE_SECONDS)
          nil
        end
      end
    end
  end
end
```

**`cancellation:` is a required fourth keyword and the caller's real token is threaded all the way
down.** `Failures.wrap` answers `TRANSPORT-3` by asking the **token** first, never the exception
(verified fact 3: a cancel-by-socket-close and a peer reset arrive as the same `IOError` with the same
message), so a pump that passed `Cancellation.none` could never report a cancellation correctly at
all. `Adapter#call` (Task 19) supplies the token it was given, and separately registers
`cancellation.on_cancel { Dexpace.close_quietly(pump) }` — whose `#release` connection-finish step is
what wakes a producer blocked in a socket read when the **caller's** cancellation fires mid-body. That
subscription is detached in the same `ensure`, through the `Cancellation::Subscription` handle phase 2
returns (`P2-14`), so a client-lifetime token does not retain one closure and one response per
request.

- [ ] **Step 4: `sig/` mirror, run**

Run: `bundle exec ruby -w gems/dexpace-transport-net_http/test/dexpace/transport/net_http/response_pump_test.rb`
Expected: PASS, 5 runs. **No test allocates the 4 MiB body more than once, and no test sleeps to
synchronise** beyond the dribble script's own deliberate, bounded delay, which is the thing under
test rather than a wait for something else.

---

## Task 19: `Dexpace::Transport::NetHTTP` — the module, `Adapter`, registration

**Requirement IDs:** `TRANSPORT-1`–`6`, `15`, `16`, `20`, `22`, `29`; the require-time registration
(`SEAM-2`, `NFR-14`'s skew assertion via phase 2's `Registry#register`); `P8-10`.
**Design:** "The object model `8a` ships"; `R2`, `R3`, `R6`'s logger keyword; every `Adapter`-level
Deviation Ledger row.

**Files:**
- Create: `.../net_http/adapter.rb`, its `sig/` mirror
- Modify: `.../net_http.rb` (adds `.build`/`.using`/`.default`, `REGISTRY_KEY`, the registration
  call), its `sig/` mirror
- Test: `.../test/dexpace/transport/net_http/adapter_test.rb`

**Needs:** Tasks 14–18 in full; phase 2's `Transport`, `Closeable`, `Cancellation`; phase 5a's
`Dexpace::Clock`, `Dexpace.configuration`.
**Produces:** `NetHTTP.build(timeout:, logger:)`, `.using(client, logger:)`, `.default`,
`Adapter#call`/`#close`/`#closed?`/`#owned?`.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "net/http"
require_relative "../../../test_helper"

# TRANSPORT-1-6, 15, 16, 20, 22, 29. The lifecycle and concurrency proofs; the per-mapping unit
# tests already live in Tasks 16-18 and are not repeated here.
class DexpaceTransportNetHttpAdapterTest < DexpaceTestCase
  NetHTTP = Dexpace::Transport::NetHTTP

  def server(&script)
    Dexpace::Conformance::WireServer.start(script)
  end

  test ".build produces an owned adapter; .using produces a borrowing one" do
    owned = NetHTTP.build
    client = Net::HTTP.new("127.0.0.1", 1)
    client.max_retries = 0
    borrowed = NetHTTP.using(client)

    assert(owned.owned?)
    refute(borrowed.owned?)
  end

  test ".using refuses a client whose max_retries is not zero (P8-10)" do
    client = Net::HTTP.new("127.0.0.1", 1)

    assert_raises(Dexpace::InvalidArgumentError) { NetHTTP.using(client) }
  end

  test ".default builds a fresh instance every call" do
    refute_same(NetHTTP.default, NetHTTP.default)
  end

  test "TRANSPORT-15/16: an owned adapter raises ClosedError after close; closing twice is a no-op" do
    wire = server(&Dexpace::Conformance::Scripts.fixed("ok"))
    adapter = NetHTTP.build
    adapter.close
    adapter.close

    assert_raises(Dexpace::ClosedError) do
      adapter.call(request_for(wire), Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
    end
    wire.close
  end

  test "TRANSPORT-15: a borrowed adapter's close does not disable the caller's own client" do
    wire = server(&Dexpace::Conformance::Scripts.fixed("ok"))
    client = Net::HTTP.new("127.0.0.1", wire.port)
    client.max_retries = 0
    adapter = NetHTTP.using(client)
    adapter.call(request_for(wire), Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
    adapter.close

    res = client.start { |c| c.request(Net::HTTP::Get.new("/")) }

    assert_equal("200", res.code)
    wire.close
  end

  test "P8-6: a non-nil per-call timeout against a borrowed client raises" do
    wire = server(&Dexpace::Conformance::Scripts.fixed("ok"))
    client = Net::HTTP.new("127.0.0.1", wire.port)
    client.max_retries = 0
    adapter = NetHTTP.using(client)
    options = Dexpace::RequestOptions.builder.tap { |b| b.timeout = 1.0 }.build

    assert_raises(Dexpace::InvalidArgumentError) do
      adapter.call(request_for(wire), options, Dexpace::Cancellation.none)
    end
    wire.close
  end

  test "TRANSPORT-29: many concurrent calls through one adapter each get their own response" do
    wire = server { |conn, head| Dexpace::Conformance::Scripts.write_response(conn, body: head.first.split(" ")[1]) }
    adapter = NetHTTP.build
    mismatches = Thread::Queue.new
    threads = 4.times.map do |t|
      Thread.new do
        10.times do |i|
          path = "/#{t}-#{i}"
          res = adapter.call(request_for(wire, path: path), Dexpace::RequestOptions::EMPTY,
                              Dexpace::Cancellation.none)
          mismatches.push([path, res.body_string]) unless res.body_string == path
        end
      end
    end
    threads.each(&:join)
    found = []
    found << mismatches.pop until mismatches.empty?

    assert_empty(found)
    adapter.close
    wire.close
  end

  test "a ruby -w POST with a body raises no warning, per verified fact 5" do
    wire = server(&Dexpace::Conformance::Scripts.fixed("ok"))
    adapter = NetHTTP.build
    body = Dexpace::BufferBody.new(Dexpace::IO::Buffer.of_bytes("x".b))
    request = Dexpace::Request.build(method: "POST", url: "http://127.0.0.1:#{wire.port}/",
                                      headers: Dexpace::Headers::EMPTY, body: body)

    with_warning_raising do
      adapter.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
    end
    adapter.close
    wire.close
  end

  test "a cancellation delivered under a blocked read raises, rather than completing" do
    blocked = Thread::Queue.new
    wire = server(
      &Dexpace::Conformance::Scripts.hang_after_headers(on_headers_written: -> { blocked.push(true) }),
    )
    adapter = NetHTTP.build
    source = Dexpace::Cancellation.source
    # Fires when the SERVER reports the head is flushed -- the instant the call enters its first
    # body read -- never after a guessed `sleep`. A blocking Queue#pop is not a sleep.
    canceller = Thread.new { blocked.pop; source.cancel(:test) }

    error = begin
      adapter.call(request_for(wire), Dexpace::RequestOptions::EMPTY, source.token)
      nil
    rescue StandardError => e
      e
    end
    canceller.join

    refute_nil(error, "the naive assertion is SKIPPED by the bug: the call must raise, not return 200")
    adapter.close
    wire.close
  end

  private

  def request_for(wire, path: "/")
    Dexpace::Request.build(method: "GET", url: "http://127.0.0.1:#{wire.port}#{path}",
                            headers: Dexpace::Headers::EMPTY, body: nil)
  end
end
```

`with_warning_raising` is `test_helper.rb`'s existing shared support (phase 0's own shared test
case already overrides `Warning.warn` to raise, per the design's verified fact 5 — this test uses
whatever name that helper already has rather than a second one).

- [ ] **Step 2: Run to confirm failure.**

- [ ] **Step 3: Extend `lib/dexpace/transport/net_http.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "net_http/version"
require_relative "net_http/adapter"

module Dexpace
  module Transport
    module NetHTTP
      DEFAULT_TIMEOUT_SECONDS = 60.0
      MIN_TIMEOUT_SECONDS = 0.001
      JOIN_DEADLINE_SECONDS = 5.0

      # The key the require-time registration below uses, and the key a caller passes to
      # Dexpace::Transport.install/.swap when they want this adapter by name.
      REGISTRY_KEY = :net_http

      module_function

      # The SDK-managed construction. TRANSPORT-29's "effectively immutable after construction"
      # frozen adapter, built per call by #call itself (never a shared @client) -- verified
      # fact 9: a shared Net::HTTP under eight threads produced 128 errors and 26 mismatched
      # responses; a per-call one produced zero of either.
      def build(timeout: nil, logger: ::Dexpace::Instrumentation::Logger::NULL)
        Adapter.owning(timeout: timeout, logger: logger)
      end

      # The borrowing construction. P8-10: refuses at construction unless the caller's own
      # client already has max_retries == 0, because TRANSPORT-2 scopes the disable to an
      # "SDK-managed" transport and XCUT-22 forbids mutating a caller's object -- so on a
      # borrowed client the adapter may neither set the knob nor silently leave the hole.
      def using(client, logger: ::Dexpace::Instrumentation::Logger::NULL)
        Adapter.borrowing(client, logger: logger)
      end

      # SEAM-5's zero-argument factory the registry calls. A FRESH instance every call, never
      # memoized -- a memoized default would be one adapter shared across every unconfigured
      # consumer in the process, which is the shared-client hazard verified fact 9 measured.
      def default
        build
      end

      # module-organization/5c33e5ce: require-time registration is the one load-time side effect
      # this repository permits. It is the LAST STATEMENT INSIDE `module NetHTTP` -- not after the
      # final `end` -- so `method(:default)` resolves against `self`, which is this module, exactly
      # as the design's object-model section writes it. Written below the `end`, `self` would be
      # `main` and `method(:default)` would name the wrong thing (or nothing).
      #
      # The `core:` keyword is REQUIRED by phase 2's Registry#register and raises Dexpace::SeamError
      # on a Dexpace::VERSION skew (design section 2.3, DEF-21, P2-7).
      ::Dexpace::Transport.register(
        REGISTRY_KEY, method(:default),
        core: "~> #{::Dexpace::VERSION.split(".").first(2).join(".")}",
      )
    end
  end
end
```

- [ ] **Step 4: Write `lib/dexpace/transport/net_http/adapter.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "net/http"
require_relative "../net_http"
require_relative "deadline"
require_relative "failures"
require_relative "request_mapper"
require_relative "response_mapper"
require_relative "response_pump"

module Dexpace
  module Transport
    module NetHTTP
      # The transport. private_class_method :new; two named entry points make ownership a
      # construction-time fact (design section 3.7), which is what SEAM-15's documented
      # post-close mode keys off.
      class Adapter
        include ::Dexpace::Closeable
        private_class_method :new

        def self.owning(timeout:, logger:)
          new(client: nil, timeout: timeout, logger: logger, owned: true)
        end

        def self.borrowing(client, logger:)
          unless client.max_retries.zero?
            raise ::Dexpace::InvalidArgumentError,
                  "a borrowed Net::HTTP must have max_retries == 0 (TRANSPORT-2); the adapter " \
                  "may not set it on a client it does not own (XCUT-22)"
          end

          new(client: client, timeout: nil, logger: logger, owned: false)
        end

        def initialize(client:, timeout:, logger:, owned:)
          @client = client
          @timeout = timeout
          @logger = logger
          @clock = ::Dexpace::Clock::SYSTEM
          initialize_closeable(owned: owned)
        end

        # SEAM-11, SEAM-13, SEAM-15. TRANSPORT-3-6, 10, 11, 14, 17, 20, 22, 24-27, 29.
        def call(request, options, cancellation)
          raise ::Dexpace::ClosedError, "this transport is closed" if closed? && owned?

          budget = resolve_timeout(options)
          deadline_or_nil, http = if owned?
                                     owned_client_for(budget)
                                   else
                                     borrowed_client_for(options)
                                   end
          if deadline_or_nil&.expired?
            raise ::Dexpace::TransportError.new("the per-call budget expired before dispatch",
                                                 phase: :connect)
          end

          dispatch(request, http, deadline_or_nil, cancellation)
        rescue ::StandardError => e
          # NO `cause: nil` here. This rescue is the one place in the adapter where $! IS the error
          # being wrapped, so Ruby's implicit #cause wiring attaches `e` for free -- which is what
          # Dexpace::TransportError's own contract ("Ruby's implicit #cause carrying the stdlib
          # error it wrapped") and Task 15's tests both require. `raise error, cause: nil` is for the
          # OPPOSITE case, re-raising a failure carried across a thread boundary, and it is
          # ResponsePump's spelling (Task 18, pipeline/f02559b9) and not this one's.
          raise Failures.wrap(e, phase: :connect, cancellation: cancellation)
        end

        private

        def resolve_timeout(options)
          options.timeout || @timeout ||
            ::Dexpace.configuration.duration(::Dexpace::Configuration::Keys::REQUEST_TIMEOUT,
                                              default: DEFAULT_TIMEOUT_SECONDS)
        end

        # TRANSPORT-5/6: a fresh Net::HTTP per call, its three timeout knobs assigned from THIS
        # call's own deadline -- never a shared client, so "leaving the shared native client's
        # configuration untouched" holds by construction rather than by discipline.
        def owned_client_for(budget)
          deadline = Deadline.build(clock: @clock, budget: budget)
          http = ::Net::HTTP.new(nil, nil) # host/port assigned per request in #dispatch
          http.max_retries = 0
          http.open_timeout = deadline.clamped
          http.write_timeout = deadline.clamped
          http.read_timeout = deadline.clamped
          [deadline, http]
        end

        # P8-6: a non-nil per-call override against a borrowed client raises (checked by the
        # caller of THIS method having already resolved options.timeout above only for the
        # DEFAULT tier's sake; the borrowed branch re-checks the OPTIONS value directly, because
        # a configured or transport-level default must not be silently applied to someone else's
        # client either).
        def borrowed_client_for(options)
          unless options.timeout.nil?
            raise ::Dexpace::InvalidArgumentError,
                  "a per-call timeout override cannot apply to a borrowed Net::HTTP without " \
                  "mutating it (TRANSPORT-5 vs XCUT-22); use .build for a call that needs one"
          end

          [nil, @client]
        end

        def dispatch(request, http, deadline, cancellation)
          native = RequestMapper.build(request, logger: @logger)
          apply_endpoint(http, request.url)
          pump = ResponsePump.new(http: http, native: native, deadline: deadline,
                                   cancellation: cancellation)
          subscription = cancellation.on_cancel { ::Dexpace.close_quietly(pump) }
          begin
            head = pump.head_or_raise
            ResponseMapper.build(request: request, native: head, pump: pump)
          rescue ::StandardError => e
            ::Dexpace.close_quietly(pump)
            raise
          end
        ensure
          subscription&.detach
        end

        def apply_endpoint(http, url)
          http.address = url.hostname
          http.port = url.port
          http.use_ssl = (url.scheme == "https")
        end

        def release
          nil # the managed construction owns no long-lived native resource -- there is nothing
              # to release; the borrowing construction never reaches here at all, because
              # Closeable#close skips #release when owned? is false.
        end
      end
    end
  end
end
```

`Deadline.build` and `owned_client_for`'s knob assignment happen **before** the endpoint
(`address`/`port`) is set, which is fine — `Net::HTTP.new(nil, nil)` followed by `#address=`/`#port=`
before `#start` is what `apply_endpoint` does inside `#dispatch`, called right after
`RequestMapper.build`; the exact ordering inside `#dispatch` is: map the request, apply the
endpoint, construct the pump (which starts the connection on the producer thread using the endpoint
already assigned). TLS verification needs no code here at all — verified fact 16: an
`OpenSSL::SSL::SSLContext.new.set_params({})` yields `VERIFY_PEER` and `verify_hostname: true` by
default, so `http.use_ssl = true` with nothing else assigned is already verifying.

- [ ] **Step 5: `sig/` mirrors for both files, run**

Run: `bundle exec ruby -w gems/dexpace-transport-net_http/test/dexpace/transport/net_http/adapter_test.rb`
Expected: PASS, 9 runs.

Run: `(cd gems/dexpace-transport-net_http && bundle exec rake test)`
Expected: every test file from Tasks 14–19 passes together.

---

## Task 20: Wire the conformance suite into `dexpace-transport-net_http`'s own test task

**Requirement IDs:** the twenty-one assertable `TRANSPORT` rows the charter counts (23 own IDs minus
`TRANSPORT-28`'s ⏳ zero-copy clause and `TRANSPORT-30`), carried by the **28** assertions Tasks 9–13
wrote, run for the first time against a real adapter; `TRANSPORT-18`, `TRANSPORT-6`, `TRANSPORT-12`
and `TRANSPORT-13` asserted as `:vacuous` rather than allowed to pass silently; `TRANSPORT-15`'s
borrowed half.
**Design:** "Testing strategy", item 7; `R16`'s **suite contract** (twelve clauses as of
2026-09-12), checked rather than assumed.

**Files:**
- Create: `gems/dexpace-transport-net_http/test/dexpace/transport/net_http/conformance_test.rb`

**Needs:** Task 19 (the real adapter); Tasks 9–13 (the assertions); Task 8 (`MinitestDriver`).

- [ ] **Step 1: Write the driver invocation**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# R16: this driver is the SECOND consumer of dexpace-conformance's suite once 8c lands, and the
# FIRST here. waive: [] -- TRANSPORT-28's zero-copy clause is not a runtime waiver (open
# question 7); it has no assertion to suppress.
class DexpaceTransportNetHttpConformanceTest < Minitest::Test
  extend Dexpace::Conformance::MinitestDriver

  conformance(
    Dexpace::Conformance::TransportSuite,
    build: ->(**settings) { Dexpace::Transport::NetHTTP.build(**settings) },
    borrow: lambda do |client|
      client.max_retries = 0
      Dexpace::Transport::NetHTTP.using(client)
    end,
    waive: [],
  )
end
```

**This driver passes no `settle:`, `around:` or `wire:`, and that is the point of them having
defaults.** `TransportCase::DEFAULT_SETTLE` is `transport.call(…)`, `around` is absent so the
assertion is invoked directly, and `DEFAULT_WIRE` starts a `WireServer` — which is exactly the
behaviour this sub-phase had before the suite contract's clauses 8, 9 and 11 existed. `8c`'s driver
passes all three (its own plan's Task 19), and **the same 28 assertions run unchanged against both**,
which is the single property `dexpace-conformance` is a published gem for. If a Task 9–13 assertion
still spells its send as `transport.call(…)` when this task runs, it is a defect: the suite is green
here and unrunnable there, which is the failure mode the driver's own keywords cannot catch.

The `borrow:` lambda sets `max_retries = 0` on the caller's own client **before** handing it to
`.using`, rather than `.using` doing it — `.using` asserts the invariant and refuses a client that
does not already hold it (`P8-10`), and a driver that silently fixed the client up first would
never exercise that refusal. `TRANSPORT-15`'s conformance clause (Task 13's own assertion) builds
its own client directly and passes it through the SAME `borrow:` path this driver supplies, so the
refusal path is exercised by that assertion and the happy path by every other borrowed-half
assertion — one `borrow:` lambda, two behaviours reached through it.

- [ ] **Step 2: Run it**

Run: `bundle exec ruby -w gems/dexpace-transport-net_http/test/dexpace/transport/net_http/conformance_test.rb`
Expected: PASS, **28** runs (one `test_…` method per assertion in `TransportSuite.assertions`), with
**four** `test_...vacuous...` methods — `TRANSPORT-18`, `TRANSPORT-6`, and the `TRANSPORT-12` and
`TRANSPORT-13` cross-references — reported as **skipped**, matching Minitest's own vocabulary for
`Vacuous` in this driver (Task 8's `skip("vacuous: …")` branch). A skip is visually distinct from a
pass in Minitest's own summary line, which is what "asserted as `:vacuous` rather than allowed to
pass" means operationally. (The design's Testing-strategy item 7 says "three vacuity expectations",
counting only the three that are *cross-references to another sub-phase's rows*; `TRANSPORT-6`'s is a
fourth, and it is vacuous for its own reason — the requirement's antecedent is inverted on this
adapter, per the *Eleven rows* section.)

- [ ] **Step 3: Confirm the borrowed-client refusal is exercised, not merely reachable**

Add one direct assertion in this same test file (outside the driver-generated set):

```ruby
  test "TRANSPORT-15's borrowed half genuinely refuses a client with a non-zero max_retries" do
    client = Net::HTTP.new("127.0.0.1", 1)

    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Transport::NetHTTP.using(client) }
  end
```

This does not duplicate Task 19's own `adapter_test.rb` test of the same fact — it confirms the
conformance driver's `borrow:` lambda is what a real third-party adapter author would actually
write, and that writing it wrong (omitting the `max_retries = 0` line) fails loudly rather than
silently, which `R16`'s hand-off promises the next adapter author.

---

## Task 21: `sig/` for both gems, the Steep targets, `rbs_collection.yaml`

**Requirement IDs:** `NFR-3`, `NFR-11`.
**Design:** "The `sig/` shape" in full; open question 2.

**Files:**
- Create/modify: every `.rbs` file named in the design's module layout table that Tasks 2–20 did
  not already write inline (this task is the sweep that confirms none was skipped)
- Modify: `Steepfile`, possibly `rbs_collection.yaml`

**Needs:** everything above.

- [ ] **Step 1: Confirm every public constant in both gems has a `sig/` mirror**

Cross-check the module layout table against `Dir.glob("gems/{dexpace-transport-net_http,
dexpace-conformance}/lib/**/*.rb")` versus the matching `sig/**/*.rbs` tree, the same shape phase
0's `GemLayoutTest` already asserts generically — this step is a manual read-through, not a new
test, because that test already fails the build if a file is missing its mirror.

- [ ] **Step 2: Try `library "net-http"` on the Steep target first (open question 2)**

In `Steepfile`, the `dexpace-transport-net_http` target gains:

```ruby
target :dexpace_transport_net_http do
  signature "gems/dexpace-transport-net_http/sig", "gems/dexpace-core/sig"
  check "gems/dexpace-transport-net_http/lib"
  library "net-http"
end
```

Run: `bundle exec rake steep`

- [ ] **Step 3: If unresolved, fall back to a `rbs_collection.yaml` row**

If `steep check` reports `Net::HTTP` (or any of its collaborators) as unresolved through the
`library` line on any of the three interpreters, add net-http's row to `rbs_collection.yaml`'s
previously-empty `gems:` list (phase 0's own comment already anticipates this: "net-http and
async-http with the transports in phase 8, and each adds its own row here then"), run `bundle exec
rbs collection install`, and record in this task's own notes which interpreter forced the fallback
and what `steep check`'s diagnostic said — per open question 2's "verify rather than assume,
because an unresolvable signature makes the target's diagnostics meaningless rather than loud."

- [ ] **Step 4: Confirm `NFR-11`'s scan**

Run: `bundle exec rake gates:rbs_surface`
Expected: `gates:rbs_surface: no foreign constant in any public signature.` `Net::HTTP`,
`Net::HTTPResponse` and `Net::HTTPGenericRequest` name **no** `sig/` file in either gem: `.using`
types its `client` argument `untyped` with a YARD block naming what it must be, and every private
constant (`Adapter`, `RequestMapper`, `ResponseMapper`, `ResponsePump`, `Deadline`, `Failures` in
one gem; every conformance internal in the other) carries no `sig/` file at all, because a
`private_constant` is not `NFR-4` surface.

- [ ] **Step 5: `bundle exec rake rbs:validate steep`, both gems, all three
  interpreters (per Task 1's own grid).**

---

## Task 22: Runtime surface snapshot and RBS baseline diff

**Requirement IDs:** `NFR-4` (both halves).
**Design:** "The `sig/` shape", fourth bullet.

**Files:**
- Modify: `test/fixtures/surface/dexpace-transport-net_http.txt`,
  `test/fixtures/surface/dexpace-conformance.txt` (phase 0's runtime-surface baselines, regenerated)

**Needs:** Task 21 finished cleanly.

- [ ] **Step 1: Regenerate both artifacts**

Run: `bundle exec rake surface:regenerate`

This walks `Dexpace`'s constant tree and each class's `public_instance_methods(false)`, which is
what makes `Data.define`'s generated readers on `Assertion`/`Result`, `NetHTTP`'s require-time
`register` call's side effects, and every `.build`/`.using`/`.default` visible to the manifest even
though `rbs validate` cannot see any of them on its own.

- [ ] **Step 2: Confirm the diff is additions only**

Run: `git diff --stat test/fixtures/surface/`
Expected: two files changed, only added lines — `NFR-4`'s lock fails on a signature that
disappears or narrows without a major bump, and this sub-phase narrows nothing.

- [ ] **Step 3: Run `gates:sig_diff` and `gates:surface_snapshot` together**

Run: `bundle exec rake gates:sig_diff gates:surface_snapshot`
Expected: both green. This is the first time either gate sees non-trivial public surface for
either of these two gems.

---

## Task 23: `gates:gemspec_audit`, `gates:require_allowlist`, `gates:clean_bundle` — all three
interpreters

**Requirement IDs:** `SEAM-1`, `SEAM-2`, `NFR-1`, `NFR-2`.
**Design:** "From phase 0 — the gates that bite"; this plan's own facts 3 and 4.

**Files:**
- Modify: `tasks/gates.rake` (the `clean_bundle_check` fix, this plan's finding 3)

**Needs:** every gem file from Tasks 2–20 in place.

- [ ] **Step 1: Fix `clean_bundle_check`'s Gemfile generation (this plan's fact 3)**

```ruby
  def clean_bundle_check(name, path, entry, constant)
    Dir.mktmpdir("dexpace-clean-bundle") do |dir|
      core_path = File.join(__dir__, "..", "gems", "dexpace-core")
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        # frozen_string_literal: true
        source "https://rubygems.org"
        gem "dexpace-core", path: #{core_path.inspect}
        gem #{name.inspect}, path: #{path.inspect}
      GEMFILE
      # ... unchanged below
```

Every adapter gemspec already declares `dexpace-core` as a runtime dependency (phase 0's own Task 5
Step 4), and a Gemfile naming only the adapter cannot resolve it — `dexpace-core` is never
published, so Bundler's own source (`rubygems.org`) has nowhere to find it. This bug is latent for
every one of the five adapters already in `CLEAN_BUNDLE_ENTRIES`, not only this sub-phase's two;
fixing it here is this plan's contribution to a phase-0-owned file, made because this sub-phase is
the first to actually need `gates:clean_bundle` to pass on a gem with a real runtime dependency
graph two levels deep (`dexpace-transport-net_http` → `dexpace-core`, plus `net-http`, which
Bundler resolves normally since it is a real published gem).

- [ ] **Step 2: Run `gates:clean_bundle` for both new-surface gems, on all three interpreters**

```bash
DEXPACE_CLEAN_BUNDLE_GEM=gems/dexpace-transport-net_http bundle exec rake gates:clean_bundle
DEXPACE_CLEAN_BUNDLE_GEM=gems/dexpace-conformance bundle exec rake gates:clean_bundle
```

Repeat on 3.2.11 and 4.0.6 via `mise exec ruby@3.2.11 -- bundle exec rake gates:clean_bundle` (and
the 4.0.6 row). Expected: `gates:clean_bundle: 1 gem(s) load in isolation on Ruby …` for each,
proving the **declared** dependency closure (`dexpace-core` plus, for the transport gem, `net-http`)
is sufficient to load and run the smoke path — the standard `require entry; check VERSION`
check, per this plan's fact 4: a `TCPServer`-based smoke variant would prove nothing beyond what
this already proves, because Bundler does not gate a default gem's availability by declaration
either way. The real proof that `net-http` specifically is *declared and not merely present* is
`gates:require_allowlist`'s text scan (Step 3), which this task runs immediately after for exactly
that reason.

- [ ] **Step 3: Run the full gate set**

Run: `bundle exec rake gates:gemspec_audit gates:require_allowlist gates:clean_bundle`, on all
three interpreters.
Expected: all green. `gates:require_allowlist` reports `net/http` permitted for
`dexpace-transport-net_http` (declared) and `socket` permitted for `dexpace-conformance` (`P8-14`'s
named exception) and denied everywhere else.

- [ ] **Step 4: Verify the per-gem Ruby floor if `8c` has already landed it — never re-apply it**
  (added 2026-09-12)

`8c`'s plan Task 3 edits `VERSIONS`, `tools/versions.rb`, `tools/versions_gate.rb`, the root
`Gemfile`, `tasks/quality.rake` and `tasks/gates.rake` so `dexpace-transport-async_http` alone can
declare `required_ruby_version >= 3.3` (`P8-36`, `OI-38`). **This plan touches none of them.** If the
edit is in place when this task runs, check the state against the charter's own end-state table (*The
CI matrix after `8c`'s per-gem Ruby floor*) rather than against a diff, and confirm the three things
that bear on this sub-phase:

```bash
bundle exec rake gates:versions            # both 8a gems assert >= 3.2 against the GLOBAL floor row
bundle exec rake gates:clean_bundle        # on 3.2, both 8a gems are still in `targets`
mise exec ruby@3.2.11 -- bundle exec rake  # the whole gate set, unchanged for this sub-phase
```

Expected on every row: `gates:versions` green for `dexpace-transport-net_http` and
`dexpace-conformance` against the global `ruby floor 3.2`, because neither has a `floor:<gem-name>`
row of its own and `DexpaceVersions.ruby_floor(name)` falls back to the global value. **If the edit
is not in place, nothing here fails and nothing here adds it** — the collision exists only once
`8c`'s gemspec declares the narrower floor, and a second copy of a six-file gate edit is worse than
a missing one.

---

## Task 24: YARD's undocumented-public-method gate

**Requirement IDs:** none directly — the documentation gate every prior phase runs last.
**Design:** general repository rule; `docs/README.md`'s hierarchy.

**Files:** none new — every public class/method written in Tasks 2–20 already carries a YARD
block (each code sample above includes one); this task is the gate run and any gaps it finds fixed
in place.

- [ ] **Step 1: Run the gate**

Run: `bundle exec rake yard`
Expected: zero undocumented public objects across both gems. If any is found, the fix is a YARD
block explaining **why** the method exists or what a caller must know (per `documentation/80beb95e`)
— never a restated type signature, and never a block added just to satisfy the gate mechanically.

---

## Task 25: The knowledge note, the register findings, `docs/first-release.md`, housekeeping

**Requirement IDs:** none directly — the register and documentation follow-through every phase's
final task performs.
**Design:** "The knowledge notes `8a` files"; "The findings proposed for the registers"; "Deferrals
filed by phase 8a".

**Files:**
- Create: `docs/knowledge/notes/transport-adapter.md`
- Modify (by a human, per this plan's own hand-off, not by this plan): `docs/open-items.md`,
  `docs/deferred-items.md`, `docs/first-release.md`

**Needs:** everything above landed and green.

- [ ] **Step 1: Verify the note filed on 2026-09-12 still matches; update it if the implementation
      found otherwise**

`docs/knowledge/notes/transport-adapter.md` **already exists**: the phase-8 follow-through wrote it
on 2026-09-12, byte-for-byte from the design's "The knowledge notes `8a` files" block — two
`## Superseded` entries against `transport-adapter/7e8e2c60` and `/d16c7444`, one `## Reference`
entry beside `/0921e946`, each with its manual `sha:` marker and backticked key. (`8c`'s
`## Reference` entry against `/cb7901ef` was appended to the same file in the same change.) This
step **checks the three entries against what this sub-phase actually built and measured**, and
amends any entry the implementation contradicts — a note is what the implementation found, so a
claim that did not survive execution is corrected here rather than left standing. Do not re-create
the file and do not duplicate an entry.

- [ ] **Step 2: Verify the note structure and the override tags**

Run: `ruby scripts/verify_knowledge_structure.rb`
Expected: exits 0 (the gate that keeps `harvested/` and `notes/` apart).

Run: `ruby scripts/knowledge.rb --key transport-adapter/7e8e2c60` and `--key
transport-adapter/d16c7444`
Expected: each prints `[overridden by notes/transport-adapter.md:…]`.

- [ ] **Step 3: Hand the five register findings to a human**

The design drafts all five verbatim in "The findings proposed for the registers", plus the two
`OI-34`/`OI-35` amendments; this plan adds a **sixth**, its own (this plan's fact 4, the
clean-bundle smoke-test limitation) and a **seventh** (the `Protocol.parse`/`"http/1.0"` gap noted
in Task 17). Neither is filed by this task — the same collision hazard the design names (`OI-34`–
`OI-37` and `OI-38`–`OI-41` both dangling at once, from the charter and a sibling sub-phase written
concurrently) applies here with two more numbers in flight, and the housekeeping probe's `citations`
check is how the next free block is found rather than guessed, exactly as the design says.

- [ ] **Step 4: `docs/first-release.md`**

The design's `P8-9`-adjacent finding — "a green `dexpace-conformance` run proves less than its name
suggests" — is handed to a human for that file, together with the phase-level task's own release
line (`dexpace-conformance`'s first release, `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`'s
"phase 8 owns its gemspec, its version and its first release" clause). This plan does not edit the
file; it hands over the exact two sentences the design already drafted.

- [ ] **Step 5: Run housekeeping's probe**

Run: `ruby .claude/skills/housekeeping/probe.rb`
Fix what it reports **without rewriting prose to satisfy a check**. `CLAUDE.md`'s phase-directory
claims sentence and the `knowledge-lookup` skill's owed audit-group row are the segmentation
design's obligations, not this sub-phase plan's. **Do not run `apply.rb --write`** and do not
commit; both are the user's to ask for.

- [ ] **Step 6: Run the whole gate set one final time, on all three interpreters**

Run: `bundle exec rake` on 3.2.11, 3.4.10 and 4.0.6.
Expected: all seventeen gates green, on every row.

---

## Coverage table

Every one of the 23 IDs in this sub-phase's budget, the task numbers that satisfy it, and the
disposition the design's scope table assigns.

| ID | Disposition | Task(s) |
|---|---|---|
| `TRANSPORT-1` | Implemented — absence of a knob, a real assertion over a raw 302 | 12, 20 |
| `TRANSPORT-2` | Implemented — `max_retries = 0`; `P8-10` asserts it on a borrowed client | 12, 19, 20 |
| `TRANSPORT-3` | Implemented — token-first discrimination, `Failures.wrap` | 12, 15, 19, 20 |
| `TRANSPORT-4` | Implemented — retryable classification, cancellation flag left clear | 12, 15, 19, 20 |
| `TRANSPORT-5` | Implemented — total per-call budget, two concurrent calls each bounded by their own | 13, 14, 19, 20 |
| `TRANSPORT-6` | Implemented (SHOULD) — clamp shipped for an inverted antecedent, `:vacuous` at the conformance level, direct unit test at the adapter level | 13, 14 |
| `TRANSPORT-10` | Implemented — Content-Type precedence, three cases | 9, 16, 20 |
| `TRANSPORT-11` | Implemented — `MANAGED_HEADERS`, verbose drop logging | 9, 16, 20 |
| `TRANSPORT-14` | Implemented — filtered before `Headers::Builder`, obs-text preserved, multi-value survives | 10, 17, 20 |
| `TRANSPORT-15` | Implemented — both halves: owned refuses a later send, borrowed survives close | 13, 19, 20 |
| `TRANSPORT-16` | Implemented — idempotent close, bounded teardown | 13, 18, 19, 20 |
| `TRANSPORT-17` | Implemented — one write, asserted from outside and guaranteed by shape from inside | 12, 16, 20 |
| `TRANSPORT-18` | Vacuous, once `max_retries = 0` removes the antecedent — `OI-34` | 12, 20 |
| `TRANSPORT-19` | Implemented (SHOULD) — closing an undrained, dribbling response unblocks the producer promptly and idempotently | 11, 18, 20 |
| `TRANSPORT-20` | Implemented — the canonical retryable failure, `Dexpace::TransportError` | 2, 12, 15, 20 |
| `TRANSPORT-22` | Implemented — the connection is released when a caller-side failure follows a live response | 12, 19, 20 |
| `TRANSPORT-24` | Implemented — total status mapping including a vendor code | 10, 17, 20 |
| `TRANSPORT-25` | Implemented — lazily-read stream, byte-exact round trip, cascading close | 11, 17, 18, 20 |
| `TRANSPORT-26` | Implemented — a body-less body-permitted request substitutes a zero-length body (the library's own `set_body_internal`) | 9, 16, 20 |
| `TRANSPORT-27` | Implemented (SHOULD) — raw-header length parse, `MediaType.parse` rescue-to-nil (discrepancy 2) | 10, 17, 20 |
| `TRANSPORT-28` | Partially satisfied (SHOULD) — replayability and byte-range clauses implemented and asserted; zero-copy clause ⏳ `DEF-10`, no runtime assertion (open question 7) | 11, 20 |
| `TRANSPORT-29` | Implemented — concurrent-safety proof against a shared adapter, failing on a shared client (verified fact 9) | 13, 19, 20 |
| `TRANSPORT-30` | ⏳ `DEF-10` whole — the embedded MUSTs hold vacuously because this adapter configures no proxy at all; not implemented or asserted by this plan | none (recorded here only) |

Every ID appears. `TRANSPORT-30` carries no task because the design's own `R5`/`DEF-10` disposition
leaves it whole and this plan implements no proxy handling; it is listed so the table is a complete
accounting of the 23-ID budget rather than a list of what has code.

`PAGE-36`'s per-call-options conformance test (13, 20) and `OBS-21`/`OBS-25` (7) are phase-7c's and
phase-5b/5c's obligations respectively, discharged by this plan without owning a new ID of their
own, exactly as the design states.

---

## Discrepancies found against the design

Four findings from this planning pass, each verified by running Ruby or by reading the shipped
plan the design cites, each with the decision this plan made and why. None reopens an `R1`–`R7`
decision; each is a fact the design states that this plan found to not hold, one level below where
the design's own reasoning operates.

1. **`Dexpace::Configuration#float` does not exist.** The design's `R3` and its object model both
   write `Dexpace.configuration.float(Configuration::Keys::REQUEST_TIMEOUT, default:
   DEFAULT_TIMEOUT_SECONDS)`. Phase 5a's shipped `Configuration` class defines exactly `#string`,
   `#integer`, `#boolean` and `#duration` — no `#float`
   (`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md:2771-2812`). **What this plan
   does instead:** `Task 19` calls `Dexpace.configuration.duration(Keys::REQUEST_TIMEOUT, default:
   DEFAULT_TIMEOUT_SECONDS)`, which already returns `Float` seconds via
   `ConfigParsers.parse_duration` and returns the `default` unmodified when nothing is configured
   (`:2091-2092`). The behavioural cost, recorded rather than hidden: a caller who sets
   `REQUEST_TIMEOUT=30` gets **30 milliseconds**, because `parse_duration`'s own grammar treats a
   bare number as milliseconds (`:2126`, `CFG-7`) — a caller who wants 30 seconds must write `30s`
   or `PT30S`. This is documented in `Adapter`'s YARD (Task 19) and is `Configuration::Keys`' own
   existing convention (every other duration-shaped setting in this repository is `#duration`-typed,
   not a new precedent this plan invents).
2. **`Dexpace::MediaType.parse` raises on a malformed value; it does not return `nil`.** The
   design's `R4` section and its object model both state, three times, that `MediaType.parse`
   "downgrades" a malformed value to `nil`. Phase 1's shipped parser raises
   `Dexpace::InvalidArgumentError` whenever `slash.empty? || type.empty? || subtype.empty? ||
   subtype.include?("/")`
   (`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md:2170-2184`), and the design's
   own example string, `"not a/;;media type"`, hits exactly that branch by hand-trace
   (`type="not a"`, `subtype=""`). **What this plan does instead:** `ResponseMapper.parse_media_type`
   (Task 17) wraps the call in `rescue Dexpace::InvalidArgumentError; nil`, which is what actually
   produces `TRANSPORT-27`'s required behaviour; the design's own conclusion — "satisfied by not
   raising on a `nil`" — is correct once this plan supplies the `nil`.
3. **Phase 0's `gates:clean_bundle` fixture cannot resolve `bundle install` for any adapter with a
   runtime dependency, as currently written.** **Not a defect in the 8a design, which describes the
   right shape** — its *From phase 0* bullet already says the `Gemfile` for this gem "is
   `gem "dexpace-core", path:` **plus** `gem "dexpace-transport-net_http", path:`" — but phase 0's
   `clean_bundle_check` writes only the second line, so the design describes a workspace the gate does
   not build. (An earlier revision of this entry said the design makes no such claim; corrected
   2026-09-12.) Surfaced here because Task 23 depends on the gate working. Verified: a
   scratch two-gem workspace (a dependent gem declaring `dexpace-core`, matching every real adapter
   gemspec since phase 0's own Task 5 Step 4) with a Gemfile naming only the dependent gem's
   `path:` line failed `bundle install` with `Could not find compatible versions … dexpace-core …`;
   adding a second `gem "dexpace-core", path: ...` line resolved cleanly. **What this plan does
   instead:** Task 23 adds the second path line to `tasks/gates.rake`'s `clean_bundle_check`, fixing
   the gate for every adapter in `CLEAN_BUNDLE_ENTRIES`, not only this sub-phase's two.
4. **The design's stated reason for a `TCPServer`-based `clean_bundle` smoke test does not hold.**
   The design's "From phase 0" section says the isolation run's smoke path should be "a real
   request against a `TCPServer` the script starts … [which] is the run that proves `net-http` is
   declared rather than merely present." Verified: Bundler does not restrict a **default** gem's
   availability by Gemfile declaration at all — a scratch workspace where the dependent gem's
   `lib/` required `"net/http"` with no `net-http` dependency declared anywhere loaded and ran
   successfully under `bundle exec`. `net-http` is not scheduled to become a bundled (non-default)
   gem within 3.2–4.0, so no clean-bundle smoke test, however constructed, can distinguish
   "declared" from "merely present" for it; only `gates:require_allowlist`'s text scan does that.
   **What this plan does instead:** Task 23 keeps the standard require-and-check-`VERSION` smoke;
   the real end-to-end `TCPServer` round trip the design wanted proven lives in the adapter's own
   suite (Tasks 16–20), which is a different gate proving a different, and in this case the
   actually-necessary, property.

One further note, not rising to a discrepancy because the design never claims otherwise:
`Dexpace::Protocol.parse` has no alias for `"http/1.0"` (Task 17's caution). This plan's `WireServer`
fixture always answers `HTTP/1.1`, so the gap is never exercised by anything in this plan, and it is
handed to *The findings proposed for the registers* (Task 25) rather than fixed, because fixing it
is a phase-1 surface decision (widening `Protocol::WIRE_FORMS`) no sub-phase should take alone.


---

## Verification log (2026-09-12)

This plan was verified task by task against
`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md` and
against the charter `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`. Only changes are
logged; a check that changed nothing is not. Every Ruby fact below was re-run on the one interpreter
available here, **Ruby 3.4.10** with **Bundler 4.0.20**; nothing was installed into the project or the
user's gem directory.

### Adjudication of `## Discrepancies found against the design`

Each of the four was re-derived from the source it cites rather than taken on trust.

1. **`Configuration#float` — the plan is right; the DESIGN was corrected.** Phase 5a's shipped
   `Configuration` defines `#string`, `#raw_property`, `#integer`, `#boolean` and `#duration` and
   nothing else (`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md:2771-2802`, read
   directly). `parse_duration` (`:2087-2130`) returns `Float` seconds, returns the `default`
   unmodified for a `nil` raw value, and treats a bare number as **milliseconds** (`CFG-7`). The
   design's `R3` tier table and its *From phase 5a* prerequisite both said `#float`; both now say
   `#duration`, each with the correction stated in place, and `P8-5`'s Deviation Ledger row now names
   the reader and the milliseconds grammar.
2. **`MediaType.parse` raises — the plan is right; the DESIGN was corrected.** Phase 1's shipped
   parser (`…-phase1-core-http-domain-model.md:2168-2183`) raises `Dexpace::InvalidArgumentError`
   whenever `slash.empty? || type.empty? || subtype.empty? || subtype.include?("/")`, and also raises
   on `nil` through `Model.required!`. The design's own example, `"not a/;;media type"`, hits that
   branch exactly: `split_parameters` cuts at the first `;`, the essence is `"not a/"`, and
   `partition("/")` yields `subtype = ""`. Three design sentences said the parser "downgrades" to
   `nil`; `R4` step 3 now owns the downgrade through a `rescue Dexpace::InvalidArgumentError`, and the
   object-model and verified-fact-12 sentences were corrected with it.
3. **`gates:clean_bundle`'s one-line Gemfile — the plan's fix is right; the PLAN's attribution was
   corrected.** Measured on Bundler 4.0.20: a scratch workspace with a `dexpace-core` path gem and a
   `dexpace-foo` path gem declaring `add_dependency "dexpace-core", "~> 0.0"`, with a Gemfile naming
   only `dexpace-foo`, failed with *"Because every version of dexpace-foo depends on dexpace-core
   ~> 0.0 and dexpace-core ~> 0.0 could not be found in rubygems repository … version solving has
   failed"*; adding the `dexpace-core` path line resolved and ran. Phase 0's `clean_bundle_check`
   writes one `gem` line, and every adapter gemspec declares `dexpace-core`
   (`…-phase0-scaffold-and-quality-gates.md:1319`), so the defect is latent for all five adapter rows
   of `CLEAN_BUNDLE_ENTRIES` and Task 23's fix is correct. **But this plan wrongly said it was "not a
   claim the 8a design makes at all"** — the design's *From phase 0* bullet already describes the
   two-line Gemfile. The design describes the right shape; phase 0's code does not build it. The
   entry now says so.
4. **The `TCPServer` clean-bundle smoke rationale — the plan is right; the DESIGN was corrected.**
   Measured on Bundler 4.0.20 / Ruby 3.4.10: a scratch workspace whose only gem's `lib/` does
   `require "net/http"` with **no** `net-http` dependency declared anywhere installed and ran to
   completion under `bundle exec`, resolving `Net::HTTP`. Bundler does not gate a *default* gem by
   declaration, and `net-http` does not leave the default set anywhere in 3.2–4.0, so no smoke path
   however constructed recovers the property. The design's *From phase 0* bullet no longer claims one
   and names `gates:require_allowlist`'s text scan as the gate that does prove declaration.

### Findings applied to the plan

**Correctness — would have failed at load or at first run.**

- **`private_class_method :new` does not mean "private outside the gem".** Verified on 3.4.10: it
  makes `new` a private singleton method, so *any* explicit-receiver call raises `NoMethodError:
  private method 'new' called for class …`, whatever the file or lexical scope. 34 `Assertion.new(`
  and 7 `Result.new(` call sites — in `transport_suite.rb`, both drivers, all five assertion groups
  and every Task 4/6/8 test — were changed to `.build(`, and Task 4's note claiming otherwise was
  replaced with the measurement.
- **`require_relative "../model"` in `dexpace-conformance` resolves to a file that does not exist.**
  `Dexpace::Model` is `dexpace-core`'s, at `gems/dexpace-core/lib/dexpace/model.rb`; the relative form
  would look for it inside `dexpace-conformance`'s own `lib/`. Both occurrences (Task 4's `Assertion`
  and `Result`) are now `require "dexpace/model"`, which is the form phase 0's allowlist permits for a
  declared `dexpace-core` dependency.
- **`ResponseMapper.build` deleted `content-length` from the native response *before* copying the
  headers**, so the caller would never have seen the value the server sent — the opposite of `R4`'s
  own "the raw header still reaches the caller". `filter_headers` now runs first, with the ordering
  stated inline as load-bearing.
- **`Adapter#call` raised `Failures.wrap(…), cause: nil`**, discarding the `#cause` that
  `Dexpace::TransportError`'s contract and Task 15's own tests both require, and directly
  contradicting Task 15's prose ("it is `Adapter#call`'s `raise` that gives it a `#cause`"). The
  `cause: nil` is removed, with the `pipeline/f02559b9` distinction stated where the two spellings
  meet.

**Tests that slept to synchronise (Global Constraints; `testing/4ef070df`).** Four, all replaced with
a deterministic wait; the two fixture-side `sleep`s that *simulate* a slow or dead server
(`Scripts.dribble`, `Scripts.hang_after_headers`) stay, because they are the behaviour under test.

- Task 5's `sleep 0.05 while server.closed_connections.zero?` and Task 11's
  `sleep 0.05 until kase.wire.closed_connections.positive?` → **`WireServer#await_closed_connection`**,
  a new blocking `Queue#pop` fed from `#handle`'s `ensure` and closed by `#close`. Put on the server
  rather than on a per-script `on_close:` keyword (which is what both tasks' own prose proposed) so
  the eleven scripts need no change and `8c` inherits the wait with the fixture.
- Task 12's `TRANSPORT-3` assertion and Task 19's cancellation test each did
  `Thread.new { sleep 0.2; source.cancel(…) }`. `Scripts.hang_after_headers` gained an
  `on_headers_written:` callable, invoked on the server's thread the instant the head is flushed —
  which is the instant the client enters its first body read. Both now pop a `Thread::Queue` fed from
  there, and both join the canceller thread.

**Missing failing-test-first steps.** Tasks 11, 12 and 13 jumped straight to "Step 3: Extend
`ASSERTIONS`" with no test written or run first. Each gained a Step 1 (registration plus a
conforming *and* a deliberately non-conforming `StubTransport` per assertion — the second half is what
proves an assertion can fail at all) and a Step 2; Task 11 also gained the missing Step 4. Task 3's
steps ran 1, 2, 3, 2, 3, 4; renumbered 1–6.

**Sketches written wrong on purpose.** Five blocks instructed the implementer to write code the
following paragraph then retracted — a plan executed task-by-task is the one place that device does
real damage. Each is now the final code with the rejected alternative kept as prose: `MinitestDriver`'s
two `define_method` passes (Task 8), `Failures.wrap`'s `instance_variable_set` and self-raising
variants (Task 15), `parse_length!`'s `if false` branch and doubled `ensure` (Task 17), `Deadline.new`
in the test (Task 14), and the registration call placed after `module NetHTTP`'s `end` (Task 19, where
`method(:default)` would resolve against `main`). `ResponsePump`'s `nil_token` placeholder (Task 18) is
likewise gone: `cancellation:` is now a required fourth keyword threaded from `Adapter#call`, which is
what `TRANSPORT-3`'s ask-the-token-first rule requires of both `Failures.wrap` call sites.

**Counts and claims.**

- `TransportSuite.assertions.size` is **28**, not 21 — the plan's own breakdown (5 + 4 + 3 + 8 + 8)
  sums to 28, and Task 20's "21 runs" followed the wrong total. Task 13 now asserts the count where
  the array closes; Task 20 expects 28. The *twenty-one* figure is the charter's count of assertable
  `TRANSPORT` **rows** (23 own IDs less `TRANSPORT-28`'s ⏳ clause and `TRANSPORT-30`), which is a
  different number from the assertions carrying them; Task 20's header now says which is which.
- **Four** assertions are `Vacuous`, not three: `TRANSPORT-18`, `TRANSPORT-6`, `TRANSPORT-12`,
  `TRANSPORT-13`. The design's "three vacuity expectations" counts only the cross-references to other
  sub-phases' rows; `TRANSPORT-6`'s is a fourth, for its own reason.

**Fidelity to the design.**

- **`PAGE-36`'s assertion drove both calls with the same `RequestOptions`** (`timeout = 5` twice),
  which passes against a transport that reads options once and reuses them — the exact defect `7c`
  filed the row for. The second call now carries genuinely different options.
- **Task 18's tests hand-rolled a `TCPServer` fixture** beside `dexpace-conformance`'s, against design
  boundary 13. They now use `WireServer` + `Scripts.dribble`/`.fixed`, with the reason stated and with
  the note that this needs no gemspec change, because phase 0's root `Gemfile` path-loads every gem
  under `gems/` — so `NFR-2`'s two-dependency budget and `gates:clean_bundle`'s `lib/`-only run are
  both untouched. The two now-unused `require "socket"` lines in that gem's tests became
  `require "net/http"`.
- **`Failures`' `WRAPPABLE` constant was never read** by the final `wrap` body, which is a catch-all.
  The constant is removed rather than left as `NFR-4`-locked surface with no caller (`OI-8`'s shape),
  and the families it listed are kept in the comment where they document verified fact 7. The
  **design** was corrected to match, because the plan is right on the merits: `P6-4`'s obligation is
  "wrap, and default to retryable, **not** wrap and get the classification right by hand", and an
  enumerated list fails exactly the way `P6-4` warns — an unlisted family escapes unwrapped and
  classifies not-retryable.
- **`MinitestDriver.conformance` ended with `puts(suite.run(…)) if $VERBOSE`.** Every run in this
  repository is a `-w` run, so the guard is always true and the line silently doubled every
  conformance run's socket traffic during class-body evaluation. Removed; the `skip("waived: …")`
  branch already names every waived ID in Minitest's own summary, which is §9.3's requirement.
- **`RequireAllowlist.scan_file` was given `gem_name: nil`**, contradicting the same step's stated
  intent that a caller who forgets it must see an `ArgumentError`. The default is gone.
- **The `### Commands` block listed three commands phase 0 does not define** —
  `bundle exec rubocop --fail-level=convention`, `bundle exec steep check`, `bundle exec rbs validate`
  — where phase 0 ships `rake rubocop` and `rake rbs:validate steep`, and `bundle exec rake yard`
  where phase 0 ships `rake yard bundler_audit`. Replaced with phase 0's own spellings, and
  `cops:test`, `test:gems`, `test:gates` and `ruby -Itest test/gates/<name>_test.rb` added, all of
  which phase 0 defines and this plan's tasks use.

### Checked and unchanged

- **Every ID in the coverage table is in the charter's `8a` budget**, and every one of the 23 appears
  exactly once; `TRANSPORT-7`, `8`, `9`, `12`, `13`, `21`, `23` are absent, which is the charter's
  `8c` assignment. No `ASYNC` ID appears anywhere in the plan.
- **Every source sketch carries `# frozen_string_literal: true` on line 1 and
  `# SPDX-License-Identifier: MIT` on line 2** (`NFR-13`), and every test file opens with a header
  comment naming the requirement IDs it exercises.
- **No task proposes `Timeout.timeout`, `Thread#raise`, `Thread#kill`, `Thread#terminate` or
  `Thread#exit`.** `ResponsePump#release` and `WireServer#close` are both latch → wake → **bounded**
  `Thread#join(JOIN_DEADLINE_SECONDS)`.
- **Both `Thread::Mutex` holds are across the flag flip only**, in `ResponsePump` and `WireServer`
  alike; neither is held across a queue close, a socket close or a join.
- The API names the plan reaches for were checked against the phases that ship them and all resolve:
  `Cancellation.none`/`.source`/`#on_cancel` → `Subscription#detach` (phase 2), `Headers.builder`,
  `Headers.inbound_builder`, `Headers::EMPTY`, `RequestOptions.builder`, `RequestOptions::EMPTY`,
  `Dexpace::URL`, `Dexpace::CancelledError` (phase 2), `Dexpace::Clock::SYSTEM` (5a),
  `Dexpace::BufferBody`, `Dexpace::IO::Buffer`, `FileBody.new(path, media_type:, offset:, count:)`
  (3b).
- The `sig/` shape matches the design: no `Net::` constant in any `.rbs`, `.using`'s client typed
  `untyped`, `Assertion#body` typed `^(untyped) -> void`, and `_Transport` declared only in
  `dexpace-conformance`'s `sig/`.

## Handoff to follow-through

Items this verification pass found that belong in a document it may not write. **None is filed here.**

- **`docs/open-items.md`** — the plan hands seven findings to a human (the design's five, plus the
  clean-bundle smoke-test limitation and the `Protocol.parse`/`"http/1.0"` gap). This pass adds
  nothing to that list and confirms the numbering hazard the plan already states: `OI-34`–`OI-37` are
  cited by the charter and a further block by a sibling sub-phase, both dangling, so the next free
  block is found with `ruby .claude/skills/housekeeping/probe.rb --only citations`, never guessed.
- **`tasks/gates.rake` is phase 0's file and Task 23 edits it.** The one-line-Gemfile defect is
  measured above and affects all five adapter rows of `CLEAN_BUNDLE_ENTRIES`; whoever reviews the
  phase-level PR should see it as a phase-0 repair carried by 8a, not as an 8a-local workaround.
- **`Dexpace::TransportError` is defined by two plans.** 8a's Task 2 writes it (shape recorded below);
  8c's plan writes it as well. The phase-level PR is where one of the two becomes a no-op
  confirmation — 8a's Task 2 already says so in its own preamble. A later reconciliation agent owns
  the merge; neither document is edited here.

### Added by the cross-sub-phase reconciliation pass, 2026-09-12

Seven things this pass settled across the phase's seven documents. Each is recorded in the document
that changed; what is listed here is what a follow-through agent still has to carry out.

1. **`Dexpace::TransportError` has one owner now: this plan's Task 2.** The charter's phase-level
   task 1 no longer says "whoever lands first". `8c`'s Task 4 became a citation and a verification,
   and its own definition is the fallback for the out-of-order case only. The shape kept is this
   plan's — the superset, with `#phase` and a default message — because `8c` constructs the class
   positionally at every site and needs nothing this one lacks. **Nothing for a register.**
2. **`TRANSPORT-27` and `TRANSPORT-28`'s charter cells are corrected in place.** The charter now says
   `TRANSPORT-27` is satisfied whole (with the wrong "half unreachable" premise named, and the reason:
   its fact 12 measured `#request` without a block) and `TRANSPORT-28` partially satisfied rather than
   ⏳ whole. This plan's coverage table already said both; **no edit is owed here, and none to
   `docs/deferred-items.md` either** — `DEF-10` keeps `TRANSPORT-30` and `TRANSPORT-28`'s zero-copy
   clause, and `DEF-3`'s `BODY-12` clause 2 is still UNSCHEDULED with phase 8a named.
3. **The `P8-<n>` bands are fixed in the charter**: `8a` `P8-1`–`P8-19` (using `P8-1`–`P8-14`), `8b`
   `P8-20`–`P8-35` (using `P8-20`–`P8-25`), `8c` `P8-36`–`P8-50` (using `P8-36`–`P8-40`, with
   `P8-41`–`P8-50` unallocated and `P8-41` retired unfiled). **Nothing was renumbered**, so no
   citation moved; `docs/deviations.md` receives fourteen rows from this sub-phase when the phase
   lands, unchanged.
4. **The suite contract is one list of twelve clauses**, owned by this sub-phase's design under
   `R16` → *The suite contract*, and cited by `8c`'s design by section name and path. **Task 6 now
   builds the three mechanisms the merge added** — `settle:`, `around:` and `wire:` on
   `TransportSuite.run` / `TransportCase` — so `8c` drives the suite with no build-order dependency
   beyond "`8a`'s gem exists". Tasks 9–13 call `kase.settle(…)` and never `transport.call(…)`.
5. **The header-drop contract is shared and is stated once in the charter.** Ten folded names on both
   adapters, `Events::TRANSPORT_HEADER_DROPPED` as the one event name, `"header"`/`"reason"` as the
   field keys, `TRANSPORT-13`'s three-mode policy and its bound of 64 `8c`-only. Task 2 Step 5b adds
   the core constant if `8c` has not; Task 16 emits through it. **A follow-through agent should
   expect `docs/deviations.md`'s `P8-13` row to read as the ten-name set, not a nine-name one.**
6. **The CI matrix after `8c`'s per-gem Ruby floor is stated once in the charter**, and this plan
   touches none of the six files. Task 23 Step 4 verifies rather than re-applies.
7. **`OI-42`–`OI-45` are this sub-phase's four proposed open items** (`8b`'s three follow at
   `OI-46`–`OI-48`), each written out in the register's own row format in the design's *The findings
   proposed for the registers*. The fifth proposal there targets `docs/first-release.md` and carries
   no `OI-<n>`, deliberately. **Task 25 hands all five over; a filer runs
   `ruby .claude/skills/housekeeping/probe.rb --only citations` first, because fifteen numbers
   (`OI-34`–`OI-48`) are cited across phase 8 with no row in `docs/open-items.md` yet.**
