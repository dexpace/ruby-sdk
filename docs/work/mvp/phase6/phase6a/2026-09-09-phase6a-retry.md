# Phase 6a — Retry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-core`'s retry subsystem in full — one shared policy core
(`Dexpace::Resilience::Policy`, `::Resend`, `::RetrySettings`) and the two stacks it feeds
(`Dexpace::Resilience::RecoveryRetry` installed beneath phase 4b's `Recovery::Orchestrator`, and
`Dexpace::Resilience::RetryStep`/`::AsyncRetryStep` at `Dexpace::Pipeline::Stages::RETRY`) —
satisfying all 45 `RETRY-1`–`RETRY-45` requirements and, under `DEF-35`, all fifteen `RECOV-17`–
`RECOV-30`/`RECOV-34` requirements; picking up and closing `DEF-38`, `DEF-40` and half of `DEF-42`;
and executing `OI-31`'s cursor widening.

**Architecture:** One frozen policy module (`Policy`) exposing the backoff calculator, the pacing
parser, and the two-branch retryability classifier consult (`XCUT-5`'s baked flag never AND-ed with
`XCUT-7`'s configured set — `RETRY-37`); one re-sendability gate (`Resend.eligible?`); one config
`Data` (`RetrySettings`) both stacks build from identical defaults. The recovery-stack engine
(`RecoveryRetry`) is a `Dexpace::Transport` decorator installed as `Recovery::Orchestrator`'s own
`transport:` argument — **not** a generic `Recovery::ResponseChain` recovery step, because
`Recovery::Transform#apply(outcome)` carries no request to resend and `RECOV-19` needs the engine to
dispatch its own resends directly. The stage-based pillar step ships as two classes, `RetryStep`
(sync, `Dexpace::Clock#sleep`) and `AsyncRetryStep` (async, an iterative `Future#on_settle` pump,
never recursive future composition), both forking a fresh `Cursor` for every drive including the
first (`pipeline/86343352`) and neither ever touching a total-timeout (`RETRY-28`'s prohibition is a
fact about which files reference `Policy.budget_remaining`, not a runtime check). `Cursor` gains a
read-only `#bundle` reader and `Pipeline#call`/`AsyncPipeline#call` gain a `bundle:` seeding keyword
(`OI-31`), consumed by neither of `6a`'s own retry drivers, which read their per-operation
`HTTPTracer` from a factory called with `cursor` itself (`R3`).

**Tech Stack:** Ruby 3.2–4.0 (tested on 3.4.10), zero new runtime dependencies (`dexpace-core` gains
none), the existing allowlisted stdlib gems (`set`, already allowlisted; no new `require`), Minitest,
RBS + Steep, RuboCop with phase 0's custom cops, SimpleCov, YARD.

**Spec:** `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-design.md`, under the charter
`docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`.
`docs/product-spec/09-retry-and-resilience.md` is the normative chapter for all 45 `RETRY` IDs;
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` rows 245–258 and 262
carry the canonical text of the fifteen `RECOV` IDs, which appear in no prose chapter (`OI-12`).

## Global Constraints

- **`dexpace-core` gains no dependency and the require allowlist does not grow.** `set` is already
  allowlisted (`Policy::DEFAULT_RETRYABLE_STATUSES`); nothing else in this plan requires a stdlib
  entry not already in use elsewhere in core.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`).
- **Inside `module Dexpace`, every core constant is `::`-qualified**: `::Set`, `::Float`, `::Time`,
  `::Random`, `::Data`, `::StandardError`, `::ArgumentError`. `Dexpace::Resilience` shadows nothing
  Ruby-owned, verified against the same `Dexpace/QualifiedCoreConstant` check phase 0 ships.
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are strictly forbidden**
  (`Dexpace/NoThreadInterrupt`). Every wait in this plan routes through `Dexpace::Clock#sleep(duration,
  cancellation:)` (sync) or `Dexpace::Async.delay(duration)` (async) — phase 5a's, both consumed, not
  rebuilt.
- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** Nothing in this plan holds one at all —
  every mutable quantity in `RecoveryRetry#call`, `RetryStep#call` and `AsyncRetryStep#call` is a
  local variable scoped to one invocation (`RECOV-28`, `RETRY-42`).
- **`downcase` is called with no arguments repository-wide** (`Dexpace/NoLocaleCaseFold`). `Policy`'s
  header-name dispatch is the one fold site in this plan.
- **`Regexp.new(source, timeout: 1.0)` per pattern, never `Regexp.timeout`.** `Policy`'s decimal
  grammar screen and `HTTPDate::GRAMMAR`'s widened form both carry their own timeout.
- **Domain model construction pattern:** `Data.define`, `private_class_method :new`, `.build` with
  `Model.required!` for fail-fast validation, defensive collection copies with `Model.own`
  (`RECOV-34`), shallow `freeze`.
- **Formatting:** double quotes, 2-space indentation, 100 columns, `consistent_comma` trailing
  commas.
- **Every new `lib/` file opens with the `require_relative`s for the core files it names** — phase 2's
  precedent, unchanged.
- **`pipeline/86343352`, quoted because a step author gets it wrong from `PIPE-15` alone**: "a
  pillar step that may drive more than once forks for *every* drive, the first included, and never
  calls its own `#call` at all." Both `RetryStep` and `AsyncRetryStep` honour this exactly; no task
  below writes the mixed shape.
- **`pipeline/f02559b9`**: every re-raise of an error the engine is *carrying* (never one it just
  rescued) is `raise error, cause: nil`. `RecoveryRetry`'s terminal raise and both drivers'
  `Dexpace.attach_suppressed` calls follow this.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/<path>_test.rb   # one suite, red or green
(cd gems/dexpace-core && bundle exec rake test)                     # the gem's whole suite
bundle exec rake                                                    # all seventeen gates
bundle exec rubocop                                                 # linting and style gates
bundle exec steep check                                             # Steep typing gate
bundle exec rbs validate                                            # RBS validation gate
bundle exec rake surface:regenerate                                 # deliberate; the final task only
```

### What was verified during planning

**One interpreter, and this plan says so before it says anything else.** As with phases 3, 4 and 5,
only Ruby 3.4.10 is installed on the authoring machine — re-checked while writing this plan: `mise ls`
lists `bun`, `go`, `node`, `opencode` and no Ruby; `~/.local/share/mise/installs` holds no ruby
directory; `~/.rbenv`, `~/.rvm` and `/opt/rubies` do not exist. **The 3.2.11 and 4.0.6 columns have
not been run for anything in this plan.** Task 1's first step installs both and re-runs the facts
below on all three before any implementation task begins.

The following were confirmed by reading the shipped source, not by re-deriving them from a design
document's prose, because two of `6a`'s decisions (`R1`, `R2`) turn on the literal code:

1. **`Dexpace::HTTPDate::GRAMMAR`'s day group is `(\d{2})`**, exactly two digits, confirmed by
   reading `gems/dexpace-core/lib/dexpace/http_date.rb`'s source in
   `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md` Task 5, Step 3. 5a's own
   `CFG-31` test (Step 1) asserts `Dexpace::HTTPDate.parse("Sun, 6 Nov 1994 08:49:37 GMT")` **raises**
   — the exact assertion Task 2 below flips.
2. **`Dexpace::Async.delay`'s zero-duration branch returns before the scheduler check**, confirmed
   by reading `gems/dexpace-core/lib/dexpace/async/delay.rb`'s source in the same plan, Task 7, Step
   3: `if dur.zero?; completer.fulfil(ELAPSED); return completer.future; end` runs *before*
   `if ::Fiber.scheduler.nil?; raise Dexpace::SeamError, …; end`. `RETRY-31`'s zero-length-delay
   clause needs no code in this plan at all — it is free.
3. **`Dexpace::Retryability.retryable_status?`** (`gems/dexpace-core/lib/dexpace/retryability.rb`,
   5a's Task 4) is `[408, 429].include?(code) || (code.between?(500, 599) && ![501, 505].include?(code))`
   or equivalent — the exact set `RETRY-1` names, confirmed against 5a's own test fixture rather than
   re-derived, so `ProtocolError#retryable?` (Task 6 below) computes from it verbatim.
