# Phase 8c — Asynchronous Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-transport-async_http` in full — `Adapter` (`.new`/`.over`, `#call`,
`#close`), `Endpoints`, `Clients`, `RequestMapper`/`RequestBody`, `ResponseMapper`/`ResponseBody`,
`Errors.wrap`, `DropPolicy` — plus the one phase-level type it and `8a` both need
(`Dexpace::TransportError < ::IOError`, in `dexpace-core`) and the one phase-0 gate edit its Ruby
floor collides with (`VERSIONS`, `tools/versions.rb`, the root `Gemfile`, `VersionsGate`,
`test:gems`). Ten requirement IDs — `TRANSPORT-7`, `8`, `9`, `12`, `13`, `21`, `23`, `ASYNC-6`,
`21`, `22` — nine MUST and one SHOULD, with `ASYNC-21` **N/A** per the design's §11.21 reading and
`TRANSPORT-8` **satisfied here** where §12 records it vacuous (`R14`, `OI-41`). No deferral is
filed; four existing deferred-items rows are picked up or reported against, named in each task.

**Architecture:** One dispatch path, eighteen steps, all inside one method
(`Adapter#call(request, options, cancellation)`), returning a `Dexpace::Async::Future` before
anything fallible runs (`TRANSPORT-21`). Steps 1–10 run on the caller's own fiber — mint the
pivot, check closed, check for a reactor, re-validate headers (`DEF-25`), drop framing headers
(`TRANSPORT-11`), drop wire-grammar violations (`TRANSPORT-12`/`13`), build the endpoint, fetch or
build the per-origin client — and route every raise through `rescue StandardError` to
`completer.fail`, which excludes `Async::Cancel`, `NoMemoryError`, `SystemExit`,
`SignalException` and `Interrupt` automatically because none of the five is a `StandardError`
descendant (no hand-written fatal list is needed). Steps 11–18 run inside a **child**
`Async::Task` (`Async::Task.current.async { … }`, never `Async { }`) wrapped in
`task.with_timeout(deadline)`: the native call, check-after-resume, response adaptation, and one
`ensure` that closes the native response unless delivered and — the one place this plan writes
no `rescue Async::Cancel`/`Async::Stop` — settles the pivot cancelled by inspecting `$!` inside
that same `ensure` and calling `completer.request_cancel(cancellation.reason)`, never
`completer.fail(CancelledError.new(...))` directly, because only `request_cancel` produces a
`Settlement` `Future#cancelled?` reports true for (`R13`). `Errors.wrap` is a table, not a `case`
chain, and passes a `Dexpace::` error through unwrapped.

**Tech Stack:** Ruby 3.3–4.0 for this gem alone (`P8-36`; the repository floor stays 3.2 for
every other gem), Minitest, RBS + Steep (the `async_http` target phase 0 already scaffolded),
RuboCop, SimpleCov, YARD. `dexpace-core` gains no new third-party dependency; this gem's own
`NFR-2` budget is spent on `async-http ~> 0.104`.

**Spec:** `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md`
(2278 lines, read in full), under the charter
`docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`.
`docs/product-spec/17-transport-adapter-conformance-contract.md` and
`docs/product-spec/18-asynchronous-runtime-adapter-contract.md` are the two normative chapters;
appendix C `:559-610` carries the canonical text and modal level of all ten IDs.

## Global Constraints

- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden** (`Dexpace/NoThreadInterrupt`),
  **in the test tree as well as in `lib/`**: phase 0's `.rubocop.yml` enables the cop
  repository-wide and excludes only `vendor/**/*`, `tmp/**/*`, `doc/**/*` and
  `test/fixtures/**/*`, so a gem's own `test/support/` file is scanned like any other. Nothing in
  this plan uses any of the three; every deadline is `Async::Task#with_timeout`, every
  cancellation is `Async::Task#cancel`, and every fixture thread is retired by closing the
  `Thread::Queue` or `TCPServer` it is blocked on and then `#join`ing with a bounded timeout.
- **No test in this plan sleeps to wait for a state change.** A blocking assertion uses a
  `Thread::Queue` the fixture server controls (cancellation tests), the reactor's own scheduling
  (Sync/Async blocks), or a measured elapsed-time assertion with a two-order-of-magnitude margin
  (the one `with_timeout` duration check). **There is exactly one `sleep` in this plan**: the 1 ms
  per-attempt pause in the HTTP/2 fixture's own bounded bind-readiness loop (Task 14), which waits
  on a fixture socket being bound and never on adapter behaviour.
- **`rescue Async::Cancel` and `rescue Async::Stop` appear in no file this plan writes.** Every
  place the design's `R13` needs to notice a cancellation, this plan inspects `$!` inside an
  `ensure` clause instead — that is an inspection, not a rescue, and it never stops the exception
  from propagating.
- **`Async::Task#cancel`, never `#stop`.** `#stop` is a deprecated alias (`OI-40`); every call site
  in this plan spells it `#cancel`.
- **`URI::RFC3986_PARSER` is never called by this gem.** `Dexpace::Request#url` already arrives as
  a frozen `URI::Generic` parsed by phase 1's `Dexpace::URL.parse!` (which pins
  `URI::RFC3986_PARSER` itself); this gem hands that object straight to
  `Async::HTTP::Endpoint.new`, never through `Async::HTTP::Endpoint.parse`, which routes through
  `URI.parse` and therefore `URI::DEFAULT_PARSER` (design step 9, verified fact 13).
- **`Thread::Mutex` is held nowhere across a suspension point.** This gem's two mutexes —
  `Clients`'s per-origin fetch-or-insert and `Dexpace::Closeable`'s close latch — each guard a
  critical section with no I/O and no `await`/`with_timeout`/`native.call` inside it.
- **`downcase` takes no arguments** (`Dexpace/NoLocaleCaseFold`). `DropPolicy` folds header names
  with `name.to_s.downcase`, never `downcase(:turkic)` or similar.
- **Bytes on the wire are BINARY.** Every chunk this gem yields outbound or reads inbound is
  retagged with `String#b`, never `force_encoding`.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`).
- **`Regexp.new(source, timeout:)`, never the bare literal or `Regexp.timeout`.** This plan writes
  exactly one regexp (the RFC 7230 token predicate, Task 6) and it carries its own timeout even
  though its character class cannot backtrack.
- **No constant outside `Dexpace::` and the fixed stdlib allowlist appears in any public
  signature under `sig/`** (`NFR-11`, `gates:rbs_surface`). `.over(client)` takes a gem-local
  `_Client` interface, never `Async::HTTP::Client`; `Adapter#call` returns `Dexpace::Async::Future`
  and takes `Dexpace::Request`, `Dexpace::RequestOptions?`, `Dexpace::Cancellation`, mentioning no
  foreign constant.
- **Formatting:** double quotes, 2-space indentation, 100 columns, `consistent_comma` trailing
  commas — this repository's RuboCop baseline throughout.
- **Domain model construction pattern, where it applies here.** `Adapter`, `Clients`, `Endpoints`,
  `Errors`, `RequestBody`, `ResponseBody` are service objects, not `Data` values — none of the
  six holds a set of fields whose only job is comparison, and three of the six (`Adapter`,
  `Clients`, `ResponseBody`) hold genuinely mutable state (a close latch, a per-origin `Hash`, a
  read cursor). `DropPolicy` is the one object here that is data-shaped, and Task 7 states
  explicitly why it still is not itself frozen at the top level.

### Commands

```bash
bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/<path>_test.rb
(cd gems/dexpace-transport-async_http && bundle exec rake test)
bundle exec ruby -w gems/dexpace-core/test/dexpace/<path>_test.rb        # the one core suite this plan touches
(cd gems/dexpace-core && bundle exec rake test)
bundle exec rake                                                        # all seventeen gates
bundle exec rake gates:gemspec_audit gates:require_allowlist gates:clean_bundle
bundle exec rake gates:versions
bundle exec rake rubocop
bundle exec rbs collection install                                      # phase 0's CI runs exactly this
bundle exec rake rbs:validate
bundle exec rake steep
bundle exec rake gates:rbs_surface gates:sig_diff gates:surface_snapshot
bundle exec rake surface:regenerate                                     # deliberate; Task 19 only
bundle exec rake yard
bundle exec rake bundler_audit
```

### What was verified during planning

**One interpreter is installed in this session: Ruby 3.4.10, plus the pinned scratchpad
`GEM_HOME`** (`async-http` 0.104.0, `async` 2.45.1, `async-pool` 0.12.0, `protocol-http` 0.71.0,
`protocol-http1` 0.41.0, `protocol-http2` 0.28.0, `io-event` 1.22.0). **The 3.3 and 4.0 columns
have not been run for anything below**, which is this plan's own open question 8 and Task 1
installs both. Re-confirmed directly, against the exact GEM_HOME the task handed me, rather than
trusted from the design's prose:

1. **`async-http`'s and `protocol-http`'s `required_ruby_version` are both `>= 3.3`** —
   `Gem::Specification.find_by_name("async-http").required_ruby_version` and the same for
   `protocol-http`. `R15`'s collision is real on this exact install, not only as the design
   measured it on 2026-09-11.
2. **`require "async/http"` alone already defines `Protocol::HTTP::Body::Readable` and
   `Protocol::HTTP::Request`** — `defined?(Protocol::HTTP::Body::Readable)` and
   `defined?(Protocol::HTTP::Request)` both report `"constant"` after nothing but
   `require "async/http"`. **This is the fact that resolves a real inconsistency in the design,
   recorded under Discrepancies below**: the design's own "require set, stated exactly" lists
   `protocol/http/body/readable` and `protocol/http/request` as files this gem requires directly,
   in the same paragraph that says reaching a transitive gem's class directly "would be the
   adapter version of the mistake SEAM-1 bars core from making." This plan follows the second
   sentence: no file in this gem carries `require "protocol/http/..."` of any kind; every
   `Protocol::HTTP::` constant is reached through `async-http`'s own already-loaded surface.
3. **A child task's `ensure` sees `$!.is_a?(Async::Cancel)` when a parent cancels it, `rescue
   StandardError` never runs on that path, and `Async::Cancel` does not propagate through
   `#wait`.** Reproduced with a minimal `Async` script under the scratchpad `GEM_HOME`: a task
   cancelled from its parent hits `ensure` with `$!` classed `Async::Cancel`, an explicit
   `rescue *[StandardError]` guard never fires, `task.cancel(cause: :my_reason)` makes
   `$!.cause == :my_reason` inside that same `ensure`, and `parent.async { … }.wait` on a
   cancelled child returns `nil` with `child.status == :cancelled` — it does **not** re-raise
   `Async::Cancel` to the waiter. That last clause is not in the design's own verified-facts list
   and is what makes `R13`'s "$! inspected inside an ensure, never rescued" mechanism sound: a
   parent that later `.wait`s on this gem's exchange task cannot receive a surprise
   `Async::Cancel` through that call.
4. **`Async::Task#cancel`'s signature is `(later = false, cause: $!)`, and `#stop` is a deprecated
   alias**, both reproduced directly: `Async::Task.instance_method(:stop).owner` reports
   `Async::Node`, and `async-2.45.1/lib/async/node.rb` carries the `@deprecated` tag immediately
   above `def stop(...) = cancel(...)`.
5. **`Protocol::HTTP::Body::Readable#each`'s own default implementation closes the body in its own
   `ensure`, on both normal exhaustion and a mid-stream error** — read directly from
   `protocol-http-0.71.0/lib/protocol/http/body/readable.rb`: `each` is `while chunk = self.read;
   yield chunk; end` wrapped in `begin/ensure; self.close(error); end`. This plan's `ResponseBody`
   therefore does **not** delegate to the native body's own `#each` (which would double as an
   implicit early close this gem's own `Dexpace::Closeable` latch should own instead); it drives
   `@native.read` directly in a `while` loop and closes through its own latch, matching the
   design's literal "one native `#read` per yield" and keeping the two close paths from racing.
6. **`Protocol::HTTP::Client#call` takes exactly one `Protocol::HTTP::Request`, and
   `Protocol::HTTP::Request.new`'s parameters are `scheme, authority, method, path, version,
   headers, body, protocol, interim_response`, all positional-optional** —
   `Async::HTTP::Client.instance_method(:call).parameters` is `[[:req, :request]]`;
   `Protocol::HTTP::Request.instance_method(:initialize).parameters` matches the nine names
   above. `Protocol::HTTP::Headers.new` takes one positional `fields` array of `[name, value]`
   pairs. Task 8 builds the request object against these exact positions.
7. **`Dexpace::Configuration` has no existing timeout or connection-limit key** — phase 5a's
   shipped `Configuration::Keys` is `MAX_RETRY_ATTEMPTS`, `LOG_LEVEL`, `HTTP_PROXY`,
   `HTTPS_PROXY`, `NO_PROXY`, `MAX_MATERIALIZED_BYTES`, `MAX_TRACKED_CONTEXTS` — read directly
   from the phase 5a plan's own `Keys` module rather than assumed absent. **Corrected 2026-09-12:**
   this said "both of this gem's configuration reads are therefore genuinely new keys". Only one is.
   `TRANSPORT_CONNECTION_LIMIT` is genuinely this gem's — `Net::HTTP` is constructed per call and has
   no pool to bound, so `8a` will never want it. The **timeout** read is `8a`'s
   `Keys::REQUEST_TIMEOUT`, which `8a`'s Task 2 declares and which this gem reads rather than
   re-spelling: this document's own design says "`8c` reads the same key rather than declaring a
   second spelling", and the charter states it once under *Shared transport contracts* item 4. The
   hazard the original sentence was guarding against — "a key `8a` independently invents for the same
   concept" — is exactly what a second spelling here would have created, from this side.
8. **`Dexpace::ResponseBody` already exists in `dexpace-core` (phase 3b) and is not what this gem
   uses**, read directly from the phase 3b plan: it is a handle over a `BufferedSource` the
   transport built with `.wrapping`, and closing it closes that `BufferedSource`, which in turn
   closes what it wraps. This gem's own `.over`-built `BufferedSource` (chosen specifically to
   avoid `OI-9`'s one-byte-per-read defect in `.wrapping`) does **not** close what it iterates —
   `.over`'s own design note says so in as many words — so reusing core's `Dexpace::ResponseBody`
   over a `.over`-built source would leak the native connection on every close. This gem's
   `ResponseBody` therefore implements `Dexpace::Body`'s module contract directly and holds
   `@native` itself, closing it in its own `#release`; it is a different class from
   `Dexpace::ResponseBody` and lives in a different namespace, on purpose.
