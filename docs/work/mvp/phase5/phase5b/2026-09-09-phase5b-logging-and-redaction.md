# Phase 5b — The Logging Facade and Redaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-core`'s logging facade, URL/header redaction engine, payload preview renderer,
and HTTP pipeline instrumentation step at `Stages::LOGGING` — satisfying all 28 `OBS-1`–`OBS-20`,
`OBS-24`, and `OBS-34`–`OBS-40` requirement IDs (26 implemented, 2 deferred: `DEF-41` for `OBS-19`,
`DEF-9` for `OBS-37`), discharging `XCUT-19`, `XCUT-20`, and `XCUT-11`, closing `DEF-27`, taking the
optional diagnostic half of `DEF-32`, supplying `DEF-31`'s shutdown event shape, picking up `DEF-34`'s
two remaining wirings and editing its row, and shipping the HTTP instrumentation step at `Stages::LOGGING`
with tracer and meter slots populated by `5c`.

**Architecture:** A zero-dependency structured logging facade and redaction subsystem composed of:
a four-tier severity enum (`Severity`); frozen, stable vocabularies (`Keys` and `Events`); a duck-typed
sink interface with a frozen default (`NULL_SINK`, `interface _Sink`); a total rendering subsystem
with 8 KiB byte-sliced truncation (`Render`); a thread/fiber diagnostic context bridge with per-key union
restoration over `Fiber[]=` alone (`Diagnostics`, `interface _DiagnosticSnapshot`); an immutable, default-deny
redaction engine (`RedactionPolicy`, `Redactor`) guaranteeing total URL and header sanitization on the way into
`#field`; a mutable event accumulator with an allocation-free inert singleton (`Event`, `Event::INERT`);
a facade entry point with once-per-logger collision diagnostics (`Logger`, `Logger::NULL`); a single fail-safe
error containment primitive (`Instrumentation.contain`); a charset-aware text and binary-safe preview
renderer (`Preview`); a three-level HTTP logging granularity selector with tolerant parsing and strict
required-key layered configuration resolution (`HTTPLogging`); a shared private event emitter (`Emitter`);
and two pipeline steps (`Step`, `AsyncStep`) installed at `Stages::LOGGING`.

**Tech Stack:** Ruby 3.2–4.0 (tested on 3.4.10), zero runtime dependencies, allowlisted stdlib
gems (`uri`, `set`), Minitest, RBS + Steep, RuboCop with phase 0's custom cops, SimpleCov, YARD.

**Spec:** `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`, under the
charter `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`.
`docs/product-spec/15-instrumentation-and-observability.md` is the normative chapter;
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` carries the canonical
text for all 28 `OBS` IDs and related cross-cutting requirements (`XCUT-19`, `XCUT-20`, `XCUT-11`,
`DEF-27`, `DEF-31`, `DEF-32`, `DEF-34`, `DEF-41`).

## Global Constraints

- **`dexpace-core` gains no dependency and the require allowlist does not grow (`R5`, `SEAM-1`, `NFR-1`).**
  The gemspec contains zero `add_dependency` lines. Core may `require` only entries from the phase 0
  allowlist (`monitor`, `uri`, `stringio`, `strscan`, `time`, `date`, `securerandom`, `digest`, `openssl`,
  `forwardable`, `set`, `singleton`). Phase 5b requires exactly two allowlisted entries: `uri` (for URL parsing)
  and `set` (for allow-lists). **Core never `require`s `logger`** (`boundary 1`), because `logger` becomes a
  bundled gem in Ruby 4.0 (`Gem::BUNDLED_GEMS::SINCE["logger"] == "4.0.0"`); the sink is an uncoupled duck type
  (`_Sink`) satisfied structurally by standard loggers.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`).
- **Inside `module Dexpace`, anywhere, every core constant is `::`-qualified**: `::Thread`,
  `::Thread::Mutex`, `::Thread::Queue`, `::Regexp`, `::Time`, `::Process`, `::Fiber`, `::Random`,
  `::Data`, `::ENV`, `::URI`, `::StandardError`, `::ArgumentError`, `::IOError`, `::Kernel`, `::Hash`,
  `::Array`, `::Set`, `::Encoding`.
- **`Dexpace::Instrumentation::Logger` shadows the stdlib `Logger`** (`P5-38`). Because the sink is a duck type
  and §8.1 fixes the facade name as `Logger`, the name is preserved. Every reference to either constant is fully
  qualified (`::Logger` vs `Dexpace::Instrumentation::Logger`). The default sink is named `NULL_SINK` rather than
  `NullLogger` to prevent having two `Logger`-suffixed constants in the same namespace (`P5-19`).
- **`Timeout.timeout`, `Thread#raise`, and `Thread#kill` are strictly forbidden** (`Dexpace/NoThreadInterrupt`).
  Diagnostic containment (`Instrumentation.contain`) catches only `::StandardError`, ensuring asynchronous interrupts
  are not swallowed.
- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** The single mutex in 5b (`OBS-8`'s emit-once guard on `Event`)
  is held strictly across the boolean flag transition and **released before calling the sink** (`boundary 2`, verified
  fact 12), preventing deadlocks when a sink's block yields across fibers on the same thread.
- **`downcase` is called with no arguments repository-wide** (`Dexpace/NoLocaleCaseFold`). All header, parameter,
  and level case folds use bare `downcase` (`OBS-12`, `OBS-18`, `OBS-35`, `OBS-38`).
- **`Regexp.new(source, timeout: 1.0)` per pattern, never `Regexp.timeout`.** All regular expressions (such as RFC 6839
  structured syntax suffix matching in `Preview`) compile with an explicit per-pattern timeout.
- **`URI::RFC3986_PARSER` is pinned explicitly for every URI operation** (`Dexpace/NoUriDefaultParser`). Unescaping
  uses `URI.decode_uri_component` or `URI.decode_www_form_component`, never obsolete `URI::RFC3986_PARSER.unescape`.
- **Domain model construction pattern:** `Data.define`, `private_class_method :new`, `.build` with `Model.required!`
  for fail-fast validation (`SEAM-29`), defensive collection copies with `Model.own`, and shallow `freeze`. `Severity`,
  `RedactionPolicy`, and `HTTPLogging` are immutable `Data` types. `Event` and `Logger` are plain classes with
  `private_class_method :new` (`P5-21`) because `Event` accumulates mutable fields before emit (`OBS-8`) and `Logger`
  holds the once-per-logger collision latch (`OBS-40`).
- **Formatting:** double quotes, 2-space indentation, 100 columns, `consistent_comma` trailing commas.
- **Every new `lib/` file opens with the `require_relative`s for the core files it names.** `lib/dexpace.rb`'s require
  order is an organized declaration rather than a brittle implicit dependency.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/<path>_test.rb   # one suite, red or green
(cd gems/dexpace-core && bundle exec rake test)                                   # the gem's whole suite
bundle exec rake                                                                  # all seventeen gates
bundle exec rubocop                                                               # linting and style gates
bundle exec steep check                                                           # Steep typing gate
bundle exec rbs validate                                                          # RBS validation gate
bundle exec rake surface:regenerate                                               # deliberate; Task 16 only
```

### What was verified during planning, and how

**One interpreter, stated before the facts because it limits every one of them.** The design's thirteen facts
were run on Ruby 3.4.10 (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`) and on nothing else:
`mise ls` lists `bun`, `go`, `node`, and `opencode` and no Ruby; `~/.local/share/mise/installs` holds no `ruby` directory;
and `~/.rbenv`, `~/.rvm`, and `/opt/rubies` do not exist. **The 3.2.11 and 4.0.6 columns have not been run.** Task 1 instructs
the executing worker to install both and run the matrix facts suite. Every claim below is a 3.4.10 claim until Task 1
confirms the matrix, and the five floor-straddling facts carry the consequence of each not holding in open question 1.

The following were re-run on 3.4.10 while writing this plan, because each decides a code fence:
1. `Fiber[]=` writes and reads without a warning; `Fiber#storage=` warns on every call with `:experimental` category and
   rejects `String` keys with `TypeError`. `Fiber[:a] = nil` deletes the key (`Fiber.current.storage.key?(:a)` is `false`).
2. `Fiber.current.storage` returns a fresh, unfrozen `Hash` on every call. In a fiber created with `Fiber.new(storage: nil)`,
   `Fiber.current.storage` is `nil`, not `{}`.
3. The per-key union restore `(prior.keys | snapshot.keys).each { |k| Fiber[k] = prior[k] }` is exact. A prior key holding
   literal `nil` restores as absent (`prior2 = {a: nil, b: 1}` restores as `{b: 1}`), which is reachable only via the
   experimental setter `P5-23` avoids.
4. Scoped `Warning.warn` filter around `Fiber#storage=` works, but mutates process-global state; per-key restore over `Fiber[]=`
   avoids both the warning and the process-global mutation.
5. The inert-chain allocation count, measured against a stand-in for `Event::INERT` (a frozen singleton whose
   builder methods return `self` and whose `#emit` is a no-op — `Event` does not exist until Task 9): with a
   `Symbol` key and an `Integer` value the two-loop delta is exactly **0** with and without
   `# frozen_string_literal: true`; with a bare `"x"` literal it is **0** with the comment and **~1000**
   without. The argument types, not the magic comment, are what make the assertion file-independent (`R8`).
6. `URI::RFC3986_PARSER` raises `URI::InvalidURIError: cannot set user with opaque` and `query conflicts with opaque` on component
   assignment to opaque URIs (`mailto:`, `urn:`, `data:`). `P5-27`'s rule (never assign absent components) keeps opaque URIs
   untouched.
7. `String#downcase` raises `ArgumentError: input string invalid` on percent-decoded invalid UTF-8 (e.g. `URI.decode_www_form_component("%FF")`).
   Because `ArgumentError` is not a `URI::Error`, `Redactor` rescues `::StandardError` (`P5-26`).
8. Rendering totality: anonymous exception classes (`Class.new(StandardError)`) have `nil` names; objects whose `#to_s` raises
   and exceptions whose `#message` raises propagate `StandardError`. `Render` guards class names and rescues `::StandardError`.
9. `OBS-7` cap: `#byteslice(0, 8192)` on multibyte strings can create invalid encodings; `#scrub("")` before appending the truncation
   marker ensures valid UTF-8. The cap is strictly on bytesize (`P5-29`).
10. `Symbol#name` returns the same frozen `String` on every call; `Symbol#to_s` allocates a fresh string each time. `Diagnostics.folded`
    uses `Symbol#name` (`P5-24`).
11. Transcoding from `Encoding::BINARY` directly destroys non-ASCII characters; retagging with `force_encoding` first and then encoding
    to UTF-8 preserves all characters (`OI-7`, `P5-31`).
12. `Thread::Mutex` is per-fiber-owned and non-reentrant. Mutexes must be released before yielding to sink blocks.
13. `Async::Future#on_settle` yields a `Settlement` (`Data.define(:response, :error, :cancelled)`, whose one
    predicate is `#success?`) on the settling thread/fiber, "invoked exactly once". Read out of phase 2's
    shipped definition, not measured.

## This plan's open questions, resolved

The design closes with six open questions for the plan. Five are resolved below with concrete decisions and rationale; **question 1 is an instruction to a future worker and is not claimed as done**. Questions 1–6 are the design's own six, in its order; **question 7 is a seventh the design did not anticipate**, raised by this plan and settled at the 5b/5c reconciliation pass rather than left open — it is filed as `OI-31`.

1. **Re-running the five floor-straddling facts on 3.2.11 and 4.0.6.**
   - *Decision:* Task 1 ships `logging_matrix_facts_test.rb`, asserting Facts 1 (`Fiber[]=` write/delete without warning), 2 (`Fiber.current.storage` fresh copy and `nil` handling), 3 (per-key union restore), 6 (`URI::RFC3986_PARSER` opaque URI raises and minimal mutation), and 9 (`#byteslice` multibyte invalidity and `#scrub` sanitization). Task 1 installs `ruby@3.2.11` and `ruby@4.0.6` and runs the harness on each.
   - *What has and has not been run:* **Only 3.4.10 is installed on the authoring machine**, so no fact has been observed on 3.2.11 or 4.0.6. Task 1 instructs the worker to run both; results are recorded in the Task 1 execution log.
   - *If a fact does not hold on the floor:*
     - Fact 1: If `Fiber[:k] = nil` stores rather than deletes on some Ruby, the restore loop deletes explicitly (`Fiber.current.storage&.delete(k)`) instead of assigning; `P5-23` survives.
     - Fact 2: If `Fiber.current.storage` is not `nil` on `Fiber.new(storage: nil)`, the `|| {}` guard remains safe and idempotent.
     - Fact 3: The per-key union restore remains the single warning-free mechanism; if `nil` restoration differs, `P5-23`'s documented residual covers it.
     - Fact 6: If opaque URI assignment behavior differs, `P5-27`'s rule never assigns absent components, so opaque URIs never invoke the setters. Totality is preserved by `rescue ::StandardError`.
     - Fact 9: If `#byteslice` behavior differs, `#scrub("")` guarantees valid string encoding before appending the marker on all versions.

2. **Reconciliation with `5c` (2026-09-09) — adoption of cross-phase contracts.**
   - *Decision:* Adopt the reconciled names and contracts as written. `Diagnostics::TRACE_ID = :"trace.id"`, `Diagnostics::SPAN_ID = :"span.id"`, and `DEFAULT_KEYS` are owned by 5b as `Symbol`s; `5c` cites them and defines no duplicates. `Keys::INSTRUMENT_REQUEST_COUNT` (`"http.client.request.count"`) and `Keys::INSTRUMENT_REQUEST_DURATION` (`"http.client.request.duration"`) are owned by 5b (`R11`, `P5-16`). `Step` and `AsyncStep` default `tracer_factory:` to `Dexpace::Instrumentation::NO_TRACER_FACTORY` and `meter:` to `Dexpace::Instrumentation::NO_METER` (`P5-33`). 5b defines `interface _Sink` and `interface _DiagnosticSnapshot`; `interface _Meter`, `_Counter`, and `_Histogram` belong to `5c`. The recording doubles `RecordingTracer`, `RecordingSpan`, and `RecordingMeter` belong to `5c` and are reused by 5b (`P5-48`).

3. **Confirmation of `Dexpace::MediaType` accessor names.**
   - *Confirmed against phase 1's shipped definition:* `MediaType` is `Data.define(:type, :subtype, :parameters)`, with `#type` and `#subtype` **already folded to lower case at construction** (`HTTP-23`), so `Preview` performs no fold of its own and the design's "four `downcase` call sites" is three in 5b's code. `#charset` returns the value downcased, or `nil` when absent **or unrecognised**, and never raises (`HTTP-24`) — which is what makes `Encoding.find` unreachable from `Preview`. There is no `#suffix` reader.
   - *Decision:* `Preview.render` reads `media_type.type` and `media_type.subtype`. It matches the structured syntax suffixes (`+json`, `+xml`) using a compiled, per-pattern timed regular expression `SUFFIX_REGEXP = ::Regexp.new('(\\+json|\\+xml)\\z', timeout: 1.0)`. `P5-31` retains the regexp pattern.

4. **Confirmation of `Dexpace::Async::Future#on_settle` and `Settlement` shape.**
   - *Confirmed against phase 2's shipped definition:* `class Settlement < ::Data.define(:response, :error, :cancelled)`, `include Dexpace::Model`, `private_class_method :new`, built through `.build(response:, error:, cancelled:)`, `.success(response)`, `.failure(error)` or `.cancellation(error)`. Its `initialize` enforces "exactly one of response or error" and "a cancelled settlement carries an error". **Its only predicate is `#success?`, which is `error.nil?`** — there is no `#cancelled?` (the reader is `#cancelled`, no question mark), no `#value` and no `#outcome`. `Future`'s surface is `#settled?`, `#cancelled?`, `#wait(cancellation:)`, `#value(cancellation:)`, `#on_settle { |settlement| … }` and `#cancel(reason = nil)`; `#outcome` is on `Completer` and *returns* a `Settlement`.
   - *Decision:* `AsyncStep` branches on **`#success?` alone**, which is total because `initialize` guarantees exactly one of the two is set. On success it emits `http.response` with the status code and headers; otherwise it emits the failure `http.response` with `Keys::ERROR_TYPE` from `settlement.error.class.name` (falling back to `"Error"` for an anonymous class, verified fact 8) and attaches `settlement.error` via `#cause`. **A cancellation needs no third branch**: `.cancellation(error)` carries an error, so it takes the failure branch and `error.type` names the cancellation error's own class.

5. **Default for `preview_bytes:` in `Step.build` and `AsyncStep.build`.**
   - *Decision:* `Step.build` and `AsyncStep.build` take `preview_bytes: nil` as a keyword. When `level` is `HTTPLogging::BODY`, `preview_bytes` MUST be provided as a positive integer; if `nil` or non-positive, `.build` raises `Dexpace::InvalidArgumentError` through the one `SEAM-29` message form (`P5-36` precedent: fail fast rather than baking in an unconfigured silent limit).
   - *Where 8192 comes from, stated because a magic number in an `NFR-4`-locked signature is permanent:* it is **not** a default in any 5b signature. `OBS-36`'s own canonical text is "body capture MUST be bounded to a configurable preview size (**reference default 8 KiB**)", so 8 KiB is the *specification's* reference figure and a **caller's** choice, resolved and passed in: `configuration.integer(Dexpace::Configuration::Keys::LOG_PREVIEW_BYTES, default: 8 * 1024)`. `Configuration#integer(name, default: nil)` is `5a`'s shipped accessor and `LOG_PREVIEW_BYTES` is the one key name `DEF-34` has 5b add in the change that reads it. Putting the figure in `Step.build`'s default instead would make a memory bound nobody chose, and `NFR-4` locks a default the moment it ships.

6. **Recording-sink and test doubles under `gems/dexpace-core/test/support/`.**
   - *Survey of existing test support:* Phases 2 through 5a ship stream, source, clock, and scheduler fakes, none of which implement the `_Sink` duck type or fiber storage isolation.
   - *Decision:* Task 1 creates `test/support/recording_sink.rb` (`Dexpace::RecordingSink`, implementing `_Sink` with per-severity enablement switches and an array of recorded entries) and `test/support/diagnostic_context.rb` (`Dexpace::DiagnosticContext.preserve` helper for test isolation). For tracing and metrics, 5b reuses `5c`'s `RecordingTracer`, `RecordingSpan`, and `RecordingMeter` rather than creating redundant doubles (`DEF-29`, `P5-48`).
   - *Namespace, settled at reconciliation:* both of 5b's doubles are **flat under `Dexpace`**, not under `Dexpace::Instrumentation`. `5a`'s three — `Dexpace::FakeClock`, `Dexpace::FakeSource`, `Dexpace::ProbeScheduler` — are the precedent that decides it, `5c`'s six follow the same rule, and 5b's own `Dexpace::DiagnosticContext` already did. The draft's `Dexpace::Instrumentation::RecordingSink` would have put a test-only constant in the shipping namespace the runtime surface manifest walks.

7. **How the step reaches the execution context — settled, and filed as `OI-31`.**
   - *What was found:* the design's step body calls `tracer_factory_for(request)`, `bundle_for(request)` and `operation_name_for(request)`, and **no mechanism exists by which a pipeline step can reach a `RequestContext` or an `Instrumentation::Bundle`.** Phase 4c is explicit — "4c does not consume 4a at all" — `Cursor`'s whole surface is `#call`, `#fork`, `#may_fork?`, `#request`, `#options`, `#cancellation`, `#state(stage)` and `#spent?`; `Dexpace::Request`'s members are `(:method, :url, :headers, :body)` with no `#context`; `Dexpace::RequestOptions`' — the other thing `Cursor` hands out — are `(:timeout, :max_retries, :tags)`; `PIPE-11` forbids reading per-call state from ambient storage ("per-request mutable state MUST live in the per-call cursor … never on the step"); and `CTX-11`'s `ContextStore` is not a back door, because the step holds no call key and `CTX-13` lets the store evict any entry, "the most-recently inserted included". Phase 4a's forward-obligations table hands phase 5 the `Bundle` and `RequestContext#operation_name` and names **no pipeline seam** for them.
   - *Verified at the reconciliation pass and unchanged:* every one of those readings was re-checked against phase 4a's and 4c's shipped documents rather than taken from this plan. The finding holds.
   - *Decision:* **the first clause of the reconciled precedence is not implemented in phase 5, and it is not left in this plan's margin.** It is filed as **`OI-31`** in `docs/open-items.md`, both designs state the degradation where they argue for the rule, and `Step`'s `bundle_for` carries the reasoning in a comment naming the row. The three helpers resolve through `respond_to?` to the step's own `tracer_factory:` keyword and to `Bundle::NONE`, so `Step` is correct and testable **today** against a real `Dexpace::Request`, and the degraded path is exactly `OBS-34`'s and `XCUT-19`(e)'s default configuration — no tracer, no meter, `none`. **`OBS-34`'s conformance clause is unaffected**, because the step's own keyword supplies the tracer factory and the meter the test asserts against.
   - *Who closes it:* **phase 6**, which owns the pillar steps and is the first thing that either widens `Cursor` with a context reader or has `Pipeline.standard` (`DEF-39`) thread a bundle in at construction. Both are widenings and therefore `NFR-4`-legal. When it lands, `bundle_for` is the one method that changes and no signature moves — which is why the `respond_to?` probes stay rather than being deleted as dead code.

## Task order and dependency chain

Sixteen tasks, in exact buildable dependency order:

1. **Matrix fact verification and test support doubles** (`logging_matrix_facts_test.rb`, `RecordingSink`, `DiagnosticContext`) — installs `ruby@3.2.11` and `ruby@4.0.6`, verifies the five floor-straddling facts on all three, and produces the test doubles required by later tasks.
2. `Dexpace::Instrumentation::Severity` (`OBS-2`, `P5-16`, `P5-17`) — four-level frozen `Data` closed set with `.of` factory; standalone.
3. `Dexpace::Instrumentation::Keys` and `::Events` (`OBS-4`, `OBS-20`, `OBS-39`, `P5-16`) — frozen string constants for stable event and field vocabulary; standalone.
4. `Dexpace::Instrumentation::NULL_SINK` and RBS `_Sink` (`OBS-1`, `OBS-2`, `P5-16`, `P5-19`) — frozen duck-typed default sink and public RBS interface; needs Task 2.
5. `Dexpace::Instrumentation::Render` (`OBS-6`, `OBS-7`, `P5-29`) — private total value rendering and 8 KiB byte-sliced truncation; standalone.
6. `Dexpace::Instrumentation::Diagnostics` and `_DiagnosticSnapshot` (`OBS-10`, `OBS-24`, `P5-16`, `P5-17`, `P5-22`, `P5-23`, `P5-24`) — fiber storage capture, union restoration, and folded context; needs Task 3.
7. `Dexpace::Instrumentation::RedactionPolicy` (`OBS-12`, `OBS-17`, `OBS-18`, `XCUT-19`, `P5-16`, `P5-17`, `P5-30`, `P5-35`) — immutable configuration model for URL and header sanitization; standalone.
8. `Dexpace::Instrumentation::Redactor` (`OBS-11`–`OBS-18`, `XCUT-19`, `XCUT-20`, `P5-16`, `P5-17`, `P5-25`, `P5-26`, `P5-27`, `P5-28`) — total URL and header redactor; needs Task 7.
9. `Dexpace::Instrumentation::Event` and `Event::INERT` (`OBS-1`, `OBS-3`–`OBS-9`, `OBS-39`, `OBS-40`, `P5-16`, `P5-17`, `P5-18`, `P5-20`, `P5-21`) — mutable event builder and frozen inert singleton; needs Tasks 2, 3, 5, 6, 8.
10. `Dexpace::Instrumentation::Logger` and `Logger::NULL` (`OBS-1`, `OBS-2`, `OBS-9`, `OBS-10`, `OBS-40`, `P5-16`, `P5-17`, `P5-38`) — logger facade and null logger instance; needs Tasks 4, 6, 8, 9.
11. `Dexpace::Instrumentation.contain` (`OBS-20`, `XCUT-20`, `P5-17`, `P5-37`) — fail-safe emission containment module function; needs Tasks 2, 3, 10.
12. `Dexpace::Instrumentation::Preview` (`OBS-38`, `P5-16`, `P5-17`, `P5-31`) — charset-aware text and binary-safe payload preview renderer; standalone.
13. `Dexpace::Instrumentation::HTTPLogging` (`OBS-34`, `OBS-35`, `P5-16`, `P5-17`, `P5-36`) — logging level closed set, tolerant parser, and layered resolver; standalone.
14. Downstream register wirings (`DEF-27`, `DEF-32`, `DEF-34`, `P5-8`) — wirings in `closeable.rb`, `hooks.rb`, `proxy/resolution.rb`, and `configuration/keys.rb`; needs Tasks 3, 10, 11.
15. `Dexpace::Instrumentation::Emitter`, `Step`, and `AsyncStep` (`OBS-34`, `OBS-36`, `OBS-39`, `OBS-20`, `DEF-34`, `P5-16`, `P5-17`, `P5-33`, `P5-34`) — private emitter and pipeline steps at `Stages::LOGGING`; needs Tasks 3, 10, 11, 12, 13, 14.
16. Final wiring, surface snapshot, RBS baseline, checklist, and register edits — `lib/dexpace.rb` require order, surface regeneration, RBS validation, checklist update, and deferred/open items registers.