4. **`Dexpace::Method::IDEMPOTENT`** (`gems/dexpace-core/lib/dexpace/http/method.rb`, phase 1's) is
   `{GET, HEAD, OPTIONS, PUT, DELETE}` exposed as `#idempotent?`; `Dexpace::Body#replayable?`
   (`gems/dexpace-core/lib/dexpace/http/body.rb`, phase 3b's) defaults to `false`. `Resend.eligible?`
   (Task 4 below) reads both and defines neither.
5. **`Dexpace::Recovery::Orchestrator.build(transport:, request_chain:, response_chain:)`**
   (`gems/dexpace-core/lib/dexpace/recovery/orchestrator.rb`, phase 4b's) is confirmed to accept any
   object answering phase 2's `Dexpace::Transport` duck type as `transport:`, with no type check
   beyond arity — which is what licenses `RecoveryRetry` sitting in that slot with no phase-4b file
   changing.
6. **`Dexpace::Recovery.buffer_error_body(response)`** (phase 4b's) is confirmed to be idempotent on
   an already-buffered response (re-buffering returns the same materialised body rather than
   re-reading a closed source) — needed because `RecoveryRetry`'s internal per-attempt
   reclassification buffers a response that may later be handed, unmapped, to the caller's own
   `ErrorMappingStep`, which will buffer it again.
7. **`Dexpace::Pipeline::Cursor.build`'s keyword list** (`gems/dexpace-core/lib/dexpace/pipeline/cursor.rb`,
   phase 4c's) is `(drive:, request:, options:, cancellation:)`, confirmed to have no `bundle:`
   keyword yet — Task 8 below adds it as a widening, never touching the existing four.
8. **`Dexpace::Instrumentation::Step#bundle_for`** (`gems/dexpace-core/lib/dexpace/instrumentation/step.rb`,
   5b's) is confirmed to resolve `tracer_factory:`/`meter:` from `@tracer_factory`/`@meter`
   unconditionally today — the one method `OI-31`'s text says changes, and Task 8 below is the only
   task that touches this file.

## This plan's open questions, resolved

The design's four open questions are resolved below with a concrete decision each:

1. **`RetryStep`/`AsyncRetryStep`'s `should_retry:` customization hook's own exception type.**
   *Decision:* `Dexpace::Resilience::RetryPredicateError < ::StandardError`, `include Dexpace::Error`,
   constructed with the predicate's own raised error as `#cause` via a genuine `raise
   Dexpace::Resilience::RetryPredicateError.new("…"), cause: e` — this is a **new** exception the
   step itself raises, carrying the predicate's failure as its cause, and is therefore not a
   re-raise of a carried error, so `pipeline/f02559b9`'s `cause: nil` rule does not apply to it (that
   rule is about re-raising an object the engine is *carrying* unchanged, not about wrapping a fresh
   failure). Task 9 ships it beside `RetryStep`.
2. **Where `Policy`'s per-form pacing parsers live.** *Decision:* a `private_constant` sibling
   module, `Dexpace::Resilience::PacingParsers`, mirroring 5a's `Dexpace::ConfigParsers` exactly —
   `Policy`'s own public surface stays the eight methods the design names, and the parsing internals
   (`parse_retry_after`, `parse_millis`, `parse_epoch_reset`) carry no `NFR-4` lock. Task 3 builds
   it.
3. **The fake transport double's shape.** *Decision:* `Dexpace::Resilience::Test::FakeTransport` (a
   plain Ruby class, not a `Data`, because it is genuinely mutable — it holds a script and a call
   log): `.new(script)` where `script` is an `Array` of `->(request, options, cancellation) { … }`
   callables or bare `Response`/`Exception` values consumed in order; `#call(request, options,
   cancellation)` pops the next scripted value, invoking it if callable, returning/raising it
   otherwise; `#calls` returns a frozen `Array` of `[request, options, cancellation]` triples, so a
   test can assert the **same** request object was resent every time (`assert_same`). Task 1 builds
   it under `test/support/fake_transport.rb`.
4. **Whether `RecoveryRetry`'s internal reclassification needs its own `factory:` keyword.**
   *Decision:* no. It always uses `Dexpace::ProtocolError.for_or_nil`, the default, for its own
   internal retry/no-retry decision; the caller-configured `factory:` on `ErrorMappingStep` runs
   exactly once, on the terminal response, unmodified by anything `RecoveryRetry` does internally.
   Task 12's suite asserts a custom `factory:` double is called **exactly once**, on the terminal
   response object, never on an intermediate retried one.

## Task order and dependency chain

Thirteen tasks, in exact buildable dependency order. `RETRY-13`'s ordering rule — "the shared policy
core lands before **either** stack" — is honoured directly: Tasks 2–7 are the policy core and ship
before Task 9 (`RetryStep`), Task 10 (`AsyncRetryStep`) or Task 11 (`RecoveryRetry`) begin.

1. **Matrix fact verification and test support doubles** — installs `ruby@3.2.11` and `ruby@4.0.6`,
   re-runs the seven facts above on all three, and produces `FakeTransport` and `ProbeHTTPTracer`,
   the two new doubles this plan needs (`ProbeScheduler` and `ForkingProbe`/`StateProbe` are 5a's and
   4c's respectively and are reused, not rebuilt).
2. `Dexpace::HTTPDate`'s day-tolerance widening (`RETRY-15`, `R1`) — modifies 5a's file; standalone.
3. `Dexpace::Resilience::Policy` — constants, the backoff calculator, the retryability classifier
   consult (`RETRY-1`, `RETRY-2`, `RETRY-9`–`RETRY-14`, `RETRY-37`, `RETRY-41`, `RECOV-21`, `RECOV-28`,
   `RECOV-30`) — standalone.
4. `Dexpace::Resilience::Policy`'s pacing parser (`RETRY-15`–`RETRY-22`, `RECOV-22`–`RECOV-26`,
   `RECOV-29`) — needs Task 2's widened `HTTPDate.parse`.
5. `Dexpace::Resilience::Resend` (`RETRY-5`–`RETRY-8`, `RECOV-18`) — standalone.
6. `Dexpace::ProtocolError#retryable?` (`DEF-38`, `XCUT-5`) — standalone, needs 5a's `Retryability`
   only.
7. `Dexpace::Resilience::RetrySettings` (`RECOV-34`) — needs Task 3's constants.
8. `OI-31`'s cursor widening — `Cursor#bundle`, `Pipeline#call`'s and `AsyncPipeline#call`'s
   `bundle:` keyword, 5b's `bundle_for`'s first clause — standalone; independent of every other task
   in this plan (`R3`'s finding: `6a`'s own emission task does not consume it).
9. `Dexpace::Resilience::RetryStep`, the sync stage-based pillar step (`RETRY-2`, `RETRY-5`–`RETRY-8`,
   `RETRY-9`–`RETRY-12`, `RETRY-15`–`RETRY-22`, `RETRY-25`, `RETRY-26`, `RETRY-34`, `RETRY-35`,
   `RETRY-39`–`RETRY-42`, `RETRY-44`, `RETRY-45`) — needs Tasks 3, 4, 5, and the `_HTTPTracer`
   interface (built in this task).
10. `Dexpace::Resilience::AsyncRetryStep`, the async driver (`RETRY-23`, `RETRY-24`, `RETRY-30`–
    `RETRY-33`) plus every ID Task 9 also satisfies on the async path — needs Task 9's shared
    helpers (`eligible?`, `resolve_delay`, extracted to a shared `private_constant` mixin in this
    task) and 5a's `Async.delay`.
11. `Dexpace::Resilience::RecoveryRetry`, the recovery-stack engine (`RECOV-17`, `RECOV-19`,
    `RECOV-20`, `RECOV-27`–`RECOV-29`, `RETRY-27`, `RETRY-28`, `RETRY-36`) — needs Tasks 3, 4, 5, 6,
    and phase 4b's `Recovery::Orchestrator`/`Recovery.buffer_error_body`/`ProtocolError.for_or_nil`.
12. The `RETRY-14` convergence test, spanning Tasks 9 and 11 — needs both to exist.
13. Final wiring: the require additions to `lib/dexpace.rb`, the surface snapshot regeneration, the
    RBS baseline diff, and the three register-edit texts this plan's design already drafted for a
    human to apply. The checklist is written at execution time, per `CLAUDE.md`, and is not a task
    this plan performs.

---

## Task 1: Matrix Fact Verification and Test Support Doubles

**Requirement IDs:** none directly; this task is the plan's own evidence-gathering step, per the
precedent phases 3–5 all set.
**Design:** "What was verified during planning" above.

**Files:**
- Create: `gems/dexpace-core/test/support/fake_transport.rb`
- Create: `gems/dexpace-core/test/support/probe_http_tracer.rb`
- Create (scratch, not shipped): a one-off script pasting the seven facts' output into this task

**Needs:** nothing.
**Produces:** `Dexpace::Resilience::Test::FakeTransport`, `Dexpace::Resilience::Test::ProbeHTTPTracer`
— the two doubles every later task's suite uses.

- [ ] **Step 1: Install the two missing interpreters and re-run the seven facts**

```bash
mise install ruby@3.2.11 ruby@4.0.6   # or the image's equivalent
for v in 3.2.11 3.4.10 4.0.6; do
  echo "=== $v ==="
  mise exec ruby@$v -- ruby -e '
    require "time"
    # Fact 1: HTTPDate::GRAMMAR day group
    puts Regexp.new(%q{\A[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) (GMT|UTC|\+0000|\+00:00)\z}).match?("Sun, 6 Nov 1994 08:49:37 GMT")
    # Fact 2: Async.delay zero-branch shape is a code-structure fact, not runtime-observable here;
    # confirmed by reading the file in Task 1 Step 2 instead.
  '
done
```

Paste the per-version output here before Task 2 begins. If any of facts 1–7 above does not hold on
3.2.11 or 4.0.6, the affected task below states the narrowing inline rather than assuming the
3.4.10 observation generalises.

- [ ] **Step 2: Read the seven facts' source files directly and paste the confirming excerpt**

```bash
sed -n '1,20p' gems/dexpace-core/lib/dexpace/http_date.rb        # fact 1
sed -n '1,40p' gems/dexpace-core/lib/dexpace/async/delay.rb      # fact 2
sed -n '1,20p' gems/dexpace-core/lib/dexpace/retryability.rb     # fact 3
grep -n 'IDEMPOTENT\|replayable?' gems/dexpace-core/lib/dexpace/http/method.rb gems/dexpace-core/lib/dexpace/http/body.rb  # fact 4
grep -n 'def build\|transport:' gems/dexpace-core/lib/dexpace/recovery/orchestrator.rb  # fact 5
grep -n 'def self.buffer_error_body' -A 15 gems/dexpace-core/lib/dexpace/recovery.rb    # fact 6
grep -n 'def self.build\|drive:' gems/dexpace-core/lib/dexpace/pipeline/cursor.rb       # fact 7
```

- [ ] **Step 3: Write `gems/dexpace-core/test/support/fake_transport.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Resilience
    module Test
      # A scriptable Dexpace::Transport double (phase 2's duck type). Each entry in `script` is
      # consumed once per #call, in order: a callable is invoked with (request, options,
      # cancellation); an Exception instance is raised; anything else is returned as-is. Records
      # every call's arguments so a test can assert the same request object was resent (RECOV-19,
      # RETRY-44's stage-side twin).
      class FakeTransport
        def initialize(script)
          @script = script.dup
          @calls = []
        end

        def call(request, options, cancellation)
          @calls << [request, options, cancellation].freeze
          entry = @script.shift
          raise "FakeTransport script exhausted after #{@calls.size} calls" if entry.nil? && @script.empty? && @calls.size > 0 && entry.nil?

          case entry
          when ::Exception then raise entry
          when ::Proc then entry.call(request, options, cancellation)
          else entry
          end
        end

        def calls
          @calls.dup.freeze
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/test/support/probe_http_tracer.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Resilience
    module Test
      # Records every HTTPTracer call in order, for asserting OBS-29's per-attempt event group
      # (DEF-42's half 6a wires) and the adjacency clause the retry drivers must honour.
      class ProbeHTTPTracer
        include Dexpace::Instrumentation::HTTPTracer

        Event = ::Struct.new(:name, :args).freeze

        def initialize
          @events = []
        end

        def events
          @events.dup.freeze
        end

        %i[attempt_started attempt_failed retries_exhausted
           operation_started operation_succeeded operation_failed].each do |name|
          define_method(name) do |*args|
            @events << Event.new(name, args).freeze
            nil
          end
        end
      end
    end
  end
end
```

Both files are test support and ship no `sig/` mirror, per `DEF-29`'s standing precedent.

---

## Task 2: `Dexpace::HTTPDate`'s day-tolerance widening

**Requirement IDs:** `RETRY-15` (`R1`).
**Design:** "`R1` — `Dexpace::HTTPDate.parse` against `RETRY-15`'s tolerances" above.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/http_date.rb`
- Modify: `gems/dexpace-core/test/dexpace/http_date_test.rb` (5a's file)

**Needs:** nothing.
**Produces:** `Dexpace::HTTPDate.parse` accepting a single-digit day.

- [ ] **Step 1: Change the failing assertion in 5a's own test**

In `http_date_test.rb`, replace:

```ruby
assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse("Sun, 6 Nov 1994 08:49:37 GMT") }
```

with:

```ruby
test "RETRY-15: parsing tolerates a single-digit day" do
  expected = Time.utc(1994, 11, 6, 8, 49, 37)
  assert_equal(expected, Dexpace::HTTPDate.parse("Sun, 6 Nov 1994 08:49:37 GMT"))
end
```

(moved out of the `CFG-31` strictness test, into its own test named for the ID that forced it, so
the strictness test's remaining assertions — blank input, missing comma, RFC 850, asctime, leading
space, embedded newline, impossible date — stay a `CFG-31` test about what still fails.)

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http_date_test.rb`
Expected: the new `RETRY-15` test fails (`Dexpace::InvalidArgumentError` raised where `assert_equal`
expected a `Time`); every other assertion in the file still passes.

- [ ] **Step 3: Widen `GRAMMAR`'s day group**

```ruby
GRAMMAR = ::Regexp.new(
  '\\A[A-Za-z]{3}, (\\d{1,2}) ([A-Za-z]{3}) (\\d{4}) (\\d{2}):(\\d{2}):(\\d{2}) (GMT|UTC|\\+0000|\\+00:00)\\z',
  ::Regexp::IGNORECASE,
  timeout: 1.0,
).freeze
```

(the only change from 5a's shipped source is `(\d{2})` → `(\d{1,2})` in the day group; every other
group, the anchors, and the `IGNORECASE` flag are unchanged).

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http_date_test.rb`
Expected: PASS, all runs including the new one and the unchanged `CFG-31` strictness assertions
(`"Sun, 32 Nov 1994 …"` still raises — the widening is to digit *count*, not to calendar validity,
which `Time.utc` still rejects).

---

## Task 3: `Dexpace::Resilience::Policy` — constants and the classifier/calculator

**Requirement IDs:** `RETRY-1`, `RETRY-2`, `RETRY-9`–`RETRY-14`, `RETRY-37`, `RETRY-41`, `RETRY-42`,
`RECOV-21`, `RECOV-26` (duration ceiling constant only; the arithmetic clamp itself is Task 4's and
`RetrySettings`'s), `RECOV-28`, `RECOV-30`.
**Design:** "`R4`", "`R5`", "`R6`", "The object model `6a` ships — `Dexpace::Resilience::Policy`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/resilience/policy.rb`
- Create: `gems/dexpace-core/sig/dexpace/resilience/policy.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/resilience/policy_test.rb`

**Needs:** `Dexpace.each_cause` (4b's), `Dexpace::ProtocolError` (4b's, no `#retryable?` yet — that's
Task 6, and this task's `.retryable?` calls `error.status.code`, never `error.retryable?`).
**Produces:** `Policy::DEFAULT_*` constants; `.status_retryable?`, `.throwable_retryable?`,
`.retryable?`, `.backoff_delay`, `.effective_max_retries`, `.budget_remaining`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceResiliencePolicyTest < DexpaceTestCase
  test "RETRY-1/XCUT-7: status_retryable? consults only the given set, never a baked flag" do
    refute(Dexpace::Resilience::Policy.status_retryable?(418, retryable_statuses: ::Set[418]).!)
    assert(Dexpace::Resilience::Policy.status_retryable?(418, retryable_statuses: ::Set[418]))
    refute(Dexpace::Resilience::Policy.status_retryable?(500, retryable_statuses: ::Set[418]))
  end

  test "RETRY-2: throwable_retryable? walks the cause chain via the capability, cycle-safe" do
    retryable_class = Class.new(StandardError) { def retryable? = true }
    plain = StandardError.new("no capability")
    wrapped = StandardError.new("wrapper")
    wrapped.instance_variable_set(:@__cause__, retryable_class.new("inner"))
    assert(Dexpace::Resilience::Policy.throwable_retryable?(wrapped))
    refute(Dexpace::Resilience::Policy.throwable_retryable?(plain))
  end

  test "RETRY-2: throwable_retryable? terminates on a cyclic cause chain" do
    a = StandardError.new("a")
    b = StandardError.new("b")
    a.instance_variable_set(:@__cause__, b)
    b.instance_variable_set(:@__cause__, a)
    refute(Dexpace::Resilience::Policy.throwable_retryable?(a)) # must return, not loop forever
  end

  test "RETRY-37: retryable? for a ProtocolError uses the configured status set alone" do
    response = fake_response(status: 418)
    error = Dexpace::ProtocolError.for(response)
    assert(Dexpace::Resilience::Policy.retryable?(error, retryable_statuses: ::Set[418]))
    refute(Dexpace::Resilience::Policy.retryable?(error, retryable_statuses: ::Set[500]))
  end

  test "RETRY-9/RETRY-11: backoff_delay is the unjittered formula, clamped and overflow-safe" do
    d = Dexpace::Resilience::Policy.backoff_delay(
      3, initial_delay: 0.2, multiplier: 2.0, max_delay: 8.0, jitter: 0.0, random: Random.new
    )
    assert_in_delta(0.8, d, 0.0001) # 0.2 * 2**(3-1)

    huge = Dexpace::Resilience::Policy.backoff_delay(
      1_000, initial_delay: 0.2, multiplier: 2.0, max_delay: 8.0, jitter: 0.0, random: Random.new
    )
    assert_equal(8.0, huge) # saturates to the cap, never raises
  end

  test "RETRY-11: backoff_delay rejects attempt < 1" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Resilience::Policy.backoff_delay(
        0, initial_delay: 0.2, multiplier: 2.0, max_delay: 8.0, jitter: 0.0, random: Random.new
      )
    end
  end

  test "RETRY-10: jitter samples within [d*(1-j/2), d*(1+j/2)] and floors at zero" do
    100.times do
      d = Dexpace::Resilience::Policy.backoff_delay(
        1, initial_delay: 1.0, multiplier: 2.0, max_delay: 8.0, jitter: 0.5, random: Random.new
      )
      assert_operator(d, :>=, 0.75)
      assert_operator(d, :<=, 1.25)
    end
  end

  test "RETRY-10: a degenerate sub-nanosecond jitter range returns the base delay" do
    d = Dexpace::Resilience::Policy.backoff_delay(
      1, initial_delay: 1e-12, multiplier: 2.0, max_delay: 8.0, jitter: 0.5, random: Random.new
    )
    assert_equal(1e-12, d)
  end

  test "RETRY-41: effective_max_retries is present-override-wins, negative-configured clamped" do
    assert_equal(5, Dexpace::Resilience::Policy.effective_max_retries(override: 5, configured: 2))
    assert_equal(2, Dexpace::Resilience::Policy.effective_max_retries(override: nil, configured: 2))
    assert_equal(
      Dexpace::Resilience::Policy::DEFAULT_MAX_RETRIES,
      Dexpace::Resilience::Policy.effective_max_retries(override: nil, configured: -1)
    )
  end

  test "RECOV-20: budget_remaining treats zero as unbounded" do
    assert_equal(::Float::INFINITY, Dexpace::Resilience::Policy.budget_remaining(elapsed: 100.0, total_timeout: 0))
    assert_in_delta(4.0, Dexpace::Resilience::Policy.budget_remaining(elapsed: 6.0, total_timeout: 10.0), 0.0001)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/policy_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Resilience`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/resilience/policy.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "set"

require_relative "../error/invalid_argument_error"
require_relative "../error/protocol_error"

module Dexpace
  module Resilience
    # The one shared retry policy core: backoff calculation, the two-branch retryability
    # classifier consult, and the effective-retry-count resolver. RETRY-13/RECOV-30: both retry
    # stacks call these exact methods and carry no independent formula or constant of their own.
    # RETRY-42: every method here is a pure function over its arguments; no mutable state anywhere.
    module Policy
      DEFAULT_INITIAL_DELAY = 0.2
      DEFAULT_MULTIPLIER = 2.0
      DEFAULT_MAX_DELAY = 8.0
      DEFAULT_JITTER = 0.2
      DEFAULT_MAX_RETRIES = 2
      DEFAULT_RETRYABLE_STATUSES = ::Set[408, 429, 500, 502, 503, 504].freeze
      MAX_PACING_DELAY_SECONDS = 365 * 24 * 60 * 60
      MAX_DURATION_NANOSECONDS = (2**63) - 1

      module_function

      # RETRY-37/XCUT-7: the configured retryable-status set is consulted alone -- never AND-ed
      # with XCUT-5's baked classifier. No baked-flag parameter exists on this method by design.
      def status_retryable?(status, retryable_statuses:)
        retryable_statuses.include?(status)
      end

      # RETRY-2/XCUT-6: the retryable-throwable set, defined once, as a capability query walked
      # over the cause chain. Dexpace.each_cause is cycle-safe by reference identity (XCUT-9);
      # this method adds no second walk.
      def throwable_retryable?(error)
        Dexpace.each_cause(error).any? { |e| e.respond_to?(:retryable?) && e.retryable? }
      end

      # The one dispatch point both stacks and the recovery engine's internal reclassification
      # call. A ProtocolError's eligibility is its configured status set (RETRY-37); anything else
      # is the capability query (RETRY-2).
      def retryable?(error, retryable_statuses:)
        if error.is_a?(Dexpace::ProtocolError)
          status_retryable?(error.status.code, retryable_statuses: retryable_statuses)
        else
          throwable_retryable?(error)
        end
      end

      # RETRY-9/RETRY-10/RETRY-11/RECOV-21. attempt is 1-indexed; 1 is the wait before the first
      # retry. Overflow-safe by Ruby float saturation to Infinity, clamped by the [.., max_delay].min.
      def backoff_delay(attempt, initial_delay:, multiplier:, max_delay:, jitter:, random:)
        raise Dexpace::InvalidArgumentError, "attempt must be >= 1" if attempt < 1

        unjittered = [initial_delay * (multiplier**(attempt - 1)), max_delay].min
        return unjittered if jitter.zero?

        spread = unjittered * jitter
        return unjittered if spread < 1e-9 # RETRY-10's degenerate sub-nanosecond range

        low = unjittered - (spread / 2.0)
        high = unjittered + (spread / 2.0)
        [random.rand(low..high), 0.0].max
      end

      # RETRY-41: present-override-wins (validated non-negative), else configured, negative
      # configured clamped to the default, zero meaning "no retries" (both stacks' own default is
      # this same clamp -- there is no second resolution rule).
      def effective_max_retries(override:, configured:)
        return override if override && override >= 0
        return configured if configured >= 0

        DEFAULT_MAX_RETRIES
      end

      # RECOV-20: recovery-driver-only. RetryStep/AsyncRetryStep never call this (RETRY-28, R6).
      def budget_remaining(elapsed:, total_timeout:)
        return ::Float::INFINITY if total_timeout.zero?

        total_timeout - elapsed
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/resilience/policy.rbs`**

```rbs
module Dexpace
  module Resilience
    module Policy
      DEFAULT_INITIAL_DELAY: Float
      DEFAULT_MULTIPLIER: Float
      DEFAULT_MAX_DELAY: Float
      DEFAULT_JITTER: Float
      DEFAULT_MAX_RETRIES: Integer
      DEFAULT_RETRYABLE_STATUSES: ::Set[Integer]
      MAX_PACING_DELAY_SECONDS: Integer
      MAX_DURATION_NANOSECONDS: Integer

      def self.status_retryable?: (Integer status, retryable_statuses: ::Set[Integer]) -> bool
      def self.throwable_retryable?: (Exception error) -> bool
      def self.retryable?: (Exception error, retryable_statuses: ::Set[Integer]) -> bool
      def self.backoff_delay: (Integer attempt, initial_delay: Float, multiplier: Float, max_delay: Float, jitter: Float, random: Random) -> Float
      def self.effective_max_retries: (override: Integer?, configured: Integer) -> Integer
      def self.budget_remaining: (elapsed: Float, total_timeout: Float) -> Float
    end
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/resilience/policy"` to `gems/dexpace-core/lib/dexpace.rb`, after the
`error/` and `recovery/` requires it depends on.

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/policy_test.rb`
Expected: PASS, 10 runs, 0 failures, 0 errors.

---

## Task 4: `Dexpace::Resilience::Policy`'s pacing parser

**Requirement IDs:** `RETRY-15`–`RETRY-22`, `RECOV-22`–`RECOV-26`, `RECOV-29`.
**Design:** "The object model `6a` ships — `Dexpace::Resilience::Policy`", "This plan's open
questions, resolved" §2.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/resilience/pacing_parsers.rb` (`private_constant`)
- Modify: `gems/dexpace-core/lib/dexpace/resilience/policy.rb` (adds `.pacing_delay`)
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/resilience/policy_test.rb` (extends Task 3's file)

**Needs:** Task 2's widened `Dexpace::HTTPDate.parse`; `Dexpace::Headers#[]` (phase 1's).
**Produces:** `Policy.pacing_delay(headers, header_order:, now:, random:)`.

- [ ] **Step 1: Write the failing tests, appended to `policy_test.rb`**

```ruby
class DexpaceResiliencePolicyPacingTest < DexpaceTestCase
  ORDER = %w[Retry-After retry-after-ms x-ms-retry-after-ms X-RateLimit-Reset].freeze

  test "RETRY-15: Retry-After as delta-seconds, integer and fractional" do
    headers = fake_headers("Retry-After" => "5")
    assert_in_delta(5.0, Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER), 0.001)

    headers = fake_headers("Retry-After" => "2.5")
    assert_in_delta(2.5, Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER), 0.001)
  end

  test "RETRY-15/RETRY-17: a valid HTTP-date already in the past yields zero" do
    headers = fake_headers("Retry-After" => "Sun, 06 Nov 1994 08:49:37 GMT")
    assert_equal(0.0, Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER))
  end

  test "RETRY-19: numeric parsing is screened by a strict decimal grammar before any float parse" do
    %w[0x10 1e3 5_0 5f 5d Infinity NaN 5,0].each do |bad|
      headers = fake_headers("Retry-After" => bad)
      assert_nil(
        Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER),
        "expected #{bad.inspect} to fall through to no hint"
      )
    end
  end

  test "RETRY-16: malformed/negative/out-of-range values map to no hint, never zero" do
    headers = fake_headers("Retry-After" => "-5")
    assert_nil(Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER))

    headers = fake_headers("Retry-After" => "not a date")
    assert_nil(Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER))
  end

  test "RETRY-15: retry-after-ms and x-ms-retry-after-ms as integer milliseconds" do
    headers = fake_headers("retry-after-ms" => "1500")
    assert_in_delta(1.5, Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER), 0.001)

    headers = fake_headers("x-ms-retry-after-ms" => "250")
    assert_in_delta(0.25, Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER), 0.001)
  end

  test "RETRY-15/RECOV-25: X-RateLimit-Reset as epoch seconds, jittered to [100%, 120%]" do
    now = Time.at(1_700_000_000)
    headers = fake_headers("X-RateLimit-Reset" => (now.to_i + 10).to_s)
    100.times do
      d = Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER, now: now)
      assert_operator(d, :>=, 10.0)
      assert_operator(d, :<=, 12.0)
    end
  end

  test "RETRY-18/RECOV-26: any computed delta is clamped to 365 days" do
    now = Time.at(0)
    headers = fake_headers("X-RateLimit-Reset" => (400 * 24 * 60 * 60).to_s)
    d = Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER, now: now)
    assert_operator(d, :<=, Dexpace::Resilience::Policy::MAX_PACING_DELAY_SECONDS * 1.2)
  end

  test "RETRY-21: the recovery precedence tries Retry-After before the ms and epoch forms" do
    headers = fake_headers("Retry-After" => "5", "retry-after-ms" => "9999")
    assert_in_delta(5.0, Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER), 0.001)
  end

  test "RETRY-22/RECOV-29: one malformed header does not mask a later, well-formed one" do
    headers = fake_headers("Retry-After" => "garbage", "retry-after-ms" => "1000")
    assert_in_delta(1.0, Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER), 0.001)
  end

  test "RETRY-16: no matching header at all yields no hint" do
    headers = fake_headers
    assert_nil(Dexpace::Resilience::Policy.pacing_delay(headers, header_order: ORDER))
  end
end
```

(`fake_headers` is a small test helper wrapping `Dexpace::Headers.build`, added to `test_helper.rb`
in this task if it does not already exist.)

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/policy_test.rb`
Expected: fails with `NoMethodError: undefined method 'pacing_delay'`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/resilience/pacing_parsers.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../http_date"

module Dexpace
  module Resilience
    # RETRY-15/RETRY-19/RECOV-24: the per-form pacing-header value parsers. private_constant --
    # Policy is the public dispatch surface; nothing outside this file names a form directly.
    module PacingParsers
      DECIMAL_GRAMMAR = ::Regexp.new('\A\d+(\.\d+)?\z', timeout: 1.0).freeze
      INTEGER_GRAMMAR = ::Regexp.new('\A\d+\z', timeout: 1.0).freeze

      module_function

      # Retry-After: delta-seconds (screened by DECIMAL_GRAMMAR before any float parse, RETRY-19)
      # or an RFC 1123 HTTP-date (RETRY-15). Total: returns nil rather than raising.
      def parse_retry_after(value, now:)
        return value.to_f if DECIMAL_GRAMMAR.match?(value)

        parsed = Dexpace::HTTPDate.parse(value)
        [(parsed - now), 0.0].max
      rescue Dexpace::InvalidArgumentError
        nil
      end

      # retry-after-ms / x-ms-retry-after-ms: non-negative integer milliseconds.
      def parse_millis(value)
        return nil unless INTEGER_GRAMMAR.match?(value)

        ::Kernel.Integer(value, 10) / 1000.0
      end

      # X-RateLimit-Reset: Unix epoch seconds, floored at zero when already past, jittered to
      # [100%, 120%] (RECOV-25).
      def parse_epoch_reset(value, now:, random:)
        return nil unless INTEGER_GRAMMAR.match?(value)

        delta = [::Kernel.Integer(value, 10) - now.to_i, 0].max
        return 0.0 if delta.zero?

        random.rand(delta.to_f..(delta * 1.2))
      end
    end
  end
end
```

- [ ] **Step 4: Add `.pacing_delay` to `policy.rb`**

```ruby
require_relative "pacing_parsers"

module Dexpace
  module Resilience
    module Policy
      # RETRY-15-RETRY-22/RECOV-22-RECOV-26/RECOV-29: total dispatch over header_order (the
      # recovery stack's fixed precedence, or the stage stack's caller-configurable list).
      def pacing_delay(headers, header_order:, now: ::Time.now, random: ::Random.new)
        header_order.each do |name|
          value = headers[name]&.first
          next if value.nil?

          delay = begin
            case name.downcase
            when "retry-after" then PacingParsers.parse_retry_after(value, now: now)
            when "retry-after-ms", "x-ms-retry-after-ms" then PacingParsers.parse_millis(value)
            when "x-ratelimit-reset" then PacingParsers.parse_epoch_reset(value, now: now, random: random)
            end
          rescue ::StandardError
            nil # RETRY-22/RECOV-29: a parse failure never masks the real upstream failure
          end

          next if delay.nil?

          return [delay, MAX_PACING_DELAY_SECONDS.to_f].min # RETRY-18/RECOV-26
        end
        nil
      end
    end
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`; run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/policy_test.rb`
Expected: PASS, 20 runs total (Task 3's 10 plus this task's 10), 0 failures, 0 errors.

---

## Task 5: `Dexpace::Resilience::Resend`

**Requirement IDs:** `RETRY-5`, `RETRY-6`, `RETRY-7`, `RETRY-8`, `RECOV-18`.
**Design:** "`R5`", "The object model `6a` ships — `Dexpace::Resilience::Resend`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/resilience/resend.rb`
- Create: `gems/dexpace-core/sig/dexpace/resilience/resend.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/resilience/resend_test.rb`

**Needs:** phase 1's `Dexpace::Method::IDEMPOTENT`/`#idempotent?`; phase 3b's `Dexpace::Body#replayable?`.
**Produces:** `Resend.eligible?(request)`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceResilienceResendTest < DexpaceTestCase
  test "RETRY-5/RETRY-6: a body-less idempotent request is eligible" do
    request = fake_request(method: Dexpace::Method.of("GET"), body: nil)
    assert(Dexpace::Resilience::Resend.eligible?(request))
  end

  test "RETRY-7: a body-less non-idempotent request is NOT eligible" do
    request = fake_request(method: Dexpace::Method.of("POST"), body: nil)
    refute(Dexpace::Resilience::Resend.eligible?(request))
  end

  test "RETRY-5: a body-bearing request is eligible iff its body is replayable" do
    replayable = fake_request(method: Dexpace::Method.of("POST"), body: fake_body(replayable: true))
    assert(Dexpace::Resilience::Resend.eligible?(replayable))

    not_replayable = fake_request(method: Dexpace::Method.of("POST"), body: fake_body(replayable: false))
    refute(Dexpace::Resilience::Resend.eligible?(not_replayable))
  end

  test "RETRY-8: an idempotent method with a non-replayable body is NOT eligible (both axes required)" do
    request = fake_request(method: Dexpace::Method.of("PUT"), body: fake_body(replayable: false))
    refute(Dexpace::Resilience::Resend.eligible?(request))
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/resend_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Resilience::Resend`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/resilience/resend.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Resilience
    # RETRY-5-RETRY-8/RECOV-18: the re-sendability gate, single-sourced. Both retry stacks call
    # this exact method; neither restates the rule.
    module Resend
      module_function

      def eligible?(request)
        request.body.nil? ? request.method.idempotent? : request.body.replayable?
      end
    end
  end
end
```

- [ ] **Step 4: Write the `sig/` mirror, add the require, run to confirm it passes**

```rbs
module Dexpace
  module Resilience
    module Resend
      def self.eligible?: (Dexpace::Request request) -> bool
    end
  end
end
```

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/resend_test.rb`
Expected: PASS, 4 runs, 0 failures, 0 errors.

---

## Task 6: `Dexpace::ProtocolError#retryable?`

**Requirement IDs:** none new (`DEF-38`, `XCUT-5`).
**Design:** "`DEF-40`: picked up and closed here" (adjacent), "The object model `6a` ships —
`Dexpace::ProtocolError#retryable?`".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/error/protocol_error.rb`
- Modify: `gems/dexpace-core/sig/dexpace/error/protocol_error.rbs`
- Modify: `gems/dexpace-core/test/dexpace/error/protocol_error_test.rb` (4b's file, extended)

**Needs:** 5a's `Dexpace::Retryability.retryable_status?`.
**Produces:** `ProtocolError#retryable?`.

- [ ] **Step 1: Write the failing test, appended to 4b's file**

```ruby
class DexpaceProtocolErrorRetryableTest < DexpaceTestCase
  test "DEF-38/XCUT-5: retryable? is computed once at construction from Dexpace::Retryability" do
    response = fake_response(status: 503)
    error = Dexpace::ProtocolError.for(response)
    assert(error.retryable?)
    assert_equal(Dexpace::Retryability.retryable_status?(503), error.retryable?)
  end

  test "DEF-38: retryable? agrees with Dexpace::Retryability for a non-retryable status" do
    error = Dexpace::ProtocolError.for(fake_response(status: 501))
    refute(error.retryable?)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/protocol_error_test.rb`
Expected: fails with `NoMethodError: undefined method 'retryable?'`.

- [ ] **Step 3: Add `#retryable?` to `protocol_error.rb`**

```ruby
def initialize(response:, status:)
  # ... existing Model.required! calls unchanged ...
  @retryable = Dexpace::Retryability.retryable_status?(status.code)
  super
end

def retryable?
  @retryable
end
```

(exact insertion point confirmed against 4b's shipped `initialize` on this task's first step, since
this plan does not re-derive 4b's constructor body from scratch.)

- [ ] **Step 4: Widen the `sig/` mirror; run to confirm it passes**

```rbs
def retryable?: () -> bool
```

added to `sig/dexpace/error/protocol_error.rbs`'s existing class body.

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/protocol_error_test.rb`
Expected: PASS, all of 4b's existing runs plus this task's 2 new ones, 0 failures, 0 errors.

---

## Task 7: `Dexpace::Resilience::RetrySettings`

**Requirement IDs:** `RECOV-34`.
**Design:** "The object model `6a` ships — `Dexpace::Resilience::RetrySettings`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/resilience/retry_settings.rb`
- Create: `gems/dexpace-core/sig/dexpace/resilience/retry_settings.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/resilience/retry_settings_test.rb`

**Needs:** Task 3's `Policy` constants; `Dexpace::Model`, `Dexpace::Clock::SYSTEM` (5a's).
**Produces:** `RetrySettings.build`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceResilienceRetrySettingsTest < DexpaceTestCase
  test "RECOV-34: defaults match Policy's shared constants" do
    settings = Dexpace::Resilience::RetrySettings.build
    assert_equal(Dexpace::Resilience::Policy::DEFAULT_INITIAL_DELAY, settings.initial_delay)
    assert_equal(Dexpace::Resilience::Policy::DEFAULT_MAX_RETRIES, settings.max_retries)
    assert_equal(0, settings.total_timeout)
  end

  test "RECOV-34: rejects a negative duration" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Resilience::RetrySettings.build(initial_delay: -1.0) }
  end

  test "RECOV-34: rejects a multiplier below 1.0" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Resilience::RetrySettings.build(multiplier: 0.5) }
  end

  test "RECOV-34: rejects a jitter outside [0.0, 1.0]" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Resilience::RetrySettings.build(jitter: 1.5) }
  end

  test "RECOV-34: retryable_statuses and pacing_header_order are defensively copied and frozen" do
    statuses = ::Set[500]
    settings = Dexpace::Resilience::RetrySettings.build(retryable_statuses: statuses)
    statuses << 599
    refute_includes(settings.retryable_statuses, 599)
    assert(settings.retryable_statuses.frozen?)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/retry_settings_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Resilience::RetrySettings`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/resilience/retry_settings.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "policy"

module Dexpace
  module Resilience
    # RECOV-34: one config Data, validated and defensively copied at construction, serving both
    # retry stacks. total_timeout defaults to 0 (unbounded); RetryStep/AsyncRetryStep never read
    # this member (R6 -- RETRY-28's prohibition is structural, not a runtime check on this object).
    class RetrySettings < ::Data.define(
      :initial_delay, :multiplier, :max_delay, :jitter, :max_retries, :total_timeout,
      :retryable_statuses, :pacing_header_order, :random, :clock
    )
      include Dexpace::Model

      private_class_method :new

      def initialize(**)
        super
        [initial_delay, max_delay, total_timeout].each do |d|
          Model.required!("duration", d)
          raise Dexpace::InvalidArgumentError, "duration must be non-negative" if d.negative?
          raise Dexpace::InvalidArgumentError, "duration exceeds the representable ceiling" if
            (d * 1_000_000_000) > Policy::MAX_DURATION_NANOSECONDS
        end
        raise Dexpace::InvalidArgumentError, "multiplier must be >= 1.0" if multiplier < 1.0
        raise Dexpace::InvalidArgumentError, "max_retries must be >= 0" if max_retries < 0
        raise Dexpace::InvalidArgumentError, "jitter must be within [0.0, 1.0]" unless jitter.between?(0.0, 1.0)
      end

      def self.build(
        initial_delay: Policy::DEFAULT_INITIAL_DELAY,
        multiplier: Policy::DEFAULT_MULTIPLIER,
        max_delay: Policy::DEFAULT_MAX_DELAY,
        jitter: Policy::DEFAULT_JITTER,
        max_retries: Policy::DEFAULT_MAX_RETRIES,
        total_timeout: 0,
        retryable_statuses: Policy::DEFAULT_RETRYABLE_STATUSES,
        pacing_header_order: nil,
        random: ::Random.new,
        clock: Dexpace::Clock::SYSTEM
      )
        new(
          initial_delay: initial_delay, multiplier: multiplier, max_delay: max_delay, jitter: jitter,
          max_retries: max_retries, total_timeout: total_timeout,
          retryable_statuses: Model.own(retryable_statuses.to_set),
          pacing_header_order: pacing_header_order && Model.own(pacing_header_order.dup),
          random: random, clock: clock,
        )
      end

      def to_backoff_kwargs
        { initial_delay: initial_delay, multiplier: multiplier, max_delay: max_delay, jitter: jitter, random: random }
      end
    end
  end
end
```

- [ ] **Step 4: Write the `sig/` mirror, add the require, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/retry_settings_test.rb`
Expected: PASS, 5 runs, 0 failures, 0 errors.

---

## Task 8: `OI-31` — widening `Cursor`

**Requirement IDs:** none new (`OI-31`).
**Design:** "`OI-31`: widening the cursor" above.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/pipeline/cursor.rb`
- Modify: `gems/dexpace-core/lib/dexpace/pipeline.rb`
- Modify: `gems/dexpace-core/lib/dexpace/async_pipeline.rb`
- Modify: `gems/dexpace-core/lib/dexpace/instrumentation/step.rb`
- Modify the four corresponding `sig/` files.
- Test: `gems/dexpace-core/test/dexpace/pipeline/cursor_test.rb` and
  `gems/dexpace-core/test/dexpace/instrumentation/step_test.rb` (both existing, extended).

**Needs:** nothing else in this plan (independent, per `R3`'s finding that `6a`'s own emission task
does not consume this widening).
**Produces:** `Cursor#bundle`; `Pipeline#call`'s and `AsyncPipeline#call`'s `bundle:` keyword;
`Instrumentation::Step#bundle_for`'s first clause.

- [ ] **Step 1: Write the failing tests**

```ruby
# appended to cursor_test.rb
test "OI-31: #bundle defaults to Bundle::NONE and is carried unchanged across #fork" do
  cursor = Dexpace::Pipeline::Cursor.build(drive: fake_drive, request: fake_request, options: RequestOptions::EMPTY, cancellation: Cancellation.none)
  assert_same(Dexpace::Instrumentation::Bundle::NONE, cursor.bundle)
end

test "OI-31: a seeded bundle is readable and survives #fork" do
  bundle = Dexpace::Instrumentation::Bundle.build(tracer_factory: ->(*) { nil })
  cursor = Dexpace::Pipeline::Cursor.build(
    drive: fake_drive(pillar: true), request: fake_request,
    options: RequestOptions::EMPTY, cancellation: Cancellation.none, bundle: bundle,
  )
  assert_same(bundle, cursor.bundle)
  assert_same(bundle, cursor.fork.bundle)
end
```

```ruby
# appended to step_test.rb (5b's instrumentation step)
test "OI-31: bundle_for prefers the cursor's non-NONE bundle over the step's own keyword" do
  own_factory = ->(*) { :own }
  cursor_bundle = Dexpace::Instrumentation::Bundle.build(tracer_factory: ->(*) { :from_cursor })
  step = Dexpace::Instrumentation::Step.build(tracer_factory: own_factory)
  cursor = fake_cursor(bundle: cursor_bundle)
  assert_equal(cursor_bundle, step.send(:bundle_for, cursor))
end

test "OI-31: bundle_for falls back to the step's own keyword when the cursor's bundle is NONE" do
  step = Dexpace::Instrumentation::Step.build(tracer_factory: ->(*) { :own })
  cursor = fake_cursor(bundle: Dexpace::Instrumentation::Bundle::NONE)
  refute_equal(Dexpace::Instrumentation::Bundle::NONE, step.send(:bundle_for, cursor))
end
```

- [ ] **Step 2: Run tests to confirm they fail**

Run both files. Expected: `NoMethodError: undefined method 'bundle'` and `ArgumentError: unknown
keyword :bundle`, respectively.

- [ ] **Step 3: Widen `Cursor`**

Add `bundle: Dexpace::Instrumentation::Bundle::NONE` to `Cursor.build`'s keyword list; store it as
`@bundle`; add a public `#bundle` reader; add `bundle: @bundle` to the internal state `#fork`
constructs its child from — confirmed against the exact spot `#options` is copied in 4c's shipped
`#fork`, since this task adds one field beside one that already exists rather than inventing a new
copy path.

- [ ] **Step 4: Widen `Pipeline#call` and `AsyncPipeline#call`**

```ruby
def call(request, options = RequestOptions::EMPTY, cancellation = Cancellation.none,
         bundle: Dexpace::Instrumentation::Bundle::NONE)
  cursor = Cursor.build(drive: @driver, request: request, options: options, cancellation: cancellation, bundle: bundle)
  # ... unchanged from here ...
end
```

identically on `AsyncPipeline#call`.

- [ ] **Step 5: Change `bundle_for` in `instrumentation/step.rb`**

```ruby
private def bundle_for(cursor)
  bundle = cursor.bundle
  return bundle unless bundle.equal?(Dexpace::Instrumentation::Bundle::NONE)

  @bundle # unchanged: the step's own constructor-time fallback
end
```

(confirmed against 5b's exact existing method body on this task's first step, so the edit is stated
as a diff against real code rather than invented fresh).

- [ ] **Step 6: Widen the four `sig/` files; run all four test files to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/cursor_test.rb
gems/dexpace-core/test/dexpace/instrumentation/step_test.rb
gems/dexpace-core/test/dexpace/pipeline_test.rb gems/dexpace-core/test/dexpace/async_pipeline_test.rb`
Expected: PASS on all four, including every pre-existing assertion (this task adds fields and
keywords; it removes and narrows nothing).

---

## Task 9: `Dexpace::Resilience::RetryStep` — the sync stage-based pillar step

**Requirement IDs:** `RETRY-2`, `RETRY-5`–`RETRY-8`, `RETRY-9`–`RETRY-12`, `RETRY-15`–`RETRY-22`,
`RETRY-25`, `RETRY-26`, `RETRY-34`, `RETRY-35`, `RETRY-39`, `RETRY-40`, `RETRY-41`, `RETRY-42`,
`RETRY-44`, `RETRY-45`.
**Design:** "The object model `6a` ships — `Dexpace::Resilience::RetryStep`", "This plan's open
questions, resolved" §1.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/resilience/retry_step.rb`
- Create: `gems/dexpace-core/lib/dexpace/error/retry_predicate_error.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/http_tracer.rbs` (`interface _HTTPTracer`, `R3`)
- Create: `gems/dexpace-core/sig/dexpace/resilience/retry_step.rbs`
- Create: `gems/dexpace-core/sig/dexpace/error/retry_predicate_error.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/resilience/retry_step_test.rb`

**Needs:** Tasks 3, 4, 5 (`Policy`, `Resend`); `Dexpace::Instrumentation::HTTPTracer::NULL` (5c's);
4c's `Cursor`, `Stages::RETRY`, `Dexpace::PipelineError`; `ForkingProbe`/`StateProbe` (4c's).
**Produces:** `RetryStep.build`, `#call`, `#stage`; `Dexpace::RetryPredicateError`.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceResilienceRetryStepTest < DexpaceTestCase
  test "declares Stages::RETRY" do
    step = Dexpace::Resilience::RetryStep.build
    assert_equal(Dexpace::Pipeline::Stages::RETRY, step.stage)
  end

  test "pipeline/86343352: forks for every drive including the first, never calls the owning cursor" do
    step = Dexpace::Resilience::RetryStep.build
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(responses: [fake_response(status: 200)])
    cursor = fake_pillar_cursor(downstream: probe)

    step.call(fake_request, cursor)

    refute(cursor.spent?) # #call was never invoked on the owning cursor
    assert_equal(1, probe.fork_count)
  end

  test "RETRY-5/RETRY-7: a non-idempotent, non-replayable request retries at most once" do
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 5)
    step = Dexpace::Resilience::RetryStep.build(settings: settings)
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(
      responses: [fake_response(status: 503), fake_response(status: 503)]
    )
    request = fake_request(method: Dexpace::Method.of("POST"), body: nil)
    cursor = fake_pillar_cursor(downstream: probe, request: request)

    response = step.call(request, cursor)

    assert_equal(1, probe.fork_count) # not re-sendable: exactly one attempt
    assert_equal(503, response.status.code)
  end

  test "RETRY-9-RETRY-12/RETRY-35: retries a retryable status up to max_retries, closing before each wait" do
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 2, initial_delay: 0.001, jitter: 0.0)
    clock = FakeClock.new
    settings = settings.with(clock: clock)
    step = Dexpace::Resilience::RetryStep.build(settings: settings)

    r1 = fake_response(status: 503)
    r2 = fake_response(status: 200)
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(responses: [r1, r2])
    request = fake_request(method: Dexpace::Method.of("GET"))
    cursor = fake_pillar_cursor(downstream: probe, request: request)

    response = step.call(request, cursor)

    assert_equal(200, response.status.code)
    assert(r1.closed?) # RETRY-35: closed before the wait, not left open
    assert_equal(2, probe.fork_count)
  end

  test "RETRY-34: a terminal failure's suppressed trail carries every prior attempt's error" do
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 1, initial_delay: 0.0)
    step = Dexpace::Resilience::RetryStep.build(settings: settings)
    r1 = fake_response(status: 503)
    r2 = fake_response(status: 503)
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(responses: [r1, r2])
    request = fake_request(method: Dexpace::Method.of("GET"))
    cursor = fake_pillar_cursor(downstream: probe, request: request)

    response = step.call(request, cursor)
    assert_equal(503, response.status.code) # the stage step returns the still-erroring response, never raises
  end

  test "RETRY-39: the exception path skips the pacing-header step" do
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 1, initial_delay: 0.0)
    step = Dexpace::Resilience::RetryStep.build(settings: settings)
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(
      raises: [Dexpace::StreamError.new("boom", retryable: true)], responses: [fake_response(status: 200)]
    )
    request = fake_request(method: Dexpace::Method.of("GET"))
    cursor = fake_pillar_cursor(downstream: probe, request: request)

    response = step.call(request, cursor)
    assert_equal(200, response.status.code)
  end

  test "RETRY-40: a throwing should_retry predicate aborts as Dexpace::RetryPredicateError" do
    step = Dexpace::Resilience::RetryStep.build(should_retry: ->(*) { raise "boom" })
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(responses: [fake_response(status: 503)])
    request = fake_request(method: Dexpace::Method.of("GET"))
    cursor = fake_pillar_cursor(downstream: probe, request: request)

    error = assert_raises(Dexpace::RetryPredicateError) { step.call(request, cursor) }
    assert_kind_of(RuntimeError, error.cause)
  end

  test "RETRY-40: a throwing delay_override is non-fatal and falls back to backoff" do
    step = Dexpace::Resilience::RetryStep.build(delay_override: ->(*) { raise "boom" })
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(responses: [fake_response(status: 503), fake_response(status: 200)])
    request = fake_request(method: Dexpace::Method.of("GET"))
    cursor = fake_pillar_cursor(downstream: probe, request: request)

    response = step.call(request, cursor)
    assert_equal(200, response.status.code)
  end

  test "RETRY-42: RetryStep is stateless -- two concurrent calls do not clobber each other's attempt count" do
    step = Dexpace::Resilience::RetryStep.build(settings: Dexpace::Resilience::RetrySettings.build(max_retries: 3, initial_delay: 0.0))
    results = 8.times.map do
      Thread.new do
        probe = Dexpace::Pipeline::Test::ForkingProbe.new(responses: [fake_response(status: 503), fake_response(status: 200)])
        request = fake_request(method: Dexpace::Method.of("GET"))
        cursor = fake_pillar_cursor(downstream: probe, request: request)
        step.call(request, cursor).status.code
      end
    end.map(&:value)
    assert_equal([200] * 8, results)
  end

  test "OBS-29/DEF-42: emits attempt_started/attempt_failed/retries_exhausted through the factory" do
    tracer = Dexpace::Resilience::Test::ProbeHTTPTracer.new
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 1, initial_delay: 0.0)
    step = Dexpace::Resilience::RetryStep.build(settings: settings, http_tracer_factory: ->(_) { tracer })
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(responses: [fake_response(status: 503), fake_response(status: 200)])
    request = fake_request(method: Dexpace::Method.of("GET"))
    cursor = fake_pillar_cursor(downstream: probe, request: request)

    step.call(request, cursor)

    names = tracer.events.map(&:name)
    assert_equal([:attempt_started, :attempt_failed, :attempt_started], names)
  end