9. **`TRANSPORT-27`'s canonical text fixes the unknown-length sentinel as `-1`, never `nil`** —
   `grep -n '^| TRANSPORT-27 ' docs/product-spec/appendix-c-…md` reads "an absent/invalid
   Content-Length SHOULD map to the SDK's unknown-length sentinel (**-1**)", matching phase 3b's
   `BODY-35` (`Dexpace::Body#content_length` is `-1`, never `nil`, "an ID-bearing rule beats the
   styleguide's nil-as-absence default"). **This is the design's second concrete error, recorded
   under Discrepancies**: its own "object model" section names the method `#length` and says
   "nil is TRANSPORT-27's unknown-length sentinel, free." This plan's `ResponseBody` implements
   `#content_length` (the name every other `Dexpace::Body` in the codebase uses, and the name
   `Response#content_length`, if such an accessor is added later, would read), mapping a native
   `nil` length to `-1`.

The following were confirmed by reading the shipped design/plan of the phase that built them, not
re-derived:

- **`Dexpace::HeaderSyntax.validate_name!(name) -> String`**, `.validate_outbound_value!(value,
  name:) -> String`, `.validate_inbound_value!(value, name:) -> String`, `.valid_name?`,
  `.valid_outbound_value?`, `.escape(name) -> String`, all `module_function`. Each `validate_*!`
  raises `Dexpace::InvalidArgumentError` naming the escaped header and the requirement ID
  (`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md:684-751`).
- **`Dexpace::Async::Completer#fail(error)` requires `error.is_a?(::Exception)`**, settles
  `Settlement.failure(error)`, and — the method this plan's `R13` ensure calls instead —
  **`#request_cancel(reason = nil)` is public, idempotent (returns `false` once already settled),
  builds `Dexpace::CancelledError.new(reason)` itself, and fires every registered `#on_cancel`
  hook** (`…phase2…-seam-foundations.md:1902-1935`). `Future#cancelled?` reads
  `@completer.outcome&.cancelled`, which only `request_cancel`'s `Settlement.cancellation(...)`
  sets — `Completer#fail` with a `CancelledError` instance would **not** make `#cancelled?` true,
  which is why this plan never calls `fail` for a cancellation.
- **`Dexpace::Async::Completer#on_cancel { |reason| … }` returns `self`, not a subscription**
  (`…phase2…-seam-foundations.md:1938-1947`), and `#request_cancel` steals and clears the hook list
  when it settles. There is nothing to detach and nothing to leak: the `Completer` is minted per
  call. This is the opposite of the token's contract on the next line, and the two are easy to
  confuse — Task 11's bridge wires both and detaches only the token's.
- **`Dexpace::Cancellation#on_cancel { |reason| … }` returns a `Subscription` with `#detach`**,
  fires its block exactly once even under composition, and `#check!` raises
  `Dexpace::CancelledError, reason` (`…phase2…-seam-foundations.md:1280-1349`).
- **`Dexpace::Closeable#initialize_closeable(owned:)` sets a frozen `@dexpace_owned` and a
  `Thread::Mutex`-guarded `@dexpace_closed` flag; `#close` flips the flag inside the mutex and
  calls the private `#release` outside it, only when `owned`** (`…phase2…-seam-foundations.md:532-583`).
  `Dexpace.close_quietly(resource)` rescues `StandardError` only, from `#close` itself, and
  always returns `nil`.
- **`Dexpace::AsyncTransport.register(key, factory, core:)` and `.conforms?(object)` = "responds
  to `#call` with arity 3"** (`…phase2…-seam-foundations.md:3854-3893`); `Registry#register`
  raises on a key collision with a *different* factory and is silent on the same one twice, and
  the skew assertion is inside `register` itself, so `core:` is checked at require time.
- **`Dexpace::Response.builder`** takes `.request=`, `.protocol=` (coerces a `String`),
  `.status=` (coerces an `Integer`), `.headers=`, `.body=`, `.reason=`, and `.build` raises
  `Dexpace::InvalidArgumentError` naming the first missing required field
  (`…phase1…-core-http-domain-model.md:3170-3240`). `Dexpace::Headers.inbound_builder` exists
  specifically for building headers from a response, under `HTTP-19`'s more lenient grammar.
- **`Dexpace::Instrumentation.contain(logger, event:) { … } -> nil`** rescues `StandardError` from
  the block, emits one `WARNING`-severity diagnostic naming the block's own failure, and swallows
  a *second* failure from the emission itself; it does **not** rescue anything the block does not
  raise, so an intentional `logger.event(severity).…emit` call inside the block is what
  `DropPolicy` puts there (`…phase5b…-logging-and-redaction.md:2419-2541`). Every real
  call site in that same plan (`close_quietly`, `Hooks.notify`, the request/response logging
  step) wraps a `logger.event(Severity).event(Events::SOME_CONSTANT).field(...).emit` call in
  exactly this shape, which `DropPolicy#report` (Task 7) matches.
- **`Configuration#integer(name, default:)` and `#duration(name, default:)`** both return `nil`
  only when no default is given and no source has the key
  (`…phase5a…-configuration.md:2771-2853`).

## This plan's open questions, resolved

The design's own eight, plus one this plan found while writing Task 7 (marked separately, since
it is not one of the design's eight and this plan does not pretend the design asked it).

1. **`gem_rbs_collection` coverage for `async-http`.** *Not resolvable from this sandbox* (no
   network access to the collection's index). Task 17 checks at implementation time and writes
   whichever row it finds; either way no foreign constant reaches a public signature, per the
   design's own three clauses, so the public-surface gates are unaffected regardless of the
   answer.
2. **Who edits `VERSIONS`/`gates:versions` for the per-gem floor.** *This plan's own PR carries
   it* (Task 3), against the design's own recommendation that it be a phase-level task. Reason:
   without it, `bundle install` on the repository's 3.2 CI row fails outright the moment this
   gem's gemspec exists (the root `Gemfile` adds every `gems/*` directory unconditionally — a
   fact the design's own R15 section does not mention, recorded under Discrepancies), so this
   gem cannot be built, tested, or even `bundle install`ed standalone without the edit. If `8a` or
   `8b` lands a phase-level PR with the same edit first, Task 3 becomes a verification step
   instead of a fresh diff — its own steps say so.
3. **`connection_limit`'s key name and default.** *A new key*,
   `Configuration::Keys::TRANSPORT_CONNECTION_LIMIT`, default **8** (matching the design's own
   number, chosen because verified fact 9 measured the library's own default as unbounded).
   Verified fact 7 above confirms no existing key already names this concept, so there is no
   collision to avoid — only one to *not create* going forward, stated in Task 8's own comment so
   `8a` knows the name is taken and the concept it names.
4. **Where `DropPolicy` lives.** *This gem*, per the design's own recommendation, confirmed:
   `OI-8`'s shape (public, `NFR-4`-locked, no caller yet) is exactly what a core-resident policy
   with one external caller would become, and moving it later widens rather than narrows.
5. **The h2 multiplexing test.** *Ten concurrent streams on one connection*, chosen because it is
   comfortably above the eight-connection default `connection_limit` this gem sets for HTTP/1.1
   (so the test is unambiguously about one h2 connection's own multiplexing, not about the pool),
   and small enough to stay inside the 30-second suite budget.
6. **Per-run vs per-suite certificate generation.** *Per run*, per the design's own
   recommendation: an RSA-2048 keygen costs ~100 ms (measured incidentally in the design's own
   fact 3), and per-suite caching needs a `.gitignore` entry and an invalidation story this plan
   has no use for.
7. **The `ASYNC-7` contrast assertion's shape.** *Two measured behaviours, not two README
   strings.* `8b`'s and this gem's own conformance suites each assert, independently, that
   cancelling a native primitive mid-read aborts within a bounded time on their own adapter;
   Task 16 states the exact assertion this gem contributes and why comparing prose is the wrong
   test.
8. **Re-running the facts on 3.3 and 4.0.** Task 1 installs both and re-runs every numbered fact
   above; this plan states in advance what changes if one fails (see Task 1's own step 4) rather
   than leaving the reader to guess.

**A ninth, not the design's own, found while writing Task 7.** `DEF-41`'s row says "phase 8
writes a small `Data` over both [ingredients]," which if read as "`DropPolicy` itself is a
`Data.define` value" collides with `Data`'s own automatic freeze-on-construction: a frozen
top-level object cannot later reassign an ivar to a new snapshot, which `DropPolicy`'s bounded
per-name latch must do on every distinct new header name. *Decision:* `DropPolicy` is a plain
class (not `Data.define`) that holds one frozen `Data` snapshot in one ivar, replaced wholesale
under its own mutex on the write path and read without a lock — the shape
`concurrency-and-async/f414b864`'s note prescribes for exactly this kind of mutable state, and the
one already used by phase 2's own `Registry`. Task 7 states this in the code's own comment so a
reviewer comparing this plan against the design's one-line description does not read the shape
choice as a deviation from an instruction the design never gave in enough detail to follow
literally.

## Task order and dependency chain

Nineteen tasks. Two hard ordering rules:

**External:** the gemspec's `async-http` dependency line (Task 2) lands before the first
`require "async/http"` anywhere in this gem's `lib/` (Task 6 is the first), because phase 0's
require-allowlist audit permits a third-party `require` only for the exact dependency name (or
its `-`-to-`/` form) the gemspec already declares (verified directly against
`RequireAllowlist.third_party_for`, which reads `spec.runtime_dependencies`).

**Internal:** `Dexpace::TransportError` (Task 4) lands before `Errors.wrap` (Task 6), which lands
before `Adapter` (Task 9), which lands before every test task that drives it (Tasks 10–16).

**Fifteen of the nineteen tasks open with a failing test; four deliberately do not, and the
absence is a decision rather than an oversight.** Task 1 gathers evidence and writes two fixture
doubles with nothing yet to assert against; Task 17 configures `sig/`, the Steep target and
`rbs_collection.yaml`; Task 18 runs existing gates on three interpreters; Task 19 wires, hands
over and (once `8a` exists) drives someone else's suite. None of the four adds behaviour this gem
could assert, and each instead states the exact gate output it expects — which is the same
contract a failing test gives, expressed through the gate that already exists.

1. Matrix and floor fact re-verification, plus this gem's local test doubles.
2. The gemspec, the skeleton's entry-file wiring, and the ordering gate.
3. The phase-0 gate edit for a per-gem Ruby floor (`R15`, `OI-38`).
4. `Dexpace::TransportError < ::IOError` in `dexpace-core` — the phase-level type.
5. `Endpoints` — `URI::Generic` → `Async::HTTP::Endpoint`, TLS defaults, the origin key.
6. `Errors.wrap` and its table.
7. `DropPolicy` — `TRANSPORT-13`, `OBS-19`, `DEF-41`.
8. `Clients` — the per-origin map, `Configuration` reads, `#close` over `pool.close` (`P8-37`).
9. `RequestMapper` and `RequestBody` — `DEF-25`'s raise, `TRANSPORT-10`/`11`/`12`/`26`'s drops.
10. `ResponseMapper` and `ResponseBody` — `TRANSPORT-14`/`24`/`27`, the pull-per-demand body.
11. `Adapter` — construction, the eighteen-step dispatch path, the `R13` ensure discipline.
12. `TRANSPORT-7`/`9` and `ASYNC-6` direction two — the orphan-close conformance tests.
13. `TRANSPORT-8` and `ASYNC-6` direction one — the parent-cancellation-versus-timeout pair.
14. The in-process HTTP/2 fixture, plaintext and TLS.
15. `TRANSPORT-12`/`13` dispatched over both protocols.
16. `TRANSPORT-21`/`23`, `ASYNC-21`/`22`, and the `ASYNC-7` contrast.
17. `sig/`, the Steep target, `rbs_collection.yaml`.
18. `gates:clean_bundle` on 3.3/3.4/4.0, the CI matrix's 3.2 exclusion, `first-release.md`'s lines.
19. The second-driver conformance convergence, the knowledge note, final wiring.

---
## Task 1: Matrix and floor fact re-verification, plus this gem's local test doubles

**Requirement IDs:** none directly; the evidence-gathering step every prior phase's plan opens
with.
**Design:** "Verified Ruby facts this sub-phase is built on"; open question 8.

- [ ] **Step 1: Install the 3.3 and 4.0 columns**

```bash
mise install ruby@3.3.8 ruby@4.0.6   # exact patch versions per whatever mise resolves at
                                       # implementation time; the matrix cares about the minor
```

- [ ] **Step 2: Re-run the design's thirteen verified facts on both, against the same scratchpad
  `GEM_HOME`'s package set**

```bash
for rb in 3.3.8 4.0.6; do
  ~/.local/share/mise/installs/ruby/$rb/bin/ruby -S bundle exec ruby \
    -e 'require "async/http"; p RUBY_VERSION; p Gem::Specification.find_by_name("async-http").required_ruby_version'
done
```

Also re-run this plan's own facts 3–6 above (the `$!`/`ensure`/`#wait` script, the
`Async::Task#cancel` introspection, the `Readable#each` source read, the
`Client#call`/`Request.new` parameter introspection) on both interpreters, using the scratch
scripts under `scratchpad/p8c/*.rb` the design's own Reference section names.

**If any fact diverges on 3.3 or 4.0** (per open question 8): write a note under
`docs/knowledge/notes/concurrency-and-async.md` or `transport-adapter.md` recording exactly what
changed and on which interpreter, rather than editing this plan or the design — the design's own
discipline for `observability/65191069`'s single-interpreter caveat, applied here. Nothing in this
plan changes as a result unless a fact this plan's own code depends on (facts 3, 4, 5, 6, 9 above)
turns out false, in which case the affected task is revisited before it is implemented, not after.

- [ ] **Step 3: Write the fixture doubles every later task shares**

`gems/dexpace-transport-async_http/test/support/recording_body.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      module Test
        # R13's counting double over Protocol::HTTP::Body::Readable. Counting the close beats
        # watching the socket: "the connection looked released" is not an assertion, and this is.
        class RecordingBody < ::Protocol::HTTP::Body::Readable
          attr_reader :close_count, :close_errors

          def initialize(chunks, length: nil)
            super()
            @chunks = chunks.dup
            @length = length
            @close_count = 0
            @close_errors = []
          end

          def length = @length

          def read
            @chunks.shift
          end

          def close(error = nil)
            @close_count += 1
            @close_errors << error
            super
          end
        end
      end
    end
  end
end
```

`gems/dexpace-transport-async_http/test/support/holding_server.rb` — a raw `TCPServer` that
writes a status line and headers, then blocks on a `Thread::Queue` the test controls before
writing the body, so a cancellation test can provoke cancellation from a provably-blocked state
with no sleep:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "socket"

module Dexpace
  module Transport
    module AsyncHTTP
      module Test
        # A fixture that decides when the client leaves the "waiting for body" state, so a
        # cancellation test needs no sleep to "get into" it -- it provokes cancellation only
        # after this server confirms (via #release) that it is holding the connection open.
        class HoldingServer
          def initialize
            @server = TCPServer.new("127.0.0.1", 0)
            @gate = Thread::Queue.new
            @accepted = Thread::Queue.new
            @thread = Thread.new { serve }
          end

          def port = @server.addr[1]

          # Blocks the calling (test) thread/fiber until this server has accepted a connection
          # and written the response head. Safe to call from inside a reactor: this thread is
          # not the reactor's, so the test's own fiber does not need to yield for it.
          def wait_for_accept
            @accepted.pop
          end

          def release(body = "released")
            @gate.push(body)
          end

          # No Thread#kill anywhere: phase 0's Dexpace/NoThreadInterrupt cop is enabled
          # repository-wide and .rubocop.yml excludes only vendor/, tmp/, doc/ and
          # test/fixtures/** -- a gem's own test/support/ file is scanned like any other, and
          # `rake rubocop` is findings-fatal. The thread is retired by closing what it is blocked
          # on instead: Thread::Queue#close wakes a blocked #pop with nil and TCPServer#close
          # wakes a blocked #accept with IOError, both measured by phase 8's charter (fact 13).
          def close
            @gate.close
            @server.close
            @thread.join(1)
            nil
          end

          private

          def serve
            socket = @server.accept
            socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n")
            @accepted.push(true)
            body = @gate.pop # nil once #close has closed the queue: the fixture is shutting down
            socket.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}") if body
          rescue IOError, Errno::EBADF, Errno::ECONNRESET, ClosedQueueError
            nil
          ensure
            socket&.close
          end
        end
      end
    end
  end
end
```

**The forbidden three bind this file too, and that is checked rather than assumed.** Phase 0's
`.rubocop.yml` enables `Dexpace/NoThreadInterrupt` with an `Exclude:` of `vendor/**/*`,
`tmp/**/*`, `doc/**/*` and `test/fixtures/**/*` only, so a `Thread#kill` in a gem's own
`test/support/` file is an offence and `rake rubocop` runs `--fail-level=convention`. Every
fixture in this plan therefore retires its thread by closing what that thread is blocked on — a
`Thread::Queue` or the `TCPServer` itself — and then `#join`s with a bounded timeout. That is also
the better fixture: a killed thread never runs the `ensure` that closes its socket.

- [ ] **Step 4: Run nothing yet — there is no code under test.** Confirm only that both files
  load: `ruby -Igems/dexpace-transport-async_http/test -e 'require "support/recording_body";
  require "support/holding_server"'` under the scratchpad `GEM_HOME`, expecting no output.

---

## Task 2: The gemspec, the skeleton's entry-file wiring, and the ordering gate

**Requirement IDs:** none new (`NFR-2`; boundary 7, boundary 8).
**Design:** "From phase 0 — the gates this gem meets first"; "Module layout"; "The registration
call and the skew assertion."

**Files:**
- Modify: `gems/dexpace-transport-async_http/dexpace-transport-async_http.gemspec`,
  `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http.rb`,
  `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/version.rb`
- Test: `gems/dexpace-transport-async_http/test/dexpace/transport/async_http_test.rb` (phase 0's,
  extended)

**This task is the ordering gate.** Every later task's first `require "async/http"` depends on
Step 3 landing first.

- [ ] **Step 1: Write the failing tests**

```ruby
  test "NFR-2: the gemspec declares dexpace-core plus exactly one third-party gem" do
    spec = Gem::Specification.load(
      File.expand_path("../../../dexpace-transport-async_http.gemspec", __dir__),
    )
    names = spec.runtime_dependencies.map(&:name).sort

    assert_equal(%w[async-http dexpace-core], names)
    dep = spec.runtime_dependencies.find { |d| d.name == "async-http" }
    assert_equal(["~> 0.104"], dep.requirements_list)
  end

  # P8-36. This gem's own floor is narrower than the repository's -- verified fact 1 above, and
  # the whole subject of Task 3.
  test "P8-36: this gem's required_ruby_version is >= 3.3, not the repository's 3.2 floor" do
    spec = Gem::Specification.load(
      File.expand_path("../../../dexpace-transport-async_http.gemspec", __dir__),
    )

    assert_equal(">= 3.3", spec.required_ruby_version.to_s)
  end

  test "the adapter registers itself against the async transport seam with a core version" \
       " assertion" do
    assert_includes(Dexpace::AsyncTransport.registered_keys, :async_http)
  end
```

- [ ] **Step 2: Run to confirm they fail**

Expected: FAIL on all three — no `async-http` dependency, `required_ruby_version` still `>= 3.2`,
no registration.

- [ ] **Step 3: Add the gemspec line and narrow the floor**

```ruby
spec.add_dependency "async-http", "~> 0.104"

# P8-36: narrower than DexpaceVersions.ruby_floor (the repository's 3.2). async-http 0.95.0 and
# async 2.38.0 both raised required_ruby_version to >= 3.3 on 2026-03-08; the highest release
# compatible with 3.2 is eleven minor versions behind the one every fact in this gem's design
# was verified against. A floor a gem declares must be a floor it is tested on (R15, OI-38).
# Task 3 is the phase-0 gate edit that makes this line coexist with gates:versions.
spec.required_ruby_version = ">= 3.3"
```

This **replaces** phase 0's `spec.required_ruby_version = ">= #{DexpaceVersions.ruby_floor}"`
line for this one gemspec only; every other gem's gemspec is untouched.

- [ ] **Step 4: Extend the entry file**

Keep phase 0's namespace/`VERSION` declaration verbatim above this. Add, in order:

```ruby
require "async/http"

require_relative "async_http/errors"
require_relative "async_http/drop_policy"
require_relative "async_http/endpoints"
require_relative "async_http/request_body"
require_relative "async_http/request_mapper"
require_relative "async_http/response_body"
require_relative "async_http/response_mapper"
require_relative "async_http/clients"
require_relative "async_http/adapter"

module Dexpace
  module Transport
    module AsyncHTTP
      # The ~> MAJOR.MINOR requirement on dexpace-core, derived rather than written twice
      # (design §2.4, boundary 8).
      CORE_REQUIREMENT = "~> #{Dexpace::VERSION.split(".").first(2).join(".")}"

      Dexpace::AsyncTransport.register(
        :async_http,
        ->(**options) { Adapter.new(**options) },
        core: CORE_REQUIREMENT,
      )
    end
  end
end
```

`Adapter`, `Errors`, `DropPolicy`, `Endpoints`, `RequestMapper`, `RequestBody`, `ResponseMapper`,
`ResponseBody`, `Clients` do not exist yet; Steps 5–13 write minimal
`raise ::NotImplementedError` stand-ins so this task's own tests can run in isolation, and each
later task deletes exactly one stand-in.

- [ ] **Step 5: Run the gate that this task exists for**

```bash
bundle exec rake gates:gemspec_audit gates:require_allowlist
```

Expected: `gates:gemspec_audit` sees a second gem (beside `dexpace-serde-json`, if `7a` has
landed) with a third-party dependency; `gates:require_allowlist`'s adapter extension now permits
`require "async/http"` (and `async-http`, its `-`-to-`/` form) for this gem specifically, because
`third_party_for` reads it straight off the gemspec `Step 3` just wrote. **`gates:clean_bundle`
and `gates:versions` are not run yet** — both fail until Task 3 lands, and that is the point of
running them again at the end of Task 3 rather than here.

---
## Task 3: The phase-0 gate edit for a per-gem Ruby floor

**Requirement IDs:** none new (`NFR-2`, `NFR-10`, `NFR-14`; `P8-36`, `OI-38`).
**Design:** `R15`'s "What has to change, named so it is not discovered at execution time"; open
question 2.

**Files:**
- Modify: `VERSIONS`, `tools/versions.rb`, `Gemfile`, `tools/versions_gate.rb`,
  `tasks/quality.rake`, `tasks/gates.rake`
- Test: `test/gates/versions_gate_test.rb` (phase 0's, extended),
  `test/fixtures/gates/versions/per_gem_floor_ahead/` (new fixture)

**Why this plan carries it rather than leaving it to a phase-level PR** (open question 2): the
root `Gemfile` phase 0 wrote adds **every** `gems/*` directory unconditionally
(`Dir.glob("gems/*", base: __dir__).each { |dir| gem File.basename(dir), path: dir }`). Bundler
checks `required_ruby_version` for every gem in the Gemfile at `bundle install` time, path gems
included — so the moment Task 2's Step 3 lands, `bundle install` on Ruby 3.2 fails for the
**entire workspace**, not only for this gem. This is a fact the design's own `R15` section does
not name (it addresses `gates:versions`, the CI matrix and `docs/first-release.md`, but not the
`Gemfile` itself), and it is why this task cannot be deferred past Task 2 without leaving the
repository's 3.2 CI row permanently red. If `8a` or `8b`'s own phase-level PR lands this edit
first, Step 3 below finds the `Gemfile` already conditional and Step 5's test already green, and
this task is a verification pass rather than a diff.

- [ ] **Step 1: Write the failing test**

```ruby
  test "rejects a per-gem floor ahead of what the gemspec declares" do
    found = VersionsGate.violations(File.join(FIXTURES, "per_gem_floor_ahead"))

    assert_includes(found.join("\n"), "dexpace-transport-async_http")
  end
```

Fixture `test/fixtures/gates/versions/per_gem_floor_ahead/`: a `VERSIONS` naming
`floor:dexpace-transport-async_http` as `3.3`, and that one gem's gemspec left at
`required_ruby_version = ">= 3.2"` — the mismatch the gate must catch.

- [ ] **Step 2: Run to confirm it fails**

Run: `ruby -Itest test/gates/versions_gate_test.rb`
Expected: the new test fails — today's `gem_violations` reads only `value("ruby", "floor",
versions)`, a single global floor, so it reports every gem against `>= 3.2` and never notices a
per-gem row exists at all.

- [ ] **Step 3: Add the per-gem floor line to `VERSIONS`**

```
ruby floor                        3.2
ruby floor:dexpace-transport-async_http  3.3
ruby matrix                       3.2 3.3 3.4 4.0
```

**Why `floor:<gem-name>` and not the design's own four-token sketch
(`ruby floor dexpace-transport-async_http   3.3`):** `VERSIONS`'s existing `RECORD` regex is
`/\A(kind)[ \t]+(name)[ \t]+(value)[ \t]*\z/` — exactly three tokens after the kind. A fourth
token collapses into the value field of the *existing* `floor` row's own lookup
(`DexpaceVersions.value("ruby", "floor")` would return everything after the second token,
`"dexpace-transport-async_http   3.3"`, an unparsed string) rather than creating a second,
independently-keyed record. Colon-joining the gem name into the `name` column needs no change to
the regex, to `.records`, or to any existing `.value` call site — it is additive.

- [ ] **Step 4: Add the per-gem reader to `tools/versions.rb`**

```ruby
  # A per-gem floor when one exists, else the global floor (design R15). Colon-joined into the
  # `name` column so the three-token VERSIONS grammar needs no change.
  def ruby_floor(gem_name = nil)
    return value("ruby", "floor") if gem_name.nil?

    begin
      value("ruby", "floor:#{gem_name}")
    rescue ::KeyError
      value("ruby", "floor")
    end
  end
```

This **replaces** the existing zero-argument `def ruby_floor = value("ruby", "floor")` — every
existing call site (`Gemfile`, `gates:versions`) that calls it with no argument is unaffected.

- [ ] **Step 5: Make the root `Gemfile` skip a gem this Ruby cannot satisfy**

```ruby
Dir.glob("gems/*", base: __dir__).sort.each do |dir|
  name = File.basename(dir)
  floor = Gem::Version.new(DexpaceVersions.ruby_floor(name))
  next if Gem::Version.new(RUBY_VERSION) < floor

  gem name, path: dir
end
```

Without this, `bundle install` on the 3.2 CI row raises
`Bundler::GemVersionPromoter`/`Gem::RubyVersionMismatch`-shaped errors for the whole workspace the
moment Task 2 lands, per this task's own opening paragraph.

- [ ] **Step 6: Teach `VersionsGate.gem_violations` the per-gem floor**

```ruby
  def gem_violations(root, versions)
    Dir.glob(File.join(root, "gems/*")).sort.flat_map do |dir|
      name = File.basename(dir)
      declared = DexpaceVersions.value("gem", name, versions)
      floor = ">= #{DexpaceVersions.ruby_floor(name, versions)}"    # NOTE: ruby_floor's third arg
      spec = Gem::Specification.load(File.join(dir, "#{name}.gemspec"))
      # … the rest of the existing method body, unchanged, reading `floor` instead of the old
      # single `">= #{DexpaceVersions.value("ruby", "floor", versions)}"` local.
    end
  end
```

`DexpaceVersions.ruby_floor` gains a third, optional `path` positional to match every other
reader in the file (`value(kind, name, path = PATH)`); Step 4's version above is extended:

```ruby
  def ruby_floor(gem_name = nil, path = PATH)
    return value("ruby", "floor", path) if gem_name.nil?

    begin
      value("ruby", "floor:#{gem_name}", path)
    rescue ::KeyError
      value("ruby", "floor", path)
    end
  end
```

- [ ] **Step 7: Make `test:gems` skip a gem's suite on a Ruby below its own floor**

In `tasks/quality.rake`:

```ruby
namespace :test do
  task :gems do
    require_relative "../tools/versions"
    excluded = Dir.glob("gems/*").select do |dir|
      Gem::Version.new(RUBY_VERSION) <
        Gem::Version.new(DexpaceVersions.ruby_floor(File.basename(dir)))
    end
    files = FileList["gems/*/test/**/*_test.rb"]
            .reject { |f| excluded.any? { |dir| f.start_with?("#{dir}/") } }
    run_suite(files, Dir.glob("gems/*/lib").sort + %w[test], coverage: true)
  end
end
```

- [ ] **Step 7b: Make `gates:clean_bundle` skip a gem this Ruby cannot satisfy**

`test:gems` is not the only task that would fail on the 3.2 row. Phase 0's `gates:clean_bundle`
iterates a hard-coded `CLEAN_BUNDLE_ENTRIES` hash of all six gems and, for each, writes a scratch
`Gemfile` and runs `bundle install` — and Bundler refuses to install a path gem whose
`required_ruby_version` the running interpreter does not satisfy. Without this the 3.2 row is red
for the same reason Step 5 exists, and Task 18's Step 2 (which expects one *fewer* isolated gem on
3.2) has nothing to observe. In `tasks/gates.rake`, inside the `:clean_bundle` task, after
`targets` is chosen:

```ruby
    targets = targets.reject do |name, _|
      Gem::Version.new(RUBY_VERSION) < Gem::Version.new(DexpaceVersions.ruby_floor(name))
    end
```

with `require_relative "../tools/versions"` beside the task's existing requires. The count in the
task's own closing `puts` is `targets.size`, so it reports the smaller number on 3.2 by itself.

**`gates:gemspec_audit` and `gates:require_allowlist` need no equivalent** — checked rather than
assumed: both only `Gem::Specification.load` a gemspec and read text under `lib/`, and neither
installs or loads the gem, so both pass on 3.2 with this gem present. The design's `R15` lists all
four tasks as needing the exclusion; only two of the four actually do, and the other two are left
alone rather than given a skip they do not need.

- [ ] **Step 8: Run the test to confirm it passes, then the full gate set this task touches**

```bash
ruby -Itest test/gates/versions_gate_test.rb
bundle exec rake gates:versions gates:gemspec_audit gates:require_allowlist test:gems
```

Expected: all green on 3.4.10. `gates:versions` now reports this gem's `>= 3.3` as agreeing with
its own per-gem `VERSIONS` row rather than the global one; `test:gems` still runs this gem's own
suite here (3.4.10 satisfies its 3.3 floor) and will skip it only on the 3.2 row, which Task 18
verifies directly.

- [ ] **Step 9: State the matrix this task leaves behind, for `8a` and `8b` to align to**

The other two sub-phase plans touch the same four files if they do this independently, so the
end state is written out here once rather than inferred from a diff:

| | After this task |
|---|---|
| `VERSIONS` | unchanged except for one added line, `ruby floor:dexpace-transport-async_http  3.3`, beside the global `ruby floor  3.2`. `ruby matrix` still reads `3.2 3.3 3.4 4.0`. |
| `.github/workflows/ci.yml` | **unchanged.** Four rows, every job on every row, every gate in some job. `gates:versions`'s matrix assertion and `ci_workflow_test.rb` both still pass unedited. |
| `tools/versions.rb` | `ruby_floor` gains two optional positionals: `ruby_floor(gem_name = nil, path = PATH)`. Every existing zero-argument call site is unaffected. |
| `Gemfile` | the `gems/*` glob skips a gem whose per-gem floor this interpreter does not meet. |
| `tools/versions_gate.rb` | `gem_violations` reads the per-gem floor instead of one global local. |
| `tasks/quality.rake` | `test:gems` rejects an excluded gem's test files. |
| `tasks/gates.rake` | `gates:clean_bundle` rejects an excluded gem from `targets`. |
| Effect on the 3.2 row | exactly one gem, `dexpace-transport-async_http`, is absent from `bundle install`, `test:gems` and `gates:clean_bundle`. Every other gem and every gate is unchanged on every row. |

**If `8a` or `8b` lands the same edit first**, Steps 3–7b find it already in place and this task is
a verification pass; the table above is then the thing to check against, not a second diff to
apply.

**No edit to `.github/workflows/ci.yml` is needed.** The workflow already runs the same steps on
every matrix row; the exclusion lives entirely inside the Ruby-side tasks this task just edited,
which each consult `RUBY_VERSION` for themselves. `ci_workflow_test.rb`'s "every listed gate
appears in some job" assertion is unaffected because no gate disappears from any job — one gem
is skipped *inside* several gates on one row, which is a different thing.

---
## Task 4: `Dexpace::TransportError < ::IOError` — the phase-level type

**Requirement IDs:** none new (`XCUT-4` branch (b); consumed by `TRANSPORT-20`/`21`/etc.).
**Design:** "Out of scope, explicitly" — "the phase-level task, **landed by `8a`'s Task 2**… lands in
`dexpace-core`, which is none of the three sub-phases' gems"; `P6-4`'s obligation; the charter's
*Phase-level tasks owned by no sub-phase*, item 1.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/error/transport_error.rb`,
  `gems/dexpace-core/sig/dexpace/error/transport_error.rbs`
- Test: `gems/dexpace-core/test/dexpace/error/transport_error_test.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`

**This is the one file in this plan that lands in a gem neither `8c` nor any of the other two
sub-phases owns, and as of 2026-09-12 it is normally *not* this plan's to write.** The charter
assigned it to "whoever lands first"; that produced two definitions with two shapes, and the charter
now fixes **`8a`'s Task 2 as the lander** — `8a` runs first under the recommended order, and
`dexpace-conformance` (`8a`'s gem) asserts against the class in the suite contract's clause 5, so the
suite cannot be written against a class that does not exist.

**So this task is normally a verification step, and writes the class only in the out-of-order case.**

- **If `Dexpace::TransportError` already exists** (the expected case): confirm the three properties
  Step 1's tests assert — `< ::IOError`, `include Dexpace::Error`, `#retryable?` always `true`
  (`XCUT-4` branch (b), `P6-4`) — plus `P3-3`'s sibling check against `Dexpace::StreamError`, and
  **keep the definition that is there**. `8a`'s shape is a **superset** of the one sketched below: it
  adds an optional `phase:` keyword (`Symbol?`, one of `:connect`/`:write`/`:read`/`:close`, for
  diagnostics only and never branched on by `RETRY-2`'s capability query) and a default message.
  **This gem needs nothing that shape lacks**: `Errors.wrap` (Task 6) constructs it positionally as
  `Dexpace::TransportError.new("#{error.class}: #{error.message}")` at every site, which the optional
  keyword leaves untouched, and all four of Step 1's assertions pass against it unchanged. Run the
  test file, confirm green, and proceed to Task 5.
- **If it does not exist** (`8c` executing before `8a`): write it as Steps 3–5 describe, *including*
  `8a`'s `#phase` reader and default message, so the two gems never carry two shapes and `8a`'s Task 2
  becomes the no-op confirmation its own preamble describes. The sketch below is the minimum this gem
  depends on, not the whole of what the phase lands.

Either way the class is reviewed once, at the **phase-level PR**, and never twice.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# XCUT-4 branch (b): the transport-family error, no response, always-retryable at the error
# level, and an ::IOError descendant so an existing "rescue IOError" catch site keeps matching a
# dexpace failure without knowing dexpace exists.
class DexpaceTransportErrorTest < DexpaceTestCase
  test "is an IOError, includes Dexpace::Error, and reports itself always-retryable" do
    error = Dexpace::TransportError.new("connection refused")

    assert_kind_of(::IOError, error)
    assert_kind_of(Dexpace::Error, error)
    assert(error.retryable?)
  end

  test "there is no keyword that can make it not retryable" do
    error = Dexpace::TransportError.new("dns failure")

    assert(error.retryable?)
    refute_respond_to(Dexpace::TransportError, :new_retryable) # no escape hatch exists
  end

  # P3-3: TransportError and StreamError are siblings, never one a subclass of the other.
  test "is not a StreamError and StreamError is not a TransportError" do
    refute_operator(Dexpace::TransportError, :<, Dexpace::StreamError)
    refute_operator(Dexpace::StreamError, :<, Dexpace::TransportError)
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::TransportError`.

- [ ] **Step 3: Write `lib/dexpace/error/transport_error.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # XCUT-4 branch (b): the transport family. No response was received, so this belongs to the
  # runtime's I/O-error family (::IOError) rather than to the response-carrying protocol-error
  # branch, and it MUST report itself always-retryable at the error level -- "no response
  # reached the server" is treated as transient by construction. There is deliberately no
  # keyword that overrides #retryable?: the requirement's own word is "always", and every
  # adapter that wraps a bare stdlib I/O or timeout error into this class inherits that reading
  # rather than re-deciding it per call site (P6-4).
  #
  # A sibling of Dexpace::StreamError, never its ancestor or descendant (P3-3): one is "no
  # response reached the server", the other is "the body stream itself misbehaved after a
  # response existed", and collapsing the two into one hierarchy would make #retryable? true for
  # a failure that has nothing to do with the network.
  class TransportError < ::IOError
    include Dexpace::Error

    def retryable? = true
  end
end
```

- [ ] **Step 4: Write the `sig/` mirror**

```rbs
module Dexpace
  class TransportError < IOError
    include Dexpace::Error

    def retryable?: () -> true
  end
end
```

- [ ] **Step 5: Wire the require and run the suite**

Add `require_relative "dexpace/error/transport_error"` to `lib/dexpace.rb`, immediately after
`dexpace/error/stream_error` (phase 3a's), so the two siblings sit together in the require order.

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/transport_error_test.rb`
Expected: PASS, 3 runs. Then `bundle exec rake rubocop rbs:validate steep` for `dexpace-core`.

---
## Task 5: `Endpoints` — `URI::Generic` → `Async::HTTP::Endpoint`, TLS defaults, the origin key

**Requirement IDs:** none new (boundary 19; `TRANSPORT-15`'s ownership split is `Adapter`'s).
**Design:** "Endpoint construction" (step 9); "TLS defaults."

**Files:**
- Create: `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/endpoints.rb`,
  the `sig/` mirror
- Test: `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/endpoints_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# Step 9: Dexpace::Request#url arrives already parsed by URI::RFC3986_PARSER (phase 1's
# Dexpace::URL.parse!); this module never calls URI.parse or Async::HTTP::Endpoint.parse.
class DexpaceTransportAsyncHTTPEndpointsTest < DexpaceTestCase
  Endpoints = Dexpace::Transport::AsyncHTTP::Endpoints

  test "builds a plaintext endpoint straight from the already-parsed URI" do
    url = Dexpace::URL.parse!("http://example.test:8080/a%20b?q=1")
    endpoint = Endpoints.for(url)

    assert_equal("example.test", endpoint.url.host)
    assert_equal(8080, endpoint.url.port)
  end

  test "an https URL always gets an adapter-supplied ssl_context, never async-http's own" do
    url = Dexpace::URL.parse!("https://example.test/")
    endpoint = Endpoints.for(url)

    refute_nil(endpoint.ssl_context)
    assert_equal(::OpenSSL::SSL::VERIFY_PEER, endpoint.ssl_context.verify_mode)
  end

  test "the adapter-supplied ssl_context offers h2 and http/1.1 by ALPN" do
    url = Dexpace::URL.parse!("https://example.test/")
    endpoint = Endpoints.for(url)

    assert_equal(%w[h2 http/1.1], endpoint.ssl_context.alpn_protocols)
  end

  test "a caller-supplied ssl_context is used verbatim and not silently re-armed" do
    ctx = ::OpenSSL::SSL::SSLContext.new
    url = Dexpace::URL.parse!("https://example.test/")
    endpoint = Endpoints.for(url, ssl_context: ctx)

    assert_same(ctx, endpoint.ssl_context)
  end

  test "a caller can force prior-knowledge h2 over plaintext" do
    url = Dexpace::URL.parse!("http://example.test/")
    endpoint = Endpoints.for(url, protocol: ::Async::HTTP::Protocol::HTTP2)

    assert_equal(::Async::HTTP::Protocol::HTTP2, endpoint.protocol)
  end

  test "the origin key is scheme, host and port, and two URLs sharing all three share a key" do
    a = Dexpace::URL.parse!("https://example.test:443/one")
    b = Dexpace::URL.parse!("https://example.test:443/two")
    c = Dexpace::URL.parse!("https://example.test:8443/one")

    assert_equal(Endpoints.origin_for(a), Endpoints.origin_for(b))
    refute_equal(Endpoints.origin_for(a), Endpoints.origin_for(c))
  end
end
```

- [ ] **Step 2: Run to confirm they fail**

Expected: FAIL — `uninitialized constant Dexpace::Transport::AsyncHTTP::Endpoints`.

- [ ] **Step 3: Write `lib/dexpace/transport/async_http/endpoints.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # URI::Generic -> Async::HTTP::Endpoint, and the origin key Clients maps on.
      #
      # Never calls Async::HTTP::Endpoint.parse: that method routes through URI.parse, i.e.
      # URI::DEFAULT_PARSER, which IS URI::RFC3986_PARSER on 3.4.10 and RFC2396_PARSER below it
      # (design §3.5, the straddle this repository pins against everywhere else). Dexpace::URL
      # already parsed `url` with URI::RFC3986_PARSER at phase 1's own construction time
      # (verified fact 13: Endpoint.new accepts an RFC3986-parsed URI::HTTP directly and only
      # requires #absolute?), so this module hands that object straight through.
      module Endpoints
        # `extend self`, never `module_function`: phase 0's .rubocop.yml sets
        # Style/ModuleFunction to EnforcedStyle: extend_self repository-wide
        # (data-modeling/3775e9d7), and `rake rubocop` is findings-fatal.
        extend self

        ALPN_PROTOCOLS = %w[h2 http/1.1].freeze

        def for(url, ssl_context: nil, protocol: nil, connect_timeout: nil)
          options = { protocol: protocol }.compact
          options[:ssl_context] = url.scheme == "https" ? ssl_context_for(ssl_context) : nil
          options[:timeout] = connect_timeout if connect_timeout
          ::Async::HTTP::Endpoint.new(url, **options.compact)
        end

        def origin_for(url) = [url.scheme, url.host, url.port].freeze

        private

        # Two measured library defaults this adapter deliberately overrides (design "TLS
        # defaults"): Endpoint#ssl_verify_mode returns VERIFY_NONE for any hostname matching
        # localhost, and a caller-supplied context is used verbatim with alpn_protocols never
        # set on it, so HTTP/2 over TLS is unreachable unless something sets it. This method is
        # the "something."
        def ssl_context_for(supplied)
          return supplied if supplied

          context = ::OpenSSL::SSL::SSLContext.new
          context.set_params(verify_mode: ::OpenSSL::SSL::VERIFY_PEER)
          context.alpn_protocols = ALPN_PROTOCOLS
          context
        end
      end
    end
  end
end
```

`require "openssl"` and `require "uri"` are both permitted here under the same rule core lives
by — `openssl` carries no `Gem::BUNDLED_GEMS::SINCE` entry (verified fact 12) — but neither line
is written: `openssl` is already loaded as one of `async-http`'s own declared dependencies by the
time this file runs, and `uri` by phase 1's `Dexpace::URL`. Adding either `require` line here
would be redundant, not wrong, and this file omits both to keep the require-allowlist scan
matching what the design's "require set, stated exactly" actually lists for this gem.

- [ ] **Step 4: Write `sig/dexpace/transport/async_http/endpoints.rbs`**

```rbs
module Dexpace
  module Transport
    module AsyncHTTP
      module Endpoints
        ALPN_PROTOCOLS: Array[String]

        def self.for: (
          URI::Generic url,
          ?ssl_context: untyped?,
          ?protocol: untyped?,
          ?connect_timeout: Float?
        ) -> untyped
        def self.origin_for: (URI::Generic url) -> [String?, String?, Integer?]
      end
    end
  end
end
```

`ssl_context:`/`protocol:` and the return type are `untyped`: both are `Async::HTTP`/`OpenSSL`
constants, and `NFR-11`'s scan only cares that they never appear in a signature under
`Dexpace::Transport::AsyncHTTP` — `untyped` is silent about the foreign type by construction,
which is the same reading Task 17 applies everywhere else in this gem's `sig/`.

- [ ] **Step 5: Run the suite**

Run: `bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/endpoints_test.rb`
Expected: PASS, 6 runs.

---
## Task 6: `Errors.wrap` and its table

**Requirement IDs:** none new (`TRANSPORT-20` consumed; `P6-4`'s obligation discharged for this
adapter).
**Design:** "Error wrapping" (step 17); verified fact 11.

**Files:**
- Create: `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/errors.rb`,
  the `sig/` mirror
- Test: `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/errors_test.rb`

**This is the first file in this gem whose code references an `Async::`/`Protocol::HTTP::`
constant.** It carries no `require` line of its own — the entry file's own `require
"async/http"` (Task 2) has already run by the time `require_relative` reaches this file, and
Task 2's ordering gate (the gemspec dependency landing before that require) is what makes the
entry file's line legal in the first place.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# Step 17's table, as data. P6-4: "wrap, and default to retryable" -- not one of the seven
# families async-http raises is an ::IOError (verified fact 11), so every one of these needs
# Dexpace::TransportError to answer #retryable? at all.
class DexpaceTransportAsyncHTTPErrorsTest < DexpaceTestCase
  Errors = Dexpace::Transport::AsyncHTTP::Errors

  NATIVE = [
    ::Async::TimeoutError.new("deadline"),
    ::Errno::ECONNREFUSED.new,
    ::SocketError.new("dns"),
    ::OpenSSL::SSL::SSLError.new("handshake"),
    ::EOFError.new,
    ::Protocol::HTTP::RefusedError.new("bad header"),
    ::Protocol::HTTP::RemoteError.new("peer reset"),
  ].freeze

  test "every native family wraps into a retryable Dexpace::TransportError carrying the " \
       "original as #cause" do
    NATIVE.each do |native|
      wrapped = Errors.wrap(native)

      assert_kind_of(Dexpace::TransportError, wrapped, native.class.to_s)
      assert(wrapped.retryable?, native.class.to_s)
      assert_same(native, wrapped.cause, native.class.to_s)
    end
  end

  test "a Dexpace:: error is passed through unwrapped, unchanged, with no cause added" do
    original = Dexpace::StreamError.new("already ours")

    assert_same(original, Errors.wrap(original))
    assert_nil(Errors.wrap(original).cause)
  end

  test "is callable standalone, with no ambient rescue in flight" do
    # No begin/rescue anywhere above this line -- $! is nil here, and .wrap must still attach
    # the argument as #cause rather than depending on an ambient in-flight exception.
    wrapped = Errors.wrap(::EOFError.new("no ambient rescue"))

    assert_kind_of(::EOFError, wrapped.cause)
  end

  test "never sees Async::Cancel, by construction" do
    # Errors.wrap is only ever called from a `rescue StandardError` in the adapter, which
    # Async::Cancel (< Exception) cannot reach. This test documents the invariant rather than
    # exercising a code path that does not exist: passing Async::Cancel in would wrap it like
    # any other native error, which is exactly the outcome R13 forbids -- so no call site may
    # ever construct one to pass here.
    refute_operator(::Async::Cancel, :<, ::StandardError)
  end
end
```

- [ ] **Step 2: Run to confirm they fail**

Expected: FAIL — `uninitialized constant Dexpace::Transport::AsyncHTTP::Errors`.

- [ ] **Step 3: Write `lib/dexpace/transport/async_http/errors.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # Step 17's table, kept as data (a wrap that never sees a class it doesn't recognise, and
      # a table a reviewer can read as an exhaustive list) rather than a case/when chain.
      module Errors
        extend self   # Style/ModuleFunction: extend_self, repository-wide (phase 0)

        # Every native family this adapter's own exchange can raise past dispatch (verified
        # fact 11). Documentation and a coverage anchor, not a dispatch table: every one of
        # these wraps identically, because XCUT-4 branch (b) makes TransportError ALWAYS
        # retryable regardless of which native family produced it.
        RECOGNISED = [
          ::Async::TimeoutError,
          ::SystemCallError,
          ::SocketError,
          ::OpenSSL::SSL::SSLError,
          ::EOFError,
          ::Protocol::HTTP::Error,
        ].freeze

        # A Dexpace:: error is already ours and passes straight through, unwrapped and with no
        # cause added (P3-3: this adapter's own Dexpace::StreamError is a sibling of
        # TransportError and must never gain it as a cause). Everything else wraps into a
        # retryable Dexpace::TransportError.
        #
        # #cause is set through `raise wrapped, cause: error` and immediately re-rescued, rather
        # than through Exception.new (which takes no cause: keyword) or through relying on the
        # caller's own ambient $! (which would make this method's behaviour depend on whether
        # its caller happens to be inside an active rescue -- untestable standalone, and this
        # method IS tested standalone, in the third test above).
        def wrap(error)
          return error if error.is_a?(Dexpace::Error)

          wrapped = Dexpace::TransportError.new("#{error.class}: #{error.message}")
          begin
            raise wrapped, cause: error
          rescue Dexpace::TransportError => captured
            captured
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/transport/async_http/errors.rbs`**

```rbs
module Dexpace
  module Transport
    module AsyncHTTP
      module Errors
        RECOGNISED: Array[untyped]

        def self.wrap: (Exception error) -> Exception
      end
    end
  end
end
```

`error`'s and the return type's `Exception` are stdlib, not foreign to the allowlist (`NFR-11`
scans for third-party/other-namespace *constants*, and `Exception` is a Ruby core class every
target already sees).

- [ ] **Step 5: Delete the entry file's `Errors` stand-in and run the suite**

Run: `bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/errors_test.rb`
Expected: PASS, 4 runs. Then `bundle exec rake gates:require_allowlist` — the first real check
that `require "async/http"` in this gem's `lib/` is permitted.

---
## Task 7: `DropPolicy` — `TRANSPORT-13`, `OBS-19`, `DEF-41`

**Requirement IDs:** `TRANSPORT-13`.
**Design:** "`Dexpace::Transport::AsyncHTTP::DropPolicy`"; `DEF-41`'s row; this plan's own ninth
open question above.

**Files:**
- Create: `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/drop_policy.rb`,
  the `sig/` mirror
- Modify: `gems/dexpace-core/lib/dexpace/instrumentation/events.rb`,
  `gems/dexpace-core/sig/dexpace/instrumentation/events.rbs` (a widening: one new constant,
  following the one-constant-per-call-site-type convention every existing row in that module
  already uses — `INSTRUMENTATION_CLOSE`, `_HOOK`, `_CONFIG`, `_LOG` — never reused generically)
- Test: `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/drop_policy_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/recording_sink" # dexpace-core's own, per phase 5b's plan

# TRANSPORT-13 (SHOULD): a configurable policy for how header drops are logged, with the
# per-name dedup mode case-insensitive and bounded. §17's own conformance clause: "under
# once-per-header assert the same name warns once then goes quiet, a different name warns once."
class DexpaceTransportAsyncHTTPDropPolicyTest < DexpaceTestCase
  DropPolicy = Dexpace::Transport::AsyncHTTP::DropPolicy
  Severity = Dexpace::Instrumentation::Severity

  def logger_and_sink
    sink = Dexpace::RecordingSink.new
    [Dexpace::Instrumentation::Logger.build(sink: sink), sink]
  end

  test "EVERY mode warns on every drop, same name or not" do
    logger, sink = logger_and_sink
    policy = DropPolicy.build(mode: DropPolicy::EVERY)

    policy.report(logger, "X-Bad Name", "not a token")
    policy.report(logger, "X-Bad Name", "not a token")

    assert_equal([:warn, :warn], sink.entries.map(&:severity))
  end

  test "QUIET never warns" do
    logger, sink = logger_and_sink
    policy = DropPolicy.build(mode: DropPolicy::QUIET)

    policy.report(logger, "X-Bad Name", "not a token")

    assert_equal([:debug], sink.entries.map(&:severity))
  end

  test "ONCE_PER_NAME (the default) warns once per distinct folded name, then goes quiet" do
    logger, sink = logger_and_sink
    policy = DropPolicy.build

    policy.report(logger, "X-Bad Name", "not a token")
    policy.report(logger, "X-Bad Name", "not a token")
    policy.report(logger, "Y-Bad Name", "not a token")

    assert_equal([:warn, :debug, :warn], sink.entries.map(&:severity))
  end

  test "the per-name latch is case-insensitive on the folded name" do
    logger, sink = logger_and_sink
    policy = DropPolicy.build

    policy.report(logger, "X-Bad Name", "not a token")
    policy.report(logger, "x-bad name", "not a token")

    assert_equal([:warn, :debug], sink.entries.map(&:severity))
  end

  test "bounded at 64 distinct names; the 65th degrades to quiet rather than growing" do
    logger, sink = logger_and_sink
    policy = DropPolicy.build

    64.times { |i| policy.report(logger, "X-Bad-#{i}", "not a token") }
    policy.report(logger, "X-Bad-64", "not a token")

    assert_equal(64, sink.entries.count { |e| e.severity == :warn })
    assert_equal(:debug, sink.entries.last.severity)
  end

  test "a drop's own event carries the header name and the reason as fields" do
    logger, sink = logger_and_sink
    DropPolicy.build.report(logger, "X-Bad Name", "not a token")

    record = sink.entries.first.payload
    assert_equal("X-Bad Name", record["header"])
    assert_equal("not a token", record["reason"])
  end

  test "a rejected mode raises Dexpace::InvalidArgumentError rather than degrading silently" do
    assert_raises(Dexpace::InvalidArgumentError) { DropPolicy.build(mode: :bogus) }
  end
end
```

- [ ] **Step 2: Run to confirm they fail**

Expected: FAIL — `uninitialized constant Dexpace::Transport::AsyncHTTP::DropPolicy`.

- [ ] **Step 3: Add one `Events` constant to `dexpace-core`**

```ruby
      # TRANSPORT-13/DEF-41, phase 8c: the drop-logging call site, the first in the repository
      # where an adapter drops a header rather than raising on it.
      TRANSPORT_HEADER_DROPPED = "http.transport.header_dropped"
```

Beside the existing `INSTRUMENTATION_LOG`/`_CLOSE`/`_HOOK`/`_CONFIG` rows in
`Dexpace::Instrumentation::Events`, and the matching `String` line in the `sig/` mirror. This is
a widening (one new constant; nothing narrows or moves), so `NFR-4`'s lock is unaffected and
`gates:sig_diff` has nothing to say about it once a release tag exists.

- [ ] **Step 4: Write `lib/dexpace/transport/async_http/drop_policy.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # TRANSPORT-13 (SHOULD): a configurable policy for how a dropped header is logged, with
      # the per-name dedup mode bounded so an attacker synthesising unbounded distinct names
      # cannot grow it without limit. DEF-41's own row predicts this shape almost exactly:
      # "phase 8 writes a small Data over both [5b's Severity and its once-per-key latch idea],
      # at the one call site that actually drops a header."
      #
      # Not itself a Data.define value at the top level, even though the sentence above reads
      # that way: Data freezes automatically at the end of #initialize (including through a
      # custom override that calls super), and this object's whole job is to grow a bounded
      # per-name table over its own lifetime -- a frozen top-level object cannot reassign the
      # ivar that table lives in. What IS a frozen Data value is the SNAPSHOT this object holds
      # in one ivar and replaces wholesale under its own mutex on the write path, reading it
      # without a lock everywhere else -- concurrency-and-async/f414b864's prescribed shape for
      # exactly this kind of mutable state, and the same shape phase 2's own Registry uses for
      # its factory table.
      class DropPolicy
        Snapshot = ::Data.define(:seen)
        private_constant :Snapshot

        MAX_TRACKED_NAMES = 64

        EVERY = :every
        ONCE_PER_NAME = :once_per_name
        QUIET = :quiet
        MODES = [EVERY, ONCE_PER_NAME, QUIET].freeze

        private_class_method :new

        def self.build(mode: ONCE_PER_NAME)
          unless MODES.include?(mode)
            raise Dexpace::InvalidArgumentError,
                  "mode must be one of #{MODES.inspect}, got #{mode.inspect}"
          end

          new(mode: mode)
        end

        def initialize(mode:)
          @mode = mode
          @mutex = ::Thread::Mutex.new
          @snapshot = Snapshot.new(seen: {}.freeze)
        end

        # TRANSPORT-13's own conformance clause, discharged by the severity this method picks:
        # "under once-per-header assert the same name warns once then goes quiet, a different
        # name warns once." Every emission goes through Instrumentation.contain, because
        # OBS-20's "every log-emission site" is not scoped to phase 5's own sites -- this is the
        # first site outside that phase.
        def report(logger, name, reason)
          severity = severity_for(name)
          Dexpace::Instrumentation.contain(
            logger, event: Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED
          ) do
            logger.event(severity)
                  .event(Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED)
                  .field("header", name)
                  .field("reason", reason)
                  .emit
          end
          nil
        end

        private

        def severity_for(name)
          case @mode
          when EVERY then Dexpace::Instrumentation::Severity::WARNING
          when QUIET then Dexpace::Instrumentation::Severity::VERBOSE
          else warn_once_per_name?(name.to_s.downcase) ? Dexpace::Instrumentation::Severity::WARNING
                                                        : Dexpace::Instrumentation::Severity::VERBOSE
          end
        end

        def warn_once_per_name?(folded)
          @mutex.synchronize do
            snapshot = @snapshot
            next false if snapshot.seen.key?(folded)
            next false if snapshot.seen.size >= MAX_TRACKED_NAMES

            @snapshot = Snapshot.new(seen: snapshot.seen.merge(folded => true).freeze)
            true
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Write `sig/dexpace/transport/async_http/drop_policy.rbs`**

```rbs
module Dexpace
  module Transport
    module AsyncHTTP
      class DropPolicy
        MAX_TRACKED_NAMES: Integer
        EVERY: Symbol
        ONCE_PER_NAME: Symbol
        QUIET: Symbol
        MODES: Array[Symbol]

        def self.build: (?mode: Symbol) -> DropPolicy
        def report: (untyped logger, String name, String reason) -> nil
      end
    end
  end
end
```

`logger`'s `untyped`: `Dexpace::Instrumentation::Logger` is a `Dexpace::` constant and could be
named exactly, but this file's own `sig/` target is lenient on internals per the design's own
target-by-target Steep adoption, and `DropPolicy` is not on the public-surface list (Task 17
states which four constants are). Left `untyped` here rather than named, to match the density
the rest of this internal object's signature already uses.

- [ ] **Step 6: Delete the entry file's `DropPolicy` stand-in and run**

Run: `bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/drop_policy_test.rb`
Expected: PASS, 8 runs. Then `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/events_test.rb`
for the new constant, and `bundle exec rake rbs:validate steep` across both gems.

---
## Task 8: `Clients` — the per-origin map, `Configuration` reads, `#close` over `pool.close`

**Requirement IDs:** none new (`TRANSPORT-1`, `TRANSPORT-2`, `TRANSPORT-16`, `TRANSPORT-29`
consumed by construction; `P8-37`).
**Design:** "`Dexpace::Transport::AsyncHTTP::Clients`"; step 10's construction-argument table;
open question 3; deviation `P8-37`.

**Files:**
- Create: `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/clients.rb`,
  the `sig/` mirror
- Modify: `gems/dexpace-core/lib/dexpace/configuration/keys.rb`, its `sig/` mirror (two new
  keys — a widening, per verified fact 7 above)
- Test: `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/clients_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# concurrency-and-async/c0fab747 (smallest critical section) and /ee54cb68 (never hold a lock
# across I/O): #fetch's mutex guards a Hash read and a Hash insert and nothing else -- the client
# itself is built outside the lock, because building it loads the default certificate store from
# disk. Async::HTTP::Client.new opens no socket (verified fact 9 -- the pool's own constructor
# block runs on #acquire, not on #new), so a client discarded by a lost insert race costs nothing.
class DexpaceTransportAsyncHTTPClientsTest < DexpaceTestCase
  Clients = Dexpace::Transport::AsyncHTTP::Clients

  def url(str) = Dexpace::URL.parse!(str)

  test "fetch memoises one client per origin" do
    clients = Clients.build

    first = clients.fetch(url("https://example.test/a"))
    second = clients.fetch(url("https://example.test/b"))
    third = clients.fetch(url("https://example.test:8443/a"))

    assert_same(first, second)
    refute_same(first, third)
  end

  test "every client disables the native retry loop (TRANSPORT-2, TRANSPORT-17, TRANSPORT-18)" do
    client = Clients.build.fetch(url("https://example.test/"))

    assert_equal(0, client.instance_variable_get(:@retries))
  end

  test "the connection limit reads TRANSPORT_CONNECTION_LIMIT off Configuration, default 8" do
    client = Clients.build.fetch(url("https://example.test/"))

    assert_equal(8, client.pool.instance_variable_get(:@limit))
  end

  test "a configured connection limit overrides the default" do
    config = Dexpace::Configuration.build(
      overrides: { Dexpace::Configuration::Keys::TRANSPORT_CONNECTION_LIMIT => "3" },
    )
    client = Clients.build(configuration: config).fetch(url("https://example.test/"))

    assert_equal(3, client.pool.instance_variable_get(:@limit))
  end

  # P8-37: Async::HTTP::Client#close is `@pool.wait_until_free { … }` then `@pool.close` --
  # measured blocking 253ms with one request in flight (design fact 9). #close here calls
  # `client.pool.close` directly, which is `drain` then clear with no wait.
  test "close releases every client's pool directly, never through Client#close" do
    clients = Clients.build
    client = clients.fetch(url("https://example.test/"))
    pool = client.pool

    closed_via_client = false
    client.define_singleton_method(:close) { closed_via_client = true }
    pool.define_singleton_method(:close) { @closed = true }

    clients.close

    refute(closed_via_client)
    assert(pool.instance_variable_get(:@closed))
  end

  test "close is idempotent" do
    clients = Clients.build
    clients.fetch(url("https://example.test/"))

    clients.close
    clients.close # must not raise a second time
  end
end
```

- [ ] **Step 2: Run to confirm they fail**

Expected: FAIL — `uninitialized constant Dexpace::Transport::AsyncHTTP::Clients`.

- [ ] **Step 3: Add the one `Configuration::Keys` this gem owns, and read `8a`'s for the timeout**

```ruby
      TRANSPORT_CONNECTION_LIMIT = "TRANSPORT_CONNECTION_LIMIT"
```

Beside the existing rows in `Dexpace::Configuration::Keys`, plus a matching `String` line in the
`sig/` mirror. Verified fact 7 confirms the name collides with nothing phase 5a shipped, and the
concept is genuinely this gem's alone: `Net::HTTP` is constructed per call and has no pool to bound,
so `8a` will never want it.

**Corrected 2026-09-12, with the correction stated.** This step also declared a second key,
`TRANSPORT_REQUEST_TIMEOUT_SECONDS`, for the per-call deadline. **It must not**: `8a`'s Task 2 declares
`Dexpace::Configuration::Keys::REQUEST_TIMEOUT` for the same concept, this gem's own design already says
"`8c` reads the same key rather than declaring a second spelling", and the charter states it once under
*Shared transport contracts* item 4. Two spellings for one concept means one caller setting governs one
transport and not the other, which is exactly the silent wrong answer `PAGE-36` exists to prevent one
layer up. **Task 11 reads `Keys::REQUEST_TIMEOUT` through
`Dexpace.configuration.duration(Keys::REQUEST_TIMEOUT, default: DEFAULT_REQUEST_TIMEOUT_SECONDS)`** —
5a ships no `#float`, and `#duration` returns `Float` seconds and returns the `default` unmodified when
nothing is configured. The behavioural consequence, documented in `Adapter`'s YARD exactly as `8a`
documents it in its own: `parse_duration`'s grammar treats a **bare number as milliseconds** (`CFG-7`),
so `REQUEST_TIMEOUT=30` is thirty *milliseconds* and a caller who wants thirty seconds writes `30s` or
`PT30S`. **Whichever of `8a` and `8c` executes first declares `REQUEST_TIMEOUT`; the other finds it.**

- [ ] **Step 4: Write `lib/dexpace/transport/async_http/clients.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # The per-origin Async::HTTP::Client map. #fetch's critical section contains no I/O and
      # no suspension point (Client.new opens no socket -- verified fact 9), which is what
      # makes a plain, non-reentrant, per-fiber-owned Thread::Mutex safe here
      # (concurrency-and-async/c0fab747, /ee54cb68).
      class Clients
        DEFAULT_CONNECTION_LIMIT = 8

        private_class_method :new

        def self.build(configuration: nil, connection_limit: nil, ssl_context: nil)
          new(configuration: configuration || Dexpace.configuration,
              connection_limit: connection_limit, ssl_context: ssl_context)
        end

        # connection_limit:/ssl_context: are Adapter.new's own convenience keywords (design's
        # construction table) -- an explicit override wins over Configuration without requiring
        # the caller to build a whole Configuration just to set one number or one context.
        def initialize(configuration:, connection_limit: nil, ssl_context: nil)
          @configuration = configuration
          @ssl_context = ssl_context
          @limit = connection_limit || @configuration.integer(
            Dexpace::Configuration::Keys::TRANSPORT_CONNECTION_LIMIT,
            default: DEFAULT_CONNECTION_LIMIT,
          )
          @mutex = ::Thread::Mutex.new
          @by_origin = {}
        end

        # The client is built OUTSIDE the lock and inserted under it, so the critical section is a
        # Hash read and a Hash insert and nothing else. Building inside it would hold the mutex
        # across Endpoints' OpenSSL::SSL::SSLContext#set_params, which loads the default
        # certificate store from disk -- filesystem I/O, and therefore a scheduler suspension
        # point under a fiber scheduler, which concurrency-and-async/ee54cb68 and /f261a143 forbid
        # a lock being held across. A lost race discards an unused client, which costs nothing:
        # Client.new opens no socket (verified fact 9).
        def fetch(url)
          origin = Endpoints.origin_for(url)
          existing = @mutex.synchronize { @by_origin[origin] }
          return existing if existing

          candidate = build_client(url)
          @mutex.synchronize { @by_origin[origin] ||= candidate }
        end

        # P8-37: Async::HTTP::Client#close is `@pool.wait_until_free { … }` then `@pool.close`
        # -- an unbounded await XCUT-13/TRANSPORT-16 forbid in as many words, and it writes a
        # JSON `Console.warn` line to the host's stderr on the way, which nothing in this SDK
        # may do on the caller's behalf. Async::Pool::Controller#close is `drain` (retire every
        # resource) then clear, with no wait -- the conforming route, and public API
        # (Client#attr :pool), not a `send`.
        def close
          clients = @mutex.synchronize { @by_origin.values }
          clients.each { |client| Dexpace.close_quietly(client.pool) }
          nil
        end

        private

        def build_client(url)
          endpoint = Endpoints.for(url, ssl_context: @ssl_context)
          ::Async::HTTP::Client.new(endpoint, retries: 0, limit: @limit)
        end
      end
    end
  end
end
```

`Dexpace.close_quietly(client.pool)` — `Async::Pool::Controller#close` takes no argument and
raises nothing under ordinary conditions, so `close_quietly` here is belt-and-braces rather than
load-bearing; it is used anyway so every close in this gem goes through the one sanctioned exit,
consistently.

- [ ] **Step 5: Write `sig/dexpace/transport/async_http/clients.rbs`**

```rbs
module Dexpace
  module Transport
    module AsyncHTTP
      class Clients
        DEFAULT_CONNECTION_LIMIT: Integer

        def self.build: (
          ?configuration: untyped?, ?connection_limit: Integer?, ?ssl_context: untyped?
        ) -> Clients
        def fetch: (URI::Generic url) -> untyped
        def close: () -> nil
      end
    end
  end
end
```

- [ ] **Step 6: Run the suite**

Run: `bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/clients_test.rb`
Expected: PASS, 6 runs. Then
`bundle exec ruby -w gems/dexpace-core/test/dexpace/configuration/keys_test.rb` for the two new
keys.

---
## Task 9: `RequestMapper` and `RequestBody` — `DEF-25`, `TRANSPORT-10`/`11`/`12`/`13`/`26`

**Requirement IDs:** `TRANSPORT-12` (implementation half; the dispatched-over-both-protocols test
is Task 15), `TRANSPORT-13` (implementation half; the test is Task 15).
**Design:** "The dispatch path, in order" steps 4–9; "`Dexpace::Transport::AsyncHTTP::RequestBody`";
deviation `P8-40`.

**Files:**
- Create: `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/request_mapper.rb`,
  `.../request_body.rb`, both `sig/` mirrors
- Test: `.../test/dexpace/transport/async_http/request_mapper_test.rb`, `request_body_test.rb`

- [ ] **Step 1: Write the failing tests**

`request_mapper_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# DEF-25: HeaderSyntax re-run immediately before dispatch, on every name and outbound value.
# TRANSPORT-11: the framing-header drop set, larger than the requirement's minimum because
# verified fact 5 makes each entry a smuggling vector (a caller-set host/content-length is
# APPENDED, not recomputed, on this adapter). TRANSPORT-12/13, P8-40: the RFC 7230 token
# predicate applied before dispatch, on both protocols, unconditionally.
class DexpaceTransportAsyncHTTPRequestMapperTest < DexpaceTestCase
  RequestMapper = Dexpace::Transport::AsyncHTTP::RequestMapper

  # Request::Builder exposes a writer per member plus #header(name, value) -- and no readers
  # (phase 1, "a writer per member and #build"), so the headers are accumulated here and assigned
  # once rather than read back off the builder.
  def request(headers: {}, body: nil, method: "GET", url: "https://example.test/p")
    builder = Dexpace::Request.builder
    builder.method = method
    builder.url = url
    headers.each { |name, value| builder.header(name, value) }
    builder.body = body
    builder.build
  end

  def logger_and_sink
    sink = Dexpace::RecordingSink.new
    [Dexpace::Instrumentation::Logger.build(sink: sink), sink]
  end

  test "DEF-25: a header name HeaderSyntax rejects raises before anything is dispatched" do
    logger, = logger_and_sink
    bad = request(headers: { "Bad Name" => "v" })

    error = assert_raises(Dexpace::InvalidArgumentError) do
      RequestMapper.call(bad, nil, drop_policy: Dexpace::Transport::AsyncHTTP::DropPolicy.build,
                                    logger: logger)
    end
    assert_match(/HTTP-17/, error.message)
  end

  test "DEF-25: an outbound value HeaderSyntax rejects raises before anything is dispatched" do
    logger, = logger_and_sink
    bad = request(headers: { "X-Trace" => "a\x01b" })

    assert_raises(Dexpace::InvalidArgumentError) do
      RequestMapper.call(bad, nil, drop_policy: Dexpace::Transport::AsyncHTTP::DropPolicy.build,
                                    logger: logger)
    end
  end

  test "TRANSPORT-11: host, content-length and transfer-encoding are dropped and logged " \
       "verbose, case-insensitively" do
    logger, sink = logger_and_sink
    req = request(headers: { "Host" => "bogus.example", "Content-Length" => "999",
                              "TRANSFER-ENCODING" => "chunked", "X-Keep" => "yes" })

    native = RequestMapper.call(req, nil,
                                 drop_policy: Dexpace::Transport::AsyncHTTP::DropPolicy.build,
                                 logger: logger)

    names = native.headers.to_a.map { |k, _| k.downcase }
    refute_includes(names, "host")
    refute_includes(names, "content-length")
    refute_includes(names, "transfer-encoding")
    assert_includes(names, "x-keep")
    assert_equal([:debug, :debug, :debug], sink.entries.map(&:severity))
  end

  test "TRANSPORT-12/13, P8-40: a name the RFC 7230 token grammar rejects is dropped, " \
       "reported through DropPolicy, and every other header still dispatches" do
    logger, sink = logger_and_sink
    policy = Dexpace::Transport::AsyncHTTP::DropPolicy.build
    req = request(headers: { "Bad Name" => "v", "X-Normal" => "n" })
    # HeaderSyntax accepts "Bad Name" (HTTP-17's grammar is looser than RFC 7230's token set);
    # only the wire-grammar drop below rejects it -- that gap is TRANSPORT-12's own antecedent.

    native = RequestMapper.call(req, nil, drop_policy: policy, logger: logger)

    names = native.headers.to_a.map { |k, _| k.downcase }
    refute_includes(names, "bad name")
    assert_includes(names, "x-normal")
    assert_equal([:warn], sink.entries.map(&:severity))
  end

  test "TRANSPORT-10: an explicit Content-Type wins over the body's own media type" do
    logger, = logger_and_sink
    body = Dexpace::Body.string("{}", media_type: Dexpace::MediaType.parse("application/json"))
    req = request(headers: { "Content-Type" => "text/plain" }, body: body, method: "POST")

    native = RequestMapper.call(req, nil,
                                 drop_policy: Dexpace::Transport::AsyncHTTP::DropPolicy.build,
                                 logger: logger)

    content_types = native.headers.to_a.select { |k, _| k.downcase == "content-type" }
    assert_equal([["Content-Type", "text/plain"]], content_types)
  end

  test "TRANSPORT-10: with no explicit header, the body's own media type is emitted" do
    logger, = logger_and_sink
    body = Dexpace::Body.string("{}", media_type: Dexpace::MediaType.parse("application/json"))
    req = request(body: body, method: "POST")

    native = RequestMapper.call(req, nil,
                                 drop_policy: Dexpace::Transport::AsyncHTTP::DropPolicy.build,
                                 logger: logger)

    content_types = native.headers.to_a.select { |k, _| k.downcase == "content-type" }
    assert_equal([["content-type", "application/json"]], content_types)
  end

  test "a body-less request maps to a nil native body" do
    logger, = logger_and_sink
    req = request(method: "POST")

    native = RequestMapper.call(req, nil,
                                 drop_policy: Dexpace::Transport::AsyncHTTP::DropPolicy.build,
                                 logger: logger)

    assert_nil(native.body)
  end
end
```

`request_body_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# A Protocol::HTTP::Body::Readable subclass over a Dexpace::Body, so an outbound body is never
# materialised -- verified fact 7 measured exactly one #read per chunk plus one for
# end-of-stream over the reference library; this test asserts the same property against
# Dexpace::Body's own #each contract rather than re-deriving it.
class DexpaceTransportAsyncHTTPRequestBodyTest < DexpaceTestCase
  RequestBody = Dexpace::Transport::AsyncHTTP::RequestBody

  test "reads exactly one chunk per #read call, then nil at end of stream" do
    source = Class.new(Dexpace::Body) do
      def write_to(sink)
        sink.write("ab".b)
        sink.write("cd".b)
        4
      end
    end.new
    body = RequestBody.new(source)

    assert_equal("ab", body.read)
    assert_equal("cd", body.read)
    assert_nil(body.read)
  end

  test "#length reports the wrapped body's own content_length, or nil for the -1 sentinel" do
    known = RequestBody.new(Dexpace::Body.bytes("abc".b))
    unknown = RequestBody.new(Class.new(Dexpace::Body) { def write_to(_s) = 0 }.new)

    assert_equal(3, known.length)
    assert_nil(unknown.length)
  end

  test "#rewindable? mirrors the wrapped body's #replayable?, and #rewind resets the read cursor" do
    replayable = RequestBody.new(Dexpace::Body.bytes("abc".b))

    assert(replayable.rewindable?)
    replayable.read
    assert(replayable.rewind)
    assert_equal("abc", replayable.read)
  end

  test "a single-use (non-replayable) body refuses to rewind" do
    single_use = RequestBody.new(Class.new(Dexpace::Body) do
      def write_to(sink) = sink.write("x".b)
    end.new)
    single_use.read

    refute(single_use.rewind)
  end
end
```

- [ ] **Step 2: Run to confirm they fail**

Expected: FAIL — `uninitialized constant Dexpace::Transport::AsyncHTTP::RequestMapper` /
`RequestBody`.

- [ ] **Step 3: Write `lib/dexpace/transport/async_http/request_body.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # A Protocol::HTTP::Body::Readable subclass over a Dexpace::Body, so an outbound body is
      # never materialised. Protocol::HTTP::Body::Buffered.wrap is NOT used for this: it
      # materialises an #each-yielding object in full (verified fact 7), which would violate
      # SEAM-11's streaming intent on the write side.
      #
      # Driven through Dexpace::Body#each's own Enumerator (`to_enum(:each)` with no block),
      # which internally pumps #write_to through a Fiber -- the same #each-abandonment residue
      # phase 3b's own Dexpace::Body already documents for every #each-shaped consumer, not a
      # new hazard this class introduces.
      class RequestBody < ::Protocol::HTTP::Body::Readable
        def initialize(body)
          super()
          @body = body
          @enumerator = nil
        end

        def length
          value = @body.content_length
          value.negative? ? nil : value
        end

        def rewindable? = @body.replayable?

        def rewind
          return false unless rewindable?

          @enumerator = nil
          true
        end

        def read
          @enumerator ||= @body.each
          @enumerator.next.b
        rescue ::StopIteration
          nil
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `lib/dexpace/transport/async_http/request_mapper.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # Steps 4-9 of the dispatch path: wire-boundary re-validation, the framing-header drop,
      # the wire-grammar drop, Content-Type authority, and the native Protocol::HTTP::Request.
      module RequestMapper
        extend self   # Style/ModuleFunction: extend_self, repository-wide (phase 0)

        # TRANSPORT-11's drop set, larger than the requirement's minimum because verified fact 5
        # makes each entry a smuggling vector on this adapter specifically: `write_request`
        # writes `host:`/`content-length:` unconditionally and a caller-set one is APPENDED, not
        # recomputed, producing the canonical Host-duplication and CL.CL/TE.CL smuggling shapes.
        #
        # These TEN folded names are a SHARED transport contract, stated once in the charter's
        # "Shared transport contracts" subsection and implemented identically by
        # dexpace-transport-net_http under its own constant name (NFR-2 forbids either gem
        # depending on the other, so the membership is what is shared, not the constant name). A
        # conformance assertion reads this list on both adapters, so a divergence must be a red
        # test here, which is why this gem's suite asserts the membership verbatim.
        #
        # `trailer` was missing and was added 2026-09-12: this adapter accepts no caller-supplied
        # trailers, so a caller-set Trailer announces fields that will never be sent.
        # `proxy-authorization` is in NEITHER adapter's set -- TRANSPORT-30's embedded MUST is
        # about credentials the SDK holds, and it holds none.
        FRAMING_HEADERS = %w[
          host content-length transfer-encoding connection keep-alive proxy-connection te trailer
          upgrade expect
        ].freeze

        # RFC 7230's token grammar. A per-pattern timeout (never Regexp.timeout) even though a
        # character class with no backtracking cannot pathologically time out -- the rule is
        # repository-wide and this file carves no exception.
        TOKEN = ::Regexp.new(/\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/.source, timeout: 1.0)

        def call(request, _options, drop_policy:, logger:)
          validate!(request.headers) # DEF-25: raises, uncaught here, on purpose (step 4)

          fields = []
          seen_content_type = false
          request.headers.each do |name, value|
            folded = name.to_s.downcase
            seen_content_type ||= folded == "content-type"
            if FRAMING_HEADERS.include?(folded)
              log_framing_drop(logger, name)
            elsif TOKEN.match?(name.to_s) # TRANSPORT-12/13, P8-40: both protocols, unconditionally
              fields << [name.to_s, value]
            else
              drop_policy.report(logger, name, "not a valid RFC 7230 token (TRANSPORT-12)")
            end
          end

          if !seen_content_type && request.body&.media_type
            fields << ["content-type", request.body.media_type.to_s]
          end

          ::Protocol::HTTP::Request.new(
            request.url.scheme,
            authority_for(request.url),
            request.method.to_s,
            request.url.request_uri,
            nil,
            ::Protocol::HTTP::Headers.new(fields),
            request.body ? RequestBody.new(request.body) : nil,
          )
        end

        private

        def validate!(headers)
          headers.each do |name, value|
            Dexpace::HeaderSyntax.validate_name!(name)
            Dexpace::HeaderSyntax.validate_outbound_value!(value, name: name)
          end
          nil
        end

        def authority_for(url)
          port = url.port
          port && port != url.default_port ? "#{url.host}:#{port}" : url.host
        end

        # TRANSPORT-11's SHOULD: log each drop at verbose, through the one sanctioned
        # containment helper (OBS-20's "every log-emission site"). Not routed through DropPolicy
        # -- that policy's three modes are TRANSPORT-13's, over the wire-grammar drop only; a
        # framing-header drop is always verbose, never a WARNING an attacker could suppress by
        # exhausting the per-name bound.
        def log_framing_drop(logger, name)
          Dexpace::Instrumentation.contain(
            logger, event: Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED
          ) do
            logger.event(Dexpace::Instrumentation::Severity::VERBOSE)
                  .event(Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED)
                  .field("header", name)
                  .field("reason", "transport framing header (TRANSPORT-11)")
                  .emit
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Write the two `sig/` mirrors**

```rbs
module Dexpace
  module Transport
    module AsyncHTTP
      class RequestBody
        def initialize: (untyped body) -> void
        def length: () -> Integer?
        def rewindable?: () -> bool
        def rewind: () -> bool
        def read: () -> String?
      end

      module RequestMapper
        FRAMING_HEADERS: Array[String]
        TOKEN: Regexp

        def self.call: (
          Dexpace::Request request, Dexpace::RequestOptions? options,
          drop_policy: untyped, logger: untyped
        ) -> untyped
      end
    end
  end
end
```

- [ ] **Step 6: Delete the entry file's two stand-ins and run**

Run:
`bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/request_body_test.rb`
`bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/request_mapper_test.rb`
Expected: PASS, 4 and 8 runs.

---
## Task 10: `ResponseMapper` and `ResponseBody` — `TRANSPORT-14`/`24`/`27`, the pull-per-demand body

**Requirement IDs:** none new directly (`TRANSPORT-14`, `TRANSPORT-24`, `TRANSPORT-27` are `8a`'s
rows; this gem satisfies each again as the second driver, Task 19); `ASYNC-21` (N/A row's
property, asserted in Task 16), `SSE-39`'s pull property.
**Design:** "The dispatch path" step 15; "`Dexpace::Transport::AsyncHTTP::ResponseBody`";
verified facts 6 and 11; the `#content_length`/`-1` correction recorded under Discrepancies.

**Files:**
- Create: `.../lib/dexpace/transport/async_http/response_mapper.rb`, `.../response_body.rb`,
  both `sig/` mirrors
- Test: `.../test/dexpace/transport/async_http/response_mapper_test.rb`, `response_body_test.rb`

- [ ] **Step 1: Write the failing tests**

`response_body_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/recording_body"

# Fact 6: lazy, pull-shaped, BINARY, unfrozen; close does not drain. Fact 5 (protocol/http/body's
# own #each already closes on exhaustion) is why this class drives @native.read directly in a
# loop rather than delegating to @native.each -- one close path, this object's own #release, not
# two racing ones.
class DexpaceTransportAsyncHTTPResponseBodyTest < DexpaceTestCase
  ResponseBody = Dexpace::Transport::AsyncHTTP::ResponseBody
  RecordingBody = Dexpace::Transport::AsyncHTTP::Test::RecordingBody

  test "#each yields one native #read per chunk, retagged BINARY, and stops at nil" do
    native = RecordingBody.new(["a".b, "b".b])
    body = ResponseBody.new(native: native, media_type: nil, content_length: -1)

    chunks = []
    body.each { |c| chunks << c }

    assert_equal(["a", "b"], chunks)
    assert(chunks.all? { |c| c.encoding == ::Encoding::BINARY })
  end

  test "#each closes the native body exactly once, on natural exhaustion" do
    native = RecordingBody.new(["a".b])
    body = ResponseBody.new(native: native, media_type: nil, content_length: -1)

    body.each { |_c| }

    assert_equal(1, native.close_count)
  end

  test "an explicit #close after full consumption does not double-close" do
    native = RecordingBody.new(["a".b])
    body = ResponseBody.new(native: native, media_type: nil, content_length: -1)

    body.each { |_c| }
    body.close

    assert_equal(1, native.close_count)
  end

  test "#close before consumption releases the native body exactly once (TRANSPORT-16)" do
    native = RecordingBody.new(["a".b, "b".b])
    body = ResponseBody.new(native: native, media_type: nil, content_length: -1)

    body.close
    body.close

    assert_equal(1, native.close_count)
  end

  test "#source is built with BufferedSource.over, never .wrapping (OI-9)" do
    native = RecordingBody.new(["a".b])
    body = ResponseBody.new(native: native, media_type: nil, content_length: -1)

    assert_instance_of(Dexpace::IO::BufferedSource, body.source)
  end

  test "#content_length maps a native nil length to the -1 sentinel, never nil (BODY-35, " \
       "TRANSPORT-27)" do
    native = RecordingBody.new([], length: nil)
    body = ResponseBody.new(native: native, media_type: nil, content_length: -1)

    assert_equal(-1, body.content_length)
  end

  test "#content_length reports a known native length exactly" do
    native = RecordingBody.new(["hi".b], length: 2)
    body = ResponseBody.new(native: native, media_type: nil, content_length: 2)

    assert_equal(2, body.content_length)
  end
end
```

`response_mapper_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/recording_body"

# TRANSPORT-14: obs-text in a value preserved, a control byte in a value dropped (that header
# only, logged verbose); the malformed-NAME half is unreachable on this adapter (verified fact
# 11 -- protocol-http1 raises BadHeader out of the read, before a response exists to adapt), so
# no test attempts it here -- it is a NAMED WAIVER in Task 19's conformance run, not a silent gap.
# TRANSPORT-24: total status mapping. TRANSPORT-27: malformed Content-Type downgrades to no
# media type; absent/invalid Content-Length maps to the -1 sentinel.
class DexpaceTransportAsyncHTTPResponseMapperTest < DexpaceTestCase
  ResponseMapper = Dexpace::Transport::AsyncHTTP::ResponseMapper
  RecordingBody = Dexpace::Transport::AsyncHTTP::Test::RecordingBody

  def native_response(status: 200, headers: [], body: RecordingBody.new([], length: nil))
    ::Protocol::HTTP::Response.new("HTTP/1.1", status, ::Protocol::HTTP::Headers.new(headers),
                                    body)
  end

  def request
    builder = Dexpace::Request.builder
    builder.url = "https://example.test/"
    builder.build
  end

  test "TRANSPORT-24: a non-standard status still maps, with a readable body" do
    response = ResponseMapper.call(native_response(status: 520), request: request,
                                                                  logger: Dexpace::Instrumentation::Logger::NULL)

    assert_equal(520, response.status.code)
  end

  test "TRANSPORT-14: a control byte in an inbound value is dropped, that header only" do
    native = native_response(headers: [["x-ctl", "a\x01b"], ["x-normal", "n"]])
    response = ResponseMapper.call(native, request: request,
                                            logger: Dexpace::Instrumentation::Logger::NULL)

    assert_nil(response.headers["x-ctl"])
    assert_equal(["n"], response.headers["x-normal"])
  end

  test "TRANSPORT-14: obs-text in an inbound value is preserved" do
    native = native_response(headers: [["x-obs", "caf\xE9".b]])
    response = ResponseMapper.call(native, request: request,
                                            logger: Dexpace::Instrumentation::Logger::NULL)

    assert_equal(["caf\xE9".b], response.headers["x-obs"])
  end

  test "TRANSPORT-27: a malformed Content-Type downgrades to no media type rather than " \
       "failing the response" do
    native = native_response(headers: [["content-type", "not a/;;media type"]])
    response = ResponseMapper.call(native, request: request,
                                            logger: Dexpace::Instrumentation::Logger::NULL)

    assert_nil(response.body.media_type)
  end

  test "TRANSPORT-27: an absent native length maps to the -1 sentinel" do
    response = ResponseMapper.call(native_response, request: request,
                                                      logger: Dexpace::Instrumentation::Logger::NULL)

    assert_equal(-1, response.body.content_length)
  end
end
```

- [ ] **Step 2: Run to confirm they fail**

Expected: FAIL — `uninitialized constant Dexpace::Transport::AsyncHTTP::ResponseBody` /
`ResponseMapper`.

- [ ] **Step 3: Write `lib/dexpace/transport/async_http/response_body.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # A Dexpace::Body over Protocol::HTTP::Body::Readable. Not core's own
      # Dexpace::ResponseBody: that class closes the Dexpace::IO::BufferedSource it was handed,
      # which is correct for a source built with .wrapping (which owns and closes what it
      # wraps) and WRONG for one built with .over (which owns nothing -- verified directly
      # against phase 3a's own design note). This class holds @native itself and closes IT,
      # never relying on the BufferedSource layer to cascade a close it was never given.
      class ResponseBody
        include Dexpace::Body
        include Dexpace::Closeable

        attr_reader :media_type

        def initialize(native:, media_type:, content_length:)
          @native = native
          @media_type = media_type
          @content_length = content_length
          initialize_closeable(owned: true)
        end

        # BODY-35: -1, never nil (verified fact 9 above; TRANSPORT-27's own canonical text names
        # -1 as the sentinel, which the design's "nil" phrasing does not -- see Discrepancies).
        def content_length = @content_length

        # Protocol::HTTP::Body::Readable#each's own default closes on exhaustion AND on error
        # (verified fact 5) -- this loop is written by hand instead, so this object's own
        # Closeable latch is the ONLY thing that ever calls #release, and #close (public,
        # idempotent) rather than @native.close (private, single-shot) is what natural
        # exhaustion calls, so an explicit caller #close afterward is a safe no-op.
        def each
          return to_enum(:each) unless block_given?

          while (chunk = @native.read)
            yield chunk.b
          end
          close
          nil
        end

        def source
          Dexpace::IO::BufferedSource.over(self)
        end

        private

        def release
          @native.close
          nil
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `lib/dexpace/transport/async_http/response_mapper.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # Step 15: TRANSPORT-14's lenient inbound copy, TRANSPORT-24's total status mapping, and
      # TRANSPORT-27's two downgrades. The malformed-header-NAME half of TRANSPORT-14 never
      # reaches this module at all: protocol-http1 raises Protocol::HTTP1::BadHeader out of the
      # native read, before a response object exists to adapt (verified fact 11) -- Task 19
      # carries that as a named waiver, not code here.
      module ResponseMapper
        extend self   # Style/ModuleFunction: extend_self, repository-wide (phase 0)

        # Response::Builder is "a writer per member and #build" (phase 1) -- no readers -- so the
        # headers are built into a local first and assigned, never read back off the builder.
        def call(native, request:, logger:)
          headers = inbound_headers(native, logger)
          builder = Dexpace::Response.builder
          builder.request = request
          builder.protocol = native.version
          builder.status = native.status
          builder.headers = headers
          builder.body = wrap_body(native, headers)
          builder.build
        end

        private

        # TRANSPORT-14: a control byte in a value is dropped (that header only, logged verbose);
        # obs-text is preserved (HeaderSyntax's inbound grammar, HTTP-19, already permits it).
        # Dexpace::Headers.inbound_builder is what applies that looser grammar rather than the
        # outbound one HTTP-18 fixes.
        def inbound_headers(native, logger)
          builder = Dexpace::Headers.inbound_builder
          native.headers.each do |name, value|
            builder.add(name, value)
          rescue Dexpace::InvalidArgumentError
            log_inbound_drop(logger, name)
          end
          builder.build
        end

        def log_inbound_drop(logger, name)
          Dexpace::Instrumentation.contain(
            logger, event: Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED
          ) do
            logger.event(Dexpace::Instrumentation::Severity::VERBOSE)
                  .event(Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED)
                  .field("header", name)
                  .field("reason", "control byte in an inbound value (TRANSPORT-14)")
                  .emit
          end
        end

        # TRANSPORT-27: a malformed/absent Content-Type downgrades to "no media type" rather
        # than failing the response; an absent native #length maps to the -1 sentinel, never
        # nil (BODY-35, and TRANSPORT-27's own canonical text).
        def wrap_body(native, headers)
          media_type = media_type_for(headers)
          length = native.length || -1
          ResponseBody.new(native: native, media_type: media_type, content_length: length)
        end

        def media_type_for(headers)
          raw = headers["content-type"]&.first
          return nil if raw.nil?

          Dexpace::MediaType.parse(raw)
        rescue Dexpace::InvalidArgumentError
          nil
        end
      end
    end
  end
end
```

- [ ] **Step 5: Write the two `sig/` mirrors**

```rbs
module Dexpace
  module Transport
    module AsyncHTTP
      class ResponseBody
        include Dexpace::Body
        include Dexpace::Closeable

        def initialize: (native: untyped, media_type: Dexpace::MediaType?, content_length: Integer) -> void
        def content_length: () -> Integer
        def each: () { (String) -> void } -> nil
        def source: () -> Dexpace::IO::BufferedSource
      end

      module ResponseMapper
        def self.call: (untyped native, request: Dexpace::Request, logger: untyped) -> Dexpace::Response
      end
    end
  end
end
```

- [ ] **Step 6: Delete the entry file's two stand-ins and run**

Run both new test files. Expected: PASS, 7 runs (`response_body_test.rb`) and 5 runs
(`response_mapper_test.rb`).

---
## Task 11: `Adapter` — construction, the eighteen-step dispatch path, the `R13` ensure discipline

**Requirement IDs:** `TRANSPORT-21` (implementation half; the test is Task 16), `TRANSPORT-23`
(implementation half — cites phase 2's `Settlement`, writes no second guard; the test is Task 16),
`ASYNC-6` (both directions, wired here; the tests are Tasks 12 and 13), `ASYNC-22`
(implementation half — no per-call state outside the exchange task and its `Completer`; the test
is Task 16).
**Design:** "The dispatch path, in order," all eighteen steps; "The object model — `Adapter`";
deviation `P8-39`; `R13`'s four-part decision, quoted in full above.

**Files:**
- Create: `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/adapter.rb`,
  the `sig/` mirror
- Test: `.../test/dexpace/transport/async_http/adapter_test.rb` (the synchronous, pre-task half
  only — Tasks 12–16 cover everything that needs a live exchange)

- [ ] **Step 1: Write the failing tests for the synchronous half**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# Steps 1-3: mint the pivot and return it before anything fallible runs (TRANSPORT-21). Every
# assertion below needs no reactor and no fixture server, because every one of them settles
# before step 11 ever spawns a task.
class DexpaceTransportAsyncHTTPAdapterSyncTest < DexpaceTestCase
  Adapter = Dexpace::Transport::AsyncHTTP::Adapter

  def request(headers: {}, url: "https://example.test/")
    builder = Dexpace::Request.builder
    builder.url = url
    builder.headers = headers
    builder.build
  end

  test ".new builds and owns its own Clients; .over borrows a caller-supplied client and " \
       "never closes it (TRANSPORT-15, XCUT-22)" do
    owning = Adapter.new
    assert(owning.owned?)

    client = Object.new
    def client.call(_r) = raise("never called in this test")
    def client.pool = Object.new.tap { |p| def p.close = nil }
    borrowing = Adapter.over(client)
    refute(borrowing.owned?)

    closed = false
    client.pool.define_singleton_method(:close) { closed = true }
    borrowing.close
    refute(closed, "an .over adapter must never close the caller's client")
  end

  test "TRANSPORT-21: calling outside a reactor settles a SeamError through the future, " \
       "never a synchronous raise (P8-39)" do
    adapter = Adapter.new
    future = nil

    assert_nothing_raised { future = adapter.call(request, nil, Dexpace::Cancellation.none) }
    error = assert_raises(Dexpace::SeamError) { future.value }
    assert_match(/Async reactor/, error.message)
  end

  test "TRANSPORT-21: a header HeaderSyntax rejects settles through the future (DEF-25)" do
    adapter = Adapter.new
    bad = request(headers: { "Bad Name" => "v" })

    Sync do
      future = adapter.call(bad, nil, Dexpace::Cancellation.none)
      assert_raises(Dexpace::InvalidArgumentError) { future.value }
    end
  end

  test "a send after close settles ClosedError through the future, never a synchronous raise " \
       "(SEAM-15's channel is TRANSPORT-21's here, boundary 17)" do
    adapter = Adapter.new
    adapter.close

    Sync do
      future = adapter.call(request, nil, Dexpace::Cancellation.none)
      assert_raises(Dexpace::ClosedError) { future.value }
    end
  end

  test "#close is idempotent and does not block" do
    adapter = Adapter.new
    adapter.close
    adapter.close # must not raise
    assert(adapter.closed?)
  end

  test "ASYNC-22: the adapter's own instance state is limited to its Clients map and its " \
       "close latch -- nothing per-call lives on self" do
    adapter = Adapter.new
    ivars = adapter.instance_variables

    assert_equal(
      %i[@borrowed_client @clients @configuration @drop_policy @logger @ssl_context
         @dexpace_owned @dexpace_closed @dexpace_close_mutex].sort,
      ivars.sort,
    )
  end
end
```

- [ ] **Step 2: Run to confirm they fail**

Expected: FAIL — `uninitialized constant Dexpace::Transport::AsyncHTTP::Adapter`.

- [ ] **Step 3: Write `lib/dexpace/transport/async_http/adapter.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # The Dexpace::AsyncTransport seam implementation. #call returns a Dexpace::Async::Future
      # before doing anything fallible (step 1); nothing between step 1 and step 18 raises to
      # the caller except Async::Cancel, NoMemoryError, SystemExit, SignalException and
      # Interrupt -- none of which is a StandardError descendant, so `rescue StandardError`
      # excludes all five automatically and no hand-written "fatal" list exists anywhere below.
      class Adapter
        include Dexpace::Closeable

        DEFAULT_REQUEST_TIMEOUT_SECONDS = 60.0

        REACTOR_MESSAGE = "Dexpace::Transport::AsyncHTTP requires a running Async reactor; " \
                           "wrap the call in `Sync { }` or `Async { }`"

        # .new: builds and owns its Clients map (TRANSPORT-15's owning entry point).
        # .over(client): borrows a single caller-supplied client for every request regardless
        # of origin, and never closes it (TRANSPORT-15's borrowing entry point) -- delegates to
        # the same #initialize with borrowed_client: set, which is what keeps @dexpace_owned a
        # frozen construction-time fact set exactly once (cross-cutting-invariants/093b7681,
        # XCUT-22, SEAM-14).
        # logger: is not in the design's own construction table, which lists only
        # `configuration:`, `ssl_context:`, `connection_limit:` and `drop_policy:` -- but
        # DropPolicy's own #report (Task 7) and every drop site in RequestMapper/ResponseMapper
        # (Tasks 9-10) need a Dexpace::Instrumentation::Logger to emit through, and neither the
        # design's own construction table nor Dexpace::Configuration carries one (verified: 5a's
        # shipped Configuration has no #logger accessor). Added here as a widening -- NFR-4
        # locks a narrowing or a disappearance, never an addition -- defaulting to the silent
        # sink so a caller who never mentions logging gets exactly today's behaviour.
        def initialize(configuration: nil, ssl_context: nil, connection_limit: nil,
                        drop_policy: nil, logger: nil, borrowed_client: nil)
          @configuration = configuration || Dexpace.configuration
          @ssl_context = ssl_context
          @drop_policy = drop_policy || DropPolicy.build
          @logger = logger || Dexpace::Instrumentation::Logger::NULL

          @borrowed_client = borrowed_client # set on both branches: `ruby -w` warns on a read
                                              # of an instance variable no branch ever assigned,
                                              # and #client_for reads it unconditionally.
          if borrowed_client
            @clients = nil
            initialize_closeable(owned: false)
          else
            @clients = Clients.build(configuration: @configuration,
                                      connection_limit: connection_limit, ssl_context: @ssl_context)
            initialize_closeable(owned: true)
          end
        end

        def self.over(client, **kwargs) = new(borrowed_client: client, **kwargs)

        def call(request, options, cancellation)
          completer = Dexpace::Async::Completer.new

          # Step 2: post-close guard, through the future -- SEAM-15's raise is the SYNC seam's
          # channel; TRANSPORT-21 governs this one (boundary 17).
          if closed?
            completer.fail(Dexpace::ClosedError.new)
            return completer.future
          end

          # Step 3: reactor check (P8-39). #call creates no reactor of its own: Sync {} would
          # block the caller's thread and defeat the seam, and an owned reactor thread is a
          # thread pool by another name -- 8b's territory, not this gem's.
          task = ::Async::Task.current?
          if task.nil?
            completer.fail(Dexpace::SeamError.new(REACTOR_MESSAGE))
            return completer.future
          end

          # Steps 4-10: DEF-25's re-validation, the two header drops, endpoint/client
          # resolution -- all on the caller's own fiber, no suspension point, so a failure here
          # is delivered through the future without ever creating a task.
          begin
            native_request = RequestMapper.call(request, options, drop_policy: @drop_policy,
                                                                    logger: @logger)
            client = client_for(request.url)
          rescue StandardError => e
            completer.fail(e)
            return completer.future
          end

          # Keys::REQUEST_TIMEOUT is 8a's constant and is SHARED (the charter's Shared
          # transport contracts item 4): one caller setting governs both transports. 5a ships
          # no #float; #duration returns Float seconds and returns `default` unmodified when
          # nothing is configured -- and its grammar reads a BARE NUMBER AS MILLISECONDS
          # (CFG-7), so REQUEST_TIMEOUT=30 is thirty milliseconds. Documented in this class's
          # YARD block, exactly as 8a documents it in its own.
          deadline = options&.timeout || @configuration.duration(
            Dexpace::Configuration::Keys::REQUEST_TIMEOUT,
            default: DEFAULT_REQUEST_TIMEOUT_SECONDS,
          )

          # Step 11: the exchange task, a CHILD of the caller's task (task.async, never
          # Async {}) -- verified fact 10/3 above: Async {} inside a running reactor does not
          # make the new task a child, so a caller's own structured cancellation would not
          # reach it.
          task.async do |exchange|
            run_exchange(exchange, client, native_request, request, completer, cancellation,
                         deadline)
          end

          completer.future
        end

        private

        # Steps 11-18, inside the child task.
        def run_exchange(exchange, client, native_request, request, completer, cancellation,
                          deadline)
          # Step 13: the cancellation bridge, both directions, wired once. #cancel, never the
          # deprecated #stop (verified fact 4 above / design fact 10).
          #
          # Only ONE of the two is detachable, and the asymmetry is phase 2's, not this gem's:
          # Dexpace::Cancellation#on_cancel returns a Subscription with #detach (the token may
          # outlive the call, so the hook must be removable), while Dexpace::Async::Completer
          # #on_cancel returns `self` -- there is nothing to detach, and nothing to leak, because
          # the Completer is minted per call and dies with the future. Calling #detach on what
          # Completer#on_cancel returns would raise NoMethodError inside the ensure below and mask
          # every exit path.
          cancel_subscription = cancellation.on_cancel { |reason| exchange.cancel(cause: reason) }
          completer.on_cancel { |reason| exchange.cancel(cause: reason) }

          native = nil
          delivered = false
          begin
            # Step 12: one explicit deadline value, on the per-call task, never ambient.
            exchange.with_timeout(deadline) do
              native = client.call(native_request)
              # Step 14: check-after-resume (concurrency-and-async/611b9392).
              cancellation.check!
              # Step 15: response adaptation.
              response = ResponseMapper.call(native, request: request, logger: @logger)
              # Step 18: settle. TRANSPORT-23/SEAM-16 need no second guard here -- Settlement's
              # own "exactly one of response/error" makes a null success unreachable.
              delivered = completer.fulfil(response)
            end
          rescue Dexpace::CancelledError => e
            # Check-after-resume's OWN discovery path: cancellation.check! raising here is the
            # same cancellation the `cancel_subscription` hook above will also deliver as
            # Async::Cancel at this fiber's next scheduler checkpoint -- but a direct, un-
            # suspended #check! can observe it first. Routed through #request_cancel, exactly
            # like the ensure's $! branch below, so both discovery paths produce the one
            # Settlement Future#cancelled? reads true -- never completer.fail(e), which would
            # settle a FAILURE carrying a CancelledError instance rather than a cancellation.
            completer.request_cancel(e.reason)
          rescue StandardError => e
            # Step 17: everything else reaching here is wrapped, except a Dexpace:: error
            # already carrying its own identity (Errors.wrap passes those through unchanged).
            # Async::Cancel is not a StandardError and is never seen by this clause.
            completer.fail(Errors.wrap(e))
          ensure
            # R13, part 1: the ONLY branch Async::Cancel reaches. Close the native response
            # unless it was already delivered.
            cancel_subscription.detach
            Dexpace.close_quietly(native) unless delivered
            # R13, parts 3-4: no `rescue Async::Cancel`/`Async::Stop` anywhere in this method --
            # $! is inspected here, inside an ensure, which never stops the exception
            # propagating and is therefore not a rescue. completer.request_cancel is called
            # (never completer.fail(CancelledError.new(...))) because only #request_cancel
            # produces the Settlement Future#cancelled? reads as true, and it is idempotent, so
            # calling it when the pivot is already settled through the ordinary success/failure
            # path above is a safe no-op.
            completer.request_cancel(cancellation.reason) if $!.is_a?(::Async::Cancel)
          end
        end

        def client_for(url) = @borrowed_client || @clients.fetch(url)

        def release
          @clients&.close
          nil
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/transport/async_http/adapter.rbs`**

```rbs
module Dexpace
  module Transport
    module AsyncHTTP
      # The seam this gem borrows a native client across (.over). Declared as a gem-local
      # interface, never as Async::HTTP::Client, so NFR-11's scan sees no foreign constant --
      # the seam really is a duck type, and the YARD block on .over names Async::HTTP::Client in
      # prose, which the scan does not read.
      interface _Client
        def call: (untyped) -> untyped
        def close: () -> void
        def pool: () -> untyped
      end

      class Adapter
        DEFAULT_REQUEST_TIMEOUT_SECONDS: Float
        REACTOR_MESSAGE: String

        def initialize: (
          ?configuration: untyped?, ?ssl_context: untyped?, ?connection_limit: Integer?,
          ?drop_policy: DropPolicy?, ?logger: untyped?, ?borrowed_client: _Client?
        ) -> void
        def self.over: (_Client client, **untyped) -> Adapter
        def call: (
          Dexpace::Request request, Dexpace::RequestOptions? options,
          Dexpace::Cancellation cancellation
        ) -> Dexpace::Async::Future
      end
    end
  end
end
```

- [ ] **Step 5: Delete the entry file's `Adapter` stand-in and the now-stale registration
  lambda's `**options` forwarding target, run the suite**

Run: `bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/adapter_test.rb`
Expected: PASS, 7 runs. Then `bundle exec rake gates:require_allowlist gates:rbs_surface` for
this gem — the first run of `gates:rbs_surface` that has a real `.over`/`_Client` pair to scan.

---
## Task 12: `TRANSPORT-7`/`9` and `ASYNC-6` direction two — the orphan-close conformance tests

**Requirement IDs:** `TRANSPORT-7`, `TRANSPORT-9`, `ASYNC-6` (the "pivot → task" direction: both
cancelling the token and cancelling the future must reach the in-flight native exchange).
**Design:** `R13` in full — "the test that a correct-looking wrong implementation passes, and
the one it does not."

**Files:**
- Test: `.../test/dexpace/transport/async_http/cancellation_test.rb`

**Deterministic, no sleep, per the design's own three techniques**: the `HoldingServer` from
Task 1 decides when the client leaves the blocking read, so no sleep is needed to "get into" it;
`Dexpace::Cancellation::Source` is the test's own cancel trigger; assertions are on
`close_count`/`task.status`/an event *sequence*, never on elapsed time.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/holding_server"
require_relative "../../../support/recording_body"

# R13: "writes a test asserting the close ran on a cancellation specifically -- not only on a
# timeout, which is the test a correct-looking wrong implementation passes." Both tests below
# are in this one file, deliberately, so neither can be deleted without the other being missed.
class DexpaceTransportAsyncHTTPCancellationTest < DexpaceTestCase
  Adapter = Dexpace::Transport::AsyncHTTP::Adapter
  HoldingServer = Dexpace::Transport::AsyncHTTP::Test::HoldingServer
  RecordingBody = Dexpace::Transport::AsyncHTTP::Test::RecordingBody

  def request(url)
    builder = Dexpace::Request.builder
    builder.url = url
    builder.build
  end

  # TRANSPORT-7: "cancel an in-flight future and assert the native call is cancelled."
  # ASYNC-6, direction "token -> task": cancelling Dexpace::Cancellation reaches the exchange.
  test "TRANSPORT-7/ASYNC-6: cancelling the token aborts a blocked native read and settles a " \
       "terminal, non-retryable CancelledError" do
    server = HoldingServer.new
    adapter = Adapter.new
    source = Dexpace::Cancellation.source

    begin
      Sync do |task|
        future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil, source.token)
        server.wait_for_accept # provably blocked in the body read; no sleep needed
        source.cancel(:token_cancelled)

        error = assert_raises(Dexpace::CancelledError) { future.value }
        assert_equal(:token_cancelled, error.reason)
        refute_respond_to(error, :retryable?) # CancelledError, never Dexpace::TransportError
      end
    ensure
      adapter.close
      server.close
    end
  end

  # ASYNC-6, direction "pivot -> task": cancelling the FUTURE itself, not the token, must also
  # reach the in-flight exchange -- the conformance clause's second half, and the one direction
  # only an async transport can satisfy for real (design's own claim under ASYNC-6).
  test "ASYNC-6: cancelling the future reaches the native exchange" do
    server = HoldingServer.new
    adapter = Adapter.new

    begin
      Sync do
        future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil,
                               Dexpace::Cancellation.none)
        server.wait_for_accept
        future.cancel(:future_cancelled)

        error = assert_raises(Dexpace::CancelledError) { future.value }
        assert_equal(:future_cancelled, error.reason)
      end
    ensure
      adapter.close
      server.close
    end
  end

  # TRANSPORT-9: "a native response delivered after the SDK future has already completed or
  # cancelled must be closed." Deterministic via check-after-resume, not exotic timing: the
  # token is cancelled BEFORE #call runs, so cancellation.check! raises the instant the fake
  # client returns a response the exchange never gets to deliver.
  test "TRANSPORT-9: a native response the exchange obtains after the token was already " \
       "cancelled is closed rather than delivered" do
    native = RecordingBody.new(["late".b])
    fake_client = Object.new
    fake_client.define_singleton_method(:call) do |_req|
      ::Protocol::HTTP::Response.new("HTTP/1.1", 200, ::Protocol::HTTP::Headers.new([]), native)
    end
    fake_pool = Object.new
    fake_pool.define_singleton_method(:close) {}
    fake_client.define_singleton_method(:pool) { fake_pool }
    adapter = Adapter.over(fake_client)
    source = Dexpace::Cancellation.source
    source.cancel(:already_gone) # cancelled BEFORE the call even starts

    Sync do
      future = adapter.call(request("http://example.test/"), nil, source.token)
      assert_raises(Dexpace::CancelledError) { future.value }
    end

    assert_equal(1, native.close_count)
  end

  # The negative twin (ASYNC-20): a response already delivered to the caller must not be
  # closed by a LATE cancellation -- #stop on an already-finished task is a no-op (design fact
  # 8), and this is that property observed through the adapter rather than the raw runtime.
  test "ASYNC-20: cancelling the future after delivery does not close the delivered response" do
    server = HoldingServer.new
    adapter = Adapter.new

    begin
      Sync do
        future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil,
                               Dexpace::Cancellation.none)
        server.wait_for_accept
        server.release("ok")
        response = future.value

        future.cancel(:too_late) # no-op: the pivot is already settled successfully

        refute_predicate(response.body, :closed?)
      end
    ensure
      adapter.close
      server.close
    end
  end
end
```

- [ ] **Step 2: Run to confirm the first two fail for the right reason**

Expected: at this point in the plan `Adapter`/`Clients`/`RequestMapper`/`ResponseMapper` all
exist (Tasks 5–11), so these tests exercise real code end to end; if any of the four fails for a
reason other than a genuine cancellation-ordering bug, stop and re-read `R13` before proceeding
rather than patching the test to match an implementation that guessed wrong.

- [ ] **Step 3: Run to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/cancellation_test.rb`
Expected: PASS, 4 runs. **The test that a correct-looking wrong implementation passes and this
one does not**: an implementation that wrote `rescue StandardError` around the whole exchange
(swallowing `Dexpace::CancelledError` into a plain failure via `completer.fail` instead of
`#request_cancel`) would still pass every other test in this plan up to here — `future.value`
would still raise *some* error — but would fail this file's first and third tests specifically,
because `assert_raises(Dexpace::CancelledError)` would instead see a settled failure whose
`Future#cancelled?` is `false`. That is `R13`'s own point, reproduced rather than asserted.

---
## Task 13: `TRANSPORT-8` and `ASYNC-6` direction one — parent-cancellation versus timeout

**Requirement IDs:** `TRANSPORT-8` (`R14`: satisfied on this adapter, where §12 records it
vacuous), `ASYNC-6` (the "token → task" direction is Task 12's; this task adds the harder case
— a cancellation the SDK never asked for, arriving from the host runtime's own structured
concurrency).
**Design:** `R14` in full; the canonical text quoted for `TRANSPORT-8`; step 12's deadline
scoping.

**Files:**
- Test: `.../test/dexpace/transport/async_http/parent_cancellation_test.rb`

**This task's deadline scope, stated once here because it is not re-argued elsewhere:** the
`with_timeout` wrap in Task 11 covers `client.call` through `completer.fulfil` — the round trip
that produces a `Dexpace::Response` — and stops there, because `IO-40` forbids the body/stream
layer from carrying a timeout of its own and `ResponseBody`/`BufferedSource` are given none
(design's own boundary table). The timeout test below therefore uses a server that withholds
the **response head**, not one that withholds the body (`HoldingServer` withholds the body and
is `Task 12`'s fixture for a different reason).

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "socket"
require_relative "../../../test_helper"

# R14: "every async probe in the charter ran HTTP/1.1 against a local TCPServer; the HTTP/2
# path was not exercised" is not this task's gap to close (that is Task 14's fixture) -- this
# task closes the OTHER half the charter could not verify: TRANSPORT-8's antecedent measured
# live, and the pairing with a genuine timeout on the same path.
class DexpaceTransportAsyncHTTPParentCancellationTest < DexpaceTestCase
  Adapter = Dexpace::Transport::AsyncHTTP::Adapter

  # Accepts and writes nothing -- the client blocks waiting for the status line, which is
  # exactly the phase this half needs to hold: before Client#call has returned anything at all.
  class SilentServer
    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @accepted = Thread::Queue.new
      @gate = Thread::Queue.new
      @thread = Thread.new do
        socket = @server.accept
        @accepted.push(true)
        @gate.pop # parks until #close closes the queue; never a sleep and never a Thread#kill
      rescue IOError, Errno::EBADF, ClosedQueueError
        nil
      ensure
        socket&.close
      end
    end

    def port = @server.addr[1]
    def wait_for_accept = @accepted.pop

    def close
      @gate.close
      @server.close
      @thread.join(1)
      nil
    end
  end

  def request(url)
    builder = Dexpace::Request.builder
    builder.url = url
    builder.build
  end

  test "TRANSPORT-8: cancelling a PARENT task delivers Async::Cancel into the still-live " \
       "exchange and settles a terminal, non-retryable CancelledError -- the antecedent the " \
       "charter could not verify" do
    server = SilentServer.new
    adapter = Adapter.new
    future = nil

    begin
      Sync do |root|
        # The exchange Adapter#call spawns is a CHILD of `supervisor`, not of `root`, because
        # `task.async` inside #call reads Async::Task.current at the moment #call runs.
        # Structured concurrency means `supervisor`'s own block cannot be considered finished
        # until its child (the exchange) is -- so cancelling `supervisor` from `root`, an
        # ordinary sibling relationship and not self-cancellation, cascades into the exchange
        # exactly as an "internal cancel-all" would (TRANSPORT-8's own example phrase).
        supervisor = root.async do
          future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil,
                                 Dexpace::Cancellation.none)
        end
        server.wait_for_accept
        supervisor.cancel

        error = assert_raises(Dexpace::CancelledError) { future.value }
        refute_respond_to(error, :retryable?)
      end
    ensure
      adapter.close
      server.close
    end
  end

  test "TRANSPORT-8's pair: a with_timeout expiry on the SAME withheld-head path settles a " \
       "RETRYABLE Dexpace::TransportError, never CancelledError" do
    server = SilentServer.new
    adapter = Adapter.new

    begin
      Sync do
        req = request("http://127.0.0.1:#{server.port}/")
        options = Dexpace::RequestOptions.builder.tap { |b| b.timeout = 0.05 }.build
        server.wait_for_accept # (a no-op wait here; included only to keep the two tests visibly
                                # symmetric -- the deadline fires regardless of it)
        future = adapter.call(req, options, Dexpace::Cancellation.none)

        error = assert_raises(Dexpace::TransportError) { future.value }
        assert(error.retryable?)
      end
    ensure
      adapter.close
      server.close
    end
  end
end
```

- [ ] **Step 2: Run to confirm they fail, then to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/parent_cancellation_test.rb`
Expected: PASS, 2 runs, both well under the 30-second suite budget (the timeout test's own
`0.05` second deadline is the longest wait in this file). **This is the row that closes `OI-41`
by measurement**: §12 lists `TRANSPORT-8` among the MUSTs that hold vacuously, and this test is
the reason this gem's own checklist row says *satisfied*, not vacuous — a fact this plan cannot
change in `docs/sdk-design-ruby/12-…md` itself (frozen), only report against it (Task 19).

---
## Task 14: The in-process HTTP/2 fixture, plaintext and TLS

**Requirement IDs:** none new (infrastructure for Task 15's `TRANSPORT-12`/`13` tests and
Task 19's second-driver run); resolves open questions 5 and 6.
**Design:** verified facts 2 and 3; "`R16` — who writes the conformance harness"; "What 8c
additionally supplies and `8a` cannot: an HTTP/2 driver."

**Files:**
- Create: `gems/dexpace-transport-async_http/test/support/http2_server.rb`
- Test: `.../test/dexpace/transport/async_http/http2_server_test.rb` (the fixture proves
  itself before Task 15 depends on it)

**Lives in this gem, never in `dexpace-conformance`**: that gem declares `dexpace-core` and
nothing else, and an HTTP/2 server needs `async-http` (boundary the design states explicitly
under `R16`).

**Every call in this task's code was run against the exact scratchpad `GEM_HOME` while writing
this plan** (`/tmp/h2check.rb`, `/tmp/tlscheck.rb`), not left as a sketch to be re-derived —
`Async::HTTP::Server.new(app, endpoint).run` takes the same `Endpoint` object a client also
connects with (`Async::HTTP::Endpoint.parse(url, protocol:)` for plaintext prior-knowledge h2,
two separately-optioned `Endpoint.parse` calls, one per side, for TLS, because the server needs
`cert:`/`key:` and the client needs `cert_store:`); both printed `"HTTP/2"` for
`response.version`. `Async::HTTP::Endpoint#bind` exists but returns a plain `Array` of bound
sockets `Server.new` does not accept (it reads `endpoint.protocol`/`.scheme` on its second
argument) — confirmed by running it and reading the `NoMethodError` — so this fixture passes the
`Endpoint` itself to `Server.new`, not a bound socket.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/http2_server"

# Facts 2 and 3: a plaintext prior-knowledge h2 server/client pair, and a TLS pair negotiating
# h2 by real ALPN against a self-signed certificate. Both measured here as the fixture's own
# proof of concept, before Task 15 builds on it.
class DexpaceTransportAsyncHTTPHTTP2ServerTest < DexpaceTestCase
  HTTP2Server = Dexpace::Transport::AsyncHTTP::Test::HTTP2Server

  test "plaintext prior-knowledge h2 negotiates HTTP/2 with no client-side ALPN" do
    Sync do
      server = HTTP2Server.plaintext { |_request| [200, [], ["hi"]] }
      client = ::Async::HTTP::Client.new(server.client_endpoint)

      response = client.get("/")

      assert_equal("HTTP/2", response.version)
    ensure
      client&.close
      server&.close
    end
  end

  test "TLS negotiates h2 by ALPN against the fixture's self-signed certificate, generated " \
       "fresh for this run" do
    Sync do
      server = HTTP2Server.tls { |_request| [200, [], ["hi"]] }
      client = ::Async::HTTP::Client.new(server.client_endpoint)

      response = client.get("/")

      assert_equal("HTTP/2", response.version)
    ensure
      client&.close
      server&.close
    end
  end

  # Task 15 drives the same assertions over both protocols through this one fixture, so the
  # HTTP/1.1 constructor proves itself here beside the other two.
  test "the http1 constructor serves HTTP/1.1 over the same interface" do
    Sync do
      server = HTTP2Server.http1 { |_request| [200, [], ["hi"]] }
      client = ::Async::HTTP::Client.new(server.client_endpoint)

      response = client.get("/")

      assert_equal("HTTP/1.1", response.version)
    ensure
      client&.close
      server&.close
    end
  end

  test "each run generates its own certificate rather than a cached one" do
    Sync do
      a = HTTP2Server.tls { |_r| [200, [], []] }
      b = HTTP2Server.tls { |_r| [200, [], []] }

      refute_equal(a.certificate.to_der, b.certificate.to_der)
    ensure
      a&.close
      b&.close
    end
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `cannot load such file -- support/http2_server`.

- [ ] **Step 3: Write `test/support/http2_server.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "async/http"
require "openssl"
require "socket"

module Dexpace
  module Transport
    module AsyncHTTP
      module Test
        # An in-process async-http server over BOTH plaintext prior-knowledge h2 and a
        # self-signed TLS endpoint with real ALPN negotiation -- the HTTP/2 driver design's
        # `R16` says only this gem can supply, because 8a's TCPServer fixture speaks HTTP/1.1
        # bytes only. Must be constructed inside a running reactor (Sync/Async): it spawns its
        # own accept-loop task on Async::Task.current, exactly as the adapter's own exchange
        # does for a real request.
        #
        # Generates its own certificate per run (open question 6): an RSA-2048 keygen costs
        # ~100ms (measured incidentally in the design's own fact 3, and again while writing
        # this task), cheap enough to pay every run and avoiding a cached artefact's own
        # .gitignore/invalidation story.
        class HTTP2Server
          attr_reader :client_endpoint, :cert_store, :certificate

          # Three constructors, one fixture. `.http1` exists so Task 15 can ask "what did the peer
          # receive" off the same kind of object on both protocols instead of hand-rolling a
          # second server beside this one.
          def self.plaintext(&handler) = new(tls: false, http2: true, &handler)
          def self.http1(&handler) = new(tls: false, http2: false, &handler)
          def self.tls(&handler) = new(tls: true, http2: true, &handler)

          def initialize(tls:, http2: true, &handler)
            port = free_port
            app = build_app(handler)

            if tls
              generate_certificate!
              server_endpoint = ::Async::HTTP::Endpoint.parse(
                "https://127.0.0.1:#{port}", ssl_context: server_ssl_context,
              )
              @client_endpoint = ::Async::HTTP::Endpoint.parse(
                "https://127.0.0.1:#{port}", ssl_context: client_ssl_context,
              )
            else
              options = http2 ? { protocol: ::Async::HTTP::Protocol::HTTP2 } : {}
              server_endpoint = ::Async::HTTP::Endpoint.parse("http://127.0.0.1:#{port}", **options)
              @client_endpoint = server_endpoint
            end

            @task = ::Async::Task.current.async do
              ::Async::HTTP::Server.new(app, server_endpoint).run
            end
            wait_until_accepting(port)
          end

          # #cancel, never the deprecated #stop (OI-40) -- this plan's own Global Constraint binds
          # its fixtures as well as its lib/, because a fixture is where a deprecated spelling
          # survives longest.
          def close
            @task&.cancel
            nil
          end

          private

          def free_port
            probe = ::TCPServer.new("127.0.0.1", 0)
            probe.addr[1]
          ensure
            probe&.close
          end

          def build_app(handler)
            lambda do |request|
              status, headers, body = handler.call(request)
              ::Protocol::HTTP::Response[status, headers, body]
            end
          end

          # Bind-readiness only -- not a wait for adapter behaviour under test. The server
          # task's own bind happens asynchronously after `#initialize` returns; without this,
          # the very first connection attempt races it. Bounded at 200 x 1ms = 200ms, an order
          # of magnitude above the ~1-5ms this typically takes on this machine.
          def wait_until_accepting(port)
            200.times do
              ::TCPSocket.new("127.0.0.1", port).close
              return
            rescue ::Errno::ECONNREFUSED
              sleep 0.001
            end
            raise "HTTP2Server never started accepting on port #{port}"
          end

          def generate_certificate!
            key = ::OpenSSL::PKey::RSA.new(2048)
            name = ::OpenSSL::X509::Name.parse("/CN=127.0.0.1")
            cert = ::OpenSSL::X509::Certificate.new
            cert.version = 2
            cert.serial = 1
            cert.subject = name
            cert.issuer = name
            cert.public_key = key.public_key
            cert.not_before = ::Time.now
            cert.not_after = ::Time.now + 3600
            factory = ::OpenSSL::X509::ExtensionFactory.new
            factory.subject_certificate = cert
            factory.issuer_certificate = cert
            cert.add_extension(
              factory.create_extension("subjectAltName", "DNS:localhost,IP:127.0.0.1"),
            )
            cert.sign(key, ::OpenSSL::Digest.new("SHA256"))

            @key = key
            @certificate = cert
            @cert_store = ::OpenSSL::X509::Store.new
            @cert_store.add_cert(cert)
          end

          def server_ssl_context
            context = ::OpenSSL::SSL::SSLContext.new
            context.cert = @certificate
            context.key = @key
            context.alpn_select_cb = ->(protocols) { protocols.include?("h2") ? "h2" : protocols.first }
            context
          end

          def client_ssl_context
            context = ::OpenSSL::SSL::SSLContext.new
            context.set_params(verify_mode: ::OpenSSL::SSL::VERIFY_PEER, cert_store: @cert_store)
            context.alpn_protocols = %w[h2 http/1.1]
            context
          end
        end
      end
    end
  end
end
```

`#wait_until_accepting`'s tiny per-attempt `sleep 0.001` is bind-readiness for a fixture's own
accept loop starting up, not a test waiting on adapter behaviour — the same category as
`HoldingServer`'s underlying `Thread.new` needing no equivalent guard only because a raw
`TCPServer#accept` blocks the OS thread it runs on rather than racing a reactor tick.

- [ ] **Step 4: Run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/http2_server_test.rb`
Expected: PASS, 4 runs, each well under one second (RSA-2048 keygen is the slowest step, at
~100ms per the design's own measurement, reproduced while writing this task).

---
## Task 15: `TRANSPORT-12`/`13` dispatched over both protocols

**Requirement IDs:** `TRANSPORT-12`, `TRANSPORT-13`.
**Design:** step 6's own conformance clause; deviation `P8-40`; "The tests each own ID needs" —
"over HTTP/1.1 and over HTTP/2, because only the pair proves `P8-40`."

**Files:**
- Test: `.../test/dexpace/transport/async_http/wire_grammar_test.rb`

**Why both protocols, stated once here rather than per test:** verified fact 4 measured
`protocol-http2` transmitting `"Bad Name"` (lowercased, unvalidated) while `protocol-http1`
raises `BadHeader` on the same input. A test run only over HTTP/1.1 could pass with the wire-
grammar drop deleted entirely — HTTP/1.1's own library would still refuse the header on its own
(differently: by raising, which `TRANSPORT-12` also forbids letting escape) — so only the h2
half proves this gem's own drop is doing anything at all on that protocol.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/http2_server"

class DexpaceTransportAsyncHTTPWireGrammarTest < DexpaceTestCase
  Adapter = Dexpace::Transport::AsyncHTTP::Adapter
  HTTP2Server = Dexpace::Transport::AsyncHTTP::Test::HTTP2Server

  def request(url, headers:)
    builder = Dexpace::Request.builder
    builder.url = url
    builder.headers = headers
    builder.build
  end

  # Both protocols are served by Task 14's one fixture (`.http1` and `.plaintext`), so "what did
  # the peer receive" is read off the SAME kind of object on both, never off raw bytes for one and
  # a parsed request for the other -- and the fixture's own bounded bind-readiness wait is written
  # once rather than copied here.
  %i[http1 plaintext].each do |variant|
    test "TRANSPORT-12/13, P8-40 over #{variant}: a non-token name is dropped, the normal " \
         "header and body still dispatch, and the future completes normally" do
      received = nil
      Sync do
        server = HTTP2Server.public_send(variant) do |req|
          received = req.headers.to_a
          [200, [], ["ok"]]
        end
        endpoint = server.client_endpoint

        adapter = Adapter.over(Async::HTTP::Client.new(endpoint))
        req = request(endpoint.url.to_s, headers: { "Bad Name" => "v", "X-Normal" => "n" })
        response = adapter.call(req, nil, Dexpace::Cancellation.none).value

        assert_equal(200, response.status.code)
        names = received.map { |k, _| k.downcase }
        refute_includes(names, "bad name")
        assert_includes(names, "x-normal")
      ensure
        server&.close
      end
    end
  end

  test "TRANSPORT-13: a real dispatch through a DropPolicy warns once per distinct bad name" do
    sink = Dexpace::RecordingSink.new
    logger = Dexpace::Instrumentation::Logger.build(sink: sink)

    Sync do
      server = HTTP2Server.plaintext { |_req| [200, [], []] }
      adapter = Adapter.over(Async::HTTP::Client.new(server.client_endpoint),
                              drop_policy: Dexpace::Transport::AsyncHTTP::DropPolicy.build,
                              logger: logger)
      req = request(server.client_endpoint.url.to_s, headers: { "Bad Name" => "v" })

      adapter.call(req, nil, Dexpace::Cancellation.none).value
      adapter.call(req, nil, Dexpace::Cancellation.none).value

      warnings = sink.entries.select { |e| e.severity == :warn }
      assert_equal(1, warnings.size)
    ensure
      server&.close
    end
  end
end
```

- [ ] **Step 2: Run to confirm they fail, then to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/wire_grammar_test.rb`
Expected: PASS, 3 runs (two protocol variants plus the dedup check).

**If the HTTP/2 variant passes and the HTTP/1.1 variant does not** (or vice versa): this is
exactly `TRANSPORT-12`'s own antecedent asymmetry (verified fact 4/5) surfacing as a genuine
test failure rather than a fixture bug — re-read `P8-40` before changing either the test or the
implementation, because the correct fix is almost always in `RequestMapper`'s drop predicate
(Task 9), never in loosening the assertion.

---
## Task 16: `TRANSPORT-21`/`23`, `ASYNC-21`/`22`, and the `ASYNC-7` contrast

**Requirement IDs:** `TRANSPORT-21` (test half; implementation is Task 11), `TRANSPORT-23` (test
half), `ASYNC-21` (**N/A**, §11.21 — the property is asserted anyway, on 7b's precedent),
`ASYNC-22` (test half), `ASYNC-7` (this gem's half of the cross-adapter contrast; `8b` owns the
ID).
**Design:** "The tests each own ID needs"; open question 7.

**Files:**
- Test: `.../test/dexpace/transport/async_http/dispatch_conformance_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/http2_server"
require_relative "../../../support/holding_server"
require_relative "../../../support/recording_body"

class DexpaceTransportAsyncHTTPDispatchConformanceTest < DexpaceTestCase
  Adapter = Dexpace::Transport::AsyncHTTP::Adapter
  HTTP2Server = Dexpace::Transport::AsyncHTTP::Test::HTTP2Server
  HoldingServer = Dexpace::Transport::AsyncHTTP::Test::HoldingServer
  RecordingBody = Dexpace::Transport::AsyncHTTP::Test::RecordingBody

  def request(url)
    builder = Dexpace::Request.builder
    builder.url = url
    builder.build
  end

  # TRANSPORT-21's third pre-dispatch failure (the other two are Task 11's own sync suite): a
  # URL whose scheme Async::HTTP::Endpoint cannot build an endpoint for.
  test "TRANSPORT-21: a URL the endpoint cannot build settles through the future" do
    adapter = Adapter.new

    Sync do
      future = adapter.call(request("ftp://example.test/"), nil, Dexpace::Cancellation.none)
      assert_raises(StandardError) { future.value } # the exact class is Endpoints'/async-http's
                                                       # own; TRANSPORT-21's own clause is only
                                                       # that it arrives through the future
    ensure
      adapter.close
    end
  end

  # TRANSPORT-23/SEAM-16: structural, via phase 2's Settlement -- asserted anyway.
  test "TRANSPORT-23: a successful dispatch never settles with a nil response" do
    Sync do
      server = HTTP2Server.plaintext { |_req| [200, [], ["ok"]] }
      adapter = Adapter.over(Async::HTTP::Client.new(server.client_endpoint))

      response = adapter.call(request(server.client_endpoint.url.to_s), nil,
                               Dexpace::Cancellation.none).value

      refute_nil(response)
      assert_instance_of(Dexpace::Response, response)
    ensure
      server&.close
    end
  end

  # ASYNC-21 is N/A (adapter-scoped, §11.21, no reactive adapter ships) -- the property it
  # protects is asserted anyway, on 7b's own precedent for its pull path.
  test "ASYNC-21's property: exactly one native #read per #each yield, with nothing read " \
       "ahead of consumer demand" do
    native = RecordingBody.new(["a".b, "b".b, "c".b])
    body = Dexpace::Transport::AsyncHTTP::ResponseBody.new(native: native, media_type: nil,
                                                             content_length: -1)
    reads_before = []

    body.each do |_chunk|
      reads_before << native.instance_variable_get(:@chunks).size
    end

    # After yielding the FIRST chunk, exactly two remain (one read consumed one chunk,
    # nothing pulled ahead); after the second, exactly one; after the third, zero.
    assert_equal([2, 1, 0], reads_before)
  end

  # ASYNC-22: many concurrent calls through ONE adapter, each resolving to its OWN response,
  # with no cross-talk. Sixteen, because the requirement's own word is "many" and the design's
  # own probe ran eight.
  test "ASYNC-22: sixteen concurrent calls through one adapter resolve with no cross-talk" do
    Sync do
      server = HTTP2Server.plaintext { |req| [200, [], [req.headers["x-nonce"].first]] }
      adapter = Adapter.over(Async::HTTP::Client.new(server.client_endpoint))

      futures = 16.times.map do |i|
        req = Dexpace::Request.builder.tap do |b|
          b.url = server.client_endpoint.url.to_s
          b.headers = { "X-Nonce" => i.to_s }
        end.build
        adapter.call(req, nil, Dexpace::Cancellation.none)
      end

      bodies = futures.each_with_index.map { |f, i| [i, f.value.body_string] }
      assert_equal((0...16).map(&:to_s), bodies.sort_by(&:first).map(&:last))
    ensure
      server&.close
    end
  end

  # ASYNC-7, this gem's own half of the cross-adapter contrast §3.3 fixes: "the reactor-backed
  # ones abort at the next scheduler checkpoint." Measured as a bound, not compared against a
  # README string (open question 7) -- 8b's own suite asserts its own half over a blocking
  # read that is allowed to FINISH; this asserts this adapter's read is ABORTED, promptly.
  test "ASYNC-7: cancellation aborts a blocked read at the next scheduler checkpoint, well " \
       "under the time the response would have taken to arrive naturally" do
    server = HoldingServer.new
    adapter = Adapter.new
    source = Dexpace::Cancellation.source

    begin
      Sync do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        future = adapter.call(request("http://127.0.0.1:#{server.port}/"), nil, source.token)
        server.wait_for_accept
        source.cancel(:abort_now)
        assert_raises(Dexpace::CancelledError) { future.value }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        assert_operator(elapsed, :<, 1.0) # the server never releases; a thread adapter
                                            # LETTING the read finish would hang far longer
      end
    ensure
      adapter.close
      server.close
    end
  end
end
```

- [ ] **Step 2: Run to confirm they fail, then to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-transport-async_http/test/dexpace/transport/async_http/dispatch_conformance_test.rb`
Expected: PASS, 5 runs.

---
## Task 17: `sig/`, the Steep target, `rbs_collection.yaml`

**Requirement IDs:** none new (`NFR-3`, `NFR-11`; open question 1).
**Design:** "The `sig/` shape," all three clauses; `Steepfile`'s existing `target :async_http`
(phase 0).

**Files:**
- Modify: `Steepfile`, `rbs_collection.yaml`
- Verify: every `sig/` file already written in Tasks 5–11 (this task adds nothing new to
  `sig/` — every mirror was written alongside its `.rb` file, per this plan's own habit of
  never leaving a `sig/` file for "later")

- [ ] **Step 1: Determine `gem_rbs_collection` coverage (open question 1)**

```bash
bundle exec rbs collection install
```

Read the resulting `.gem_rbs_collection/` (or its absence). **If `async-http` (or any gem in its
closure) has a row**, add it to `rbs_collection.yaml`'s `gems:` list following the file's own
existing comment shape:

```yaml
gems:
  - name: async-http
```

**If it does not**, leave `gems: []` and add one line to the file's own comment:

```
# async-http (phase 8c): no gem_rbs_collection signatures found as of <date>; every foreign
# constant this gem's own sig/ touches is `untyped` inside this gem's own Steep target.
```

**Either way the public surface is unaffected** — the `sig/` section's three clauses (Task 5's
`Endpoints`, Task 11's `_Client` interface, every `ResponseBody`/native-handle site left
`untyped`) already keep every foreign constant out of a *public* signature, so this step
changes only how strictly this gem's *internals* are checked, never what a consumer's `steep
check` sees.

- [ ] **Step 2: Confirm the `Steepfile`'s `target :async_http` needs no new `library` line**

Phase 0's block (already scaffolded) is:

```ruby
target :async_http do
  check "gems/dexpace-transport-async_http/lib"
  signature "gems/dexpace-transport-async_http/sig", "gems/dexpace-core/sig"
  configure_code_diagnostics(D::Ruby.default)
end
```

No `library "..."` line is added: this gem declares no *stdlib* RBS dependency beyond what
`D::Ruby.default` already includes, and its one third-party dependency's signatures (if any)
come from Step 1's `rbs_collection.yaml` row, not from `library`.

- [ ] **Step 3: Run the full RBS/Steep gate set**

```bash
bundle exec rbs collection install
bundle exec rake rbs:validate
bundle exec rake steep
bundle exec rake gates:rbs_surface
```

Expected: clean. `gates:rbs_surface`'s scan over this gem's `sig/` should report zero
non-`Dexpace::`/non-stdlib constants — `Async::HTTP::Client`, `Protocol::HTTP::*` and
`OpenSSL::*` all stay `untyped` at every public boundary, named only in YARD prose (Task 19
writes the YARD blocks for the four public constants Task 18 below enumerates).

- [ ] **Step 4: `gates:sig_diff` and `gates:surface_snapshot`**

```bash
bundle exec rake gates:sig_diff gates:surface_snapshot
```

`gates:sig_diff` has nothing to diff for this gem (no previous release tag exists yet) — phase 0
already handles the no-tag case, and this step only confirms that handling still fires rather
than erroring. `gates:surface_snapshot` is regenerated as part of Task 19's final wiring, not
here, because this gem's constant tree is not yet final until the registration call and the
public-surface list (Task 18) are both settled.

---
## Task 18: `gates:clean_bundle` on 3.3/3.4/4.0, the CI matrix's 3.2 exclusion, `first-release.md`

**Requirement IDs:** none new (`NFR-1`, `NFR-2`; `P8-36`, `R15`).
**Design:** "The three zero-dependency checks, from this gem's side"; "CI matrix"; the two
`docs/first-release.md` lines under the `OI-38` finding.

**Files:**
- Verify: `.github/workflows/ci.yml` (no edit — Task 3 already made the exclusion live inside
  the Ruby-side tasks, not the YAML)
- Hand to a human: two `docs/first-release.md` lines (this task drafts them; does not file them)

- [ ] **Step 1: Run `gates:clean_bundle` on every Ruby this gem supports**

```bash
for rb in 3.3.8 3.4.10 4.0.6; do
  ~/.local/share/mise/installs/ruby/$rb/bin/ruby -S bundle exec rake gates:clean_bundle
done
```

Expected: `gates:clean_bundle: N gem(s) load in isolation on Ruby <version>.` on each, with
`dexpace-transport-async_http` among the isolated gems on all three — a scratch `Gemfile`
holding only `gem "dexpace-transport-async_http", path: …`, then `bundle exec ruby -e` requiring
it and driving one exchange against an in-process fixture (`Adapter.over` against
`HTTP2Server.plaintext`, reusing Task 14's fixture). The gems activated must be exactly
`dexpace-core`, `async-http` and `async-http`'s own transitive closure — an activation of
`concurrent-ruby`, `logger` or a second HTTP library is the failure this run exists to catch.

- [ ] **Step 2: Run `gates:clean_bundle` on 3.2 and confirm this gem is excluded, not broken**

```bash
~/.local/share/mise/installs/ruby/3.2.11/bin/ruby -S bundle exec rake gates:clean_bundle
```

Expected: `gates:clean_bundle: N gem(s) load in isolation on Ruby 3.2.11.`, with `N` one **less**
than the 3.3+ rows (this gem absent) and every *other* gem still isolating cleanly — proof that
Task 3's `Gemfile`/`test:gems` edit does what it says rather than merely not crashing.

- [ ] **Step 3: Confirm the CI workflow needs no edit**

```bash
ruby -Itest test/gates/ci_workflow_test.rb
```

Expected: PASS, unchanged from before this plan started. The workflow's `test` job already runs
`gates:clean_bundle`/`gates:gemspec_audit`/`gates:require_allowlist`/`test:gems` identically on
every matrix row; the per-Ruby skip lives entirely inside those Ruby-side tasks (Task 3), so
`ci_workflow_test.rb`'s "every listed gate appears in some job" assertion is unaffected — no gate
disappears from any job, one gem is skipped inside several gates on one row.

- [ ] **Step 4: Draft the two `docs/first-release.md` lines**

Handed to a human in Task 19, not filed by this task:

> - `dexpace-transport-async_http` requires Ruby **>= 3.3**, narrower than every other gem in
>   the workspace (`P8-36`, `OI-38`). A consumer on Ruby 3.2 composes `dexpace-core`,
>   `dexpace-transport-net_http`, `dexpace-serde-json`, `dexpace-async-thread` and
>   `dexpace-conformance`, and loses only the reactor transport — `NFR-2`'s separability paying
>   for itself.
> - The gem's transitive closure contains `io-event`, which compiles a C extension
>   (`ext/extconf.rb`). A platform with no toolchain and no precompiled `io-event` cannot
>   install this gem; the same two gems above still work for that consumer.

---
## Task 19: The second-driver conformance convergence, the knowledge note, final wiring

**Requirement IDs:** none new (the second-driver run re-asserts `8a`'s 23 `TRANSPORT` rows, per
the charter's one-row-per-ID convention — no second row for any of them here).
**Design:** `R16` → *What 8c needs the suite to assume — cited, not restated*, which points at the
one twelve-clause **suite contract** in
`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md`
(`R16` → *The suite contract*); "The knowledge note `8c` files"; "The findings proposed for the
registers"; "Deferrals and the register sweep."

- [ ] **Step 1: Run 8a's suite as a second driver — written to run when it exists, and to be a
  no-op today**

**`dexpace-conformance` and `dexpace-transport-net_http` do not exist in this repository yet**
(neither `8a` nor its artifacts have landed as of this plan). This step is therefore written as
the task an implementer runs *once they do*, not as code this plan adds today:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# gems/dexpace-transport-async_http/test/dexpace/transport/async_http/conformance_test.rb
#
# The second-driver run over 8a's suite. It re-asserts 8a's TRANSPORT rows against this adapter
# and owns none of them; the two waivers below name TRANSPORT-14 and TRANSPORT-27 explicitly, and
# both are scoped to THIS adapter -- see the note after this block.
#
# Skips itself entirely until dexpace-conformance exists -- R16 assigns its assertion objects
# and TCPServer fixture to 8a, and this gem is only ever their SECOND driver, never their
# author. If 8c lands before 8a, this file is where the missing artifacts would be written, to
# the twelve-clause suite contract 8a's design owns, and 8a's own design records that it
# consumed rather than wrote them (the charter's own rule, read from this side).
#
# Corrected 2026-09-12 by the cross-sub-phase reconciliation pass. The earlier sketch named
# `Dexpace::Conformance::SeamAssertions`, which 8a ships no such constant for; reached into
# another gem's test/ tree with a five-level require_relative, which styleguide 12.6 forbids and
# which would not exist in the packaged gem; built its factory through
# `Async::HTTP::Endpoint.parse`, which routes through URI::DEFAULT_PARSER and is the one call
# this plan's own Global Constraints forbid (design step 9, boundary 19); and waived
# TRANSPORT-27 for BOTH drivers, which 8a measured to be wrong about Net::HTTP.
if defined?(Dexpace::Conformance)
  class DexpaceTransportAsyncHTTPConformanceTest < DexpaceTestCase
    extend Dexpace::Conformance::MinitestDriver

    conformance(
      Dexpace::Conformance::TransportSuite,

      # Clause 4: a FACTORY, never an instance and never a constant. This adapter routes by
      # Request#url and owns a client per origin, so it needs no base URL: TransportCase#request
      # already builds every request against the live fixture's own port.
      build: ->(**settings) { Dexpace::Transport::AsyncHTTP::Adapter.new(**settings) },
      borrow: ->(client) { Dexpace::Transport::AsyncHTTP::Adapter.over(client) },

      # Clause 8: `send` is ONE primitive, and the async driver is what awaits the future. A
      # cancellation surfaces from here as Dexpace::CancelledError, because Completer#request_
      # cancel settles the Settlement.cancellation that Future#value re-raises (clause 5).
      settle: ->(transport, request, options, cancellation) {
        transport.call(request, options, cancellation).value(cancellation: cancellation)
      },

      # Clause 9: the runner INVOKES each assertion, so the driver may wrap it. This adapter
      # fails its future outside a reactor by design (P8-39), and a body streamed under a fiber
      # scheduler has to be read inside the reactor this opens.
      around: ->(&block) { Sync { block.call } },

      # Clause 12 / §9.3's named-waiver mechanism: the requirement ID is listed so the gap is
      # reported rather than restated. Both are unreachable on THIS adapter; neither is a claim
      # about 8a's, which waives nothing.
      waive: ["TRANSPORT-14", "TRANSPORT-27"],
    )
  end
else
  warn "dexpace-conformance not yet present -- 8a's conformance suite has not landed; this " \
       "gem's second-driver run is a no-op until it does (R16)."
end
```

**Two waivers, both scoped to this adapter, and one of them was wrongly scoped before.**
`TRANSPORT-14`'s malformed-inbound-header-**name** clause is unreachable here — `protocol-http1`
raises `BadHeader` out of the read before a response exists to adapt (verified fact 11, `P8-38`,
`OI-39`). `TRANSPORT-27`'s invalid-`Content-Length` clause is unreachable here too
(`Protocol::HTTP1::BadRequest` out of the read). **Corrected 2026-09-12**: this plan and its design
both reported the second one "unreachable on both MVP adapters for the same reason" and proposed
"one waiver covering both drivers". `8a` measured `Net::HTTP` directly under the block form it uses,
found the head delivered in full before `Net::HTTPResponse#content_length` raises, and implements the
clause (`8a`'s `R4`, resolved as satisfied whole). **`8a`'s driver waives nothing**, and the sentence
that must not survive anywhere is "one waiver covering both drivers".

**Clause 11's second fixture is a separate `conformance(…)` call**, not a second file: the same suite,
the same factory, the same `settle:` and `around:`, and `wire:` pointing at Task 14's in-process HTTP/2
server instead of `WireServer`. That fixture stays in this gem's `test/support/` — `dexpace-conformance`
declares `dexpace-core` and nothing else, and an HTTP/2 server needs `async-http`.

- [ ] **Step 2: Run the whole gate set on all three interpreters this gem supports**

```bash
for rb in 3.3.8 3.4.10 4.0.6; do
  ~/.local/share/mise/installs/ruby/$rb/bin/ruby -S bundle exec rake
done
```

Every one of the seventeen gates, with `gates:gemspec_audit`, `gates:require_allowlist` and
`gates:clean_bundle` now seeing this gem's third-party dependency for the first time on each
row.

- [ ] **Step 3: Regenerate the runtime surface snapshot; confirm the RBS diff has nothing to say**

```bash
bundle exec rake surface:regenerate
```

Confirm the diff shows only additions: this gem's registration call, `Adapter`, `DropPolicy`
and `_Client` are all new to the tree, and `NFR-4`'s lock fails on a signature that disappears
or narrows, which nothing here does. The four constants a later phase may cite (`Dexpace::
Transport::AsyncHTTP`, `::Adapter`, `::DropPolicy`, `::_Client`) each carry a YARD block naming
*why*, not restating the signature — `.over`'s YARD block is where `Async::HTTP::Client` is
named in prose, since `NFR-11`'s scan does not read YARD.

- [ ] **Step 4: Verify the note filed on 2026-09-12 still matches; update it if the implementation
      found otherwise**

`docs/knowledge/notes/transport-adapter.md`'s `## Reference` entry **already exists**: the phase-8
follow-through wrote it on 2026-09-12 from the design's draft — role `review`, a manual
`sha:manual-phase8c-http2-no-validation` marker, backticking `transport-adapter/cb7901ef` as the
harvested rule it annotates — into the same file `8a`'s three entries occupy. Check it against what
this sub-phase actually measured against `protocol-http1` and `protocol-http2` and amend it if
execution contradicts it; do not re-create the file and do not duplicate the entry. Then run
`ruby scripts/verify_knowledge_structure.rb` (the gate) and `ruby scripts/knowledge_drift.rb`
(the hand-run report). `harvested/` is not edited.

- [ ] **Step 5: Hand the register findings to a human**

This plan does not file any of the following — it hands them over verbatim, as the design
already drafted them, for a human to paste:

- Four `docs/open-items.md` rows, `OI-38` through `OI-41` (the design's own text, quoted in
  full in "The findings proposed for the registers").
- The one-sentence addition to `DEF-41`'s row (the design's own text, under "Deferrals and the
  register sweep").
- Task 18's two `docs/first-release.md` lines.
- `docs/deviations.md`'s consolidation of **`P8-36`–`P8-40`** — all five, carried unchanged from
  the design, since this plan judged none of them differently. **No sixth row.** An earlier
  revision of this plan proposed a `P8-41` for the require-set correction (discrepancy 2 below);
  it is retired, because a ledger row records a deliberate difference from the **reference
  contract** and declining to write two `require` lines a phase-0 gate rejects is neither
  deliberate nor a difference from the contract — it is the design being wrong about its own gate,
  and it is now corrected in the design itself. Nothing cites `P8-41` and no row was ever written,
  so no id is reused and `P8-41`–`P8-50` stay unallocated inside 8c's band.

- [ ] **Step 6: Run housekeeping's probe**

```bash
ruby .claude/skills/housekeeping/probe.rb
```

Fix what it reports **without rewriting prose to satisfy a check**. `CLAUDE.md`'s
phase-directory claims sentence is the charter's obligation, not this plan's — if it is still
wrong when this task runs, that is `8a`'s or the phase-level PR's finding, not this plan's to
silently correct. **Do not run `apply.rb --write` and do not commit** — both are the user's to
ask for.

---

## Coverage table

Every one of the ten IDs, the task numbers that implement and test it, and each disposition's
reason.

| ID | Level | Disposition | Implemented in | Tested in |
|---|---|---|---|---|
| `TRANSPORT-7` | MUST | ✅ satisfied | Task 11 (steps 11–13) | Task 12 |
| `TRANSPORT-8` | MUST | ✅ satisfied — §12 records it vacuous; `R14`, `OI-41` (open) | Task 11 (steps 4/17's discrimination) | Task 13 |
| `TRANSPORT-9` | MUST | ✅ satisfied — phase 2's `Completer#fulfil` does the work; this gem writes no second guard | Task 11 (the `ensure`) | Task 12 |
| `TRANSPORT-12` | MUST | ✅ satisfied on both protocols by construction (`P8-40`) | Task 9 (steps 4–6) | Task 15 |
| `TRANSPORT-13` | SHOULD | ✅ satisfied — bounded at 64, case-insensitive | Task 7 | Tasks 7, 15 |
| `TRANSPORT-21` | MUST | ✅ satisfied | Task 11 (steps 1–3, 10) | Tasks 11, 16 |
| `TRANSPORT-23` | MUST | ✅ satisfied — phase 2's `Settlement`, no second guard | Task 11 (step 18) | Task 16 |
| `ASYNC-6` | MUST | ✅ satisfied, both directions | Task 11 (step 13) | Tasks 12 (token→task and pivot→task), 13 (native→pivot: a parent task's cancellation, the hardest case) |
| `ASYNC-21` | MUST | **N/A** — §11.21, adapter-scoped, no reactive adapter ships; property held anyway | Task 10 (`ResponseBody#each`) | Task 16 |
| `ASYNC-22` | MUST | ✅ satisfied — no per-call state outside the exchange task and its `Completer` | Task 11 (construction) | Tasks 11, 16 |

No `DEF-<n>` row applies to any of the ten — none is deferred, dispositioned as ⏳, or moved in
or out of this sub-phase's budget by a register entry.

---

## Discrepancies found against the design

Three, each concrete and each mechanically checkable against the exact installed stack this plan
was written against. None is a disagreement about what 8c should *do* — this plan follows the
design's own reasoning in every case — only about sentences the design states as fact that this
plan found to measure differently. **All three were re-verified independently on 2026-09-12 and
the design was corrected in place for each**; the verification log at the end of this file records
the evidence and the verdict.

1. **`TRANSPORT-27`'s unknown-length sentinel is `-1`, not `nil`.** The design's "The object
   model 8c ships" section states `ResponseBody`'s length accessor as "`#length` -> Integer |
   nil (native `#length`; nil is `TRANSPORT-27`'s sentinel)," and its verified fact 6 says "That
   `nil` is `TRANSPORT-27`'s unknown-length sentinel, free." `grep -n '^| TRANSPORT-27 '
   docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` reads: "an
   absent/invalid Content-Length SHOULD map to the SDK's unknown-length sentinel **(-1)**" —
   matching phase 3b's shipped `BODY-35` (`Dexpace::Body#content_length` is `-1`, never `nil`,
   "an ID-bearing rule beats the styleguide's nil-as-absence default"), read directly from that
   phase's own plan. This plan's `ResponseBody` (Task 10) therefore implements `#content_length`
   (the name every other `Dexpace::Body` in the codebase already uses) and maps a native `nil`
   length to `-1` at the point it is read (`ResponseMapper.wrap_body`), never passing `nil`
   through. Nothing else about the design's `TRANSPORT-27` reasoning changes: the malformed-
   Content-Type downgrade is unaffected, and the invalid-Content-Length half stays unreachable
   for the reason the design's own `R14` report to `8a`'s `R4` already states.
2. **This gem cannot `require` two of the four files the design's own "require set, stated
   exactly" lists.** That paragraph names `dexpace`, `async/http`, `protocol/http/body/readable`,
   `protocol/http/request`, `uri` and `openssl` as the files this gem requires — in the same
   section that says, of a *different* transitive gem, "requiring one directly would be the
   adapter version of the mistake `SEAM-1` bars core from making. Where 8c needs a class from a
   transitive gem it reaches it through `async-http`'s own surface, which is the gem it
   declared." `protocol-http` (which owns both `Protocol::HTTP::Body::Readable` and
   `Protocol::HTTP::Request`) is exactly such a transitive gem: this gem's gemspec declares only
   `dexpace-core` and `async-http` (Task 2), so `RequireAllowlist.third_party_for` — read
   directly from phase 0's own shipped implementation — permits only `async-http`/`async/http`
   for this gem, and a bare `require "protocol/http/body/readable"` would fail
   `gates:require_allowlist` with "not in the require allowlist... declare it as a dependency if
   this is an adapter (`NFR-2`)." Verified directly against the installed stack: `require
   "async/http"` alone already defines both constants (`defined?(Protocol::HTTP::Body::
   Readable)` and `defined?(Protocol::HTTP::Request)` both report `"constant"`), so no
   `require` line for either is needed at all. This plan's `RequestBody`/`RequestMapper` (Task
   9) follow the design's *second* sentence rather than its literal file list: neither file
   carries a `require "protocol/http/..."` of any kind, and both constants are reached through
   `async-http`'s own already-loaded surface. **No ledger row**: see the verification log below for
   why the `P8-41` this plan first proposed is retired, and the design's own require-set paragraph
   for the correction it now carries.
3. **`ASYNC-6`'s inward direction settles through `Completer#request_cancel`, not `Completer#fail`.**
   The design's `ASYNC-6` row reads "the task's own `Async::Cancel` inward to `Completer#fail`",
   and its `R13` part 3 says "the task's own `:cancelled` status plus `Completer#on_cancel` settle
   the pivot". Neither settles a cancellation: `Future#cancelled?` reads
   `@completer.outcome&.cancelled`, which only `Settlement.cancellation` sets, and only
   `Completer#request_cancel` produces one — `#fail(CancelledError.new(...))` settles a *failure*
   whose `#cancelled?` is `false`, and `#on_cancel` registers a hook and settles nothing (phase 2,
   `…-seam-foundations.md:1922-1947`). Phase 2's own `Bridge::AsyncOver#deliver` takes exactly the
   `completer.request_cancel(cancellation.reason)` branch on this path. Task 11 already writes
   `#request_cancel`, with that argument in its own comment; this entry records that the design's
   two sentences were the ones that moved, and both are corrected there.

---

## Verification log (2026-09-12)

An independent pass over all nineteen tasks and the ten-ID coverage table against the design, the
charter and the phase-0 gates. Every change is listed with the one line of evidence that forced
it. Nothing was rewritten to make a check pass; where the design was right and this plan was
wrong, the plan moved, and where this plan was right the design was corrected in place instead
(each of those carries its own "Corrected 2026-09-12" note there).

**Adjudicated: the two discrepancies this plan filed against the design.**

1. **`TRANSPORT-27`'s sentinel is `-1`. The plan is right; the design is corrected.**
   `grep -n '^| TRANSPORT-27 ' docs/product-spec/appendix-c-…md` reads "an absent/invalid
   Content-Length SHOULD map to the SDK's unknown-length sentinel (-1)", and `BODY-35` fixes the
   same value on `Dexpace::Body#content_length`
   (`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md:720`). The design's
   object-model block and its verified fact 6 both now say so.
2. **The require-allowlist gate does apply to adapter gems, so the plan's correction stands — and
   `P8-41` is retired.** `RequireAllowlist.violations(root)` globs `gems/*` and scans every gem's
   `lib/**/*.rb`; `third_party_for` permits only the dependency names that gem's own gemspec
   declares (`["async-http", "async/http"]` here), and `reason_for` fails everything else with
   "not in the require allowlist"
   (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md:2169-2231`). So a
   `require "protocol/http/body/readable"` really would fail the gate; the discrepancy is not
   moot. `CLAUDE.md`'s "adapter gems are exempt" is about the *bundled-gem/zero-dependency* rule,
   not about the scan. Re-measured directly: `require "async/http"` alone reports `"constant"` for
   both `Protocol::HTTP::Body::Readable` and `Protocol::HTTP::Request`, so no second `require` is
   wanted either. **`P8-41` is not filed**: design §10's subject is a deliberate difference from
   the reference contract, and this is the design being wrong about its own gate — now fixed
   there. The band `P8-41`–`P8-50` stays unallocated; no id is reused.

**A third divergence, found in this pass and now filed as discrepancy 3.** The design's `ASYNC-6`
row said the inward direction settles through `Completer#fail`, and `R13` part 3 credited
`Completer#on_cancel`. Neither produces a `Settlement.cancellation`, which is the only outcome
`Future#cancelled?` reads as true; `#request_cancel` does, and phase 2's own
`Bridge::AsyncOver#deliver` takes exactly that branch
(`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:1922-1935`, `:3654`). Task 11 already
wrote `#request_cancel`; the two design sentences are corrected.

**Corrections applied to this plan.**

- **Task 11, the cancellation bridge: `future_subscription.detach` removed.**
  `Dexpace::Async::Completer#on_cancel` returns `self`, not a `Subscription`
  (`…phase2…-seam-foundations.md:1938-1947`) — the call would have raised `NoMethodError` inside
  the `ensure` and masked every exit path. Only the token's subscription is detachable, and the
  asymmetry is now stated in "What was verified during planning".
- **Task 8, `Clients#fetch`: the client is built outside the mutex.** `Endpoints.ssl_context_for`
  runs `OpenSSL::SSL::SSLContext#set_params`, which loads the default certificate store from disk;
  holding the lock across it is the `concurrency-and-async/ee54cb68` + `/f261a143` violation the
  task's own header cites. A lost insert race discards an unused client, which costs nothing
  because `Client.new` opens no socket.
- **Task 3 gains Step 7b: `gates:clean_bundle` learns the per-gem floor.** Its
  `CLEAN_BUNDLE_ENTRIES` hash is iterated unconditionally and each entry runs `bundle install`,
  which Bundler refuses for a path gem this interpreter cannot satisfy
  (`…phase0…-scaffold-and-quality-gates.md:2341-2400`) — so without it the 3.2 row is red for the
  same reason Step 5 exists, and Task 18's Step 2 has nothing to observe. Checked rather than
  assumed for the other two: `gates:gemspec_audit` and `gates:require_allowlist` only load a
  gemspec and read text, so both pass on 3.2 with this gem present and neither is given a skip it
  does not need.
- **The design's `R15` exclusion list is corrected there too** — two tasks too long
  (`gates:gemspec_audit`, `gates:require_allowlist`) and one short (the root `Gemfile`), and `OI-38`'s
  proposed row is re-worded to match, so what a human pastes into the register is what the gates need.
- **Task 3 gains Step 9: the end-state table for `VERSIONS`, `ci.yml`, `tools/versions.rb`,
  `Gemfile`, `tools/versions_gate.rb` and the two rake files**, so `8a` and `8b` align to one
  description rather than to a diff.
- **Task 3, Step 7: the two-identical-branch ternary removed** — dead code, and a RuboCop offence
  in a findings-fatal gate.
- **Four modules move from `module_function` to `extend self`** (`Endpoints`, `Errors`,
  `RequestMapper`, `ResponseMapper`), with their `private_class_method` lines replaced by a
  `private` section. Phase 0's `.rubocop.yml` sets `Style/ModuleFunction: EnforcedStyle:
  extend_self` repository-wide (`…phase0…-scaffold-and-quality-gates.md:740-742`,
  `data-modeling/3775e9d7`), and `rake rubocop` runs `--fail-level=convention`.
- **Every fixture `Thread#kill` and the one bare `sleep` are gone** (`HoldingServer`,
  `SilentServer`). `Dexpace/NoThreadInterrupt` is enabled repository-wide and `.rubocop.yml`
  excludes only `vendor/`, `tmp/`, `doc/` and `test/fixtures/**/*` — a gem's own `test/support/`
  file is scanned like any other, so the plan's "a Minitest support file is fine" note was wrong
  about the gate. Both fixtures now close the `Thread::Queue` or `TCPServer` the thread is blocked
  on and `#join(1)`, which also lets each fixture's `ensure` actually close its socket. The Global
  Constraint is restated accordingly, and its claim about "a 400 ms inter-chunk gap reused
  verbatim" is replaced by what the plan actually contains: one 1 ms bind-readiness pause.
- **Task 15's hand-rolled `http1_server` helper is deleted.** Its readiness loop was
  `200.times { … } rescue retry`, which is not valid as written and would retry the whole method
  on failure; it also leaked a probe socket and called the deprecated `#stop`. Both protocol
  variants now run against Task 14's one fixture, which gains a `.http1` constructor (and a test
  proving it, so Task 14 is 4 runs rather than 3) — the same fixture on both protocols is also
  what `R16` clause 9 asks the suite for.