---
## Task 1: Matrix Fact Verification and Test Support Doubles

**Requirement IDs:** `OBS-1`, `OBS-2`, `OBS-7`, `OBS-10`, `OBS-15`, `OBS-24`.
**Design:** "The verified Ruby facts this phase is built on" (Facts 1, 2, 3, 6, 9); "Testing strategy" (Two doubles of 5b's own: `RecordingSink`, `DiagnosticContext`).

**Files:**
- Create: `gems/dexpace-core/test/support/recording_sink.rb`
- Create: `gems/dexpace-core/test/support/diagnostic_context.rb`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/logging_matrix_facts_test.rb`

**Interfaces:**
- Consumes: Ruby standard library, core `Dexpace` namespace.
- Produces: `Dexpace::RecordingSink` and `Dexpace::DiagnosticContext` test support doubles.

**The file is `logging_matrix_facts_test.rb` and not `matrix_facts_test.rb`, and that is a
reconciliation fix.** Both this plan and `5c`'s claimed
`test/dexpace/instrumentation/matrix_facts_test.rb` — two different suites at one path, written in
isolated worktrees, and whichever landed second would have overwritten the first with no conflict to
notice, because the class names differ. `5c`'s is `tracing_matrix_facts_test.rb`. `5a`'s
`test/dexpace/matrix_facts_test.rb` sits a directory up and is untouched by either.

- [ ] **Step 1: Install the two interpreters this plan has not run on**

Only 3.4.10 is installed on the authoring machine, so the floor (3.2.11) and ceiling (4.0.6) columns are
unobserved. Install both before writing any code that rests on a floor-straddling fact:

```bash
mise install ruby@3.2.11 ruby@4.0.6
mise exec ruby@3.2.11 -- ruby -v
mise exec ruby@4.0.6  -- ruby -v
```

Then run this task's suite on **each** of the three, not only the development interpreter:

```bash
for v in 3.2.11 3.4.10 4.0.6; do
  mise exec ruby@$v -- ruby -w gems/dexpace-core/test/dexpace/instrumentation/logging_matrix_facts_test.rb
done
```

If either refuses to build, stop and record it here rather than proceeding on the assumption that 3.4.10
speaks for the range: every YARD claim in this sub-phase narrows to the versions actually observed, and
open question 1's per-fact fallbacks apply.

- [ ] **Step 2: Write the matrix facts and test support doubles test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
require_relative "../../support/diagnostic_context"
require "uri"

# Exercises: OBS-1, OBS-2, OBS-7, OBS-10, OBS-15, OBS-24
class LoggingMatrixFactsTest < DexpaceTestCase
  # DexpaceTestCase prepends FatalWarnings to Warning.singleton_class, so the ONE
  # Fiber#storage= call this sub-phase makes (here, and in diagnostics_test.rb's unfiltered
  # mode) would fail its own test on the warning it is asserting. This harness prepends OVER
  # FatalWarnings and is armed only inside capture_warnings. It is a test-file harness, not a
  # third test-support double: the design fixes 5b's doubles at exactly two, and 5a set the
  # precedent inline in proxy_test.rb for the identical reason. The sink is thread-local and
  # the module holds no state of its own, so `rake test` loading several suites into ONE
  # process prepends several cooperating copies rather than copies that shadow one another
  # and fall through to FatalWarnings.
  module WarningCapture
    def warn(message, category: nil)
      sink = ::Thread.current[:dexpace_warning_sink]
      return super if sink.nil?

      sink << [message, category]
      nil
    end
  end
  ::Warning.singleton_class.prepend(WarningCapture)

  def capture_warnings
    sink = []
    ::Thread.current[:dexpace_warning_sink] = sink
    yield
    sink
  ensure
    ::Thread.current[:dexpace_warning_sink] = nil
  end

  test "Fact 1: Fiber[]= writes and deletes without warning; Fiber#storage= warns and rejects String keys" do
    warnings = capture_warnings do
      ::Fiber[:matrix_key] = 123
      assert_equal(123, ::Fiber[:matrix_key])

      # Deletion behavior via nil assignment
      ::Fiber[:matrix_key] = nil
      refute(::Fiber.current.storage&.key?(:matrix_key))
    end
    # R12 turns on this half: Fiber[]= is warning-free, which is why the restore loop uses it.
    assert_empty(warnings)

    # Fiber#storage= warns with category :experimental on every call ...
    storage_warnings = capture_warnings do
      ::Fiber.current.storage = { matrix_key: 1 }
    end
    assert_equal(1, storage_warnings.size)
    assert_equal(:experimental, storage_warnings.first[1])
    assert_includes(storage_warnings.first[0], "Fiber#storage=")

    # ... and rejects a String key, which Fiber[]= silently coerces. This is what makes the
    # diagnostic-context key space Symbol-shaped (P5-24). The call still WARNS before it
    # raises, so it has to sit inside the harness too: outside it, FatalWarnings turns the
    # warning into a RuntimeError and assert_raises(TypeError) never sees its exception.
    capture_warnings do
      assert_raises(::TypeError) { ::Fiber.current.storage = { "str_key" => 1 } }
    end

    ::Fiber[:"k.dot"] = 1
    assert_equal(1, ::Fiber[:"k.dot"])
  ensure
    ::Fiber[:"k.dot"] = nil
    ::Fiber[:matrix_key] = nil
  end

  test "Fact 2: Fiber.current.storage returns a fresh, unfrozen Hash and handles nil storage" do
    s1 = ::Fiber.current.storage
    s2 = ::Fiber.current.storage
    refute_same(s1, s2)
    refute(s1.frozen?)

    # Storage nil on opted-out fiber
    fiber_nil_storage = ::Fiber.new(storage: nil) do
      ::Fiber.current.storage
    end.resume
    assert_nil(fiber_nil_storage)
  end

  test "Fact 3: per-key union restore restores prior storage exactly" do
    Dexpace::DiagnosticContext.preserve do
      ::Fiber[:key_a] = "alpha"
      prior = ::Fiber.current.storage || {}

      # Snapshot installed
      snapshot = { key_a: "overwritten", key_b: "beta" }
      snapshot.each { |k, v| ::Fiber[k] = v }
      assert_equal("overwritten", ::Fiber[:key_a])
      assert_equal("beta", ::Fiber[:key_b])

      # Union restore
      (prior.keys | snapshot.keys).each { |k| ::Fiber[k] = prior[k] }
      restored = ::Fiber.current.storage || {}
      assert_equal("alpha", restored[:key_a])
      refute(restored.key?(:key_b))
    end
  end

  test "Fact 6: URI::RFC3986_PARSER raises on component assignment to opaque URIs" do
    parser = ::URI::RFC3986_PARSER
    opaque = parser.parse("mailto:support@example.com")
    assert_raises(::URI::InvalidURIError) { opaque.userinfo = "***:***" }
    assert_raises(::URI::InvalidURIError) { opaque.query = "a=1" }
  end

  test "Fact 9: multibyte byteslice can produce invalid string and scrub rescues valid encoding" do
    multibyte = "é" * 5000
    sliced = multibyte.byteslice(0, 8191)
    refute(sliced.valid_encoding?)
    scrubbed = sliced.scrub("")
    assert(scrubbed.valid_encoding?)
    assert_operator(scrubbed.bytesize, :<=, 8191)
  end

  test "RecordingSink satisfies _Sink duck type and captures entries" do
    sink = Dexpace::RecordingSink.new
    assert(sink.debug?)
    assert(sink.info?)
    assert(sink.warn?)
    assert(sink.error?)

    sink.info("hello")
    sink.warn { "computed warning" }
    assert_equal(2, sink.entries.size)
    assert_equal(:info, sink.entries[0].severity)
    assert_equal("hello", sink.entries[0].message)
    assert_equal(:warn, sink.entries[1].severity)
    assert_equal("computed warning", sink.entries[1].payload)
  end
end
```

- [ ] **Step 3: Run test to confirm it fails before support doubles are written**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/logging_matrix_facts_test.rb`
Expected: fails with `LoadError` loading `recording_sink`.

- [ ] **Step 4: Write test support doubles**

Write `gems/dexpace-core/test/support/recording_sink.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# 5a's precedent decides the namespace: its three doubles are Dexpace::FakeClock,
# Dexpace::FakeSource and Dexpace::ProbeScheduler -- flat under Dexpace, not under the
# subsystem namespace they exercise -- and 5c's six recording doubles follow it. Putting it
# at Dexpace::Instrumentation::RecordingSink instead would drop a test-only constant into
# the shipping namespace the surface manifest walks, and would make 5b inconsistent with
# its OWN second double, Dexpace::DiagnosticContext, in the same directory.
module Dexpace
  class RecordingSink
    Entry = ::Data.define(:severity, :message, :payload)

    attr_accessor :debug_enabled, :info_enabled, :warn_enabled, :error_enabled
    attr_reader :entries

    def initialize(debug_enabled: true, info_enabled: true, warn_enabled: true, error_enabled: true)
      @debug_enabled = debug_enabled
      @info_enabled = info_enabled
      @warn_enabled = warn_enabled
      @error_enabled = error_enabled
      @entries = []
      @mutex = ::Thread::Mutex.new
    end

    def debug(msg = nil, &block)
      record(:debug, msg, &block)
    end

    def info(msg = nil, &block)
      record(:info, msg, &block)
    end

    def warn(msg = nil, &block)
      record(:warn, msg, &block)
    end

    def error(msg = nil, &block)
      record(:error, msg, &block)
    end

    def debug? = @debug_enabled
    def info? = @info_enabled
    def warn? = @warn_enabled
    def error? = @error_enabled

    def clear
      @mutex.synchronize { @entries.clear }
    end

    private

    def record(severity, msg)
      payload = block_given? ? yield : msg
      @mutex.synchronize do
        @entries << Entry.new(severity: severity, message: msg, payload: payload).freeze
      end
      nil
    end
  end
end
```

Write `gems/dexpace-core/test/support/diagnostic_context.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module DiagnosticContext
    # Restores fiber storage after block execution to guarantee test isolation
    def self.preserve
      prior = (::Fiber.current.storage || {}).dup
      yield
    ensure
      current = ::Fiber.current.storage || {}
      (prior.keys | current.keys).each do |k|
        ::Fiber[k] = prior[k]
      end
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/logging_matrix_facts_test.rb`
Expected: 6 runs, 0 failures, 0 errors, 0 skips.

---
## Task 2: `Dexpace::Instrumentation::Severity`

**Requirement IDs:** `OBS-2`.
**Design:** "Dexpace::Instrumentation::Severity — OBS-2"; `P5-16`, `P5-17`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/severity.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/severity.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/severity_test.rb`

**Interfaces:**
- Consumes: `Dexpace::InvalidArgumentError`.
- Produces: `Dexpace::Instrumentation::Severity` closed set (`ERROR`, `WARNING`, `INFO`, `VERBOSE`, `ALL`) and `.of` factory.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/severity_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/instrumentation/severity"

# Exercises: OBS-2
class SeverityTest < DexpaceTestCase
  test "defines exactly four severity levels mapped to backend sink methods and predicates" do
    assert_equal(:error, Dexpace::Instrumentation::Severity::ERROR.name)
    assert_equal(:error, Dexpace::Instrumentation::Severity::ERROR.sink_method)
    assert_equal(:error?, Dexpace::Instrumentation::Severity::ERROR.sink_predicate)

    assert_equal(:warning, Dexpace::Instrumentation::Severity::WARNING.name)
    assert_equal(:warn, Dexpace::Instrumentation::Severity::WARNING.sink_method)
    assert_equal(:warn?, Dexpace::Instrumentation::Severity::WARNING.sink_predicate)

    assert_equal(:info, Dexpace::Instrumentation::Severity::INFO.name)
    assert_equal(:info, Dexpace::Instrumentation::Severity::INFO.sink_method)
    assert_equal(:info?, Dexpace::Instrumentation::Severity::INFO.sink_predicate)

    assert_equal(:verbose, Dexpace::Instrumentation::Severity::VERBOSE.name)
    assert_equal(:debug, Dexpace::Instrumentation::Severity::VERBOSE.sink_method)
    assert_equal(:debug?, Dexpace::Instrumentation::Severity::VERBOSE.sink_predicate)

    assert_equal(
      [
        Dexpace::Instrumentation::Severity::ERROR,
        Dexpace::Instrumentation::Severity::WARNING,
        Dexpace::Instrumentation::Severity::INFO,
        Dexpace::Instrumentation::Severity::VERBOSE,
      ],
      Dexpace::Instrumentation::Severity::ALL
    )
    assert(Dexpace::Instrumentation::Severity::ALL.frozen?)
  end

  test "Severity.of resolves valid symbols and raises InvalidArgumentError on invalid input" do
    assert_same(Dexpace::Instrumentation::Severity::INFO, Dexpace::Instrumentation::Severity.of(:info))
    assert_same(Dexpace::Instrumentation::Severity::ERROR, Dexpace::Instrumentation::Severity.of(:error))
    assert_same(Dexpace::Instrumentation::Severity::WARNING, Dexpace::Instrumentation::Severity.of(:warning))
    assert_same(Dexpace::Instrumentation::Severity::VERBOSE, Dexpace::Instrumentation::Severity.of(:verbose))

    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Instrumentation::Severity.of(:unknown) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Instrumentation::Severity.of("info") }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Instrumentation::Severity.of(nil) }
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/severity_test.rb`
Expected: fails with `LoadError` loading `severity.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/severity.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error/invalid_argument_error"

module Dexpace
  module Instrumentation
    # OBS-2: Exactly four severity levels mapped onto backend's ERROR, WARN, INFO, and most-verbose/DEBUG levels.
    class Severity < ::Data.define(:name, :sink_method, :sink_predicate)
      private_class_method :new

      ERROR   = new(:error, :error, :error?).freeze
      WARNING = new(:warning, :warn, :warn?).freeze
      INFO    = new(:info, :info, :info?).freeze
      VERBOSE = new(:verbose, :debug, :debug?).freeze

      ALL = [ERROR, WARNING, INFO, VERBOSE].freeze

      LOOKUP = ALL.to_h { |s| [s.name, s] }.freeze
      private_constant :LOOKUP

      def self.of(name)
        LOOKUP.fetch(name) do
          raise InvalidArgumentError, "unrecognized severity #{name.inspect}; must be one of :error, :warning, :info, :verbose"
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write RBS signature**

Write `gems/dexpace-core/sig/dexpace/instrumentation/severity.rbs`:
```rbs
module Dexpace
  module Instrumentation
    class Severity < Data
      ERROR: Severity
      WARNING: Severity
      INFO: Severity
      VERBOSE: Severity
      ALL: Array[Severity]

      def name: () -> Symbol
      def sink_method: () -> Symbol
      def sink_predicate: () -> Symbol

      def self.of: (Symbol name) -> Severity
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/severity_test.rb`
Expected: 2 runs, 0 failures, 0 errors, 0 skips.

---
## Task 3: `Dexpace::Instrumentation::Keys` and `::Events`

**Requirement IDs:** `OBS-4`, `OBS-20`, `OBS-39`.
**Design:** "Dexpace::Instrumentation::Keys and ::Events — OBS-39, OBS-4, OBS-20"; `P5-16`, `R11`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/keys.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/keys.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/keys_test.rb`

**Interfaces:**
- Consumes: None (pure string constants).
- Produces: `Dexpace::Instrumentation::Keys` (15 frozen strings) and `Dexpace::Instrumentation::Events` (8 frozen strings).

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/keys_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/instrumentation/keys"

# Exercises: OBS-4, OBS-20, OBS-39
class KeysAndEventsTest < DexpaceTestCase
  test "Keys module defines all fifteen frozen string constants" do
    k = Dexpace::Instrumentation::Keys
    assert_equal("event", k::EVENT)
    assert_equal("http.request.method", k::HTTP_REQUEST_METHOD)
    assert_equal("url.full", k::URL_FULL)
    assert_equal("http.response.status_code", k::HTTP_RESPONSE_STATUS_CODE)
    assert_equal("http.response.duration_ms", k::HTTP_RESPONSE_DURATION_MS)
    assert_equal("http.request.body.size", k::HTTP_REQUEST_BODY_SIZE)
    assert_equal("http.response.body.size", k::HTTP_RESPONSE_BODY_SIZE)
    assert_equal("http.request.body.preview", k::HTTP_REQUEST_BODY_PREVIEW)
    assert_equal("http.response.body.preview", k::HTTP_RESPONSE_BODY_PREVIEW)
    assert_equal("http.request.header.", k::HTTP_REQUEST_HEADER_PREFIX)
    assert_equal("http.response.header.", k::HTTP_RESPONSE_HEADER_PREFIX)
    assert_equal("error.type", k::ERROR_TYPE)
    # OBS-39's "the throwable cause attached" -- the fifteenth key, added at reconciliation.
    # Event#emit wrote it as a bare "cause" literal, which is an emitted field key outside the
    # vocabulary OBS-39 requires to be stable and outside §8.1's surface-snapshot coverage.
    assert_equal("cause", k::CAUSE)
    assert_equal("http.client.request.count", k::INSTRUMENT_REQUEST_COUNT)
    assert_equal("http.client.request.duration", k::INSTRUMENT_REQUEST_DURATION)

    k.constants.each do |const_name|
      val = k.const_get(const_name)
      assert(val.frozen?, "#{const_name} must be frozen")
      assert_kind_of(String, val)
    end
  end

  test "Events module defines all eight frozen string constants" do
    e = Dexpace::Instrumentation::Events
    assert_equal("http.request", e::HTTP_REQUEST)
    assert_equal("http.response", e::HTTP_RESPONSE)
    assert_equal("http.instrumentation.", e::INSTRUMENTATION_PREFIX)
    assert_equal("http.instrumentation.log", e::INSTRUMENTATION_LOG)
    assert_equal("http.instrumentation.close", e::INSTRUMENTATION_CLOSE)
    assert_equal("http.instrumentation.hook", e::INSTRUMENTATION_HOOK)
    assert_equal("http.instrumentation.shutdown", e::INSTRUMENTATION_SHUTDOWN)
    assert_equal("http.instrumentation.config", e::INSTRUMENTATION_CONFIG)

    e.constants.each do |const_name|
      val = e.const_get(const_name)
      assert(val.frozen?, "#{const_name} must be frozen")
      assert_kind_of(String, val)
      if const_name.to_s.start_with?("INSTRUMENTATION_") && const_name != :INSTRUMENTATION_PREFIX
        assert_operator(val, :start_with?, e::INSTRUMENTATION_PREFIX)
      end
    end
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/keys_test.rb`
Expected: fails with `LoadError` loading `keys.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/keys.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-39: Stable vocabulary of emitted field keys.
    module Keys
      EVENT                       = "event"
      HTTP_REQUEST_METHOD         = "http.request.method"
      URL_FULL                    = "url.full"
      HTTP_RESPONSE_STATUS_CODE   = "http.response.status_code"
      HTTP_RESPONSE_DURATION_MS   = "http.response.duration_ms"
      HTTP_REQUEST_BODY_SIZE      = "http.request.body.size"
      HTTP_RESPONSE_BODY_SIZE     = "http.response.body.size"
      HTTP_REQUEST_BODY_PREVIEW   = "http.request.body.preview"
      HTTP_RESPONSE_BODY_PREVIEW  = "http.response.body.preview"
      HTTP_REQUEST_HEADER_PREFIX  = "http.request.header."
      HTTP_RESPONSE_HEADER_PREFIX = "http.response.header."
      ERROR_TYPE                  = "error.type"
      # OBS-39: "a failure emits an 'http.response' event with 'error.type' and the throwable
      # cause attached". Event#emit is the only writer.
      CAUSE                       = "cause"

      # R11, OBS-34: OTel metric instrument names owned by 5b.
      INSTRUMENT_REQUEST_COUNT    = "http.client.request.count"
      INSTRUMENT_REQUEST_DURATION = "http.client.request.duration"
    end

    # OBS-39, OBS-20: Stable vocabulary of emitted structured event names.
    module Events
      HTTP_REQUEST             = "http.request"
      HTTP_RESPONSE            = "http.response"

      # OBS-20: Diagnostic event namespace and failure containment routes.
      INSTRUMENTATION_PREFIX   = "http.instrumentation."
      INSTRUMENTATION_LOG      = "http.instrumentation.log"
      INSTRUMENTATION_CLOSE    = "http.instrumentation.close"
      INSTRUMENTATION_HOOK     = "http.instrumentation.hook"
      INSTRUMENTATION_SHUTDOWN = "http.instrumentation.shutdown"
      INSTRUMENTATION_CONFIG   = "http.instrumentation.config"
    end
  end
end
```

- [ ] **Step 4: Write RBS signature**

Write `gems/dexpace-core/sig/dexpace/instrumentation/keys.rbs`:
```rbs
module Dexpace
  module Instrumentation
    module Keys
      EVENT: String
      HTTP_REQUEST_METHOD: String
      URL_FULL: String
      HTTP_RESPONSE_STATUS_CODE: String
      HTTP_RESPONSE_DURATION_MS: String
      HTTP_REQUEST_BODY_SIZE: String
      HTTP_RESPONSE_BODY_SIZE: String
      HTTP_REQUEST_BODY_PREVIEW: String
      HTTP_RESPONSE_BODY_PREVIEW: String
      HTTP_REQUEST_HEADER_PREFIX: String
      HTTP_RESPONSE_HEADER_PREFIX: String
      ERROR_TYPE: String
      CAUSE: String
      INSTRUMENT_REQUEST_COUNT: String
      INSTRUMENT_REQUEST_DURATION: String
    end

    module Events
      HTTP_REQUEST: String
      HTTP_RESPONSE: String
      INSTRUMENTATION_PREFIX: String
      INSTRUMENTATION_LOG: String
      INSTRUMENTATION_CLOSE: String
      INSTRUMENTATION_HOOK: String
      INSTRUMENTATION_SHUTDOWN: String
      INSTRUMENTATION_CONFIG: String
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/keys_test.rb`
Expected: 2 runs, 0 failures, 0 errors, 0 skips.