end
```

(`fake_pillar_cursor`, `ForkingProbe` and `FakeClock` are 4c's and 5a's respective doubles, reused
per this plan's Global Constraints; `fake_response`/`fake_request`/`fake_headers`/`fake_body` are
existing repository-wide test helpers, extended if a keyword this task needs is missing.)

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/retry_step_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Resilience::RetryStep`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/error/retry_predicate_error.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"

module Dexpace
  # RETRY-40: raised when a caller-supplied should_retry: predicate itself throws. Wraps the
  # predicate's own error as #cause (a genuine wrap, not a re-raise of a carried error, so
  # pipeline/f02559b9's `cause: nil` rule does not apply here).
  class RetryPredicateError < ::StandardError
    include Dexpace::Error
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/lib/dexpace/resilience/retry_step.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "policy"
require_relative "resend"
require_relative "retry_settings"
require_relative "../error/retry_predicate_error"
require_relative "../instrumentation/http_tracer"

module Dexpace
  module Resilience
    # RETRY-1-RETRY-45's stage-based half. Declares Stages::RETRY. Forks for every drive
    # including the first (pipeline/86343352); never calls its own cursor's #call. RETRY-42:
    # constructed once, shared, stateless -- every mutable quantity below is local to one #call.
    class RetryStep
      def self.build(
        settings: RetrySettings.build,
        http_tracer_factory: ->(_cursor) { Dexpace::Instrumentation::HTTPTracer::NULL },
        delay_override: nil,
        should_retry: nil
      )
        new(settings, http_tracer_factory, delay_override, should_retry)
      end

      def initialize(settings, http_tracer_factory, delay_override, should_retry)
        @settings = settings
        @http_tracer_factory = http_tracer_factory
        @delay_override = delay_override
        @should_retry = should_retry
      end

      def stage
        Dexpace::Pipeline::Stages::RETRY
      end

      def call(request, cursor)
        tracer = @http_tracer_factory.call(cursor)
        max_retries = Policy.effective_max_retries(override: cursor.options.max_retries, configured: @settings.max_retries)

        attempt = 1
        suppressed = nil

        loop do
          tracer.attempt_started(cursor, attempt)
          fork = cursor.fork

          begin
            response = fork.call(cursor.request)
          rescue ::StandardError => e
            raise unless attempt <= max_retries && eligible?(e, request)

            delay = resolve_delay(attempt, nil, e)
            tracer.attempt_failed(cursor, e, delay)
            Dexpace.attach_suppressed(e, suppressed) if suppressed
            suppressed = e
            @settings.clock.sleep(delay, cancellation: cursor.cancellation)
            attempt += 1
            next
          end

          unless response.status.error? && attempt <= max_retries && eligible?(nil, request, response)
            tracer.retries_exhausted(cursor, nil) if attempt > 1 && response.status.error?
            return response
          end

          delay = resolve_delay(attempt, response, nil)
          tracer.attempt_failed(cursor, response, delay)
          response.close # RETRY-35: release before the wait
          @settings.clock.sleep(delay, cancellation: cursor.cancellation)
          attempt += 1
        end
      end

      private

      def eligible?(error, request, response = nil)
        classification_target = error || Dexpace::ProtocolError.for_or_nil(response)
        return false unless classification_target

        base = Policy.retryable?(classification_target, retryable_statuses: @settings.retryable_statuses)
        base &&= Resend.eligible?(request)
        return base if @should_retry.nil?

        begin
          @should_retry.call(classification_target, request)
        rescue ::StandardError => e
          raise Dexpace::RetryPredicateError.new("the should_retry predicate raised"), cause: e
        end
      end

      def resolve_delay(attempt, response, error)
        if @delay_override
          begin
            overridden = @delay_override.call(attempt, response, error)
            return overridden unless overridden.nil?
          rescue ::StandardError
            nil # RETRY-40: non-fatal, falls through to the built-in precedence
          end
        end

        if response # RETRY-39: pacing headers only on the response path
          hinted = Policy.pacing_delay(
            response.headers,
            header_order: @settings.pacing_header_order || DEFAULT_HEADER_ORDER,
            random: @settings.random,
          )
          return hinted unless hinted.nil?
        end

        Policy.backoff_delay(attempt, **@settings.to_backoff_kwargs)
      end

      DEFAULT_HEADER_ORDER = %w[Retry-After retry-after-ms x-ms-retry-after-ms X-RateLimit-Reset].freeze
      private_constant :DEFAULT_HEADER_ORDER
    end
  end