- **`HTTP2Server#close` calls `#cancel`, not the deprecated `#stop`** — the plan's own Global
  Constraint (`OI-40`), which its fixture broke.
- **Two builder reads removed** (`ResponseMapper.call`, Task 9's `request` test helper). Phase 1
  ships "a writer per member and `#build`" with no readers
  (`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md:3165-3168`, `:2877-2880`), so
  `builder.headers` would raise; the values are built into a local, and the test helper uses
  `Request::Builder#header(name, value)`, which phase 1 does ship.
- **Task 12 declares `RecordingBody`** — the file required it and used it unqualified.
- **Task 19's `conformance_test.rb` sketch gains `# frozen_string_literal: true`, its SPDX line
  and a header naming the IDs it re-asserts** (`NFR-13`, and this plan's own Global Constraint).
  It was the only source sketch in the plan missing both.
- **The coverage table's `ASYNC-6` row names the right directions.** It read "Tasks 12
  (pivot→task), 13 (token→task)"; Task 13 is the *native→pivot* case (a parent task's
  cancellation), as both task headers already said.
- **`### Commands` now lists only commands phase 0 defines**: `bundle exec rake rubocop`,
  `bundle exec rake rbs:validate` and `bundle exec rake steep` replace three bare-binary
  spellings; `rbs collection install` stays, because phase 0's CI runs exactly that
  (`…phase0…-scaffold-and-quality-gates.md:3673`). Task 17's Step 3 block is corrected the same
  way. Everything else in the block — `rake`, `test:gems`, the five `gates:*`, `surface:regenerate`,
  `yard`, `bundler_audit`, per-gem `rake test` — is a real phase-0 task.
- **The four tasks with no failing-test-first step (1, 17, 18, 19) now say why**, in *Task order
  and dependency chain*, so the absence reads as a decision.

**Checked and deliberately left alone.**

- **`RequestBody#read` driving `Dexpace::Body#each` through an `Enumerator`.** §7.1's rule is that
  *this gem* must not acquire a resource inside an `Enumerator` block, and it does not: the
  enumerator wraps a caller-owned `Dexpace::Body` whose `#each` contract, and whose abandonment
  residue, are phase 3b's and are already documented there. The plan's own comment says so.
- **The HTTP/2 fixture's bounded bind-readiness loop.** It waits on a fixture socket being bound,
  never on adapter behaviour, it is bounded at 200 × 1 ms, and the alternative (`Endpoint#bind`)
  returns an object `Async::HTTP::Server.new` does not accept — measured while the plan was
  written.
- **`ASYNC-21` as N/A with the property asserted anyway**, and **`TRANSPORT-8` as satisfied where
  §12 records it vacuous** (`OI-41`). Both match the charter and §11.21/§9.3; neither is re-opened
  here.
- **The coverage table is complete**: ten rows for ten IDs, no `DEF-<n>` moving an ID in or out,
  which agrees with the charter's `8c` scope table.

**Facts re-measured in this pass** (Ruby 3.4.10, `async-http` 0.104.0, `async` 2.45.1):
`required_ruby_version` is `>= 3.3`; `Async::Stop.equal?(Async::Cancel)` is `true` and
`Async::Cancel.ancestors.take(3)` is `[Async::Cancel, Exception, Object]`;
`Async::Task.instance_method(:stop).owner` is `Async::Node` and `#cancel`'s parameters are
`[[:opt, :later], [:key, :cause]]`; `Async::HTTP::DEFAULT_RETRIES` is `3`;
`Protocol::HTTP::Request#initialize`'s nine positional parameters are as Task 9 uses them; and
`Protocol::HTTP::Body::Readable#each` closes the body in its own `ensure`
(`protocol-http-0.71.0/lib/protocol/http/body/readable.rb:94-106`), which is why Task 10 drives
`@native.read` in its own loop.

---

## Handoff to follow-through

Things this sub-phase cannot write itself, recorded here so they are not rediscovered. **None is a
register edit performed by this plan**, and this section is new as of the cross-sub-phase
reconciliation pass on 2026-09-12 — this plan was the only one of the three without one.

1. **`Dexpace::TransportError` is `8a`'s Task 2 to land, not this plan's.** The charter's phase-level
   task 1 read "whoever lands first writes it" and both plans then wrote it, with two shapes. It now
   names `8a`, because `8a` runs first under the recommended order and because `dexpace-conformance`
   asserts against the class in the suite contract's clause 5. **Task 4 here is a verification step**
   and writes the class only in the out-of-order case, in which case it writes `8a`'s shape — the
   superset, with an optional `phase:` keyword and a default message — so the phase never carries two
   definitions. This gem constructs the class positionally and needs nothing that shape lacks.
2. **The deviation bands are settled in the charter and nothing was renumbered.** `8a` `P8-1`–`P8-19`
   (using `P8-1`–`P8-14`), `8b` `P8-20`–`P8-35` (using `P8-20`–`P8-25`), **`8c` `P8-36`–`P8-50`
   (using `P8-36`–`P8-40`)**. This design's own preamble said `8a` had `P8-1`–`P8-20` and `8b`
   `P8-21`–`P8-35`, which was one of three mutually inconsistent statements; it is corrected in place
   there and the charter is now the single source. `P8-41`–`P8-50` stay unallocated and **`P8-41` is
   retired unfiled** — nothing cites it, no `docs/deviations.md` row was ever written, and no id is
   reused. `docs/deviations.md` receives this sub-phase's five rows unchanged.
3. **The suite contract is one twelve-clause list and `8a`'s design owns it.** This design's nine
   clauses were merged into `8a`'s five on 2026-09-12 and this document now cites that section by name
   and path instead of carrying a second copy. `8a`'s plan Task 6 builds the three mechanisms the merge
   added — `settle:`, `around:` and `wire:` on `TransportSuite.run` / `TransportCase` — so Task 19's
   driver has the shapes it needs. **Two things a reviewer of the phase-level PR should check**: that
   `8a`'s Tasks 9–13 call `kase.settle(…)` and never `transport.call(…)` directly, and that no
   assertion compares a header name against the wire's exact spelling, which on this adapter fails
   across the HTTP/1.1–HTTP/2 boundary within one test run.
4. **The header-drop contract is shared and is stated once in the charter** (*Shared transport
   contracts*, item 1 and 2). `FRAMING_HEADERS` gained `trailer` and is now the same **ten** folded
   names `8a` drops; `proxy-authorization` is in neither set. Drops on both adapters are logged through
   `Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED` with `String` `"header"` and `"reason"`
   field keys. That constant is a one-line `dexpace-core` widening **added by whichever sub-phase
   executes first** — Task 7 Step 3 here, or `8a`'s Task 2 Step 5b — and a no-op confirmation for the
   other; the phase-level PR should see exactly one diff for it. `TRANSPORT-13`'s three-mode policy and
   its bound of 64 stay `8c`-only, because the ID is vacuous on `8a`.
5. **`Keys::REQUEST_TIMEOUT` is `8a`'s constant and this gem reads it.** Task 8 Step 3 previously
   declared a second spelling, `TRANSPORT_REQUEST_TIMEOUT_SECONDS`; it is corrected, because one caller
   setting must govern both transports. `Keys::TRANSPORT_CONNECTION_LIMIT` stays this gem's alone.
   A reviewer should see exactly one timeout key in `Dexpace::Configuration::Keys` after phase 8.
6. **Task 3's six-file gate edit is this plan's and nobody else's.** `VERSIONS`, `tools/versions.rb`,
   `tools/versions_gate.rb`, the root `Gemfile`, `tasks/quality.rake` and `tasks/gates.rake` change so
   this gem alone can declare `required_ruby_version >= 3.3` (`P8-36`, `OI-38`). The end state is
   written out once in the charter (*The CI matrix after `8c`'s per-gem Ruby floor*) and in Task 3's own
   Step 9 table; **`8a` and `8b` touch none of those files and run their gates on all three
   interpreters unchanged**, in either execution order. If `8a` or `8b` lands the same edit first, Task
   3 is a verification pass against that table rather than a second diff. `.github/workflows/ci.yml` is
   not edited at all.
7. **`OI-38`–`OI-41` keep their numbers, and the block around them is now known.** `8a`'s four proposed
   open items are `OI-42`–`OI-45` and `8b`'s three are `OI-46`–`OI-48`, assigned in sub-phase order
   after this document's four. Fifteen numbers (`OI-34`–`OI-48`) are cited across phase 8 with no row
   in `docs/open-items.md`; the probe reports each as a dangling citation until they are pasted, which
   is the expected state and not drift. **A filer runs
   `ruby .claude/skills/housekeeping/probe.rb --only citations` before pasting**; if any is filed under
   a different number, every one after it shifts and the shift is mechanical, because nothing in phase
   8 cites an `OI-3x`/`OI-4x` from source code.
8. **Two items the reconciliation pass found in this plan and did not fix, because they are execution-
   time decisions rather than cross-document conflicts.** Task 19's driver sketch is written against
   `MinitestDriver`/`TransportSuite` as `8a`'s design fixes them, but `8a`'s gem does not exist yet, so
   the exact keyword spellings are confirmed at execution time against the shipped code — not pinned
   here, for the same reason Task 9's phase-7c signature calls are not. And the second `conformance(…)`
   call for the HTTP/2 fixture (clause 11) is described rather than written out, because its `wire:`
   argument is Task 14's constructor, which Task 19 runs after.