---
## Task 4: `Dexpace::Instrumentation::NULL_SINK` and RBS `_Sink` Interface

**Requirement IDs:** `OBS-1`, `OBS-2`.
**Design:** "Dexpace::Instrumentation::NULL_SINK — OBS-1's default output"; `P5-16`, `P5-19`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/null_sink.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/null_sink.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/null_sink_test.rb`

**Interfaces:**
- Consumes: None.
- Produces: `Dexpace::Instrumentation::NULL_SINK` frozen singleton and RBS `interface _Sink`.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/null_sink_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/instrumentation/null_sink"

# Exercises: OBS-1, OBS-2
class NullSinkTest < DexpaceTestCase
  test "NULL_SINK implements the _Sink duck type returning nil and false" do
    sink = Dexpace::Instrumentation::NULL_SINK
    assert(sink.frozen?)

    # Predicates all return false
    refute(sink.debug?)
    refute(sink.info?)
    refute(sink.warn?)
    refute(sink.error?)

    # Methods return nil and never evaluate blocks
    block_evaluated = false
    assert_nil(sink.debug("msg"))
    assert_nil(sink.debug { block_evaluated = true; "block" })
    refute(block_evaluated)

    assert_nil(sink.info("msg"))
    assert_nil(sink.info { block_evaluated = true; "block" })
    refute(block_evaluated)

    assert_nil(sink.warn("msg"))
    assert_nil(sink.warn { block_evaluated = true; "block" })
    refute(block_evaluated)

    assert_nil(sink.error("msg"))
    assert_nil(sink.error { block_evaluated = true; "block" })
    refute(block_evaluated)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/null_sink_test.rb`
Expected: fails with `LoadError` loading `null_sink.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/null_sink.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-1: Frozen singleton null sink satisfying the duck type without requiring logger.
    class NullSink
      def debug(_msg = nil) = nil
      def info(_msg = nil) = nil
      def warn(_msg = nil) = nil
      def error(_msg = nil) = nil

      def debug? = false
      def info? = false
      def warn? = false
      def error? = false
    end
    private_constant :NullSink

    NULL_SINK = NullSink.new.freeze
  end
end
```

- [ ] **Step 4: Write RBS signature**

Write `gems/dexpace-core/sig/dexpace/instrumentation/null_sink.rbs`:
```rbs
module Dexpace
  interface _Sink
    def debug: (?untyped msg) ?{ () -> untyped } -> void
    def info:  (?untyped msg) ?{ () -> untyped } -> void
    def warn:  (?untyped msg) ?{ () -> untyped } -> void
    def error: (?untyped msg) ?{ () -> untyped } -> void
    def debug?: () -> bool
    def info?:  () -> bool
    def warn?:  () -> bool
    def error?: () -> bool
  end

  module Instrumentation
    NULL_SINK: _Sink
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/null_sink_test.rb`
Expected: 1 run, 0 failures, 0 errors, 0 skips.

---
## Task 5: `Dexpace::Instrumentation::Render`

**Requirement IDs:** `OBS-6`, `OBS-7`.
**Design:** "Rendering is total (OBS-6), and it lives in Instrumentation::Render, private_constant"; `P5-29`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/render.rb`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/render_test.rb`

**Interfaces:**
- Consumes: Ruby standard library.
- Produces: `Dexpace::Instrumentation::Render` (`private_constant`), providing `.render(value)`.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/render_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/instrumentation/render"

# Exercises: OBS-6, OBS-7
class RenderTest < DexpaceTestCase
  Render = Dexpace::Instrumentation.const_get(:Render)

  test "renders nil as string null" do
    assert_equal("null", Render.render(nil))
  end

  test "preserves primitive types" do
    assert_equal(42, Render.render(42))
    assert_equal(3.14, Render.render(3.14))
    assert_equal(true, Render.render(true))
    assert_equal(false, Render.render(false))
  end

  test "renders standard exception as SimpleClassName: message" do
    err = ::ArgumentError.new("invalid value")
    assert_equal("ArgumentError: invalid value", Render.render(err))
  end

  test "renders anonymous exception with nil class name safely" do
    anon_class = ::Class.new(::StandardError)
    err = anon_class.new("failure")
    assert_equal("Class: failure", Render.render(err))
  end

  test "substitutes unrenderable diagnostic placeholder when exception message or to_s raises" do
    bad_err = ::Class.new(::StandardError) do
      def message = raise "boom in message"
      def to_s = raise "boom in to_s"
    end.new
    rendered = Render.render(bad_err)
    assert_match(/\A\[unrenderable [^\]]+\]\z/, rendered)
  end

  test "substitutes unrenderable diagnostic placeholder when object to_s raises" do
    bad_obj = ::Object.new
    def bad_obj.to_s = raise "boom"
    rendered = Render.render(bad_obj)
    assert_match(/\A\[unrenderable [^\]]+\]\z/, rendered)
  end

  test "renders collections in bracketed textual form" do
    assert_equal("[1, 2, 3]", Render.render([1, 2, 3]))

    # Hash#inspect's spacing changed at Ruby 3.4.0 ({"a"=>1} on 3.2/3.3, {"a" => 1} from 3.4),
    # and 3.2 is the floor of this matrix. OBS-6 asks for "a bracketed textual form" and fixes
    # no spelling, so the assertion is on the shape rather than on one interpreter's rendering.
    hash_rendered = Render.render({ "a" => 1 })
    assert_operator(hash_rendered, :start_with?, "{")
    assert_operator(hash_rendered, :end_with?, "}")
    assert_includes(hash_rendered, "\"a\"")
    assert_includes(hash_rendered, "1")
  end

  test "truncates strings exceeding 8 KiB on byte boundaries and appends truncation marker" do
    multibyte_prefix = "é" * 5000 # 10,000 bytes
    rendered = Render.render(multibyte_prefix)
    assert(rendered.valid_encoding?)
    assert_operator(rendered.bytesize, :<=, 8192 + Render::TRUNCATION_MARKER.bytesize)
    assert_operator(rendered, :end_with?, Render::TRUNCATION_MARKER)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/render_test.rb`
Expected: fails with `LoadError` loading `render.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/render.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-6, OBS-7: Total rendering and 8 KiB byte-sliced truncation.
    module Render
      MAX_VALUE_BYTES   = 8 * 1024
      TRUNCATION_MARKER = "…[truncated]"

      def self.render(value)
        return "null" if value.nil?
        return value if value.is_a?(::Integer) || value.is_a?(::Float) || value.is_a?(::TrueClass) || value.is_a?(::FalseClass)

        rendered_str =
          if value.is_a?(::Exception)
            render_exception(value)
          elsif value.is_a?(::Array) || value.is_a?(::Hash)
            render_collection(value)
          else
            render_object(value)
          end

        truncate(rendered_str)
      end

      def self.render_exception(err)
        class_name = err.class.name&.split("::")&.last || "Class"
        msg = err.message
        "#{class_name}: #{msg}"
      rescue ::StandardError
        unrenderable(err)
      end
      private_class_method :render_exception

      def self.render_collection(col)
        col.inspect
      rescue ::StandardError
        unrenderable(col)
      end
      private_class_method :render_collection

      def self.render_object(obj)
        obj.to_s
      rescue ::StandardError
        unrenderable(obj)
      end
      private_class_method :render_object

      def self.unrenderable(obj)
        name = obj.class.name&.split("::")&.last || "Object"
        "[unrenderable #{name}]"
      end
      private_class_method :unrenderable

      def self.truncate(str)
        return str if str.bytesize <= MAX_VALUE_BYTES

        str.byteslice(0, MAX_VALUE_BYTES).scrub("") + TRUNCATION_MARKER
      end
      private_class_method :truncate
    end
    private_constant :Render
  end
end
```

- [ ] **Step 4: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/render_test.rb`
Expected: 8 runs, 0 failures, 0 errors, 0 skips.

---
## Task 6: `Dexpace::Instrumentation::Diagnostics` and `_DiagnosticSnapshot`

**Requirement IDs:** `OBS-10`, `OBS-24`.
**Design:** "Dexpace::Instrumentation::Diagnostics — OBS-10, OBS-24"; `P5-16`, `P5-17`, `P5-22`, `P5-23`, `P5-24`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/diagnostics.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/diagnostics.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/diagnostics_test.rb`

**Interfaces:**
- Consumes: `Fiber.current.storage`, `Fiber[]=`.
- Produces: `Dexpace::Instrumentation::Diagnostics` with `.capture`, `.with`, `.folded`, and RBS `interface _DiagnosticSnapshot`.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/diagnostics_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/diagnostic_context"
require_relative "../../../lib/dexpace/instrumentation/diagnostics"

# Exercises: OBS-10, OBS-24
class DiagnosticsTest < DexpaceTestCase
  Diag = Dexpace::Instrumentation::Diagnostics

  # See logging_matrix_facts_test.rb for why this harness exists rather than a third support double.
  module WarningCapture
    def warn(message, category: nil)
      sink = ::Thread.current[:dexpace_warning_sink]
      return super if sink.nil?

      sink << [message, category]
      nil
    end
  end
  ::Warning.singleton_class.prepend(WarningCapture)

  def capture_warnings
    sink = []
    ::Thread.current[:dexpace_warning_sink] = sink
    yield
    sink
  ensure
    ::Thread.current[:dexpace_warning_sink] = nil
  end

  test "defines TRACE_ID and SPAN_ID as Symbols and DEFAULT_KEYS as frozen array" do
    assert_equal(:"trace.id", Diag::TRACE_ID)
    assert_equal(:"span.id", Diag::SPAN_ID)
    assert_equal([Diag::TRACE_ID, Diag::SPAN_ID], Diag::DEFAULT_KEYS)
    assert(Diag::DEFAULT_KEYS.frozen?)
  end

  test "OBS-24: capture returns a shallow-frozen Hash snapshot of fiber storage" do
    Dexpace::DiagnosticContext.preserve do
      ::Fiber[:"trace.id"] = "t1"
      snapshot = Diag.capture

      # Asserted per key, not as whole-map equality: testing/4ef070df requires every test to
      # run alone in any order, and `rake test` shares one process and one main thread, so a
      # whole-map assertion is an assertion about every OTHER suite's fiber-storage hygiene.
      assert_equal("t1", snapshot[:"trace.id"])
      assert(snapshot.frozen?)

      # Verified fact 2: Fiber.current.storage already returns a fresh unfrozen Hash on every
      # call, so capture is one read plus one freeze with nothing to duplicate.
      refute_same(snapshot, Diag.capture)
      refute(::Fiber.current.storage.frozen?)
    end
  end

  test "with installs snapshot and restores prior storage including on exception" do
    Dexpace::DiagnosticContext.preserve do
      ::Fiber[:prior_key] = "prior_val"
      snapshot = { :"trace.id" => "t2", new_key: "val2" }

      # Successful block execution
      inside_ran = false
      Diag.with(snapshot) do
        inside_ran = true
        assert_equal("t2", ::Fiber[:"trace.id"])
        assert_equal("val2", ::Fiber[:new_key])
      end
      assert(inside_ran)
      assert_equal("prior_val", ::Fiber[:prior_key])
      assert_nil(::Fiber[:"trace.id"])
      assert_nil(::Fiber[:new_key])

      # Exception raised in block
      assert_raises(::RuntimeError) do
        Diag.with(snapshot) do
          assert_equal("t2", ::Fiber[:"trace.id"])
          raise "error inside with"
        end
      end
      assert_equal("prior_val", ::Fiber[:prior_key])
      assert_nil(::Fiber[:"trace.id"])
    end
  end

  test "OBS-24: with bridges a real thread boundary and restores B's OWN prior context" do
    Dexpace::DiagnosticContext.preserve do
      ::Fiber[:"trace.id"] = "parent_trace"
      snapshot = Diag.capture

      # A new Thread INHERITS a copy of the parent's fiber storage, so thread B's "original
      # context" already contains trace.id => "parent_trace". A test that asserts B's
      # trace.id is nil afterwards is asserting that the bridge CORRUPTED B's context.
      # This is the trap the design names; the assertion is `== prior`, not `nil`.
      thread_result = ::Thread.new do
        ::Fiber[:thread_local] = "orig"
        ::Fiber[:"trace.id"] = "b_own_trace"
        b_prior = ::Fiber.current.storage.dup

        inside_trace = nil
        inside_span = nil
        Diag.with(snapshot.merge(:"span.id" => "s1")) do
          inside_trace = ::Fiber[:"trace.id"]
          inside_span = ::Fiber[:"span.id"]
        end

        [inside_trace, inside_span, b_prior, ::Fiber.current.storage]
      end.value

      # A's captured keys are visible inside the block ...
      assert_equal("parent_trace", thread_result[0])
      assert_equal("s1", thread_result[1])
      # ... and B's own context is restored byte for byte afterwards, including the key the
      # snapshot introduced being gone again (verified fact 3's per-key union restore).
      assert_equal(thread_result[2], thread_result[3])
      assert_equal("b_own_trace", thread_result[3][:"trace.id"])
      assert_equal("orig", thread_result[3][:thread_local])
      refute(thread_result[3].key?(:"span.id"))
    end
  end

  test "folded in allow-listed mode folds only present allow-listed keys converted to string via Symbol#name" do
    Dexpace::DiagnosticContext.preserve do
      ::Fiber[:"trace.id"] = "1111"
      ::Fiber[:other_key] = "other"

      folded = Diag.folded(Diag::DEFAULT_KEYS)
      assert_equal({ "trace.id" => "1111" }, folded)
      assert_same(Diag::TRACE_ID.name, folded.keys.first)
    end
  end

  test "OBS-10: folded in unfiltered mode folds every present key and skips nil values" do
    Dexpace::DiagnosticContext.preserve do
      # R12: this is the ONLY Fiber#storage= call anywhere in the repository after 5b, and it
      # is here because a nil-VALUED key is the input OBS-10's "Keys with null values MUST be
      # skipped" is about, and Fiber[:a] = nil DELETES rather than storing nil — so this
      # setter is the only constructor of the state under test. The ban is on lib/, not on a
      # test deliberately exercising a host-produced state.
      #
      # The call warns (:experimental) on every Ruby, and DexpaceTestCase turns a warning into
      # a failure, so it runs inside the capture harness. If a second Fiber#storage= ever
      # appears outside a harness, FatalWarnings is what catches it — which is the point.
      warnings = capture_warnings { ::Fiber.current.storage = { a: nil, b: "beta" } }
      assert_equal(1, warnings.size)

      folded = Diag.folded(nil)
      assert_equal({ "b" => "beta" }, folded)
      refute(folded.key?("a"))
    end
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/diagnostics_test.rb`
Expected: fails with `LoadError` loading `diagnostics.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/diagnostics.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-10, OBS-24: Diagnostic context carrier, snapshot capture, union restore, and folding.
    module Diagnostics
      TRACE_ID     = :"trace.id"
      SPAN_ID      = :"span.id"
      DEFAULT_KEYS = [TRACE_ID, SPAN_ID].freeze

      def self.capture
        (::Fiber.current.storage || {}).freeze
      end

      def self.with(snapshot)
        prior = ::Fiber.current.storage || {}
        snapshot.each { |k, v| ::Fiber[k] = v }
        yield
      ensure
        (prior.keys | snapshot.keys).each { |k| ::Fiber[k] = prior[k] }
      end

      def self.folded(allow_list)
        folded_map = {}
        if allow_list
          allow_list.each do |k|
            val = ::Fiber[k]
            next if val.nil?

            key_str = k.is_a?(::Symbol) ? k.name : k.to_s
            folded_map[key_str] = val
          end
        else
          storage = ::Fiber.current.storage || {}
          storage.each do |k, v|
            next if v.nil?

            key_str = k.is_a?(::Symbol) ? k.name : k.to_s
            folded_map[key_str] = v
          end
        end
        folded_map
      end
    end
  end
end
```

- [ ] **Step 4: Write RBS signature**

Write `gems/dexpace-core/sig/dexpace/instrumentation/diagnostics.rbs`:
```rbs
module Dexpace
  interface _DiagnosticSnapshot
    def each: () { ([Symbol, untyped]) -> void } -> void
    def keys: () -> Array[Symbol]
    def []: (Symbol) -> untyped
  end

  module Instrumentation
    module Diagnostics
      TRACE_ID: Symbol
      SPAN_ID: Symbol
      DEFAULT_KEYS: Array[Symbol]

      def self.capture: () -> Hash[Symbol, untyped]
      def self.with: [T] (_DiagnosticSnapshot snapshot) { () -> T } -> T
      def self.folded: (Array[Symbol]? allow_list) -> Hash[String, untyped]
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/diagnostics_test.rb`
Expected: 6 runs, 0 failures, 0 errors, 0 skips.

---
## Task 7: `Dexpace::Instrumentation::RedactionPolicy`

**Requirement IDs:** `OBS-12`, `OBS-17`, `OBS-18`, `XCUT-19`.
**Design:** "Dexpace::Instrumentation::RedactionPolicy — OBS-12, OBS-17, OBS-18, XCUT-19"; `P5-16`, `P5-17`, `P5-30`, `P5-35`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/redaction_policy.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/redaction_policy.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/redaction_policy_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `require "set"`.
- Produces: `Dexpace::Instrumentation::RedactionPolicy` immutable domain model and `DEFAULT` constant.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/redaction_policy_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/instrumentation/redaction_policy"

# Exercises: OBS-12, OBS-17, OBS-18, XCUT-19
class RedactionPolicyTest < DexpaceTestCase
  Policy = Dexpace::Instrumentation::RedactionPolicy

  test "RedactionPolicy::DEFAULT has exact spec-mandated default sets and omit flag false" do
    default_policy = Policy::DEFAULT
    assert(default_policy.frozen?)

    # OBS-12: exactly {api-version}
    assert_equal(::Set["api-version"], default_policy.query_allow_list)

    # OBS-17: at minimum Location and Content-Location
    assert_equal(::Set["location", "content-location"], default_policy.url_header_names)

    # OBS-18: omit_disallowed_headers defaults to false (P5-35)
    assert_equal(false, default_policy.omit_disallowed_headers)

    # OBS-18, P5-30: 26 diagnostic header names, no credentials, no challenge headers
    expected_headers = ::Set[
      "accept", "accept-encoding", "cache-control", "connection", "content-encoding",
      "content-length", "content-location", "content-type", "date", "etag", "expires",
      "if-match", "if-modified-since", "if-none-match", "if-unmodified-since",
      "last-modified", "location", "retry-after", "server", "traceparent", "tracestate",
      "user-agent", "vary", "via", "x-correlation-id", "x-request-id"
    ]
    assert_equal(expected_headers, default_policy.header_allow_list)
    refute(default_policy.header_allow_list.include?("authorization"))
    refute(default_policy.header_allow_list.include?("proxy-authorization"))
    refute(default_policy.header_allow_list.include?("www-authenticate"))
    refute(default_policy.header_allow_list.include?("proxy-authenticate"))
  end

  test "RedactionPolicy.build normalizes collections to downcased frozen sets" do
    custom = Policy.build(
      query_allow_list: ["Api-Version", "Page"],
      header_allow_list: ["Content-Type", "Accept"],
      url_header_names: ["Location"],
      omit_disallowed_headers: true
    )
    assert_equal(::Set["api-version", "page"], custom.query_allow_list)
    assert_equal(::Set["content-type", "accept"], custom.header_allow_list)
    assert_equal(::Set["location"], custom.url_header_names)
    assert_equal(true, custom.omit_disallowed_headers)
  end

  test "RedactionPolicy supports with derivation" do
    default_policy = Policy::DEFAULT
    derived = default_policy.with(omit_disallowed_headers: true)
    assert_equal(true, derived.omit_disallowed_headers)
    assert_equal(default_policy.query_allow_list, derived.query_allow_list)
    assert_equal(default_policy.header_allow_list, derived.header_allow_list)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/redaction_policy_test.rb`
Expected: fails with `LoadError` loading `redaction_policy.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/redaction_policy.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "set"
require_relative "../model"

module Dexpace
  module Instrumentation
    # OBS-12, OBS-17, OBS-18: Configuration policy for URL and header sanitization.
    class RedactionPolicy < ::Data.define(:query_allow_list, :header_allow_list, :url_header_names, :omit_disallowed_headers)
      include Model
      private_class_method :new

      DEFAULT_QUERY_ALLOW_LIST = ::Set["api-version"].freeze
      DEFAULT_URL_HEADER_NAMES = ::Set["location", "content-location"].freeze
      DEFAULT_HEADER_ALLOW_LIST = ::Set[
        "accept", "accept-encoding", "cache-control", "connection", "content-encoding",
        "content-length", "content-location", "content-type", "date", "etag", "expires",
        "if-match", "if-modified-since", "if-none-match", "if-unmodified-since",
        "last-modified", "location", "retry-after", "server", "traceparent", "tracestate",
        "user-agent", "vary", "via", "x-correlation-id", "x-request-id"
      ].freeze

      def self.build(
        query_allow_list: DEFAULT_QUERY_ALLOW_LIST,
        header_allow_list: DEFAULT_HEADER_ALLOW_LIST,
        url_header_names: DEFAULT_URL_HEADER_NAMES,
        omit_disallowed_headers: false
      )
        q_set = query_allow_list.map { |item| item.to_s.downcase }.to_set.freeze
        h_set = header_allow_list.map { |item| item.to_s.downcase }.to_set.freeze
        u_set = url_header_names.map { |item| item.to_s.downcase }.to_set.freeze
        omit = omit_disallowed_headers ? true : false

        new(
          query_allow_list: q_set,
          header_allow_list: h_set,
          url_header_names: u_set,
          omit_disallowed_headers: omit
        ).freeze
      end

      DEFAULT = build.freeze

      def with(**changes)
        current = {
          query_allow_list: query_allow_list,
          header_allow_list: header_allow_list,
          url_header_names: url_header_names,
          omit_disallowed_headers: omit_disallowed_headers,
        }
        self.class.build(**current.merge(changes))
      end
    end
  end
end
```

- [ ] **Step 4: Write RBS signature**

Write `gems/dexpace-core/sig/dexpace/instrumentation/redaction_policy.rbs`:
```rbs
module Dexpace
  module Instrumentation
    class RedactionPolicy < Data
      include Model

      DEFAULT: RedactionPolicy
      DEFAULT_QUERY_ALLOW_LIST: Set[String]
      DEFAULT_HEADER_ALLOW_LIST: Set[String]
      DEFAULT_URL_HEADER_NAMES: Set[String]

      def query_allow_list: () -> Set[String]
      def header_allow_list: () -> Set[String]
      def url_header_names: () -> Set[String]
      def omit_disallowed_headers: () -> bool

      def self.build: (
        ?query_allow_list: Enumerable[String],
        ?header_allow_list: Enumerable[String],
        ?url_header_names: Enumerable[String],
        ?omit_disallowed_headers: bool
      ) -> RedactionPolicy

      def with: (
        ?query_allow_list: Enumerable[String],
        ?header_allow_list: Enumerable[String],
        ?url_header_names: Enumerable[String],
        ?omit_disallowed_headers: bool
      ) -> RedactionPolicy
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/redaction_policy_test.rb`
Expected: 3 runs, 0 failures, 0 errors, 0 skips.

---
## Task 8: `Dexpace::Instrumentation::Redactor`

**Requirement IDs:** `OBS-11`, `OBS-12`, `OBS-13`, `OBS-14`, `OBS-15`, `OBS-16`, `OBS-17`, `OBS-18`, `XCUT-19`, `XCUT-20`.
**Design:** "Dexpace::Instrumentation::Redactor — OBS-11–OBS-18, XCUT-19, XCUT-20"; `P5-16`, `P5-17`, `P5-25`, `P5-26`, `P5-27`, `P5-28`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/redactor.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/redactor.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/redactor_test.rb`