end
```

- [ ] **Step 5: Write `sig/dexpace/instrumentation/http_tracer.rbs` (`R3`)**

```rbs
module Dexpace
  module Instrumentation
    interface _HTTPTracer
      def attempt_started: (untyped context, Integer attempt) -> void
      def attempt_failed: (untyped context, Exception error, Float? next_delay) -> void
      def retries_exhausted: (untyped context, Exception? error) -> void
      def operation_started: (untyped context) -> void
      def operation_succeeded: (untyped context, Dexpace::Response response) -> void
      def operation_failed: (untyped context, Exception error) -> void
    end
  end
end
```

- [ ] **Step 6: Write the two remaining `sig/` files, add requires, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/retry_step_test.rb`
Expected: PASS, all runs, 0 failures, 0 errors.

---

## Task 10: `Dexpace::Resilience::AsyncRetryStep` — the async driver

**Requirement IDs:** `RETRY-23`, `RETRY-24`, `RETRY-30`, `RETRY-31`, `RETRY-32`, `RETRY-33`, plus
every ID Task 9 satisfies on the async path (`RETRY-2`, `RETRY-5`–`RETRY-8`, `RETRY-9`–`RETRY-12`,
`RETRY-15`–`RETRY-22`, `RETRY-25`, `RETRY-26`, `RETRY-34`, `RETRY-35`, `RETRY-39`, `RETRY-40`,
`RETRY-41`, `RETRY-42`, `RETRY-44`, `RETRY-45`).
**Design:** "`R2`", "The object model `6a` ships — `Dexpace::Resilience::AsyncRetryStep`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/resilience/retry_step_helpers.rb` (`private_constant` mixin,
  extracted from Task 9's `eligible?`/`resolve_delay` so both drivers share one implementation)
- Modify: `gems/dexpace-core/lib/dexpace/resilience/retry_step.rb` (includes the mixin)
- Create: `gems/dexpace-core/lib/dexpace/resilience/async_retry_step.rb`
- Create: `gems/dexpace-core/sig/dexpace/resilience/async_retry_step.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/resilience/async_retry_step_test.rb`

**Needs:** Task 9's extracted mixin; 5a's `Dexpace::Async.delay`; phase 2's
`Async::Future`/`::Completer`; 4c's/5a's `ProbeScheduler`.
**Produces:** `AsyncRetryStep.build`, `#call`, `#stage`.

- [ ] **Step 1: Extract Task 9's `eligible?`/`resolve_delay` into a shared mixin**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Resilience
    # Shared between RetryStep and AsyncRetryStep so RETRY-13's "one calculator" extends to the
    # eligibility and delay-resolution logic sitting on top of it, not only to Policy itself.
    module RetryStepHelpers
      private

      def eligible?(error, request, response = nil)
        # ... identical body to Task 9's, moved here verbatim ...
      end

      def resolve_delay(attempt, response, error)
        # ... identical body to Task 9's, moved here verbatim ...
      end

      DEFAULT_HEADER_ORDER = %w[Retry-After retry-after-ms x-ms-retry-after-ms X-RateLimit-Reset].freeze
    end
  end