**Interfaces:**
- Consumes: `require "uri"`, `RedactionPolicy`.
- Produces: `Dexpace::Instrumentation::Redactor` with `#url`, `#header_value`, `#header_name?`, `#policy`, and `DEFAULT`.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/redactor_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/instrumentation/redactor"

# Exercises: OBS-11, OBS-12, OBS-13, OBS-14, OBS-15, OBS-16, OBS-17, OBS-18, XCUT-19, XCUT-20
class RedactorTest < DexpaceTestCase
  Redactor = Dexpace::Instrumentation::Redactor

  def redactor
    Redactor::DEFAULT
  end

  test "OBS-11: userinfo unconditionally redacted to fixed placeholder" do
    redacted = redactor.url("https://alice:secret@example.com/path")
    assert_equal("https://***:***@example.com/path", redacted)
    refute_includes(redacted, "alice")
    refute_includes(redacted, "secret")

    # User with no password
    assert_equal("https://***:***@example.com/path", redactor.url("https://alice@example.com/path"))
  end

  test "OBS-12: query parameters redacted preserving allow-list with multi-value atomicity" do
    # api-version kept, secret redacted
    url = "https://example.com/path?api-version=2026-01-01&token=secret"
    assert_equal("https://example.com/path?api-version=2026-01-01&token=***", redactor.url(url))

    # Multi-value atomicity across three occurrences
    multi_url = "https://example.com/path?token=1&token=2&token=3"
    assert_equal("https://example.com/path?token=***&token=***&token=***", redactor.url(multi_url))

    # Invalid UTF-8 parameter name handled safely without raising (Fact 7)
    invalid_utf8_url = "https://example.com/path?%FF=secret"
    res = redactor.url(invalid_utf8_url)
    assert_includes(res, "***")
  end

  test "OBS-13: fragment key-value pairs redacted like query and plain fragments kept verbatim" do
    # Fragment with key=value tokens
    assert_equal("https://example.com/path#token=***", redactor.url("https://example.com/path#token=secret"))
    assert_equal("https://example.com/path#api-version=2026-01-01", redactor.url("https://example.com/path#api-version=2026-01-01"))

    # Plain fragment with no '=' preserved verbatim
    assert_equal("https://example.com/path#section2", redactor.url("https://example.com/path#section2"))
  end

  test "OBS-14: preserves scheme, host, port, path, trailing question mark and internal fragment question mark" do
    # Trailing question mark preserved
    assert_equal("https://example.com:8443/path?", redactor.url("https://example.com:8443/path?"))

    # Question mark inside fragment does not create spurious query delimiter.
    # The chapter's own conformance case asserts the ABSENCE of a '?' before the '#', not
    # that the fragment survives: "a?b=c" carries an '=', so OBS-13 redacts it to "a?b=***".
    # A test that asserted full equality would be asserting against OBS-13.
    redacted = redactor.url("http://example.com/path#a?b=c")
    assert_equal("http://example.com/path", redacted.split("#", 2).first)
    refute_includes(redacted.split("#", 2).first, "?")
    assert_equal("a?b=***", redacted.split("#", 2).last)
  end

  test "OBS-15: totality returns fixed sentinel on parse failure" do
    assert_equal(Redactor::MALFORMED_URL, redactor.url("not a url at all"))
    assert_equal(Redactor::MALFORMED_URL, redactor.url("https://example.com/path with spaces"))
  end

  test "OBS-15, P5-27: opaque URIs round-trip untouched, and the rebuild rescue is covered" do
    # P5-27: an opaque URI has userinfo, query and fragment all nil, so no setter runs and
    # the URI::InvalidURIError those setters raise is never reached through this entry point.
    assert_equal("mailto:support@example.com", redactor.url("mailto:support@example.com"))
    assert_equal("urn:isbn:123", redactor.url("urn:isbn:123"))

    # The rescue is the totality backstop, not the mechanism, so it is covered directly
    # rather than left with a comment claiming it cannot happen: a policy whose allow-list
    # lookup raises drives the rewrite into the rescue on an otherwise ordinary URL.
    exploding_policy = Object.new
    def exploding_policy.query_allow_list = raise(::RuntimeError, "policy exploded")
    def exploding_policy.url_header_names = ::Set[]
    def exploding_policy.header_allow_list = ::Set[]
    hostile = Redactor.build(policy: exploding_policy)
    assert_equal(Redactor::MALFORMED_URL, hostile.url("https://example.com/p?a=1"))
  end

  test "OBS-16: header URL redaction with relative and unparseable paths" do
    # Parseable absolute URL redacted normally
    assert_equal(
      "https://example.com/path?api-version=1",
      redactor.header_value("location", "https://example.com/path?api-version=1")
    )

    # Relative URL with query
    assert_equal("/cb?***", redactor.header_value("location", "/cb?code=SECRET"))

    # Relative URL with empty query
    assert_equal("/cb?***", redactor.header_value("location", "/cb?"))

    # Fragment only
    assert_equal("?***", redactor.header_value("location", "#frag"))

    # Relative URL with neither query nor fragment returned verbatim
    assert_equal("/static/path", redactor.header_value("location", "/static/path"))

    # Unparseable URL with spaces and query
    assert_equal("bad path?***", redactor.header_value("location", "bad path?secret=1"))
  end

  test "OBS-17: only url_header_names are redacted as URLs" do
    # Location is redacted as URL
    assert_equal("/path?***", redactor.header_value("location", "/path?token=secret"))

    # Content-Type is not a URL header and passes through unchanged
    assert_equal("application/json; charset=utf-8", redactor.header_value("content-type", "application/json; charset=utf-8"))
  end

  test "OBS-18: header_name? checks allow-list and authorization negative test" do
    assert(redactor.header_name?("content-type"))
    assert(redactor.header_name?("Content-Type"))
    refute(redactor.header_name?("authorization"))
    refute(redactor.header_name?("Authorization"))
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/redactor_test.rb`
Expected: fails with `LoadError` loading `redactor.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/redactor.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"
require_relative "redaction_policy"

module Dexpace
  module Instrumentation
    # OBS-11..OBS-18, XCUT-19, XCUT-20: Total URL and header redactor.
    class Redactor
      MALFORMED_URL     = "[malformed url]"
      REDACTED_VALUE    = "***"
      REDACTED_USERINFO = "***:***"
      REDACTED_HEADER   = "REDACTED"
      RELATIVE_MARKER   = "?***"

      attr_reader :policy

      private_class_method :new

      # Defined before DEFAULT is assigned: the class body runs top to bottom, and a
      # `DEFAULT = build` placed above `initialize` reaches Object#initialize and raises
      # ArgumentError at require time.
      def initialize(policy)
        @policy = policy
      end

      def self.build(policy: RedactionPolicy::DEFAULT)
        new(policy).freeze
      end

      DEFAULT = build.freeze

      # OBS-11..OBS-15: URL redaction with total fallback to MALFORMED_URL
      def url(value)
        return MALFORMED_URL if value.nil?

        parsed = ::URI::RFC3986_PARSER.parse(value.to_s)
        # P5-27: Never mutate absent components to avoid opaque URI raises
        parsed.userinfo = REDACTED_USERINFO if parsed.userinfo

        if parsed.query
          parsed.query = redact_query_string(parsed.query)
        end

        if parsed.fragment
          parsed.fragment = redact_fragment_string(parsed.fragment)
        end

        parsed.to_s
      rescue ::StandardError
        MALFORMED_URL
      end

      # OBS-16, OBS-17: Header value redaction.
      # P5-25: this entry point NEVER returns MALFORMED_URL. OBS-15's sentinel and OBS-16's
      # ?*** marker are opposite answers to the same unparseable input, and conflating them
      # loses one requirement whichever way it is conflated. The totality backstop here is
      # the marker, applied to whatever prefix of the raw value survives.
      def header_value(name, value)
        return value if value.nil?

        folded_name = name.to_s.scrub("").downcase
        return value unless @policy.url_header_names.include?(folded_name)

        redact_header_url(value.to_s)
      rescue ::StandardError
        RELATIVE_MARKER
      end

      # OBS-18: Checks whether header name is in the configured allow-list
      def header_name?(name)
        return false if name.nil?

        @policy.header_allow_list.include?(name.to_s.scrub("").downcase)
      end

      private

      def redact_header_url(raw_val)
        parsed = ::URI::RFC3986_PARSER.parse(raw_val)
        if parsed.scheme
          url(raw_val)
        else
          # Relative URL: keep path and drop query/fragment
          has_query_or_fragment = !parsed.query.nil? || !parsed.fragment.nil?
          has_query_or_fragment ? "#{parsed.path}#{RELATIVE_MARKER}" : raw_val
        end
      rescue ::StandardError
        # P5-26: StandardError and not URI::Error — URI::InvalidURIError is already under it,
        # and listing both is a Lint/ShadowedException offence against a fatal-findings cop set.
        # P5-28: Unparseable route via string surgery
        q_idx = raw_val.index("?")
        f_idx = raw_val.index("#")
        cut_idx = [q_idx, f_idx].compact.min

        if cut_idx
          "#{raw_val[0...cut_idx]}#{RELATIVE_MARKER}"
        else
          raw_val
        end
      end

      def redact_query_string(query)
        return "" if query.empty?

        pairs = query.split("&", -1)
        redacted_pairs = pairs.map do |pair|
          next pair if pair.empty?

          k, has_eq, v = pair.partition("=")
          if has_eq.empty?
            pair
          else
            decoded_key = ::URI.decode_www_form_component(k).scrub("").downcase
            val_to_emit = @policy.query_allow_list.include?(decoded_key) ? v : REDACTED_VALUE
            "#{k}=#{val_to_emit}"
          end
        end

        redacted_pairs.join("&")
      end

      def redact_fragment_string(fragment)
        return fragment unless fragment.include?("=")

        tokens = fragment.split("&", -1)
        redacted_tokens = tokens.map do |token|
          k, has_eq, v = token.partition("=")
          if has_eq.empty?
            token
          else
            decoded_key = ::URI.decode_www_form_component(k).scrub("").downcase
            val_to_emit = @policy.query_allow_list.include?(decoded_key) ? v : REDACTED_VALUE
            "#{k}=#{val_to_emit}"
          end
        end

        redacted_tokens.join("&")
      end
    end
  end
end
```

- [ ] **Step 4: Write RBS signature**

Write `gems/dexpace-core/sig/dexpace/instrumentation/redactor.rbs`:
```rbs
module Dexpace
  module Instrumentation
    class Redactor
      MALFORMED_URL: String
      REDACTED_VALUE: String
      REDACTED_USERINFO: String
      REDACTED_HEADER: String
      RELATIVE_MARKER: String
      DEFAULT: Redactor

      def policy: () -> RedactionPolicy

      def self.build: (?policy: RedactionPolicy) -> Redactor
      def url: (untyped value) -> String
      def header_value: (untyped name, untyped value) -> String
      def header_name?: (untyped name) -> bool
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/redactor_test.rb`
Expected: 9 runs, 0 failures, 0 errors, 0 skips.

---
## Task 9: `Dexpace::Instrumentation::Event` and `Event::INERT`

**Requirement IDs:** `OBS-1`, `OBS-3`, `OBS-4`, `OBS-5`, `OBS-6`, `OBS-7`, `OBS-8`, `OBS-9`, `OBS-39`, `OBS-40`.
**Design:** "Dexpace::Instrumentation::Event and Event::INERT — OBS-1, OBS-3–OBS-9, OBS-39, OBS-40, OBS-7"; `P5-16`, `P5-17`, `P5-18`, `P5-20`, `P5-21`, `R8`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/event.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/event.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/event_test.rb`

**Interfaces:**
- Consumes: `Severity`, `Keys`, `Render`, `Diagnostics`, `Redactor`, `_Sink`.
- Produces: `Dexpace::Instrumentation::Event` class, `Event::INERT` shared singleton.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/event_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
require_relative "../../../lib/dexpace/instrumentation/severity"
require_relative "../../../lib/dexpace/instrumentation/keys"
require_relative "../../../lib/dexpace/instrumentation/render"
require_relative "../../../lib/dexpace/instrumentation/diagnostics"
require_relative "../../../lib/dexpace/instrumentation/redactor"
require_relative "../../../lib/dexpace/instrumentation/event"

# Exercises: OBS-1, OBS-3, OBS-4, OBS-5, OBS-6, OBS-7, OBS-8, OBS-9, OBS-39, OBS-40
class EventTest < DexpaceTestCase
  Event = Dexpace::Instrumentation::Event
  Severity = Dexpace::Instrumentation::Severity
  Keys = Dexpace::Instrumentation::Keys
  RecordingSink = Dexpace::RecordingSink

  def build_live_event(sink, severity: Severity::INFO, context: {}, redactor: Dexpace::Instrumentation::Redactor::DEFAULT)
    mutex = ::Thread::Mutex.new
    warn_latch = [false]
    Event.send(:new, severity, sink, redactor, context, Dexpace::Instrumentation::Diagnostics::DEFAULT_KEYS, mutex, warn_latch)
  end

  # R8. Two properties make this assertion portable, and neither is the file's magic comment:
  #   1. EVERY argument is a Symbol, an Integer or nil. None allocates on any Ruby, with or
  #      without `# frozen_string_literal: true`. A bare "x" literal allocates one object per
  #      call in a file that lacks the comment -- which is how this assertion would fail in
  #      dexpace-conformance (DEF-22, phase 8) against a CORRECT implementation.
  #   2. It is the DELTA of two loop sizes asserted == 0, not an absolute count under a bound.
  #      An absolute count is ~8 for a chain that allocates nothing per call (warm-up, method
  #      cache, the block object), and a fudge factor is what hides a 1-per-1000 regression.
  # This file carries the magic comment by repository rule; that is NOT this test's
  # precondition, and phase 8 copies this comment along with the assertion.
  test "OBS-1: Event::INERT allocation test yields 0 delta between loop sizes" do
    inert = Event::INERT
    assert(inert.frozen?)

    measure_allocs = ->(n) do
      ::GC.disable
      before = ::GC.stat(:total_allocated_objects)
      n.times { inert.field(:k, 1).event(:x).cause(nil).emit }
      ::GC.stat(:total_allocated_objects) - before
    ensure
      ::GC.enable
    end

    # Warm up before measuring. The FIRST measured call pays one-off interpreter cost --
    # method-cache population, the inline caches on the four call sites -- which lands
    # entirely in whichever loop runs first and leaves a small non-zero constant in an
    # otherwise exact delta. The design's own reconciliation pass saw the same asymmetry
    # from the other side (999 where 1000 was expected). Warming makes the two measurements
    # comparable; it does not weaken the assertion, which is still an exact == 0.
    measure_allocs.call(100)

    delta = measure_allocs.call(2_000) - measure_allocs.call(1_000)
    assert_equal(0, delta)
  end

  test "OBS-1: Event::INERT builder methods return self and emit returns nil" do
    inert = Event::INERT
    assert_same(inert, inert.field("key", "val"))
    assert_same(inert, inert.event("name"))
    assert_same(inert, inert.cause(::StandardError.new))
    assert_nil(inert.emit)
  end

  test "OBS-3: field rejects empty or nil key and renders nil value as string null" do
    sink = RecordingSink.new
    event = build_live_event(sink)

    assert_raises(Dexpace::InvalidArgumentError) { event.field("", "val") }
    assert_raises(Dexpace::InvalidArgumentError) { event.field(nil, "val") }

    event.field("null_key", nil).emit
    assert_equal(1, sink.entries.size)
    record = sink.entries.first.payload
    assert_equal("null", record["null_key"])
  end

  test "OBS-4: event(name) sets tag under 'event' key and empty name clears it" do
    sink = RecordingSink.new
    event = build_live_event(sink)

    event.event("order_placed").emit
    assert_equal("order_placed", sink.entries.first.payload[Keys::EVENT])

    # Clearing tag
    sink.clear
    event2 = build_live_event(sink)
    event2.event("temp").event("").emit
    refute(sink.entries.first.payload.key?(Keys::EVENT))
  end

  test "OBS-5: precedence rules: per-event field wins over global context and diagnostic context" do
    sink = RecordingSink.new
    diag_snapshot = { :"trace.id" => "diag_trace", shared: "diag_shared" }

    Dexpace::Instrumentation::Diagnostics.with(diag_snapshot) do
      event = build_live_event(sink, context: { "shared" => "global_shared", "global_only" => "val" })
      event.field("shared", "event_shared")
      event.emit

      record = sink.entries.first.payload
      assert_equal("event_shared", record["shared"])
      assert_equal("val", record["global_only"])
      assert_equal("diag_trace", record["trace.id"])
    end
  end

  test "OBS-8: emit at most once guard is safe under concurrent invocation" do
    sink = RecordingSink.new
    event = build_live_event(sink)
    q = ::Thread::Queue.new

    threads = 4.times.map do
      ::Thread.new do
        q.pop
        event.emit
      end
    end

    4.times { q << true }
    threads.each(&:join)

    assert_equal(1, sink.entries.size)
  end

  test "OBS-39, OBS-11..OBS-18: URL and header redaction run on the way into #field" do
    sink = RecordingSink.new
    event = build_live_event(sink)

    event.field(Keys::URL_FULL, "https://user:pass@example.com/api?token=secret")
    event.field("#{Keys::HTTP_REQUEST_HEADER_PREFIX}location", "/cb?secret=yes")
    event.emit

    record = sink.entries.first.payload
    assert_equal("https://***:***@example.com/api?token=***", record[Keys::URL_FULL])
    assert_equal("/cb?***", record["#{Keys::HTTP_REQUEST_HEADER_PREFIX}location"])
  end

  test "OBS-40: collision diagnostic warns once at verbose level on per-event field collision" do
    sink = RecordingSink.new(debug_enabled: true)
    warn_latch = [false]
    mutex = ::Thread::Mutex.new

    # First event with collision
    e1 = Event.send(:new, Severity::INFO, sink, Dexpace::Instrumentation::Redactor::DEFAULT, {}, [], mutex, warn_latch)
    e1.event("tagged_event").field(Keys::EVENT, "colliding_field").emit

    assert_equal(2, sink.entries.size) # 1 debug warning + 1 info event
    assert_equal(:debug, sink.entries[0].severity)
    assert_match(/collided/, sink.entries[0].payload)
    assert_equal("tagged_event", sink.entries[1].payload[Keys::EVENT])

    # Second event with collision does not repeat warning (latched)
    sink.clear
    e2 = Event.send(:new, Severity::INFO, sink, Dexpace::Instrumentation::Redactor::DEFAULT, {}, [], mutex, warn_latch)
    e2.event("tagged_event2").field(Keys::EVENT, "colliding_field2").emit

    assert_equal(1, sink.entries.size) # only info event, no warning
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/event_test.rb`
Expected: fails with `LoadError` loading `event.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/event.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "keys"
require_relative "render"
require_relative "diagnostics"
require_relative "redactor"

module Dexpace
  module Instrumentation
    # OBS-1..OBS-9, OBS-39, OBS-40: Mutable structured log event accumulator.
    class Event
      private_class_method :new

      # OBS-1, P5-20: Shared frozen singleton returned for disabled log levels. The subclass
      # overrides every builder method to return self and #emit to return nil, and writes no
      # instance variable, which is what makes freezing it safe; is_a?(Event) stays true.
      # INERT is built with .allocate because Event#initialize takes seven collaborators an
      # inert event has no use for -- so `new` stays private here too.
      class Inert < Event
        def field(_key, _value) = self
        def event(_name) = self
        def cause(_error) = self
        def emit = nil
      end
      private_constant :Inert

      INERT = Inert.allocate.freeze

      def initialize(severity, sink, redactor, context, diagnostic_keys, mutex, warn_latched)
        @severity        = severity
        @sink            = sink
        @redactor        = redactor
        @context         = context
        @diagnostic_keys = diagnostic_keys
        @mutex           = mutex
        @warn_latched    = warn_latched
        @fields          = {}
        @event_tag       = nil
        @cause_error     = nil
        @emitted         = false
      end

      # OBS-3, OBS-5, OBS-11..OBS-18: Sets key-value pair; redacts on insertion
      def field(key, value)
        # OBS-3: nil, a non-String/Symbol, and a key empty after #to_s all take the SAME
        # route, Model.required!, so the message form is SEAM-29's one form -- "field key is
        # required" -- and not a second spelling invented here.
        str_key = (key.is_a?(::String) || key.is_a?(::Symbol)) ? key.to_s : nil
        Model.required!("field key", str_key.nil? || str_key.empty? ? nil : str_key)

        redacted_val =
          if str_key == Keys::URL_FULL
            @redactor.url(value)
          elsif str_key.start_with?(Keys::HTTP_REQUEST_HEADER_PREFIX)
            hname = str_key.delete_prefix(Keys::HTTP_REQUEST_HEADER_PREFIX)
            @redactor.header_value(hname, value)
          elsif str_key.start_with?(Keys::HTTP_RESPONSE_HEADER_PREFIX)
            hname = str_key.delete_prefix(Keys::HTTP_RESPONSE_HEADER_PREFIX)
            @redactor.header_value(hname, value)
          else
            value
          end

        @fields[str_key] = redacted_val
        self
      end

      # OBS-4: Sets authoritative categorisation tag under 'event'; empty clears
      def event(name)
        @event_tag = (name.nil? || name.to_s.empty?) ? nil : name.to_s
        self
      end

      # OBS-39: Attaches throwable cause
      def cause(error)
        @cause_error = error
        self
      end

      # OBS-8: Terminal emission at most once, thread-safe, mutex released before sink call
      def emit
        @mutex.synchronize do
          return nil if @emitted

          @emitted = true
        end

        # OBS-40: Collision diagnostic
        if @event_tag && @fields.key?(Keys::EVENT) && @warn_latched
          should_warn = false
          @mutex.synchronize do
            unless @warn_latched[0]
              @warn_latched[0] = true
              should_warn = true
            end
          end
          if should_warn && @sink.respond_to?(:debug?) && @sink.debug?
            @sink.debug { "event tag #{@event_tag.inspect} collided with field 'event'; field dropped (OBS-40)" }
          end
        end

        # OBS-5 precedence: folded diagnostic context, then global context, then per-event fields
        record = {}
        diag = Diagnostics.folded(@diagnostic_keys)
        diag.each { |k, v| record[k] = v }
        @context.each { |k, v| record[k.to_s] = v }
        @fields.each { |k, v| record[k] = v }

        if @event_tag
          record[Keys::EVENT] = @event_tag
        end

        if @cause_error
          record[Keys::CAUSE] = Render.render(@cause_error)
        end

        rendered_record = {}
        record.each do |k, v|
          rendered_record[k] = Render.render(v)
        end

        @sink.public_send(@severity.sink_method) { rendered_record }
        nil
      end
    end
  end
end
```

- [ ] **Step 4: Write RBS signature**

Write `gems/dexpace-core/sig/dexpace/instrumentation/event.rbs`:
```rbs
module Dexpace
  module Instrumentation
    class Event
      INERT: Event

      def field: (untyped key, untyped value) -> self
      def event: (untyped name) -> self
      def cause: (untyped error) -> self
      def emit: () -> void
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/event_test.rb`
Expected: 8 runs, 0 failures, 0 errors, 0 skips.

---
## Task 10: `Dexpace::Instrumentation::Logger` and `Logger::NULL`

**Requirement IDs:** `OBS-1`, `OBS-2`, `OBS-9`, `OBS-10`, `OBS-40`.
**Design:** "Dexpace::Instrumentation::Logger and Logger::NULL — OBS-1, OBS-2, OBS-9, OBS-10, OBS-40"; `P5-16`, `P5-17`, `P5-38`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/logger.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/logger.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/logger_test.rb`

**Interfaces:**
- Consumes: `Severity`, `NULL_SINK`, `Event`, `Diagnostics`, `Redactor`.
- Produces: `Dexpace::Instrumentation::Logger` class, `Logger::NULL` singleton.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/logger_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
require_relative "../../../lib/dexpace/instrumentation/severity"
require_relative "../../../lib/dexpace/instrumentation/null_sink"
require_relative "../../../lib/dexpace/instrumentation/event"
require_relative "../../../lib/dexpace/instrumentation/logger"

# Exercises: OBS-1, OBS-2, OBS-9, OBS-10, OBS-40
class LoggerTest < DexpaceTestCase
  Logger = Dexpace::Instrumentation::Logger
  Severity = Dexpace::Instrumentation::Severity
  Event = Dexpace::Instrumentation::Event
  RecordingSink = Dexpace::RecordingSink

  test "OBS-1: event returns Event::INERT when level is disabled on sink" do
    sink = RecordingSink.new(info_enabled: false, debug_enabled: true)
    logger = Logger.build(sink: sink)

    # Disabled level returns the shared singleton. OBS-1's conformance clause is
    # "reference-identical across calls", and R8 requires the assertion to be written as a
    # QUALIFIED constant reference, because that is the form dexpace-conformance restates
    # from a different gem -- and it is what forces Event::INERT public (P5-20).
    inert_event = logger.event(Severity::INFO)
    assert_same(Dexpace::Instrumentation::Event::INERT, inert_event)
    assert_same(inert_event, logger.event(Severity::INFO))
    refute(logger.enabled?(Severity::INFO))

    # Enabled level returns live Event instance
    live_event = logger.event(Severity::VERBOSE)
    refute_same(Event::INERT, live_event)
    assert(logger.enabled?(Severity::VERBOSE))
  end

  test "Logger::NULL is a frozen instance over NULL_SINK" do
    null_logger = Logger::NULL
    assert(null_logger.frozen?)
    assert_same(Dexpace::Instrumentation::NULL_SINK, null_logger.sink)
    assert_same(Event::INERT, null_logger.event(Severity::INFO))
    assert_same(Event::INERT, null_logger.event(Severity::ERROR))
  end

  test "OBS-9: context is frozen at configuration and referenced on emitted events" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink, context: { "env" => "staging" })

    assert_equal({ "env" => "staging" }, logger.context)
    assert(logger.context.frozen?)

    logger.event(Severity::INFO).field("k", "v").emit
    assert_equal(1, sink.entries.size)
    assert_equal("staging", sink.entries.first.payload["env"])
  end

  test "OBS-10: diagnostic_keys nil is a mode, not 'use the default', and folds every key" do
    # nil is opt-in unfiltered mode, asserted through behaviour rather than through a reader:
    # P5-17 does not put #diagnostic_keys on the public surface.
    sink = RecordingSink.new
    logger = Logger.build(sink: sink, diagnostic_keys: nil)

    Dexpace::Instrumentation::Diagnostics.with({ :"trace.id" => "t", other: "o" }) do
      logger.event(Severity::INFO).emit
    end

    payload = sink.entries.first.payload
    assert_equal("t", payload["trace.id"])
    assert_equal("o", payload["other"])

    # And the default allow-list folds only {trace.id, span.id}.
    sink.clear
    default_logger = Logger.build(sink: sink)
    Dexpace::Instrumentation::Diagnostics.with({ :"trace.id" => "t", other: "o" }) do
      default_logger.event(Severity::INFO).emit
    end
    assert_equal("t", sink.entries.first.payload["trace.id"])
    refute(sink.entries.first.payload.key?("other"))
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/logger_test.rb`
Expected: fails with `LoadError` loading `logger.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/logger.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "severity"
require_relative "null_sink"
require_relative "diagnostics"
require_relative "redactor"
require_relative "event"

module Dexpace
  module Instrumentation
    # OBS-1, OBS-2, OBS-9, OBS-10: Logging facade entry point.
    class Logger
      private_class_method :new

      # P5-17 fixes the public method surface at .build, #event, #enabled?, #context and
      # #sink. @redactor and @diagnostic_keys are collaborators the Event carries, not
      # readers: a public reader here would be NFR-4-locked surface the ledger does not name.
      attr_reader :sink, :context

      # Defined before NULL is assigned: the class body runs top to bottom, and a
      # `NULL = build(...)` placed above `initialize` reaches Object#initialize and raises
      # ArgumentError at require time.
      def initialize(sink, context, redactor, diagnostic_keys, mutex, warn_latched)
        @sink            = sink
        @context         = context
        @redactor        = redactor
        @diagnostic_keys = diagnostic_keys
        @mutex           = mutex
        @warn_latched    = warn_latched
      end

      def self.build(
        sink: NULL_SINK,
        context: {},
        redactor: Redactor::DEFAULT,
        diagnostic_keys: Diagnostics::DEFAULT_KEYS
      )
        ctx = Model.own(context || {})
        mutex = ::Thread::Mutex.new
        warn_latched = [false]

        new(sink, ctx, redactor, diagnostic_keys, mutex, warn_latched).freeze
      end

      NULL = build(sink: NULL_SINK).freeze

      # OBS-1: Checks enablement once; returns Event::INERT if disabled
      def event(severity)
        sev = resolve_severity(severity)
        return Event::INERT unless enabled?(sev)

        Event.send(:new, sev, @sink, @redactor, @context, @diagnostic_keys, @mutex, @warn_latched)
      end

      def enabled?(severity)
        sev = resolve_severity(severity)
        @sink.public_send(sev.sink_predicate)
      end

      private

      def resolve_severity(severity)
        severity.is_a?(Severity) ? severity : Severity.of(severity)
      end
    end
  end
end
```

- [ ] **Step 4: Write RBS signature**

Write `gems/dexpace-core/sig/dexpace/instrumentation/logger.rbs`:
```rbs
module Dexpace
  module Instrumentation
    class Logger
      NULL: Logger

      def sink: () -> _Sink
      def context: () -> Hash[String, untyped]

      def self.build: (
        ?sink: _Sink,
        ?context: Hash[untyped, untyped],
        ?redactor: Redactor,
        ?diagnostic_keys: Array[Symbol]?
      ) -> Logger

      def event: (Severity | Symbol severity) -> Event
      def enabled?: (Severity | Symbol severity) -> bool
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/logger_test.rb`
Expected: 4 runs, 0 failures, 0 errors, 0 skips.

---
## Task 11: `Dexpace::Instrumentation.contain`

**Requirement IDs:** `OBS-20`, `XCUT-20`.
**Design:** "Dexpace::Instrumentation.contain(logger, event:) { … } -> nil — OBS-20, XCUT-20"; `P5-17`, `P5-37`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/contain.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/contain.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/contain_test.rb`

**Interfaces:**
- Consumes: `Severity`, `Events`, `Logger`.
- Produces: `Dexpace::Instrumentation.contain(logger, event:)` module function.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/contain_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
require_relative "../../../lib/dexpace/instrumentation/logger"
require_relative "../../../lib/dexpace/instrumentation/contain"

# Exercises: OBS-20, XCUT-20
class ContainTest < DexpaceTestCase
  RecordingSink = Dexpace::RecordingSink
  Events = Dexpace::Instrumentation::Events
  Keys = Dexpace::Instrumentation::Keys
  Logger = Dexpace::Instrumentation::Logger

  test "contain executes block and returns nil on success" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)

    ran = false
    result = Dexpace::Instrumentation.contain(logger, event: Events::INSTRUMENTATION_LOG) do
      ran = true
      "value that must be swallowed"
    end

    assert(ran)
    assert_nil(result)
    assert_equal(0, sink.entries.size)
  end

  test "contain catches StandardError and emits diagnostic event at WARNING with cause" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)

    result = Dexpace::Instrumentation.contain(logger, event: Events::INSTRUMENTATION_LOG) do
      raise ::IOError, "network stream severed"
    end

    assert_nil(result)
    assert_equal(1, sink.entries.size)
    entry = sink.entries.first
    assert_equal(:warn, entry.severity)
    record = entry.payload
    assert_equal(Events::INSTRUMENTATION_LOG, record[Keys::EVENT])
    assert_equal("IOError: network stream severed", record[Keys::CAUSE])
  end

  test "contain swallows secondary failures if logger emit itself raises" do
    exploding_sink = Object.new
    def exploding_sink.warn? = true
    def exploding_sink.warn = raise(::StandardError, "secondary sink failure")

    logger = Logger.build(sink: exploding_sink)

    result = Dexpace::Instrumentation.contain(logger, event: Events::INSTRUMENTATION_LOG) do
      raise ::ArgumentError, "primary error"
    end

    assert_nil(result)
  end

  test "contain does NOT catch fatal exceptions like SignalException or NoMemoryError" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)

    assert_raises(::SignalException) do
      Dexpace::Instrumentation.contain(logger, event: Events::INSTRUMENTATION_LOG) do
        raise ::SignalException, "SIGTERM"
      end
    end
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/contain_test.rb`
Expected: fails with `LoadError` loading `contain.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/contain.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "severity"

module Dexpace
  module Instrumentation
    # OBS-20, XCUT-20: Error containment primitive for log-emission sites.
    def self.contain(logger, event:)
      yield
      nil
    rescue ::StandardError => e
      begin
        logger.event(Severity::WARNING).event(event).cause(e).emit
      rescue ::StandardError
        nil # OBS-20: Secondary failure while emitting diagnostic MUST be swallowed
      end
      nil
    end
  end
end
```

- [ ] **Step 4: Write RBS signature**

Write `gems/dexpace-core/sig/dexpace/instrumentation/contain.rbs`:
```rbs
module Dexpace
  module Instrumentation
    def self.contain: (Logger logger, event: String) { () -> untyped } -> void
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/contain_test.rb`
Expected: 4 runs, 0 failures, 0 errors, 0 skips.

---
## Task 12: `Dexpace::Instrumentation::Preview`

**Requirement IDs:** `OBS-38`.
**Design:** "Dexpace::Instrumentation::Preview — OBS-38"; `P5-16`, `P5-17`, `P5-31`, `OI-7`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/preview.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/preview.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/preview_test.rb`

**Interfaces:**
- Consumes: `Dexpace::MediaType`.
- Produces: `Dexpace::Instrumentation::Preview` module with `.render(bytes, media_type:)`.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/preview_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/instrumentation/preview"

# Exercises: OBS-38
class PreviewTest < DexpaceTestCase
  Preview = Dexpace::Instrumentation::Preview

  # Test helper to simulate MediaType
  FakeMediaType = ::Data.define(:type, :subtype, :charset)

  test "renders empty bytes as empty string" do
    assert_equal("", Preview.render("", media_type: nil))
    assert_equal("", Preview.render(nil, media_type: nil))
  end

  test "renders binary media types and absent media types with binary format marker" do
    bytes = "raw\x00binary\xFF".b
    assert_equal(11, bytes.bytesize)
    assert_equal("[binary 11 bytes captured]", Preview.render(bytes, media_type: nil))

    image_media = FakeMediaType.new("image", "png", nil)
    assert_equal("[binary 11 bytes captured]", Preview.render(bytes, media_type: image_media))
  end

  test "renders text/plain with UTF-8 encoding safely" do
    media = FakeMediaType.new("text", "plain", "utf-8")
    assert_equal("hello world", Preview.render("hello world", media_type: media))
  end

  test "renders text with non-UTF-8 charset using corrected transcoding recipe (OI-7)" do
    iso_media = FakeMediaType.new("text", "plain", "iso-8859-1")
    iso_bytes = "caf\xE9".b # "café" in ISO-8859-1
    rendered = Preview.render(iso_bytes, media_type: iso_media)
    assert_equal("café", rendered)
    assert_equal(::Encoding::UTF_8, rendered.encoding)
  end

  test "renders structured syntax suffixes +json and +xml as text" do
    json_suffix_media = FakeMediaType.new("application", "problem+json", "utf-8")
    assert_equal('{"err": 1}', Preview.render('{"err": 1}', media_type: json_suffix_media))

    xml_suffix_media = FakeMediaType.new("application", "atom+xml", "utf-8")
    assert_equal('<entry/>', Preview.render('<entry/>', media_type: xml_suffix_media))
  end

  test "decoding never throws on truncated multibyte bytes and substitutes replacement character" do
    utf8_media = FakeMediaType.new("application", "json", "utf-8")
    truncated_bytes = "\xE4\xBD".b # truncated multibyte
    rendered = Preview.render(truncated_bytes, media_type: utf8_media)
    assert(rendered.valid_encoding?)
    assert_includes(rendered, "\uFFFD")
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/preview_test.rb`
Expected: fails with `LoadError` loading `preview.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/preview.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "set"

module Dexpace
  module Instrumentation
    # OBS-38: Charset-aware text and binary-safe payload preview renderer.
    module Preview
      BINARY_MARKER_FORMAT = "[binary %d bytes captured]"
      TEXT_SUBTYPES = ::Set[
        "json", "xml", "yaml", "csv", "javascript", "graphql", "x-www-form-urlencoded", "x-ndjson"
      ].freeze
      # RFC 6839 structured-syntax suffixes. Per-pattern timeout, never Regexp.timeout, which
      # would impose a process-wide budget on the host. private_constant: P5-16 names
      # BINARY_MARKER_FORMAT and TEXT_SUBTYPES as this module's public constants and no third.
      SUFFIX_REGEXP = ::Regexp.new('(\+json|\+xml)\z', timeout: 1.0)
      private_constant :SUFFIX_REGEXP

      def self.render(bytes, media_type:)
        return "" if bytes.nil? || bytes.empty?
        return format_binary(bytes) if media_type.nil?

        if text_media_type?(media_type)
          decode_text(bytes, media_type)
        else
          format_binary(bytes)
        end
      end

      def self.text_media_type?(media_type)
        return true if media_type.type == "text"

        subtype = media_type.subtype
        return false unless subtype

        TEXT_SUBTYPES.include?(subtype) || SUFFIX_REGEXP.match?(subtype)
      end
      private_class_method :text_media_type?

      # OI-7, P5-31: Retag before transcoding to avoid destroying non-ASCII bytes
      def self.decode_text(bytes, media_type)
        raw_bytes = bytes.is_a?(::String) ? bytes.b : bytes.to_s.b
        charset = media_type.charset
        enc =
          if charset
            begin
              ::Encoding.find(charset)
            rescue ::ArgumentError
              ::Encoding::UTF_8
            end
          else
            ::Encoding::UTF_8
          end

        raw_bytes.dup.force_encoding(enc).encode(::Encoding::UTF_8, enc, invalid: :replace, undef: :replace)
      rescue ::StandardError
        format_binary(bytes)
      end
      private_class_method :decode_text

      def self.format_binary(bytes)
        size = bytes.respond_to?(:bytesize) ? bytes.bytesize : bytes.to_s.bytesize
        ::Kernel.sprintf(BINARY_MARKER_FORMAT, size)
      end
      private_class_method :format_binary
    end
  end
end
```

- [ ] **Step 4: Write RBS signature**

Write `gems/dexpace-core/sig/dexpace/instrumentation/preview.rbs`:
```rbs
module Dexpace
  module Instrumentation
    module Preview
      BINARY_MARKER_FORMAT: String
      TEXT_SUBTYPES: Set[String]

      def self.render: (untyped bytes, media_type: Dexpace::MediaType?) -> String
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/preview_test.rb`
Expected: 6 runs, 0 failures, 0 errors, 0 skips.

---
## Task 13: `Dexpace::Instrumentation::HTTPLogging`

**Requirement IDs:** `OBS-34`, `OBS-35`.
**Design:** "Dexpace::Instrumentation::HTTPLogging — OBS-34, OBS-35"; `P5-16`, `P5-17`, `P5-36`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/http_logging.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/http_logging.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/http_logging_test.rb`

**Interfaces:**
- Consumes: `Dexpace::InvalidArgumentError`.
- Produces: `Dexpace::Instrumentation::HTTPLogging` closed set (`NONE`, `HEADERS`, `BODY`, `DEFAULT`), `.parse`, and `.resolve`.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/http_logging_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/instrumentation/http_logging"

# Exercises: OBS-34, OBS-35
class HTTPLoggingTest < DexpaceTestCase
  HTTPLogging = Dexpace::Instrumentation::HTTPLogging

  FakeConfig = ::Data.define(:values) do
    def string(k) = values[k]
  end

  test "defines three ordering levels and defaults to NONE" do
    assert_equal(:none, HTTPLogging::NONE.name)
    assert_equal(0, HTTPLogging::NONE.order)

    assert_equal(:headers, HTTPLogging::HEADERS.name)
    assert_equal(1, HTTPLogging::HEADERS.order)

    assert_equal(:body, HTTPLogging::BODY.name)
    assert_equal(2, HTTPLogging::BODY.order)

    assert_same(HTTPLogging::NONE, HTTPLogging::DEFAULT)
    assert(HTTPLogging::BODY.at_least?(HTTPLogging::HEADERS))
    assert(HTTPLogging::HEADERS.at_least?(HTTPLogging::HEADERS))
    refute(HTTPLogging::NONE.at_least?(HTTPLogging::HEADERS))
  end

  test "of strictly resolves valid symbol or raises InvalidArgumentError" do
    assert_same(HTTPLogging::NONE, HTTPLogging.of(:none))
    assert_same(HTTPLogging::HEADERS, HTTPLogging.of(:headers))
    assert_same(HTTPLogging::BODY, HTTPLogging.of(:body))

    assert_raises(Dexpace::InvalidArgumentError) { HTTPLogging.of(:all) }
    assert_raises(Dexpace::InvalidArgumentError) { HTTPLogging.of("headers") }
  end

  test "parse tolerantly parses strings with whitespace and case insensitive matching" do
    assert_same(HTTPLogging::HEADERS, HTTPLogging.parse("  Headers  "))
    assert_same(HTTPLogging::HEADERS, HTTPLogging.parse("HEADERS"))
    assert_same(HTTPLogging::BODY, HTTPLogging.parse("body"))
    assert_same(HTTPLogging::NONE, HTTPLogging.parse("none"))

    # Unrecognized or empty falls back to default without raising
    assert_same(HTTPLogging::NONE, HTTPLogging.parse("invalid"))
    assert_same(HTTPLogging::HEADERS, HTTPLogging.parse("invalid", default: HTTPLogging::HEADERS))
    assert_same(HTTPLogging::NONE, HTTPLogging.parse(""))
    assert_same(HTTPLogging::NONE, HTTPLogging.parse(nil))
  end

  test "resolve requires key keyword with no default and resolves from configuration (P5-36)" do
    # The key is a caller's, not the SDK's: OBS-35's embedded MUST is "The SDK MUST NOT bake
    # in a default config key name", so a caller's own spelling is used here deliberately.
    # Configuration::Keys::LOG_LEVEL is a published name a caller MAY pass and nothing here
    # falls back to it, which is what 5a reconciled against CFG-14 on 5b's behalf.
    config = FakeConfig.new({ "sdk.log_level" => "headers" })
    level = HTTPLogging.resolve(config, key: "sdk.log_level")
    assert_same(HTTPLogging::HEADERS, level)

    # Missing key in config falls back to default
    level_default = HTTPLogging.resolve(config, key: "missing.key", default: HTTPLogging::BODY)
    assert_same(HTTPLogging::BODY, level_default)

    # Missing key keyword is an ArgumentError
    assert_raises(::ArgumentError) { HTTPLogging.resolve(config) }
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/http_logging_test.rb`
Expected: fails with `LoadError` loading `http_logging.rb`.

- [ ] **Step 3: Write implementation**

Write `gems/dexpace-core/lib/dexpace/instrumentation/http_logging.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error/invalid_argument_error"

module Dexpace
  module Instrumentation
    # OBS-34, OBS-35: HTTP logging granularity closed set and tolerant resolver.
    class HTTPLogging < ::Data.define(:name, :order)
      private_class_method :new

      NONE    = new(:none, 0).freeze
      HEADERS = new(:headers, 1).freeze
      BODY    = new(:body, 2).freeze

      DEFAULT = NONE

      # P5-16 names NONE, HEADERS, BODY and DEFAULT as this type's public constants and no
      # fifth, so ALL is private here (unlike Severity::ALL, which the ledger row does name).
      ALL = [NONE, HEADERS, BODY].freeze
      LOOKUP = ALL.to_h { |l| [l.name, l] }.freeze
      STRING_LOOKUP = ALL.to_h { |l| [l.name.name, l] }.freeze
      private_constant :ALL, :LOOKUP, :STRING_LOOKUP

      def at_least?(other)
        order >= other.order
      end

      def self.of(name)
        LOOKUP.fetch(name) do
          raise InvalidArgumentError, "unrecognized HTTP logging level #{name.inspect}; must be :none, :headers, or :body"
        end
      end

      def self.parse(text, default: NONE)
        return default if text.nil?

        normalized = text.to_s.strip.downcase
        STRING_LOOKUP.fetch(normalized, default)
      end

      # OBS-35, P5-36: Resolves from configuration; key is required with no fallback default key
      def self.resolve(configuration, key:, default: NONE)
        raw = configuration.string(key)
        parse(raw, default: default)
      end
    end
  end
end
```

- [ ] **Step 4: Write RBS signature**

Write `gems/dexpace-core/sig/dexpace/instrumentation/http_logging.rbs`:
```rbs
module Dexpace
  module Instrumentation
    class HTTPLogging < Data
      NONE: HTTPLogging
      HEADERS: HTTPLogging
      BODY: HTTPLogging
      DEFAULT: HTTPLogging

      def name: () -> Symbol
      def order: () -> Integer
      def at_least?: (HTTPLogging other) -> bool

      def self.of: (Symbol name) -> HTTPLogging
      def self.parse: (untyped text, ?default: HTTPLogging) -> HTTPLogging
      def self.resolve: (untyped configuration, key: String, ?default: HTTPLogging) -> HTTPLogging
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/http_logging_test.rb`
Expected: 4 runs, 0 failures, 0 errors, 0 skips.

---
## Task 14: Downstream Register Wirings

**Requirement IDs:** `DEF-27`, `DEF-32`, `DEF-34`, `CFG-24`, `CFG-25`.
**Design:** "The two picked-up register wirings — DEF-27, DEF-32, DEF-34; P5-8 discharged".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/closeable.rb`
- Modify: `gems/dexpace-core/sig/dexpace/closeable.rbs`
- Modify: `gems/dexpace-core/lib/dexpace/hooks.rb`
- Modify: `gems/dexpace-core/lib/dexpace/proxy/resolution.rb`
- Modify: `gems/dexpace-core/lib/dexpace/configuration/keys.rb`
- Modify: `gems/dexpace-core/sig/dexpace/configuration/keys.rbs`
- Modify: `gems/dexpace-core/lib/dexpace/proxy.rb` (`Proxy.resolve` gains `logger:`)
- Modify: `gems/dexpace-core/sig/dexpace/proxy.rbs`
- Modify: `gems/dexpace-core/test/dexpace/closeable_test.rb` (**two** stale `DEF-27` claims — phase 2's and phase 4b's; see Step 5)
- Test: `gems/dexpace-core/test/dexpace/instrumentation/downstream_wirings_test.rb`