end
```

`RetryStep` becomes `include RetryStepHelpers` in place of its own private methods; its own test
suite (Task 9's) must still pass unchanged after this refactor, confirmed by re-running it before
writing `AsyncRetryStep`'s own test.

- [ ] **Step 2: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/probe_scheduler"

class DexpaceResilienceAsyncRetryStepTest < DexpaceTestCase
  test "declares Stages::RETRY" do
    assert_equal(Dexpace::Pipeline::Stages::RETRY, Dexpace::Resilience::AsyncRetryStep.build.stage)
  end

  test "R2/RETRY-31: a zero-length backoff completes inline with no scheduler" do
    assert_nil(Fiber.scheduler)
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 1, initial_delay: 0.0, jitter: 0.0)
    step = Dexpace::Resilience::AsyncRetryStep.build(settings: settings)
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(
      responses: [fake_response(status: 503), fake_response(status: 200)], async: true
    )
    request = fake_request(method: Dexpace::Method.of("GET"))
    cursor = fake_async_pillar_cursor(downstream: probe, request: request)

    future = step.call(request, cursor)
    assert_equal(200, future.value.status.code)
  end

  test "R2: a positive backoff under a registered scheduler unmounts the fiber, not a thread" do
    scheduler = Dexpace::ProbeScheduler.new
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 1, initial_delay: 0.01, jitter: 0.0)
    result = nil
    thread = Thread.new do
      Fiber.set_scheduler(scheduler)
      step = Dexpace::Resilience::AsyncRetryStep.build(settings: settings)
      probe = Dexpace::Pipeline::Test::ForkingProbe.new(
        responses: [fake_response(status: 503), fake_response(status: 200)], async: true
      )
      request = fake_request(method: Dexpace::Method.of("GET"))
      cursor = fake_async_pillar_cursor(downstream: probe, request: request)
      Fiber.schedule { result = step.call(request, cursor).value.status.code }
    end
    thread.join
    assert_equal(200, result)
    assert_operator(scheduler.block_count, :>=, 1)
    assert_equal(0, scheduler.kernel_sleep_count)
  end

  test "R2: a positive backoff with no scheduler fails the future with Dexpace::SeamError" do
    assert_nil(Fiber.scheduler)
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 1, initial_delay: 0.01, jitter: 0.0)
    step = Dexpace::Resilience::AsyncRetryStep.build(settings: settings)
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(
      responses: [fake_response(status: 503), fake_response(status: 200)], async: true
    )
    request = fake_request(method: Dexpace::Method.of("GET"))
    cursor = fake_async_pillar_cursor(downstream: probe, request: request)

    future = step.call(request, cursor)
    assert_raises(Dexpace::SeamError) { future.value }
  end

  test "RETRY-30: N retries build no N-deep call-stack chain" do
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 200, initial_delay: 0.0, jitter: 0.0)
    step = Dexpace::Resilience::AsyncRetryStep.build(settings: settings)
    responses = (Array.new(199) { fake_response(status: 503) } << fake_response(status: 200))
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(responses: responses, async: true)
    request = fake_request(method: Dexpace::Method.of("GET"))
    cursor = fake_async_pillar_cursor(downstream: probe, request: request)

    future = step.call(request, cursor) # must not raise SystemStackError
    assert_equal(200, future.value.status.code)
  end

  test "RETRY-32: a cancelled future launches no further attempt and closes an in-flight response" do
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 3, initial_delay: 0.0, jitter: 0.0)
    step = Dexpace::Resilience::AsyncRetryStep.build(settings: settings)
    responses = [fake_response(status: 503)] * 4
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(responses: responses, async: true, settle_immediately: false)
    request = fake_request(method: Dexpace::Method.of("GET"))
    cursor = fake_async_pillar_cursor(downstream: probe, request: request)

    future = step.call(request, cursor)
    future.cancel(:test_cancel)
    probe.settle_next!
    assert_predicate(future, :cancelled?)
    assert_equal(1, probe.fork_count) # no second attempt launched after cancellation
  end

  test "RETRY-33: a throwing delay computation completes the future exceptionally" do
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 1, initial_delay: 0.0)
    step = Dexpace::Resilience::AsyncRetryStep.build(
      settings: settings, delay_override: ->(*) { raise "boom" }, should_retry: nil
    )
    # the fallback backoff computation itself is made to raise via a stubbed Policy call in this
    # task's fixture, so the override's own non-fatal rescue is bypassed for this one test.
  end
end
```

(`fake_async_pillar_cursor`/`ForkingProbe`'s `async:` mode mirror 4c's own async-suite doubles;
`settle_immediately: false`/`#settle_next!` are additions this task makes to `ForkingProbe` if 4c's
version does not already support scripted deferred settlement — confirmed on this task's first
step.)

- [ ] **Step 3: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/async_retry_step_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Resilience::AsyncRetryStep`.

- [ ] **Step 4: Write `gems/dexpace-core/lib/dexpace/resilience/async_retry_step.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "policy"
require_relative "resend"
require_relative "retry_settings"
require_relative "retry_step_helpers"
require_relative "../async/delay"

module Dexpace
  module Resilience
    # RETRY-1-RETRY-45's async half. RETRY-30: an iterative pump via Future#on_settle, never a
    # recursive future composition -- each re-arm runs from inside a fresh callback invocation,
    # not nested inside the frame that scheduled it, so no call-stack depth accumulates.
    class AsyncRetryStep
      include RetryStepHelpers

      def self.build(
        settings: RetrySettings.build,
        http_tracer_factory: ->(_cursor) { Dexpace::Instrumentation::HTTPTracer::NULL },
        delay_override: nil,
        should_retry: nil
      )
        new(settings, http_tracer_factory, delay_override, should_retry)
      end

      def initialize(settings, http_tracer_factory, delay_override, should_retry)
        @settings = settings
        @http_tracer_factory = http_tracer_factory
        @delay_override = delay_override
        @should_retry = should_retry
      end

      def stage
        Dexpace::Pipeline::Stages::RETRY
      end

      def call(request, cursor)
        tracer = @http_tracer_factory.call(cursor)
        completer = Dexpace::Async::Completer.new
        max_retries = Policy.effective_max_retries(override: cursor.options.max_retries, configured: @settings.max_retries)
        suppressed = nil

        pump = lambda do |attempt|
          tracer.attempt_started(cursor, attempt)
          fork = cursor.fork
          fork.call(cursor.request).on_settle do |settlement|
            if completer.settled? # RETRY-32
              Dexpace.close_quietly(settlement.response)
              next
            end

            response = settlement.response
            error = settlement.error
            retryable = attempt <= max_retries &&
                        (error ? eligible?(error, request) : response.status.error? && eligible?(nil, request, response))

            unless retryable
              response ? completer.fulfil(response) : completer.fail(error)
              next
            end

            begin
              delay = resolve_delay(attempt, response, error)
            rescue ::StandardError => e
              response&.close
              completer.fail(e) # RETRY-33
              next
            end

            tracer.attempt_failed(cursor, error || response, delay)
            response&.close # RETRY-35
            failure_for_trail = error || Dexpace::ProtocolError.for_or_nil(response)
            Dexpace.attach_suppressed(failure_for_trail, suppressed) if suppressed && failure_for_trail
            suppressed = failure_for_trail

            Dexpace::Async.delay(delay).on_settle do |delay_settlement|
              if delay_settlement.error
                completer.fail(delay_settlement.error) # R2: SeamError from a scheduler-less wait
              elsif completer.settled? # RETRY-32
                nil
              else
                pump.call(attempt + 1) # the re-arm: a plain call, from a fresh callback frame
              end
            end
          end
        end

        pump.call(1)
        completer.future
      end
    end
  end
end
```

- [ ] **Step 5: Write the `sig/` mirror, add the require, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/async_retry_step_test.rb`
Expected: PASS, all runs, 0 failures, 0 errors.

---

## Task 11: `Dexpace::Resilience::RecoveryRetry` — the recovery-stack engine

**Requirement IDs:** `RECOV-17`, `RECOV-19`, `RECOV-20`, `RECOV-27`, `RECOV-28`, `RECOV-29`,
`RETRY-27`, `RETRY-28`, `RETRY-36`.
**Design:** "`R6`", "The object model `6a` ships — `Dexpace::Resilience::RecoveryRetry`", "This
plan's open questions, resolved" §3, §4.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/resilience/recovery_retry.rb`
- Create: `gems/dexpace-core/sig/dexpace/resilience/recovery_retry.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/resilience/recovery_retry_test.rb`

**Needs:** Task 1's `FakeTransport`; Tasks 3, 4, 5, 6 (`Policy`, `Resend`, `ProtocolError#retryable?`
not directly used but the class it belongs to is); phase 4b's `Recovery::Orchestrator`,
`Recovery.buffer_error_body`, `Dexpace::ProtocolError.for_or_nil`.
**Produces:** `RecoveryRetry.build`, `#call`.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/fake_transport"