**Interfaces:**
- Consumes: `close_quietly`, `Hooks`, `ProxyResolution`, `Configuration::Keys`, `contain`, `Logger`, `Events`.
- Produces: Integrated diagnostic logging across disposal, hook notification, proxy resolution, and configuration key constants.

- [ ] **Step 1: Write the failing test**

Write `gems/dexpace-core/test/dexpace/instrumentation/downstream_wirings_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
# This suite crosses four subsystems 5b only modifies (close_quietly, Hooks, ProxyResolution,
# Configuration::Keys), so it loads the whole gem rather than hand-picking files.
require_relative "../../../lib/dexpace"

# Exercises: DEF-27, DEF-32, DEF-34, P5-8, CFG-24, CFG-25
class DownstreamWiringsTest < DexpaceTestCase
  RecordingSink = Dexpace::RecordingSink
  Logger = Dexpace::Instrumentation::Logger
  Events = Dexpace::Instrumentation::Events
  Keys = Dexpace::Instrumentation::Keys

  test "DEF-27: close_quietly without onto: routes rescued error through Instrumentation.contain" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)

    bad_resource = Object.new
    def bad_resource.close = raise(::IOError, "close failure")

    Dexpace.close_quietly(bad_resource, logger: logger)

    assert_equal(1, sink.entries.size)
    record = sink.entries.first.payload
    assert_equal(Events::INSTRUMENTATION_CLOSE, record[Keys::EVENT])
    assert_equal("IOError: close failure", record[Keys::CAUSE])
  end

  test "DEF-32: Hooks.notify emits diagnostic for secondary hook failures without replacing trail" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)

    h1 = ->(_) { raise ::IOError, "first hook error" }
    h2 = ->(_) { raise ::ArgumentError, "second hook error" }

    ex = assert_raises(::IOError) do
      Dexpace::Hooks.notify([h1, h2], :arg, logger: logger)
    end

    assert_equal("first hook error", ex.message)
    # First error is re-raised with suppressed trail, second error emitted as diagnostic
    assert_equal(1, sink.entries.size)
    assert_equal(Events::INSTRUMENTATION_HOOK, sink.entries.first.payload[Keys::EVENT])
    assert_equal("ArgumentError: second hook error", sink.entries.first.payload[Keys::CAUSE])
  end

  # DexpaceTestCase prepends FatalWarnings to Warning.singleton_class, so a warning CFG-24
  # and CFG-25 REQUIRE would otherwise fail this test. 5a met the same problem in
  # proxy_test.rb and solved it inline rather than adding a test-support double; the design
  # fixes 5b's doubles at exactly two, so this harness lives here for the same reason.
  # It prepends over FatalWarnings, so it must be installed and removed around the block.
  module WarningCapture
    def warn(message, category: nil)
      sink = ::Thread.current[:dexpace_warning_sink]
      return super if sink.nil?

      sink << [message, category]
      nil
    end
  end
  ::Warning.singleton_class.prepend(WarningCapture)

  def capture_warnings
    sink = []
    ::Thread.current[:dexpace_warning_sink] = sink
    yield
    sink
  ensure
    ::Thread.current[:dexpace_warning_sink] = nil
  end

  test "P5-8: ProxyResolution emits INSTRUMENTATION_CONFIG event beside Kernel#warn" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)

    # CFG-25: a proxy URL with no explicit port warns. Resolution goes through the public
    # entry point, Dexpace::Proxy.resolve(configuration, logger:); ProxyResolution is a
    # private_constant and has no resolve_from_env.
    config = Dexpace.configuration.derive do |b|
      b.override(Dexpace::Configuration::Keys::HTTPS_PROXY, "http://proxy.example.com")
    end

    warnings = capture_warnings do
      Dexpace::Proxy.resolve(config, logger: logger)
    end

    refute_empty(warnings)
    assert_includes(warnings.first[0], "[dexpace]")
    assert_equal(1, sink.entries.size)
    assert_equal(Events::INSTRUMENTATION_CONFIG, sink.entries.first.payload[Keys::EVENT])
  end

  test "DEF-34: Configuration::Keys gains LOG_PREVIEW_BYTES and leaves 5a's LOG_LEVEL alone" do
    cfg_keys = Dexpace::Configuration::Keys
    # 5a's constant, untouched by 5b. Its value is the name itself, as all seven of 5a's are.
    assert_equal("LOG_LEVEL", cfg_keys::LOG_LEVEL)
    # 5b's one new name, added in the change that reads it (DEF-34).
    assert_equal("LOG_PREVIEW_BYTES", cfg_keys::LOG_PREVIEW_BYTES)
    assert(cfg_keys::LOG_LEVEL.frozen?)
    assert(cfg_keys::LOG_PREVIEW_BYTES.frozen?)
  end

  test "DEF-27: the no-logger default still returns nil and still does not raise" do
    # 4b's interface table anticipates the change: "Phase 5 adds the http.instrumentation.*
    # diagnostic for the onto:-absent case and closes the row". What survives it is the RETURN
    # contract -- CFG-21's null-safety clause -- and that is what this asserts. What does NOT
    # survive is the claim that the error VANISHES, which stands in two places in
    # closeable_test.rb and which Step 5 removes.
    bad_resource = Object.new
    def bad_resource.close = raise(::IOError, "close failure")

    assert_nil(Dexpace.close_quietly(bad_resource))

    # And the onto: route is untouched: the trail still receives the secondary.
    primary = ::RuntimeError.new("primary")
    Dexpace.close_quietly(bad_resource, onto: primary)
    assert_equal(1, Dexpace.suppressed(primary).size)
    assert_kind_of(::IOError, Dexpace.suppressed(primary).first)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/downstream_wirings_test.rb`
Expected: fails on `close_quietly` missing `logger:` keyword or `Configuration::Keys` missing constants.

- [ ] **Step 3: Modify implementation files**

Update `gems/dexpace-core/lib/dexpace/closeable.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "instrumentation/keys"
require_relative "instrumentation/severity"
require_relative "instrumentation/logger"
require_relative "instrumentation/contain"

module Dexpace
  # DEF-27: close_quietly gains a third keyword, logger:, defaulting to Logger::NULL, and
  # routes the onto:-absent branch through contain. Phase 2's nil-safety (CFG-21's last
  # clause) and phase 4b's entry-time validation of onto: are BOTH preserved: 4b validates
  # before the close is attempted, so an invalid onto: raises without closing anything.
  def self.close_quietly(resource, onto: nil, logger: Instrumentation::Logger::NULL)
    unless onto.nil? || onto.is_a?(::Exception)
      raise InvalidArgumentError, "onto must be an Exception"
    end
    return nil if resource.nil?
    return nil unless resource.respond_to?(:close)

    resource.close
  rescue ::StandardError => e
    if onto
      Dexpace.attach_suppressed(onto, e)
    else
      Instrumentation.contain(logger, event: Instrumentation::Events::INSTRUMENTATION_CLOSE) do
        logger.event(Instrumentation::Severity::WARNING)
              .event(Instrumentation::Events::INSTRUMENTATION_CLOSE)
              .cause(e)
              .emit
      end
    end
    nil
  end
end
```

Update `gems/dexpace-core/sig/dexpace/closeable.rbs`:
```rbs
module Dexpace
  def self.close_quietly: (untyped resource, ?onto: untyped, ?logger: Instrumentation::Logger) -> void
end
```

Update `gems/dexpace-core/lib/dexpace/hooks.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "instrumentation/keys"
require_relative "instrumentation/severity"
require_relative "instrumentation/logger"
require_relative "instrumentation/contain"

module Dexpace
  module Hooks
    def self.notify(hooks, argument, logger: Instrumentation::Logger::NULL)
      primary_error = nil

      hooks.each do |hook|
        hook.call(argument)
      rescue ::StandardError => e
        if primary_error.nil?
          primary_error = e
        else
          # Phase 4b's trail, unchanged: Dexpace.attach_suppressed(primary, secondary) is
          # the module function; there is no #add_suppressed instance method anywhere.
          Dexpace.attach_suppressed(primary_error, e)
          # DEF-32: Secondary hook failures emitted as diagnostics BESIDE the trail.
          Instrumentation.contain(logger, event: Instrumentation::Events::INSTRUMENTATION_HOOK) do
            logger.event(Instrumentation::Severity::WARNING)
                  .event(Instrumentation::Events::INSTRUMENTATION_HOOK)
                  .cause(e)
                  .emit
          end
        end
      end

      raise primary_error if primary_error
      nil
    end
  end
  private_constant :Hooks
end
```

Update `gems/dexpace-core/lib/dexpace/proxy/resolution.rb`:

`5a` funnels all six warning call sites through one private helper, `ProxyResolution.emit(message)`,
whose whole body is `::Kernel.warn("[dexpace] #{message}")`. That single helper is where the event goes
— one edit, not six — and `Dexpace::Proxy.resolve(configuration = Dexpace.configuration)` plus
`ProxyResolution.resolve(configuration)` each gain a `logger:` keyword that reaches it. **The warning
stays** (`P5-8`, P2-6's shape). `ProxyResolution` is a `private_constant` with no `sig/` mirror, so this
adds no public surface beyond `Proxy.resolve`'s keyword.

```ruby
# P5-8, CFG-24, CFG-25: an http.instrumentation.config event BESIDE the warning, never instead of it.
def emit(message, logger)
  ::Kernel.warn("[dexpace] #{message}")
  Instrumentation.contain(logger, event: Instrumentation::Events::INSTRUMENTATION_CONFIG) do
    logger.event(Instrumentation::Severity::WARNING)
          .event(Instrumentation::Events::INSTRUMENTATION_CONFIG)
          .field("message", message)
          .emit
  end
  nil
end
```

Update `gems/dexpace-core/lib/dexpace/configuration/keys.rb`:

**`Keys::LOG_LEVEL` already exists and is `5a`'s — it is `"LOG_LEVEL"`, and 5b must not restate,
rename or revalue it.** `5a` ships seven constants whose value is the name itself
(`MAX_RETRY_ATTEMPTS`, `LOG_LEVEL`, `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`,
`MAX_MATERIALIZED_BYTES`, `MAX_TRACKED_CONTEXTS`), and `LOG_LEVEL` is `OBS-35`'s published name a
caller may pass — never a fallback (`P5-36`). `DEF-34`'s two wirings therefore need exactly **one**
new key, the shared body-preview size, added in the change that reads it, following the same
value-equals-name convention:

```ruby
LOG_PREVIEW_BYTES = "LOG_PREVIEW_BYTES"
```

Update `gems/dexpace-core/sig/dexpace/configuration/keys.rbs`:
Add:
```rbs
LOG_PREVIEW_BYTES: String
```

- [ ] **Step 4: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/downstream_wirings_test.rb`
Expected: 5 runs, 0 failures, 0 errors, 0 skips.

- [ ] **Step 5: Remove the two stale `DEF-27` claims in `closeable_test.rb`**

**There are two, not one, and they are in the same file.** Checked against both owning plans at the
reconciliation pass, because the draft named only phase 2's:

1. **Phase 2's**, inside `test "close_quietly closes what it is given and swallows a close failure"` —
   the comment `# DEF-27: the rescued error is dropped until phase 4 supplies the suppressed trail
   and phase 5 the instrumentation diagnostic. Asserted rather than left as a comment, so the day a
   route lands this test is what has to change.` **This is that day.** Phase 2 wrote the sentence to
   be deleted by whoever landed the second route.
2. **Phase 4b's**, the *name* of `test "close_quietly with onto: absent drops error and returns nil"`.
   "Drops error" is no longer true: the error now reaches `Instrumentation.contain` and, with a
   logger supplied, an `http.instrumentation.close` event.

**What is removed is the claim, not the assertion.** Both tests assert `assert_nil(...)` on the
return value, and both still pass: `close_quietly` still returns `nil` and still does not raise on
the `onto:`-absent path, because `logger:` defaults to `Logger::NULL` and `contain` swallows. That
return contract is `CFG-21`'s last clause and 5b does not touch it — which is what keeps every
existing caller correct. So: delete phase 2's comment, rename 4b's test to
`"close_quietly with onto: absent returns nil and routes the error to the logger"`, and leave both
bodies alone. Do it in **this** change, not later: `DEF-27` cannot move to `picked-up` in Task 16
while either sentence stands, and a `picked-up` row contradicted by a green test in the same gem is
worse than a row left open.

---
## Task 15: `Dexpace::Instrumentation::Emitter`, `Step`, and `AsyncStep`

**Requirement IDs:** `OBS-20`, `OBS-34`, `OBS-36`, `OBS-39`, `DEF-34`.
**Design:** "Dexpace::Instrumentation::Step and ::AsyncStep — OBS-34, OBS-36, OBS-39, OBS-20"; `P5-16`, `P5-17`, `P5-33`, `P5-34`, `R11`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/emitter.rb` (`private_constant`)
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/step.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/step.rbs`
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/async_step.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/async_step.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/step_test.rb`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/async_step_test.rb`

**Interfaces:**
- Consumes: `Logger`, `Redactor`, `HTTPLogging`, `Preview`, `Clock::SYSTEM`, `Stages::LOGGING`, `5c`'s tracing and metrics interfaces.
- Produces: `Dexpace::Instrumentation::Step` and `Dexpace::Instrumentation::AsyncStep` pipeline stages.

- [ ] **Step 1: Write the failing tests**

Write `gems/dexpace-core/test/dexpace/instrumentation/step_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
# 5c's doubles, CONSUMED and not redefined (P5-48). The design is explicit: "5b's step tests
# reuse them rather than adding a second set", which is DEF-29's one-double-per-idea concern
# met rather than deferred. A second RecordingTracer/RecordingMeter under 5b would be two
# files at one path and the exact drift DEF-29 would later have to consolidate.
require_relative "../../support/recording_tracer"
require_relative "../../support/recording_span"
require_relative "../../support/recording_meter"
require_relative "../../../lib/dexpace"

# Exercises: OBS-18, OBS-20, OBS-34, OBS-36, OBS-39, DEF-34
class StepTest < DexpaceTestCase
  Step = Dexpace::Instrumentation::Step
  HTTPLogging = Dexpace::Instrumentation::HTTPLogging
  Keys = Dexpace::Instrumentation::Keys
  Events = Dexpace::Instrumentation::Events
  RecordingSink = Dexpace::RecordingSink
  Logger = Dexpace::Instrumentation::Logger
  Redactor = Dexpace::Instrumentation::Redactor

  # 5c's constants, verified against 5c's Task 1 fences at reconciliation rather than
  # guessed. RecordingTracerFactory is a SEPARATE top-level constant, not RecordingTracer::
  # Factory; all six sit flat under Dexpace, on 5a's FakeClock precedent.
  RecordingTracerFactory = Dexpace::RecordingTracerFactory
  RecordingTracer = Dexpace::RecordingTracer
  RecordingMeter = Dexpace::RecordingMeter

  # 5b's own fakes are the pipeline shapes 4c does not ship a test double for. There is NO
  # fake tracer, span, scope, counter, histogram or meter here: those are 5c's, above, and
  # 5b declares no RecordingCounter and no RecordingHistogram -- they are 5c's too.
  FakeClock = ::Data.define(:monotonic)
  FakeCursor = ::Data.define(:response) do
    def call(new_request = nil) = response
  end

  def build_request(method: "GET", url: "https://example.com/data", headers: {}, body: nil)
    builder = Dexpace::Headers.builder
    headers.each { |name, value| builder.add(name, value) }
    Dexpace::Request.build(method: method, url: url, headers: builder.build, body: body)
  end

  def build_response(request, status: 200, headers: {}, body: nil)
    builder = Dexpace::Headers.inbound_builder
    headers.each { |name, value| builder.add(name, value) }
    Dexpace::Response.build(request: request, protocol: Dexpace::Protocol::HTTP_1_1,
                            status: status, reason: nil, headers: builder.build, body: body)
  end

  # This is the test that discharges OBS-34's conformance clause -- "at none assert no
  # request/response events but the span still starts/ends and the counter/histogram still
  # record" -- and it asserts four things in ONE test on purpose. A test that asserted only
  # "no events at none" passes under an implementation that guards the span with the same if.
  test "OBS-34: at level NONE silences log events while span lifecycle and metrics run (independence clause)" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)
    factory = RecordingTracerFactory.new
    meter = RecordingMeter.new
    clock = FakeClock.new(100.0)

    step = Step.build(
      logger: logger,
      redactor: Redactor::DEFAULT,
      level: HTTPLogging::NONE,
      tracer_factory: factory,
      meter: meter,
      clock: clock
    )

    req = build_request
    cursor = FakeCursor.new(build_response(req))

    step.call(req, cursor)

    # Conformance assertion 1: zero sink writes
    assert_equal(0, sink.entries.size)

    # 2 and 3: exactly one tracer, one span start and one span end. #tracers is the factory's
    # log of what it manufactured -- calling factory.tracer again would MAKE a second tracer
    # and assert nothing about the one the step used. RecordingSpan has no #finished?: it
    # latches into #finished_at, an Array, which is how 5c asserts OBS-21's idempotent finish.
    assert_equal(1, factory.tracers.size)
    tracer = factory.tracers.first
    assert_equal(1, tracer.spans.size)
    assert_equal(1, tracer.spans.first.finished_at.size)

    # 4: the counter and the histogram each record once, under 5b's two instrument names.
    # RecordingMeter exposes #counters and #histograms, both Arrays in creation order, and no
    # by-name lookup; the step manufactures exactly one of each in .build, so the assertion is
    # on that one -- and on its #name, so a swap of the two constants would fail.
    assert_equal(1, meter.counters.size)
    assert_equal(Keys::INSTRUMENT_REQUEST_COUNT, meter.counters.first.name)
    assert_equal(1, meter.counters.first.records.size)
    assert_equal(1, meter.histograms.size)
    assert_equal(Keys::INSTRUMENT_REQUEST_DURATION, meter.histograms.first.name)
    assert_equal(1, meter.histograms.first.records.size)

    # OBS-31's attributes keyword is OPTIONAL on both instruments and 5b passes none; the
    # recorded entry is therefore {amount:, attributes: nil}. See the ensure in step.rb.
    assert_equal({ amount: 1, attributes: nil }, meter.counters.first.records.first)
  end

  test "OBS-34, OBS-39: at level HEADERS emits http.request and http.response events with headers and duration" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)

    step = Step.build(
      logger: logger,
      redactor: Redactor::DEFAULT,
      level: HTTPLogging::HEADERS
    )

    req = build_request(
      method: "POST",
      url: "https://example.com/submit?token=secret",
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer sk-live-abc123" }
    )
    res = build_response(req, status: 201,
                         headers: { "Location" => "https://example.com/res/1?token=secret" })
    cursor = FakeCursor.new(res)

    step.call(req, cursor)

    assert_equal(2, sink.entries.size)

    # Request event
    req_entry = sink.entries[0]
    assert_equal(Events::HTTP_REQUEST, req_entry.payload[Keys::EVENT])
    assert_equal("POST", req_entry.payload[Keys::HTTP_REQUEST_METHOD])
    assert_equal("https://example.com/submit?token=***", req_entry.payload[Keys::URL_FULL])
    assert_equal("application/json", req_entry.payload["#{Keys::HTTP_REQUEST_HEADER_PREFIX}content-type"])

    # OBS-18's NEGATIVE, which is the assertion that matters. Asserting only that an
    # Authorization key is absent passes under an implementation that logs the value under a
    # different key, so the assertion is that the credential appears NOWHERE in the payload.
    refute(req_entry.payload.key?("#{Keys::HTTP_REQUEST_HEADER_PREFIX}authorization"))
    refute_includes(req_entry.payload.inspect, "Bearer")
    refute_includes(req_entry.payload.inspect, "sk-live-abc123")

    # Response event
    res_entry = sink.entries[1]
    assert_equal(Events::HTTP_RESPONSE, res_entry.payload[Keys::EVENT])
    assert_equal(201, res_entry.payload[Keys::HTTP_RESPONSE_STATUS_CODE])
    assert_operator(res_entry.payload[Keys::HTTP_RESPONSE_DURATION_MS], :>=, 0)
    # OBS-17: Location goes through the URL redactor; every other header value passes through.
    assert_equal("https://example.com/res/1?token=***", res_entry.payload["#{Keys::HTTP_RESPONSE_HEADER_PREFIX}location"])
  end

  test "OBS-20: sink error in contain does not fail request while meter error propagates" do
    bad_sink = Object.new
    def bad_sink.info? = true
    def bad_sink.info = raise(::IOError, "sink write failure")
    def bad_sink.warn? = true
    def bad_sink.warn = nil

    logger = Logger.build(sink: bad_sink)
    step = Step.build(logger: logger, redactor: Redactor::DEFAULT, level: HTTPLogging::HEADERS)

    req = build_request(url: "https://example.com/")
    cursor = FakeCursor.new(build_response(req))

    # Completes normally despite the sink throwing on every emission site. Asserted on the
    # returned response, never with assert_nothing_raised (testing/26b866e1).
    response = step.call(req, cursor)
    assert_equal(200, response.status.code)

    # Throwing meter propagates (OBS-20's asymmetry). This half is an assert_raises, and
    # writing it as "and nothing bad happens" is how the asymmetry gets quietly removed.
    throwing_meter = Object.new
    def throwing_meter.create_counter(*, **) = self
    def throwing_meter.create_histogram(*, **) = self
    def throwing_meter.add(*, **) = raise(::StandardError, "meter failure")
    def throwing_meter.record(*, **) = nil

    step_with_bad_meter = Step.build(
      logger: logger,
      redactor: Redactor::DEFAULT,
      level: HTTPLogging::NONE,
      meter: throwing_meter
    )

    assert_raises(::StandardError) do
      step_with_bad_meter.call(req, FakeCursor.new(build_response(req)))
    end
  end

  test "DEF-34: preview_bytes must be positive integer when level is BODY" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Step.build(
        logger: Logger::NULL,
        redactor: Redactor::DEFAULT,
        level: HTTPLogging::BODY,
        preview_bytes: nil
      )
    end
  end
end
```

Write `gems/dexpace-core/test/dexpace/instrumentation/async_step_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
require_relative "../../../lib/dexpace"