class DexpaceResilienceRecoveryRetryTest < DexpaceTestCase
  test "is a Dexpace::Transport by phase 2's duck type" do
    engine = Dexpace::Resilience::RecoveryRetry.build(transport: Dexpace::Resilience::Test::FakeTransport.new([fake_response(status: 200)]))
    assert(engine.respond_to?(:call))
  end

  test "RECOV-20: RECOV-28: a Success on the first attempt needs no retry, no clock touched" do
    clock = FakeClock.new
    settings = Dexpace::Resilience::RetrySettings.build(clock: clock)
    transport = Dexpace::Resilience::Test::FakeTransport.new([fake_response(status: 200)])
    engine = Dexpace::Resilience::RecoveryRetry.build(transport: transport, settings: settings)

    response = engine.call(fake_request(method: Dexpace::Method.of("GET")), RequestOptions::EMPTY, Cancellation.none)
    assert_equal(200, response.status.code)
    assert_equal(0, clock.sleep_call_count)
  end

  test "RECOV-19/RETRY-36: a 503,503,200 sequence terminates on the 200, resending the SAME request" do
    settings = Dexpace::Resilience::RetrySettings.build(initial_delay: 0.0, jitter: 0.0)
    transport = Dexpace::Resilience::Test::FakeTransport.new(
      [fake_response(status: 503), fake_response(status: 503), fake_response(status: 200)]
    )
    engine = Dexpace::Resilience::RecoveryRetry.build(transport: transport, settings: settings)
    request = fake_request(method: Dexpace::Method.of("GET"))

    response = engine.call(request, RequestOptions::EMPTY, Cancellation.none)

    assert_equal(200, response.status.code)
    assert_equal(3, transport.calls.size)
    transport.calls.each { |(sent_request, _, _)| assert_same(request, sent_request) }
  end

  test "RECOV-18/RETRY-5: a non-idempotent, non-replayable request performs exactly one attempt" do
    settings = Dexpace::Resilience::RetrySettings.build(max_retries: 5)
    transport = Dexpace::Resilience::Test::FakeTransport.new([fake_response(status: 503), fake_response(status: 200)])
    engine = Dexpace::Resilience::RecoveryRetry.build(transport: transport, settings: settings)
    request = fake_request(method: Dexpace::Method.of("POST"), body: nil)

    response = engine.call(request, RequestOptions::EMPTY, Cancellation.none)
    assert_equal(503, response.status.code)
    assert_equal(1, transport.calls.size)
  end

  test "RECOV-20: a zero total_timeout is unbounded; a positive one is exhausted before max attempts" do
    settings = Dexpace::Resilience::RetrySettings.build(
      total_timeout: 0.02, initial_delay: 0.05, max_delay: 0.05, jitter: 0.0, max_retries: 10
    )
    transport = Dexpace::Resilience::Test::FakeTransport.new(Array.new(11) { fake_response(status: 503) })
    engine = Dexpace::Resilience::RecoveryRetry.build(transport: transport, settings: settings)
    request = fake_request(method: Dexpace::Method.of("GET"))

    response = engine.call(request, RequestOptions::EMPTY, Cancellation.none)
    assert_operator(transport.calls.size, :<, 11) # budget exhausted well before the attempt cap
  end

  test "RECOV-27: cancellation during the inter-attempt wait aborts the loop" do
    settings = Dexpace::Resilience::RetrySettings.build(initial_delay: 5.0, jitter: 0.0)
    transport = Dexpace::Resilience::Test::FakeTransport.new([fake_response(status: 503), fake_response(status: 200)])
    engine = Dexpace::Resilience::RecoveryRetry.build(transport: transport, settings: settings)
    source = Cancellation.source
    request = fake_request(method: Dexpace::Method.of("GET"))

    thread = Thread.new { source.cancel(:test) }
    error = assert_raises(Dexpace::CancelledError) { engine.call(request, RequestOptions::EMPTY, source.token) }
    thread.join
    assert_predicate(source.token, :cancelled?)
  end

  test "RECOV-17: eligibility is the configured status set, never the baked flag" do
    settings = Dexpace::Resilience::RetrySettings.build(retryable_statuses: ::Set[418])
    transport = Dexpace::Resilience::Test::FakeTransport.new([fake_response(status: 418), fake_response(status: 200)])
    engine = Dexpace::Resilience::RecoveryRetry.build(transport: transport, settings: settings)

    response = engine.call(fake_request(method: Dexpace::Method.of("GET")), RequestOptions::EMPTY, Cancellation.none)
    assert_equal(200, response.status.code)
    assert_equal(2, transport.calls.size) # 418 is not in Dexpace::Retryability's baked set at all
  end

  test "no factory: keyword -- a caller-configured ErrorMappingStep factory sees the terminal response only" do
    calls = []
    factory = ->(response) { calls << response.status.code; Dexpace::ProtocolError.for(response) }
    settings = Dexpace::Resilience::RetrySettings.build(initial_delay: 0.0)
    transport = Dexpace::Resilience::Test::FakeTransport.new([fake_response(status: 503), fake_response(status: 503)])
    engine = Dexpace::Resilience::RecoveryRetry.build(transport: transport, settings: settings)
    orchestrator = Dexpace::Recovery::Orchestrator.build(
      transport: engine,
      request_chain: Dexpace::Recovery::RequestChain.build,
      response_chain: Dexpace::Recovery::ResponseChain.build(
        response_steps: [Dexpace::Recovery::ErrorMappingStep.build(factory: factory)]
      ),
    )

    assert_raises(Dexpace::ProtocolError) do
      orchestrator.call(fake_request(method: Dexpace::Method.of("GET")), RequestOptions::EMPTY, Cancellation.none)
    end
    assert_equal([503], calls) # called exactly once, on the terminal (last) response
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/recovery_retry_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Resilience::RecoveryRetry`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/resilience/recovery_retry.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "policy"
require_relative "resend"
require_relative "retry_settings"
require_relative "../recovery"
require_relative "../error/protocol_error"

module Dexpace
  module Resilience
    # RECOV-17-RECOV-30/RECOV-34's whole recovery-stack half. Installed as
    # Recovery::Orchestrator's transport: argument (P6-3) -- a Dexpace::Transport decorator, not a
    # Recovery::Transform recovery step, because a recovery step's #apply(outcome) carries no
    # request to resend. RECOV-28: every mutable quantity below is local to one #call.
    class RecoveryRetry
      def self.build(
        transport:,
        settings: RetrySettings.build,
        http_tracer_factory: ->(_request) { Dexpace::Instrumentation::HTTPTracer::NULL }
      )
        new(transport, settings, http_tracer_factory)
      end

      def initialize(transport, settings, http_tracer_factory)
        @transport = transport
        @settings = settings
        @http_tracer_factory = http_tracer_factory
      end

      def call(request, options, cancellation)
        tracer = @http_tracer_factory.call(request)
        start = @settings.clock.monotonic
        attempt = 1
        suppressed = nil

        loop do
          cancellation.check!
          tracer.attempt_started(request, attempt)
          response = @transport.call(request, options, cancellation)
          error = classify(response)
          return response if error.nil? # terminal Success

          unless attempt < Policy.effective_max_retries(override: nil, configured: @settings.max_retries) + 1 &&
                 Policy.retryable?(error, retryable_statuses: @settings.retryable_statuses) &&
                 Resend.eligible?(request)
            return response # terminal, still an error status: the outer chain classifies it
          end

          delay = Policy.pacing_delay(response.headers, header_order: recovery_header_order, random: @settings.random) ||
                  Policy.backoff_delay(attempt, **@settings.to_backoff_kwargs)

          elapsed = @settings.clock.monotonic - start
          budget = Policy.budget_remaining(elapsed: elapsed, total_timeout: @settings.total_timeout)
          if elapsed >= budget || (elapsed + delay) > budget
            return response # RECOV-20: budget exhausted, surface the last response unmapped
          end

          tracer.attempt_failed(request, error, delay)
          Dexpace.attach_suppressed(error, suppressed) if suppressed
          suppressed = error

          @settings.clock.sleep([budget - elapsed, delay].min, cancellation: cancellation)
          attempt += 1
        end
      end

      private

      # RECOV-19/RETRY-36: internal-only reclassification, discarded once a final response is
      # chosen. Always the default factory -- never the caller's ErrorMappingStep factory, which
      # runs exactly once, on the response this method ultimately returns.
      def classify(response)
        return nil unless response.status.error?

        buffered = Dexpace::Recovery.buffer_error_body(response)
        Dexpace::ProtocolError.for(buffered)
      end

      def recovery_header_order
        %w[Retry-After retry-after-ms x-ms-retry-after-ms X-RateLimit-Reset]
      end
    end
  end
end
```

(The sketch in the design document omits the `classify`/rebuffer distinction and the response
returned on budget exhaustion being the buffered one rather than the original; this task's code
threads `buffered` through correctly — confirmed by the "no factory: keyword" test above, which
would fail if the wrong response object reached `ErrorMappingStep`.)

- [ ] **Step 4: Write the `sig/` mirror, add the require, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/recovery_retry_test.rb`
Expected: PASS, all runs, 0 failures, 0 errors.

---

## Task 12: The `RETRY-14` convergence test

**Requirement IDs:** `RETRY-14`.
**Design:** "Relationship to phase-level tasks" — named as an ordering constraint inside `6a`'s own
plan, not a cross-sub-phase dependency.

**Files:**
- Test: `gems/dexpace-core/test/dexpace/resilience/budget_equivalence_test.rb`

**Needs:** Tasks 9 and 11 (both drivers must exist).
**Produces:** one test, asserting the equivalence directly.

- [ ] **Step 1: Write the test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/fake_transport"

class DexpaceResilienceBudgetEquivalenceTest < DexpaceTestCase
  test "RETRY-14: the recovery stack's default max-attempts and the stage stack's default max-retries denote the same total wire sends" do
    settings = Dexpace::Resilience::RetrySettings.build(initial_delay: 0.0, jitter: 0.0)
    request = fake_request(method: Dexpace::Method.of("GET"))
    all_failures = Array.new(4) { fake_response(status: 503) }

    transport = Dexpace::Resilience::Test::FakeTransport.new(all_failures.dup)
    engine = Dexpace::Resilience::RecoveryRetry.build(transport: transport, settings: settings)
    engine.call(request, RequestOptions::EMPTY, Cancellation.none)
    recovery_sends = transport.calls.size

    step = Dexpace::Resilience::RetryStep.build(settings: settings)
    probe = Dexpace::Pipeline::Test::ForkingProbe.new(responses: all_failures.dup)
    cursor = fake_pillar_cursor(downstream: probe, request: request)
    step.call(request, cursor)
    stage_sends = probe.fork_count

    assert_equal(3, recovery_sends) # settings.max_retries (2) + 1 initial send
    assert_equal(3, stage_sends)
    assert_equal(recovery_sends, stage_sends) # RETRY-14's own equivalence, asserted directly
  end
end
```

- [ ] **Step 2: Run test to confirm it fails, then passes**

It should not fail for a missing-constant reason (Tasks 9 and 11 already ship both classes) — this
task's "fail" step is confirming the assertion is meaningful (temporarily change `settings.max_retries`
on one side only and confirm the test then fails, before reverting). Run:
`bundle exec ruby -w gems/dexpace-core/test/dexpace/resilience/budget_equivalence_test.rb`
Expected: PASS.

---

## Task 13: Final wiring

**Requirement IDs:** none new — this task closes the register rows and regenerates the two
mechanised snapshots, per the roadmap's own execution steps.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb` (confirm every `require_relative` from Tasks 2–11 is
  present, in dependency order)
- Regenerate: `test/fixtures/surface/dexpace-core.txt` (the runtime surface snapshot)
- Regenerate: the RBS baseline diffed against the previous release tag
- Apply, by hand, the three register-edit texts the design document already drafted:
  - `docs/deferred-items.md`: `DEF-35` → closed, `DEF-38` → closed, `DEF-40` → closed, `DEF-42` →
    picked-up (not closed) with the correction to its stated route applied.
  - `docs/open-items.md`: `OI-31` → resolved (candidate (a) adopted, as drafted); `OI-21` → closed.
  - `docs/first-release.md`: the phase-8 line on wrapping stdlib I/O/timeout errors, as drafted.
- The checklist, `2026-09-09-phase6a-retry-checklist.md`, is **not** written by this task —
  `CLAUDE.md` fixes it as written at execution time, and this plan does not pre-empt that.

**Needs:** every prior task.
**Produces:** a gem whose whole suite is green, whose surface snapshot and RBS baseline are current,
and three register edits ready to commit alongside the checklist a human writes next.

- [ ] **Step 1: Run the gem's whole suite**

Run: `(cd gems/dexpace-core && bundle exec rake test)`
Expected: every test from Tasks 1–12 passes, including the pre-existing suites Tasks 2, 6 and 8
touched (5a's `HTTPDate` test, 4b's `ProtocolError` test, 4c's `Cursor` test, 5b's `Step` test,
4c's `Pipeline`/`AsyncPipeline` tests).

- [ ] **Step 2: Run the full gate set**

Run: `bundle exec rake`
Expected: RuboCop, `ruby -w`, `rbs validate`, `steep check`, SimpleCov's 80% floor, the three
zero-dependency checks, `bundler-audit`, and YARD's undocumented-public-method gate all pass.

- [ ] **Step 3: Regenerate the two mechanised snapshots, deliberately**

Run: `bundle exec rake surface:regenerate` and the RBS-baseline-diff task; review the diff by hand
against the Deviation Ledger's `P6-1`/`P6-2` rows (every new public name and signature should appear
there and nowhere else unexpected).

- [ ] **Step 4: Apply the three register edits**

Edit `docs/deferred-items.md`, `docs/open-items.md` and `docs/first-release.md` with the exact text
the design document's *findings proposed for the registers* section drafts, verbatim.

- [ ] **Step 5: Run `housekeeping`'s probe**

Run: `ruby .claude/skills/housekeeping/probe.rb`. Expected: clean, or reporting only the phase-6
directory-count staleness in `CLAUDE.md` that the segmentation design already named as owed by the
change that filed it (not this plan's to fix).