# Exercises: OBS-34, OBS-36, OBS-39, OBS-20, OBS-17
class AsyncStepTest < DexpaceTestCase
  AsyncStep = Dexpace::Instrumentation::AsyncStep
  HTTPLogging = Dexpace::Instrumentation::HTTPLogging
  RecordingSink = Dexpace::RecordingSink
  Logger = Dexpace::Instrumentation::Logger
  Redactor = Dexpace::Instrumentation::Redactor
  Keys = Dexpace::Instrumentation::Keys
  Events = Dexpace::Instrumentation::Events

  # Phase 2's shipped type, used rather than faked: Settlement is a public Data over exactly
  # (:response, :error, :cancelled), built through .success / .failure / .cancellation, whose
  # ONE predicate is #success? (== error.nil?). There is no #cancelled? -- the reader is
  # #cancelled, with no question mark -- and no #value and no #outcome; #outcome is on
  # Completer and RETURNS a Settlement. AsyncStep therefore branches on #success? alone.
  Settlement = Dexpace::Async::Settlement

  def build_request(url: "https://example.com/async")
    Dexpace::Request.build(method: "GET", url: url, headers: Dexpace::Headers::EMPTY, body: nil)
  end

  def build_response(request, status: 200)
    Dexpace::Response.build(request: request, protocol: Dexpace::Protocol::HTTP_1_1,
                            status: status, reason: nil,
                            headers: Dexpace::Headers::EMPTY, body: nil)
  end

  class FakeFuture
    attr_reader :settle_callback
    def on_settle(&block)
      @settle_callback = block
      self
    end
  end

  class FakeAsyncCursor
    attr_reader :future
    def initialize = (@future = FakeFuture.new)
    def call(_req) = @future
  end

  test "AsyncStep registers on_settle and emits response event upon success settlement" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)
    step = AsyncStep.build(logger: logger, redactor: Redactor::DEFAULT, level: HTTPLogging::HEADERS)

    req = build_request
    cursor = FakeAsyncCursor.new

    # Verified fact 13: Future offers #on_settle and no combinator, so the step registers a
    # callback and returns THE SAME future. No second future is created and PIPE's chain is
    # untouched.
    returned_future = step.call(req, cursor)
    assert_same(cursor.future, returned_future)
    assert_equal(1, sink.entries.size) # request event

    cursor.future.settle_callback.call(Settlement.success(build_response(req)))

    assert_equal(2, sink.entries.size)
    assert_equal(Events::HTTP_RESPONSE, sink.entries[1].payload[Keys::EVENT])
    assert_equal(200, sink.entries[1].payload[Keys::HTTP_RESPONSE_STATUS_CODE])
  end

  test "AsyncStep emits failure event upon error settlement" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)
    step = AsyncStep.build(logger: logger, redactor: Redactor::DEFAULT, level: HTTPLogging::HEADERS)

    req = build_request
    cursor = FakeAsyncCursor.new

    step.call(req, cursor)

    err = ::IOError.new("connection timeout")
    cursor.future.settle_callback.call(Settlement.failure(err))

    assert_equal(2, sink.entries.size)
    failure_entry = sink.entries[1]
    assert_equal(Events::HTTP_RESPONSE, failure_entry.payload[Keys::EVENT])
    assert_equal("IOError", failure_entry.payload[Keys::ERROR_TYPE])
    assert_equal("IOError: connection timeout", failure_entry.payload[Keys::CAUSE])
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/step_test.rb`
Expected: fails with `LoadError` loading `step.rb`.

- [ ] **Step 3: Write Emitter, Step, and AsyncStep implementations**

Write `gems/dexpace-core/lib/dexpace/instrumentation/emitter.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Phase 1's Dexpace::URL, and the path is http/url.rb -- the constant is flat under Dexpace
# but the FILE is under http/, checked against phase 1's module layout at reconciliation.
require_relative "../http/url"
require_relative "severity"
require_relative "keys"
require_relative "http_logging"
require_relative "preview"

module Dexpace
  module Instrumentation
    # OBS-17, OBS-39, P5-34: Private shared event emitter for sync and async steps. Two steps
    # sharing one policy OBJECT satisfy OBS-17's letter and drift the moment one grows a field
    # the other lacks; two steps sharing one Emitter -- which owns every logger.event(...) call
    # and every field key in the sub-phase -- cannot.
    class Emitter
      def emit_request(logger, redactor, request, level, _preview_bytes)
        ev = logger.event(Severity::INFO).event(Events::HTTP_REQUEST)
        # Request#method is a Dexpace::Method value object, not a String; #to_s is its token.
        ev.field(Keys::HTTP_REQUEST_METHOD, request.method.to_s)
        # Request#url is a frozen URI::Generic; URL.external_form is HTTP-46's sanctioned
        # string form. OBS-39's "url.full MUST always be the redacted URL" is discharged
        # structurally by Event#field's reserved-key table, not by redacting here.
        ev.field(Keys::URL_FULL, Dexpace::URL.external_form(request.url))

        emit_headers(ev, redactor, request.headers, Keys::HTTP_REQUEST_HEADER_PREFIX)

        body = request.body
        ev.field(Keys::HTTP_REQUEST_BODY_SIZE, body.content_length) if body&.content_length

        if level.at_least?(HTTPLogging::BODY) && body.respond_to?(:snapshot)
          # BODY-20: #snapshot is the bytes mirrored so far. #preview_bytes on the response
          # wrapper is the CAP, not the payload -- rendering it would log an Integer.
          ev.field(Keys::HTTP_REQUEST_BODY_PREVIEW,
                   Preview.render(body.snapshot, media_type: media_type_of(body)))
        end

        ev.emit
      end

      def emit_response(logger, redactor, _request, response, duration_ms, level, _preview_bytes)
        ev = logger.event(Severity::INFO).event(Events::HTTP_RESPONSE)
        # Response#status is a Dexpace::Status value object; #code is the Integer.
        ev.field(Keys::HTTP_RESPONSE_STATUS_CODE, response.status.code)
        ev.field(Keys::HTTP_RESPONSE_DURATION_MS, duration_ms)

        emit_headers(ev, redactor, response.headers, Keys::HTTP_RESPONSE_HEADER_PREFIX)

        body = response.body
        ev.field(Keys::HTTP_RESPONSE_BODY_SIZE, body.content_length) if body&.content_length

        if level.at_least?(HTTPLogging::BODY) && body.respond_to?(:snapshot)
          ev.field(Keys::HTTP_RESPONSE_BODY_PREVIEW,
                   Preview.render(body.snapshot, media_type: media_type_of(body)))
        end

        ev.emit
      end

      def emit_failure(logger, _redactor, _request, error, duration_ms)
        ev = logger.event(Severity::ERROR).event(Events::HTTP_RESPONSE)
        err_type = error.class.name || "Error"
        ev.field(Keys::ERROR_TYPE, err_type)
        ev.cause(error)
        ev.field(Keys::HTTP_RESPONSE_DURATION_MS, duration_ms) if duration_ms
        # OBS-39, and phase 4b's ProtocolError decision CONFIRMED and extended: no body and
        # no body preview is attached to a failure event at any level below BODY. A message
        # is what lands in a log by default, and an error body is the payload most likely to
        # carry a token.
        ev.emit
      end

      private

      # OBS-18 gates NAMES first: a header whose name is not allow-listed never reaches a
      # value redactor, because its value is not logged. OBS-17 then decides whether the
      # value goes through the URL redactor, which Event#field's reserved-key table does by
      # matching the prefix -- so this method passes the raw value and does not redact.
      # Headers has no #each; #each_entry yields frozen [name, value] pairs, one per value,
      # and the name it yields is the ORIGINAL casing, so it is folded for the gate.
      # OBS-38 is charset-aware for text, and the charset lives on the body's media type.
      # Phase 3b's two wrappers delegate to a body that may or may not carry one; MediaType
      # already returns nil for an absent or unrecognised charset and never raises, and
      # Preview.render treats an absent media type as binary, which is the safe direction.
      def media_type_of(body)
        body.respond_to?(:media_type) ? body.media_type : nil
      end

      def emit_headers(event, redactor, headers, prefix)
        return if headers.nil?

        headers.each_entry do |(name, value)|
          folded = name.downcase
          next unless redactor.header_name?(folded)

          event.field("#{prefix}#{folded}", value)
        end
      end
    end
    private_constant :Emitter
  end
end
```

Write `gems/dexpace-core/lib/dexpace/instrumentation/step.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../pipeline/stages"
require_relative "../clock"
require_relative "../error/invalid_argument_error"
require_relative "../http/body/request_logging_body"
require_relative "../http/body/response_logging_body"
require_relative "keys"
require_relative "http_logging"
require_relative "contain"
require_relative "emitter"
# 4a's, all three checked against 4a's own module layout at reconciliation rather than
# inferred: NO_TRACER_FACTORY and NO_TRACER both live in no_tracer.rb -- there is NO
# no_tracer_factory.rb -- and Bundle::NONE is in bundle.rb.
require_relative "no_tracer"
require_relative "bundle"
# 5c's NO_METER and Tracing.correlate. Cross-segment: 5b calls, 5c declares (R11, settled).
# The paths are 5c's Module layout, checked at reconciliation and not inferred from the
# constant names: NO_METER lives in meter.rb, NOT no_meter.rb. Tracing is tracing.rb.
require_relative "meter"
require_relative "tracing"

module Dexpace
  module Instrumentation
    # OBS-34, OBS-36, OBS-39, OBS-20: HTTP instrumentation pipeline step at Stages::LOGGING.
    class Step
      private_class_method :new

      attr_reader :stage

      # P5-33, R11, charter boundary 10: the two slots default to the constants the phase
      # already ships -- Instrumentation::NO_TRACER_FACTORY is PHASE 4a's and
      # Instrumentation::NO_METER is 5c's. 5b defines NEITHER. "Neither segment ships a
      # second step, a second diagnostic-context key-name constant, or a second no-op meter"
      # is the boundary, and a locally-defined fallback would be exactly that second no-op,
      # NFR-4-locked under a name P5-16 does not carry. There is no `# PENDING 5c` here and
      # the plan must not reintroduce one.
      def self.build(
        logger:,
        redactor:,
        level:,
        tracer_factory: Instrumentation::NO_TRACER_FACTORY,
        meter: Instrumentation::NO_METER,
        preview_bytes: nil,
        clock: Clock::SYSTEM
      )
        # Open question 5, decided: NO 8 KiB fallback lives in this signature. OBS-36's
        # "reference default 8 KiB" is a figure a CALLER resolves and passes; baking it into
        # an NFR-4-locked default would be a memory bound nobody chose, and P5-36 is the
        # precedent (the key is passed, never baked in).
        if level.at_least?(HTTPLogging::BODY)
          unless preview_bytes.is_a?(::Integer) && preview_bytes.positive?
            raise InvalidArgumentError, "preview_bytes is required"
          end
        end

        counter = meter.create_counter(Keys::INSTRUMENT_REQUEST_COUNT)
        histogram = meter.create_histogram(Keys::INSTRUMENT_REQUEST_DURATION)

        new(logger, redactor, level, tracer_factory, counter, histogram, preview_bytes, clock).freeze
      end

      def initialize(logger, redactor, level, tracer_factory, counter, histogram, preview_bytes, clock)
        @logger          = logger
        @redactor        = redactor
        @level           = level
        @tracer_factory  = tracer_factory
        @counter         = counter
        @histogram       = histogram
        @preview_bytes   = preview_bytes
        @clock           = clock
        @emitter         = Emitter.new
        @stage           = Pipeline::Stages::LOGGING
      end

      def call(request, cursor)
        started = @clock.monotonic
        op_name = operation_name_for(request)
        factory = tracer_factory_for(request)
        tracer = factory.tracer(op_name)
        span = tracer.start_span(op_name)
        scope = correlate_span(span, request)

        logged = @level.at_least?(HTTPLogging::HEADERS)
        request = wrap_request_body(request) if @level.at_least?(HTTPLogging::BODY)

        if logged
          Instrumentation.contain(@logger, event: Events::INSTRUMENTATION_LOG) do
            @emitter.emit_request(@logger, @redactor, request, @level, @preview_bytes)
          end
        end

        response = cursor.call(request)
        response = wrap_response_body(response) if @level.at_least?(HTTPLogging::BODY)

        duration_ms = (@clock.monotonic - started) * 1000.0
        if logged
          Instrumentation.contain(@logger, event: Events::INSTRUMENTATION_LOG) do
            @emitter.emit_response(@logger, @redactor, request, response, duration_ms, @level, @preview_bytes)
          end
        end

        response
      rescue ::StandardError => e
        duration_ms = (@clock.monotonic - started) * 1000.0
        if logged
          Instrumentation.contain(@logger, event: Events::INSTRUMENTATION_LOG) do
            @emitter.emit_failure(@logger, @redactor, request, e, duration_ms)
          end
        end
        raise
      ensure
        scope&.close
        span&.finish
        # OBS-20, OBS-30: Tracer and meter calls MUST NOT be defensively contained; throwing will propagate.
        # OBS-31 makes attributes: an OPTIONAL keyword on both instruments -- the MUST is that the
        # instrument ACCEPT per-measurement attributes, not that every caller supply them -- and 5b
        # supplies none: no OBS requirement fixes an attribute set for these two instruments (OBS-32's
        # semantic conventions are DEF-9's), and 5c's verified fact 1 measures an inline hash literal at
        # a call site at ~1 allocation per call whether or not the callee splats. When DEF-9 lands, the
        # set is hoisted to a frozen constant and passed; the signature does not change.
        @counter.add(1)
        @histogram.record((@clock.monotonic - started) * 1000.0)
      end

      private

      # OI-31, and it is stated rather than papered over. Phase 4c is explicit that
      # "4c does not consume 4a at all": Cursor's whole surface is #call, #fork, #may_fork?,
      # #request, #options, #cancellation, #state(stage) and #spent?; Dexpace::Request's
      # members are (:method, :url, :headers, :body); RequestOptions' are (:timeout,
      # :max_retries, :tags). There is NO reader by which a step reaches a RequestContext or
      # an Instrumentation::Bundle, PIPE-11 forbids reading one from ambient storage, and
      # CTX-11's ContextStore is not a back door (the step holds no call key, and CTX-13 lets
      # it evict any entry). So the FIRST clause of the reconciled precedence is not
      # implementable in phase 5 and these three helpers resolve to the step's own keyword and
      # to Bundle::NONE -- exactly the default configuration OBS-34 and XCUT-19(e) describe,
      # which is why OBS-34's conformance clause is unaffected. Phase 6 closes it, by widening
      # Cursor or by having Pipeline.standard (DEF-39) thread a bundle in; bundle_for is then
      # the one method that changes and no signature moves. The respond_to? probes stay,
      # because they are what makes that later change a one-method edit.
      def bundle_for(request)
        return nil unless request.respond_to?(:context)

        context = request.context
        context.respond_to?(:bundle) ? context.bundle : nil
      end

      def operation_name_for(request)
        # 4a: RequestContext#operation_name is "already carried and already advisory".
        context = request.respond_to?(:context) ? request.context : nil
        name = context.respond_to?(:operation_name) ? context.operation_name : nil
        name || Events::HTTP_REQUEST
      end

      # 5c's precedence, implemented and not contradicted: the request context's bundle when
      # it is not Bundle::NONE, else the step's keyword, else the constant (which IS the
      # keyword's default).
      def tracer_factory_for(request)
        bundle = bundle_for(request)
        return @tracer_factory if bundle.nil? || bundle.equal?(Bundle::NONE)

        bundle.tracer_factory || @tracer_factory
      end

      # 5c's scope handle. Tracing.correlate pushes Diagnostics::TRACE_ID and ::SPAN_ID for a
      # recording span and delegates to plain activation for a non-recording one, so one call
      # covers both branches and this step needs no test on the recording flag. Called
      # directly, never feature-probed: R11 settles the name.
      def correlate_span(span, request)
        Tracing.correlate(span, bundle_for(request) || Bundle::NONE)
      end

      # DEF-34, OBS-36: the only place in core that constructs either wrapper, which is what
      # makes BODY-34's "engaged only when body-level logging is enabled" structurally true.
      # 3b's over-cap regime already replays the prefix and continues from the live tail, so
      # 5b writes no streaming code -- it supplies the cap and the gate.
      def wrap_request_body(request)
        return request if request.body.nil?

        request.with(body: RequestLoggingBody.new(request.body, tap_limit: @preview_bytes))
      end

      def wrap_response_body(response)
        return response if response.body.nil?

        response.with(body: ResponseLoggingBody.new(response.body, preview_bytes: @preview_bytes))
      end
    end
  end
end
```

Write `gems/dexpace-core/lib/dexpace/instrumentation/async_step.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "step"

module Dexpace
  module Instrumentation
    # OBS-34, OBS-36, OBS-39, OBS-20: Async HTTP instrumentation pipeline step at Stages::LOGGING.
    # P5-34: two steps over one private_constant Emitter, which is what makes OBS-17's
    # "shared ... so it cannot drift" structural rather than a promise. Subclassing inherits
    # .build unchanged, so both steps take the same keywords by construction; `new` stays
    # private, because class-method visibility is inherited through the singleton chain.
    class AsyncStep < Step
      def call(request, cursor)
        started = @clock.monotonic
        op_name = operation_name_for(request)
        factory = tracer_factory_for(request)
        tracer = factory.tracer(op_name)
        span = tracer.start_span(op_name)
        scope = correlate_span(span, request)

        logged = @level.at_least?(HTTPLogging::HEADERS)
        request = wrap_request_body(request) if @level.at_least?(HTTPLogging::BODY)

        if logged
          Instrumentation.contain(@logger, event: Events::INSTRUMENTATION_LOG) do
            @emitter.emit_request(@logger, @redactor, request, @level, @preview_bytes)
          end
        end

        future = cursor.call(request)

        future.on_settle do |settlement|
          duration_ms = (@clock.monotonic - started) * 1000.0
          begin
            if settlement.success?
              response = settlement.response
              response = wrap_response_body(response) if @level.at_least?(HTTPLogging::BODY)
              if logged
                Instrumentation.contain(@logger, event: Events::INSTRUMENTATION_LOG) do
                  @emitter.emit_response(@logger, @redactor, request, response, duration_ms, @level, @preview_bytes)
                end
              end
            else
              error = settlement.error || settlement
              if logged
                Instrumentation.contain(@logger, event: Events::INSTRUMENTATION_LOG) do
                  @emitter.emit_failure(@logger, @redactor, request, error, duration_ms)
                end
              end
            end
          ensure
            scope&.close if scope.respond_to?(:close)
            span&.finish if span.respond_to?(:finish)
            # OBS-20: Meter throwing on settling thread propagates to settling context
            @counter.add(1)
            @histogram.record(duration_ms)
          end
        end

        future
      end
    end
  end
end
```

- [ ] **Step 4: Write RBS signatures**

Write `gems/dexpace-core/sig/dexpace/instrumentation/step.rbs`:
```rbs
module Dexpace
  module Instrumentation
    class Step
      attr_reader stage: Pipeline::Stage

      def self.build: (
        logger: Logger,
        redactor: Redactor,
        level: HTTPLogging,
        ?tracer_factory: _TracerFactory,
        ?meter: _Meter,
        ?preview_bytes: Integer?,
        ?clock: Clock
      ) -> Step

      def call: (untyped request, untyped cursor) -> untyped
    end
  end
end
```

Both signatures are written inside `module Dexpace; module Instrumentation`, so `_TracerFactory`
(4a's, five parameters) and `_Meter` (`5c`'s, filled) are reached by bare name. **5b declares
neither, nor `_Counter` or `_Histogram`** — two declarations of one interface name is an
`rbs validate` failure, not a merge conflict — and typing them `untyped` instead would put the two
slots outside `NFR-11`'s scan for no gain, since both interfaces exist in the same gem.

Write `gems/dexpace-core/sig/dexpace/instrumentation/async_step.rbs`:
```rbs
module Dexpace
  module Instrumentation
    class AsyncStep < Step
      def self.build: (
        logger: Logger,
        redactor: Redactor,
        level: HTTPLogging,
        ?tracer_factory: _TracerFactory,
        ?meter: _Meter,
        ?preview_bytes: Integer?,
        ?clock: Clock
      ) -> AsyncStep

      def call: (untyped request, untyped cursor) -> untyped
    end
  end
end
```

- [ ] **Step 5: Run tests to confirm they pass**

Run:
`bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/step_test.rb`
`bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/async_step_test.rb`
Expected: 4 runs and 2 runs, 0 failures, 0 errors, 0 skips.

---
## Task 16: Final Wiring, Surface Manifest, RBS Baseline, Checklist, and Register Edits

**Requirement IDs:** `OBS-1`–`OBS-20`, `OBS-24`, `OBS-34`–`OBS-40`, `NFR-4`, `NFR-11`, `NFR-13`.
**Design:** "Module layout", "The interface surface later phases may cite", "Deviation Ledger".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Update: **repository-root** `test/fixtures/surface/dexpace-core.txt` (the manifest lives beside
  `test/support/dexpace_test_case.rb` at the root, not inside the gem)
- Create: `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-checklist.md`
- Modify: `docs/deferred-items.md` (`DEF-27`, `DEF-34`, `DEF-31`)
- Read-only: `docs/deferred-items.md` (`DEF-41`), `docs/open-items.md` (`OI-25`, `OI-26`, `OI-27`, `OI-30`, `OI-31`)
- Test: `gems/dexpace-core/test/dexpace/instrumentation/final_wiring_test.rb`

- [ ] **Step 1: Write the final wiring verification test**

Write `gems/dexpace-core/test/dexpace/instrumentation/final_wiring_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace"

class FinalWiringTest < DexpaceTestCase
  test "all public Phase 5b constants are defined and exported" do
    inst = Dexpace::Instrumentation
    assert(defined?(inst::Severity))
    assert(defined?(inst::Keys))
    assert(defined?(inst::Events))
    assert(defined?(inst::NULL_SINK))
    assert(defined?(inst::Event))
    assert(defined?(inst::Event::INERT))
    assert(defined?(inst::Logger))
    assert(defined?(inst::Logger::NULL))
    assert(defined?(inst::Diagnostics))
    assert(defined?(inst::Diagnostics::TRACE_ID))
    assert(defined?(inst::Diagnostics::SPAN_ID))
    assert(defined?(inst::Diagnostics::DEFAULT_KEYS))
    assert(defined?(inst::RedactionPolicy))
    assert(defined?(inst::RedactionPolicy::DEFAULT))
    assert(defined?(inst::Redactor))
    assert(defined?(inst::Redactor::DEFAULT))
    assert(defined?(inst::Preview))
    assert(defined?(inst::HTTPLogging))
    assert(defined?(inst::Step))
    assert(defined?(inst::AsyncStep))
  end
end
```

- [ ] **Step 2: Update `lib/dexpace.rb` with explicit require order**

Add to `gems/dexpace-core/lib/dexpace.rb`:
```ruby
require_relative "dexpace/instrumentation/severity"
require_relative "dexpace/instrumentation/keys"
require_relative "dexpace/instrumentation/null_sink"
require_relative "dexpace/instrumentation/render"
require_relative "dexpace/instrumentation/diagnostics"
require_relative "dexpace/instrumentation/redaction_policy"
require_relative "dexpace/instrumentation/redactor"
require_relative "dexpace/instrumentation/event"
require_relative "dexpace/instrumentation/logger"
require_relative "dexpace/instrumentation/contain"
require_relative "dexpace/instrumentation/preview"
require_relative "dexpace/instrumentation/http_logging"
require_relative "dexpace/instrumentation/emitter"
require_relative "dexpace/instrumentation/step"
require_relative "dexpace/instrumentation/async_step"
```

Two things about this list, because both are the kind of thing a later reader re-derives.

**The order is the dependency order and is not arbitrary.** `event.rb` requires `keys`, `render`,
`diagnostics` and `redactor`, all of which precede it; `logger.rb` requires `severity`, `null_sink`,
`diagnostics`, `redactor` and `event`; `contain.rb` requires `severity`; `emitter.rb` requires
`keys`, `http_logging` and `preview`; `step.rb` requires `http_logging`, `contain` and `emitter`.
`lib/dexpace.rb` issues explicit requires for the whole tree rather than using an autoloader, because
every autoloader worth using is a gem — which also makes the require audit a text scan.

**Task 14's four modified files pull part of this tree in ahead of this list, and that is not a
cycle.** `closeable.rb` and `hooks.rb` now `require_relative "instrumentation/logger"`, and
`lib/dexpace.rb` requires `closeable` early. Nothing in the instrumentation tree requires `closeable`,
`hooks` or `proxy/resolution`, so the graph stays acyclic; `require_relative` is idempotent, so the
entries above are a declaration of intent rather than the thing that first loads them. Do not
"fix" the apparent redundancy by deleting either side.

- [ ] **Step 3: Regenerate surface snapshot and validate RBS**

Execute commands:
```bash
bundle exec rake surface:regenerate
bundle exec rbs validate
bundle exec steep check
bundle exec rubocop
```

- [ ] **Step 4: Update deferred items and open items registers**

**Never renumber an item ID and never reuse one, and file nothing that is already filed.** Both
phase-4 plans re-filed rows the design had already appended, which is the failure this step is
worded to prevent: `DEF-41`, `OI-25`, `OI-26`, `OI-27` and `OI-30` are **already in the registers**,
appended by the pass that reconciled 5b's design with `5c`'s, and `OI-31` by the pass that reconciled the
two **plans**. They are **verified, never re-filed**.
Derive the counts, never write them:
`ruby .claude/skills/housekeeping/probe.rb --only citations`.

1. In `docs/deferred-items.md` — three edits, and no new row:
   - `DEF-27`: `Status` moves to `picked-up`. The row's own pick-up condition names phase 5
     explicitly ("phase 5 supplies the second with §8.1's facade and **closes this row**"), and the
     second disposal route now exists: `close_quietly`'s `onto:`-absent branch routes through
     `Instrumentation.contain` with `Events::INSTRUMENTATION_CLOSE`. The `onto:` route, the
     suppressed trail and `CFG-21`'s null-safety are untouched.
   - `DEF-34`: `Status` moves to `picked-up`. `5a` supplied the third wiring and deliberately did
     not edit the row; **5b lands second and edits it**, having supplied the other two — the shared
     preview size read into both phase-3b wrappers, and the gating of their construction on
     `HTTPLogging::BODY`.
   - `DEF-31`: append a **dated line to `Status` only**. 5b ships `Events::INSTRUMENTATION_SHUTDOWN`
     and the field shape; it does **not** move the row to `picked-up`, because the first thing in
     this repository that owns an executor is phase 8's `dexpace-async-thread`.
2. Verify, and change nothing:
   - `docs/deferred-items.md`: `DEF-41` (`OBS-19`'s header-drop verbosity policy, target phase 8) is
     present. `DEF-9` is untouched and is cited by `OBS-37`'s ⏳ row.
   - `docs/open-items.md`: `OI-25` (`Event#tag` named by §8.1 and by no requirement), `OI-26`
     (`Dexpace/QualifiedCoreConstant` cannot carry `Logger`), `OI-27` (the charter's 5b scope table
     versus its own `R10`), `OI-30` (`OBS-24` assigned to 5b in prose and to `5c` in arithmetic) and
     `OI-31` (the step's slot precedence names a context bundle a pipeline step cannot reach) are all
     present. **`OI-30` is the one this plan depends on**: `OBS-24` is 5b's, it has a row in
     the requirement map below, and Task 6 implements it. **`OI-31` is the one Task 15 is written
     around**: it is what open question 7 resolves to, and `Step#bundle_for`'s comment cites it.
3. `P5-39` stays an **unused gap**. It was reserved by the design and never needed; nothing is
   renumbered to close it, and no task may claim it.

- [ ] **Step 5: Write the sub-phase checklist**

Write `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-checklist.md`: **one row
per requirement ID in scope**, naming for each the numbered task that satisfies it, or recording it as
a deferral (`DEF-<n>`) or a deviation. All 28 — `OBS-1`–`OBS-20`, `OBS-24`, `OBS-34`–`OBS-40` — plus the
non-ID obligations (`DEF-27`, `DEF-31`, `DEF-32`, `DEF-34`, `P5-8`) and the ✅ / 🚫 / ⏳ / N/A legend the
roadmap fixes. The requirement map in *Self-review against the design* below is the source; the
checklist is the shipped artefact, and a requirement in scope with no row is the failure this
project's conventions exist to prevent.

- [ ] **Step 6: Run full test suite and confirm green**

Execute:
```bash
(cd gems/dexpace-core && bundle exec rake test)
bundle exec rake
```

Then, if Task 1's two interpreters installed, run the gem's suite on each row of the matrix — a
syntax check is not a substitute, because `TargetRubyVersion` catches syntax and not stdlib
availability (§9.2):

```bash
for v in 3.2.11 3.4.10 4.0.6; do
  mise exec ruby@$v -- bundle exec rake test
done
```

---
## Self-review against the design

### What was run, and what was not

Stated first, because a plan that implies more verification than it performed is the failure this
section exists to prevent.

- **Run.** Every Ruby fence in this document was extracted and parsed with `ruby -c` and with
  `ruby -w -c`: 39 fences, zero syntax errors, zero parse-time warnings. The thirteen
  implementation/test pairs that stand alone — `Severity`, `Keys`/`Events`, `NULL_SINK`, `Render`,
  `RecordingSink`/`DiagnosticContext`, `Diagnostics`, `RedactionPolicy`, `Redactor`, `Event`,
  `Logger`, `contain`, `Preview`, `HTTPLogging`, plus the matrix-facts suite — were then **executed**
  against a harness supplying `Dexpace::Model`, `Dexpace::InvalidArgumentError` and a
  `DexpaceTestCase` that prepends the real `FatalWarnings` to `Warning.singleton_class`: **63 runs,
  341 assertions, 0 failures, 0 errors**, on Ruby 3.4.10 under `-w`. The declared "Expected: N runs"
  line under each task was checked against the actual `test` block count in that task's fence.
- **Not run.** Tasks 14, 15 and 16 depend on phases 1–4 and on `5c`, none of which exists as code, so
  their fences are parsed and reviewed against the shipped API spellings in those phases' documents
  and **not executed**. The `3.2.11` and `4.0.6` matrix columns are **not run** — see open question 1
  and Task 1, which instruct a worker to run them and record the result; only 3.4.10 is installed.
- **Re-run at the 5b/5c plan reconciliation, 2026-09-09.** The pass that reconciled this plan with
  `5c`'s changed fences in Tasks 1, 3, 9, 11, 14, 15 and 16, so the `63 runs, 341 assertions` figure
  above is the **pre-reconciliation** measurement and is not re-claimed for the changed suites. What
  was re-run: all 39 Ruby fences re-parsed under `ruby -w -c`, **0 errors**; Task 3's `Keys`/`Events`
  pair re-executed with the new fifteenth constant, **2 runs, 79 assertions, 0 failures**; and Task
  15's corrected assertions executed against `5c`'s three test-support fences extracted verbatim from
  its plan — `factory.tracers`, `span.finished_at`, `meter.counters`/`#histograms` and the
  `{amount:, attributes:}` record shape — **4 runs, 21 assertions, 0 failures**, which is also what
  proved all four of the draft's guesses wrong rather than only asserting the fix. Tasks 14, 15 and 16
  still depend on phases 1–4 and remain unexecuted end to end.
- **Checked by hand against the owning phase's document, because a wrong spelling here raises on
  first call:** `Request#method` is a `Dexpace::Method` (`#to_s` is its token) and `#url` is a frozen
  `URI::Generic` reached as a `String` through `Dexpace::URL.external_form`; `Response#status` is a
  `Dexpace::Status` and the integer is `#code`; `Headers` has **no `#each`** — `#each_entry` yields
  frozen `[name, value]` pairs; `Body#content_length`, not `#size`; `ResponseLoggingBody#preview_bytes`
  is the **cap**, and the captured bytes are `#snapshot`; `Dexpace.attach_suppressed(primary,
  secondary)` is a module function and there is no `#add_suppressed`; `Settlement`'s one predicate is
  `#success?` and its reader is `#cancelled`, no question mark; `Configuration::Keys::LOG_LEVEL` is
  `"LOG_LEVEL"` and is `5a`'s, not 5b's to revalue; `Dexpace::Proxy.resolve` takes an optional
  positional configuration and `ProxyResolution` is a `private_constant` with no `resolve_from_env`.

### What 5b consumes from `5c`, confirmed at the reconciliation pass

**These were guesses when this plan was written and are now checked against `5c`'s own fences.** A sibling
pass owns the `5c` plan; 5b names what it consumes and changes no `5c` file. Every row below was verified
against `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics.md` on 2026-09-09, and where the
guess was wrong this plan was corrected — not `5c`.

| What 5b uses | Where | Confirmed shape |
|---|---|---|
| `Dexpace::Instrumentation::NO_METER` | `Step.build`'s `meter:` default (`P5-33`) | Confirmed. A public frozen constant `5c` ships in **`lib/dexpace/instrumentation/meter.rb`** — not `no_meter.rb`, which was 5b's guess from the constant name and is corrected in `step.rb`'s `require_relative` |
| `Dexpace::Instrumentation::Tracing.correlate(span, bundle) -> scope` and `Scope#close` | `Step#call`, `AsyncStep#on_settle` | Confirmed, in `lib/dexpace/instrumentation/tracing.rb`. `correlate` pushes `Diagnostics::TRACE_ID`/`::SPAN_ID` for a recording span and delegates to plain activation otherwise, so 5b needs no test on the recording flag. **5b uses the handle form on both paths** — `5c`'s design said the block form is "what `5b`'s sync step calls" and that sentence was corrected at reconciliation: `Step#call` already owns the `ensure` the block would duplicate, and `AsyncStep < Step` shares one `correlate_span` helper. Both forms ship; `P5-45` is not reopened |
| `_Tracer#start_span(name)`, `_Span#finish` | `Step#call` | Confirmed. 4a's `_TracerFactory#tracer` is separate, keeps its five parameters, and is settled |
| `_Meter#create_counter(name)` / `#create_histogram(name)`, `_Counter#add(amount, attributes: nil)`, `_Histogram#record(amount, attributes: nil)` | `Step.build`, `Step#call`'s `ensure` | Confirmed, and **`attributes:` is optional on both**. `OBS-31`'s MUST is that the instrument *accept* per-measurement attributes; nothing requires a caller to pass them, and no `OBS` requirement fixes an attribute set for these two instruments (`OBS-32`'s conventions are ⏳ `DEF-9`). 5b passes none and says so at the `ensure`. Instruments are manufactured **once in `.build`**, not per request (`OBS-31`, `OBS-25`) |
| `test/support/recording_tracer.rb`, `recording_span.rb`, `recording_meter.rb` (`P5-48`) | `step_test.rb` | **Four of 5b's guesses were wrong and are fixed in Task 15.** `5c` ships a separate top-level `Dexpace::RecordingTracerFactory`, not `RecordingTracer::Factory`; the factory logs what it made in `#tracers`, so calling `#tracer` again would manufacture a second one; `RecordingSpan` has no `#finished?` — it latches into `#finished_at`, an `Array`; and `RecordingMeter` exposes `#counters` / `#histograms` (Arrays in creation order) with no by-name lookup, each element a `RecordingCounter`/`RecordingHistogram` whose `#records` entries are `{amount:, attributes:}`. All six constants are flat under `Dexpace`. **`RecordingCounter` and `RecordingHistogram` are `5c`'s and 5b declares neither**; 5b adds no second set (`DEF-29`) |
| `interface _Meter`, `_Counter`, `_Histogram` | `step.rbs`, `async_step.rbs` | Confirmed: declared **filled** by `5c`, in `sig/dexpace/instrumentation/meter.rbs`, and **exactly once across the two plans** — two declarations of one interface name is an `rbs validate` failure. 5b declares none and now *types against* them by bare name (`?meter: _Meter`) rather than `untyped`, since both signatures are written inside `module Instrumentation` |
| File paths `instrumentation/meter.rb` and `instrumentation/tracing.rb` | `step.rb`'s `require_relative`s | Checked against `5c`'s *Module layout*. `tracing.rb` was right; `no_meter.rb` was wrong and is now `meter.rb` |
| File paths `instrumentation/no_tracer.rb` and `instrumentation/bundle.rb` | `step.rb`'s `require_relative`s | **Phase 4a's, not `5c`'s, and a fifth guessed path found at reconciliation.** 4a's module layout puts `NO_TRACER_FACTORY` *and* `NO_TRACER` in `no_tracer.rb`; there is no `no_tracer_factory.rb`. `bundle.rb` was not required at all and now is, because `Step` names `Bundle::NONE` |
| File path `http/url.rb` | `emitter.rb`'s `require_relative` | **Phase 1's, and the sixth.** `Dexpace::URL` is a flat constant but its file is under `http/`, so the require is `../http/url` and not `../url`. Every other cross-phase path in this plan was checked the same way and is right: `../clock`, `../model`, `../error/invalid_argument_error`, `../pipeline/stages`, `../http/body/request_logging_body` and `../http/body/response_logging_body` |
| `Dexpace::Instrumentation::Bundle::NONE` | `Step`'s `tracer_factory_for`, `correlate_span` | Phase 4a's, not `5c`'s. `step.rb` now requires `bundle` explicitly rather than relying on another file having pulled it in |

**The one thing that did not reconcile, and it is filed rather than papered over.** `5c`'s precedence rule
gives the context's bundle priority over the step's keyword, and **no channel exists by which the step reaches
a bundle**. See open question 7 and `OI-31`. The degradation is safe, `OBS-34`'s conformance clause is
unaffected, and phase 6 is named as the closer.

### Requirement ID Mapping

Twenty-eight requirement IDs: **26 ✅ Implemented, 2 ⏳ Deferred (`OBS-19`, `OBS-37`)**, matching the design scope table exactly.

| Requirement ID | Level | Disposition / Task | Summary |
|---|---|---|---|
| `OBS-1` | MUST | ✅ Tasks 4, 9, 10 | Allocation-free disabled logging returning shared `Event::INERT` singleton |
| `OBS-2` | MUST | ✅ Tasks 2, 4, 10 | Exactly 4 severity levels (ERROR, WARNING, INFO, VERBOSE) mapped to backend methods |
| `OBS-3` | MUST | ✅ Task 9 | Empty key rejected with error; null value emitted as literal `"null"` |
| `OBS-4` | MUST | ✅ Tasks 3, 9 | `event(name)` categorisation tag; empty name clears; suppresses duplicate `event` keys |
| `OBS-5` | MUST | ✅ Task 9 | Merging precedence: per-event field > global context > diagnostic context |
| `OBS-6` | MUST | ✅ Tasks 5, 9 | Total rendering: `SimpleClassName: message` exception format, bracketed collections, unrenderable fallback |
| `OBS-7` | SHOULD | ✅ Tasks 5, 9 | Bounded maximum value length (8 KiB) measured in bytes via `#byteslice` + `#scrub` + marker |
| `OBS-8` | MUST | ✅ Task 9 | Emit at most once guard; thread-safe with mutex released before sink call |
| `OBS-9` | MUST | ✅ Tasks 9, 10 | Global context referenced on every event without deep copying |
| `OBS-10` | MUST | ✅ Tasks 6, 9, 10 | Diagnostic context folding: `{trace.id, span.id}` default; nil allow-list folds all; null values skipped |
| `OBS-11` | MUST | ✅ Tasks 8, 9 | URL userinfo unconditionally redacted to `***:***@` placeholder |
| `OBS-12` | MUST | ✅ Tasks 7, 8, 9 | Query parameter redaction: `{api-version}` allow-list; multi-value atomicity |
| `OBS-13` | MUST | ✅ Tasks 8, 9 | Fragment key-value pairs redacted like query; plain fragment without `=` preserved |
| `OBS-14` | MUST | ✅ Tasks 8, 9 | Preserves scheme, host, port, path; trailing `?` preserved; no spurious `?` before `#` |
| `OBS-15` | MUST | ✅ Task 8 | Total URL redaction: returns `[malformed url]` sentinel on any failure, never throws |
| `OBS-16` | MUST | ✅ Tasks 8, 9 | Header URL redaction: relative and unparseable paths preserve path and append `?***` |
| `OBS-17` | MUST | ✅ Tasks 7, 8, 15 | Redaction policy shared by sync and async paths via `Emitter`; `Location` and `Content-Location` redacted |
| `OBS-18` | MUST | ✅ Tasks 7, 8, 9 | Diagnostic non-credential header allow-list (26 names); disallowed headers redacted with `REDACTED` |
| `OBS-19` | SHOULD | ⏳ **DEF-41** (Task 16) | Header-drop verbosity policy deferred to Phase 8 transport adapters (`R10`, `P5-32`) |
| `OBS-20` | MUST | ✅ Tasks 11, 14, 15 | Error containment at all log emission sites; diagnostics emitted; secondary errors swallowed |
| `OBS-24` | MUST | ✅ Task 6 | Immutable context snapshot (`Fiber.current.storage`) and union restoration across threads |
| `OBS-34` | MUST | ✅ Tasks 13, 15 | Granularity levels (none, headers, body); at none, tracing/metrics run while logs silenced |
| `OBS-35` | SHOULD | ✅ Task 13 | Tolerant level parsing; layered configuration resolution requires explicit key keyword |
| `OBS-36` | MUST | ✅ Task 15 | Request and response body preview capture engaged only at body level (`DEF-34`) |
| `OBS-37` | SHOULD | ⏳ **DEF-9** | Async streaming body preview skip deferred post-v1 with async adapters |
| `OBS-38` | SHOULD | ✅ Tasks 12, 15 | Charset-aware preview decoding for text and `[binary N bytes captured]` for non-text |
| `OBS-39` | MUST | ✅ Tasks 3, 9, 15 | Stable event (`http.request`, `http.response`) and field vocabulary; `url.full` always redacted |
| `OBS-40` | SHOULD | ✅ Tasks 9, 10 | Collision diagnostic: warns once at verbose when per-event field collides with event tag |

### The non-`OBS` obligations 5b carries without owning a new ID

| Obligation | Where | Note |
|---|---|---|
| `XCUT-19` — default-deny redaction | Tasks 7, 8, 13 | Default sets: `{api-version}`, 26 headers, level `none`. Userinfo cannot be allow-listed |
| `XCUT-20` — total error containment | Tasks 8, 11 | `contain`, `MALFORMED_URL`, and never-throw preview decode ensure logging never breaks caller |
| `XCUT-11` — thread-safe shared instances | Tasks 7, 8 | `Redactor` and `RedactionPolicy` are frozen with no mutable per-call state |
| `DEF-27` — `close_quietly` diagnostic | Task 14 | Closed. Routes onto-absent through `contain` emitting `INSTRUMENTATION_CLOSE` |
| `DEF-31` — lifecycle shutdown event | Task 3, 16 | Half supplied: `Events::INSTRUMENTATION_SHUTDOWN` constant shipped; row stays open for Phase 8 |
| `DEF-32` — hook failure diagnostic | Task 14 | Option taken: secondary hook errors emitted as `INSTRUMENTATION_HOOK` diagnostics |
| `DEF-34` — preview body cap wirings | Tasks 14, 15 | Picked up: `preview_bytes` cap gated at `HTTPLogging::BODY`; keys declared in `Configuration::Keys` |
| `DEF-41` — `OBS-19` header-drop policy | Task 16 | Filed by Phase 5b design, target Phase 8 |
| `DEF-9` — `OBS-37` async preview skip | — | Untouched; post-v1 with async adapters |
| `OI-25`, `OI-26`, `OI-27`, `OI-30`, `OI-31` | Tasks 15, 16 | **Already filed** — the first four by the design reconciliation, `OI-31` by the plan reconciliation; Task 16 verifies them and re-files nothing. `OI-30` is one this plan rests on: it records that the charter assigns `OBS-24` to 5b in prose and to `5c` in arithmetic, and the design resolves it to 5b — which is why `OBS-24` has a row above and Task 6 implements it. `OI-31` is the other: the step's slot precedence names a context bundle no pipeline step can reach, so its first clause degrades to the keyword and to `Bundle::NONE`, which is `OBS-34`'s own default configuration and leaves its conformance clause unaffected |
| `P5-39` | — | A deliberate, **unused** gap in the ledger. No task claims it and nothing is renumbered to close it |
| `DEF-29` | Tasks 1, 15 | Untouched. 5b adds exactly **two** doubles, `RecordingSink` and `DiagnosticContext`; the recording tracer, span and meter are `5c`'s and are consumed, not duplicated (`P5-48`) |

### Deviation Ledger Mapping

Twenty-three deviations: `P5-16` through `P5-38` (`P5-39` is a deliberate gap).

| # | Deviation | Requirement / Document | Task |
|---|---|---|---|
| `P5-16` | Public constants design §8.1 does not name | `NFR-4`, §8.1 | Tasks 2, 3, 4, 6, 7, 8, 12, 13, 15, 16 |
| `P5-17` | Public methods design §8.1 does not name | `NFR-4`, §8.1 | Tasks 2, 6, 7, 8, 10, 11, 12, 13, 14, 15 |
| `P5-18` | `Event#tag(key, value)` not shipped | §8.1, `OBS-4`, `OBS-5` | Task 9 |
| `P5-19` | Default sink is `NULL_SINK` instance, not `NullLogger` class | §8.1, `OBS-1` | Task 4 |
| `P5-20` | `Event::INERT` is frozen `Event::Inert < Event` instance | `OBS-1`, `NFR-3` | Task 9 |
| `P5-21` | `Event` and `Logger` are plain classes, not `Data` | `OBS-8`, `OBS-40` | Tasks 9, 10 |
| `P5-22` | `OBS-24` snapshot is shallow-frozen Hash, no Ractor claim | `OBS-24` | Task 6 |
| `P5-23` | `OBS-24` union restore per key via `Fiber[]=` alone | `OBS-24`, `OI-13`, `NFR-7` | Task 6 |
| `P5-24` | Diagnostic-context keys are Symbols; fold uses `Symbol#name` | `OBS-10`, `OBS-23` | Task 6 |
| `P5-25` | Redactor has two entry points `#url` and `#header_value` | `OBS-15`, `OBS-16` | Task 8 |
| `P5-26` | Redactor rescues `StandardError`, not `URI::Error` | `OBS-15`, `OBS-12` | Task 8 |
| `P5-27` | Redactor never assigns an absent URI component | `OBS-14`, `OBS-15` | Task 8 |
| `P5-28` | `OBS-16` relative or unparseable is two code paths | `OBS-16` | Task 8 |
| `P5-29` | `OBS-7` cap measured in bytes via `#byteslice` + `#scrub` | `OBS-7` | Task 5 |
| `P5-30` | Header allow-list excludes auth and challenge headers | `OBS-18`, `XCUT-19` | Task 7 |
| `P5-31` | `OBS-38` text/binary set chosen; corrected transcode recipe | `OBS-38`, `OI-7` | Task 12 |
| `P5-32` | `OBS-19` carried ⏳ against `DEF-41` instead of "vacuous" | `OBS-19`, `DEF-41` | Task 16 |
| `P5-33` | Step tracer and meter slots defaulted to `NO_TRACER_FACTORY` and `NO_METER` | `OBS-34`, `R11` | Task 15 |
| `P5-34` | Two steps (`Step`, `AsyncStep`) over one `Emitter` | `OBS-17`, `PIPE-28` | Task 15 |
| `P5-35` | `RedactionPolicy#omit_disallowed_headers` defaults to `false` | `OBS-18` | Task 7 |
| `P5-36` | `HTTPLogging.resolve` requires `key:` keyword with no default | `OBS-35`, `CFG-14` | Task 13 |
| `P5-37` | `Instrumentation.contain` is a module function | `OBS-20`, `XCUT-20` | Task 11 |
| `P5-38` | `Logger` keeps §8.1 name despite shadowing stdlib | §8.1, `SEAM-1` | Task 10 |
